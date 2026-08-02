-- ServerScriptService/Systems/VehicleChassis.luau
--!strict
-- GHOSTNET :: Fahrzeuge bauen UND verdrahten.
--
-- ERSETZT die bisherige Version vollstaendig. Was sich geaendert hat:
--
-- 1. KAROSSERIE WIRD WIEDER GEBAUT
--    Die alte Version hat auf fertige Modelle aus Assets/Vehicles gewartet.
--    Die Ordner sind leer, also lief JEDES Auto ueber den Platzhalterzweig:
--    magenta Kasten, vier Zylinder, Namensschild drueber. Deshalb sah alles
--    kaputt aus - der Code war nicht defekt, es fehlte schlicht der Inhalt.
--    Jetzt baut BuildBody() eine richtige Karosserie aus Parts und Wedges:
--    Motorhaube, abfallende Dachlinie, Kotfluegel, Fenster, Lichter, Grill.
--    Echte Modelle haben weiter Vorrang - liegt eins in Assets/Vehicles,
--    wird es benutzt und dieser Zweig nie betreten.
--
-- 2. RAEDER FLIEGEN NICHT MEHR WEG
--    Drei Fehler zusammen, alle behoben (siehe Kommentare unten):
--      a) Zylinderraeder wurden um 90 Grad um Z gedreht. Roblox-Zylinder
--         zeigen entlang ihrer LOKALEN X-Achse. Ein Autorad braucht die
--         Achse seitlich, also GAR KEINE Drehung. Durch die Drehung lag das
--         Rad flach wie ein Teller.
--      b) Der Antriebs-Constraint griff auf der lokalen X-Achse des Rades an.
--         Nach der Fehldrehung aus (a) zeigte die senkrecht nach oben. Der
--         Motor hat also versucht, das Rad um eine falsche Achse zu drehen.
--      c) SpringConstraint UND CylindricalConstraint hingen an DENSELBEN
--         zwei Attachments, beide mit LimitsEnabled. Zwei Limit-Solver auf
--         demselben Freiheitsgrad schaukeln sich auf, bis die Baugruppe
--         auseinanderfliegt. Jetzt fuehrt nur der Cylindrical die Grenzen,
--         die Feder liefert nur noch Kraft.
--    Dazu: MotorMaxAngularAcceleration war math.huge. Unendlich ist im
--    Physiksolver ein NaN-Generator. Jetzt ein endlicher Wert.
--
-- 3. BAUPLAN EINES FAHRZEUGMODELLS (unveraendert, Assets muessen das treffen)
--    Sedan (Model)
--    |-- Chassis     Part, unsichtbar, PrimaryPart - die Kollisionsbox
--    |-- Body        die sichtbare Karosserie
--    |-- Wheels/     FL, FR, RL, RR   (bei 2 Raedern: F, R)
--    +-- DriveSeat   VehicleSeat
--    Name faengt mit F an = gelenkt, mit R an = angetrieben.
--
-- 4. KOLLISION
--    Nur Chassis kollidiert mit der Welt. Karosserie, Glas, Lichter sind
--    CanCollide = false, sonst haengt das Auto an jeder Bordsteinkante.
--    Raeder kollidieren in eigener CollisionGroup.
--
-- 5. NETZWERKBESITZ
--    Beim Einsteigen bekommt der Client den Besitz. Folge: er kann Position
--    und Tempo faelschen. Dieses Modul gibt deshalb NIE eine Belohnung und
--    liest NIE eine Position als Beweis.
--
-- 6. EINE QUELLE FUER ALLE FAHRZEUGE
--    Verkehr und Streifenwagen holen ihre Karosserie ueber BuildShell() aus
--    genau diesem Bauplan. Sonst haette der Spieler ein richtiges Auto und
--    der Verkehr weiter magenta Kloetze - und ein gestohlenes Auto wuerde
--    beim Kurzschliessen sichtbar die Form wechseln.

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
-- KAROSSERIE
--
-- Alles hier ist relativ zur BodySize der Klasse. Ein Sportwagen ist flach
-- und breit, ein Van hoch und kastig - der Unterschied entsteht aus den
-- Proportionen, nicht aus Sonderfaellen pro Fahrzeug.
--==========================================================================

