-- ServerScriptService/Systems/VehicleChassis.luau
--!strict
-- GHOSTNET :: Fahrzeuge VERDRAHTEN, nicht bauen.
--
-- WAS SICH GEAENDERT HAT
--   Frueher hat dieses Modul die Karosserie selbst aus Parts zusammengesetzt:
--   ein Kasten Body, ein Kasten Dach, vier Zylinder, zwei Kaestchen Licht.
--   Das ist die Decke - kein Material und kein Licht macht aus einem Quader
--   ein Auto. Ein Auto braucht Motorhaube, Kotfluegel, abfallende Dachlinie,
--   Radkaesten, Fenster mit Rahmen. Das sind zwei Dutzend geformte Flaechen,
--   und die entstehen in Blender oder Studio, nicht zur Laufzeit.
--
--   Jetzt gilt: die Karosserie kommt als fertiges Modell aus
--   ReplicatedStorage/Assets/Vehicles, dieses Modul haengt Physik daran.
--
-- WAS EIN FAHRZEUGMODELL ENTHALTEN MUSS (Config.Assets.VehicleRequired)
--   Sedan (Model)
--   |-- Chassis     Part, unsichtbar, PrimaryPart - die Kollisionsbox
--   |-- Body        MeshPart, die sichtbare Karosserie
--   |-- Glass       MeshPart, Fenster                    (optional)
--   |-- Wheels/     FL, FR, RL, RR   (bei 2 Raedern: F, R)
--   |-- Lights/     HeadL, HeadR, TailL, TailR           (optional)
--   +-- DriveSeat   VehicleSeat
--
--   Name faengt mit F an = gelenkt, mit R an = angetrieben. Damit passt
--   dieselbe Verdrahtung auf Auto und Motorrad.
--
--   Fehlt ein Pflichtteil, gibt es eine klare Meldung mit Modellname UND
--   fehlendem Teil - keinen stillen Absturz und kein halb fahrendes Auto.
--
-- KOLLISION SAUBER GETRENNT
--   Nur Chassis kollidiert mit der Welt. Karosserie, Glas und Lichter sind
--   CanCollide = false. Sonst haengt das Auto an jeder Kante fest, weil
--   zwei Dutzend Einzelflaechen gleichzeitig kollidieren.
--   Raeder kollidieren, aber in einer eigenen CollisionGroup: sie sollen den
--   Boden treffen und nicht die Raeder des Nachbarautos.
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
local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AssetLibrary = require(ReplicatedStorage.Shared.AssetLibrary)
local Config = require(ReplicatedStorage.Shared.Config)
local Vehicles = require(ReplicatedStorage.Shared.Vehicles)

local VehicleChassis = {}

type VehicleClass = Vehicles.VehicleClass

local FOLDER_NAME = "GhostNet_Vehicles"
local A = Config.Assets

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

--==========================================================================
-- PLATZHALTER
--
-- Der einzige Ort in diesem Modul, an dem noch Geometrie entsteht - und das
-- ist Absicht. Solange eine Vorlage fehlt, soll das Spiel FAHRBAR bleiben,
-- aber unuebersehbar unfertig aussehen. Deshalb: magenta Kasten, vier
-- Zylinder, sonst nichts. Kein Dach, keine Lichter, keine Farbwahl.
--
-- Sobald Assets/Vehicles/<Name> existiert, wird dieser Zweig nie wieder
-- betreten. Er ist eine Baustellenabsperrung, kein Fahrzeugdesign.
--==========================================================================

