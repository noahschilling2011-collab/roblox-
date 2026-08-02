-- StarterPlayer/StarterPlayerScripts/UI/StoreUI.client.luau
--!strict
-- GHOSTNET :: Robux-Store, Taste [P].
--
-- Zeigt nur an, was der Server geschickt hat. Der Kauf selbst laeuft ueber
-- Roblox; was er bewirkt, entscheidet ProcessReceipt auf dem Server.
--
-- Solange Noah keine IDs im Creator Dashboard eingetragen hat, ist hier
-- nichts kaufbar - die Eintraege stehen dann als "noch nicht verfuegbar" da,
-- statt still zu fehlen.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local UITheme = require(ReplicatedStorage.Shared.UITheme)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local C = UITheme.Color

local store = { Passes = {}, Products = {} }
local hackOpen = false

--==========================================================================
-- Aufbau
--==========================================================================

local gui = UITheme.Screen("GhostNetStore", 17)
gui.Parent = playerGui

local openButton = UITheme.Button({
	Name = "OpenStore",
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.new(0, 176, 1, -46),
	Size = UDim2.fromOffset(120, 46),
	BackgroundColor3 = C.Panel,
	BackgroundTransparency = 0.06,
	Text = "",
	Parent = gui,
})
UITheme.Corner(openButton, 4)
UITheme.Stroke(openButton, C.Amber)

UITheme.Label({
	Name = "Caption",
	Text = "[P]  STORE",
	TextColor3 = C.Amber,
	TextSize = 14,
	TextXAlignment = Enum.TextXAlignment.Center,
	Size = UDim2.fromScale(1, 1),
	Parent = openButton,
})

local backdrop = UITheme.Frame({
	Name = "Backdrop",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.new(0, 0, 0),
	BackgroundTransparency = 1,
	Visible = false,
	Parent = gui,
})

local window = UITheme.Frame({
	Name = "Window",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.new(0.9, 0, 0.85, 0),
	BackgroundColor3 = C.Background,
	ClipsDescendants = true,
	Parent = backdrop,
})
UITheme.Corner(window, 5)
UITheme.Stroke(window, C.Amber)

local sizeConstraint = Instance.new("UISizeConstraint")
sizeConstraint.MaxSize = Vector2.new(640, 520)
sizeConstraint.MinSize = Vector2.new(300, 300)
sizeConstraint.Parent = window

local titleBar = UITheme.Frame({
	Name = "TitleBar",
	Size = UDim2.new(1, 0, 0, 34),
	BackgroundColor3 = C.Panel,
	Parent = window,
})

UITheme.Label({
	Name = "Title",
	Text = "GHOSTNET // STORE",
	TextColor3 = C.Amber,
	TextSize = 14,
	Position = UDim2.new(0, 12, 0, 0),
	Size = UDim2.new(0.6, 0, 1, 0),
	Parent = titleBar,
})

local closeButton = UITheme.Button({
	Name = "Close",
	Text = "SCHLIESSEN",
	TextSize = 11,
	TextColor3 = C.Magenta,
	BackgroundColor3 = C.PanelLight,
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, -8, 0.5, 0),
	Size = UDim2.fromOffset(88, 24),
	Parent = titleBar,
})
UITheme.Corner(closeButton, 3)
UITheme.Stroke(closeButton, C.Magenta)

UITheme.Label({
	Name = "Fairness",
	Text = "Nichts hier loest ein Raetsel fuer dich. Zeit, Platz und Aussehen - mehr nicht.",
	TextColor3 = C.TextDim,
	TextSize = 12,
	TextWrapped = true,
	Position = UDim2.new(0, 14, 0, 40),
	Size = UDim2.new(1, -28, 0, 30),
	Parent = window,
})

local list = Instance.new("ScrollingFrame")
list.Name = "List"
list.BackgroundTransparency = 1
list.BorderSizePixel = 0
list.Position = UDim2.new(0, 14, 0, 74)
list.Size = UDim2.new(1, -28, 1, -88)
list.CanvasSize = UDim2.new()
list.AutomaticCanvasSize = Enum.AutomaticSize.Y
list.ScrollBarThickness = 4
list.ScrollBarImageColor3 = C.Line
list.Parent = window

local listLayout = Instance.new("UIListLayout")
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Padding = UDim.new(0, 8)
listLayout.Parent = list

--==========================================================================
-- Anzeige
--==========================================================================

local order = 0

local function clearList()
	order = 0
	for _, child in list:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

