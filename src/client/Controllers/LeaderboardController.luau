--!strict
-- LeaderboardController: Ranglisten-Panel (🏆) am rechten Bildschirmrand.
-- Zeigt die globalen Top-Listen "Meiste Likes" und "Meiste Gesamt-Energie"
-- aus dem LeaderboardUpdated-Event. Die Server-Spielerliste (leaderstats)
-- ergänzt das um die Live-Werte im aktuellen Server.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local Remotes = require(Shared:WaitForChild("Remotes") :: ModuleScript) :: {
	getEvent: (name: string) -> RemoteEvent,
	getFunction: (name: string) -> RemoteFunction,
}

type LeaderboardEntry = { userId: number, name: string, value: number }
type LeaderboardSnapshot = { likes: { LeaderboardEntry }, energy: { LeaderboardEntry } }

-- Farbschema (identisch zum UIController).
local PANEL_COLOR = Color3.fromRGB(30, 32, 44)
local ROW_COLOR = Color3.fromRGB(44, 47, 63)
local STROKE_COLOR = Color3.fromRGB(70, 75, 100)
local TEXT_COLOR = Color3.fromRGB(235, 238, 245)
local SUBTEXT_COLOR = Color3.fromRGB(158, 164, 186)
local SECTION_COLOR = Color3.fromRGB(214, 160, 72)
local HIGHLIGHT_COLOR = Color3.fromRGB(120, 90, 200) -- eigene Platzierung

local PANEL_WIDTH = 280

local LeaderboardController = {}

local localPlayer = Players.LocalPlayer

local listFrame: Frame? = nil
local lastSnapshot: LeaderboardSnapshot = { likes = {}, energy = {} }

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

-- Tausendertrennung mit Punkt (1.234.567).
local function formatNumber(value: number): string
	local text = tostring(math.floor(value))
	local formatted = text
	while true do
		local replaced, count = string.gsub(formatted, "^(-?%d+)(%d%d%d)", "%1.%2")
		formatted = replaced
		if count == 0 then
			break
		end
	end
	return formatted
end

-- Baut die Listen im Panel neu auf.
local function rebuildList()
	local frame = listFrame
	if frame == nil then
		return
	end
	for _, child in frame:GetChildren() do
		if not child:IsA("UIListLayout") then
			child:Destroy()
		end
	end

	local order = 0

	local function addSection(title: string, entries: { LeaderboardEntry }, unit: string)
		order += 1
		local header = Instance.new("TextLabel")
		header.Name = `Header_{order}`
		header.BackgroundTransparency = 1
		header.Size = UDim2.new(1, 0, 0, 22)
		header.Font = Enum.Font.GothamBold
		header.TextSize = 13
		header.TextColor3 = SECTION_COLOR
		header.TextXAlignment = Enum.TextXAlignment.Left
		header.Text = title
		header.LayoutOrder = order
		header.Parent = frame

		if #entries == 0 then
			order += 1
			local hint = Instance.new("TextLabel")
			hint.Name = `Hint_{order}`
			hint.BackgroundTransparency = 1
			hint.Size = UDim2.new(1, 0, 0, 30)
			hint.Font = Enum.Font.GothamMedium
			hint.TextSize = 11
			hint.TextColor3 = SUBTEXT_COLOR
			hint.TextWrapped = true
			hint.TextXAlignment = Enum.TextXAlignment.Left
			hint.Text = "Noch keine Einträge - die Liste aktualisiert sich alle 2 Minuten."
			hint.LayoutOrder = order
			hint.Parent = frame
			return
		end

		for rank, entry in entries do
			order += 1
			local row = Instance.new("Frame")
			row.Name = `Row_{order}`
			row.Size = UDim2.new(1, 0, 0, 26)
			row.BackgroundColor3 = if entry.userId == localPlayer.UserId then HIGHLIGHT_COLOR else ROW_COLOR
			row.LayoutOrder = order
			addCorner(row, 6)
			row.Parent = frame

			local rankLabel = Instance.new("TextLabel")
			rankLabel.BackgroundTransparency = 1
			rankLabel.Position = UDim2.new(0, 8, 0, 0)
			rankLabel.Size = UDim2.new(0, 24, 1, 0)
			rankLabel.Font = Enum.Font.GothamBold
			rankLabel.TextSize = 12
			rankLabel.TextColor3 = SECTION_COLOR
			rankLabel.TextXAlignment = Enum.TextXAlignment.Left
			rankLabel.Text = `{rank}.`
			rankLabel.Parent = row

			local nameLabel = Instance.new("TextLabel")
			nameLabel.BackgroundTransparency = 1
			nameLabel.Position = UDim2.new(0, 34, 0, 0)
			nameLabel.Size = UDim2.new(1, -120, 1, 0)
			nameLabel.Font = Enum.Font.GothamMedium
			nameLabel.TextSize = 12
			nameLabel.TextColor3 = TEXT_COLOR
			nameLabel.TextXAlignment = Enum.TextXAlignment.Left
			nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
			nameLabel.Text = entry.name
			nameLabel.Parent = row

			local valueLabel = Instance.new("TextLabel")
			valueLabel.BackgroundTransparency = 1
			valueLabel.AnchorPoint = Vector2.new(1, 0)
			valueLabel.Position = UDim2.new(1, -8, 0, 0)
			valueLabel.Size = UDim2.new(0, 84, 1, 0)
			valueLabel.Font = Enum.Font.GothamBold
			valueLabel.TextSize = 12
			valueLabel.TextColor3 = TEXT_COLOR
			valueLabel.TextXAlignment = Enum.TextXAlignment.Right
			valueLabel.Text = `{formatNumber(entry.value)} {unit}`
			valueLabel.Parent = row
		end
	end

	addSection("❤️ Meiste Likes", lastSnapshot.likes, "Likes")
	addSection("⚡ Meiste Gesamt-Energie", lastSnapshot.energy, "")