local function placeholderVehicle(class: VehicleClass): Model
	local model = AssetLibrary.Placeholder("Vehicles", class.Asset, class.BodySize)
	local block = model.PrimaryPart :: BasePart

	-- Der Platzhalterklotz wird zur unsichtbaren Kollisionsbox, damit das
	-- Modell denselben Vertrag erfuellt wie eine echte Vorlage.
	block.Name = "Chassis"
	block.Transparency = 1
	block.CanCollide = true

	local body = Instance.new("Part")
	body.Name = "Body"
	body.Size = class.BodySize * A.PlaceholderBodyScale
	body.Color = A.PlaceholderColour
	body.Material = Enum.Material.SmoothPlastic
	body.CFrame = block.CFrame
	body.Parent = model

	local wheels = Instance.new("Folder")
	wheels.Name = "Wheels"
	wheels.Parent = model

	local halfX = class.BodySize.X * 0.5
	local halfZ = class.BodySize.Z * 0.5
	local wheelY = -class.BodySize.Y * 0.5

	local slots: { { name: string, offset: Vector3 } }
	if class.Wheels == 2 then
		slots = {
			{ name = "F", offset = Vector3.new(0, wheelY, -halfZ * 0.78) },
			{ name = "R", offset = Vector3.new(0, wheelY, halfZ * 0.78) },
		}
	else
		slots = {
			{ name = "FL", offset = Vector3.new(-halfX, wheelY, -halfZ * 0.7) },
			{ name = "FR", offset = Vector3.new(halfX, wheelY, -halfZ * 0.7) },
			{ name = "RL", offset = Vector3.new(-halfX, wheelY, halfZ * 0.7) },
			{ name = "RR", offset = Vector3.new(halfX, wheelY, halfZ * 0.7) },
		}
	end

	for _, slot in slots do
		local wheel = Instance.new("Part")
		wheel.Name = slot.name
		wheel.Shape = Enum.PartType.Cylinder
		wheel.Size = Vector3.new(class.WheelWidth, class.WheelRadius * 2, class.WheelRadius * 2)
		wheel.Color = A.PlaceholderColour
		wheel.Material = Enum.Material.SmoothPlastic
		-- Zylinder liegen in Roblox entlang ihrer X-Achse.
		wheel.CFrame = block.CFrame * CFrame.new(slot.offset) * CFrame.Angles(0, 0, math.rad(90))
		wheel.Parent = wheels
	end

	local seat = Instance.new("VehicleSeat")
	seat.Name = "DriveSeat"
	seat.Size = Vector3.new(2.4, 0.4, 2.4)
	seat.CFrame = block.CFrame * CFrame.new(0, class.BodySize.Y * 0.5 + 0.2, 0)
	seat.Transparency = 1
	seat.Parent = model

	return model
end

--==========================================================================
-- Verdrahten
--==========================================================================

-- Ein Rad samt Traeger und den drei Verbindungen. Die POSITION kommt aus
-- dem Modell - wo die Raeder sitzen, entscheidet der, der das Auto gebaut
-- hat, nicht dieser Code.
local function wireWheel(model: Model, chassis: BasePart, wheel: BasePart, class: VehicleClass)
	local V = Config.Vehicle

	local steered = string.sub(wheel.Name, 1, 1) == "F"
	local driven = string.sub(wheel.Name, 1, 1) == "R"
	local offset = chassis.CFrame:PointToObjectSpace(wheel.Position)
	-- Linke Raeder drehen spiegelverkehrt zu den rechten.
	local side = if offset.X < 0 then -1 else 1

	wheel.CanQuery = false
	wheel.CanCollide = true
	wheel.Anchored = false
	wheel.Massless = false
	wheel.CustomPhysicalProperties = physical(V.WheelDensity, class.Grip * V.WheelFriction, V.WheelElasticity)
	pcall(function()
		wheel.CollisionGroup = V.WheelCollisionGroup
	end)

	--== Radtraeger: fast masselos, sonst schlingert das Auto ==============
	local carrier = Instance.new("Part")
	carrier.Name = wheel.Name .. "_Carrier"
	carrier.Size = Vector3.new(0.4, 0.4, 0.4)
	carrier.Transparency = 1
	carrier.CanCollide = false
	carrier.CanQuery = false
	carrier.CanTouch = false
	carrier.CustomPhysicalProperties = physical(V.CarrierDensity, 0.3, 0)
	carrier.CFrame = CFrame.new(wheel.Position)
	carrier.Parent = model

	--== Federung und Lenkung (senkrechte Achse) ===========================
	-- Achse zeigt nach UNTEN: positiver Abstand = ausgefedert.
	local mount = offset + Vector3.new(0, V.SuspensionLength, 0)
	local bodyAttach = attachment(chassis, wheel.Name .. "_Susp", mount, Vector3.new(0, -1, 0), Vector3.new(0, 0, 1))
	local carrierUp = attachment(carrier, "SuspHub", Vector3.zero, Vector3.new(0, -1, 0), Vector3.new(0, 0, 1))

	local spring = Instance.new("SpringConstraint")
	spring.Name = wheel.Name .. "_Suspension"
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

