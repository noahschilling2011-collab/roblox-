--!strict
-- Globale Spielkonstanten. Balancing-Werte bitte hier ändern, nicht in den Services.

local GameConfig = {
	-- Planet
	PLANET_SLOTS = 12, -- Anzahl Biom-Slots pro Planet
	PLOT_SPACING_STUDS = 512, -- Abstand zwischen Spielerplaneten in der Welt
	PLOT_HEIGHT_STUDS = 120, -- Höhe der schwebenden Planeten über dem Ursprung

	-- Energie
	START_ENERGY = 50,
	PASSIVE_INCOME_INTERVAL_SECONDS = 60, -- Taktung des passiven Biom-Einkommens

	-- Physisches Sammeln auf der Insel
	BASE_MAGNET_RADIUS = 6, -- Einsammel-Radius ohne Upgrades (Studs)
	MAGNET_RADIUS_PER_LEVEL = 1.5, -- zusätzlicher Radius pro Magnet-Upgrade
	BASE_BACKPACK_CAPACITY = 30, -- Rucksack-Plätze ohne Upgrades
	BACKPACK_CAPACITY_PER_LEVEL = 15, -- zusätzliche Plätze pro Rucksack-Upgrade
	HARVEST_TICK_SECONDS = 0.25, -- Takt der serverseitigen Näherungs-Prüfung
	SPAWN_TICK_SECONDS = 1, -- Takt des Objekt-Spawners
	SELL_PAD_RADIUS = 9, -- Reichweite der Verkaufs-Zone (Studs)

	-- Loot
	LOOT_ROLL_COST = 25, -- Energiekosten pro Fund-Wurf

	-- Handel
	MAX_TRADE_ITEMS_PER_SIDE = 4,
	TRADE_LOCK_SECONDS = 3, -- Sicherheitspause nach beidseitigem Akzeptieren

	-- Daten
	PROFILE_SCHEMA_VERSION = 5, -- v4: Tutorial; v5: Rucksack/Upgrades/Statistiken (Insel-Loop)
	DATASTORE_NAME = "PlanetForge_v1",
	AUTOSAVE_INTERVAL_SECONDS = 120,

	-- Globale Events
	EVENT_CHECK_INTERVAL_SECONDS = 60, -- wie oft der Event-Scheduler würfelt
	EVENT_MIN_GAP_SECONDS = 15 * 60, -- Mindestabstand zwischen zwei globalen Events
	EVENT_START_CHANCE = 0.25, -- Chance pro Prüfintervall, dass ein Event startet

	-- Rangliste
	LEADERBOARD_REFRESH_SECONDS = 120, -- Schreib- und Lese-Takt der globalen Ranglisten
	LEADERBOARD_TOP_N = 20, -- Anzahl der angezeigten Plätze
	LEADERBOARD_STORE_LIKES = "PF_Rangliste_Likes_v1",
	LEADERBOARD_STORE_ENERGY = "PF_Rangliste_Energie_v1",

	-- Tagesbonus (Energie je aufeinanderfolgendem Login-Tag; Tag 7+ = letzter Wert)
	DAILY_REWARDS = { 50, 100, 150, 250, 350, 450, 600 },

	-- Planetenname
	PLANET_NAME_MAX_LENGTH = 24,

	-- Tutorial (First-Time Experience, neuer Loop)
	TUTORIAL_STEP_COUNT = 4, -- Schritte: 5 sammeln, verkaufen, Upgrade kaufen, Biom freischalten
	TUTORIAL_STEP_REWARDS = { 25, 25, 60, 100 }, -- Energie-Belohnung je Schritt (stockt nie)
	TUTORIAL_HINT_LIFETIME_LIMIT = 100, -- Einsteiger-Hinweise verschwinden ab dieser Lifetime-Energie

	-- Sound (Client): zentrale Lautstärke der PlanetForge-Soundgruppe (0..1)
	SOUND_MASTER_VOLUME = 0.5,
}

return GameConfig
