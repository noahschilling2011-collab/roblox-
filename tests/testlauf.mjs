// Testlauf für Planet Forge: lädt die echten Shared-Module des Spiels in eine
// echte Luau-VM (luau-web/WASM) und führt Logik- und Balancing-Tests aus.
import { LuauState } from "luau-web";
import { readFileSync } from "fs";

const REPO = new URL("..", import.meta.url).pathname.replace(/\/$/, "");

function loadModule(relPath) {
  let src = readFileSync(`${REPO}/${relPath}`, "utf8");
  // Roblox-spezifische Zeilen für die reine Luau-VM anpassen:
  src = src.replace(/^--!strict\s*$/m, "");
  src = src.replace(/^local (\w+) = require\(.+\)$/gm, 'local $1 = __deps["$1"]');
  src = src.replace(/^export type/gm, "type");
  return src;
}

const modules = [
  ["Types", "src/shared/Types.luau"],
  ["GameConfig", "src/shared/Config/GameConfig.luau"],
  ["ProgressionConfig", "src/shared/Config/ProgressionConfig.luau"],
  ["WeightedRandom", "src/shared/Util/WeightedRandom.luau"],
  ["RarityConfig", "src/shared/Config/RarityConfig.luau"],
  ["CollectibleConfig", "src/shared/Config/CollectibleConfig.luau"],
  ["BiomeConfig", "src/shared/Config/BiomeConfig.luau"],
  ["EventConfig", "src/shared/Config/EventConfig.luau"],
  ["MonetizationConfig", "src/shared/Config/MonetizationConfig.luau"],
];

const prelude = `
-- Stubs für Roblox-Globals (nur was die Shared-Module brauchen).
local Color3 = {
	fromRGB = function(r, g, b) return { r = r, g = g, b = b, kind = "Color3" } end,
	new = function(r, g, b) return { r = r, g = g, b = b, kind = "Color3" } end,
}
local Enum = setmetatable({}, { __index = function(_, class)
	return setmetatable({}, { __index = function(_, item) return class .. "." .. item end })
end })
local Random = {
	new = function()
		local rng = {}
		function rng:NextNumber(a, b)
			if a == nil then return math.random() end
			return a + math.random() * (b - a)
		end
		function rng:NextInteger(a, b) return math.random(a, b) end
		return rng
	end,
}
local game = { GetService = function() return {} end }
local __deps = {}
`;

let body = prelude;
for (const [name, path] of modules) {
  body += `\n__deps["${name}"] = (function()\n${loadModule(path)}\nend)()\n`;
}

