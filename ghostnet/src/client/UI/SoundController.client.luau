-- StarterPlayer/StarterPlayerScripts/UI/SoundController.client.luau
--!strict
-- GHOSTNET :: Spielt die Klaenge aus dem SoundCatalog.
--
-- Der Controller kennt keine einzige Asset-Id. Er fragt den SoundCatalog,
-- und wenn dort noch nichts eingetragen ist, passiert schlicht nichts -
-- das Spiel bleibt lauffaehig, es klingt nur nach nichts.
--
-- Zwei Dinge machen hier den Unterschied:
--   1. Die Tonhoehe der Knoten-Klicks steigt mit der Pfadlaenge. Aus
--      Klickgeraeuschen wird eine aufsteigende Melodie, und ein geloestes
--      Raetsel klingt nach Erfolg.
--   2. Die Ambience wird waehrend eines Hacks leiser, damit die UI-Sounds
--      tragen - und kommt beim Alarm schlagartig laut zurueck.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local SoundCatalog = require(ReplicatedStorage.Shared.SoundCatalog)

local player = Players.LocalPlayer
local S = SoundCatalog.Settings

--==========================================================================
-- Abspielen
--==========================================================================

local holder = Instance.new("Folder")
holder.Name = "GhostNetSounds"
holder.Parent = SoundService

-- Ein Sound pro Aufruf. Bei leerer Id passiert nichts.
local function play(group: string, key: string, volume: number?, pitch: number?): Sound?
	local id = SoundCatalog.Get(group, key)
	if not id then
		return nil
	end

	local sound = Instance.new("Sound")
	sound.SoundId = id
	sound.Volume = volume or S.UIVolume
	sound.PlaybackSpeed = pitch or 1
	sound.Parent = holder
	sound:Play()
	sound.Ended:Once(function()
		sound:Destroy()
	end)
	-- Notbremse, falls Ended bei einer kaputten Id nie feuert.
	task.delay(12, function()
		if sound.Parent then
			sound:Destroy()
		end
	end)
	return sound
end

--== Dauerklaenge ==========================================================

local ambience: Sound? = nil

local function startAmbience()
	local id = SoundCatalog.Get("World", "Ambience")
	if not id then
		return
	end
	local sound = Instance.new("Sound")
	sound.Name = "Ambience"
	sound.SoundId = id
	sound.Looped = true
	sound.Volume = S.AmbienceVolume
	sound.Parent = holder
	sound:Play()
	ambience = sound
end

local function setAmbienceFactor(factor: number)
	local sound = ambience
	if not sound then
		return
	end
	TweenService:Create(sound, TweenInfo.new(S.AmbienceDuckTime), {
		Volume = S.AmbienceVolume * factor,
	}):Play()
end

local criticalLoop: Sound? = nil

local function setCriticalLoop(on: boolean)
	if on and not criticalLoop then
		local id = SoundCatalog.Get("Trace", "Critical")
		if not id then
			return
		end
		local sound = Instance.new("Sound")
		sound.Name = "TraceCritical"
		sound.SoundId = id
		sound.Looped = true
		sound.Volume = S.UIVolume
		sound.Parent = holder
		sound:Play()
		criticalLoop = sound
	elseif not on and criticalLoop then
		criticalLoop:Destroy()
		criticalLoop = nil
	end
end

--==========================================================================
-- Hack: Melodie und Countdown
--==========================================================================

local hack = {
	Open = false,
	PathLength = 0,
	Deadline = 0,
	NextTick = 0,
}

local function nodePitch(): number
	local steps = math.clamp(hack.PathLength, 0, S.MaxSemitones)
	return S.SemitoneRatio ^ steps
end

Remotes.HackSessionStarted.OnClientEvent:Connect(function(data: any)
	hack.Open = true
	hack.PathLength = 0
	hack.Deadline = if typeof(data) == "table" then (tonumber(data.Deadline) or 0) else 0
	hack.NextTick = 0

	play("UI", "HackStart")
	setAmbienceFactor(S.AmbienceDuckFactor)
end)

