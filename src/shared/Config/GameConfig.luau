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
	PROFILE_SCHEMA_VERSION = 10, -- v8: PurchaseId-Log; v9: Offline-Earnings; v10: 2x-Boost
	PURCHASE_LOG_LIMIT = 50, -- gemerkte PurchaseIds gegen Doppelgutschrift

	-- Ausrüstung
	BASE_PET_SLOTS = 3, -- gleichzeitig aktive Pets (per Gamepass erweiterbar)
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

	-- Tagesbonus (Energie je aufeinanderfolgendem Login-Tag; Tag 7+ = letzter Wert).
	-- Tag 7 lohnt sich bewusst deutlich (Retention-Anker).
	DAILY_REWARDS = { 50, 100, 150, 250, 400, 600, 1200 },

	-- Offline-Earnings: Anteil des passiven Einkommens, das Biome
	-- waehrend der Abwesenheit "weiterverdienen" (gedeckelt).
	OFFLINE_EARNINGS_RATE = 0.5,
	OFFLINE_EARNINGS_CAP_HOURS = 8,

	-- Freunde-Boost: Bonus auf ALLE Energie-Einnahmen pro Freund, der
	-- gleichzeitig im selben Server spielt (im HUD sichtbar, gedeckelt).
	FRIEND_BOOST_PER_FRIEND = 0.10, -- +10% pro Freund
	FRIEND_BOOST_MAX_FRIENDS = 3, -- Deckel: maximal +30%

	-- Auto-Harvest (Gamepass): Takt des automatischen Einsammelns
	-- (1 Objekt pro Takt; Verkaufen am SellPad bleibt Handarbeit).
	AUTO_HARVEST_INTERVAL_SECONDS = 1,

	-- Spannung & Glücksmomente (variable Belohnungen halten den Loop frisch):
	-- Goldene Objekte: seltener Spawn mit vielfachem Wert und Gold-Optik.
	GOLDEN_OBJECT_CHANCE = 0.05, -- Chance pro Spawn
	GOLDEN_OBJECT_VALUE_FACTOR = 8,
	-- Sammel-Kette: schnelles Sammeln stapelt einen Wert-Bonus.
	COMBO_WINDOW_SECONDS = 3, -- so lange hält die Kette nach dem letzten Fund
	COMBO_BONUS_PER_STACK = 0.02, -- +2% Objektwert pro Ketten-Stufe
	COMBO_MAX_STACKS = 25, -- Deckel: +50%
	-- Kritischer Verkauf: seltener Jackpot-Moment am Verkaufs-Pad.
	CRIT_SALE_CHANCE = 0.1,
	CRIT_SALE_FACTOR = 2,
	-- Meteoriten-Einschlag: Überraschungs-Event auf der eigenen Insel.
	METEOR_CHECK_INTERVAL_SECONDS = 30, -- wie oft pro Spieler gewürfelt wird
	METEOR_CHANCE_PER_CHECK = 0.18, -- ~ alle 2-3 Minuten ein Meteor
	METEOR_CRYSTAL_COUNT = 4, -- Kristalle pro Einschlag
	METEOR_CRYSTAL_VALUE = 25, -- Basis-Energie pro Kristall (Multiplikatoren wirken)
	METEOR_CRYSTAL_LIFETIME_SECONDS = 25, -- danach zerfallen die Kristalle
	METEOR_CLEAR_BONUS = 50, -- Bonus, wenn ALLE Kristalle eingesammelt wurden

	-- Planetenname
	PLANET_NAME_MAX_LENGTH = 24,

	-- Tutorial (First-Time Experience, neuer Loop)
	-- Schritte: 5 sammeln, verkaufen, Upgrade, 2. Biom, Fund-Wurf, 500 Gesamt-Energie
	TUTORIAL_STEP_COUNT = 6,
	TUTORIAL_STEP_REWARDS = { 25, 25, 60, 100, 150, 250 }, -- Energie-Belohnung je Schritt (stockt nie)
	TUTORIAL_LIFETIME_GOAL = 500, -- Ziel von Schritt 6 (Gesamt-Energie)
	TUTORIAL_HINT_LIFETIME_LIMIT = 100, -- Einsteiger-Hinweise verschwinden ab dieser Lifetime-Energie

	-- Sound (Client): zentrale Lautstärke der PlanetForge-Soundgruppe (0..1)
	SOUND_MASTER_VOLUME = 0.5,
}

return GameConfig
