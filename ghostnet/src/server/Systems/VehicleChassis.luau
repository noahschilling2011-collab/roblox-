-- ServerScriptService/Systems/VehicleChassis.luau
--!strict
-- GHOSTNET :: EIN Chassis, viele Karosserien.
--
-- Es gibt kein Skript pro Auto. Dieses Modul baut aus einem Datensatz in
-- Shared/Vehicles.luau ein fahrbares Fahrzeug. Eine neue Klasse = ein
-- Tabelleneintrag, keine Zeile Code.
--
-- AUFBAU PRO RAD (in dieser Reihenfolge wichtig)
--   Chassis --SpringConstraint--> Radtraeger      Federung
--   Chassis --CylindricalConstraint--> Radtraeger senkrechte Achse:
--                                                 Federweg + LENKUNG (Servo)
--   Radtraeger --CylindricalConstraint--> Rad     seitliche Achse:
--                                                 ANTRIEB (Motor)
--   Der Radtraeger ist noetig, weil eine einzelne Achse nicht gleichzeitig
--   Federweg (senkrecht) und Raddrehung (seitlich) sein kann.
--
-- NETZWERKBESITZ UND SICHERHEIT
--   Beim Einsteigen bekommt der Client den Besitz ueber alle Fahrzeugteile.
--   Ohne das faehrt sich das Auto wie durch Sirup, weil jede Eingabe eine
--   Rundreise zum Server braucht.
--   FOLGE: Der Client besitzt die Fahrzeugphysik. Er kann also Position und
--   Tempo faelschen. Deshalb gibt dieses Modul NIEMALS eine Belohnung und
--   liest NIEMALS eine Position als Beweis. Wer irgendwo ankommen muss, wird
--   ueber einen serverseitigen Trigger geprueft - genau wie beim Hacken.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Vehicles = require(ReplicatedStorage.Shared.Vehicles)

local VehicleChassis = {}

type VehicleClass = Vehicles.VehicleClass

local FOLDER_NAME = "GhostNet_Vehicles"

local function container(): Folder
	local existing = workspace:FindFirstChild(FOLDER_NAME)
	if existing and existing:IsA("Folder") then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = FOLDER_NAME
	folder.Parent = workspace
	return folder
end

--==========================================================================
-- Bauteile
--==========================================================================

local function physical(density: number, friction: number, elasticity: number): PhysicalProperties
	return PhysicalProperties.new(density, friction, elasticity, 100, 1)
end

local function attachment(parent: BasePart, name: string, position: Vector3, axis: Vector3, secondary: Vector3): Attachment
	local a = Instance.new("Attachment")
	a.Name = name
	a.Position = position
	a.Axis = axis
	a.SecondaryAxis = secondary
	a.Parent = parent
	return a
end

