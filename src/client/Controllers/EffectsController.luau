--!strict
-- EffectsController: zentrales "Juice"-Modul des Clients.
--
-- Bietet anderen Controllern Sounds, fliegende Energie-Zahlen, Partikel-
-- Bursts am eigenen Planeten und Screen-Shake an. Alle Sounds hängen an
-- einer SoundGroup in SoundService; die Gesamtlautstärke kommt zentral aus
-- GameConfig.SOUND_MASTER_VOLUME. Es werden ausschließlich Engine-eigene
-- rbxasset://-Sounddateien verwendet (immer verfügbar, keine Moderation).
--
-- Startet als ERSTER Controller, alle Funktionen sind aber auch vor init()
-- gefahrlos aufrufbar (sie tun dann einfach nichts).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ConfigFolder = Shared:WaitForChild("Config")

local GameConfig = require(ConfigFolder:WaitForChild("GameConfig") :: ModuleScript) :: {
	SOUND_MASTER_VOLUME: number,
}

local ACCENT_COLOR = Color3.fromRGB(214, 160, 72)

type SoundDef = { file: string, pitch: number, volume: number }

-- Nur Engine-Sounddateien (rbxasset://), damit nie etwas fehlt.
local SOUND_DEFS: { [string]: SoundDef } = {
	collect = { file = "rbxasset://sounds/electronicpingshort.wav", pitch = 1.15, volume = 0.6 },
	pop = { file = "rbxasset://sounds/snap.mp3", pitch = 1.0, volume = 0.7 },
	tick = { file = "rbxasset://sounds/electronicpingshort.wav", pitch = 1.7, volume = 0.18 },
	reveal = { file = "rbxasset://sounds/swoosh.wav", pitch = 1.0, volume = 0.8 },
	fanfare = { file = "rbxasset://sounds/impact_water.mp3", pitch = 1.35, volume = 0.8 },
}

local EffectsController = {}

local localPlayer = Players.LocalPlayer

local soundGroup: SoundGroup? = nil
local effectsGui: ScreenGui? = nil
local shakeCounter = 0

-- Spielt einen benannten Sound (optional mit abweichender Tonhöhe).
function EffectsController.playSound(name: string, pitchOverride: number?)
	local def = SOUND_DEFS[name]
	local group = soundGroup
	if def == nil or group == nil then
		return
	end

	local sound = Instance.new("Sound")
	sound.SoundId = def.file
	sound.Volume = def.volume
	sound.PlaybackSpeed = pitchOverride or def.pitch
	sound.SoundGroup = group
	sound.Parent = SoundService
	sound:Play()
	task.delay(4, function()
		sound:Destroy()
	end)
end

-- "+N ⚡" fliegt vom Sammel-Button hoch zum Energie-Zähler.
function EffectsController.flyEnergyToCounter(amount: number)
	local gui = effectsGui
	if gui == nil then
		return
	end

	local playerGui = localPlayer:FindFirstChild("PlayerGui")
	if playerGui == nil then
		return
	end
	local mainGui = playerGui:FindFirstChild("PlanetForgeUI")
	if mainGui == nil then
		return
	end
	local buttonBar = mainGui:FindFirstChild("ButtonBar")
	local header = mainGui:FindFirstChild("Header")
	local sourceButton = if buttonBar ~= nil then buttonBar:FindFirstChild("CollectEnergy") else nil
	local targetLabel = if header ~= nil then header:FindFirstChild("Energy") else nil
	if sourceButton == nil or not sourceButton:IsA("GuiObject") or targetLabel == nil or not targetLabel:IsA("GuiObject") then
		return
	end

	local source = (sourceButton :: GuiObject).AbsolutePosition
		+ (sourceButton :: GuiObject).AbsoluteSize / 2
	local target = (targetLabel :: GuiObject).AbsolutePosition
		+ (targetLabel :: GuiObject).AbsoluteSize / 2

	local label = Instance.new("TextLabel")
	label.Name = "FlyingEnergy"
	label.BackgroundTransparency = 1
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.new(0, source.X, 0, source.Y)
	label.Size = UDim2.new(0, 120, 0, 24)
	label.Font = Enum.Font.GothamBold
	label.TextSize = 20
	label.TextColor3 = ACCENT_COLOR
	label.TextStrokeTransparency = 0.5
	label.Text = `+{amount} ⚡`
	label.Parent = gui

	local flight = TweenService:Create(
		label,
		TweenInfo.new(0.65, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ Position = UDim2.new(0, target.X, 0, target.Y), TextSize = 12 }
	)
	flight:Play()
	flight.Completed:Once(function()
		local fade = TweenService:Create(label, TweenInfo.new(0.15), { TextTransparency = 1, TextStrokeTransparency = 1 })
		fade:Play()
		fade.Completed:Once(function()
			label:Destroy()
		end)
	end)
end

-- Kurzer Partikel-Burst am eigenen Planetenkern (rein lokal).
function EffectsController.burstAtOwnPlanet(color: Color3?)
	local plots = Workspace:FindFirstChild("PlanetPlots")
	local plot = if plots ~= nil then plots:FindFirstChild(`Plot_{localPlayer.UserId}`) else nil
	local core = if plot ~= nil then plot:FindFirstChild("Core") else nil
	if core == nil or not core:IsA("BasePart") then
		return
	end

	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "LocalBurst"
	local burstColor = color or ACCENT_COLOR
	emitter.Color = ColorSequence.new(burstColor)
	emitter.LightEmission = 0.7
	emitter.Rate = 0
	emitter.Lifetime = NumberRange.new(0.4, 0.9)
	emitter.Speed = NumberRange.new(8, 14)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Size = NumberSequence.new(0.7)
	emitter.Parent = core
	emitter:Emit(14)
	task.delay(1.5, function()
		emitter:Destroy()
	end)
end

-- Kurzer, abklingender Screen-Shake (z. B. bei legendären Funden).
function EffectsController.screenShake(intensity: number?)
	local camera = Workspace.CurrentCamera
	if camera == nil then
		return
	end

	local strength = intensity or 1
	local duration = 0.35
	shakeCounter += 1
	local bindName = `PlanetForgeShake_{shakeCounter}`
	local rng = Random.new()
	local startedAt = os.clock()

	RunService:BindToRenderStep(bindName, Enum.RenderPriority.Camera.Value + 1, function()
		local elapsed = os.clock() - startedAt
		if elapsed >= duration then
			RunService:UnbindFromRenderStep(bindName)
			return
		end
		local falloff = 1 - elapsed / duration
		local amplitude = 0.35 * strength * falloff
		local offset = CFrame.new(
			rng:NextNumber(-amplitude, amplitude),
			rng:NextNumber(-amplitude, amplitude),
			0
		) * CFrame.Angles(0, 0, math.rad(rng:NextNumber(-1, 1) * strength * falloff))
		camera.CFrame = camera.CFrame * offset
	end)
end

-- Einheitliches Button-Feedback: sanftes Hover- (1.05) und Press-Scaling (0.95).
function EffectsController.addButtonFX(button: GuiButton)
	local scale = Instance.new("UIScale")
	scale.Name = "FXScale"
	scale.Parent = button

	local function tweenTo(value: number, seconds: number)
		TweenService:Create(scale, TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Scale = value,
		}):Play()
	end

	button.MouseEnter:Connect(function()
		tweenTo(1.05, 0.12)
	end)
	button.MouseLeave:Connect(function()
		tweenTo(1, 0.12)
	end)
	button.MouseButton1Down:Connect(function()
		tweenTo(0.95, 0.08)
	end)
	button.MouseButton1Up:Connect(function()
		tweenTo(1.05, 0.1)
	end)
