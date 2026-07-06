--!strict
-- ProgressionConfig: Insel-Upgrades, Multiplikator-Formel und Rebirth-Canon.
--
-- GESAMT-MULTIPLIKATOR (auf jeden Verkaufs- und Passiv-Ertrag):
--   Gesamt = BASE × (1 + Biome-Bonus) × (1 + Upgrade-Bonus)
--            × Pet-Bonus × Rebirth-Multiplikator
--   - Biome-Bonus: jedes freigeschaltete Biom +10%, jedes Biom-Level darüber +5%
--   - Upgrade-Bonus: jede Upgrade-Stufe (Magnet + Rucksack) +2%
--   - Pet-Bonus: Produkt der Boni ausgerüsteter Pets (Phase 3; ohne Pets = 1)
--   - Rebirth: +50% pro Wiedergeburt, stapelnd (0 -> ×1, 1 -> ×1,5, 2 -> ×2 ...)

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

--------------------------------------------------------------------------
-- Multiplikator-Formel (Canon)
--------------------------------------------------------------------------

ProgressionConfig.BASE_MULTIPLIER = 1
ProgressionConfig.BIOME_BONUS_PER_BIOME = 0.10 -- je freigeschaltetes Biom
ProgressionConfig.BIOME_BONUS_PER_LEVEL = 0.05 -- je Biom-Level über Stufe 1
ProgressionConfig.UPGRADE_BONUS_PER_LEVEL = 0.02 -- je Upgrade-Stufe (alle Upgrades)
ProgressionConfig.REBIRTH_BONUS = 0.5 -- +50% pro Wiedergeburt, stapelnd

-- Rebirth-Schwelle: lifetimeEnergy, ab der die nächste Wiedergeburt möglich ist.
-- HINWEIS (Balancing-Vorschlag, bewusst NICHT eigenmächtig geändert):
-- 25.000 ist für den ersten Rebirth in Session 1-2 vermutlich zu hoch.
-- Empfehlung nach erstem Playtest: 5.000-8.000 als Einstiegs-Schwelle testen.
ProgressionConfig.REBIRTH_BASE_THRESHOLD = 25000
ProgressionConfig.REBIRTH_THRESHOLD_FACTOR = 2 -- jede weitere verdoppelt die Schwelle

-- Bonus aus freigeschalteten Biomen und ihren Leveln (0 = kein Bonus).
function ProgressionConfig.getBiomeBonus(biomes: { { biomeId: string, slot: number, level: number, placedAt: number } }): number
	local bonus = 0
	for _, placed in biomes do
		bonus += ProgressionConfig.BIOME_BONUS_PER_BIOME
		bonus += (placed.level - 1) * ProgressionConfig.BIOME_BONUS_PER_LEVEL
	end
	return bonus
end

-- Bonus aus Insel-Upgrades (0 = kein Bonus).
function ProgressionConfig.getUpgradeBonus(upgrades: { [string]: number }): number
	local totalLevels = 0
	for _, level in upgrades do
		totalLevels += level
	end
	return totalLevels * ProgressionConfig.UPGRADE_BONUS_PER_LEVEL
end

-- Permanenter Rebirth-Multiplikator (1 = noch keine Wiedergeburt).
function ProgressionConfig.getRebirthMultiplier(rebirths: number): number
	return 1 + rebirths * ProgressionConfig.REBIRTH_BONUS
end

-- lifetimeEnergy-Schwelle für die nächste Wiedergeburt.
function ProgressionConfig.getRebirthThreshold(rebirths: number): number
	return ProgressionConfig.REBIRTH_BASE_THRESHOLD * ProgressionConfig.REBIRTH_THRESHOLD_FACTOR ^ rebirths
end

-- Gesamt-Multiplikator eines Profils. petBonus kommt aus dem Equip-System
-- (Phase 3); ohne ausgerüstete Pets 1 übergeben.
function ProgressionConfig.getTotalMultiplier(
	biomes: { { biomeId: string, slot: number, level: number, placedAt: number } },
	upgrades: { [string]: number },
	rebirths: number,
	petBonus: number?
): number
	return ProgressionConfig.BASE_MULTIPLIER
		* (1 + ProgressionConfig.getBiomeBonus(biomes))
		* (1 + ProgressionConfig.getUpgradeBonus(upgrades))
		* (petBonus or 1)
		* ProgressionConfig.getRebirthMultiplier(rebirths)
end

return ProgressionConfig
