--!strict
-- ShopUIController: der 🛒 Robux- & Trümmer-Shop.
--
-- Ein richtiger Shop wie in den großen Roblox-Spielen - aber strikt nach
-- unserer Regel: NUR Kosmetik (Skins, Bundles, Season-Pass), kein einziger
-- Gameplay-Vorteil. Drei Bereiche in einem Panel:
--   ⭐ Season-Pass (Gamepass)          -> PromptGamePassPurchase
--   🎁 Skins & Bundles (Robux)         -> PromptProductPurchase
--   🧱 Trümmer-Skins (erspielte Währung) -> BuySkinWithDebris
-- Platzhalter-IDs (0) zeigen "Bald verfügbar" und sind nur im
-- Studio-Testmodus simulierbar. Besitz/Guthaben kommen ausschließlich
-- vom Server (SkinsChanged).

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Network = require(Shared:WaitForChild("Network") :: ModuleScript) :: {
	getEvent: (name: string) -> RemoteEvent,
	getFunction: (name: string) -> RemoteFunction,
}
local SkinCatalog = require(Shared:WaitForChild("Config"):WaitForChild("SkinCatalog") :: ModuleScript) :: any
local MonetizationCatalog =
	require(Shared:WaitForChild("Config"):WaitForChild("MonetizationCatalog") :: ModuleScript) :: any

local ControllersFolder = script.Parent :: Instance
local UIController = require(ControllersFolder:WaitForChild("UIController") :: ModuleScript) :: any

local PANEL_COLOR = Color3.fromRGB(28, 30, 40)
local CARD_COLOR = Color3.fromRGB(42, 45, 60)
local TEXT_COLOR = Color3.fromRGB(235, 238, 245)
local SUBTEXT_COLOR = Color3.fromRGB(158, 164, 186)
local ACCENT_COLOR = Color3.fromRGB(255, 190, 70)
local BUY_COLOR = Color3.fromRGB(80, 170, 110)
local ROBUX_COLOR = Color3.fromRGB(90, 200, 120)
local DISABLED_COLOR = Color3.fromRGB(70, 74, 92)

local ShopUIController = {}

local ownedSkins: { [string]: boolean } = {}
local truemmer = 0

local panel: Frame? = nil
local listFrame: ScrollingFrame? = nil
local currencyLabel: TextLabel? = nil

local buyDebrisFunction: RemoteFunction? = nil
local simulateFunction: RemoteFunction? = nil

