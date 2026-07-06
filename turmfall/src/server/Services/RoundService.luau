--!strict
-- RoundService: die Server-StateMachine und EINZIGE Source of Truth über
-- den Rundenzustand. Clients spiegeln nur, was RoundStateChanged sendet.
--
-- Phasen: Lobby -> Aufbau -> Bauphase -> Wertung -> Lobby
--   Lobby     wartet auf LOBBY_MIN_PLAYERS, dann Countdown
--   Aufbau    Turm/Deck/Punkte zurücksetzen, Spieler auf die Plattform
--   Bauphase  BUILD_SECONDS bauen; Drops, Kollaps-Erkennung, Live-Board
--   Wertung   Endabrechnung, Sieger zeigen, zurück in die Lobby

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Network = require(Shared.Network)
local GameConfig = require(Shared.Config.GameConfig)
local Types = require(Shared.Types)

local TowerService = require(script.Parent.TowerService)
local DeckService = require(script.Parent.DeckService)
local CollapseService = require(script.Parent.CollapseService)
local ScoreService = require(script.Parent.ScoreService)
local MonetizationService = require(script.Parent.MonetizationService)

local RoundService = {}

local currentPhase: Types.RoundPhase = "Lobby"

local stateEvent: RemoteEvent? = nil
local notificationEvent: RemoteEvent? = nil

-- Aktuellen Zustand an alle senden (info trägt Zusatzdaten je Phase).
local function broadcastState(secondsLeft: number, info: { [string]: any }?)
	if stateEvent ~= nil then
		(stateEvent :: RemoteEvent):FireAllClients(currentPhase, secondsLeft, info or {})
	end
end

local function setPhase(phase: Types.RoundPhase)
	currentPhase = phase

	-- Zentrale Schalter je Phase - die Services wissen nichts von Phasen,
	-- sie werden von hier aus an- und abgestellt (Single Source of Truth).
	TowerService.setBuildAllowed(phase == "Bauphase")
	DeckService.setDropsActive(phase == "Bauphase")
	CollapseService.setActive(phase == "Bauphase")
	ScoreService.setLiveUpdates(phase == "Bauphase")
end

local function notifyAll(message: string, kind: string)
	if notificationEvent ~= nil then
		(notificationEvent :: RemoteEvent):FireAllClients(message, kind)
	end
end

-- Teleportiert alle Spieler an den Rand der Basisplattform (im Kreis).
local function teleportPlayersToPlatform()
	local players = Players:GetPlayers()
	local radius = GameConfig.BASE_PLATFORM_SIZE / 2 - 4
	local topY = TowerService.getBaseTopY()
	for index, player in players do
		local character = player.Character
		if character == nil then
			continue
		end
		local angle = (index / math.max(#players, 1)) * 2 * math.pi
		local position = Vector3.new(math.cos(angle) * radius, topY + 4, math.sin(angle) * radius)
		-- Blick zur Mitte.
		character:PivotTo(CFrame.lookAt(position, Vector3.new(0, topY + 4, 0)))
	end
end

-- Wartet in der Lobby, bis genug Spieler da sind; bricht der Countdown
-- ab, wenn wieder zu wenige da sind. Blockiert bis zum Rundenstart.
local function runLobby()
	setPhase("Lobby")
	while true do
		-- Auf Mindestspielerzahl warten.
		while #Players:GetPlayers() < GameConfig.LOBBY_MIN_PLAYERS do
			broadcastState(0, { playersNeeded = GameConfig.LOBBY_MIN_PLAYERS - #Players:GetPlayers() })
			task.wait(1)
		end

		-- Countdown; abbrechen, wenn jemand geht.
		local aborted = false
		for secondsLeft = GameConfig.LOBBY_COUNTDOWN_SECONDS, 1, -1 do
			if #Players:GetPlayers() < GameConfig.LOBBY_MIN_PLAYERS then
				aborted = true
				break
			end
			broadcastState(secondsLeft, { countdown = true })
			task.wait(1)
		end
		if not aborted then
			return
		end
		notifyAll("Zu wenige Spieler - Countdown abgebrochen.", "error")
	end
end

local function runSetup()
	setPhase("Aufbau")

	-- Frische Runde: Turm weg, Schuld-Gedächtnis weg, Punkte weg.
	TowerService.resetTower()
	CollapseService.resetRound()
	ScoreService.resetRound()
	DeckService.resetRound(true) -- inkl. Startteil, damit sofort gebaut wird
	teleportPlayersToPlatform()

	for secondsLeft = GameConfig.SETUP_SECONDS, 1, -1 do
		broadcastState(secondsLeft)
		task.wait(1)
	end
end

local function runBuild()
	setPhase("Bauphase")
	notifyAll("🏗️ BAUPHASE! Baut den Turm - hoch hinaus gibt Punkte, Kollaps kostet alles!", "success")

	local finaleEvent = Network.getEvent("FinaleStarted")
	local finaleStarted = false

	for secondsLeft = GameConfig.BUILD_SECONDS, 1, -1 do
		-- "Letzter Stein"-Finale: die letzten Sekunden setzt jeder genau
		-- EIN Teil (Zeitlupe/Kamera machen die Clients rein visuell).
		if not finaleStarted and secondsLeft <= GameConfig.FINALE_SECONDS then
			finaleStarted = true
			TowerService.setFinaleMode(true)
			finaleEvent:FireAllClients()
			notifyAll(`🪨 LETZTER STEIN! Jeder setzt jetzt genau EIN Teil - macht es zählbar!`, "success")
		end
		broadcastState(secondsLeft, if finaleStarted then { finale = true } else nil)
		task.wait(1)
	end

	TowerService.setFinaleMode(false)
end

local function runScoring()
	setPhase("Wertung")

	local entries = ScoreService.finishRound()
	local winner = entries[1]
	if winner ~= nil and winner.points > 0 then
		notifyAll(`🏆 Runde vorbei! Sieger: {winner.name} mit {winner.points} Punkten!`, "success")
	else
		notifyAll("Runde vorbei - niemand hat gepunktet. Nächster Versuch!", "info")
	end

	-- Trümmer-Ausschüttung (erspielte Zweitwährung, Meilenstein 3).
	MonetizationService.awardRoundDebris(entries)

	for secondsLeft = GameConfig.SCORING_SECONDS, 1, -1 do
		broadcastState(secondsLeft, { final = true })
		task.wait(1)
	end
end

function RoundService.getPhase(): Types.RoundPhase
	return currentPhase
end

function RoundService.init()
	stateEvent = Network.getEvent("RoundStateChanged")
	notificationEvent = Network.getEvent("Notification")

	-- Neuen Spielern sofort den aktuellen Zustand spiegeln.
	Players.PlayerAdded:Connect(function()
		task.wait(1)
		broadcastState(0)
		ScoreService.broadcast()
	end)

	-- Die eigentliche StateMachine als Endlos-Schleife.
	task.spawn(function()
		while true do
			runLobby()
			runSetup()
			runBuild()
			runScoring()
		end
	end)
end

return RoundService
