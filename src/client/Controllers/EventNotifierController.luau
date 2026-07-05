--!strict
-- EventNotifierController: zeigt globale Live-Events als Banner oben Mitte an.
-- Pro Event ein dezenter Farbakzent, Countdown "endet in M:SS" (jede Sekunde
-- aktualisiert). Während "schwarzes_loch" wird zusätzlich ein
-- ColorCorrectionEffect (Saturation -0.5) in Lighting gesetzt und danach
-- sauber wieder entfernt.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ConfigFolder = Shared:WaitForChild("Config")
local ControllersFolder = script.Parent :: Instance

local Remotes = require(Shared:WaitForChild("Remotes") :: ModuleScript) :: {
	getEvent: (name: string) -> RemoteEvent,
	getFunction: (name: string) -> RemoteFunction,
}
local EventConfig = require(ConfigFolder:WaitForChild("EventConfig") :: ModuleScript) :: {
	Events: { [string]: { id: string, displayName: string, announceText: string } },
}
local UIController = require(ControllersFolder:WaitForChild("UIController") :: ModuleScript) :: {
	showToast: (message: string, kind: string) -> (),
}

-- Farbschema (identisch zum UIController).
local PANEL_COLOR = Color3.fromRGB(30, 32, 44)
local TEXT_COLOR = Color3.fromRGB(235, 238, 245)
local SUBTEXT_COLOR = Color3.fromRGB(158, 164, 186)

-- Dezenter Farbakzent pro Event.
local ACCENT_COLORS: { [string]: Color3 } = {
	meteoritenschauer = Color3.fromRGB(255, 150, 70),
	goldener_regen = Color3.fromRGB(255, 210, 90),
	kreaturen_spawn = Color3.fromRGB(120, 220, 130),
	alien_invasion = Color3.fromRGB(170, 110, 255),
	schwarzes_loch = Color3.fromRGB(140, 120, 255),
}
local DEFAULT_ACCENT = Color3.fromRGB(66, 133, 244)

local BLACK_HOLE_EVENT_ID = "schwarzes_loch"
local FADE_SECONDS = 0.4

local EventNotifierController = {}

-- Restsekunden -> "M:SS" (z. B. 95 -> "1:35").
local function formatCountdown(seconds: number): string
	local clamped = math.max(0, math.floor(seconds))
	local minutes = clamped // 60
	local remainder = clamped % 60
	return `{minutes}:{string.format("%02d", remainder)}`
end

