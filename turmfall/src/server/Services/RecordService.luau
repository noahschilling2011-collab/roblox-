--!strict
-- RecordService: Server-Rekorde für den höchsten Turm (Woche + Allzeit).
--
-- Der virale Klassiker: Ein sichtbares Denkmal, auf dem der beste Wert
-- verewigt ist - Spieler kommen wieder, um sich selbst dort zu sehen.
-- Am Rundenende wird die höchste überlebende Turmhöhe gegen die
-- gespeicherten Rekorde geprüft (DataStore, UpdateAsync gegen Races
-- zwischen Servern) und das Denkmal-Schild aktualisiert.

local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Network = require(Shared.Network)
local GameConfig = require(Shared.Config.GameConfig)
local Types = require(Shared.Types)

local TowerService = require(script.Parent.TowerService)
local LobbyService = require(script.Parent.LobbyService)

type Record = {
	height: number,
	name: string,
	at: number,
}

local RecordService = {}

local store: DataStore? = nil

local weekRecord: Record? = nil
local allTimeRecord: Record? = nil

local notificationEvent: RemoteEvent? = nil

-- Wochen-Schlüssel (UTC-Wochennummer seit Epoche).
local function weekKey(): string
	return `woche_{math.floor(os.time() / 604800)}`
end

local function readRecord(key: string): Record?
	if store == nil then
		return nil
	end
	local ok, result = pcall(function()
		return (store :: DataStore):GetAsync(key)
	end)
	if ok and typeof(result) == "table" and typeof((result :: any).height) == "number" then
		return result :: Record
	end
	return nil
end

-- Schreibt einen Rekord NUR, wenn er auch im Store noch besser ist
-- (UpdateAsync: zwei Server können nicht gegenseitig überschreiben).
local function writeRecordIfBetter(key: string, candidate: Record): Record
	if store == nil then
		return candidate
	end
	local best = candidate
	local ok, err = pcall(function()
		(store :: DataStore):UpdateAsync(key, function(existing: any)
			if typeof(existing) == "table" and typeof(existing.height) == "number" and existing.height >= candidate.height then
				best = existing :: Record
				return nil -- bestehender Rekord ist besser: nichts schreiben
			end
			return candidate
		end)
	end)
	if not ok then
		warn(`[Turmfall] Rekord speichern fehlgeschlagen: {err}`)
	end
	return best
end

local function updateMonument()
	local week = weekRecord
	local allTime = allTimeRecord
	local weekText = if week ~= nil then `{week.height} Studs ({week.name})` else "– noch offen –"
	local allTimeText = if allTime ~= nil then `{allTime.height} Studs ({allTime.name})` else "– noch offen –"
	LobbyService.setMonumentText(`🏆 Höchster Turm der Woche\n{weekText}\n⭐ Allzeit: {allTimeText}`)
end

-- Rundenabschluss: Turmhöhe gegen die Rekorde prüfen (RoundService).
function RecordService.submitRound(entries: { Types.ScoreEntry })
	local height = TowerService.getMaxTowerHeightStuds()
	if height <= 0 then
		return
	end
	local winner = entries[1]
	local holderName = if winner ~= nil and winner.points > 0 then winner.name else "das Team"
	local candidate: Record = { height = height, name = holderName, at = os.time() }

	-- Wochen-Rekord.
	local currentWeek = weekRecord
	if currentWeek == nil or height > currentWeek.height then
		weekRecord = writeRecordIfBetter(weekKey(), candidate)
		if weekRecord ~= nil and (weekRecord :: Record).at == candidate.at and notificationEvent ~= nil then
			(notificationEvent :: RemoteEvent):FireAllClients(
				`🏆 NEUER WOCHEN-REKORD: {height} Studs! Verewigt am Denkmal!`,
				"success"
			)
		end
	end

	-- Allzeit-Rekord.
	local currentAllTime = allTimeRecord
	if currentAllTime == nil or height > currentAllTime.height then
		allTimeRecord = writeRecordIfBetter("allzeit", candidate)
		if allTimeRecord ~= nil and (allTimeRecord :: Record).at == candidate.at and notificationEvent ~= nil then
			(notificationEvent :: RemoteEvent):FireAllClients(
				`⭐ NEUER ALLZEIT-REKORD: {height} Studs! LEGENDÄR!`,
				"success"
			)
		end
	end

	updateMonument()
end

function RecordService.init()
	notificationEvent = Network.getEvent("Notification")

	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(GameConfig.RECORD_STORE_NAME)
	end)
	if ok then
		store = result
	else
		warn(`[Turmfall] Rekord-DataStore nicht verfügbar: {result}`)
	end

	-- Gespeicherte Rekorde laden und aufs Denkmal schreiben.
	task.spawn(function()
		weekRecord = readRecord(weekKey())
		allTimeRecord = readRecord("allzeit")
		updateMonument()
	end)
end

return RecordService
