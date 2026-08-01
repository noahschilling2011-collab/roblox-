-- ServerScriptService/World/StoryWorld.server.luau
--!strict
-- GHOSTNET :: Die Orte, an denen die Story spielt.
--
-- Hier steht KEINE Spiellogik - nur Parts, Tags und Attribute. Genau wie bei
-- TestTargets: der HackService, der MissionService und der RaidService lesen
-- die Attribute und wissen dann, was zu tun ist.
--
-- Und das Wichtigste: Nichts davon verschwindet nach der Mission. Das
-- Uebungsterminal bleibt stehen, der Laden bleibt aufbrechbar (Cooldown), das
-- Apartment ist ab M03 der Hub, die Bank ab M05 das Endgame-Ziel.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local FOLDER_NAME = "GhostNet_StoryWorld"

if workspace:FindFirstChild(FOLDER_NAME) then
	return -- schon gebaut (z.B. nach einem Studio-Reload)
end

local folder = Instance.new("Folder")
folder.Name = FOLDER_NAME
folder.Parent = workspace

--==========================================================================
-- Bau-Helfer
--==========================================================================

type PartProps = {
	Name: string,
	Size: Vector3,
	CFrame: CFrame,
	Color: Color3,
	Material: Enum.Material?,
	Transparency: number?,
	CanCollide: boolean?,
	Parent: Instance?,
}

local function makePart(props: PartProps): Part
	local p = Instance.new("Part")
	p.Name = props.Name
	p.Size = props.Size
	p.CFrame = props.CFrame
	p.Color = props.Color
	p.Material = props.Material or Enum.Material.SmoothPlastic
	p.Transparency = props.Transparency or 0
	p.CanCollide = if props.CanCollide == nil then true else props.CanCollide
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = props.Parent or folder
	return p
end

local function makeHackable(part: BasePart, attributes: { [string]: any })
	for key, value in attributes do
		part:SetAttribute(key, value)
	end
	part:SetAttribute("Offline", false)
	CollectionService:AddTag(part, Config.HackableTag)
end

-- Unsichtbarer Trigger fuer GOTO-Schritte. Der MissionService prueft die
-- Distanz dazu serverseitig.
local function makeWaypoint(id: string, position: Vector3)
	local p = makePart({
		Name = "WP_" .. id,
		Size = Vector3.new(8, 12, 8),
		CFrame = CFrame.new(position),
		Color = Config.Theme.Cyan,
		Transparency = 1,
		CanCollide = false,
	})
	p.CanQuery = false
	p.CanTouch = false
	p:SetAttribute("WaypointId", id)
	CollectionService:AddTag(p, Config.WaypointTag)
end

-- Ansprechbares Objekt fuer TALK-Schritte.
local function makeContact(part: BasePart, id: string, displayName: string)
	part:SetAttribute("ContactId", id)
	part:SetAttribute("DisplayName", displayName)
	CollectionService:AddTag(part, Config.ContactTag)
end

local function accentLight(part: BasePart, color: Color3, range: number, brightness: number?)
	local light = Instance.new("PointLight")
	light.Color = color
	light.Brightness = brightness or 2
	light.Range = range
	light.Parent = part
end

local function sign(part: BasePart, title: string, subtitle: string, color: Color3, height: number)
	local gui = Instance.new("BillboardGui")
	gui.Name = "Sign"
	gui.Size = UDim2.fromOffset(240, 46)
	gui.StudsOffsetWorldSpace = Vector3.new(0, height, 0)
	gui.MaxDistance = 180

	local head = Instance.new("TextLabel")
	head.BackgroundTransparency = 1
	head.Font = Enum.Font.Code
	head.Text = title
	head.TextColor3 = color
	head.TextSize = 18
	head.Size = UDim2.new(1, 0, 0.6, 0)
	head.Parent = gui

	local sub = Instance.new("TextLabel")
	sub.BackgroundTransparency = 1
	sub.Font = Enum.Font.Code
	sub.Text = subtitle
	sub.TextColor3 = Config.Theme.TextDim
	sub.TextSize = 13
	sub.Position = UDim2.new(0, 0, 0.6, 0)
	sub.Size = UDim2.new(1, 0, 0.4, 0)
	sub.Parent = gui

	gui.Parent = part
end