local function addCorner(instance: Instance, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = instance
end

--------------------------------------------------------------------------
-- Kauf-Aktionen
--------------------------------------------------------------------------

local function invokeSimple(remote: RemoteFunction?, argument: string)
	if remote == nil then
		return
	end
	task.spawn(function()
		local ok, serverOk, err = pcall(function()
			return (remote :: RemoteFunction):InvokeServer(argument)
		end)
		if not ok then
			UIController.showToast("Verbindungsfehler - bitte erneut versuchen.", "error")
		elseif serverOk == true then
			UIController.showToast("Gekauft! Viel Spaß! 🎉", "success")
		elseif typeof(err) == "string" then
			UIController.showToast(err, "error")
		end
	end)
end

local function buyProduct(productKey: string, productId: number)
	if productId ~= 0 then
		MarketplaceService:PromptProductPurchase(Players.LocalPlayer, productId)
	elseif RunService:IsStudio() then
		invokeSimple(simulateFunction, productKey)
	else
		UIController.showToast("Bald verfügbar - Produkt-ID ist noch nicht eingetragen.", "info")
	end
end

local function buySeasonPass()
	local gamePassId = MonetizationCatalog.SEASON_PASS_GAMEPASS_ID
	if gamePassId ~= 0 then
		MarketplaceService:PromptGamePassPurchase(Players.LocalPlayer, gamePassId)
	else
		UIController.showToast("Season-Pass kommt bald - die Gamepass-ID ist noch nicht eingetragen.", "info")
	end
end

--------------------------------------------------------------------------
-- Karten-Bausteine
--------------------------------------------------------------------------

local cardOrder = 0

local function addSectionHeader(parent: Instance, text: string)
	cardOrder += 1
	local header = Instance.new("TextLabel")
	header.LayoutOrder = cardOrder
	header.BackgroundTransparency = 1
	header.Size = UDim2.new(1, -8, 0, 28)
	header.Font = Enum.Font.GothamBold
	header.TextSize = 15
	header.TextColor3 = ACCENT_COLOR
	header.TextXAlignment = Enum.TextXAlignment.Left
	header.Text = text
	header.Parent = parent
end

-- Eine Shop-Karte: Titel, Beschreibung, Kauf-Button rechts.
local function addCard(parent: Instance, title: string, description: string, buttonText: string, buttonColor: Color3, enabled: boolean, onBuy: (() -> ())?)
	cardOrder += 1
	local card = Instance.new("Frame")
	card.LayoutOrder = cardOrder
	card.Size = UDim2.new(1, -8, 0, 62)
	card.BackgroundColor3 = CARD_COLOR
	addCorner(card, 10)
	card.Parent = parent

	local titleLabel = Instance.new("TextLabel")
	titleLabel.BackgroundTransparency = 1
	titleLabel.Position = UDim2.new(0, 10, 0, 7)
	titleLabel.Size = UDim2.new(1, -140, 0, 20)
	titleLabel.Font = Enum.Font.GothamBold
	titleLabel.TextSize = 14
	titleLabel.TextColor3 = TEXT_COLOR
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.TextTruncate = Enum.TextTruncate.AtEnd
	titleLabel.Text = title
	titleLabel.Parent = card

	local descriptionLabel = Instance.new("TextLabel")
	descriptionLabel.BackgroundTransparency = 1
	descriptionLabel.Position = UDim2.new(0, 10, 0, 28)
	descriptionLabel.Size = UDim2.new(1, -140, 0, 28)
	descriptionLabel.Font = Enum.Font.GothamMedium
	descriptionLabel.TextSize = 11
	descriptionLabel.TextColor3 = SUBTEXT_COLOR
	descriptionLabel.TextXAlignment = Enum.TextXAlignment.Left
	descriptionLabel.TextWrapped = true
	descriptionLabel.Text = description
	descriptionLabel.Parent = card

	local button = Instance.new("TextButton")
	button.AnchorPoint = Vector2.new(1, 0.5)
	button.Position = UDim2.new(1, -10, 0.5, 0)
	button.Size = UDim2.new(0, 118, 0, 34)
	button.BackgroundColor3 = if enabled then buttonColor else DISABLED_COLOR
	button.Font = Enum.Font.GothamBold
	button.TextSize = 12
	button.TextColor3 = TEXT_COLOR
	button.TextWrapped = true
	button.Text = buttonText
	button.AutoButtonColor = enabled
	addCorner(button, 8)
	button.Parent = card

	if enabled and onBuy ~= nil then
		button.Activated:Connect(onBuy)
	end
end

--------------------------------------------------------------------------
-- Inhalt aufbauen
--------------------------------------------------------------------------

local function skinNames(skinIds: { string }): string
	local names = {}
	for _, skinId in skinIds do
		local skin = SkinCatalog.Skins[skinId]
		table.insert(names, if skin ~= nil then skin.name else skinId)
	end
	return table.concat(names, " + ")
end

local function ownsAll(skinIds: { string }): boolean
	for _, skinId in skinIds do
		if ownedSkins[skinId] ~= true then
			return false
		end
	end
	return true
end

local function refreshList()
	local container = listFrame
	if container == nil then
		return
	end
	for _, child in container:GetChildren() do
		if child:IsA("Frame") or child:IsA("TextLabel") then
			child:Destroy()
		end
	end
	cardOrder = 0

	-- ⭐ Season-Pass.
	addSectionHeader(container, "⭐ Season-Pass (Gamepass)")
	local passOwned = ownsAll(MonetizationCatalog.SEASON_PASS_SKINS)
	addCard(
		container,
		"Season-Pass: Legendäre Sammlung",
		`Enthält: {skinNames(MonetizationCatalog.SEASON_PASS_SKINS)}`,
		if passOwned then "✓ Im Besitz" else "Kaufen (R$)",
		ROBUX_COLOR,
		not passOwned,
		buySeasonPass
	)

	-- 🎁 Robux-Produkte (Einzel-Skins + Bundles).
	addSectionHeader(container, "🎁 Skins & Bundles (Robux)")
	for _, productKey in MonetizationCatalog.getSortedProductKeys() do
		local product = MonetizationCatalog.DEVPRODUCT_IDS[productKey]
		local owned = ownsAll(product.grantsSkins)
		local isPlaceholder = product.productId == 0
		local buttonText = if owned
			then "✓ Im Besitz"
			elseif not isPlaceholder then "Kaufen (R$)"
			elseif RunService:IsStudio() then "Testkauf (Studio)"
			else "Bald verfügbar"
		addCard(
			container,
			product.displayName,
			`Enthält: {skinNames(product.grantsSkins)}`,
			buttonText,
			ROBUX_COLOR,
			not owned and (not isPlaceholder or RunService:IsStudio()),
			function()
				buyProduct(productKey, product.productId)
			end
		)
	end

	-- 🧱 Trümmer-Skins (erspielte Währung, Free-Progression).
	addSectionHeader(container, "🧱 Trümmer-Skins (erspielt, nicht kaufbar)")
	for _, skinId in SkinCatalog.getSortedIds() do
		local skin = SkinCatalog.Skins[skinId]
		if skin.priceDebris == nil then
			continue
		end
		local owned = ownedSkins[skinId] == true
		local affordable = truemmer >= skin.priceDebris
		addCard(
			container,
			skin.name,
			`{skin.rarity}-Skin für alle Teile`,
			if owned then "✓ Im Besitz" else `Kaufen ({skin.priceDebris} 🧱)`,
			if affordable then BUY_COLOR else DISABLED_COLOR,
			not owned,
			function()
				invokeSimple(buyDebrisFunction, skinId)
			end
		)
	end
end

--------------------------------------------------------------------------
-- Panel
--------------------------------------------------------------------------

local function buildUI()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "TurmfallShop"
	screenGui.ResetOnSpawn = false
	screenGui.DisplayOrder = 22
	screenGui.Parent = playerGui

	local toggle = Instance.new("TextButton")
	toggle.Name = "ShopToggle"
	toggle.Position = UDim2.new(0, 12, 0, 54)
	toggle.Size = UDim2.new(0, 110, 0, 36)
	toggle.BackgroundColor3 = PANEL_COLOR
	toggle.Font = Enum.Font.GothamBold
	toggle.TextSize = 14
	toggle.TextColor3 = ACCENT_COLOR
	toggle.Text = "🛒 Shop"
	addCorner(toggle, 10)
	local toggleStroke = Instance.new("UIStroke")
	toggleStroke.Color = ACCENT_COLOR
	toggleStroke.Transparency = 0.4
	toggleStroke.Parent = toggle
	toggle.Parent = screenGui

	local frame = Instance.new("Frame")
	frame.Name = "ShopPanel"
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.new(0.5, 0, 0.5, 0)
	frame.Size = UDim2.new(0, 520, 0, 420)
	frame.BackgroundColor3 = PANEL_COLOR
	frame.Visible = false
	addCorner(frame, 12)
	local stroke = Instance.new("UIStroke")
	stroke.Color = ACCENT_COLOR
	stroke.Parent = frame
	frame.Parent = screenGui
	panel = frame

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Position = UDim2.new(0, 14, 0, 10)
	title.Size = UDim2.new(1, -170, 0, 22)
	title.Font = Enum.Font.GothamBold
	title.TextSize = 16
	title.TextColor3 = ACCENT_COLOR
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = "🛒 Shop – nur Kosmetik, kein Pay-to-Win"
	title.Parent = frame

	local currency = Instance.new("TextLabel")
	currency.BackgroundTransparency = 1
	currency.AnchorPoint = Vector2.new(1, 0)
	currency.Position = UDim2.new(1, -14, 0, 10)
	currency.Size = UDim2.new(0, 140, 0, 22)
	currency.Font = Enum.Font.GothamBold
	currency.TextSize = 14
	currency.TextColor3 = TEXT_COLOR
	currency.TextXAlignment = Enum.TextXAlignment.Right
	currency.Text = "🧱 0"
	currency.Parent = frame
	currencyLabel = currency

	local scroll = Instance.new("ScrollingFrame")
	scroll.Position = UDim2.new(0, 14, 0, 40)
	scroll.Size = UDim2.new(1, -28, 1, -54)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 6
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	scroll.Parent = frame
	listFrame = scroll

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 6)
	layout.Parent = scroll

	toggle.Activated:Connect(function()
		frame.Visible = not frame.Visible
		if frame.Visible then
			refreshList()
		end
	end)
