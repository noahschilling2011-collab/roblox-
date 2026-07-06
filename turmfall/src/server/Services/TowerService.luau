--!strict
-- TowerService: der gemeinsame Turm - Arena, Platzierung, Physik-Budget.
--
-- =========================================================================
-- PHYSIK-OWNERSHIP (das kritischste technische Detail des Projekts):
-- Alle Turm-Teile werden mit BasePart:SetNetworkOwner(nil) SERVER-OWNED
-- gemacht. Ohne das würde Roblox die Physiksimulation naher Teile an
-- einzelne Clients delegieren - ein manipulierter Client könnte dann
-- Teile "weich" fallen lassen, fremde Segmente anschubsen oder den
-- Kollaps-Zeitpunkt verfälschen. Da unser Schuld-System aus den
-- Teil-Positionen den Verursacher ableitet, wäre die Schuldzuweisung
-- damit manipulierbar und unfair. Server-Ownership kostet etwas Latenz
-- im Physik-Gefühl, garantiert aber, dass ALLE Spieler dieselbe,
-- unbestechliche Simulation sehen.
-- =========================================================================
--
-- Platzierung: Der Client schickt nur einen WUNSCH (Teiltyp + CFrame).
-- Der Server validiert ALLES: Phase, Cooldown, Teilbesitz (DeckService),
-- Reichweite, Nachbarschaft, Überlappung. Niemals dem Client vertrauen.
--
-- Physik-Budget: Maximal GameConfig.MAX_PHYSICS_PARTS aktive Teile.
-- Ab dem Limit werden die untersten, ruhigen Teile "versteinert"
-- (Anchored = true -> raus aus der Simulation). Das ist von Anfang an
-- eingebaut, weil ein nachgerüstetes Limit bestehende Türme zerreißen würde.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Network = require(Shared.Network)
local GameConfig = require(Shared.Config.GameConfig)
local PartCatalog = require(Shared.Config.PartCatalog)
local Types = require(Shared.Types)

local DeckService = require(script.Parent.DeckService)
local CollapseService = require(script.Parent.CollapseService)

-- Ein platziertes Teil im Turm.
export type Piece = {
	pieceId: number,
	model: Model,
	primaryPart: BasePart,
	ownerUserId: number,
	partTypeId: string,
	placedAt: number,
	petrified: boolean,
	fallen: boolean,
}

local TowerService = {}

local pieces: { Piece } = {}
local piecesById: { [number]: Piece } = {}
local nextPieceId = 1

local buildAllowed = false
local lastPlaceAt: { [Player]: number } = {}

local towerFolder: Folder? = nil
local basePlatform: BasePart? = nil

local partPlacedEvent: RemoteEvent? = nil

-- Hook (RoundService/M4): zusätzliche Platzierungsregeln, z. B. das Finale.
TowerService.extraPlacementCheck = function(_player: Player, _cframe: CFrame): (boolean, string?)
	return true, nil
end

--------------------------------------------------------------------------
-- Arena
--------------------------------------------------------------------------

local function getTowerFolder(): Folder
	if towerFolder ~= nil and towerFolder.Parent ~= nil then
		return towerFolder :: Folder
	end
	local folder = Instance.new("Folder")
	folder.Name = "Turm"
	folder.Parent = Workspace
	towerFolder = folder
	return folder
end

