--!strict
-- HUD: Vorrat, Rate, Wins, Tempo-Balken, Schild, Onboarding, Meldungen.
-- Baut ausschliesslich mit UiKit - hier steht keine eigene Farbe und keine
-- eigene Pixelzahl, die nicht aus Theme kommt.
--
-- Zwei Layouts, ein Codepfad:
--   breit    Statuskarte links unter dem Roblox-Menue, Knoepfe darunter
--   compact  Statuskarte als Streifen oben mittig, Knoepfe am rechten Rand
--
-- Reservierte Bildschirmbereiche, in die nichts gehoert: oben links der
-- Roblox-Menueknopf (deshalb HUD_TOP_INSET), oben rechts der Chat, unten
-- links der Stick und unten rechts der Sprung-Knopf (HUD_BOTTOM_INSET).
--
-- [BEKANNTE LUECKE] Das Layout wird beim Start einmal gewaehlt. Dreht ein
-- Spieler das Handy im Spiel, wechselt es erst beim naechsten Respawn.

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Theme = require(Shared:WaitForChild("Theme"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local EconomyConfig = require(Shared:WaitForChild("Config"):WaitForChild("EconomyConfig"))
local TutorialConfig = require(Shared:WaitForChild("Config"):WaitForChild("TutorialConfig"))
local UiKit = require(script.Parent.Parent.UiKit)

local HudController = {}

local player = Players.LocalPlayer

local TOAST_SECONDS = 3.5
local FLOAT_COOLDOWN = 0.6 -- so oft darf hoechstens eine +Zahl aufsteigen

-- Bruchteil der Tempo-Skala. Sie laeuft von BASE_WALK_SPEED bis
-- BASE_WALK_SPEED + MAX_SPEED_BONUS - dieselbe Rechnung fuer den Balken
-- und fuer die Markierungen der Tore, damit beide zusammenpassen.
local function speedFraction(speed: number): number
	return math.clamp((speed - EconomyConfig.BASE_WALK_SPEED) / EconomyConfig.MAX_SPEED_BONUS, 0, 1)
end

function HudController.start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "KeycapHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	UiKit.autoScale(gui)

	local compact = UiKit.compact()
	local margin = Theme.SPACE.L
	local pad = Theme.SPACE.M

	local width = if compact then Theme.HUD_COMPACT_WIDTH else Theme.HUD_PANEL_WIDTH
	local height = if compact then Theme.HUD_STATS_COMPACT_HEIGHT else Theme.HUD_STATS_HEIGHT
	local statsPosition = if compact
		then UDim2.new(0.5, -width / 2, 0, Theme.SPACE.S)
		else UDim2.new(0, margin, 0, Theme.HUD_TOP_INSET)

	local stats = UiKit.panel(gui, UDim2.new(0, width, 0, height), statsPosition)
	local inner = UDim2.new(1, -pad * 2, 0, 0)

	-- Zeilenraster der Statuskarte. Zwei Rhythmen, einer je Layout.
	local yLabel = if compact then 6 else 12
	local yVorrat = if compact then 24 else 34
	local yRate = if compact then 66 else 96
	local yBar = if compact then 86 else 168

	UiKit.text(stats, {
		size = inner + UDim2.new(0, 0, 0, 20),
		position = UDim2.new(0, pad, 0, yLabel),
		textSize = Theme.TEXT_SIZE.SMALL,
		color = Theme.TEXT_MUTED,
		text = "VORRAT",
	})

	-- Wins sind die zweite Zahl: klein, aber in Gold, damit sie nicht mit
	-- dem Vorrat konkurriert und trotzdem sofort gefunden wird.
	local winsLabel = UiKit.text(stats, {
		size = inner + UDim2.new(0, 0, 0, 30),
		position = UDim2.new(0, pad, 0, yLabel - Theme.SPACE.XS),
		textSize = if compact then Theme.TEXT_SIZE.BODY else Theme.TEXT_SIZE.TITLE,
		color = Theme.GOLD_TEXT,
		align = Enum.TextXAlignment.Right,
		text = "0 Wins",
	})

	-- Die groesste Zahl auf dem Bildschirm. Alles andere ordnet sich ihr
	-- unter - sie ist der Grund, warum jemand ueberhaupt hier steht.
	local vorratLabel = UiKit.text(stats, {
		size = inner + UDim2.new(0, 0, 0, (if compact then 44 else 60)),
		position = UDim2.new(0, pad, 0, yVorrat),
		textSize = if compact then Theme.TEXT_SIZE.HERO else Theme.TEXT_SIZE.DISPLAY,
		text = "0",
	})
	local bumpVorrat = UiKit.bump(vorratLabel)

	local rateLabel = UiKit.text(stats, {
		size = inner + UDim2.new(0, 0, 0, 20),
		position = UDim2.new(0, pad, 0, yRate),
		textSize = Theme.TEXT_SIZE.SMALL,
		color = Theme.TEXT_MUTED,
		text = "+0 pro Sekunde",
	})

	local tempoLabel: TextLabel? = nil
	local hintLabel: TextLabel? = nil

	if not compact then
		local divider = Instance.new("Frame")
		divider.Size = UDim2.new(1, -pad * 2, 0, 1)
		divider.Position = UDim2.new(0, pad, 0, 124)
		divider.BackgroundColor3 = Theme.PANEL_EDGE
		divider.BorderSizePixel = 0
		divider.Parent = stats

		tempoLabel = UiKit.text(stats, {
			size = inner + UDim2.new(0, 0, 0, 26),
			position = UDim2.new(0, pad, 0, 136),
			textSize = Theme.TEXT_SIZE.BODY,
			text = "TEMPO 16",
		})
		hintLabel = UiKit.text(stats, {
			size = inner + UDim2.new(0, 0, 0, 22),
			position = UDim2.new(0, pad, 0, 138),
			textSize = Theme.TEXT_SIZE.SMALL,
			color = Theme.TEXT_MUTED,
			align = Enum.TextXAlignment.Right,
			text = "",
		})
	end

	-- Eigene Flaeche fuer den Balken: die Bruchteile der Tor-Markierungen
	-- muessen sich auf die Balkenbreite beziehen, nicht auf die Karte.
	local barArea = Instance.new("Frame")
	barArea.BackgroundTransparency = 1
	barArea.Size = UDim2.new(1, -pad * 2, 0, (if compact then Theme.BAR_HEIGHT_COMPACT else 44))
	barArea.Position = UDim2.new(0, pad, 0, yBar)
	barArea.Parent = stats

	local marks: { number } = {}
	for _, gate in EconomyConfig.STAGE_GATES do
		table.insert(marks, speedFraction(gate))
	end

	local bar = UiKit.speedBar(barArea, {
		size = UDim2.new(1, 0, 0, (if compact then Theme.BAR_HEIGHT_COMPACT else Theme.BAR_HEIGHT)),
		marks = marks,
	})

	-- Beschriftung der Tore. Auf dem Handy fallen sie weg: dort tragen die
	-- Markierungen allein, sonst frisst die Zeile die halbe Karte.
	if not compact then
		for _, gate in EconomyConfig.STAGE_GATES do
			UiKit.text(barArea, {
				size = UDim2.new(0, 40, 0, 20),
				position = UDim2.new(speedFraction(gate), -20, 0, Theme.BAR_HEIGHT + Theme.SPACE.XS),
				textSize = Theme.TEXT_SIZE.SMALL,
				color = Theme.TEXT_MUTED,
				align = Enum.TextXAlignment.Center,
				text = tostring(gate),
			})
		end
	end

	-- Schild-Knopf. Drei Zustaende, drei Farben, jeweils dunkle Schrift.
	local buttonWidth = if compact then Theme.HUD_COMPACT_BUTTON_WIDTH else width
	local shieldPosition = if compact
		then UDim2.new(1, -(buttonWidth + pad), 0, Theme.HUD_TOP_INSET)
		else UDim2.new(0, margin, 0, Theme.HUD_TOP_INSET + Theme.HUD_STATS_HEIGHT + Theme.SPACE.S)

	local shieldButton = UiKit.button(gui, {
		size = UDim2.new(0, buttonWidth, 0, Theme.TOUCH_MIN),
		position = shieldPosition,
		text = "Schild",
		textSize = if compact then Theme.TEXT_SIZE.SMALL else Theme.TEXT_SIZE.BODY,
		base = Theme.BLUE,
		edge = Theme.BLUE_DARK,
	})

	-- Onboarding-Karte unten mittig, oberhalb der Daumen-Zone. Jede Karte
	-- traegt einen Satz, die Schritt-Punkte und einen wandernden Balken -
	-- ohne Bewegung liest ein neuer Spieler den Text nicht.
	local tutorialWidth = if compact then Theme.HUD_TUTORIAL_COMPACT_WIDTH else Theme.HUD_TUTORIAL_WIDTH
	local tutorialCard = UiKit.panel(
		gui,
		UDim2.new(0, tutorialWidth, 0, Theme.HUD_TUTORIAL_HEIGHT),
		UDim2.new(0.5, -tutorialWidth / 2, 1, -(Theme.HUD_TUTORIAL_HEIGHT + Theme.HUD_BOTTOM_INSET))
	)
	tutorialCard.Visible = false
	tutorialCard.ClipsDescendants = true

	local tutorialText = UiKit.text(tutorialCard, {
		size = UDim2.new(1, -Theme.SPACE.XL, 0, 52),
		position = UDim2.new(0, pad, 0, pad),
		textSize = Theme.TEXT_SIZE.LEAD,
		align = Enum.TextXAlignment.Center,
		wrapped = true,
	})
	local stepCount = #TutorialConfig.STEPS
	local dotsWidth = stepCount * Theme.PIP + (stepCount - 1) * Theme.PIP_GAP
	local tutorialDots = UiKit.dots(tutorialCard, {
		count = stepCount,
		position = UDim2.new(0.5, -dotsWidth / 2, 0, 68),
	})
	UiKit.crawler(tutorialCard, Theme.GOLD)

	-- Meldungen: kurze Zeile fuer den Spieler selbst, Banner fuer den
	-- ganzen Server, Karte fuer Klau und Auszahlung.
	local toastY = if compact then Theme.HUD_STATS_COMPACT_HEIGHT + Theme.SPACE.L else Theme.SPACE.XXL + Theme.SPACE.XL
	local toast = UiKit.text(gui, {
		size = UDim2.new(0, Theme.TOAST_WIDTH, 0, Theme.TOAST_HEIGHT),
		position = UDim2.new(0.5, -Theme.TOAST_WIDTH / 2, 0, toastY),
		textSize = Theme.TEXT_SIZE.LEAD,
		align = Enum.TextXAlignment.Center,
	})
	toast.TextStrokeTransparency = 0.4
	toast.ZIndex = 3

	-- Breit sitzt die serverweite Zeile oben mittig. Auf dem Handy liegt
	-- dort der Statusstreifen, also rutscht sie unter die Toast-Zeile.
	local bannerY = if compact then toastY + Theme.TOAST_HEIGHT + Theme.SPACE.S else Theme.SPACE.S
	local showBanner = UiKit.banner(gui, UDim2.new(0.5, -Theme.BANNER_WIDTH / 2, 0, bannerY))
	local showAlert = UiKit.alert(gui)

	gui.Parent = player:WaitForChild("PlayerGui")

	shieldButton.Activated:Connect(function()
		Remotes.get("ActivateShield"):FireServer()
	end)

	local lastVorrat = 0
	local lastFloat = 0

	Remotes.get("StateChanged").OnClientEvent:Connect(function(state)
		local vorrat = math.floor(state.vorrat)
		vorratLabel.Text = UiKit.number(vorrat)
		winsLabel.Text = ("%s Wins"):format(UiKit.number(state.wins))
		if compact and state.carrying then
			-- Im schmalen Layout gibt es keine Hinweiszeile: die Ratenzeile
			-- uebernimmt den einen Zustand, der wirklich draengt.
			rateLabel.Text = "BEUTE - lauf nach Hause!"
			rateLabel.TextColor3 = Theme.RED_TEXT
		elseif compact then
			rateLabel.Text = ("+%d pro Sekunde   ·   Tempo %d"):format(state.rate, math.floor(state.speed))
			rateLabel.TextColor3 = Theme.TEXT_MUTED
		else
			rateLabel.Text = ("+%d pro Sekunde"):format(state.rate)
		end

		-- Wachsen sichtbar machen: die Zahl selbst zuckt, daneben steigt
		-- der Zuwachs auf. Hoechstens alle FLOAT_COOLDOWN Sekunden, sonst
		-- flimmert die Karte.
		local gained = vorrat - lastVorrat
		if gained > 0 then
			bumpVorrat()
			local now = os.clock()
			if now - lastFloat >= FLOAT_COOLDOWN then
				lastFloat = now
				UiKit.floatUp(stats, {
					text = ("+%s"):format(UiKit.number(gained)),
					position = UDim2.new(1, -(140 + Theme.SPACE.M), 0, yVorrat),
				})
			end
		end
		lastVorrat = vorrat

		bar.set(speedFraction(state.speed))

		if tempoLabel then
			tempoLabel.Text = ("TEMPO %d"):format(math.floor(state.speed))
		end

		if hintLabel then
			if state.carrying then
				hintLabel.Text = "Beute! Lauf nach Hause"
				hintLabel.TextColor3 = Theme.RED_TEXT
			elseif state.nextStage then
				hintLabel.Text = ("Stage %d ab %s"):format(state.nextStage, UiKit.number(state.nextStageVorrat))
				hintLabel.TextColor3 = Theme.TEXT_MUTED
			else
				hintLabel.Text = "Alle Tore offen"
				hintLabel.TextColor3 = Theme.GREEN_TEXT
			end
		end

		if state.tutorial then
			tutorialCard.Visible = true
			tutorialText.Text = state.tutorial.text
			tutorialDots.set(state.tutorial.step)
		else
			tutorialCard.Visible = false
		end

		if state.shieldLeft > 0 then
			-- Laeuft: gruen. Gruen heisst im ganzen Spiel "das ist gut fuer
			-- dich", und geschuetzt zu sein ist der gute Zustand.
			shieldButton.Text = ("Schild %ds"):format(state.shieldLeft)
			UiKit.setButtonColors(shieldButton, Theme.GREEN, Theme.GREEN_DARK)
		elseif state.shieldCooldown > 0 then
			shieldButton.Text = ("Laedt %ds"):format(state.shieldCooldown)
			UiKit.setButtonColors(shieldButton, Theme.PANEL_EDGE, Theme.TEXT_MUTED)
		else
			shieldButton.Text = if compact then "Schild" else "Schild einschalten"
			UiKit.setButtonColors(shieldButton, Theme.BLUE, Theme.BLUE_DARK)
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

	Remotes.get("Alert").OnClientEvent:Connect(function(payload)
		if typeof(payload) ~= "table" then
			return
		end
		showAlert(tostring(payload.kind), tostring(payload.title), tostring(payload.body))
	end)

	Remotes.get("Announce").OnClientEvent:Connect(function(payload)
		if typeof(payload) ~= "table" then
			return
		end
		showBanner(tostring(payload.text), payload.rarity)
	end)
end

return HudController
