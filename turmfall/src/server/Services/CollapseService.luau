--!strict
-- CollapseService: Kollaps-Erkennung, Ringpuffer und Schuld-System.
--
-- Fallregel: Ein Teil gilt als "gefallen", sobald seine Mitte unter die
-- Y-Höhe der Basisplattform fällt. Fallen mehr als FALL_COLLAPSE_RATIO
-- (30%) der platzierten Teile innerhalb von FALL_WINDOW_SECONDS (5 s),
-- wird ein Kollaps-Event ausgelöst.
--
-- Schuld-System: Für jedes Teil sind Platzierer + Zeitstempel geloggt.
-- Ein Ringpuffer speichert RING_BUFFER_SECONDS lang alle Teil-Positionen
-- mit RING_BUFFER_HZ (4 Hz). Beim Kollaps entscheidet BlameLogic (pur,
-- getestet): Das zuletzt platzierte Teil mit physischem Kontakt zur
-- Kollaps-Kaskade bestimmt den Verursacher. Aus demselben Ringpuffer
-- speist sich das 5-Sekunden-Schuld-Replay für alle Clients.
--
-- Abhängigkeits-Hinweis: Dieser Service kennt den TowerService NICHT
-- (kein Require-Zyklus). Der TowerService registriert seine Teile hier
-- (push) und hängt sich über den onFallen-Hook ein.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Network = require(Shared.Network)
local GameConfig = require(Shared.Config.GameConfig)
local PartCatalog = require(Shared.Config.PartCatalog)
local BlameLogic = require(Shared.BlameLogic)
local Types = require(Shared.Types)

-- Ein überwachtes Teil (vom TowerService registriert).
type TrackedPiece = {
	pieceId: number,
	ownerUserId: number,
	partTypeId: string,
	primaryPart: BasePart,
	model: Model,
	placedAt: number,
	fallen: boolean,
	fallenAt: number?,
}

local CollapseService = {}

-- Hooks (setzt der TowerService bzw. ScoreService in init - kein Zyklus).
CollapseService.onFallen = function(_pieceId: number) end
CollapseService.onCollapse = function(_culpritUserId: number?) end

local tracked: { [number]: TrackedPiece } = {}
local trackedCount = 0

-- Ringpuffer: feste Kapazität, Schreibzeiger läuft im Kreis.
local RING_CAPACITY = GameConfig.RING_BUFFER_SECONDS * GameConfig.RING_BUFFER_HZ
local ringSamples: { Types.RingSample } = {}
local ringWriteIndex = 0

-- Gefallene Teile im gleitenden Fenster (für die 30%-Regel).
local recentFalls: { { pieceId: number, at: number } } = {}

local detectionActive = false

-- Solange dieser Zeitpunkt in der Zukunft liegt, ist die Schuld-Zuweisung
-- ausgesetzt (Katastrophen-Events: für Wind/Erdbeben verliert NIEMAND
-- seinen Einsatz - das wäre unfair und fühlbar falsch).
local blameSuspendedUntil = 0

local collapseEvent: RemoteEvent? = nil

--------------------------------------------------------------------------
-- Registrierung (vom TowerService gepusht)
--------------------------------------------------------------------------

function CollapseService.registerPiece(
	pieceId: number,
	ownerUserId: number,
	partTypeId: string,
	primaryPart: BasePart,
	model: Model,
	placedAt: number
)
	tracked[pieceId] = {
		pieceId = pieceId,
		ownerUserId = ownerUserId,
		partTypeId = partTypeId,
		primaryPart = primaryPart,
		model = model,
		placedAt = placedAt,
		fallen = false,
		fallenAt = nil,
	}
	trackedCount += 1
end

-- Neue Runde: alles vergessen.
function CollapseService.resetRound()
	table.clear(tracked)
	trackedCount = 0
	table.clear(ringSamples)
	ringWriteIndex = 0
	table.clear(recentFalls)
	blameSuspendedUntil = 0
end

function CollapseService.setActive(active: boolean)
	detectionActive = active
end

-- Setzt die Schuld-Zuweisung für einige Sekunden aus (DisasterService).
function CollapseService.suspendBlame(seconds: number)
	blameSuspendedUntil = math.max(blameSuspendedUntil, os.clock() + seconds)
end

--------------------------------------------------------------------------
-- Ringpuffer
--------------------------------------------------------------------------

local function captureSample()
	local positions: { [number]: Types.Vec3 } = {}
	for pieceId, piece in tracked do
		if piece.model.Parent == nil then
			continue
		end
		local position = piece.primaryPart.Position
		positions[pieceId] = { x = position.X, y = position.Y, z = position.Z }
	end

	ringWriteIndex = (ringWriteIndex % RING_CAPACITY) + 1
	ringSamples[ringWriteIndex] = { t = os.clock(), positions = positions }
end

-- Samples chronologisch (älteste zuerst), optional auf die letzten
-- `seconds` begrenzt und auf eine pieceId-Menge gefiltert.
local function getOrderedSamples(seconds: number?, filterIds: { [number]: boolean }?): { Types.RingSample }
	local cutoff = if seconds ~= nil then os.clock() - seconds else nil
	local ordered: { Types.RingSample } = {}
	for offset = 1, RING_CAPACITY do
		local index = (ringWriteIndex + offset - 1) % RING_CAPACITY + 1
		local sample = ringSamples[index]
		if sample == nil then
			continue
		end
		if cutoff ~= nil and sample.t < cutoff then
			continue
		end
		if filterIds ~= nil then
			local filtered: { [number]: Types.Vec3 } = {}
			for pieceId in filterIds do
				local position = sample.positions[pieceId]
				if position ~= nil then
					filtered[pieceId] = position
				end
			end
			table.insert(ordered, { t = sample.t, positions = filtered })
		else
			table.insert(ordered, sample)
		end
	end
	return ordered