--==========================================================================
-- 1) UEBUNGSTERMINAL  -  direkt am Spawn, Schwierigkeit 1
-- Erzeugt bewusst KEINEN Trace (Attribut NoTrace): niemand soll auffliegen,
-- bevor er weiss, was der Balken bedeutet. "Teaches" sagt der HackUI, dass
-- sie das Raetsel beim Oeffnen einmal erklaeren soll.
--==========================================================================
do
	local base = Vector3.new(-11, 0, 8)

	makePart({
		Name = "TerminalSockel",
		Size = Vector3.new(3, 3, 2),
		CFrame = CFrame.new(base + Vector3.new(0, 1.5, 0)),
		Color = Color3.fromRGB(26, 30, 38),
		Material = Enum.Material.Metal,
	})

	local screen = makePart({
		Name = "Wartungsterminal",
		Size = Vector3.new(3.2, 2.4, 0.4),
		CFrame = CFrame.new(base + Vector3.new(0, 4, 0)) * CFrame.Angles(math.rad(-12), 0, 0),
		Color = Config.Theme.Cyan,
		Material = Enum.Material.Neon,
	})
	accentLight(screen, Config.Theme.Cyan, 16, 3)

	makeHackable(screen, {
		TargetId = "TUT_TERMINAL",
		DisplayName = "WARTUNGSTERMINAL // uebung",
		Difficulty = 1,
		HackType = "NodeBreach",
		RequiredLevel = 1,
		OnSuccess = "Offline",
		DownTime = 8,
		Cooldown = 20,
		NoTrace = true,
		Teaches = true,
	})

	sign(screen, "UEBUNG", "kein Risiko - einfach ausprobieren", Config.Theme.Cyan, 3.4)
end

--==========================================================================
-- 2) DER LADEN  -  Kreuzung Nord
-- Zwei gestaffelte Ziele in einer Alarm-Gruppe. Schloss startet die Uhr,
-- Tresor stoppt sie. Bleibt nach M02 als wiederholbarer Ueberfall stehen.
--==========================================================================
do
	local base = Vector3.new(-62, 0, -70)

	makeWaypoint("STORE_FRONT", base + Vector3.new(0, 4, 9))

	-- Huelle
	makePart({
		Name = "LadenBoden",
		Size = Vector3.new(24, 1, 18),
		CFrame = CFrame.new(base + Vector3.new(0, 0.5, -2)),
		Color = Color3.fromRGB(22, 25, 31),
		Material = Enum.Material.Concrete,
	})
	makePart({
		Name = "LadenRueckwand",
		Size = Vector3.new(24, 12, 1),
		CFrame = CFrame.new(base + Vector3.new(0, 6, -11)),
		Color = Color3.fromRGB(28, 32, 40),
		Material = Enum.Material.Concrete,
	})
	makePart({
		Name = "LadenWandLinks",
		Size = Vector3.new(1, 12, 18),
		CFrame = CFrame.new(base + Vector3.new(-12, 6, -2)),
		Color = Color3.fromRGB(28, 32, 40),
		Material = Enum.Material.Concrete,
	})
	makePart({
		Name = "LadenWandRechts",
		Size = Vector3.new(1, 12, 18),
		CFrame = CFrame.new(base + Vector3.new(12, 6, -2)),
		Color = Color3.fromRGB(28, 32, 40),
		Material = Enum.Material.Concrete,
	})
	makePart({
		Name = "LadenDach",
		Size = Vector3.new(25, 0.8, 19),
		CFrame = CFrame.new(base + Vector3.new(0, 12, -2)),
		Color = Color3.fromRGB(18, 21, 27),
		Material = Enum.Material.Metal,
	})
	-- Front mit Tueroeffnung
	makePart({
		Name = "LadenFrontLinks",
		Size = Vector3.new(9, 12, 1),
		CFrame = CFrame.new(base + Vector3.new(-7.5, 6, 7)),
		Color = Color3.fromRGB(28, 32, 40),
		Material = Enum.Material.Concrete,
	})
	makePart({
		Name = "LadenFrontRechts",
		Size = Vector3.new(9, 12, 1),
		CFrame = CFrame.new(base + Vector3.new(7.5, 6, 7)),
		Color = Color3.fromRGB(28, 32, 40),
		Material = Enum.Material.Concrete,
	})
	makePart({
		Name = "LadenSturz",
		Size = Vector3.new(6, 3, 1),
		CFrame = CFrame.new(base + Vector3.new(0, 10.5, 7)),
		Color = Color3.fromRGB(28, 32, 40),
		Material = Enum.Material.Concrete,
	})

	-- Ziel 1: Tuerschloss. Startet die Alarm-Uhr.
	local lock = makePart({
		Name = "Tuerschloss",
		Size = Vector3.new(6, 9, 0.7),
		CFrame = CFrame.new(base + Vector3.new(0, 4.5, 7)),
		Color = Color3.fromRGB(20, 26, 34),
		Material = Enum.Material.Metal,
	})
	accentLight(lock, Config.Theme.Amber, 14)
	makeHackable(lock, {
		TargetId = "STORE_LOCK",
		DisplayName = "TUERSCHLOSS // Kreuzung Nord",
		Difficulty = 3,
		HackType = "NodeBreach",
		RequiredLevel = 1,
		OnSuccess = "DoorOpen",
		DownTime = 45, -- lange genug offen, um wirklich reinzukommen
		Cooldown = Config.Raid.StoreCooldown,
		AlarmGroup = "STORE",
		AlarmStarts = true,
	})
	sign(lock, "LADEN", "Notstrom - Schloss zuerst", Config.Theme.Amber, 6)

	-- Ziel 2: Tresor im Inneren. Stoppt die Uhr.
	makePart({
		Name = "TresorSockel",
		Size = Vector3.new(6, 1, 4),
		CFrame = CFrame.new(base + Vector3.new(0, 1.5, -9)),
		Color = Color3.fromRGB(24, 28, 34),
		Material = Enum.Material.Concrete,
	})
	local safe = makePart({
		Name = "Tresor",
		Size = Vector3.new(5, 5, 3.4),
		CFrame = CFrame.new(base + Vector3.new(0, 4.5, -9)),
		Color = Color3.fromRGB(32, 38, 48),
		Material = Enum.Material.Metal,
	})
	accentLight(safe, Config.Theme.Magenta, 14)
	makeHackable(safe, {
		TargetId = "STORE_SAFE",
		DisplayName = "TRESOR // Kreuzung Nord",
		Difficulty = 5,
		HackType = "NodeBreach",
		RequiredLevel = 1,
		OnSuccess = "AtmPayout",
		DownTime = 20,
		Cooldown = Config.Raid.StoreCooldown,
		AlarmGroup = "STORE",
		AlarmEnds = true,
	})
