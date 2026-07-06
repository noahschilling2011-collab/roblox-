--!strict
-- UIController: baut das komplette HUD von Planet Forge zur Laufzeit per
-- Instance.new auf (Kopfleiste, Aktionsbuttons, Toast-Feed, Loot-Popup,
-- Statistikzeile). Andere Controller zeigen Meldungen über
-- UIController.showToast(message, kind) an.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ConfigFolder = Shared:WaitForChild("Config")

local Remotes = require(Shared:WaitForChild("Remotes") :: ModuleScript) :: {
	getEvent: (name: string) -> RemoteEvent,
	getFunction: (name: string) -> RemoteFunction,
}
local GameConfig = require(ConfigFolder:WaitForChild("GameConfig") :: ModuleScript) :: {
	LOOT_ROLL_COST: number,
}
local RarityConfig = require(ConfigFolder:WaitForChild("RarityConfig") :: ModuleScript) :: {
	Tiers: { [string]: { displayName: string, color: Color3 } },
	TierOrder: { string },
}
local CollectibleConfig = require(ConfigFolder:WaitForChild("CollectibleConfig") :: ModuleScript) :: {
	Collectibles: { [string]: { displayName: string } },
}
local EffectsController = require(script.Parent:WaitForChild("EffectsController") :: ModuleScript) :: {
	playSound: (name: string, pitchOverride: number?) -> (),
	flyEnergyToCounter: (amount: number) -> (),
	burstAtOwnPlanet: (color: Color3?) -> (),
	screenShake: (intensity: number?) -> (),
	addButtonFX: (button: GuiButton) -> (),
	addGradient: (guiObject: GuiObject) -> (),
}

-- Farbschema: dunkle Panels, helle Schrift.
local PANEL_COLOR = Color3.fromRGB(30, 32, 44)
local STROKE_COLOR = Color3.fromRGB(70, 75, 100)
local TEXT_COLOR = Color3.fromRGB(235, 238, 245)
local SUBTEXT_COLOR = Color3.fromRGB(158, 164, 186)

local TOAST_LIFETIME_SECONDS = 4
local FADE_SECONDS = 0.35
local LOOT_POPUP_SECONDS = 3
local LOOT_SUSPENSE_SECONDS = 1.5 -- Spannungsaufbau vor dem Reveal
local LOOT_SUSPENSE_TICK = 0.12

-- Ab diesen Stufen gibt es Screen-Shake + Glow beim Reveal.
local HIGH_TIER: { [string]: boolean } = {
	Legendary = true,
	Mythic = true,
	Cosmic = true,
}

local TOAST_COLORS: { [string]: Color3 } = {
	info = Color3.fromRGB(66, 133, 244),
	success = Color3.fromRGB(76, 175, 110),
	error = Color3.fromRGB(214, 72, 72),
}

local UIController = {}

-- Wird in init() gesetzt; showToast() wartet notfalls kurz darauf.
local toastContainer: Frame? = nil
local toastOrder = 0
local lootPopupGeneration = 0
local activeLootTween: Tween? = nil

-- Kontextueller Kaufhinweis (Energie-Pakete): maximal einmal pro Session.
local purchaseHintShown = false

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

local function addStroke(parent: Instance, color: Color3): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = 1
	stroke.Parent = parent
	return stroke
end

local function createLabel(parent: Instance, name: string, text: string): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamMedium
	label.TextColor3 = TEXT_COLOR
	label.TextSize = 14
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Text = text
	label.Parent = parent
	return label
end

