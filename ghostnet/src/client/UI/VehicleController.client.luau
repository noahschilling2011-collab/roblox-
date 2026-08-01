-- StarterPlayer/StarterPlayerScripts/UI/VehicleController.client.luau
--!strict
-- GHOSTNET :: Fahren.
--
-- WARUM DIE STEUERUNG HIER LIEGT UND NICHT AUF DEM SERVER
--   Beim Einsteigen gibt der Server dem Client den Netzwerkbesitz ueber das
--   Fahrzeug. Die Physik laeuft also lokal. Wuerde der Server die Motoren
--   stellen, braeuchte jeder Gasstoss eine Rundreise - das Auto fuehlt sich
--   dann an wie Sirup. Deshalb setzt der Fahrer seine Constraints selbst.
--
--   Das ist ausdruecklich in Ordnung, weil an Fahrzeugposition und -tempo
--   NICHTS haengt, was Geld oder Fortschritt bewegt. Ankommen wird ueber
--   serverseitige Trigger geprueft, nie ueber eine gemeldete Position.
--
-- DAS FAHRGEFUEHL
--   Ein Auto fuehlt sich nicht schnell an, weil eine Zahl hoch ist, sondern
--   weil die Kamera zurueckweicht, das Sichtfeld aufgeht, der Motor
--   hochdreht und die Reifen quietschen. Genau das steht unten.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local SoundCatalog = require(ReplicatedStorage.Shared.SoundCatalog)
local UITheme = require(ReplicatedStorage.Shared.UITheme)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local camera = workspace.CurrentCamera

local C = UITheme.Color
local V = Config.Vehicle

--==========================================================================
-- Zustand
--==========================================================================

type Ride = {
	Model: Model,
	Body: BasePart,
	Seat: VehicleSeat,
	Drives: { CylindricalConstraint },
	Steers: { CylindricalConstraint },
	BrakeLights: { BasePart },
	MaxSpeed: number,
	Acceleration: number,
	BrakeForce: number,
	TurnAngle: number,
	WheelRadius: number,
	Steer: number,
	Engine: Sound?,
	Squeal: Sound?,
}

local ride: Ride? = nil
local skidMarks: { BasePart } = {}

--==========================================================================
-- Tacho
--==========================================================================

local gui = UITheme.Screen("GhostNetVehicle", 14)
gui.Enabled = false
gui.Parent = playerGui

local panel = UITheme.Frame({
	Name = "Speedo",
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, -18, 1, -46),
	Size = UDim2.fromOffset(190, 76),
	BackgroundColor3 = C.Panel,
	BackgroundTransparency = 0.08,
	Parent = gui,
})
UITheme.Corner(panel, 4)
UITheme.Stroke(panel, C.CyanDim)
UITheme.Padding(panel, 10)

local nameLabel = UITheme.Label({
	Name = "Name",
	Text = "",
	TextColor3 = C.TextDim,
	TextSize = 11,
	Size = UDim2.new(1, 0, 0, 12),
	Parent = panel,
})

local speedLabel = UITheme.Label({
	Name = "Speed",
	Text = "0",
	TextColor3 = C.Cyan,
	TextSize = 26,
	Position = UDim2.new(0, 0, 0, 14),
	Size = UDim2.new(1, 0, 0, 28),
	Parent = panel,
})

local barTrack = UITheme.Frame({
	Name = "Track",
	Position = UDim2.new(0, 0, 1, -10),
	Size = UDim2.new(1, 0, 0, 6),
	BackgroundColor3 = C.PanelLight,
	Parent = panel,
})
UITheme.Corner(barTrack, 3)

local barFill = UITheme.Frame({
	Name = "Fill",
	Size = UDim2.fromScale(0, 1),
	BackgroundColor3 = C.Cyan,
	Parent = barTrack,
})
UITheme.Corner(barFill, 3)

local hintLabel = UITheme.Label({
	Name = "Hint",
	Text = "[W][S] Gas/Bremse   [A][D] Lenken",
	TextColor3 = C.TextDim,
	TextSize = 10,
	Position = UDim2.new(0, 0, 1, -22),
	Size = UDim2.new(1, 0, 0, 11),
	Parent = panel,
})

--==========================================================================
-- Klang
--==========================================================================

local function makeSound(parent: BasePart, group: string, key: string, volume: number, looped: boolean): Sound?
	local id = SoundCatalog.Get(group, key)
	if not id then
		return nil -- noch keine Id eingetragen: bleibt still, nichts geht kaputt
	end
	local sound = Instance.new("Sound")
	sound.SoundId = id
	sound.Volume = volume
	sound.Looped = looped
	sound.RollOffMaxDistance = 140
	sound.Parent = parent
	if looped then
		sound:Play()
	end
	return sound
