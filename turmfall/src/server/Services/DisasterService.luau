--!strict
-- DisasterService: Katastrophen-Events mitten in der Bauphase.
--
-- Inspiriert von den erfolgreichsten Roblox-Rundenspielen (Natural
-- Disaster Survival & Co.): Zufällige, VORGEWARNTE Ereignisse machen
-- jede Runde anders und erzeugen "Alle-schreien-gleichzeitig"-Momente.
--
--   💨 Windböe    seitliche Stöße auf alle aktiven Teile
--   🌍 Erdbeben   zufälliges Rütteln für einige Sekunden
--   ✨ Goldrausch  jeder bekommt ein Gratis-Teil; wer im Zeitfenster
--                 platziert, baut GOLDENE Teile mit 3-facher Wertung
--
-- Fairness: Während (und kurz nach) Wind/Erdbeben ist die Schuld-Zuweisung
-- ausgesetzt (CollapseService.suspendBlame) - für Katastrophen verliert
-- NIEMAND seinen Einsatz. Der Server bleibt für alles autoritativ; die
-- Clients bekommen nur DisasterEvent für Banner/Sounds/Geruckel.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Network = require(Shared.Network)
local GameConfig = require(Shared.Config.GameConfig)

local DeckService = require(script.Parent.DeckService)
local CollapseService = require(script.Parent.CollapseService)
local TowerService = require(script.Parent.TowerService)

export type DisasterId = "windboe" | "erdbeben" | "goldrausch"

local DISASTERS: { { id: DisasterId, weight: number, label: string } } = {
	{ id = "windboe", weight = 35, label = "💨 WINDBÖE im Anflug - haltet euch fest!" },
	{ id = "erdbeben", weight = 30, label = "🌍 ERDBEBEN! Der Boden fängt gleich an zu beben!" },
	{ id = "goldrausch", weight = 35, label = "✨ GOLDRAUSCH! Gleich zählt jedes neue Teil 3-fach!" },
}

local DisasterService = {}

local active = false
local eventRunning = false
local lastEventAt = 0

local disasterEvent: RemoteEvent? = nil
local notificationEvent: RemoteEvent? = nil

local rng = Random.new()

local function fireStage(eventId: string, stage: string)
	if disasterEvent ~= nil then
		(disasterEvent :: RemoteEvent):FireAllClients(eventId, stage)
	end
end

local function notifyAll(message: string, kind: string)
	if notificationEvent ~= nil then
		(notificationEvent :: RemoteEvent):FireAllClients(message, kind)
	end
end

local function pickDisaster(): { id: DisasterId, weight: number, label: string }
	local totalWeight = 0
	for _, disaster in DISASTERS do
		totalWeight += disaster.weight
	end
	local roll = rng:NextNumber(0, totalWeight)
	local runningSum = 0
	for _, disaster in DISASTERS do
		runningSum += disaster.weight
		if roll <= runningSum then
			return disaster
		end
	end
	return DISASTERS[1]
end

--------------------------------------------------------------------------
-- Die drei Ereignisse
--------------------------------------------------------------------------

local function runWind()
	-- Zufällige horizontale Richtung; Stöße im Takt auf alle aktiven Teile.
	local angle = rng:NextNumber(0, 2 * math.pi)
	local windDirection = Vector3.new(math.cos(angle), 0.15, math.sin(angle))
	CollapseService.suspendBlame(GameConfig.WIND_DURATION_SECONDS + GameConfig.DISASTER_BLAME_GRACE_SECONDS)

	local endsAt = os.clock() + GameConfig.WIND_DURATION_SECONDS
	while os.clock() < endsAt do
		for _, part in TowerService.getActivePrimaryParts() do
			part.AssemblyLinearVelocity += windDirection * GameConfig.WIND_IMPULSE_SPEED
		end
		task.wait(0.4)
	end
end

local function runQuake()
	CollapseService.suspendBlame(GameConfig.QUAKE_DURATION_SECONDS + GameConfig.DISASTER_BLAME_GRACE_SECONDS)

	local endsAt = os.clock() + GameConfig.QUAKE_DURATION_SECONDS
	while os.clock() < endsAt do
		for _, part in TowerService.getActivePrimaryParts() do
			part.AssemblyLinearVelocity += Vector3.new(
				rng:NextNumber(-1, 1) * GameConfig.QUAKE_IMPULSE_SPEED,
				rng:NextNumber(0, 0.6) * GameConfig.QUAKE_IMPULSE_SPEED,
				rng:NextNumber(-1, 1) * GameConfig.QUAKE_IMPULSE_SPEED
			)
		end
		task.wait(0.5)
	end
end

local function runGoldRush()
	-- Jeder bekommt sofort ein Teil; das Gold-Fenster öffnet der TowerService.
	TowerService.setGoldRush(GameConfig.GOLDRUSH_WINDOW_SECONDS)
	for _, player in Players:GetPlayers() do
		DeckService.grantPart(player, "leichtblock")
	end
	notifyAll(
		`✨ GOLDRAUSCH: {GameConfig.GOLDRUSH_WINDOW_SECONDS} Sekunden lang zählen neue Teile {GameConfig.GOLD_SCORE_MULTIPLIER}-fach!`,
		"success"
	)
	task.wait(GameConfig.GOLDRUSH_WINDOW_SECONDS)
end

--------------------------------------------------------------------------
-- Ablauf
--------------------------------------------------------------------------

local function runDisaster()
	eventRunning = true
	local disaster = pickDisaster()

	-- Vorwarnung (Banner + Sound machen die Clients).
	notifyAll(disaster.label, "error")
	fireStage(disaster.id, "warnung")
	task.wait(GameConfig.DISASTER_WARNING_SECONDS)

	-- Phase könnte inzwischen vorbei sein.
	if active then
		fireStage(disaster.id, "start")
		if disaster.id == "windboe" then
			runWind()
		elseif disaster.id == "erdbeben" then
			runQuake()
		else
			runGoldRush()
		end
		fireStage(disaster.id, "ende")
	end

	lastEventAt = os.clock()
	eventRunning = false
end

-- RoundService schaltet die Events pro Phase an/aus.
function DisasterService.setActive(isActive: boolean)
	active = isActive
	if isActive then
		lastEventAt = os.clock() -- Mindestabstand ab Phasenstart
	end
end

function DisasterService.init()
	disasterEvent = Network.getEvent("DisasterEvent")
	notificationEvent = Network.getEvent("Notification")

	task.spawn(function()
		while true do
			task.wait(GameConfig.DISASTER_CHECK_SECONDS)
			if not active or eventRunning then
				continue
			end
			if os.clock() - lastEventAt < GameConfig.DISASTER_MIN_GAP_SECONDS then
				continue
			end
			-- Erst würfeln, wenn genug Teile stehen (sonst ist Wind witzlos).
			if TowerService.getPieceCount() < GameConfig.FALL_MIN_PIECES then
				continue
			end
			if rng:NextNumber() < GameConfig.DISASTER_CHANCE_PER_CHECK then
				task.spawn(runDisaster)
			end
		end
	end)
end

return DisasterService