-- Alles, was man ansieht, aber nicht anfasst: keine Kollision, keine
-- Abfrage, kaum Masse. Sonst haengt das Auto an jeder Bordsteinkante.
local function makeCosmetic(part: BasePart)
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Anchored = false
	part.Massless = true
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

	local model: Model
	if AssetLibrary.Has("Vehicles", class.Asset) then
		model = AssetLibrary.Clone("Vehicles", class.Asset, class.BodySize)
	else
		model = placeholderVehicle(class)
	end
	model.Name = ("Vehicle_%s"):format(class.Id)

	--== Vertrag pruefen ===================================================
	local required = if class.Wheels == 2 then A.VehicleRequiredTwoWheel else A.VehicleRequired
	local complete, gaps = AssetLibrary.Verify(model, required)
	if not complete then
		warn(
			("[GHOSTNET] Fahrzeugvorlage '%s' (Klasse %s) ist unvollstaendig. Fehlende Teile: %s"):format(
				class.Asset,
				class.Id,
				table.concat(gaps, ", ")
			)
		)
		warn("           Erwartet wird: " .. table.concat(required, ", "))
		model:Destroy()
		return nil
	end

	local chassis = AssetLibrary.Find(model, "Chassis") :: BasePart
	local seat = AssetLibrary.Find(model, "DriveSeat") :: VehicleSeat
	local wheelFolder = AssetLibrary.Find(model, "Wheels") :: Instance

	if not chassis:IsA("BasePart") then
		warn(("[GHOSTNET] '%s': Chassis ist kein BasePart."):format(class.Asset))
		model:Destroy()
		return nil
	end
	if not seat:IsA("VehicleSeat") then
		warn(("[GHOSTNET] '%s': DriveSeat ist kein VehicleSeat."):format(class.Asset))
		model:Destroy()
		return nil
	end

	model.PrimaryPart = chassis
	model:PivotTo(cframe)

	--== Chassis: die einzige echte Kollisionsbox ==========================
	chassis.Transparency = 1
	chassis.CanCollide = true
	chassis.CanQuery = false
	chassis.Anchored = false
	chassis.Massless = false
	chassis.CustomPhysicalProperties = physical(class.Mass, 0.3, 0.1)

	--== Sichtbares: dekorativ, nie kollidierend ===========================
	for _, descendant in model:GetDescendants() do
		if not descendant:IsA("BasePart") then
			continue
		end
		if descendant == chassis or descendant == seat then
			continue
		end
		if descendant:IsDescendantOf(wheelFolder) then
			continue
		end
		makeCosmetic(descendant)
	end

	-- Lackierung: nur die Karosserie, nicht Glas und nicht die Lichter.
	local body = AssetLibrary.Find(model, "Body")
	if colour and body and body:IsA("BasePart") then
		body.Color = colour
	elseif body and body:IsA("BasePart") and not model:GetAttribute("Placeholder") then
		body.Color = class.Colour
	end

	--== Sitz ==============================================================
	seat.Transparency = 1
	seat.CanQuery = false
	seat.CanCollide = false
	seat.Massless = true
	seat.MaxSpeed = class.MaxSpeed
	seat.Torque = 0 -- der VehicleSeat treibt nichts an, das machen die Raeder
	seat.TurnSpeed = 0

	if not seat:FindFirstChild("EnterPrompt") then
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "EnterPrompt"
		prompt.ActionText = "Einsteigen"
		prompt.ObjectText = class.Name
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = Config.Vehicle.EnterRange
		prompt.RequiresLineOfSight = false
		prompt.Parent = seat
	end

	-- Der Sitz haengt fest an der Kollisionsbox. Hier ist eine WeldConstraint
	-- richtig: beide Teile sind NICHT anchored, es ist echte Physik.
	local seatWeld = Instance.new("WeldConstraint")
	seatWeld.Part0 = chassis
	seatWeld.Part1 = seat
	seatWeld.Parent = chassis

	-- Alles Kosmetische fest an die Kollisionsbox schweissen. Auch hier:
	-- echte Physik zwischen nicht-anchored Teilen, also wirkt es.
	for _, descendant in model:GetDescendants() do
		if not descendant:IsA("BasePart") then
			continue
		end
		if descendant == chassis or descendant == seat or descendant:IsDescendantOf(wheelFolder) then
			continue
		end
		if descendant.Name:match("_Carrier$") then
			continue
		end
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = chassis
		weld.Part1 = descendant
		weld.Parent = chassis
	end

	--== Raeder ============================================================
	for _, wheel in wheelFolder:GetChildren() do
		if wheel:IsA("BasePart") then
			wireWheel(model, chassis, wheel, class)
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
	local seat = model:FindFirstChild("DriveSeat")
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

	-- Raeder treffen den Boden, aber nicht die Raeder des Nachbarautos.
	-- Ohne das verhaken sich zwei Fahrzeuge, sobald sie sich beruehren.
	pcall(function()
		local group = Config.Vehicle.WheelCollisionGroup
		PhysicsService:RegisterCollisionGroup(group)
		PhysicsService:CollisionGroupSetCollidable(group, group, false)
	end)

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

	print(("[GHOSTNET] VehicleChassis bereit. %d Klassen, Karosserien aus Assets/Vehicles."):format(Vehicles.Count()))
end

return VehicleChassis
