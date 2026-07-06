--!strict
-- HarvestController: Client-Effekte für das physische Sammeln.
--
-- Der Server entscheidet, WAS gesammelt/verkauft wird (HarvestService);
-- dieser Controller macht es fühlbar: Sammel-Sound + fliegende Wert-Zahl,
-- Verkaufs-Feedback und ein dezenter "Rucksack voll"-Hinweis.


local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ConfigFolder = Shared:WaitForChild("Config")
local ControllersFolder = script.Parent :: Instance

local Remotes = require(Shared:WaitForChild("Remotes") :: ModuleScript) :: {
	getEvent: (name: string) -> RemoteEvent,
	getFunction: (name: string) -> RemoteFunction,
}
local GameConfig = require(ConfigFolder:WaitForChild("GameConfig") :: ModuleScript) :: {
	COMBO_WINDOW_SECONDS: number,
	COMBO_BONUS_PER_STACK: number,
}
local UIController = require(ControllersFolder:WaitForChild("UIController") :: ModuleScript) :: {
	showToast: (message: string, kind: string) -> (),
}
local EffectsController = require(ControllersFolder:WaitForChild("EffectsController") :: ModuleScript) :: {
	playSound: (name: string, pitchOverride: number?) -> (),
	flyPartToCharacter: (position: Vector3, color: Color3?) -> (),
	coinRain: (coinCount: number?) -> (),
	countUpAtCounter: (amount: number) -> (),
	screenShake: (intensity: number?) -> (),
}

local FULL_HINT_COOLDOWN_SECONDS = 45

-- Ab dieser Ketten-Stufe wird die Combo-Anzeige eingeblendet.
local COMBO_SHOW_THRESHOLD = 4
local COMBO_HOT_THRESHOLD = 15 -- ab hier wird die Anzeige "heiß" (rot)

local GOLD_COLOR = Color3.fromRGB(255, 208, 70)

local HarvestController = {}

local lastFullHintAt = 0
local shopHintShown = false -- Kaufanreiz maximal 1x pro Session
local collectPitch = 1

-- Combo-Anzeige (unten Mitte, über der Buttonleiste).
local comboLabel: TextLabel? = nil
local comboGeneration = 0

-- Baut die (anfangs unsichtbare) Combo-Anzeige.
local function buildComboUI()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "PlanetForgeCombo"
	screenGui.ResetOnSpawn = false
	screenGui.Parent = playerGui

	-- Position: über der Tutorial-Box (-78..-142), damit sich beide nie überlappen.
	local label = Instance.new("TextLabel")
	label.Name = "Combo"
	label.AnchorPoint = Vector2.new(0.5, 1)
	label.Position = UDim2.new(0.5, 0, 1, -150)
	label.Size = UDim2.new(0, 320, 0, 26)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextSize = 20
	label.TextColor3 = GOLD_COLOR
	label.TextStrokeTransparency = 0.4
	label.Visible = false
	label.Parent = screenGui

	comboLabel = label
end

-- Zeigt die Ketten-Stufe an und blendet sie nach dem Ketten-Fenster aus.
local function showCombo(count: number)
	local label = comboLabel
	if label == nil then
		return
	end

	local bonusPercent = math.floor(count * GameConfig.COMBO_BONUS_PER_STACK * 100 + 0.5)
	label.Text = `🔥 Kette x{count} (+{bonusPercent}%)`
	label.TextColor3 = if count >= COMBO_HOT_THRESHOLD then Color3.fromRGB(255, 96, 60) else GOLD_COLOR
	label.TextSize = math.min(20 + count, 32)
	label.Visible = true

	comboGeneration += 1
	local generation = comboGeneration
	task.delay(GameConfig.COMBO_WINDOW_SECONDS, function()
		if generation == comboGeneration and comboLabel ~= nil then
			(comboLabel :: TextLabel).Visible = false
		end
	end)
end

