--!strict
-- HUD: Vorrat, Rate, Wins, naechstes Tor, Schild. Grosse Touch-Ziele,
-- damit es auf dem Handy bedienbar bleibt.

local Players = game:GetService("Players")

local Theme = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Theme"))
local Remotes = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Remotes"))

local HudController = {}

local player = Players.LocalPlayer

local function panel(parent: Instance, size: UDim2, position: UDim2): Frame
	local frame = Instance.new("Frame")
	frame.Size = size
	frame.Position = position
	frame.BackgroundColor3 = Theme.PANEL
	frame.BorderSizePixel = 0
	local corner = Instance.new("UICorner")
	corner.CornerRadius = Theme.CORNER
	corner.Parent = frame
	frame.Parent = parent
	return frame
end

local function label(parent: Instance, size: UDim2, position: UDim2, text: string): TextLabel
	local element = Instance.new("TextLabel")
	element.Size = size
	element.Position = position
	element.BackgroundTransparency = 1
	element.Font = Theme.FONT
	element.TextScaled = true
	element.TextColor3 = Theme.TEXT
	element.TextXAlignment = Enum.TextXAlignment.Left
	element.Text = text
	element.Parent = parent
	return element
end

-- Button mit dunklerer Unterkante (3D-Effekt).
local function button(parent: Instance, size: UDim2, position: UDim2, text: string, base: Color3, edge: Color3): TextButton
	local holder = Instance.new("Frame")
	holder.Size = size
	holder.Position = position
	holder.BackgroundColor3 = edge
	holder.BorderSizePixel = 0
	local holderCorner = Instance.new("UICorner")
	holderCorner.CornerRadius = Theme.CORNER
	holderCorner.Parent = holder

	local btn = Instance.new("TextButton")
	btn.Size = UDim2.new(1, 0, 1, -Theme.BUTTON_EDGE_HEIGHT)
	btn.Position = UDim2.new(0, 0, 0, 0)
	btn.BackgroundColor3 = base
	btn.BorderSizePixel = 0
	btn.Font = Theme.FONT
	btn.TextScaled = true
	btn.TextColor3 = Color3.new(1, 1, 1)
	btn.Text = text
	local btnCorner = Instance.new("UICorner")
	btnCorner.CornerRadius = Theme.CORNER
	btnCorner.Parent = btn
	btn.Parent = holder

	holder.Parent = parent
	return btn
end

function HudController.start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "KeycapHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true

	local top = panel(gui, UDim2.new(0, 320, 0, 150), UDim2.new(0, 16, 0, 16))
	local vorratLabel = label(top, UDim2.new(1, -20, 0, 44), UDim2.new(0, 12, 0, 8), "Vorrat 0")
	local rateLabel = label(top, UDim2.new(1, -20, 0, 30), UDim2.new(0, 12, 0, 54), "+0 / Sekunde")
	rateLabel.TextColor3 = Theme.TEXT_MUTED
	local winsLabel = label(top, UDim2.new(1, -20, 0, 36), UDim2.new(0, 12, 0, 88), "0 Wins")
	winsLabel.TextColor3 = Theme.GOLD_DARK
	local hintLabel = label(top, UDim2.new(1, -20, 0, 22), UDim2.new(0, 12, 0, 124), "")
	hintLabel.TextColor3 = Theme.TEXT_MUTED

	local shieldButton = button(
		gui,
		UDim2.new(0, 200, 0, 64),
		UDim2.new(0, 16, 0, 178),
		"Schild",
		Theme.BLUE,
		Theme.BLUE_DARK
	)

	-- Tutorial-Karte unten mittig: gut lesbar, weit weg von den Statuszahlen
	-- oben links. Der Abstand nach unten muss den Sprung-Knopf freilassen,
	-- der auf dem Handy unten rechts sitzt.
	local tutorialCard = panel(gui, UDim2.new(0.9, 0, 0, 84), UDim2.new(0.05, 0, 1, -200))
	tutorialCard.Visible = false
	local tutorialText = label(tutorialCard, UDim2.new(1, -24, 1, -16), UDim2.new(0, 12, 0, 8), "")
	tutorialText.TextXAlignment = Enum.TextXAlignment.Center
	tutorialText.TextWrapped = true
	tutorialText.TextScaled = false
	tutorialText.TextSize = 22

	local toast = label(gui, UDim2.new(0, 460, 0, 40), UDim2.new(0.5, -230, 0, 24), "")
	toast.TextXAlignment = Enum.TextXAlignment.Center
	toast.TextStrokeTransparency = 0.4
	toast.TextColor3 = Theme.TEXT

	gui.Parent = player:WaitForChild("PlayerGui")

	shieldButton.Activated:Connect(function()
		Remotes.get("ActivateShield"):FireServer()
	end)

	Remotes.get("StateChanged").OnClientEvent:Connect(function(state)
		vorratLabel.Text = ("Vorrat %d"):format(state.vorrat)
		rateLabel.Text = ("+%d / Sekunde   Tempo %d"):format(state.rate, math.floor(state.speed))
		winsLabel.Text = ("%d Wins"):format(state.wins)

		if state.carrying then
			hintLabel.Text = "Du traegst Beute - lauf nach Hause!"
			hintLabel.TextColor3 = Theme.RED
		elseif state.nextStage then
			hintLabel.Text = ("Stage %d ab %d Vorrat"):format(state.nextStage, state.nextStageVorrat)
			hintLabel.TextColor3 = Theme.TEXT_MUTED
		else
			hintLabel.Text = "Alle Tore offen - lauf zu Stage 3!"
			hintLabel.TextColor3 = Theme.GREEN_DARK
		end

		if state.tutorial then
			tutorialCard.Visible = true
			tutorialText.Text = ("Schritt %d: %s"):format(state.tutorial.step, state.tutorial.text)
		else
			tutorialCard.Visible = false
		end

		if state.shieldLeft > 0 then
			shieldButton.Text = ("Schild %ds"):format(state.shieldLeft)
		elseif state.shieldCooldown > 0 then
			shieldButton.Text = ("Laedt %ds"):format(state.shieldCooldown)
		else
			shieldButton.Text = "Schild"
		end
	end)

	local toastToken = 0
	Remotes.get("Notify").OnClientEvent:Connect(function(text)
		toast.Text = tostring(text)
		toastToken += 1
		local myToken = toastToken
		task.delay(3.5, function()
			if toastToken == myToken then
				toast.Text = ""
			end
		end)
	end)
end

return HudController
