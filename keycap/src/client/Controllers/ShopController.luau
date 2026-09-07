--!strict
-- Laden: Tasten und Steckplaetze kaufen. Die Preise hier sind nur Anzeige -
-- was ein Kauf kostet, entscheidet allein der Server.
--
-- Das Gestaltungsproblem dieser Liste: die Seltenheit muss auf einen Blick
-- erkennbar sein, ohne dass man liest. Deshalb traegt sie vier Signale
-- gleichzeitig (in UiKit.keyRow): Farbe, Rahmenstaerke, Zahl der Punkte
-- und Hoehe der Taste. Farbe allein reicht nicht - das Spiel wird auf
-- billigen Displays in der Sonne gespielt.

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Theme = require(Shared:WaitForChild("Theme"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local EconomyConfig = require(Shared:WaitForChild("Config"):WaitForChild("EconomyConfig"))
local WorldConfig = require(Shared:WaitForChild("Config"):WaitForChild("WorldConfig"))
local UiKit = require(script.Parent.Parent.UiKit)

local ShopController = {}

local player = Players.LocalPlayer

function ShopController.start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "KeycapShop"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	UiKit.autoScale(gui)

	local compact = UiKit.compact()
	local margin = Theme.SPACE.L
	local pad = Theme.SPACE.M

	-- Sitzt in derselben Spalte wie das HUD: breit unter dem Schild-Knopf,
	-- auf dem Handy als zweiter Knopf am rechten Rand.
	local buttonWidth = if compact then Theme.HUD_COMPACT_BUTTON_WIDTH else Theme.HUD_PANEL_WIDTH
	local shieldBottom = Theme.HUD_TOP_INSET + Theme.HUD_STATS_HEIGHT + Theme.SPACE.S + Theme.TOUCH_MIN
	local openPosition = if compact
		then UDim2.new(1, -(buttonWidth + pad), 0, Theme.HUD_TOP_INSET + Theme.TOUCH_MIN + Theme.SPACE.S)
		else UDim2.new(0, margin, 0, shieldBottom + Theme.SPACE.S)

	local openButton = UiKit.button(gui, {
		size = UDim2.new(0, buttonWidth, 0, Theme.TOUCH_MIN),
		position = openPosition,
		text = "Laden",
		textSize = if compact then Theme.TEXT_SIZE.SMALL else Theme.TEXT_SIZE.BODY,
		base = Theme.GREEN,
		edge = Theme.GREEN_DARK,
	})

	-- Hoehe nicht ausrechnen, sondern vom Layout bestimmen lassen - sonst
	-- passt sie nicht mehr, sobald eine Seltenheit dazukommt. Oben
	-- verankert, damit das Panel auf 360 px Hoehe nicht unten rausfaellt.
	local panelWidth = if compact then Theme.HUD_TUTORIAL_COMPACT_WIDTH else Theme.SHOP_PANEL_WIDTH
	local panel = UiKit.panel(
		gui,
		UDim2.new(0, panelWidth, 0, 0),
		UDim2.new(0.5, -panelWidth / 2, 0, Theme.SPACE.L)
	)
	panel.AutomaticSize = Enum.AutomaticSize.Y
	panel.Visible = false
	panel.ZIndex = 2
	UiKit.stack(panel)

	UiKit.text(panel, {
		size = UDim2.new(1, 0, 0, 38),
		textSize = Theme.TEXT_SIZE.TITLE,
		align = Enum.TextXAlignment.Center,
		text = "Tasten kaufen",
		layoutOrder = 0,
	})

	-- Scrollflaeche: fuenf Zeilen a 88 px passen breit hin, auf einem
	-- Handy quer nicht. Statt zwei Layouts scrollt die Liste.
	local list = Instance.new("ScrollingFrame")
	list.Size = UDim2.new(1, 0, 0, (if compact then Theme.SHOP_LIST_HEIGHT_COMPACT else Theme.SHOP_LIST_HEIGHT))
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.CanvasSize = UDim2.new(0, 0, 0, 0)
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.ScrollBarThickness = Theme.SCROLLBAR
	list.ScrollBarImageColor3 = Theme.PANEL_EDGE
	list.ScrollingDirection = Enum.ScrollingDirection.Y
	list.LayoutOrder = 1
	list.Parent = panel
	UiKit.column(list)

	for index, rarityName in EconomyConfig.RARITY_ORDER do
		local rarity = EconomyConfig.RARITIES[rarityName]
		local buy = UiKit.keyRow(list, {
			rarity = rarityName,
			letter = WorldConfig.KEY_LEGENDS[index] or "A",
			title = rarityName,
			rateText = ("+%d Vorrat pro Sekunde"):format(rarity.vorratPerSecond),
			priceText = ("%s Wins"):format(UiKit.number(rarity.price)),
			layoutOrder = index,
		})
		buy.Activated:Connect(function()
			Remotes.get("BuyKey"):FireServer(rarityName)
		end)
	end

	local slotButton = UiKit.button(panel, {
		size = UDim2.new(1, 0, 0, Theme.TOUCH_MIN),
		text = "Steckplatz kaufen",
		base = Theme.GOLD,
		edge = Theme.GOLD_DARK,
		layoutOrder = 2,
	})
	slotButton.Activated:Connect(function()
		Remotes.get("BuySlot"):FireServer()
	end)

	local closeButton = UiKit.button(panel, {
		size = UDim2.new(1, 0, 0, Theme.TOUCH_MIN),
		text = "Schliessen",
		base = Theme.PANEL,
		edge = Theme.PANEL_EDGE,
		layoutOrder = 3,
	})
	closeButton.Activated:Connect(function()
		panel.Visible = false
	end)

	gui.Parent = player:WaitForChild("PlayerGui")

	openButton.Activated:Connect(function()
		panel.Visible = not panel.Visible
	end)

	Remotes.get("StateChanged").OnClientEvent:Connect(function(state)
		if state.slotPrice then
			slotButton.Text = ("Steckplatz %d   %s Wins"):format(state.slots + 1, UiKit.number(state.slotPrice))
		else
			slotButton.Text = "Alle Steckplaetze gekauft"
		end
		openButton.Text = if compact
			then ("Laden %d/%d"):format(state.keyCount, state.slots)
			else ("Laden   %d von %d Tasten"):format(state.keyCount, state.slots)
	end)
end

return ShopController