end

--==========================================================================
-- Fahrzeug einsammeln
--==========================================================================

local function collect(seat: VehicleSeat): Ride?
	local model = seat.Parent
	if not model or not model:IsA("Model") then
		return nil
	end
	local body = model:FindFirstChild("Body")
	if not body or not body:IsA("BasePart") then
		return nil
	end

	local drives: { CylindricalConstraint } = {}
	local steers: { CylindricalConstraint } = {}
	local brakeLights: { BasePart } = {}

	for _, descendant in model:GetDescendants() do
		if descendant:IsA("CylindricalConstraint") then
			if descendant:GetAttribute("Driven") == true then
				table.insert(drives, descendant)
			elseif descendant:GetAttribute("Steered") ~= nil then
				table.insert(steers, descendant)
			end
		elseif descendant:IsA("BasePart") and descendant.Name == "BrakeLight" then
			table.insert(brakeLights, descendant)
		end
	end

	return {
		Model = model,
		Body = body,
		Seat = seat,
		Drives = drives,
		Steers = steers,
		BrakeLights = brakeLights,
		MaxSpeed = tonumber(model:GetAttribute("MaxSpeed")) or 60,
		Acceleration = tonumber(model:GetAttribute("Acceleration")) or 6000,
		BrakeForce = tonumber(model:GetAttribute("BrakeForce")) or 8000,
		TurnAngle = tonumber(model:GetAttribute("TurnAngle")) or 30,
		WheelRadius = tonumber(model:GetAttribute("WheelRadius")) or 1.5,
		Steer = 0,
		Engine = nil,
		Squeal = nil,
	}
end

--==========================================================================
-- Ein- und Aussteigen
--==========================================================================

local function stop()
	local current = ride
	if not current then
		return
	end
	ride = nil

	-- Motoren aus, sonst faehrt das leere Auto weiter.
	for _, drive in current.Drives do
		if drive.Parent then
			drive.MotorMaxTorque = 0
			drive.AngularVelocity = 0
		end
	end
	for _, steer in current.Steers do
		if steer.Parent then
			steer.TargetAngle = 0
		end
	end
	for _, light in current.BrakeLights do
		if light.Parent then
			light.Color = Color3.fromRGB(120, 20, 30)
		end
	end
	if current.Engine then
		current.Engine:Destroy()
	end
	if current.Squeal then
		current.Squeal:Destroy()
	end

	gui.Enabled = false
	TweenService:Create(camera, TweenInfo.new(0.4), { FieldOfView = V.CameraFovBase }):Play()
end

local function start(seat: VehicleSeat)
	stop()
	local collected = collect(seat)
	if not collected then
		return
	end

	-- Motor und Reifenquietschen. Solange im SoundCatalog nichts eingetragen
	-- ist, liefert makeSound nil und es bleibt einfach still.
	collected.Engine = makeSound(collected.Body, "Vehicle", "Engine", V.EngineVolume, true)
	collected.Squeal = makeSound(collected.Body, "Vehicle", "TyreSqueal", 0, true)

	ride = collected
	nameLabel.Text = tostring(collected.Model:GetAttribute("ClassId") or "FAHRZEUG")
	gui.Enabled = true
end

