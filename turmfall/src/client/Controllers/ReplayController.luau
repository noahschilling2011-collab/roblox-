--!strict
-- ReplayController: das 5-Sekunden-Schuld-Replay nach einem Kollaps.
--
-- Der Server schickt beim Kollaps die letzten Sekunden der Kaskade aus
-- seinem Ringpuffer (Positionen bei 4 Hz) plus das Verursacher-Teil.
-- Dieser Controller baut daraus Geister-Teile, spielt die Bewegung mit
-- Interpolation ab, richtet die Kamera auf das auslösende Teil und
-- blendet den Namen des Verursachers ein. Danach wird alles aufgeräumt
-- und die Kamera zurückgegeben.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Network = require(Shared:WaitForChild("Network") :: ModuleScript) :: {
	getEvent: (name: string) -> RemoteEvent,
	getFunction: (name: string) -> RemoteFunction,
}
local PartCatalog = require(Shared:WaitForChild("Config"):WaitForChild("PartCatalog") :: ModuleScript) :: any
local GameConfig = require(Shared:WaitForChild("Config"):WaitForChild("GameConfig") :: ModuleScript) :: any

local ControllersFolder = script.Parent :: Instance
local SkinUIController = require(ControllersFolder:WaitForChild("SkinUIController") :: ModuleScript) :: {
	getEquippedCollapseEffect: () -> string?,
}

local CULPRIT_COLOR = Color3.fromRGB(255, 70, 60)
local GHOST_COLOR = Color3.fromRGB(180, 185, 200)

local ReplayController = {}

local replayRunning = false

local function vec3(v: any): Vector3?
	if typeof(v) ~= "table" or typeof(v.x) ~= "number" or typeof(v.y) ~= "number" or typeof(v.z) ~= "number" then
		return nil
	end
	return Vector3.new(v.x, v.y, v.z)
end

-- Banner "💥 KOLLAPS - Schuld: X" für die Dauer des Replays.
local function showBanner(culpritName: string?): () -> ()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "TurmfallReplay"
	screenGui.IgnoreGuiInset = true
	screenGui.DisplayOrder = 50
	screenGui.Parent = playerGui

	local banner = Instance.new("Frame")
	banner.AnchorPoint = Vector2.new(0.5, 0)
	banner.Position = UDim2.new(0.5, 0, 0, 90)
	banner.Size = UDim2.new(0, 460, 0, 74)
	banner.BackgroundColor3 = Color3.fromRGB(24, 22, 30)
	banner.BackgroundTransparency = 0.15
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = banner
	local stroke = Instance.new("UIStroke")
	stroke.Color = CULPRIT_COLOR
	stroke.Thickness = 2
	stroke.Parent = banner
	banner.Parent = screenGui

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Position = UDim2.new(0, 0, 0, 8)
	title.Size = UDim2.new(1, 0, 0, 28)
	title.Font = Enum.Font.GothamBold
	title.TextSize = 22
	title.TextColor3 = CULPRIT_COLOR
	title.Text = "💥 KOLLAPS!"
	title.Parent = banner

	local subtitle = Instance.new("TextLabel")
	subtitle.BackgroundTransparency = 1
	subtitle.Position = UDim2.new(0, 0, 0, 38)
	subtitle.Size = UDim2.new(1, 0, 0, 26)
	subtitle.Font = Enum.Font.GothamMedium
	subtitle.TextSize = 16
	subtitle.TextColor3 = Color3.fromRGB(235, 238, 245)
	subtitle.Text = if culpritName ~= nil
		then `Schuld: {culpritName}  ·  REPLAY`
		else "Kein eindeutiger Verursacher  ·  REPLAY"
	subtitle.Parent = banner

	return function()
		screenGui:Destroy()
	end
end

-- Konfetti-Kollaps (Skin-Effekt, rein clientseitig): bunter Partikel-Burst.
local function playConfetti(position: Vector3)
	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(1, 1, 1)
	anchor.Position = position
	anchor.Parent = Workspace

	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 90, 90)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(90, 200, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 220, 90)),
	})
	emitter.LightEmission = 0.8
	emitter.Rate = 0
	emitter.Lifetime = NumberRange.new(1, 2)
	emitter.Speed = NumberRange.new(10, 22)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Size = NumberSequence.new(0.5)
	emitter.Parent = anchor
	emitter:Emit(90)

	task.delay(3, function()
		anchor:Destroy()
	end)
end

