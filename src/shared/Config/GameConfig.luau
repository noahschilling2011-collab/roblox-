--!strict
-- Globale Spielkonstanten. Balancing-Werte bitte hier ändern, nicht in den Services.

local GameConfig = {
	-- Planet
	PLANET_SLOTS = 12, -- Anzahl Biom-Slots pro Planet
	PLOT_SPACING_STUDS = 512, -- Abstand zwischen Spielerplaneten in der Welt
	PLOT_HEIGHT_STUDS = 120, -- Höhe der schwebenden Planeten über dem Ursprung

	-- Energie
	START_ENERGY = 50,
	COLLECT_AMOUNT = 5, -- Energie pro manuellem Einsammeln
	COLLECT_COOLDOWN_SECONDS = 6,
	PASSIVE_INCOME_INTERVAL_SECONDS = 60, -- Taktung des passiven Biom-Einkommens

	-- Loot
	LOOT_ROLL_COST = 25, -- Energiekosten pro Fund-Wurf

	-- Handel
	MAX_TRADE_ITEMS_PER_SIDE = 4,
	TRADE_LOCK_SECONDS = 3, -- Sicherheitspause nach beidseitigem Akzeptieren

	-- Daten
	PROFILE_SCHEMA_VERSION = 1,
	DATASTORE_NAME = "PlanetForge_v1",
	AUTOSAVE_INTERVAL_SECONDS = 120,

	-- Globale Events
	EVENT_CHECK_INTERVAL_SECONDS = 60, -- wie oft der Event-Scheduler würfelt
	EVENT_MIN_GAP_SECONDS = 15 * 60, -- Mindestabstand zwischen zwei globalen Events
	EVENT_START_CHANCE = 0.25, -- Chance pro Prüfintervall, dass ein Event startet
}

return GameConfig
