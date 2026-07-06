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
	perk: ("double_mult" | "pet_slots" | "vip")?, -- dauerhafter Spielvorteil
}

export type ProductDef = {
	key: string,
	productId: number, -- PLATZHALTER: echte ID aus dem Creator Dashboard eintragen
	displayName: string,
	description: string,
	grantsCosmetic: Types.CosmeticId?, -- einmalige Kosmetik-Freischaltung
	grantsEnergy: number?, -- Währungspaket (wiederholt kaufbar)
	perk: "instant_rebirth"?, -- Sofort-Wiedergeburt (wiederholt kaufbar)
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
MonetizationConfig.Gamepasses = {
	gp_kosmische_sammlung = {
		key = "gp_kosmische_sammlung",
		gamePassId = 0,
		displayName = "Kosmische Sammlung",
		description = "Galaxie-Kern-Skin und Sternenstaub-Aura für deinen Planeten.",
		grantsCosmetics = { "skin_galaxie", "aura_sternenstaub" },
	},
	gp_wettermeister = {
		key = "gp_wettermeister",
		gamePassId = 0,
		displayName = "Wettermeister",
		description = "Aurora und Sternschnuppen als Wettereffekte.",
		grantsCosmetics = { "wetter_aurora", "wetter_sternschnuppen" },
	},
	gp_haustier_freund = {
		key = "gp_haustier_freund",
		gamePassId = 0,
		displayName = "Haustier-Freund",
		description = "Mini-Komet und Sternenwelpe begleiten dich.",
		grantsCosmetics = { "haustier_mini_komet", "haustier_sternenwelpe" },
	},
	gp_double_mult = {
		key = "gp_double_mult",
		gamePassId = 0,
		displayName = "2x Multiplikator",
		description = "Verdoppelt dauerhaft ALLE Energie-Einnahmen.",
		grantsCosmetics = {},
		perk = "double_mult",
	},
	gp_pet_slots = {
		key = "gp_pet_slots",
		gamePassId = 0,
		displayName = "+2 Pet-Slots",
		description = "Rüste 5 statt 3 Pets gleichzeitig aus.",
		grantsCosmetics = {},
		perk = "pet_slots",
	},
	gp_vip = {
		key = "gp_vip",
		gamePassId = 0,
		displayName = "👑 VIP",
		description = "Goldener VIP-Trail, [VIP]-Chat-Tag und doppelter Tagesbonus.",
		grantsCosmetics = {},
		perk = "vip",
	},
} :: { [string]: GamepassDef }

-- Zusätzliche Pet-Slots des +2-Gamepasses.
MonetizationConfig.PET_SLOTS_BONUS = 2

-- Developer Products: schalten je eine Kosmetik dauerhaft frei.
-- (Bereits gekaufte Produkte zeigt der Shop als "Im Besitz" an.)
MonetizationConfig.DeveloperProducts = {
	prod_skin_gold = {
		key = "prod_skin_gold",
		productId = 0,
		displayName = "Goldener Kern",
		description = "Schaltet den goldenen Planetenkern frei.",
		grantsCosmetic = "skin_gold",
	},
	prod_skin_lava = {
		key = "prod_skin_lava",
		productId = 0,
		displayName = "Lava-Kern",
		description = "Schaltet den Lava-Planetenkern frei.",
		grantsCosmetic = "skin_lava",
	},
	prod_skin_eis = {
		key = "prod_skin_eis",
		productId = 0,
		displayName = "Eiskern",
		description = "Schaltet den Eis-Planetenkern frei.",
		grantsCosmetic = "skin_eis",
	},
	prod_aura_regenbogen = {
		key = "prod_aura_regenbogen",
		productId = 0,
		displayName = "Regenbogen-Aura",
		description = "Schaltet die Regenbogen-Aura frei.",
		grantsCosmetic = "aura_regenbogen",
	},
	-- Währungspakete (wiederholt kaufbar; zählen NICHT zur Gesamt-Energie,
	-- schalten also weder Biome noch Rebirths frei).
	prod_energie_klein = {
		key = "prod_energie_klein",
		productId = 0,
		displayName = "Energie-Paket S",
		description = "1.000 Energie sofort auf dein Konto.",
		grantsEnergy = 1000,
	},
	prod_energie_mittel = {
		key = "prod_energie_mittel",
		productId = 0,
		displayName = "Energie-Paket M",
		description = "6.000 Energie sofort auf dein Konto.",
		grantsEnergy = 6000,
	},
	prod_energie_gross = {
		key = "prod_energie_gross",
		productId = 0,
		displayName = "Energie-Paket L",
		description = "20.000 Energie sofort auf dein Konto.",
		grantsEnergy = 20000,
	},
	prod_instant_rebirth = {
		key = "prod_instant_rebirth",
		productId = 0,
		displayName = "Sofort-Wiedergeburt",
		description = "Löst sofort eine Wiedergeburt aus - ohne Schwelle.",
		perk = "instant_rebirth",
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
