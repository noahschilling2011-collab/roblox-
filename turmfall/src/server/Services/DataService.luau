--!strict
-- DataService: Persistenz der Spielerprofile MIT Session-Locking.
--
-- Warum Session-Locking: Ohne Lock können zwei Server (Server-Wechsel,
-- Absturz-Rejoin) dasselbe Profil gleichzeitig halten und sich beim
-- Speichern gegenseitig überschreiben (Skins/Käufe verschwinden - der
-- schlimmste Fehler in einem Spiel mit Käufen). Deshalb liegt im DataStore
-- ein Wrapper { lock = {jobId, at}, data = profil }:
--   - Beim Laden setzt UpdateAsync den Lock atomar auf unsere JobId -
--     ABER nur, wenn kein fremder, frischer Lock existiert.
--   - Hält ein anderer Server einen frischen Lock, versuchen wir es kurz
--     erneut; danach läuft die Session READ-ONLY (saveable = false),
--     damit wir niemals fremde Daten überschreiben.
--   - Ein Heartbeat verlängert unseren Lock; beim Verlassen wird
--     gespeichert und der Lock freigegeben. Abgestürzte Server blockieren
--     dank LOCK_TIMEOUT nur kurz.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local SkinCatalog = require(Shared.Config.SkinCatalog)

local STORE_NAME = "Turmfall_v1"
local KEY_PREFIX = "spieler_"
local PROFILE_VERSION = 1

local LOCK_TIMEOUT_SECONDS = 120 -- fremde Locks älter als das gelten als tot
local LOCK_HEARTBEAT_SECONDS = 60
local LOCK_ACQUIRE_ATTEMPTS = 3
local LOCK_ACQUIRE_WAIT_SECONDS = 3
local MAX_SAVE_ATTEMPTS = 3
local SAVE_RETRY_SECONDS = 2
local WAIT_POLL_SECONDS = 0.1

export type Profile = {
	version: number,
	ownedSkins: { string },
	equipped: { [string]: string }, -- Slot (Teiltyp oder "kollaps") -> Skin-ID
	truemmer: number, -- Zweitwährung (erspielt, nicht kaufbar)
	receiptIds: { string }, -- verarbeitete Kauf-Belege (Idempotenz, M3)
	roundsPlayed: number,
}

type SessionEntry = {
	profile: Profile,
	dirty: boolean,
	saveable: boolean, -- false = Lock nicht bekommen/Ladefehler: NIE speichern
}

local DataService = {}

local sessions: { [Player]: SessionEntry } = {}
local store: DataStore? = nil
local jobId = if game.JobId ~= "" then game.JobId else "studio"

local function deepCopy(value: any): any
	if typeof(value) == "table" then
		local copy = {}
		for key, child in value do
			copy[key] = deepCopy(child)
		end
		return copy
	end
	return value
end

local function buildDefaultProfile(): Profile
	local owned: { string } = {}
	local equipped: { [string]: string } = {}
	-- Start-Skins ("unlockCondition = start") besitzt jeder sofort.
	for _, id in SkinCatalog.getSortedIds() do
		if SkinCatalog.Skins[id].unlockCondition == "start" then
			table.insert(owned, id)
		end
	end
	return {
		version = PROFILE_VERSION,
		ownedSkins = owned,
		equipped = equipped,
		truemmer = 0,
		receiptIds = {},
		roundsPlayed = 0,
	}
end

-- Fehlende Felder aus dem Standardprofil ergänzen (Migration).
local function migrateProfile(loaded: any): Profile
	local default = buildDefaultProfile()
	if typeof(loaded) ~= "table" then
		return default
	end
	for key, defaultValue in default :: { [string]: any } do
		if loaded[key] == nil then
			loaded[key] = deepCopy(defaultValue)
		end
	end
	loaded.version = PROFILE_VERSION
	return loaded :: Profile
end

--------------------------------------------------------------------------
-- Laden mit Lock
--------------------------------------------------------------------------

-- Ein UpdateAsync-Versuch: Lock übernehmen, wenn frei/abgelaufen/eigener.
-- Rückgabe: (gelungen, profil).
local function tryAcquire(key: string): (boolean, Profile?)
	local dataStore = store :: DataStore
	local acquired = false
	local profile: Profile? = nil

	local ok, err = pcall(function()
		dataStore:UpdateAsync(key, function(existing: any)
			local wrapper = if typeof(existing) == "table" then existing else {}
			local lock = wrapper.lock
			local lockIsForeign = typeof(lock) == "table"
				and lock.jobId ~= jobId
				and typeof(lock.at) == "number"
				and os.time() - lock.at < LOCK_TIMEOUT_SECONDS
			if lockIsForeign then
				acquired = false
				return nil -- nichts schreiben, fremder Lock lebt noch
			end
			acquired = true
			profile = migrateProfile(wrapper.data)
			return { lock = { jobId = jobId, at = os.time() }, data = wrapper.data or {} }
		end)
	end)
	if not ok then
		warn(`[Turmfall] Laden/Lock fehlgeschlagen: {err}`)
		return false, nil
	end
	return acquired, profile