-- Spielt das Replay ab (blockiert den aufrufenden Thread bis zum Ende).
-- playbackScale > 1 = Zeitlupe (Skin-Effekt, rein clientseitig).
local function playReplay(data: any, playbackScale: number)
	local samples = data.samples :: { any }
	if typeof(samples) ~= "table" or #samples < 2 then
		return -- ohne Verlauf kein Replay
	end
	local pieceInfos = if typeof(data.pieces) == "table" then data.pieces :: { [any]: any } else {}
	local culpritPieceId = data.culpritPieceId

	-- Geister-Teile bauen (einfache Blöcke in Teilgröße).
	local ghostFolder = Instance.new("Folder")
	ghostFolder.Name = "KollapsReplay"
	local ghosts: { [any]: BasePart } = {}
	for pieceId, info in pieceInfos do
		local def = PartCatalog.Parts[if typeof(info) == "table" then info.partTypeId else ""]
		local ghost = Instance.new("Part")
		ghost.Anchored = true
		ghost.CanCollide = false
		ghost.CanQuery = false
		ghost.Material = Enum.Material.Neon
		ghost.Transparency = 0.35
		ghost.Size = if def ~= nil then Vector3.new(def.size.x, def.size.y, def.size.z) else Vector3.new(2, 2, 2)
		ghost.Color = if pieceId == culpritPieceId then CULPRIT_COLOR else GHOST_COLOR
		ghost.Parent = ghostFolder
		ghosts[pieceId] = ghost
	end
	ghostFolder.Parent = Workspace

	-- Kamera übernehmen.
	local camera = Workspace.CurrentCamera
	local previousCameraType = if camera ~= nil then camera.CameraType else nil
	if camera ~= nil then
		camera.CameraType = Enum.CameraType.Scriptable
	end

	-- Zeitachse der Samples normalisieren.
	local startTime = samples[1].t
	local endTime = samples[#samples].t
	local timeline = math.max(endTime - startTime, 0.1)
	local playbackSeconds = GameConfig.REPLAY_SECONDS * playbackScale

	local clockStart = os.clock()
	while os.clock() - clockStart < playbackSeconds do
		local progress = (os.clock() - clockStart) / playbackSeconds
		local sampleTime = startTime + progress * timeline

		-- Sample-Paar um sampleTime finden und interpolieren.
		local beforeSample = samples[1]
		local afterSample = samples[#samples]
		for index = 1, #samples - 1 do
			if samples[index].t <= sampleTime and samples[index + 1].t >= sampleTime then
				beforeSample = samples[index]
				afterSample = samples[index + 1]
				break
			end
		end
		local span = math.max(afterSample.t - beforeSample.t, 0.001)
		local alpha = math.clamp((sampleTime - beforeSample.t) / span, 0, 1)

		local focusPosition: Vector3? = nil
		for pieceId, ghost in ghosts do
			local fromPosition = vec3(beforeSample.positions[pieceId])
			local toPosition = vec3(afterSample.positions[pieceId])
			local position = if fromPosition ~= nil and toPosition ~= nil
				then fromPosition:Lerp(toPosition, alpha)
				else (toPosition or fromPosition)
			if position ~= nil then
				ghost.Position = position
				if pieceId == culpritPieceId then
					focusPosition = position
				end
				if focusPosition == nil then
					focusPosition = position
				end
			end
		end

		-- Kamera: Blick auf das auslösende Teil (bzw. die Kaskade).
		if camera ~= nil and focusPosition ~= nil then
			local target = focusPosition :: Vector3
			camera.CFrame = CFrame.lookAt(target + Vector3.new(18, 12, 18), target)
		end

		RunService.RenderStepped:Wait()
	end

	-- Aufräumen und Kamera zurückgeben.
	ghostFolder:Destroy()
	if camera ~= nil then
		camera.CameraType = previousCameraType or Enum.CameraType.Custom
		local character = Players.LocalPlayer.Character
		local humanoid = if character ~= nil then character:FindFirstChildOfClass("Humanoid") else nil
		if humanoid ~= nil then
			camera.CameraSubject = humanoid
		end
	end
end

function ReplayController.init()
	Network.getEvent("CollapseHappened").OnClientEvent:Connect(function(data: any)
		if typeof(data) ~= "table" or replayRunning then
			return
		end
		replayRunning = true

		-- Dumpfer Einschlag-Sound.
		local sound = Instance.new("Sound")
		sound.SoundId = "rbxasset://sounds/impact_water.mp3"
		sound.Volume = 0.9
		sound.PlaybackSpeed = 0.6
		sound.Parent = Workspace
		sound:Play()
		task.delay(3, function()
			sound:Destroy()
		end)

		-- Ausgerüsteter Kollaps-Effekt (Skin, rein clientseitig visuell).
		local effect = SkinUIController.getEquippedCollapseEffect()
		local playbackScale = if effect == "zeitlupe" then 1.6 else 1
		if effect == "konfetti" then
			-- Burst am Ort des ersten Replay-Teils.
			local firstSample = if typeof(data.samples) == "table" then (data.samples :: { any })[1] else nil
			if typeof(firstSample) == "table" and typeof(firstSample.positions) == "table" then
				for _, rawPosition in firstSample.positions :: { [any]: any } do
					local position = vec3(rawPosition)
					if position ~= nil then
						playConfetti(position :: Vector3)
						break
					end
				end
			end
		end

		local closeBanner = showBanner(if typeof(data.culpritName) == "string" then data.culpritName else nil)
		local ok, err = pcall(playReplay, data, playbackScale)
		closeBanner()
		replayRunning = false
		if not ok then
			warn(`[Turmfall] Replay fehlgeschlagen: {err}`)
		end
	end)
end

return ReplayController
