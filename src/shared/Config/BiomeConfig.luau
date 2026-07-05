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
		description = "Glitzernde Gletscher und ewiger Frost – eiskalt, aber wunderschön.",
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
		description = "Brodelnde Lava und rauchende Krater. Rohe Energie direkt aus dem Planetenkern.",
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
