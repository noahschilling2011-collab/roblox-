-- StarterPlayer/StarterPlayerScripts/UI/CityUI.client.luau
--!strict
-- GHOSTNET :: Garage, Fahndungsstufe und die Endgame-Entscheidung.
--
-- Reine Anzeige. Ob ein Fahrzeug ausgeparkt werden darf, was es kostet und
-- welche Fahndungsstufe gilt, entscheidet ausschliesslich der Server.
--
-- Garage mit [G], die Entscheidung erscheint erst, wenn Mission 10 durch ist.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local UITheme = require(ReplicatedStorage.Shared.UITheme)
local Vehicles = require(ReplicatedStorage.Shared.Vehicles)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local C = UITheme.Color

local garage = { Owned = {}, Spawned = "", DealerOpen = false, Colours = {}, RepaintCost = 0 }
local pursuit = { Level = 0, Escaping = false, Seconds = 0 }
local endgame = { Unlocked = false, Choice = "", SwitchIn = 0 }
local banked = 0
local busy = false
local selectedColour = "Schwarz"

--==========================================================================
-- Fahndungsstufe: Sterne oben Mitte
--==========================================================================

local gui = UITheme.Screen("GhostNetCity", 13)
gui.Parent = playerGui

local starHolder = UITheme.Frame({
	Name = "Wanted",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 160),
	Size = UDim2.fromOffset(240, 40),
	BackgroundTransparency = 1,
	Visible = false,
	Parent = gui,
})
local starLayout = Instance.new("UIListLayout")
starLayout.FillDirection = Enum.FillDirection.Horizontal
starLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
starLayout.Padding = UDim.new(0, 6)
starLayout.Parent = starHolder

local stars: { TextLabel } = {}
for index = 1, Config.Pursuit.MaxLevel do
	local star = UITheme.Label({
		Name = "Star",
		Text = "\u{2605}",
		TextColor3 = C.Line,
		TextSize = 26,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.fromOffset(28, 32),
		LayoutOrder = index,
		Parent = starHolder,
	})
	table.insert(stars, star)
end

local escapeLabel = UITheme.Label({
	Name = "Escape",
	Text = "",
	TextColor3 = C.Amber,
	TextSize = 13,
	TextXAlignment = Enum.TextXAlignment.Center,
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 200),
	Size = UDim2.fromOffset(320, 18),
	Visible = false,
	Parent = gui,
})

local function refreshPursuit()
	starHolder.Visible = pursuit.Level > 0
	escapeLabel.Visible = pursuit.Escaping

	for index, star in stars do
		if index <= pursuit.Level then
			local pulse = 0.5 + 0.5 * math.sin(os.clock() * 6 + index)
			star.TextColor3 = C.Magenta:Lerp(C.Amber, pulse * 0.4)
		else
			star.TextColor3 = C.Line
		end
	end

	if pursuit.Escaping then
		escapeLabel.Text = ("AUSSER SICHT - noch %d s, dann bist du raus"):format(math.ceil(pursuit.Seconds))
	end
end

--==========================================================================
-- Garage
--==========================================================================

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
	Size = UDim2.new(0.9, 0, 0.82, 0),
	BackgroundColor3 = C.Background,
	ClipsDescendants = true,
	Parent = backdrop,
})
UITheme.Corner(window, 5)
UITheme.Stroke(window, C.CyanDim)

local sizeConstraint = Instance.new("UISizeConstraint")
sizeConstraint.MaxSize = Vector2.new(700, 520)
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
	Text = "GHOSTNET // GARAGE",
	TextColor3 = C.Cyan,
	TextSize = 14,
	Position = UDim2.new(0, 12, 0, 0),
	Size = UDim2.new(0.5, 0, 1, 0),
	Parent = titleBar,
})

local statusLabel = UITheme.Label({
	Name = "Status",
	Text = "",
	TextColor3 = C.TextDim,
	TextSize = 12,
	TextXAlignment = Enum.TextXAlignment.Right,
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -104, 0, 0),
	Size = UDim2.new(0.5, 0, 1, 0),
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
	Text = "",
	TextColor3 = C.TextDim,
	TextSize = 12,
	Position = UDim2.new(0, 14, 0, 40),
	Size = UDim2.new(1, -28, 0, 16),
	Parent = window,
})

