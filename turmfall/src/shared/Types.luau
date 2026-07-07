--!strict
-- Gemeinsame Typdefinitionen für Turmfall (Server und Client).

-- Rundenphasen der Server-StateMachine (RoundService = Source of Truth).
export type RoundPhase = "Lobby" | "Aufbau" | "Bauphase" | "Wertung"

-- IDs der Bauteil-Typen (PartCatalog).
export type PartTypeId =
	"fundament"
	| "saeule"
	| "balken"
	| "schwerblock"
	| "leichtblock"
	| "schraegkeil"
	| "federblock"

-- Ein Eintrag im Platzierungs-Log (Schuld-System).
export type PlacementRecord = {
	pieceId: number,
	ownerUserId: number,
	placedAt: number, -- os.clock() beim Platzieren
}

-- Position eines Teils als einfache Tabelle (Ringpuffer/Replay sind
-- bewusst Roblox-frei, damit die Schuld-Logik pur testbar ist).
export type Vec3 = { x: number, y: number, z: number }

-- Ein Ringpuffer-Sample: Zeitstempel + Positionen aller lebenden Teile.
export type RingSample = {
	t: number,
	positions: { [number]: Vec3 }, -- pieceId -> Position
}

-- Replay-Daten, die beim Kollaps an alle Clients gehen.
export type ReplayPieceInfo = {
	partTypeId: string,
	ownerUserId: number,
}

export type ReplayData = {
	samples: { RingSample }, -- nur die letzten REPLAY_SECONDS, nur Kaskaden-Teile
	pieces: { [number]: ReplayPieceInfo }, -- pieceId -> Info
	culpritPieceId: number?,
	culpritUserId: number?,
	culpritName: string?,
	disasterCaused: boolean?, -- true = Katastrophe war schuld, niemand zahlt
}

-- Eintrag fürs Punkte-Board.
export type ScoreEntry = {
	userId: number,
	name: string,
	points: number,
	culprit: boolean, -- hat diese Runde einen Kollaps verursacht
	level: number?, -- XP-Level (LevelLogic), sichtbare Langzeit-Progression
}

-- Reine Sicht auf ein Teil für die Punkteberechnung (ScoreLogic).
export type ScoringPiece = {
	ownerUserId: number,
	heightAboveBase: number, -- Y-Höhe der Teil-Mitte über der Plattform-Oberkante
	fallen: boolean,
	multiplier: number?, -- z. B. 3 für goldene Teile (Goldrausch); nil = 1
}

return {}
