--!strict
-- MeteorService: Überraschungs-Event auf der eigenen Insel.
--
-- In unregelmäßigen Abständen (GameConfig.METEOR_*) schlägt ein Meteor auf
-- der Insel eines anwesenden Spielers ein: Warnung als Toast, sichtbarer
-- Feuerball-Sturz, Einschlag mit Partikel-Burst - und zurück bleiben
-- glühende Meteor-Kristalle, die nur kurz existieren. Wer schnell genug
-- alle einsammelt, bekommt einen Extra-Bonus. Die Energie wird über
-- EnergyService.grantEnergy gutgeschrieben (alle Multiplikatoren wirken).
--
-- Serverseitig autoritativ: Spawn-Ort, Lebenszeit und Einsammel-Distanz
-- (Magnet-Radius aus dem Profil) entscheidet ausschließlich der Server.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)

local DataService = require(script.Parent.DataService)
local EnergyService = require(script.Parent.EnergyService)
local HarvestService = require(script.Parent.HarvestService)
local PlanetService = require(script.Parent.PlanetService)

local METEOR_COLOR = Color3.fromRGB(255, 140, 50)
local CRYSTAL_COLOR = Color3.fromRGB(255, 170, 90)

-- Einschlagpunkt: im Grasring zwischen Plaza und Biom-Zonen.
local IMPACT_RADIUS_MIN = 20
local IMPACT_RADIUS_MAX = 40
local IMPACT_HEIGHT = 110 -- Starthöhe des Feuerballs über der Insel
local FALL_SECONDS = 1.4

-- Nur wer wirklich auf seiner Insel steht, bekommt einen Meteor.
local PRESENCE_RADIUS = 100
local COLLECT_TICK_SECONDS = 0.3

-- Ein aktiver Kristall eines Einschlags.
type Crystal = {
	part: BasePart,
	expiresAt: number,
}

-- Aktiver Einschlag pro Spieler (maximal einer gleichzeitig).
type MeteorState = {
	crystals: { Crystal },
	totalSpawned: number,
	collected: number,
}

local activeMeteors: { [Player]: MeteorState } = {}

local objectCollectedEvent: RemoteEvent? = nil
local notificationEvent: RemoteEvent? = nil

local rng = Random.new()

local MeteorService = {}

local function notify(player: Player, message: string, kind: string)
	if notificationEvent ~= nil then
		(notificationEvent :: RemoteEvent):FireClient(player, message, kind)
	end
end

-- Charakter-Wurzel eines Spielers (nil, wenn nicht bereit).
local function getRoot(player: Player): BasePart?
	local character = player.Character
	if character == nil then
		return nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if root ~= nil and root:IsA("BasePart") then
		return root
	end
	return nil
end

-- Kurzlebiger Sound an einer Position (Engine-Sound, zerstört sich selbst).
local function playSoundAt(parent: Instance, soundId: string, volume: number, speed: number)
	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.Volume = volume
	sound.PlaybackSpeed = speed
	sound.RollOffMaxDistance = 220
	sound.Parent = parent
	sound:Play()
	task.delay(3, function()
		sound:Destroy()
	end)
end

-- Erzeugt einen glühenden Meteor-Kristall am Einschlagpunkt.
local function spawnCrystal(parent: Instance, position: Vector3): BasePart
	local crystal = Instance.new("Part")
	crystal.Name = "MeteorKristall"
	crystal.Size = Vector3.new(1.6, 2.6, 1.6)
	crystal.Color = CRYSTAL_COLOR
	crystal.Material = Enum.Material.Neon
	crystal.Anchored = true
	crystal.CanCollide = false
	crystal.CanQuery = false
	crystal.CanTouch = false
	crystal.CFrame = CFrame.new(position)
		* CFrame.Angles(rng:NextNumber(-0.3, 0.3), rng:NextNumber(0, math.pi), rng:NextNumber(-0.3, 0.3))

	local light = Instance.new("PointLight")
	light.Color = CRYSTAL_COLOR
	light.Range = 9
	light.Brightness = 1
	light.Parent = crystal

	crystal.Parent = parent
	return crystal
