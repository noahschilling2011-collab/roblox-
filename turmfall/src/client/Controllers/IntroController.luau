--!strict
-- IntroController: erklärt Turmfall beim ersten Beitritt (und jederzeit
-- über den ❓-Hilfe-Button). Kinderfreundlich: wenige, klare Schritte mit
-- Emojis statt Textwand - und ein großer "Los geht's!"-Button.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local PANEL_COLOR = Color3.fromRGB(28, 30, 40)
local TEXT_COLOR = Color3.fromRGB(235, 238, 245)
local ACCENT_COLOR = Color3.fromRGB(255, 190, 70)
local OK_COLOR = Color3.fromRGB(90, 190, 120)

local IntroController = {}

local panel: Frame? = nil

local function addCorner(instance: Instance, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = instance
end

local function buildUI()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "TurmfallIntro"
	screenGui.ResetOnSpawn = false
	screenGui.DisplayOrder = 60
	screenGui.Parent = playerGui

	-- ❓-Hilfe-Button (unter Skins und Shop), öffnet die Erklärung erneut.
	local helpButton = Instance.new("TextButton")
	helpButton.Name = "HelpToggle"
	helpButton.Position = UDim2.new(0, 12, 0, 96)
	helpButton.Size = UDim2.new(0, 110, 0, 36)
	helpButton.BackgroundColor3 = PANEL_COLOR
	helpButton.Font = Enum.Font.GothamBold
	helpButton.TextSize = 14
	helpButton.TextColor3 = TEXT_COLOR
	helpButton.Text = "❓ Hilfe"
	addCorner(helpButton, 10)
	helpButton.Parent = screenGui

	-- Erklärungs-Panel (beim Start sichtbar).
	local frame = Instance.new("Frame")
	frame.Name = "IntroPanel"
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.new(0.5, 0, 0.5, 0)
	frame.Size = UDim2.new(0, 560, 0, 420)
	frame.BackgroundColor3 = PANEL_COLOR
	frame.BackgroundTransparency = 0.03
	addCorner(frame, 14)
	local stroke = Instance.new("UIStroke")
	stroke.Color = ACCENT_COLOR
	stroke.Thickness = 2
	stroke.Parent = frame
	frame.Parent = screenGui
	panel = frame

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Position = UDim2.new(0, 0, 0, 14)
	title.Size = UDim2.new(1, 0, 0, 34)
	title.Font = Enum.Font.GothamBlack
	title.TextSize = 26
	title.TextColor3 = ACCENT_COLOR
	title.Text = "🏗️ TURMFALL – So geht's!"
	title.Parent = frame

	local lines = {
		"1️⃣  Alle 15 Sekunden bekommst du ein BAUTEIL (Hotbar unten, Tasten 1–3).",
		"2️⃣  Ziele mit der Maus und KLICKE zum Bauen – R dreht das Teil. Grüner Geist = passt, roter Geist sagt dir, warum nicht.",
		"3️⃣  Gebaut wird nur AN den Turm oder die Plattform – alle 12 Spieler bauen am SELBEN Turm!",
		"4️⃣  Je HÖHER deine Teile am Rundenende stehen, desto mehr Punkte. 🟢 Sprungpads + Gerüst-Ringe bringen dich nach oben – das Gerüst wächst mit, bau so hoch du willst!",
		"5️⃣  Aber Vorsicht: Wer den Turm zum EINSTURZ bringt, verliert ALLES – und das 💥 Schuld-Replay zeigt es jedem!",
		"⭐  Nebenbei: Katastrophen überstehen, Aufträge erfüllen, 🧱 Trümmer verdienen und im 🛒 Shop Skins holen.",
	}

	local list = Instance.new("Frame")
	list.BackgroundTransparency = 1
	list.Position = UDim2.new(0, 20, 0, 56)
	list.Size = UDim2.new(1, -40, 1, -130)
	list.Parent = frame
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 8)
	layout.Parent = list

	for order, text in lines do
		local line = Instance.new("TextLabel")
		line.LayoutOrder = order
		line.BackgroundTransparency = 1
		line.Size = UDim2.new(1, 0, 0, 44)
		line.Font = Enum.Font.GothamMedium
		line.TextSize = 14
		line.TextColor3 = TEXT_COLOR
		line.TextXAlignment = Enum.TextXAlignment.Left
		line.TextYAlignment = Enum.TextYAlignment.Top
		line.TextWrapped = true
		line.Text = text
		line.Parent = list
	end

	local startButton = Instance.new("TextButton")
	startButton.AnchorPoint = Vector2.new(0.5, 1)
	startButton.Position = UDim2.new(0.5, 0, 1, -16)
	startButton.Size = UDim2.new(0, 280, 0, 46)
	startButton.BackgroundColor3 = OK_COLOR
	startButton.Font = Enum.Font.GothamBold
	startButton.TextSize = 18
	startButton.TextColor3 = TEXT_COLOR
	startButton.Text = "✅ Verstanden – los geht's!"
	addCorner(startButton, 12)
	startButton.Parent = frame

	startButton.Activated:Connect(function()
		frame.Visible = false
	end)
	helpButton.Activated:Connect(function()
		frame.Visible = not frame.Visible
	end)

	-- Auf reinen Touch-Geräten die Tastatur-Hinweise umformulieren
	-- (Bauen/Drehen laufen dort über die 🧱/🔄-Buttons).
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		title.Text = "🏗️ TURMFALL – So geht's! (Touch)"
		for _, child in list:GetChildren() do
			if not child:IsA("TextLabel") then
				continue
			end
			if string.find(child.Text, "1️⃣") ~= nil then
				child.Text = "1️⃣  Alle 15 Sekunden bekommst du ein BAUTEIL (Hotbar unten antippen)."
			elseif string.find(child.Text, "2️⃣") ~= nil then
				child.Text =
					"2️⃣  Tippe zum Zielen, dann 🧱 BAUEN drücken – 🔄 dreht das Teil. Grün = passt, Rot sagt dir, warum nicht."
			end
		end
	end
end

function IntroController.init()
	buildUI()
end

return IntroController
