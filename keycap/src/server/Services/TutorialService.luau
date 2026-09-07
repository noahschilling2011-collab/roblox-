--!strict
-- Onboarding. Der Fortschritt liegt im Profil, nicht im Client - nach einem
-- Rejoin faengt niemand von vorne an, und der Client kann sich die
-- Abschluss-Belohnung nicht selbst geben.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local EconomyLogic = require(Shared.EconomyLogic)
local TutorialConfig = require(Shared.Config.TutorialConfig)
local Remotes = require(Shared.Remotes)
local DataService = require(script.Parent.DataService)
local ProductionService = require(script.Parent.ProductionService)

local TutorialService = {}

local function notify(player: Player, text: string)
	Remotes.get("Notify"):FireClient(player, text)
end

local function currentStep(profile: DataService.Profile)
	return TutorialConfig.STEPS[profile.tutorialStep]
end

local function advance(player: Player, profile: DataService.Profile)
	profile.tutorialStep += 1
	if profile.tutorialStep > #TutorialConfig.STEPS then
		profile.wins += TutorialConfig.REWARD_WINS
		DataService.syncLeaderstats(player)
		notify(player, ("%s  (+%d Wins)"):format(TutorialConfig.DONE_TEXT, TutorialConfig.REWARD_WINS))
	end
end

-- Wird von CourseService, ShopService und StealService gerufen. Der Name
-- muss zum `event` des aktuellen Schritts passen, sonst passiert nichts -
-- so kann kein Schritt uebersprungen werden.
function TutorialService.report(player: Player, event: string)
	local profile = DataService.get(player)
	if not profile then
		return
	end
	local step = currentStep(profile)
	if step and step.event == event then
		advance(player, profile)
	end
end

-- Zustand fuer den Client. Gibt nil zurueck, wenn das Tutorial durch ist.
--
-- ACHTUNG: Diese Funktion kann den Fortschritt WEITERSCHALTEN. Der erste
-- Schritt haengt an einer Zahl statt an einer Handlung, es gibt also nichts,
-- was ihn melden koennte - er wird hier beim Abfragen geprueft. StateService
-- ruft das im festen Takt, damit ist das der einzige Ort, an dem gepollt wird.
function TutorialService.stateFor(player: Player): { step: number, text: string }?
	local profile = DataService.get(player)
	if not profile then
		return nil
	end
	local step = currentStep(profile)
	if not step then
		return nil
	end

	-- Der erste Schritt haengt an einer Zahl, nicht an einer Handlung:
	-- sobald genug Vorrat da ist, ist er erledigt.
	if step.event == "vorrat" and step.requiresVorratForStage then
		local vorrat = ProductionService.totalVorrat(profile)
		if EconomyLogic.canEnterStage(vorrat, step.requiresVorratForStage) then
			advance(player, profile)
			step = currentStep(profile)
			if not step then
				return nil
			end
		end
	end

	return { step = profile.tutorialStep, text = step.text }
end

function TutorialService.start()
	print(("[KEYCAP] TutorialService: %d Schritte, %d Wins Belohnung"):format(
		#TutorialConfig.STEPS,
		TutorialConfig.REWARD_WINS
	))
end

return TutorialService
