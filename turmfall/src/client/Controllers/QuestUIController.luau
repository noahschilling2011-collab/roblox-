--!strict
-- QuestUIController: kompaktes Aufträge-Panel unten links.
-- Zeigt die drei Session-Aufträge mit Fortschritt; erledigte bekommen
-- einen Haken. Daten kommen ausschließlich vom Server (QuestsChanged).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Network = require(Shared:WaitForChild("Network") :: ModuleScript) :: {
	getEvent: (name: string) -> RemoteEvent,
	getFunction: (name: string) -> RemoteFunction,
}

local PANEL_COLOR = Color3.fromRGB(28, 30, 40)
local TEXT_COLOR = Color3.fromRGB(235, 238, 245)
local SUBTEXT_COLOR = Color3.fromRGB(158, 164, 186)
local ACCENT_COLOR = Color3.fromRGB(255, 190, 70)
local DONE_COLOR = Color3.fromRGB(90, 190, 120)

local QuestUIController = {}

local rows: { TextLabel } = {}

local function buildUI()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "TurmfallQuests"
	screenGui.ResetOnSpawn = false
	screenGui.Parent = playerGui

	local panel = Instance.new("Frame")
	panel.Name = "QuestPanel"
	panel.AnchorPoint = Vector2.new(0, 1)
	panel.Position = UDim2.new(0, 12, 1, -14)
	panel.Size = UDim2.new(0, 250, 0, 96)
	panel.BackgroundColor3 = PANEL_COLOR
	panel.BackgroundTransparency = 0.15
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = panel
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(70, 75, 100)
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
	title.Text = "🎯 Aufträge (Session)"
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

function QuestUIController.init()
	buildUI()

	Network.getEvent("QuestsChanged").OnClientEvent:Connect(function(quests: any)
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
				row.Text = `☐ {quest.text} ({quest.progress}/{quest.target}) – +{quest.reward} 🧱`
				row.TextColor3 = TEXT_COLOR
			end
		end
	end)
end

return QuestUIController
