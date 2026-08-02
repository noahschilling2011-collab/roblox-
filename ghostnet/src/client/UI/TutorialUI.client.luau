-- StarterPlayer/StarterPlayerScripts/UI/TutorialUI.client.luau
--!strict
-- GHOSTNET :: Der gefuehrte Einstieg - und der Alarm.
--
-- HARTE REGELN FUERS TUTORIAL (aus dem Bauplan, nicht verhandelbar)
--   * Jeder Schritt wird durch eine HANDLUNG ausgeloest, nie durch einen Timer.
--   * Nie zwei Hinweise gleichzeitig sichtbar.
--   * Alles ueberspringbar. Der Zustand liegt im Profil, nicht hier.
--   * Nach Abschluss greift kein einziges Tutorial-Element je wieder.
--
-- Welcher Schritt dran ist, weiss ausschliesslich der Server. Dieses Skript
-- liest nur MissionSync mit und uebersetzt es in einen Satz auf dem Schirm.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local UITheme = require(ReplicatedStorage.Shared.UITheme)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local C = UITheme.Color

local TUTORIAL_MISSION = "M01_FIRSTHACK"

--==========================================================================
-- Zustand
--==========================================================================

local activeMission = ""
local stepIndex = 0
local tutorialDone = false
local currentHint = ""

--==========================================================================
-- Aufbau
--==========================================================================

local gui = UITheme.Screen("GhostNetTutorial", 18)
gui.Parent = playerGui

--== Der eine Hinweis =======================================================
-- Bewusst genau EIN Feld. Zwei Hinweise gleichzeitig gibt es damit nicht,
-- weil der zweite den ersten ueberschreibt.

local hint = UITheme.Frame({
	Name = "Hint",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 24),
	Size = UDim2.fromOffset(460, 58),
	BackgroundColor3 = C.Panel,
	BackgroundTransparency = 0.05,
	Visible = false,
	Parent = gui,
})
UITheme.Corner(hint, 4)
UITheme.Stroke(hint, C.Cyan)
UITheme.Padding(hint, 12)

local hintText = UITheme.Label({
	Name = "Text",
	Text = "",
	TextColor3 = C.Text,
	TextSize = 16,
	TextWrapped = true,
	TextXAlignment = Enum.TextXAlignment.Center,
	Size = UDim2.new(1, -70, 1, 0),
	Parent = hint,
})

local skipButton = UITheme.Button({
	Name = "Skip",
	Text = "UEBERSPRINGEN",
	TextSize = 10,
	TextColor3 = C.TextDim,
	BackgroundColor3 = C.PanelLight,
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, 0, 0.5, 0),
	Size = UDim2.fromOffset(64, 44), -- Touch-Ziel
	Parent = hint,
})
UITheme.Corner(skipButton, 3)
UITheme.Stroke(skipButton, C.Line)

skipButton.Activated:Connect(function()
	Remotes.MissionSkip:FireServer({})
end)

local function showHint(text: string)
	if text == currentHint then
		return
	end
	currentHint = text

	if text == "" then
		hint.Visible = false
		return
	end

	hintText.Text = text
	if not hint.Visible then
		hint.Visible = true
		hint.Size = UDim2.fromOffset(460, 20)
		TweenService:Create(hint, UITheme.Tween.Slow, { Size = UDim2.fromOffset(460, 58) }):Play()
	else
		UITheme.Flash(hint, C.CyanDim)
	end
end

--== Einmalige Hervorhebung des Trace-Balkens ==============================

local traceCallout = UITheme.Frame({
	Name = "TraceCallout",
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -18, 0, 150),
	Size = UDim2.fromOffset(240, 62),
	BackgroundColor3 = C.Panel,
	BackgroundTransparency = 0.05,
	Visible = false,
	Parent = gui,
})
UITheme.Corner(traceCallout, 4)
UITheme.Stroke(traceCallout, C.Magenta)
UITheme.Padding(traceCallout, 10)

UITheme.Label({
	Name = "Text",
	Text = "Das da oben ist deine Spur.\nBei 100 verlierst du alles,\nwas du noch nicht verkauft hast.",
	TextColor3 = C.Text,
	TextSize = 12,
	TextWrapped = true,
	Size = UDim2.fromScale(1, 1),
	Parent = traceCallout,
})

local traceCalloutShown = false

local function showTraceCallout()
	if traceCalloutShown or tutorialDone then
		return
	end
	traceCalloutShown = true
	traceCallout.Visible = true
	traceCallout.BackgroundTransparency = 1
	TweenService:Create(traceCallout, UITheme.Tween.Slow, { BackgroundTransparency = 0.05 }):Play()

	task.delay(7, function()
		TweenService:Create(traceCallout, UITheme.Tween.Slow, { BackgroundTransparency = 1 }):Play()
		task.wait(0.5)
		traceCallout.Visible = false
	end)
end

--==========================================================================
-- Alarm-Anzeige (gehoert nicht zum Tutorial, aber in dieselbe Ebene:
-- es ist der zweite Fall, in dem der Spieler SOFORT etwas verstehen muss)
--==========================================================================

local alarmPanel = UITheme.Frame({
	Name = "Alarm",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 96),
	Size = UDim2.fromOffset(360, 52),
	BackgroundColor3 = C.Panel,
	BackgroundTransparency = 0.05,
	Visible = false,
	Parent = gui,
})
UITheme.Corner(alarmPanel, 4)
local alarmStroke = UITheme.Stroke(alarmPanel, C.Amber)
UITheme.Padding(alarmPanel, 10)