local function watchCharacter(character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid or not humanoid:IsA("Humanoid") then
		return
	end
	humanoid.Seated:Connect(function(active, seat)
		if active and seat and seat:IsA("VehicleSeat") then
			start(seat)
		else
			stop()
		end
	end)
	-- Tod im Auto: sauber aussteigen, sonst haengt die Kamera fest.
	humanoid.Died:Connect(stop)
end

if player.Character then
	task.spawn(watchCharacter, player.Character)
end
player.CharacterAdded:Connect(watchCharacter)

--==========================================================================
-- Bremsspuren
--==========================================================================

local function leaveSkid(position: Vector3, direction: Vector3)
	if #skidMarks >= V.SkidMaxMarks then
		local oldest = table.remove(skidMarks, 1)
		if oldest then
			oldest:Destroy()
		end
	end

	local mark = Instance.new("Part")
	mark.Size = Vector3.new(0.6, 0.05, 2.4)
	mark.CFrame = CFrame.lookAt(position, position + direction) * CFrame.new(0, 0.03, 0)
	mark.Anchored = true
	mark.CanCollide = false
	mark.CanQuery = false
	mark.CanTouch = false
	mark.CastShadow = false
	mark.Color = Color3.fromRGB(12, 12, 14)
	mark.Material = Enum.Material.SmoothPlastic
	mark.Transparency = 0.3
	mark.Parent = workspace
	table.insert(skidMarks, mark)

	TweenService:Create(mark, TweenInfo.new(V.SkidLifetime), { Transparency = 1 }):Play()
	task.delay(V.SkidLifetime + 0.2, function()
		local index = table.find(skidMarks, mark)
		if index then
			table.remove(skidMarks, index)
		end
		mark:Destroy()
	end)
end

--==========================================================================
-- Der Fahr-Loop
--==========================================================================

RunService.RenderStepped:Connect(function(dt)
	local current = ride
	if not current then
		return
	end
	if not current.Model.Parent or not current.Body.Parent then
		stop()
		return
	end

	local seat = current.Seat
	local throttle = seat.Throttle -- -1 .. 1, liefert Roblox selbst
	local steerInput = seat.Steer -- -1 .. 1

	local velocity = current.Body.AssemblyLinearVelocity
	local speed = velocity.Magnitude
	local forward = current.Body.CFrame.LookVector
	local right = current.Body.CFrame.RightVector
	local forwardSpeed = velocity:Dot(forward)
	local sideSpeed = math.abs(velocity:Dot(right))

	--== Lenken ============================================================
	-- Bei Tempo weniger Einschlag: sonst ueberschlaegt sich jedes Auto beim
	-- ersten Vollausschlag auf der Geraden.
	local speedFactor = 1 - math.clamp(speed / current.MaxSpeed, 0, 1) * V.SteerSpeedFalloff
	local wanted = steerInput * current.TurnAngle * speedFactor
	current.Steer += (wanted - current.Steer) * math.clamp(dt * V.SteerSpeed, 0, 1)

	for _, steerConstraint in current.Steers do
		if steerConstraint.Parent and steerConstraint:GetAttribute("Steered") == true then
			steerConstraint.TargetAngle = current.Steer
		end
	end

	--== Gas und Bremse ====================================================
	local braking = (throttle < -0.1 and forwardSpeed > 1) or (throttle > 0.1 and forwardSpeed < -1)
	local targetAngular = 0
	local torque = 0

	if braking then
		targetAngular = 0
		torque = current.BrakeForce * V.BrakeTorqueScale
	elseif math.abs(throttle) > 0.05 then
		-- Winkelgeschwindigkeit aus Wunschtempo und Radradius.
		targetAngular = (current.MaxSpeed / current.WheelRadius) * throttle
		torque = current.Acceleration * V.TorqueScale
	else
		-- Kein Gas: leichtes Motorbremsen, damit das Auto nicht ewig rollt.
		targetAngular = 0
		torque = current.Acceleration * 0.12
	end

	for _, drive in current.Drives do
		if drive.Parent then
			drive.MotorMaxTorque = torque
			drive.AngularVelocity = targetAngular
		end
	end

	--== Rueckleuchten =====================================================
	for _, light in current.BrakeLights do
		if light.Parent then
			light.Color = if braking then Color3.fromRGB(255, 60, 70) else Color3.fromRGB(120, 20, 30)
		end
	end

	--== Kamera ============================================================
	-- Ohne das fuehlt sich kein Auto schnell an, egal wie hoch die Zahl steht.
	local fraction = math.clamp(speed / current.MaxSpeed, 0, 1)
	local wantedFov = V.CameraFovBase + (V.CameraFovFast - V.CameraFovBase) * fraction
	camera.FieldOfView += (wantedFov - camera.FieldOfView) * math.clamp(dt / math.max(V.CameraFovLerp, 0.01), 0, 1)

	--== Klang =============================================================
	if current.Engine then
		local load = math.max(fraction, math.abs(throttle) * 0.35)
		current.Engine.PlaybackSpeed = V.EnginePitchIdle + (V.EnginePitchMax - V.EnginePitchIdle) * load
	end

	local drifting = sideSpeed > V.SkidThreshold
	if current.Squeal then
		current.Squeal.Volume = if drifting then math.clamp((sideSpeed - V.SkidThreshold) / 20, 0, 0.6) else 0
	end

	--== Bremsspuren =======================================================
	if (drifting or (braking and speed > 25)) and math.random() < 0.5 then
		leaveSkid(current.Body.Position - Vector3.new(0, current.Body.Size.Y * 0.5, 0), forward)
	end

	--== Tacho =============================================================
	speedLabel.Text = ("%d"):format(math.floor(speed * 1.1)) -- Studs/s grob als km/h
	speedLabel.TextColor3 = if fraction > 0.85 then C.Magenta elseif fraction > 0.6 then C.Amber else C.Cyan
	barFill.Size = UDim2.fromScale(fraction, 1)
	barFill.BackgroundColor3 = speedLabel.TextColor3
	hintLabel.Text = if drifting then "GRIP VERLOREN" else "[W][S] Gas/Bremse   [A][D] Lenken"
end)
