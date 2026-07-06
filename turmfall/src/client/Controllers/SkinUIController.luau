--!strict
-- SkinUIController: Inventar- und Ausrüsten-UI für Skins.
--
-- Grid mit Raritätsrahmen-Farben (Common grau, Rare blau, Epic lila,
-- Legendary gold). Klick auf einen besessenen Skin rüstet ihn aus
-- (Universal-Skins in alle Teil-Slots, Kollaps-Effekte in den
-- Kollaps-Slot); erneuter Klick rüstet ab. Besitz/Ausrüstung kommen
-- ausschließlich vom Server (SkinsChanged).

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
local CELL_COLOR = Color3.fromRGB(42, 45, 60)
local TEXT_COLOR = Color3.fromRGB(235, 238, 245)
local SUBTEXT_COLOR = Color3.fromRGB(158, 164, 186)
local ACCENT_COLOR = Color3.fromRGB(255, 190, 70)

local SkinUIController = {}

local ownedSkins: { [string]: boolean } = {}
local equipped: { [string]: string } = {}
local truemmer = 0

local panel: Frame? = nil
local grid: ScrollingFrame? = nil
local currencyLabel: TextLabel? = nil

local equipFunction: RemoteFunction? = nil
local buyDebrisFunction: RemoteFunction? = nil
local simulateFunction: RemoteFunction? = nil

