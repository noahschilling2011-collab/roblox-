-- ServerScriptService/World/City.server.luau
--!strict
-- GHOSTNET :: Vantorra.
--
-- Baut Strassen, Gehwege und Haeuser entlang des Graphen aus RoadNetwork.
-- Reine Geometrie - kein Objekt hier traegt Spiellogik.
--
-- ALLE FARBEN KOMMEN AUS Config.Palette
--   Hier steht kein einziger Farbwert. Die Stadt heller oder dunkler zu
--   machen ist eine Aenderung an der Palette, nicht an diesem Skript.
--
-- LEISTUNGSBUDGET (verbindlich, nicht optional)
--   Alles Dekorative: Anchored, CanQuery = false, CanTouch = false,
--   CastShadow = false bei kleinen Teilen. Fenster sind spiegelnde
--   FLAECHEN, keine Lichtquellen - hunderte PointLights waeren auf dem
--   Handy nicht bezahlbar. Bei Tageslicht sieht man sie ohnehin kaum,
--   deshalb entfallen sie unter Config.World.PermanentDay ganz.
--
--   Nur der als "Dense" markierte Bezirk wird voll ausgebaut. Der Rest bleibt
--   Rohbau, bis er dran ist: eine grosse leere Stadt ist schlimmer als ein
--   kleiner voller Block.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local AssetLibrary = require(ReplicatedStorage.Shared.AssetLibrary)
local Config = require(ReplicatedStorage.Shared.Config)
local Districts = require(ReplicatedStorage.Shared.Districts)

local RoadNetwork = require(ServerScriptService:WaitForChild("Systems"):WaitForChild("RoadNetwork"))

local FOLDER_NAME = "GhostNet_City"

if workspace:FindFirstChild(FOLDER_NAME) then
	return
end

RoadNetwork.Build()

local folder = Instance.new("Folder")
folder.Name = FOLDER_NAME
folder.Parent = workspace

local rng = Random.new(Config.World.Seed)
local C = Config.City
local A = Config.Assets

