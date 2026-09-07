--!strict
-- Profil-Speicher mit Session-Lock, Autosave und Speichern beim Verlassen.
--
-- Warum handgeschrieben statt ProfileService: das Konzept verbietet fremde
-- Bibliotheken. Der Lock ist deshalb hier drin - ohne ihn koennen zwei
-- Server dasselbe Profil schreiben und beim Server-Hopping gehen Tasten
-- verloren oder verdoppeln sich.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local EconomyConfig = require(Shared.Config.EconomyConfig)

-- 2: tutorialStep dazu. Profile aus Version 1 bekommen ihn per Migration
-- auf 1 gesetzt und laufen das Tutorial einmal - das Spiel ist nie
-- veroeffentlicht worden, es gibt also niemanden, den das stoert.
local SCHEMA_VERSION = 2
local STORE_NAME = "KeycapRush_Profiles_v1"
local LOCK_STALE_SECONDS = 120 -- aelterer Lock gilt als abgestuerzter Server
-- Ein Schreibvorgang erneuert Daten UND Lock, deshalb nur ein Intervall.
-- Nicht bei jeder Aenderung speichern - der Vorrat waechst sekuendlich und
-- DataStore drosselt Schreibvorgaenge.
local AUTOSAVE_SECONDS = 45
local MAX_RETRIES = 4

export type Key = { rarity: string, vorrat: number }
export type Profile = {
	schemaVersion: number,
	wins: number,
	slots: number,
	keys: { Key },
	totalStolen: number,
	totalCashedOut: number,
	tutorialStep: number,
}

local DataService = {}
DataService.__index = DataService

local store = DataStoreService:GetDataStore(STORE_NAME)
local profiles: { [number]: Profile } = {}
local loading: { [number]: boolean } = {}

local function defaultProfile(): Profile
	local keys: { Key } = {}
	-- Startausstattung: zwei Common-Tasten, damit sofort etwas produziert.
	for _ = 1, 2 do
		table.insert(keys, { rarity = "Common", vorrat = 0 })
	end
	return {
		schemaVersion = SCHEMA_VERSION,
		wins = 0,
		slots = EconomyConfig.START_KEY_SLOTS,
		keys = keys,
		totalStolen = 0,
		totalCashedOut = 0,
		tutorialStep = 1,
	}
end

-- Generische Migration: fehlende Felder aus dem Default auffuellen. Kein
-- Loeschen unbekannter Felder, damit ein Rollback nichts vernichtet.
local function migrate(raw: any): Profile
	local base = defaultProfile()
	if type(raw) ~= "table" then
		return base
	end
	for field, value in base :: any do
		if raw[field] == nil then
			raw[field] = value
		end
	end
	raw.schemaVersion = SCHEMA_VERSION
	-- Vorrat wird bewusst nicht uebernommen (siehe PERSIST_VORRAT).
	if not EconomyConfig.PERSIST_VORRAT then
		for _, key in raw.keys do
			key.vorrat = 0
		end
	end
	return raw :: Profile
end

local function retry<T>(label: string, fn: () -> T): (boolean, T?)
	local delaySeconds = 1
	for attempt = 1, MAX_RETRIES do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		warn(("[DataService] %s fehlgeschlagen (Versuch %d): %s"):format(label, attempt, tostring(result)))
		if attempt < MAX_RETRIES then
			task.wait(delaySeconds)
			delaySeconds *= 2
		end
	end
	return false, nil
end

local function storeKey(userId: number): string
	return "player_" .. userId
end

-- Lock nehmen und Profil holen. Gibt nil zurueck, wenn ein anderer Server
-- das Profil noch haelt - dann darf der Spieler NICHT spielen.
local function acquire(userId: number): Profile?
	local jobId = if RunService:IsStudio() then "studio" else game.JobId
	local blocked = false
	local loaded: any = nil

	-- Ein einziger UpdateAsync: Lock nehmen UND die Daten mitlesen. Ein
	-- zusaetzliches GetAsync waere ein zweiter Request ohne Mehrwert.
	local ok = retry("Lock " .. userId, function()
		blocked = false
		loaded = nil
		store:UpdateAsync(storeKey(userId), function(raw)
			local entry = raw
			if type(entry) ~= "table" or entry.data == nil then
				entry = { lock = nil, data = entry }
			end
			local lock = entry.lock
			if lock and lock.jobId ~= jobId and (os.time() - (lock.at or 0)) < LOCK_STALE_SECONDS then
				blocked = true
				return nil -- nichts schreiben, fremder Lock ist frisch
			end
			entry.lock = { jobId = jobId, at = os.time() }
			loaded = entry.data
			return entry
		end)
		return true
	end)

	if not ok or blocked then
		return nil
	end
	return migrate(loaded)