end

-- Lässt den Feuerball fallen und legt danach die Kristalle aus.
local function launchMeteor(player: Player, origin: CFrame)
	local angle = rng:NextNumber(0, 2 * math.pi)
	local distance = rng:NextNumber(IMPACT_RADIUS_MIN, IMPACT_RADIUS_MAX)
	-- Y: Inseloberkante (+2) plus etwas Luft.
	local impactPosition = origin.Position + Vector3.new(math.cos(angle) * distance, 3, math.sin(angle) * distance)

	notify(player, "☄️ Achtung: Ein Meteor stürzt auf deine Insel!", "info")

	-- Feuerball mit Leucht-Schweif.
	local meteor = Instance.new("Part")
	meteor.Name = "Meteor"
	meteor.Shape = Enum.PartType.Ball
	meteor.Size = Vector3.new(5, 5, 5)
	meteor.Color = METEOR_COLOR
	meteor.Material = Enum.Material.Neon
	meteor.Anchored = true
	meteor.CanCollide = false
	meteor.CanQuery = false
	meteor.CanTouch = false
	meteor.CFrame = CFrame.new(impactPosition + Vector3.new(12, IMPACT_HEIGHT, 12))

	local trail = Instance.new("ParticleEmitter")
	trail.Color = ColorSequence.new(METEOR_COLOR, Color3.fromRGB(120, 60, 30))
	trail.LightEmission = 0.8
	trail.Rate = 40
	trail.Lifetime = NumberRange.new(0.5, 1)
	trail.Speed = NumberRange.new(1, 3)
	trail.Size = NumberSequence.new(1.4)
	trail.Parent = meteor

	local glow = Instance.new("PointLight")
	glow.Color = METEOR_COLOR
	glow.Range = 24
	glow.Brightness = 1.5
	glow.Parent = meteor

	meteor.Parent = Workspace
	playSoundAt(meteor, "rbxasset://sounds/swoosh.wav", 0.8, 0.6)

	local fall = TweenService:Create(
		meteor,
		TweenInfo.new(FALL_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ CFrame = CFrame.new(impactPosition) }
	)
	fall:Play()
	fall.Completed:Once(function()
		-- Einschlag: Knall, Lichtblitz, Partikel-Burst - dann Kristalle.
		playSoundAt(meteor, "rbxasset://sounds/snap.mp3", 1, 0.55)
		local burst = Instance.new("ParticleEmitter")
		burst.Color = ColorSequence.new(METEOR_COLOR, Color3.new(1, 1, 1))
		burst.LightEmission = 1
		burst.Rate = 0
		burst.Lifetime = NumberRange.new(0.5, 1)
		burst.Speed = NumberRange.new(12, 22)
		burst.SpreadAngle = Vector2.new(180, 180)
		burst.Size = NumberSequence.new(1)
		burst.Parent = meteor
		burst:Emit(40)

		task.delay(1.2, function()
			meteor:Destroy()
		end)

		-- Spieler könnte während des Sturzes gegangen sein.
		if player.Parent == nil then
			return
		end

		-- Kristalle im Kreis um den Einschlagpunkt (überleben nur kurz).
		local plotFolder = Workspace:FindFirstChild("PlanetPlots")
		local parent: Instance = if plotFolder ~= nil then plotFolder else Workspace
		local state: MeteorState = {
			crystals = {},
			totalSpawned = GameConfig.METEOR_CRYSTAL_COUNT,
			collected = 0,
		}
		for index = 1, GameConfig.METEOR_CRYSTAL_COUNT do
			local crystalAngle = (index / GameConfig.METEOR_CRYSTAL_COUNT) * 2 * math.pi + rng:NextNumber(-0.4, 0.4)
			local crystalDistance = rng:NextNumber(3, 6.5)
			local position = impactPosition
				+ Vector3.new(math.cos(crystalAngle) * crystalDistance, 0.4, math.sin(crystalAngle) * crystalDistance)
			table.insert(state.crystals, {
				part = spawnCrystal(parent, position),
				expiresAt = os.clock() + GameConfig.METEOR_CRYSTAL_LIFETIME_SECONDS,
			})
		end
		activeMeteors[player] = state
		notify(
			player,
			`☄️ Meteor eingeschlagen! Sammle {GameConfig.METEOR_CRYSTAL_COUNT} Kristalle, bevor sie zerfallen!`,
			"success"
		)
	end)
