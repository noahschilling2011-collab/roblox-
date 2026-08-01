-- ServerScriptService/Systems/AdminService.luau
--!strict
-- GHOSTNET :: Admin-Befehle.
--
-- SICHERHEIT ZUERST - das ist kein Nebensatz
--   Ein schlecht gebautes Admin-Panel ist der haeufigste Weg, auf dem
--   Roblox-Spiele zerstoert werden. Der Client kann JEDES RemoteEvent
--   feuern, das er sieht. Ein Admin-Remote, das dem Client glaubt, ist ein
--   Gratis-Geldautomat.
--
--   Deshalb gilt hier:
--   1. Die UserId-Liste liegt in ServerScriptService, nie in ReplicatedStorage.
--   2. JEDER Befehl prueft die Autorisierung in der ersten Zeile. Dass der
--      Knopf nur Admins angezeigt wird, ist voellig irrelevant.
--   3. Die gefaehrlichsten Befehle brauchen zusaetzlich IsStudio().
--   4. Jede Aktion wird geloggt: wer, was, wann, an wem.
--   5. Eigener Rate-Limit-Eintrag.

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Goods = require(ReplicatedStorage.Shared.Goods)
local Missions = require(ReplicatedStorage.Shared.Missions)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local AdminList = require(script.Parent.Parent.AdminList)

local EconomyService = require(script.Parent.EconomyService)
local HackService = require(script.Parent.HackService)
local HackTargets = require(script.Parent.HackTargets)
local MarketService = require(script.Parent.MarketService)
local MissionService = require(script.Parent.MissionService)
local RateLimiter = require(script.Parent.RateLimiter)
local SaveService = require(script.Parent.SaveService)
local TraceService = require(script.Parent.TraceService)

local AdminService = {}

--==========================================================================
-- Hilfsfunktionen
--==========================================================================

local function reply(ok: boolean, text: string, extra: { [string]: any }?): { [string]: any }
	local payload: { [string]: any } = { Ok = ok, Text = text }
	if extra then
		for key, value in extra do
			payload[key] = value
		end
	end
	return payload
end

local function audit(admin: Player, command: string, detail: string)
	warn(("[GHOSTNET][ADMIN] %s (%d) -> %s  %s"):format(admin.Name, admin.UserId, command, detail))
end

-- Zielspieler eines Befehls. Ohne Angabe der Admin selbst.
local function resolveTarget(admin: Player, name: any): Player?
	if typeof(name) ~= "string" or name == "" then
		return admin
	end
	for _, player in Players:GetPlayers() do
		if player.Name == name then
			return player
		end
	end
	return nil
end

local function clampNumber(value: any, low: number, high: number): number?
	if typeof(value) ~= "number" or value ~= value then
		return nil
	end
	return math.clamp(math.floor(value), low, high)
end

--==========================================================================
-- Befehle
--
-- studioOnly = true  ->  greift live nicht, auch nicht fuer echte Admins.
--==========================================================================

type Command = {
	StudioOnly: boolean,
	Run: (admin: Player, payload: { [string]: any }) -> { [string]: any },
}

local COMMANDS: { [string]: Command } = {}

--== Wirtschaft ============================================================

COMMANDS.SetCrypto = {
	StudioOnly = true,
	Run = function(admin, payload)
		local target = resolveTarget(admin, payload.Player)
		if not target then
			return reply(false, "Spieler nicht gefunden")
		end
		local profile = SaveService.Get(target)
		if not profile then
			return reply(false, "Profil nicht geladen")
		end

		local banked = clampNumber(payload.Banked, 0, 1e9)
		local unsold = clampNumber(payload.Unsold, 0, 1e9)
		if banked then
			profile.Banked = banked
		end
		if unsold then
			profile.Unsold = unsold
		end

		EconomyService.Sync(target)
		SaveService.RequestSave(target)
		audit(admin, "SetCrypto", ("%s bank=%s unsold=%s"):format(target.Name, tostring(banked), tostring(unsold)))
		return reply(true, ("%s: Bank %d, Unverkauft %d"):format(target.Name, profile.Banked, profile.Unsold))
	end,
}

COMMANDS.SetRig = {
	StudioOnly = true,
	Run = function(admin, payload)
		local target = resolveTarget(admin, payload.Player)
		if not target then
			return reply(false, "Spieler nicht gefunden")
		end
		local level = clampNumber(payload.Level, 1, Config.Rig.MaxLevel)
		if not level then
			return reply(false, "Level fehlt")
		end

		local component = payload.Component
		local applied = {}
		for _, name in Config.Rig.Components do
			if component == nil or component == name then
				EconomyService.SetRigLevel(target, name, level)
				table.insert(applied, name)
			end
		end
		if #applied == 0 then
			return reply(false, "Unbekanntes Bauteil")
		end

		EconomyService.Sync(target)
		SaveService.RequestSave(target)
		audit(admin, "SetRig", ("%s %s = %d"):format(target.Name, table.concat(applied, ","), level))
		return reply(true, ("%s: %s auf Stufe %d"):format(target.Name, table.concat(applied, ", "), level))
	end,
}