-- Kleine Wert-Zahl, die vom eingesammelten Objekt aufsteigt (3D-Billboard).
local function showFloatingValue(position: Vector3, value: number, color: Color3, golden: boolean?)
	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.CFrame = CFrame.new(position)
	anchor.Parent = Workspace

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(90, 26)
	billboard.StudsOffset = Vector3.new(0, 1.5, 0)
	billboard.AlwaysOnTop = true
	billboard.Parent = anchor

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBold
	label.TextSize = if golden == true then 26 else 18
	label.TextColor3 = color
	label.TextStrokeTransparency = 0.4
	label.Text = if golden == true then `+{value} ✨` else `+{value}`
	label.Parent = billboard

	local rise = TweenService:Create(
		billboard,
		TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ StudsOffset = Vector3.new(0, 4.5, 0) }
	)
	local fade = TweenService:Create(label, TweenInfo.new(0.35), { TextTransparency = 1, TextStrokeTransparency = 1 })
	rise:Play()
	task.delay(0.4, function()
		fade:Play()
	end)
	task.delay(0.9, function()
		anchor:Destroy()
	end)
end

function HarvestController.init()
	buildComboUI()

	-- Sammel-Effekt: Sound (leicht steigende Tonhöhe bei Ketten) + Wert-Zahl
	-- + Combo-Anzeige; goldene Objekte bekommen extra Fanfare und Funkeln.
	Remotes.getEvent("ObjectCollected").OnClientEvent:Connect(
		function(position: any, value: any, color: any, comboCount: any, golden: any)
			if typeof(position) ~= "Vector3" or typeof(value) ~= "number" then
				return
			end
			collectPitch = math.min(collectPitch + 0.04, 1.5)
			EffectsController.playSound("collect", collectPitch)
			task.delay(2, function()
				collectPitch = math.max(collectPitch - 0.04, 1)
			end)
			if golden == true then
				EffectsController.playSound("fanfare", 1.5)
			end
			local effectColor = if typeof(color) == "Color3" then color else Color3.fromRGB(255, 224, 130)
			-- Objekt fliegt sichtbar zum Spieler, Wert steigt am Sammelpunkt auf.
			EffectsController.flyPartToCharacter(position, effectColor)
			showFloatingValue(position, value, effectColor, golden == true)
			if typeof(comboCount) == "number" and comboCount >= COMBO_SHOW_THRESHOLD then
				showCombo(comboCount)
			end
		end
	)

	-- Verkaufs-Feedback: Münz-Regen + hochzählender Energie-Zähler;
	-- kritische Verkäufe knallen richtig (Shake + eigener Toast).
	Remotes.getEvent("SoldBackpack").OnClientEvent:Connect(function(gained: any, itemsSold: any, critical: any)
		if typeof(gained) ~= "number" then
			return
		end
		local items = if typeof(itemsSold) == "number" then itemsSold else 0
		if critical == true then
			EffectsController.playSound("fanfare", 0.85)
			EffectsController.screenShake(1)
			EffectsController.coinRain(math.clamp(items * 2, 10, 28))
			EffectsController.countUpAtCounter(gained)
			UIController.showToast(`💥 KRITISCHER VERKAUF! Doppelte Beute: +{gained} Energie!`, "success")
		else
			EffectsController.playSound("fanfare", 1.1)
			EffectsController.coinRain(math.clamp(items, 4, 16))
			EffectsController.countUpAtCounter(gained)
			UIController.showToast(`Verkauft: {items} Objekte für {gained} Energie! ⚡`, "success")
		end
	end)

	-- Dezenter Hinweis, wenn der Rucksack voll ist (gedrosselt).
	Remotes.getEvent("BackpackChanged").OnClientEvent:Connect(function(items: any, capacity: any)
		if typeof(items) ~= "number" or typeof(capacity) ~= "number" then
			return
		end
		if items >= capacity and os.clock() - lastFullHintAt > FULL_HINT_COOLDOWN_SECONDS then
			lastFullHintAt = os.clock()
			UIController.showToast("Rucksack voll! Verkaufe am goldenen 💰-Pad auf deiner Insel.", "info")
			-- Kontextueller Kaufanreiz: einmal pro Session, nicht nervig.
			if not shopHintShown then
				shopHintShown = true
				task.delay(2, function()
					UIController.showToast('Tipp: Größerer Rucksack? Insel-Upgrade im „Biome"-Menü oder 🛒 Shop.', "info")
				end)
			end
		end
	end)
end

return HarvestController
