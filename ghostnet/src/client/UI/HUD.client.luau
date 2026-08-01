-- StarterPlayer/StarterPlayerScripts/UI/HUD.client.luau
--!strict
-- GHOSTNET :: Dauerhaftes HUD - Wallet, Trace, Ziel-Prompt, Meldungen.
--
-- Der HUD trifft KEINE Entscheidungen. Er zeigt an, was der Server sagt,
-- und schickt beim Druck auf [E] eine Bitte los. Ob sie erlaubt ist,
-- entscheidet ausschliesslich der Server.
--
-- Der Trace-Balken ist das wichtigste Element auf dem Schirm: er muss immer
-- sichtbar sein und ab Config.Trace.WarnAt anfangen zu pulsieren. Die Frage
-- "noch ein Hack oder erst verkaufen?" soll man fuehlen, nicht ausrechnen.

local CollectionService = game:GetService("CollectionService")
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
-- Zustand
--==========================================================================

local wallet = { Banked = 0, Unsold = 0, Tier = 1 }
local rig = table.clone(Config.Rig.StartLevels)
local trace = { Value = 0, Max = Config.Trace.Max, Locked = false, LockUntil = 0 }
local hackOpen = false
local cooldownUntil: { [string]: number } = {} -- [targetId] = os.clock()

-- Worauf der Prompt gerade zeigt: entweder ein Hack-Ziel oder der Hehler.
local currentKind: string? = nil -- "HACK" | "FENCE"
local currentTargetId: string? = nil

--==========================================================================
-- Aufbau
--==========================================================================

local gui = UITheme.Screen("GhostNetHUD", 10)
gui.Parent = playerGui

--== Wallet oben rechts ====================================================

local walletPanel = UITheme.Frame({
	Name = "Wallet",
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -18, 0, 18),
	Size = UDim2.fromOffset(240, 62),
	BackgroundColor3 = C.Panel,
	BackgroundTransparency = 0.08,
	Parent = gui,
})
UITheme.Corner(walletPanel, 4)
UITheme.Stroke(walletPanel, C.Line)
UITheme.Padding(walletPanel, 10)

UITheme.Label({
	Name = "Title",
	Text = "UNVERKAUFT",
	TextColor3 = C.TextDim,
	TextSize = 11,
	Size = UDim2.new(1, 0, 0, 12),
	Parent = walletPanel,
})

local walletValue = UITheme.Label({
	Name = "Value",
	Text = "0 CRY",
	TextColor3 = C.Cyan,
	TextSize = 22,
	Position = UDim2.new(0, 0, 0, 14),
	Size = UDim2.new(1, 0, 0, 26),
	Parent = walletPanel,
})

local walletSub = UITheme.Label({
	Name = "Sub",
	Text = "BANK 0   //   TIER 1",
	TextColor3 = C.TextDim,
	TextSize = 12,
	Position = UDim2.new(0, 0, 1, -13),
	Size = UDim2.new(1, 0, 0, 13),
	Parent = walletPanel,
})

--== Trace direkt darunter =================================================

local tracePanel = UITheme.Frame({
	Name = "Trace",
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -18, 0, 88),
	Size = UDim2.fromOffset(240, 54),
	BackgroundColor3 = C.Panel,
	BackgroundTransparency = 0.08,
	Parent = gui,
})
UITheme.Corner(tracePanel, 4)
local traceStroke = UITheme.Stroke(tracePanel, C.Line)
UITheme.Padding(tracePanel, 10)

local traceTitle = UITheme.Label({
	Name = "Title",
	Text = "TRACE",
	TextColor3 = C.TextDim,
	TextSize = 11,
	Size = UDim2.new(0.5, 0, 0, 12),
	Parent = tracePanel,
})

local traceValue = UITheme.Label({
	Name = "Value",
	Text = "0%",
	TextColor3 = C.Cyan,
	TextSize = 12,
	TextXAlignment = Enum.TextXAlignment.Right,
	Position = UDim2.new(0.5, 0, 0, 0),
	Size = UDim2.new(0.5, 0, 0, 12),
	Parent = tracePanel,
})