-- Ein Rad samt Traeger und den drei Verbindungen.
local function buildWheel(
	model: Model,
	body: BasePart,
	class: VehicleClass,
	offset: Vector3,
	steered: boolean,
	driven: boolean,
	side: number
)
	local V = Config.Vehicle

	--== Radtraeger: fast masselos, sonst schlingert das Auto ==============
	local carrier = Instance.new("Part")
	carrier.Name = "Carrier"
	carrier.Size = Vector3.new(0.4, 0.4, 0.4)
	carrier.Transparency = 1
	carrier.CanCollide = false
	carrier.CanQuery = false
	carrier.CanTouch = false
	carrier.CustomPhysicalProperties = physical(V.CarrierDensity, 0.3, 0)
	carrier.CFrame = body.CFrame * CFrame.new(offset - Vector3.new(0, V.SuspensionLength, 0))
	carrier.Parent = model

	--== Rad ===============================================================
	local wheel = Instance.new("Part")
	wheel.Name = "Wheel"
	wheel.Shape = Enum.PartType.Cylinder
	wheel.Size = Vector3.new(class.WheelWidth, class.WheelRadius * 2, class.WheelRadius * 2)
	wheel.Color = Color3.fromRGB(18, 18, 20)
	wheel.Material = Enum.Material.Rubber
	wheel.CanQuery = false
	wheel.CustomPhysicalProperties = physical(V.WheelDensity, class.Grip * V.WheelFriction, V.WheelElasticity)
	-- Zylinder liegen in Roblox entlang ihrer X-Achse: um 90 Grad drehen,
	-- damit die Lauflaeche zum Boden zeigt.
	wheel.CFrame = carrier.CFrame * CFrame.Angles(0, 0, math.rad(90))
	wheel.Parent = model

	--== Federung und Lenkung (senkrechte Achse) ===========================
	-- Achse zeigt nach UNTEN: positiver Abstand = ausgefedert.
	local bodyAttach = attachment(body, "Susp", offset, Vector3.new(0, -1, 0), Vector3.new(0, 0, 1))
	local carrierUp = attachment(carrier, "SuspHub", Vector3.zero, Vector3.new(0, -1, 0), Vector3.new(0, 0, 1))

	local spring = Instance.new("SpringConstraint")
	spring.Name = "Suspension"
	spring.Attachment0 = bodyAttach
	spring.Attachment1 = carrierUp
	spring.FreeLength = V.SuspensionLength
	spring.Stiffness = class.SuspensionStiffness
	spring.Damping = V.SuspensionDamping
	spring.LimitsEnabled = true
	spring.MinLength = math.max(0.1, V.SuspensionLength - V.SuspensionTravel)
	spring.MaxLength = V.SuspensionLength + V.SuspensionTravel
	spring.Parent = model

	-- Fuehrt den Traeger senkrecht und dreht ihn beim Lenken.
	local steer = Instance.new("CylindricalConstraint")
	steer.Name = if steered then "Steer" else "Guide"
	steer.Attachment0 = bodyAttach
	steer.Attachment1 = carrierUp
	steer.LimitsEnabled = true
	steer.LowerLimit = math.max(0.1, V.SuspensionLength - V.SuspensionTravel)
	steer.UpperLimit = V.SuspensionLength + V.SuspensionTravel
	steer.ActuatorType = Enum.ActuatorType.None -- die Feder macht die Kraft
	-- Auch nicht gelenkte Raeder bekommen einen Servo auf 0 Grad: sonst
	-- flattern sie frei um die Hochachse.
	steer.AngularActuatorType = Enum.ActuatorType.Servo
	steer.AngularSpeed = V.SteerSpeed * 10
	steer.ServoMaxTorque = class.Acceleration * 4
	steer.TargetAngle = 0
	steer.Parent = model

	--== Antrieb (seitliche Achse) =========================================
	local carrierSide = attachment(carrier, "Axle", Vector3.zero, Vector3.new(side, 0, 0), Vector3.new(0, 1, 0))
	local wheelSide = attachment(wheel, "Hub", Vector3.zero, Vector3.new(side, 0, 0), Vector3.new(0, 1, 0))

	local drive = Instance.new("CylindricalConstraint")
	drive.Name = if driven then "Drive" else "Roll"
	drive.Attachment0 = carrierSide
	drive.Attachment1 = wheelSide
	drive.LimitsEnabled = true
	drive.LowerLimit = 0
	drive.UpperLimit = 0 -- kein seitliches Spiel
	drive.ActuatorType = Enum.ActuatorType.None
	drive.AngularActuatorType = Enum.ActuatorType.Motor
	drive.MotorMaxTorque = 0 -- Leerlauf, der Fahrer setzt das
	drive.MotorMaxAngularAcceleration = math.huge
	drive.AngularVelocity = 0
	drive.Parent = model

	-- Attribute, damit der Client-Controller die Teile findet, ohne dass
	-- hier Namen doppelt gepflegt werden muessen.
	drive:SetAttribute("Driven", driven)
	steer:SetAttribute("Steered", steered)
	steer:SetAttribute("SideSign", side)
end

--==========================================================================
-- Ein komplettes Fahrzeug
--==========================================================================

