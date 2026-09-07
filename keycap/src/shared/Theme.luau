--!strict
-- Design-System. Farben, Schrift, Abstaende und Groessen stehen NUR hier -
-- weder Controller noch Services setzen eigene Werte.
--
-- Stil: hell und freundlich, creme-weisse Flaechen, kraeftige Akzente,
-- runde Ecken, Knoepfe mit dunklerer Unterkante. Kein dunkles Dashboard.

local Theme = {
	FONT = Enum.Font.FredokaOne,

	-- ---------------------------------------------------------------
	-- Farben
	-- ---------------------------------------------------------------
	PANEL = Color3.fromRGB(252, 249, 240), -- creme-weiss
	PANEL_EDGE = Color3.fromRGB(214, 206, 188),
	-- Tinte. Eine einzige fast-schwarze Farbe fuer Schrift auf bunten
	-- Flaechen, fuer die Umrandung um jedes Element und fuer die Kante
	-- unter jedem Knopf. Dass sie ueberall wiederkehrt, ist das, was den
	-- Look zusammenhaelt - siehe DESIGN.md.
	INK = Color3.fromRGB(24, 20, 18),
	OUTLINE_THICKNESS = 3, -- Umrandung von Panels und Knoepfen

	-- Bewegung. Jede Animation bleibt unter 0,4 s - beim zwanzigsten Mal
	-- darf sie nicht nerven. Alles ueber TweenService, nichts ueber
	-- while-true-Schleifen.
	MOTION = {
		DROP_SECONDS = 0.34, -- gekaufte Taste faellt in den Sockel
		DROP_HEIGHT = 26,
		PULSE_SECONDS = 1.1, -- volle Taste, langsam - das darf auffallen
		PULSE_SCALE = 1.08,
		COLLAPSE_SECONDS = 0.38, -- Lichtsaeule bricht beim Auszahlen zusammen
		DOME_SECONDS = 0.3, -- Kuppel waechst von unten
		FLASH_SECONDS = 0.18, -- kurzer Blitz beim gelungenen Klau
	},
	GRADIENT_LIFT = 0.14, -- Verlauf: oben um diesen Anteil heller

	TEXT = Color3.fromRGB(58, 52, 44),
	TEXT_MUTED = Color3.fromRGB(108, 100, 88),

	-- Knopfschrift ist IMMER dunkel, nie weiss. Weiss auf diesen hellen
	-- Akzenten kommt nur auf 2,4:1 - fuer Kinder auf einem Handy im
	-- Hellen unlesbar. Dunkle Schrift schafft ueberall mindestens 4,5:1,
	-- und die Akzente bleiben so kraeftig, wie sie sein sollen.
	-- Nachgerechnet im Testlauf, nicht geschaetzt.
	GREEN = Color3.fromRGB(64, 196, 86),
	GREEN_DARK = Color3.fromRGB(38, 138, 56),
	BLUE = Color3.fromRGB(56, 166, 246),
	BLUE_DARK = Color3.fromRGB(30, 112, 182),
	GOLD = Color3.fromRGB(255, 190, 32),
	GOLD_DARK = Color3.fromRGB(200, 138, 12),
	RED = Color3.fromRGB(246, 84, 74), -- nur fuer Flaechen
	RED_DARK = Color3.fromRGB(180, 48, 40), -- Kante unter einer roten Flaeche
	PURPLE = Color3.fromRGB(176, 102, 244),
	PURPLE_DARK = Color3.fromRGB(126, 62, 190),

	-- Textfarben der Akzente. Bewusst eigene Werte statt der _DARK-Kanten:
	-- eine Knopfkante muss nur dunkler sein als ihre Flaeche, eine Schrift
	-- muss 4,5:1 gegen das creme-weisse Panel schaffen. GOLD_DARK kommt dort
	-- nur auf 2,45:1 - als grosse Wins-Zahl waere das unlesbar gewesen.
	GOLD_TEXT = Color3.fromRGB(140, 96, 10),
	GREEN_TEXT = Color3.fromRGB(44, 116, 54),
	RED_TEXT = Color3.fromRGB(186, 68, 62),

	-- Die Kappe. Eine echte Keycap-Farbwelt, kein Regenbogen: warmes
	-- Off-White, Salbei, Petrol, Violett, Bernstein.
	-- Rare und Epic sind gegenueber dem Entwurf zwei Toene dunkler - mit
	-- den Originalwerten schaffte die Legende nur 3,91 bzw. 3,84:1.
	RARITY_COLORS = {
		Common = Color3.fromRGB(232, 228, 218),
		Uncommon = Color3.fromRGB(127, 168, 138),
		Rare = Color3.fromRGB(53, 111, 147),
		Epic = Color3.fromRGB(123, 79, 196),
		Legendary = Color3.fromRGB(255, 159, 28),
	},

	-- ---------------------------------------------------------------
	-- WELT — "Du bist winzig auf einem Schreibtisch. Nachts."
	--
	-- Der Boden ist eine Schreibtischmatte, die Plots stehen auf einer
	-- Tastaturplatte. Alles dunkel und kuehl; das Licht kommt vom Monitor
	-- am Rand und von den Tasten selbst, nicht von der Sonne.
	--
	-- WICHTIG zur Kante: auf dem hellen HUD ist die Kante DUNKEL (INK).
	-- Auf der dunklen Welt geht das nicht - INK hat Leuchtdichte 0,0074,
	-- die Matte 0,0073, die Tinte waere heller als der Boden. Weltkanten
	-- sind deshalb AUFHELLEND (SEAM). Zwei Gruende, zwei Farben.
	--
	-- Die Tonwerte liegen dicht beieinander (1,1-1,4:1). Das ist Absicht -
	-- eine dunkle Szene lebt von feinen Abstufungen. Lesbarkeit tragen
	-- Kanten und Licht, nicht Flaechenkontrast.
	-- ---------------------------------------------------------------
	WORLD = {
		MAT = Color3.fromRGB(20, 20, 28), -- Schreibtischmatte, der Boden
		MAT_MATERIAL = Enum.Material.Fabric,
		SEAM = Color3.fromRGB(46, 46, 62), -- Naht und Kante, hellt auf
		SEAM_MATERIAL = Enum.Material.Fabric,
		PLATE = Color3.fromRGB(34, 34, 44), -- Tastaturplatte, traegt die Plots
		PLATE_MATERIAL = Enum.Material.Metal,
		CHASSIS = Color3.fromRGB(51, 51, 63), -- Rahmen um die Platte
		CHASSIS_MATERIAL = Enum.Material.Metal,
		SOCKET = Color3.fromRGB(14, 14, 20), -- leere Mulde, dunkler als die Platte
		SOCKET_MATERIAL = Enum.Material.SmoothPlastic,
		PATH = Color3.fromRGB(26, 26, 36), -- Weg und Promenade
		PATH_MATERIAL = Enum.Material.Fabric,

		-- Signalfarbe. NUR fuer Cash-Out-Pad, Schildkuppel und
		-- Beute-Leuchtturm. Wenn Cyan leuchtet, passiert etwas - deshalb
		-- kommt die Farbe sonst nirgends vor.
		SIGNAL = Color3.fromRGB(61, 224, 224),
		SIGNAL_DIM = Color3.fromRGB(28, 128, 128),

		-- Hintergrund. Alles nur wenig heller als die Matte - es sind
		-- Silhouetten im Gegenlicht, keine Objekte zum Anschauen.
		CUP = Color3.fromRGB(58, 58, 74),
		CUP_COFFEE = Color3.fromRGB(24, 16, 14),
		CABLE = Color3.fromRGB(30, 30, 40),
		MOUSE = Color3.fromRGB(44, 44, 56),
		DUST = Color3.fromRGB(150, 165, 200),
	},

	-- Dunkle Kante je Seltenheit. Ohne die ist eine Taste eine flache
	-- Flaeche - weder der 3D-Effekt der Knoepfe noch das Kantenlicht der
	-- Tasten in der Welt haben sonst einen Wert, aus dem sie sich rechnen.
	-- Der Stem-Ring unter der Kappe, der sie vom Sockel absetzt. Jeweils
	-- 55 % der Kappenhelligkeit - dieselbe Beziehung wie Knopf zu Kante.
	RARITY_EDGE = {
		Common = Color3.fromRGB(128, 125, 120),
		Uncommon = Color3.fromRGB(70, 92, 76),
		Rare = Color3.fromRGB(29, 61, 81),
		Epic = Color3.fromRGB(68, 43, 108),
		Legendary = Color3.fromRGB(140, 87, 15),
	},

	-- Schrift AUF der jeweiligen Seltenheitsfarbe. Nachgerechnet gegen die
	-- eigene Flaeche: Common 6,2:1 - Uncommon 5,1:1 - Rare 4,6:1 -
	-- Epic 5,4:1 - Legendary 5,1:1. Weiss waere auf allen fuenf unlesbar.
	-- Die Legende, also der Buchstabe auf der Kappe. Nachgerechnet gegen
	-- die eigene Kappe: Common 11,8 - Uncommon 5,6 - Rare 4,9 - Epic 4,8 -
	-- Legendary 8,2:1. Helle Kappen tragen dunkle Legenden und umgekehrt.
	RARITY_INK = {
		Common = Color3.fromRGB(42, 38, 32),
		Uncommon = Color3.fromRGB(28, 42, 32),
		Rare = Color3.fromRGB(232, 244, 250),
		Epic = Color3.fromRGB(244, 234, 255),
		Legendary = Color3.fromRGB(42, 26, 0),
	},

	-- Rang 1-5. Traegt alles, was die Seltenheit OHNE Farbe zeigt:
	-- Zahl der Punkte im Laden, Rahmenstaerke, Kantenlicht in der Welt.
	-- Farbe allein reicht auf einem billigen Display in der Sonne nicht.
	-- Material je Stufe. Ab Rare wird die Kappe glaenzender, Legendary
	-- bekommt Metall - aus der Entfernung unterscheidbar, auch wenn ein
	-- billiges Display die Farbe verwaescht.
	RARITY_MATERIAL = {
		Common = Enum.Material.SmoothPlastic,
		Uncommon = Enum.Material.SmoothPlastic,
		Rare = Enum.Material.Plastic,
		Epic = Enum.Material.Plastic,
		Legendary = Enum.Material.Metal,
	},

	-- Reichweite des PointLights in der Kappe. 0 = kein Licht.
	-- Das ist keine Deko: Rare und Epic schaffen gegen die Tastaturplatte
	-- nur 2,89 bzw. 2,82:1 - ohne eigenes Licht verschwinden sie darauf.
	RARITY_LIGHT_RANGE = {
		Common = 0,
		Uncommon = 0,
		Rare = 12,
		Epic = 16,
		Legendary = 24,
	},
	RARITY_LIGHT_BRIGHTNESS = 1.4,
	-- Nur die wertvollsten Tasten eines Plots leuchten. Ohne diese Grenze
	-- waeren es im Vollausbau 181 PointLights (9 Spielerplots x 20
	-- Steckplaetze plus Monitor) - das ist auf dem Handy nicht bezahlbar.
	-- Mit 4 je Plot sind es hoechstens 48. Wer die teuersten Tasten
	-- leuchten sieht, sieht genau das, was ihn als Dieb interessiert.
	MAX_LIGHTS_PER_PLOT = 4,

	RARITY_RANK = {
		Common = 1,
		Uncommon = 2,
		Rare = 3,
		Epic = 4,
		Legendary = 5,
	},

	-- Hoehenfaktor der Taste in der Welt (mal WorldConfig.KEY_SIZE.Y).
	-- Die Grundflaeche bleibt gleich, damit das Steckplatz-Raster passt -
	-- unterschiedlich ist die Hoehe. Aus 20 m ist das der erste Unterschied,
	-- den man sieht, noch vor der Farbe.
	KEY_CROWN = {
		Common = 1,
		Uncommon = 1.2,
		Rare = 1.5,
		Epic = 1.9,
		Legendary = 2.4,
	},
	KEY_RIM_BASE = 0.04, -- Kantenlicht Grundstaerke (Studs)
	KEY_RIM_STEP = 0.03, -- plus je Rang
	KEY_LABEL_DISTANCE = 160, -- Sichtweite der schwebenden Vorratszahl

	-- ---------------------------------------------------------------
	-- Abstaende. Eine Skala, keine krummen Zwischenwerte.
	-- ---------------------------------------------------------------
	SPACE = { XS = 4, S = 8, M = 12, L = 16, XL = 24, XXL = 40 },

	-- ---------------------------------------------------------------
	-- Schriftgroessen in Pixeln (bei UIScale 1).
	-- ---------------------------------------------------------------
	-- DISPLAY und BLAST sind neu. HERO 38 war der groesste Grad; der Vorrat
	-- ist aber die Zahl, um die sich das ganze Spiel dreht, und muss die
	-- groesste auf dem Bildschirm sein. BLAST nur fuer den Cash-Out.
	TEXT_SIZE = { SMALL = 16, BODY = 20, LEAD = 24, TITLE = 30, HERO = 38, DISPLAY = 56, BLAST = 96 },

	-- ---------------------------------------------------------------
	-- Formen
	-- ---------------------------------------------------------------
	CORNER = UDim.new(0, 16), -- gross wirkt nach Spielzeug, klein nach Technik
	BUTTON_EDGE_HEIGHT = 4, -- dunklere Unterkante fuer den 3D-Effekt
	-- Kleinstes Touch-Ziel. Alles Anklickbare ist mindestens so hoch -
	-- darunter trifft ein Kinderdaumen auf dem Handy nicht zuverlaessig.
	TOUCH_MIN = 56,

	-- ---------------------------------------------------------------
	-- Layout des HUD
	-- ---------------------------------------------------------------
	-- Reservierte Bildschirmbereiche. Oben links sitzt der Roblox-Menue-
	-- knopf: die Statuskarte lag vorher bei y=16 und damit darunter.
	HUD_TOP_INSET = 72, -- ab hier faengt eigene UI oben an
	HUD_BOTTOM_INSET = 120, -- darunter: Stick links, Sprung-Knopf rechts

	HUD_PANEL_WIDTH = 320,
	-- 156 -> 240: der Tempo-Balken mit den drei Tor-Markierungen und der
	-- groessere Vorrat (DISPLAY 56 statt HERO 38) brauchen die Hoehe.
	HUD_STATS_HEIGHT = 240,

	-- Handy quer: Statuskarte wird zum Streifen oben mittig, die Knoepfe
	-- wandern an den rechten Rand. Sonst liegt das HUD unter dem Stick.
	HUD_STATS_COMPACT_HEIGHT = 108,
	HUD_COMPACT_WIDTH = 320,
	HUD_COMPACT_BUTTON_WIDTH = 76,
	COMPACT_MAX_WIDTH = 900,
	COMPACT_MAX_HEIGHT = 520,

	HUD_TUTORIAL_WIDTH = 720,
	HUD_TUTORIAL_COMPACT_WIDTH = 460,
	HUD_TUTORIAL_HEIGHT = 96,

	-- Tempo-Balken
	BAR_HEIGHT = 20,
	BAR_HEIGHT_COMPACT = 12,
	BAR_MARK_WIDTH = 4,

	-- Seltenheitspunkte
	PIP = 10,
	PIP_GAP = 4,
	PIP_CORNER = 3,

	-- Taste als Bild im Laden
	KEYCAP_EDGE = 8, -- Unterkante der kleinen Taste
	KEY_THUMB = 64, -- Hoehe einer Legendary
	KEY_THUMB_STEP = 6, -- je Rang niedriger

	-- 400 -> 560: eine Zeile traegt Tastenbild, Name, Punkte, Produktion
	-- und Kaufknopf. Bei 400 stand der Preis im Namen - genau das war der
	-- Grund, warum man die Seltenheit lesen musste statt sie zu sehen.
	SHOP_PANEL_WIDTH = 560,
	SHOP_ROW_HEIGHT = 88,
	SHOP_ROW_STROKE = 1, -- plus Rang: Common 2, Legendary 6
	SHOP_LIST_HEIGHT = 472,
	SHOP_LIST_HEIGHT_COMPACT = 208,
	SHOP_BUY_WIDTH = 128,
	SCROLLBAR = 6,

	-- Meldungen
	TOAST_WIDTH = 520,
	TOAST_HEIGHT = 40,
	BANNER_WIDTH = 640, -- laesst links das Menue und rechts den Chat frei
	BANNER_HEIGHT = 44,
	BANNER_SECONDS = 4,
	ALERT_WIDTH = 560,
	ALERT_HEIGHT = 168,
	ALERT_BAR = 8,
	ALERT_SECONDS = 4,

	-- Bewegung
	BUMP_SCALE = 1.08, -- Vorrat-Zahl beim Wachsen
	FLOAT_RISE = 52, -- wie weit die +Zahl steigt
	CRAWLER_WIDTH = 80,
	CRAWLER_HEIGHT = 4,

	-- ---------------------------------------------------------------
	-- UIScale: das HUD ist in festen Pixeln gebaut und wird fuer kleine
	-- Bildschirme heruntergerechnet. Referenz ist eine 1280 Pixel breite
	-- Ansicht; darunter wird verkleinert, darueber nicht vergroessert
	-- (sonst wirkt das HUD auf dem Monitor klobig).
	-- ---------------------------------------------------------------
	SCALE_REFERENCE_WIDTH = 1280,
	SCALE_MIN = 0.7,
	SCALE_MAX = 1,
}

return Theme