-- Wie stark faellt Dach/Motorhaube ab, wie weit steht die Kabine hinten.
-- Ein Profil pro Silhouette, nicht pro Fahrzeug: neue Klassen erben eins.
type Profile = {
	CabinStart: number, -- Anfang der Kabine, 0 = Front, 1 = Heck
	CabinEnd: number,
	CabinHeight: number, -- Anteil der Gesamthoehe ueber der Guertellinie
	NoseDrop: number, -- wie flach die Front zulaeuft
	TailDrop: number,
}

local PROFILES: { [string]: Profile } = {
	COMPACT = { CabinStart = 0.32, CabinEnd = 0.86, CabinHeight = 0.42, NoseDrop = 0.30, TailDrop = 0.18 },
	SEDAN = { CabinStart = 0.34, CabinEnd = 0.78, CabinHeight = 0.40, NoseDrop = 0.34, TailDrop = 0.30 },
	SPORT = { CabinStart = 0.40, CabinEnd = 0.74, CabinHeight = 0.34, NoseDrop = 0.46, TailDrop = 0.34 },
	VAN = { CabinStart = 0.22, CabinEnd = 0.94, CabinHeight = 0.52, NoseDrop = 0.18, TailDrop = 0.06 },
}

local DEFAULT_PROFILE: Profile =
	{ CabinStart = 0.34, CabinEnd = 0.80, CabinHeight = 0.42, NoseDrop = 0.32, TailDrop = 0.24 }

local function profileFor(class: VehicleClass): Profile
	return PROFILES[class.Id] or DEFAULT_PROFILE
end

local function piece(parent: Instance, name: string, size: Vector3, cf: CFrame, colour: Color3, material: Enum.Material): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cf
	part.Color = colour
	part.Material = material
	part.Anchored = false
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

local function wedge(parent: Instance, name: string, size: Vector3, cf: CFrame, colour: Color3): WedgePart
	local part = Instance.new("WedgePart")
	part.Name = name
	part.Size = size
	part.CFrame = cf
	part.Color = colour
	part.Material = Enum.Material.Metal
	part.Anchored = false
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.Parent = parent
	return part
end