function VehicleChassis.Build(classId: string, cframe: CFrame, colour: Color3?): Model?
	local class = Vehicles.Get(classId)
	if not class then
		warn(("[GHOSTNET] Unbekannte Fahrzeugklasse '%s'."):format(tostring(classId)))
		return nil
	end

	local V = Config.Vehicle
	local model = Instance.new("Model")
	model.Name = ("Vehicle_%s"):format(class.Id)

	--== Karosserie ========================================================
	local body = Instance.new("Part")
	body.Name = "Body"
	body.Size = class.BodySize
	body.CFrame = cframe
	body.Color = colour or class.Colour
	body.Material = Enum.Material.SmoothPlastic
	body.CustomPhysicalProperties = physical(class.Mass, 0.3, 0.1)
	body.Parent = model
	model.PrimaryPart = body

	-- Dach, damit es nicht wie eine Kiste aussieht. Nur Deko.
	local roof = Instance.new("Part")
	roof.Name = "Roof"
	roof.Size = Vector3.new(class.BodySize.X * 0.86, class.BodySize.Y * 0.7, class.BodySize.Z * 0.5)
	roof.CFrame = cframe * CFrame.new(0, class.BodySize.Y * 0.8, -class.BodySize.Z * 0.06)
	roof.Color = (colour or class.Colour):Lerp(Color3.new(0, 0, 0), 0.35)
	roof.Material = Enum.Material.Glass
	roof.Transparency = 0.35
	roof.CanQuery = false
	roof.CustomPhysicalProperties = physical(0.05, 0.3, 0.1)
	roof.Parent = model

	local roofWeld = Instance.new("WeldConstraint")
	roofWeld.Part0 = body
	roofWeld.Part1 = roof
	roofWeld.Parent = body

	--== Rueckleuchten (der Client schaltet sie beim Bremsen hell) =========
	for _, side in { -1, 1 } do
		local light = Instance.new("Part")
		light.Name = "BrakeLight"
		light.Size = Vector3.new(class.BodySize.X * 0.22, 0.4, 0.3)
		light.CFrame = cframe * CFrame.new(side * class.BodySize.X * 0.32, 0.2, class.BodySize.Z * 0.5)
		light.Color = Color3.fromRGB(120, 20, 30)
		light.Material = Enum.Material.Neon
		light.CanQuery = false
		light.CanTouch = false
		light.CustomPhysicalProperties = physical(0.01, 0.3, 0)
		light.Parent = model

		local weld = Instance.new("WeldConstraint")
		weld.Part0 = body
		weld.Part1 = light
		weld.Parent = body
	end

	--== Sitz ==============================================================
	local seat = Instance.new("VehicleSeat")
	seat.Name = "DriverSeat"
	seat.Size = Vector3.new(2.4, 0.4, 2.4)
	seat.CFrame = cframe * CFrame.new(0, class.BodySize.Y * 0.5 + 0.2, 0)
	seat.Transparency = 1
	seat.CanQuery = false
	seat.MaxSpeed = class.MaxSpeed
	seat.Torque = 0 -- der VehicleSeat treibt nichts an, das machen die Raeder
	seat.TurnSpeed = 0
	seat.CustomPhysicalProperties = physical(0.01, 0.3, 0)
	seat.Parent = model

	local seatWeld = Instance.new("WeldConstraint")
	seatWeld.Part0 = body
	seatWeld.Part1 = seat
	seatWeld.Parent = body

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "EnterPrompt"
	prompt.ActionText = "Einsteigen"
	prompt.ObjectText = class.Name
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = seat

	--== Raeder ============================================================
	local halfX = class.BodySize.X * 0.5
	local halfZ = class.BodySize.Z * 0.5
	local wheelY = -class.BodySize.Y * 0.5 + V.SuspensionLength * 0.2

	if class.Wheels == 2 then
		-- Motorrad: vorne gelenkt, hinten angetrieben, beide mittig.
		buildWheel(model, body, class, Vector3.new(0, wheelY, -halfZ * 0.78), true, false, 1)
		buildWheel(model, body, class, Vector3.new(0, wheelY, halfZ * 0.78), false, true, 1)
	else
		for _, side in { -1, 1 } do
			buildWheel(model, body, class, Vector3.new(side * halfX, wheelY, -halfZ * 0.7), true, false, side)
			buildWheel(model, body, class, Vector3.new(side * halfX, wheelY, halfZ * 0.7), false, true, side)
		end
	end

	--== Attribute: der Client liest daraus seine Fahrwerte ================
	model:SetAttribute("ClassId", class.Id)
	model:SetAttribute("MaxSpeed", class.MaxSpeed)
	model:SetAttribute("Acceleration", class.Acceleration)
	model:SetAttribute("BrakeForce", class.BrakeForce)
	model:SetAttribute("TurnAngle", class.TurnAngle)
	model:SetAttribute("WheelRadius", class.WheelRadius)
	model:SetAttribute("HeatFactor", class.HeatFactor)
	model:SetAttribute("Damage", 0)

	-- Streaming: das Fahrzeug muss auch dann existieren, wenn der Besitzer
	-- kurz aus der Ladezone faehrt.
	model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent

	CollectionService:AddTag(model, Config.VehicleTag)
	model.Parent = container()
	return model
