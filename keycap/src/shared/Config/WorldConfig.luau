--!strict
-- Aufbau der Karte. Alles wird zur Laufzeit aus Parts gebaut, damit die
-- Place-Datei leer bleiben kann. Keine Magic Numbers in den Services.

local WorldConfig = {
	-- Plots: eine Reihe nebeneinander, je Spieler einer.
	PLOT_COUNT = 12, -- Obergrenze fuer die Servergroesse
	PLOT_SIZE = Vector3.new(48, 2, 48),
	PLOT_SPACING = 64, -- Mittenabstand zweier Plots
	PLOT_ORIGIN = Vector3.new(0, 8, 0), -- Mitte des ersten Plots

	-- Chassis unter der Plotplatte. Ohne das schwebt der Plot als nackte
	-- Scheibe; mit Ueberstand liest er sich als Tastatur-Gehaeuse, in dem
	-- die Tasten stecken.
	PLOT_DECK_OVERHANG = 3, -- wie weit das Chassis seitlich ueber die Platte steht
	PLOT_DECK_HEIGHT = 1.6,
	-- Umlaufender erhoehter Rand. Kostet KEINEN zusaetzlichen Part: das
	-- Chassis wird nach oben verlaengert, die Platte sitzt darin.
	PLOT_RIM_HEIGHT = 1,

	-- Schildkuppel ueber dem Plot. Nur sichtbar, solange das Schild laeuft.
	SHIELD_DOME_SCALE = 1.15, -- Durchmesser relativ zur Plotbreite

	-- Beute-Leuchtturm: Lichtsaeule ueber dem Plot, deren Hoehe mit dem
	-- Vorrat waechst. Ein Dieb auf Stage 2 sieht drei Saeulen und weiss
	-- sofort, wohin - ohne in ein Menue zu schauen.
	BEACON_WIDTH = 3,
	BEACON_MIN_HEIGHT = 8,
	BEACON_MAX_HEIGHT = 160,
	-- Bei welchem Vorrat der Leuchtturm seine volle Hoehe hat. Gekoppelt
	-- an den Speed-Deckel: wer so viel hat, ist maximal schnell und
	-- maximal interessant.
	BEACON_FULL_VORRAT = 4200,

	-- Leerer Steckplatz: flache, dunkle Mulde. Damit sieht man aus der
	-- Entfernung, wie voll ein Plot ist - fuer einen Dieb die wichtigste
	-- Information, bevor er hinlaeuft.
	SLOT_MARKER_HEIGHT = 0.2,
	SLOT_MARKER_SCALE = 0.78, -- Anteil der Tastengrundflaeche

	-- Schild an der Vorderkante. War bisher ein unsichtbarer Part mit
	-- schwebendem Text - jetzt eine echte Tafel, an der der Text haengt.
	SIGN_BOARD_SIZE = Vector3.new(16, 4.5, 0.8),

	-- Podest unter dem Auszahlungs-Pad, damit es aus der Ferne als Ziel
	-- erkennbar ist und nicht als Fleck im Boden.
	PAD_RING_OVERHANG = 3.5,
	PAD_RING_HEIGHT = 1.2,

	-- Steckplaetze auf dem Plot: Raster, auf dem die Tasten stehen.
	SLOT_COLUMNS = 5,
	SLOT_SPACING = 9,
	KEY_SIZE = Vector3.new(6, 3, 6),

	-- Silhouette der Tastenkappe. Eine echte Keycap ist unten breiter als
	-- oben und hat einen sichtbaren Absatz zum Sockel - aus 30 m erkennt
	-- man eine Tastatur an der Silhouette, nicht an den Buchstaben.
	--
	-- Gebaut als zwei gestapelte Quader statt aus WedgeParts. Begruendung:
	-- eine echte Schraege braeuchte vier Wedges pro Kappe, das waeren bei
	-- 192 Tasten 768 Parts zusaetzlich - mehr als das gesamte restliche
	-- Budget. Der zweistufige Absatz kostet einen Part und liest sich auf
	-- Spielentfernung gleich.
	KEY_TOP_INSET = 0.82, -- Deckplatte auf 82 % der Grundflaeche
	KEY_TOP_HEIGHT = 0.45,
	KEY_STEM_INSET = 0.68, -- Stem-Ring, schmaler als der Koerper
	KEY_STEM_HEIGHT = 0.6,

	-- Die Legende sitzt nicht mittig, sondern leicht nach oben-links -
	-- so wie auf einer echten Tastatur. Zwei Zahlen, grosse Wirkung.
	KEY_LEGEND_OFFSET = Vector2.new(-0.10, -0.12),

	-- "Zuhause": Radius um die Plotmitte, in dem der Besitzer als anwesend
	-- gilt (verdoppelt die Klau-Dauer).
	PRESENCE_RADIUS = 34,

	-- Parcours: drei Stages, jede weiter weg. Die Cash-Out-Pads stehen am
	-- Ende der jeweiligen Stage.
	STAGE_PAD_POSITIONS = {
		Vector3.new(0, 8, -140),
		Vector3.new(0, 8, -300),
		Vector3.new(0, 8, -520),
	},
	STAGE_PAD_SIZE = Vector3.new(24, 2, 24),

	-- Speed-Tore: wer langsamer ist, kommt nicht durch.
	STAGE_GATE_POSITIONS = {
		Vector3.new(0, 12, -60),
		Vector3.new(0, 12, -210),
		Vector3.new(0, 12, -400),
	},
	STAGE_GATE_SIZE = Vector3.new(40, 12, 2),

	-- Laufwege. Ohne die faellt man ins Leere: zwischen zwei Plots liegen
	-- PLOT_SPACING - PLOT_SIZE.X = 16 Studs Luecke, und zwischen Plotreihe
	-- und Stage 1 war ueberhaupt nichts.
	PATH_WIDTH = 40, -- Breite der Promenade vor den Plots

	-- ---------------------------------------------------------------
	-- Der Parcours. Riesige Tastenkappen mit Luecken dazwischen, die man
	-- nur mit genug WalkSpeed ueberspringt. Die Sprungweite IST das Gate.
	--
	-- Rechnung (Workspace.Gravity 196.2, Humanoid.JumpPower 50, das ist
	-- der Engine-Standard bei UseJumpPower = true):
	--   Anfangsgeschwindigkeit v0 = 50
	--   Flugzeit t = 2 * v0 / g = 2 * 50 / 196.2 = 0,5097 s
	--   Weite   d = WalkSpeed * t
	--     Speed 16 (Start) ->  8,2 Studs
	--     Speed 30 (Gate 1) -> 15,3 Studs
	--     Speed 50 (Gate 2) -> 25,5 Studs
	--     Speed 75 (Gate 3) -> 38,2 Studs
	--
	-- Die Luecken liegen bei 85 % der Maximalweite des jeweiligen
	-- Gate-Speeds. Damit ist das Tor weich: wer knapp darunter liegt,
	-- kommt auch durch, wer deutlich darunter liegt, faellt. Auf 100 %
	-- gesetzt gaebe es keine Marge und jeder Fehltritt waere ein Absturz -
	-- das widerspricht "Landeflaechen grosszuegig, kein Overshoot-Fail".
	-- ACHTUNG: massgeblich ist die DIAGONALE, nicht die Luecke. Wer
	-- seitlich versetzt springt, legt sqrt(luecke^2 + (2*versatz)^2)
	-- zurueck. Mit Versatz 7 und Luecke 21,7 waeren das 25,8 Studs bei
	-- 25,5 Maximalweite - genau auf Gate-Speed kaeme niemand rueber.
	-- Die Luecke bezahlt den Versatz deshalb mit:
	--   Stage 1: Versatz 0  -> Luecke 13,0  Diagonale 13,0  ab Speed 25,5
	--   Stage 2: Versatz 7  -> Luecke 16,5  Diagonale 21,7  ab Speed 42,5
	--   Stage 3: Versatz 11 -> Luecke 23,9  Diagonale 32,5  ab Speed 63,8
	-- ---------------------------------------------------------------
	JUMP_GRAVITY = 196.2, -- ungeprueft: bitte in Studio gegen Workspace.Gravity abgleichen
	JUMP_POWER = 50, -- ungeprueft: haengt an StarterPlayer.CharacterUseJumpPower
	JUMP_MARGIN = 0.85, -- Anteil der Maximalweite, den eine Luecke ausmacht

	STAGES = {
		{ gap = 13, depth = 20, width = 34, sideways = 0, moves = false },
		{ gap = 16.5, depth = 16, width = 26, sideways = 7, moves = false },
		{ gap = 23.9, depth = 13, width = 22, sideways = 11, moves = true },
	},
	-- Bewegliche Kappen in Stage 3: nur senkrecht, langsam, kleine
	-- Amplitude. ungeprueft: ob ein verankerter Part per CFrame den
	-- Spieler zuverlaessig traegt - die Recherche sagt "waagerecht nein,
	-- senkrecht ruckelig ja". Deshalb klein und langsam.
	MOVING_AMPLITUDE = 4,
	MOVING_SECONDS = 2.6,
	MOVING_EVERY = 3, -- jede dritte Kappe bewegt sich

	-- Absturz: unter diese Hoehe gefallen heisst zurueck an den
	-- Stage-Anfang, nicht auf den Plot. Fehler kostet Zeit, nicht den Lauf.
	FALL_Y = -60,
	PROMENADE_DEPTH = 24, -- Streifen vor der Plotreihe, verbindet alle Plots
	PATH_MARGIN = 12, -- wie weit der Weg ueber das letzte Pad hinausgeht

	-- Wie oft der Server den Zustand an die Clients schickt.
	STATE_PUSH_INTERVAL = 0.5,

	-- NPC-Plots [ENTSCHEIDUNG]
	-- Die Bewertung: "Der Loop braucht Mitspieler und du hast keine."
	-- Auf einem leeren Server waere KEYCAP RUSH ein Farm-Spiel. NPC-Plots
	-- sind immer da und immer beklaubar - sie fuellen die Luecke, ohne den
	-- Wettbewerb zwischen echten Spielern zu ersetzen.
	NPC_PLOT_COUNT = 3, -- belegen die letzten Plots der Reihe
	NPC_NAMES = { "Alte Tastatur", "Fundbuero", "Schrottplatz" },

	-- Tastenbeschriftung. Eine Taste ohne Buchstabe ist ein Wuerfel - der
	-- Buchstabe ist die ganze optische Identitaet des Spiels. Reihenfolge
	-- wie auf einer Tastatur, damit ein voller Plot lesbar wirkt.
	KEY_LEGENDS = {
		"A", "S", "D", "F", "G",
		"H", "J", "K", "L", "Q",
		"W", "E", "R", "T", "Y",
		"U", "I", "O", "P", "Z",
	},

	-- Beleuchtung: Schreibtisch bei Nacht. Die Szene wird vom Monitor am
	-- Rand und von den Tasten beleuchtet, nicht von der Sonne. [ENTSCHEIDUNG]
	LIGHTING = {
		AMBIENT = Color3.fromRGB(14, 15, 22), -- fast schwarz, leicht blaeulich
		OUTDOOR_AMBIENT = Color3.fromRGB(20, 24, 36),
		BRIGHTNESS = 0.6, -- Sonne fast aus
		CLOCK_TIME = 0.5, -- kurz nach Mitternacht
		GEOGRAPHIC_LATITUDE = 0,
		ENVIRONMENT_DIFFUSE = 0.15,
		ENVIRONMENT_SPECULAR = 0.9, -- Metall soll das Monitorlicht spiegeln
		EXPOSURE_COMPENSATION = 0.35, -- hebt die dunklen Toene wieder an

		-- Dunst duenn: dichter Dunst frisst in einer Nachtszene den Kontrast.
		ATMOSPHERE_DENSITY = 0.12,
		ATMOSPHERE_HAZE = 0.4,
		ATMOSPHERE_GLARE = 0,
		ATMOSPHERE_COLOR = Color3.fromRGB(28, 32, 46),
		ATMOSPHERE_DECAY = Color3.fromRGB(12, 14, 24),

		-- Bloom scharf. Vorher stand die Schwelle bei 1.4 und es gab zwei
		-- Neon-Parts - deshalb sah man ihn nie. Unter 1 greift er auch bei
		-- normal hellen Flaechen, die leuchtenden Tasten bekommen einen Hof.
		BLOOM_INTENSITY = 1.1,
		BLOOM_SIZE = 32,
		BLOOM_THRESHOLD = 0.85,

		-- Zwei Zahlen, grosse Wirkung: Saettigung hoch, Kontrast leicht hoch,
		-- Farbstich ins Kuehle.
		CC_BRIGHTNESS = 0,
		CC_CONTRAST = 0.12,
		CC_SATURATION = 0.22,
		CC_TINT = Color3.fromRGB(226, 234, 255),

		SUNRAYS_INTENSITY = 0.04, -- dezent, es ist Nacht
		SUNRAYS_SPREAD = 0.6,

		-- Tiefenunschaerfe sehr schwach. Zu viel kostet auf dem Handy.
		DOF_FAR_INTENSITY = 0.28,
		DOF_FOCUS_DISTANCE = 60,
		DOF_IN_FOCUS_RADIUS = 140,
		DOF_NEAR_INTENSITY = 0,

		-- Der Monitor. Kein Objekt, sondern eine Lichtquelle: eine grosse,
		-- schwach leuchtende Flaeche, die die Szene von einer Seite kalt
		-- anleuchtet. Das ist der Trick, der die Nacht-Stimmung macht.
		MONITOR_SIZE = Vector3.new(2, 320, 560),
		MONITOR_POSITION = Vector3.new(-720, 170, -180),
		MONITOR_COLOR = Color3.fromRGB(150, 180, 255),
		MONITOR_LIGHT_BRIGHTNESS = 2.2,
		MONITOR_LIGHT_RANGE = 900,
		MONITOR_TRANSPARENCY = 0.15,
	},

	-- Part-Budget: obere Schranke fuer alles, was der Server baut.
	-- Auf dem Handy ist die Zahl gleichzeitig sichtbarer ProximityPrompts
	-- oft das engere Limit als die reine Part-Zahl. UNGEPRUEFT - nicht gemessen.
	PART_BUDGET = 3000,
}

return WorldConfig
