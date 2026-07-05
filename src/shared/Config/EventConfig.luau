--!strict
-- Konfiguration der globalen Live-Events (serverweit, alle Spieler gleichzeitig).
-- Der Scheduler (GlobalEventService) würfelt gemäß GameConfig alle
-- EVENT_CHECK_INTERVAL_SECONDS und wählt dann gewichtet aus dieser Liste.
-- Nicht betroffene Multiplikatoren stehen immer auf 1.

export type GlobalEventDef = {
	id: string,
	displayName: string,
	description: string,
	announceText: string,
	durationSeconds: number,
	weight: number,
	energyMultiplier: number,
	lootLuckMultiplier: number,
}

local EventConfig = {}

EventConfig.Events = {
	meteoritenschauer = {
		id = "meteoritenschauer",
		displayName = "Meteoritenschauer",
		description = "Meteoriten mit seltenen Materialien schlagen überall ein. Fund-Glück verdreifacht.",
		announceText = "Meteoritenschauer! Seltene Materialien regnen vom Himmel – Fund-Glück x3!",
		durationSeconds = 300,
		weight = 30,
		energyMultiplier = 1,
		lootLuckMultiplier = 3,
	},
	goldener_regen = {
		id = "goldener_regen",
		displayName = "Goldener Regen",
		description = "Goldene Tropfen laden alle Planeten auf. Sämtliche Energie-Einnahmen verdoppelt.",
		announceText = "Goldener Regen! Alle Energie-Einnahmen sind verdoppelt – sammelt, was das Zeug hält!",
		durationSeconds = 360,
		weight = 25,
		energyMultiplier = 2,
		lootLuckMultiplier = 1,
	},
	kreaturen_spawn = {
		id = "kreaturen_spawn",
		displayName = "Seltene Kreaturen",
		description = "Scheue, seltene Kreaturen zeigen sich überall. Fund-Glück verfünffacht.",
		announceText = "Seltene Kreaturen gesichtet! Fund-Glück x5 – jetzt oder nie!",
		durationSeconds = 300,
		weight = 15,
		energyMultiplier = 1,
		lootLuckMultiplier = 5,
	},
	alien_invasion = {
		id = "alien_invasion",
		displayName = "Alien-Invasion",
		description = "Außerirdische Besucher bringen Chaos und Beute: Energie x1.5 und Fund-Glück x1.5.",
		announceText = "Alien-Invasion! Die Besucher bringen Energie x1.5 UND Fund-Glück x1.5 mit!",
		durationSeconds = 480,
		weight = 20,
		energyMultiplier = 1.5,
		lootLuckMultiplier = 1.5,
	},
	schwarzes_loch = {
		id = "schwarzes_loch",
		displayName = "Schwarzes Loch",
		description = "Ein Schwarzes Loch verzerrt Raum und Zeit. Alle Energie-Einnahmen verdreifacht.",
		announceText = "Ein Schwarzes Loch ist aufgetaucht! 10 Minuten lang Energie x3 – haltet euch fest!",
		durationSeconds = 600,
		weight = 10,
		energyMultiplier = 3,
		lootLuckMultiplier = 1,
	},
} :: { [string]: GlobalEventDef }

return EventConfig