end

--==========================================================================
-- 3) DAS APARTMENT  -  ab M03 der Hub
-- Kein Kulissenraum: hier stehen ab Phase C das Darknet und das Lager.
--==========================================================================
do
	local base = Vector3.new(46, 0, 22)

	makeWaypoint("APARTMENT_DOOR", base + Vector3.new(0, 4, 9))

	makePart({
		Name = "ApartmentBoden",
		Size = Vector3.new(20, 1, 18),
		CFrame = CFrame.new(base + Vector3.new(0, 0.5, 0)),
		Color = Color3.fromRGB(26, 24, 30),
		Material = Enum.Material.WoodPlanks,
	})
	makePart({
		Name = "ApartmentRueckwand",
		Size = Vector3.new(20, 11, 1),
		CFrame = CFrame.new(base + Vector3.new(0, 6, -9)),
		Color = Color3.fromRGB(30, 28, 36),
		Material = Enum.Material.Brick,
	})
	makePart({
		Name = "ApartmentWandLinks",
		Size = Vector3.new(1, 11, 18),
		CFrame = CFrame.new(base + Vector3.new(-10, 6, 0)),
		Color = Color3.fromRGB(30, 28, 36),
		Material = Enum.Material.Brick,
	})
	makePart({
		Name = "ApartmentWandRechts",
		Size = Vector3.new(1, 11, 18),
		CFrame = CFrame.new(base + Vector3.new(10, 6, 0)),
		Color = Color3.fromRGB(30, 28, 36),
		Material = Enum.Material.Brick,
	})
	makePart({
		Name = "ApartmentDach",
		Size = Vector3.new(21, 0.8, 19),
		CFrame = CFrame.new(base + Vector3.new(0, 11, 0)),
		Color = Color3.fromRGB(18, 17, 22),
		Material = Enum.Material.Concrete,
	})
	makePart({
		Name = "ApartmentFrontLinks",
		Size = Vector3.new(7, 11, 1),
		CFrame = CFrame.new(base + Vector3.new(-6.5, 6, 9)),
		Color = Color3.fromRGB(30, 28, 36),
		Material = Enum.Material.Brick,
	})
	makePart({
		Name = "ApartmentFrontRechts",
		Size = Vector3.new(7, 11, 1),
		CFrame = CFrame.new(base + Vector3.new(6.5, 6, 9)),
		Color = Color3.fromRGB(30, 28, 36),
		Material = Enum.Material.Brick,
	})
	makePart({
		Name = "ApartmentSturz",
		Size = Vector3.new(6, 4, 1),
		CFrame = CFrame.new(base + Vector3.new(0, 9, 9)),
		Color = Color3.fromRGB(30, 28, 36),
		Material = Enum.Material.Brick,
	})

	-- Der Rechner. Kontakt fuer TALK-Schritte und ab Phase C der Zugang
	-- zum Darknet.
	makePart({
		Name = "Schreibtisch",
		Size = Vector3.new(8, 0.4, 3),
		CFrame = CFrame.new(base + Vector3.new(0, 3.4, -7)),
		Color = Color3.fromRGB(38, 34, 30),
		Material = Enum.Material.Wood,
	})
	local rig = makePart({
		Name = "Rechner",
		Size = Vector3.new(5.4, 3, 0.5),
		CFrame = CFrame.new(base + Vector3.new(0, 5.2, -7.4)) * CFrame.Angles(math.rad(-8), 0, 0),
		Color = Config.Theme.Cyan,
		Material = Enum.Material.Neon,
	})
	accentLight(rig, Config.Theme.Cyan, 20, 3)
	makeContact(rig, "HOME_RIG", "DEIN RECHNER")
	sign(rig, "RECHNER", "[E] - Darknet", Config.Theme.Cyan, 3)

	makePart({
		Name = "ApartmentLampe",
		Size = Vector3.new(19, 0.3, 0.6),
		CFrame = CFrame.new(base + Vector3.new(0, 10.4, 0)),
		Color = Config.Theme.Amber,
		Material = Enum.Material.Neon,
		CanCollide = false,
	})
