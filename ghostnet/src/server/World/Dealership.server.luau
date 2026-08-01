-- ServerScriptService/World/Dealership.server.luau
--!strict
-- GHOSTNET :: Autohaendler, Garage und die Bezirks-Wegpunkte.
--
-- Der Showroom stellt die Fahrzeuge PHYSISCH aus. Der Spieler geht hin,
-- sieht sie, steigt ein und faehrt eine Runde auf dem abgesperrten Gelaende -
-- das ist deutlich besser als ein Menue mit Bildern und kostet kaum mehr.
--
-- Wie ueberall: nur Parts, Tags und Attribute.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Config = require(ReplicatedStorage.Shared.Config)
local Districts = require(ReplicatedStorage.Shared.Districts)
local Vehicles = require(ReplicatedStorage.Shared.Vehicles)

local VehicleChassis = require(ServerScriptService:WaitForChild("Systems"):WaitForChild("VehicleChassis"))

local FOLDER_NAME = "GhostNet_Dealership"

if workspace:FindFirstChild(FOLDER_NAME) then
	return
end

local folder = Instance.new("Folder")
folder.Name = FOLDER_NAME
folder.Parent = workspace

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

local function waypoint(id: string, position: Vector3)
	local p = part("WP_" .. id, Vector3.new(14, 16, 14), CFrame.new(position), Config.Theme.Cyan, Enum.Material.Neon)
	p.Transparency = 1
	p.CanCollide = false
	p.CanTouch = false
	p:SetAttribute("WaypointId", id)
	CollectionService:AddTag(p, Config.WaypointTag)
end

local function sign(target: BasePart, title: string, subtitle: string, colour: Color3, height: number)
	local gui = Instance.new("BillboardGui")
	gui.Name = "Sign"
	gui.Size = UDim2.fromOffset(260, 48)
	gui.StudsOffsetWorldSpace = Vector3.new(0, height, 0)
	gui.MaxDistance = 200

	local head = Instance.new("TextLabel")
	head.BackgroundTransparency = 1
	head.Font = Enum.Font.Code
	head.Text = title
	head.TextColor3 = colour
	head.TextSize = 18
	head.Size = UDim2.new(1, 0, 0.6, 0)
	head.Parent = gui

	local sub = Instance.new("TextLabel")
	sub.BackgroundTransparency = 1
	sub.Font = Enum.Font.Code
	sub.Text = subtitle
	sub.TextColor3 = Config.Theme.TextDim
	sub.TextSize = 12
	sub.Position = UDim2.new(0, 0, 0.6, 0)
	sub.Size = UDim2.new(1, 0, 0.4, 0)
	sub.Parent = gui

	gui.Parent = target
end

--==========================================================================
-- Autohaendler mit Showroom
--==========================================================================

local dealerBase = Vector3.new(-96, 0, 40)

part(
	"ShowroomBoden",
	Vector3.new(74, 1, 40),
	CFrame.new(dealerBase + Vector3.new(0, 0.5, 0)),
	Config.Palette.InnenBoden,
	Enum.Material.Concrete
).CanCollide = true

part(
	"ShowroomRueckwand",
	Vector3.new(74, 18, 1),
	CFrame.new(dealerBase + Vector3.new(0, 9, -20)),
	Config.Palette.InnenWand,
	Enum.Material.Concrete
).CanCollide = true

part(
	"ShowroomDach",
	Vector3.new(75, 1, 41),
	CFrame.new(dealerBase + Vector3.new(0, 18, 0)),
	Config.Palette.Dach,
	Enum.Material.Metal
).CanCollide = true

