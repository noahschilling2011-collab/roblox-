-- ServerScriptService/Systems/PhoneService.luau
--!strict
-- GHOSTNET :: Die Story als Chatverlauf mit Wren.
--
-- DAS PROBLEM, DAS DAS LOEST
--   MissionService und Missions.luau funktionieren seit Langem. Nur sieht
--   der Spieler nichts davon: das Briefing blinkt einmal auf und ist weg.
--   Eine Geschichte, die man nicht nachlesen kann, ist keine Geschichte.
--
-- KEIN NEUES SPEICHERFELD, KEINE MIGRATION
--   Der Verlauf wird bei jedem Sync AUS DEM STORY-ZUSTAND GEBAUT: erledigte
--   Missionen plus die aktive. Damit ist er automatisch korrekt, ueberlebt
--   jeden Serverwechsel und das Profil-Schema bleibt unveraendert.
--   Ein zweites, mitgeschriebenes Chatprotokoll waere eine zweite Wahrheit,
--   die irgendwann von der ersten abweicht.
--
-- KEIN NEUES MISSIONSSYSTEM
--   Hier wird nichts entschieden. PhoneService liest, formatiert und
--   verschickt - angenommen und abgeschlossen wird weiter im MissionService.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Missions = require(ReplicatedStorage.Shared.Missions)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local RateLimiter = require(script.Parent.RateLimiter)
local MissionService = require(script.Parent.MissionService)
local SaveService = require(script.Parent.SaveService)

local PhoneService = {}

local P = Config.Phone

-- Ungelesen ist reine Sitzungsinformation: wer neu einsteigt, soll das
-- Telefon leuchten sehen. Das muss keinen Serverwechsel ueberleben.
local unread: { [Player]: boolean } = {}

--==========================================================================
-- Verlauf bauen
--==========================================================================

type Message = {
	From: string,
	Text: string,
	Mission: string,
	State: string, -- "DONE" | "ACTIVE" | "INFO"
}

local function push(list: { Message }, from: string, text: string, mission: string, state: string)
	table.insert(list, { From = from, Text = text, Mission = mission, State = state })
end

local function buildHistory(player: Player): ({ Message }, string)
	local profile = SaveService.Get(player)
	local messages: { Message } = {}
	if not profile then
		return messages, ""
	end

	local story = profile.Story

	-- Erledigtes zuerst, in der Reihenfolge der Registry - dann liest sich
	-- der Verlauf wie ein Gespraech und nicht wie eine Datenbank.
	for _, mission in Missions.List do
		if not Missions.IsCompleted(story, mission.Id) then
			continue
		end
		push(messages, "WREN", mission.Briefing, mission.Id, "DONE")
		push(messages, "DU", "Erledigt.", mission.Id, "DONE")
	end

	local activeTitle = ""
	if story.Active ~= "" then
		local mission = Missions.Get(story.Active)
		if mission then
			activeTitle = mission.Title
			push(messages, "WREN", mission.Briefing, mission.Id, "ACTIVE")
		end
	elseif #story.Completed >= #Missions.List and #Missions.List > 0 then
		-- Story durch. Das Telefon bleibt der Ort, an dem es weitergeht -
		-- die wiederholbaren Ziele stehen ohnehin alle in der Stadt.
		push(
			messages,
			"WREN",
			"Das war die Geschichte. Die Stadt laeuft weiter.\nNimm dir, was du brauchst - du weisst jetzt, wie.",
			"",
			"INFO"
		)
	end

	-- Nie unbegrenzt wachsen lassen: bei sehr langen Verlaeufen zaehlt nur,
	-- was zuletzt passiert ist.
	while #messages > P.HistoryLimit do
		table.remove(messages, 1)
	end

	return messages, activeTitle
end

-- Kurze Zusammenfassung fuer den Wiedereinstieg. Wer eine Woche weg war,
-- muss in einem Satz zurueck in die Geschichte finden.
local function summaryFor(player: Player): string
	local profile = SaveService.Get(player)
	if not profile then
		return ""
	end
	local story = profile.Story
	local last = story.Completed[#story.Completed]
	if not last then
		return ""
	end
	local mission = Missions.Get(last)
	if not mission then
		return ""
	end
	if story.Active == "" then
		return ("Zuletzt: %s. Wren meldet sich."):format(mission.Title)
	end
	return ("Zuletzt: %s. Wren wartet auf Antwort."):format(mission.Title)
end

--==========================================================================
-- Senden
--==========================================================================

function PhoneService.SyncTo(player: Player)
	if not player.Parent then
		return
	end
	local messages, activeTitle = buildHistory(player)
	Remotes.PhoneSync:FireClient(player, {
		Messages = messages,
		Unread = unread[player] == true,
		ActiveTitle = activeTitle,
		Summary = summaryFor(player),
	})
end

-- Es gibt etwas Neues. Der Knopf pulsiert, bis der Spieler hinsieht.
function PhoneService.Notify(player: Player)
	unread[player] = true
	PhoneService.SyncTo(player)
end

--==========================================================================

function PhoneService.Init()
	Remotes.PhoneRead.OnServerEvent:Connect(function(player: Player)
		if not RateLimiter.Check(player, "PhoneRead") then
			return
		end
		unread[player] = false
		PhoneService.SyncTo(player)
	end)

	-- An den MissionService anhaengen statt ihn anzufassen: eine neue
	-- Mission und ein Abschluss sind genau die zwei Momente, in denen das
	-- Telefon klingeln muss.
	MissionService.OnMissionComplete(function(player: Player)
		-- Verzoegert, damit die naechste Mission schon gestartet ist und die
		-- Nachricht gleich den neuen Auftrag enthaelt. Innerhalb des
		-- Fensters, in dem der Spieler noch hinsieht.
		task.delay(P.NextMessageDelay, function()
			if player.Parent then
				PhoneService.Notify(player)
			end
		end)
	end)

	Players.PlayerAdded:Connect(function(player)
		unread[player] = true
	end)
	Players.PlayerRemoving:Connect(function(player)
		unread[player] = nil
	end)

	-- Sobald ein Profil geladen ist, kennt der Verlauf seinen Inhalt.
	SaveService.OnReady(function(player: Player)
		unread[player] = true
		PhoneService.SyncTo(player)
	end)

	print("[GHOSTNET] PhoneService bereit.")
end

return PhoneService
