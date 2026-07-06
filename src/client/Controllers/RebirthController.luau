--!strict
-- RebirthController: Wiedergeburt-Dialog mit klarer Vorher/Nachher-Anzeige.
--
-- Zeigt Fortschritt zur nächsten Rebirth-Schwelle, den aktuellen und den
-- zukünftigen permanenten Multiplikator sowie eine klare Liste, was beim
-- Reset verloren geht und was bleibt. Der Bestätigen-Button ist erst ab
-- erreichter Schwelle aktiv (der Server validiert zusätzlich).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ConfigFolder = Shared:WaitForChild("Config")
local ControllersFolder = script.Parent :: Instance

local Remotes = require(Shared:WaitForChild("Remotes") :: ModuleScript) :: {
	getEvent: (name: string) -> RemoteEvent,
	getFunction: (name: string) -> RemoteFunction,
}
local ProgressionConfig = require(ConfigFolder:WaitForChild("ProgressionConfig") :: ModuleScript) :: {
	REBIRTH_BONUS: number,
	getRebirthMultiplier: (rebirths: number) -> number,
}
local UIController = require(ControllersFolder:WaitForChild("UIController") :: ModuleScript) :: {
	showToast: (message: string, kind: string) -> (),
}
local EffectsController = require(ControllersFolder:WaitForChild("EffectsController") :: ModuleScript) :: {
	playSound: (name: string, pitchOverride: number?) -> (),
	screenShake: (intensity: number?) -> (),
}

-- Farbschema (identisch zum UIController).
local PANEL_COLOR = Color3.fromRGB(30, 32, 44)
local ROW_COLOR = Color3.fromRGB(44, 47, 63)
local STROKE_COLOR = Color3.fromRGB(70, 75, 100)
local TEXT_COLOR = Color3.fromRGB(235, 238, 245)
local SUBTEXT_COLOR = Color3.fromRGB(158, 164, 186)
local ACCENT_COLOR = Color3.fromRGB(214, 160, 72)
local CONFIRM_COLOR = Color3.fromRGB(178, 62, 62)
local DISABLED_COLOR = Color3.fromRGB(60, 64, 84)
local BAR_COLOR = Color3.fromRGB(120, 90, 200)

local RebirthController = {}

local localPlayer = Players.LocalPlayer

-- Stand aus MultiplierChanged / EnergyChanged.
local rebirths = 0
local nextThreshold = math.huge
local lifetimeEnergy = 0

local dialog: Frame? = nil
local beforeLabel: TextLabel? = nil
local afterLabel: TextLabel? = nil
local progressLabel: TextLabel? = nil
local progressFill: Frame? = nil
local confirmButton: TextButton? = nil

local rebirthFunction: RemoteFunction? = nil

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

local function formatNumber(value: number): string
	local text = tostring(math.floor(value))
	while true do
		local replaced: number
		text, replaced = text:gsub("^(-?%d+)(%d%d%d)", "%1.%2")
		if replaced == 0 then
			break
		end
	end
	return text
end

local function formatMultiplier(value: number): string
	return (string.gsub(string.format("×%.1f", value), "%.", ","))
end

-- Dialog-Inhalte an den aktuellen Stand angleichen.
local function refreshDialog()
	if dialog == nil then
		return
	end

	local ready = lifetimeEnergy >= nextThreshold;

	(beforeLabel :: TextLabel).Text = `Jetzt: {formatMultiplier(ProgressionConfig.getRebirthMultiplier(rebirths))} permanent`;
	(afterLabel :: TextLabel).Text =
		`Nach Wiedergeburt {rebirths + 1}: {formatMultiplier(ProgressionConfig.getRebirthMultiplier(rebirths + 1))} permanent`;
	(progressLabel :: TextLabel).Text =
		`Fortschritt: {formatNumber(lifetimeEnergy)} / {formatNumber(nextThreshold)} Gesamt-Energie`

	local fraction = if nextThreshold > 0 then math.clamp(lifetimeEnergy / nextThreshold, 0, 1) else 0;
	(progressFill :: Frame).Size = UDim2.new(fraction, 0, 1, 0)

	local button = confirmButton :: TextButton
	button.Text = if ready then "Wiedergeburt! 🔄" else "Noch nicht bereit"
	button.BackgroundColor3 = if ready then CONFIRM_COLOR else DISABLED_COLOR
	button.AutoButtonColor = ready
