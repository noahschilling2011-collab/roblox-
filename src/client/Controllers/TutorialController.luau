--!strict
-- TutorialController: geführte First-Time Experience.
--
-- Zeigt für neue Spieler vier Schritte mit Textbox und pulsierendem
-- Highlight auf dem jeweils richtigen Bedienelement:
--   1  Platziere deine erste Wiese  (Biome-Menü + leerer Slot pulsiert)
--   2  Sammle Energie ein           ("Energie sammeln"-Button pulsiert)
--   3  Kaufe ein Upgrade            (Biome-Menü pulsiert)
--   4  Suche deinen ersten Fund     ("Fund suchen"-Button pulsiert)
--
-- Der Fortschritt liegt im Profil (tutorialStep, TutorialService validiert
-- autoritativ); dieses Tutorial erscheint deshalb nur einmal. Zusätzlich
-- bekommen leere Slots und der Sammel-Button dezente Hinweis-Schilder,
-- solange der Spieler unter GameConfig.TUTORIAL_HINT_LIFETIME_LIMIT
-- Lifetime-Energie hat.

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
	COLLECT_AMOUNT: number,
	TUTORIAL_STEP_COUNT: number,
	TUTORIAL_HINT_LIFETIME_LIMIT: number,
}
local UIController = require(ControllersFolder:WaitForChild("UIController") :: ModuleScript) :: {
	showToast: (message: string, kind: string) -> (),
}

-- Farbschema (identisch zum UIController) plus Gold-Akzent für Highlights.
local PANEL_COLOR = Color3.fromRGB(30, 32, 44)
local STROKE_COLOR = Color3.fromRGB(70, 75, 100)
local TEXT_COLOR = Color3.fromRGB(235, 238, 245)
local SUBTEXT_COLOR = Color3.fromRGB(158, 164, 186)
local ACCENT_COLOR = Color3.fromRGB(214, 160, 72)
local SKIP_COLOR = Color3.fromRGB(60, 64, 84)

local DONE_STEP = GameConfig.TUTORIAL_STEP_COUNT + 1
local PULSE_INFO = TweenInfo.new(0.7, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)

type StepDef = {
	text: string,
	target: "biome" | "collect" | "loot",
	highlightSlot: boolean, -- zusätzlich einen leeren Slot in der Welt pulsieren lassen
}

local STEPS: { StepDef } = {
	{ text = 'Öffne links „Biome" und platziere deine erste Wiese! 🌿', target = "biome", highlightSlot = true },
	{ text = 'Super! Jetzt drücke unten auf „Energie sammeln". ⚡', target = "collect", highlightSlot = false },
	{ text = 'Kaufe ein Upgrade: Öffne „Biome" und drücke bei deiner Wiese auf „Upgrade"!', target = "biome", highlightSlot = false },
	{ text = 'Fast geschafft: Suche deinen ersten Fund! 🎁', target = "loot", highlightSlot = false },
}

local TutorialController = {}

local localPlayer = Players.LocalPlayer

local currentStep = 0
local advanceInFlight = false
local lifetimeEnergy = 0

-- Zwischenspeicher aus PlanetUpdated für Bedingungen und Slot-Suche.
local snapshotBiomeCount = 0
local snapshotMaxLevel = 0
local snapshotCollectibles = 0
local occupiedSlots: { [number]: boolean } = {}

-- UI-Referenzen (in buildUI gesetzt).
local tutorialFrame: Frame? = nil
local stepLabel: TextLabel? = nil
local textLabel: TextLabel? = nil

-- Aktive Highlight-Objekte des aktuellen Schritts (werden bei Wechsel entsorgt).
local activeHighlights: { Instance } = {}
local activeTweens: { Tween } = {}

-- Hinweis-Schilder (unabhängig vom Tutorial, solange Lifetime < Limit).
local slotHints: { [number]: BillboardGui } = {}
local collectHint: TextLabel? = nil
local hintsRemoved = false

local tutorialActionFunction: RemoteFunction? = nil

