-- StarterPlayer/StarterPlayerScripts/UI/AdminUI.client.luau
--!strict
-- GHOSTNET :: Admin-Panel, F2.
--
-- WICHTIG: Dieses Skript ist reine Bequemlichkeit. Es entscheidet NICHTS.
-- Ob ein Befehl ausgefuehrt wird, prueft der AdminService in der ersten
-- Zeile jedes Handlers anhand der UserId. Wer dieses Skript manipuliert oder
-- die Remote von Hand feuert, bekommt genau dieselbe Ablehnung.
--
-- Das Panel taucht erst auf, wenn der Server AdminReady geschickt hat.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local UITheme = require(ReplicatedStorage.Shared.UITheme)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local C = UITheme.Color

local authorised = false
local studio = false
local busy = false

--==========================================================================
-- Aufbau
--==========================================================================

local gui = UITheme.Screen("GhostNetAdmin", 40)
gui.Enabled = false
gui.Parent = playerGui

local window = UITheme.Frame({
	Name = "Window",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.new(0.9, 0, 0.85, 0),
	BackgroundColor3 = C.Background,
	ClipsDescendants = true,
	Parent = gui,
})
UITheme.Corner(window, 5)
UITheme.Stroke(window, C.Magenta)

local sizeConstraint = Instance.new("UISizeConstraint")
sizeConstraint.MaxSize = Vector2.new(760, 560)
sizeConstraint.MinSize = Vector2.new(320, 320)
sizeConstraint.Parent = window

local titleBar = UITheme.Frame({
	Name = "TitleBar",
	Size = UDim2.new(1, 0, 0, 32),
	BackgroundColor3 = C.Panel,
	Parent = window,
})

local titleLabel = UITheme.Label({
	Name = "Title",
	Text = "GHOSTNET // ADMIN",
	TextColor3 = C.Magenta,
	TextSize = 14,
	Position = UDim2.new(0, 12, 0, 0),
	Size = UDim2.new(0.7, 0, 1, 0),
	Parent = titleBar,
})

local closeButton = UITheme.Button({
	Name = "Close",
	Text = "F2",
	TextSize = 11,
	TextColor3 = C.TextDim,
	BackgroundColor3 = C.PanelLight,
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, -8, 0.5, 0),
	Size = UDim2.fromOffset(48, 22),
	Parent = titleBar,
})
UITheme.Corner(closeButton, 3)

--== Eingabefelder =========================================================

local function inputBox(name: string, placeholder: string, x: number, width: number): TextBox
	local box = Instance.new("TextBox")
	box.Name = name
	box.BackgroundColor3 = C.PanelLight
	box.BorderSizePixel = 0
	box.Font = UITheme.Font
	box.TextColor3 = C.Text
	box.TextSize = 13
	box.PlaceholderText = placeholder
	box.PlaceholderColor3 = C.TextDim
	box.Text = ""
	box.ClearTextOnFocus = false
	box.Position = UDim2.new(0, x, 0, 40)
	box.Size = UDim2.fromOffset(width, 28)
	box.Parent = window
	UITheme.Corner(box, 3)
	UITheme.Stroke(box, C.Line)
	return box
end

local playerBox = inputBox("PlayerBox", "Spieler (leer = du)", 12, 170)
local valueBox = inputBox("ValueBox", "Wert / Id", 190, 150)

--== Ausgabe ===============================================================

local output = Instance.new("ScrollingFrame")
output.Name = "Output"
output.BackgroundColor3 = C.Panel
output.BorderSizePixel = 0
output.AnchorPoint = Vector2.new(1, 0)
output.Position = UDim2.new(1, -12, 0, 76)
output.Size = UDim2.new(0.46, 0, 1, -88)
output.CanvasSize = UDim2.new()
output.AutomaticCanvasSize = Enum.AutomaticSize.Y
output.ScrollBarThickness = 4
output.ScrollBarImageColor3 = C.Line
output.Parent = window
UITheme.Corner(output, 3)
UITheme.Stroke(output, C.Line)
UITheme.Padding(output, 8)

local outputLayout = Instance.new("UIListLayout")
outputLayout.SortOrder = Enum.SortOrder.LayoutOrder
outputLayout.Padding = UDim.new(0, 2)
outputLayout.Parent = output

local outputLines: { TextLabel } = {}

local function log(text: string, colour: Color3?)
	local line = UITheme.Label({
		Text = text,
		TextColor3 = colour or C.Text,
		TextSize = 11,
		TextWrapped = true,
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.new(1, 0, 0, 0),
		LayoutOrder = #outputLines + 1,
		Parent = output,
	})
	table.insert(outputLines, line)
	while #outputLines > 80 do
		local old = table.remove(outputLines, 1)
		if old then
			old:Destroy()
		end
	end
	output.CanvasPosition = Vector2.new(0, 1e6)
end

--== Befehlsliste ==========================================================

local buttonArea = Instance.new("ScrollingFrame")
buttonArea.Name = "Commands"
buttonArea.BackgroundTransparency = 1
buttonArea.BorderSizePixel = 0
buttonArea.Position = UDim2.new(0, 12, 0, 76)
buttonArea.Size = UDim2.new(0.5, -24, 1, -88)
buttonArea.CanvasSize = UDim2.new()
buttonArea.AutomaticCanvasSize = Enum.AutomaticSize.Y
buttonArea.ScrollBarThickness = 4
buttonArea.ScrollBarImageColor3 = C.Line
buttonArea.Parent = window

local buttonLayout = Instance.new("UIListLayout")
buttonLayout.SortOrder = Enum.SortOrder.LayoutOrder
buttonLayout.Padding = UDim.new(0, 4)
buttonLayout.Parent = buttonArea

local order = 0

