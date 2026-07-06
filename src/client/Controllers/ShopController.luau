--!strict
-- ShopController: Robux-Shop am rechten Bildschirmrand.
-- Zeigt Gamepässe und Einzelkäufe (nur Kosmetik!) und verwaltet unter
-- "Meine Kosmetik" das Ausrüsten gekaufter Inhalte. Käufe laufen über die
-- offiziellen Roblox-Kaufdialoge (MarketplaceService); die Gutschrift macht
-- ausschließlich der Server (MonetizationService).

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ConfigFolder = Shared:WaitForChild("Config")
local ControllersFolder = script.Parent :: Instance

local Remotes = require(Shared:WaitForChild("Remotes") :: ModuleScript) :: {
	getEvent: (name: string) -> RemoteEvent,
	getFunction: (name: string) -> RemoteFunction,
}

type CosmeticDef = {
	id: string,
	displayName: string,
	description: string,
	category: string,
	visual: { color: Color3?, secondaryColor: Color3?, material: Enum.Material?, glow: boolean? },
}
type GamepassDef = {
	key: string,
	gamePassId: number,
	displayName: string,
	description: string,
	grantsCosmetics: { string },
}
type ProductDef = {
	key: string,
	productId: number,
	displayName: string,
	description: string,
	grantsCosmetic: string,
}

local MonetizationConfig = require(ConfigFolder:WaitForChild("MonetizationConfig") :: ModuleScript) :: {
	Categories: { string },
	CategoryNames: { [string]: string },
	Cosmetics: { [string]: CosmeticDef },
	Gamepasses: { [string]: GamepassDef },
	DeveloperProducts: { [string]: ProductDef },
	getGamepassKeys: () -> { string },
	getProductKeys: () -> { string },
}
local UIController = require(ControllersFolder:WaitForChild("UIController") :: ModuleScript) :: {
	showToast: (message: string, kind: string) -> (),
}

-- Farbschema (identisch zum UIController).
local PANEL_COLOR = Color3.fromRGB(30, 32, 44)
local ROW_COLOR = Color3.fromRGB(44, 47, 63)
local STROKE_COLOR = Color3.fromRGB(70, 75, 100)
local TEXT_COLOR = Color3.fromRGB(235, 238, 245)
local SUBTEXT_COLOR = Color3.fromRGB(158, 164, 186)
local BUY_BUTTON_COLOR = Color3.fromRGB(56, 160, 92)
local DISABLED_BUTTON_COLOR = Color3.fromRGB(60, 64, 84)
local EQUIP_BUTTON_COLOR = Color3.fromRGB(52, 96, 178)
local EQUIPPED_BUTTON_COLOR = Color3.fromRGB(120, 90, 200)
local SECTION_COLOR = Color3.fromRGB(214, 160, 72)

local PANEL_WIDTH = 320
local ROW_HEIGHT = 56

local ShopController = {}

local localPlayer = Players.LocalPlayer

-- Lokaler Kosmetik-Stand aus CosmeticsUpdated.
local ownedSet: { [string]: boolean } = {}
local equipped: { [string]: string } = {}

local cosmeticsFrame: Frame? = nil
local equipFunction: RemoteFunction? = nil

