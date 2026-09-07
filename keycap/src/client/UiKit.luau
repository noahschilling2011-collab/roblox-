--!strict
-- Bausteine fuer die Oberflaeche. Jeder Controller baut damit, keiner baut
-- eigene Rahmen oder Knoepfe - sonst laufen die Panels optisch auseinander.
--
-- Alle Werte kommen aus Theme. In dieser Datei steht keine Farbe und keine
-- Pixelzahl, die nicht von dort kommt.
--
-- Was Roblox-UI NICHT kann und was hier deshalb fehlt: kein Blur hinter
-- Elementen, kein Schatten als Effekt, kein Radialverlauf. Die Trennung
-- zwischen Panel und Welt macht der Rahmen, Tiefe macht die dunklere
-- Unterkante, Verlaeufe laufen linear ueber eine Achse.

local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Theme = require(Shared:WaitForChild("Theme"))

local UiKit = {}

local function round(instance: Instance, radius: UDim?)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = radius or Theme.CORNER
	corner.Parent = instance
end

-- Handy quer: schmaler Bildschirm, Daumen an beiden unteren Ecken. Dann
-- baut das HUD anders auf. Wird beim Start einmal gefragt.
function UiKit.compact(): boolean
	if not UserInputService.TouchEnabled then
		return false
	end
	local camera = workspace.CurrentCamera
	if not camera then
		return false
	end
	local viewport = camera.ViewportSize
	return viewport.X < Theme.COMPACT_MAX_WIDTH or viewport.Y < Theme.COMPACT_MAX_HEIGHT
end

-- Tausenderpunkte. "2.470" liest ein Kind schneller als "2470", und der
-- Vorrat ist im Normalfall vierstellig.
function UiKit.number(value: number): string
	local text = tostring(math.floor(math.abs(value)))
	local out = ""
	local count = 0
	for i = #text, 1, -1 do
		out = string.sub(text, i, i) .. out
		count += 1
		if count % 3 == 0 and i > 1 then
			out = "." .. out
		end
	end
	if value < 0 then
		return "-" .. out
	end
	return out
end

function UiKit.stroke(target: Instance, color: Color3, thickness: number?): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = thickness or 2
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = target
	return stroke
end

-- Linearer Verlauf ueber eine Achse. 90 = oben nach unten.
-- Dieselbe Farbe um GRADIENT_LIFT aufgehellt. Der Verlauf von hier nach
-- unten gibt einer Flaeche die Plastik, die Roblox-UI ohne Schatten fehlt.
function UiKit.lift(color: Color3): Color3
	local factor = 1 + Theme.GRADIENT_LIFT
	return Color3.new(
		math.min(1, color.R * factor),
		math.min(1, color.G * factor),
		math.min(1, color.B * factor)
	)
end

function UiKit.gradient(target: Instance, from: Color3, to: Color3, rotation: number?): UIGradient
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(from, to)
	gradient.Rotation = rotation or 90
	gradient.Parent = target
	return gradient
end

-- Creme-weisse Flaeche mit runden Ecken und Kante.
function UiKit.panel(parent: Instance, size: UDim2, position: UDim2): Frame
	local frame = Instance.new("Frame")
	frame.Size = size
	frame.Position = position
	frame.BackgroundColor3 = Theme.PANEL
	frame.BorderSizePixel = 0
	round(frame)
	-- Umrandung in Tinte statt zarter Kante: ohne sie schwimmt eine helle
	-- Flaeche im Bild, mit ihr steht sie darauf. Der groesste einzelne
	-- Unterschied zum bisherigen Pastell-Look.
	UiKit.stroke(frame, Theme.INK, Theme.OUTLINE_THICKNESS)
	frame.Parent = parent
	return frame
end

export type TextOptions = {
	size: UDim2,
	position: UDim2?,
	text: string?,
	textSize: number?,
	color: Color3?,
	align: Enum.TextXAlignment?,
	wrapped: boolean?,
	layoutOrder: number?,
}

