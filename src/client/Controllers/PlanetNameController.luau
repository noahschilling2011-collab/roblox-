--!strict
-- PlanetNameController: kleines Panel oben links, um den eigenen Planeten
-- zu benennen (RenamePlanet). Der Server filtert den Namen (Pflicht) und
-- aktualisiert das Namensschild über dem Planetenkern.

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
	PLANET_NAME_MAX_LENGTH: number,
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
local SAVE_BUTTON_COLOR = Color3.fromRGB(56, 160, 92)

local PlanetNameController = {}

local localPlayer = Players.LocalPlayer

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

function PlanetNameController.init()
	local renameFunction = Remotes.getFunction("RenamePlanet")
	local playerGui = localPlayer:WaitForChild("PlayerGui")

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "PlanetForgeName"
	screenGui.ResetOnSpawn = false
	screenGui.Parent = playerGui

	local toggleButton = Instance.new("TextButton")
	toggleButton.Name = "NameToggle"
	toggleButton.Position = UDim2.new(0, 12, 0, 12)
	toggleButton.Size = UDim2.new(0, 160, 0, 36)
	toggleButton.BackgroundColor3 = PANEL_COLOR
	toggleButton.Font = Enum.Font.GothamBold
	toggleButton.TextSize = 13
	toggleButton.TextColor3 = TEXT_COLOR
	toggleButton.Text = "✏️ Planet benennen"
	addCorner(toggleButton, 10)
	addStroke(toggleButton, STROKE_COLOR)
	toggleButton.Parent = screenGui

	local panel = Instance.new("Frame")
	panel.Name = "NamePanel"
	panel.Position = UDim2.new(0, 12, 0, 54)
	panel.Size = UDim2.new(0, 240, 0, 96)
	panel.BackgroundColor3 = PANEL_COLOR
	panel.Visible = false
	addCorner(panel, 12)
	addStroke(panel, STROKE_COLOR)
	panel.Parent = screenGui

	local textBox = Instance.new("TextBox")
	textBox.Name = "NameInput"
	textBox.Position = UDim2.new(0, 10, 0, 10)
	textBox.Size = UDim2.new(1, -20, 0, 34)
	textBox.BackgroundColor3 = ROW_COLOR
	textBox.Font = Enum.Font.GothamMedium
	textBox.TextSize = 13
	textBox.TextColor3 = TEXT_COLOR
	textBox.PlaceholderText = `Neuer Name (3-{GameConfig.PLANET_NAME_MAX_LENGTH} Zeichen)`
	textBox.PlaceholderColor3 = SUBTEXT_COLOR
	textBox.Text = ""
	textBox.ClearTextOnFocus = false
	addCorner(textBox, 8)
	textBox.Parent = panel

	local saveButton = Instance.new("TextButton")
	saveButton.Name = "Save"
	saveButton.Position = UDim2.new(0, 10, 0, 52)
	saveButton.Size = UDim2.new(1, -20, 0, 32)
	saveButton.BackgroundColor3 = SAVE_BUTTON_COLOR
	saveButton.Font = Enum.Font.GothamBold
	saveButton.TextSize = 13
	saveButton.TextColor3 = TEXT_COLOR
	saveButton.Text = "Speichern"
	addCorner(saveButton, 8)
	saveButton.Parent = panel

	toggleButton.Activated:Connect(function()
		panel.Visible = not panel.Visible
	end)

	saveButton.Activated:Connect(function()
		local desiredName = textBox.Text
		task.spawn(function()
			local ok, success, payload = pcall(function()
				return renameFunction:InvokeServer(desiredName)
			end)
			if not ok then
				UIController.showToast("Verbindungsfehler - bitte erneut versuchen.", "error")
				return
			end
			if success == true and typeof(payload) == "string" then
				UIController.showToast(`Dein Planet heißt jetzt "{payload}"!`, "success")
				textBox.Text = ""
				panel.Visible = false
			elseif typeof(payload) == "string" then
				UIController.showToast(payload, "error")
			end
		end)
	end)
end

return PlanetNameController
