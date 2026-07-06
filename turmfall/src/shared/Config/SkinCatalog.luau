--!strict
-- SkinCatalog: alle kosmetischen Skins von Turmfall.
--
-- =========================================================================
-- WARUM SKINS REIN KOSMETISCH SIND (nicht verhandelbar):
-- Turmfall ist ein Physik-Wettbewerb: Alle 12 Spieler teilen sich EINEN
-- Turm und dieselben vier Teiltypen. Die komplette Fairness des Spiels
-- hängt daran, dass ein Schwerblock für JEDEN Spieler exakt gleich schwer,
-- gleich groß und gleich griffig ist. Kaufbare Physik-Vorteile (dichtere
-- Blöcke, klebrigere Keile, stabilere Federn) würden:
--   1. das Schuld-System entwerten - wer verlor, "hatte halt schlechtere
--      Teile", jede Kollaps-Zuweisung wäre anfechtbar,
--   2. Pay-to-Win erzeugen - zahlende Spieler bauen objektiv sicherer und
--      sabotieren effektiver, Gratis-Spieler verlieren systematisch,
--   3. das Balancing zerstören - jede neue Physik-Eigenschaft multipliziert
--      die Testmatrix aus 4 Teiltypen × 12 Spielern × Sabotage-Taktiken.
-- Deshalb verändern Skins AUSSCHLIESSLICH Optik (Material, Farbe, Textur,
-- Partikel). visualData darf keine Physik-Felder enthalten - validate()
-- unten erzwingt das und wird von den Tests und (ab Meilenstein 3) vom
-- Monetarisierungs-Guard geprüft.
-- =========================================================================

export type SkinRarity = "Common" | "Rare" | "Epic" | "Legendary"

-- category "teil"    = Skin für Bauteile (partType = Teiltyp oder "alle")
-- category "kollaps" = rein clientseitiger Kollaps-Effekt
export type SkinDef = {
	id: string,
	name: string,
	rarity: SkinRarity,
	category: "teil" | "kollaps",
	partType: string?, -- Teiltyp-ID oder "alle" (nur category "teil")
	visualData: {
		material: string?, -- Enum.Material-Name (nur Optik!)
		color: { r: number, g: number, b: number }?,
		textureAssetId: number?, -- 0 = Platzhalter (echte Textur später)
		sparkle: boolean?, -- Glanz-Partikel
		effectId: string?, -- Kollaps-Effekte: "konfetti" | "zeitlupe"
	},
	-- Freischaltung: genau EINE Quelle pro Skin.
	unlockCondition: string?, -- "start" = jeder besitzt ihn sofort
	priceRobux: number?, -- Verkauf über Developer Product (Meilenstein 3)
	priceDebris: number?, -- Zweitwährung "Trümmer" (Meilenstein 3)
}

local SkinCatalog = {}

SkinCatalog.Rarities = { "Common", "Rare", "Epic", "Legendary" }

SkinCatalog.RarityColors = {
	Common = { r = 158, g = 164, b = 186 },
	Rare = { r = 80, g = 150, b = 240 },
	Epic = { r = 170, g = 90, b = 220 },
	Legendary = { r = 255, g = 190, b = 60 },
}

