--!strict
-- QuestController: kompaktes Session-Quest-Panel unten links.
-- Zeigt die drei Ziele der Session mit Fortschritt; erledigte Quests
-- bekommen einen Haken und werden ausgegraut.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local Remotes = require(Shared:WaitForChild("Remotes") :: ModuleScript) :: {
	getEvent: (name: string) -> RemoteEvent,
	getFunction: (name: string) -> RemoteFunction,
}

local PANEL_COLOR = Color3.fromRGB(30, 32, 44)
local STROKE_COLOR = Color3.fromRGB(70, 75, 100)
local TEXT_COLOR = Color3.fromRGB(235, 238, 245)
local SUBTEXT_COLOR = Color3.fromRGB(158, 164, 186)
local ACCENT_COLOR = Color3.fromRGB(214, 160, 72)
local DONE_COLOR = Color3.fromRGB(76, 175, 110)

local QuestController = {}

local rows: { TextLabel } = {}

local function addCorner(instance: Instance, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = instance
end

local function buildUI()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "PlanetForgeQuests"
	screenGui.ResetOnSpawn = false
	screenGui.Parent = playerGui

	local panel = Instance.new("Frame")
	panel.Name = "QuestPanel"
	panel.AnchorPoint = Vector2.new(0, 1)
	panel.Position = UDim2.new(0, 14, 1, -90)
	panel.Size = UDim2.new(0, 250, 0, 96)
	panel.BackgroundColor3 = PANEL_COLOR
	panel.BackgroundTransparency = 0.15
	addCorner(panel, 10)
	local stroke = Instance.new("UIStroke")
	stroke.Color = STROKE_COLOR
	stroke.Parent = panel
	panel.Parent = screenGui

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Position = UDim2.new(0, 10, 0, 6)
	title.Size = UDim2.new(1, -20, 0, 16)
	title.Font = Enum.Font.GothamBold
	title.TextSize = 12
	title.TextColor3 = ACCENT_COLOR
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = "🎯 Session-Ziele"
	title.Parent = panel

	for index = 1, 3 do
		local row = Instance.new("TextLabel")
		row.Name = `Quest_{index}`
		row.BackgroundTransparency = 1
		row.Position = UDim2.new(0, 10, 0, 8 + index * 20)
		row.Size = UDim2.new(1, -20, 0, 18)
		row.Font = Enum.Font.GothamMedium
		row.TextSize = 12
		row.TextColor3 = SUBTEXT_COLOR
		row.TextXAlignment = Enum.TextXAlignment.Left
		row.TextTruncate = Enum.TextTruncate.AtEnd
		row.Text = "…"
		row.Parent = panel
		table.insert(rows, row)
	end
end

function QuestController.init()
	buildUI()

	Remotes.getEvent("QuestsUpdated").OnClientEvent:Connect(function(quests: any)
		if typeof(quests) ~= "table" then
			return
		end
		for index, row in rows do
			local quest = (quests :: { any })[index]
			if typeof(quest) ~= "table" then
				row.Text = ""
				continue
			end
			if quest.done == true then
				row.Text = `✓ {quest.text}`
				row.TextColor3 = DONE_COLOR
			else
				row.Text = `☐ {quest.text} ({quest.progress}/{quest.target}) – +{quest.reward} ⚡`
				row.TextColor3 = TEXT_COLOR
			end
		end
	end)
end

return QuestController
