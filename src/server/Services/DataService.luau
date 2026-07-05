--!strict
-- DataService: Persistenz der Spielerprofile über DataStoreService.
--
-- HINWEIS FÜR PRODUKTION:
-- Dieses Skelett nutzt bewusst einfaches Last-Writer-Wins OHNE Session-Locking.
-- Für einen echten Launch ist Session-Locking nötig (z. B. via ProfileStore),
-- damit parallele Sessions desselben Spielers (Server-Wechsel, Absturz-Rejoins)
-- den Spielstand nicht gegenseitig überschreiben.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)

local KEY_PREFIX = "player_"
local MAX_LOAD_ATTEMPTS = 3
local LOAD_BACKOFF_SECONDS = { 1, 2, 4 } -- Wartezeit nach dem 1./2./3. Fehlversuch
local WAIT_POLL_SECONDS = 0.1

-- Ein Session-Eintrag pro eingeloggtem Spieler.
type SessionEntry = {
	profile: Types.PlayerProfile,
	dirty: boolean, -- true = beim nächsten Autosave sichern
	saveable: boolean, -- false = Laden schlug fehl; niemals speichern, sonst würde ein alter Stand überschrieben
}

local sessions: { [Player]: SessionEntry } = {}

-- DataStore-Handle; wird auf nil gesetzt, wenn kein API-Zugriff möglich ist
-- (z. B. in Studio ohne aktivierten Studio-API-Zugriff).
local store: DataStore? = nil

local DataService = {}

-- Tiefe Kopie eines (JSON-artigen) Wertes.
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

-- Frisches Standardprofil (tiefe Kopie pro Spieler, niemals geteilt).
local function buildDefaultProfile(): Types.PlayerProfile
	return {
		version = GameConfig.PROFILE_SCHEMA_VERSION,
		energy = GameConfig.START_ENERGY,
		lifetimeEnergy = 0,
		biomes = {},
		collectibles = {},
		visits = 0,
		likes = 0,
		createdAt = os.time(),
	}
end

-- Schema-Migration: fehlende Felder aus dem Standardprofil ergänzen und
-- die Versionsnummer hochsetzen. Unbekannte/kaputte Daten -> Standardprofil.
local function migrateProfile(loaded: any): Types.PlayerProfile
	local default = buildDefaultProfile()
	if typeof(loaded) ~= "table" then
		return default
	end

	local version = loaded.version
	if typeof(version) ~= "number" or version < GameConfig.PROFILE_SCHEMA_VERSION then
		for key, defaultValue in default :: { [string]: any } do
			if loaded[key] == nil then
				loaded[key] = deepCopy(defaultValue)
			end
		end
		loaded.version = GameConfig.PROFILE_SCHEMA_VERSION
	end

	return loaded :: Types.PlayerProfile
end

-- Lädt das Profil eines Spielers mit bis zu MAX_LOAD_ATTEMPTS Versuchen.
-- Rückgabe: (profile, saveable). saveable = false bedeutet: nur Standardprofil,
-- darf nicht gespeichert werden.
local function loadProfile(player: Player): (Types.PlayerProfile, boolean)
	local dataStore = store
	if dataStore == nil then
		warn(`[PlanetForge] Kein DataStore-Zugriff - Standardprofil für {player.Name} (wird nicht gespeichert)`)
		return buildDefaultProfile(), false
	end

	local key = KEY_PREFIX .. player.UserId
	for attempt = 1, MAX_LOAD_ATTEMPTS do
		local ok, result = pcall(function()
			return dataStore:GetAsync(key)
		end)

		if ok then
			if result == nil then
				-- Neuer Spieler: frisches Standardprofil, darf gespeichert werden.
				return buildDefaultProfile(), true
			end
			return migrateProfile(result), true
		end

		local message = tostring(result)
		warn(`[PlanetForge] Laden fehlgeschlagen für {player.Name} (Versuch {attempt}/{MAX_LOAD_ATTEMPTS}): {message}`)

		-- Studio ohne API-Zugriff: sauber degradieren statt weiter zu versuchen.
		if string.find(string.lower(message), "studio", 1, true) ~= nil then
			store = nil
			warn("[PlanetForge] Studio ohne DataStore-API-Zugriff erkannt - es wird nichts gespeichert")
			break
		end

		if attempt < MAX_LOAD_ATTEMPTS then
			task.wait(LOAD_BACKOFF_SECONDS[attempt])
		end
	end

	warn(`[PlanetForge] Alle Ladeversuche fehlgeschlagen - Standardprofil für {player.Name} (wird nicht gespeichert)`)
	return buildDefaultProfile(), false