function UiKit.text(parent: Instance, options: TextOptions): TextLabel
	local element = Instance.new("TextLabel")
	element.Size = options.size
	element.Position = options.position or UDim2.new(0, 0, 0, 0)
	element.BackgroundTransparency = 1
	element.Font = Theme.FONT
	element.TextScaled = false
	element.TextSize = options.textSize or Theme.TEXT_SIZE.BODY
	element.TextColor3 = options.color or Theme.TEXT
	element.TextXAlignment = options.align or Enum.TextXAlignment.Left
	element.TextWrapped = options.wrapped or false
	element.LayoutOrder = options.layoutOrder or 0
	element.Text = options.text or ""
	element.Parent = parent
	return element
end

export type ButtonOptions = {
	size: UDim2,
	position: UDim2?,
	text: string,
	base: Color3,
	edge: Color3,
	textColor: Color3?,
	textSize: number?,
	layoutOrder: number?,
}

-- Knopf mit dunklerer Unterkante. Beim Druecken rutscht die Oberseite auf
-- die Kante - dieselbe Bewegung, die ein echter Tastenanschlag macht.
-- Ohne diese Rueckmeldung fuehlt sich auf dem Handy nichts an, weil es
-- keinen Hover-Zustand gibt.
function UiKit.button(parent: Instance, options: ButtonOptions): TextButton
	local holder = Instance.new("Frame")
	holder.Size = options.size
	holder.Position = options.position or UDim2.new(0, 0, 0, 0)
	holder.BackgroundColor3 = options.edge
	holder.BorderSizePixel = 0
	holder.LayoutOrder = options.layoutOrder or 0
	round(holder)

	local button = Instance.new("TextButton")
	button.Size = UDim2.new(1, 0, 1, -Theme.BUTTON_EDGE_HEIGHT)
	button.Position = UDim2.new(0, 0, 0, 0)
	button.BackgroundColor3 = options.base
	button.BorderSizePixel = 0
	button.AutoButtonColor = false -- eigene Rueckmeldung statt Roblox-Graufilter
	button.Font = Theme.FONT
	button.TextScaled = false
	button.TextSize = options.textSize or Theme.TEXT_SIZE.BODY
	button.TextColor3 = options.textColor or Theme.INK
	button.Text = options.text
	round(button)
	-- Verlauf oben heller, dazu dieselbe Tinten-Umrandung wie die Panels.
	-- Zusammen mit der dunkleren Unterkante im Halter ergibt das drei
	-- Tiefenebenen ohne einen einzigen Schatten.
	UiKit.gradient(button, UiKit.lift(options.base), options.base)
	UiKit.stroke(button, Theme.INK, Theme.OUTLINE_THICKNESS)

	local raised = UDim2.new(0, 0, 0, 0)
	local pressed = UDim2.new(0, 0, 0, Theme.BUTTON_EDGE_HEIGHT)
	button.MouseButton1Down:Connect(function()
		button.Position = pressed
	end)
	button.MouseButton1Up:Connect(function()
		button.Position = raised
	end)
	-- Wer den Finger neben dem Knopf loslaesst, bekommt kein MouseButton1Up.
	button.MouseLeave:Connect(function()
		button.Position = raised
	end)

	button.Parent = holder
	holder.Parent = parent
	return button
end

-- Farbe eines bestehenden Knopfes umsetzen (Zustaende des Schild-Knopfes).
-- Die Kante sitzt im Halter darunter, deshalb beide.
function UiKit.setButtonColors(button: TextButton, base: Color3, edge: Color3)
	button.BackgroundColor3 = base
	local holder = button.Parent
	if holder and holder:IsA("Frame") then
		holder.BackgroundColor3 = edge
	end
	-- Ohne das behaelt ein umgefaerbter Knopf den Verlauf der alten Farbe.
	local gradient = button:FindFirstChildOfClass("UIGradient")
	if gradient then
		gradient.Color = ColorSequence.new(UiKit.lift(base), base)
	end
