-- ServerScriptService/Systems/SaveService.luau
--!strict
-- GHOSTNET :: Das Profil. Einzige Stelle im ganzen Projekt, die einen
-- DataStore anfasst.
--
-- WAS HIER DRINSTEHT
--   Alles, was einen Serverwechsel ueberleben muss: Bank, Unverkauftes, Rig,
--   Trace, Ziel-Cooldowns, Statistik. Alle Zeitstempel sind os.time()
--   (Unix-Zeit) - os.clock() ist die Laufzeit DIESES Serverprozesses und
--   damit nach einem Rejoin wertlos.
--
-- SESSION-LOCK
--   Beim Laden schreibt der Server eine frische SessionId ins Profil. Taucht
--   derselbe Spieler auf einem zweiten Server auf, ueberschreibt der neue die
--   Id - der aeltere Server merkt das beim naechsten Speichern, schreibt NICHT
--   mehr und beendet seine Sitzung. Ohne das ueberschreiben sich zwei Server
--   gegenseitig und man kann sich per Server-Hopping Sachen duplizieren.
--
-- WENN DAS LADEN SCHEITERT
--   Wird gekickt. Mit einem leeren Profil weiterspielen zu lassen waere
--   schlimmer: der Save beim Verlassen wuerde echten Fortschritt mit Nullen
--   ueberschreiben.

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Types = require(ReplicatedStorage.Shared.Types)

type Profile = Types.Profile

local SaveService = {}

local store: DataStore? = nil

local profiles: { [Player]: Profile } = {}
local sessionIds: { [Player]: string } = {}
local memoryOnly: { [Player]: boolean } = {} -- Studio-Notbetrieb ohne DataStore
local lastSaveAt: { [Player]: number } = {} -- os.clock()
local savePending: { [Player]: boolean } = {}
local saving: { [Player]: boolean } = {}
local finished: { [Player]: boolean } = {} -- Sitzung beendet, nicht mehr schreiben

local readyCallbacks: { (Player, Profile) -> () } = {}

--==========================================================================
-- Profil-Schema
--==========================================================================

local function defaultStats(): Types.Stats
	return { Hacks = 0, Fails = 0, Busts = 0, Sales = 0, Earned = 0, Upgrades = 0 }
end

function SaveService.DefaultProfile(): Profile
	local start = Config.Rig.StartLevels
	return {
		SchemaVersion = Config.Save.SchemaVersion,
		Banked = 0,
		Unsold = 0,
		Rig = { CPU = start.CPU, RAM = start.RAM, Cooling = start.Cooling, NetCard = start.NetCard },
		Trace = 0,
		Cooldowns = {},
		Stats = defaultStats(),
		LastSeen = os.time(),
		SessionId = "",
	}
end

local function toCount(value: any): number?
	if typeof(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
		return nil
	end
	return math.max(0, math.floor(value))
end

-- Migration und Missbrauchsschutz in einem: alles, was fehlt, kommt aus dem
-- Default, alles was da ist, wird auf Typ und Wertebereich geprueft. Neue
-- Felder in kuenftigen Schema-Versionen brauchen deshalb nur hier eine Zeile.
local function sanitize(raw: any): Profile
	local p = SaveService.DefaultProfile()
	if typeof(raw) ~= "table" then
		return p
	end

	p.Banked = toCount(raw.Banked) or p.Banked
	p.Unsold = toCount(raw.Unsold) or p.Unsold

	if typeof(raw.Rig) == "table" then
		for _, component in Config.Rig.Components do
			local level = (raw.Rig :: any)[component]
			if typeof(level) == "number" and level == level then
				(p.Rig :: any)[component] = math.clamp(math.floor(level), 1, Config.Rig.MaxLevel)
			end
		end
	end

	if typeof(raw.Trace) == "number" and raw.Trace == raw.Trace then
		p.Trace = math.clamp(raw.Trace, 0, Config.Trace.Max)
	end

	if typeof(raw.Cooldowns) == "table" then
		local now = os.time()
		for id, until_ in raw.Cooldowns do
			-- Abgelaufenes gar nicht erst uebernehmen: haelt das Profil klein.
			if typeof(id) == "string" and #id <= 32 and typeof(until_) == "number" and until_ > now then
				p.Cooldowns[id] = math.floor(until_)
			end
		end
	end

	if typeof(raw.Stats) == "table" then
		for key in defaultStats() do
			local value = toCount((raw.Stats :: any)[key])
			if value then
				(p.Stats :: any)[key] = value
			end
		end
	end

	p.LastSeen = toCount(raw.LastSeen) or p.LastSeen
	if typeof(raw.SessionId) == "string" then
		p.SessionId = raw.SessionId
	end

	p.SchemaVersion = Config.Save.SchemaVersion
	return p
end

-- Alte Cooldowns wegwerfen, bevor gespeichert wird.
local function pruneCooldowns(profile: Profile)
	local cutoff = os.time() - Config.Cooldown.KeepSeconds
	for id, until_ in profile.Cooldowns do
		if until_ < cutoff then
			profile.Cooldowns[id] = nil
		end
	end
end

-- Flache Kopie fuer den Store, damit ein laufender Save nicht mit dem
-- Live-Profil kollidiert, das der Spieler gerade weiter veraendert.
local function snapshotOf(profile: Profile): Profile
	local copy = table.clone(profile) :: Profile
	copy.Rig = table.clone(profile.Rig)
	copy.Stats = table.clone(profile.Stats)
	copy.Cooldowns = table.clone(profile.Cooldowns)
	return copy
end

--==========================================================================
-- DataStore-Zugriff (immer pcall + Backoff)
--==========================================================================

local function getStore(): DataStore?
	if store then
		return store
	end
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(Config.Save.StoreName)
	end)
	if ok and result then
		store = result
		return store
	end
	return nil
