--!strict
-- UIController: HUD von Turmfall - Phasen-Banner mit Countdown, Hotbar,
-- Leaderboard und Toast-Meldungen. Der Client spiegelt hier NUR, was der
-- Server sendet (RoundService ist die einzige Source of Truth).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Network = require(Shared:WaitForChild("Network") :: ModuleScript) :: {
	getEvent: (name: string) -> RemoteEvent,
	getFunction: (name: string) -> RemoteFunction,
}
local PartCatalog = require(Shared:WaitForChild("Config"):WaitForChild("PartCatalog") :: ModuleScript) :: any
local GameConfig = require(Shared:WaitForChild("Config"):WaitForChild("GameConfig") :: ModuleScript) :: any

local PANEL_COLOR = Color3.fromRGB(28, 30, 40)
local TEXT_COLOR = Color3.fromRGB(235, 238, 245)
local SUBTEXT_COLOR = Color3.fromRGB(158, 164, 186)
local ACCENT_COLOR = Color3.fromRGB(255, 190, 70)
local DANGER_COLOR = Color3.fromRGB(220, 80, 70)
local OK_COLOR = Color3.fromRGB(90, 190, 120)

local TOAST_COLORS: { [string]: Color3 } = {
	info = Color3.fromRGB(66, 133, 244),
	success = OK_COLOR,
	error = DANGER_COLOR,
}

local PHASE_LABELS: { [string]: string } = {
	Lobby = "LOBBY",
	Aufbau = "AUFBAU",
	Bauphase = "BAUPHASE",
	Wertung = "WERTUNG",
}

local UIController = {}

-- Auswahl-Callback für den PlacementController (Slot-Klick in der Hotbar).
UIController.onSlotSelected = function(_index: number?) end

local hotbarItems: { string } = {}
local selectedIndex: number? = nil
local currentPhase = "Lobby"

local phaseLabel: TextLabel? = nil
local timerLabel: TextLabel? = nil
local slotButtons: { TextButton } = {}
local boardRows: Frame? = nil
local toastContainer: Frame? = nil
local toastOrder = 0

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

local function formatTime(seconds: number): string
	local minutes = math.floor(seconds / 60)
	return string.format("%d:%02d", minutes, seconds % 60)
end

--------------------------------------------------------------------------
-- Aufbau
--------------------------------------------------------------------------

