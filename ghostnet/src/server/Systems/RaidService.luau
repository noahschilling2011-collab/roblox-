-- ServerScriptService/Systems/RaidService.luau
--!strict
-- GHOSTNET :: Mehrstufige Ziele mit Alarm-Uhr.
--
-- DAS PROBLEM, DAS ES LOEST
--   Ein einzelner Hack ist eine ruhige Denkaufgabe. Ein Ueberfall soll sich
--   anders anfuehlen: Sobald das erste Schloss faellt, laeuft eine Uhr. Das
--   ist die erste Situation im Spiel, in der man wirklich schwitzt.
--
-- WIE MAN EINEN UEBERFALL BAUT - ohne eine Zeile Code
--   Attribute an den Hack-Zielen:
--     AlarmGroup  = "STORE"   beide Ziele gehoeren zusammen
--     AlarmStarts = true      an dem Ziel, das die Uhr startet
--     AlarmEnds   = true      an dem Ziel, das sie stoppt
--     FailBusts   = true      ein Fehlschlag hier ist sofort ein Bust
--     RequiresTwo = true      zu zweit laeuft die Uhr halb so schnell
--
-- Die Uhr laeuft PRO SPIELER, nicht pro Gebaeude. Sonst wuerde ein zweiter
-- Spieler den Alarm des ersten erben, und Co-Op wuerde bestrafen statt helfen.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Geometry = require(ReplicatedStorage.Shared.Geometry)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local HackService = require(script.Parent.HackService)
local PursuitService = require(script.Parent.PursuitService)
local HackTargets = require(script.Parent.HackTargets)
local TraceService = require(script.Parent.TraceService)

local RaidService = {}

type Alarm = {
	Group: string,
	Label: string,
	Remaining: number, -- Sekunden, laeuft rueckwaerts
	Total: number,
	Coop: boolean,
	TargetId: string, -- Ziel, das die Uhr stoppt (fuer den Marker)
}

local alarms: { [Player]: Alarm } = {}
local lastSyncAt: { [Player]: number } = {}

--==========================================================================
-- Anzeige
--==========================================================================

local function syncAlarm(player: Player, force: boolean?)
	if not player.Parent then
		return
	end
	local now = os.clock()
	if not force and now - (lastSyncAt[player] or 0) < Config.Raid.AlarmSyncInterval then
		return
	end
	lastSyncAt[player] = now

	local alarm = alarms[player]
	if not alarm then
		Remotes.AlarmSync:FireClient(player, { Active = false })
		return
	end

	Remotes.AlarmSync:FireClient(player, {
		Active = true,
		Label = alarm.Label,
		Remaining = alarm.Remaining,
		Total = alarm.Total,
		WarnAt = Config.Raid.AlarmWarnAt,
		Coop = alarm.Coop,
	})
end

--==========================================================================
-- Co-Op
--==========================================================================

-- Steht ein zweiter Spieler nah genug an einem Ziel mit RequiresTwo?
-- Das ist der einzige Grund im ganzen Spiel, einen Freund mitzubringen -
-- deshalb muss es spuerbar sein und nicht nur ein Prozentpunkt.
function RaidService.HasPartner(player: Player, part: BasePart): boolean
	if part:GetAttribute("RequiresTwo") ~= true then
		return false
	end
	return Geometry.HasNearbyOtherPlayer(player, part, Config.Raid.CoopRange)
end

--==========================================================================
-- Uhr starten und stoppen
--==========================================================================

local function findEndTarget(group: string): string
	for id, target in HackTargets.All() do
		if target.Part:GetAttribute("AlarmGroup") == group and target.Part:GetAttribute("AlarmEnds") == true then
			return id
		end
	end
	return ""
end

local function startAlarm(player: Player, group: string, label: string)
	alarms[player] = {
		Group = group,
		Label = label,
		Remaining = Config.Raid.AlarmSeconds,
		Total = Config.Raid.AlarmSeconds,
		Coop = false,
		TargetId = findEndTarget(group),
	}
	warn(("[GHOSTNET] Alarm '%s' laeuft fuer %s (%d s)."):format(group, player.Name, Config.Raid.AlarmSeconds))
	syncAlarm(player, true)
end

