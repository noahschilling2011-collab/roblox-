-- ServerScriptService/World/BankInterior.server.luau
--!strict
-- GHOSTNET :: Die Nakamura Bank von innen.
--
-- Alles hier drin ist GEDECKT (kein Attribut Exposed): drinnen zahlt normal
-- und ist sicherer. Der Aufschlag fuer offene Ziele liegt draussen an der
-- Fassade - siehe Config.Cover.
--
-- DREI EBENEN, DREI WEGE HINEIN. Ein Raubzug, der jedes Mal identisch
-- ablaeuft, ist nach dem dritten Mal langweilig.
--
--   1. Schalterhalle    oeffentlich, Wachen mit Sichtkegel, Deckenkameras
--   2. Sicherheitsbereich  nur ueber die gehackte Schleuse
--   3. Tresorraum       Schliessfaecher plus Haupttresor
--
--   Leise    Kameras vorher hacken, Wachen umgehen -> wenig Trace, volle Beute
--   Schnell  direkt zur Schleuse, Alarm sofort -> Wettlauf gegen die Uhr
--   Von oben ueber Dach und Lueftung, umgeht die Halle -> braucht Tier 3
--
-- Wie ueberall: nur Parts, Tags und Attribute. Die Logik liegt in
-- HackService, RaidService und GuardService.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local FOLDER_NAME = "GhostNet_BankInterior"

if workspace:FindFirstChild(FOLDER_NAME) then
	return
end

local folder = Instance.new("Folder")
folder.Name = FOLDER_NAME
folder.Parent = workspace

-- Liegt hinter der bestehenden Bankfassade aus StoryWorld.
local base = Vector3.new(78, 0, -86)

local function part(name: string, size: Vector3, cframe: CFrame, colour: Color3, material: Enum.Material): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cframe
	p.Color = colour
	p.Material = material
	p.Anchored = true
	p.CanQuery = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = folder
	return p
end

local function hackable(target: BasePart, attributes: { [string]: any })
	for key, value in attributes do
		target:SetAttribute(key, value)
	end
	target:SetAttribute("Offline", false)
	target.CanQuery = true
	CollectionService:AddTag(target, Config.HackableTag)
end

local function light(target: BasePart, colour: Color3, range: number)
	local l = Instance.new("PointLight")
	l.Color = colour
	l.Brightness = 2.5
	l.Range = range
	l.Parent = target
end

--==========================================================================
-- 1) SCHALTERHALLE  -  oeffentlich, zwei Wachen, Deckenkameras
--==========================================================================

part(
	"HalleBoden",
	Vector3.new(32, 1, 26),
	CFrame.new(base + Vector3.new(0, 1, 2)),
	Config.Palette.InnenBoden,
	Enum.Material.Marble
)

part(
	"Schaltertresen",
	Vector3.new(22, 4, 2),
	CFrame.new(base + Vector3.new(0, 3.5, -6)),
	Config.Palette.Holz,
	Enum.Material.Wood
)

-- Zwei Deckenkameras. Wer sie vorher knackt, geht den leisen Weg.
for index, offset in { Vector3.new(-11, 15, 8), Vector3.new(11, 15, 8) } do
	local cam = part(
		("HalleKamera%d"):format(index),
		Vector3.new(1.4, 1.4, 2.6),
		CFrame.new(base + offset) * CFrame.Angles(math.rad(-30), 0, 0),
		Config.Palette.MetallDunkel,
		Enum.Material.Metal
	)
	light(cam, Config.Theme.Magenta, 12)
	hackable(cam, {
		TargetId = ("BANK_HALL_CAM%d"):format(index),
		DisplayName = ("HALLENKAMERA %d // Nakamura"):format(index),
		Difficulty = 3,
		RequiredLevel = 2,
		OnSuccess = "CameraOffline",
		DownTime = 120, -- lange genug, um in Ruhe weiterzuarbeiten
		Cooldown = Config.Raid.BankCooldown,
	})
end

-- Zwei Wachen mit Patrouille. Sie melden, sie greifen nicht an.
for index, route in
	{
		{ A = base + Vector3.new(-12, 3, 10), B = base + Vector3.new(-12, 3, -4) },
		{ A = base + Vector3.new(12, 3, -4), B = base + Vector3.new(12, 3, 10) },
	}
do
	local guard = Instance.new("Model")
	guard.Name = ("Wache%d"):format(index)

	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.new(2, 5.6, 1.4)
	root.CFrame = CFrame.new(route.A)
	root.Color = Config.Palette.BetonDunkel
	root.Material = Enum.Material.Fabric
	root.Anchored = true
	root.CanCollide = false
	root.CanQuery = false
	root.Parent = guard
	guard.PrimaryPart = root

	local head = Instance.new("Part")
	head.Name = "Kopf"
	head.Size = Vector3.new(1.2, 1.2, 1.2)
	head.Color = Config.Palette.Haut
	head.Anchored = true
	head.CanCollide = false
	head.CanQuery = false
	head.CastShadow = false
	head.CFrame = root.CFrame * CFrame.new(0, 3.4, 0)
	head.Parent = guard

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = head
	weld.Parent = root

	guard:SetAttribute("PatrolA", route.A)
	guard:SetAttribute("PatrolB", route.B)
	guard:SetAttribute("AlarmGroup", "BANK")
	-- Drinnen sieht man weniger weit als auf der Strasse. Frueher hat das die
	-- Nacht erledigt; seit die Stadt dauerhaft hell ist, macht es der Ort -
	-- und der Ort steht als Attribut am Objekt, nicht im Code.
	guard:SetAttribute("SightFactor", Config.Bank.IndoorSightFactor)
	guard.Parent = folder
	CollectionService:AddTag(guard, Config.GuardTag)