-- Baut die sichtbare Karosserie um eine bereits stehende Kollisionsbox.
-- Gibt den Body-Part zurueck, damit die Lackierung ihn faerben kann.
local function buildBody(model: Model, chassis: BasePart, class: VehicleClass): BasePart
	local p = profileFor(class)
	local size = class.BodySize
	local L, W, H = size.Z, size.X, size.Y
	local colour = class.Colour
	local dark = Color3.new(colour.R * 0.35, colour.G * 0.35, colour.B * 0.35)
	local glass = Color3.fromRGB(28, 34, 44)

	local body = Instance.new("Folder")
	body.Name = "BodyParts"
	body.Parent = model

	local base = chassis.CFrame

	-- Guertellinie: unterhalb Karosserie, oberhalb Kabine.
	local beltH = H * (1 - p.CabinHeight)
	local beltY = -H * 0.5 + beltH * 0.5

	--== Rumpf: die durchgehende untere Haelfte ============================
	local hull = piece(
		body,
		"Body",
		Vector3.new(W, beltH, L),
		base * CFrame.new(0, beltY, 0),
		colour,
		Enum.Material.Metal
	)

	--== Schweller: dunkler Streifen ganz unten, macht das Auto optisch tief
	piece(
		body,
		"Sill",
		Vector3.new(W * 1.01, H * 0.14, L * 0.86),
		base * CFrame.new(0, -H * 0.5 + H * 0.07, 0),
		dark,
		Enum.Material.SmoothPlastic
	)

	--== Kabine ============================================================
	-- Z-Achse: -L/2 ist vorne, +L/2 ist hinten.
	local cabinFrontZ = -L * 0.5 + L * p.CabinStart
	local cabinBackZ = -L * 0.5 + L * p.CabinEnd
	local cabinLen = cabinBackZ - cabinFrontZ
	local cabinZ = (cabinFrontZ + cabinBackZ) * 0.5
	local cabinH = H * p.CabinHeight
	local cabinY = -H * 0.5 + beltH + cabinH * 0.5
	local cabinW = W * 0.86

	piece(
		body,
		"Cabin",
		Vector3.new(cabinW, cabinH, cabinLen),
		base * CFrame.new(0, cabinY, cabinZ),
		colour,
		Enum.Material.Metal
	)

	--== Fenster: knapp breiter als die Kabine, damit sie sichtbar sind ====
	piece(
		body,
		"GlassSide",
		Vector3.new(cabinW * 1.02, cabinH * 0.62, cabinLen * 0.92),
		base * CFrame.new(0, cabinY + cabinH * 0.08, cabinZ),
		glass,
		Enum.Material.Glass
	)

	--== Windschutzscheibe: Keil nach vorne abfallend ======================
	-- WedgePart: die schraege Flaeche steigt entlang +Z und +Y an.
	local wsLen = L * p.NoseDrop * 0.55
	wedge(
		body,
		"Windscreen",
		Vector3.new(cabinW, cabinH * 0.9, wsLen),
		base * CFrame.new(0, cabinY - cabinH * 0.05, cabinFrontZ - wsLen * 0.5),
		glass
	)

	--== Heckscheibe: gleicher Keil, um 180 Grad gedreht ===================
	local rearLen = L * p.TailDrop * 0.7
	if rearLen > 0.2 then
		wedge(
			body,
			"RearGlass",
			Vector3.new(cabinW, cabinH * 0.8, rearLen),
			base * CFrame.new(0, cabinY - cabinH * 0.1, cabinBackZ + rearLen * 0.5) * CFrame.Angles(0, math.pi, 0),
			glass
		)
	end

	--== Motorhaube: leicht abfallender Keil vor der Kabine ================
	local hoodLen = math.abs(cabinFrontZ - (-L * 0.5)) - wsLen
	if hoodLen > 0.3 then
		local hoodZ = -L * 0.5 + hoodLen * 0.5
		piece(
			body,
			"Hood",
			Vector3.new(W * 0.96, H * 0.06, hoodLen),
			base * CFrame.new(0, beltY + beltH * 0.5, hoodZ),
			colour,
			Enum.Material.Metal
		)
	end

	--== Kotfluegel ueber den Radkaesten ===================================
	-- Ohne die sitzt das Rad optisch neben dem Auto statt darin.
	local archY = -H * 0.5 + class.WheelRadius * 0.9
	local archZFront = -L * 0.5 + L * 0.20
	local archZRear = L * 0.5 - L * 0.20
	for _, zPos in { archZFront, archZRear } do
		for _, sideSign in { -1, 1 } do
			piece(
				body,
				"Arch",
				Vector3.new(W * 0.10, class.WheelRadius * 1.1, class.WheelRadius * 2.6),
				base * CFrame.new(sideSign * W * 0.5, archY, zPos),
				dark,
				Enum.Material.SmoothPlastic
			)
		end
	end

	--== Kuehlergrill ======================================================
	piece(
		body,
		"Grille",
		Vector3.new(W * 0.62, H * 0.16, 0.3),
		base * CFrame.new(0, beltY + beltH * 0.12, -L * 0.5 - 0.1),
		Color3.fromRGB(24, 26, 32),
		Enum.Material.DiamondPlate
	)

	--== Lichter ===========================================================
	local lightY = beltY + beltH * 0.22
	for _, sideSign in { -1, 1 } do
		local head = piece(
			body,
			if sideSign < 0 then "HeadL" else "HeadR",
			Vector3.new(W * 0.20, H * 0.12, 0.24),
			base * CFrame.new(sideSign * W * 0.32, lightY, -L * 0.5 - 0.08),
			Color3.fromRGB(255, 246, 214),
			Enum.Material.Neon
		)
		head:SetAttribute("Headlight", true)

		local tail = piece(
			body,
			if sideSign < 0 then "TailL" else "TailR",
			Vector3.new(W * 0.22, H * 0.10, 0.22),
			base * CFrame.new(sideSign * W * 0.30, lightY, L * 0.5 + 0.08),
			Color3.fromRGB(196, 28, 40),
			Enum.Material.Neon
		)
		tail:SetAttribute("Taillight", true)
	end

	return hull
