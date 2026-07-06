--!strict
-- LeaderboardService: Ranglisten für Planet Forge.
--
-- Zwei Ebenen:
--   1. leaderstats: die eingebaute Roblox-Spielerliste zeigt Energie, Likes
--      und Besuche aller Spieler im aktuellen Server (live, alle 5 s).
--   2. Globale Ranglisten über OrderedDataStores ("Meiste Likes" und
--      "Meiste Gesamt-Energie" über alle Server hinweg): Werte werden
--      periodisch und beim Verlassen geschrieben, die Top-Liste wird
--      periodisch gelesen und per LeaderboardUpdated an alle Clients
--      verteilt (Anzeige: LeaderboardController).
--
-- In Studio ohne DataStore-Zugriff degradiert der Service sauber:
-- leaderstats funktionieren weiter, die globalen Listen bleiben leer.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)

local DataService = require(script.Parent.DataService)

local LEADERSTATS_UPDATE_SECONDS = 5

export type LeaderboardEntry = {
	userId: number,
	name: string,
	value: number,
}

export type LeaderboardSnapshot = {
	likes: { LeaderboardEntry },
	energy: { LeaderboardEntry },
}

local likesStore: OrderedDataStore? = nil
local energyStore: OrderedDataStore? = nil

local leaderboardUpdatedEvent: RemoteEvent? = nil

-- Zuletzt gelesene Top-Listen (werden neuen Spielern direkt geschickt).
local lastSnapshot: LeaderboardSnapshot = { likes = {}, energy = {} }

-- Cache für Namen von Spielern, die nicht (mehr) im Server sind.
local nameCache: { [number]: string } = {}

local LeaderboardService = {}

-- Erstellt die leaderstats-Werte für die eingebaute Spielerliste.
local function createLeaderstats(player: Player)
	if player:FindFirstChild("leaderstats") ~= nil then
		return
	end
	local stats = Instance.new("Folder")
	stats.Name = "leaderstats"

	for _, statName in { "Energie", "Likes", "Besuche" } do
		local value = Instance.new("IntValue")
		value.Name = statName
		value.Value = 0
		value.Parent = stats
	end

	stats.Parent = player
end

local function updateLeaderstats(player: Player, profile: Types.PlayerProfile)
	local stats = player:FindFirstChild("leaderstats")
	if stats == nil then
		return
	end
	local energie = stats:FindFirstChild("Energie")
	if energie ~= nil and energie:IsA("IntValue") then
		energie.Value = math.floor(profile.energy)
	end
	local likes = stats:FindFirstChild("Likes")
	if likes ~= nil and likes:IsA("IntValue") then
		likes.Value = profile.likes
	end
	local besuche = stats:FindFirstChild("Besuche")
	if besuche ~= nil and besuche:IsA("IntValue") then
		besuche.Value = profile.visits
	end
end

-- Schreibt die Bestwerte eines Spielers in die OrderedDataStores.
local function publishScores(player: Player)
	local profile = DataService.getProfile(player)
	if profile == nil then
		return
	end

	if likesStore ~= nil then
		local ok, err = pcall(function()
			(likesStore :: OrderedDataStore):SetAsync(tostring(player.UserId), profile.likes)
		end)
		if not ok then
			warn(`[PlanetForge] Rangliste (Likes) schreiben fehlgeschlagen: {err}`)
		end
	end

	if energyStore ~= nil then
		local ok, err = pcall(function()
			(energyStore :: OrderedDataStore):SetAsync(tostring(player.UserId), math.floor(profile.lifetimeEnergy))
		end)
		if not ok then
			warn(`[PlanetForge] Rangliste (Energie) schreiben fehlgeschlagen: {err}`)
		end
	end
end