-- Baut die schwebende Arena: Basisplattform über dem Abgrund plus Spawn.
function TowerService.buildArena()
	if basePlatform ~= nil and basePlatform.Parent ~= nil then
		return
	end

	local arena = Instance.new("Folder")
	arena.Name = "Arena"

	local platform = Instance.new("Part")
	platform.Name = "Basisplattform"
	platform.Size = Vector3.new(GameConfig.BASE_PLATFORM_SIZE, GameConfig.BASE_PLATFORM_THICKNESS, GameConfig.BASE_PLATFORM_SIZE)
	platform.Position = Vector3.new(0, GameConfig.BASE_PLATFORM_Y, 0)
	platform.Anchored = true
	platform.Material = Enum.Material.Slate
	platform.Color = Color3.fromRGB(120, 118, 126)
	platform.Parent = arena
	basePlatform = platform

	-- Goldene Zielmarkierung in der Mitte.
	local marker = Instance.new("Part")
	marker.Name = "Mittelmarke"
	marker.Size = Vector3.new(6, 0.1, 6)
	marker.Position = platform.Position + Vector3.new(0, GameConfig.BASE_PLATFORM_THICKNESS / 2 + 0.05, 0)
	marker.Anchored = true
	marker.CanCollide = false
	marker.Material = Enum.Material.Neon
	marker.Color = Color3.fromRGB(255, 210, 90)
	marker.Transparency = 0.5
	marker.Parent = arena

	-- Spawn auf der Plattform (vorhandenen SpawnLocation umziehen oder anlegen).
	local spawnLocation = Workspace:FindFirstChildWhichIsA("SpawnLocation", true)
	if spawnLocation == nil then
		spawnLocation = Instance.new("SpawnLocation")
		spawnLocation.Name = "ArenaSpawn"
		spawnLocation.Anchored = true
		spawnLocation.Parent = arena
	end
	local spawnPad = spawnLocation :: SpawnLocation
	spawnPad.Size = Vector3.new(8, 0.4, 8)
	spawnPad.CFrame = CFrame.new(
		0,
		GameConfig.BASE_PLATFORM_Y + GameConfig.BASE_PLATFORM_THICKNESS / 2 + 0.2,
		GameConfig.BASE_PLATFORM_SIZE / 2 - 5
	)
	spawnPad.Color = Color3.fromRGB(60, 62, 74)
	spawnPad.Duration = 0

	arena.Parent = Workspace
end

-- Oberkante der Basisplattform (Welt-Y).
function TowerService.getBaseTopY(): number
	return GameConfig.BASE_PLATFORM_Y + GameConfig.BASE_PLATFORM_THICKNESS / 2
end

--------------------------------------------------------------------------
-- Platzierungs-Validierung (alles serverseitig)
--------------------------------------------------------------------------

-- Client-CFrames werden NIE übernommen: Wir extrahieren nur Position und
-- Y-Rotation und bauen daraus einen sauberen, aufrechten CFrame.
local function sanitizeCFrame(cframeArg: unknown): CFrame?
	if typeof(cframeArg) ~= "CFrame" then
		return nil
	end
	local cframe = cframeArg :: CFrame
	local position = cframe.Position
	-- NaN/Inf abwehren.
	if position.X ~= position.X or math.abs(position.X) > 10000 then
		return nil
	end
	if position.Y ~= position.Y or math.abs(position.Y) > 10000 then
		return nil
	end
	if position.Z ~= position.Z or math.abs(position.Z) > 10000 then
		return nil
	end
	-- Nur die Y-Rotation (Gieren) übernehmen, auf 45°-Schritte gerastert.
	local lookVector = cframe.LookVector
	local yaw = math.atan2(-lookVector.X, -lookVector.Z)
	local snappedYaw = math.rad(math.round(math.deg(yaw) / 45) * 45)
	return CFrame.new(position) * CFrame.Angles(0, snappedYaw, 0)
end

-- Nachbarschaft: nah genug an der Plattform ODER an einem existierenden Teil.
local function isAdjacent(targetPosition: Vector3, ownRadius: number): boolean
	local platform = basePlatform
	if platform ~= nil then
		local half = GameConfig.BASE_PLATFORM_SIZE / 2
		local topY = TowerService.getBaseTopY()
		local withinX = math.abs(targetPosition.X - platform.Position.X) <= half
		local withinZ = math.abs(targetPosition.Z - platform.Position.Z) <= half
		local aboveTop = targetPosition.Y - topY
		if withinX and withinZ and aboveTop >= 0 and aboveTop <= ownRadius + GameConfig.PLACE_ADJACENCY_STUDS then
			return true
		end
	end

	for _, piece in pieces do
		if piece.fallen or piece.primaryPart.Parent == nil then
			continue
		end
		local otherRadius = PartCatalog.getApproxRadius(piece.partTypeId)
		local maxGap = ownRadius + otherRadius + GameConfig.PLACE_ADJACENCY_STUDS
		if (piece.primaryPart.Position - targetPosition).Magnitude <= maxGap then
			return true
		end
	end
	return false
end

-- Überlappung: Zielvolumen darf keine existierenden Turm-Teile schneiden.
local function overlapsExistingParts(targetCFrame: CFrame, partTypeId: string): boolean
	local def = PartCatalog.Parts[partTypeId]
	if def == nil then
		return true
	end
	-- Leicht verkleinert, damit bündiges Anlegen erlaubt bleibt.
	local checkSize = Vector3.new(def.size.x, def.size.y, def.size.z) * 0.85
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { getTowerFolder() }
	local found = Workspace:GetPartBoundsInBox(targetCFrame, checkSize, params)
	return #found > 0