local alarmLabel = UITheme.Label({
	Name = "Text",
	Text = "",
	TextColor3 = C.Amber,
	TextSize = 14,
	Size = UDim2.new(1, 0, 0, 16),
	Parent = alarmPanel,
})

local alarmTrack = UITheme.Frame({
	Name = "Track",
	Position = UDim2.new(0, 0, 0, 20),
	Size = UDim2.new(1, 0, 0, 10),
	BackgroundColor3 = C.PanelLight,
	Parent = alarmPanel,
})
UITheme.Corner(alarmTrack, 3)

local alarmFill = UITheme.Frame({
	Name = "Fill",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = C.Amber,
	Parent = alarmTrack,
})
UITheme.Corner(alarmFill, 3)

local alarm = { Active = false, Remaining = 0, Total = 1, Warn = false, Coop = false }

Remotes.AlarmSync.OnClientEvent:Connect(function(data: any)
	if typeof(data) ~= "table" then
		return
	end

	if data.Active ~= true then
		alarm.Active = false
		alarmPanel.Visible = false
		if data.Triggered == true then
			-- Die Uhr ist durchgelaufen. Der Spieler muss wissen, was das
			-- gekostet hat, sonst wirkt der Trace-Sprung wie ein Bug.
			showHint(("ALARM! Der Laden hat die Polizei gerufen. Trace +%d."):format(
				math.floor(tonumber(data.TracePenalty) or 0)
			))
			task.delay(5, function()
				if currentHint:sub(1, 6) == "ALARM!" then
					showHint("")
				end
			end)
		end
		return
	end

	alarm.Active = true
	alarm.Remaining = tonumber(data.Remaining) or 0
	alarm.Total = math.max(1, tonumber(data.Total) or 1)
	alarm.Warn = alarm.Remaining <= (tonumber(data.WarnAt) or Config.Raid.AlarmWarnAt)
	alarm.Coop = data.Coop == true

	alarmPanel.Visible = true
	alarmLabel.Text = ("ALARM // %s%s"):format(
		if typeof(data.Label) == "string" then data.Label else "",
		if alarm.Coop then "   [PARTNER: halbes Tempo]" else ""
	)
end)

--==========================================================================
-- Tutorial-Ablauf
-- Jeder Zustand haengt an einer Handlung, die der Server bestaetigt hat.
--==========================================================================

local function refreshTutorial()
	if tutorialDone or activeMission ~= TUTORIAL_MISSION then
		showHint("")
		return
	end

	if stepIndex == 1 then
		showHint("Geh zum leuchtenden Terminal und druecke [E].")
	elseif stepIndex == 2 then
		showHint("Geknackt. Die Beute ist noch heiss - bring sie zum Hehler hinter dem Spawn.")
	else
		showHint("")
	end
end

Remotes.MissionSync.OnClientEvent:Connect(function(data: any)
	if typeof(data) ~= "table" then
		return
	end

	activeMission = if typeof(data.Active) == "string" then data.Active else ""
	stepIndex = tonumber(data.StepIndex) or 0

	if typeof(data.Completed) == "table" then
		for _, id in data.Completed do
			if id == TUTORIAL_MISSION then
				tutorialDone = true
			end
		end
	end

	if tutorialDone then
		-- Ab hier greift nie wieder ein Tutorial-Element.
		showHint("")
		hint.Visible = false
		traceCallout.Visible = false
		return
	end

	refreshTutorial()
end)

-- Der erste erfolgreiche Hack ist die Handlung, die den Trace erklaert.
Remotes.HackResolved.OnClientEvent:Connect(function(data: any)
	if tutorialDone or typeof(data) ~= "table" or data.Success ~= true then
		return
	end
	if activeMission == TUTORIAL_MISSION then
		showTraceCallout()
	end
end)

--==========================================================================
-- Schleife: nur der Alarm-Balken muss jeden Frame stimmen
--==========================================================================

RunService.RenderStepped:Connect(function(dt)
	if not alarm.Active then
		return
	end

	-- Lokal weiterzaehlen, damit der Balken fluessig laeuft; der Server
	-- korrigiert alle halbe Sekunde.
	alarm.Remaining = math.max(0, alarm.Remaining - dt)
	local fraction = math.clamp(alarm.Remaining / alarm.Total, 0, 1)
	alarmFill.Size = UDim2.fromScale(fraction, 1)

	local warn = alarm.Remaining <= Config.Raid.AlarmWarnAt
	if warn then
		local pulse = 0.5 + 0.5 * math.sin(os.clock() * 14)
		alarmFill.BackgroundColor3 = C.Magenta:Lerp(C.Amber, pulse)
		alarmStroke.Color = C.Magenta
		alarmStroke.Thickness = 1 + pulse * 1.5
	else
		alarmFill.BackgroundColor3 = C.Amber
		alarmStroke.Color = C.Amber
		alarmStroke.Thickness = 1
	end

	alarmLabel.Text = ("ALARM // noch %ds%s"):format(
		math.ceil(alarm.Remaining),
		if alarm.Coop then "   [PARTNER: halbes Tempo]" else ""
	)
end)