local traceTrack = UITheme.Frame({
	Name = "Track",
	Position = UDim2.new(0, 0, 0, 18),
	Size = UDim2.new(1, 0, 0, 12),
	BackgroundColor3 = C.PanelLight,
	Parent = tracePanel,
})
UITheme.Corner(traceTrack, 3)

local traceFill = UITheme.Frame({
	Name = "Fill",
	Size = UDim2.fromScale(0, 1),
	BackgroundColor3 = C.Cyan,
	Parent = traceTrack,
})
UITheme.Corner(traceFill, 3)

local traceHint = UITheme.Label({
	Name = "Hint",
	Text = "ruhig",
	TextColor3 = C.TextDim,
	TextSize = 11,
	Position = UDim2.new(0, 0, 1, -12),
	Size = UDim2.new(1, 0, 0, 12),
	Parent = tracePanel,
})

--== Ziel-Prompt unten Mitte ===============================================

local prompt = UITheme.Button({
	Name = "TargetPrompt",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -46),
	Size = UDim2.fromOffset(380, 82),
	BackgroundColor3 = C.Panel,
	BackgroundTransparency = 0.06,
	Visible = false,
	Parent = gui,
})
UITheme.Corner(prompt, 4)
local promptStroke = UITheme.Stroke(prompt, C.CyanDim)
UITheme.Padding(prompt, 12)

local promptName = UITheme.Label({
	Name = "Name",
	Text = "",
	TextColor3 = C.Cyan,
	TextSize = 16,
	Size = UDim2.new(1, 0, 0, 18),
	Parent = prompt,
})

local promptInfo = UITheme.Label({
	Name = "Info",
	Text = "",
	TextColor3 = C.TextDim,
	TextSize = 12,
	Position = UDim2.new(0, 0, 0, 22),
	Size = UDim2.new(1, 0, 0, 14),
	Parent = prompt,
})

local promptAction = UITheme.Label({
	Name = "Action",
	Text = "[E]  BREACH",
	TextColor3 = C.Text,
	TextSize = 15,
	Position = UDim2.new(0, 0, 1, -18),
	Size = UDim2.new(1, 0, 0, 16),
	Parent = prompt,
})

--== Meldungen =============================================================

local toastHolder = UITheme.Frame({
	Name = "Toasts",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -138),
	Size = UDim2.fromOffset(440, 130),
	BackgroundTransparency = 1,
	Parent = gui,
})
local toastLayout = Instance.new("UIListLayout")
toastLayout.SortOrder = Enum.SortOrder.LayoutOrder
toastLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom
toastLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
toastLayout.Padding = UDim.new(0, 4)
toastLayout.Parent = toastHolder

local toastOrder = 0

local function toast(text: string, color: Color3)
	toastOrder += 1
	local item = UITheme.Frame({
		Name = "Toast",
		Size = UDim2.fromOffset(440, 26),
		BackgroundColor3 = C.Panel,
		BackgroundTransparency = 0.15,
		LayoutOrder = toastOrder,
		Parent = toastHolder,
	})
	UITheme.Corner(item, 3)
	UITheme.Stroke(item, color)

	local label = UITheme.Label({
		Text = text,
		TextColor3 = color,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.fromScale(1, 1),
		Parent = item,
	})

	task.delay(3.2, function()
		if not item.Parent then
			return
		end
		TweenService:Create(item, UITheme.Tween.Normal, { BackgroundTransparency = 1 }):Play()
		TweenService:Create(label, UITheme.Tween.Normal, { TextTransparency = 1 }):Play()
		task.wait(0.3)
		item:Destroy()
	end)
end

--== Bust-Blitz ============================================================

local bustFlash = UITheme.Frame({
	Name = "BustFlash",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = C.Magenta,
	BackgroundTransparency = 1,
	Visible = false,
	ZIndex = 80,
	Parent = gui,
})