end

--==========================================================================
-- 4) NAKAMURA BANK  -  das Grossziel (M05, danach mit langem Cooldown)
-- Drei Stufen in einer Alarm-Gruppe. Der Tresorraum bustet bei Fehlschlag
-- und traegt RequiresTwo: zu zweit halbiert sich Trace und Alarmtempo.
--==========================================================================
do
	local base = Vector3.new(78, 0, -86)

	makeWaypoint("BANK_FRONT", base + Vector3.new(0, 4, 16))

	makePart({
		Name = "BankBoden",
		Size = Vector3.new(34, 1, 30),
		CFrame = CFrame.new(base + Vector3.new(0, 0.5, 0)),
		Color = Color3.fromRGB(20, 22, 28),
		Material = Enum.Material.Marble,
	})
	makePart({
		Name = "BankRueckwand",
		Size = Vector3.new(34, 18, 1),
		CFrame = CFrame.new(base + Vector3.new(0, 9, -15)),
		Color = Color3.fromRGB(26, 29, 36),
		Material = Enum.Material.Concrete,
	})
	makePart({
		Name = "BankWandLinks",
		Size = Vector3.new(1, 18, 30),
		CFrame = CFrame.new(base + Vector3.new(-17, 9, 0)),
		Color = Color3.fromRGB(26, 29, 36),
		Material = Enum.Material.Concrete,
	})
	makePart({
		Name = "BankWandRechts",
		Size = Vector3.new(1, 18, 30),
		CFrame = CFrame.new(base + Vector3.new(17, 9, 0)),
		Color = Color3.fromRGB(26, 29, 36),
		Material = Enum.Material.Concrete,
	})
	makePart({
		Name = "BankDach",
		Size = Vector3.new(35, 1, 31),
		CFrame = CFrame.new(base + Vector3.new(0, 18, 0)),
		Color = Color3.fromRGB(16, 18, 23),
		Material = Enum.Material.Concrete,
	})
	makePart({
		Name = "BankFrontLinks",
		Size = Vector3.new(14, 18, 1),
		CFrame = CFrame.new(base + Vector3.new(-10, 9, 15)),
		Color = Color3.fromRGB(26, 29, 36),
		Material = Enum.Material.Concrete,
	})
	makePart({
		Name = "BankFrontRechts",
		Size = Vector3.new(14, 18, 1),
		CFrame = CFrame.new(base + Vector3.new(10, 9, 15)),
		Color = Color3.fromRGB(26, 29, 36),
		Material = Enum.Material.Concrete,
	})
	makePart({
		Name = "BankSturz",
		Size = Vector3.new(6, 8, 1),
		CFrame = CFrame.new(base + Vector3.new(0, 14, 15)),
		Color = Color3.fromRGB(26, 29, 36),
		Material = Enum.Material.Concrete,
	})

	-- Stufe 1: Aussenkamera. Startet die Uhr.
	makePart({
		Name = "BankKameraArm",
		Size = Vector3.new(0.5, 0.5, 3),
		CFrame = CFrame.new(base + Vector3.new(-6, 15, 16.5)),
		Color = Color3.fromRGB(38, 44, 54),
		Material = Enum.Material.Metal,
	})
	local cam = makePart({
		Name = "Aussenkamera",
		Size = Vector3.new(1.6, 1.6, 3),
		CFrame = CFrame.new(base + Vector3.new(-6, 15, 18)) * CFrame.Angles(math.rad(-20), 0, 0),
		Color = Color3.fromRGB(24, 30, 38),
		Material = Enum.Material.Metal,
	})
	accentLight(cam, Config.Theme.Magenta, 16)
	makeHackable(cam, {
		TargetId = "BANK_CAM",
		DisplayName = "CAM-01 // Nakamura Bank",
		Difficulty = 4,
		HackType = "NodeBreach",
		RequiredLevel = 2,
		OnSuccess = "CameraOffline",
		DownTime = 90,
		Cooldown = Config.Raid.BankCooldown,
		AlarmGroup = "BANK",
		AlarmStarts = true,
	})
	sign(cam, "NAKAMURA BANK", "drei Schichten, ein Alarm", Config.Theme.Magenta, 3.4)

	-- Stufe 2: Sicherheitstuer.
	local door = makePart({
		Name = "BankSicherheitstuer",
		Size = Vector3.new(6, 12, 0.9),
		CFrame = CFrame.new(base + Vector3.new(0, 6, 15)),
		Color = Color3.fromRGB(18, 24, 32),
		Material = Enum.Material.Metal,
	})
	accentLight(door, Config.Theme.Cyan, 14)
	makeHackable(door, {
		TargetId = "BANK_DOOR",
		DisplayName = "SICHERHEITSTUER // Nakamura Bank",
		Difficulty = 6,
		HackType = "NodeBreach",
		RequiredLevel = 2,
		OnSuccess = "DoorOpen",
		DownTime = 60,
		Cooldown = Config.Raid.BankCooldown,
		AlarmGroup = "BANK",
	})

	-- Stufe 3: Tresorraum. Fehlschlag = sofort auffliegen. Zu zweit leichter.
	makePart({
		Name = "TresorraumRahmen",
		Size = Vector3.new(12, 12, 2),
		CFrame = CFrame.new(base + Vector3.new(0, 6, -13)),
		Color = Color3.fromRGB(22, 25, 32),
		Material = Enum.Material.Metal,
	})
	local vault = makePart({
		Name = "Tresorraum",
		Size = Vector3.new(8, 8, 2.6),
		CFrame = CFrame.new(base + Vector3.new(0, 5, -12)),
		Color = Color3.fromRGB(40, 46, 58),
		Material = Enum.Material.DiamondPlate,
	})
	accentLight(vault, Config.Theme.Amber, 20, 3)
	makeHackable(vault, {
		TargetId = "BANK_VAULT",
		DisplayName = "TRESORRAUM // Nakamura Bank",
		Difficulty = 8,
		HackType = "NodeBreach",
		RequiredLevel = 3,
		OnSuccess = "AtmPayout",
		DownTime = 30,
		Cooldown = Config.Raid.BankCooldown,
		AlarmGroup = "BANK",
		AlarmEnds = true,
		FailBusts = true,
		RequiresTwo = true,
	})
	sign(vault, "TRESORRAUM", "Fehlschlag = sofort auffliegen", Config.Theme.Amber, 5)
end

print("[GHOSTNET] Story-Welt gebaut: Uebungsterminal, Laden, Apartment, Nakamura Bank.")