end

--------------------------------------------------------------------------
-- Fall- und Kollaps-Erkennung
--------------------------------------------------------------------------

-- Schwelle: unter der Plattform-Mitte (minus Marge) gilt ein Teil als gefallen.
local function getFallThresholdY(): number
	return GameConfig.BASE_PLATFORM_Y - GameConfig.FALL_MARGIN_STUDS
end

local function triggerCollapse(fallenSet: { [number]: boolean })
	-- Katastrophen-Kollaps: keine Schuld, niemand verliert den Einsatz.
	local disasterCaused = os.clock() < blameSuspendedUntil

	-- Schuld ermitteln (purer, getesteter Algorithmus).
	local culpritPieceId: number? = nil
	local culpritUserId: number? = nil
	if not disasterCaused then
		local placements: { Types.PlacementRecord } = {}
		local radii: { [number]: number } = {}
		for pieceId, piece in tracked do
			table.insert(placements, { pieceId = pieceId, ownerUserId = piece.ownerUserId, placedAt = piece.placedAt })
			radii[pieceId] = PartCatalog.getApproxRadius(piece.partTypeId)
		end
		local allSamples = getOrderedSamples(GameConfig.RING_BUFFER_SECONDS, nil)
		culpritPieceId, culpritUserId =
			BlameLogic.findCulprit(placements, allSamples, fallenSet, radii, GameConfig.BLAME_CONTACT_MARGIN_STUDS)
	end

	-- Replay-Daten: nur Kaskade + Verursacher-Teil, letzte REPLAY_SECONDS.
	local replayIds: { [number]: boolean } = table.clone(fallenSet)
	if culpritPieceId ~= nil then
		replayIds[culpritPieceId :: number] = true
	end
	local replaySamples = getOrderedSamples(GameConfig.REPLAY_SECONDS, replayIds)

	local pieceInfos: { [number]: Types.ReplayPieceInfo } = {}
	for pieceId in replayIds do
		local piece = tracked[pieceId]
		if piece ~= nil then
			pieceInfos[pieceId] = { partTypeId = piece.partTypeId, ownerUserId = piece.ownerUserId }
		end
	end

	local culpritName: string? = nil
	if culpritUserId ~= nil then
		local culpritPlayer = Players:GetPlayerByUserId(culpritUserId :: number)
		culpritName = if culpritPlayer ~= nil then culpritPlayer.DisplayName else `Spieler {culpritUserId}`
	end

	local replayData: Types.ReplayData = {
		samples = replaySamples,
		pieces = pieceInfos,
		culpritPieceId = culpritPieceId,
		culpritUserId = culpritUserId,
		culpritName = culpritName,
		disasterCaused = disasterCaused,
	}

	-- Wertung informieren (Verursacher verliert den Einsatz) und senden.
	CollapseService.onCollapse(culpritUserId)
	if collapseEvent ~= nil then
		(collapseEvent :: RemoteEvent):FireAllClients(replayData)
	end

	-- Gefallene Teile aufräumen; das Fenster beginnt von vorn.
	for pieceId in fallenSet do
		local piece = tracked[pieceId]
		if piece ~= nil and piece.model.Parent ~= nil then
			piece.model:Destroy()
		end
	end
	table.clear(recentFalls)
end

local function detectionTick()
	local now = os.clock()
	local thresholdY = getFallThresholdY()

	-- Neue Fälle erkennen.
	for pieceId, piece in tracked do
		if piece.fallen or piece.model.Parent == nil then
			continue
		end
		if piece.primaryPart.Position.Y < thresholdY then
			piece.fallen = true
			piece.fallenAt = now
			table.insert(recentFalls, { pieceId = pieceId, at = now })
			CollapseService.onFallen(pieceId)
			-- Einzeln gefallene Teile verschwinden nach kurzer Zeit.
			local model = piece.model
			task.delay(2, function()
				if model.Parent ~= nil then
					model:Destroy()
				end
			end)
		end
	end

	-- Fenster ausdünnen.
	for index = #recentFalls, 1, -1 do
		if now - recentFalls[index].at > GameConfig.FALL_WINDOW_SECONDS then
			table.remove(recentFalls, index)
		end
	end

	-- 30%-Regel prüfen.
	if not detectionActive then
		return
	end
	if trackedCount < GameConfig.FALL_MIN_PIECES then
		return
	end
	if #recentFalls > GameConfig.FALL_COLLAPSE_RATIO * trackedCount then
		local fallenSet: { [number]: boolean } = {}
		for _, fall in recentFalls do
			fallenSet[fall.pieceId] = true
		end
		triggerCollapse(fallenSet)
	end
end

function CollapseService.init()
	collapseEvent = Network.getEvent("CollapseHappened")

	-- Ringpuffer-Takt (4 Hz).
	task.spawn(function()
		local interval = 1 / GameConfig.RING_BUFFER_HZ
		while true do
			task.wait(interval)
			captureSample()
			detectionTick()
		end
	end)
end

return CollapseService
