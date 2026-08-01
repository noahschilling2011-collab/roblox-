-- StarterPlayer/StarterPlayerScripts/UI/ShopUI.client.luau
--!strict
-- GHOSTNET :: Der Rig-Shop. Hier wird Guthaben zu Fortschritt.
--
-- Das Fenster rechnet NICHTS aus, was zaehlt: Preise stehen in Config und
-- werden vom Server unabhaengig nochmal berechnet. Der Client schickt beim
-- Kauf nur, WELCHES Bauteil gemeint ist.
--
-- Bedienung: Knopf unten links oder Taste [B]. Bewusst von ueberall aus
-- erreichbar - das Rig ist die eigene Ausruestung, kein Ladenregal.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local UITheme = require(ReplicatedStorage.Shared.UITheme)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local C = UITheme.Color

--==========================================================================
-- Zustand (reine Anzeige)
--==========================================================================

local banked = 0
local rig = table.clone(Config.Rig.StartLevels)
local busy = false
local hackOpen = false

type Row = {
	Frame: Frame,
	Level: TextLabel,
	Effect: TextLabel,
	Button: TextButton,
	Price: TextLabel,
}

local rows: { [string]: Row } = {}

--==========================================================================
-- Aufbau
--==========================================================================

local gui = UITheme.Screen("GhostNetShop", 15)
gui.Parent = playerGui

--== Oeffnen-Knopf unten links ============================================

local openButton = UITheme.Button({
	Name = "OpenShop",
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.new(0, 18, 1, -46),
	Size = UDim2.fromOffset(150, 46), -- gross genug fuer Touch
	BackgroundColor3 = C.Panel,
	BackgroundTransparency = 0.06,
	Text = "",
	Parent = gui,
})
UITheme.Corner(openButton, 4)
UITheme.Stroke(openButton, C.CyanDim)

UITheme.Label({
	Name = "Caption",
	Text = "[B]  RIG-SHOP",
	TextColor3 = C.Cyan,
	TextSize = 14,
	TextXAlignment = Enum.TextXAlignment.Center,
	Size = UDim2.fromScale(1, 1),
	Parent = openButton,
})

--== Fenster ===============================================================

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
	Size = UDim2.new(0.9, 0, 0.8, 0),
	BackgroundColor3 = C.Background,
	ClipsDescendants = true,
	Parent = backdrop,
})
UITheme.Corner(window, 5)
UITheme.Stroke(window, C.CyanDim)

local windowSize = Instance.new("UISizeConstraint")
windowSize.MaxSize = Vector2.new(660, 470)
windowSize.MinSize = Vector2.new(300, 300)
windowSize.Parent = window

local titleBar = UITheme.Frame({
	Name = "TitleBar",
	Size = UDim2.new(1, 0, 0, 34),
	BackgroundColor3 = C.Panel,
	Parent = window,
})

UITheme.Label({
	Name = "Title",
	Text = "GHOSTNET // RIG-SHOP",
	TextColor3 = C.Cyan,
	TextSize = 14,
	Position = UDim2.new(0, 12, 0, 0),
	Size = UDim2.new(0.6, 0, 1, 0),
	Parent = titleBar,
})