end

-- Remote-Handler: PlacePart(partTypeId, cframe) -> (ok, err?).
local function handlePlacePart(player: Player, partTypeIdArg: unknown, cframeArg: unknown): (boolean, any?)
	if not buildAllowed then
		return false, "Gerade ist keine Bauphase."
	end
	if typeof(partTypeIdArg) ~= "string" or PartCatalog.Parts[partTypeIdArg] == nil then
		return false, "Unbekannter Teiltyp."
	end
	local partTypeId = partTypeIdArg :: string

	local targetCFrame = sanitizeCFrame(cframeArg)
	if targetCFrame == nil then
		return false, "Ungültige Zielposition."
	end
	local cframe = targetCFrame :: CFrame

	-- Anti-Spam-Cooldown.
	local now = os.clock()
	if now - (lastPlaceAt[player] or 0) < GameConfig.PLACE_COOLDOWN_SECONDS then
		return false, "Nicht so schnell - kurz warten!"
	end

	-- Reichweite: Zielposition muss nah am Charakter liegen.
	local character = player.Character
	local root = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
	if root == nil or not root:IsA("BasePart") then
		return false, "Dein Charakter ist gerade nicht bereit."
	end
	if ((root :: BasePart).Position - cframe.Position).Magnitude > GameConfig.PLACE_REACH_STUDS then
		return false, `Zu weit weg (max. {GameConfig.PLACE_REACH_STUDS} Studs).`
	end

	-- Nachbarschaft: nur angrenzend an Plattform oder existierende Teile.
	local ownRadius = PartCatalog.getApproxRadius(partTypeId)
	if not isAdjacent(cframe.Position, ownRadius) then
		return false, "Du musst angrenzend an den Turm oder die Plattform bauen."
	end

	-- Kein Hineinbauen in existierende Teile.
	if overlapsExistingParts(cframe, partTypeId) then
		return false, "Dort ist schon ein Teil im Weg."
	end

	-- Zusätzliche Regeln (z. B. Finale/Sabotage in späteren Meilensteinen).
	local extraOk, extraErr = TowerService.extraPlacementCheck(player, cframe)
	if not extraOk then
		return false, extraErr or "Platzierung gerade nicht erlaubt."
	end

	-- Teil MUSS aus der eigenen Hotbar kommen (verbraucht es atomar).
	if not DeckService.consumePart(player, partTypeId) then
		return false, "Dieses Teil hast du nicht in der Hotbar."
	end

	lastPlaceAt[player] = now

	-- Jetzt wirklich bauen.
	local model = PartCatalog.create(partTypeId)
	model:PivotTo(cframe)
	model.Name = `Teil_{nextPieceId}_{partTypeId}`
	model:SetAttribute("OwnerUserId", player.UserId)
	model.Parent = getTowerFolder()

	-- SERVER-OWNERSHIP für jedes BasePart (siehe Kopfkommentar: ohne das
	-- wäre die Schuldzuweisung beim Kollaps durch Clients manipulierbar).
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant:SetNetworkOwner(nil)
		end
	end

	local piece: Piece = {
		pieceId = nextPieceId,
		model = model,
		primaryPart = model.PrimaryPart :: BasePart,
		ownerUserId = player.UserId,
		partTypeId = partTypeId,
		placedAt = now,
		petrified = false,
		fallen = false,
	}
	nextPieceId += 1
	table.insert(pieces, piece)
	piecesById[piece.pieceId] = piece

	-- Schuld-System: Platzierer + Zeitstempel loggen, Ringpuffer registrieren.
	CollapseService.registerPiece(piece.pieceId, player.UserId, partTypeId, piece.primaryPart, model, now)

	if partPlacedEvent ~= nil then
		(partPlacedEvent :: RemoteEvent):FireAllClients(cframe.Position, partTypeId)
	end
	return true, nil
end

--------------------------------------------------------------------------
-- Physik-Budget: Versteinern der untersten, ruhigen Teile
--------------------------------------------------------------------------