-- Starter-Katalog: 12 Teil-Skins + 2 Kollaps-Effekte.
SkinCatalog.Skins = {
	-- Commons (frei bzw. sehr günstig - jeder soll sofort etwas haben).
	holz = {
		id = "holz",
		name = "Holz (Standard)",
		rarity = "Common",
		category = "teil",
		partType = "alle",
		visualData = { material = "WoodPlanks", color = { r = 150, g = 112, b = 70 } },
		unlockCondition = "start",
	},
	backstein = {
		id = "backstein",
		name = "Backstein",
		rarity = "Common",
		category = "teil",
		partType = "alle",
		visualData = { material = "Brick", color = { r = 168, g = 92, b = 72 } },
		unlockCondition = "start",
	},
	sandstein = {
		id = "sandstein",
		name = "Sandstein",
		rarity = "Common",
		category = "teil",
		partType = "alle",
		visualData = { material = "Sandstone", color = { r = 216, g = 190, b = 140 } },
		priceDebris = 150,
	},
	kiefernholz = {
		id = "kiefernholz",
		name = "Helles Kiefernholz",
		rarity = "Common",
		category = "teil",
		partType = "alle",
		visualData = { material = "Wood", color = { r = 198, g = 166, b = 120 } },
		priceDebris = 150,
	},

	-- Rares.
	marmor = {
		id = "marmor",
		name = "Marmor",
		rarity = "Rare",
		category = "teil",
		partType = "alle",
		visualData = { material = "Marble", color = { r = 226, g = 224, b = 218 } },
		priceDebris = 600,
	},
	obsidian = {
		id = "obsidian",
		name = "Obsidian",
		rarity = "Rare",
		category = "teil",
		partType = "alle",
		visualData = { material = "Basalt", color = { r = 38, g = 34, b = 48 } },
		priceDebris = 600,
	},
	rostmetall = {
		id = "rostmetall",
		name = "Rostmetall",
		rarity = "Rare",
		category = "teil",
		partType = "schwerblock",
		visualData = { material = "CorrodedMetal", color = { r = 150, g = 96, b = 60 } },
		priceRobux = 0, -- TODO: echten Preis im Creator Dashboard festlegen
	},
	eiskeil = {
		id = "eiskeil",
		name = "Eiskeil",
		rarity = "Rare",
		category = "teil",
		partType = "schraegkeil",
		visualData = { material = "Ice", color = { r = 170, g = 220, b = 250 } },
		priceRobux = 0, -- TODO: echten Preis im Creator Dashboard festlegen
	},

	-- Epics.
	goldbarren = {
		id = "goldbarren",
		name = "Goldbarren",
		rarity = "Epic",
		category = "teil",
		partType = "alle",
		visualData = { material = "Metal", color = { r = 235, g = 186, b = 60 }, sparkle = true },
		priceRobux = 0, -- TODO: echten Preis im Creator Dashboard festlegen
	},
	neonwabe = {
		id = "neonwabe",
		name = "Neonwabe",
		rarity = "Epic",
		category = "teil",
		partType = "alle",
		visualData = { material = "Neon", color = { r = 90, g = 220, b = 200 } },
		priceRobux = 0, -- TODO: echten Preis im Creator Dashboard festlegen
	},

	-- Legendaries.
	glasglanz = {
		id = "glasglanz",
		name = "Glasblock mit Glanz",
		rarity = "Legendary",
		category = "teil",
		partType = "alle",
		visualData = { material = "Glass", color = { r = 200, g = 230, b = 245 }, sparkle = true },
		priceRobux = 0, -- TODO: echten Preis im Creator Dashboard festlegen
	},
	galaxit = {
		id = "galaxit",
		name = "Galaxit",
		rarity = "Legendary",
		category = "teil",
		partType = "alle",
		visualData = { material = "Glass", color = { r = 96, g = 70, b = 180 }, sparkle = true, textureAssetId = 0 },
		priceRobux = 0, -- TODO: echten Preis im Creator Dashboard festlegen
	},

	-- Kollaps-Effekte (eigene Kategorie, rein clientseitig visuell).
	kollaps_konfetti = {
		id = "kollaps_konfetti",
		name = "Konfetti-Kollaps",
		rarity = "Epic",
		category = "kollaps",
		visualData = { effectId = "konfetti" },
		priceRobux = 0, -- TODO: echten Preis im Creator Dashboard festlegen
	},
	kollaps_zeitlupe = {
		id = "kollaps_zeitlupe",
		name = "Zeitlupen-Kollaps",
		rarity = "Legendary",
		category = "kollaps",
		visualData = { effectId = "zeitlupe" },
		priceRobux = 0, -- TODO: echten Preis im Creator Dashboard festlegen
	},
} :: { [string]: SkinDef }

-- Sortierte IDs (Rarität, dann Name) für stabile Shop-/Inventar-Anzeige.
function SkinCatalog.getSortedIds(): { string }
	local rarityOrder = { Common = 1, Rare = 2, Epic = 3, Legendary = 4 }
	local ids: { string } = {}
	for id in SkinCatalog.Skins do
		table.insert(ids, id)
	end
	table.sort(ids, function(a, b)
		local skinA = SkinCatalog.Skins[a]
		local skinB = SkinCatalog.Skins[b]
		if rarityOrder[skinA.rarity] ~= rarityOrder[skinB.rarity] then
			return rarityOrder[skinA.rarity] < rarityOrder[skinB.rarity]
		end
		return skinA.name < skinB.name
	end)
	return ids
end

-- GUARD: erzwingt, dass Skins rein kosmetisch bleiben (siehe Kopfkommentar).
-- Wird von den Tests und dem Monetarisierungs-Guard aufgerufen; wirft bei
-- Verstößen einen Fehler mit Klartext-Begründung.
local FORBIDDEN_VISUAL_FIELDS = { "density", "friction", "elasticity", "mass", "size", "gravity" }
local ALLOWED_VISUAL_FIELDS = {
	material = true,
	color = true,
	textureAssetId = true,
	sparkle = true,
	effectId = true,
}

function SkinCatalog.validate()
	for id, skin in SkinCatalog.Skins do
		assert(skin.id == id, `Skin {id}: id-Feld stimmt nicht mit dem Schlüssel überein`)
		assert(SkinCatalog.RarityColors[skin.rarity] ~= nil, `Skin {id}: unbekannte Rarität {skin.rarity}`)

		if skin.category == "teil" then
			assert(skin.partType ~= nil, `Skin {id}: Teil-Skin braucht partType`)
		else
			assert(skin.category == "kollaps", `Skin {id}: unbekannte Kategorie`)
			assert(skin.visualData.effectId ~= nil, `Skin {id}: Kollaps-Skin braucht effectId`)
		end

		-- Genau EINE Freischalt-Quelle.
		local sources = 0
		if skin.unlockCondition ~= nil then
			sources += 1
		end
		if skin.priceRobux ~= nil then
			sources += 1
		end
		if skin.priceDebris ~= nil then
			sources += 1
		end
		assert(sources == 1, `Skin {id}: braucht genau EINE Freischalt-Quelle (hat {sources})`)

		-- Kosmetik-Guard: keine Physik-Felder, nur erlaubte Optik-Felder.
		for _, forbidden in FORBIDDEN_VISUAL_FIELDS do
			assert(
				(skin.visualData :: { [string]: any })[forbidden] == nil,
				`Skin {id}: visualData.{forbidden} ist ein Physik-Feld - Skins sind REIN kosmetisch!`
			)
		end
		for field in skin.visualData :: { [string]: any } do
			assert(ALLOWED_VISUAL_FIELDS[field] == true, `Skin {id}: unbekanntes visualData-Feld {field}`)
		end
	end
end

return SkinCatalog
