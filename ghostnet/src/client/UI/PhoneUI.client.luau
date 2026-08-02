-- StarterPlayerScripts/UI/PhoneUI.client.luau
--!strict
-- GHOSTNET :: Das Telefon und der Auftrags-Tracker.
--
-- DAS TELEFON
--   Ein einziges Element traegt die ganze Story. Der Knopf unten rechts
--   leuchtet und pulsiert, wenn Wren geschrieben hat. Drinnen steht der
--   Verlauf - Nachrichten erscheinen einzeln, mit kurzer Tippanimation.
--   Alte Nachrichten bleiben lesbar: wer eine Woche weg war, kommt zurueck
--   in die Geschichte.
--
-- DER TRACKER
--   Links oben, klein, dauerhaft: Titel, aktueller Schritt, Entfernung.
--   Ohne Auftrag steht dort, was zu tun ist - nie eine leere Ecke.
--   Das ist die Antwort auf "was soll ich jetzt machen".
--
-- KEIN NEUES MISSIONSSYSTEM
--   Hier wird nur angezeigt. Angenommen und abgeschlossen wird weiter
--   serverseitig im MissionService.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local UITheme = require(ReplicatedStorage.Shared.UITheme)

local P = Config.Phone
local C = UITheme.Color
local player = Players.LocalPlayer

local gui = UITheme.Screen("GhostNetPhone", 9)
gui.Parent = player:WaitForChild("PlayerGui")

--==========================================================================
-- Auftrags-Tracker, links oben
--==========================================================================

local tracker = UITheme.Frame({
	Name = "Auftrag",
	BackgroundColor3 = C.Panel,
	BackgroundTransparency = 0.1,
	Position = UDim2.fromOffset(14, 14),
	Size = UDim2.fromOffset(280, 62),
	ZIndex = 3,
})
UITheme.Corner(tracker, 4)
UITheme.Stroke(tracker, C.Line, 1)
tracker.Parent = gui

local trackerTitle = UITheme.Label({
	Name = "Titel",
	Text = "KEIN AUFTRAG",
	TextColor3 = C.Cyan,
	TextSize = 14,
	Position = UDim2.fromOffset(10, 6),
	Size = UDim2.fromOffset(260, 18),
	ZIndex = 4,
})
trackerTitle.Parent = tracker

local trackerStep = UITheme.Label({
	Name = "Schritt",
	Text = "[M] oeffnet die Karte",
	TextColor3 = C.Text,
	TextSize = 12,
	TextWrapped = true,
	Position = UDim2.fromOffset(10, 24),
	Size = UDim2.fromOffset(200, 32),
	ZIndex = 4,
})
trackerStep.Parent = tracker

local trackerDistance = UITheme.Label({
	Name = "Entfernung",
	Text = "",
	TextColor3 = C.Amber,
	TextSize = 13,
	TextXAlignment = Enum.TextXAlignment.Right,
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, -10, 1, -6),
	Size = UDim2.fromOffset(80, 16),
	ZIndex = 4,
})
trackerDistance.Parent = tracker

--==========================================================================
-- Telefon-Knopf, unten rechts
--==========================================================================

local phoneButton = UITheme.Button({
	Name = "Telefon",
	Text = "",
	BackgroundColor3 = C.Panel,
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, -P.Margin, 1, -P.Margin),
	Size = UDim2.fromOffset(P.ButtonSize, P.ButtonSize),
	ZIndex = 6,
})
UITheme.Corner(phoneButton, 10)
local phoneStroke = UITheme.Stroke(phoneButton, C.Line, 2)
phoneButton.Parent = gui

-- Das Symbol: ein Hoerer ist ohne Bild schwer, ein Display mit Antenne
-- liest sich sofort als Geraet.
do
	local screen = UITheme.Frame({
		Name = "Display",
		BackgroundColor3 = C.Cyan,
		BackgroundTransparency = 0.35,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.52),
		Size = UDim2.fromOffset(P.ButtonSize * 0.44, P.ButtonSize * 0.6),
		ZIndex = 7,
	})
	UITheme.Corner(screen, 3)
	screen.Parent = phoneButton
end

local badge = UITheme.Frame({
	Name = "Neu",
	BackgroundColor3 = C.Magenta,
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, 2, 0, -2),
	Size = UDim2.fromOffset(14, 14),
	Visible = false,
	ZIndex = 9,
})
UITheme.Corner(badge, 7)
badge.Parent = phoneButton

--==========================================================================
-- Chatfenster
--==========================================================================

local backdrop = UITheme.Frame({
	Name = "Hintergrund",
	BackgroundColor3 = C.Background,
	BackgroundTransparency = 0.35,
	Size = UDim2.fromScale(1, 1),
	Visible = false,
	ZIndex = 40,
})
backdrop.Parent = gui