local list = Instance.new("ScrollingFrame")
list.Name = "List"
list.BackgroundTransparency = 1
list.BorderSizePixel = 0
list.Position = UDim2.new(0, 14, 0, 60)
list.Size = UDim2.new(1, -28, 1, -110)
list.CanvasSize = UDim2.new()
list.AutomaticCanvasSize = Enum.AutomaticSize.Y
list.ScrollBarThickness = 4
list.ScrollBarImageColor3 = C.Line
list.Parent = window

local listLayout = Instance.new("UIListLayout")
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Padding = UDim.new(0, 8)
listLayout.Parent = list

local footer = UITheme.Label({
	Name = "Footer",
	Text = "",
	TextColor3 = C.TextDim,
	TextSize = 12,
	Position = UDim2.new(0, 14, 1, -34),
	Size = UDim2.new(1, -28, 0, 18),
	Parent = window,
})

local function say(text: string, colour: Color3)
	footer.Text = text
	footer.TextColor3 = colour
end

local function send(payload: { [string]: any })
	if busy then
		return
	end
	busy = true
	task.spawn(function()
		local ok, response = pcall(function()
			return Remotes.VehicleAction:InvokeServer(payload)
		end)
		busy = false

		if not ok or typeof(response) ~= "table" then
			say("Aktion fehlgeschlagen.", C.Magenta)
			return
		end
		if response.Ok then
			say("Erledigt.", C.Green)
			return
		end

		-- Klartext mit Zahl, wo es eine gibt.
		local reason = response.Reason
		if reason == "FUNDS" then
			say(("Zu wenig auf der Bank - es fehlen %d CRY."):format(response.Missing or 0), C.Amber)
		elseif reason == "TOO_FAR" then
			say(("Zu weit vom Ausparkplatz - %d Studs, erlaubt sind %d."):format(
				response.Distance or 0,
				response.Range or 0
			), C.Amber)
		elseif reason == "CLOSED" then
			say(("Haendler hat zu - offen von %d bis %d Uhr."):format(response.Open or 0, response.Close or 0), C.Amber)
		elseif reason == "NO_DEALER" then
			say("Du stehst nicht beim Haendler.", C.Amber)
		elseif reason == "NO_SPAWN" then
			say("Kein Ausparkplatz in der Naehe.", C.Amber)
		elseif reason == "NOT_OWNED" then
			say("Das Fahrzeug gehoert dir nicht.", C.Amber)
		elseif reason == "ALREADY_OWNED" then
			say("Hast du schon.", C.TextDim)
		else
			say("Abgelehnt.", C.Amber)
		end
	end)
end

local function clearList()
	for _, child in list:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