end

-- Shop-Stand in der Lobby: Wer aufs blaue Pad läuft, öffnet den Shop
-- automatisch (und beim Weglaufen schließt er wieder). Reine Client-Nähe -
-- die Käufe selbst validiert weiterhin komplett der Server.
local function watchShopPad()
	task.spawn(function()
		local Workspace = game:GetService("Workspace")
		local lobby = Workspace:WaitForChild("Lobby", 30)
		if lobby == nil then
			return
		end
		local pad = lobby:WaitForChild("ShopPad", 30)
		if pad == nil or not pad:IsA("BasePart") then
			return
		end

		local wasNear = false
		while true do
			task.wait(0.4)
			local character = Players.LocalPlayer.Character
			local root = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
			if root == nil or not root:IsA("BasePart") then
				continue
			end
			local near = ((root :: BasePart).Position - (pad :: BasePart).Position).Magnitude <= 7
			if near and not wasNear and panel ~= nil then
				(panel :: Frame).Visible = true
				refreshList()
			elseif not near and wasNear and panel ~= nil then
				(panel :: Frame).Visible = false
			end
			wasNear = near
		end
	end)
end

function ShopUIController.init()
	buyDebrisFunction = Network.getFunction("BuySkinWithDebris")
	simulateFunction = Network.getFunction("SimulatePurchase")
	buildUI()
	watchShopPad()

	Network.getEvent("SkinsChanged").OnClientEvent:Connect(function(owned: any, _equipped: any, truemmerArg: any)
		if typeof(owned) == "table" then
			table.clear(ownedSkins)
			for _, skinId in owned :: { string } do
				ownedSkins[skinId] = true
			end
		end
		if typeof(truemmerArg) == "number" then
			truemmer = truemmerArg
			if currencyLabel ~= nil then
				(currencyLabel :: TextLabel).Text = `🧱 {truemmer}`
			end
		end
		if panel ~= nil and (panel :: Frame).Visible then
			refreshList()
		end
	end)
end

return ShopUIController