COMMANDS.SetTrace = {
	StudioOnly = true,
	Run = function(admin, payload)
		local target = resolveTarget(admin, payload.Player)
		if not target then
			return reply(false, "Spieler nicht gefunden")
		end
		local profile = SaveService.Get(target)
		if not profile then
			return reply(false, "Profil nicht geladen")
		end
		local value = clampNumber(payload.Value, 0, Config.Trace.Max)
		if not value then
			return reply(false, "Wert fehlt")
		end

		-- Ueber den Service, damit ein Wert von 100 auch wirklich einen Bust
		-- ausloest statt nur die Zahl zu setzen.
		profile.Trace = 0
		TraceService.Add(target, value)
		audit(admin, "SetTrace", ("%s = %d"):format(target.Name, value))
		return reply(true, ("%s: Trace auf %d"):format(target.Name, value))
	end,
}

COMMANDS.Bust = {
	StudioOnly = true,
	Run = function(admin, payload)
		local target = resolveTarget(admin, payload.Player)
		if not target then
			return reply(false, "Spieler nicht gefunden")
		end
		local profile = SaveService.Get(target)
		if not profile then
			return reply(false, "Profil nicht geladen")
		end
		profile.Trace = 0
		TraceService.Add(target, Config.Trace.Max)
		audit(admin, "Bust", target.Name)
		return reply(true, ("%s wurde gebustet"):format(target.Name))
	end,
}

--== Missionen =============================================================

COMMANDS.SetMission = {
	StudioOnly = true,
	Run = function(admin, payload)
		local target = resolveTarget(admin, payload.Player)
		if not target then
			return reply(false, "Spieler nicht gefunden")
		end
		local profile = SaveService.Get(target)
		if not profile then
			return reply(false, "Profil nicht geladen")
		end

		local missionId = payload.MissionId
		if typeof(missionId) ~= "string" or not Missions.Get(missionId) then
			return reply(false, "Unbekannte Mission")
		end

		-- Alle Vorgaenger als erledigt eintragen, sonst waere die Mission
		-- gar nicht verfuegbar.
		local story = profile.Story
		for _, mission in Missions.List do
			if mission.Id == missionId then
				break
			end
			if not Missions.IsCompleted(story, mission.Id) then
				table.insert(story.Completed, mission.Id)
			end
			local unlock = mission.Reward and mission.Reward.Unlock
			if typeof(unlock) == "string" and unlock ~= "" and not Missions.HasUnlock(story, unlock) then
				table.insert(story.Unlocks, unlock)
			end
		end

		local index = table.find(story.Completed, missionId)
		if index then
			table.remove(story.Completed, index)
		end
		story.Active = missionId
		story.Step = 1
		story.StepProgress = 0
		story.StepStartedAt = os.time()

		SaveService.RequestSave(target)
		MissionService.Sync(target)
		audit(admin, "SetMission", ("%s -> %s"):format(target.Name, missionId))
		return reply(true, ("%s startet %s"):format(target.Name, missionId))
	end,
}

COMMANDS.ResetStory = {
	StudioOnly = true,
	Run = function(admin, payload)
		local target = resolveTarget(admin, payload.Player)
		if not target then
			return reply(false, "Spieler nicht gefunden")
		end
		local profile = SaveService.Get(target)
		if not profile then
			return reply(false, "Profil nicht geladen")
		end

		profile.Story.Active = ""
		profile.Story.Step = 1
		profile.Story.StepProgress = 0
		profile.Story.StepStartedAt = 0
		table.clear(profile.Story.Completed)
		table.clear(profile.Story.Unlocks)

		SaveService.RequestSave(target)
		MissionService.Sync(target)
		audit(admin, "ResetStory", target.Name)
		return reply(true, ("Story von %s zurueckgesetzt"):format(target.Name))
	end,
}

COMMANDS.GrantUnlock = {
	StudioOnly = true,
	Run = function(admin, payload)
		local target = resolveTarget(admin, payload.Player)
		if not target then
			return reply(false, "Spieler nicht gefunden")
		end
		local profile = SaveService.Get(target)
		if not profile then
			return reply(false, "Profil nicht geladen")
		end
		local key = payload.Unlock
		if typeof(key) ~= "string" or key == "" or #key > 48 then
			return reply(false, "Unlock fehlt")
		end
		if not Missions.HasUnlock(profile.Story, key) then
			table.insert(profile.Story.Unlocks, key)
		end
		SaveService.RequestSave(target)
		MissionService.Sync(target)
		audit(admin, "GrantUnlock", ("%s -> %s"):format(target.Name, key))
		return reply(true, ("%s hat jetzt %s"):format(target.Name, key))
	end,
}

