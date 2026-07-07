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

export type DisasterId = "windboe" | "erdbeben" | "goldrausch" | "meteor"

local DISASTERS: { { id: DisasterId, weight: number, label: string } } = {
	{ id = "windboe", weight = 28, label = "💨 WINDBÖE im Anflug - haltet euch fest!" },
	{ id = "erdbeben", weight = 24, label = "🌍 ERDBEBEN! Der Boden fängt gleich an zu beben!" },
	{ id = "goldrausch", weight = 28, label = "✨ GOLDRAUSCH! Gleich zählt jedes neue Teil 3-fach!" },
	{ id = "meteor", weight = 20, label = "☄️ METEOR IM ANFLUG - weg vom Turm!" },
}

local DisasterService = {}

-- Hook (QuestService): wird nach jedem beendeten Event gefeuert.
DisasterService.onDisasterEnded = function(_eventId: string) end

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

-- Meteor: Feuerball stürzt auf den höchsten Turmbereich, Druckwelle
-- schleudert Teile im Umkreis weg. Reines Physik-Spektakel - Charaktere
-- bleiben unberührt (kinderfreundlich), Schuld ist ausgesetzt.
local function runMeteor()
	CollapseService.suspendBlame(GameConfig.METEOR_FALL_SECONDS + GameConfig.DISASTER_BLAME_GRACE_SECONDS)

	-- Ziel: Position eines zufälligen aktiven Teils (sonst Plattform-Mitte).
	local parts = TowerService.getActivePrimaryParts()
	local targetPosition = Vector3.new(0, TowerService.getBaseTopY(), 0)
	if #parts > 0 then
		targetPosition = parts[rng:NextInteger(1, #parts)].Position
	end

	local meteor = Instance.new("Part")
	meteor.Name = "Meteor"
	meteor.Shape = Enum.PartType.Ball
	meteor.Size = Vector3.new(6, 6, 6)
	meteor.Color = Color3.fromRGB(255, 130, 50)
	meteor.Material = Enum.Material.Neon
	meteor.Anchored = true
	meteor.CanCollide = false
	meteor.CanQuery = false
	meteor.CanTouch = false
	meteor.Position = targetPosition + Vector3.new(24, 90, 24)

	local trail = Instance.new("ParticleEmitter")
	trail.Color = ColorSequence.new(Color3.fromRGB(255, 130, 50), Color3.fromRGB(120, 60, 30))
	trail.LightEmission = 0.8
	trail.Rate = 50
	trail.Lifetime = NumberRange.new(0.4, 0.9)
	trail.Speed = NumberRange.new(1, 3)
	trail.Size = NumberSequence.new(1.6)
	trail.Parent = meteor
	meteor.Parent = workspace

	-- Sturz als Server-Tween (alle sehen exakt dasselbe).
	local TweenService = game:GetService("TweenService")
	local fall = TweenService:Create(
		meteor,
		TweenInfo.new(GameConfig.METEOR_FALL_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ Position = targetPosition }
	)
	fall:Play()
	fall.Completed:Wait()

	-- Einschlag: Knall + Druckwelle auf Teile im Radius.
	local burst = Instance.new("ParticleEmitter")
	burst.Color = ColorSequence.new(Color3.fromRGB(255, 160, 70), Color3.new(1, 1, 1))
	burst.LightEmission = 1
	burst.Rate = 0
	burst.Lifetime = NumberRange.new(0.5, 1)
	burst.Speed = NumberRange.new(14, 26)
	burst.SpreadAngle = Vector2.new(180, 180)
	burst.Size = NumberSequence.new(1.2)
	burst.Parent = meteor
	burst:Emit(50)

	local sound = Instance.new("Sound")
	sound.SoundId = "rbxasset://sounds/impact_water.mp3"
	sound.Volume = 1
	sound.PlaybackSpeed = 0.5
	sound.RollOffMaxDistance = 300
	sound.Parent = meteor
	sound:Play()

	for _, part in TowerService.getActivePrimaryParts() do
		local offset = part.Position - targetPosition
		local distance = offset.Magnitude
		if distance <= GameConfig.METEOR_BLAST_RADIUS then
			local falloff = 1 - distance / GameConfig.METEOR_BLAST_RADIUS
			local direction = if distance > 0.1 then offset.Unit else Vector3.new(0, 1, 0)
			part.AssemblyLinearVelocity += (direction + Vector3.new(0, 0.4, 0))
				* GameConfig.METEOR_BLAST_SPEED
				* falloff
		end
	end

	task.delay(1.5, function()
		meteor:Destroy()
	end)
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
		elseif disaster.id == "meteor" then
			runMeteor()
		else
			runGoldRush()
		end
		fireStage(disaster.id, "ende")
		DisasterService.onDisasterEnded(disaster.id)
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