local function addCorner(instance: Instance, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = instance
end

local function addStroke(instance: Instance, color: Color3)
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = 1
	stroke.Parent = instance
end

local function createLabel(parent: Instance, name: string, text: string): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamMedium
	label.TextColor3 = TEXT_COLOR
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Text = text
	label.Parent = parent
	return label
end

-- Kauf-Zeile für einen Gamepass oder ein Developer Product.
local function createPurchaseRow(
	parent: Instance,
	order: number,
	displayName: string,
	description: string,
	assetId: number,
	infoType: Enum.InfoType,
	onBuy: () -> ()
): TextButton
	local row = Instance.new("Frame")
	row.Name = `Row_{order}`
	row.Size = UDim2.new(1, 0, 0, ROW_HEIGHT)
	row.BackgroundColor3 = ROW_COLOR
	row.LayoutOrder = order
	addCorner(row, 8)
	row.Parent = parent

	local nameLabel = createLabel(row, "Name", displayName)
	nameLabel.Position = UDim2.new(0, 10, 0, 6)
	nameLabel.Size = UDim2.new(1, -110, 0, 18)
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextSize = 14

	local descLabel = createLabel(row, "Desc", description)
	descLabel.Position = UDim2.new(0, 10, 0, 26)
	descLabel.Size = UDim2.new(1, -110, 0, 26)
	descLabel.TextSize = 11
	descLabel.TextColor3 = SUBTEXT_COLOR
	descLabel.TextWrapped = true
	descLabel.TextYAlignment = Enum.TextYAlignment.Top

	local buyButton = Instance.new("TextButton")
	buyButton.Name = "Buy"
	buyButton.AnchorPoint = Vector2.new(1, 0.5)
	buyButton.Position = UDim2.new(1, -8, 0.5, 0)
	buyButton.Size = UDim2.new(0, 88, 0, 34)
	buyButton.Font = Enum.Font.GothamBold
	buyButton.TextSize = 12
	buyButton.TextColor3 = TEXT_COLOR
	addCorner(buyButton, 8)
	buyButton.Parent = row

	if assetId == 0 then
		-- Platzhalter-ID: Produkt wurde im Creator Dashboard noch nicht angelegt.
		buyButton.Text = "Bald..."
		buyButton.BackgroundColor3 = DISABLED_BUTTON_COLOR
		buyButton.AutoButtonColor = false
	else
		buyButton.Text = "Kaufen"
		buyButton.BackgroundColor3 = BUY_BUTTON_COLOR
		buyButton.Activated:Connect(onBuy)

		-- Preis asynchron nachladen und im Button anzeigen.
		task.spawn(function()
			local ok, info = pcall(function()
				return MarketplaceService:GetProductInfo(assetId, infoType)
			end)
			if ok and typeof(info) == "table" and typeof(info.PriceInRobux) == "number" then
				buyButton.Text = `{info.PriceInRobux} R$`
			end
		end)
	end

	return buyButton
end

-- "Meine Kosmetik" neu aufbauen (nach jedem CosmeticsUpdated).
local function rebuildCosmeticsSection()
	local frame = cosmeticsFrame
	if frame == nil then
		return
	end
	for _, child in frame:GetChildren() do
		if not child:IsA("UIListLayout") then
			child:Destroy()
		end
	end

	local order = 0
	local ownedAny = false

	for _, category in MonetizationConfig.Categories do
		-- Alle besessenen Kosmetiken dieser Kategorie einsammeln (sortiert).
		local ids: { string } = {}
		for cosmeticId in ownedSet do
			local def = MonetizationConfig.Cosmetics[cosmeticId]
			if def ~= nil and def.category == category then
				table.insert(ids, cosmeticId)
			end
		end
		table.sort(ids)
		if #ids == 0 then
			continue
		end
		ownedAny = true

		order += 1
		local header = createLabel(frame, `Cat_{category}`, MonetizationConfig.CategoryNames[category] or category)
		header.Size = UDim2.new(1, 0, 0, 20)
		header.TextSize = 12
		header.TextColor3 = SECTION_COLOR
		header.LayoutOrder = order

		for _, cosmeticId in ids do
			local def = MonetizationConfig.Cosmetics[cosmeticId]
			local isEquipped = equipped[category] == cosmeticId

			order += 1
			local row = Instance.new("Frame")
			row.Name = `Own_{cosmeticId}`
			row.Size = UDim2.new(1, 0, 0, 40)
			row.BackgroundColor3 = ROW_COLOR
			row.LayoutOrder = order
			addCorner(row, 8)
			row.Parent = frame

			local swatch = Instance.new("Frame")
			swatch.Name = "Swatch"
			swatch.AnchorPoint = Vector2.new(0, 0.5)
			swatch.Position = UDim2.new(0, 8, 0.5, 0)
			swatch.Size = UDim2.new(0, 14, 0, 14)
			swatch.BackgroundColor3 = def.visual.color or TEXT_COLOR
			addCorner(swatch, 7)
			swatch.Parent = row

			local nameLabel = createLabel(row, "Name", def.displayName)
			nameLabel.AnchorPoint = Vector2.new(0, 0.5)
			nameLabel.Position = UDim2.new(0, 30, 0.5, 0)
			nameLabel.Size = UDim2.new(1, -130, 0, 18)
			nameLabel.TextSize = 13

			local equipButton = Instance.new("TextButton")
			equipButton.Name = "Equip"
			equipButton.AnchorPoint = Vector2.new(1, 0.5)
			equipButton.Position = UDim2.new(1, -8, 0.5, 0)
			equipButton.Size = UDim2.new(0, 88, 0, 28)
			equipButton.Font = Enum.Font.GothamBold
			equipButton.TextSize = 12
			equipButton.TextColor3 = TEXT_COLOR
			equipButton.Text = if isEquipped then "Ablegen" else "Ausrüsten"
			equipButton.BackgroundColor3 = if isEquipped then EQUIPPED_BUTTON_COLOR else EQUIP_BUTTON_COLOR
			addCorner(equipButton, 8)
			equipButton.Parent = row

			equipButton.Activated:Connect(function()
				local remote = equipFunction
				if remote == nil then
					return
				end
				task.spawn(function()
					local ok, success, err = pcall(function()
						return remote:InvokeServer(category, if isEquipped then nil else cosmeticId)
					end)
					if not ok then
						UIController.showToast("Verbindungsfehler – bitte erneut versuchen.", "error")
					elseif success ~= true and typeof(err) == "string" then
						UIController.showToast(err, "error")
					end
				end)
			end)
		end
	end

	if not ownedAny then
		local hint = createLabel(frame, "Empty", "Noch keine Kosmetik – kaufe oben etwas oder hol dir einen Gamepass!")
		hint.Size = UDim2.new(1, 0, 0, 40)
		hint.TextSize = 12
		hint.TextColor3 = SUBTEXT_COLOR
		hint.TextWrapped = true
		hint.LayoutOrder = 1
	end
end

local function buildUI()
	local playerGui = localPlayer:WaitForChild("PlayerGui")

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "PlanetForgeShop"
	screenGui.ResetOnSpawn = false
	screenGui.Parent = playerGui

	-- Umschalt-Button am rechten Rand.
	local toggleButton = Instance.new("TextButton")
	toggleButton.Name = "ShopToggle"
	toggleButton.AnchorPoint = Vector2.new(1, 0.5)
	toggleButton.Position = UDim2.new(1, -12, 0.35, 0)
	toggleButton.Size = UDim2.new(0, 110, 0, 40)
	toggleButton.BackgroundColor3 = PANEL_COLOR
	toggleButton.Font = Enum.Font.GothamBold
	toggleButton.TextSize = 14
	toggleButton.TextColor3 = TEXT_COLOR
	toggleButton.Text = "🛒 Shop"
	addCorner(toggleButton, 10)
	addStroke(toggleButton, STROKE_COLOR)
	toggleButton.Parent = screenGui

	-- Shop-Panel (ScrollingFrame).
	local panel = Instance.new("ScrollingFrame")
	panel.Name = "ShopPanel"
	panel.AnchorPoint = Vector2.new(1, 0.5)
	panel.Position = UDim2.new(1, -12, 0.5, 0)
	panel.Size = UDim2.new(0, PANEL_WIDTH, 0.7, 0)
	panel.BackgroundColor3 = PANEL_COLOR
	panel.ScrollBarThickness = 6
	panel.AutomaticCanvasSize = Enum.AutomaticSize.Y
	panel.CanvasSize = UDim2.new(0, 0, 0, 0)
	panel.Visible = false
	addCorner(panel, 12)
	addStroke(panel, STROKE_COLOR)
	panel.Parent = screenGui

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 10)
	padding.PaddingBottom = UDim.new(0, 10)
	padding.PaddingLeft = UDim.new(0, 10)
	padding.PaddingRight = UDim.new(0, 10)
	padding.Parent = panel

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 6)
	layout.Parent = panel

	toggleButton.Activated:Connect(function()
		panel.Visible = not panel.Visible
	end)

	local order = 0
	local function addSectionLabel(text: string)
		order += 1
		local label = createLabel(panel, `Section_{order}`, text)
		label.Size = UDim2.new(1, 0, 0, 22)
		label.Font = Enum.Font.GothamBold
		label.TextSize = 13
		label.TextColor3 = SECTION_COLOR
		label.LayoutOrder = order
	end

	-- Fairness-Hinweis ganz oben.
	order += 1
	local fairness = createLabel(panel, "Fairness", "Nur Kosmetik – keine Spielvorteile, kein Pay-to-Win.")
	fairness.Size = UDim2.new(1, 0, 0, 30)
	fairness.TextSize = 11
	fairness.TextColor3 = SUBTEXT_COLOR
	fairness.TextWrapped = true
	fairness.LayoutOrder = order

	addSectionLabel("Gamepässe")
	for _, key in MonetizationConfig.getGamepassKeys() do
		local def = MonetizationConfig.Gamepasses[key]
		order += 1
		local row = createPurchaseRow(
			panel,
			order,
			def.displayName,
			def.description,
			def.gamePassId,
			Enum.InfoType.GamePass,
			function()
				MarketplaceService:PromptGamePassPurchase(localPlayer, def.gamePassId)
			end
		)
		row.LayoutOrder = order
	end

	addSectionLabel("Einzelkäufe")
	for _, key in MonetizationConfig.getProductKeys() do
		local def = MonetizationConfig.DeveloperProducts[key]
		order += 1
		createPurchaseRow(
			panel,
			order,
			def.displayName,
			def.description,
			def.productId,
			Enum.InfoType.Product,
			function()
				if ownedSet[def.grantsCosmetic] == true then
					UIController.showToast("Das besitzt du schon!", "info")
					return
				end
				MarketplaceService:PromptProductPurchase(localPlayer, def.productId)
			end
		)
	end

	addSectionLabel("Meine Kosmetik")
	order += 1
	local owned = Instance.new("Frame")
	owned.Name = "OwnedCosmetics"
	owned.Size = UDim2.new(1, 0, 0, 0)
	owned.AutomaticSize = Enum.AutomaticSize.Y
	owned.BackgroundTransparency = 1
	owned.LayoutOrder = order
	owned.Parent = panel

	local ownedLayout = Instance.new("UIListLayout")
	ownedLayout.SortOrder = Enum.SortOrder.LayoutOrder
	ownedLayout.Padding = UDim.new(0, 6)
	ownedLayout.Parent = owned

	cosmeticsFrame = owned
	rebuildCosmeticsSection()
end

function ShopController.init()
	equipFunction = Remotes.getFunction("EquipCosmetic")

	Remotes.getEvent("CosmeticsUpdated").OnClientEvent:Connect(function(ownedArg: any, equippedArg: any)
		ownedSet = {}
		if typeof(ownedArg) == "table" then
			for _, cosmeticId in ownedArg :: { any } do
				if typeof(cosmeticId) == "string" then
					ownedSet[cosmeticId] = true
				end
			end
		end

		equipped = {}
		if typeof(equippedArg) == "table" then
			for category, cosmeticId in equippedArg :: { [any]: any } do
				if typeof(category) == "string" and typeof(cosmeticId) == "string" then
					equipped[category] = cosmeticId
				end
			end
		end

		rebuildCosmeticsSection()
	end)

	buildUI()
end

return ShopController