local function countActivePhysicsParts(): number
	local count = 0
	for _, piece in pieces do
		if piece.fallen or piece.petrified or piece.model.Parent == nil then
			continue
		end
		for _, descendant in piece.model:GetDescendants() do
			if descendant:IsA("BasePart") then
				count += 1
			end
		end
	end
	return count
end

local function petrifyPiece(piece: Piece)
	piece.petrified = true
	for _, descendant in piece.model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
		end
	end
	-- Dezente optische Rückmeldung: versteinerte Teile wirken "gesetzt".
	piece.primaryPart.Material = Enum.Material.Concrete
end

local function petrifyTick()
	local active = countActivePhysicsParts()
	if active <= GameConfig.MAX_PHYSICS_PARTS then
		return
	end
	local target = math.floor(GameConfig.MAX_PHYSICS_PARTS * GameConfig.PETRIFY_TARGET_RATIO)

	-- Unterste zuerst (Kopie sortieren, Original-Reihenfolge = Platzierung).
	local candidates = {}
	for _, piece in pieces do
		if not piece.fallen and not piece.petrified and piece.model.Parent ~= nil then
			table.insert(candidates, piece)
		end
	end
	table.sort(candidates, function(a, b)
		return a.primaryPart.Position.Y < b.primaryPart.Position.Y
	end)

	for _, piece in candidates do
		if active <= target then
			break
		end
		-- Nur ruhige Teile versteinern - ein fliegendes Teil einzufrieren
		-- würde den Kollaps-Verlauf verfälschen.
		if piece.primaryPart.AssemblyLinearVelocity.Magnitude > GameConfig.PETRIFY_MAX_SPEED then
			continue
		end
		petrifyPiece(piece)
		for _, descendant in piece.model:GetDescendants() do
			if descendant:IsA("BasePart") then
				active -= 1
			end
		end
	end
end

--------------------------------------------------------------------------
-- Rundensteuerung / öffentliche API
--------------------------------------------------------------------------

function TowerService.setBuildAllowed(allowed: boolean)
	buildAllowed = allowed
end

-- Entfernt alle Teile (neue Runde).
function TowerService.resetTower()
	for _, piece in pieces do
		if piece.model.Parent ~= nil then
			piece.model:Destroy()
		end
	end
	table.clear(pieces)
	table.clear(piecesById)
	table.clear(lastPlaceAt)
end

-- Markiert ein Teil als gefallen (ruft der CollapseService).
function TowerService.markFallen(pieceId: number)
	local piece = piecesById[pieceId]
	if piece ~= nil then
		piece.fallen = true
	end
end

-- Zerstört das Modell eines gefallenen Teils (nach dem Kollaps/Timeout).
function TowerService.destroyPiece(pieceId: number)
	local piece = piecesById[pieceId]
	if piece ~= nil and piece.model.Parent ~= nil then
		piece.model:Destroy()
	end
end

-- Reine Sicht für die Punkteberechnung (ScoreLogic).
function TowerService.getScoringPieces(): { Types.ScoringPiece }
	local baseTopY = TowerService.getBaseTopY()
	local result: { Types.ScoringPiece } = {}
	for _, piece in pieces do
		local stillThere = piece.model.Parent ~= nil and not piece.fallen
		table.insert(result, {
			ownerUserId = piece.ownerUserId,
			heightAboveBase = if stillThere then piece.primaryPart.Position.Y - baseTopY else 0,
			fallen = not stillThere,
		})
	end
	return result
end

function TowerService.getPieceCount(): number
	local count = 0
	for _, piece in pieces do
		if not piece.fallen and piece.model.Parent ~= nil then
			count += 1
		end
	end
	return count
end

function TowerService.getPiece(pieceId: number): Piece?
	return piecesById[pieceId]
end

function TowerService.init()
	partPlacedEvent = Network.getEvent("PartPlaced")
	Network.getFunction("PlacePart").OnServerInvoke = handlePlacePart

	-- Hook: der CollapseService meldet gefallene Teile zurück (kein Zyklus,
	-- weil nur WIR ihn requiren - er kennt uns nicht).
	CollapseService.onFallen = TowerService.markFallen

	TowerService.buildArena()

	Players.PlayerRemoving:Connect(function(player)
		lastPlaceAt[player] = nil
	end)

	-- Physik-Budget von Anfang an überwachen.
	task.spawn(function()
		while true do
			task.wait(GameConfig.PETRIFY_CHECK_SECONDS)
			petrifyTick()
		end
	end)
end

return TowerService