--== Welt ==================================================================

COMMANDS.ListTargets = {
	StudioOnly = false,
	Run = function(admin, _payload)
		local rows: { { [string]: any } } = {}
		for id, target in HackTargets.All() do
			table.insert(rows, {
				Id = id,
				Name = target.DisplayName,
				Difficulty = target.Difficulty,
				RequiredLevel = target.RequiredLevel,
				Offline = HackTargets.IsDown(target),
				Cooldown = math.ceil(HackTargets.CooldownLeft(admin, id)),
				Position = target.Part.Position,
			})
		end
		table.sort(rows, function(a, b)
			return (a.Id :: string) < (b.Id :: string)
		end)
		return reply(true, ("%d Ziele"):format(#rows), { Targets = rows })
	end,
}

COMMANDS.ClearCooldown = {
	StudioOnly = false,
	Run = function(admin, payload)
		local target = resolveTarget(admin, payload.Player)
		if not target then
			return reply(false, "Spieler nicht gefunden")
		end
		local profile = SaveService.Get(target)
		if not profile then
			return reply(false, "Profil nicht geladen")
		end

		local targetId = payload.TargetId
		if typeof(targetId) == "string" and targetId ~= "" then
			profile.Cooldowns[targetId] = nil
			audit(admin, "ClearCooldown", ("%s / %s"):format(target.Name, targetId))
		else
			table.clear(profile.Cooldowns)
			audit(admin, "ClearCooldown", ("%s / alle"):format(target.Name))
		end

		EconomyService.Sync(target)
		SaveService.RequestSave(target)
		return reply(true, "Cooldowns geloescht")
	end,
}

COMMANDS.Teleport = {
	StudioOnly = false,
	Run = function(admin, payload)
		local targetId = payload.TargetId
		if typeof(targetId) ~= "string" then
			return reply(false, "TargetId fehlt")
		end
		local target = HackTargets.Get(targetId)
		if not target then
			return reply(false, "Ziel nicht gefunden")
		end
		local character = admin.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not root or not root:IsA("BasePart") then
			return reply(false, "Kein Character")
		end

		root.CFrame = CFrame.new(target.Part.Position + Vector3.new(0, 4, 8))
		audit(admin, "Teleport", targetId)
		return reply(true, ("Bei %s"):format(target.DisplayName))
	end,
}

--== Markt =================================================================

COMMANDS.MarketState = {
	StudioOnly = false,
	Run = function(_admin, _payload)
		local rows: { { [string]: any } } = {}
		for _, good in Goods.List do
			table.insert(rows, {
				Id = good.Id,
				Name = good.Name,
				Factor = MarketService.GetFactor(good.Id),
				Buy = MarketService.GetBuyPrice(good.Id),
				Sell = MarketService.GetSellPrice(good.Id),
			})
		end
		return reply(true, ("%d Waren"):format(#rows), { Market = rows })
	end,
}

COMMANDS.MarketEvent = {
	StudioOnly = true,
	Run = function(admin, payload)
		local group = payload.Group
		if typeof(group) ~= "string" or group == "" then
			return reply(false, "Group fehlt")
		end
		local strength = payload.Strength
		if typeof(strength) ~= "number" or strength ~= strength then
			strength = Config.Market.EventStrengthMax
		end
		MarketService.ForceEvent(group, math.clamp(strength, -0.9, 0.9))
		audit(admin, "MarketEvent", ("%s %.2f"):format(group, strength))
		return reply(true, ("Event auf %s ausgeloest"):format(group))
	end,
}

COMMANDS.SetPrice = {
	StudioOnly = true,
	Run = function(admin, payload)
		local goodId = payload.GoodId
		if not Goods.Exists(goodId) then
			return reply(false, "Unbekannte Ware")
		end
		local factor = payload.Factor
		if typeof(factor) ~= "number" or factor ~= factor then
			return reply(false, "Factor fehlt")
		end
		MarketService.SetFactor(goodId, factor)
		audit(admin, "SetPrice", ("%s = %.2f"):format(goodId, factor))
		return reply(true, ("%s auf Faktor %.2f"):format(goodId, factor))
	end,
}

--== Debug =================================================================

COMMANDS.Sessions = {
	StudioOnly = false,
	Run = function(_admin, _payload)
		local rows: { { [string]: any } } = {}
		for _, player in Players:GetPlayers() do
			table.insert(rows, {
				Name = player.Name,
				Ready = SaveService.IsReady(player),
				MemoryOnly = SaveService.IsMemoryOnly(player),
				Hacking = HackService.IsHacking(player),
				Trace = math.floor(TraceService.Get(player)),
				Tier = EconomyService.GetTier(player),
				Banked = EconomyService.GetBanked(player),
				Unsold = EconomyService.GetUnsold(player),
			})
		end
		return reply(true, ("%d Spieler"):format(#rows), { Sessions = rows })
	end,
}

-- Der wichtigste Befehl im ganzen Panel: ohne "Profil ausgeben" debuggt man
-- Speicherfehler blind.
COMMANDS.DumpProfile = {
	StudioOnly = false,
	Run = function(admin, payload)
		local target = resolveTarget(admin, payload.Player)
		if not target then
			return reply(false, "Spieler nicht gefunden")
		end
		local profile = SaveService.Get(target)
		if not profile then
			return reply(false, "Profil nicht geladen")
		end

		local ok, json = pcall(function()
			return HttpService:JSONEncode(profile)
		end)
		if not ok then
			return reply(false, "Profil laesst sich nicht als JSON schreiben")
		end

		-- Auch in die Server-Ausgabe, damit man es kopieren kann.
		print(("[GHOSTNET][ADMIN] Profil %s:\n%s"):format(target.Name, json))
		audit(admin, "DumpProfile", target.Name)
		return reply(true, ("Profil von %s"):format(target.Name), { Json = json })
	end,
}

COMMANDS.ForceSave = {
	StudioOnly = false,
	Run = function(admin, payload)
		local target = resolveTarget(admin, payload.Player)
		if not target then
			return reply(false, "Spieler nicht gefunden")
		end
		local saved = SaveService.SaveNow(target)
		audit(admin, "ForceSave", ("%s ok=%s"):format(target.Name, tostring(saved)))
		return reply(saved, if saved then "Gespeichert" else "Speichern fehlgeschlagen (siehe Ausgabe)")
	end,
}

--==========================================================================
-- Eingang
--==========================================================================

local function handle(player: Player, payload: any): { [string]: any }
	-- ERSTE ZEILE: Autorisierung. Nicht die zweite, nicht nach dem
	-- Typcheck - die erste.
	if not AdminList.IsAdmin(player) then
		warn(("[GHOSTNET][ADMIN] ABGELEHNT: %s (%d) hat einen Admin-Befehl versucht."):format(
			player.Name,
			player.UserId
		))
		return reply(false, "Nicht autorisiert")
	end

	if not RateLimiter.Check(player, "AdminCommand") then
		return reply(false, "Zu schnell")
	end
	if typeof(payload) ~= "table" then
		return reply(false, "Ungueltige Anfrage")
	end

	local name = (payload :: any).Command
	if typeof(name) ~= "string" then
		return reply(false, "Kein Befehl")
	end

	local command = COMMANDS[name]
	if not command then
		return reply(false, ("Unbekannter Befehl: %s"):format(name))
	end

	if command.StudioOnly and not AdminList.IsStudioOnlyAllowed() then
		warn(("[GHOSTNET][ADMIN] '%s' ist nur im Studio erlaubt - %s abgelehnt."):format(name, player.Name))
		return reply(false, "Dieser Befehl existiert im Live-Spiel nicht")
	end

	local ok, response = pcall(command.Run, player, payload)
	if not ok then
		warn(("[GHOSTNET][ADMIN] Befehl '%s' ist abgestuerzt: %s"):format(name, tostring(response)))
		return reply(false, "Befehl fehlgeschlagen")
	end
	return response
end

--==========================================================================

function AdminService.Init()
	Remotes.AdminCommand.OnServerInvoke = function(player: Player, payload: any): { [string]: any }
		local ok, response = pcall(handle, player, payload)
		if not ok then
			warn(("[GHOSTNET][ADMIN] Eingang abgestuerzt: %s"):format(tostring(response)))
			return reply(false, "Fehler")
		end
		return response
	end

	-- Der Client fragt beim Join, ob er das Panel ueberhaupt zeigen darf.
	-- Die Antwort ist reine Bequemlichkeit; jeder Befehl prueft nochmal.
	Players.PlayerAdded:Connect(function(player)
		task.defer(function()
			if AdminList.IsAdmin(player) and player.Parent then
				Remotes.AdminReady:FireClient(player, { Studio = AdminList.IsStudioOnlyAllowed() })
			end
		end)
	end)
	for _, player in Players:GetPlayers() do
		if AdminList.IsAdmin(player) then
			Remotes.AdminReady:FireClient(player, { Studio = AdminList.IsStudioOnlyAllowed() })
		end
	end

	print(("[GHOSTNET] AdminService bereit. %d eingetragene Admins%s."):format(
		AdminList.Count(),
		if AdminList.IsStudioOnlyAllowed() then " (+ Studio)" else ""
	))
end

return AdminService
