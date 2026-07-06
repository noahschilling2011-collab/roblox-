--!strict
-- Monetarisierung: Gamepässe, Developer Products und der Kosmetik-Katalog.
--
-- GRUNDSATZ (siehe docs/MONETARISIERUNG.md): Für Robux gibt es ausschließlich
-- Kosmetik – Planeten-Skins, Auren, Wettereffekte und Haustiere. Niemals
-- Energie, Fund-Würfe, Loot-Chancen oder andere Spielvorteile.
--
-- EINRICHTUNG: Die IDs unten sind Platzhalter (0). Im Roblox Creator Dashboard
-- unter "Monetarisierung" die Gamepässe bzw. Developer Products anlegen und
-- die echten IDs hier eintragen. Solange eine ID 0 ist, zeigt der Shop den
-- Eintrag als "Bald verfügbar" an und Käufe sind deaktiviert.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)

-- Rein optische Eigenschaften; die Anwendung übernimmt PlanetService bzw.
-- MonetizationService (Haustiere).
export type CosmeticVisual = {
	color: Color3?, -- Hauptfarbe (Kern, Partikel, Haustier-Körper)
	secondaryColor: Color3?, -- zweite Farbe für Verläufe
	material: Enum.Material?, -- Material für Kern-Skins und Haustiere
	glow: boolean?, -- true = zusätzliches PointLight
}

export type CosmeticDef = {
	id: Types.CosmeticId,
	displayName: string,
	description: string,
	category: Types.CosmeticCategory,
	visual: CosmeticVisual,
}

export type GamepassDef = {
	key: string,
	gamePassId: number, -- PLATZHALTER: echte ID aus dem Creator Dashboard eintragen
	displayName: string,
	description: string,
	grantsCosmetics: { Types.CosmeticId },
	perk: ("double_mult" | "pet_slots" | "vip" | "auto_harvest")?, -- dauerhafter Spielvorteil
	suggestedRobux: number?, -- TODO: nur Preis-VORSCHLAG; der echte Preis wird im Dashboard gesetzt
}

export type ProductDef = {
	key: string,
	productId: number, -- PLATZHALTER: echte ID aus dem Creator Dashboard eintragen
	displayName: string,
	description: string,
	grantsCosmetic: Types.CosmeticId?, -- einmalige Kosmetik-Freischaltung
	grantsEnergy: number?, -- Währungspaket (wiederholt kaufbar)
	perk: ("instant_rebirth" | "boost_2x")?, -- Sofort-Rebirth / 20-Min-Boost (wiederholt kaufbar)
	suggestedRobux: number?, -- TODO: nur Preis-VORSCHLAG; der echte Preis wird im Dashboard gesetzt
}

local MonetizationConfig = {}

-- STUDIO-TESTMODUS: Solange Produkt-IDs 0 sind, simuliert ein Klick im Shop
-- den erfolgreichen Kauf - ABER ausschliesslich in Roblox Studio. Der Server
-- prüft RunService:IsStudio() hart (MonetizationService.isTestPurchaseAllowed);
-- in einem veröffentlichten Spiel hat dieses Flag deshalb NIE eine Wirkung.
-- So lassen sich Equip, Haustiere und Effekte ohne echte IDs testen.
MonetizationConfig.testModeInStudio = true

MonetizationConfig.Categories = { "skin", "aura", "wetter", "haustier" }

MonetizationConfig.CategoryNames = {
	skin = "Planeten-Skin",
	aura = "Aura",
	wetter = "Wettereffekt",
	haustier = "Haustier",
}

