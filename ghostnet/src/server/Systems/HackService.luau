-- ServerScriptService/Systems/HackService.luau
--!strict
-- GHOSTNET :: Das eine Hack-Modul.
--
-- Hier laufen alle Hack-Sessions zusammen. Der Service kennt KEINEN
-- einzelnen Objekttyp - er liest nur Attribute und ruft ein Minispiel auf.
-- Ein neues Ziel in der Welt braucht deshalb keine Zeile Code.
--
-- SERVER-AUTORITAET
--   Der Client schickt ausschliesslich "ich habe X angeklickt". Der Server
--   fuehrt den Raetselzustand, die Uhr, die Versuche, die Distanz und den
--   Cooldown. Kein Remote nimmt jemals ein Ergebnis, eine Zeit oder einen
--   Betrag vom Client entgegen.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Geometry = require(ReplicatedStorage.Shared.Geometry)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Types = require(ReplicatedStorage.Shared.Types)

local EconomyService = require(script.Parent.EconomyService)
local HackEffects = require(script.Parent.HackEffects)
local HackTargets = require(script.Parent.HackTargets)
local RateLimiter = require(script.Parent.RateLimiter)
local SaveService = require(script.Parent.SaveService)
local TraceService = require(script.Parent.TraceService)

type Session = Types.Session

local HackService = {}

-- Minispiel-Register. Phase 3 traegt SignalMatch / CodeCrack hier ein -
-- sonst aendert sich nichts.
local Minigames = {
	NodeBreach = require(script.Parent.Minigames.NodeBreach),
}

local sessions: { [Player]: Session } = {}

-- Wer mitbekommen will, dass ein Hack ausgegangen ist, meldet sich hier an -
-- genau wie bei TraceService.OnBust. Dadurch bleibt die Richtung
-- MissionService -> HackService und kein Modul requiret rueckwaerts.
local resolvedCallbacks: { (Player, { [string]: any }) -> () } = {}

function HackService.OnHackResolved(callback: (Player, { [string]: any }) -> ())
	table.insert(resolvedCallbacks, callback)
end

--==========================================================================
-- Hilfsfunktionen
--==========================================================================

local function now(): number
	return workspace:GetServerTimeNow()
end

local function isTable(v: any): boolean
	return typeof(v) == "table"
end

local function isCleanString(v: any, maxLen: number): boolean
	return typeof(v) == "string" and #v > 0 and #v <= maxLen
end

local function isInteger(v: any): boolean
	return typeof(v) == "number" and v == v and v % 1 == 0 and math.abs(v) < 1e9
end

--==========================================================================
-- Abschluss einer Session
--==========================================================================

-- reason: SOLVED | TIMEOUT | NO_ATTEMPTS | OUT_OF_RANGE | ABORTED | TARGET_GONE | BUSTED
local function resolve(session: Session, success: boolean, reason: string)
	if session.Resolved then
		return
	end
	session.Resolved = true

	local player = session.Player
	if sessions[player] == session then
		sessions[player] = nil
	end

	local target = HackTargets.Get(session.TargetId)
	local reward = 0
	local traceDelta = 0
	local cooldown = 0

	if target then
		-- Trace faellt immer an, nur unterschiedlich stark. Weglaufen oder
		-- abbrechen ist also billiger, aber nie gratis.
		local factor = 1.0
		if not success then
			factor = if reason == "ABORTED" then Config.Trace.AbortFactor else Config.Trace.FailFactor
		end
		local cooling = EconomyService.GetRig(player).Cooling
		traceDelta = Config.GetTraceGain(target.TraceGain * factor, cooling)

		-- Uebungsziel: erzeugt bewusst gar keinen Trace, damit niemand im
		-- Tutorial auffliegt, bevor er weiss, was der Balken bedeutet.
		if target.Part:GetAttribute("NoTrace") == true then
			traceDelta = 0
		end

		-- Co-Op: ein zweiter Spieler in Reichweite eines RequiresTwo-Ziels
		-- halbiert den Trace-Anstieg. Das ist der Grund, einen Freund
		-- mitzubringen - und er muss spuerbar sein.
		if
			target.Part:GetAttribute("RequiresTwo") == true
			and Geometry.HasNearbyOtherPlayer(player, target.Part, Config.Raid.CoopRange)
		then
			traceDelta *= Config.Raid.CoopTraceFactor
		end

		if success then
			reward = target.Reward
			cooldown = target.Cooldown
			EconomyService.AwardUnsold(player, reward)
			HackTargets.SetCooldown(player, target.Id, cooldown)
			HackTargets.MarkDown(target, target.DownTime)
			HackEffects.Apply(target, player)
		else
			cooldown = Config.Cooldown.AfterFail
			HackTargets.SetCooldown(player, target.Id, cooldown)
		end

		EconomyService.CountHack(player, success)
	end

	-- Erst gutschreiben, dann den Trace anwenden: wer sich mit dem letzten
	-- Hack in den Bust treibt, verliert genau diese Beute auch wieder. Das
	-- ist der Moment, um den es geht.
	if traceDelta > 0 then
		TraceService.Add(player, traceDelta)
	end

	if player.Parent then
		Remotes.HackResolved:FireClient(player, {
			SessionId = session.Id,
			Success = success,
			Reason = reason,
			Reward = reward,
			TraceDelta = traceDelta,
			Cooldown = cooldown,
			TargetId = session.TargetId,
			Effect = target and target.OnSuccess or "",
		})
	end

	if target then
		SaveService.RequestSave(player)
	end

	for _, callback in resolvedCallbacks do
		task.spawn(function()
			local ok, err = pcall(callback, player, {
				TargetId = session.TargetId,
				Success = success,
				Reason = reason,
				Reward = reward,
				Difficulty = session.Difficulty,
				HackType = session.HackType,
			})
			if not ok then
				warn(("[GHOSTNET] OnHackResolved-Callback fehlgeschlagen: %s"):format(tostring(err)))
			end
		end)
	end