end

local function studioFallbackAllowed(): boolean
	return Config.Save.StudioMemoryFallback and RunService:IsStudio()
end

-- Fuehrt fn mit Wiederholungen aus. Liefert (erfolgreich, Ergebnis).
-- Im Studio wird kuerzer probiert: ist "Studio Access to API Services" aus,
-- scheitert jeder Versuch, und niemand will 7 Sekunden auf den Notbetrieb warten.
local function withRetry(label: string, playerName: string, fn: () -> any): (boolean, any)
	local maxRetries = if studioFallbackAllowed() then Config.Save.StudioRetries else Config.Save.MaxRetries
	local waitTime = Config.Save.RetryBase
	local lastError: any = nil

	for attempt = 1, maxRetries do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		lastError = result
		warn(("[GHOSTNET] %s fuer %s fehlgeschlagen (Versuch %d/%d): %s"):format(
			label,
			playerName,
			attempt,
			maxRetries,
			tostring(result)
		))
		if attempt < maxRetries then
			task.wait(waitTime)
			waitTime *= Config.Save.RetryFactor
		end
	end

	warn(("[GHOSTNET] %s fuer %s endgueltig gescheitert: %s"):format(label, playerName, tostring(lastError)))
	return false, nil
end

--==========================================================================
-- Laden
--==========================================================================

local function fireReady(player: Player, profile: Profile)
	for _, callback in readyCallbacks do
		local ok, err = pcall(callback, player, profile)
		if not ok then
			warn(("[GHOSTNET] Profil-Callback fehlgeschlagen: %s"):format(tostring(err)))
		end
	end
end

local function loadProfile(player: Player)
	local sessionId = HttpService:GenerateGUID(false)
	sessionIds[player] = sessionId

	local dataStore = getStore()
	if not dataStore then
		if studioFallbackAllowed() then
			warn("[GHOSTNET] Kein DataStore erreichbar - Studio-Notbetrieb, es wird NICHTS gespeichert.")
			memoryOnly[player] = true
			local fallback = SaveService.DefaultProfile()
			profiles[player] = fallback
			fireReady(player, fallback)
			return
		end
		player:Kick(Config.Save.KickMessage)
		return
	end

	local key = Config.Save.KeyFormat:format(player.UserId)

	local ok, loaded = withRetry("Profil laden", player.Name, function()
		return dataStore:UpdateAsync(key, function(raw: any): Profile
			local profile = sanitize(raw)

			-- Abkuehlung fuer die Zeit, in der der Spieler offline war. Der
			-- Trace laeuft also nicht "eingefroren" weiter - wer eine Woche
			-- weg war, faengt sauber an.
			local elapsed = math.max(0, os.time() - profile.LastSeen)
			if elapsed > 0 and profile.Trace > 0 then
				profile.Trace = math.max(0, profile.Trace - Config.GetTraceDecay(profile.Rig.Cooling) * elapsed)
			end

			-- Die juengere Sitzung uebernimmt das Schloss.
			profile.SessionId = sessionId
			profile.LastSeen = os.time()
			return profile
		end)
	end)

	if not player.Parent then
		return -- waehrend des Ladens rausgegangen
	end

	if not ok or typeof(loaded) ~= "table" then
		if studioFallbackAllowed() then
			warn(("[GHOSTNET] Laden fuer %s gescheitert - Studio-Notbetrieb ohne Speichern."):format(player.Name))
			memoryOnly[player] = true
			local fallback = SaveService.DefaultProfile()
			profiles[player] = fallback
			fireReady(player, fallback)
			return
		end
		player:Kick(Config.Save.KickMessage)
		return
	end

	local profile = sanitize(loaded)
	profile.SessionId = sessionId
	profiles[player] = profile
	lastSaveAt[player] = os.clock()

	print(("[GHOSTNET] Profil geladen: %s (Bank %d, Unverkauft %d, Trace %.0f)"):format(
		player.Name,
		profile.Banked,
		profile.Unsold,
		profile.Trace
	))

	fireReady(player, profile)
end

--==========================================================================
-- Speichern
--==========================================================================

