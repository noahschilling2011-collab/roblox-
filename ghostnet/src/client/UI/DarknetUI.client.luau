-- StarterPlayer/StarterPlayerScripts/UI/DarknetUI.client.luau
--!strict
-- GHOSTNET :: Der Darknet-Markt am eigenen Rechner.
--
-- Reine Anzeige. Der Client schickt beim Handeln ausschliesslich
-- { Action, GoodId, Amount } - nie einen Preis. Was etwas kostet, entscheidet
-- allein der Server.
--
-- Der Mini-Chart ist kein Deko-Element: ohne ihn ist jede Kaufentscheidung
-- ein Muenzwurf, und dann ist Handel kein Spiel, sondern Warten.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Geometry = require(ReplicatedStorage.Shared.Geometry)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local UITheme = require(ReplicatedStorage.Shared.UITheme)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local C = UITheme.Color

--==========================================================================
-- Zustand (Abschrift vom Server)
--==========================================================================

local market: { [string]: any } = { Goods = {}, Event = nil }
local stash: { [string]: number } = {}
local slots = { Used = 0, Total = Config.Market.SlotsBase }
local banked = 0
local unlocked = false
local hackOpen = false
local busy = false
local amount = 1

type Row = {
	Frame: Frame,
	Price: TextLabel,
	Trend: TextLabel,
	Owned: TextLabel,
	Chart: Frame,
	Bars: { Frame },
	Buy: TextButton,
	Sell: TextButton,
}

local rows: { [string]: Row } = {}

--==========================================================================
-- Aufbau
--==========================================================================

local gui = UITheme.Screen("GhostNetDarknet", 16)
gui.Parent = playerGui

local prompt = UITheme.Button({
	Name = "OpenPrompt",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -136),
	Size = UDim2.fromOffset(320, 46),
	BackgroundColor3 = C.Panel,
	BackgroundTransparency = 0.06,
	Text = "",
	Visible = false,
	Parent = gui,
})
UITheme.Corner(prompt, 4)
UITheme.Stroke(prompt, C.Cyan)

UITheme.Label({
	Name = "Caption",
	Text = "[E]  DARKNET OEFFNEN",
	TextColor3 = C.Cyan,
	TextSize = 14,
	TextXAlignment = Enum.TextXAlignment.Center,
	Size = UDim2.fromScale(1, 1),
	Parent = prompt,
})

local backdrop = UITheme.Frame({
	Name = "Backdrop",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.new(0, 0, 0),
	BackgroundTransparency = 1,
	Visible = false,
	Parent = gui,
})

local window = UITheme.Frame({
	Name = "Window",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.new(0.94, 0, 0.88, 0),
	BackgroundColor3 = C.Background,
	ClipsDescendants = true,
	Parent = backdrop,
})
UITheme.Corner(window, 5)
UITheme.Stroke(window, C.CyanDim)

local sizeConstraint = Instance.new("UISizeConstraint")
sizeConstraint.MaxSize = Vector2.new(780, 560)
sizeConstraint.MinSize = Vector2.new(320, 320)
sizeConstraint.Parent = window

local titleBar = UITheme.Frame({
	Name = "TitleBar",
	Size = UDim2.new(1, 0, 0, 34),
	BackgroundColor3 = C.Panel,
	Parent = window,
})

UITheme.Label({
	Name = "Title",
	Text = "GHOSTNET // DARKNET",
	TextColor3 = C.Cyan,
	TextSize = 14,
	Position = UDim2.new(0, 12, 0, 0),
	Size = UDim2.new(0.4, 0, 1, 0),
	Parent = titleBar,
})

local walletLabel = UITheme.Label({
	Name = "Wallet",
	Text = "",
	TextColor3 = C.Green,
	TextSize = 13,
	TextXAlignment = Enum.TextXAlignment.Right,
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -104, 0, 0),
	Size = UDim2.new(0.6, 0, 1, 0),
	Parent = titleBar,
})

