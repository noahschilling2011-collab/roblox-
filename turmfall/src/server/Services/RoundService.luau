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
local DisasterService = require(script.Parent.DisasterService)
local RecordService = require(script.Parent.RecordService)

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
	DisasterService.setActive(phase == "Bauphase")
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

-- Wartet in der Lobby bis zum Rundenstart. Zwei Wege hinaus:
--   - Multiplayer: ab LOBBY_MIN_PLAYERS läuft der normale Countdown.
--   - Solo-Modus: Wer allein ist, startet nach SOLO_START_WAIT_SECONDS
--     eine Übungsrunde (joint rechtzeitig jemand, gilt der Countdown).
local function runLobby()
	setPhase("Lobby")
	while true do
		local playerCount = #Players:GetPlayers()

		if playerCount >= GameConfig.LOBBY_MIN_PLAYERS then
			-- Multiplayer-Countdown; abbrechen, wenn jemand geht.
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
		elseif playerCount >= 1 and GameConfig.SOLO_MODE_ENABLED then
			-- Solo-Anlauf: kurz warten, ob noch jemand einsteigt.
			local interrupted = false
			for secondsLeft = GameConfig.SOLO_START_WAIT_SECONDS, 1, -1 do
				local currentCount = #Players:GetPlayers()
				if currentCount >= GameConfig.LOBBY_MIN_PLAYERS or currentCount == 0 then
					interrupted = true -- Mitspieler da bzw. alle weg: neu entscheiden
					break
				end
				broadcastState(secondsLeft, { soloCountdown = true })
				task.wait(1)
			end
			if not interrupted then
				notifyAll("🧍 Solo-Runde! Übe den Turmbau - Mitspieler können jederzeit einsteigen.", "info")
				return
			end
		else
			-- Leerer Server oder Solo-Modus deaktiviert: auf Spieler warten.
			broadcastState(0, { playersNeeded = math.max(GameConfig.LOBBY_MIN_PLAYERS - playerCount, 1) })
			task.wait(1)
		end
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

-- Sieger-Feier: goldene Krone + Konfetti über dem Gewinner für die Dauer
-- der Wertung - der Moment, für den man die nächste Runde bleibt.
local function celebrateWinner(winnerUserId: number)
	local winner = Players:GetPlayerByUserId(winnerUserId)
	local character = if winner ~= nil then winner.Character else nil
	local head = if character ~= nil then character:FindFirstChild("Head") else nil
	if head == nil or not head:IsA("BasePart") then
		return
	end

	local crown = Instance.new("Part")
	crown.Name = "SiegerKrone"
	crown.Shape = Enum.PartType.Cylinder
	crown.Size = Vector3.new(0.4, 1.8, 1.8)
	crown.Color = Color3.fromRGB(235, 186, 60)
	crown.Material = Enum.Material.Neon
	crown.CanCollide = false
	crown.Massless = true
	crown.CFrame = (head :: BasePart).CFrame * CFrame.new(0, 1.2, 0) * CFrame.Angles(0, 0, math.rad(90))
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = head :: BasePart
	weld.Part1 = crown
	weld.Parent = crown
	crown.Parent = character

	local confetti = Instance.new("ParticleEmitter")
	confetti.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 90, 90)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(90, 200, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 220, 90)),
	})
	confetti.LightEmission = 0.8
	confetti.Rate = 25
	confetti.Lifetime = NumberRange.new(1, 2)
	confetti.Speed = NumberRange.new(6, 12)
	confetti.SpreadAngle = Vector2.new(180, 180)
	confetti.Size = NumberSequence.new(0.4)
	confetti.Parent = crown

	task.delay(GameConfig.SCORING_SECONDS, function()
		crown:Destroy()
	end)
end

local function runScoring()
	setPhase("Wertung")

	local entries = ScoreService.finishRound()
	local winner = entries[1]
	if winner ~= nil and winner.points > 0 then
		notifyAll(`🏆 Runde vorbei! Sieger: {winner.name} mit {winner.points} Punkten!`, "success")
		celebrateWinner(winner.userId)
	else
		notifyAll("Runde vorbei - niemand hat gepunktet. Nächster Versuch!", "info")
	end

	-- Trümmer-Ausschüttung (erspielte Zweitwährung, Meilenstein 3).
	MonetizationService.awardRoundDebris(entries)

	-- Turmhöhe gegen Wochen-/Allzeit-Rekord prüfen (Denkmal).
	RecordService.submitRound(entries)

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
