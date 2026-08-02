-- ServerScriptService/World/TestTargets.server.luau
--!strict
-- GHOSTNET :: Drei Testobjekte und ein Hehler fuer Phase 1.
--
-- Wichtig fuer das Gesamtbild: In diesem Skript steht KEINE Hack-Logik.
-- Es baut Parts und setzt Attribute. Genau so entstehen spaeter auch alle
-- echten Ziele in der Stadt - per Hand im Studio oder per Generator.
--
-- Der Hehler steht bewusst am Spawn und damit ein Stueck von den Zielen weg:
-- Der Rueckweg kostet Zeit, waehrend der Trace weiterlaeuft. Ohne diese
-- Distanz waere Verkaufen keine Entscheidung, sondern nur ein Knopf.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local FOLDER_NAME = "GhostNet_TestTargets"

if workspace:FindFirstChild(FOLDER_NAME) then
	return -- schon gebaut (z.B. nach einem Studio-Reload)
end

local folder = Instance.new("Folder")
folder.Name = FOLDER_NAME
folder.Parent = workspace

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

-- Macht aus einem beliebigen Part ein Hack-Ziel. Nur Attribute, sonst nichts.
local function makeHackable(part: BasePart, attributes: { [string]: any })
	for key, value in attributes do
		part:SetAttribute(key, value)
	end
	part:SetAttribute("Offline", false)
	CollectionService:AddTag(part, Config.HackableTag)
end

local function accentLight(part: BasePart, color: Color3, range: number)
	local light = Instance.new("PointLight")
	light.Color = color
	light.Brightness = 2
	light.Range = range
	light.Parent = part
end

-- Schwebender Text ueber einem Part. Nur Deko und Orientierung.
local function signboard(part: BasePart, title: string, subtitle: string, color: Color3, height: number)
	local gui = Instance.new("BillboardGui")
	gui.Name = "Sign"
	gui.Size = UDim2.fromOffset(220, 46)
	gui.StudsOffsetWorldSpace = Vector3.new(0, height, 0)
	gui.AlwaysOnTop = false
	gui.MaxDistance = 140

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
-- 1) UEBERWACHUNGSKAMERA  -  Schwierigkeit 2
--==========================================================================
do
	local base = Vector3.new(-24, 0, -26)

	makePart({
		Name = "KameraMast",
		Size = Vector3.new(0.8, 12, 0.8),
		CFrame = CFrame.new(base + Vector3.new(0, 6, 0)),
		Color = Config.Palette.Metall,
		Material = Enum.Material.Metal,
	})

	makePart({
		Name = "KameraArm",
		Size = Vector3.new(3.4, 0.5, 0.5),
		CFrame = CFrame.new(base + Vector3.new(1.7, 11.6, 0)),
		Color = Config.Palette.Metall,
		Material = Enum.Material.Metal,
	})

	local head = makePart({
		Name = "Ueberwachungskamera",
		Size = Vector3.new(1.6, 1.6, 3.2),
		CFrame = CFrame.new(base + Vector3.new(3.4, 11.2, 0)) * CFrame.Angles(math.rad(-15), 0, 0),
		Color = Config.Palette.MetallDunkel,
		Material = Enum.Material.Metal,
	})
	accentLight(head, Config.Theme.Magenta, 14)

	makeHackable(head, {
		DisplayName = "CAM-07 // Kreuzung Nord",
		Difficulty = 2,
		HackType = "NodeBreach",
		RequiredLevel = 1,
		OnSuccess = "CameraOffline",
		DownTime = 30,
		-- Haengt an einer Fassade ueber dem Gehweg: jeder sieht einen dabei.
		Exposed = true,
	})
end

--==========================================================================
-- 2) SICHERHEITSTUER  -  Schwierigkeit 4
--==========================================================================
do
	local base = Vector3.new(0, 0, -38)

	makePart({
		Name = "WandLinks",
		Size = Vector3.new(10, 12, 1.2),
		CFrame = CFrame.new(base + Vector3.new(-8, 6, 0)),
		Color = Config.Palette.Beton,
		Material = Enum.Material.Concrete,
	})
	makePart({
		Name = "WandRechts",
		Size = Vector3.new(10, 12, 1.2),
		CFrame = CFrame.new(base + Vector3.new(8, 6, 0)),
		Color = Config.Palette.Beton,
		Material = Enum.Material.Concrete,
	})
	makePart({
		Name = "Sturz",
		Size = Vector3.new(6, 2, 1.2),
		CFrame = CFrame.new(base + Vector3.new(0, 11, 0)),
		Color = Config.Palette.Beton,
		Material = Enum.Material.Concrete,
	})

	local door = makePart({
		Name = "Sicherheitstuer",
		Size = Vector3.new(6, 10, 0.8),
		CFrame = CFrame.new(base + Vector3.new(0, 5, 0)),
		Color = Config.Palette.MetallDunkel,
		Material = Enum.Material.Metal,
	})
	accentLight(door, Config.Theme.Cyan, 12)

	makeHackable(door, {
		-- Kein Exposed: die Tuer liegt an der Rueckseite der Halle. Weniger
		-- Ertrag als der Automat, dafuer sieht einen dort niemand.
		DisplayName = "SEC-DOOR // Lagerhalle B",
		Difficulty = 4,
		HackType = "NodeBreach",
		RequiredLevel = 1,
		OnSuccess = "DoorOpen",
		DownTime = 12,
	})