end

-- Untereinander-Layout mit gleichmaessigem Abstand und Innenrand.
function UiKit.stack(parent: Instance, padding: number?)
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, padding or Theme.SPACE.S)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = parent

	local inset = Instance.new("UIPadding")
	local space = UDim.new(0, Theme.SPACE.M)
	inset.PaddingTop = space
	inset.PaddingBottom = space
	inset.PaddingLeft = space
	inset.PaddingRight = space
	inset.Parent = parent

	return layout
end

-- Nur Layout, kein Innenrand - fuer Listen in einer Scrollflaeche und fuer
-- Reihen, die von links nach rechts laufen.
function UiKit.column(parent: Instance, padding: number?): UIListLayout
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, padding or Theme.SPACE.S)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = parent
	return layout
end

export type KeycapOptions = {
	size: UDim2,
	position: UDim2?,
	rarity: string,
	letter: string?,
	layoutOrder: number?,
}

-- Kleine Taste als Bild: Unterkante in der Kantenfarbe, Oberseite mit
-- linearem Verlauf, Buchstabe in der dunklen Seltenheitsfarbe. Gleiche
-- Bauweise wie die Knoepfe, damit der Laden zur Welt passt.
function UiKit.keycap(parent: Instance, options: KeycapOptions): Frame
	local base = Theme.RARITY_COLORS[options.rarity] or Theme.PANEL
	local edge = Theme.RARITY_EDGE[options.rarity] or Theme.PANEL_EDGE
	local ink = Theme.RARITY_INK[options.rarity] or Theme.TEXT
	local level = Theme.RARITY_RANK[options.rarity] or 1

	local holder = Instance.new("Frame")
	holder.Size = options.size
	holder.Position = options.position or UDim2.new(0, 0, 0, 0)
	holder.BackgroundColor3 = edge
	holder.BorderSizePixel = 0
	holder.LayoutOrder = options.layoutOrder or 0
	round(holder)

	local top = Instance.new("Frame")
	top.Size = UDim2.new(1, -Theme.SPACE.S, 1, -Theme.KEYCAP_EDGE)
	top.Position = UDim2.new(0, Theme.SPACE.XS, 0, 0)
	top.BackgroundColor3 = base
	top.BorderSizePixel = 0
	round(top)
	-- Derselbe Aufhell-Faktor wie bei den Knoepfen. Vorher stand hier ein
	-- eigener Wert (0.3 Richtung Weiss) - damit waren Tasten im Laden
	-- anders hell als Knoepfe daneben.
	UiKit.gradient(top, UiKit.lift(base), base, 90)
	top.Parent = holder

	local letter = Instance.new("TextLabel")
	letter.Size = UDim2.new(1, 0, 1, 0)
	letter.BackgroundTransparency = 1
	letter.Font = Theme.FONT
	letter.TextScaled = true
	letter.TextColor3 = ink
	letter.Text = options.letter or "A"
	letter.Parent = top

	-- Legendary bekommt zusaetzlich einen Rahmen mit Verlauf. Ein Rahmen
	-- darf einen Verlauf haben, eine Flaeche kein Leuchten - das ist in
	-- Roblox-UI der einzige Weg, "es leuchtet" zu sagen.
	if level >= 5 then
		local rim = UiKit.stroke(holder, edge, 3)
		UiKit.gradient(rim, Theme.GOLD, edge, 90)
	end

	holder.Parent = parent
	return holder
end