end

--==========================================================================
-- RAEDER
--
-- WICHTIG ZUR ORIENTIERUNG:
-- Ein Roblox-Zylinder hat seine runde Flaeche entlang der lokalen X-Achse.
-- Size = (Breite, Durchmesser, Durchmesser).
-- Ein Autorad muss sich um die SEITLICHE Achse drehen - und die seitliche
-- Achse des Fahrzeugs ist ebenfalls X. Also: KEINE Drehung. Genau hier lag
-- der alte Fehler (CFrame.Angles(0, 0, rad(90)) hat X nach oben gekippt).
--==========================================================================

local function buildWheel(parent: Instance, name: string, class: VehicleClass, cf: CFrame): Part
	local wheel = Instance.new("Part")
	wheel.Name = name
	wheel.Shape = Enum.PartType.Cylinder
	wheel.Size = Vector3.new(class.WheelWidth, class.WheelRadius * 2, class.WheelRadius * 2)
	wheel.Color = Color3.fromRGB(26, 26, 30)
	wheel.Material = Enum.Material.Rubber
	wheel.TopSurface = Enum.SurfaceType.Smooth
	wheel.BottomSurface = Enum.SurfaceType.Smooth
	wheel.CFrame = cf -- keine Zusatzdrehung, siehe Kommentar oben
	wheel.Parent = parent
	return wheel
end

--==========================================================================
-- KOMPLETTES PLATZHALTERFREIES FAHRZEUG
--==========================================================================

local function buildVehicle(class: VehicleClass): Model
	local model = Instance.new("Model")
	model.Name = ("Vehicle_%s"):format(class.Id)

	local chassis = Instance.new("Part")
	chassis.Name = "Chassis"
	chassis.Size = class.BodySize
	chassis.Transparency = 1
	chassis.CanCollide = true
	chassis.CanQuery = false
	chassis.TopSurface = Enum.SurfaceType.Smooth
	chassis.BottomSurface = Enum.SurfaceType.Smooth
	chassis.Parent = model
	model.PrimaryPart = chassis

	buildBody(model, chassis, class)

	local wheels = Instance.new("Folder")
	wheels.Name = "Wheels"
	wheels.Parent = model

	-- Raeder sitzen unten aussen. Y liegt bewusst UNTER der Karosserie:
	-- die Feder zieht das Chassis danach auf Fahrhoehe.
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
		buildWheel(wheels, slot.name, class, chassis.CFrame * CFrame.new(slot.offset))
	end

	local seat = Instance.new("VehicleSeat")
	seat.Name = "DriveSeat"
	seat.Size = Vector3.new(2.4, 0.4, 2.4)
	seat.CFrame = chassis.CFrame * CFrame.new(0, class.BodySize.Y * 0.2, 0)
	seat.Transparency = 1
	seat.Parent = model

	return model
end

--==========================================================================
-- HUELLE FUER VERKEHR UND POLIZEI
--
-- Dasselbe Aussehen, keine Physik: alles Anchored, keine Constraints, kein
-- Sitz-Prompt. Damit sieht ein Verkehrsauto exakt aus wie ein gekauftes -
-- und beim Kurzschliessen wechselt nichts sichtbar die Form.
--
-- Der Aufrufer positioniert per PivotTo und schaltet an, was er braucht.
--==========================================================================