Remotes.HackFeedback.OnClientEvent:Connect(function(data: any)
	if typeof(data) ~= "table" then
		return
	end

	if data.Reason == "MASKED_ICE" then
		hack.PathLength = 0 -- die Melodie faengt von vorn an
		play("UI", "IceHit", S.UIVolume * 1.2)
		return
	end

	if data.Ok == true then
		local feedback = data.Feedback
		if typeof(feedback) == "table" and typeof(feedback.Path) == "table" then
			hack.PathLength = math.max(0, #feedback.Path - 1)
		else
			hack.PathLength += 1
		end
		play("UI", "NodeSelect", S.UIVolume, nodePitch())
	else
		play("UI", "NodeInvalid", S.UIVolume * 0.8)
	end
end)

Remotes.HackResolved.OnClientEvent:Connect(function(data: any)
	hack.Open = false
	setAmbienceFactor(1)

	if typeof(data) ~= "table" then
		return
	end
	if data.Success == true then
		play("UI", "HackSuccess", S.UIVolume * 1.1)
	else
		play("UI", "HackFail", S.UIVolume)
	end
end)

--==========================================================================
-- Trace
--==========================================================================

local traceState = "RUHIG"

Remotes.TraceSync.OnClientEvent:Connect(function(data: any)
	if typeof(data) ~= "table" then
		return
	end

	if typeof(data.Bust) == "table" then
		play("Trace", "Bust", S.UIVolume * 1.3)
		setCriticalLoop(false)
		traceState = "RUHIG"
		return
	end

	local value = tonumber(data.Trace) or 0
	local next_ = if value >= Config.Trace.CriticalAt
		then "KRITISCH"
		elseif value >= Config.Trace.WarnAt then "WARNUNG"
		else "RUHIG"

	if next_ ~= traceState then
		if next_ == "WARNUNG" then
			play("Trace", "Warn")
			setCriticalLoop(false)
		elseif next_ == "KRITISCH" then
			setCriticalLoop(true)
		else
			setCriticalLoop(false)
		end
		traceState = next_
	end
end)

--==========================================================================
-- Welt, Markt, Alarm
--==========================================================================

local EFFECT_SOUND: { [string]: string } = {
	CameraOffline = "CameraDown",
	DoorOpen = "DoorOpen",
	AtmPayout = "SafeOpen",
}

Remotes.HackResolved.OnClientEvent:Connect(function(data: any)
	if typeof(data) ~= "table" or data.Success ~= true then
		return
	end
	local key = EFFECT_SOUND[tostring(data.Effect)]
	if key then
		play("World", key, S.WorldVolume)
	end
end)

Remotes.SellResult.OnClientEvent:Connect(function(data: any)
	if typeof(data) == "table" and data.Ok == true then
		play("Market", "Sell", S.WorldVolume)
	end
end)

Remotes.EconomySync.OnClientEvent:Connect(function() end) -- bewusst still

Remotes.MarketEvent.OnClientEvent:Connect(function()
	play("Market", "PriceAlert")
end)

Remotes.InventorySync.OnClientEvent:Connect(function() end) -- bewusst still

local alarmActive = false

Remotes.AlarmSync.OnClientEvent:Connect(function(data: any)
	if typeof(data) ~= "table" then
		return
	end
	if data.Active == true then
		if not alarmActive then
			alarmActive = true
			play("World", "Alarm", S.WorldVolume)
			-- Beim Alarm kommt die Ambience schlagartig laut zurueck.
			setAmbienceFactor(S.AmbienceAlarmFactor)
		end
	else
		alarmActive = false
		setAmbienceFactor(if hack.Open then S.AmbienceDuckFactor else 1)
	end
end)

--==========================================================================
-- Countdown: Frequenz steigt zum Ende hin
--==========================================================================

RunService.RenderStepped:Connect(function()
	if not hack.Open or hack.Deadline <= 0 then
		return
	end

	local remaining = hack.Deadline - workspace:GetServerTimeNow()
	if remaining <= 0 or remaining > S.CountdownFrom then
		return
	end

	local now = os.clock()
	if now < hack.NextTick then
		return
	end

	-- Je weniger Zeit, desto kuerzer der Abstand zwischen den Ticks.
	local fraction = math.clamp(remaining / S.CountdownFrom, 0, 1)
	local interval = S.CountdownMinInterval + (S.CountdownMaxInterval - S.CountdownMinInterval) * fraction
	hack.NextTick = now + interval

	play("UI", "Countdown", S.UIVolume * 0.8, 1 + (1 - fraction) * 0.3)
end)

--==========================================================================

startAmbience()

local filled, total = SoundCatalog.Count()
if filled == 0 then
	warn(("[GHOSTNET] Keine Sound-IDs eingetragen (0 von %d). Das Spiel laeuft, ist aber stumm."):format(total))
else
	print(("[GHOSTNET] SoundController bereit. %d von %d IDs eingetragen."):format(filled, total))
end

local _ = player
