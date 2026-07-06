--!strict
-- PlanetBuilderController: Bau-Menü am linken Bildschirmrand.
-- Aufklappbares Panel "Biome" (Kauf über PlaceBiome) und Abschnitt
-- "Meine Slots" mit den 12 Planeten-Slots (Upgrade über UpgradeBiome).
-- Der letzte PlanetUpdated-Snapshot wird lokal gecacht, um freie Slots und
-- Upgrade-Kosten anzuzeigen; der Server bleibt autoritativ.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ConfigFolder = Shared:WaitForChild("Config")
local ControllersFolder = script.Parent :: Instance

local Remotes = require(Shared:WaitForChild("Remotes") :: ModuleScript) :: {
	getEvent: (name: string) -> RemoteEvent,
	getFunction: (name: string) -> RemoteFunction,
}
local GameConfig = require(ConfigFolder:WaitForChild("GameConfig") :: ModuleScript) :: {
	PLANET_SLOTS: number,
}

type BiomeDef = {
	id: string,
	displayName: string,
	baseCost: number,
	maxLevel: number,
	color: Color3,
	unlockAtLifetimeEnergy: number,
}
type PlacedBiome = { biomeId: string, slot: number, level: number, placedAt: number }
type PlanetSnapshot = { biomes: { PlacedBiome }, visits: number, likes: number }
type BiomeRow = { button: TextButton, swatch: Frame, nameLabel: TextLabel, costLabel: TextLabel, lockLabel: TextLabel }
type SlotRow = { infoLabel: TextLabel, upgradeButton: TextButton }

local BiomeConfig = require(ConfigFolder:WaitForChild("BiomeConfig") :: ModuleScript) :: {
	Biomes: { [string]: BiomeDef },
	getSortedIds: () -> { string },
	getUpgradeCost: (biomeId: string, currentLevel: number) -> number,
}
local UIController = require(ControllersFolder:WaitForChild("UIController") :: ModuleScript) :: {
	showToast: (message: string, kind: string) -> (),
}
type UpgradeDef = { id: string, displayName: string, description: string, maxLevel: number }
local ProgressionConfig = require(ConfigFolder:WaitForChild("ProgressionConfig") :: ModuleScript) :: {
	Upgrades: { [string]: UpgradeDef },
	getUpgradeCost: (upgradeId: string, currentLevel: number) -> number,
}

-- Farbschema (identisch zum UIController).
local PANEL_COLOR = Color3.fromRGB(30, 32, 44)
local ROW_COLOR = Color3.fromRGB(44, 47, 63)
local STROKE_COLOR = Color3.fromRGB(70, 75, 100)
local TEXT_COLOR = Color3.fromRGB(235, 238, 245)
local SUBTEXT_COLOR = Color3.fromRGB(158, 164, 186)
local LOCKED_TEXT_COLOR = Color3.fromRGB(110, 114, 132)
local LOCK_HINT_COLOR = Color3.fromRGB(214, 160, 72)
local CANNOT_AFFORD_COLOR = Color3.fromRGB(214, 110, 110)
local UPGRADE_BUTTON_COLOR = Color3.fromRGB(52, 96, 178)
local UPGRADE_MAX_COLOR = Color3.fromRGB(60, 64, 84)

local PlanetBuilderController = {}

-- Lokaler Cache aus PlanetUpdated / EnergyChanged.
local lastSnapshot: PlanetSnapshot? = nil
local currentEnergy = 0
local lifetimeEnergy = 0

local biomeRows: { [string]: BiomeRow } = {}
local slotRows: { SlotRow } = {}

-- Insel-Upgrades (Magnet, Rucksack) aus ProgressionConfig.
type UpgradeRow = { infoLabel: TextLabel, buyButton: TextButton }
local upgradeRows: { [string]: UpgradeRow } = {}
local upgradeLevels: { [string]: number } = {}

-- 1234567 -> "1.234.567" (deutsche Tausendertrennung mit Punkt).
local function formatNumber(value: number): string
	local text = tostring(math.floor(value + 0.5))
	while true do
		local replaced: number
		text, replaced = text:gsub("^(-?%d+)(%d%d%d)", "%1.%2")
		if replaced == 0 then
			break
		end
	end
	return text
end

