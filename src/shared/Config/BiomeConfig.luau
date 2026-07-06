--!strict
-- Konfiguration aller Biome, die auf einem Planeten platziert werden können.
-- Balancing-Canon: Kosten, Freischaltungsschwellen und Einkommenswerte hier
-- ändern, nicht in den Services.

export type BiomeDef = {
	id: string,
	displayName: string,
	description: string,
	baseCost: number,
	upgradeCostMultiplier: number,
	baseEnergyPerMinute: number,
	maxLevel: number,
	color: Color3,
	unlockAtLifetimeEnergy: number,
}

-- Für alle Biome identisch (Canon).
local MAX_LEVEL = 5
local UPGRADE_COST_MULTIPLIER = 1.75

local BiomeConfig = {}

BiomeConfig.Biomes = {
	wiese = {
		id = "wiese",
		displayName = "Wiese",
		description = "Saftiges Gras und erste Blumen – der bescheidene Anfang jedes Planeten.",
		baseCost = 25,
		upgradeCostMultiplier = UPGRADE_COST_MULTIPLIER,
		baseEnergyPerMinute = 1,
		maxLevel = MAX_LEVEL,
		color = Color3.fromRGB(124, 200, 84),
		unlockAtLifetimeEnergy = 0,
	},
	wald = {
		id = "wald",
		displayName = "Wald",
		description = "Dichte Baumkronen voller Leben. Hier raschelt es an jeder Ecke.",
		baseCost = 100,
		upgradeCostMultiplier = UPGRADE_COST_MULTIPLIER,
		baseEnergyPerMinute = 2,
		maxLevel = MAX_LEVEL,
		color = Color3.fromRGB(34, 120, 45),
		unlockAtLifetimeEnergy = 0,
	},
	wueste = {
		id = "wueste",
		displayName = "Wüste",
		description = "Endlose Dünen unter glühender Sonne. Karg, aber voller verborgener Schätze.",
		baseCost = 250,
		upgradeCostMultiplier = UPGRADE_COST_MULTIPLIER,
		baseEnergyPerMinute = 4,
		maxLevel = MAX_LEVEL,
		color = Color3.fromRGB(230, 195, 120),
		unlockAtLifetimeEnergy = 500,
	},
	ozean = {
		id = "ozean",
		displayName = "Ozean",
		description = "Tiefblaues Wasser, das deinen Planeten zum Leuchten bringt.",
		baseCost = 500,
		upgradeCostMultiplier = UPGRADE_COST_MULTIPLIER,
		baseEnergyPerMinute = 8,
		maxLevel = MAX_LEVEL,
		color = Color3.fromRGB(30, 110, 200),
		unlockAtLifetimeEnergy = 1000,
	},
	dschungel = {
		id = "dschungel",
		displayName = "Dschungel",
		description = "Undurchdringliches Grün voller exotischer Rufe und seltener Kreaturen.",
		baseCost = 1000,
		upgradeCostMultiplier = UPGRADE_COST_MULTIPLIER,
		baseEnergyPerMinute = 15,
		maxLevel = MAX_LEVEL,
		color = Color3.fromRGB(18, 150, 72),
		unlockAtLifetimeEnergy = 2500,
	},
	eiswelt = {
		id = "eiswelt",
		displayName = "Eiswelt",
		description = "Glitzernde Gletscher und ewiger Frost. Eissplitter schmelzen schnell – sei flink!",
		baseCost = 2500,
		upgradeCostMultiplier = UPGRADE_COST_MULTIPLIER,
		baseEnergyPerMinute = 30,
		maxLevel = MAX_LEVEL,
		color = Color3.fromRGB(170, 225, 250),
		unlockAtLifetimeEnergy = 5000,
	},
	vulkan = {
		id = "vulkan",
		displayName = "Vulkan",
		description = "Brodelnde Lava und rauchende Krater. Glutsteine musst du erst abkühlen lassen!",
		baseCost = 5000,
		upgradeCostMultiplier = UPGRADE_COST_MULTIPLIER,
		baseEnergyPerMinute = 60,
		maxLevel = MAX_LEVEL,
		color = Color3.fromRGB(200, 60, 30),
		unlockAtLifetimeEnergy = 10000,
	},
	pilzwald = {
		id = "pilzwald",
		displayName = "Pilzwald",
		description = "Riesige, leuchtende Pilze in schillernden Farben – ein Wald wie aus einem Traum.",
		baseCost = 10000,
		upgradeCostMultiplier = UPGRADE_COST_MULTIPLIER,
		baseEnergyPerMinute = 120,
		maxLevel = MAX_LEVEL,
		color = Color3.fromRGB(170, 90, 200),
		unlockAtLifetimeEnergy = 25000,
	},
	kristallfelder = {
		id = "kristallfelder",
		displayName = "Kristallfelder",
		description = "Felder aus singenden Kristallen, die pure Energie in den Himmel strahlen.",
		baseCost = 25000,
		upgradeCostMultiplier = UPGRADE_COST_MULTIPLIER,
		baseEnergyPerMinute = 250,
		maxLevel = MAX_LEVEL,
		color = Color3.fromRGB(90, 230, 220),
		unlockAtLifetimeEnergy = 50000,
	},
	kosmische_ebene = {
		id = "kosmische_ebene",
		displayName = "Kosmische Ebene",
		description = "Ein Riss ins Universum selbst: Sterne, Nebel und unendliche Kraft.",
		baseCost = 100000,
		upgradeCostMultiplier = UPGRADE_COST_MULTIPLIER,
		baseEnergyPerMinute = 600,
		maxLevel = MAX_LEVEL,
		color = Color3.fromRGB(120, 80, 255),
		unlockAtLifetimeEnergy = 250000,
	},
} :: { [string]: BiomeDef }