local function addCorner(parent: Instance, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = parent
end

local function createLabel(parent: Instance, name: string, text: string): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamMedium
	label.TextColor3 = TEXT_COLOR
	label.TextSize = 14
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Text = text
	label.Parent = parent
	return label
end

function EventNotifierController.init()
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "PlanetForgeEventUI"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.DisplayOrder = 8

	-- Banner oben Mitte (unterhalb der Kopfleiste des UIControllers).
	local banner = Instance.new("CanvasGroup")
	banner.Name = "EventBanner"
	banner.AnchorPoint = Vector2.new(0.5, 0)
	banner.Position = UDim2.new(0.5, 0, 0, 60)
	banner.Size = UDim2.new(0, 480, 0, 78)
	banner.BackgroundColor3 = PANEL_COLOR
	banner.Visible = false
	addCorner(banner, 12)

	local stroke = Instance.new("UIStroke")
	stroke.Color = DEFAULT_ACCENT
	stroke.Thickness = 2
	stroke.Parent = banner

	local titleLabel = createLabel(banner, "Title", "")
	titleLabel.Position = UDim2.new(0, 16, 0, 10)
	titleLabel.Size = UDim2.new(1, -180, 0, 22)
	titleLabel.Font = Enum.Font.GothamBold
	titleLabel.TextSize = 18

	local countdownLabel = createLabel(banner, "Countdown", "")
	countdownLabel.AnchorPoint = Vector2.new(1, 0)
	countdownLabel.Position = UDim2.new(1, -16, 0, 12)
	countdownLabel.Size = UDim2.new(0, 150, 0, 20)
	countdownLabel.TextSize = 14
	countdownLabel.TextXAlignment = Enum.TextXAlignment.Right

	local announceLabel = createLabel(banner, "Announce", "")
	announceLabel.Position = UDim2.new(0, 16, 0, 36)
	announceLabel.Size = UDim2.new(1, -32, 0, 34)
	announceLabel.TextSize = 13
	announceLabel.TextColor3 = SUBTEXT_COLOR
	announceLabel.TextWrapped = true
	announceLabel.TextYAlignment = Enum.TextYAlignment.Top

	banner.Parent = screenGui
	screenGui.Parent = playerGui

	-- Generation entwertet alte Countdown-Schleifen, wenn ein neues Event
	-- startet oder das aktuelle endet.
	local generation = 0
	local activeTween: Tween? = nil
	local colorCorrection: ColorCorrectionEffect? = nil

	local function cancelActiveTween()
		local tween = activeTween
		if tween ~= nil then
			tween:Cancel()
			activeTween = nil
		end
	end

	-- Lighting-Effekt für das Schwarze Loch setzen bzw. sauber entfernen.
	local function setBlackHoleEffect(enabled: boolean)
		if enabled then
			if colorCorrection == nil then
				local effect = Instance.new("ColorCorrectionEffect")
				effect.Name = "PlanetForgeSchwarzesLoch"
				effect.Saturation = -0.5
				effect.Parent = Lighting
				colorCorrection = effect
			end
		else
			local effect = colorCorrection
			if effect ~= nil then
				effect:Destroy()
				colorCorrection = nil
			end
		end
	end

	local function hideBanner()
		if not banner.Visible then
			return
		end
		cancelActiveTween()
		local tween = TweenService:Create(banner, TweenInfo.new(FADE_SECONDS), { GroupTransparency = 1 })
		activeTween = tween
		tween:Play()
		tween.Completed:Once(function()
			-- Nur verstecken, wenn nicht inzwischen ein neues Event läuft.
			if activeTween == tween then
				banner.Visible = false
				activeTween = nil
			end
		end)
	end

	local function onEventStarted(eventId: any, endsAt: any)
		if typeof(eventId) ~= "string" or typeof(endsAt) ~= "number" then
			return
		end
		local def = EventConfig.Events[eventId]
		if def == nil then
			warn(`[PlanetForge] Unbekanntes globales Event vom Server: {eventId}`)
			return
		end

		generation += 1
		local myGeneration = generation

		local accent = ACCENT_COLORS[eventId] or DEFAULT_ACCENT
		titleLabel.Text = def.displayName
		titleLabel.TextColor3 = accent
		announceLabel.Text = def.announceText
		stroke.Color = accent
		countdownLabel.Text = `endet in {formatCountdown(endsAt - os.time())}`

		cancelActiveTween()
		banner.GroupTransparency = 0
		banner.Visible = true

		setBlackHoleEffect(eventId == BLACK_HOLE_EVENT_ID)

		-- Countdown jede Sekunde aktualisieren; bei Ablauf selbst ausblenden
		-- (falls GlobalEventEnded z. B. durch einen Rejoin verpasst wurde).
		task.spawn(function()
			while generation == myGeneration do
				local remaining = endsAt - os.time()
				if remaining <= 0 then
					break
				end
				countdownLabel.Text = `endet in {formatCountdown(remaining)}`
				task.wait(1)
			end
			if generation == myGeneration then
				generation += 1
				hideBanner()
				setBlackHoleEffect(false)
			end
		end)
	end

	local function onEventEnded(_eventId: any)
		generation += 1
		hideBanner()
		setBlackHoleEffect(false)
		UIController.showToast("Event vorbei", "info")
	end

	Remotes.getEvent("GlobalEventStarted").OnClientEvent:Connect(onEventStarted)
	Remotes.getEvent("GlobalEventEnded").OnClientEvent:Connect(onEventEnded)
end

return EventNotifierController