-- Fuenf Punkte, davon so viele gefuellt wie der Rang. Die Seltenheit muss
-- ohne Lesen erkennbar sein, und Farbe allein reicht auf einem billigen
-- Display in der Sonne nicht.
function UiKit.pips(parent: Instance, options: { rarity: string, position: UDim2 }): Frame
	local level = Theme.RARITY_RANK[options.rarity] or 1
	local fill = Theme.RARITY_EDGE[options.rarity] or Theme.PANEL_EDGE

	local row = Instance.new("Frame")
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(0, Theme.PIP * 5 + Theme.PIP_GAP * 4, 0, Theme.PIP)
	row.Position = options.position
	UiKit.column(row, Theme.PIP_GAP).FillDirection = Enum.FillDirection.Horizontal

	for index = 1, 5 do
		local pip = Instance.new("Frame")
		pip.Size = UDim2.new(0, Theme.PIP, 0, Theme.PIP)
		pip.BorderSizePixel = 0
		pip.LayoutOrder = index
		pip.BackgroundColor3 = if index <= level then fill else Theme.PANEL_EDGE
		pip.BackgroundTransparency = if index <= level then 0 else 0.55
		round(pip, UDim.new(0, Theme.PIP_CORNER))
		pip.Parent = row
	end

	row.Parent = parent
	return row
end

export type SpeedBarOptions = {
	size: UDim2,
	position: UDim2?,
	marks: { number },
}

-- Tempo-Balken mit Markierungen an den Stage-Toren: der Spieler soll
-- sehen, wie weit er kommt, ohne zwei Zahlen zu vergleichen.
function UiKit.speedBar(parent: Instance, options: SpeedBarOptions)
	local track = Instance.new("Frame")
	track.Size = options.size
	track.Position = options.position or UDim2.new(0, 0, 0, 0)
	track.BackgroundColor3 = Theme.PANEL_EDGE
	track.BorderSizePixel = 0
	track.ClipsDescendants = true
	round(track, UDim.new(1, 0))

	local fill = Instance.new("Frame")
	fill.Size = UDim2.new(0, 0, 1, 0)
	fill.BackgroundColor3 = Theme.GREEN
	fill.BorderSizePixel = 0
	round(fill, UDim.new(1, 0))
	UiKit.gradient(fill, Theme.GREEN, Theme.GOLD, 0)
	fill.Parent = track

	for _, fraction in options.marks do
		local mark = Instance.new("Frame")
		mark.Size = UDim2.new(0, Theme.BAR_MARK_WIDTH, 1, 0)
		mark.Position = UDim2.new(fraction, -Theme.BAR_MARK_WIDTH / 2, 0, 0)
		mark.BackgroundColor3 = Theme.TEXT
		mark.BorderSizePixel = 0
		mark.ZIndex = 2
		mark.Parent = track
	end

	track.Parent = parent

	local api = {}
	function api.set(fraction: number)
		TweenService:Create(fill, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = UDim2.new(math.clamp(fraction, 0, 1), 0, 1, 0),
		}):Play()
	end
	return api
end

-- Die Vorrat-Zahl muss beim Wachsen spuerbar sein: 90 ms hoch auf 1.08,
-- 130 ms zurueck. Kurz genug, dass es bei jedem Tick nicht nervt.
function UiKit.bump(target: GuiObject)
	local scale = Instance.new("UIScale")
	scale.Parent = target
	local up = TweenService:Create(scale, TweenInfo.new(0.09, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Scale = Theme.BUMP_SCALE,
	})
	local down = TweenService:Create(scale, TweenInfo.new(0.13, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		Scale = 1,
	})
	up.Completed:Connect(function()
		down:Play()
	end)
	return function()
		up:Play()
	end
end

-- Steigende Plus-Zahl: macht den Zuwachs sichtbar, ohne die grosse Zahl zu
-- stoeren. Steigt FLOAT_RISE Pixel in 700 ms und blendet dabei aus.
function UiKit.floatUp(parent: Instance, options: { text: string, position: UDim2, color: Color3? })
	local label = UiKit.text(parent, {
		size = UDim2.new(0, 140, 0, 26),
		position = options.position,
		text = options.text,
		textSize = Theme.TEXT_SIZE.BODY,
		color = options.color or Theme.GREEN_TEXT,
	})
	label.ZIndex = 5

	local target = UDim2.new(
		options.position.X.Scale,
		options.position.X.Offset,
		options.position.Y.Scale,
		options.position.Y.Offset - Theme.FLOAT_RISE
	)
	TweenService:Create(label, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = target,
		TextTransparency = 1,
	}):Play()
	task.delay(0.8, function()
		label:Destroy()
	end)
