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

	-- ---------------------------------------------------------------
	-- Abstaende. Eine Skala, keine krummen Zwischenwerte.
	-- ---------------------------------------------------------------
	SPACE = { XS = 4, S = 8, M = 12, L = 16, XL = 24, XXL = 40 },

	-- ---------------------------------------------------------------
	-- Schriftgroessen in Pixeln (bei UIScale 1).
	-- ---------------------------------------------------------------
	TEXT_SIZE = { SMALL = 16, BODY = 20, LEAD = 24, TITLE = 30, HERO = 38 },

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
	HUD_PANEL_WIDTH = 320,
	HUD_STATS_HEIGHT = 156, -- Statuskarte; die Knoepfe darunter richten sich danach
	SHOP_PANEL_WIDTH = 400,

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