end

-- Dezenter vertikaler Verlauf für Panels/Buttons (heller oben).
function EffectsController.addGradient(guiObject: GuiObject)
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(200, 200, 210))
	gradient.Parent = guiObject
end

-- Lokales Geister-Objekt fliegt vom Sammelpunkt zum Spieler (das echte
-- Objekt hat der Server bereits entfernt).
function EffectsController.flyPartToCharacter(position: Vector3, color: Color3?)
	local character = localPlayer.Character
	local root = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
	if root == nil or not root:IsA("BasePart") then
		return
	end

	local ghost = Instance.new("Part")
	ghost.Shape = Enum.PartType.Ball
	ghost.Size = Vector3.new(1, 1, 1)
	ghost.Color = color or ACCENT_COLOR
	ghost.Material = Enum.Material.Neon
	ghost.Anchored = true
	ghost.CanCollide = false
	ghost.CanQuery = false
	ghost.CFrame = CFrame.new(position)
	ghost.Parent = Workspace

	local tween = TweenService:Create(
		ghost,
		TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ CFrame = (root :: BasePart).CFrame, Size = Vector3.new(0.3, 0.3, 0.3), Transparency = 0.4 }
	)
	tween:Play()
	tween.Completed:Once(function()
		ghost:Destroy()
	end)
end