local function addCorner(instance: Instance, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = instance
end

local function rarityColor(rarity: string): Color3
	local rgb = SkinCatalog.RarityColors[rarity] or { r = 158, g = 164, b = 186 }
	return Color3.fromRGB(rgb.r, rgb.g, rgb.b)
end

-- Ist der Skin gerade (irgendwo) ausgerüstet?
local function isEquipped(skinId: string): boolean
	for _, equippedId in equipped do
		if equippedId == skinId then
			return true
		end
	end
	return false
end

-- Ziel-Slot beim Klick: Kollaps-Effekte -> "kollaps", Universal -> "alle",
-- teilgebundene Skins -> ihr Teiltyp.
local function slotForSkin(skin: any): string
	if skin.category == "kollaps" then
		return "kollaps"
	end
	return if skin.partType == "alle" then "alle" else skin.partType
end

local function requestEquip(skin: any)
	local remote = equipFunction
	if remote == nil then
		return
	end
	local slot = slotForSkin(skin)
	local newSkinId: string? = if isEquipped(skin.id) then nil else skin.id
	task.spawn(function()
		local ok, serverOk, err = pcall(function()
			return remote:InvokeServer(slot, newSkinId)
		end)
		if not ok then
			UIController.showToast("Verbindungsfehler - bitte erneut versuchen.", "error")
		elseif serverOk ~= true and typeof(err) == "string" then
			UIController.showToast(err, "error")
		end
	end)
end

-- Kauf eines gesperrten Skins anstoßen: Trümmer direkt, Robux über den
-- Roblox-Kaufdialog (bzw. Studio-Testmodus bei Platzhalter-IDs).
local function requestBuy(skin: any)
	if skin.priceDebris ~= nil then
		local remote = buyDebrisFunction
		if remote == nil then
			return
		end
		task.spawn(function()
			local ok, serverOk, err = pcall(function()
				return remote:InvokeServer(skin.id)
			end)
			if not ok then
				UIController.showToast("Verbindungsfehler - bitte erneut versuchen.", "error")
			elseif serverOk ~= true and typeof(err) == "string" then
				UIController.showToast(err, "error")
			end
		end)
		return
	end

	if skin.priceRobux ~= nil then
		-- Passendes Einzel-Produkt im Katalog suchen.
		local productKey: string? = nil
		local productId = 0
		for key, def in MonetizationCatalog.DEVPRODUCT_IDS :: { [string]: any } do
			if #def.grantsSkins == 1 and def.grantsSkins[1] == skin.id then
				productKey = key
				productId = def.productId
				break
			end
		end
		if productKey == nil then
			UIController.showToast("Dieser Skin kommt aus einem Bundle oder dem Season-Pass.", "info")
			return
		end
		if productId ~= 0 then
			MarketplaceService:PromptProductPurchase(Players.LocalPlayer, productId)
		elseif RunService:IsStudio() and simulateFunction ~= nil then
			-- Studio-Testmodus für Platzhalter-IDs.
			task.spawn(function()
				local ok, serverOk, err = pcall(function()
					return (simulateFunction :: RemoteFunction):InvokeServer(productKey)
				end)
				if ok and serverOk == true then
					UIController.showToast("Testkauf simuliert (nur Studio).", "success")
				elseif typeof(err) == "string" then
					UIController.showToast(err, "error")
				end
			end)
		else
			UIController.showToast("Bald verfügbar - die Produkt-ID ist noch nicht eingetragen.", "info")
		end
	end
end

--------------------------------------------------------------------------
-- Grid
--------------------------------------------------------------------------

local function priceText(skin: any): string
	if skin.unlockCondition == "start" then
		return "Start-Skin"
	elseif skin.priceDebris ~= nil then
		return `🧱 {skin.priceDebris} Trümmer`
	elseif skin.priceRobux ~= nil then
		return "R$ (Shop)"
	end
	return "?"
end

local function refreshGrid()
	local container = grid
	if container == nil then
		return
	end
	for _, child in container:GetChildren() do
		if child:IsA("TextButton") then
			child:Destroy()
		end
	end

	for order, skinId in SkinCatalog.getSortedIds() do
		local skin = SkinCatalog.Skins[skinId]
		local owned = ownedSkins[skinId] == true

		local cell = Instance.new("TextButton")
		cell.Name = skinId
		cell.LayoutOrder = order
		cell.Size = UDim2.new(0, 132, 0, 84)
		cell.BackgroundColor3 = CELL_COLOR
		cell.Text = ""
		cell.AutoButtonColor = owned
		addCorner(cell, 10)
		local stroke = Instance.new("UIStroke")
		stroke.Color = rarityColor(skin.rarity)
		stroke.Thickness = if isEquipped(skinId) then 3 else 1.5
		stroke.Parent = cell

		local nameLabel = Instance.new("TextLabel")
		nameLabel.BackgroundTransparency = 1
		nameLabel.Position = UDim2.new(0, 6, 0, 6)
		nameLabel.Size = UDim2.new(1, -12, 0, 34)
		nameLabel.Font = Enum.Font.GothamBold
		nameLabel.TextSize = 13
		nameLabel.TextColor3 = if owned then TEXT_COLOR else SUBTEXT_COLOR
		nameLabel.TextWrapped = true
		nameLabel.Text = skin.name
		nameLabel.Parent = cell

		local rarityLabel = Instance.new("TextLabel")
		rarityLabel.BackgroundTransparency = 1
		rarityLabel.Position = UDim2.new(0, 6, 0, 42)
		rarityLabel.Size = UDim2.new(1, -12, 0, 14)
		rarityLabel.Font = Enum.Font.GothamMedium
		rarityLabel.TextSize = 11
		rarityLabel.TextColor3 = rarityColor(skin.rarity)
		rarityLabel.Text = skin.rarity .. (if skin.category == "kollaps" then " · Kollaps-Effekt" else "")
		rarityLabel.Parent = cell

		local statusLabel = Instance.new("TextLabel")
		statusLabel.BackgroundTransparency = 1
		statusLabel.Position = UDim2.new(0, 6, 1, -22)
		statusLabel.Size = UDim2.new(1, -12, 0, 16)
		statusLabel.Font = Enum.Font.GothamMedium
		statusLabel.TextSize = 11
		statusLabel.TextColor3 = if isEquipped(skinId)
			then ACCENT_COLOR
			elseif owned then Color3.fromRGB(120, 200, 140)
			else SUBTEXT_COLOR
		statusLabel.Text = if isEquipped(skinId) then "✓ Ausgerüstet" elseif owned then "Im Besitz" else `🔒 {priceText(skin)}`
		statusLabel.Parent = cell

		cell.AutoButtonColor = true
		cell.Activated:Connect(function()
			if ownedSkins[skinId] == true then
				requestEquip(skin)
			else
				requestBuy(skin)
			end
		end)
		cell.Parent = container
	end
end

--------------------------------------------------------------------------
-- Panel
--------------------------------------------------------------------------

local function buildUI()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "TurmfallSkins"
	screenGui.ResetOnSpawn = false
	screenGui.DisplayOrder = 20
	screenGui.Parent = playerGui

	local toggle = Instance.new("TextButton")
	toggle.Name = "SkinsToggle"
	toggle.Position = UDim2.new(0, 12, 0, 12)
	toggle.Size = UDim2.new(0, 110, 0, 36)
	toggle.BackgroundColor3 = PANEL_COLOR
	toggle.Font = Enum.Font.GothamBold
	toggle.TextSize = 14
	toggle.TextColor3 = TEXT_COLOR
	toggle.Text = "🎨 Skins"
	addCorner(toggle, 10)
	toggle.Parent = screenGui

	local frame = Instance.new("Frame")
	frame.Name = "SkinPanel"
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.new(0.5, 0, 0.5, 0)
	frame.Size = UDim2.new(0, 460, 0, 360)
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
	title.Size = UDim2.new(1, -28, 0, 22)
	title.Font = Enum.Font.GothamBold
	title.TextSize = 16
	title.TextColor3 = ACCENT_COLOR
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = "🎨 Skins – rein kosmetisch, null Vorteil"
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
	grid = scroll

	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.new(0, 132, 0, 84)
	layout.CellPadding = UDim2.new(0, 8, 0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = scroll

	toggle.Activated:Connect(function()
		frame.Visible = not frame.Visible
	end)
end

--------------------------------------------------------------------------
-- Öffentliche API + Init
--------------------------------------------------------------------------

-- Für den ReplayController: welcher Kollaps-Effekt ist ausgerüstet?
function SkinUIController.getEquippedCollapseEffect(): string?
	local skinId = equipped.kollaps
	if skinId == nil then
		return nil
	end
	local skin = SkinCatalog.Skins[skinId]
	return if skin ~= nil then skin.visualData.effectId else nil
end

function SkinUIController.init()
	equipFunction = Network.getFunction("EquipSkin")
	buyDebrisFunction = Network.getFunction("BuySkinWithDebris")
	simulateFunction = Network.getFunction("SimulatePurchase")
	buildUI()

	Network.getEvent("SkinsChanged").OnClientEvent:Connect(function(owned: any, equippedArg: any, truemmerArg: any)
		if typeof(owned) == "table" then
			table.clear(ownedSkins)
			for _, skinId in owned :: { string } do
				ownedSkins[skinId] = true
			end
		end
		if typeof(equippedArg) == "table" then
			equipped = equippedArg :: { [string]: string }
		end
		if typeof(truemmerArg) == "number" then
			truemmer = truemmerArg
			if currencyLabel ~= nil then
				(currencyLabel :: TextLabel).Text = `🧱 {truemmer}`
			end
		end
		refreshGrid()
	end)
end

return SkinUIController
