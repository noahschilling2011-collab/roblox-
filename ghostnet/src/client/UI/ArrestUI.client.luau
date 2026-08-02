-- StarterPlayerScripts/UI/ArrestUI.client.luau
--!strict
-- GHOSTNET :: Festnahme, Zelle und der Entkommen-Balken.
--
-- FAIR BLEIBEN IST EIN ANZEIGEPROBLEM
--   Eine Festnahme fuehlt sich nur dann gerecht an, wenn der Spieler drei
--   Dinge sieht:
--     1. dass ihn jemand gleich greift  ("ZUGRIFF" - die Vorwarnung)
--     2. wie kurz er vor dem Entkommen steht (der Balken)
--     3. wie lange die Zelle noch dauert   (der Countdown)
--   Ohne das ist es Willkuer, und Willkuer laesst Leute aufhoeren.
--
-- ENTSCHIEDEN WIRD NICHTS HIER
--   Der Server nimmt fest, rechnet die Kosten und setzt den Spieler um.
--   Dieses Skript zeigt an, was passiert ist.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local UITheme = require(ReplicatedStorage.Shared.UITheme)

local C = UITheme.Color
local player = Players.LocalPlayer

local gui = UITheme.Screen("GhostNetArrest", 20)
gui.Parent = player:WaitForChild("PlayerGui")

--==========================================================================
-- Entkommen-Balken
--==========================================================================

local escapePanel = UITheme.Frame({
	Name = "Entkommen",
	BackgroundColor3 = C.Panel,
	BackgroundTransparency = 0.1,
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 210),
	Size = UDim2.fromOffset(260, 44),
	Visible = false,
	ZIndex = 4,
})
UITheme.Corner(escapePanel, 4)
UITheme.Stroke(escapePanel, C.Line, 1)
escapePanel.Parent = gui

local escapeLabel = UITheme.Label({
	Name = "Text",
	Text = "ENTKOMMEN",
	TextColor3 = C.Amber,
	TextSize = 12,
	TextXAlignment = Enum.TextXAlignment.Center,
	Position = UDim2.fromOffset(0, 5),
	Size = UDim2.new(1, 0, 0, 14),
	ZIndex = 5,
})
escapeLabel.Parent = escapePanel

local escapeTrack = UITheme.Frame({
	Name = "Balken",
	BackgroundColor3 = C.PanelLight,
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 24),
	Size = UDim2.fromOffset(232, 10),
	ZIndex = 5,
})
UITheme.Corner(escapeTrack, 5)
escapeTrack.Parent = escapePanel

local escapeFill = UITheme.Frame({
	Name = "Fuellung",
	BackgroundColor3 = C.Green,
	Size = UDim2.fromScale(0, 1),
	ZIndex = 6,
})
UITheme.Corner(escapeFill, 5)
escapeFill.Parent = escapeTrack

--==========================================================================
-- Vorwarnung und Festnahme
--==========================================================================

local overlay = UITheme.Frame({
	Name = "Ueberlagerung",
	BackgroundColor3 = C.Background,
	BackgroundTransparency = 1,
	Size = UDim2.fromScale(1, 1),
	Visible = false,
	ZIndex = 60,
})
overlay.Parent = gui

local bigText = UITheme.Label({
	Name = "Meldung",
	Text = "",
	TextColor3 = C.Magenta,
	TextSize = 44,
	TextXAlignment = Enum.TextXAlignment.Center,
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.44),
	Size = UDim2.new(1, 0, 0, 56),
	ZIndex = 61,
})
bigText.Parent = overlay

local subText = UITheme.Label({
	Name = "Untertitel",
	Text = "",
	TextColor3 = C.Text,
	TextSize = 16,
	TextXAlignment = Enum.TextXAlignment.Center,
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.54),
	Size = UDim2.new(1, 0, 0, 24),
	ZIndex = 61,
})
subText.Parent = overlay

local warnLabel = UITheme.Label({
	Name = "Zugriff",
	Text = "ZUGRIFF",
	TextColor3 = C.Magenta,
	TextSize = 26,
	TextXAlignment = Enum.TextXAlignment.Center,
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.72),
	Size = UDim2.new(1, 0, 0, 30),
	Visible = false,
	ZIndex = 62,
})
warnLabel.Parent = gui

--==========================================================================
-- Zustand
--==========================================================================

local jailUntil = 0
local jailStation = ""
local warnUntil = 0

Remotes.PursuitSync.OnClientEvent:Connect(function(payload)
	if typeof(payload) ~= "table" then
		return
	end
	local level = if typeof(payload.Level) == "number" then payload.Level else 0
	local escaping = payload.Escaping == true
	local progress = if typeof(payload.EscapeProgress) == "number" then payload.EscapeProgress else 0

	escapePanel.Visible = level > 0
	if level > 0 then
		escapeFill.Size = UDim2.fromScale(math.clamp(progress, 0, 1), 1)
		if escaping then
			escapeLabel.Text = ("ENTKOMMEN  %d%%"):format(math.floor(progress * 100))
			escapeLabel.TextColor3 = C.Green
			escapeFill.BackgroundColor3 = C.Green
		else
			escapeLabel.Text = if payload.OnFoot == true then "SIE SIND AUSGESTIEGEN" else "SIE SEHEN DICH"
			escapeLabel.TextColor3 = C.Magenta
			escapeFill.BackgroundColor3 = C.Magenta
		end
	end
end)

Remotes.ArrestSync.OnClientEvent:Connect(function(payload)
	if typeof(payload) ~= "table" then
		return
	end
	local state = payload.State
	local seconds = if typeof(payload.Seconds) == "number" then payload.Seconds else 0
	jailStation = if typeof(payload.Station) == "string" then payload.Station else ""

	if state == "WARNING" then
		-- Nie festnehmen ohne Vorwarnung: erst der Ruf, dann der Zugriff.
		warnUntil = os.clock() + Config.Pursuit.WarnSeconds + 0.5
		return
	end

	if state == "CAUGHT" then
		overlay.Visible = true
		overlay.BackgroundTransparency = 0.25
		bigText.Text = "FESTGENOMMEN"
		subText.Text = "Alles Unverkaufte ist weg."
		jailUntil = os.time() + seconds
		return
	end

	if state == "JAILED" then
		overlay.Visible = true
		overlay.BackgroundTransparency = 0.55
		bigText.Text = "ZELLE"
		jailUntil = os.time() + seconds
		return
	end

	if state == "FREE" then
		overlay.Visible = false
		jailUntil = 0
		bigText.Text = ""
		subText.Text = ""
	end
end)

--==========================================================================

RunService.RenderStepped:Connect(function()
	warnLabel.Visible = os.clock() < warnUntil

	if jailUntil > 0 then
		local left = jailUntil - os.time()
		if left <= 0 then
			overlay.Visible = false
			jailUntil = 0
		elseif bigText.Text == "ZELLE" then
			subText.Text = ("%s  //  Entlassung in %d s"):format(jailStation, left)
		end
	end
end)