local function refreshGarage()
	statusLabel.Text = ("BANK %d CRY"):format(banked)
	hintLabel.Text = if garage.DealerOpen
		then "Haendler offen. Kaufen geht nur am Tresen, Ausparken nur in der Garage."
		else ("Haendler geschlossen (%d-%d Uhr). Ausparken geht trotzdem."):format(
			Config.Dealer.OpenHour,
			Config.Dealer.CloseHour
		)

	if not backdrop.Visible then
		return
	end
	clearList()

	local order = 0
	local ownedIds: { [string]: string } = {}
	for _, entry in garage.Owned do
		ownedIds[entry.ClassId] = entry.Colour
	end

	for _, class in Vehicles.List do
		order += 1
		local owned = ownedIds[class.Id] ~= nil
		local isOut = garage.Spawned == class.Id

		local frame = UITheme.Frame({
			Name = class.Id,
			Size = UDim2.new(1, -8, 0, 78),
			BackgroundColor3 = C.Panel,
			LayoutOrder = order,
			Parent = list,
		})
		UITheme.Corner(frame, 4)
		UITheme.Stroke(frame, if isOut then C.Cyan else C.Line)
		UITheme.Padding(frame, 10)

		UITheme.Label({
			Name = "Name",
			Text = class.Name,
			TextColor3 = if owned then C.Cyan else C.TextDim,
			TextSize = 15,
			Size = UDim2.new(1, -150, 0, 18),
			Parent = frame,
		})
		UITheme.Label({
			Name = "Blurb",
			Text = class.Blurb,
			TextColor3 = C.TextDim,
			TextSize = 11,
			TextWrapped = true,
			Position = UDim2.new(0, 0, 0, 19),
			Size = UDim2.new(1, -150, 0, 26),
			Parent = frame,
		})
		UITheme.Label({
			Name = "Stats",
			Text = ("%d km/h  //  Lager +%d  //  Auffaelligkeit %.1fx"):format(
				math.floor(class.MaxSpeed * 1.1),
				Vehicles.StashBonus(class.Id),
				class.HeatFactor
			),
			TextColor3 = C.Amber,
			TextSize = 11,
			Position = UDim2.new(0, 0, 1, -14),
			Size = UDim2.new(1, 0, 0, 14),
			Parent = frame,
		})

		local button = UITheme.Button({
			Name = "Action",
			Text = "",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, 0, 0, 4),
			Size = UDim2.fromOffset(132, 44),
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

		if isOut then
			caption.Text = "EINPARKEN"
			caption.TextColor3 = C.Magenta
			stroke.Color = C.Magenta
			button.Activated:Connect(function()
				send({ Action = "DESPAWN" })
			end)
		elseif owned then
			caption.Text = "AUSPARKEN"
			caption.TextColor3 = C.Cyan
			stroke.Color = C.Cyan
			button.Activated:Connect(function()
				send({ Action = "SPAWN", ClassId = class.Id })
			end)
		else
			caption.Text = ("%d CRY"):format(class.Price)
			caption.TextColor3 = if banked >= class.Price then C.Amber else C.TextDim
			stroke.Color = if banked >= class.Price then C.Amber else C.Line
			button.Activated:Connect(function()
				send({ Action = "BUY", ClassId = class.Id, Colour = selectedColour })
			end)
		end
	end

	-- Lackfarbe. Rein kosmetisch - keine Leistungsteile, sonst muesste das
	-- Fahrverhalten mehrfach ausbalanciert werden.
	order += 1
	local paint = UITheme.Frame({
		Name = "Paint",
		Size = UDim2.new(1, -8, 0, 60),
		BackgroundColor3 = C.Panel,
		LayoutOrder = order,
		Parent = list,
	})
	UITheme.Corner(paint, 4)
	UITheme.Stroke(paint, C.Line)
	UITheme.Padding(paint, 10)

	UITheme.Label({
		Name = "Title",
		Text = ("LACK  //  %d CRY  //  gewaehlt: %s"):format(garage.RepaintCost, selectedColour),
		TextColor3 = C.TextDim,
		TextSize = 12,
		Size = UDim2.new(1, 0, 0, 14),
		Parent = paint,
	})

	local x = 0
	for _, name in Config.Dealer.ColourOptions do
		local swatch = UITheme.Button({
			Name = name,
			Text = name,
			TextSize = 11,
			TextColor3 = if name == selectedColour then C.Cyan else C.TextDim,
			BackgroundColor3 = C.PanelLight,
			Position = UDim2.new(0, x, 0, 20),
			Size = UDim2.fromOffset(84, 26),
			Parent = paint,
		})
		UITheme.Corner(swatch, 3)
		UITheme.Stroke(swatch, if name == selectedColour then C.Cyan else C.Line)
		swatch.Activated:Connect(function()
			selectedColour = name
			refreshGarage()
		end)
		x += 88
	end
end

local function setOpen(open: boolean)
	backdrop.Visible = open
	if open then
		say("", C.TextDim)
		refreshGarage()
		backdrop.BackgroundTransparency = 1
		window.Size = UDim2.new(0.9, 0, 0.3, 0)
		TweenService:Create(backdrop, UITheme.Tween.Normal, { BackgroundTransparency = 0.45 }):Play()
		TweenService:Create(window, UITheme.Tween.Slow, { Size = UDim2.new(0.9, 0, 0.82, 0) }):Play()
	end
end

closeButton.Activated:Connect(function()
	setOpen(false)
end)

--==========================================================================
-- Endgame-Entscheidung
--==========================================================================

local choicePanel = UITheme.Frame({
	Name = "Endgame",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -200),
	Size = UDim2.fromOffset(460, 118),
	BackgroundColor3 = C.Panel,
	BackgroundTransparency = 0.05,
	Visible = false,
	Parent = gui,
})
UITheme.Corner(choicePanel, 4)
UITheme.Stroke(choicePanel, C.Magenta)
UITheme.Padding(choicePanel, 12)

UITheme.Label({
	Name = "Title",
	Text = "DU WARST NIE EIN KRIMINELLER. DU WARST EIN TEST.",
	TextColor3 = C.Magenta,
	TextSize = 13,
	Size = UDim2.new(1, 0, 0, 16),
	Parent = choicePanel,
})

