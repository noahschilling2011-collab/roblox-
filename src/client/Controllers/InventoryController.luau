--!strict
-- InventoryController: Inventar-Screen für gezogene Loot-Items.
--
-- Grid aller besessenen Items, gruppiert nach Typ (Pets/Trails/Skins),
-- Rarity-Farbrahmen aus RarityConfig, Duplikate mit Zähler, Tooltip mit
-- Name/Rarity/Bonus/Herkunft. Klick rüstet aus bzw. ab (EquipItem);
-- ausgerüstete Items zeigen einen goldenen Rahmen mit Haken.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ConfigFolder = Shared:WaitForChild("Config")
local ControllersFolder = script.Parent :: Instance

local Remotes = require(Shared:WaitForChild("Remotes") :: ModuleScript) :: {
	getEvent: (name: string) -> RemoteEvent,
	getFunction: (name: string) -> RemoteFunction,
}
type CollectibleDef = {
	id: string,
	displayName: string,
	description: string,
	rarity: string,
	itemType: string?,
	bonusMultiplier: number?,
}
local CollectibleConfig = require(ConfigFolder:WaitForChild("CollectibleConfig") :: ModuleScript) :: {
	Collectibles: { [string]: CollectibleDef },
}
local RarityConfig = require(ConfigFolder:WaitForChild("RarityConfig") :: ModuleScript) :: {
	Tiers: { [string]: { displayName: string, color: Color3 } },
	TierOrder: { string },
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
local ACCENT_COLOR = Color3.fromRGB(214, 160, 72)

local TYPE_ICONS: { [string]: string } = { pet = "🐾", trail = "✨", skin = "🌟" }
local TYPE_NAMES: { [string]: string } = { pet = "Pets", trail = "Trails", skin = "Skins" }
local SOURCE_NAMES: { [string]: string } = { loot = "Fund-Wurf", trade = "Handel", event = "Event" }

local InventoryController = {}

local localPlayer = Players.LocalPlayer

-- Besitz (aus PlanetUpdated) und Ausrüstung (aus EquipmentUpdated).
type OwnedGroup = { collectibleId: string, uids: { string }, source: string }
local groups: { [string]: OwnedGroup } = {}
local equippedUids: { [string]: boolean } = {}
local maxPetSlots = 3
local equippedPetCount = 0

local panel: Frame? = nil
local sectionFrames: { [string]: Frame } = {}
local sectionHeaders: { [string]: TextLabel } = {}
local tooltipLabel: TextLabel? = nil

local equipFunction: RemoteFunction? = nil

local function addCorner(instance: Instance, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = instance
end

local function addStroke(instance: Instance, color: Color3): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = 1
	stroke.Parent = instance
	return stroke
end

-- Tooltip-Inhalt für eine Item-Gruppe.
local function tooltipText(group: OwnedGroup): string
	local def = CollectibleConfig.Collectibles[group.collectibleId]
	if def == nil then
		return group.collectibleId
	end
	local tier = RarityConfig.Tiers[def.rarity]
	local rarityName = if tier ~= nil then tier.displayName else def.rarity
	local itemType = def.itemType or "pet"

	local bonusText = ""
	if itemType == "pet" then
		local bonus = def.bonusMultiplier or 1
		bonusText = `  |  Bonus: ×{string.format("%.2f", bonus)}`
	end
	local source = SOURCE_NAMES[group.source] or group.source
	return `{def.displayName}  |  {rarityName}{bonusText}  |  Herkunft: {source}  |  Anzahl: {#group.uids}`
end

-- Klick auf eine Zelle: aus- oder anlegen.
local function onCellClicked(group: OwnedGroup)
	local remote = equipFunction
	if remote == nil then
		return
	end

	-- Ausgerüstete uid dieser Gruppe suchen; sonst erste freie nehmen.
	local equippedUid: string? = nil
	local freeUid: string? = nil
	for _, uid in group.uids do
		if equippedUids[uid] then
			equippedUid = uid
		elseif freeUid == nil then
			freeUid = uid
		end
	end

	local targetUid = equippedUid or freeUid
	if targetUid == nil then
		return
	end
	local equip = equippedUid == nil

	task.spawn(function()
		local ok, serverOk, err = pcall(function()
			return remote:InvokeServer(targetUid, equip)
		end)
		if not ok then
			UIController.showToast("Verbindungsfehler – bitte erneut versuchen.", "error")
		elseif serverOk ~= true and typeof(err) == "string" then
			UIController.showToast(err, "error")
		else
			EffectsController.playSound("pop", if equip then 1.1 else 0.9)
		end
	end)
end

-- Inventar-Grid neu aufbauen.
local function rebuild()
	if panel == nil then
		return
	end

	for _, frame in sectionFrames do
		for _, child in frame:GetChildren() do
			if not child:IsA("UIGridLayout") then
				child:Destroy()
			end
		end
	end

	-- Gruppen nach Typ und Seltenheit (selten zuerst) sortieren.
	local byType: { [string]: { OwnedGroup } } = { pet = {}, trail = {}, skin = {} }
	for _, group in groups do
		local def = CollectibleConfig.Collectibles[group.collectibleId]
		local itemType = if def ~= nil then def.itemType or "pet" else "pet"
		table.insert(byType[itemType] or byType.pet, group)
	end

	local rarityOrder: { [string]: number } = {}
	for index, tierName in RarityConfig.TierOrder do
		rarityOrder[tierName] = index
	end

	equippedPetCount = 0
	for _, group in groups do
		local def = CollectibleConfig.Collectibles[group.collectibleId]
		if def ~= nil and (def.itemType or "pet") == "pet" then
			for _, uid in group.uids do
				if equippedUids[uid] then
					equippedPetCount += 1
				end
			end
		end
	end

	for itemType, list in byType do
		table.sort(list, function(a, b)
			local defA = CollectibleConfig.Collectibles[a.collectibleId]
			local defB = CollectibleConfig.Collectibles[b.collectibleId]
			local orderA = if defA ~= nil then rarityOrder[defA.rarity] or 0 else 0
			local orderB = if defB ~= nil then rarityOrder[defB.rarity] or 0 else 0
			if orderA ~= orderB then
				return orderA > orderB
			end
			return a.collectibleId < b.collectibleId
		end)

		local header = sectionHeaders[itemType]
		if header ~= nil then
			local suffix = if itemType == "pet" then ` ({equippedPetCount}/{maxPetSlots} ausgerüstet)` else ""
			header.Text = `{TYPE_ICONS[itemType]} {TYPE_NAMES[itemType]}{suffix}`
		end

		local frame = sectionFrames[itemType]
		if frame == nil then
			continue
		end

		for _, group in list do
			local def = CollectibleConfig.Collectibles[group.collectibleId]
			if def == nil then
				continue
			end
			local tier = RarityConfig.Tiers[def.rarity]
			local rarityColor = if tier ~= nil then tier.color else TEXT_COLOR

			local isEquipped = false
			for _, uid in group.uids do
				if equippedUids[uid] then
					isEquipped = true
					break
				end
			end

			local cell = Instance.new("TextButton")
			cell.Name = `Item_{group.collectibleId}`
			cell.Text = ""
			cell.BackgroundColor3 = ROW_COLOR
			addCorner(cell, 10)
			local stroke = addStroke(cell, if isEquipped then ACCENT_COLOR else rarityColor)
			stroke.Thickness = if isEquipped then 3 else 2
			cell.Parent = frame

			local icon = Instance.new("TextLabel")
			icon.BackgroundTransparency = 1
			icon.Position = UDim2.new(0, 0, 0, 4)
			icon.Size = UDim2.new(1, 0, 0, 26)
			icon.Font = Enum.Font.GothamBold
			icon.TextSize = 22
			icon.Text = TYPE_ICONS[def.itemType or "pet"] or "🎁"
			icon.Parent = cell

			local nameLabel = Instance.new("TextLabel")
			nameLabel.BackgroundTransparency = 1
			nameLabel.Position = UDim2.new(0, 2, 0, 32)
			nameLabel.Size = UDim2.new(1, -4, 0, 26)
			nameLabel.Font = Enum.Font.GothamMedium
			nameLabel.TextSize = 10
			nameLabel.TextColor3 = rarityColor
			nameLabel.TextWrapped = true
			nameLabel.Text = def.displayName
			nameLabel.Parent = cell

			if #group.uids > 1 then
				local count = Instance.new("TextLabel")
				count.BackgroundColor3 = PANEL_COLOR
				count.AnchorPoint = Vector2.new(1, 1)
				count.Position = UDim2.new(1, -2, 1, -2)
				count.Size = UDim2.new(0, 24, 0, 14)
				count.Font = Enum.Font.GothamBold
				count.TextSize = 10
				count.TextColor3 = TEXT_COLOR
				count.Text = `×{#group.uids}`
				addCorner(count, 6)
				count.Parent = cell
			end

			if isEquipped then
				local check = Instance.new("TextLabel")
				check.BackgroundTransparency = 1
				check.Position = UDim2.new(0, 4, 0, 2)
				check.Size = UDim2.new(0, 16, 0, 16)
				check.Font = Enum.Font.GothamBold
				check.TextSize = 14
				check.TextColor3 = ACCENT_COLOR
				check.Text = "✓"
				check.Parent = cell
			end

			cell.MouseEnter:Connect(function()
				if tooltipLabel ~= nil then
					tooltipLabel.Text = tooltipText(group)
				end
			end)
			cell.MouseLeave:Connect(function()
				if tooltipLabel ~= nil then
					tooltipLabel.Text = "Fahre über ein Item für Details – Klick rüstet aus/ab."
				end
			end)
			cell.Activated:Connect(function()
				onCellClicked(group)
			end)
		end
	end
end

local function buildUI()
	local playerGui = localPlayer:WaitForChild("PlayerGui")

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "PlanetForgeInventory"
	screenGui.ResetOnSpawn = false
	screenGui.DisplayOrder = 15
	screenGui.Parent = playerGui

	local toggleButton = Instance.new("TextButton")
	toggleButton.Name = "InventoryToggle"
	toggleButton.Position = UDim2.new(0, 14, 0, 62)
	toggleButton.Size = UDim2.new(0, 150, 0, 38)
	toggleButton.BackgroundColor3 = PANEL_COLOR
	toggleButton.Font = Enum.Font.GothamBold
	toggleButton.TextSize = 14
	toggleButton.TextColor3 = TEXT_COLOR
	toggleButton.Text = "🎒 Inventar"
	addCorner(toggleButton, 10)
	addStroke(toggleButton, STROKE_COLOR)
	toggleButton.Parent = screenGui

	local frame = Instance.new("Frame")
	frame.Name = "InventoryPanel"
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.new(0.5, 0, 0.45, 0)
	frame.Size = UDim2.new(0, 470, 0, 440)
	frame.BackgroundColor3 = PANEL_COLOR
	frame.Visible = false
	addCorner(frame, 12)
	addStroke(frame, STROKE_COLOR)
	frame.Parent = screenGui

	toggleButton.Activated:Connect(function()
		frame.Visible = not frame.Visible
	end)

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Position = UDim2.new(0, 14, 0, 10)
	title.Size = UDim2.new(1, -28, 0, 22)
	title.Font = Enum.Font.GothamBold
	title.TextSize = 16
	title.TextColor3 = TEXT_COLOR
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = "🎒 Inventar"
	title.Parent = frame

	local scroll = Instance.new("ScrollingFrame")
	scroll.Position = UDim2.new(0, 10, 0, 38)
	scroll.Size = UDim2.new(1, -20, 1, -80)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 6
	scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.Parent = frame

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 8)
	layout.Parent = scroll

	local order = 0
	for _, itemType in { "pet", "trail", "skin" } do
		order += 1
		local header = Instance.new("TextLabel")
		header.Name = `Header_{itemType}`
		header.BackgroundTransparency = 1
		header.Size = UDim2.new(1, 0, 0, 20)
		header.Font = Enum.Font.GothamBold
		header.TextSize = 13
		header.TextColor3 = ACCENT_COLOR
		header.TextXAlignment = Enum.TextXAlignment.Left
		header.Text = `{TYPE_ICONS[itemType]} {TYPE_NAMES[itemType]}`
		header.LayoutOrder = order
		header.Parent = scroll
		sectionHeaders[itemType] = header

		order += 1
		local section = Instance.new("Frame")
		section.Name = `Section_{itemType}`
		section.BackgroundTransparency = 1
		section.Size = UDim2.new(1, 0, 0, 0)
		section.AutomaticSize = Enum.AutomaticSize.Y
		section.LayoutOrder = order
		section.Parent = scroll

		local grid = Instance.new("UIGridLayout")
		grid.CellSize = UDim2.new(0, 80, 0, 64)
		grid.CellPadding = UDim2.new(0, 6, 0, 6)
		grid.SortOrder = Enum.SortOrder.LayoutOrder
		grid.Parent = section

		sectionFrames[itemType] = section
	end

	-- Tooltip-Zeile am unteren Rand.
	local tooltip = Instance.new("TextLabel")
	tooltip.Name = "Tooltip"
	tooltip.BackgroundColor3 = ROW_COLOR
	tooltip.AnchorPoint = Vector2.new(0.5, 1)
	tooltip.Position = UDim2.new(0.5, 0, 1, -10)
	tooltip.Size = UDim2.new(1, -20, 0, 26)
	tooltip.Font = Enum.Font.GothamMedium
	tooltip.TextSize = 11
	tooltip.TextColor3 = SUBTEXT_COLOR
	tooltip.TextTruncate = Enum.TextTruncate.AtEnd
	tooltip.Text = "Fahre über ein Item für Details – Klick rüstet aus/ab."
	addCorner(tooltip, 8)
	tooltip.Parent = frame

	panel = frame
	tooltipLabel = tooltip
end

function InventoryController.init()
	equipFunction = Remotes.getFunction("EquipItem")

	-- Besitz aus dem Insel-Snapshot gruppieren.
	Remotes.getEvent("PlanetUpdated").OnClientEvent:Connect(function(snapshot: any)
		if typeof(snapshot) ~= "table" or typeof(snapshot.collectibles) ~= "table" then
			return
		end
		groups = {}
		for _, owned in snapshot.collectibles :: { any } do
			if typeof(owned) == "table" and typeof(owned.uid) == "string" and typeof(owned.collectibleId) == "string" then
				local group = groups[owned.collectibleId]
				if group == nil then
					group = {
						collectibleId = owned.collectibleId,
						uids = {},
						source = if typeof(owned.source) == "string" then owned.source else "loot",
					}
					groups[owned.collectibleId] = group
				end
				table.insert(group.uids, owned.uid)
			end
		end
		rebuild()
	end)

	-- Ausrüstungs-Stand übernehmen.
	Remotes.getEvent("EquipmentUpdated").OnClientEvent:Connect(function(equipped: any)
		if typeof(equipped) ~= "table" then
			return
		end
		equippedUids = {}
		if typeof(equipped.pets) == "table" then
			for _, uid in equipped.pets :: { any } do
				if typeof(uid) == "string" then
					equippedUids[uid] = true
				end
			end
		end
		if typeof(equipped.trail) == "string" then
			equippedUids[equipped.trail] = true
		end
		if typeof(equipped.skin) == "string" then
			equippedUids[equipped.skin] = true
		end
		if typeof(equipped.maxPetSlots) == "number" then
			maxPetSlots = equipped.maxPetSlots
		end
		rebuild()
	end)

	buildUI()
end

return InventoryController