local bustBanner = UITheme.Label({
	Name = "BustBanner",
	Text = "",
	TextColor3 = C.Magenta,
	TextSize = 40,
	TextXAlignment = Enum.TextXAlignment.Center,
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.36),
	Size = UDim2.new(1, 0, 0, 48),
	TextTransparency = 1,
	ZIndex = 81,
	Parent = gui,
})

local function playBust(lost: number)
	bustFlash.Visible = true
	bustFlash.BackgroundTransparency = 0.35
	bustBanner.Text = ("GESCHNAPPT  //  -%d CRY"):format(lost)
	bustBanner.TextTransparency = 0

	TweenService:Create(bustFlash, TweenInfo.new(0.9, Enum.EasingStyle.Quad), { BackgroundTransparency = 1 }):Play()
	TweenService:Create(bustBanner, TweenInfo.new(2.0, Enum.EasingStyle.Quad), { TextTransparency = 1 }):Play()
	task.delay(2.1, function()
		bustFlash.Visible = false
	end)

	toast(("TRACE 100 - ALLES UNVERKAUFTE VERLOREN (-%d CRY)"):format(lost), C.Magenta)
end

--== Weltmarkierung des naechsten Ziels ====================================

local highlight = Instance.new("Highlight")
highlight.FillColor = C.Cyan
highlight.FillTransparency = 0.86
highlight.OutlineColor = C.Cyan
highlight.OutlineTransparency = 0.15
highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
highlight.Enabled = false
highlight.Parent = gui

--==========================================================================
-- Anzeige aktualisieren
--==========================================================================

local function refreshWallet()
	walletValue.Text = ("%d CRY"):format(wallet.Unsold)
	walletValue.TextColor3 = if wallet.Unsold > 0 then C.Cyan else C.TextDim
	walletSub.Text = ("BANK %d   //   TIER %d"):format(wallet.Banked, wallet.Tier)
end

local function refreshTrace()
	local fraction = math.clamp(trace.Value / math.max(1, trace.Max), 0, 1)
	traceFill.Size = UDim2.fromScale(fraction, 1)
	traceValue.Text = ("%d%%"):format(math.floor(trace.Value + 0.5))

	if trace.Locked then
		traceHint.Text = ("gesperrt // %ds"):format(math.ceil(math.max(0, trace.LockUntil - os.clock())))
		traceHint.TextColor3 = C.Magenta
	elseif trace.Value >= Config.Trace.CriticalAt then
		traceHint.Text = "KRITISCH - sofort verkaufen"
		traceHint.TextColor3 = C.Magenta
	elseif trace.Value >= Config.Trace.WarnAt then
		traceHint.Text = "heiss - besser abliefern"
		traceHint.TextColor3 = C.Amber
	elseif trace.Value > 0 then
		traceHint.Text = "kuehlt ab"
		traceHint.TextColor3 = C.TextDim
	else
		traceHint.Text = "ruhig"
		traceHint.TextColor3 = C.TextDim
	end
end

local function cooldownLeft(id: string): number
	local until_ = cooldownUntil[id]
	if not until_ then
		return 0
	end
	return math.max(0, until_ - os.clock())
end

local function hidePrompt()
	if prompt.Visible then
		prompt.Visible = false
	end
	currentKind = nil
	currentTargetId = nil
	highlight.Enabled = false
	highlight.Adornee = nil
end

local function showFencePrompt(fence: BasePart, distance: number)
	currentKind = "FENCE"
	currentTargetId = nil
	prompt.Visible = true
	highlight.Adornee = fence
	highlight.Enabled = true
	highlight.OutlineColor = C.Green

	local name = fence:GetAttribute("DisplayName")
	promptName.Text = if typeof(name) == "string" and name ~= "" then name else fence.Name
	promptName.TextColor3 = C.Green
	promptStroke.Color = C.Green

	local _, fee, net = Config.GetSellPayout(wallet.Unsold)
	promptInfo.Text = ("%d CRY UNVERKAUFT   //   GEBUEHR %d   //   %.0fm"):format(wallet.Unsold, fee, distance)

	if wallet.Unsold < Config.Sell.MinAmount then
		promptAction.Text = "NICHTS ZU VERKAUFEN"
		promptAction.TextColor3 = C.TextDim
	else
		promptAction.Text = ("[E]  VERKAUFEN  ->  +%d BANK,  TRACE -%d"):format(net, Config.Sell.TraceRelief)
		promptAction.TextColor3 = C.Green
	end