MonetizationConfig.Cosmetics = {
	-- Planeten-Skins: verändern Material und Farbe des Planetenkerns.
	skin_gold = {
		id = "skin_gold",
		displayName = "Goldener Kern",
		description = "Dein Planetenkern glänzt in purem Gold.",
		category = "skin",
		visual = { color = Color3.fromRGB(226, 176, 44), material = Enum.Material.Metal, glow = true },
	},
	skin_lava = {
		id = "skin_lava",
		displayName = "Lava-Kern",
		description = "Ein glühender Kern aus flüssigem Gestein.",
		category = "skin",
		visual = { color = Color3.fromRGB(255, 96, 32), material = Enum.Material.Neon, glow = true },
	},
	skin_eis = {
		id = "skin_eis",
		displayName = "Eiskern",
		description = "Kristallklares Eis, kalt und wunderschön.",
		category = "skin",
		visual = { color = Color3.fromRGB(160, 220, 255), material = Enum.Material.Ice, glow = false },
	},
	skin_galaxie = {
		id = "skin_galaxie",
		displayName = "Galaxie-Kern",
		description = "Ein Kern wie ein Fenster ins Universum.",
		category = "skin",
		visual = {
			color = Color3.fromRGB(88, 60, 160),
			secondaryColor = Color3.fromRGB(180, 120, 255),
			material = Enum.Material.Glass,
			glow = true,
		},
	},

	-- Auren: Partikel, die den Planetenkern umspielen.
	aura_sternenstaub = {
		id = "aura_sternenstaub",
		displayName = "Sternenstaub-Aura",
		description = "Feiner Sternenstaub funkelt um deinen Planeten.",
		category = "aura",
		visual = { color = Color3.fromRGB(255, 255, 220) },
	},
	aura_regenbogen = {
		id = "aura_regenbogen",
		displayName = "Regenbogen-Aura",
		description = "Ein schimmernder Regenbogen-Schleier.",
		category = "aura",
		visual = { color = Color3.fromRGB(255, 80, 80), secondaryColor = Color3.fromRGB(80, 130, 255) },
	},

	-- Wettereffekte: Atmosphäre über dem Planeten.
	wetter_aurora = {
		id = "wetter_aurora",
		displayName = "Aurora",
		description = "Polarlichter tanzen über deinem Planeten.",
		category = "wetter",
		visual = { color = Color3.fromRGB(80, 255, 180), secondaryColor = Color3.fromRGB(120, 80, 255) },
	},
	wetter_sternschnuppen = {
		id = "wetter_sternschnuppen",
		displayName = "Sternschnuppen",
		description = "Ein steter Strom von Sternschnuppen.",
		category = "wetter",
		visual = { color = Color3.fromRGB(255, 240, 180) },
	},

	-- Haustiere: schweben dekorativ neben dem Besitzer.
	haustier_mini_komet = {
		id = "haustier_mini_komet",
		displayName = "Mini-Komet",
		description = "Ein kleiner Komet, der dir treu folgt.",
		category = "haustier",
		visual = { color = Color3.fromRGB(150, 200, 255), material = Enum.Material.Neon, glow = true },
	},
	haustier_sternenwelpe = {
		id = "haustier_sternenwelpe",
		displayName = "Sternenwelpe",
		description = "Ein verspielter Funke aus purem Sternenlicht.",
		category = "haustier",
		visual = { color = Color3.fromRGB(255, 210, 120), material = Enum.Material.Neon, glow = true },
	},
} :: { [string]: CosmeticDef }

-- Gamepässe: einmaliger Kauf, dauerhafte Freischaltung (auch nach Rejoin).
-- suggestedRobux ist NUR ein Vorschlag - TODO: echte Preise im Dashboard setzen.
MonetizationConfig.Gamepasses = {
	gp_kosmische_sammlung = {
		key = "gp_kosmische_sammlung",
		gamePassId = 0, -- TODO: echte Gamepass-ID eintragen
		displayName = "Kosmische Sammlung",
		description = "Galaxie-Kern-Skin und Sternenstaub-Aura für deinen Planeten.",
		grantsCosmetics = { "skin_galaxie", "aura_sternenstaub" },
		suggestedRobux = 149,
	},
	gp_wettermeister = {
		key = "gp_wettermeister",
		gamePassId = 0, -- TODO: echte Gamepass-ID eintragen
		displayName = "Wettermeister",
		description = "Aurora und Sternschnuppen als Wettereffekte.",
		grantsCosmetics = { "wetter_aurora", "wetter_sternschnuppen" },
		suggestedRobux = 99,
	},
	gp_haustier_freund = {
		key = "gp_haustier_freund",
		gamePassId = 0, -- TODO: echte Gamepass-ID eintragen
		displayName = "Haustier-Freund",
		description = "Mini-Komet und Sternenwelpe begleiten dich.",
		grantsCosmetics = { "haustier_mini_komet", "haustier_sternenwelpe" },
		suggestedRobux = 199,
	},
	gp_double_mult = {
		key = "gp_double_mult",
		gamePassId = 0, -- TODO: echte Gamepass-ID eintragen
		displayName = "2x Multiplikator",
		description = "Verdoppelt dauerhaft ALLE Energie-Einnahmen.",
		grantsCosmetics = {},
		perk = "double_mult",
		suggestedRobux = 349,
	},
	gp_pet_slots = {
		key = "gp_pet_slots",
		gamePassId = 0, -- TODO: echte Gamepass-ID eintragen
		displayName = "+2 Pet-Slots",
		description = "Rüste 5 statt 3 Pets gleichzeitig aus.",
		grantsCosmetics = {},
		perk = "pet_slots",
		suggestedRobux = 249,
	},
	gp_auto_harvest = {
		key = "gp_auto_harvest",
		gamePassId = 0, -- TODO: echte Gamepass-ID eintragen
		displayName = "🤖 Auto-Sammler",
		description = "Sammelt automatisch 1 Objekt pro Sekunde auf deiner Insel ein.",
		grantsCosmetics = {},
		perk = "auto_harvest",
		suggestedRobux = 299,
	},
	gp_vip = {
		key = "gp_vip",
		gamePassId = 0, -- TODO: echte Gamepass-ID eintragen
		displayName = "👑 VIP",
		description = "Goldener VIP-Trail, [VIP]-Chat-Tag und doppelter Tagesbonus.",
		grantsCosmetics = {},
		perk = "vip",
		suggestedRobux = 399,
	},
} :: { [string]: GamepassDef }

