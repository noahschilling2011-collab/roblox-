--!strict
-- Balancing-Canon fuer KEYCAP RUSH. Werte NUR hier aendern, nie in Services.
--
-- Herkunft der Werte:
--   [KONZEPT]  = steht so im KEYCAP-RUSH-Konzeptdokument (ueber die Bewertung zitiert)
--   [GEMESSEN] = muss in Studio gemessen werden, Platzhalter bis dahin
--   [ABGELEITET] = wird in EconomyLogic aus den obigen berechnet, nicht geraten
--
-- Die Bewertung (docs/KEYCAP_RUSH_BEWERTUNG.md) hat zwei Luecken benannt:
-- Tastenpreis und Produktionsrate pro Seltenheit. Beide stehen hier.

local EconomyConfig = {
	-- ---------------------------------------------------------------
	-- Speed [KONZEPT]
	-- WalkSpeed = BASE + min(vorrat * SPEED_PER_VORRAT, MAX_SPEED_BONUS)
	-- ---------------------------------------------------------------
	BASE_WALK_SPEED = 16,
	SPEED_PER_VORRAT = 0.02,
	MAX_SPEED_BONUS = 84, -- Deckel bei WalkSpeed 100 (Vorrat 4200)
	CARRY_SPEED_FACTOR = 0.6, -- geklaute Taste tragen: 40% langsamer [KONZEPT]

	-- ---------------------------------------------------------------
	-- Stages [KONZEPT]
	-- ---------------------------------------------------------------
	STAGE_GATES = { 30, 50, 75 }, -- Mindest-WalkSpeed pro Stage

	-- Rundlaufzeit Plot -> Cash-Out-Pad -> Plot, in Sekunden. [GEMESSEN]
	-- ACHTUNG: Das sind Schaetzwerte. Sobald der Parcours in Studio steht,
	-- einmal mit Stoppuhr messen und hier eintragen - ALLE Auszahlungs-
	-- faktoren und die Schilddauer haengen daran und rechnen sich neu.
	STAGE_RUN_SECONDS = { 40, 80, 140 },

	-- ---------------------------------------------------------------
	-- Auszahlung [ABGELEITET aus STAGE_RUN_SECONDS]
	-- Wins = floor(vorrat * faktor). Die Faktoren stehen NICHT hier als
	-- feste Zahlen, weil sie sonst nicht zu den Laufzeiten passen.
	-- Siehe EconomyLogic.payoutFactors().
	-- ---------------------------------------------------------------
	BASE_PAYOUT_FACTOR = 0.02, -- Faktor von Stage 1, Anker der Ableitung
	REFERENCE_HOLD_SECONDS = 300, -- typische Sammeldauer zwischen zwei Auszahlungen
	DISTANCE_PREMIUM = 1.12, -- +12% Bonus pro Stage, damit der Umweg etwas bringt

	-- ---------------------------------------------------------------
	-- Tasten: Produktion und Preis [KONZEPT-LUECKE, hier geschlossen]
	-- vorratPerSecond = Produktion. price = Kaufpreis in Wins.
	-- Preis pro Produktionseinheit steigt mit der Seltenheit - dadurch ist
	-- nicht der Preis der Engpass, sondern die Zahl der Steckplaetze.
	-- ---------------------------------------------------------------
	RARITY_ORDER = { "Common", "Uncommon", "Rare", "Epic", "Legendary" },
	RARITIES = {
		Common = { vorratPerSecond = 1, price = 10 },
		Uncommon = { vorratPerSecond = 3, price = 40 },
		Rare = { vorratPerSecond = 9, price = 150 },
		Epic = { vorratPerSecond = 30, price = 600 },
		Legendary = { vorratPerSecond = 100, price = 2500 },
	},

	START_KEY_SLOTS = 10, -- Steckplaetze auf dem Plot beim Start
	MAX_KEY_SLOTS = 20,
	SLOT_PRICE_BASE = 500, -- Preis fuer den 11. Slot
	SLOT_PRICE_GROWTH = 1.6, -- jeder weitere Slot kostet 1.6x

	-- ---------------------------------------------------------------
	-- Diebstahl
	-- Aenderung aus Abschnitt 6 der Bewertung: jede Taste haelt ihren
	-- EIGENEN Vorrat, der Plot-Vorrat ist die Summe. Wer eine Taste klaut,
	-- klaut ihren Vorrat mit. Damit ist Horten nicht mehr gratis.
	-- ---------------------------------------------------------------
	STEAL_VORRAT_SHARE = 0.5, -- Anteil des Tastenvorrats, den der Dieb bekommt
	STEAL_VORRAT_CAP = 5000, -- Rest verfaellt - deckelt den Gluecksgriff
	STEAL_PAIR_COOLDOWN_SECONDS = 90, -- pro Dieb-Opfer-Paar [KONZEPT]
	PRESENCE_HOLD_FACTOR = 2, -- Besitzer zuhause: Klau-Dauer verdoppelt [KONZEPT]

	-- ---------------------------------------------------------------
	-- Schild [ABGELEITET aus STAGE_RUN_SECONDS]
	-- Das Konzept sagt 45 s Schutz / 180 s Abklingzeit. Bei einem
	-- Stage-3-Rundlauf von 140 s schuetzt das genau die Situation nicht,
	-- fuer die es da ist. Siehe EconomyLogic.shieldWindow().
	-- ---------------------------------------------------------------
	SHIELD_COOLDOWN_RATIO = 2, -- Abklingzeit = 2x Schilddauer -> jeder 2. Lauf geschuetzt

	-- ---------------------------------------------------------------
	-- Interaktion [ENTSCHEIDUNG, nicht aus dem Konzept]
	-- ---------------------------------------------------------------
	STEAL_HOLD_SECONDS = 4, -- Halten am Klau-Prompt (x2 wenn Besitzer zuhause)
	CASHOUT_HOLD_SECONDS = 0.6, -- kurzes Halten statt Beruehrung [KONZEPT]
	CARRY_SECONDS = 8, -- so lange traegt man die geklaute Taste sichtbar
	SHOP_HOLD_SECONDS = 0.3,

	-- Rate-Limit pro Spieler und Remote (Anfragen pro Sekunde).
	REMOTE_RATE_LIMIT = 6,

	-- Vorrat wird beim Verlassen NICHT gespeichert. Sonst waere Horten
	-- offline risikofrei - genau das Loch, das die per-Taste-Aenderung
	-- schliessen soll. Gespeichert werden Wins, Slots und Tasten.
	PERSIST_VORRAT = false,
}

return EconomyConfig