end

local function showHackPrompt(target: BasePart, distance: number, id: string)
	currentKind = "HACK"
	currentTargetId = id
	prompt.Visible = true
	highlight.Adornee = target
	highlight.Enabled = true

	local name = target:GetAttribute("DisplayName")
	promptName.Text = if typeof(name) == "string" and name ~= "" then name else target.Name
	promptName.TextColor3 = C.Cyan

	local difficulty = target:GetAttribute("Difficulty")
	local reward = target:GetAttribute("Reward")
	local diffNum = if typeof(difficulty) == "number" then difficulty else 1
	local rewardNum = if typeof(reward) == "number" and reward >= 0 then reward else Config.GetReward(diffNum)

	promptInfo.Text = ("SCHWIERIGKEIT %d/10   //   %d CRY   //   %.0fm"):format(diffNum, rewardNum, distance)

	local offline = target:GetAttribute("Offline") == true
	local cd = cooldownLeft(id)

	if trace.Locked then
		promptAction.Text = ("AUFGEFLOGEN // %ds RUHE"):format(math.ceil(math.max(0, trace.LockUntil - os.clock())))
		promptAction.TextColor3 = C.Magenta
		highlight.OutlineColor = C.Magenta
		promptStroke.Color = C.Magenta
	elseif offline then
		promptAction.Text = "ZIEL BEREITS OFFLINE"
		promptAction.TextColor3 = C.TextDim
		highlight.OutlineColor = C.Line
		promptStroke.Color = C.Line
	elseif cd > 0 then
		promptAction.Text = ("GESPERRT // %ds"):format(math.ceil(cd))
		promptAction.TextColor3 = C.Amber
		highlight.OutlineColor = C.Amber
		promptStroke.Color = C.Amber
	else
		promptAction.Text = "[E]  BREACH"
		promptAction.TextColor3 = C.Text
		highlight.OutlineColor = C.Cyan
		promptStroke.Color = C.CyanDim
	end
end

-- Sucht das naechste bedienbare Objekt. Hehler und Hack-Ziel konkurrieren:
-- was naeher dran ist, gewinnt den Prompt. Deshalb gibt es nur EINE Taste.
local function scan()
	if hackOpen then
		hidePrompt()
		return
	end

	local position = Geometry.AlivePosition(player)
	if not position then
		hidePrompt()
		return
	end

	local hackRange = Config.GetRange(rig.NetCard)
	local bestHack: BasePart? = nil
	local bestHackDistance = math.huge

	for _, inst in CollectionService:GetTagged(Config.HackableTag) do
		if inst:IsA("BasePart") and inst:IsDescendantOf(workspace) then
			local d = Geometry.SurfaceDistance(inst, position)
			if d <= hackRange and d < bestHackDistance then
				bestHack, bestHackDistance = inst, d
			end
		end
	end

	local bestFence: BasePart? = nil
	local bestFenceDistance = math.huge

	for _, inst in CollectionService:GetTagged(Config.FenceTag) do
		if inst:IsA("BasePart") and inst:IsDescendantOf(workspace) then
			local d = Geometry.SurfaceDistance(inst, position)
			if d <= Config.Sell.Range and d < bestFenceDistance then
				bestFence, bestFenceDistance = inst, d
			end
		end
	end

	if bestFence and bestFenceDistance <= bestHackDistance then
		showFencePrompt(bestFence, bestFenceDistance)
		return
	end

	if bestHack then
		local id = bestHack:GetAttribute("TargetId")
		if typeof(id) ~= "string" then
			hidePrompt() -- Server hat den Part noch nicht registriert
			return
		end
		showHackPrompt(bestHack, bestHackDistance, id)
		return
	end

	hidePrompt()