function VehicleChassis.BuildShell(classId: string): (Model?, VehicleClass?)
	local class = Vehicles.Get(classId)
	if not class then
		return nil, nil
	end

	local model: Model
	if AssetLibrary.Has("Vehicles", class.Asset) then
		model = AssetLibrary.Clone("Vehicles", class.Asset, class.BodySize)
	else
		model = buildVehicle(class)
	end

	-- Der Sitz ist an einer Kulisse nur im Weg: man wuerde sich in ein Auto
	-- setzen, das gar nicht faehrt.
	local seat = model:FindFirstChild("DriveSeat")
	if seat then
		seat:Destroy()
	end

	local pivot = model.PrimaryPart or model:FindFirstChild("Chassis")
	if pivot and pivot:IsA("BasePart") then
		model.PrimaryPart = pivot
	end

	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanTouch = false
			descendant.CanQuery = false
			descendant.CanCollide = descendant == model.PrimaryPart
			descendant.Massless = false
			if descendant ~= model.PrimaryPart then
				descendant.CastShadow = false
			end
		end
	end

	return model, class
end

--==========================================================================
-- Verdrahten
--==========================================================================

local function wireWheel(model: Model, chassis: BasePart, wheel: BasePart, class: VehicleClass)
	local V = Config.Vehicle

	local steered = string.sub(wheel.Name, 1, 1) == "F"
	local driven = string.sub(wheel.Name, 1, 1) == "R"
	local offset = chassis.CFrame:PointToObjectSpace(wheel.Position)
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
	-- FIX (c): Feder und Cylindrical haengen NICHT mehr am selben
	-- Attachment-Paar. Beide bekommen ein eigenes Paar an derselben Stelle.
	-- Zwei Constraints mit eigenen Limits auf einem Attachment-Paar
	-- schaukeln sich gegenseitig auf, bis die Baugruppe explodiert.
	local mount = offset + Vector3.new(0, V.SuspensionLength, 0)

	local springTop = attachment(chassis, wheel.Name .. "_SpringTop", mount, Vector3.new(0, -1, 0), Vector3.new(0, 0, 1))
	local springBottom = attachment(carrier, "SpringHub", Vector3.zero, Vector3.new(0, -1, 0), Vector3.new(0, 0, 1))

	local guideTop = attachment(chassis, wheel.Name .. "_GuideTop", mount, Vector3.new(0, -1, 0), Vector3.new(0, 0, 1))
	local guideBottom = attachment(carrier, "GuideHub", Vector3.zero, Vector3.new(0, -1, 0), Vector3.new(0, 0, 1))

	-- Die Feder liefert NUR Kraft. Keine Limits - die fuehrt der Cylindrical.
	local spring = Instance.new("SpringConstraint")
	spring.Name = wheel.Name .. "_Suspension"
	spring.Attachment0 = springTop
	spring.Attachment1 = springBottom
	spring.FreeLength = V.SuspensionLength
	spring.Stiffness = class.SuspensionStiffness
	spring.Damping = V.SuspensionDamping
	spring.LimitsEnabled = false
	spring.Parent = model

	-- Der Cylindrical fuehrt den Traeger senkrecht, begrenzt den Federweg
	-- und dreht beim Lenken. Er ist der einzige, der Grenzen setzt.
	local steer = Instance.new("CylindricalConstraint")
	steer.Name = if steered then "Steer" else "Guide"
	steer.Attachment0 = guideTop
	steer.Attachment1 = guideBottom
	steer.LimitsEnabled = true
	steer.LowerLimit = math.max(0.1, V.SuspensionLength - V.SuspensionTravel)
	steer.UpperLimit = V.SuspensionLength + V.SuspensionTravel
	steer.ActuatorType = Enum.ActuatorType.None
	steer.AngularActuatorType = Enum.ActuatorType.Servo
	steer.AngularSpeed = V.SteerSpeed * 10
	-- FIX: war class.Acceleration * 4 (bis ~46000 beim Sportwagen). Fuer die
	-- Hochachse eines fast masselosen Traegers voellig ueberzogen - das Rad
	-- hat gezappelt. Ein fester, ausreichender Wert ist hier stabiler.
	steer.ServoMaxTorque = V.SteerServoTorque
	steer.TargetAngle = 0
	steer.Parent = model

	--== Antrieb (seitliche Achse) =========================================
	-- FIX (b): Achse ist die SEITLICHE Achse. Weil das Rad jetzt nicht mehr
	-- fehlrotiert wird, stimmt lokale X von Rad und Traeger ueberein.
	local carrierSide = attachment(carrier, "Axle", Vector3.zero, Vector3.new(side, 0, 0), Vector3.new(0, 1, 0))
	local wheelSide = attachment(wheel, "Hub", Vector3.zero, Vector3.new(side, 0, 0), Vector3.new(0, 1, 0))

	local drive = Instance.new("CylindricalConstraint")
	drive.Name = if driven then "Drive" else "Roll"
	drive.Attachment0 = carrierSide
	drive.Attachment1 = wheelSide
	drive.LimitsEnabled = true
	drive.LowerLimit = 0
	drive.UpperLimit = 0
	drive.ActuatorType = Enum.ActuatorType.None
	drive.AngularActuatorType = Enum.ActuatorType.Motor
	drive.MotorMaxTorque = 0 -- Leerlauf, der Fahrer setzt das
	-- FIX: war math.huge. Unendliche Beschleunigung erzeugt im Solver NaN,
	-- und ein NaN in einer Baugruppe schleudert alle Teile ins Nichts.
	drive.MotorMaxAngularAcceleration = V.MotorMaxAcceleration
	drive.AngularVelocity = 0
	drive.Parent = model

	drive:SetAttribute("Driven", driven)
	steer:SetAttribute("Steered", steered)
	steer:SetAttribute("SideSign", side)