-- Löst eine UserId in einen Anzeigenamen auf (Server-Spieler zuerst, dann Cache/API).
local function resolveName(userId: number): string
	local online = Players:GetPlayerByUserId(userId)
	if online ~= nil then
		return online.DisplayName
	end
	local cached = nameCache[userId]
	if cached ~= nil then
		return cached
	end
	local ok, name = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	if ok and typeof(name) == "string" then
		nameCache[userId] = name
		return name
	end
	return `Spieler {userId}`
end

-- Liest die Top-N-Einträge eines OrderedDataStores.
local function fetchTop(store: OrderedDataStore?): { LeaderboardEntry }
	if store == nil then
		return {}
	end

	local ok, pages = pcall(function()
		return (store :: OrderedDataStore):GetSortedAsync(false, GameConfig.LEADERBOARD_TOP_N)
	end)
	if not ok then
		warn(`[PlanetForge] Rangliste lesen fehlgeschlagen: {pages}`)
		return {}
	end

	local entries: { LeaderboardEntry } = {}
	local okPage, page = pcall(function()
		return (pages :: DataStorePages):GetCurrentPage()
	end)
	if not okPage or typeof(page) ~= "table" then
		return {}
	end

	for _, item in page :: { { key: string, value: number } } do
		local userId = tonumber(item.key)
		if userId ~= nil and typeof(item.value) == "number" and item.value > 0 then
			table.insert(entries, {
				userId = userId,
				name = resolveName(userId),
				value = item.value,
			})
		end
	end
	return entries
end

local function broadcastSnapshot()
	if leaderboardUpdatedEvent == nil then
		return
	end
	(leaderboardUpdatedEvent :: RemoteEvent):FireAllClients(lastSnapshot)
end

function LeaderboardService.init()
	leaderboardUpdatedEvent = Remotes.getEvent("LeaderboardUpdated")

	-- OrderedDataStores holen (kann in Studio ohne API-Zugriff fehlschlagen).
	local okLikes, likesResult = pcall(function()
		return DataStoreService:GetOrderedDataStore(GameConfig.LEADERBOARD_STORE_LIKES)
	end)
	if okLikes then
		likesStore = likesResult
	else
		warn(`[PlanetForge] OrderedDataStore (Likes) nicht verfügbar: {likesResult}`)
	end

	local okEnergy, energyResult = pcall(function()
		return DataStoreService:GetOrderedDataStore(GameConfig.LEADERBOARD_STORE_ENERGY)
	end)
	if okEnergy then
		energyStore = energyResult
	else
		warn(`[PlanetForge] OrderedDataStore (Energie) nicht verfügbar: {energyResult}`)
	end

	Players.PlayerAdded:Connect(function(player)
		createLeaderstats(player)
		task.spawn(function()
			local profile = DataService.waitForProfile(player)
			if profile ~= nil then
				updateLeaderstats(player, profile)
			end
			-- Aktuellen Ranglisten-Stand direkt an den neuen Spieler schicken.
			if leaderboardUpdatedEvent ~= nil then
				(leaderboardUpdatedEvent :: RemoteEvent):FireClient(player, lastSnapshot)
			end
		end)
	end)

	Players.PlayerRemoving:Connect(function(player)
		task.spawn(publishScores, player)
	end)

	for _, player in Players:GetPlayers() do
		createLeaderstats(player)
	end

	-- Live-Aktualisierung der leaderstats im Server.
	task.spawn(function()
		while true do
			task.wait(LEADERSTATS_UPDATE_SECONDS)
			for _, player in Players:GetPlayers() do
				local profile = DataService.getProfile(player)
				if profile ~= nil then
					updateLeaderstats(player, profile)
				end
			end
		end
	end)

	-- Periodisch eigene Werte schreiben und die globalen Top-Listen lesen.
	task.spawn(function()
		while true do
			for _, player in Players:GetPlayers() do
				publishScores(player)
			end

			lastSnapshot = {
				likes = fetchTop(likesStore),
				energy = fetchTop(energyStore),
			}
			broadcastSnapshot()

			task.wait(GameConfig.LEADERBOARD_REFRESH_SECONDS)
		end
	end)
end

return LeaderboardService