end

-- Endlos wandernder Balken. Auf jeder Onboarding-Karte muss sich etwas
-- bewegen - ein neuer Spieler darf nie auf einen Text starren, der
-- stillsteht.
function UiKit.crawler(parent: Instance, color: Color3): Frame
	local bar = Instance.new("Frame")
	bar.Size = UDim2.new(0, Theme.CRAWLER_WIDTH, 0, Theme.CRAWLER_HEIGHT)
	bar.Position = UDim2.new(0, 0, 1, -Theme.CRAWLER_HEIGHT)
	bar.BackgroundColor3 = color
	bar.BorderSizePixel = 0
	bar.Parent = parent

	TweenService:Create(
		bar,
		TweenInfo.new(2.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ Position = UDim2.new(1, -Theme.CRAWLER_WIDTH, 1, -Theme.CRAWLER_HEIGHT) }
	):Play()
	return bar
end

-- Schritt-Punkte des Onboardings: zeigt, dass es endlich ist.
function UiKit.dots(parent: Instance, options: { count: number, position: UDim2 })
	local row = Instance.new("Frame")
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(0, options.count * Theme.PIP + (options.count - 1) * Theme.PIP_GAP, 0, Theme.PIP)
	row.Position = options.position
	UiKit.column(row, Theme.PIP_GAP).FillDirection = Enum.FillDirection.Horizontal

	local dots: { Frame } = {}
	for index = 1, options.count do
		local dot = Instance.new("Frame")
		dot.Size = UDim2.new(0, Theme.PIP, 0, Theme.PIP)
		dot.BorderSizePixel = 0
		dot.LayoutOrder = index
		dot.BackgroundColor3 = Theme.PANEL_EDGE
		round(dot, UDim.new(1, 0))
		dot.Parent = row
		table.insert(dots, dot)
	end
	row.Parent = parent

	local api = {}
	function api.set(step: number)
		for index, dot in dots do
			dot.BackgroundColor3 = if index <= step then Theme.GREEN else Theme.PANEL_EDGE
		end
	end
	return api
end

-- Serverweite Zeile. Faehrt ein, bleibt BANNER_SECONDS, faehrt aus. Farbe
-- kommt aus der Seltenheit, damit man ohne Lesen weiss, wie fett der Klau
-- war.
function UiKit.banner(parent: Instance, position: UDim2)
	local hidden = UDim2.new(position.X.Scale, position.X.Offset, 0, -Theme.BANNER_HEIGHT)

	local holder = Instance.new("Frame")
	holder.Size = UDim2.new(0, Theme.BANNER_WIDTH, 0, Theme.BANNER_HEIGHT)
	holder.Position = hidden
	holder.BackgroundColor3 = Theme.GOLD
	holder.BorderSizePixel = 0
	holder.Visible = false
	holder.ZIndex = 4
	round(holder)
	local stroke = UiKit.stroke(holder, Theme.GOLD_DARK, 3)

	local label = UiKit.text(holder, {
		size = UDim2.new(1, -Theme.SPACE.XL, 1, 0),
		position = UDim2.new(0, Theme.SPACE.M, 0, 0),
		textSize = Theme.TEXT_SIZE.BODY,
		align = Enum.TextXAlignment.Center,
	})
	holder.Parent = parent

	local token = 0
	return function(text: string, rarity: string?)
		local base = if rarity then Theme.RARITY_COLORS[rarity] else nil
		local edge = if rarity then Theme.RARITY_EDGE[rarity] else nil
		local ink = if rarity then Theme.RARITY_INK[rarity] else nil
		holder.BackgroundColor3 = base or Theme.GOLD
		stroke.Color = edge or Theme.GOLD_DARK
		label.TextColor3 = ink or Theme.GOLD_TEXT
		label.Text = text

		token += 1
		local mine = token
		holder.Visible = true
		holder.Position = hidden
		TweenService:Create(holder, TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Position = position,
		}):Play()

		task.delay(Theme.BANNER_SECONDS, function()
			if token ~= mine then
				return
			end
			TweenService:Create(holder, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				Position = hidden,
			}):Play()
			task.delay(0.25, function()
				if token == mine then
					holder.Visible = false
				end
			end)
		end)
	end