end

local function buildUI()
	local playerGui = localPlayer:WaitForChild("PlayerGui")

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "PlanetForgeLeaderboard"
	screenGui.ResetOnSpawn = false
	screenGui.Parent = playerGui

	local toggleButton = Instance.new("TextButton")
	toggleButton.Name = "LeaderboardToggle"
	toggleButton.AnchorPoint = Vector2.new(1, 0.5)
	toggleButton.Position = UDim2.new(1, -12, 0.25, 0)
	toggleButton.Size = UDim2.new(0, 110, 0, 40)
	toggleButton.BackgroundColor3 = PANEL_COLOR
	toggleButton.Font = Enum.Font.GothamBold
	toggleButton.TextSize = 14
	toggleButton.TextColor3 = TEXT_COLOR
	toggleButton.Text = "🏆 Rangliste"
	addCorner(toggleButton, 10)
	addStroke(toggleButton, STROKE_COLOR)
	toggleButton.Parent = screenGui

	local panel = Instance.new("ScrollingFrame")
	panel.Name = "LeaderboardPanel"
	panel.AnchorPoint = Vector2.new(1, 0)
	panel.Position = UDim2.new(1, -130, 0.25, -20)
	panel.Size = UDim2.new(0, PANEL_WIDTH, 0.55, 0)
	panel.BackgroundColor3 = PANEL_COLOR
	panel.ScrollBarThickness = 6
	panel.AutomaticCanvasSize = Enum.AutomaticSize.Y
	panel.CanvasSize = UDim2.new(0, 0, 0, 0)
	panel.Visible = false
	addCorner(panel, 12)
	addStroke(panel, STROKE_COLOR)
	panel.Parent = screenGui

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 10)
	padding.PaddingBottom = UDim.new(0, 10)
	padding.PaddingLeft = UDim.new(0, 10)
	padding.PaddingRight = UDim.new(0, 10)
	padding.Parent = panel

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 4)
	layout.Parent = panel

	toggleButton.Activated:Connect(function()
		panel.Visible = not panel.Visible
	end)

	listFrame = panel
	rebuildList()
end

function LeaderboardController.init()
	Remotes.getEvent("LeaderboardUpdated").OnClientEvent:Connect(function(snapshot: any)
		if typeof(snapshot) ~= "table" then
			return
		end
		local likes = if typeof(snapshot.likes) == "table" then snapshot.likes else {}
		local energy = if typeof(snapshot.energy) == "table" then snapshot.energy else {}
		lastSnapshot = { likes = likes, energy = energy }
		rebuildList()
	end)

	buildUI()
end

return LeaderboardController
