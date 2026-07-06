--!strict
-- SelfCheckService: Selbsttest beim Serverstart.
--
-- Prüft Konfiguration und Remote-Aufbau auf innere Konsistenz und meldet
-- Probleme als Warnungen in der Ausgabe (Studio: Output-Fenster). Der Test
-- verändert nichts am Spielzustand und blockiert den Start nicht - er macht
-- Konfigurationsfehler nur sofort sichtbar, statt sie erst im Spiel zu finden.
--
-- Läuft als letzter Service der Startreihenfolge (alle Remotes existieren dann).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local BiomeConfig = require(ReplicatedStorage.Shared.Config.BiomeConfig)
local RarityConfig = require(ReplicatedStorage.Shared.Config.RarityConfig)
local CollectibleConfig = require(ReplicatedStorage.Shared.Config.CollectibleConfig)
local EventConfig = require(ReplicatedStorage.Shared.Config.EventConfig)
local MonetizationConfig = require(ReplicatedStorage.Shared.Config.MonetizationConfig)

local ProgressionConfig = require(ReplicatedStorage.Shared.Config.ProgressionConfig)

local BiomeVisuals = require(script.Parent.BiomeVisuals)
local MonetizationService = require(script.Parent.MonetizationService)

local SelfCheckService = {}

local checksRun = 0
local problems: { string } = {}

-- Abschnitts-Ergebnisse für die Zusammenfassung am Ende.
local sections: { { name: string, checks: number, problems: number } } = {}
local currentSection: { name: string, checks: number, problems: number }? = nil

local function beginSection(name: string)
	local section = { name = name, checks = 0, problems = 0 }
	table.insert(sections, section)
	currentSection = section
end

local function check(condition: boolean, message: string)
	checksRun += 1
	local section = currentSection
	if section ~= nil then
		section.checks += 1
	end
	if not condition then
		table.insert(problems, message)
		if section ~= nil then
			section.problems += 1
		end
	end
end