local closeButton = UITheme.Button({
	Name = "Close",
	Text = "SCHLIESSEN",
	TextSize = 11,
	TextColor3 = C.Magenta,
	BackgroundColor3 = C.PanelLight,
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, -8, 0.5, 0),
	Size = UDim2.fromOffset(88, 24),
	Parent = titleBar,
})
UITheme.Corner(closeButton, 3)
UITheme.Stroke(closeButton, C.Magenta)

--== Kopfzeile: Event und Menge ============================================

local eventLabel = UITheme.Label({
	Name = "Event",
	Text = "",
	TextColor3 = C.Amber,
	TextSize = 13,
	Position = UDim2.new(0, 14, 0, 40),
	Size = UDim2.new(1, -180, 0, 18),
	Parent = window,
})

local amountHolder = UITheme.Frame({
	Name = "Amount",
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -14, 0, 38),
	Size = UDim2.fromOffset(150, 30),
	BackgroundTransparency = 1,
	Parent = window,
})

local amountLabel = UITheme.Label({
	Name = "Value",
	Text = "1",
	TextColor3 = C.Text,
	TextSize = 15,
	TextXAlignment = Enum.TextXAlignment.Center,
	Position = UDim2.new(0, 46, 0, 0),
	Size = UDim2.fromOffset(58, 30),
	Parent = amountHolder,
})

local function stepButton(text: string, x: number, delta: number): TextButton
	local b = UITheme.Button({
		Name = "Step" .. text,
		Text = text,
		TextSize = 18,
		TextColor3 = C.Cyan,
		BackgroundColor3 = C.PanelLight,
		Position = UDim2.new(0, x, 0, 0),
		Size = UDim2.fromOffset(44, 30),
		Parent = amountHolder,
	})
	UITheme.Corner(b, 3)
	UITheme.Stroke(b, C.Line)
	b.Activated:Connect(function()
		amount = math.clamp(amount + delta, 1, Config.Market.MaxPerTrade)
		amountLabel.Text = tostring(amount)
	end)
	return b
end

stepButton("-", 0, -1)
stepButton("+", 106, 1)

--== Warenliste ============================================================

local list = Instance.new("ScrollingFrame")
list.Name = "List"
list.BackgroundTransparency = 1
list.BorderSizePixel = 0
list.Position = UDim2.new(0, 14, 0, 72)
list.Size = UDim2.new(1, -28, 1, -110)
list.CanvasSize = UDim2.new()
list.AutomaticCanvasSize = Enum.AutomaticSize.Y
list.ScrollBarThickness = 4
list.ScrollBarImageColor3 = C.CyanDim
list.Parent = window

local listLayout = Instance.new("UIListLayout")
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Padding = UDim.new(0, 8)
listLayout.Parent = list

local statusLabel = UITheme.Label({
	Name = "Status",
	Text = "",
	TextColor3 = C.TextDim,
	TextSize = 12,
	Position = UDim2.new(0, 14, 1, -30),
	Size = UDim2.new(1, -28, 0, 18),
	Parent = window,
})

--==========================================================================
-- Eine Zeile je Ware
--==========================================================================

local trade: (string, string) -> ()

local CHART_BARS = 16