local panel = UITheme.Frame({
	Name = "Chat",
	BackgroundColor3 = C.Panel,
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, -P.Margin, 1, -P.Margin - P.ButtonSize - 10),
	Size = UDim2.fromOffset(P.PanelWidth, P.PanelHeight),
	ZIndex = 41,
})
UITheme.Corner(panel, 6)
UITheme.Stroke(panel, C.Cyan, 1)
panel.Parent = backdrop

local header = UITheme.Label({
	Name = "Kopf",
	Text = "WREN",
	TextColor3 = C.Magenta,
	TextSize = 16,
	Position = UDim2.fromOffset(12, 8),
	Size = UDim2.fromOffset(200, 20),
	ZIndex = 42,
})
header.Parent = panel

local summaryLabel = UITheme.Label({
	Name = "Rueckblick",
	Text = "",
	TextColor3 = C.TextDim,
	TextSize = 11,
	TextWrapped = true,
	Position = UDim2.fromOffset(12, 28),
	Size = UDim2.fromOffset(P.PanelWidth - 24, 26),
	ZIndex = 42,
})
summaryLabel.Parent = panel

local scroll = Instance.new("ScrollingFrame")
scroll.Name = "Verlauf"
scroll.BackgroundTransparency = 1
scroll.BorderSizePixel = 0
scroll.Position = UDim2.fromOffset(10, 58)
scroll.Size = UDim2.fromOffset(P.PanelWidth - 20, P.PanelHeight - 118)
scroll.CanvasSize = UDim2.fromOffset(0, 0)
scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
scroll.ScrollBarThickness = 4
scroll.ScrollBarImageColor3 = C.Line
scroll.ZIndex = 42
scroll.Parent = panel

local layout = Instance.new("UIListLayout")
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Padding = UDim.new(0, 8)
layout.Parent = scroll

local acceptButton = UITheme.Button({
	Name = "Annehmen",
	Text = "ANNEHMEN",
	TextColor3 = C.Green,
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -10),
	Size = UDim2.fromOffset(P.PanelWidth - 24, 40),
	Visible = false,
	ZIndex = 44,
})
UITheme.Corner(acceptButton, 4)
acceptButton.Parent = panel

local closeButton = UITheme.Button({
	Name = "Schliessen",
	Text = "X",
	TextColor3 = C.TextDim,
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -8, 0, 6),
	Size = UDim2.fromOffset(34, 26),
	ZIndex = 44,
})
UITheme.Corner(closeButton, 4)
closeButton.Parent = panel

--==========================================================================
-- Nachrichten zeichnen
--==========================================================================

local order = 0

local function bubble(from: string, text: string, dim: boolean): Frame
	order += 1
	local mine = from == "DU"

	local holder = UITheme.Frame({
		Name = from,
		BackgroundColor3 = if mine then C.PanelLight else C.Background,
		BackgroundTransparency = if dim then 0.5 else 0.05,
		Size = UDim2.new(0.86, 0, 0, 20),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = order,
		ZIndex = 43,
	})
	UITheme.Corner(holder, 5)
	UITheme.Padding(holder, 8)

	local alignment = Instance.new("UIListLayout")
	alignment.Parent = holder

	local label = UITheme.Label({
		Name = "Text",
		Text = text,
		TextColor3 = if mine then C.TextDim else C.Text,
		TextTransparency = if dim then 0.35 else 0,
		TextSize = 13,
		TextWrapped = true,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		ZIndex = 44,
	})
	label.Parent = holder

	if mine then
		local push = Instance.new("UIPadding")
		push.PaddingLeft = UDim.new(0, 40)
		push.Parent = holder
	end

	holder.Parent = scroll
	return holder
end

-- Tippanimation. Ohne sie fuehlt sich der Chat wie eine Textwand an, mit ihr
-- wie ein Gespraech - und das ist der ganze Punkt am Telefon.
local typingToken = 0

local function showTyping(): Frame
	order += 1
	local dots = UITheme.Frame({
		Name = "Tippt",
		BackgroundColor3 = C.Background,
		BackgroundTransparency = 0.2,
		Size = UDim2.fromOffset(56, 24),
		LayoutOrder = order,
		ZIndex = 43,
	})
	UITheme.Corner(dots, 5)

	local label = UITheme.Label({
		Text = "...",
		TextColor3 = C.TextDim,
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 44,
	})
	label.Parent = dots

	dots.Parent = scroll
	return dots
end

local activeMission = ""