end

-- Speichert einen Session-Eintrag via UpdateAsync (Last-Writer-Wins, siehe Kopfkommentar).
local function saveProfile(player: Player, entry: SessionEntry): boolean
	local dataStore = store
	if dataStore == nil or not entry.saveable then
		return false
	end

	local key = KEY_PREFIX .. player.UserId
	-- Tiefe Kopie, damit spätere Änderungen den laufenden Schreibvorgang nicht stören.
	local snapshot = deepCopy(entry.profile)

	local ok, err = pcall(function()
		dataStore:UpdateAsync(key, function()
			return snapshot
		end)
	end)

	if ok then
		entry.dirty = false
		return true
	end

	warn(`[PlanetForge] Speichern fehlgeschlagen für {player.Name}: {err}`)
	return false
end

local function onPlayerAdded(player: Player)
	local profile, saveable = loadProfile(player)

	-- Spieler könnte den Server während des (yieldenden) Ladens verlassen haben.
	if player.Parent == nil then
		return
	end

	sessions[player] = {
		profile = profile,
		dirty = false,
		saveable = saveable,
	}
end

local function onPlayerRemoving(player: Player)
	local entry = sessions[player]
	sessions[player] = nil
	if entry ~= nil then
		saveProfile(player, entry)
	end
end

function DataService.init()
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(GameConfig.DATASTORE_NAME)
	end)
	if ok then
		store = result
	else
		warn(`[PlanetForge] GetDataStore fehlgeschlagen: {result}`)
	end

	Players.PlayerAdded:Connect(function(player)
		task.spawn(onPlayerAdded, player)
	end)
	Players.PlayerRemoving:Connect(onPlayerRemoving)

	-- Spieler, die vor init() beigetreten sind (z. B. Studio-Solo-Test).
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	-- Autosave-Schleife: sichert regelmäßig nur veränderte Profile.
	-- Die dirty-Einträge werden erst ohne Yield eingesammelt: saveProfile yieldet
	-- (UpdateAsync), und ein während der Iteration beitretender Spieler würde
	-- `sessions` mitten in der Schleife verändern (undefiniertes Verhalten).
	task.spawn(function()
		while true do
			task.wait(GameConfig.AUTOSAVE_INTERVAL_SECONDS)

			local toSave = {}
			for player, entry in sessions do
				if entry.dirty then
					table.insert(toSave, { player = player, entry = entry })
				end
			end

			for _, item in toSave do
				-- Nur speichern, wenn der Spieler noch da ist (sonst hat
				-- PlayerRemoving bereits gesichert und aufgeräumt).
				if sessions[item.player] == item.entry then
					saveProfile(item.player, item.entry)
				end
			end
		end
	end)

	-- Beim Server-Shutdown alle verbliebenen Profile sichern und synchron warten.
	game:BindToClose(function()
		local pending = 0
		for player, entry in sessions do
			pending += 1
			task.spawn(function()
				saveProfile(player, entry)
				pending -= 1
			end)
		end
		while pending > 0 do
			task.wait(WAIT_POLL_SECONDS)
		end
	end)
end

-- Gibt das Profil zurück oder nil, solange es noch nicht geladen ist.
function DataService.getProfile(player: Player): Types.PlayerProfile?
	local entry = sessions[player]
	if entry ~= nil then
		return entry.profile
	end
	return nil
end

-- Yieldet, bis das Profil geladen ist. Gibt nil zurück, sobald der Spieler weg ist.
function DataService.waitForProfile(player: Player): Types.PlayerProfile?
	while player.Parent ~= nil do
		local entry = sessions[player]
		if entry ~= nil then
			return entry.profile
		end
		task.wait(WAIT_POLL_SECONDS)
	end
	return nil
end

-- Markiert das Profil, damit es beim nächsten Autosave gesichert wird.
function DataService.markDirty(player: Player)
	local entry = sessions[player]
	if entry ~= nil then
		entry.dirty = true
	end
end

return DataService
