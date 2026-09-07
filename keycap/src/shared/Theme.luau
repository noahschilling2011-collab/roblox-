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
	TEXT = Color3.fromRGB(58, 52, 44),
	TEXT_MUTED = Color3.fromRGB(108, 100, 88),

	-- Knopfschrift ist IMMER dunkel, nie weiss. Weiss auf diesen hellen
	-- Akzenten kommt nur auf 2,4:1 - fuer Kinder auf einem Handy im
	-- Hellen unlesbar. Dunkle Schrift schafft ueberall mindestens 4,5:1,
	-- und die Akzente bleiben so kraeftig, wie sie sein sollen.
	-- Nachgerechnet im Testlauf, nicht geschaetzt.
	GREEN = Color3.fromRGB(86, 190, 96),
	GREEN_DARK = Color3.fromRGB(58, 146, 68),
	BLUE = Color3.fromRGB(108, 186, 240),
	BLUE_DARK = Color3.fromRGB(62, 132, 190),
	GOLD = Color3.fromRGB(248, 196, 62),
	GOLD_DARK = Color3.fromRGB(206, 152, 32),
	RED = Color3.fromRGB(230, 96, 88), -- nur fuer Flaechen
	RED_DARK = Color3.fromRGB(168, 60, 54), -- Kante unter einer roten Flaeche

	-- Textfarben der Akzente. Bewusst eigene Werte statt der _DARK-Kanten:
	-- eine Knopfkante muss nur dunkler sein als ihre Flaeche, eine Schrift
	-- muss 4,5:1 gegen das creme-weisse Panel schaffen. GOLD_DARK kommt dort
	-- nur auf 2,45:1 - als grosse Wins-Zahl waere das unlesbar gewesen.
	GOLD_TEXT = Color3.fromRGB(140, 96, 10),
	GREEN_TEXT = Color3.fromRGB(44, 116, 54),
	RED_TEXT = Color3.fromRGB(186, 68, 62),

	RARITY_COLORS = {
		Common = Color3.fromRGB(206, 206, 206),
		Uncommon = Color3.fromRGB(120, 206, 120),
		Rare = Color3.fromRGB(134, 190, 248),
		Epic = Color3.fromRGB(206, 164, 248),
		Legendary = Color3.fromRGB(248, 186, 70),
	},

	-- Dunkle Kante je Seltenheit. Ohne die ist eine Taste eine flache
	-- Flaeche - weder der 3D-Effekt der Knoepfe noch das Kantenlicht der
	-- Tasten in der Welt haben sonst einen Wert, aus dem sie sich rechnen.
	RARITY_EDGE = {
		Common = Color3.fromRGB(168, 168, 168),
		Uncommon = Color3.fromRGB(78, 158, 78),
		Rare = Color3.fromRGB(78, 136, 196),
		Epic = Color3.fromRGB(144, 104, 196),
		Legendary = Color3.fromRGB(196, 138, 30),
	},

	-- Schrift AUF der jeweiligen Seltenheitsfarbe. Nachgerechnet gegen die
	-- eigene Flaeche: Common 6,2:1 - Uncommon 5,1:1 - Rare 4,6:1 -
	-- Epic 5,4:1 - Legendary 5,1:1. Weiss waere auf allen fuenf unlesbar.
	RARITY_INK = {
		Common = Color3.fromRGB(74, 66, 56),
		Uncommon = Color3.fromRGB(30, 76, 30),
		Rare = Color3.fromRGB(30, 74, 120),
		Epic = Color3.fromRGB(74, 46, 108),
		Legendary = Color3.fromRGB(106, 66, 4),
	},

	-- Rang 1-5. Traegt alles, was die Seltenheit OHNE Farbe zeigt:
	-- Zahl der Punkte im Laden, Rahmenstaerke, Kantenlicht in der Welt.
	-- Farbe allein reicht auf einem billigen Display in der Sonne nicht.
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
	CORNER = UDim.new(0, 12),
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