end

-- Grosse Einblendung fuer Klau und Auszahlung.
--
-- Die Flaeche bleibt creme-weiss, die Farbe steckt in Kante, Kopfbalken
-- und Schrift: Rot als Textfarbe schafft auf dem Panel 4,9:1, dunkle
-- Schrift auf einer roten Flaeche nur 3,6:1. Rot ist im Theme
-- ausdruecklich "nur fuer Flaechen" - also traegt hier der Balken das Rot
-- und nicht der Text.
function UiKit.alert(parent: Instance)
	local shown = UDim2.new(0.5, -Theme.ALERT_WIDTH / 2, 0.2, 0)

	local card = UiKit.panel(parent, UDim2.new(0, Theme.ALERT_WIDTH, 0, Theme.ALERT_HEIGHT), shown)
	card.Visible = false
	card.ZIndex = 6
	card.ClipsDescendants = true
	-- Panel bringt seine Kante schon mit: umfaerben, nicht verdoppeln.
	local stroke = card:FindFirstChildOfClass("UIStroke") or UiKit.stroke(card, Theme.RED_DARK, 4)
	stroke.Color = Theme.RED_DARK
	stroke.Thickness = 4

	local bar = Instance.new("Frame")
	bar.Size = UDim2.new(1, 0, 0, Theme.ALERT_BAR)
	bar.BackgroundColor3 = Theme.RED
	bar.BorderSizePixel = 0
	bar.Parent = card

	local title = UiKit.text(card, {
		size = UDim2.new(1, -Theme.SPACE.XL, 0, 68),
		position = UDim2.new(0, Theme.SPACE.M, 0, Theme.SPACE.L),
		textSize = Theme.TEXT_SIZE.TITLE,
		color = Theme.RED_TEXT,
		align = Enum.TextXAlignment.Center,
	})
	local body = UiKit.text(card, {
		size = UDim2.new(1, -Theme.SPACE.XL, 0, 52),
		position = UDim2.new(0, Theme.SPACE.M, 0, 96),
		textSize = Theme.TEXT_SIZE.LEAD,
		align = Enum.TextXAlignment.Center,
		wrapped = true,
	})
	local bumpTitle = UiKit.bump(title)

	local token = 0
	return function(kind: string, titleText: string, bodyText: string)
		local cashout = kind == "cashout"
		stroke.Color = if cashout then Theme.GOLD_DARK else Theme.RED_DARK
		bar.BackgroundColor3 = if cashout then Theme.GOLD else Theme.RED
		title.TextColor3 = if cashout then Theme.GOLD_TEXT else Theme.RED_TEXT
		title.TextSize = if cashout then Theme.TEXT_SIZE.BLAST else Theme.TEXT_SIZE.TITLE
		title.Text = titleText
		body.Text = bodyText

		card.Visible = true
		card.Position = shown
		bumpTitle()

		-- Ruettler beim Klau: zwei kurze Ausschlaege, dann steht die Karte.
		if not cashout then
			local left = UDim2.new(0.5, -Theme.ALERT_WIDTH / 2 - Theme.SPACE.S, 0.2, 0)
			local right = UDim2.new(0.5, -Theme.ALERT_WIDTH / 2 + Theme.SPACE.S, 0.2, 0)
			task.spawn(function()
				for _, target in { left, right, shown } do
					TweenService:Create(card, TweenInfo.new(0.06, Enum.EasingStyle.Linear), {
						Position = target,
					}):Play()
					task.wait(0.07)
				end
			end)
		end

		token += 1
		local mine = token
		task.delay(Theme.ALERT_SECONDS, function()
			if token == mine then
				card.Visible = false
			end
		end)
	end