local function addCorner(parent: Instance, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = parent
end

local function createLabel(parent: Instance, name: string, text: string, position: UDim2, size: UDim2): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamMedium
	label.TextColor3 = TEXT_COLOR
	label.TextSize = 13
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Text = text
	label.Position = position
	label.Size = size
	label.Parent = parent
	return label
end

-- Ruft eine RemoteFunction auf; bei ok=false erscheint die deutsche
-- Fehlermeldung des Servers als Toast, bei Erfolg optional eine Bestätigung.
local function invokeRemote(functionName: string, successMessage: string?, ...: any)
	local args = table.pack(...)
	task.spawn(function()
		local ok, serverOk, payload = pcall(function()
			return Remotes.getFunction(functionName):InvokeServer(table.unpack(args, 1, args.n))
		end)
		if not ok then
			UIController.showToast("Verbindungsfehler – bitte erneut versuchen.", "error")
		elseif serverOk ~= true then
			UIController.showToast(if typeof(payload) == "string" then payload else "Aktion fehlgeschlagen.", "error")
		elseif successMessage ~= nil then
			UIController.showToast(successMessage, "success")
		end
	end)
end

-- Zeilen der Insel-Upgrades aktuell halten (Level, Kosten, Färbung).
local function refreshUpgradeRows()
	for upgradeId, row in upgradeRows do
		local def = ProgressionConfig.Upgrades[upgradeId]
		local level = upgradeLevels[upgradeId] or 0
		row.infoLabel.Text = `{def.displayName}  Lv. {level}`
		if level >= def.maxLevel then
			row.buyButton.Text = "Max"
			row.buyButton.BackgroundColor3 = UPGRADE_MAX_COLOR
			row.buyButton.AutoButtonColor = false
		else
			local cost = ProgressionConfig.getUpgradeCost(upgradeId, level)
			row.buyButton.Text = `Kaufen ({formatNumber(cost)})`
			row.buyButton.BackgroundColor3 = if currentEnergy >= cost then UPGRADE_BUTTON_COLOR else CANNOT_AFFORD_COLOR
		end
	end
end

-- Zeile für ein Insel-Upgrade anlegen.
local function createUpgradeRow(parent: Instance, def: UpgradeDef, order: number): UpgradeRow
	local row = Instance.new("Frame")
	row.Name = `Upgrade_{def.id}`
	row.Size = UDim2.new(1, -8, 0, 52)
	row.BackgroundColor3 = ROW_COLOR
	row.LayoutOrder = order
	addCorner(row, 8)
	row.Parent = parent

	local infoLabel = createLabel(row, "Info", def.displayName, UDim2.new(0, 10, 0, 6), UDim2.new(1, -140, 0, 18))
	infoLabel.Font = Enum.Font.GothamBold
	infoLabel.TextSize = 13

	local descLabel = createLabel(row, "Desc", def.description, UDim2.new(0, 10, 0, 26), UDim2.new(1, -140, 0, 22))
	descLabel.TextSize = 11
	descLabel.TextColor3 = SUBTEXT_COLOR
	descLabel.TextWrapped = true

	local buyButton = Instance.new("TextButton")
	buyButton.Name = "Buy"
	buyButton.AnchorPoint = Vector2.new(1, 0.5)
	buyButton.Position = UDim2.new(1, -8, 0.5, 0)
	buyButton.Size = UDim2.new(0, 118, 0, 30)
	buyButton.BackgroundColor3 = UPGRADE_BUTTON_COLOR
	buyButton.Font = Enum.Font.GothamBold
	buyButton.TextSize = 12
	buyButton.TextColor3 = TEXT_COLOR
	buyButton.Text = "Kaufen"
	addCorner(buyButton, 8)
	buyButton.Parent = row

	buyButton.Activated:Connect(function()
		invokeRemote("BuyUpgrade", `{def.displayName} verbessert!`, def.id)
	end)

	return { infoLabel = infoLabel, buyButton = buyButton }
end

-- Klick auf eine Biom-Zeile: nächsten freien Slot suchen und kaufen.
local function onBiomeClicked(biomeId: string)
	local def = BiomeConfig.Biomes[biomeId]
	if def == nil then
		return
	end
	if lifetimeEnergy < def.unlockAtLifetimeEnergy then
		UIController.showToast(
			`{def.displayName} ist noch gesperrt – ab {formatNumber(def.unlockAtLifetimeEnergy)} Gesamt-Energie.`,
			"error"
		)
		return
	end

	local snapshot = lastSnapshot
	if snapshot == nil then
		UIController.showToast("Dein Planet lädt noch – versuche es gleich erneut.", "error")
		return
	end

	local occupied: { [number]: boolean } = {}
	for _, placed in snapshot.biomes do
		occupied[placed.slot] = true
	end
	for slot = 1, GameConfig.PLANET_SLOTS do
		if not occupied[slot] then
			invokeRemote("PlaceBiome", `{def.displayName} platziert!`, biomeId, slot)
			return
		end
	end
	UIController.showToast(`Alle {GameConfig.PLANET_SLOTS} Slots sind belegt.`, "error")
end

-- Klick auf den Upgrade-Button eines Slots.
local function onUpgradeClicked(slot: number)
	local snapshot = lastSnapshot
	if snapshot == nil then
		return
	end
	for _, placed in snapshot.biomes do
		if placed.slot == slot then
			local def = BiomeConfig.Biomes[placed.biomeId]
			if def ~= nil and placed.level >= def.maxLevel then
				UIController.showToast("Dieses Biom ist bereits auf Maximalstufe.", "info")
			else
				invokeRemote("UpgradeBiome", "Biom verbessert!", slot)
			end
			return
		end
	end
end

-- Sperr-/Kostenanzeige der Biom-Liste aktualisieren.
local function refreshBiomeRows()
	for biomeId, row in biomeRows do
		local def = BiomeConfig.Biomes[biomeId]
		if def == nil then
			continue
		end
		if lifetimeEnergy < def.unlockAtLifetimeEnergy then
			row.nameLabel.TextColor3 = LOCKED_TEXT_COLOR
			row.costLabel.TextColor3 = LOCKED_TEXT_COLOR
			row.swatch.BackgroundTransparency = 0.65
			row.button.AutoButtonColor = false
			row.lockLabel.Text = `Gesperrt – ab {formatNumber(def.unlockAtLifetimeEnergy)} Gesamt-Energie`
			row.lockLabel.Visible = true
		else
			row.nameLabel.TextColor3 = TEXT_COLOR
			-- Kosten rot einfärben, wenn die aktuelle Energie nicht reicht.
			row.costLabel.TextColor3 = if currentEnergy >= def.baseCost then SUBTEXT_COLOR else CANNOT_AFFORD_COLOR
			row.swatch.BackgroundTransparency = 0
			row.button.AutoButtonColor = true
			row.lockLabel.Visible = false
		end
	end
end

-- Slot-Übersicht aus dem gecachten Snapshot neu aufbauen.
local function refreshSlotRows()
	local bySlot: { [number]: PlacedBiome } = {}
	local snapshot = lastSnapshot
	if snapshot ~= nil then
		for _, placed in snapshot.biomes do
			bySlot[placed.slot] = placed
		end
	end

	for slot, row in slotRows do
		local placed = bySlot[slot]
		if placed == nil then
			row.infoLabel.Text = "frei"
			row.infoLabel.TextColor3 = SUBTEXT_COLOR
			row.upgradeButton.Visible = false
		else
			local def = BiomeConfig.Biomes[placed.biomeId]
			local displayName = if def ~= nil then def.displayName else placed.biomeId
			local maxLevel = if def ~= nil then def.maxLevel else 5
			row.infoLabel.Text = `{displayName}  Lv. {placed.level}`
			row.infoLabel.TextColor3 = TEXT_COLOR
			row.upgradeButton.Visible = true
			if placed.level >= maxLevel then
				row.upgradeButton.Text = "Max"
				row.upgradeButton.BackgroundColor3 = UPGRADE_MAX_COLOR
				row.upgradeButton.AutoButtonColor = false
			else
				local cost = BiomeConfig.getUpgradeCost(placed.biomeId, placed.level)
				row.upgradeButton.Text = `Upgrade ({formatNumber(cost)})`
				row.upgradeButton.BackgroundColor3 = UPGRADE_BUTTON_COLOR
				row.upgradeButton.AutoButtonColor = true
			end
		end
	end
end

local function createBiomeRow(parent: Instance, def: BiomeDef, order: number): BiomeRow
	local row = Instance.new("TextButton")
	row.Name = def.id
	row.LayoutOrder = order
	row.Size = UDim2.new(1, -8, 0, 46)
	row.BackgroundColor3 = ROW_COLOR
	row.Text = ""
	row.AutoButtonColor = true
	addCorner(row, 8)
	row.Parent = parent

	local swatch = Instance.new("Frame")
	swatch.Name = "Swatch"
	swatch.Position = UDim2.new(0, 8, 0, 8)
	swatch.Size = UDim2.new(0, 10, 1, -16)
	swatch.BackgroundColor3 = def.color
	swatch.BorderSizePixel = 0
	addCorner(swatch, 4)
	swatch.Parent = row

	local nameLabel =
		createLabel(row, "BiomeName", def.displayName, UDim2.new(0, 28, 0, 5), UDim2.new(0.5, -28, 0, 18))
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextSize = 14

	local costText = `Kosten: {formatNumber(def.baseCost)}`
	local costLabel = createLabel(row, "Cost", costText, UDim2.new(0, 28, 0, 24), UDim2.new(0.5, -28, 0, 16))
	costLabel.TextSize = 11
	costLabel.TextColor3 = SUBTEXT_COLOR

	local lockLabel = createLabel(row, "Lock", "", UDim2.new(1, -8, 0, 0), UDim2.new(0.5, -32, 1, 0))
	lockLabel.AnchorPoint = Vector2.new(1, 0)
	lockLabel.TextSize = 10
	lockLabel.TextColor3 = LOCK_HINT_COLOR
	lockLabel.TextXAlignment = Enum.TextXAlignment.Right
	lockLabel.TextWrapped = true
	lockLabel.Visible = false

	row.Activated:Connect(function()
		onBiomeClicked(def.id)
	end)

	return { button = row, swatch = swatch, nameLabel = nameLabel, costLabel = costLabel, lockLabel = lockLabel }
end

local function createSlotRow(parent: Instance, slot: number, order: number): SlotRow
	local row = Instance.new("Frame")
	row.Name = `Slot{slot}`
	row.LayoutOrder = order
	row.Size = UDim2.new(1, -8, 0, 40)
	row.BackgroundColor3 = ROW_COLOR
	addCorner(row, 8)
	row.Parent = parent

	local slotLabel = createLabel(row, "SlotNumber", `Zone {slot}`, UDim2.new(0, 10, 0, 0), UDim2.new(0, 52, 1, 0))
	slotLabel.TextSize = 11
	slotLabel.TextColor3 = SUBTEXT_COLOR

	local infoLabel = createLabel(row, "Info", "frei", UDim2.new(0, 66, 0, 0), UDim2.new(1, -206, 1, 0))
	infoLabel.TextColor3 = SUBTEXT_COLOR

	local upgradeButton = Instance.new("TextButton")
	upgradeButton.Name = "Upgrade"
	upgradeButton.AnchorPoint = Vector2.new(1, 0.5)
	upgradeButton.Position = UDim2.new(1, -8, 0.5, 0)
	upgradeButton.Size = UDim2.new(0, 126, 0, 28)
	upgradeButton.BackgroundColor3 = UPGRADE_BUTTON_COLOR
	upgradeButton.Font = Enum.Font.GothamBold
	upgradeButton.TextSize = 11
	upgradeButton.TextColor3 = TEXT_COLOR
	upgradeButton.Text = ""
	upgradeButton.Visible = false
	addCorner(upgradeButton, 6)
	upgradeButton.Activated:Connect(function()
		onUpgradeClicked(slot)
	end)
	upgradeButton.Parent = row

	return { infoLabel = infoLabel, upgradeButton = upgradeButton }
end

local function buildGui(playerGui: PlayerGui)
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "PlanetForgeBuildUI"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.DisplayOrder = 9

	-- Toggle-Button klappt das Panel auf und zu.
	local toggleButton = Instance.new("TextButton")
	toggleButton.Name = "ToggleBiomes"
	toggleButton.Position = UDim2.new(0, 14, 0, 110)
	toggleButton.Size = UDim2.new(0, 150, 0, 38)
	toggleButton.BackgroundColor3 = PANEL_COLOR
	toggleButton.Font = Enum.Font.GothamBold
	toggleButton.TextSize = 15
	toggleButton.TextColor3 = TEXT_COLOR
	toggleButton.Text = "Biome"
	addCorner(toggleButton, 10)
	local stroke = Instance.new("UIStroke")
	stroke.Color = STROKE_COLOR
	stroke.Thickness = 1
	stroke.Parent = toggleButton
	toggleButton.Parent = screenGui

	local panel = Instance.new("Frame")
	panel.Name = "BuildPanel"
	panel.Position = UDim2.new(0, 14, 0, 154)
	panel.Size = UDim2.new(0, 330, 0.6, 0)
	panel.BackgroundColor3 = PANEL_COLOR
	panel.BackgroundTransparency = 0.05
	panel.Visible = false
	addCorner(panel, 10)
	panel.Parent = screenGui

	toggleButton.Activated:Connect(function()
		panel.Visible = not panel.Visible
	end)

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Content"
	scroll.Position = UDim2.new(0, 8, 0, 8)
	scroll.Size = UDim2.new(1, -16, 1, -16)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 6
	scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.Parent = panel

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 6)
	layout.Parent = scroll

	local order = 0
	local function nextOrder(): number
		order += 1
		return order
	end

	-- Abschnitt: Insel-Upgrades (Magnet, Rucksack).
	local upgradeHeader =
		createLabel(scroll, "UpgradeHeader", "Insel-Upgrades", UDim2.new(0, 0, 0, 0), UDim2.new(1, -8, 0, 24))
	upgradeHeader.LayoutOrder = nextOrder()
	upgradeHeader.Font = Enum.Font.GothamBold
	upgradeHeader.TextSize = 16

	for _, upgradeId in { "magnet", "backpack" } do
		upgradeRows[upgradeId] = createUpgradeRow(scroll, ProgressionConfig.Upgrades[upgradeId], nextOrder())
	end

	-- Abschnitt: Biom-Liste (sortiert nach Kosten).
	local biomeHeader = createLabel(scroll, "BiomeHeader", "Biome", UDim2.new(0, 0, 0, 0), UDim2.new(1, -8, 0, 24))
	biomeHeader.LayoutOrder = nextOrder()
	biomeHeader.Font = Enum.Font.GothamBold
	biomeHeader.TextSize = 16

	for _, biomeId in BiomeConfig.getSortedIds() do
		biomeRows[biomeId] = createBiomeRow(scroll, BiomeConfig.Biomes[biomeId], nextOrder())
	end

	-- Abschnitt: die 12 Zonen der eigenen Insel.
	local slotsHeader =
		createLabel(scroll, "SlotsHeader", "Meine Zonen", UDim2.new(0, 0, 0, 0), UDim2.new(1, -8, 0, 24))
	slotsHeader.LayoutOrder = nextOrder()
	slotsHeader.Font = Enum.Font.GothamBold
	slotsHeader.TextSize = 16

	for slot = 1, GameConfig.PLANET_SLOTS do
		slotRows[slot] = createSlotRow(scroll, slot, nextOrder())
	end

	screenGui.Parent = playerGui