end

--==========================================================================
-- Eingabe
--==========================================================================

local function activate()
	if hackOpen then
		return
	end
	if currentKind == "FENCE" then
		Remotes.SellRequest:FireServer({})
	elseif currentKind == "HACK" and currentTargetId then
		Remotes.HackRequestStart:FireServer({ TargetId = currentTargetId })
	end
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	if input.KeyCode == Enum.KeyCode.E then
		activate()
	end
end)

prompt.Activated:Connect(activate) -- Touch/Klick

--==========================================================================
-- Server-Meldungen
--==========================================================================

Remotes.EconomySync.OnClientEvent:Connect(function(snapshot: any)
	if typeof(snapshot) ~= "table" then
		return
	end
	wallet.Banked = snapshot.Banked or 0
	wallet.Unsold = snapshot.Unsold or 0
	wallet.Tier = snapshot.Tier or 1
	if typeof(snapshot.Rig) == "table" then
		rig = snapshot.Rig
	end
	-- Der Server schickt Restsekunden, keine Zeitstempel - nur so stimmt die
	-- Anzeige auch, wenn die Uhr des Clients anders geht.
	if typeof(snapshot.Cooldowns) == "table" then
		for id, seconds in snapshot.Cooldowns do
			if typeof(id) == "string" and typeof(seconds) == "number" and seconds > 0 then
				cooldownUntil[id] = os.clock() + seconds
			end
		end
	end
	refreshWallet()
end)

Remotes.TraceSync.OnClientEvent:Connect(function(data: any)
	if typeof(data) ~= "table" then
		return
	end
	trace.Value = tonumber(data.Trace) or trace.Value
	trace.Max = tonumber(data.Max) or trace.Max
	trace.Locked = data.Locked == true
	trace.LockUntil = os.clock() + (tonumber(data.LockSeconds) or 0)

	if typeof(data.Bust) == "table" then
		playBust(math.floor(tonumber(data.Bust.Lost) or 0))
	end

	refreshTrace()
end)

Remotes.SellResult.OnClientEvent:Connect(function(data: any)
	if typeof(data) ~= "table" then
		return
	end
	if data.Ok then
		toast(
			("VERKAUFT   %d CRY  -  %d GEBUEHR  =  +%d BANK   //   TRACE -%d"):format(
				data.Gross or 0,
				data.Fee or 0,
				data.Net or 0,
				data.Relief or 0
			),
			C.Green
		)
		return
	end

	if data.Reason == "RANGE" then
		toast(("Zu weit vom Hehler weg - du bist %d Studs entfernt, erlaubt sind %d"):format(
			math.floor(tonumber(data.Distance) or 0),
			math.floor(tonumber(data.Range) or Config.Sell.Range)
		), C.Amber)
		return
	end

	local reasons: { [string]: string } = {
		EMPTY = "Du hast nichts Unverkauftes dabei",
		NO_FENCE = "Kein Hehler in der Naehe",
		LOADING = "Profil laedt noch - gleich nochmal",
	}
	toast(reasons[data.Reason] or "Verkauf abgelehnt", C.Amber)
end)

Remotes.HackSessionStarted.OnClientEvent:Connect(function()
	hackOpen = true
	hidePrompt()
end)

Remotes.HackResolved.OnClientEvent:Connect(function(data: any)
	hackOpen = false
	if typeof(data) ~= "table" then
		return
	end

	if typeof(data.TargetId) == "string" and typeof(data.Cooldown) == "number" and data.Cooldown > 0 then
		cooldownUntil[data.TargetId] = os.clock() + data.Cooldown
	end

	if data.Success then
		toast(("BREACH ERFOLGREICH   +%d CRY   TRACE +%.0f"):format(data.Reward or 0, data.TraceDelta or 0), C.Cyan)
	else
		local reasons: { [string]: string } = {
			TIMEOUT = "ZEIT ABGELAUFEN",
			NO_ATTEMPTS = "RIG UEBERLASTET - KEINE VERSUCHE MEHR",
			OUT_OF_RANGE = "VERBINDUNG ABGERISSEN - ZU WEIT WEG",
			ABORTED = "ABGEBROCHEN",
			TARGET_GONE = "ZIEL VERSCHWUNDEN",
			BUSTED = "AUFGEFLOGEN - VERBINDUNG GEKAPPT",
		}
		local text = reasons[data.Reason] or "BREACH FEHLGESCHLAGEN"
		toast(("%s   TRACE +%.0f"):format(text, data.TraceDelta or 0), C.Magenta)
	end
end)