local function stopAlarm(player: Player, reason: string)
	local alarm = alarms[player]
	if not alarm then
		return
	end
	alarms[player] = nil
	print(("[GHOSTNET] Alarm '%s' fuer %s beendet: %s"):format(alarm.Group, player.Name, reason))
	syncAlarm(player, true)
end

-- Die Uhr ist durchgelaufen. Kein Bust, aber ein Trace-Sprung, den man merkt.
local function triggerAlarm(player: Player)
	local alarm = alarms[player]
	if not alarm then
		return
	end
	alarms[player] = nil

	warn(("[GHOSTNET] ALARM ausgeloest: %s in Gruppe '%s'."):format(player.Name, alarm.Group))
	HackService.AbortFor(player, "ALARM")
	TraceService.Add(player, Config.Raid.AlarmTracePenalty)
	-- Ein durchgelaufener Alarm ruft die Polizei. Genau dafuer ist die
	-- Fahndungsstufe da.
	PursuitService.AddHeat(player, 2)

	if player.Parent then
		Remotes.AlarmSync:FireClient(player, {
			Active = false,
			Triggered = true,
			Label = alarm.Label,
			TracePenalty = Config.Raid.AlarmTracePenalty,
		})
	end
end

-- Von aussen ausgeloester Alarm (Wache hat jemanden gesehen). Startet
-- dieselbe Uhr wie ein geknacktes Ziel - kein zweites Alarm-System daneben.
function RaidService.RaiseAlarm(player: Player, group: string, label: string)
	if alarms[player] then
		return
	end
	startAlarm(player, group, label)
end

function RaidService.IsAlarmed(player: Player): boolean
	return alarms[player] ~= nil
end

function RaidService.AlarmSecondsLeft(player: Player): number
	local alarm = alarms[player]
	return if alarm then math.max(0, alarm.Remaining) else 0
end

--==========================================================================
-- Reaktion auf Hacks
--==========================================================================

local function onHackResolved(player: Player, data: { [string]: any })
	local target = HackTargets.Get(data.TargetId)
	if not target then
		return
	end
	local part = target.Part
	local group = part:GetAttribute("AlarmGroup")

	if data.Success ~= true then
		-- Fehlschlag an einem Ziel mit FailBusts: sofort auffliegen, nicht
		-- nur ein normaler Fehlversuch. Genau das macht die Bank teuer.
		if part:GetAttribute("FailBusts") == true then
			warn(("[GHOSTNET] %s ist an einem FailBusts-Ziel gescheitert - sofortiger Bust."):format(player.Name))
			if typeof(group) == "string" then
				stopAlarm(player, "Fehlschlag")
			end
			TraceService.Add(player, Config.Raid.FailBustTrace)
		end
		return
	end

	if typeof(group) ~= "string" or group == "" then
		return
	end

	if part:GetAttribute("AlarmEnds") == true then
		local alarm = alarms[player]
		if alarm and alarm.Group == group then
			stopAlarm(player, "Ziel erreicht")
		end
		return
	end

	if part:GetAttribute("AlarmStarts") == true and not alarms[player] then
		startAlarm(player, group, target.DisplayName)
	end
end

--==========================================================================
-- Takt
--==========================================================================

local function tick()
	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator < 0.25 then
			return
		end
		local step = accumulator
		accumulator = 0

		for player, alarm in alarms do
			if not player.Parent then
				alarms[player] = nil
				continue
			end

			-- Partner in der Naehe des Zielobjekts bremst die Uhr.
			local coop = false
			local endTarget = HackTargets.Get(alarm.TargetId)
			if endTarget then
				coop = RaidService.HasPartner(player, endTarget.Part)
			end
			alarm.Coop = coop

			alarm.Remaining -= step * (if coop then Config.Raid.CoopAlarmFactor else 1)

			if alarm.Remaining <= 0 then
				triggerAlarm(player)
			else
				syncAlarm(player, false)
			end
		end
	end)
end

--==========================================================================

function RaidService.Init()
	HackService.OnHackResolved(onHackResolved)

	Players.PlayerRemoving:Connect(function(player)
		alarms[player] = nil
		lastSyncAt[player] = nil
	end)

	tick()

	print(("[GHOSTNET] RaidService bereit. Alarm %d s, Strafe +%d Trace."):format(
		Config.Raid.AlarmSeconds,
		Config.Raid.AlarmTracePenalty
	))
end

return RaidService