-- Münz-Regen über dem Spieler (Verkaufs-Moment).
function EffectsController.coinRain(coinCount: number?)
	local character = localPlayer.Character
	local root = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
	if root == nil or not root:IsA("BasePart") then
		return
	end
	local origin = (root :: BasePart).Position

	local rng = Random.new()
	for _ = 1, math.clamp(coinCount or 10, 4, 16) do
		local coin = Instance.new("Part")
		coin.Shape = Enum.PartType.Cylinder
		coin.Size = Vector3.new(0.15, 0.9, 0.9)
		coin.Color = Color3.fromRGB(255, 210, 90)
		coin.Material = Enum.Material.Metal
		coin.Anchored = true
		coin.CanCollide = false
		coin.CanQuery = false
		local offset = Vector3.new(rng:NextNumber(-4, 4), rng:NextNumber(5, 8), rng:NextNumber(-4, 4))
		coin.CFrame = CFrame.new(origin + offset) * CFrame.Angles(0, 0, math.rad(90))
		coin.Parent = Workspace

		local fall = TweenService:Create(
			coin,
			TweenInfo.new(rng:NextNumber(0.5, 0.9), Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{
				CFrame = CFrame.new(origin + Vector3.new(offset.X, -1, offset.Z))
					* CFrame.Angles(rng:NextNumber() * 3, rng:NextNumber() * 3, math.rad(90)),
				Transparency = 0.5,
			}
		)
		fall:Play()
		fall.Completed:Once(function()
			coin:Destroy()
		end)
	end
end

-- Aufsteigender Zähler am Energie-HUD ("+123 ⚡" zählt sichtbar hoch).
function EffectsController.countUpAtCounter(amount: number)
	local gui = effectsGui
	if gui == nil or amount <= 0 then
		return
	end

	local playerGui = localPlayer:FindFirstChild("PlayerGui")
	local mainGui = if playerGui ~= nil then playerGui:FindFirstChild("PlanetForgeUI") else nil
	local header = if mainGui ~= nil then mainGui:FindFirstChild("Header") else nil
	local target = if header ~= nil then header:FindFirstChild("Energy") else nil
	if target == nil or not target:IsA("GuiObject") then
		return
	end
	local anchor = (target :: GuiObject).AbsolutePosition + (target :: GuiObject).AbsoluteSize / 2

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.new(0, anchor.X, 0, anchor.Y + 26)
	label.Size = UDim2.new(0, 200, 0, 24)
	label.Font = Enum.Font.GothamBold
	label.TextSize = 18
	label.TextColor3 = ACCENT_COLOR
	label.TextStrokeTransparency = 0.5
	label.Text = "+0 ⚡"
	label.Parent = gui

	task.spawn(function()
		local duration = 0.8
		local startedAt = os.clock()
		while true do
			local alpha = math.clamp((os.clock() - startedAt) / duration, 0, 1)
			label.Text = `+{math.floor(amount * alpha)} ⚡`
			if alpha >= 1 then
				break
			end
			task.wait(0.03)
		end
		local fade = TweenService:Create(label, TweenInfo.new(0.4), {
			TextTransparency = 1,
			TextStrokeTransparency = 1,
			Position = label.Position - UDim2.fromOffset(0, 18),
		})
		fade:Play()
		fade.Completed:Once(function()
			label:Destroy()
		end)
	end)
end

-- Kurzer Kamera-Schwenk zu einem Welt-Part (z. B. neu freigelegte Zone).
local cameraPanActive = false
function EffectsController.panCameraTo(part: BasePart, holdSeconds: number?)
	if cameraPanActive then
		return
	end
	local camera = Workspace.CurrentCamera
	if camera == nil then
		return
	end
	cameraPanActive = true

	task.spawn(function()
		local originalType = camera.CameraType
		camera.CameraType = Enum.CameraType.Scriptable

		local lookFrom = part.Position + Vector3.new(0, 22, 26)
		local tween = TweenService:Create(
			camera,
			TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ CFrame = CFrame.lookAt(lookFrom, part.Position) }
		)
		tween:Play()
		tween.Completed:Wait()
		task.wait(holdSeconds or 1.2)

		camera.CameraType = originalType
		cameraPanActive = false
	end)
end

function EffectsController.init()
	-- Zentrale SoundGroup mit Lautstärke aus GameConfig.
	local group = Instance.new("SoundGroup")
	group.Name = "PlanetForgeSounds"
	group.Volume = math.clamp(GameConfig.SOUND_MASTER_VOLUME, 0, 1)
	group.Parent = SoundService
	soundGroup = group

	-- Eigene Ebene für fliegende Zahlen und ähnliche Overlay-Effekte.
	local playerGui = localPlayer:WaitForChild("PlayerGui")
	local gui = Instance.new("ScreenGui")
	gui.Name = "PlanetForgeEffects"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 30
	gui.Parent = playerGui
	effectsGui = gui
end

return EffectsController
