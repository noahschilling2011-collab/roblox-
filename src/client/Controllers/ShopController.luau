--!strict
-- ShopController: Robux-Shop mit Kategorie-Tabs am rechten Bildschirmrand.
--
-- Tabs: "Gamepässe", "Einzelkäufe", "Meine Kosmetik". Jede Kauf-Zeile zeigt
-- eine Vorschau (Farb-Swatch + Kategorie-Icon), den Preis und - falls schon
-- freigeschaltet - ein "Im Besitz ✓"-Badge. Käufe laufen über die offiziellen
-- Roblox-Kaufdialoge; die Gutschrift macht ausschließlich der Server.
--
-- STUDIO-TESTMODUS: Ist eine Produkt-ID noch 0 und läuft das Spiel in Studio
-- (MonetizationConfig.testModeInStudio), zeigt der Button "Test-Kauf" und
-- simuliert den Kauf über SimulatePurchase - der Server prüft Studio hart.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

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
	perk: string?,
}
type ProductDef = {
	key: string,
	productId: number,
	displayName: string,
	description: string,
	grantsCosmetic: string?,
	grantsEnergy: number?,
	perk: string?,
}

local MonetizationConfig = require(ConfigFolder:WaitForChild("MonetizationConfig") :: ModuleScript) :: {
	testModeInStudio: boolean,
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
local EffectsController = require(ControllersFolder:WaitForChild("EffectsController") :: ModuleScript) :: {
	playSound: (name: string, pitchOverride: number?) -> (),
}

-- Farbschema (identisch zum UIController).
local PANEL_COLOR = Color3.fromRGB(30, 32, 44)
local ROW_COLOR = Color3.fromRGB(44, 47, 63)
local STROKE_COLOR = Color3.fromRGB(70, 75, 100)
local TEXT_COLOR = Color3.fromRGB(235, 238, 245)
local SUBTEXT_COLOR = Color3.fromRGB(158, 164, 186)
local BUY_BUTTON_COLOR = Color3.fromRGB(56, 160, 92)
local TEST_BUTTON_COLOR = Color3.fromRGB(214, 160, 72)
local DISABLED_BUTTON_COLOR = Color3.fromRGB(60, 64, 84)
local EQUIP_BUTTON_COLOR = Color3.fromRGB(52, 96, 178)
local EQUIPPED_BUTTON_COLOR = Color3.fromRGB(120, 90, 200)
local OWNED_BADGE_COLOR = Color3.fromRGB(76, 175, 110)
local TAB_ACTIVE_COLOR = Color3.fromRGB(52, 96, 178)

local PANEL_WIDTH = 340
local ROW_HEIGHT = 62

-- Kategorie-Icons für die Vorschau.
local CATEGORY_ICONS: { [string]: string } = {
	skin = "🪐",
	aura = "✨",
	wetter = "🌦️",
	haustier = "🐾",
}

-- Icons für Gamepass-Perks und Verbrauchs-Produkte.
local PERK_ICONS: { [string]: string } = {
	double_mult = "✖2",
	pet_slots = "🐾",
	vip = "👑",
	instant_rebirth = "🔄",
	energy = "⚡",
}

local ShopController = {}

local localPlayer = Players.LocalPlayer

-- Lokaler Kosmetik-Stand aus CosmeticsUpdated.
local ownedSet: { [string]: boolean } = {}
local equipped: { [string]: string } = {}
local ownedPasses: { [string]: boolean } = {}
local shopPanel: Frame? = nil

local cosmeticsFrame: Frame? = nil
local equipFunction: RemoteFunction? = nil
local simulateFunction: RemoteFunction? = nil

-- Zeilen-Aktualisierer, die bei jedem CosmeticsUpdated laufen (Badges usw.).
local rowUpdaters: { () -> () } = {}

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

-- Testmodus aus Client-Sicht (der Server prüft zusätzlich hart).
local function isTestModeActive(): boolean
	return MonetizationConfig.testModeInStudio == true and RunService:IsStudio()
end

-- Vorschau: runder Farb-Swatch mit Kategorie-Icon.
local function createPreview(parent: Instance, color: Color3, category: string)
	local swatch = Instance.new("Frame")
	swatch.Name = "Preview"
	swatch.AnchorPoint = Vector2.new(0, 0.5)
	swatch.Position = UDim2.new(0, 8, 0.5, 0)
	swatch.Size = UDim2.new(0, 40, 0, 40)
	swatch.BackgroundColor3 = color
	addCorner(swatch, 20)
	addStroke(swatch, STROKE_COLOR)
	swatch.Parent = parent

	local iconText: string
	if string.sub(category, 1, 5) == "perk:" then
		iconText = PERK_ICONS[string.sub(category, 6)] or "🎁"
	else
		iconText = CATEGORY_ICONS[category] or "🎁"
	end

	local icon = Instance.new("TextLabel")
	icon.BackgroundTransparency = 1
	icon.Size = UDim2.new(1, 0, 1, 0)
	icon.Font = Enum.Font.GothamBold
	icon.TextSize = 20
	icon.Text = iconText
	icon.Parent = swatch
end

-- Kauf-Zeile für einen Gamepass oder ein Developer Product.
local function createPurchaseRow(
	parent: Instance,
	order: number,
	displayName: string,
	description: string,
	previewColor: Color3,
	previewCategory: string,
	assetId: number,
	infoType: Enum.InfoType,
	isOwned: () -> boolean,
	onBuy: () -> (),
	onTestBuy: () -> ()
)
	local row = Instance.new("Frame")
	row.Name = `Row_{order}`
	row.Size = UDim2.new(1, 0, 0, ROW_HEIGHT)
	row.BackgroundColor3 = ROW_COLOR
	row.LayoutOrder = order
	addCorner(row, 8)
	row.Parent = parent

	createPreview(row, previewColor, previewCategory)

	local nameLabel = createLabel(row, "Name", displayName)
	nameLabel.Position = UDim2.new(0, 56, 0, 8)
	nameLabel.Size = UDim2.new(1, -160, 0, 18)
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextSize = 14

	local descLabel = createLabel(row, "Desc", description)
	descLabel.Position = UDim2.new(0, 56, 0, 28)
	descLabel.Size = UDim2.new(1, -160, 0, 28)
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

	local ownedBadge = Instance.new("TextLabel")
	ownedBadge.Name = "OwnedBadge"
	ownedBadge.AnchorPoint = Vector2.new(1, 0.5)
	ownedBadge.Position = UDim2.new(1, -8, 0.5, 0)
	ownedBadge.Size = UDim2.new(0, 88, 0, 34)
	ownedBadge.BackgroundColor3 = OWNED_BADGE_COLOR
	ownedBadge.Font = Enum.Font.GothamBold
	ownedBadge.TextSize = 12
	ownedBadge.TextColor3 = TEXT_COLOR
	ownedBadge.Text = "Im Besitz ✓"
	ownedBadge.Visible = false
	addCorner(ownedBadge, 8)
	ownedBadge.Parent = row

	-- Kaufweg bestimmen: echte ID -> Roblox-Dialog; ID 0 im Studio-Testmodus
	-- -> Test-Kauf; sonst deaktiviert.
	if assetId ~= 0 then
		buyButton.Text = "Kaufen"
		buyButton.BackgroundColor3 = BUY_BUTTON_COLOR
		buyButton.Activated:Connect(onBuy)
		task.spawn(function()
			local ok, info = pcall(function()
				return MarketplaceService:GetProductInfo(assetId, infoType)
			end)
			if ok and typeof(info) == "table" and typeof(info.PriceInRobux) == "number" then
				buyButton.Text = `{info.PriceInRobux} R$`
			end
		end)
	elseif isTestModeActive() then
		buyButton.Text = "Test-Kauf"
		buyButton.BackgroundColor3 = TEST_BUTTON_COLOR
		buyButton.Activated:Connect(onTestBuy)
	else
		buyButton.Text = "Bald..."
		buyButton.BackgroundColor3 = DISABLED_BUTTON_COLOR
		buyButton.AutoButtonColor = false
	end

	-- Badge/Button live umschalten, sobald sich der Besitz ändert.
	table.insert(rowUpdaters, function()
		local owned = isOwned()
		ownedBadge.Visible = owned
		buyButton.Visible = not owned
	end)
end

-- Test-Kauf über den Server simulieren (nur Studio; Server prüft hart).
local function requestTestPurchase(kind: string, key: string)
	local remote = simulateFunction
	if remote == nil then
		return
	end
	task.spawn(function()
		local ok, serverOk, message = pcall(function()
			return remote:InvokeServer(kind, key)
		end)
		if not ok then
			UIController.showToast("Verbindungsfehler – bitte erneut versuchen.", "error")
		elseif serverOk ~= true and typeof(message) == "string" then
			UIController.showToast(message, "error")
		else
			EffectsController.playSound("collect")
		end
	end)
end

local function runRowUpdaters()
	for _, update in rowUpdaters do
		update()
	end
end

-- "Meine Kosmetik" neu aufbauen (nach jedem CosmeticsUpdated).
local function rebuildCosmeticsSection()
	local frame = cosmeticsFrame
	if frame == nil then
		return
	end
	for _, child in frame:GetChildren() do
		if not (child:IsA("UIListLayout") or child:IsA("UIPadding")) then
			child:Destroy()
		end
	end

	local order = 0
	local ownedAny = false

	for _, category in MonetizationConfig.Categories do
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
		header.Font = Enum.Font.GothamBold
		header.TextSize = 12
		header.TextColor3 = TEST_BUTTON_COLOR
		header.LayoutOrder = order

		for _, cosmeticId in ids do
			local def = MonetizationConfig.Cosmetics[cosmeticId]
			local isEquipped = equipped[category] == cosmeticId

			order += 1
			local row = Instance.new("Frame")
			row.Name = `Own_{cosmeticId}`
			row.Size = UDim2.new(1, 0, 0, 48)
			row.BackgroundColor3 = ROW_COLOR
			row.LayoutOrder = order
			addCorner(row, 8)
			row.Parent = frame

			local preview = Instance.new("Frame")
			preview.AnchorPoint = Vector2.new(0, 0.5)
			preview.Position = UDim2.new(0, 8, 0.5, 0)
			preview.Size = UDim2.new(0, 30, 0, 30)
			preview.BackgroundColor3 = def.visual.color or TEXT_COLOR
			addCorner(preview, 15)
			preview.Parent = row

			local icon = Instance.new("TextLabel")
			icon.BackgroundTransparency = 1
			icon.Size = UDim2.new(1, 0, 1, 0)
			icon.Font = Enum.Font.GothamBold
			icon.TextSize = 15
			icon.Text = CATEGORY_ICONS[def.category] or "🎁"
			icon.Parent = preview

			local nameLabel = createLabel(row, "Name", def.displayName)
			nameLabel.AnchorPoint = Vector2.new(0, 0.5)
			nameLabel.Position = UDim2.new(0, 46, 0.5, 0)
			nameLabel.Size = UDim2.new(1, -150, 0, 18)
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
					else
						EffectsController.playSound("pop")
					end
				end)
			end)
		end
	end

	if not ownedAny then
		local hint = createLabel(frame, "Empty", 'Noch keine Kosmetik – hol dir etwas aus den Tabs „Gamepässe" oder „Einzelkäufe"!')
		hint.Size = UDim2.new(1, 0, 0, 44)
		hint.TextSize = 12
		hint.TextColor3 = SUBTEXT_COLOR
		hint.TextWrapped = true
		hint.LayoutOrder = 1
	end