local function render(payload: { [string]: any })
	typingToken += 1
	local token = typingToken

	for _, child in scroll:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	order = 0

	summaryLabel.Text = if typeof(payload.Summary) == "string" then payload.Summary else ""

	local messages = payload.Messages
	if typeof(messages) ~= "table" then
		return
	end

	-- Alles Erledigte sofort und blass. Nur die aktuelle Nachricht wird
	-- getippt - sonst wartet man beim Wiedereinstieg eine Minute auf
	-- Nachrichten, die man laengst kennt.
	local last: { [string]: any }? = nil
	for _, message in messages do
		if message.State == "ACTIVE" then
			last = message
		else
			bubble(message.From, message.Text, true)
		end
	end

	if not last then
		acceptButton.Visible = false
		activeMission = ""
		return
	end

	activeMission = last.Mission
	task.spawn(function()
		local dots = showTyping()
		task.wait(P.TypingSeconds)
		if token ~= typingToken then
			dots:Destroy()
			return
		end
		dots:Destroy()

		local holder = bubble(last.From, "", false)
		local label = holder:FindFirstChild("Text")
		if label and label:IsA("TextLabel") then
			UITheme.TypeInto(label, last.Text, P.CharsPerSecond, function()
				return token ~= typingToken
			end)
		end
		if token == typingToken then
			acceptButton.Visible = true
		end
	end)
end

--==========================================================================
-- Empfangen
--==========================================================================

local unread = false

Remotes.PhoneSync.OnClientEvent:Connect(function(payload)
	if typeof(payload) ~= "table" then
		return
	end
	unread = payload.Unread == true
	badge.Visible = unread
	render(payload)
end)

--== Tracker-Daten =========================================================

local stepText = ""
local missionTitle = ""
local waypoint: Vector3? = nil

Remotes.MissionSync.OnClientEvent:Connect(function(payload)
	if typeof(payload) ~= "table" then
		return
	end
	missionTitle = if typeof(payload.Title) == "string" then payload.Title else ""
	stepText = if typeof(payload.StepText) == "string" then payload.StepText else ""

	if missionTitle == "" then
		trackerTitle.Text = "KEIN AUFTRAG"
		trackerTitle.TextColor3 = C.TextDim
		trackerStep.Text = "[M] oeffnet die Karte"
	else
		trackerTitle.Text = missionTitle:upper()
		trackerTitle.TextColor3 = C.Cyan
		trackerStep.Text = stepText
		-- Kurz aufleuchten, wenn sich etwas getan hat. Sonst dezent.
		UITheme.Flash(tracker, C.Cyan)
	end
end)

Remotes.WaypointSync.OnClientEvent:Connect(function(payload)
	waypoint = if typeof(payload) == "table" and typeof(payload.Position) == "Vector3"
		then payload.Position
		else nil
end)

--==========================================================================
-- Laufender Betrieb
--==========================================================================

local function alivePosition(): Vector3?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root.Position
	end
	return nil
end

RunService.RenderStepped:Connect(function()
	-- Entfernung zum aktuellen Ziel. Der wichtigste Wert im Tracker: er
	-- sagt dem Spieler, ob er richtig laeuft.
	local position = alivePosition()
	if waypoint and position then
		local flat = Vector3.new(waypoint.X - position.X, 0, waypoint.Z - position.Z)
		trackerDistance.Text = ("%dm"):format(math.round(flat.Magnitude))
	else
		trackerDistance.Text = ""
	end

	if unread then
		local pulse = 0.5 + 0.5 * math.sin(os.clock() * P.PulseSpeed)
		phoneStroke.Color = C.Line:Lerp(C.Magenta, pulse)
		phoneStroke.Thickness = 2 + P.PulseDepth * pulse * 4
	else
		phoneStroke.Color = C.Line
		phoneStroke.Thickness = 2
	end
end)

--==========================================================================
-- Bedienung
--==========================================================================

local function setOpen(open: boolean)
	backdrop.Visible = open
	if open then
		Remotes.PhoneRead:FireServer()
		unread = false
		badge.Visible = false
	end
end

phoneButton.Activated:Connect(function()
	setOpen(not backdrop.Visible)
end)
closeButton.Activated:Connect(function()
	setOpen(false)
end)

acceptButton.Activated:Connect(function()
	if activeMission ~= "" then
		-- Setzt serverseitig den Wegpunkt - und damit auch die Route.
		Remotes.MissionAccept:FireServer({ MissionId = activeMission })
	end
	setOpen(false)
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	if input.KeyCode == Enum.KeyCode.T then
		setOpen(not backdrop.Visible)
	elseif input.KeyCode == Enum.KeyCode.Escape and backdrop.Visible then
		setOpen(false)
	end
end)