end

--==========================================================================
-- 3) GELDAUTOMAT  -  Schwierigkeit 6
--==========================================================================
do
	local base = Vector3.new(24, 0, -26)

	makePart({
		Name = "AutomatSockel",
		Size = Vector3.new(5, 1, 3),
		CFrame = CFrame.new(base + Vector3.new(0, 0.5, 0)),
		Color = Config.Palette.BetonDunkel,
		Material = Enum.Material.Concrete,
	})

	local atm = makePart({
		Name = "Geldautomat",
		Size = Vector3.new(4.4, 7, 2.4),
		CFrame = CFrame.new(base + Vector3.new(0, 4.5, 0)),
		Color = Config.Palette.Metall,
		Material = Enum.Material.Metal,
	})

	makePart({
		Name = "AutomatDisplay",
		Size = Vector3.new(3, 2.2, 0.2),
		CFrame = CFrame.new(base + Vector3.new(0, 5.6, 1.25)),
		Color = Config.Theme.Cyan,
		Material = Enum.Material.Neon,
		CanCollide = false,
	})
	accentLight(atm, Config.Theme.Cyan, 16)

	makeHackable(atm, {
		DisplayName = "ATM // Nakamura Bank",
		Difficulty = 6,
		HackType = "NodeBreach",
		RequiredLevel = 1,
		OnSuccess = "AtmPayout",
		Cooldown = 300,
		DownTime = 20,
		-- Steht offen am Gehweg. Das lohnendste Ziel der Uebungszone -
		-- und das, bei dem der Trace am schnellsten hochgeht.
		Exposed = true,
	})
end

--==========================================================================
-- 4) HEHLER  -  hier wird Unverkauftes zu sicherem Guthaben
-- Wie bei den Hack-Zielen gilt: nur ein Part plus Tag. Ein zweiter Hehler
-- irgendwo in der Stadt braucht keine Zeile Code.
--==========================================================================
do
	local base = Vector3.new(0, 0, 20)

	makePart({
		Name = "HehlerRueckwand",
		Size = Vector3.new(12, 9, 1),
		CFrame = CFrame.new(base + Vector3.new(0, 4.5, 2.5)),
		Color = Config.Palette.Beton,
		Material = Enum.Material.Concrete,
	})

	makePart({
		Name = "HehlerDach",
		Size = Vector3.new(13, 0.6, 6),
		CFrame = CFrame.new(base + Vector3.new(0, 9, 0)),
		Color = Config.Palette.Dach,
		Material = Enum.Material.Metal,
	})

	local counter = makePart({
		Name = "Hehler",
		Size = Vector3.new(10, 4, 2.4),
		CFrame = CFrame.new(base + Vector3.new(0, 2, 0)),
		Color = Config.Palette.Metall,
		Material = Enum.Material.Metal,
	})

	makePart({
		Name = "HehlerLeuchtband",
		Size = Vector3.new(10.2, 0.35, 2.6),
		CFrame = CFrame.new(base + Vector3.new(0, 4.1, 0)),
		Color = Config.Theme.Green,
		Material = Enum.Material.Neon,
		CanCollide = false,
	})

	local light = Instance.new("PointLight")
	light.Color = Config.Theme.Green
	light.Brightness = 3
	light.Range = 22
	light.Parent = counter

	counter:SetAttribute("DisplayName", "HEHLER // Kanalgasse")
	CollectionService:AddTag(counter, Config.FenceTag)

	signboard(
		counter,
		"HEHLER",
		("Gebuehr %d%%  //  Trace -%d"):format(math.floor(Config.Sell.FeePercent * 100), Config.Sell.TraceRelief),
		Config.Theme.Green,
		4.6
	)
end

print("[GHOSTNET] Testwelt gebaut: Kamera (D2), Sicherheitstuer (D4), Geldautomat (D6), Hehler am Spawn.")