-- Zeigt eine farbige Einblendung im Feed rechts oben (info/success/error).
local function showToastInternal(message: string, kind: string)
	local container = toastContainer
	if container == nil then
		return
	end

	local accentColor = TOAST_COLORS[kind] or TOAST_COLORS.info

	toastOrder += 1
	local toast = Instance.new("CanvasGroup")
	toast.Name = "Toast"
	toast.LayoutOrder = toastOrder
	toast.Size = UDim2.new(1, 0, 0, 0)
	toast.AutomaticSize = Enum.AutomaticSize.Y
	toast.BackgroundColor3 = PANEL_COLOR
	toast.BorderSizePixel = 0
	addCorner(toast, 8)

	local accent = Instance.new("Frame")
	accent.Name = "Accent"
	accent.Size = UDim2.new(0, 4, 1, 0)
	accent.BackgroundColor3 = accentColor
	accent.BorderSizePixel = 0
	accent.Parent = toast

	local label = createLabel(toast, "Message", message)
	label.Position = UDim2.new(0, 14, 0, 0)
	label.Size = UDim2.new(1, -24, 0, 0)
	label.AutomaticSize = Enum.AutomaticSize.Y
	label.TextWrapped = true

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 10)
	padding.PaddingBottom = UDim.new(0, 10)
	padding.Parent = toast

	toast.Parent = container

	-- Nach 4 s ausfaden und entfernen.
	task.delay(TOAST_LIFETIME_SECONDS, function()
		local tween = TweenService:Create(toast, TweenInfo.new(FADE_SECONDS), { GroupTransparency = 1 })
		tween:Play()
		tween.Completed:Once(function()
			toast:Destroy()
		end)
	end)

	-- Kontextueller Kaufhinweis: Wenn dem Spieler Energie fehlt, GENAU EINMAL
	-- pro Session freundlich auf die Energie-Pakete im Shop hinweisen
	-- (bewusst dezent - keine Popups, kein Spam).
	if not purchaseHintShown and kind == "error" and string.find(message, "Nicht genug Energie", 1, true) ~= nil then
		purchaseHintShown = true
		task.delay(0.8, function()
			showToastInternal("💡 Tipp: Am blauen Shop-Pad gibt es Energie-Pakete, falls mal etwas fehlt.", "info")
		end)
	end
end

-- Öffentliche API für andere Controller (z. B. PlanetBuilderController).
function UIController.showToast(message: string, kind: string)
	if toastContainer ~= nil then
		showToastInternal(message, kind)
		return
	end
	-- UI ist evtl. noch nicht aufgebaut: kurz warten (max. 10 s), dann anzeigen.
	task.spawn(function()
		local deadline = os.clock() + 10
		while toastContainer == nil and os.clock() < deadline do
			task.wait(0.1)
		end
		if toastContainer ~= nil then
			showToastInternal(message, kind)
		end
	end)
end

-- Ruft eine argumentlose RemoteFunction auf; bei ok=false erscheint die
-- deutsche Fehlermeldung des Servers als Toast, bei Erfolg läuft onSuccess.
local function invokeAction(functionName: string, onSuccess: ((payload: any) -> ())?)
	task.spawn(function()
		local ok, serverOk, payload = pcall(function()
			return Remotes.getFunction(functionName):InvokeServer()
		end)
		if not ok then
			UIController.showToast("Verbindungsfehler – bitte erneut versuchen.", "error")
			return
		end
		if serverOk ~= true then
			local message = if typeof(payload) == "string" then payload else "Aktion fehlgeschlagen."
			UIController.showToast(message, "error")
			return
		end
		if onSuccess ~= nil then
			onSuccess(payload)
		end
	end)
end

local function createActionButton(
	parent: Instance,
	order: number,
	text: string,
	functionName: string,
	onSuccess: ((payload: any) -> ())?
): TextButton
	local button = Instance.new("TextButton")
	button.Name = functionName
	button.LayoutOrder = order
	button.Size = UDim2.new(0, 168, 1, 0)
	button.BackgroundColor3 = PANEL_COLOR
	button.Font = Enum.Font.GothamBold
	button.TextSize = 15
	button.TextColor3 = TEXT_COLOR
	button.Text = text
	button.AutoButtonColor = true
	addCorner(button, 10)
	addStroke(button, STROKE_COLOR)
	button.Activated:Connect(function()
		invokeAction(functionName, onSuccess)
	end)
	EffectsController.addGradient(button)
	EffectsController.addButtonFX(button)
	button.Parent = parent
	return button
end

type GuiRefs = {
	energyLabel: TextLabel,
	lifetimeLabel: TextLabel,
	backpackLabel: TextLabel,
	multiplierLabel: TextLabel,
	statsLabel: TextLabel,
	lootPopup: CanvasGroup,
	lootName: TextLabel,
	lootRarity: TextLabel,
	lootStroke: UIStroke,
}