const tests = `
local GameConfig = __deps["GameConfig"]
local ProgressionConfig = __deps["ProgressionConfig"]
local WeightedRandom = __deps["WeightedRandom"]
local RarityConfig = __deps["RarityConfig"]
local CollectibleConfig = __deps["CollectibleConfig"]
local BiomeConfig = __deps["BiomeConfig"]
local EventConfig = __deps["EventConfig"]
local MonetizationConfig = __deps["MonetizationConfig"]

local results = {}
local passed = 0
local failed = 0

local function test(name, fn)
	local ok, err = pcall(fn)
	if ok then
		passed += 1
		table.insert(results, "OK   | " .. name)
	else
		failed += 1
		table.insert(results, "FAIL | " .. name .. " -> " .. tostring(err))
	end
end

local function expect(cond, msg)
	if not cond then
		error(msg, 0)
	end
end

-- 1) GameConfig-Canon
test("GameConfig: Canon-Konstanten", function()
	expect(GameConfig.PLANET_SLOTS == 12, "PLANET_SLOTS != 12")
	expect(GameConfig.LOOT_ROLL_COST == 25, "LOOT_ROLL_COST != 25")
	expect(GameConfig.PROFILE_SCHEMA_VERSION == 10, "Schema-Version != 10")
	expect(GameConfig.BASE_PET_SLOTS == 3, "BASE_PET_SLOTS != 3")
	expect(GameConfig.PURCHASE_LOG_LIMIT >= 10, "PURCHASE_LOG_LIMIT < 10")
	expect(GameConfig.MAX_TRADE_ITEMS_PER_SIDE == 4, "Trade-Items != 4")
	expect(GameConfig.TRADE_LOCK_SECONDS == 3, "Trade-Lock != 3")
	expect(GameConfig.BASE_MAGNET_RADIUS > 0, "BASE_MAGNET_RADIUS <= 0")
	expect(GameConfig.BASE_BACKPACK_CAPACITY >= 5, "BASE_BACKPACK_CAPACITY < 5")
end)

test("Sammel-Loop: Harvest-Definition fuer jedes Biom", function()
	local count = 0
	for biomeId in BiomeConfig.Biomes do
		local harvest = BiomeConfig.Harvest[biomeId]
		expect(harvest ~= nil, "Harvest fehlt: " .. biomeId)
		expect(harvest.value > 0, biomeId .. ": value <= 0")
		expect(harvest.maxActive >= 1, biomeId .. ": maxActive < 1")
		expect(harvest.respawnSeconds > 0, biomeId .. ": respawnSeconds <= 0")
		count += 1
	end
	expect(count == 10, "Harvest-Anzahl != 10")
	expect(BiomeConfig.getMaxActive("wiese", 1) == 6, "getMaxActive(wiese, 1) != 6")
	expect(BiomeConfig.getMaxActive("wiese", 5) == 14, "getMaxActive(wiese, 5) != 14")
end)

test("ProgressionConfig: Upgrade-Kosten exponentiell (Faktor 1.15-1.25)", function()
	for upgradeId, def in ProgressionConfig.Upgrades do
		expect(def.baseCost > 0, upgradeId .. ": baseCost <= 0")
		expect(def.costFactor >= 1.15 and def.costFactor <= 1.25, upgradeId .. ": Faktor ausserhalb 1.15-1.25")
		expect(
			ProgressionConfig.getUpgradeCost(upgradeId, 0) == def.baseCost,
			upgradeId .. ": Level-0-Kosten != baseCost"
		)
		expect(
			ProgressionConfig.getUpgradeCost(upgradeId, 5) == math.floor(def.baseCost * def.costFactor ^ 5),
			upgradeId .. ": Level-5-Formel falsch"
		)
	end
end)

test("GameConfig: Tagesbonus-Tabelle", function()
	expect(#GameConfig.DAILY_REWARDS == 7, "DAILY_REWARDS braucht 7 Eintraege")
	expect(GameConfig.DAILY_REWARDS[1] == 50, "Tag 1 != 50")
	expect(GameConfig.DAILY_REWARDS[7] == 1200, "Tag 7 != 1200 (Retention-Anker)")
	expect(GameConfig.OFFLINE_EARNINGS_RATE == 0.5, "Offline-Rate != 0.5")
	expect(GameConfig.OFFLINE_EARNINGS_CAP_HOURS == 8, "Offline-Cap != 8h")
	expect(math.abs(GameConfig.FRIEND_BOOST_PER_FRIEND - 0.1) < 1e-9, "Freunde-Boost != 10% pro Freund")
	expect(GameConfig.FRIEND_BOOST_MAX_FRIENDS == 3, "Freunde-Boost-Deckel != 3 Freunde (+30%)")
	expect(GameConfig.AUTO_HARVEST_INTERVAL_SECONDS == 1, "Auto-Harvest-Takt != 1s")
	for i = 2, #GameConfig.DAILY_REWARDS do
		expect(GameConfig.DAILY_REWARDS[i] > GameConfig.DAILY_REWARDS[i - 1], "nicht streng aufsteigend bei Index " .. i)
	end
end)

-- 2) Biome-Canon (alle 10 exakt)
test("BiomeConfig: alle 10 Canon-Biome exakt", function()
	local canon = {
		wiese = { 25, 0, 1 },
		wald = { 100, 0, 2 },
		wueste = { 250, 500, 4 },
		ozean = { 500, 1000, 8 },
		dschungel = { 1000, 2500, 15 },
		eiswelt = { 2500, 5000, 30 },
		vulkan = { 5000, 10000, 60 },
		pilzwald = { 10000, 25000, 120 },
		kristallfelder = { 25000, 50000, 250 },
		kosmische_ebene = { 100000, 250000, 600 },
	}
	local count = 0
	for id, expected in canon do
		local def = BiomeConfig.Biomes[id]
		expect(def ~= nil, "Biom fehlt: " .. id)
		expect(def.baseCost == expected[1], id .. ": baseCost " .. def.baseCost .. " != " .. expected[1])
		expect(def.unlockAtLifetimeEnergy == expected[2], id .. ": unlock falsch")
		expect(def.baseEnergyPerMinute == expected[3], id .. ": Einkommen falsch")
		expect(def.maxLevel == 5, id .. ": maxLevel != 5")
		expect(def.upgradeCostMultiplier == 1.75, id .. ": Multiplikator != 1.75")
		count += 1
	end
	for id in BiomeConfig.Biomes do
		expect(canon[id] ~= nil, "unbekanntes Biom: " .. id)
	end
	expect(count == 10, "Biom-Anzahl != 10")
end)

test("BiomeConfig: getSortedIds aufsteigend nach Kosten", function()
	local sorted = BiomeConfig.getSortedIds()
	expect(#sorted == 10, "Anzahl != 10")
	expect(sorted[1] == "wiese", "erstes Biom != wiese")
	expect(sorted[10] == "kosmische_ebene", "letztes Biom != kosmische_ebene")
	for i = 2, #sorted do
		expect(
			BiomeConfig.Biomes[sorted[i - 1]].baseCost <= BiomeConfig.Biomes[sorted[i]].baseCost,
			"nicht aufsteigend bei " .. sorted[i]
		)
	end
end)

test("BiomeConfig: Upgrade-Formel floor(baseCost * 1.75^level)", function()
	expect(BiomeConfig.getUpgradeCost("wiese", 1) == 43, "wiese L1 != 43")
	expect(BiomeConfig.getUpgradeCost("wiese", 4) == math.floor(25 * 1.75 ^ 4), "wiese L4 falsch")
	expect(BiomeConfig.getUpgradeCost("vulkan", 3) == math.floor(5000 * 1.75 ^ 3), "vulkan L3 falsch")
end)

-- 3) Seltenheiten
test("RarityConfig: Tier-Gewichte 60/25/10/4/1, Mythic/Cosmic 0", function()
	local weights = { Common = 60, Uncommon = 25, Rare = 10, Epic = 4, Legendary = 1, Mythic = 0, Cosmic = 0 }
	for tier, weight in weights do
		expect(RarityConfig.Tiers[tier] ~= nil, "Tier fehlt: " .. tier)
		expect(RarityConfig.Tiers[tier].weight == weight, tier .. ": Gewicht falsch")
	end
end)

test("RarityConfig: Ultra-Rares exakt 1:1.000.000 / 1:100.000 / 1:10.000", function()
	expect(#RarityConfig.UltraRares == 3, "Anzahl != 3")
	expect(RarityConfig.UltraRares[1].collectibleId == "kosmischer_kern", "Platz 1 falsch")
	expect(RarityConfig.UltraRares[1].oneIn == 1000000, "kosmischer_kern != 1e6")
	expect(RarityConfig.UltraRares[2].collectibleId == "goldener_drache", "Platz 2 falsch")
	expect(RarityConfig.UltraRares[2].oneIn == 100000, "goldener_drache != 1e5")
	expect(RarityConfig.UltraRares[3].collectibleId == "kristall", "Platz 3 falsch")
	expect(RarityConfig.UltraRares[3].oneIn == 10000, "kristall != 1e4")
end)

test("CollectibleConfig: Pools vollstaendig, Ultra-Rares separat", function()
	local minima = { Common = 6, Uncommon = 6, Rare = 4, Epic = 3, Legendary = 2 }
	for tier, minimum in minima do
		local ids = CollectibleConfig.getIdsByRarity(tier)
		expect(#ids >= minimum, tier .. "-Pool zu klein: " .. #ids .. " < " .. minimum)
	end
	for _, ultra in RarityConfig.UltraRares do
		local def = CollectibleConfig.Collectibles[ultra.collectibleId]
		expect(def ~= nil, "Ultra-Rare fehlt im Katalog: " .. ultra.collectibleId)
		for _, poolId in CollectibleConfig.getIdsByRarity(def.rarity) do
			expect(poolId ~= ultra.collectibleId, ultra.collectibleId .. " faelschlich im normalen Pool")
		end
	end
	expect(CollectibleConfig.Collectibles["kristall"].rarity == "Legendary", "kristall != Legendary")
	expect(CollectibleConfig.Collectibles["goldener_drache"].rarity == "Mythic", "drache != Mythic")
	expect(CollectibleConfig.Collectibles["kosmischer_kern"].rarity == "Cosmic", "kern != Cosmic")
end)

-- 4) Events
test("EventConfig: alle 5 Canon-Events exakt", function()
	local canon = {
		meteoritenschauer = { 300, 30, 1, 3 },
		goldener_regen = { 360, 25, 2, 1 },
		kreaturen_spawn = { 300, 15, 1, 5 },
		alien_invasion = { 480, 20, 1.5, 1.5 },
		schwarzes_loch = { 600, 10, 3, 1 },
	}
	local count = 0
	for id, expected in canon do
		local def = EventConfig.Events[id]
		expect(def ~= nil, "Event fehlt: " .. id)
		expect(def.durationSeconds == expected[1], id .. ": Dauer falsch")
		expect(def.weight == expected[2], id .. ": Gewicht falsch")
		expect(def.energyMultiplier == expected[3], id .. ": Energie-Multiplikator falsch")
		expect(def.lootLuckMultiplier == expected[4], id .. ": Loot-Glueck falsch")
		count += 1
	end
	for id in EventConfig.Events do
		expect(canon[id] ~= nil, "unbekanntes Event: " .. id)
	end
	expect(count == 5, "Event-Anzahl != 5")
end)

-- 5) Monetarisierung
test("MonetizationConfig: alle Verweise gueltig", function()
	for key, def in MonetizationConfig.Gamepasses do
		for _, cosmeticId in def.grantsCosmetics do
			expect(MonetizationConfig.Cosmetics[cosmeticId] ~= nil, key .. " vergibt unbekannte Kosmetik " .. cosmeticId)
		end
	end
	for key, def in MonetizationConfig.DeveloperProducts do
		if def.grantsCosmetic ~= nil then
			expect(MonetizationConfig.Cosmetics[def.grantsCosmetic] ~= nil, key .. " vergibt unbekannte Kosmetik")
		end
	end
	for id, def in MonetizationConfig.Cosmetics do
		expect(MonetizationConfig.CategoryNames[def.category] ~= nil, id .. ": unbekannte Kategorie")
	end
	expect(MonetizationConfig.findProductByProductId(999999) == nil, "findProductByProductId muss fuer unbekannte IDs nil geben")
	expect(MonetizationConfig.findProductByProductId(0) == nil, "Platzhalter-ID 0 darf nie matchen")
end)

-- 6) WeightedRandom: echte Verteilungstests
test("WeightedRandom.pick: Verteilung entspricht den Gewichten", function()
	math.randomseed(42)
	local entries = {}
	local weights = { Common = 60, Uncommon = 25, Rare = 10, Epic = 4, Legendary = 1 }
	for name, weight in weights do
		table.insert(entries, { value = name, weight = weight })
	end
	local counts = { Common = 0, Uncommon = 0, Rare = 0, Epic = 0, Legendary = 0 }
	local n = 200000
	for _ = 1, n do
		local picked = WeightedRandom.pick(entries)
		counts[picked] += 1
	end
	for name, weight in weights do
		local expected = n * weight / 100
		local actual = counts[name]
		local deviation = math.abs(actual - expected) / expected
		expect(deviation < 0.15, name .. ": Abweichung " .. math.floor(deviation * 100) .. "% (erwartet ~" .. expected .. ", war " .. actual .. ")")
	end
end)

test("WeightedRandom.oneIn: Trefferquote ~1/n", function()
	math.randomseed(1337)
	local n = 100000
	local hits = 0
	for _ = 1, n do
		if WeightedRandom.oneIn(4) then
			hits += 1
		end
	end
	local rate = hits / n
	expect(rate > 0.22 and rate < 0.28, "oneIn(4)-Quote " .. rate .. " weicht zu stark von 0.25 ab")
end)

-- 7) Loot-Wurf-Simulation (Spiegel der LootService-Logik)
test("Loot-Simulation: 50.000 Wuerfe ohne Fehler, nie Mythic/Cosmic im Pool-Wurf", function()
	math.randomseed(7)
	local tierEntries = {}
	for _, tierName in RarityConfig.TierOrder do
		local tierDef = RarityConfig.Tiers[tierName]
		if tierDef ~= nil and tierDef.weight > 0 then
			table.insert(tierEntries, { value = tierName, weight = tierDef.weight })
		end
	end
	expect(#tierEntries == 5, "Pool muss genau 5 Stufen haben")
	for _ = 1, 50000 do
		local tier = WeightedRandom.pick(tierEntries)
		expect(tier ~= "Mythic" and tier ~= "Cosmic", "Mythic/Cosmic im normalen Wurf")
		local ids = CollectibleConfig.getIdsByRarity(tier)
		expect(#ids > 0, "leerer Pool fuer " .. tier)
		local pickedId = ids[math.random(1, #ids)]
		expect(CollectibleConfig.Collectibles[pickedId] ~= nil, "unbekanntes Objekt " .. tostring(pickedId))
	end
end)

test("Loot-Glueck: Formel verbessert Ultra-Rare-Chance korrekt", function()
	-- max(1, floor(n / Glueck)) - wie in LootService.
	local function effective(n, luck)
		return math.max(1, math.floor(n / luck))
	end
	expect(effective(10000, 1) == 10000, "ohne Event falsch")
	expect(effective(10000, 5) == 2000, "Kreaturen-Event (x5) falsch")
	expect(effective(10000, 3) == 3333, "Meteoritenschauer (x3) falsch")
	expect(effective(2, 100) == 1, "Untergrenze 1 verletzt")
end)

-- 6b) Equip-System: Item-Typen und Pet-Boni
test("CollectibleConfig: jedes Item hat Typ und Bonus", function()
	local counts = { pet = 0, trail = 0, skin = 0 }
	for id, def in CollectibleConfig.Collectibles do
		local itemType = def.itemType
		expect(itemType == "pet" or itemType == "trail" or itemType == "skin", id .. ": itemType fehlt")
		counts[itemType] += 1
		expect((def.bonusMultiplier or 0) >= 1, id .. ": bonusMultiplier < 1")
		if itemType ~= "pet" then
			expect(def.bonusMultiplier == 1, id .. ": nur Pets haben Bonus > 1")
		end
	end
	expect(counts.pet >= 5, "zu wenige Pets")
	expect(counts.trail >= 3, "zu wenige Trails")
	expect(counts.skin >= 3, "zu wenige Skins")
	-- Seltener = stärker: Drache (Mythic) schlägt Feldmaus (Common).
	expect(
		CollectibleConfig.Collectibles["goldener_drache"].bonusMultiplier
			> CollectibleConfig.Collectibles["feldmaus"].bonusMultiplier,
		"Pet-Bonus skaliert nicht mit Seltenheit"
	)
end)

-- 7a) Multiplikator-Formel und Rebirth (Spiegel von ProgressionConfig)
test("Progression: Multiplikator-Formel exakt", function()
	-- Leer = Basis 1.
	expect(ProgressionConfig.getTotalMultiplier({}, {}, 0, 1) == 1, "leeres Profil != 1")
	-- 2 Biome (Level 1 + Level 3) -> Biome-Bonus 0.1*2 + 0.05*2 = 0.3.
	local biomes = {
		{ biomeId = "wiese", slot = 1, level = 1, placedAt = 0 },
		{ biomeId = "wald", slot = 2, level = 3, placedAt = 0 },
	}
	local bonus = ProgressionConfig.getBiomeBonus(biomes)
	expect(math.abs(bonus - 0.3) < 1e-9, "Biome-Bonus falsch: " .. bonus)
	-- 5 Upgrade-Stufen -> +10%.
	local upgradeBonus = ProgressionConfig.getUpgradeBonus({ magnet = 3, backpack = 2 })
	expect(math.abs(upgradeBonus - 0.1) < 1e-9, "Upgrade-Bonus falsch")
	-- Gesamt: 1 * 1.3 * 1.1 * 1.2 (Pet) * 2 (2 Rebirths) = 3.432
	local total = ProgressionConfig.getTotalMultiplier(biomes, { magnet = 3, backpack = 2 }, 2, 1.2)
	expect(math.abs(total - 1.3 * 1.1 * 1.2 * 2) < 1e-9, "Gesamt-Multiplikator falsch: " .. total)
end)

test("Progression: Rebirth-Schwellen verdoppeln sich", function()
	expect(ProgressionConfig.getRebirthThreshold(0) == 25000, "Schwelle 0 != 25000")
	expect(ProgressionConfig.getRebirthThreshold(1) == 50000, "Schwelle 1 != 50000")
	expect(ProgressionConfig.getRebirthThreshold(3) == 200000, "Schwelle 3 != 200000")
	expect(ProgressionConfig.getRebirthMultiplier(0) == 1, "Rebirth-Mult 0 != 1")
	expect(ProgressionConfig.getRebirthMultiplier(4) == 3, "Rebirth-Mult 4 != 3 (+50% stapelnd)")
end)

-- 7b) Tutorial-Oekonomie und Studio-Testmodus
test("Tutorial: jeder Schritt bleibt bezahlbar (Spiegel der Belohnungslogik)", function()
	expect(GameConfig.TUTORIAL_STEP_COUNT == 4, "TUTORIAL_STEP_COUNT != 4")
	local rewards = GameConfig.TUTORIAL_STEP_REWARDS
	expect(#rewards == GameConfig.TUTORIAL_STEP_COUNT, "REWARDS-Anzahl != Schritte")
	-- Schritt 1+2: 5 Wiesen-Objekte sammeln und verkaufen.
	local sellValue = 5 * BiomeConfig.Harvest["wiese"].value
	local cheapestUpgrade = math.min(
		ProgressionConfig.getUpgradeCost("magnet", 0),
		ProgressionConfig.getUpgradeCost("backpack", 0)
	)
	local afterStep2 = GameConfig.START_ENERGY + rewards[1] + rewards[2] + sellValue
	expect(afterStep2 >= cheapestUpgrade, "Upgrade in Schritt 3 nicht bezahlbar")
	-- Schritt 4: zweites Biom (Wald, 100) muss bezahlbar sein.
	local afterStep3 = afterStep2 - cheapestUpgrade + rewards[3]
	expect(afterStep3 >= BiomeConfig.Biomes["wald"].baseCost, "Zweites Biom in Schritt 4 nicht bezahlbar")
end)

test("MonetizationConfig: Studio-Testmodus-Flag vorhanden", function()
	expect(type(MonetizationConfig.testModeInStudio) == "boolean", "testModeInStudio muss ein Boolean sein")
end)

test("MonetizationConfig: Kauf-Kette komplett (Pakete, Rebirth, Perk-Paesse)", function()
	for _, key in { "gp_double_mult", "gp_pet_slots", "gp_vip", "gp_auto_harvest" } do
		expect(MonetizationConfig.Gamepasses[key] ~= nil, "Gamepass fehlt: " .. key)
	end
	local sizes = {}
	for key, def in MonetizationConfig.DeveloperProducts do
		local rules = 0
		if def.grantsCosmetic ~= nil then rules += 1 end
		if def.grantsEnergy ~= nil then
			rules += 1
			expect(def.grantsEnergy > 0, key .. ": grantsEnergy <= 0")
			table.insert(sizes, def.grantsEnergy)
		end
		if def.perk ~= nil then rules += 1 end
		expect(rules == 1, key .. ": genau EINE Gutschrift-Regel noetig")
	end
	expect(#sizes == 3, "es muss genau 3 Energie-Pakete geben")
	expect(MonetizationConfig.DeveloperProducts["prod_instant_rebirth"].perk == "instant_rebirth", "Sofort-Rebirth fehlt")
	expect(MonetizationConfig.DeveloperProducts["prod_boost_2x"].perk == "boost_2x", "2x-Boost-Produkt fehlt")
	expect(MonetizationConfig.BOOST_DURATION_SECONDS == 20 * 60, "Boost-Dauer != 20 Minuten")
	expect(MonetizationConfig.BOOST_MULTIPLIER == 2, "Boost-Multiplikator != 2")
	expect(MonetizationConfig.PET_SLOTS_BONUS == 2, "PET_SLOTS_BONUS != 2")
end)

-- 8) Tagesbonus-Logik (Spiegel des DailyRewardService)
test("Tagesbonus: Streak-Regeln und Deckelung", function()
	local rewards = GameConfig.DAILY_REWARDS
	local function claim(lastDay, today, streak)
		if lastDay >= today then
			return nil, streak -- heute schon kassiert
		end
		local newStreak = if lastDay == today - 1 then streak + 1 else 1
		local index = math.clamp(newStreak, 1, #rewards)
		return rewards[index], newStreak
	end

	local reward, streak = claim(0, 20000, 0) -- allererster Login
	expect(reward == 50 and streak == 1, "erster Login falsch")

	reward, streak = claim(19999, 20000, 3) -- Folgetag
	expect(reward == rewards[4] and streak == 4, "Folgetag falsch")

	reward, streak = claim(19997, 20000, 6) -- Tag verpasst -> Reset
	expect(reward == 50 and streak == 1, "Reset nach Pause falsch")

	reward, streak = claim(19999, 20000, 9) -- Streak ueber Tabellenende
	expect(reward == 1200 and streak == 10, "Deckelung auf letzten Wert falsch")

	reward = claim(20000, 20000, 5) -- heute schon kassiert
	expect(reward == nil, "Doppel-Auszahlung moeglich!")
end)

table.insert(results, "")
table.insert(results, "ERGEBNIS: " .. passed .. " bestanden, " .. failed .. " fehlgeschlagen (" .. (passed + failed) .. " Tests)")
return table.concat(results, "\\n"), failed
`;

const state = await LuauState.createAsync();
try {
  const fn = state.loadstring(body + tests, "planet-forge-tests", true);
  const [report, failedCount] = await fn();
  console.log(report);
  process.exit(failedCount > 0 ? 1 : 0);
} catch (e) {
  console.error("HARNESS-FEHLER:", e.message ?? e);
  process.exit(2);
} finally {
  state.destroy();
}