end

function HackService.AbortFor(player: Player, reason: string)
	local session = sessions[player]
	if session then
		resolve(session, false, reason)
	end
end

--==========================================================================
-- Start
--==========================================================================

-- Sagt dem Spieler, WARUM ein Start nicht geklappt hat. Ohne das klickt man
-- im Spiel ins Leere und haelt es fuer einen Bug.
local function deny(player: Player, targetId: string, reason: string, seconds: number?)
	if player.Parent then
		Remotes.HackDenied:FireClient(player, {
			TargetId = targetId,
			Reason = reason,
			Seconds = seconds or 0,
		})
	end
end

local function onRequestStart(player: Player, payload: any)
	if not RateLimiter.Check(player, "HackRequestStart") then
		return
	end
	if not isTable(payload) then
		return
	end

	local targetId = (payload :: any).TargetId
	if not isCleanString(targetId, 32) then
		return
	end

	if sessions[player] then
		return -- laeuft schon eine Session
	end

	-- Ohne geladenes Profil gibt es keinen Cooldown und kein Rig - dann wird
	-- gar nicht erst gestartet, statt mit Startwerten zu spielen.
	if not SaveService.IsReady(player) then
		deny(player, targetId, "LOADING")
		return
	end

	-- Nach einem Bust ist erstmal Ruhe.
	local lockLeft = TraceService.LockSecondsLeft(player)
	if lockLeft > 0 then
		deny(player, targetId, "BUSTED", math.ceil(lockLeft))
		return
	end

	local target = HackTargets.Get(targetId)
	if not target or not target.Part.Parent then
		deny(player, targetId, "UNKNOWN_TARGET")
		return
	end

	if HackTargets.IsDown(target) then
		deny(player, target.Id, "OFFLINE")
		return
	end

	local cooldownLeft = HackTargets.CooldownLeft(player, target.Id)
	if cooldownLeft > 0 then
		deny(player, target.Id, "COOLDOWN", math.ceil(cooldownLeft))
		return
	end

	if EconomyService.GetTier(player) < target.RequiredLevel then
		deny(player, target.Id, "LEVEL", target.RequiredLevel)
		return
	end

	local minigame = (Minigames :: any)[target.HackType]
	if not minigame then
		warn(("[GHOSTNET] %s verlangt HackType '%s', den es nicht gibt."):format(
			target.Part:GetFullName(),
			target.HackType
		))
		deny(player, target.Id, "INTERNAL")
		return
	end

	-- Distanz IMMER serverseitig. Der Client bekommt hier kein Wort.
	local range = EconomyService.GetRange(player) + Config.Range.Tolerance
	local distance = HackTargets.DistanceFromPlayer(target, player)
	if not distance or distance > range then
		deny(player, target.Id, "RANGE")
		return
	end

	local rig = EconomyService.GetRig(player)
	local timeLimit = Config.GetTimeLimit(rig.CPU, target.Difficulty)
	local attempts = Config.GetAttempts(rig.RAM)

	local rng = Random.new()
	local public, state = minigame.Generate(target.Difficulty, rng)

	local session: Session = {
		Id = HttpService:GenerateGUID(false),
		Player = player,
		TargetId = target.Id,
		HackType = target.HackType,
		Difficulty = target.Difficulty,
		Range = range,
		ExpectedStep = 1,
		AttemptsLeft = attempts,
		Deadline = now() + timeLimit,
		StartedAt = now(),
		State = state,
		Resolved = false,
	}
	sessions[player] = session

	Remotes.HackSessionStarted:FireClient(player, {
		SessionId = session.Id,
		HackType = session.HackType,
		Label = minigame.Label(),
		Public = public,
		Deadline = session.Deadline,
		TimeLimit = timeLimit,
		Attempts = attempts,
		-- Attribut "Teaches" am Part: die HackUI erklaert das Raetsel dann
		-- im Spiel. Haengt bewusst am Objekt und nicht am Missionsfortschritt,
		-- damit der HackService den MissionService nicht kennen muss.
		Tutorial = target.Part:GetAttribute("Teaches") == true,
		Target = {
			Id = target.Id,
			Name = target.DisplayName,
			Difficulty = target.Difficulty,
			Reward = target.Reward,
		},
	})