end

-- Ein Sammel-/Zerfalls-Takt für die Kristalle eines Spielers.
local function crystalTick(player: Player, state: MeteorState)
	local profile = DataService.getProfile(player)
	local root = getRoot(player)
	local now = os.clock()

	for index = #state.crystals, 1, -1 do
		local crystal = state.crystals[index]

		if crystal.part.Parent == nil then
			table.remove(state.crystals, index)
			continue
		end

		-- Zerfall: Kristall schrumpft sichtbar weg.
		if now >= crystal.expiresAt then
			table.remove(state.crystals, index)
			local part = crystal.part
			local tween = TweenService:Create(
				part,
				TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{ Size = part.Size * 0.05, Transparency = 1 }
			)
			tween:Play()
			tween.Completed:Once(function()
				part:Destroy()
			end)
			continue
		end

		-- Einsammeln über den Magnet-Radius des Profils.
		if profile ~= nil and root ~= nil then
			local radius = HarvestService.getMagnetRadius(profile)
			if (crystal.part.Position - root.Position).Magnitude <= radius then
				table.remove(state.crystals, index)
				state.collected += 1

				local gained = EnergyService.grantEnergy(player, GameConfig.METEOR_CRYSTAL_VALUE)
				profile.stats.collected += 1
				DataService.markDirty(player)

				if objectCollectedEvent ~= nil then
					(objectCollectedEvent :: RemoteEvent):FireClient(
						player,
						crystal.part.Position,
						gained,
						CRYSTAL_COLOR,
						nil,
						true -- Gold-Juice auch für Meteor-Kristalle
					)
				end
				crystal.part:Destroy()

				-- Alle erwischt? Extra-Bonus für den vollen Abbau.
				if state.collected >= state.totalSpawned then
					local bonus = EnergyService.grantEnergy(player, GameConfig.METEOR_CLEAR_BONUS)
					notify(player, `☄️ Meteor komplett abgebaut! Bonus: +{bonus} Energie! 🎉`, "success")
				end
			end
		end
	end

	if #state.crystals == 0 then
		activeMeteors[player] = nil
	end
end

function MeteorService.init()
	objectCollectedEvent = Remotes.getEvent("ObjectCollected")
	notificationEvent = Remotes.getEvent("Notification")

	Players.PlayerRemoving:Connect(function(player)
		local state = activeMeteors[player]
		if state ~= nil then
			for _, crystal in state.crystals do
				if crystal.part.Parent ~= nil then
					crystal.part:Destroy()
				end
			end
		end
		activeMeteors[player] = nil
	end)

	-- Würfel-Schleife: entscheidet pro Spieler, ob ein Meteor kommt.
	task.spawn(function()
		while true do
			task.wait(GameConfig.METEOR_CHECK_INTERVAL_SECONDS)
			for _, player in Players:GetPlayers() do
				if activeMeteors[player] ~= nil then
					continue -- es liegen noch Kristalle
				end
				if rng:NextNumber() >= GameConfig.METEOR_CHANCE_PER_CHECK then
					continue
				end
				local origin = PlanetService.getPlotOrigin(player)
				local root = getRoot(player)
				if origin == nil or root == nil then
					continue
				end
				-- Nur wenn der Spieler wirklich auf seiner Insel steht.
				if (root.Position - origin.Position).Magnitude > PRESENCE_RADIUS then
					continue
				end
				launchMeteor(player, origin)
			end
		end
	end)

	-- Sammel-/Zerfalls-Schleife für aktive Kristalle.
	task.spawn(function()
		while true do
			task.wait(COLLECT_TICK_SECONDS)
			for player, state in activeMeteors do
				crystalTick(player, state)
			end
		end
	end)
end

return MeteorService