local function header(text: string)
	order += 1
	UITheme.Label({
		Name = "H",
		Text = text,
		TextColor3 = C.TextDim,
		TextSize = 11,
		Size = UDim2.new(1, -8, 0, 16),
		LayoutOrder = order,
		Parent = list,
	})
end

local function entry(kind: string, item: { [string]: any })
	order += 1
	local frame = UITheme.Frame({
		Name = tostring(item.Key),
		Size = UDim2.new(1, -8, 0, 68),
		BackgroundColor3 = C.Panel,
		LayoutOrder = order,
		Parent = list,
	})
	UITheme.Corner(frame, 4)
	UITheme.Stroke(frame, C.Line)
	UITheme.Padding(frame, 10)

	UITheme.Label({
		Name = "Name",
		Text = tostring(item.Name),
		TextColor3 = C.Amber,
		TextSize = 15,
		Size = UDim2.new(1, -150, 0, 18),
		Parent = frame,
	})

	UITheme.Label({
		Name = "Text",
		Text = tostring(item.Text),
		TextColor3 = C.TextDim,
		TextSize = 12,
		TextWrapped = true,
		Position = UDim2.new(0, 0, 0, 20),
		Size = UDim2.new(1, -150, 0, 28),
		Parent = frame,
	})

	local button = UITheme.Button({
		Name = "Buy",
		Text = "",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.fromOffset(132, 44), -- Touch-Ziel
		BackgroundColor3 = C.PanelLight,
		Parent = frame,
	})
	UITheme.Corner(button, 4)
	local stroke = UITheme.Stroke(button, C.Line)

	local caption = UITheme.Label({
		Name = "Caption",
		Text = "",
		TextColor3 = C.TextDim,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.fromScale(1, 1),
		Parent = button,
	})

	if item.Owned == true then
		caption.Text = "GEHOERT DIR"
		caption.TextColor3 = C.Green
		stroke.Color = C.Green
	elseif item.Available ~= true then
		-- Ehrlich anzeigen statt still nichts tun: so sieht Noah sofort,
		-- welche ID im Dashboard noch fehlt.
		caption.Text = "NOCH NICHT DA"
		caption.TextColor3 = C.TextDim
	else
		caption.Text = "KAUFEN"
		caption.TextColor3 = C.Amber
		stroke.Color = C.Amber
		button.Activated:Connect(function()
			Remotes.StorePrompt:FireServer({ Kind = kind, Key = item.Key })
		end)
	end
end

local function refresh()
	clearList()
	header("DAUERHAFT (GAMEPASS)")
	for _, item in store.Passes do
		entry("Gamepass", item)
	end
	header("EINMALIG")
	for _, item in store.Products do
		entry("Product", item)
	end
end

--==========================================================================
-- Oeffnen
--==========================================================================

local function setOpen(open: boolean)
	if open and hackOpen then
		return
	end
	backdrop.Visible = open
	openButton.Visible = not open and not hackOpen
	if open then
		refresh()
		backdrop.BackgroundTransparency = 1
		window.Size = UDim2.new(0.9, 0, 0.3, 0)
		TweenService:Create(backdrop, UITheme.Tween.Normal, { BackgroundTransparency = 0.45 }):Play()
		TweenService:Create(window, UITheme.Tween.Slow, { Size = UDim2.new(0.9, 0, 0.85, 0) }):Play()
	end
end

openButton.Activated:Connect(function()
	setOpen(true)
end)
closeButton.Activated:Connect(function()
	setOpen(false)
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	if input.KeyCode == Enum.KeyCode.P then
		setOpen(not backdrop.Visible)
	elseif input.KeyCode == Enum.KeyCode.Escape and backdrop.Visible then
		setOpen(false)
	end
end)

--==========================================================================
-- Server-Meldungen
--==========================================================================

Remotes.StoreSync.OnClientEvent:Connect(function(data: any)
	if typeof(data) ~= "table" then
		return
	end
	store.Passes = if typeof(data.Passes) == "table" then data.Passes else {}
	store.Products = if typeof(data.Products) == "table" then data.Products else {}
	if backdrop.Visible then
		refresh()
	end
end)

Remotes.HackSessionStarted.OnClientEvent:Connect(function()
	hackOpen = true
	setOpen(false)
	openButton.Visible = false
end)

Remotes.HackResolved.OnClientEvent:Connect(function()
	hackOpen = false
	openButton.Visible = not backdrop.Visible
end)

refresh()
