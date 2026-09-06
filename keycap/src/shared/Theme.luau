--!strict
-- Zentrale Farb- und Font-Tabelle. Farben NIE in Controllern hardcoden.
-- Stil: hell und freundlich, kein dunkles Dashboard.

local Theme = {
	FONT = Enum.Font.FredokaOne,

	PANEL = Color3.fromRGB(252, 249, 240), -- creme-weiss
	PANEL_EDGE = Color3.fromRGB(214, 206, 188),
	TEXT = Color3.fromRGB(58, 52, 44),
	TEXT_MUTED = Color3.fromRGB(132, 124, 112),

	GREEN = Color3.fromRGB(86, 190, 96),
	GREEN_DARK = Color3.fromRGB(58, 146, 68),
	BLUE = Color3.fromRGB(72, 158, 226),
	BLUE_DARK = Color3.fromRGB(46, 116, 178),
	GOLD = Color3.fromRGB(248, 196, 62),
	GOLD_DARK = Color3.fromRGB(206, 152, 32),
	RED = Color3.fromRGB(230, 96, 88),

	CORNER = UDim.new(0, 12),
	BUTTON_EDGE_HEIGHT = 4, -- dunklere Unterkante fuer den 3D-Effekt

	RARITY_COLORS = {
		Common = Color3.fromRGB(206, 206, 206),
		Uncommon = Color3.fromRGB(120, 206, 120),
		Rare = Color3.fromRGB(94, 156, 232),
		Epic = Color3.fromRGB(178, 118, 232),
		Legendary = Color3.fromRGB(248, 186, 70),
	},
}

return Theme