-- Zusätzliche Pet-Slots des +2-Gamepasses.
MonetizationConfig.PET_SLOTS_BONUS = 2

-- Zeitlich begrenzter 2x-Boost (Developer Product prod_boost_2x).
-- Mehrfachkauf verlängert die Laufzeit; überlebt Rejoins (boostUntil im Profil).
MonetizationConfig.BOOST_DURATION_SECONDS = 20 * 60
MonetizationConfig.BOOST_MULTIPLIER = 2

-- Developer Products: schalten je eine Kosmetik dauerhaft frei.
-- (Bereits gekaufte Produkte zeigt der Shop als "Im Besitz" an.)
MonetizationConfig.DeveloperProducts = {
	prod_skin_gold = {
		key = "prod_skin_gold",
		productId = 0, -- TODO: echte Produkt-ID eintragen
		displayName = "Goldener Kern",
		description = "Schaltet den goldenen Planetenkern frei.",
		grantsCosmetic = "skin_gold",
		suggestedRobux = 59,
	},
	prod_skin_lava = {
		key = "prod_skin_lava",
		productId = 0, -- TODO: echte Produkt-ID eintragen
		displayName = "Lava-Kern",
		description = "Schaltet den Lava-Planetenkern frei.",
		grantsCosmetic = "skin_lava",
		suggestedRobux = 59,
	},
	prod_skin_eis = {
		key = "prod_skin_eis",
		productId = 0, -- TODO: echte Produkt-ID eintragen
		displayName = "Eiskern",
		description = "Schaltet den Eis-Planetenkern frei.",
		grantsCosmetic = "skin_eis",
		suggestedRobux = 49,
	},
	prod_aura_regenbogen = {
		key = "prod_aura_regenbogen",
		productId = 0, -- TODO: echte Produkt-ID eintragen
		displayName = "Regenbogen-Aura",
		description = "Schaltet die Regenbogen-Aura frei.",
		grantsCosmetic = "aura_regenbogen",
		suggestedRobux = 79,
	},
	-- Währungspakete (wiederholt kaufbar; zählen NICHT zur Gesamt-Energie,
	-- schalten also weder Biome noch Rebirths frei).
	prod_energie_klein = {
		key = "prod_energie_klein",
		productId = 0, -- TODO: echte Produkt-ID eintragen
		displayName = "Energie-Paket S",
		description = "1.000 Energie sofort auf dein Konto.",
		grantsEnergy = 1000,
		suggestedRobux = 25,
	},
	prod_energie_mittel = {
		key = "prod_energie_mittel",
		productId = 0, -- TODO: echte Produkt-ID eintragen
		displayName = "Energie-Paket M",
		description = "6.000 Energie sofort auf dein Konto.",
		grantsEnergy = 6000,
		suggestedRobux = 99,
	},
	prod_energie_gross = {
		key = "prod_energie_gross",
		productId = 0, -- TODO: echte Produkt-ID eintragen
		displayName = "Energie-Paket L",
		description = "20.000 Energie sofort auf dein Konto.",
		grantsEnergy = 20000,
		suggestedRobux = 249,
	},
	prod_instant_rebirth = {
		key = "prod_instant_rebirth",
		productId = 0, -- TODO: echte Produkt-ID eintragen
		displayName = "Sofort-Wiedergeburt",
		description = "Löst sofort eine Wiedergeburt aus - ohne Schwelle.",
		perk = "instant_rebirth",
		suggestedRobux = 149,
	},
	prod_boost_2x = {
		key = "prod_boost_2x",
		productId = 0, -- TODO: echte Produkt-ID eintragen
		displayName = "🔥 2x-Boost (20 Min.)",
		description = "Verdoppelt 20 Minuten lang alle Energie-Einnahmen. Stapelt die Laufzeit.",
		perk = "boost_2x",
		suggestedRobux = 49,
	},
} :: { [string]: ProductDef }

-- Sortierte Schlüssel für stabile Shop-Anzeige.
function MonetizationConfig.getGamepassKeys(): { string }
	local keys = {}
	for key in MonetizationConfig.Gamepasses do
		table.insert(keys, key)
	end
	table.sort(keys)
	return keys
end

function MonetizationConfig.getProductKeys(): { string }
	local keys = {}
	for key in MonetizationConfig.DeveloperProducts do
		table.insert(keys, key)
	end
	table.sort(keys)
	return keys
end

-- Findet ein Developer Product anhand seiner Roblox-Produkt-ID (für ProcessReceipt).
function MonetizationConfig.findProductByProductId(productId: number): ProductDef?
	for _, def in MonetizationConfig.DeveloperProducts do
		if def.productId ~= 0 and def.productId == productId then
			return def
		end
	end
	return nil
end

return MonetizationConfig