end

-- Scrollbaren Tab-Inhalt anlegen.
local function createTabContent(parent: Instance): ScrollingFrame
	local frame = Instance.new("ScrollingFrame")
	frame.Position = UDim2.new(0, 0, 0, 44)
	frame.Size = UDim2.new(1, 0, 1, -44)
	frame.BackgroundTransparency = 1
	frame.ScrollBarThickness = 6
	frame.AutomaticCanvasSize = Enum.AutomaticSize.Y
	frame.CanvasSize = UDim2.new(0, 0, 0, 0)
	frame.Visible = false
	frame.Parent = parent

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 8)
	padding.PaddingLeft = UDim.new(0, 10)
	padding.PaddingRight = UDim.new(0, 10)
	padding.PaddingBottom = UDim.new(0, 8)
	padding.Parent = frame

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 6)
	layout.Parent = frame

	return frame
end

local function buildUI()
	local playerGui = localPlayer:WaitForChild("PlayerGui")

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "PlanetForgeShop"
	screenGui.ResetOnSpawn = false
	screenGui.Parent = playerGui

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

	local panel = Instance.new("Frame")
	panel.Name = "ShopPanel"
	panel.AnchorPoint = Vector2.new(1, 0.5)
	panel.Position = UDim2.new(1, -130, 0.5, 0)
	panel.Size = UDim2.new(0, PANEL_WIDTH, 0.72, 0)
	panel.BackgroundColor3 = PANEL_COLOR
	panel.Visible = false
	addCorner(panel, 12)
	addStroke(panel, STROKE_COLOR)
	panel.Parent = screenGui

	toggleButton.Activated:Connect(function()
		panel.Visible = not panel.Visible
	end)

	-- Tab-Leiste.
	local tabBar = Instance.new("Frame")
	tabBar.Name = "Tabs"
	tabBar.Position = UDim2.new(0, 8, 0, 8)
	tabBar.Size = UDim2.new(1, -16, 0, 30)
	tabBar.BackgroundTransparency = 1
	tabBar.Parent = panel

	local tabLayout = Instance.new("UIListLayout")
	tabLayout.FillDirection = Enum.FillDirection.Horizontal
	tabLayout.SortOrder = Enum.SortOrder.LayoutOrder
	tabLayout.Padding = UDim.new(0, 6)
	tabLayout.Parent = tabBar

	local gamepassContent = createTabContent(panel)
	gamepassContent.Name = "GamepassContent"
	local productContent = createTabContent(panel)
	productContent.Name = "ProductContent"
	local cosmeticsContent = createTabContent(panel)
	cosmeticsContent.Name = "CosmeticsContent"

	local tabs: { { button: TextButton, content: ScrollingFrame } } = {}

	local function selectTab(selectedIndex: number)
		for index, tab in tabs do
			local active = index == selectedIndex
			tab.content.Visible = active
			tab.button.BackgroundColor3 = if active then TAB_ACTIVE_COLOR else ROW_COLOR
		end
	end

	local function addTab(order: number, title: string, content: ScrollingFrame)
		local button = Instance.new("TextButton")
		button.Name = `Tab_{order}`
		button.LayoutOrder = order
		button.Size = UDim2.new(0, 104, 1, 0)
		button.BackgroundColor3 = ROW_COLOR
		button.Font = Enum.Font.GothamBold
		button.TextSize = 11
		button.TextColor3 = TEXT_COLOR
		button.Text = title
		addCorner(button, 8)
		button.Parent = tabBar

		table.insert(tabs, { button = button, content = content })
		local index = #tabs
		button.Activated:Connect(function()
			selectTab(index)
		end)
	end

	addTab(1, "Gamepässe", gamepassContent)
	addTab(2, "Einzelkäufe", productContent)
	addTab(3, "Meine Kosmetik", cosmeticsContent)
	selectTab(1)

	-- Gamepass-Zeilen (Vorschau = erste enthaltene Kosmetik).
	local order = 0
	for _, key in MonetizationConfig.getGamepassKeys() do
		local def = MonetizationConfig.Gamepasses[key]
		local firstCosmetic = MonetizationConfig.Cosmetics[def.grantsCosmetics[1]]
		local previewColor = if firstCosmetic ~= nil
			then firstCosmetic.visual.color or TEXT_COLOR
			else TEST_BUTTON_COLOR
		local previewIcon = if firstCosmetic ~= nil
			then firstCosmetic.category
			else `perk:{def.perk or "vip"}`
		order += 1
		createPurchaseRow(
			gamepassContent,
			order,
			def.displayName,
			def.description,
			previewColor,
			previewIcon,
			def.gamePassId,
			Enum.InfoType.GamePass,
			function()
				-- Perk-Pässe: Besitz kommt aus dem Pass-Cache des Servers.
				if def.perk ~= nil then
					return ownedPasses[key] == true
				end
				for _, cosmeticId in def.grantsCosmetics do
					if not ownedSet[cosmeticId] then
						return false
					end
				end
				return true
			end,
			function()
				MarketplaceService:PromptGamePassPurchase(localPlayer, def.gamePassId)
			end,
			function()
				requestTestPurchase("gamepass", key)
			end
		)
	end

	-- Einzelkauf-Zeilen.
	for _, key in MonetizationConfig.getProductKeys() do
		local def = MonetizationConfig.DeveloperProducts[key]
		local cosmeticId = def.grantsCosmetic
		local cosmetic = if cosmeticId ~= nil then MonetizationConfig.Cosmetics[cosmeticId] else nil
		local previewColor = if cosmetic ~= nil then cosmetic.visual.color or TEXT_COLOR else TEST_BUTTON_COLOR
		local previewIcon = if cosmetic ~= nil
			then cosmetic.category
			elseif def.grantsEnergy ~= nil then "perk:energy"
			else `perk:{def.perk or "energy"}`
		order += 1
		createPurchaseRow(
			productContent,
			order,
			def.displayName,
			def.description,
			previewColor,
			previewIcon,
			def.productId,
			Enum.InfoType.Product,
			function()
				-- Verbrauchs-Produkte (Energie, Sofort-Rebirth) sind immer kaufbar.
				if cosmeticId == nil then
					return false
				end
				return ownedSet[cosmeticId] == true
			end,
			function()
				MarketplaceService:PromptProductPurchase(localPlayer, def.productId)
			end,
			function()
				requestTestPurchase("product", key)
			end
		)
	end

	-- Hinweis im Testmodus.
	if isTestModeActive() then
		order += 1
		local hint = createLabel(gamepassContent, "TestHint", 'Studio-Testmodus aktiv: „Test-Kauf" schaltet ohne Robux frei (nur in Studio).')
		hint.Size = UDim2.new(1, 0, 0, 30)
		hint.TextSize = 10
		hint.TextColor3 = TEST_BUTTON_COLOR
		hint.TextWrapped = true
		hint.LayoutOrder = order
	end

	cosmeticsFrame = cosmeticsContent
	shopPanel = panel
	rebuildCosmeticsSection()
	runRowUpdaters()
