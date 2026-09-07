--!strict
-- HUD: Vorrat, Rate, Wins, naechstes Tor, Schild, Tutorial-Karte.
-- Baut ausschliesslich mit UiKit - hier steht keine eigene Farbe und
-- keine eigene Pixelzahl.

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Theme = require(Shared:WaitForChild("Theme"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local UiKit = require(script.Parent.Parent.UiKit)

local HudController = {}

local player = Players.LocalPlayer

local TOAST_SECONDS = 3.5

function HudController.start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "KeycapHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	UiKit.autoScale(gui)

	local margin = Theme.SPACE.L
	local width = Theme.HUD_PANEL_WIDTH

	-- Statuskarte oben links. Die Zeilen sind nach Wichtigkeit gestaffelt:
	-- Vorrat ist die Zahl, auf die der Spieler schaut, Wins die zweite.
	local stats = UiKit.panel(gui, UDim2.new(0, width, 0, Theme.HUD_STATS_HEIGHT), UDim2.new(0, margin, 0, margin))
	local inner = UDim2.new(1, -Theme.SPACE.XL, 0, 0)
	local left = Theme.SPACE.M

	local vorratLabel = UiKit.text(stats, {
		size = inner + UDim2.new(0, 0, 0, 44),
		position = UDim2.new(0, left, 0, Theme.SPACE.S),
		textSize = Theme.TEXT_SIZE.HERO,
		text = "Vorrat 0",
	})
	local rateLabel = UiKit.text(stats, {
		size = inner + UDim2.new(0, 0, 0, 24),
		position = UDim2.new(0, left, 0, 54),
		textSize = Theme.TEXT_SIZE.SMALL,
		color = Theme.TEXT_MUTED,
		text = "+0 pro Sekunde",
	})
	local winsLabel = UiKit.text(stats, {
		size = inner + UDim2.new(0, 0, 0, 34),
		position = UDim2.new(0, left, 0, 84),
		textSize = Theme.TEXT_SIZE.TITLE,
		color = Theme.GOLD_TEXT,
		text = "0 Wins",
	})
	local hintLabel = UiKit.text(stats, {
		size = inner + UDim2.new(0, 0, 0, 22),
		position = UDim2.new(0, left, 0, 124),
		textSize = Theme.TEXT_SIZE.SMALL,
		color = Theme.TEXT_MUTED,
		text = "",
	})

	local shieldButton = UiKit.button(gui, {
		size = UDim2.new(0, width, 0, Theme.TOUCH_MIN),
		position = UDim2.new(0, margin, 0, Theme.HUD_STATS_HEIGHT + margin + Theme.SPACE.S),
		text = "Schild",
		base = Theme.BLUE,
		edge = Theme.BLUE_DARK,
	})

	-- Tutorial-Karte unten mittig. Der Abstand nach unten laesst den
	-- Sprung-Knopf frei, der auf dem Handy unten rechts sitzt.
	local tutorialCard = UiKit.panel(gui, UDim2.new(0.9, 0, 0, 84), UDim2.new(0.05, 0, 1, -200))
	tutorialCard.Visible = false
	local tutorialText = UiKit.text(tutorialCard, {
		size = UDim2.new(1, -Theme.SPACE.XL, 1, -Theme.SPACE.L),
		position = UDim2.new(0, Theme.SPACE.M, 0, Theme.SPACE.S),
		textSize = Theme.TEXT_SIZE.LEAD,
		align = Enum.TextXAlignment.Center,
		wrapped = true,
	})

	local toast = UiKit.text(gui, {
		size = UDim2.new(0, 520, 0, 40),
		position = UDim2.new(0.5, -260, 0, Theme.SPACE.XL),
		textSize = Theme.TEXT_SIZE.LEAD,
		align = Enum.TextXAlignment.Center,
	})
	toast.TextStrokeTransparency = 0.4

	gui.Parent = player:WaitForChild("PlayerGui")

	shieldButton.Activated:Connect(function()
		Remotes.get("ActivateShield"):FireServer()
	end)

	Remotes.get("StateChanged").OnClientEvent:Connect(function(state)
		vorratLabel.Text = ("Vorrat %d"):format(state.vorrat)
		rateLabel.Text = ("+%d pro Sekunde   ·   Tempo %d"):format(state.rate, math.floor(state.speed))
		winsLabel.Text = ("%d Wins"):format(state.wins)

		if state.carrying then
			hintLabel.Text = "Du traegst Beute - lauf nach Hause!"
			hintLabel.TextColor3 = Theme.RED_TEXT
		elseif state.nextStage then
			hintLabel.Text = ("Stage %d ab %d Vorrat"):format(state.nextStage, state.nextStageVorrat)
			hintLabel.TextColor3 = Theme.TEXT_MUTED
		else
			hintLabel.Text = "Alle Tore offen - lauf zu Stage 3!"
			hintLabel.TextColor3 = Theme.GREEN_TEXT
		end

		if state.tutorial then
			tutorialCard.Visible = true
			tutorialText.Text = ("Schritt %d: %s"):format(state.tutorial.step, state.tutorial.text)
		else
			tutorialCard.Visible = false
		end

		if state.shieldLeft > 0 then
			shieldButton.Text = ("Schild aktiv - %ds"):format(state.shieldLeft)
		elseif state.shieldCooldown > 0 then
			shieldButton.Text = ("Schild laedt - %ds"):format(state.shieldCooldown)
		else
			shieldButton.Text = "Schild einschalten"
		end
	end)

	local toastToken = 0
	Remotes.get("Notify").OnClientEvent:Connect(function(text)
		toast.Text = tostring(text)
		toastToken += 1
		local myToken = toastToken
		task.delay(TOAST_SECONDS, function()
			if toastToken == myToken then
				toast.Text = ""
			end
		end)
	end)
end

return HudController