local function endSession(player: Player, reason: string)
	if finished[player] then
		return
	end
	finished[player] = true
	profiles[player] = nil
	savePending[player] = nil
	if player.Parent then
		warn(("[GHOSTNET] Sitzung von %s beendet: %s"):format(player.Name, reason))
		player:Kick(Config.Save.LockKickMessage)
	end
end

-- final = letzter Save dieser Sitzung, danach wird das Schloss freigegeben.
local function saveProfile(player: Player, final: boolean): boolean
	if memoryOnly[player] then
		return false
	end
	local profile = profiles[player]
	if not profile then
		return false -- nie ein Profil schreiben, das nie geladen wurde
	end
	if saving[player] then
		return false
	end
	saving[player] = true

	profile.LastSeen = os.time()
	pruneCooldowns(profile)

	local snapshot = snapshotOf(profile)
	local mySession = sessionIds[player] or ""
	snapshot.SessionId = if final then "" else mySession

	local dataStore = getStore()
	local lostLock = false

	local ok = false
	if dataStore then
		local key = Config.Save.KeyFormat:format(player.UserId)
		ok = (withRetry("Profil speichern", player.Name, function()
			dataStore:UpdateAsync(key, function(raw: any)
				if
					typeof(raw) == "table"
					and typeof(raw.SessionId) == "string"
					and raw.SessionId ~= ""
					and raw.SessionId ~= mySession
				then
					-- Ein juengerer Server hat uebernommen. nil bricht den
					-- Schreibvorgang ab, statt fremden Fortschritt zu ueberbuegeln.
					lostLock = true
					return nil
				end
				return snapshot
			end)
			return true
		end))
	end

	saving[player] = nil
	lastSaveAt[player] = os.clock()
	savePending[player] = nil

	if lostLock then
		endSession(player, "Session-Lock von einem anderen Server uebernommen")
		return false
	end

	return ok
end

--==========================================================================
-- Oeffentliche Schnittstelle
--==========================================================================

-- Das Live-Profil. nil solange geladen wird oder wenn das Laden gescheitert
-- ist. Jeder Aufrufer muss mit nil umgehen koennen.
function SaveService.Get(player: Player): Profile?
	return profiles[player]
end

function SaveService.IsReady(player: Player): boolean
	return profiles[player] ~= nil
end

-- Nur zur Anzeige/Diagnose: im Studio-Notbetrieb wird nichts gespeichert.
function SaveService.IsMemoryOnly(player: Player): boolean
	return memoryOnly[player] == true
end

-- Wird fuer jeden Spieler genau einmal aufgerufen, sobald sein Profil steht -
-- auch fuer Spieler, die schon da waren, als der Callback registriert wurde.
function SaveService.OnReady(callback: (Player, Profile) -> ())
	table.insert(readyCallbacks, callback)
	for player, profile in profiles do
		task.spawn(callback, player, profile)
	end
end

-- Nach wichtigen Ereignissen (Verkauf, Kauf, Bust). Gedrosselt, damit ein
-- Spieler nicht durch schnelles Klicken das Schreib-Budget leert.
function SaveService.RequestSave(player: Player)
	if profiles[player] then
		savePending[player] = true
	end
end

function SaveService.SaveNow(player: Player): boolean
	return saveProfile(player, false)
end

--==========================================================================

function SaveService.Init()
	Players.PlayerAdded:Connect(function(player)
		task.spawn(loadProfile, player)
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(loadProfile, player)
	end

	Players.PlayerRemoving:Connect(function(player)
		-- Laeuft gerade ein Autosave, warten wir kurz darauf. Sonst wuerde der
		-- Abschluss-Save wegen saving[player] wortlos aussteigen und die
		-- letzten Sekunden Fortschritt waeren weg.
		local deadline = os.clock() + Config.Save.LeaveSaveWait
		while saving[player] and os.clock() < deadline do
			task.wait(0.1)
		end

		saveProfile(player, true)
		profiles[player] = nil
		sessionIds[player] = nil
		memoryOnly[player] = nil
		lastSaveAt[player] = nil
		savePending[player] = nil
		saving[player] = nil
		finished[player] = nil
	end)

	-- Ein Takt fuer Autosave und angeforderte Zwischenspeicherungen.
	task.spawn(function()
		while true do
			task.wait(1)
			local now = os.clock()
			for _, player in Players:GetPlayers() do
				if not profiles[player] or saving[player] then
					continue
				end
				local age = now - (lastSaveAt[player] or now)
				local due = age >= Config.Save.Interval
					or (savePending[player] == true and age >= Config.Save.MinInterval)
				if due then
					saveProfile(player, false)
				end
			end
		end
	end)

	game:BindToClose(function()
		local open = 0
		for _, player in Players:GetPlayers() do
			if profiles[player] then
				open += 1
				task.spawn(function()
					saveProfile(player, true)
					open -= 1
				end)
			end
		end
		local deadline = os.clock() + Config.Save.BindToCloseSeconds
		while open > 0 and os.clock() < deadline do
			task.wait(0.1)
		end
	end)

	print("[GHOSTNET] SaveService bereit.")
end

return SaveService