end

local function write(userId: number, profile: Profile, releaseLock: boolean): boolean
	local jobId = if RunService:IsStudio() then "studio" else game.JobId
	local ok = retry("Speichern " .. userId, function()
		store:UpdateAsync(storeKey(userId), function(raw)
			local entry = if type(raw) == "table" and raw.data ~= nil then raw else { lock = nil }
			local lock = entry.lock
			-- Nur schreiben, wenn wir den Lock halten (oder er verwaist ist).
			if lock and lock.jobId ~= jobId and (os.time() - (lock.at or 0)) < LOCK_STALE_SECONDS then
				return nil
			end
			entry.data = profile
			entry.lock = if releaseLock then nil else { jobId = jobId, at = os.time() }
			return entry
		end)
		return true
	end)
	return ok
end

function DataService.get(player: Player): Profile?
	return profiles[player.UserId]
end

function DataService.save(player: Player, releaseLock: boolean): boolean
	local profile = profiles[player.UserId]
	if not profile then
		return false
	end
	return write(player.UserId, profile, releaseLock)
end

local function onPlayerAdded(player: Player)
	loading[player.UserId] = true
	local profile = acquire(player.UserId)
	loading[player.UserId] = nil

	if not profile then
		if player.Parent then
			player:Kick("Deine Daten werden noch von einem anderen Server benutzt. Bitte in einer Minute nochmal beitreten.")
		end
		return
	end
	if not player.Parent then
		write(player.UserId, profile, true) -- schon wieder weg: Lock freigeben
		return
	end
	profiles[player.UserId] = profile

	local stats = Instance.new("Folder")
	stats.Name = "leaderstats"
	local wins = Instance.new("IntValue")
	wins.Name = "Wins"
	wins.Value = profile.wins
	wins.Parent = stats
	local stolen = Instance.new("IntValue")
	-- Die Bewertung: die Rangliste eines Klau-Spiels soll Beute zeigen.
	stolen.Name = "Beute"
	stolen.Value = profile.totalStolen
	stolen.Parent = stats
	stats.Parent = player
end

local function onPlayerRemoving(player: Player)
	if profiles[player.UserId] then
		write(player.UserId, profiles[player.UserId], true)
		profiles[player.UserId] = nil
	end
end

function DataService.syncLeaderstats(player: Player)
	local profile = profiles[player.UserId]
	local stats = player:FindFirstChild("leaderstats")
	if not profile or not stats then
		return
	end
	local wins = stats:FindFirstChild("Wins")
	if wins and wins:IsA("IntValue") then
		wins.Value = profile.wins
	end
	local stolen = stats:FindFirstChild("Beute")
	if stolen and stolen:IsA("IntValue") then
		stolen.Value = profile.totalStolen
	end
end

function DataService.start()
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerAdded:Connect(function(player)
		task.spawn(onPlayerAdded, player)
	end)
	Players.PlayerRemoving:Connect(onPlayerRemoving)

	-- Autosave: erneuert in einem Zug die Daten und den Lock, damit kein
	-- anderer Server das Profil uebernimmt, solange der Spieler hier ist.
	task.spawn(function()
		while true do
			task.wait(AUTOSAVE_SECONDS)
			for userId, profile in profiles do
				write(userId, profile, false)
			end
		end
	end)

	game:BindToClose(function()
		for userId, profile in profiles do
			write(userId, profile, true)
		end
	end)

	print("[KEYCAP] DataService bereit (Schema " .. SCHEMA_VERSION .. ")")
end

return DataService