end

function ShopController.init()
	equipFunction = Remotes.getFunction("EquipCosmetic")
	simulateFunction = Remotes.getFunction("SimulatePurchase")

	Remotes.getEvent("CosmeticsUpdated").OnClientEvent:Connect(function(ownedArg: any, equippedArg: any, passesArg: any)
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

		ownedPasses = {}
		if typeof(passesArg) == "table" then
			for key, owned in passesArg :: { [any]: any } do
				if typeof(key) == "string" and owned == true then
					ownedPasses[key] = true
				end
			end
		end

		rebuildCosmeticsSection()
		runRowUpdaters()
	end)

	buildUI()

	-- Shop-Bereich auf der Insel: Betreten des blauen Pads öffnet den Shop.
	task.spawn(function()
		local wasNear = false
		while true do
			task.wait(0.5)
			local panel = shopPanel
			if panel == nil then
				continue
			end
			local character = localPlayer.Character
			local root = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
			local plots = workspace:FindFirstChild("PlanetPlots")
			local plot = if plots ~= nil then plots:FindFirstChild(`Plot_{localPlayer.UserId}`) else nil
			local pad = if plot ~= nil then plot:FindFirstChild("ShopPad") else nil
			if root == nil or not root:IsA("BasePart") or pad == nil or not pad:IsA("BasePart") then
				wasNear = false
				continue
			end
			local near = ((root :: BasePart).Position - (pad :: BasePart).Position).Magnitude <= 9
			if near and not wasNear then
				panel.Visible = true
				EffectsController.playSound("pop", 1.05)
			end
			wasNear = near
		end
	end)
end

return ShopController