local choiceHint = UITheme.Label({
	Name = "Hint",
	Text = "",
	TextColor3 = C.TextDim,
	TextSize = 11,
	TextWrapped = true,
	Position = UDim2.new(0, 0, 0, 18),
	Size = UDim2.new(1, 0, 0, 28),
	Parent = choicePanel,
})

local function choiceButton(text: string, sub: string, colour: Color3, x: number, choice: string)
	local button = UITheme.Button({
		Name = choice,
		Text = "",
		Position = UDim2.new(0, x, 0, 50),
		Size = UDim2.fromOffset(210, 44),
		BackgroundColor3 = C.PanelLight,
		Parent = choicePanel,
	})
	UITheme.Corner(button, 4)
	UITheme.Stroke(button, colour)

	UITheme.Label({
		Name = "Caption",
		Text = text,
		TextColor3 = colour,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 18),
		Position = UDim2.new(0, 0, 0, 4),
		Parent = button,
	})
	UITheme.Label({
		Name = "Sub",
		Text = sub,
		TextColor3 = C.TextDim,
		TextSize = 10,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 14),
		Position = UDim2.new(0, 0, 0, 24),
		Parent = button,
	})

	button.Activated:Connect(function()
		Remotes.EndgameChoice:FireServer({ Choice = choice })
	end)
end

choiceButton("KASSIEREN", "halber Trace, weniger Beute", C.Cyan, 0, "CASH")
choiceButton("VERBRENNEN", "mehr Ertrag, haerteres Spiel", C.Magenta, 222, "BURN")

local function refreshEndgame()
	choicePanel.Visible = endgame.Unlocked
	if not endgame.Unlocked then
		return
	end
	if endgame.Choice == "" then
		choiceHint.Text = "Entscheide dich. Umstellen geht spaeter einmal pro Woche."
	elseif endgame.SwitchIn > 0 then
		choiceHint.Text = ("Aktuell: %s. Umstellbar in %d Stunden."):format(
			if endgame.Choice == "CASH" then "Kassieren" else "Verbrennen",
			math.ceil(endgame.SwitchIn / 3600)
		)
	else
		choiceHint.Text = ("Aktuell: %s. Du kannst jetzt umstellen."):format(
			if endgame.Choice == "CASH" then "Kassieren" else "Verbrennen"
		)
	end
end

--==========================================================================
-- Eingabe und Server-Meldungen
--==========================================================================

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	if input.KeyCode == Enum.KeyCode.G then
		setOpen(not backdrop.Visible)
	elseif input.KeyCode == Enum.KeyCode.Escape and backdrop.Visible then
		setOpen(false)
	end
end)

Remotes.GarageSync.OnClientEvent:Connect(function(data: any)
	if typeof(data) ~= "table" then
		return
	end
	garage.Owned = if typeof(data.Owned) == "table" then data.Owned else {}
	garage.Spawned = if typeof(data.Spawned) == "string" then data.Spawned else ""
	garage.DealerOpen = data.DealerOpen == true
	garage.RepaintCost = tonumber(data.RepaintCost) or 0
	refreshGarage()
end)

Remotes.PursuitSync.OnClientEvent:Connect(function(data: any)
	if typeof(data) ~= "table" then
		return
	end
	pursuit.Level = tonumber(data.Level) or 0
	pursuit.Escaping = data.Escaping == true
	pursuit.Seconds = tonumber(data.EscapeSeconds) or 0
	refreshPursuit()
end)

Remotes.EconomySync.OnClientEvent:Connect(function(snapshot: any)
	if typeof(snapshot) ~= "table" then
		return
	end
	banked = snapshot.Banked or 0
	refreshGarage()
end)

Remotes.MissionSync.OnClientEvent:Connect(function(data: any)
	if typeof(data) ~= "table" then
		return
	end
	endgame.Choice = if typeof(data.Allegiance) == "string" then data.Allegiance else ""
	endgame.SwitchIn = tonumber(data.AllegianceSwitchIn) or 0
	endgame.Unlocked = false
	if typeof(data.Unlocks) == "table" then
		for _, key in data.Unlocks do
			if key == "ENDGAME" then
				endgame.Unlocked = true
				break
			end
		end
	end
	refreshEndgame()
end)

Remotes.HackSessionStarted.OnClientEvent:Connect(function()
	setOpen(false)
end)

refreshPursuit()
refreshEndgame()
