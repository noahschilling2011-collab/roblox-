--!strict
-- Laden: Tasten und Steckplaetze kaufen. Die Preise hier sind nur Anzeige -
-- was ein Kauf kostet, entscheidet allein der Server.

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Theme = require(Shared:WaitForChild("Theme"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local EconomyConfig = require(Shared:WaitForChild("Config"):WaitForChild("EconomyConfig"))
local UiKit = require(script.Parent.Parent.UiKit)

local ShopController = {}

local player = Players.LocalPlayer

function ShopController.start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "KeycapShop"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	UiKit.autoScale(gui)

	local margin = Theme.SPACE.L
	-- Sitzt in der linken Spalte unter der Statuskarte und dem Schild-Knopf.
	local shieldBottom = Theme.HUD_STATS_HEIGHT + margin + Theme.SPACE.S + Theme.TOUCH_MIN
	local openButton = UiKit.button(gui, {
		size = UDim2.new(0, Theme.HUD_PANEL_WIDTH, 0, Theme.TOUCH_MIN),
		position = UDim2.new(0, margin, 0, shieldBottom + Theme.SPACE.S),
		text = "Laden",
		base = Theme.GREEN,
		edge = Theme.GREEN_DARK,
	})

	-- Hoehe nicht ausrechnen, sondern vom Layout bestimmen lassen - sonst
	-- passt sie nicht mehr, sobald eine Seltenheit dazukommt.
	local panel = UiKit.panel(gui, UDim2.new(0, Theme.SHOP_PANEL_WIDTH, 0, 0), UDim2.new(0.5, -Theme.SHOP_PANEL_WIDTH / 2, 0.5, -240))
	panel.AutomaticSize = Enum.AutomaticSize.Y
	panel.Visible = false
	UiKit.stack(panel)

	UiKit.text(panel, {
		size = UDim2.new(1, 0, 0, 38),
		textSize = Theme.TEXT_SIZE.TITLE,
		align = Enum.TextXAlignment.Center,
		text = "Tasten kaufen",
		layoutOrder = 0,
	})

	for index, rarityName in EconomyConfig.RARITY_ORDER do
		local rarity = EconomyConfig.RARITIES[rarityName]
		local button = UiKit.button(panel, {
			size = UDim2.new(1, 0, 0, Theme.TOUCH_MIN),
			text = ("%s   +%d/s   %d Wins"):format(rarityName, rarity.vorratPerSecond, rarity.price),
			base = Theme.RARITY_COLORS[rarityName] or Theme.PANEL,
			edge = Theme.PANEL_EDGE,
			layoutOrder = index,
		})
		button.Activated:Connect(function()
			Remotes.get("BuyKey"):FireServer(rarityName)
		end)
	end

	local slotButton = UiKit.button(panel, {
		size = UDim2.new(1, 0, 0, Theme.TOUCH_MIN),
		text = "Steckplatz kaufen",
		base = Theme.GOLD,
		edge = Theme.GOLD_DARK,
		layoutOrder = #EconomyConfig.RARITY_ORDER + 1,
	})
	slotButton.Activated:Connect(function()
		Remotes.get("BuySlot"):FireServer()
	end)

	local closeButton = UiKit.button(panel, {
		size = UDim2.new(1, 0, 0, Theme.TOUCH_MIN),
		text = "Schliessen",
		base = Theme.PANEL,
		edge = Theme.PANEL_EDGE,
		layoutOrder = #EconomyConfig.RARITY_ORDER + 2,
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
			slotButton.Text = ("Steckplatz %d   %d Wins"):format(state.slots + 1, state.slotPrice)
		else
			slotButton.Text = "Alle Steckplaetze gekauft"
		end
		openButton.Text = ("Laden   %d von %d Tasten"):format(state.keyCount, state.slots)
	end)
end

return ShopController