local function addCorner(instance: Instance, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = instance
end

-- Sucht ein GUI-Objekt über einen Pfad aus WaitForChild-Schritten (mit Timeout).
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

-- Pulsierendes Highlight + Pfeil-Schild über einem leeren Slot in der Welt.
local function highlightEmptySlot()
	task.spawn(function()
		local plots = Workspace:WaitForChild("PlanetPlots", 15)
		if plots == nil then
			return
		end
		local plot = plots:WaitForChild(`Plot_{localPlayer.UserId}`, 15)
		if plot == nil then
			return
		end

		-- Ersten freien Slot laut Snapshot nehmen (Standard: Slot 1).
		local slotNumber = 1
		for candidate = 1, GameConfig.PLANET_SLOTS do
			if not occupiedSlots[candidate] then
				slotNumber = candidate
				break
			end
		end
		local slotPart = plot:FindFirstChild(`Slot_{slotNumber}`)
		if slotPart == nil or not slotPart:IsA("BasePart") then
			return
		end

		-- Falls der Schritt inzwischen weitergesprungen ist: nichts anheften.
		if currentStep ~= 1 then
			return
		end

		local highlight = Instance.new("Highlight")
		highlight.Name = "TutorialSlotPulse"
		highlight.FillColor = ACCENT_COLOR
		highlight.OutlineColor = TEXT_COLOR
		highlight.FillTransparency = 0.4
		highlight.Adornee = slotPart
		highlight.Parent = slotPart

		local billboard = Instance.new("BillboardGui")
		billboard.Name = "TutorialSlotArrow"
		billboard.Size = UDim2.new(0, 140, 0, 40)
		billboard.StudsOffset = Vector3.new(0, 6, 0)
		billboard.AlwaysOnTop = true
		billboard.Adornee = slotPart
		billboard.Parent = slotPart

		local arrow = Instance.new("TextLabel")
		arrow.BackgroundTransparency = 1
		arrow.Size = UDim2.new(1, 0, 1, 0)
		arrow.Font = Enum.Font.GothamBold
		arrow.TextSize = 18
		arrow.TextColor3 = ACCENT_COLOR
		arrow.TextStrokeTransparency = 0.4
		arrow.Text = "⬇ Hier bauen!"
		arrow.Parent = billboard

		local tween = TweenService:Create(highlight, PULSE_INFO, { FillTransparency = 0.85 })
		tween:Play()

		table.insert(activeHighlights, highlight)
		table.insert(activeHighlights, billboard)
		table.insert(activeTweens, tween)
	end)
end

-- Setzt das Highlight passend zum Schritt (Buttons liegen in anderen ScreenGuis).
local function applyStepHighlight(step: number)
	clearHighlights()
	local def = STEPS[step]
	if def == nil then
		return
	end

	task.spawn(function()
		local playerGui = localPlayer:WaitForChild("PlayerGui")
		local target: Instance? = nil
		if def.target == "biome" then
			target = waitForPath(playerGui, { "PlanetForgeBuildUI", "ToggleBiomes" }, 10)
		elseif def.target == "collect" then
			target = waitForPath(playerGui, { "PlanetForgeUI", "ButtonBar", "CollectEnergy" }, 10)
		elseif def.target == "loot" then
			target = waitForPath(playerGui, { "PlanetForgeUI", "ButtonBar", "RollLoot" }, 10)
		end
		-- Nur anheften, wenn der Schritt noch aktuell ist (WaitForChild kann dauern).
		if target ~= nil and currentStep == step then
			highlightButton(target)
		end
	end)

	if def.highlightSlot then
		highlightEmptySlot()
	end
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
	frame.Size = UDim2.new(0, 520, 0, 64)
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
	step.Size = UDim2.new(0, 200, 0, 14)
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
			UIController.showToast("Tutorial abgeschlossen – viel Spaß beim Bauen! 🎉", "success")
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

-- Prüft die lokale Sicht der Schritt-Bedingung und stößt ggf. "advance" an.
local function evaluateProgress()
	if currentStep == 1 and snapshotBiomeCount >= 1 then
		requestAdvance()
	elseif currentStep == 2 and lifetimeEnergy >= GameConfig.COLLECT_AMOUNT then
		requestAdvance()
	elseif currentStep == 3 and snapshotMaxLevel >= 2 then
		requestAdvance()
	elseif currentStep == 4 and snapshotCollectibles >= 1 then
		requestAdvance()
	end
end

-- Dezente Hinweis-Schilder über leeren Slots (nur für Einsteiger).
local function updateSlotHints()
	if hintsRemoved then
		return
	end

	task.spawn(function()
		local plots = Workspace:FindFirstChild("PlanetPlots")
		local plot = if plots ~= nil then plots:FindFirstChild(`Plot_{localPlayer.UserId}`) else nil
		if plot == nil then
			return
		end

		for slotNumber = 1, GameConfig.PLANET_SLOTS do
			local shouldShow = not occupiedSlots[slotNumber]
			local existing = slotHints[slotNumber]

			if shouldShow and existing == nil then
				local slotPart = plot:FindFirstChild(`Slot_{slotNumber}`)
				if slotPart ~= nil and slotPart:IsA("BasePart") then
					local billboard = Instance.new("BillboardGui")
					billboard.Name = "SlotHint"
					billboard.Size = UDim2.new(0, 90, 0, 22)
					billboard.StudsOffset = Vector3.new(0, 2.5, 0)
					billboard.MaxDistance = 120
					billboard.Adornee = slotPart

					local label = Instance.new("TextLabel")
					label.BackgroundTransparency = 1
					label.Size = UDim2.new(1, 0, 1, 0)
					label.Font = Enum.Font.GothamMedium
					label.TextSize = 12
					label.TextColor3 = SUBTEXT_COLOR
					label.TextTransparency = 0.25
					label.TextStrokeTransparency = 0.7
					label.Text = "Bau-Platz"
					label.Parent = billboard

					billboard.Parent = slotPart
					slotHints[slotNumber] = billboard
				end
			elseif not shouldShow and existing ~= nil then
				existing:Destroy()
				slotHints[slotNumber] = nil
			end
		end
	end)
end

local function removeAllHints()
	if hintsRemoved then
		return
	end
	hintsRemoved = true
	for slotNumber, billboard in slotHints do
		billboard:Destroy()
		slotHints[slotNumber] = nil
	end
	if collectHint ~= nil then
		collectHint:Destroy()
		collectHint = nil
	end
end

-- Kleines "+5 ⚡"-Schild im Sammel-Button für Einsteiger.
local function attachCollectHint()
	task.spawn(function()
		local playerGui = localPlayer:WaitForChild("PlayerGui")
		local button = waitForPath(playerGui, { "PlanetForgeUI", "ButtonBar", "CollectEnergy" }, 10)
		if button == nil or hintsRemoved then
			return
		end

		local hint = Instance.new("TextLabel")
		hint.Name = "BeginnerHint"
		hint.BackgroundTransparency = 1
		hint.AnchorPoint = Vector2.new(0.5, 1)
		hint.Position = UDim2.new(0.5, 0, 1, -1)
		hint.Size = UDim2.new(1, 0, 0, 12)
		hint.Font = Enum.Font.GothamMedium
		hint.TextSize = 10
		hint.TextColor3 = SUBTEXT_COLOR
		hint.Text = `gibt +{GameConfig.COLLECT_AMOUNT} ⚡`
		hint.Parent = button

		collectHint = hint
	end)
end

function TutorialController.init()
	tutorialActionFunction = Remotes.getFunction("TutorialAction")

	buildUI()
	attachCollectHint()

	Remotes.getEvent("TutorialUpdated").OnClientEvent:Connect(function(step: any)
		if typeof(step) == "number" then
			setStep(step)
		end
	end)

	Remotes.getEvent("PlanetUpdated").OnClientEvent:Connect(function(snapshot: any)
		if typeof(snapshot) ~= "table" or typeof(snapshot.biomes) ~= "table" then
			return
		end
		snapshotBiomeCount = 0
		snapshotMaxLevel = 0
		table.clear(occupiedSlots)
		for _, placed in snapshot.biomes :: { any } do
			if typeof(placed) == "table" and typeof(placed.slot) == "number" then
				snapshotBiomeCount += 1
				occupiedSlots[placed.slot] = true
				if typeof(placed.level) == "number" and placed.level > snapshotMaxLevel then
					snapshotMaxLevel = placed.level
				end
			end
		end
		snapshotCollectibles = if typeof(snapshot.collectibles) == "table" then #(snapshot.collectibles :: { any }) else 0

		updateSlotHints()
		evaluateProgress()
	end)

	Remotes.getEvent("EnergyChanged").OnClientEvent:Connect(function(_newEnergy: any, lifetime: any)
		if typeof(lifetime) ~= "number" then
			return
		end
		lifetimeEnergy = lifetime
		if lifetimeEnergy >= GameConfig.TUTORIAL_HINT_LIFETIME_LIMIT then
			removeAllHints()
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
