--!strict
-- Globale Spielkonstanten von Turmfall (Balancing-Canon).
-- Werte hier ändern, nicht in den Services.

local GameConfig = {
	-- Runden-StateMachine (RoundService).
	LOBBY_MIN_PLAYERS = 2, -- Multiplayer-Start ab 2 Spielern
	LOBBY_COUNTDOWN_SECONDS = 10, -- Countdown, sobald genug Spieler da sind

	-- Solo-Modus: Wer allein im Server ist, startet nach kurzer Wartezeit
	-- eine Übungsrunde (Mitspieler können jederzeit einsteigen - kommt
	-- rechtzeitig ein zweiter Spieler, gilt der normale Countdown).
	SOLO_MODE_ENABLED = true,
	SOLO_START_WAIT_SECONDS = 8,
	SETUP_SECONDS = 5, -- "Aufbau": Turm-Reset + Teleport + Startteil
	BUILD_SECONDS = 180, -- Bauphase: 3 Minuten
	SCORING_SECONDS = 12, -- Wertung: Leaderboard zeigen

	-- Teilvergabe (DeckService).
	PART_DROP_INTERVAL_SECONDS = 15, -- alle 15 s ein neues Teil
	HOTBAR_MAX_ITEMS = 3, -- ist die Hotbar voll, verfällt der Drop

	-- Platzierung (TowerService validiert ALLES serverseitig).
	PLACE_REACH_STUDS = 12, -- max. Abstand Spieler -> Zielposition
	PLACE_ADJACENCY_STUDS = 3, -- max. Lücke zum nächsten Teil / zur Plattform
	PLACE_COOLDOWN_SECONDS = 1, -- Anti-Spam pro Spieler
	PLACE_MAX_TILT_DEGREES = 0, -- Client darf nur um die Y-Achse rotieren

	-- Physik-Budget: hartes Limit aktiver (unanchored) Teile pro Turm.
	-- Ab dem Limit werden die untersten, ruhigen Teile "versteinert"
	-- (geankert und damit aus der Physiksimulation genommen).
	MAX_PHYSICS_PARTS = 400,
	PETRIFY_TARGET_RATIO = 0.9, -- versteinern bis auf 90% des Limits
	PETRIFY_CHECK_SECONDS = 3,
	PETRIFY_MAX_SPEED = 0.5, -- nur ruhige Teile dürfen versteinern (Studs/s)

	-- Kollaps-Erkennung (CollapseService).
	FALL_WINDOW_SECONDS = 5, -- gleitendes Fenster für die 30%-Regel
	FALL_COLLAPSE_RATIO = 0.3, -- >30% der Teile fallen -> Kollaps
	FALL_MIN_PIECES = 6, -- unterhalb dessen gibt es keinen "Kollaps" (zu früh)

	-- Schuld-System: Ringpuffer aller Teil-Positionen.
	RING_BUFFER_SECONDS = 10,
	RING_BUFFER_HZ = 4,
	REPLAY_SECONDS = 5, -- Länge des Schuld-Replays
	BLAME_CONTACT_MARGIN_STUDS = 1.25, -- Toleranz für "hatte Kontakt"

	-- Arena-Geometrie.
	BASE_PLATFORM_SIZE = 40, -- quadratische Basisplattform (Studs)
	BASE_PLATFORM_THICKNESS = 2,
	BASE_PLATFORM_Y = 20, -- Mitte der Plattform (schwebt über dem Abgrund)
	FALL_MARGIN_STUDS = 2, -- "gefallen" = unter Plattform-Mitte minus Marge

	-- Wie oft das Live-Scoreboard während der Bauphase aktualisiert wird.
	SCOREBOARD_REFRESH_SECONDS = 3,

	-- "Letzter Stein"-Finale (Meilenstein 4): In den letzten Sekunden der
	-- Bauphase darf jeder Spieler genau EIN Teil setzen.
	FINALE_SECONDS = 15,

	-- Sabotage-Balancing: Wer primär auf fremden Teilen baut, bekommt
	-- einen Instabilitäts-Cooldown.
	SABOTAGE_COOLDOWN_SECONDS = 10,
	SABOTAGE_SUPPORT_MAX_DROP = 6, -- wie weit unter dem Ziel ein Stütz-Teil liegen darf

	-- Turm-Schwank-Feedback: Server berechnet einen Stabilitäts-Score
	-- 0..100 aus der mittleren Teil-Geschwindigkeit; Clients visualisieren
	-- (Kamerawackeln + Knarz-Sounds).
	STABILITY_BROADCAST_SECONDS = 1,
	STABILITY_SPEED_FOR_ZERO = 9, -- mittlere Geschwindigkeit (Studs/s), die Score 0 bedeutet

	-- Katastrophen-Events (inspiriert von Natural Disaster Survival):
	-- Mitten in der Bauphase kommt mit Vorwarnung ein zufälliges Ereignis.
	DISASTER_MIN_GAP_SECONDS = 40, -- frühestens so lange nach Phasenstart/letztem Event
	DISASTER_CHANCE_PER_CHECK = 0.5, -- Chance pro Prüfintervall (alle 10 s)
	DISASTER_CHECK_SECONDS = 10,
	DISASTER_WARNING_SECONDS = 4, -- Vorwarnzeit ("⚠️ ... im Anflug!")
	WIND_DURATION_SECONDS = 4, -- Windböe: seitliche Stöße auf alle aktiven Teile
	WIND_IMPULSE_SPEED = 6, -- zusätzliche Geschwindigkeit pro Stoß (Studs/s)
	QUAKE_DURATION_SECONDS = 5, -- Erdbeben: zufällige Rüttel-Stöße
	QUAKE_IMPULSE_SPEED = 3,
	DISASTER_BLAME_GRACE_SECONDS = 6, -- so lange nach dem Event ist NIEMAND schuld
	GOLDRUSH_WINDOW_SECONDS = 20, -- Goldrausch: in dieser Zeit platzierte Teile sind golden
	GOLD_SCORE_MULTIPLIER = 3, -- goldene Teile zählen 3-fach

	-- XP & Level (sichtbare Langzeit-Progression wie in den Top-Spielen).
	XP_ROUND_BONUS = 20, -- Teilnahme-XP pro Runde
	XP_PER_POINT = 1, -- zusätzlich 1 XP pro Punkt

	-- Tages-Bonus (Trümmer je aufeinanderfolgendem Login-Tag; Tag 7+ = Maximum).
	-- Tägliches Wiederkommen ist der stärkste Retention-Treiber der Topspiele.
	DAILY_REWARDS = { 25, 50, 75, 100, 150, 200, 300 },

	-- Meteor-Katastrophe: Feuerball schlägt in den Turm ein (Druckwelle).
	METEOR_FALL_SECONDS = 1.2,
	METEOR_BLAST_RADIUS = 14, -- Teile in diesem Radius bekommen die Druckwelle
	METEOR_BLAST_SPEED = 16, -- Geschwindigkeit der Druckwelle (Studs/s)

	-- Server-Rekorde (höchster Turm) fürs Denkmal.
	RECORD_STORE_NAME = "Turmfall_Rekorde_v1",
}

return GameConfig