end

function PlanetBuilderController.init()
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui

	buildGui(playerGui)
	refreshBiomeRows()
	refreshSlotRows()
	refreshUpgradeRows()

	-- Upgrade-Level vom Server übernehmen.
	Remotes.getEvent("UpgradesUpdated").OnClientEvent:Connect(function(levels: any)
		if typeof(levels) ~= "table" then
			return
		end
		for upgradeId, level in levels :: { [any]: any } do
			if typeof(upgradeId) == "string" and typeof(level) == "number" then
				upgradeLevels[upgradeId] = level
			end
		end
		refreshUpgradeRows()
	end)

	-- Snapshot cachen und Slot-Übersicht aktualisieren.
	Remotes.getEvent("PlanetUpdated").OnClientEvent:Connect(function(snapshot: any)
		if typeof(snapshot) ~= "table" or typeof(snapshot.biomes) ~= "table" then
			return
		end
		lastSnapshot = snapshot :: PlanetSnapshot
		refreshSlotRows()
	end)

	-- Energie-Stände für Freischaltungen und Kostenfärbung übernehmen.
	Remotes.getEvent("EnergyChanged").OnClientEvent:Connect(function(newEnergy: any, newLifetimeEnergy: any)
		if typeof(newEnergy) == "number" then
			currentEnergy = newEnergy
		end
		if typeof(newLifetimeEnergy) == "number" then
			lifetimeEnergy = newLifetimeEnergy
		end
		refreshBiomeRows()
		refreshUpgradeRows()
	end)
end

return PlanetBuilderController