local function buildRow(goodId: string, name: string, blurb: string, order: number): Row
	local frame = UITheme.Frame({
		Name = goodId,
		Size = UDim2.new(1, -8, 0, 86),
		BackgroundColor3 = C.Panel,
		LayoutOrder = order,
		Parent = list,
	})
	UITheme.Corner(frame, 4)
	UITheme.Stroke(frame, C.Line)
	UITheme.Padding(frame, 10)

	UITheme.Label({
		Name = "Name",
		Text = name,
		TextColor3 = C.Cyan,
		TextSize = 15,
		Size = UDim2.new(0.42, 0, 0, 17),
		Parent = frame,
	})

	UITheme.Label({
		Name = "Blurb",
		Text = blurb,
		TextColor3 = C.TextDim,
		TextSize = 11,
		TextWrapped = true,
		Position = UDim2.new(0, 0, 0, 18),
		Size = UDim2.new(0.42, 0, 0, 26),
		Parent = frame,
	})

	local price = UITheme.Label({
		Name = "Price",
		Text = "",
		TextColor3 = C.Text,
		TextSize = 14,
		Position = UDim2.new(0, 0, 0, 46),
		Size = UDim2.new(0.42, 0, 0, 16),
		Parent = frame,
	})

	local owned = UITheme.Label({
		Name = "Owned",
		Text = "",
		TextColor3 = C.TextDim,
		TextSize = 11,
		Position = UDim2.new(0, 0, 1, -14),
		Size = UDim2.new(0.42, 0, 0, 14),
		Parent = frame,
	})

	-- Mini-Chart aus schmalen Balken. Kein Bild noetig, keine Asset-Id.
	local chart = UITheme.Frame({
		Name = "Chart",
		Position = UDim2.new(0.44, 0, 0, 2),
		Size = UDim2.new(0.24, 0, 1, -4),
		BackgroundColor3 = C.Background,
		Parent = frame,
	})
	UITheme.Corner(chart, 3)

	local bars: { Frame } = {}
	for i = 1, CHART_BARS do
		local bar = UITheme.Frame({
			Name = "B" .. i,
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new((i - 1) / CHART_BARS, 1, 1, -2),
			Size = UDim2.new(1 / CHART_BARS, -2, 0, 2),
			BackgroundColor3 = C.CyanDim,
			Parent = chart,
		})
		table.insert(bars, bar)
	end

	local trend = UITheme.Label({
		Name = "Trend",
		Text = "",
		TextColor3 = C.TextDim,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -2, 1, -16),
		Size = UDim2.new(1, -6, 0, 14),
		ZIndex = 2,
		Parent = chart,
	})

	local function actionButton(text: string, colour: Color3, y: number, action: string): TextButton
		local b = UITheme.Button({
			Name = action,
			Text = text,
			TextSize = 13,
			TextColor3 = colour,
			BackgroundColor3 = C.PanelLight,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, 0, 0, y),
			Size = UDim2.fromOffset(120, 30),
			Parent = frame,
		})
		UITheme.Corner(b, 3)
		UITheme.Stroke(b, colour)
		b.Activated:Connect(function()
			trade(action, goodId)
		end)
		return b
	end

	local buyButton = actionButton("KAUFEN", C.Cyan, 2, "BUY")
	local sellButton = actionButton("VERKAUFEN", C.Green, 36, "SELL")

	return {
		Frame = frame,
		Price = price,
		Trend = trend,
		Owned = owned,
		Chart = chart,
		Bars = bars,
		Buy = buyButton,
		Sell = sellButton,
	}
end

--==========================================================================
-- Anzeige
--==========================================================================

local function refresh()
	walletLabel.Text = ("BANK %d CRY   //   LAGER %d/%d"):format(banked, slots.Used, slots.Total)

	if market.Event then
		eventLabel.Text = market.Event.Text or ""
		eventLabel.TextColor3 = C.Amber
	else
		eventLabel.Text = "Markt ruhig."
		eventLabel.TextColor3 = C.TextDim
	end

	for index, entry in market.Goods do
		local row = rows[entry.Id]
		if not row then
			row = buildRow(entry.Id, entry.Name, entry.Blurb, index)
			rows[entry.Id] = row
		end

		local owned = stash[entry.Id] or 0
		row.Price.Text = ("KAUF %d   //   VERKAUF %d"):format(entry.Buy, entry.Sell)
		row.Owned.Text = ("im Lager: %d   //   Ausschussrisiko %d%%"):format(
			owned,
			math.floor(Config.GetFakeRisk(entry.Risk, slots.Tier or 1) * 100 + 0.5)
		)

		-- Chart: die letzten Faktoren auf die Balkenhoehe abbilden.
		local history = entry.History or {}
		local count = #history
		local lowest, highest = math.huge, -math.huge
		for _, value in history do
			lowest = math.min(lowest, value)
			highest = math.max(highest, value)
		end
		if count == 0 then
			lowest, highest = 0.9, 1.1
		end
		local span = math.max(0.02, highest - lowest)

		for i, bar in row.Bars do
			local historyIndex = count - CHART_BARS + i
			if historyIndex < 1 then
				bar.Visible = false
			else
				bar.Visible = true
				local value = history[historyIndex]
				local fraction = math.clamp((value - lowest) / span, 0, 1)
				bar.Size = UDim2.new(1 / CHART_BARS, -2, 0, 3 + fraction * 40)
				bar.BackgroundColor3 = if value >= 1 then C.Cyan else C.Magenta
			end
		end

		-- Trend gegenueber dem Basispreis, damit man "teuer" von "billig"
		-- unterscheiden kann, ohne zu rechnen.
		local percent = math.floor((entry.Factor - 1) * 100 + 0.5)
		if percent > 2 then
			row.Trend.Text = ("+%d%%"):format(percent)
			row.Trend.TextColor3 = C.Green
		elseif percent < -2 then
			row.Trend.Text = ("%d%%"):format(percent)
			row.Trend.TextColor3 = C.Magenta
		else
			row.Trend.Text = "stabil"
			row.Trend.TextColor3 = C.TextDim
		end

		local canBuy = not busy and banked >= entry.Buy * amount and slots.Used + amount <= slots.Total
		local canSell = not busy and owned >= amount
		row.Buy.TextColor3 = if canBuy then C.Cyan else C.TextDim
		row.Sell.TextColor3 = if canSell then C.Green else C.TextDim
	end