local counter = part(
	"HaendlerTresen",
	Vector3.new(12, 4, 3),
	CFrame.new(dealerBase + Vector3.new(0, 2.5, -16)),
	Config.Palette.Metall,
	Enum.Material.Metal
)
counter.CanCollide = true
counter.CanQuery = true
counter:SetAttribute("DisplayName", "AUTOHAUS VANTORRA")
CollectionService:AddTag(counter, Config.DealerTag)
sign(
	counter,
	"AUTOHAUS",
	-- Bei dauerhaftem Tag gibt es keinen Feierabend, auf den das Schild
	-- hinweisen koennte. Sonst stuende hier eine Zeit, die nie eintritt.
	if Config.World.PermanentDay
		then "durchgehend offen"
		else ("offen %d-%d Uhr"):format(Config.Dealer.OpenHour, Config.Dealer.CloseHour),
	Config.Theme.Amber,
	4.5
)

local band = part(
	"HaendlerLeuchtband",
	Vector3.new(74, 0.4, 1.2),
	CFrame.new(dealerBase + Vector3.new(0, 17, -19.4)),
	Config.Theme.Amber,
	Enum.Material.Neon
)
band.CanCollide = false

-- Ausstellungsfahrzeuge: physisch da, einsteigbar, Probefahrt auf dem
-- abgesperrten Gelaende. "Permanent", damit der Aufraeumer sie stehen laesst.
for index, class in Vehicles.List do
	local slot = dealerBase + Vector3.new(-30 + (index - 1) * 15, 3.5, 4)
	local model = VehicleChassis.Build(class.Id, CFrame.new(slot) * CFrame.Angles(0, math.rad(180), 0))
	if model then
		model:SetAttribute("Permanent", true)
		model:SetAttribute("Showroom", true)
		local body = model.PrimaryPart
		if body then
			sign(body, class.Name, ("%d CRY  //  %s"):format(class.Price, class.Blurb), Config.Theme.Cyan, 4)
		end
	end
end

waypoint("DEALER", dealerBase + Vector3.new(0, 6, -10))

--==========================================================================
-- Garage: der eigene Ausparkplatz
--==========================================================================

local garageBase = Vector3.new(46, 0, 44)

part(
	"GarageBoden",
	Vector3.new(26, 1, 22),
	CFrame.new(garageBase + Vector3.new(0, 0.5, 0)),
	Config.Palette.InnenBoden,
	Enum.Material.Concrete
).CanCollide = true

part(
	"GarageDach",
	Vector3.new(27, 1, 23),
	CFrame.new(garageBase + Vector3.new(0, 12, 0)),
	Config.Palette.Dach,
	Enum.Material.Metal
).CanCollide = true

for _, side in { -1, 1 } do
	part(
		"GarageWand",
		Vector3.new(1, 12, 22),
		CFrame.new(garageBase + Vector3.new(side * 13, 6, 0)),
		Config.Palette.InnenBoden,
		Enum.Material.Concrete
	).CanCollide = true
end

local spawnPad = part(
	"Ausparkplatz",
	Vector3.new(16, 0.4, 16),
	CFrame.new(garageBase + Vector3.new(0, 1.2, 0)),
	Config.Theme.Cyan,
	Enum.Material.Neon
)
spawnPad.CanCollide = false
spawnPad.Transparency = 0.65
spawnPad.CanQuery = true
CollectionService:AddTag(spawnPad, Config.VehicleSpawnTag)
sign(spawnPad, "GARAGE", "[G] - Fahrzeug ausparken", Config.Theme.Cyan, 5)

waypoint("GARAGE", garageBase + Vector3.new(0, 6, 0))

--==========================================================================
-- Wegpunkte der Bezirke, damit die Story dorthin zeigen kann
--==========================================================================

local block = Config.City.BlockSize
for _, district in Districts.List do
	local position = Vector3.new(district.GridX * block, 6, district.GridZ * block)
	if district.Id == "DOCKS" then
		waypoint("DOCKS", position)
	elseif district.Id == "HEIGHTS" then
		waypoint("HEIGHTS", position)
	elseif district.Id == "FINANCE" then
		waypoint("FINANCE", position)
	end
end

print("[GHOSTNET] Autohaus, Garage und Bezirks-Wegpunkte gebaut.")
