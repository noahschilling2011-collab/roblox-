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
	PROFILE_SCHEMA_VERSION = 4, -- v2: Kosmetik; v3: Tagesbonus/Name; v4: Tutorial
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

	-- Tutorial (First-Time Experience)
	TUTORIAL_STEP_COUNT = 4, -- Schritte: Wiese bauen, Energie sammeln, Upgrade, Fund
	TUTORIAL_STEP_REWARD = 15, -- Energie-Belohnung pro abgeschlossenem Schritt
	TUTORIAL_HINT_LIFETIME_LIMIT = 100, -- Hinweis-Schilder verschwinden ab dieser Lifetime-Energie

	-- Sound (Client): zentrale Lautstärke der PlanetForge-Soundgruppe (0..1)
	SOUND_MASTER_VOLUME = 0.5,
}

return GameConfig