end

local function buildUI()
	local playerGui = localPlayer:WaitForChild("PlayerGui")

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "PlanetForgeRebirth"
	screenGui.ResetOnSpawn = false
	screenGui.DisplayOrder = 25
	screenGui.Parent = playerGui

	-- Umschalt-Button oben links neben dem Namens-Button.
	local toggleButton = Instance.new("TextButton")
	toggleButton.Name = "RebirthToggle"
	toggleButton.Position = UDim2.new(0, 180, 0, 12)
	toggleButton.Size = UDim2.new(0, 150, 0, 36)
	toggleButton.BackgroundColor3 = PANEL_COLOR
	toggleButton.Font = Enum.Font.GothamBold
	toggleButton.TextSize = 13
	toggleButton.TextColor3 = TEXT_COLOR
	toggleButton.Text = "🔄 Wiedergeburt"
	addCorner(toggleButton, 10)
	addStroke(toggleButton, STROKE_COLOR)
	toggleButton.Parent = screenGui

	-- Bestätigungs-Dialog (zentriert).
	local frame = Instance.new("Frame")
	frame.Name = "RebirthDialog"
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.new(0.5, 0, 0.45, 0)
	frame.Size = UDim2.new(0, 420, 0, 300)
	frame.BackgroundColor3 = PANEL_COLOR
	frame.Visible = false
	addCorner(frame, 12)
	addStroke(frame, ACCENT_COLOR)
	frame.Parent = screenGui

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Position = UDim2.new(0, 16, 0, 12)
	title.Size = UDim2.new(1, -32, 0, 24)
	title.Font = Enum.Font.GothamBold
	title.TextSize = 18
	title.TextColor3 = ACCENT_COLOR
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = "🔄 Wiedergeburt"
	title.Parent = frame

	local before = Instance.new("TextLabel")
	before.Name = "Before"
	before.BackgroundTransparency = 1
	before.Position = UDim2.new(0, 16, 0, 44)
	before.Size = UDim2.new(1, -32, 0, 20)
	before.Font = Enum.Font.GothamMedium
	before.TextSize = 14
	before.TextColor3 = TEXT_COLOR
	before.TextXAlignment = Enum.TextXAlignment.Left
	before.Parent = frame

	local after = Instance.new("TextLabel")
	after.Name = "After"
	after.BackgroundTransparency = 1
	after.Position = UDim2.new(0, 16, 0, 66)
	after.Size = UDim2.new(1, -32, 0, 20)
	after.Font = Enum.Font.GothamBold
	after.TextSize = 14
	after.TextColor3 = ACCENT_COLOR
	after.TextXAlignment = Enum.TextXAlignment.Left
	after.Parent = frame

	-- Was passiert beim Reset.
	local info = Instance.new("TextLabel")
	info.BackgroundTransparency = 1
	info.Position = UDim2.new(0, 16, 0, 94)
	info.Size = UDim2.new(1, -32, 0, 84)
	info.Font = Enum.Font.GothamMedium
	info.TextSize = 12
	info.TextColor3 = SUBTEXT_COLOR
	info.TextXAlignment = Enum.TextXAlignment.Left
	info.TextYAlignment = Enum.TextYAlignment.Top
	info.TextWrapped = true
	info.Text = "❌ Zurückgesetzt: Biome (außer Start-Wiese), Energie, Gesamt-Energie, Rucksack"
		.. "\n✅ Bleibt: Sammlung, Kosmetik, Insel-Upgrades, Haustiere, Name"
		.. "\n⭐ Neu: permanenter Multiplikator und goldene Insel-Deko"
	info.Parent = frame

	-- Fortschrittsbalken zur Schwelle.
	local progressText = Instance.new("TextLabel")
	progressText.Name = "ProgressText"
	progressText.BackgroundTransparency = 1
	progressText.Position = UDim2.new(0, 16, 0, 182)
	progressText.Size = UDim2.new(1, -32, 0, 18)
	progressText.Font = Enum.Font.GothamMedium
	progressText.TextSize = 12
	progressText.TextColor3 = TEXT_COLOR
	progressText.TextXAlignment = Enum.TextXAlignment.Left
	progressText.Parent = frame

	local barBack = Instance.new("Frame")
	barBack.Position = UDim2.new(0, 16, 0, 204)
	barBack.Size = UDim2.new(1, -32, 0, 12)
	barBack.BackgroundColor3 = ROW_COLOR
	addCorner(barBack, 6)
	barBack.Parent = frame

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.new(0, 0, 1, 0)
	fill.BackgroundColor3 = BAR_COLOR
	addCorner(fill, 6)
	fill.Parent = barBack

	local cancelButton = Instance.new("TextButton")
	cancelButton.Position = UDim2.new(0, 16, 1, -56)
	cancelButton.Size = UDim2.new(0.5, -24, 0, 40)
	cancelButton.BackgroundColor3 = DISABLED_COLOR
	cancelButton.Font = Enum.Font.GothamBold
	cancelButton.TextSize = 14
	cancelButton.TextColor3 = TEXT_COLOR
	cancelButton.Text = "Abbrechen"
	addCorner(cancelButton, 10)
	cancelButton.Parent = frame

	local confirm = Instance.new("TextButton")
	confirm.Name = "Confirm"
	confirm.AnchorPoint = Vector2.new(1, 0)
	confirm.Position = UDim2.new(1, -16, 1, -56)
	confirm.Size = UDim2.new(0.5, -24, 0, 40)
	confirm.BackgroundColor3 = DISABLED_COLOR
	confirm.Font = Enum.Font.GothamBold
	confirm.TextSize = 14
	confirm.TextColor3 = TEXT_COLOR
	confirm.Text = "Noch nicht bereit"
	addCorner(confirm, 10)
	confirm.Parent = frame

	toggleButton.Activated:Connect(function()
		frame.Visible = not frame.Visible
		refreshDialog()
	end)
	cancelButton.Activated:Connect(function()
		frame.Visible = false
	end)
	confirm.Activated:Connect(function()
		if lifetimeEnergy < nextThreshold then
			UIController.showToast("Du hast die Schwelle noch nicht erreicht.", "info")
			return
		end
		local remote = rebirthFunction
		if remote == nil then
			return
		end
		task.spawn(function()
			local ok, serverOk, payload = pcall(function()
				return remote:InvokeServer()
			end)
			if not ok then
				UIController.showToast("Verbindungsfehler – bitte erneut versuchen.", "error")
			elseif serverOk ~= true and typeof(payload) == "string" then
				UIController.showToast(payload, "error")
			else
				EffectsController.playSound("fanfare", 0.9)
				EffectsController.screenShake(1.2)
				frame.Visible = false
			end
		end)
	end)

	dialog = frame
	beforeLabel = before
	afterLabel = after
	progressLabel = progressText
	progressFill = fill
	confirmButton = confirm
end

function RebirthController.init()
	rebirthFunction = Remotes.getFunction("DoRebirth")

	Remotes.getEvent("MultiplierChanged").OnClientEvent:Connect(function(info: any)
		if typeof(info) ~= "table" then
			return
		end
		if typeof(info.rebirths) == "number" then
			rebirths = info.rebirths
		end
		if typeof(info.nextThreshold) == "number" then
			nextThreshold = info.nextThreshold
		end
		if typeof(info.lifetimeEnergy) == "number" then
			lifetimeEnergy = info.lifetimeEnergy
		end
		refreshDialog()
	end)

	Remotes.getEvent("EnergyChanged").OnClientEvent:Connect(function(_energy: any, lifetime: any)
		if typeof(lifetime) == "number" then
			lifetimeEnergy = lifetime
			refreshDialog()
		end
	end)

	buildUI()
end

return RebirthController