local function decor(name: string, size: Vector3, cframe: CFrame, colour: Color3, material: Enum.Material, parent: Instance?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cframe
	p.Color = colour
	p.Material = material
	p.Anchored = true
	p.CanQuery = false
	p.CanTouch = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if size.X < 6 and size.Y < 6 and size.Z < 6 then
		p.CastShadow = false
	end
	p.Parent = parent or folder
	return p
end

--==========================================================================
-- Strassen
--==========================================================================

local roads = Instance.new("Folder")
roads.Name = "Strassen"
roads.Parent = folder

local props = Instance.new("Folder")
props.Name = "Moeblierung"
props.Parent = folder

local built: { [string]: boolean } = {}

for _, node in RoadNetwork.All() do
	for _, linkId in node.Links do
		-- Jede Kante nur einmal bauen.
		local edgeKey = if node.Id < linkId
			then ("%d-%d"):format(node.Id, linkId)
			else ("%d-%d"):format(linkId, node.Id)
		if built[edgeKey] then
			continue
		end
		built[edgeKey] = true

		local other = RoadNetwork.Get(linkId)
		if not other then
			continue
		end

		local mid = (node.Position + other.Position) * 0.5
		local delta = other.Position - node.Position
		local length = delta.Magnitude
		local horizontal = math.abs(delta.X) > math.abs(delta.Z)
		local size = if horizontal
			then Vector3.new(length, C.RoadThickness, C.RoadWidth)
			else Vector3.new(C.RoadWidth, C.RoadThickness, length)

		local road = decor("Fahrbahn", size, CFrame.new(mid), Config.Palette.Asphalt, Enum.Material.Slate, roads)
		road.Reflectance = Config.World.RoadReflectance
		road.CanCollide = true

		-- Gehwege links und rechts.
		local sidewalkSize = if horizontal
			then Vector3.new(length, C.SidewalkThickness, C.SidewalkWidth)
			else Vector3.new(C.SidewalkWidth, C.SidewalkThickness, length)
		-- Oberkante = Fahrbahnoberkante + SidewalkLift, daraus die Mitte.
		-- Frueher stand hier eine feste 0.3, zu der nichts passte -
		-- Fussgaenger schwebten oder steckten im Bordstein.
		local sidewalkY = C.RoadThickness * 0.5 + C.SidewalkLift - C.SidewalkThickness * 0.5
		for _, side in { -1, 1 } do
			local offset = if horizontal
				then Vector3.new(0, sidewalkY, side * (C.RoadWidth * 0.5 + C.SidewalkWidth * 0.5))
				else Vector3.new(side * (C.RoadWidth * 0.5 + C.SidewalkWidth * 0.5), sidewalkY, 0)
			local walk = decor(
				"Gehweg",
				sidewalkSize,
				CFrame.new(mid + offset),
				Config.Palette.Gehweg,
				Enum.Material.Concrete,
				roads
			)
			walk.CanCollide = true
		end

		-- Mittelmarkierung, matt. Gibt der Strasse eine Richtung.
		local step = 24
		local count = math.floor(length / step)
		for i = 1, count - 1 do
			local along = node.Position:Lerp(other.Position, i / count)
			decor(
				"Markierung",
				if horizontal then Vector3.new(6, 0.06, 0.6) else Vector3.new(0.6, 0.06, 6),
				CFrame.new(along + Vector3.new(0, 0.55, 0)),
				Config.Palette.Markierung,
				Enum.Material.SmoothPlastic,
				roads
			)
		end
	end
end

--==========================================================================
-- Haeuser aus wiederverwendbaren Modulen
-- Erdgeschoss, Standardetagen, Dachabschluss. Vielfalt ueber Farbe, Hoehe
-- und Schilder - nicht ueber Einzelbauten.
--==========================================================================

local blocks = Instance.new("Folder")
blocks.Name = "Bloecke"
blocks.Parent = folder

-- EIN HAUS IST EIN STAPEL, KEIN KLOTZ.
--
-- Frueher stand hier ein Quader mit Betonmaterial. Ein Quader mit
-- Betonmaterial sieht aus wie ein Quader mit Betonmaterial - da hilft kein
-- Licht und keine Farbe. Ein Gebaeude braucht Gliederung: Sockel,
-- Fensterachsen, Gesimse, Dachkante.
--
-- Also wird gestapelt:  Sockel -> n x Etage -> Dach.
-- Die Module liegen fertig unter Assets/Buildings. Vielfalt entsteht aus
-- Etagenzahl, Modulmischung, Farbe und leichter Drehung - aus acht Modulen
-- bekommt man hunderte unterschiedliche Haeuser.
local function building(centre: Vector3, district: Districts.District, dense: boolean, yaw: number)
	local tint = district.Tint
	local floors = rng:NextInteger(A.MinFloors, if dense then A.MaxFloors else A.MinFloors + 1)

	local model = Instance.new("Model")
	model.Name = ("Haus_%s"):format(district.Id)

	local y = 0

	local function place(name: string, height: number, colour: Color3, overhang: number)
		local size = Vector3.new(A.BuildingFootprint + overhang, height, A.BuildingFootprint + overhang)
		local part = AssetLibrary.Clone("Buildings", name, size)
		part:PivotTo(CFrame.new(centre + Vector3.new(0, y + height * 0.5, 0)) * CFrame.Angles(0, yaw, 0))

		local placeholder = part:GetAttribute("Placeholder") == true
		for _, descendant in part:GetDescendants() do
			if descendant:IsA("BasePart") then
				descendant.Anchored = true
				descendant.CanQuery = false
				descendant.CanTouch = false
				if descendant.Size.X < 6 and descendant.Size.Y < 6 and descendant.Size.Z < 6 then
					descendant.CastShadow = false
				end
				-- Nur Platzhalter und ausdruecklich als toenbar markierte
				-- Teile werden eingefaerbt. Ein fertiges Modul soll seine
				-- eigenen Materialien behalten.
				if placeholder or descendant:GetAttribute("Tintable") == true then
					descendant.Color = colour
				end
			end
		end
		part.Parent = model
		y += height
	end

	-- Sockel dunkler als der Rest: Gebaeude sind unten schmutziger, und ohne
	-- diesen Absatz steht das Haus wie hingestellt statt gewachsen da.
	place(A.Bases[rng:NextInteger(1, #A.Bases)], A.BaseHeight, tint:Lerp(Config.Palette.BetonDunkel, A.BaseDarken), 0)

	for _ = 1, floors do
		place(A.Floors[rng:NextInteger(1, #A.Floors)], A.FloorHeight, tint, 0)
	end

	-- Dachkante steht ueber. Ein Dach buendig mit der Fassade sieht immer
	-- nach Klotz aus - das ist die billigste Verbesserung im ganzen Baukasten.
	place(A.Roofs[rng:NextInteger(1, #A.Roofs)], A.RoofHeight, Config.Palette.Dach, A.RoofOverhang * 2)

	-- Feuerleiter: der Weg nach oben. Ohne die ist das begehbare Dach Deko,
	-- und "von oben" waere im Bankraub kein echter Weg.
	if rng:NextNumber() < A.RoofAccessChance then
		local x = centre.X + A.BuildingFootprint * 0.5 + 1
		for rung = 1, math.floor(y / A.RoofAccessStep) do
			local ladder = AssetLibrary.Clone("Props", A.RoofAccess, A.RoofAccessSize)
			ladder:PivotTo(CFrame.new(x, rung * A.RoofAccessStep, centre.Z))
			for _, descendant in ladder:GetDescendants() do
				if descendant:IsA("BasePart") then
					descendant.Anchored = true
					descendant.CanQuery = false
					descendant.CanTouch = false
					descendant.CanCollide = true
					descendant.CastShadow = false
				end
			end
			ladder.Parent = model
		end
	end

	model.Parent = blocks
end

--==========================================================================
-- STRASSENMOEBLIERUNG
--
-- Eine leere Strasse mit perfekten Haeusern wirkt tot. Eine durchschnittliche
-- Strasse mit Kram darauf wirkt echt. Laternen, Ampeln, Muelltonnen, Poller,
-- Verteilerkaesten, Schilder - das ist der billigste Realismus, den es gibt.
--==========================================================================

local function furnish(from: Vector3, to: Vector3, horizontal: boolean)
	local length = (to - from).Magnitude
	local steps = math.floor(length / A.PropSpacing)
	if steps < 1 then
		return
	end

	-- Kante des Gehwegs, auf beiden Seiten.
	local lateral = C.RoadWidth * 0.5 + C.SidewalkWidth * 0.5
	local top = C.RoadThickness * 0.5 + C.SidewalkLift

	for step = 1, steps - 1 do
		for _, side in { -1, 1 } do
			if rng:NextNumber() > A.PropChance then
				continue
			end
			local along = from:Lerp(to, step / steps)
			local sideways = if horizontal
				then Vector3.new(0, 0, side * lateral)
				else Vector3.new(side * lateral, 0, 0)
			local jitter = if horizontal
				then Vector3.new(rng:NextNumber(-A.PropJitter, A.PropJitter), 0, 0)
				else Vector3.new(0, 0, rng:NextNumber(-A.PropJitter, A.PropJitter))

			local name = A.Props[rng:NextInteger(1, #A.Props)]
			local prop = AssetLibrary.Clone("Props", name, A.PropSize)
			local at = along + sideways + jitter + Vector3.new(0, top + A.PropSize.Y * 0.5, 0)
			prop:PivotTo(CFrame.new(at) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0))

			for _, descendant in prop:GetDescendants() do
				if descendant:IsA("BasePart") then
					descendant.Anchored = true
					descendant.CanQuery = false
					descendant.CanTouch = false
					descendant.CanCollide = false -- man soll nicht am Poller haengenbleiben
					descendant.CastShadow = false
				end
			end
			prop.Parent = props
		end
	end
end

-- Ein Baublock liegt zwischen vier Kreuzungen.
local grid = C.Grid
local half = math.floor(grid / 2)
local inner = C.BlockSize - C.RoadWidth - C.SidewalkWidth * 2 - C.BuildingInset

local denseBlocks, roughBlocks = 0, 0

for gz = -half, half - 1 do
	for gx = -half, half - 1 do
		local district = Districts.At(gx, gz)
		if not district then
			continue
		end

		local centre = Vector3.new((gx + 0.5) * C.BlockSize, 0, (gz + 0.5) * C.BlockSize)
		local dense = district.Dense

		-- Ein Block traegt vier Haeuser statt eines Klotzes: das gibt
		-- Gassen, und Gassen sind fuer Motorrad und Flucht wichtig.
		--
		-- KEINE GLEICHEN ABSTAENDE. Jedes Haus wird ein Stueck versetzt und
		-- minimal gedreht. Ein perfektes Raster sieht immer nach Computer
		-- aus, und genau das faellt sofort auf.
		for _, corner in { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } } do
			local jitter = Vector3.new(
				rng:NextNumber(-A.BuildingJitter, A.BuildingJitter),
				0,
				rng:NextNumber(-A.BuildingJitter, A.BuildingJitter)
			)
			building(
				centre + Vector3.new(corner[1] * inner * 0.25, 0, corner[2] * inner * 0.25) + jitter,
				district,
				dense,
				math.rad(rng:NextNumber(-A.BuildingYaw, A.BuildingYaw))
			)
		end

		if dense then
			denseBlocks += 1
		else
			roughBlocks += 1
		end
	end
end

--==========================================================================
-- Zweiter Durchgang: Moeblierung entlang der Strassen.
-- Bewusst NACH den Haeusern, damit die Props schon wissen, wie hoch der
-- Gehweg liegt, und nicht in einer Fassade landen.
--==========================================================================

local furnished: { [string]: boolean } = {}

for _, node in RoadNetwork.All() do
	for _, linkId in node.Links do
		local edgeKey = if node.Id < linkId
			then ("%d-%d"):format(node.Id, linkId)
			else ("%d-%d"):format(linkId, node.Id)
		if furnished[edgeKey] then
			continue
		end
		furnished[edgeKey] = true

		local other = RoadNetwork.Get(linkId)
		if not other then
			continue
		end
		-- Nur im ausgebauten Bezirk moeblieren. Der Rest ist Rohbau, und
		-- Laternen an einer leeren Flaeche sehen schlimmer aus als nichts.
		local district = RoadNetwork.DistrictAt((node.Position + other.Position) * 0.5)
		if not district or not district.Dense then
			continue
		end

		local delta = other.Position - node.Position
		furnish(node.Position, other.Position, math.abs(delta.X) > math.abs(delta.Z))
	end
end

print(
	("[GHOSTNET] Vantorra gebaut: %d ausgebaute Bloecke, %d im Rohbau, %d Moebel."):format(
		denseBlocks,
		roughBlocks,
		#props:GetChildren()
	)
)
