-- StarterPlayer/StarterPlayerScripts/UI/MissionUI.client.luau
--!strict
-- GHOSTNET :: Auftragsanzeige und Wegpunkt-Marker.
--
-- Reine Anzeige. Dieses Skript entscheidet nie, ob ein Schritt erfuellt ist -
-- das macht ausschliesslich der Server und schickt das Ergebnis per
-- MissionSync. Der einzige Knopf, den der Client druecken darf, ist [E] auf
-- einen Kontakt (TALK-Schritt), und auch den prueft der Server nochmal.
--
-- Solange keine Mission laeuft, ist hier nichts zu sehen.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Geometry = require(ReplicatedStorage.Shared.Geometry)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local UITheme = require(ReplicatedStorage.Shared.UITheme)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local C = UITheme.Color

--==========================================================================
-- Zustand (nur Abschrift dessen, was der Server geschickt hat)
--==========================================================================

local mission = {
	Active = "",
	Title = "",
	StepIndex = 0,
	StepCount = 0,
	StepText = "",
	StepType = "",
	StepProgress = 0,
	StepRequired = 1,
	StepSeconds = nil :: number?,
	StepStartedAt = 0,
	ContactId = nil :: string?,
}

local marker = {
	Position = nil :: Vector3?,
	Label = "",
}

local hackOpen = false

--==========================================================================
-- Aufbau
--==========================================================================

local gui = UITheme.Screen("GhostNetMissions", 12)
gui.Parent = playerGui

local panel = UITheme.Frame({
	Name = "Mission",
	Position = UDim2.new(0, 18, 0, 18),
	Size = UDim2.fromOffset(300, 92),
	BackgroundColor3 = C.Panel,
	BackgroundTransparency = 0.08,
	Visible = false,
	Parent = gui,
})
UITheme.Corner(panel, 4)
local panelStroke = UITheme.Stroke(panel, C.CyanDim)
UITheme.Padding(panel, 10)

local kicker = UITheme.Label({
	Name = "Kicker",
	Text = "AUFTRAG",
	TextColor3 = C.TextDim,
	TextSize = 11,
	Size = UDim2.new(1, 0, 0, 12),
	Parent = panel,
})

local titleLabel = UITheme.Label({
	Name = "Title",
	Text = "",
	TextColor3 = C.Cyan,
	TextSize = 16,
	TextTruncate = Enum.TextTruncate.AtEnd,
	Position = UDim2.new(0, 0, 0, 14),
	Size = UDim2.new(1, 0, 0, 18),
	Parent = panel,
})

local stepLabel = UITheme.Label({
	Name = "Step",
	Text = "",
	TextColor3 = C.Text,
	TextSize = 13,
	TextWrapped = true,
	Position = UDim2.new(0, 0, 0, 34),
	Size = UDim2.new(1, 0, 0, 30),
	Parent = panel,
})

local progressLabel = UITheme.Label({
	Name = "Progress",
	Text = "",
	TextColor3 = C.TextDim,
	TextSize = 11,
	Position = UDim2.new(0, 0, 1, -12),
	Size = UDim2.new(1, 0, 0, 12),
	Parent = panel,
})

local progressTrack = UITheme.Frame({
	Name = "Track",
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, 0, 1, -2),
	Size = UDim2.fromOffset(110, 4),
	BackgroundColor3 = C.PanelLight,
	Parent = panel,
})
local progressFill = UITheme.Frame({
	Name = "Fill",
	Size = UDim2.fromScale(0, 1),
	BackgroundColor3 = C.Cyan,
	Parent = progressTrack,
})

--== Wegpunkt in der Welt ==================================================
-- Ein unsichtbarer Anker-Part traegt das Billboard. Rein clientseitig - er
-- existiert auf dem Server nicht und kann dort auch nichts ausloesen.

local anchor = Instance.new("Part")
anchor.Name = "GhostNetWaypointAnchor"
anchor.Anchored = true
anchor.CanCollide = false
anchor.CanQuery = false
anchor.CanTouch = false
anchor.Transparency = 1
anchor.Size = Vector3.new(1, 1, 1)

local billboard = Instance.new("BillboardGui")
billboard.Name = "Marker"
billboard.Size = UDim2.fromOffset(190, 44)
billboard.StudsOffsetWorldSpace = Vector3.new(0, 4, 0)
billboard.AlwaysOnTop = true
billboard.MaxDistance = 1000
billboard.Enabled = false
billboard.Adornee = anchor
billboard.Parent = anchor

local markerLabel = UITheme.Label({
	Name = "Text",
	Text = "",
	TextColor3 = C.Cyan,
	TextSize = 15,
	TextXAlignment = Enum.TextXAlignment.Center,
	Size = UDim2.new(1, 0, 0.6, 0),
	Parent = billboard,
})

local markerDistance = UITheme.Label({
	Name = "Distance",
	Text = "",
	TextColor3 = C.TextDim,
	TextSize = 12,
	TextXAlignment = Enum.TextXAlignment.Center,
	Position = UDim2.new(0, 0, 0.6, 0),
	Size = UDim2.new(1, 0, 0.4, 0),
	Parent = billboard,
})

anchor.Parent = workspace

--== Kontakt-Prompt (nur bei TALK-Schritten) ===============================

local contactPrompt = UITheme.Button({
	Name = "ContactPrompt",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -136),
	Size = UDim2.fromOffset(300, 46), -- Touch-Ziel
	BackgroundColor3 = C.Panel,
	BackgroundTransparency = 0.06,
	Text = "",
	Visible = false,
	Parent = gui,
})
UITheme.Corner(contactPrompt, 4)
UITheme.Stroke(contactPrompt, C.Amber)