local function buildUI()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "TurmfallUI"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.Parent = playerGui

	-- Phasen-Banner oben Mitte.
	local banner = Instance.new("Frame")
	banner.Name = "PhaseBanner"
	banner.AnchorPoint = Vector2.new(0.5, 0)
	banner.Position = UDim2.new(0.5, 0, 0, 10)
	banner.Size = UDim2.new(0, 300, 0, 58)
	banner.BackgroundColor3 = PANEL_COLOR
	banner.BackgroundTransparency = 0.1
	addCorner(banner, 12)
	addStroke(banner, ACCENT_COLOR)
	banner.Parent = screenGui

	local phase = Instance.new("TextLabel")
	phase.Name = "Phase"
	phase.BackgroundTransparency = 1
	phase.Position = UDim2.new(0, 0, 0, 7)
	phase.Size = UDim2.new(1, 0, 0, 18)
	phase.Font = Enum.Font.GothamBold
	phase.TextSize = 14
	phase.TextColor3 = ACCENT_COLOR
	phase.Text = "LOBBY"
	phase.Parent = banner
	phaseLabel = phase

	local timer = Instance.new("TextLabel")
	timer.Name = "Timer"
	timer.BackgroundTransparency = 1
	timer.Position = UDim2.new(0, 0, 0, 24)
	timer.Size = UDim2.new(1, 0, 0, 30)
	timer.Font = Enum.Font.GothamBold
	timer.TextSize = 24
	timer.TextColor3 = TEXT_COLOR
	timer.Text = "–"
	timer.Parent = banner
	timerLabel = timer

	-- Hotbar unten Mitte (3 Slots, Tasten 1-3).
	local hotbar = Instance.new("Frame")
	hotbar.Name = "Hotbar"
	hotbar.AnchorPoint = Vector2.new(0.5, 1)
	hotbar.Position = UDim2.new(0.5, 0, 1, -16)
	hotbar.Size = UDim2.new(0, 3 * 96 + 2 * 10, 0, 84)
	hotbar.BackgroundTransparency = 1
	hotbar.Parent = screenGui

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Padding = UDim.new(0, 10)
	layout.Parent = hotbar

	for index = 1, GameConfig.HOTBAR_MAX_ITEMS do
		local slot = Instance.new("TextButton")
		slot.Name = `Slot_{index}`
		slot.LayoutOrder = index
		slot.Size = UDim2.new(0, 96, 1, 0)
		slot.BackgroundColor3 = PANEL_COLOR
		slot.BackgroundTransparency = 0.1
		slot.Font = Enum.Font.GothamBold
		slot.TextSize = 13
		slot.TextColor3 = SUBTEXT_COLOR
		slot.TextWrapped = true
		slot.Text = `[{index}]\n–`
		addCorner(slot, 10)
		addStroke(slot, Color3.fromRGB(70, 75, 100))
		slot.Parent = hotbar
		slot.Activated:Connect(function()
			UIController.selectSlot(if selectedIndex == index then nil else index)
		end)
		table.insert(slotButtons, slot)
	end

	-- Leaderboard rechts.
	local board = Instance.new("Frame")
	board.Name = "Leaderboard"
	board.AnchorPoint = Vector2.new(1, 0)
	board.Position = UDim2.new(1, -12, 0, 12)
	board.Size = UDim2.new(0, 220, 0, 30 + 12 * 24)
	board.BackgroundColor3 = PANEL_COLOR
	board.BackgroundTransparency = 0.15
	addCorner(board, 10)
	addStroke(board, Color3.fromRGB(70, 75, 100))
	board.Parent = screenGui

	local boardTitle = Instance.new("TextLabel")
	boardTitle.BackgroundTransparency = 1
	boardTitle.Position = UDim2.new(0, 10, 0, 4)
	boardTitle.Size = UDim2.new(1, -20, 0, 22)
	boardTitle.Font = Enum.Font.GothamBold
	boardTitle.TextSize = 13
	boardTitle.TextColor3 = ACCENT_COLOR
	boardTitle.TextXAlignment = Enum.TextXAlignment.Left
	boardTitle.Text = "🏆 Punkte (Turmhöhe)"
	boardTitle.Parent = board

	local rows = Instance.new("Frame")
	rows.Name = "Rows"
	rows.BackgroundTransparency = 1
	rows.Position = UDim2.new(0, 10, 0, 28)
	rows.Size = UDim2.new(1, -20, 1, -34)
	rows.Parent = board
	local rowLayout = Instance.new("UIListLayout")
	rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rowLayout.Padding = UDim.new(0, 2)
	rowLayout.Parent = rows
	boardRows = rows

	-- Toast-Feed links oben.
	local toasts = Instance.new("Frame")
	toasts.Name = "Toasts"
	toasts.Position = UDim2.new(0, 12, 0, 80)
	toasts.Size = UDim2.new(0, 300, 1, -200)
	toasts.BackgroundTransparency = 1
	toasts.Parent = screenGui
	local toastLayout = Instance.new("UIListLayout")
	toastLayout.SortOrder = Enum.SortOrder.LayoutOrder
	toastLayout.Padding = UDim.new(0, 6)
	toastLayout.Parent = toasts
	toastContainer = toasts
end

--------------------------------------------------------------------------
-- Anzeige-Updates
--------------------------------------------------------------------------

local function refreshHotbar()
	for index, button in slotButtons do
		local partTypeId = hotbarItems[index]
		local def = if partTypeId ~= nil then PartCatalog.Parts[partTypeId] else nil
		if def ~= nil then
			button.Text = `[{index}] {def.icon}\n{def.displayName}`
			button.TextColor3 = TEXT_COLOR
		else
			button.Text = `[{index}]\n–`
			button.TextColor3 = SUBTEXT_COLOR
		end

		local stroke = button:FindFirstChildWhichIsA("UIStroke")
		if stroke ~= nil then
			stroke.Color = if selectedIndex == index then ACCENT_COLOR else Color3.fromRGB(70, 75, 100)
			stroke.Thickness = if selectedIndex == index then 3 else 1
		end
	end
end

-- Slot wählen (auch per Taste aus dem PlacementController). nil = abwählen.
function UIController.selectSlot(index: number?)
	if index ~= nil and hotbarItems[index :: number] == nil then
		index = nil -- leerer Slot ist nicht wählbar
	end
	selectedIndex = index
	refreshHotbar()
	UIController.onSlotSelected(index)
end

-- Aktuelle Auswahl fürs Platzieren.
function UIController.getSelected(): (number?, string?)
	if selectedIndex == nil then
		return nil, nil
	end
	return selectedIndex, hotbarItems[selectedIndex :: number]
end

function UIController.getPhase(): string
	return currentPhase
end