local function buildGui(playerGui: PlayerGui): GuiRefs
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "PlanetForgeUI"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.DisplayOrder = 10

	-- Kopfleiste oben: Energie, Lifetime-Energie, Statistikzeile.
	local header = Instance.new("Frame")
	header.Name = "Header"
	header.AnchorPoint = Vector2.new(0.5, 0)
	header.Position = UDim2.new(0.5, 0, 0, 8)
	header.Size = UDim2.new(0, 780, 0, 44)
	header.BackgroundColor3 = PANEL_COLOR
	header.BackgroundTransparency = 0.05
	addCorner(header, 10)
	addStroke(header, STROKE_COLOR)
	header.Parent = screenGui

	local energyLabel = createLabel(header, "Energy", "Energie: 0")
	energyLabel.Position = UDim2.new(0, 16, 0, 0)
	energyLabel.Size = UDim2.new(0, 230, 1, 0)
	energyLabel.Font = Enum.Font.GothamBold
	energyLabel.TextSize = 18

	local lifetimeLabel = createLabel(header, "Lifetime", "Gesamt: 0")
	lifetimeLabel.Position = UDim2.new(0, 254, 0, 0)
	lifetimeLabel.Size = UDim2.new(0, 140, 1, 0)
	lifetimeLabel.TextSize = 12
	lifetimeLabel.TextColor3 = SUBTEXT_COLOR

	local backpackLabel = createLabel(header, "Backpack", "🎒 0/30")
	backpackLabel.Position = UDim2.new(0, 400, 0, 0)
	backpackLabel.Size = UDim2.new(0, 150, 1, 0)
	backpackLabel.Font = Enum.Font.GothamBold
	backpackLabel.TextSize = 14

	-- Live-Multiplikator (Formel siehe ProgressionConfig).
	local multiplierLabel = createLabel(header, "Multiplier", "×1,0")
	multiplierLabel.Position = UDim2.new(0, 556, 0, 0)
	multiplierLabel.Size = UDim2.new(0, 70, 1, 0)
	multiplierLabel.Font = Enum.Font.GothamBold
	multiplierLabel.TextSize = 16
	multiplierLabel.TextColor3 = Color3.fromRGB(214, 160, 72)

	local statsLabel = createLabel(header, "Stats", "Besuche: 0  |  Likes: 0")
	statsLabel.AnchorPoint = Vector2.new(1, 0)
	statsLabel.Position = UDim2.new(1, -16, 0, 0)
	statsLabel.Size = UDim2.new(0, 200, 1, 0)
	statsLabel.TextSize = 12
	statsLabel.TextColor3 = SUBTEXT_COLOR
	statsLabel.TextXAlignment = Enum.TextXAlignment.Right

	-- Boost-Zeile direkt unter der Kopfleiste: zeigt Freunde-Boost und den
	-- gekauften 2x-Boost-Countdown; unsichtbar, solange nichts aktiv ist.
	local boostLabel = Instance.new("TextLabel")
	boostLabel.Name = "Boosts"
	boostLabel.AnchorPoint = Vector2.new(0.5, 0)
	boostLabel.Position = UDim2.new(0.5, 0, 0, 56)
	boostLabel.Size = UDim2.new(0, 520, 0, 18)
	boostLabel.BackgroundTransparency = 1
	boostLabel.Font = Enum.Font.GothamBold
	boostLabel.TextSize = 13
	boostLabel.TextColor3 = Color3.fromRGB(214, 160, 72)
	boostLabel.TextXAlignment = Enum.TextXAlignment.Center
	boostLabel.Text = ""
	boostLabel.Visible = false
	boostLabel.Parent = screenGui

	-- Buttonleiste unten Mitte.
	local buttonBar = Instance.new("Frame")
	buttonBar.Name = "ButtonBar"
	buttonBar.AnchorPoint = Vector2.new(0.5, 1)
	buttonBar.Position = UDim2.new(0.5, 0, 1, -14)
	buttonBar.Size = UDim2.new(0, 540, 0, 50)
	buttonBar.BackgroundTransparency = 1
	buttonBar.Parent = screenGui

	local barLayout = Instance.new("UIListLayout")
	barLayout.FillDirection = Enum.FillDirection.Horizontal
	barLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	barLayout.SortOrder = Enum.SortOrder.LayoutOrder
	barLayout.Padding = UDim.new(0, 10)
	barLayout.Parent = buttonBar

	-- Gesammelt wird physisch auf der Insel (HarvestService) - hier nur
	-- noch Fund-Suche und Heimreise.
	createActionButton(buttonBar, 1, `Fund suchen ({GameConfig.LOOT_ROLL_COST})`, "RollLoot")
	createActionButton(buttonBar, 2, "Nach Hause", "GoHome", function()
		EffectsController.playSound("pop", 0.9)
	end)

	-- Toast-Feed rechts oben.
	local toasts = Instance.new("Frame")
	toasts.Name = "Toasts"
	toasts.AnchorPoint = Vector2.new(1, 0)
	toasts.Position = UDim2.new(1, -14, 0, 64)
	toasts.Size = UDim2.new(0, 300, 1, -160)
	toasts.BackgroundTransparency = 1
	toasts.Parent = screenGui

	local toastLayout = Instance.new("UIListLayout")
	toastLayout.FillDirection = Enum.FillDirection.Vertical
	toastLayout.SortOrder = Enum.SortOrder.LayoutOrder
	toastLayout.Padding = UDim.new(0, 8)
	toastLayout.Parent = toasts

	-- Loot-Popup (zentriert, standardmäßig unsichtbar).
	local lootPopup = Instance.new("CanvasGroup")
	lootPopup.Name = "LootPopup"
	lootPopup.AnchorPoint = Vector2.new(0.5, 0.5)
	lootPopup.Position = UDim2.new(0.5, 0, 0.4, 0)
	lootPopup.Size = UDim2.new(0, 340, 0, 128)
	lootPopup.BackgroundColor3 = PANEL_COLOR
	lootPopup.Visible = false
	addCorner(lootPopup, 12)
	local lootStroke = addStroke(lootPopup, STROKE_COLOR)
	lootStroke.Thickness = 2
	lootPopup.Parent = screenGui

	local lootTitle = createLabel(lootPopup, "Title", "Neuer Fund!")
	lootTitle.Position = UDim2.new(0, 0, 0, 14)
	lootTitle.Size = UDim2.new(1, 0, 0, 18)
	lootTitle.TextXAlignment = Enum.TextXAlignment.Center
	lootTitle.TextColor3 = SUBTEXT_COLOR
	lootTitle.TextSize = 13

	local lootName = createLabel(lootPopup, "Name", "")
	lootName.Position = UDim2.new(0, 12, 0, 40)
	lootName.Size = UDim2.new(1, -24, 0, 30)
	lootName.TextXAlignment = Enum.TextXAlignment.Center
	lootName.Font = Enum.Font.GothamBold
	lootName.TextSize = 22

	local lootRarity = createLabel(lootPopup, "Rarity", "")
	lootRarity.Position = UDim2.new(0, 12, 0, 78)
	lootRarity.Size = UDim2.new(1, -24, 0, 22)
	lootRarity.TextXAlignment = Enum.TextXAlignment.Center
	lootRarity.TextSize = 16

	screenGui.Parent = playerGui
	toastContainer = toasts

	return {
		energyLabel = energyLabel,
		lifetimeLabel = lifetimeLabel,
		backpackLabel = backpackLabel,
		multiplierLabel = multiplierLabel,
		boostLabel = boostLabel,
		statsLabel = statsLabel,
		lootPopup = lootPopup,
		lootName = lootName,
		lootRarity = lootRarity,
		lootStroke = lootStroke,
	}