local function checkBiomes()
	local count = 0
	for biomeId, def in BiomeConfig.Biomes do
		count += 1
		check(def.id == biomeId, `Biom {biomeId}: id-Feld ({def.id}) weicht vom Schlüssel ab`)
		check(def.baseCost > 0, `Biom {biomeId}: baseCost muss > 0 sein`)
		check(def.baseEnergyPerMinute > 0, `Biom {biomeId}: baseEnergyPerMinute muss > 0 sein`)
		check(def.maxLevel >= 1, `Biom {biomeId}: maxLevel muss >= 1 sein`)
		check(def.unlockAtLifetimeEnergy >= 0, `Biom {biomeId}: unlockAtLifetimeEnergy darf nicht negativ sein`)
		check(def.upgradeCostMultiplier > 1, `Biom {biomeId}: upgradeCostMultiplier muss > 1 sein`)
	end
	check(count == 10, `Erwartet 10 Biome, gefunden: {count}`)

	-- getSortedIds muss nach baseCost aufsteigend sortieren.
	local sorted = BiomeConfig.getSortedIds()
	check(#sorted == count, "getSortedIds() liefert nicht alle Biome")
	for index = 2, #sorted do
		local previous = BiomeConfig.Biomes[sorted[index - 1]]
		local current = BiomeConfig.Biomes[sorted[index]]
		check(previous.baseCost <= current.baseCost, `getSortedIds(): {sorted[index - 1]} vor {sorted[index]} ist nicht aufsteigend`)
	end

	-- Stichprobe Upgrade-Formel: floor(baseCost * 1.75^level).
	local wiese = BiomeConfig.Biomes["wiese"]
	if wiese ~= nil then
		local expected = math.floor(wiese.baseCost * wiese.upgradeCostMultiplier)
		check(
			BiomeConfig.getUpgradeCost("wiese", 1) == expected,
			`getUpgradeCost(wiese, 1) = {BiomeConfig.getUpgradeCost("wiese", 1)}, erwartet {expected}`
		)
	end
end

local function checkRarityAndCollectibles()
	-- Tier-Gewichte: Common..Legendary > 0, Mythic/Cosmic = 0 (nicht im normalen Pool).
	for _, tierName in { "Common", "Uncommon", "Rare", "Epic", "Legendary" } do
		local tier = RarityConfig.Tiers[tierName]
		check(tier ~= nil and tier.weight > 0, `Seltenheit {tierName}: fehlt oder Gewicht nicht > 0`)
	end
	for _, tierName in { "Mythic", "Cosmic" } do
		local tier = RarityConfig.Tiers[tierName]
		check(tier ~= nil and tier.weight == 0, `Seltenheit {tierName}: muss Gewicht 0 haben (nur Ultra-Rare-Wurf)`)
	end

	-- Ultra-Rares: seltenste zuerst, verweisen auf existierende Sammelobjekte.
	local previousOneIn = math.huge
	for _, ultra in RarityConfig.UltraRares do
		check(ultra.oneIn >= 2, `Ultra-Rare {ultra.collectibleId}: oneIn muss >= 2 sein`)
		check(ultra.oneIn <= previousOneIn, `Ultra-Rares nicht von selten nach häufig sortiert ({ultra.collectibleId})`)
		previousOneIn = ultra.oneIn
		check(
			CollectibleConfig.Collectibles[ultra.collectibleId] ~= nil,
			`Ultra-Rare {ultra.collectibleId}: fehlt in CollectibleConfig`
		)
	end
	check(#RarityConfig.UltraRares == 3, `Erwartet 3 Ultra-Rares, gefunden: {#RarityConfig.UltraRares}`)

	-- Jedes Sammelobjekt hat eine gültige Seltenheit; jede Pool-Stufe hat Einträge.
	for collectibleId, def in CollectibleConfig.Collectibles do
		check(RarityConfig.Tiers[def.rarity] ~= nil, `Sammelobjekt {collectibleId}: unbekannte Seltenheit {def.rarity}`)
		-- Equip-System: gültiger Item-Typ und sinnvoller Bonus.
		local itemType = def.itemType
		check(
			itemType == "pet" or itemType == "trail" or itemType == "skin",
			`Sammelobjekt {collectibleId}: ungültiger itemType {tostring(itemType)}`
		)
		check((def.bonusMultiplier or 0) >= 1, `Sammelobjekt {collectibleId}: bonusMultiplier muss >= 1 sein`)
	end
	for _, tierName in { "Common", "Uncommon", "Rare", "Epic", "Legendary" } do
		check(#CollectibleConfig.getIdsByRarity(tierName) > 0, `Kein Sammelobjekt im Pool der Stufe {tierName}`)
	end

	-- Ultra-Rares dürfen NICHT im normalen Pool auftauchen (werden separat gewürfelt).
	for _, ultra in RarityConfig.UltraRares do
		local def = CollectibleConfig.Collectibles[ultra.collectibleId]
		if def ~= nil then
			for _, poolId in CollectibleConfig.getIdsByRarity(def.rarity) do
				check(poolId ~= ultra.collectibleId, `Ultra-Rare {ultra.collectibleId} ist fälschlich im normalen Pool`)
			end
		end
	end
end

local function checkEvents()
	local count = 0
	for eventId, def in EventConfig.Events do
		count += 1
		check(def.id == eventId, `Event {eventId}: id-Feld weicht vom Schlüssel ab`)
		check(def.durationSeconds > 0, `Event {eventId}: durationSeconds muss > 0 sein`)
		check(def.weight > 0, `Event {eventId}: weight muss > 0 sein`)
		check(def.energyMultiplier >= 1, `Event {eventId}: energyMultiplier darf nicht < 1 sein`)
		check(def.lootLuckMultiplier >= 1, `Event {eventId}: lootLuckMultiplier darf nicht < 1 sein`)
	end
	check(count == 5, `Erwartet 5 globale Events, gefunden: {count}`)
end

local function checkMonetization()
	-- Jede von Gamepässen/Products vergebene Kosmetik muss im Katalog existieren.
	for key, def in MonetizationConfig.Gamepasses do
		for _, cosmeticId in def.grantsCosmetics do
			check(
				MonetizationConfig.Cosmetics[cosmeticId] ~= nil,
				`Gamepass {key}: vergibt unbekannte Kosmetik {cosmeticId}`
			)
		end
	end
	for key, def in MonetizationConfig.DeveloperProducts do
		-- Jedes Produkt braucht genau eine Gutschrift-Regel.
		local rules = 0
		if def.grantsCosmetic ~= nil then
			rules += 1
			check(
				MonetizationConfig.Cosmetics[def.grantsCosmetic :: string] ~= nil,
				`Product {key}: vergibt unbekannte Kosmetik {def.grantsCosmetic}`
			)
		end
		if def.grantsEnergy ~= nil then
			rules += 1
			check((def.grantsEnergy :: number) > 0, `Product {key}: grantsEnergy muss > 0 sein`)
		end
		if def.perk ~= nil then
			rules += 1
		end
		check(rules == 1, `Product {key}: braucht genau EINE Gutschrift-Regel (hat {rules})`)
	end

	-- Die Perk-Gamepässe der Kauf-Kette müssen existieren.
	for _, key in { "gp_double_mult", "gp_pet_slots", "gp_vip", "gp_auto_harvest" } do
		check(MonetizationConfig.Gamepasses[key] ~= nil, `Gamepass {key} fehlt`)
	end
	check(MonetizationConfig.DeveloperProducts["prod_instant_rebirth"] ~= nil, "Produkt prod_instant_rebirth fehlt")
	check(MonetizationConfig.DeveloperProducts["prod_boost_2x"] ~= nil, "Produkt prod_boost_2x fehlt")
	check(MonetizationConfig.BOOST_DURATION_SECONDS > 0, "BOOST_DURATION_SECONDS muss > 0 sein")
	check(MonetizationConfig.BOOST_MULTIPLIER > 1, "BOOST_MULTIPLIER muss > 1 sein")
	check(GameConfig.PURCHASE_LOG_LIMIT >= 10, "PURCHASE_LOG_LIMIT muss >= 10 sein")

	-- Jede Kosmetik hat eine gültige Kategorie.
	for cosmeticId, def in MonetizationConfig.Cosmetics do
		check(
			MonetizationConfig.CategoryNames[def.category] ~= nil,
			`Kosmetik {cosmeticId}: unbekannte Kategorie {def.category}`
		)
	end

	-- Hinweis (keine Warnung): nicht konfigurierte Produkt-IDs auflisten.
	local unconfigured = 0
	for _, def in MonetizationConfig.Gamepasses do
		if def.gamePassId == 0 then
			unconfigured += 1
		end
	end
	for _, def in MonetizationConfig.DeveloperProducts do
		if def.productId == 0 then
			unconfigured += 1
		end
	end
	if unconfigured > 0 then
		print(`[PlanetForge] Selbsttest-Hinweis: {unconfigured} Shop-Produkt(e) ohne ID (Creator Dashboard) - Käufe dafür sind deaktiviert.`)
	end
end

local function checkGameConfigAndRemotes()
	check(GameConfig.PLANET_SLOTS == 12, "PLANET_SLOTS muss 12 sein (Canon)")
	check(GameConfig.LOOT_ROLL_COST > 0, "LOOT_ROLL_COST muss > 0 sein")
	check(#GameConfig.DAILY_REWARDS >= 1, "DAILY_REWARDS darf nicht leer sein")
	check(GameConfig.OFFLINE_EARNINGS_RATE > 0 and GameConfig.OFFLINE_EARNINGS_RATE <= 1, "OFFLINE_EARNINGS_RATE muss in (0,1] liegen")
	check(GameConfig.OFFLINE_EARNINGS_CAP_HOURS >= 1, "OFFLINE_EARNINGS_CAP_HOURS muss >= 1 sein")
	check(
		GameConfig.FRIEND_BOOST_PER_FRIEND > 0 and GameConfig.FRIEND_BOOST_PER_FRIEND <= 0.5,
		"FRIEND_BOOST_PER_FRIEND muss in (0, 0.5] liegen"
	)
	check(GameConfig.FRIEND_BOOST_MAX_FRIENDS >= 1, "FRIEND_BOOST_MAX_FRIENDS muss >= 1 sein")
	check(GameConfig.AUTO_HARVEST_INTERVAL_SECONDS > 0, "AUTO_HARVEST_INTERVAL_SECONDS muss > 0 sein")
	for index = 2, #GameConfig.DAILY_REWARDS do
		check(
			GameConfig.DAILY_REWARDS[index] >= GameConfig.DAILY_REWARDS[index - 1],
			"DAILY_REWARDS sollte aufsteigend sein (höherer Streak = mehr Bonus)"
		)
	end
	check(GameConfig.LEADERBOARD_TOP_N >= 1, "LEADERBOARD_TOP_N muss >= 1 sein")
	check(GameConfig.PLANET_NAME_MAX_LENGTH >= 3, "PLANET_NAME_MAX_LENGTH muss >= 3 sein")

	-- Alle Remotes wurden von Remotes.init() erzeugt.
	local folder = ReplicatedStorage:FindFirstChild("PlanetForgeRemotes")
	check(folder ~= nil, "Remote-Ordner PlanetForgeRemotes fehlt (Remotes.init() nicht gelaufen?)")
	if folder ~= nil then
		local events = 0
		local functions = 0
		for _, child in folder:GetChildren() do
			if child:IsA("RemoteEvent") then
				events += 1
			elseif child:IsA("RemoteFunction") then
				functions += 1
			end
		end
		check(events == 18, `Erwartet 18 RemoteEvents, gefunden: {events}`)
		check(functions == 14, `Erwartet 14 RemoteFunctions, gefunden: {functions}`)

		-- Kritische Einzel-Remotes (Tutorial, Sammel-Loop, Studio-Testmodus).
		for _, name in { "TutorialUpdated", "ObjectCollected", "BackpackChanged", "SoldBackpack", "UpgradesUpdated" } do
			local remote = folder:FindFirstChild(name)
			check(remote ~= nil and remote:IsA("RemoteEvent"), `RemoteEvent {name} fehlt`)
		end
		for _, name in { "TutorialAction", "SimulatePurchase", "BuyUpgrade", "DoRebirth" } do
			local remote = folder:FindFirstChild(name)
			check(remote ~= nil and remote:IsA("RemoteFunction"), `RemoteFunction {name} fehlt`)
		end
	end
end

local function checkHarvest()
	-- Jedes Biom braucht eine Sammel-Definition mit sinnvollen Werten.
	for biomeId in BiomeConfig.Biomes do
		local harvest = BiomeConfig.Harvest[biomeId]
		check(harvest ~= nil, `Biom {biomeId}: keine Harvest-Definition`)
		if harvest ~= nil then
			check(harvest.value > 0, `Harvest {biomeId}: value muss > 0 sein`)
			check(harvest.maxActive >= 1, `Harvest {biomeId}: maxActive muss >= 1 sein`)
			check(harvest.respawnSeconds > 0, `Harvest {biomeId}: respawnSeconds muss > 0 sein`)
			if harvest.meltSeconds ~= nil then
				check(
					(harvest.meltSeconds :: number) > harvest.respawnSeconds,
					`Harvest {biomeId}: meltSeconds muss > respawnSeconds sein`
				)
			end
			if harvest.hotSeconds ~= nil then
				check((harvest.hotSeconds :: number) > 0, `Harvest {biomeId}: hotSeconds muss > 0 sein`)
			end
		end
	end

	-- Biom-Spezialmechaniken (Eiswelt schmilzt, Vulkan glüht) sind Canon.
	check(BiomeConfig.Harvest["eiswelt"].meltSeconds ~= nil, "Eiswelt braucht die Schmelz-Mechanik")
	check(BiomeConfig.Harvest["vulkan"].hotSeconds ~= nil, "Vulkan braucht die Glut-Mechanik")

	-- Spannungs-Mechaniken: Chancen in sinnvollen Grenzen, Boni gedeckelt.
	check(
		GameConfig.GOLDEN_OBJECT_CHANCE > 0 and GameConfig.GOLDEN_OBJECT_CHANCE <= 0.2,
		"GOLDEN_OBJECT_CHANCE muss in (0, 0.2] liegen"
	)
	check(GameConfig.GOLDEN_OBJECT_VALUE_FACTOR >= 2, "GOLDEN_OBJECT_VALUE_FACTOR muss >= 2 sein")
	check(GameConfig.COMBO_WINDOW_SECONDS > 0, "COMBO_WINDOW_SECONDS muss > 0 sein")
	check(
		GameConfig.COMBO_BONUS_PER_STACK * GameConfig.COMBO_MAX_STACKS <= 1,
		"Combo-Bonus darf +100% nicht übersteigen"
	)
	check(
		GameConfig.CRIT_SALE_CHANCE > 0 and GameConfig.CRIT_SALE_CHANCE <= 0.5,
		"CRIT_SALE_CHANCE muss in (0, 0.5] liegen"
	)
	check(GameConfig.CRIT_SALE_FACTOR >= 2, "CRIT_SALE_FACTOR muss >= 2 sein")
	check(
		GameConfig.METEOR_CHANCE_PER_CHECK > 0 and GameConfig.METEOR_CHANCE_PER_CHECK < 1,
		"METEOR_CHANCE_PER_CHECK muss in (0, 1) liegen"
	)
	check(GameConfig.METEOR_CRYSTAL_COUNT >= 1, "METEOR_CRYSTAL_COUNT muss >= 1 sein")
	check(GameConfig.METEOR_CRYSTAL_VALUE > 0, "METEOR_CRYSTAL_VALUE muss > 0 sein")
	check(GameConfig.METEOR_CRYSTAL_LIFETIME_SECONDS >= 10, "Meteor-Kristalle brauchen >= 10s Lebenszeit")
	check(GameConfig.BASE_MAGNET_RADIUS > 0, "BASE_MAGNET_RADIUS muss > 0 sein")
	check(GameConfig.BASE_BACKPACK_CAPACITY >= 5, "BASE_BACKPACK_CAPACITY muss >= 5 sein")

	-- Upgrade-Kosten wachsen exponentiell im Zielkorridor 1.15..1.25.
	for upgradeId, def in ProgressionConfig.Upgrades do
		check(def.baseCost > 0, `Upgrade {upgradeId}: baseCost muss > 0 sein`)
		check(
			def.costFactor >= 1.15 and def.costFactor <= 1.25,
			`Upgrade {upgradeId}: costFactor {def.costFactor} außerhalb 1.15..1.25`
		)
	end
end

local function checkProgression()
	-- Formel-Stichproben: leeres Profil = Basis; Boni wirken monoton.
	local emptyMult = ProgressionConfig.getTotalMultiplier({}, {}, 0, 1)
	check(emptyMult == ProgressionConfig.BASE_MULTIPLIER, "Leeres Profil muss den Basis-Multiplikator ergeben")

	local withBiome = ProgressionConfig.getTotalMultiplier(
		{ { biomeId = "wiese", slot = 1, level = 3, placedAt = 0 } },
		{},
		0,
		1
	)
	check(withBiome > emptyMult, "Biome müssen den Multiplikator erhöhen")

	local withRebirth = ProgressionConfig.getTotalMultiplier({}, {}, 2, 1)
	check(
		math.abs(withRebirth - (1 + 2 * ProgressionConfig.REBIRTH_BONUS)) < 1e-9,
		"Rebirth-Multiplikator stapelt nicht korrekt (+50% pro Rebirth)"
	)

	-- Schwelle wächst pro Rebirth.
	check(
		ProgressionConfig.getRebirthThreshold(1) > ProgressionConfig.getRebirthThreshold(0),
		"Rebirth-Schwelle muss pro Wiedergeburt wachsen"
	)
end

local function checkTutorial()
	check(GameConfig.TUTORIAL_STEP_COUNT == 6, "TUTORIAL_STEP_COUNT muss 6 sein")
	check(
		#GameConfig.TUTORIAL_STEP_REWARDS == GameConfig.TUTORIAL_STEP_COUNT,
		"TUTORIAL_STEP_REWARDS braucht einen Eintrag pro Schritt"
	)
	check(GameConfig.TUTORIAL_LIFETIME_GOAL > 0, "TUTORIAL_LIFETIME_GOAL muss > 0 sein")
	-- Schritt 5 (Fund-Wurf) muss mit den Belohnungen bis dahin bezahlbar sein.
	check(
		GameConfig.TUTORIAL_STEP_REWARDS[4] >= GameConfig.LOOT_ROLL_COST,
		"Tutorial-Ökonomie: Fund-Wurf in Schritt 5 nicht sicher bezahlbar"
	)

	-- Tutorial-Ökonomie: Jeder Schritt muss mit Start-Energie, Belohnungen
	-- und dem Verkauf von 5 Wiesen-Objekten bezahlbar sein.
	local rewards = GameConfig.TUTORIAL_STEP_REWARDS
	local wieseHarvest = BiomeConfig.Harvest["wiese"]
	local wald = BiomeConfig.Biomes["wald"]
	if wieseHarvest ~= nil and wald ~= nil then
		local sellValue = 5 * wieseHarvest.value
		local cheapestUpgrade = math.min(
			ProgressionConfig.getUpgradeCost("magnet", 0),
			ProgressionConfig.getUpgradeCost("backpack", 0)
		)
		local afterStep2 = GameConfig.START_ENERGY + rewards[1] + rewards[2] + sellValue
		check(afterStep2 >= cheapestUpgrade, "Tutorial-Ökonomie: Upgrade in Schritt 3 nicht bezahlbar")
		local afterStep3 = afterStep2 - cheapestUpgrade + rewards[3]
		check(afterStep3 >= wald.baseCost, "Tutorial-Ökonomie: zweites Biom in Schritt 4 nicht bezahlbar")
	end
end

local function checkBiomeVisuals()
	-- Jedes Biom braucht ein prozedurales Deko-Set.
	for biomeId in BiomeConfig.Biomes do
		check(BiomeVisuals.Builders[biomeId] ~= nil, `Biom {biomeId}: kein Visual-Set in BiomeVisuals`)
	end
end

local function checkTestMode()
	-- Außerhalb von Studio dürfen Test-Käufe NIEMALS möglich sein.
	if not RunService:IsStudio() then
		check(
			MonetizationService.isTestPurchaseAllowed() == false,
			"KRITISCH: Studio-Testmodus ist außerhalb von Studio aktiv!"
		)
	else
		check(true, "") -- in Studio zählt der Testmodus als geprüft
	end
end

function SelfCheckService.init()
	local sectionRuns: { { name: string, fn: () -> () } } = {
		{ name = "Biome", fn = checkBiomes },
		{ name = "Seltenheiten", fn = checkRarityAndCollectibles },
		{ name = "Events", fn = checkEvents },
		{ name = "Shop", fn = checkMonetization },
		{ name = "Konfig+Remotes", fn = checkGameConfigAndRemotes },
		{ name = "Sammeln", fn = checkHarvest },
		{ name = "Progression", fn = checkProgression },
		{ name = "Tutorial", fn = checkTutorial },
		{ name = "Biom-Visuals", fn = checkBiomeVisuals },
		{ name = "Testmodus", fn = checkTestMode },
	}

	for _, section in sectionRuns do
		beginSection(section.name)
		local ok, err = pcall(section.fn)
		if not ok then
			check(false, `Abschnitt {section.name} ist selbst abgestürzt: {err}`)
		end
	end

	-- Übersichtliche Zusammenfassung: eine Zeile pro Abschnitt, dann Gesamt.
	local lines = {}
	for _, section in sections do
		local mark = if section.problems == 0 then "✓" else `✗ {section.problems}`
		table.insert(lines, `{section.name} {mark}`)
	end
	local overview = table.concat(lines, "  |  ")

	if #problems == 0 then
		print(`[PlanetForge] Selbsttest bestanden ({checksRun} Prüfungen): {overview}`)
	else
		warn(`[PlanetForge] Selbsttest: {#problems} Problem(e) bei {checksRun} Prüfungen: {overview}`)
		for _, problem in problems do
			warn(`[PlanetForge]   - {problem}`)
		end
	end
end

return SelfCheckService
