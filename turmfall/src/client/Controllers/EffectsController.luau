--!strict
-- EffectsController: Turm-Schwank-Feedback und Finale-Visuals (M4).
--
-- Der Server rechnet den Stabilitäts-Score (0..100) aus der aggregierten
-- Teil-Geschwindigkeit; dieser Controller macht ihn FÜHLBAR:
--   - Kamerawackeln proportional zur Instabilität (Humanoid.CameraOffset)
--   - Knarz-Sounds, wenn der Turm zu arbeiten beginnt
--   - Stabilitäts-Balken im HUD
-- Außerdem die "Letzter Stein"-Zeitlupe: rein clientseitige Optik
-- (Farbkorrektur + FOV) - die Physik läuft überall normal weiter.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Network = require(Shared:WaitForChild("Network") :: ModuleScript) :: {
	getEvent: (name: string) -> RemoteEvent,
	getFunction: (name: string) -> RemoteFunction,
}
local GameConfig = require(Shared:WaitForChild("Config"):WaitForChild("GameConfig") :: ModuleScript) :: any

local SHAKE_START_SCORE = 60 -- ab hier beginnt das Wackeln
local CREAK_COOLDOWN_SECONDS = 2.5

local EffectsController = {}

local stabilityScore = 100
local lastCreakAt = 0
local rng = Random.new()

local stabilityBar: Frame? = nil
local stabilityFill: Frame? = nil

local function buildStabilityBar()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "TurmfallStabilitaet"
	screenGui.ResetOnSpawn = false
	screenGui.Parent = playerGui

	local bar = Instance.new("Frame")
	bar.Name = "StabilityBar"
	bar.AnchorPoint = Vector2.new(0.5, 0)
	bar.Position = UDim2.new(0.5, 0, 0, 72)
	bar.Size = UDim2.new(0, 220, 0, 10)
	bar.BackgroundColor3 = Color3.fromRGB(28, 30, 40)
	bar.BackgroundTransparency = 0.2
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 5)
	corner.Parent = bar
	bar.Parent = screenGui

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.new(1, 0, 1, 0)
	fill.BackgroundColor3 = Color3.fromRGB(90, 190, 120)
	fill.BorderSizePixel = 0
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, 5)
	fillCorner.Parent = fill
	fill.Parent = bar

	stabilityBar = bar
	stabilityFill = fill
end

local function updateStabilityBar()
	local fill = stabilityFill
	if fill == nil then
		return
	end
	fill.Size = UDim2.new(stabilityScore / 100, 0, 1, 0)
	fill.BackgroundColor3 = if stabilityScore >= 60
		then Color3.fromRGB(90, 190, 120)
		elseif stabilityScore >= 30 then Color3.fromRGB(235, 186, 60)
		else Color3.fromRGB(220, 80, 70)
end

local function playCreak(intensity: number)
	local sound = Instance.new("Sound")
	sound.SoundId = "rbxasset://sounds/snap.mp3"
	sound.Volume = 0.25 + intensity * 0.4
	sound.PlaybackSpeed = 0.35 + rng:NextNumber(0, 0.15)
	sound.Parent = Workspace
	sound:Play()
	task.delay(2, function()
		sound:Destroy()
	end)
end

-- Finale-Zeitlupe: Farbkorrektur + FOV für die letzten Sekunden (nur Optik).
local function playFinaleVisuals()
	local color = Instance.new("ColorCorrectionEffect")
	color.Name = "TurmfallFinale"
	color.Saturation = -0.35
	color.TintColor = Color3.fromRGB(210, 220, 255)
	color.Parent = Lighting

	local camera = Workspace.CurrentCamera
	if camera ~= nil then
		TweenService:Create(camera, TweenInfo.new(1), { FieldOfView = 60 }):Play()
	end

	task.delay(GameConfig.FINALE_SECONDS, function()
		color:Destroy()
		if camera ~= nil then
			TweenService:Create(camera, TweenInfo.new(1), { FieldOfView = 70 }):Play()
		end
	end)
end

function EffectsController.init()
	buildStabilityBar()

	Network.getEvent("StabilityChanged").OnClientEvent:Connect(function(score: any)
		if typeof(score) ~= "number" then
			return
		end
		stabilityScore = math.clamp(score, 0, 100)
		updateStabilityBar()

		-- Knarzen, wenn der Turm arbeitet (gedrosselt, Intensität skaliert).
		if stabilityScore < SHAKE_START_SCORE and os.clock() - lastCreakAt > CREAK_COOLDOWN_SECONDS then
			lastCreakAt = os.clock()
			playCreak((SHAKE_START_SCORE - stabilityScore) / SHAKE_START_SCORE)
		end
	end)

	Network.getEvent("FinaleStarted").OnClientEvent:Connect(playFinaleVisuals)

	-- Kamerawackeln proportional zur Instabilität.
	RunService.RenderStepped:Connect(function()
		local character = Players.LocalPlayer.Character
		local humanoid = if character ~= nil then character:FindFirstChildOfClass("Humanoid") else nil
		if humanoid == nil then
			return
		end
		if stabilityScore >= SHAKE_START_SCORE then
			humanoid.CameraOffset = Vector3.zero
			return
		end
		local amplitude = ((SHAKE_START_SCORE - stabilityScore) / SHAKE_START_SCORE) * 0.35
		humanoid.CameraOffset = Vector3.new(
			rng:NextNumber(-amplitude, amplitude),
			rng:NextNumber(-amplitude, amplitude),
			0
		)
	end)
end

return EffectsController
