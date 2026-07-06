--!strict
-- TutorialController: geführte First-Time Experience für den Sammel-Loop.
--
-- Sechs Schritte mit Textbox und pulsierendem Highlight am richtigen Ort:
--   1  Sammle 5 Objekte          (die eigene Wiesen-Zone leuchtet)
--   2  Verkaufe am 💰-Pad        (das Verkaufs-Pad leuchtet)
--   3  Kauf ein Insel-Upgrade    (das "Biome"-Menü pulsiert)
--   4  Schalte eine 2. Zone frei (das "Biome"-Menü pulsiert)
--   5  Wirf einen Fund-Wurf      (der "Fund suchen"-Button pulsiert)
--   6  Erreiche 500 Gesamt-Energie (freies Spielen bis zum Ziel)
--
-- Der Fortschritt liegt im Profil (TutorialService validiert autoritativ);
-- das Tutorial erscheint deshalb nur einmal. Skip-Button für Rückkehrer.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ConfigFolder = Shared:WaitForChild("Config")
local ControllersFolder = script.Parent :: Instance

local Remotes = require(Shared:WaitForChild("Remotes") :: ModuleScript) :: {
	getEvent: (name: string) -> RemoteEvent,
	getFunction: (name: string) -> RemoteFunction,
}
local GameConfig = require(ConfigFolder:WaitForChild("GameConfig") :: ModuleScript) :: {
	PLANET_SLOTS: number,
	TUTORIAL_STEP_COUNT: number,
}
local UIController = require(ControllersFolder:WaitForChild("UIController") :: ModuleScript) :: {
	showToast: (message: string, kind: string) -> (),
}

-- Farbschema (identisch zum UIController) plus Gold-Akzent für Highlights.
local PANEL_COLOR = Color3.fromRGB(30, 32, 44)
local TEXT_COLOR = Color3.fromRGB(235, 238, 245)
local SUBTEXT_COLOR = Color3.fromRGB(158, 164, 186)
local ACCENT_COLOR = Color3.fromRGB(214, 160, 72)
local SKIP_COLOR = Color3.fromRGB(60, 64, 84)

local DONE_STEP = GameConfig.TUTORIAL_STEP_COUNT + 1
local PULSE_INFO = TweenInfo.new(0.7, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)

type StepDef = {
	text: string,
	target: "zone" | "sellpad" | "biomeButton" | "lootButton" | "none",
	arrowText: string?,
}

local STEPS: { StepDef } = {
	{ text = "Lauf über deine Wiese und sammle 5 Objekte ein! 🌿", target = "zone", arrowText = "⬇ Hier sammeln!" },
	{ text = "Stell dich auf das goldene Pad und verkaufe deine Beute! 💰", target = "sellpad", arrowText = "⬇ Hier verkaufen!" },
	{ text = 'Kauf dein erstes Insel-Upgrade: Öffne links „Biome"! 🧲', target = "biomeButton", arrowText = nil },
	{ text = 'Schalte eine zweite Zone frei: Kauf ein Biom im „Biome"-Menü! 🌍', target = "biomeButton", arrowText = nil },
	{ text = 'Versuch dein Glück: Drück unten auf „Fund suchen"! 🎲', target = "lootButton", arrowText = nil },
	{ text = "Sammle und verkaufe weiter, bis du 500 Gesamt-Energie hast! ⚡", target = "none", arrowText = nil },
}

local TutorialController = {}

local localPlayer = Players.LocalPlayer

local currentStep = 0
local advanceInFlight = false

-- Lokale Fortschritts-Sicht (der Server validiert autoritativ).
local collectedCount = 0
local soldOnce = false
local upgradeCount = 0
local biomeCount = 0
local lootCount = 0
local lifetimeEnergy = 0
local wieseSlot = 1 -- Slot der ersten eigenen Zone (für das Highlight)

local tutorialFrame: Frame? = nil
local stepLabel: TextLabel? = nil
local textLabel: TextLabel? = nil