end

--==========================================================================
-- Eingabe
--==========================================================================

local function onInput(player: Player, payload: any)
	if not RateLimiter.Check(player, "HackInput") then
		return
	end
	if not isTable(payload) then
		return
	end

	local session = sessions[player]
	if not session or session.Resolved then
		return
	end

	local p = payload :: any
	if not isCleanString(p.SessionId, 64) or p.SessionId ~= session.Id then
		return
	end
	if not isInteger(p.Step) or p.Step ~= session.ExpectedStep then
		return -- Wiederholung oder Luecke: verwerfen
	end
	if not isTable(p.Payload) then
		return
	end

	if now() > session.Deadline then
		resolve(session, false, "TIMEOUT")
		return
	end

	local target = HackTargets.Get(session.TargetId)
	if not target or not target.Part.Parent then
		resolve(session, false, "TARGET_GONE")
		return
	end

	local distance = HackTargets.DistanceFromPlayer(target, player)
	if not distance or distance > session.Range then
		resolve(session, false, "OUT_OF_RANGE")
		return
	end

	local minigame = (Minigames :: any)[session.HackType]
	local ok, result = pcall(minigame.Input, session.State, p.Payload)
	if not ok then
		warn(("[GHOSTNET] Minispiel '%s' ist abgestuerzt: %s"):format(session.HackType, tostring(result)))
		resolve(session, false, "ABORTED")
		return
	end

	-- Jede verarbeitete Eingabe zaehlt hoch, auch eine ungueltige.
	-- Damit kann derselbe Step nie zweimal wirken.
	session.ExpectedStep += 1

	if result.CostsAttempt then
		session.AttemptsLeft -= 1
	end

	Remotes.HackFeedback:FireClient(player, {
		SessionId = session.Id,
		Step = p.Step,
		Ok = result.Ok,
		Reason = result.Reason,
		AttemptsLeft = session.AttemptsLeft,
		Feedback = result.Feedback,
	})

	if result.Solved then
		resolve(session, true, "SOLVED")
	elseif session.AttemptsLeft <= 0 then
		resolve(session, false, "NO_ATTEMPTS")
	end
end

--==========================================================================
-- Abbruch durch den Spieler
--==========================================================================

local function onAbort(player: Player, payload: any)
	if not RateLimiter.Check(player, "HackAbort") then
		return
	end
	if not isTable(payload) then
		return
	end
	local session = sessions[player]
	if not session then
		return
	end
	if (payload :: any).SessionId ~= session.Id then
		return
	end
	resolve(session, false, "ABORTED")
end

--==========================================================================
-- Wachhund: Zeit und Distanz, unabhaengig davon, ob der Client etwas sendet
--==========================================================================

local function watchdog()
	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator < Config.Session.TickRate then
			return
		end
		accumulator = 0

		local t = now()
		for player, session in sessions do
			if session.Resolved then
				continue
			end

			if not player.Parent then
				session.Resolved = true
				sessions[player] = nil
				continue
			end

			if t > session.Deadline then
				resolve(session, false, "TIMEOUT")
				continue
			end

			if t - session.StartedAt < Config.Session.GraceAfterStart then
				continue
			end

			local target = HackTargets.Get(session.TargetId)
			if not target or not target.Part.Parent then
				resolve(session, false, "TARGET_GONE")
				continue
			end

			local distance = HackTargets.DistanceFromPlayer(target, player)
			if not distance or distance > session.Range then
				resolve(session, false, "OUT_OF_RANGE")
			end
		end
	end)
end

--==========================================================================

function HackService.Init()
	Remotes.HackRequestStart.OnServerEvent:Connect(onRequestStart)
	Remotes.HackInput.OnServerEvent:Connect(onInput)
	Remotes.HackAbort.OnServerEvent:Connect(onAbort)

	-- Beim Bust fliegt eine laufende Session sofort raus. Die Anmeldung laeuft
	-- ueber den Callback, damit der TraceService den HackService nicht kennen
	-- muss (sonst haetten wir einen Require-Kreis).
	TraceService.OnBust(function(player: Player)
		HackService.AbortFor(player, "BUSTED")
	end)

	Players.PlayerRemoving:Connect(function(player)
		local session = sessions[player]
		if session then
			session.Resolved = true
			sessions[player] = nil
		end
	end)

	watchdog()

	local types = {}
	for name in Minigames do
		table.insert(types, name)
	end
	print(("[GHOSTNET] HackService bereit. Minispiele: %s"):format(table.concat(types, ", ")))
end

return HackService
