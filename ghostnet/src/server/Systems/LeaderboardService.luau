-- ServerScriptService/Systems/LeaderboardService.luau
--!strict
-- GHOSTNET :: leaderstats und die serveruebergreifenden Top-Listen.
--
-- ZWEI LISTEN, ZWEI VERSCHIEDENE ARTEN, GUT ZU SEIN
--   GUTHABEN     wer am meisten sicher hat. Die naheliegende Liste.
--   RUHIGSTE HAND  wer die laengste Serie erfolgreicher Hacks ohne einen
--                einzigen Fehlversuch hat. Belohnt Praezision statt Zeit -
--                und ist damit auch fuer jemanden erreichbar, der nicht
--                den ganzen Tag spielt.
--
-- KEIN EIGENER DATASTORE
--   Regel 5 gilt: nur der SaveService spricht mit einem DataStore. Dieses
--   Modul benutzt SaveService.PublishScore und SaveService.TopScores.
--
-- KEIN TAKT PRO SPIELER
--   Geschrieben wird beim Verlassen und im Autosave-Rhythmus, gelesen in
--   einem langsamen Intervall fuer alle gemeinsam. Ranglisten sind nichts,
--   was sekundengenau stimmen muss.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local EconomyService = require(script.Parent.EconomyService)
local HackService = require(script.Parent.HackService)
local SaveService = require(script.Parent.SaveService)

local LeaderboardService = {}

local L = Config.Leaderboard

-- Die laufende Serie fehlerfreier Hacks. Reine Sitzungsinformation: eine
-- Serie ueber Serverwechsel hinweg zu fuehren braeuchte ein Profilfeld und
-- damit eine Migration - fuer eine Bestenliste ist das den Preis nicht wert.
-- Der HOECHSTWERT wandert dagegen in die Liste und bleibt dort.
local streak: { [Player]: number } = {}

local cache: { [string]: { { UserId: number, Value: number } } } = {}

--==========================================================================
-- leaderstats
--==========================================================================

local function ensureStats(player: Player)
	local existing = player:FindFirstChild("leaderstats")
	if existing then
		return
	end

	local folder = Instance.new("Folder")
	folder.Name = "leaderstats"

	local banked = Instance.new("IntValue")
	banked.Name = L.BankedLabel
	banked.Value = 0
	banked.Parent = folder

	local tier = Instance.new("IntValue")
	tier.Name = L.TierLabel
	tier.Value = 1
	tier.Parent = folder

	folder.Parent = player
end

local function refreshStats(player: Player)
	local stats = player:FindFirstChild("leaderstats")
	if not stats then
		return
	end
	local profile = SaveService.Get(player)
	if not profile then
		return
	end

	local banked = stats:FindFirstChild(L.BankedLabel)
	if banked and banked:IsA("IntValue") then
		banked.Value = math.floor(profile.Banked)
	end
	local tier = stats:FindFirstChild(L.TierLabel)
	if tier and tier:IsA("IntValue") then
		tier.Value = EconomyService.GetTier(player)
	end
end

--==========================================================================
-- Veroeffentlichen
--==========================================================================

local function publish(player: Player)
	local profile = SaveService.Get(player)
	if not profile then
		return
	end
	SaveService.PublishScore(L.BankedBoard, player.UserId, profile.Banked)

	local best = streak[player] or 0
	if best > 0 then
		SaveService.PublishScore(L.QuietBoard, player.UserId, best)
	end
end

--==========================================================================
-- Lesen und senden
--==========================================================================

local function pull()
	cache[L.BankedBoard] = SaveService.TopScores(L.BankedBoard, L.TopCount)
	cache[L.QuietBoard] = SaveService.TopScores(L.QuietBoard, L.TopCount)
end

-- Namen erst beim Senden nachschlagen, und nur fuer die Top-Eintraege.
-- GetNameFromUserIdAsync ist ein Netzwerkaufruf; hundert davon pro Tick
-- waeren das Ende.
local nameCache: { [number]: string } = {}

local function nameFor(userId: number): string
	local known = nameCache[userId]
	if known then
		return known
	end
	local ok, result = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	local resolved = if ok and typeof(result) == "string" then result else ("Spieler %d"):format(userId)
	nameCache[userId] = resolved
	return resolved
end

local function decorate(entries: { { UserId: number, Value: number } }?): { { [string]: any } }
	local out: { { [string]: any } } = {}
	if not entries then
		return out
	end
	for rank, entry in entries do
		table.insert(out, { Rank = rank, Name = nameFor(entry.UserId), Value = entry.Value })
	end
	return out
end

function LeaderboardService.SyncTo(player: Player)
	if not player.Parent then
		return
	end
	Remotes.LeaderboardSync:FireClient(player, {
		Banked = decorate(cache[L.BankedBoard]),
		Quiet = decorate(cache[L.QuietBoard]),
		BankedLabel = L.BankedLabel,
		QuietLabel = L.QuietLabel,
	})
end

local function broadcast()
	for _, player in Players:GetPlayers() do
		LeaderboardService.SyncTo(player)
	end
end

--==========================================================================

function LeaderboardService.Init()
	SaveService.OnReady(function(player: Player)
		ensureStats(player)
		refreshStats(player)
		streak[player] = 0
		LeaderboardService.SyncTo(player)
	end)

	-- Die ruhigste Hand: jeder Erfolg verlaengert die Serie, jeder
	-- Fehlversuch setzt sie auf null. Genau das macht sie schwer.
	HackService.OnHackResolved(function(player: Player, info: { [string]: any })
		if info.Success == true then
			streak[player] = (streak[player] or 0) + 1
		else
			streak[player] = 0
		end
		refreshStats(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		publish(player)
		streak[player] = nil
	end)

	-- Schreiben im Autosave-Rhythmus, lesen deutlich langsamer. Beides
	-- gestaffelt, damit nicht alle Server gleichzeitig auf denselben
	-- OrderedDataStore einschlagen.
	task.spawn(function()
		while true do
			task.wait(L.PublishInterval)
			for _, player in Players:GetPlayers() do
				refreshStats(player)
				publish(player)
			end
		end
	end)

	task.spawn(function()
		while true do
			local ok, err = pcall(function()
				pull()
				broadcast()
			end)
			if not ok then
				warn(("[GHOSTNET] Rangliste konnte nicht geladen werden: %s"):format(tostring(err)))
			end
			task.wait(L.RefreshInterval)
		end
	end)

	print("[GHOSTNET] LeaderboardService bereit.")
end

return LeaderboardService