UITheme.Label({
	Name = "Caption",
	Text = "[E]  ANSPRECHEN",
	TextColor3 = C.Amber,
	TextSize = 14,
	TextXAlignment = Enum.TextXAlignment.Center,
	Size = UDim2.fromScale(1, 1),
	Parent = contactPrompt,
})

--==========================================================================
-- Anzeige
--==========================================================================

local function refresh()
	local active = mission.Active ~= "" and not hackOpen
	panel.Visible = active
	if not active then
		return
	end

	titleLabel.Text = mission.Title
	stepLabel.Text = mission.StepText

	local required = math.max(1, mission.StepRequired)
	local done = math.clamp(mission.StepProgress, 0, required)

	if required > 1 then
		progressLabel.Text = ("SCHRITT %d/%d   //   %d von %d"):format(
			mission.StepIndex,
			mission.StepCount,
			done,
			required
		)
	else
		progressLabel.Text = ("SCHRITT %d/%d"):format(mission.StepIndex, mission.StepCount)
	end

	local fraction = if mission.StepCount > 0 then (mission.StepIndex - 1 + done / required) / mission.StepCount else 0
	TweenService:Create(progressFill, UITheme.Tween.Normal, { Size = UDim2.fromScale(fraction, 1) }):Play()
end

--==========================================================================
-- Server-Meldungen
--==========================================================================

Remotes.MissionSync.OnClientEvent:Connect(function(data: any)
	if typeof(data) ~= "table" then
		return
	end

	local wasActive = mission.Active
	mission.Active = if typeof(data.Active) == "string" then data.Active else ""
	mission.Title = if typeof(data.Title) == "string" then data.Title else ""
	mission.StepIndex = tonumber(data.StepIndex) or 0
	mission.StepCount = tonumber(data.StepCount) or 0
	mission.StepText = if typeof(data.StepText) == "string" then data.StepText else ""
	mission.StepType = if typeof(data.StepType) == "string" then data.StepType else ""
	mission.StepProgress = tonumber(data.StepProgress) or 0
	mission.StepRequired = tonumber(data.StepRequired) or 1
	mission.StepSeconds = tonumber(data.StepSeconds)
	mission.StepStartedAt = tonumber(data.StepStartedAt) or 0
	mission.ContactId = if typeof(data.ContactId) == "string" then data.ContactId else nil

	-- Neue Mission: Panel kurz aufziehen, damit man es bemerkt.
	if mission.Active ~= "" and mission.Active ~= wasActive then
		panel.Size = UDim2.fromOffset(300, 60)
		panel.Visible = true
		TweenService:Create(panel, UITheme.Tween.Slow, { Size = UDim2.fromOffset(300, 92) }):Play()
		UITheme.Flash(panel, C.CyanDim)
	end

	refresh()
end)

Remotes.WaypointSync.OnClientEvent:Connect(function(data: any)
	if typeof(data) ~= "table" then
		return
	end
	marker.Position = if typeof(data.Position) == "Vector3" then data.Position else nil
	marker.Label = if typeof(data.Label) == "string" then data.Label else ""

	if marker.Position then
		anchor.Position = marker.Position
		markerLabel.Text = marker.Label
		billboard.Enabled = true
	else
		billboard.Enabled = false
	end
end)

Remotes.HackSessionStarted.OnClientEvent:Connect(function()
	hackOpen = true
	panel.Visible = false
	contactPrompt.Visible = false
	billboard.Enabled = false
end)

Remotes.HackResolved.OnClientEvent:Connect(function()
	hackOpen = false
	if marker.Position then
		billboard.Enabled = true
	end
	refresh()
end)

--==========================================================================
-- TALK: der einzige Knopf, den dieses Skript hat
--==========================================================================

local nearContact = false

local function tryInteract()
	if hackOpen or not nearContact then
		return
	end
	local contactId = mission.ContactId
	if mission.StepType ~= "TALK" or not contactId then
		return
	end
	Remotes.MissionInteract:FireServer({ ContactId = contactId })
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	if input.KeyCode == Enum.KeyCode.E then
		tryInteract()
	end
end)

contactPrompt.Activated:Connect(tryInteract)

--==========================================================================
-- Schleife: Entfernung am Marker, WAIT-Countdown, Kontakt-Prompt
--==========================================================================

local accumulator = 0
RunService.RenderStepped:Connect(function(dt)
	accumulator += dt
	if accumulator < 0.12 then
		return
	end
	accumulator = 0

	local position = Geometry.AlivePosition(player)

	-- Entfernung zum Wegpunkt.
	if billboard.Enabled and marker.Position and position then
		markerDistance.Text = ("%d m"):format(math.floor((marker.Position - position).Magnitude))
	elseif billboard.Enabled then
		markerDistance.Text = ""
	end

	-- Kontakt in Reichweite? Reine Anzeige - der Server prueft nochmal.
	local wantsContact = mission.Active ~= "" and mission.StepType == "TALK" and not hackOpen
	if wantsContact and marker.Position and position then
		nearContact = (marker.Position - position).Magnitude <= Config.Mission.ContactRange
	else
		nearContact = false
	end
	contactPrompt.Visible = nearContact

	-- WAIT-Schritte zaehlen sichtbar herunter, sonst wirkt das Spiel haengend.
	if mission.Active ~= "" and mission.StepType == "WAIT" and mission.StepSeconds then
		local left = math.max(0, mission.StepStartedAt + mission.StepSeconds - os.time())
		progressLabel.Text = ("SCHRITT %d/%d   //   noch %ds"):format(mission.StepIndex, mission.StepCount, left)
	end
end)

refresh()