end

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

	--== Echtes Modell hat Vorrang, sonst wird gebaut =====================
	local model: Model
	local fromAsset = false
	if AssetLibrary.Has("Vehicles", class.Asset) then
		model = AssetLibrary.Clone("Vehicles", class.Asset, class.BodySize)
		fromAsset = true
	else
		model = buildVehicle(class)
	end
	model.Name = ("Vehicle_%s"):format(class.Id)

	--== Vertrag pruefen: nur bei Fremdmodellen noetig =====================
	if fromAsset then
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
			warn("           Erwartet: " .. table.concat(required, ", "))
			model:Destroy()
			-- Kein Totalausfall: lieber das gebaute Auto als gar keins.
			model = buildVehicle(class)
			model.Name = ("Vehicle_%s"):format(class.Id)
		end
	end

	local chassis = model:FindFirstChild("Chassis")
	local seat = model:FindFirstChild("DriveSeat")
	local wheelFolder = model:FindFirstChild("Wheels")

	if not (chassis and chassis:IsA("BasePart")) then
		warn(("[GHOSTNET] '%s': Chassis fehlt oder ist kein BasePart."):format(class.Asset))
		model:Destroy()
		return nil
	end
	if not (seat and seat:IsA("VehicleSeat")) then
		warn(("[GHOSTNET] '%s': DriveSeat fehlt oder ist kein VehicleSeat."):format(class.Asset))
		model:Destroy()
		return nil
	end
	if not wheelFolder then
		warn(("[GHOSTNET] '%s': Wheels-Ordner fehlt."):format(class.Asset))
		model:Destroy()
		return nil
	end

	local chassisPart = chassis :: BasePart
	local seatPart = seat :: VehicleSeat

	model.PrimaryPart = chassisPart
	model:PivotTo(cframe)

	--== Chassis: die einzige echte Kollisionsbox ==========================
	chassisPart.Transparency = 1
	chassisPart.CanCollide = true
	chassisPart.CanQuery = false
	chassisPart.Anchored = false
	chassisPart.Massless = false
	chassisPart.CustomPhysicalProperties = physical(class.Mass, 0.3, 0.1)

	--== Sichtbares: dekorativ, nie kollidierend ===========================
	for _, descendant in model:GetDescendants() do
		if not descendant:IsA("BasePart") then
			continue
		end
		if descendant == chassisPart or descendant == seatPart then
			continue
		end
		if descendant:IsDescendantOf(wheelFolder) then
			continue
		end
		makeCosmetic(descendant)
	end

	--== Lackierung: nur die Karosserie, nicht Glas und nicht die Lichter ==
	local bodyParts = model:FindFirstChild("BodyParts")
	local paint = colour or class.Colour
	if bodyParts then
		for _, part in bodyParts:GetChildren() do
			if part:IsA("BasePart") and (part.Name == "Body" or part.Name == "Cabin" or part.Name == "Hood") then
				part.Color = paint
			end
		end
	else
		local body = model:FindFirstChild("Body", true)
		if body and body:IsA("BasePart") then
			body.Color = paint
		end
	end

	--== Sitz ==============================================================
	seatPart.Transparency = 1
	seatPart.CanQuery = false
	seatPart.CanCollide = false
	seatPart.Massless = true
	seatPart.MaxSpeed = class.MaxSpeed
	seatPart.Torque = 0
	seatPart.TurnSpeed = 0

	if not seatPart:FindFirstChild("EnterPrompt") then
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "EnterPrompt"
		prompt.ActionText = "Einsteigen"
		prompt.ObjectText = class.Name
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = Config.Vehicle.EnterRange
		prompt.RequiresLineOfSight = false
		prompt.Parent = seatPart
	end

	--== Schwerpunkt tief ansetzen =========================================
	local ballast = Instance.new("Part")
	ballast.Name = "Ballast"
	ballast.Size = Vector3.new(class.BodySize.X * 0.5, 0.5, class.BodySize.Z * 0.5)
	ballast.Transparency = 1
	ballast.CanCollide = false
	ballast.CanQuery = false
	ballast.CanTouch = false
	ballast.CustomPhysicalProperties = physical(Config.Vehicle.BallastDensity, 0.3, 0)
	ballast.CFrame = chassisPart.CFrame * CFrame.new(0, -Config.Vehicle.BallastDrop, 0)
	ballast.Parent = model

	local ballastWeld = Instance.new("WeldConstraint")
	ballastWeld.Part0 = chassisPart
	ballastWeld.Part1 = ballast
	ballastWeld.Parent = chassisPart

	local seatWeld = Instance.new("WeldConstraint")
	seatWeld.Part0 = chassisPart
	seatWeld.Part1 = seatPart
	seatWeld.Parent = chassisPart

	--== Kosmetik ans Chassis schweissen ===================================
	-- WICHTIG: laeuft VOR wireWheel, damit die spaeter erzeugten Radtraeger
	-- nicht versehentlich mit angeschweisst werden.
	for _, descendant in model:GetDescendants() do
		if not descendant:IsA("BasePart") then
			continue
		end
		if descendant == chassisPart or descendant == seatPart or descendant == ballast then
			continue
		end
		if descendant:IsDescendantOf(wheelFolder) then
			continue
		end
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = chassisPart
		weld.Part1 = descendant
		weld.Parent = chassisPart
	end

	--== Raeder ============================================================
	for _, wheel in wheelFolder:GetChildren() do
		if wheel:IsA("BasePart") then
			wireWheel(model, chassisPart, wheel, class)
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

	model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent

	CollectionService:AddTag(model, Config.VehicleTag)
	model.Parent = container()
	return model
end

--==========================================================================
-- Besitz und Lebenszyklus  (unveraendert gegenueber der alten Version)
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
	local seatPart = seat :: VehicleSeat

	emptySince[model] = os.clock()

	seatPart:GetPropertyChangedSignal("Occupant"):Connect(function()
		local occupant = seatPart.Occupant
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

	print(("[GHOSTNET] VehicleChassis bereit. %d Klassen, Karosserie prozedural."):format(Vehicles.Count()))
end

return VehicleChassis
