--!strict
-- Gemeinsame Typdefinitionen für Planet Forge.
-- Diese Typen beschreiben das Datenmodell eines Spielerplaneten und werden
-- von Server und Client gleichermaßen verwendet.

export type BiomeId = string
export type CollectibleId = string
export type GlobalEventId = string
export type CosmeticId = string

-- Kategorien kaufbarer Kosmetik (nur Optik, niemals Spielvorteile).
export type CosmeticCategory = "skin" | "aura" | "wetter" | "haustier"

export type RarityTier = "Common" | "Uncommon" | "Rare" | "Epic" | "Legendary" | "Mythic" | "Cosmic"

-- Ein auf dem Planeten platziertes Biom (belegt genau einen Slot).
export type PlacedBiome = {
	biomeId: BiomeId,
	slot: number, -- 1 .. GameConfig.PLANET_SLOTS
	level: number, -- Ausbaustufe, 1 .. BiomeConfig.Biomes[biomeId].maxLevel
	placedAt: number, -- Unix-Zeitstempel (os.time())
}

-- Ein konkretes Sammelobjekt im Besitz eines Spielers.
-- `uid` identifiziert die Instanz eindeutig (wichtig für den Handel).
export type OwnedCollectible = {
	uid: string,
	collectibleId: CollectibleId,
	obtainedAt: number,
	source: "loot" | "event" | "trade",
}

-- Persistenter Spielstand eines Spielers.
export type PlayerProfile = {
	version: number, -- Schema-Version für spätere Migrationen
	energy: number,
	lifetimeEnergy: number, -- insgesamt jemals verdiente Energie (steuert Freischaltungen)
	biomes: { PlacedBiome },
	collectibles: { OwnedCollectible },
	visits: number, -- wie oft dieser Planet besucht wurde
	likes: number, -- Bewertungen anderer Spieler
	createdAt: number,
	ownedCosmetics: { CosmeticId }, -- per Robux freigeschaltete Kosmetik
	equippedCosmetics: { [string]: CosmeticId }, -- Kategorie -> ausgerüstete Kosmetik
	planetName: string, -- vom Spieler vergebener, gefilterter Name ("" = Standard)
	dailyStreak: number, -- aufeinanderfolgende Login-Tage (Tagesbonus)
	lastDailyClaimDay: number, -- UTC-Tagesnummer des letzten Tagesbonus (os.time() / 86400)
	tutorialStep: number, -- nächster offener Tutorial-Schritt (1..4); 5 = abgeschlossen
}

-- Ein aktuell laufendes globales Event.
export type ActiveGlobalEvent = {
	eventId: GlobalEventId,
	startedAt: number,
	endsAt: number,
}

-- Eine Seite einer Handelssitzung.
export type TradeSide = {
	userId: number,
	offeredUids: { string }, -- uids aus OwnedCollectible
	offeredEnergy: number,
	accepted: boolean,
}

-- Zustand einer Handelssitzung zwischen genau zwei Spielern.
export type TradeSession = {
	id: string,
	sides: { TradeSide }, -- immer genau 2 Einträge
	state: "negotiating" | "locked" | "completed" | "cancelled",
	createdAt: number,
}

return {}