end

--==========================================================================
-- Handeln
--==========================================================================

local REASONS: { [string]: string } = {
	FUNDS = "Zu wenig auf der Bank",
	NO_SPACE = "Lager voll",
	NOT_OWNED = "So viel hast du nicht",
	BAD_AMOUNT = "Ungueltige Menge",
	UNKNOWN_GOOD = "Diese Ware gibt es nicht",
	LOCKED = "Darknet noch nicht freigeschaltet",
	LOADING = "Profil laedt noch",
	RATE = "Zu schnell hintereinander",
	INTERNAL = "Fehler auf dem Server",
}

local function say(text: string, colour: Color3)
	statusLabel.Text = text
	statusLabel.TextColor3 = colour
end

trade = function(action: string, goodId: string)
	if busy then
		return
	end
	busy = true
	refresh()

	task.spawn(function()
		local ok, response = pcall(function()
			return Remotes.Trade:InvokeServer({ Action = action, GoodId = goodId, Amount = amount })
		end)
		busy = false

		if not ok or typeof(response) ~= "table" then
			say("Handel fehlgeschlagen.", C.Magenta)
			refresh()
			return
		end

		if response.Ok then
			if action == "BUY" then
				say(("Gekauft: %d Stueck zu je %d CRY - %d gesamt."):format(
					response.Amount or 0,
					response.Unit or 0,
					response.Total or 0
				), C.Cyan)
			else
				local fakes = response.Fakes or 0
				if fakes > 0 then
					say(("Verkauft: %d von %d echt, %d Ausschuss. +%d CRY."):format(
						response.Sold or 0,
						response.Amount or 0,
						fakes,
						response.Total or 0
					), C.Amber)
				else
					say(("Verkauft: %d Stueck zu je %d CRY. +%d CRY."):format(
						response.Sold or 0,
						response.Unit or 0,
						response.Total or 0
					), C.Green)
				end
			end
			refresh()
			return
		end

		-- Klartext mit Zahl, wo es eine gibt.
		local text = REASONS[response.Reason] or "Abgelehnt"
		if response.Reason == "FUNDS" and response.Missing then
			text = ("Zu wenig auf der Bank - es fehlen %d CRY."):format(response.Missing)
		elseif response.Reason == "NO_SPACE" then
			text = ("Lager voll - noch %d von %d Plaetzen frei."):format(response.Free or 0, response.Slots or 0)
		elseif response.Reason == "NOT_OWNED" then
			text = ("Du hast nur %d davon."):format(response.Owned or 0)
		elseif response.Reason == "BAD_AMOUNT" then
			text = ("Menge muss zwischen 1 und %d liegen."):format(response.Max or Config.Market.MaxPerTrade)
		end
		say(text, C.Amber)
		refresh()
	end)
end

--==========================================================================
-- Oeffnen / Schliessen
--==========================================================================

local nearRig = false

