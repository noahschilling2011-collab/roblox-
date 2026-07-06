--!strict
-- ScoreService: Punkte, Verursacher-Markierung und das Leaderboard.
--
-- Die eigentliche Rechenregel lebt pur und getestet in Shared/ScoreLogic:
-- Höhe der überlebenden eigenen Teile = Punkte, Kollaps-Verursacher = 0.
-- Dieser Service füttert die Logik mit dem echten Turm-Zustand und
-- verteilt das Ergebnis als ScoreboardChanged an alle Clients.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Network = require(Shared.Network)
local GameConfig = require(Shared.Config.GameConfig)
local ScoreLogic = require(Shared.ScoreLogic)
local Types = require(Shared.Types)

local TowerService = require(script.Parent.TowerService)
local CollapseService = require(script.Parent.CollapseService)

local ScoreService = {}

-- Verursacher der laufenden Runde (userId -> true).
local culprits: { [number]: boolean } = {}

local liveUpdatesActive = false

local scoreboardEvent: RemoteEvent? = nil
local notificationEvent: RemoteEvent? = nil

-- Baut die Board-Einträge aus dem aktuellen Turm-Zustand.
local function buildEntries(): { Types.ScoreEntry }
	local scores = ScoreLogic.computeScores(TowerService.getScoringPieces(), culprits)

	local entries: { Types.ScoreEntry } = {}
	for _, player in Players:GetPlayers() do
		table.insert(entries, {
			userId = player.UserId,
			name = player.DisplayName,
			points = scores[player.UserId] or 0,
			culprit = culprits[player.UserId] == true,
		})
	end
	table.sort(entries, function(a, b)
		return a.points > b.points
	end)
	return entries
end

function ScoreService.broadcast()
	if scoreboardEvent ~= nil then
		(scoreboardEvent :: RemoteEvent):FireAllClients(buildEntries())
	end
end

-- Markiert den Verursacher eines Kollapses (Hook vom CollapseService).
function ScoreService.markCulprit(culpritUserId: number?)
	if culpritUserId == nil then
		return
	end
	culprits[culpritUserId :: number] = true

	local culpritPlayer = Players:GetPlayerByUserId(culpritUserId :: number)
	if culpritPlayer ~= nil and notificationEvent ~= nil then
		(notificationEvent :: RemoteEvent):FireClient(
			culpritPlayer,
			"💥 DU hast den Turm kollabieren lassen - dein Einsatz ist weg (0 Punkte)!",
			"error"
		)
	end
	ScoreService.broadcast()
end

-- Neue Runde: Verursacher-Liste leeren.
function ScoreService.resetRound()
	table.clear(culprits)
	ScoreService.broadcast()
end

function ScoreService.setLiveUpdates(active: boolean)
	liveUpdatesActive = active
end

-- Endabrechnung der Runde (RoundService, Phase "Wertung").
function ScoreService.finishRound(): { Types.ScoreEntry }
	local entries = buildEntries()
	ScoreService.broadcast()
	return entries
end

function ScoreService.init()
	scoreboardEvent = Network.getEvent("ScoreboardChanged")
	notificationEvent = Network.getEvent("Notification")

	-- Hook: Kollaps -> Verursacher verliert den Einsatz (kein Zyklus,
	-- der CollapseService kennt diesen Service nicht).
	CollapseService.onCollapse = ScoreService.markCulprit

	-- Live-Board während der Bauphase.
	task.spawn(function()
		while true do
			task.wait(GameConfig.SCOREBOARD_REFRESH_SECONDS)
			if liveUpdatesActive then
				ScoreService.broadcast()
			end
		end
	end)
end

return ScoreService