end

--==========================================================================
-- Besitz und Lebenszyklus
--==========================================================================

local emptySince: { [Model]: number } = {}

local function parts(model: Model): { BasePart }
	local list: { BasePart } = {}
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			table.insert(list, descendant)
		end
	end
	return list
end

-- Ohne Netzwerkbesitz beim Fahrer laeuft die Physik auf dem Server und jede
-- Eingabe braucht eine Rundreise. Das Auto fuehlt sich dann an wie Sirup.
local function setOwner(model: Model, player: Player?)
	for _, part in parts(model) do
		if part.Anchored then
			continue
		end
		pcall(function()
			part:SetNetworkOwner(player)
		end)
	end
end

function VehicleChassis.Despawn(model: Model)
	emptySince[model] = nil
	if model.Parent then
		model:Destroy()
	end
end

local function watchSeat(model: Model)
	local seat = model:FindFirstChild("DriverSeat")
	if not seat or not seat:IsA("VehicleSeat") then
		return
	end

	emptySince[model] = os.clock()

	seat:GetPropertyChangedSignal("Occupant"):Connect(function()
		local occupant = seat.Occupant
		if occupant then
			local character = occupant.Parent
			local player = character and Players:GetPlayerFromCharacter(character)
			if player then
				setOwner(model, player)
				emptySince[model] = nil
				model:SetAttribute("DriverUserId", player.UserId)
				return
			end
		end

		-- Ausgestiegen, gestorben oder rausgeflogen: Besitz zurueck an den
		-- Server, sonst behaelt ein weggegangener Client die Kontrolle.
		setOwner(model, nil)
		emptySince[model] = os.clock()
		model:SetAttribute("DriverUserId", 0)
	end)
end

--==========================================================================

function VehicleChassis.Init()
	local valid, errors = Vehicles.Validate()
	if not valid then
		for _, message in errors do
			warn(("[GHOSTNET] Fahrzeugkatalog: %s"):format(message))
		end
	end

	for _, model in CollectionService:GetTagged(Config.VehicleTag) do
		if model:IsA("Model") then
			watchSeat(model)
		end
	end
	CollectionService:GetInstanceAddedSignal(Config.VehicleTag):Connect(function(inst)
		if inst:IsA("Model") then
			watchSeat(inst)
		end
	end)
	CollectionService:GetInstanceRemovedSignal(Config.VehicleTag):Connect(function(inst)
		if inst:IsA("Model") then
			emptySince[inst] = nil
		end
	end)

	-- Leerstehende Fahrzeuge raeumen. Gestaffelter Takt statt eines
	-- Heartbeat-Handlers ueber alles.
	task.spawn(function()
		while true do
			task.wait(5)
			local now = os.clock()
			for model, since in emptySince do
				if not model.Parent then
					emptySince[model] = nil
				elseif model:GetAttribute("Permanent") ~= true and now - since > Config.Vehicle.IdleDespawn then
					VehicleChassis.Despawn(model)
				end
			end
		end
	end)

	print(("[GHOSTNET] VehicleChassis bereit. %d Klassen."):format(Vehicles.Count()))
end

return VehicleChassis