end

export type KeyRowOptions = {
	rarity: string,
	letter: string,
	title: string,
	rateText: string,
	priceText: string,
	layoutOrder: number?,
}

-- Eine Ladenzeile. Die Seltenheit steht viermal drin, ohne dass man ein
-- Wort lesen muss: Farbe, Rahmenstaerke, Punkte und Hoehe der Taste.
function UiKit.keyRow(parent: Instance, options: KeyRowOptions): TextButton
	local level = Theme.RARITY_RANK[options.rarity] or 1
	local edge = Theme.RARITY_EDGE[options.rarity] or Theme.PANEL_EDGE
	local pad = Theme.SPACE.M

	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, -(Theme.SCROLLBAR + Theme.SPACE.XS), 0, Theme.SHOP_ROW_HEIGHT)
	row.BackgroundColor3 = Theme.PANEL
	row.BorderSizePixel = 0
	row.LayoutOrder = options.layoutOrder or 0
	round(row)
	UiKit.stroke(row, edge, Theme.SHOP_ROW_STROKE + level)

	local thumbHeight = Theme.KEY_THUMB - (5 - level) * Theme.KEY_THUMB_STEP
	UiKit.keycap(row, {
		size = UDim2.new(0, Theme.KEY_THUMB, 0, thumbHeight),
		-- unten ausgerichtet: die Hoehenleiter der Seltenheiten ist im
		-- Laden dieselbe wie auf dem Plot.
		position = UDim2.new(0, pad, 0, Theme.SHOP_ROW_HEIGHT - pad - thumbHeight),
		rarity = options.rarity,
		letter = options.letter,
	})

	local textLeft = pad + Theme.KEY_THUMB + Theme.SPACE.M
	local textWidth = -(textLeft + Theme.SHOP_BUY_WIDTH + pad * 2)
	UiKit.text(row, {
		size = UDim2.new(1, textWidth, 0, 24),
		position = UDim2.new(0, textLeft, 0, Theme.SPACE.M),
		textSize = Theme.TEXT_SIZE.BODY,
		text = options.title,
	})
	UiKit.pips(row, {
		rarity = options.rarity,
		position = UDim2.new(0, textLeft, 0, 42),
	})
	UiKit.text(row, {
		size = UDim2.new(1, textWidth, 0, 20),
		position = UDim2.new(0, textLeft, 0, 58),
		textSize = Theme.TEXT_SIZE.SMALL,
		color = Theme.TEXT_MUTED,
		text = options.rateText,
	})

	local buy = UiKit.button(row, {
		size = UDim2.new(0, Theme.SHOP_BUY_WIDTH, 0, Theme.TOUCH_MIN),
		position = UDim2.new(1, -(Theme.SHOP_BUY_WIDTH + pad), 0, (Theme.SHOP_ROW_HEIGHT - Theme.TOUCH_MIN) / 2),
		text = options.priceText,
		base = Theme.GREEN,
		edge = Theme.GREEN_DARK,
	})

	row.Parent = parent
	return buy
end

-- Skaliert das ganze HUD fuer kleine Bildschirme. Ohne das ist das HUD auf
-- dem Handy zu gross und verdeckt das Spiel.
function UiKit.autoScale(gui: ScreenGui): UIScale
	local scale = Instance.new("UIScale")
	scale.Parent = gui

	local camera = workspace.CurrentCamera

	local function apply()
		local viewport = if camera then camera.ViewportSize else Vector2.new(Theme.SCALE_REFERENCE_WIDTH, 720)
		local factor = viewport.X / Theme.SCALE_REFERENCE_WIDTH
		scale.Scale = math.clamp(factor, Theme.SCALE_MIN, Theme.SCALE_MAX)
	end

	apply()
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(apply)
	end
	return scale
end

return UiKit