end

function UIController.init()
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui

	local refs = buildGui(playerGui)

	-- Energie-Anzeige mit Count-Up-Animation (Zahl läuft sichtbar hoch/runter).
	local displayedEnergy = 0
	local energyAnimToken = 0
	Remotes.getEvent("EnergyChanged").OnClientEvent:Connect(function(newEnergy: any, lifetimeEnergy: any)
		if typeof(newEnergy) == "number" then
			energyAnimToken += 1
			local token = energyAnimToken
			local fromValue = displayedEnergy
			task.spawn(function()
				local duration = 0.35
				local startedAt = os.clock()
				while true do
					if token ~= energyAnimToken then
						return
					end
					local alpha = math.clamp((os.clock() - startedAt) / duration, 0, 1)
					displayedEnergy = fromValue + (newEnergy - fromValue) * alpha
					refs.energyLabel.Text = `Energie: {formatNumber(displayedEnergy)}`
					if alpha >= 1 then
						return
					end
					task.wait(0.03)
				end
			end)
		end
		if typeof(lifetimeEnergy) == "number" then
			refs.lifetimeLabel.Text = `Gesamt: {formatNumber(lifetimeEnergy)}`
		end
	end)

	-- Rucksack-Anzeige (füllt sich beim Sammeln, leert sich beim Verkaufen).
	Remotes.getEvent("BackpackChanged").OnClientEvent:Connect(function(items: any, capacity: any, value: any)
		if typeof(items) == "number" and typeof(capacity) == "number" then
			local valueText = if typeof(value) == "number" and value > 0 then ` (Wert {formatNumber(value)})` else ""
			refs.backpackLabel.Text = `🎒 {items}/{capacity}{valueText}`
			refs.backpackLabel.TextColor3 = if items >= capacity then Color3.fromRGB(214, 110, 110) else TEXT_COLOR
		end
	end)

	-- Live-Multiplikator im HUD (Komma statt Punkt, eine Nachkommastelle)
	-- plus Boost-Zeile für Freunde-Boost und 2x-Boost-Countdown.
	Remotes.getEvent("MultiplierChanged").OnClientEvent:Connect(function(info: any)
		if typeof(info) == "table" and typeof(info.total) == "number" then
			local text = string.format("×%.1f", info.total)
			refs.multiplierLabel.Text = (string.gsub(text, "%.", ","))

			local parts = {}
			if typeof(info.friendBonus) == "number" and info.friendBonus > 1.001 then
				table.insert(parts, `👥 Freunde-Boost +{math.floor((info.friendBonus - 1) * 100 + 0.5)}%`)
			end
			if typeof(info.boostSecondsLeft) == "number" and info.boostSecondsLeft > 0 then
				table.insert(parts, `🔥 2x-Boost noch {math.ceil(info.boostSecondsLeft / 60)} Min.`)
			end
			refs.boostLabel.Text = table.concat(parts, "   ·   ")
			refs.boostLabel.Visible = #parts > 0
		end
	end)

	-- Offline-Earnings: Willkommens-Popup mit grosser Summe (nutzt das
	-- Loot-Popup-Layout) plus hochzaehlender Zahl am Energie-Counter.
	Remotes.getEvent("OfflineEarnings").OnClientEvent:Connect(function(amount: any, minutes: any)
		if typeof(amount) ~= "number" or amount <= 0 then
			return
		end
		local awayText = if typeof(minutes) == "number" and minutes >= 60
			then `{math.floor(minutes / 60)} Std. {minutes % 60} Min.`
			else `{if typeof(minutes) == "number" then minutes else 0} Min.`

		lootPopupGeneration += 1
		local generation = lootPopupGeneration
		if activeLootTween ~= nil then
			activeLootTween:Cancel()
			activeLootTween = nil
		end
		refs.lootName.Text = `+{formatNumber(amount)} ⚡`
		refs.lootRarity.Text = `Willkommen zurück! Deine Biome haben {awayText} weitergearbeitet.`
		refs.lootRarity.TextColor3 = SUBTEXT_COLOR
		refs.lootStroke.Color = Color3.fromRGB(214, 160, 72)
		refs.lootStroke.Thickness = 3
		refs.lootPopup.GroupTransparency = 0
		refs.lootPopup.Visible = true
		EffectsController.playSound("fanfare", 1)

		task.delay(4, function()
			if generation ~= lootPopupGeneration then
				return
			end
			local tween = TweenService:Create(refs.lootPopup, TweenInfo.new(FADE_SECONDS), { GroupTransparency = 1 })
			activeLootTween = tween
			tween:Play()
			tween.Completed:Once(function()
				if generation == lootPopupGeneration then
					refs.lootPopup.Visible = false
				end
			end)
		end)
	end)

	-- Statistikzeile (Besuche/Likes) aus dem Planeten-Snapshot.
	Remotes.getEvent("PlanetUpdated").OnClientEvent:Connect(function(snapshot: any)
		if typeof(snapshot) ~= "table" then
			return
		end
		local visits = if typeof(snapshot.visits) == "number" then snapshot.visits else 0
		local likes = if typeof(snapshot.likes) == "number" then snapshot.likes else 0
		refs.statsLabel.Text = `Besuche: {formatNumber(visits)}  |  Likes: {formatNumber(likes)}`
	end)

	-- Server-Benachrichtigungen in den Toast-Feed leiten.
	Remotes.getEvent("Notification").OnClientEvent:Connect(function(message: any, kind: any)
		if typeof(message) ~= "string" then
			return
		end
		showToastInternal(message, if typeof(kind) == "string" then kind else "info")
	end)

	-- Loot-Popup mit Spannungsaufbau: 1,5 s durchlaufende Seltenheiten,
	-- dann Reveal in der echten Rarity-Farbe; ab Legendär Shake + Glow.
	Remotes.getEvent("LootObtained").OnClientEvent:Connect(function(collectibleId: any, rarity: any, _uid: any)
		if typeof(collectibleId) ~= "string" or typeof(rarity) ~= "string" then
			return
		end

		local collectibleDef = CollectibleConfig.Collectibles[collectibleId]
		local tierDef = RarityConfig.Tiers[rarity]
		local tierColor = if tierDef ~= nil then tierDef.color else TEXT_COLOR

		-- Generation zählt mit, damit sich überlappende Popups nicht gegenseitig
		-- vorzeitig ausblenden oder alte Spannungsphasen weiterlaufen.
		lootPopupGeneration += 1
		local generation = lootPopupGeneration

		-- Einen noch laufenden Fade-Out-Tween abbrechen, sonst blendet er das
		-- gerade neu gezeigte Popup Frame für Frame wieder aus.
		if activeLootTween ~= nil then
			activeLootTween:Cancel()
			activeLootTween = nil
		end

		refs.lootName.Text = "???"
		refs.lootRarity.Text = ""
		refs.lootStroke.Color = STROKE_COLOR
		refs.lootStroke.Thickness = 2
		refs.lootPopup.GroupTransparency = 0
		refs.lootPopup.Visible = true

		task.spawn(function()
			-- Spannungsphase: Seltenheitsstufen rotieren durch.
			local tierOrder = RarityConfig.TierOrder
			local elapsed = 0
			local index = 0
			while elapsed < LOOT_SUSPENSE_SECONDS do
				if generation ~= lootPopupGeneration then
					return
				end
				index = index % #tierOrder + 1
				local cycleTier = RarityConfig.Tiers[tierOrder[index]]
				if cycleTier ~= nil then
					refs.lootRarity.Text = cycleTier.displayName
					refs.lootRarity.TextColor3 = cycleTier.color
					refs.lootStroke.Color = cycleTier.color
				end
				EffectsController.playSound("tick")
				task.wait(LOOT_SUSPENSE_TICK)
				elapsed += LOOT_SUSPENSE_TICK
			end
			if generation ~= lootPopupGeneration then
				return
			end

			-- Reveal.
			refs.lootName.Text = if collectibleDef ~= nil then collectibleDef.displayName else collectibleId
			refs.lootRarity.Text = if tierDef ~= nil then tierDef.displayName else rarity
			refs.lootRarity.TextColor3 = tierColor
			refs.lootStroke.Color = tierColor
			EffectsController.playSound("reveal")

			if HIGH_TIER[rarity] == true then
				EffectsController.playSound("fanfare")
				EffectsController.screenShake(1)
				EffectsController.burstAtOwnPlanet(tierColor)
				-- Glow: Rahmen kurz aufblitzen lassen.
				refs.lootStroke.Thickness = 6
				local glow = TweenService:Create(refs.lootStroke, TweenInfo.new(0.6), { Thickness = 3 })
				glow:Play()
			end

			task.delay(LOOT_POPUP_SECONDS, function()
				if generation ~= lootPopupGeneration then
					return
				end
				local tween =
					TweenService:Create(refs.lootPopup, TweenInfo.new(FADE_SECONDS), { GroupTransparency = 1 })
				activeLootTween = tween
				tween:Play()
				tween.Completed:Once(function()
					if activeLootTween == tween then
						activeLootTween = nil
					end
					if generation == lootPopupGeneration then
						refs.lootPopup.Visible = false
					end
				end)
			end)
		end)
	end)
end

return UIController
