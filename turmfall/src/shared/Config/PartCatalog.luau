--!strict
-- PartCatalog: die vier Bauteil-Typen von Turmfall.
--
-- Metadaten (Größe, Dichte, Farbe, Drop-Gewicht) sind der Balancing-Canon
-- und pur testbar; die create()-Funktion baut das physische Modell und wird
-- vom Server (echtes Teil) UND vom Client (Ghost-Preview) benutzt.
--
-- WICHTIG: create() setzt KEINE Network-Ownership - das macht ausschließlich
-- der TowerService beim Platzieren (SetNetworkOwner(nil), siehe dort).

export type PartDef = {
	id: string,
	displayName: string,
	description: string,
	icon: string, -- Emoji für die Hotbar
	dropWeight: number, -- relative Wahrscheinlichkeit bei der Teilvergabe
	size: { x: number, y: number, z: number }, -- Bounding-Box (Studs)
	density: number,
	color: { r: number, g: number, b: number },
}

local PartCatalog = {}

-- Größen in Studs: 1 Rastereinheit = 2 Studs (aus dem Konzept "2x1x2" usw.).
--
-- TEILE-REWORK (D33): Die Drops bestehen fast nur noch aus BAU-freundlichen
-- Teilen (flach, gerade, stapelbar) - Säule/Balken/Fundament sind neu und
-- machen Höhe und Brücken leicht. Schrägkeil und Federblock bleiben als
-- seltene Würze (Risiko/Sabotage), dominieren aber nie wieder die Hotbar.
PartCatalog.Parts = {
	fundament = {
		id = "fundament",
		displayName = "Fundament",
		description = "Breite, flache Platte - der perfekte Boden für jede neue Etage.",
		icon = "🟫",
		dropWeight = 20,
		size = { x = 6, y = 2, z = 6 },
		density = 2,
		color = { r = 128, g = 116, b = 100 },
	},
	saeule = {
		id = "saeule",
		displayName = "Säule",
		description = "Hoch und gerade - +6 Studs Höhe mit einem einzigen Teil!",
		icon = "🏛️",
		dropWeight = 25,
		size = { x = 2, y = 6, z = 2 },
		density = 1,
		color = { r = 214, g = 208, b = 196 },
	},
	balken = {
		id = "balken",
		displayName = "Balken",
		description = "Langer, gerader Träger - überbrückt Lücken und verbindet Türme.",
		icon = "➖",
		dropWeight = 20,
		size = { x = 6, y = 2, z = 2 },
		density = 1,
		color = { r = 168, g = 132, b = 88 },
	},
	schwerblock = {
		id = "schwerblock",
		displayName = "Schwerblock",
		description = "Massiv und träge - die sichere Basis für jeden Turm.",
		icon = "⬛",
		dropWeight = 15,
		size = { x = 4, y = 2, z = 4 },
		density = 4,
		color = { r = 90, g = 94, b = 104 },
	},
	leichtblock = {
		id = "leichtblock",
		displayName = "Leichtblock",
		description = "Klein und leicht - schnell hoch gebaut, schnell gekippt.",
		icon = "⬜",
		dropWeight = 12,
		size = { x = 2, y = 2, z = 2 },
		density = 0.5,
		color = { r = 222, g = 214, b = 190 },
	},
	schraegkeil = {
		id = "schraegkeil",
		displayName = "Schrägkeil",
		description = "45-Grad-Keil - selten, riskant, perfekt für fiese Rampen.",
		icon = "◣",
		dropWeight = 5,
		size = { x = 3, y = 3, z = 3 },
		density = 1.5,
		color = { r = 196, g = 148, b = 88 },
	},
	federblock = {
		id = "federblock",
		displayName = "Federblock",
		description = "Zwei Platten auf einer Feder - selten, wippt und überrascht.",
		icon = "🌀",
		dropWeight = 3,
		size = { x = 2, y = 2.2, z = 2 },
		density = 0.7,
		color = { r = 120, g = 190, b = 150 },
	},
} :: { [string]: PartDef }

-- Teile, die sich gut stapeln lassen (für Tests/Balancing-Checks).
PartCatalog.STACKABLE_IDS = { "fundament", "saeule", "balken", "schwerblock", "leichtblock" }