local activeHighlights: { Instance } = {}
local activeTweens: { Tween } = {}

local tutorialActionFunction: RemoteFunction? = nil

local function addCorner(instance: Instance, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = instance
end

local function waitForPath(root: Instance, path: { string }, timeout: number): Instance?
	local current: Instance? = root
	for _, name in path do
		if current == nil then
			return nil
		end
		current = current:WaitForChild(name, timeout)
	end
	return current
end

local function clearHighlights()
	for _, tween in activeTweens do
		tween:Cancel()
	end
	table.clear(activeTweens)
	for _, instance in activeHighlights do
		instance:Destroy()
	end
	table.clear(activeHighlights)
end

-- Pulsierender Gold-Rahmen um einen GUI-Button.
local function highlightButton(button: Instance)
	if not button:IsA("GuiObject") then
		return
	end
	local stroke = Instance.new("UIStroke")
	stroke.Name = "TutorialPulse"
	stroke.Color = ACCENT_COLOR
	stroke.Thickness = 3
	stroke.Transparency = 0
	stroke.Parent = button

	local tween = TweenService:Create(stroke, PULSE_INFO, { Transparency = 0.75 })
	tween:Play()

	table.insert(activeHighlights, stroke)
	table.insert(activeTweens, tween)
end

-- Pulsierendes Highlight + Pfeil-Schild an einem Welt-Part der eigenen Insel.
local function highlightWorldPart(partName: string, arrowText: string?, step: number)
	task.spawn(function()
		local plots = Workspace:WaitForChild("PlanetPlots", 15)
		if plots == nil then
			return
		end
		local plot = plots:WaitForChild(`Plot_{localPlayer.UserId}`, 15)
		if plot == nil then
			return
		end
		local part = plot:FindFirstChild(partName)
		if part == nil or not part:IsA("BasePart") then
			return
		end
		if currentStep ~= step then
			return -- Schritt ist inzwischen weitergesprungen
		end

		local highlight = Instance.new("Highlight")
		highlight.Name = "TutorialPulse"
		highlight.FillColor = ACCENT_COLOR
		highlight.OutlineColor = TEXT_COLOR
		highlight.FillTransparency = 0.5
		highlight.Adornee = part
		highlight.Parent = part
		table.insert(activeHighlights, highlight)

		if arrowText ~= nil then
			local billboard = Instance.new("BillboardGui")
			billboard.Name = "TutorialArrow"
			billboard.Size = UDim2.new(0, 170, 0, 40)
			billboard.StudsOffset = Vector3.new(0, 8, 0)
			billboard.AlwaysOnTop = true
			billboard.Adornee = part
			billboard.Parent = part

			local arrow = Instance.new("TextLabel")
			arrow.BackgroundTransparency = 1
			arrow.Size = UDim2.new(1, 0, 1, 0)
			arrow.Font = Enum.Font.GothamBold
			arrow.TextSize = 18
			arrow.TextColor3 = ACCENT_COLOR
			arrow.TextStrokeTransparency = 0.4
			arrow.Text = arrowText
			arrow.Parent = billboard
			table.insert(activeHighlights, billboard)
		end

		local tween = TweenService:Create(highlight, PULSE_INFO, { FillTransparency = 0.85 })
		tween:Play()
		table.insert(activeTweens, tween)
	end)
end

-- Highlight passend zum Schritt setzen.
local function applyStepHighlight(step: number)
	clearHighlights()
	local def = STEPS[step]
	if def == nil then
		return
	end

	if def.target == "zone" then
		highlightWorldPart(`Zone_{wieseSlot}`, def.arrowText, step)
	elseif def.target == "sellpad" then
		highlightWorldPart("SellPad", def.arrowText, step)
	elseif def.target == "biomeButton" then
		task.spawn(function()
			local playerGui = localPlayer:WaitForChild("PlayerGui")
			local target = waitForPath(playerGui, { "PlanetForgeBuildUI", "ToggleBiomes" }, 10)
			if target ~= nil and currentStep == step then
				highlightButton(target)
			end
		end)
	elseif def.target == "lootButton" then
		task.spawn(function()
			local playerGui = localPlayer:WaitForChild("PlayerGui")
			local target = waitForPath(playerGui, { "PlanetForgeUI", "ButtonBar", "RollLoot" }, 10)
			if target ~= nil and currentStep == step then
				highlightButton(target)
			end
		end)
	end
	-- target == "none": Schritt 6 kommt ohne Highlight aus (freies Spielen).
end

local function buildUI()
	local playerGui = localPlayer:WaitForChild("PlayerGui")

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "PlanetForgeTutorial"
	screenGui.ResetOnSpawn = false
	screenGui.DisplayOrder = 20
	screenGui.Parent = playerGui

	local frame = Instance.new("Frame")
	frame.Name = "TutorialBox"
	frame.AnchorPoint = Vector2.new(0.5, 1)
	frame.Position = UDim2.new(0.5, 0, 1, -78)
	frame.Size = UDim2.new(0, 540, 0, 64)
	frame.BackgroundColor3 = PANEL_COLOR
	frame.Visible = false
	addCorner(frame, 12)
	local stroke = Instance.new("UIStroke")
	stroke.Color = ACCENT_COLOR
	stroke.Thickness = 2
	stroke.Parent = frame
	frame.Parent = screenGui

	local step = Instance.new("TextLabel")
	step.Name = "StepLabel"
	step.BackgroundTransparency = 1
	step.Position = UDim2.new(0, 14, 0, 8)
	step.Size = UDim2.new(0, 220, 0, 14)
	step.Font = Enum.Font.GothamBold
	step.TextSize = 11
	step.TextColor3 = ACCENT_COLOR
	step.TextXAlignment = Enum.TextXAlignment.Left
	step.Text = ""
	step.Parent = frame

	local text = Instance.new("TextLabel")
	text.Name = "TaskText"
	text.BackgroundTransparency = 1
	text.Position = UDim2.new(0, 14, 0, 24)
	text.Size = UDim2.new(1, -140, 0, 34)
	text.Font = Enum.Font.GothamMedium
	text.TextSize = 15
	text.TextColor3 = TEXT_COLOR
	text.TextXAlignment = Enum.TextXAlignment.Left
	text.TextWrapped = true
	text.Text = ""
	text.Parent = frame

	local skipButton = Instance.new("TextButton")
	skipButton.Name = "Skip"
	skipButton.AnchorPoint = Vector2.new(1, 0.5)
	skipButton.Position = UDim2.new(1, -10, 0.5, 0)
	skipButton.Size = UDim2.new(0, 108, 0, 30)
	skipButton.BackgroundColor3 = SKIP_COLOR
	skipButton.Font = Enum.Font.GothamMedium
	skipButton.TextSize = 12
	skipButton.TextColor3 = SUBTEXT_COLOR
	skipButton.Text = "Überspringen"
	addCorner(skipButton, 8)
	skipButton.Parent = frame

	skipButton.Activated:Connect(function()
		local remote = tutorialActionFunction
		if remote == nil then
			return
		end
		task.spawn(function()
			pcall(function()
				return remote:InvokeServer("skip")
			end)
		end)
	end)

	tutorialFrame = frame
	stepLabel = step
	textLabel = text
end

local function setStep(step: number)
	local wasActive = currentStep >= 1 and currentStep <= GameConfig.TUTORIAL_STEP_COUNT
	currentStep = step

	local frame = tutorialFrame
	if frame == nil then
		return
	end

	if step >= DONE_STEP or STEPS[step] == nil then
		clearHighlights()
		frame.Visible = false
		if wasActive then
			UIController.showToast("Tutorial abgeschlossen – viel Spaß auf deiner Insel! 🎉", "success")
		end
		return
	end

	local def = STEPS[step];
	(stepLabel :: TextLabel).Text = `TUTORIAL – SCHRITT {step} VON {GameConfig.TUTORIAL_STEP_COUNT}`;
	(textLabel :: TextLabel).Text = def.text
	frame.Visible = true
	applyStepHighlight(step)
end

-- Meldet dem Server, dass der aktuelle Schritt geschafft sein sollte.
local function requestAdvance()
	if advanceInFlight or currentStep < 1 or currentStep >= DONE_STEP then
		return
	end
	local remote = tutorialActionFunction
	if remote == nil then
		return
	end
	advanceInFlight = true
	task.spawn(function()
		pcall(function()
			return remote:InvokeServer("advance")
		end)
		advanceInFlight = false
	end)
end

-- Lokale Sicht der Schritt-Bedingung prüfen und ggf. "advance" anstoßen.
local function evaluateProgress()
	if currentStep == 1 and collectedCount >= 5 then
		requestAdvance()
	elseif currentStep == 2 and soldOnce then
		requestAdvance()
	elseif currentStep == 3 and upgradeCount >= 1 then
		requestAdvance()
	elseif currentStep == 4 and biomeCount >= 2 then
		requestAdvance()
	elseif currentStep == 5 and lootCount >= 1 then
		requestAdvance()
	elseif currentStep == 6 and lifetimeEnergy >= 500 then
		requestAdvance()
	end
end

function TutorialController.init()
	tutorialActionFunction = Remotes.getFunction("TutorialAction")

	buildUI()

	Remotes.getEvent("TutorialUpdated").OnClientEvent:Connect(function(step: any)
		if typeof(step) == "number" then
			setStep(step)
		end
	end)

	Remotes.getEvent("ObjectCollected").OnClientEvent:Connect(function()
		collectedCount += 1
		evaluateProgress()
	end)

	Remotes.getEvent("SoldBackpack").OnClientEvent:Connect(function()
		soldOnce = true
		evaluateProgress()
	end)

	Remotes.getEvent("LootObtained").OnClientEvent:Connect(function()
		lootCount += 1
		evaluateProgress()
	end)

	Remotes.getEvent("EnergyChanged").OnClientEvent:Connect(function(_energy: any, lifetime: any)
		if typeof(lifetime) == "number" then
			lifetimeEnergy = lifetime
			evaluateProgress()
		end
	end)

	Remotes.getEvent("UpgradesUpdated").OnClientEvent:Connect(function(levels: any)
		if typeof(levels) == "table" then
			local total = 0
			for _, level in levels :: { [any]: any } do
				if typeof(level) == "number" then
					total += level
				end
			end
			upgradeCount = total
			evaluateProgress()
		end
	end)

	Remotes.getEvent("PlanetUpdated").OnClientEvent:Connect(function(snapshot: any)
		if typeof(snapshot) ~= "table" or typeof(snapshot.biomes) ~= "table" then
			return
		end
		biomeCount = #(snapshot.biomes :: { any })
		-- Erste eigene Zone merken (Highlight für Schritt 1).
		for _, placed in snapshot.biomes :: { any } do
			if typeof(placed) == "table" and typeof(placed.slot) == "number" then
				wieseSlot = placed.slot
				break
			end
		end
		evaluateProgress()
	end)

	-- Falls das initiale TutorialUpdated verpasst wurde (Race beim Beitritt):
	-- aktuellen Stand aktiv abfragen.
	task.spawn(function()
		task.wait(2)
		if currentStep == 0 and tutorialActionFunction ~= nil then
			local ok, serverOk, step = pcall(function()
				return (tutorialActionFunction :: RemoteFunction):InvokeServer("status")
			end)
			if ok and serverOk == true and typeof(step) == "number" and currentStep == 0 then
				setStep(step)
			end
		end
	end)
end

return TutorialController