-- Sammel-Objekte, die in der Zone eines Bioms spawnen (physischer Loop):
-- Spawn-Rate (respawnSeconds) und Max-Anzahl (maxActive + Level-Bonus) sind
-- hier der Canon, nicht in den Services.
--
-- Biom-Spezialmechaniken (optional, macht die Biome spielerisch verschieden):
--   meltSeconds - Objekt schmilzt nach dieser Zeit und verschwindet (Eiswelt:
--                 wer schnell ist, kriegt mehr; der Wert ist dafür höher).
--   hotSeconds  - Objekt ist nach dem Spawn so lange glühend heiß und kann
--                 NICHT eingesammelt werden (Vulkan: Timing statt Schaden,
--                 bewusst kinderfreundlich).
export type HarvestDef = {
	label: string, -- Anzeigename des Sammel-Objekts
	value: number, -- Rucksack-Wert pro Objekt
	maxActive: number, -- gleichzeitig liegende Objekte bei Level 1
	respawnSeconds: number, -- Mindestabstand zwischen zwei Spawns
	orb: boolean, -- true = schwebender Energie-Orb, false = Boden-Objekt
	color: Color3,
	meltSeconds: number?, -- Eis-Mechanik: Lebenszeit bis zum Schmelzen
	hotSeconds: number?, -- Vulkan-Mechanik: Abkühlzeit bis sammelbar
}

BiomeConfig.Harvest = {
	wiese = { label = "Gras-Büschel", value = 1, maxActive = 6, respawnSeconds = 3, orb = false, color = Color3.fromRGB(110, 190, 80) },
	wald = { label = "Waldbeere", value = 2, maxActive = 6, respawnSeconds = 4, orb = false, color = Color3.fromRGB(150, 60, 90) },
	wueste = { label = "Sandkristall", value = 4, maxActive = 5, respawnSeconds = 4, orb = false, color = Color3.fromRGB(235, 205, 130) },
	ozean = { label = "Muschel", value = 8, maxActive = 5, respawnSeconds = 5, orb = false, color = Color3.fromRGB(200, 225, 240) },
	dschungel = { label = "Dschungelfrucht", value = 15, maxActive = 5, respawnSeconds = 5, orb = false, color = Color3.fromRGB(240, 150, 50) },
	eiswelt = { label = "Eissplitter", value = 30, maxActive = 4, respawnSeconds = 6, orb = false, color = Color3.fromRGB(180, 230, 250), meltSeconds = 12 },
	vulkan = { label = "Glutstein", value = 60, maxActive = 4, respawnSeconds = 6, orb = false, color = Color3.fromRGB(255, 110, 40), hotSeconds = 4 },
	pilzwald = { label = "Leuchtpilz", value = 120, maxActive = 4, respawnSeconds = 7, orb = false, color = Color3.fromRGB(200, 120, 230) },
	kristallfelder = { label = "Kristall-Orb", value = 250, maxActive = 3, respawnSeconds = 8, orb = true, color = Color3.fromRGB(110, 235, 225) },
	kosmische_ebene = { label = "Sternen-Orb", value = 600, maxActive = 3, respawnSeconds = 9, orb = true, color = Color3.fromRGB(255, 235, 150) },
} :: { [string]: HarvestDef }

-- Maximale gleichzeitige Objekte einer Zone (steigt mit dem Biom-Level).
function BiomeConfig.getMaxActive(biomeId: string, level: number): number
	local harvest = BiomeConfig.Harvest[biomeId]
	if harvest == nil then
		return 0
	end
	return harvest.maxActive + (level - 1) * 2
end

-- Gibt alle Biom-IDs sortiert nach baseCost (aufsteigend) zurück.
function BiomeConfig.getSortedIds(): { string }
	local ids: { string } = {}
	for id in BiomeConfig.Biomes do
		table.insert(ids, id)
	end
	table.sort(ids, function(a, b)
		return BiomeConfig.Biomes[a].baseCost < BiomeConfig.Biomes[b].baseCost
	end)
	return ids
end

-- Upgrade-Kosten von Level `currentLevel` auf `currentLevel + 1`:
-- baseCost * upgradeCostMultiplier ^ currentLevel, abgerundet.
function BiomeConfig.getUpgradeCost(biomeId: string, currentLevel: number): number
	local def = BiomeConfig.Biomes[biomeId]
	assert(def ~= nil, `Unbekanntes Biom: {biomeId}`)
	return math.floor(def.baseCost * def.upgradeCostMultiplier ^ currentLevel)
end

return BiomeConfig