-- Sortierte IDs für stabile Anzeigen/Verteilungen.
function PartCatalog.getSortedIds(): { string }
	local ids: { string } = {}
	for id in PartCatalog.Parts do
		table.insert(ids, id)
	end
	table.sort(ids)
	return ids
end

-- Kugel-Radius-Näherung eines Teils (für den Kontakt-Check der Schuld-Logik).
function PartCatalog.getApproxRadius(partTypeId: string): number
	local def = PartCatalog.Parts[partTypeId]
	if def == nil then
		return 2
	end
	return math.max(def.size.x, def.size.y, def.size.z) / 2
end

--------------------------------------------------------------------------
-- Modell-Fabrik (Server: echtes Teil, Client: Ghost-Preview)
--------------------------------------------------------------------------

local function applyCommon(part: BasePart, def: PartDef)
	part.Color = Color3.fromRGB(def.color.r, def.color.g, def.color.b)
	part.Material = Enum.Material.SmoothPlastic
	-- GRIFFIGE Physik (D33): hohe Reibung (1) mit hohem Reibungs-Gewicht
	-- und fast keine Elastizität - Teile rutschen nicht mehr voneinander
	-- und federn nicht beim Aufsetzen. DAS macht hohe Türme erst möglich.
	-- Gilt identisch für ALLE Spieler und alle Teile (Fairness).
	part.CustomPhysicalProperties = PhysicalProperties.new(def.density, 1, 0.05, 10, 1)
	part.Anchored = false
	part.CanCollide = true
end

-- Baut das (noch nicht positionierte) Modell eines Teiltyps.
-- Rückgabe: Model mit gesetztem PrimaryPart.
function PartCatalog.create(partTypeId: string): Model
	local def = PartCatalog.Parts[partTypeId]
	assert(def ~= nil, `Unbekannter Teiltyp: {partTypeId}`)

	local model = Instance.new("Model")
	model.Name = def.displayName

	if partTypeId == "schraegkeil" then
		local wedge = Instance.new("WedgePart")
		wedge.Name = "Keil"
		wedge.Size = Vector3.new(def.size.x, def.size.y, def.size.z)
		applyCommon(wedge, def)
		wedge.Parent = model
		model.PrimaryPart = wedge
	elseif partTypeId == "federblock" then
		-- Federblock: untere und obere Platte, verbunden über einen
		-- PrismaticConstraint (führt die Bewegung senkrecht) plus
		-- SpringConstraint (federt) - bewusst leicht instabil.
		local bottom = Instance.new("Part")
		bottom.Name = "Unterteil"
		bottom.Size = Vector3.new(def.size.x, 0.7, def.size.z)
		applyCommon(bottom, def)
		bottom.Parent = model

		local top = Instance.new("Part")
		top.Name = "Oberteil"
		top.Size = Vector3.new(def.size.x, 0.7, def.size.z)
		applyCommon(top, def)
		top.Color = Color3.fromRGB(def.color.r + 20, def.color.g + 20, def.color.b + 20)
		top.CFrame = bottom.CFrame * CFrame.new(0, 1.5, 0)
		top.Parent = model

		-- Achse senkrecht stellen (Attachment-Standardachse wäre X).
		local a0 = Instance.new("Attachment")
		a0.Axis = Vector3.new(0, 1, 0)
		a0.Parent = bottom
		local a1 = Instance.new("Attachment")
		a1.Axis = Vector3.new(0, 1, 0)
		a1.Parent = top

		local prismatic = Instance.new("PrismaticConstraint")
		prismatic.Attachment0 = a0
		prismatic.Attachment1 = a1
		prismatic.LimitsEnabled = true
		prismatic.LowerLimit = 0.6
		prismatic.UpperLimit = 2
		prismatic.Parent = bottom

		local spring = Instance.new("SpringConstraint")
		spring.Attachment0 = a0
		spring.Attachment1 = a1
		spring.FreeLength = 1.5
		spring.Stiffness = 600
		spring.Damping = 12
		spring.Parent = bottom

		model.PrimaryPart = bottom
	else
		local block = Instance.new("Part")
		block.Name = "Block"
		block.Size = Vector3.new(def.size.x, def.size.y, def.size.z)
		applyCommon(block, def)
		block.Parent = model
		model.PrimaryPart = block
	end

	return model
end

return PartCatalog