end

local function loadProfile(player: Player): (Profile, boolean)
	if store == nil then
		warn(`[Turmfall] Kein DataStore-Zugriff - Standardprofil für {player.Name} (wird nicht gespeichert)`)
		return buildDefaultProfile(), false
	end

	local key = KEY_PREFIX .. player.UserId
	for attempt = 1, LOCK_ACQUIRE_ATTEMPTS do
		local acquired, profile = tryAcquire(key)
		if acquired and profile ~= nil then
			return profile :: Profile, true
		end
		if attempt < LOCK_ACQUIRE_ATTEMPTS then
			task.wait(LOCK_ACQUIRE_WAIT_SECONDS)
		end
	end

	-- Lock nicht bekommen: read-only weiterspielen statt Daten zu riskieren.
	warn(`[Turmfall] Session-Lock für {player.Name} belegt - Profil ist diese Session READ-ONLY`)
	local fallback: Profile = buildDefaultProfile()
	local ok, existing = pcall(function()
		return (store :: DataStore):GetAsync(key)
	end)
	if ok and typeof(existing) == "table" then
		fallback = migrateProfile((existing :: any).data)
	end
	return fallback, false
end

--------------------------------------------------------------------------
-- Speichern (behält den Lock) und Freigeben
--------------------------------------------------------------------------

local function writeProfile(player: Player, entry: SessionEntry, releaseLock: boolean): boolean
	local dataStore = store
	if dataStore == nil or not entry.saveable then
		return false
	end

	local key = KEY_PREFIX .. player.UserId
	local snapshot = deepCopy(entry.profile)

	for attempt = 1, MAX_SAVE_ATTEMPTS do
		local ok, err = pcall(function()
			(dataStore :: DataStore):UpdateAsync(key, function()
				return {
					lock = if releaseLock then nil else { jobId = jobId, at = os.time() },
					data = snapshot,
				}
			end)
		end)
		if ok then
			entry.dirty = false
			return true
		end
		warn(`[Turmfall] Speichern fehlgeschlagen für {player.Name} (Versuch {attempt}/{MAX_SAVE_ATTEMPTS}): {err}`)
		if attempt < MAX_SAVE_ATTEMPTS then
			task.wait(SAVE_RETRY_SECONDS)
		end
	end
	return false
end

--------------------------------------------------------------------------
-- Lebenszyklus
--------------------------------------------------------------------------

local function onPlayerAdded(player: Player)
	local profile, saveable = loadProfile(player)
	if player.Parent == nil then
		return
	end
	sessions[player] = { profile = profile, dirty = false, saveable = saveable }
end

local function onPlayerRemoving(player: Player)
	local entry = sessions[player]
	sessions[player] = nil
	if entry ~= nil then
		writeProfile(player, entry, true) -- speichern UND Lock freigeben
	end
end

function DataService.init()
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)
	if ok then
		store = result
	else
		warn(`[Turmfall] GetDataStore fehlgeschlagen: {result}`)
	end
	if RunService:IsStudio() then
		jobId = "studio_" .. tostring(math.floor(os.clock() * 1000))
	end

	Players.PlayerAdded:Connect(function(player)
		task.spawn(onPlayerAdded, player)
	end)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	-- Heartbeat: Lock verlängern + veränderte Profile sichern.
	task.spawn(function()
		while true do
			task.wait(LOCK_HEARTBEAT_SECONDS)
			local toSave = {}
			for player, entry in sessions do
				table.insert(toSave, { player = player, entry = entry })
			end
			for _, item in toSave do
				if sessions[item.player] == item.entry then
					writeProfile(item.player, item.entry, false)
				end
			end
		end
	end)

	-- Server-Shutdown: alles sichern und Locks freigeben (synchron warten).
	game:BindToClose(function()
		local pending = 0
		for player, entry in sessions do
			pending += 1
			task.spawn(function()
				writeProfile(player, entry, true)
				pending -= 1
			end)
		end
		while pending > 0 do
			task.wait(WAIT_POLL_SECONDS)
		end
	end)
end

function DataService.getProfile(player: Player): Profile?
	local entry = sessions[player]
	return if entry ~= nil then entry.profile else nil
end

-- Yieldet, bis das Profil da ist (nil, wenn der Spieler weg ist).
function DataService.waitForProfile(player: Player): Profile?
	while player.Parent ~= nil do
		local entry = sessions[player]
		if entry ~= nil then
			return entry.profile
		end
		task.wait(WAIT_POLL_SECONDS)
	end
	return nil
end

function DataService.markDirty(player: Player)
	local entry = sessions[player]
	if entry ~= nil then
		entry.dirty = true
	end
end

-- Ist diese Session beschreibbar? (false = Lock verpasst -> keine Käufe!)
function DataService.isSaveable(player: Player): boolean
	local entry = sessions[player]
	return entry ~= nil and entry.saveable
end

return DataService
