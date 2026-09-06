--!strict
-- Laden: Tasten und Steckplaetze kaufen. Die Preise hier sind nur Anzeige -
-- was ein Kauf kostet, entscheidet allein der Server.

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Theme = require(Shared:WaitForChild("Theme"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local EconomyConfig = require(Shared:WaitForChild("Config"):WaitForChild("EconomyConfig"))

local ShopController = {}

local player = Players.LocalPlayer

local ROW_HEIGHT = 56

function ShopController.start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "KeycapShop"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true

	local openEdge = Instance.new("Frame")
	openEdge.Size = UDim2.new(0, 200, 0, 64)
	openEdge.Position = UDim2.new(0, 16, 0, 250)
	openEdge.BackgroundColor3 = Theme.GREEN_DARK
	openEdge.BorderSizePixel = 0
	local openEdgeCorner = Instance.new("UICorner")
	openEdgeCorner.CornerRadius = Theme.CORNER
	openEdgeCorner.Parent = openEdge

	local openButton = Instance.new("TextButton")
	openButton.Size = UDim2.new(1, 0, 1, -Theme.BUTTON_EDGE_HEIGHT)
	openButton.BackgroundColor3 = Theme.GREEN
	openButton.BorderSizePixel = 0
	openButton.Font = Theme.FONT
	openButton.TextScaled = true
	openButton.TextColor3 = Color3.new(1, 1, 1)
	openButton.Text = "Laden"
	local openCorner = Instance.new("UICorner")
	openCorner.CornerRadius = Theme.CORNER
	openCorner.Parent = openButton
	openButton.Parent = openEdge
	openEdge.Parent = gui

	local panel = Instance.new("Frame")
	-- Hoehe nicht ausrechnen, sondern vom Layout bestimmen lassen - sonst
	-- passt sie nicht mehr, sobald eine Seltenheit dazukommt.
	panel.Size = UDim2.new(0, 380, 0, 0)
	panel.AutomaticSize = Enum.AutomaticSize.Y
	panel.Position = UDim2.new(0.5, -190, 0.5, -220)
	panel.BackgroundColor3 = Theme.PANEL
	panel.BorderSizePixel = 0
	panel.Visible = false
	local panelCorner = Instance.new("UICorner")
	panelCorner.CornerRadius = Theme.CORNER
	panelCorner.Parent = panel

	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, 8)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = panel

	local padding = Instance.new("UIPadding")
	padding.PaddingBottom = UDim.new(0, 12)
	padding.PaddingTop = UDim.new(0, 12)
	padding.PaddingLeft = UDim.new(0, 12)
	padding.PaddingRight = UDim.new(0, 12)
	padding.Parent = panel

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, 0, 0, 40)
	title.BackgroundTransparency = 1
	title.Font = Theme.FONT
	title.TextScaled = true
	title.TextColor3 = Theme.TEXT
	title.Text = "Tasten kaufen"
	title.LayoutOrder = 0
	title.Parent = panel

	local function row(order: number, text: string, color: Color3, edge: Color3): TextButton
		local holder = Instance.new("Frame")
		holder.Size = UDim2.new(1, 0, 0, ROW_HEIGHT)
		holder.BackgroundColor3 = edge
		holder.BorderSizePixel = 0
		holder.LayoutOrder = order
		local holderCorner = Instance.new("UICorner")
		holderCorner.CornerRadius = Theme.CORNER
		holderCorner.Parent = holder

		local btn = Instance.new("TextButton")
		btn.Size = UDim2.new(1, 0, 1, -Theme.BUTTON_EDGE_HEIGHT)
		btn.BackgroundColor3 = color
		btn.BorderSizePixel = 0
		btn.Font = Theme.FONT
		btn.TextScaled = true
		btn.TextColor3 = Theme.TEXT
		btn.Text = text
		local btnCorner = Instance.new("UICorner")
		btnCorner.CornerRadius = Theme.CORNER
		btnCorner.Parent = btn
		btn.Parent = holder
		holder.Parent = panel
		return btn
	end

	for index, rarityName in EconomyConfig.RARITY_ORDER do
		local rarity = EconomyConfig.RARITIES[rarityName]
		local color = Theme.RARITY_COLORS[rarityName] or Theme.PANEL
		local btn = row(
			index,
			("%s  +%d/s  -  %d Wins"):format(rarityName, rarity.vorratPerSecond, rarity.price),
			color,
			Theme.PANEL_EDGE
		)
		btn.Activated:Connect(function()
			Remotes.get("BuyKey"):FireServer(rarityName)
		end)
	end

	local slotButton = row(#EconomyConfig.RARITY_ORDER + 1, "Steckplatz kaufen", Theme.GOLD, Theme.GOLD_DARK)
	slotButton.Activated:Connect(function()
		Remotes.get("BuySlot"):FireServer()
	end)

	local closeButton = row(#EconomyConfig.RARITY_ORDER + 2, "Schliessen", Theme.PANEL, Theme.PANEL_EDGE)
	closeButton.Activated:Connect(function()
		panel.Visible = false
	end)

	panel.Parent = gui
	gui.Parent = player:WaitForChild("PlayerGui")

	openButton.Activated:Connect(function()
		panel.Visible = not panel.Visible
	end)

	Remotes.get("StateChanged").OnClientEvent:Connect(function(state)
		if state.slotPrice then
			slotButton.Text = ("Steckplatz %d  -  %d Wins"):format(state.slots + 1, state.slotPrice)
		else
			slotButton.Text = "Alle Steckplaetze gekauft"
		end
		openButton.Text = ("Laden  (%d/%d)"):format(state.keyCount, state.slots)
	end)
end

return ShopController
