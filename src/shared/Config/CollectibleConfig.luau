--!strict
-- Konfiguration aller Sammelobjekte (Tiere, Pflanzen, Artefakte).
-- Objekte mit `ultraRare = true` gehören NICHT zum normalen Loot-Pool:
-- Sie werden separat über RarityConfig.UltraRares gewürfelt und tauchen
-- deshalb bewusst nicht in getIdsByRarity() auf.

local Types = require(script.Parent.Parent.Types)

export type ItemType = "pet" | "trail" | "skin"

export type CollectibleDef = {
	id: string,
	displayName: string,
	description: string,
	rarity: Types.RarityTier,
	category: "Tier" | "Pflanze" | "Artefakt",
	tradable: boolean,
	ultraRare: boolean?, -- true = nur über Ultra-Rare-Wurf erhältlich
	itemType: ItemType?, -- wird unten automatisch aus der Kategorie gesetzt
	bonusMultiplier: number?, -- Pets: multiplikativer Ertrags-Bonus (unten gesetzt)
}

local CollectibleConfig = {}

CollectibleConfig.Collectibles = {
	-- ===== Common (6) =====
	feldmaus = {
		id = "feldmaus",
		displayName = "Feldmaus",
		description = "Ein flinker kleiner Nager, der durchs Gras huscht.",
		rarity = "Common",
		category = "Tier",
		tradable = true,
	},
	wiesenfalter = {
		id = "wiesenfalter",
		displayName = "Wiesenfalter",
		description = "Ein zarter Schmetterling mit weißen Flügeln.",
		rarity = "Common",
		category = "Tier",
		tradable = true,
	},
	gaensebluemchen = {
		id = "gaensebluemchen",
		displayName = "Gänseblümchen",
		description = "Klein, weiß und überall – der Klassiker jeder Wiese.",
		rarity = "Common",
		category = "Pflanze",
		tradable = true,
	},
	loewenzahn = {
		id = "loewenzahn",
		displayName = "Löwenzahn",
		description = "Pustet man ihn an, fliegen die Samen zu neuen Planeten.",
		rarity = "Common",
		category = "Pflanze",
		tradable = true,
	},
	kieselstein = {
		id = "kieselstein",
		displayName = "Glatter Kieselstein",
		description = "Vom Wasser rundgeschliffen. Liegt gut in der Hand.",
		rarity = "Common",
		category = "Artefakt",
		tradable = true,
	},
	tonscherbe = {
		id = "tonscherbe",
		displayName = "Alte Tonscherbe",
		description = "Bruchstück eines uralten Gefäßes. Wer hat es wohl geformt?",
		rarity = "Common",
		category = "Artefakt",
		tradable = true,
	},

	-- ===== Uncommon (6) =====
	rotfuchs = {
		id = "rotfuchs",
		displayName = "Rotfuchs",
		description = "Schlau und scheu – zeigt sich nur geduldigen Beobachtern.",
		rarity = "Uncommon",
		category = "Tier",
		tradable = true,
	},
	schneehase = {
		id = "schneehase",
		displayName = "Schneehase",
		description = "Sein weißes Fell macht ihn im Eis fast unsichtbar.",
		rarity = "Uncommon",
		category = "Tier",
		tradable = true,
	},
	glockenblume = {
		id = "glockenblume",
		displayName = "Glockenblume",
		description = "Läutet leise, wenn der Wind über den Planeten streicht.",
		rarity = "Uncommon",
		category = "Pflanze",
		tradable = true,
	},
	kaktusbluete = {
		id = "kaktusbluete",
		displayName = "Kaktusblüte",
		description = "Blüht nur eine Nacht lang mitten in der Wüste.",
		rarity = "Uncommon",
		category = "Pflanze",
		tradable = true,
	},
	bernstein = {
		id = "bernstein",
		displayName = "Bernsteinklumpen",
		description = "Uraltes Baumharz mit einem winzigen Käfer darin.",
		rarity = "Uncommon",
		category = "Artefakt",
		tradable = true,
	},
	kompass = {
		id = "kompass",
		displayName = "Rostiger Kompass",
		description = "Zeigt nicht nach Norden, sondern immer zum nächsten Schatz.",
		rarity = "Uncommon",
		category = "Artefakt",
		tradable = true,
	},

	-- ===== Rare (4) =====
	polarwolf = {
		id = "polarwolf",
		displayName = "Polarwolf",
		description = "Sein Heulen hallt über die Gletscher der Eiswelt.",
		rarity = "Rare",
		category = "Tier",
		tradable = true,
	},
	lavasalamander = {
		id = "lavasalamander",
		displayName = "Lavasalamander",
		description = "Badet in flüssiger Lava, als wäre sie warmes Wasser.",
		rarity = "Rare",
		category = "Tier",
		tradable = true,
	},
	mondblume = {
		id = "mondblume",
		displayName = "Mondblume",
		description = "Öffnet ihre silbernen Blüten nur im Licht der Monde.",
		rarity = "Rare",
		category = "Pflanze",
		tradable = true,
	},
	sternenkarte = {
		id = "sternenkarte",
		displayName = "Uralte Sternenkarte",
		description = "Zeigt Galaxien, die noch niemand besucht hat.",
		rarity = "Rare",
		category = "Artefakt",
		tradable = true,
	},

	-- ===== Epic (3) =====
	phoenixkueken = {
		id = "phoenixkueken",
		displayName = "Phönixküken",
		description = "Glüht sanft und wird aus seiner eigenen Asche neu geboren.",
		rarity = "Epic",
		category = "Tier",
		tradable = true,
	},
	geisterorchidee = {
		id = "geisterorchidee",
		displayName = "Geisterorchidee",
		description = "Halb durchsichtig – manche behaupten, sie flüstert nachts.",
		rarity = "Epic",
		category = "Pflanze",
		tradable = true,
	},
	meteoritensplitter = {
		id = "meteoritensplitter",
		displayName = "Meteoritensplitter",
		description = "Noch warm vom Sturz durch die Atmosphäre.",
		rarity = "Epic",
		category = "Artefakt",
		tradable = true,
	},

	-- ===== Legendary (2, regulär) =====
	sternenwal = {
		id = "sternenwal",
		displayName = "Sternenwal",
		description = "Gleitet lautlos zwischen den Planeten und singt Lieder aus Sternenstaub.",
		rarity = "Legendary",
		category = "Tier",
		tradable = true,
	},
	weltenbaum_setzling = {
		id = "weltenbaum_setzling",
		displayName = "Weltenbaum-Setzling",
		description = "Ein junger Trieb des Baumes, der einst alle Welten verband.",
		rarity = "Legendary",
		category = "Pflanze",
		tradable = true,
	},

	-- ===== Ultra-Rares (nur über RarityConfig.UltraRares erhältlich) =====
	kristall = {
		id = "kristall",
		displayName = "Leuchtender Kristall",
		description = "Ein 1-zu-10.000-Fund, der in allen Farben des Universums schimmert.",
		rarity = "Legendary",
		category = "Artefakt",
		tradable = true,
		ultraRare = true,
	},
	goldener_drache = {
		id = "goldener_drache",
		displayName = "Goldener Drache",
		description = "Ein 1-zu-100.000-Fund. Sein Schuppenglanz überstrahlt ganze Galaxien.",
		rarity = "Mythic",
		category = "Tier",
		tradable = true,
		ultraRare = true,
	},
	kosmischer_kern = {
		id = "kosmischer_kern",
		displayName = "Kosmischer Kern",
		description = "Ein 1-zu-1.000.000-Fund: das pulsierende Herz eines vergangenen Universums.",
		rarity = "Cosmic",
		category = "Artefakt",
		tradable = true,
		ultraRare = true,
	},
} :: { [string]: CollectibleDef }

