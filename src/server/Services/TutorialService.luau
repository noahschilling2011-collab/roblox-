--!strict
-- TutorialService: serverseitiger Fortschritt der First-Time Experience.
--
-- Der Client (TutorialController) zeigt die geführten Schritte an und meldet
-- per TutorialAction("advance"), wenn er glaubt, dass der aktuelle Schritt
-- geschafft ist. Der Server bleibt autoritativ: Jeder Schritt wird gegen den
-- echten Profilzustand validiert, erst dann wird weitergeschaltet.
--
-- Schritte (profile.tutorialStep = nächster offener Schritt):
--   1  Platziere deine erste Wiese       (mindestens 1 Biom gebaut)
--   2  Sammle Energie ein                (lifetimeEnergy >= COLLECT_AMOUNT)
--   3  Kaufe ein Upgrade                 (mindestens 1 Biom auf Level >= 2)
--   4  Suche deinen ersten Fund          (mindestens 1 Sammelobjekt)
--   5  = abgeschlossen (kommt nie wieder)
--
-- Jeder abgeschlossene Schritt gibt eine kleine Energie-Belohnung
-- (GameConfig.TUTORIAL_STEP_REWARD), damit der Ablauf nie am Preis des
-- nächsten Schritts stockt. "skip" beendet das Tutorial sofort (Rückkehrer).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)

local DataService = require(script.Parent.DataService)
local EnergyService = require(script.Parent.EnergyService)

local DONE_STEP = GameConfig.TUTORIAL_STEP_COUNT + 1

local tutorialUpdatedEvent: RemoteEvent? = nil

local TutorialService = {}

-- Prüft, ob die Bedingung des angegebenen Schritts im Profil erfüllt ist.
local function isStepFulfilled(profile: Types.PlayerProfile, step: number): boolean
	if step == 1 then
		return #profile.biomes >= 1
	elseif step == 2 then
		return profile.lifetimeEnergy >= GameConfig.COLLECT_AMOUNT
	elseif step == 3 then
		for _, placed in profile.biomes do
			if placed.level >= 2 then
				return true
			end
		end
		return false
	elseif step == 4 then
		return #profile.collectibles >= 1
	end
	return false
end

local function fireUpdate(player: Player, step: number)
	if tutorialUpdatedEvent ~= nil then
		(tutorialUpdatedEvent :: RemoteEvent):FireClient(player, step)
	end
end

-- Handler für TutorialAction(action).
local function onTutorialAction(player: Player, actionArg: any): (boolean, any?)
	if typeof(actionArg) ~= "string" then
		return false, "Ungültige Aktion."
	end

	local profile = DataService.getProfile(player)
	if profile == nil then
		return false, "Dein Profil ist noch nicht geladen."
	end

	-- "status": aktueller Stand ohne Änderung (Client fragt nach dem Beitritt nach).
	if actionArg == "status" then
		return true, profile.tutorialStep
	end

	if profile.tutorialStep >= DONE_STEP then
		return true, DONE_STEP -- längst fertig; nichts zu tun
	end

	if actionArg == "skip" then
		profile.tutorialStep = DONE_STEP
		DataService.markDirty(player)
		fireUpdate(player, DONE_STEP)
		return true, DONE_STEP
	end

	if actionArg ~= "advance" then
		return false, "Unbekannte Aktion."
	end

	-- Autoritative Prüfung: Der Schritt zählt nur, wenn das Profil ihn belegt.
	if not isStepFulfilled(profile, profile.tutorialStep) then
		return false, "Dieser Schritt ist noch nicht geschafft."
	end

	profile.tutorialStep += 1
	DataService.markDirty(player)

	-- Kleine Belohnung, damit der nächste Schritt immer bezahlbar ist.
	EnergyService.grantEnergy(player, GameConfig.TUTORIAL_STEP_REWARD)

	fireUpdate(player, profile.tutorialStep)
	return true, profile.tutorialStep
end

local function onPlayerAdded(player: Player)
	local profile = DataService.waitForProfile(player)
	if profile == nil then
		return
	end

	-- Falls ältere Profile (Migration) einen ungültigen Wert tragen: klemmen.
	if typeof(profile.tutorialStep) ~= "number" or profile.tutorialStep < 1 then
		profile.tutorialStep = 1
	elseif profile.tutorialStep > DONE_STEP then
		profile.tutorialStep = DONE_STEP
	end

	fireUpdate(player, profile.tutorialStep)
end

function TutorialService.init()
	tutorialUpdatedEvent = Remotes.getEvent("TutorialUpdated")
	Remotes.getFunction("TutorialAction").OnServerInvoke = onTutorialAction

	Players.PlayerAdded:Connect(function(player)
		task.spawn(onPlayerAdded, player)
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
end

return TutorialService
