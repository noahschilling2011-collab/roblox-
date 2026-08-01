-- ServerScriptService/World/Cityscape.server.luau
--!strict
-- GHOSTNET :: Die Stadt drumherum.
--
-- Ersetzt die nackte Baseplate durch eine Strassenzeile bei Tag: helle
-- Fahrbahn, Betonfronten, Glasfenster. Reine Kulisse - kein einziges Objekt
-- hier traegt einen Tag oder eine Spiellogik.
--
-- ALLE FARBEN KOMMEN AUS Config.Palette
--   In dieser Datei steht kein einziger Farbwert mehr. Wer die Stadt heller
--   oder dunkler will, aendert die Palette und sonst nichts.
--
-- SPARSAM MIT EFFEKTEN
--   Ein Hacking-Spiel lebt von Ruhe, nicht von Partikeln. Bei Tageslicht
--   sieht man von PointLights ohnehin fast nichts - deshalb werden sie bei
--   Config.World.PermanentDay gar nicht erst erzeugt. Geschenkte Bildrate.
--
-- LEISTUNG
--   Alles ist anchored, CanQuery und CanTouch sind aus. Wer auf schwachen
--   Geraeten Probleme hat, dreht in Config.World die Anzahl runter oder
--   stellt Lighting.Technology in der Place-Datei auf ShadowMap.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local FOLDER_NAME = "GhostNet_Cityscape"

if workspace:FindFirstChild(FOLDER_NAME) then
	return
end

local folder = Instance.new("Folder")
folder.Name = FOLDER_NAME
folder.Parent = workspace

local rng = Random.new(Config.World.Seed)

local function decor(name: string, size: Vector3, cframe: CFrame, colour: Color3, material: Enum.Material): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cframe
	p.Color = colour
	p.Material = material
	p.Anchored = true
	p.CanCollide = true
	p.CanQuery = false
	p.CanTouch = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = folder
	return p
end

--==========================================================================
-- Fahrbahn
-- Der Glanz kommt ueber Material und Reflectance, nicht ueber eine Textur -
-- es soll keine Asset-Id noetig sein.
--==========================================================================
do
	local road = decor(
		"Fahrbahn",
		Vector3.new(Config.World.RoadWidth, 1, Config.World.RoadLength),
		CFrame.new(0, 0.05, -Config.World.RoadLength * 0.25),
		Config.Palette.Asphalt,
		Enum.Material.Slate
	)
	road.Reflectance = Config.World.RoadReflectance

	-- Mittellinie, matt, damit die Strasse eine Richtung bekommt.
	for i = -Config.World.RoadLength // 2, Config.World.RoadLength // 2, 18 do
		decor(
			"Markierung",
			Vector3.new(0.6, 0.05, 7),
			CFrame.new(0, 0.6, -Config.World.RoadLength * 0.25 + i),
			Config.Palette.Markierung,
			Enum.Material.SmoothPlastic
		)
	end

	-- Gehwege links und rechts.
	for _, side in { -1, 1 } do
		decor(
			"Gehweg",
			Vector3.new(10, 1.4, Config.World.RoadLength),
			CFrame.new(side * (Config.World.RoadWidth * 0.5 + 5), 0.7, -Config.World.RoadLength * 0.25),
			Config.Palette.Gehweg,
			Enum.Material.Concrete
		)
	end
end

--==========================================================================
-- Haeuserfronten mit Neonschildern
--==========================================================================

local NEON_COLOURS = { Config.Theme.Cyan, Config.Theme.Magenta, Config.Theme.Amber }

local function building(x: number, z: number, width: number, depth: number, height: number)
	decor(
		"Haus",
		Vector3.new(width, height, depth),
		CFrame.new(x, height * 0.5, z),
		-- Vielfalt ueber die Mischung zweier Palettentoene statt ueber
		-- freie Zufallsfarben: so bleibt die Zeile bei jeder Palette stimmig.
		Config.Palette.Beton:Lerp(Config.Palette.BetonHell, rng:NextNumber()),
		Enum.Material.Concrete
	)

	-- Fensterbaender. Bei Tag sind das spiegelnde Glasflaechen, keine
	-- Leuchtflaechen - erleuchtete Fenster mittags sehen falsch aus.
	local rows = math.floor(height / 9)
	for row = 1, rows do
		if rng:NextNumber() > Config.World.WindowChance then
			continue
		end
		local glass = decor(
			"Fenster",
			Vector3.new(width * 0.62, 2.2, 0.3),
			CFrame.new(x, row * 9 - 2, z + depth * 0.5 + 0.2),
			Config.Palette.Glas,
			Enum.Material.SmoothPlastic
		)
		glass.Reflectance = Config.World.WindowReflectance
		glass.Transparency = 0.1
	end

	-- Genau ein Neonschild je Haus, mit echtem Licht.
	if rng:NextNumber() < Config.World.SignChance then
		local colour = NEON_COLOURS[rng:NextInteger(1, #NEON_COLOURS)]
		local signPart = decor(
			"Neonschild",
			Vector3.new(0.6, rng:NextInteger(6, 12), 3.4),
			CFrame.new(x + width * 0.5 + 0.4, height * 0.55, z + depth * 0.35),
			colour,
			Enum.Material.Neon
		)
		-- Bei Tageslicht ist ein PointLight praktisch unsichtbar und trotzdem
		-- teuer. Das Schild selbst bleibt, das Licht sparen wir uns.
		if not Config.World.PermanentDay then
			local light = Instance.new("PointLight")
			light.Color = colour
			light.Brightness = Config.World.SignBrightness
			light.Range = Config.World.SignRange
			light.Parent = signPart
		end
	end
end

do
	local halfLength = Config.World.RoadLength * 0.5
	local edge = Config.World.RoadWidth * 0.5 + 10

	for _, side in { -1, 1 } do
		local z = -halfLength * 0.5
		while z < halfLength * 0.5 do
			local width = rng:NextInteger(18, 30)
			local depth = rng:NextInteger(18, 26)
			local height = rng:NextInteger(28, Config.World.MaxBuildingHeight)
			building(side * (edge + depth * 0.5), -Config.World.RoadLength * 0.25 + z, width, depth, height)
			z += width + rng:NextInteger(6, 14)
		end
	end
end

print("[GHOSTNET] Stadtkulisse gebaut.")
