--!strict
-- ProgressionConfig: Insel-Upgrades und (ab Phase 2) die Multiplikator-Formel.
-- Alle Kosten- und Bonuswerte sind hier der Canon.

export type UpgradeDef = {
	id: string,
	displayName: string,
	description: string,
	baseCost: number,
	costFactor: number, -- exponentielles Wachstum pro Stufe
	maxLevel: number,
}

local ProgressionConfig = {}

ProgressionConfig.Upgrades = {
	magnet = {
		id = "magnet",
		displayName = "Magnet",
		description = "Vergrößert deinen Einsammel-Radius.",
		baseCost = 50,
		costFactor = 1.2,
		maxLevel = 25,
	},
	backpack = {
		id = "backpack",
		displayName = "Rucksack",
		description = "Mehr Platz für gesammelte Objekte.",
		baseCost = 40,
		costFactor = 1.2,
		maxLevel = 25,
	},
} :: { [string]: UpgradeDef }

-- Kosten für die nächste Stufe (currentLevel -> currentLevel + 1).
function ProgressionConfig.getUpgradeCost(upgradeId: string, currentLevel: number): number
	local def = ProgressionConfig.Upgrades[upgradeId]
	assert(def ~= nil, `Unbekanntes Upgrade: {upgradeId}`)
	return math.floor(def.baseCost * def.costFactor ^ currentLevel)
end

return ProgressionConfig