local bankLabel = UITheme.Label({
	Name = "Bank",
	Text = "BANK 0 CRY",
	TextColor3 = C.Green,
	TextSize = 13,
	TextXAlignment = Enum.TextXAlignment.Right,
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -104, 0, 0),
	Size = UDim2.new(0.4, 0, 1, 0),
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

local hintLabel = UITheme.Label({
	Name = "Hint",
	Text = "Bezahlt wird von der BANK. Unverkauftes zaehlt nicht - erst zum Hehler.",
	TextColor3 = C.TextDim,
	TextSize = 12,
	Position = UDim2.new(0, 14, 0, 40),
	Size = UDim2.new(1, -28, 0, 16),
	Parent = window,
})

local list = UITheme.Frame({
	Name = "List",
	Position = UDim2.new(0, 14, 0, 62),
	Size = UDim2.new(1, -28, 1, -76),
	BackgroundTransparency = 1,
	Parent = window,
})
local listLayout = Instance.new("UIListLayout")
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Padding = UDim.new(0, 8)
listLayout.Parent = list

--== Eine Zeile je Bauteil =================================================

local buy: (string) -> ()

local function buildRow(component: string, order: number): Row
	local frame = UITheme.Frame({
		Name = component,
		Size = UDim2.new(1, 0, 0, 74),
		BackgroundColor3 = C.Panel,
		LayoutOrder = order,
		Parent = list,
	})
	UITheme.Corner(frame, 4)
	UITheme.Stroke(frame, C.Line)
	UITheme.Padding(frame, 10)

	UITheme.Label({
		Name = "Name",
		Text = (Config.Rig.Labels :: any)[component] or component,
		TextColor3 = C.Cyan,
		TextSize = 16,
		Size = UDim2.new(0.55, 0, 0, 18),
		Parent = frame,
	})

	UITheme.Label({
		Name = "Blurb",
		Text = (Config.Rig.Blurbs :: any)[component] or "",
		TextColor3 = C.TextDim,
		TextSize = 12,
		Position = UDim2.new(0, 0, 0, 20),
		Size = UDim2.new(0.55, 0, 0, 14),
		Parent = frame,
	})

	local level = UITheme.Label({
		Name = "Level",
		Text = "",
		TextColor3 = C.Text,
		TextSize = 13,
		Position = UDim2.new(0, 0, 0, 38),
		Size = UDim2.new(0.55, 0, 0, 15),
		Parent = frame,
	})

	local effect = UITheme.Label({
		Name = "Effect",
		Text = "",
		TextColor3 = C.Amber,
		TextSize = 12,
		Position = UDim2.new(0, 0, 1, -14),
		Size = UDim2.new(1, 0, 0, 14),
		Parent = frame,
	})

	local button = UITheme.Button({
		Name = "Buy",
		Text = "",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 4),
		Size = UDim2.fromOffset(132, 44), -- Touch-Ziel
		BackgroundColor3 = C.PanelLight,
		Parent = frame,
	})
	UITheme.Corner(button, 4)
	UITheme.Stroke(button, C.CyanDim)

	local price = UITheme.Label({
		Name = "Price",
		Text = "",
		TextColor3 = C.Text,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.fromScale(1, 1),
		Parent = button,
	})

	button.Activated:Connect(function()
		buy(component)
	end)

	return { Frame = frame, Level = level, Effect = effect, Button = button, Price = price }
end

for index, component in Config.Rig.Components do
	rows[component] = buildRow(component, index)
end

--==========================================================================
-- Anzeige
--==========================================================================

local function refresh()
	bankLabel.Text = ("BANK %d CRY"):format(banked)

	for _, component in Config.Rig.Components do
		local row = rows[component]
		local current = (rig :: any)[component] or 1
		local stroke = row.Frame:FindFirstChildOfClass("UIStroke")

		if current >= Config.Rig.MaxLevel then
			row.Level.Text = ("STUFE %d  //  MAXIMUM"):format(current)
			row.Effect.Text = Config.GetRigEffect(component, current)
			row.Price.Text = "AUSGEBAUT"
			row.Price.TextColor3 = C.TextDim
			row.Button.BackgroundColor3 = C.Panel
			row.Button.AutoButtonColor = false
			if stroke then
				stroke.Color = C.Line
			end
			continue
		end

		local targetLevel = current + 1
		local cost = Config.GetUpgradeCost(component, targetLevel)
		local affordable = banked >= cost and not busy

		row.Level.Text = ("STUFE %d  ->  %d"):format(current, targetLevel)
		row.Effect.Text = ("%s   ->   %s"):format(
			Config.GetRigEffect(component, current),
			Config.GetRigEffect(component, targetLevel)
		)
		row.Price.Text = ("%d CRY"):format(cost)
		row.Price.TextColor3 = if affordable then C.Text else C.TextDim
		row.Button.BackgroundColor3 = if affordable then C.PanelLight else C.Panel
		if stroke then
			stroke.Color = if affordable then C.Cyan else C.Line
		end
	end
end