local function send(payload: { [string]: any })
	if busy then
		return
	end
	busy = true
	task.spawn(function()
		local ok, response = pcall(function()
			return Remotes.AdminCommand:InvokeServer(payload)
		end)
		busy = false

		if not ok or typeof(response) ~= "table" then
			log("!! Aufruf fehlgeschlagen", C.Magenta)
			return
		end

		log(("%s %s"):format(if response.Ok then ">" else "!!", tostring(response.Text)),
			if response.Ok then C.Cyan else C.Amber)

		-- Tabellenartige Antworten zeilenweise ausgeben.
		for _, key in { "Targets", "Sessions", "Market" } do
			local rows = response[key]
			if typeof(rows) == "table" then
				for _, row in rows do
					local parts: { string } = {}
					for field, value in row do
						table.insert(parts, ("%s=%s"):format(field, tostring(value)))
					end
					table.sort(parts)
					log("   " .. table.concat(parts, "  "), C.TextDim)
				end
			end
		end

		if typeof(response.Json) == "string" then
			log(response.Json, C.Text)
			log("(auch in der Server-Ausgabe zum Kopieren)", C.TextDim)
		end
	end)
end

local function header(text: string)
	order += 1
	local label = UITheme.Label({
		Name = "H",
		Text = text,
		TextColor3 = C.TextDim,
		TextSize = 11,
		Size = UDim2.new(1, -8, 0, 18),
		LayoutOrder = order,
		Parent = buttonArea,
	})
	return label
end

local function command(text: string, build: () -> { [string]: any }, studioOnly: boolean)
	order += 1
	local button = UITheme.Button({
		Name = text,
		Text = text .. (if studioOnly then "   [Studio]" else ""),
		TextSize = 12,
		TextColor3 = if studioOnly then C.Amber else C.Cyan,
		TextXAlignment = Enum.TextXAlignment.Left,
		BackgroundColor3 = C.Panel,
		Size = UDim2.new(1, -8, 0, 30),
		LayoutOrder = order,
		Parent = buttonArea,
	})
	UITheme.Corner(button, 3)
	UITheme.Stroke(button, C.Line)
	UITheme.Padding(button, 8)
	button.Activated:Connect(function()
		send(build())
	end)
end

local function targetPlayer(): string
	return playerBox.Text
end

local function value(): string
	return valueBox.Text
end

local function number(default: number): number
	return tonumber(valueBox.Text) or default
end

header("WIRTSCHAFT")
command("Crypto setzen (Wert = Bank)", function()
	return { Command = "SetCrypto", Player = targetPlayer(), Banked = number(10000) }
end, true)
command("Unverkauft setzen (Wert)", function()
	return { Command = "SetCrypto", Player = targetPlayer(), Unsold = number(500) }
end, true)
command("Rig komplett auf Stufe (Wert)", function()
	return { Command = "SetRig", Player = targetPlayer(), Level = number(5) }
end, true)
command("Trace setzen (Wert)", function()
	return { Command = "SetTrace", Player = targetPlayer(), Value = number(80) }
end, true)
command("Bust ausloesen", function()
	return { Command = "Bust", Player = targetPlayer() }
end, true)

header("MISSIONEN")
command("Zu Mission springen (Wert = Id)", function()
	return { Command = "SetMission", Player = targetPlayer(), MissionId = value() }
end, true)
command("Story zuruecksetzen", function()
	return { Command = "ResetStory", Player = targetPlayer() }
end, true)
command("Unlock vergeben (Wert = Key)", function()
	return { Command = "GrantUnlock", Player = targetPlayer(), Unlock = value() }
end, true)

header("WELT")
command("Alle Ziele auflisten", function()
	return { Command = "ListTargets" }
end, false)
command("Cooldowns loeschen (Wert = TargetId, leer = alle)", function()
	return { Command = "ClearCooldown", Player = targetPlayer(), TargetId = value() }
end, false)
command("Zu Ziel teleportieren (Wert = TargetId)", function()
	return { Command = "Teleport", TargetId = value() }
end, false)

header("MARKT")
command("Kurse anzeigen", function()
	return { Command = "MarketState" }
end, false)
command("Event ausloesen (Wert = Gruppe)", function()
	return { Command = "MarketEvent", Group = value() }
end, true)
command("Preis setzen (Wert = GoodId:Faktor)", function()
	local id, factor = string.match(value(), "^(%w+):([%d%.]+)$")
	return { Command = "SetPrice", GoodId = id or value(), Factor = tonumber(factor) or 1 }
end, true)

header("DEBUG")
command("Aktive Sitzungen", function()
	return { Command = "Sessions" }
end, false)
command("Profil als JSON ausgeben", function()
	return { Command = "DumpProfile", Player = targetPlayer() }
end, false)
command("Speichern erzwingen", function()
	return { Command = "ForceSave", Player = targetPlayer() }
end, false)

--==========================================================================
-- Oeffnen
--==========================================================================

local function toggle()
	if not authorised then
		return
	end
	gui.Enabled = not gui.Enabled
end

closeButton.Activated:Connect(toggle)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	if input.KeyCode == Enum.KeyCode.F2 then
		toggle()
	elseif input.KeyCode == Enum.KeyCode.Escape and gui.Enabled then
		gui.Enabled = false
	end
end)

Remotes.AdminReady.OnClientEvent:Connect(function(data: any)
	authorised = true
	studio = typeof(data) == "table" and data.Studio == true
	titleLabel.Text = if studio then "GHOSTNET // ADMIN  [STUDIO]" else "GHOSTNET // ADMIN  [LIVE]"
	log("Panel bereit. F2 oeffnet und schliesst.", C.Cyan)
	if not studio then
		log("Live-Modus: Wirtschafts- und Missions-Befehle sind gesperrt.", C.Amber)
	end
end)