end

--==========================================================================
-- 2) SICHERHEITSBEREICH  -  nur ueber die Schleuse
--==========================================================================

part(
	"SchleusenWand",
	Vector3.new(32, 16, 1.5),
	CFrame.new(base + Vector3.new(0, 8, -9)),
	Config.Palette.Beton,
	Enum.Material.Metal
)

local sluice = part(
	"Schleuse",
	Vector3.new(7, 11, 1),
	CFrame.new(base + Vector3.new(0, 6, -9)),
	Config.Palette.MetallDunkel,
	Enum.Material.DiamondPlate
)
light(sluice, Config.Theme.Cyan, 14)
hackable(sluice, {
	TargetId = "BANK_SLUICE",
	DisplayName = "SCHLEUSE // Sicherheitsbereich",
	Difficulty = 6,
	RequiredLevel = 2,
	OnSuccess = "DoorOpen",
	DownTime = 90,
	Cooldown = Config.Raid.BankCooldown,
	AlarmGroup = "BANK",
	AlarmStarts = true, -- ab hier laeuft die Uhr
})

part(
	"ServerraumBoden",
	Vector3.new(32, 1, 14),
	CFrame.new(base + Vector3.new(0, 1, -17)),
	Config.Palette.InnenBoden,
	Enum.Material.Concrete
)

for index = 1, 4 do
	local rack = part(
		("Serverschrank%d"):format(index),
		Vector3.new(3, 8, 2),
		CFrame.new(base + Vector3.new(-11 + (index - 1) * 7, 5, -20)),
		Config.Palette.MetallDunkel,
		Enum.Material.Metal
	)
	local strip = part(
		("ServerLicht%d"):format(index),
		Vector3.new(2.4, 0.3, 0.2),
		CFrame.new(base + Vector3.new(-11 + (index - 1) * 7, 7.5, -18.9)),
		Config.Theme.Cyan,
		Enum.Material.Neon
	)
	strip.CanCollide = false
	local _ = rack
end

--==========================================================================
-- 3) DER WEG VON OBEN  -  Lueftungsschacht, braucht ein besseres Rig
--==========================================================================

local vent = part(
	"Lueftungsgitter",
	Vector3.new(5, 0.6, 5),
	CFrame.new(base + Vector3.new(0, 18.5, -17)),
	Config.Palette.Metall,
	Enum.Material.DiamondPlate
)
light(vent, Config.Theme.Amber, 10)
hackable(vent, {
	TargetId = "BANK_VENT",
	DisplayName = "LUEFTUNGSGITTER // Dach",
	Difficulty = 5,
	-- Hoeheres Rig noetig, sonst waere der Weg von oben immer die beste Wahl.
	RequiredLevel = Config.Bank.VentRequiredTier,
	OnSuccess = "DoorOpen",
	DownTime = 120,
	Cooldown = Config.Raid.BankCooldown,
	-- Bewusst OHNE AlarmStarts: das ist der Sinn des leisen Wegs.
})

-- Leiter vom Boden aufs Bankdach, damit der obere Weg erreichbar ist.
for y = 4, 18, 4 do
	part(
		"DachLeiter",
		Vector3.new(2.6, 0.4, 1.2),
		CFrame.new(base + Vector3.new(18, y, 12)),
		Config.Palette.Metall,
		Enum.Material.Metal
	).CanCollide = true
end

--==========================================================================
-- 4) TRESORRAUM  -  Schliessfaecher plus Haupttresor
--==========================================================================

part(
	"TresorraumBoden",
	Vector3.new(24, 1, 14),
	CFrame.new(base + Vector3.new(0, 1, -30)),
	Config.Palette.MetallDunkel,
	Enum.Material.Metal
)

-- Mehrere Schliessfaecher: beim schnellen Weg entscheidet die Uhr, wie viele
-- man noch schafft. Genau das macht "schnell" zu einer echten Option.
for index = 1, Config.Bank.VaultBoxes do
	local column = (index - 1) % 3
	local row = math.floor((index - 1) / 3)
	local box = part(
		("Schliessfach%d"):format(index),
		Vector3.new(3, 3, 1),
		CFrame.new(base + Vector3.new(-7 + column * 7, 4 + row * 4, -35)),
		Config.Palette.Metall,
		Enum.Material.Metal
	)
	hackable(box, {
		TargetId = ("BANK_BOX%d"):format(index),
		DisplayName = ("SCHLIESSFACH %d"):format(index),
		Difficulty = 4,
		RequiredLevel = 2,
		Reward = Config.Bank.BoxReward,
		OnSuccess = "AtmPayout",
		DownTime = 20,
		Cooldown = Config.Bank.BoxCooldown,
		AlarmGroup = "BANK",
	})
end

print("[GHOSTNET] Bank-Innenraum gebaut: Halle, Sicherheitsbereich, Tresorraum, Lueftung.")