local function flashRow(component: string, color: Color3, text: string)
	local row = rows[component]
	if not row then
		return
	end
	local original = row.Price.Text
	row.Price.Text = text
	row.Price.TextColor3 = color
	UITheme.Flash(row.Frame, color)
	task.delay(1.2, function()
		if row.Price.Text == text then
			row.Price.Text = original
		end
		refresh()
	end)
end

--==========================================================================
-- Kaufen
--==========================================================================

buy = function(component: string)
	if busy then
		return
	end
	local current = (rig :: any)[component] or 1
	if current >= Config.Rig.MaxLevel then
		return
	end

	busy = true
	refresh()

	task.spawn(function()
		local ok, response = pcall(function()
			return Remotes.ShopPurchase:InvokeServer({ Component = component })
		end)

		busy = false

		if not ok or typeof(response) ~= "table" then
			flashRow(component, C.Magenta, "FEHLER")
			refresh()
			return
		end

		if response.Ok then
			-- Der Server schickt die neuen Werte mit; wir raten nichts.
			if typeof(response.Snapshot) == "table" then
				banked = response.Snapshot.Banked or banked
				if typeof(response.Snapshot.Rig) == "table" then
					rig = response.Snapshot.Rig
				end
			end
			flashRow(component, C.Green, "EINGEBAUT")
			return
		end

		local reasons: { [string]: string } = {
			FUNDS = "ZU TEUER",
			MAX = "MAXIMUM",
			LOADING = "LAEDT NOCH",
			RATE = "ZU SCHNELL",
			BAD_PAYLOAD = "UNGUELTIG",
			INTERNAL = "FEHLER",
		}
		flashRow(component, C.Amber, reasons[response.Reason] or "ABGELEHNT")
	end)
end

--==========================================================================
-- Oeffnen / Schliessen
--==========================================================================

local function setOpen(open: boolean)
	if open and hackOpen then
		return -- waehrend eines Hacks kein zweites Fenster
	end
	backdrop.Visible = open
	openButton.Visible = not open

	if open then
		refresh()
		backdrop.BackgroundTransparency = 1
		window.Size = UDim2.new(0.9, 0, 0.3, 0)
		TweenService:Create(backdrop, UITheme.Tween.Normal, { BackgroundTransparency = 0.4 }):Play()
		TweenService:Create(window, UITheme.Tween.Slow, { Size = UDim2.new(0.9, 0, 0.8, 0) }):Play()
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
	if input.KeyCode == Enum.KeyCode.B then
		setOpen(not backdrop.Visible)
	elseif input.KeyCode == Enum.KeyCode.Escape and backdrop.Visible then
		setOpen(false)
	end
end)

--==========================================================================
-- Server-Meldungen
--==========================================================================

Remotes.EconomySync.OnClientEvent:Connect(function(snapshot: any)
	if typeof(snapshot) ~= "table" then
		return
	end
	banked = snapshot.Banked or 0
	if typeof(snapshot.Rig) == "table" then
		rig = snapshot.Rig
	end
	refresh()
end)

-- Nach dem ersten Verkauf im Tutorial oeffnet sich der Shop genau EINMAL von
-- selbst. Ausgeloest wird das durch den Abschluss der Tutorial-Mission, also
-- durch eine Handlung des Spielers - nie durch einen Timer.
local TUTORIAL_MISSION = "M01_FIRSTHACK"
local tutorialWasDone: boolean? = nil

Remotes.MissionSync.OnClientEvent:Connect(function(data: any)
	if typeof(data) ~= "table" or typeof(data.Completed) ~= "table" then
		return
	end

	local done = false
	for _, id in data.Completed do
		if id == TUTORIAL_MISSION then
			done = true
			break
		end
	end

	-- Beim ersten Paket nach dem Join nur merken, nicht aufmachen: sonst
	-- springt der Shop bei jedem Rejoin wieder auf.
	if tutorialWasDone == nil then
		tutorialWasDone = done
		return
	end

	if done and not tutorialWasDone then
		tutorialWasDone = true
		task.wait(1.2) -- die Abschluss-Meldung erst lesen lassen
		setOpen(true)
	end
end)

-- Waehrend eines Hacks ist der Shop tabu, sonst klickt man sich aus dem
-- laufenden Raetsel heraus.
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