function UIController.showToast(message: string, kind: string)
	local container = toastContainer
	if container == nil then
		return
	end
	toastOrder += 1
	local toast = Instance.new("Frame")
	toast.LayoutOrder = toastOrder
	toast.Size = UDim2.new(1, 0, 0, 0)
	toast.AutomaticSize = Enum.AutomaticSize.Y
	toast.BackgroundColor3 = PANEL_COLOR
	toast.BackgroundTransparency = 0.1
	addCorner(toast, 8)

	local accent = Instance.new("Frame")
	accent.Size = UDim2.new(0, 4, 1, 0)
	accent.BackgroundColor3 = TOAST_COLORS[kind] or TOAST_COLORS.info
	accent.BorderSizePixel = 0
	accent.Parent = toast

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Position = UDim2.new(0, 12, 0, 0)
	label.Size = UDim2.new(1, -20, 0, 0)
	label.AutomaticSize = Enum.AutomaticSize.Y
	label.Font = Enum.Font.GothamMedium
	label.TextSize = 13
	label.TextColor3 = TEXT_COLOR
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextWrapped = true
	label.Text = message
	label.Parent = toast

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 8)
	padding.PaddingBottom = UDim.new(0, 8)
	padding.Parent = toast

	toast.Parent = container
	task.delay(4, function()
		local tween = TweenService:Create(label, TweenInfo.new(0.4), { TextTransparency = 1 })
		tween:Play()
		tween.Completed:Once(function()
			toast:Destroy()
		end)
	end)
end

local function refreshBoard(entries: { any })
	local rows = boardRows
	if rows == nil then
		return
	end
	for _, child in rows:GetChildren() do
		if child:IsA("TextLabel") then
			child:Destroy()
		end
	end
	for rank, entry in entries do
		if typeof(entry) ~= "table" then
			continue
		end
		local row = Instance.new("TextLabel")
		row.LayoutOrder = rank
		row.BackgroundTransparency = 1
		row.Size = UDim2.new(1, 0, 0, 22)
		row.Font = Enum.Font.GothamMedium
		row.TextSize = 13
		row.TextXAlignment = Enum.TextXAlignment.Left
		row.TextTruncate = Enum.TextTruncate.AtEnd
		local marker = if entry.culprit == true then "💥 " else `{rank}. `
		row.Text = `{marker}{entry.name}  –  {entry.points}`
		row.TextColor3 = if entry.culprit == true
			then DANGER_COLOR
			elseif rank == 1 and entry.points > 0 then ACCENT_COLOR
			else TEXT_COLOR
		row.Parent = rows
	end
end

--------------------------------------------------------------------------
-- Init
--------------------------------------------------------------------------

function UIController.init()
	buildUI()

	Network.getEvent("RoundStateChanged").OnClientEvent:Connect(function(phase: any, secondsLeft: any, info: any)
		if typeof(phase) ~= "string" then
			return
		end
		currentPhase = phase;
		(phaseLabel :: TextLabel).Text = PHASE_LABELS[phase] or phase

		local timer = timerLabel :: TextLabel
		if phase == "Lobby" then
			if typeof(info) == "table" and typeof(info.playersNeeded) == "number" and info.playersNeeded > 0 then
				timer.Text = `Warte auf {info.playersNeeded} Spieler…`
				timer.TextSize = 16
			elseif typeof(secondsLeft) == "number" and secondsLeft > 0 then
				timer.Text = `Start in {secondsLeft}…`
				timer.TextSize = 22
			else
				timer.Text = "–"
			end
		elseif typeof(secondsLeft) == "number" then
			timer.Text = formatTime(secondsLeft)
			timer.TextSize = 24
			timer.TextColor3 = if phase == "Bauphase" and secondsLeft <= 15 then DANGER_COLOR else TEXT_COLOR
		end

		-- Nach der Bauphase ist keine Auswahl mehr sinnvoll.
		if phase ~= "Bauphase" and selectedIndex ~= nil then
			UIController.selectSlot(nil)
		end
	end)

	Network.getEvent("HotbarChanged").OnClientEvent:Connect(function(items: any)
		if typeof(items) ~= "table" then
			return
		end
		hotbarItems = items :: { string }
		-- Auswahl prüfen: Slot könnte geleert worden sein.
		if selectedIndex ~= nil and hotbarItems[selectedIndex :: number] == nil then
			UIController.selectSlot(nil)
		else
			refreshHotbar()
		end
	end)

	Network.getEvent("ScoreboardChanged").OnClientEvent:Connect(function(entries: any)
		if typeof(entries) == "table" then
			refreshBoard(entries :: { any })
		end
	end)

	Network.getEvent("Notification").OnClientEvent:Connect(function(message: any, kind: any)
		if typeof(message) == "string" then
			UIController.showToast(message, if typeof(kind) == "string" then kind else "info")
		end
	end)
end

return UIController