local function setOpen(open: boolean)
	if open and (hackOpen or not unlocked) then
		return
	end
	backdrop.Visible = open
	if open then
		say("", C.TextDim)
		refresh()
		backdrop.BackgroundTransparency = 1
		window.Size = UDim2.new(0.94, 0, 0.3, 0)
		TweenService:Create(backdrop, UITheme.Tween.Normal, { BackgroundTransparency = 0.45 }):Play()
		TweenService:Create(window, UITheme.Tween.Slow, { Size = UDim2.new(0.94, 0, 0.88, 0) }):Play()
	end
end

local function toggle()
	setOpen(not backdrop.Visible)
end

prompt.Activated:Connect(toggle)
closeButton.Activated:Connect(function()
	setOpen(false)
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	if input.KeyCode == Enum.KeyCode.E and nearRig and not backdrop.Visible then
		setOpen(true)
	elseif input.KeyCode == Enum.KeyCode.Escape and backdrop.Visible then
		setOpen(false)
	end
end)

--==========================================================================
-- Server-Meldungen
--==========================================================================

Remotes.MarketSync.OnClientEvent:Connect(function(data: any)
	if typeof(data) ~= "table" or typeof(data.Goods) ~= "table" then
		return
	end
	market = data
	if backdrop.Visible then
		refresh()
	end
end)

Remotes.MarketEvent.OnClientEvent:Connect(function(data: any)
	if typeof(data) ~= "table" or typeof(data.Text) ~= "string" then
		return
	end
	eventLabel.Text = data.Text
	eventLabel.TextColor3 = C.Amber
	UITheme.Flash(eventLabel, C.Amber)
end)

Remotes.InventorySync.OnClientEvent:Connect(function(data: any)
	if typeof(data) ~= "table" then
		return
	end
	stash = {}
	if typeof(data.Stash) == "table" then
		for _, entry in data.Stash do
			if typeof(entry) == "table" and typeof(entry.Id) == "string" then
				stash[entry.Id] = entry.Amount or 0
			end
		end
	end
	slots.Used = tonumber(data.Used) or 0
	slots.Total = tonumber(data.Slots) or Config.Market.SlotsBase
	;(slots :: any).Tier = tonumber(data.Tier) or 1
	if backdrop.Visible then
		refresh()
	end
end)

Remotes.EconomySync.OnClientEvent:Connect(function(snapshot: any)
	if typeof(snapshot) ~= "table" then
		return
	end
	banked = snapshot.Banked or 0
	if backdrop.Visible then
		refresh()
	end
end)

Remotes.MissionSync.OnClientEvent:Connect(function(data: any)
	if typeof(data) ~= "table" or typeof(data.Unlocks) ~= "table" then
		return
	end
	unlocked = false
	for _, key in data.Unlocks do
		if key == Config.Market.RequiredUnlock then
			unlocked = true
			break
		end
	end
	if not unlocked and backdrop.Visible then
		setOpen(false)
	end
end)

Remotes.HackSessionStarted.OnClientEvent:Connect(function()
	hackOpen = true
	setOpen(false)
	prompt.Visible = false
end)

Remotes.HackResolved.OnClientEvent:Connect(function()
	hackOpen = false
end)

--==========================================================================
-- Naehe zum Rechner
--==========================================================================

local CollectionService = game:GetService("CollectionService")

local accumulator = 0
RunService.RenderStepped:Connect(function(dt)
	accumulator += dt
	if accumulator < 0.2 then
		return
	end
	accumulator = 0

	if hackOpen or not unlocked then
		nearRig = false
		prompt.Visible = false
		return
	end

	local position = Geometry.AlivePosition(player)
	if not position then
		nearRig = false
		prompt.Visible = false
		return
	end

	nearRig = false
	for _, inst in CollectionService:GetTagged(Config.ContactTag) do
		if inst:IsA("BasePart") and inst:IsDescendantOf(workspace) then
			if Geometry.SurfaceDistance(inst, position) <= Config.Mission.ContactRange then
				nearRig = true
				break
			end
		end
	end

	prompt.Visible = nearRig and not backdrop.Visible
end)
