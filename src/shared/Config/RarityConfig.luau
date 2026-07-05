--!strict
-- Konfiguration der Seltenheitsstufen und Ultra-Rare-Würfe.
-- Die Gewichte gelten für den normalen Loot-Pool; Mythic und Cosmic haben
-- Gewicht 0 und sind AUSSCHLIESSLICH über die Ultra-Rare-Würfe erhältlich.

export type TierDef = {
	displayName: string,
	color: Color3,
	weight: number,
}

export type UltraRareDef = {
	collectibleId: string,
	oneIn: number,
}

local RarityConfig = {}

-- Reihenfolge von häufig nach selten (für Sortierung und UI).
RarityConfig.TierOrder = {
	"Common",
	"Uncommon",
	"Rare",
	"Epic",
	"Legendary",
	"Mythic",
	"Cosmic",
} :: { string }

RarityConfig.Tiers = {
	Common = {
		displayName = "Gewöhnlich",
		color = Color3.fromRGB(170, 170, 170), -- grau
		weight = 60,
	},
	Uncommon = {
		displayName = "Ungewöhnlich",
		color = Color3.fromRGB(76, 175, 80), -- grün
		weight = 25,
	},
	Rare = {
		displayName = "Selten",
		color = Color3.fromRGB(66, 133, 244), -- blau
		weight = 10,
	},
	Epic = {
		displayName = "Episch",
		color = Color3.fromRGB(156, 39, 176), -- violett
		weight = 4,
	},
	Legendary = {
		displayName = "Legendär",
		color = Color3.fromRGB(255, 152, 0), -- orange
		weight = 1,
	},
	Mythic = {
		displayName = "Mythisch",
		color = Color3.fromRGB(255, 215, 0), -- gold
		weight = 0, -- nicht im normalen Pool
	},
	Cosmic = {
		displayName = "Kosmisch",
		color = Color3.fromRGB(0, 229, 255), -- türkis
		weight = 0, -- nicht im normalen Pool
	},
} :: { [string]: TierDef }

-- Ultra-Rares werden VOR dem normalen Tier-Wurf einzeln gewürfelt,
-- die seltensten zuerst. Loot-Glück verbessert die Chance:
-- effektiv oneIn(max(1, math.floor(n / lootLuckMultiplier))).
RarityConfig.UltraRares = {
	{ collectibleId = "kosmischer_kern", oneIn = 1000000 }, -- Cosmic
	{ collectibleId = "goldener_drache", oneIn = 100000 }, -- Mythic
	{ collectibleId = "kristall", oneIn = 10000 }, -- Legendary
} :: { UltraRareDef }

return RarityConfig
