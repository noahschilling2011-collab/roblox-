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
			then Vector3.new(length, 1, C.RoadWidth)
			else Vector3.new(C.RoadWidth, 1, length)

		local road = decor("Fahrbahn", size, CFrame.new(mid), Config.Palette.Asphalt, Enum.Material.Slate, roads)
		road.Reflectance = Config.World.RoadReflectance
		road.CanCollide = true

		-- Gehwege links und rechts.
		local sidewalkSize = if horizontal
			then Vector3.new(length, 1.4, C.SidewalkWidth)
			else Vector3.new(C.SidewalkWidth, 1.4, length)
		for _, side in { -1, 1 } do
			local offset = if horizontal
				then Vector3.new(0, 0.3, side * (C.RoadWidth * 0.5 + C.SidewalkWidth * 0.5))
				else Vector3.new(side * (C.RoadWidth * 0.5 + C.SidewalkWidth * 0.5), 0.3, 0)
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

local function building(centre: Vector3, footprint: Vector3, district: Districts.District, dense: boolean)
	local height = rng:NextInteger(C.BuildingMinHeight, if dense then C.BuildingMaxHeight else C.BuildingMinHeight + 20)
	local tint = district.Tint

	-- Erdgeschoss: dunkler, mit Schaufensterband.
	decor(
		"Erdgeschoss",
		Vector3.new(footprint.X, 12, footprint.Z),
		CFrame.new(centre + Vector3.new(0, 6, 0)),
		-- Erdgeschoss abgesetzt, aber nicht Richtung Schwarz: bei heller
		-- Stadt wirkt ein schwarzer Sockel wie ein Loch in der Fassade.
		tint:Lerp(Config.Palette.BetonDunkel, 0.55),
		Enum.Material.Concrete,
		blocks
	).CanCollide = true

	-- Standardetagen als ein Block; Fenster als Neonflaechen aufgeklebt.
	decor(
		"Etagen",
		Vector3.new(footprint.X, height - 12, footprint.Z),
		CFrame.new(centre + Vector3.new(0, 12 + (height - 12) * 0.5, 0)),
		tint,
		Enum.Material.Concrete,
		blocks
	).CanCollide = true

	if dense then
		-- Fensterbaender: bei Tag spiegelndes Glas statt leuchtender Neonflaechen.
		local rows = math.floor((height - 14) / 10)
		for row = 1, rows do
			if rng:NextNumber() > Config.World.WindowChance then
				continue
			end
			for _, face in { 1, -1 } do
				local glass = decor(
					"Fenster",
					Vector3.new(footprint.X * 0.7, 2.4, 0.3),
					CFrame.new(centre + Vector3.new(0, 12 + row * 10, face * (footprint.Z * 0.5 + 0.2))),
					Config.Palette.Glas,
					Enum.Material.SmoothPlastic,
					blocks
				)
				glass.Reflectance = Config.World.WindowReflectance
				glass.Transparency = 0.1
			end
		end
	end

	-- Dachabschluss plus begehbares Dach mit Bruestung. Vertikalitaet macht
	-- ein Hacking-Spiel deutlich besser: man kommt von oben an Ziele.
	decor(
		"Dach",
		Vector3.new(footprint.X + 1.5, 1.2, footprint.Z + 1.5),
		CFrame.new(centre + Vector3.new(0, height, 0)),
		Config.Palette.Dach,
		Enum.Material.Metal,
		blocks
	).CanCollide = true

	for _, side in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
		local size = if side[1] ~= 0
			then Vector3.new(0.6, 3, footprint.Z + 1.5)
			else Vector3.new(footprint.X + 1.5, 3, 0.6)
		decor(
			"Bruestung",
			size,
			CFrame.new(centre + Vector3.new(side[1] * footprint.X * 0.5, height + 2, side[2] * footprint.Z * 0.5)),
			Config.Palette.Dach,
			Enum.Material.Metal,
			blocks
		).CanCollide = true
	end

	-- Feuerleiter: der Weg nach oben. Ohne den ist das Dach Deko.
	if rng:NextNumber() < C.RoofAccessChance then
		local x = centre.X + footprint.X * 0.5 + 1
		for y = 4, height, 4 do
			decor(
				"Sprosse",
				Vector3.new(2.6, 0.4, 1.2),
				CFrame.new(x, y, centre.Z),
				Config.Palette.Metall,
				Enum.Material.Metal,
				blocks
			).CanCollide = true
		end
	end

	-- Genau ein Neonschild je Haus, mit echtem Licht. Sparsam.
	if dense and rng:NextNumber() < C.SignChance then
		local sign = decor(
			"Neonschild",
			Vector3.new(0.7, rng:NextInteger(6, 14), 4),
			CFrame.new(centre + Vector3.new(footprint.X * 0.5 + 0.5, height * 0.5, footprint.Z * 0.25)),
			district.Neon,
			Enum.Material.Neon,
			blocks
		)
		-- Bei Tageslicht kostet ein PointLight Bildrate und bringt optisch
		-- nichts. Das Schild bleibt, das Licht entfaellt.
		if not Config.World.PermanentDay and rng:NextNumber() < C.LightChance then
			local light = Instance.new("PointLight")
			light.Color = district.Neon
			light.Brightness = Config.World.SignBrightness
			light.Range = Config.World.SignRange
			light.Parent = sign
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
		local size = inner * 0.44
		for _, corner in { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } } do
			building(
				centre + Vector3.new(corner[1] * inner * 0.25, 0, corner[2] * inner * 0.25),
				Vector3.new(size, 0, size),
				district,
				dense
			)
		end

		if dense then
			denseBlocks += 1
		else
			roughBlocks += 1
		end
	end
end

print(("[GHOSTNET] Vantorra gebaut: %d ausgebaute Bloecke, %d im Rohbau."):format(denseBlocks, roughBlocks))