-- Gibt alle regulären Sammelobjekt-IDs einer Seltenheitsstufe zurück.
-- Ultra-Rares werden bewusst ausgefiltert (separater Wurf) und alphabetisch
-- sortiert, damit die Auswahl deterministisch bleibt.
function CollectibleConfig.getIdsByRarity(rarity: string): { string }
	local ids: { string } = {}
	for id, def in CollectibleConfig.Collectibles do
		if def.rarity == rarity and def.ultraRare ~= true then
			table.insert(ids, id)
		end
	end
	table.sort(ids)
	return ids
end

--------------------------------------------------------------------------
-- Ausrüstbare Item-Typen (Inventar/Equip-System)
--------------------------------------------------------------------------

-- Loot-Kategorie -> ausrüstbarer Typ: Tiere folgen als Pets (mit Bonus),
-- Artefakte werden zu Trails, Pflanzen zu Spieler-Skins (Aura-Glow).
local CATEGORY_TO_ITEM_TYPE: { [string]: ItemType } = {
	Tier = "pet",
	Artefakt = "trail",
	Pflanze = "skin",
}

-- Multiplikativer Pet-Bonus je Seltenheit (nur wenn ausgerüstet).
local PET_BONUS_BY_RARITY: { [string]: number } = {
	Common = 1.05,
	Uncommon = 1.1,
	Rare = 1.2,
	Epic = 1.35,
	Legendary = 1.6,
	Mythic = 2.0,
	Cosmic = 3.0,
}

for _, def in CollectibleConfig.Collectibles do
	def.itemType = CATEGORY_TO_ITEM_TYPE[def.category] or "pet"
	def.bonusMultiplier = if def.itemType == "pet" then PET_BONUS_BY_RARITY[def.rarity] or 1 else 1
end

-- Effektiver Item-Typ (nie nil, nach der Zuordnung oben).
function CollectibleConfig.getItemType(collectibleId: string): ItemType?
	local def = CollectibleConfig.Collectibles[collectibleId]
	if def == nil then
		return nil
	end
	return def.itemType or "pet"
end

return CollectibleConfig
