--!strict
-- MonetizationCatalog: Developer Products, Bundles und der Season-Pass.
--
-- VERKAUFT WIRD AUSSCHLIESSLICH KOSMETIK (einzelne Skins, Skin-Bundles,
-- ein kosmetischer Season-Pass). NICHT verkäuflich: Teile, Deck-Slots,
-- Punkte, Trümmer oder irgendein Physik-/Gameplay-Vorteil. validate()
-- unten ist der GUARD, der das strukturell erzwingt: Ein Produkt KANN
-- nur Skin-IDs aus dem SkinCatalog vergeben - es gibt schlicht kein Feld,
-- über das Gameplay-Werte an Käufe gekoppelt werden könnten, und jeder
-- Verweis wird gegen den (selbst rein kosmetischen) SkinCatalog geprüft.
--
-- =========================================================================
-- TODO - ECHTE IDs EINTRAGEN:
-- Code kann keine Produkte erstellen. Die Produkte/Gamepässe müssen
-- manuell im Creator Dashboard (Monetarisierung) angelegt werden; danach
-- die echten IDs unten bei productId/gamePassId eintragen. Solange eine
-- ID 0 ist, zeigt der Shop "Bald verfügbar" und Käufe laufen nur im
-- Studio-Testmodus (SimulatePurchase).
-- =========================================================================

local SkinCatalog = require(script.Parent.SkinCatalog)

export type ProductDef = {
	key: string,
	productId: number, -- PLATZHALTER 0 -> TODO: echte ID aus dem Dashboard
	displayName: string,
	grantsSkins: { string }, -- NUR Skin-IDs - nichts anderes ist vergebbar
}

local MonetizationCatalog = {}

-- Developer Products: einzelne Skins und Bundles.
MonetizationCatalog.DEVPRODUCT_IDS = {
	skin_rostmetall = {
		key = "skin_rostmetall",
		productId = 0, -- TODO: echte Produkt-ID eintragen
		displayName = "Skin: Rostmetall",
		grantsSkins = { "rostmetall" },
	},
	skin_eiskeil = {
		key = "skin_eiskeil",
		productId = 0, -- TODO: echte Produkt-ID eintragen
		displayName = "Skin: Eiskeil",
		grantsSkins = { "eiskeil" },
	},
	skin_goldbarren = {
		key = "skin_goldbarren",
		productId = 0, -- TODO: echte Produkt-ID eintragen
		displayName = "Skin: Goldbarren",
		grantsSkins = { "goldbarren" },
	},
	skin_neonwabe = {
		key = "skin_neonwabe",
		productId = 0, -- TODO: echte Produkt-ID eintragen
		displayName = "Skin: Neonwabe",
		grantsSkins = { "neonwabe" },
	},
	skin_glasglanz = {
		key = "skin_glasglanz",
		productId = 0, -- TODO: echte Produkt-ID eintragen
		displayName = "Skin: Glasblock mit Glanz",
		grantsSkins = { "glasglanz" },
	},
	skin_kollaps_konfetti = {
		key = "skin_kollaps_konfetti",
		productId = 0, -- TODO: echte Produkt-ID eintragen
		displayName = "Kollaps-Effekt: Konfetti",
		grantsSkins = { "kollaps_konfetti" },
	},
	-- Bundles (günstiger als einzeln - klassischer Skin-Shop).
	bundle_baumeister = {
		key = "bundle_baumeister",
		productId = 0, -- TODO: echte Produkt-ID eintragen
		displayName = "Bundle: Baumeister (Rostmetall + Eiskeil)",
		grantsSkins = { "rostmetall", "eiskeil" },
	},
	bundle_glanzvoll = {
		key = "bundle_glanzvoll",
		productId = 0, -- TODO: echte Produkt-ID eintragen
		displayName = "Bundle: Glanzvoll (Goldbarren + Neonwabe)",
		grantsSkins = { "goldbarren", "neonwabe" },
	},
} :: { [string]: ProductDef }

-- Kosmetischer Season-Pass (Gamepass): schaltet exklusive Skins frei.
MonetizationCatalog.SEASON_PASS_GAMEPASS_ID = 0 -- TODO: echte Gamepass-ID eintragen
MonetizationCatalog.SEASON_PASS_SKINS = { "galaxit", "kollaps_zeitlupe" }

-- Trümmer-Ökonomie (Zweitwährung, ERSPIELT und bewusst NICHT kaufbar,
-- damit Free-Spieler eine eigene Progression haben).
MonetizationCatalog.DEBRIS_PER_POINTS = 5 -- 1 Trümmer je 5 Punkte
MonetizationCatalog.DEBRIS_ROUND_BONUS = 10 -- Teilnahme-Bonus pro Runde

function MonetizationCatalog.getSortedProductKeys(): { string }
	local keys = {}
	for key in MonetizationCatalog.DEVPRODUCT_IDS do
		table.insert(keys, key)
	end
	table.sort(keys)
	return keys
end

-- Findet ein Produkt anhand der Roblox-Produkt-ID (für ProcessReceipt).
-- Platzhalter-IDs (0) matchen NIE.
function MonetizationCatalog.findProductByProductId(productId: number): ProductDef?
	for _, def in MonetizationCatalog.DEVPRODUCT_IDS do
		if def.productId ~= 0 and def.productId == productId then
			return def
		end
	end
	return nil
end

-- GUARD (siehe Kopfkommentar): stellt sicher, dass jedes Produkt und der
-- Season-Pass ausschließlich existierende, rein kosmetische Skins vergeben.
function MonetizationCatalog.validate()
	SkinCatalog.validate() -- erst der Kosmetik-Guard des Skin-Katalogs

	for key, def in MonetizationCatalog.DEVPRODUCT_IDS do
		assert(def.key == key, `Produkt {key}: key-Feld stimmt nicht`)
		assert(#def.grantsSkins >= 1, `Produkt {key}: vergibt nichts`)
		for _, skinId in def.grantsSkins do
			local skin = SkinCatalog.Skins[skinId]
			assert(skin ~= nil, `Produkt {key}: unbekannter Skin {skinId} - nur Kosmetik ist verkäuflich!`)
			assert(
				skin.priceRobux ~= nil,
				`Produkt {key}: Skin {skinId} ist nicht als Robux-Skin markiert (priceRobux fehlt)`
			)
		end
	end

	for _, skinId in MonetizationCatalog.SEASON_PASS_SKINS do
		local skin = SkinCatalog.Skins[skinId]
		assert(skin ~= nil, `Season-Pass: unbekannter Skin {skinId}`)
		assert(skin.priceRobux ~= nil, `Season-Pass: Skin {skinId} braucht priceRobux als Quelle`)
	end

	-- Jeder Robux-Skin muss über GENAU einen Weg erreichbar sein
	-- (Produkt, Bundle oder Season-Pass) - sonst ist er totes Inventar.
	for skinId, skin in SkinCatalog.Skins do
		if skin.priceRobux == nil then
			continue
		end
		local reachable = table.find(MonetizationCatalog.SEASON_PASS_SKINS, skinId) ~= nil
		for _, def in MonetizationCatalog.DEVPRODUCT_IDS do
			if table.find(def.grantsSkins, skinId) ~= nil then
				reachable = true
			end
		end
		assert(reachable, `Robux-Skin {skinId} ist über kein Produkt/Bundle/Pass erreichbar`)
	end
end

return MonetizationCatalog