Remotes.HackDenied.OnClientEvent:Connect(function(data: any)
	if typeof(data) ~= "table" then
		return
	end
	local seconds = tonumber(data.Seconds) or 0

	-- Jede Ablehnung nennt Grund UND Zahl. Ein Spieler, der nicht versteht,
	-- warum sein Klick nichts tut, haelt das Spiel fuer kaputt und geht.
	if data.Reason == "COOLDOWN" then
		if typeof(data.TargetId) == "string" then
			cooldownUntil[data.TargetId] = os.clock() + seconds
		end
		toast(("Ziel noch heiss - %d s"):format(math.ceil(seconds)), C.Amber)
	elseif data.Reason == "LEVEL" then
		if typeof(data.Weakest) == "string" then
			toast(("Braucht Rig-Tier %d - dein schwaechstes Bauteil ist %s %d"):format(
				seconds,
				data.Weakest,
				math.floor(tonumber(data.WeakestLevel) or 1)
			), C.Amber)
		else
			toast(("Braucht Rig-Tier %d"):format(seconds), C.Amber)
		end
	elseif data.Reason == "RANGE" then
		if seconds > 0 then
			toast(("Zu weit weg - %d Studs zu viel. NetCard aufruesten?"):format(math.ceil(seconds)), C.Amber)
		else
			toast("Zu weit weg - naeher ran oder NetCard aufruesten", C.Amber)
		end
	elseif data.Reason == "OFFLINE" then
		toast("Laeuft bereits offline - warte, bis es wieder hochfaehrt", C.TextDim)
	elseif data.Reason == "BUSTED" then
		toast(("Aufgeflogen - noch %d s Ruhe, bevor du wieder ran kannst"):format(math.ceil(seconds)), C.Magenta)
	elseif data.Reason == "LOADING" then
		toast("Profil laedt noch - gleich nochmal", C.TextDim)
	elseif data.Reason == "UNKNOWN_TARGET" then
		toast("Dieses Ziel gibt es nicht mehr", C.TextDim)
	else
		toast("Zugriff verweigert - der Server hat abgelehnt", C.Magenta)
	end
end)

--==========================================================================
-- Schleife
--==========================================================================

refreshWallet()
refreshTrace()

local scanAccumulator = 0
RunService.RenderStepped:Connect(function(dt)
	scanAccumulator += dt
	if scanAccumulator >= 0.15 then
		scanAccumulator = 0
		scan()
		refreshTrace()
	end

	-- Puls ab WarnAt. Je heisser, desto schneller und roter - das ist der
	-- eigentliche Spannungsmesser des Spiels.
	if trace.Value >= Config.Trace.WarnAt then
		local critical = trace.Value >= Config.Trace.CriticalAt
		local speed = if critical then 11 else 6
		local pulse = 0.5 + 0.5 * math.sin(os.clock() * speed)
		local hot = if critical then C.Magenta else C.Amber
		traceFill.BackgroundColor3 = hot:Lerp(C.Text, pulse * 0.35)
		traceStroke.Color = hot
		traceStroke.Thickness = 1 + pulse
		traceTitle.TextColor3 = hot
	else
		traceFill.BackgroundColor3 = C.Cyan
		traceStroke.Color = C.Line
		traceStroke.Thickness = 1
		traceTitle.TextColor3 = C.TextDim
	end
end)

UITheme.Scanlines(walletPanel, 4)
