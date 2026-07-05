--!strict
-- LootService: server-autoritative Fund-Würfe (Loot-Rolls).
-- Ablauf eines Wurfs: Zuerst werden alle Ultra-Rares einzeln gewürfelt
-- (seltenste zuerst, der erste Treffer gewinnt). Trifft keiner, wird eine
-- Seltenheitsstufe gewichtet gewürfelt und daraus ein zufälliges Objekt
-- des normalen Pools gezogen. Loot-Glück aus globalen Events verbessert
-- ausschließlich die Ultra-Rare-Chancen.

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local RarityConfig = require(ReplicatedStorage.Shared.Config.RarityConfig)
local CollectibleConfig = require(ReplicatedStorage.Shared.Config.CollectibleConfig)
local WeightedRandom = require(ReplicatedStorage.Shared.Util.WeightedRandom)

local DataService = require(script.Parent.DataService)
local EnergyService = require(script.Parent.EnergyService)
local GlobalEventService = require(script.Parent.GlobalEventService)
local PlanetService = require(script.Parent.PlanetService)

local LootService = {}

local rng = Random.new()

-- Serverweite Ankündigungstexte für Ultra-Rare-Funde
-- (vorformuliert, damit die deutsche Deklination stimmt).
local ULTRA_RARE_ANNOUNCEMENTS: { [string]: string } = {
	kosmischer_kern = "hat einen Kosmischen Kern gefunden!",
	goldener_drache = "hat einen Goldenen Drachen gefunden!",
	kristall = "hat einen Leuchtenden Kristall gefunden!",
}

-- Würfelt ein Sammelobjekt. Gibt (collectibleId, rarity, isUltraRare) zurück;
-- collectibleId ist nil, wenn die Konfiguration keinen Kandidaten hergibt
-- (sollte nie passieren und wird vom Aufrufer mit Erstattung abgefangen).
local function rollCollectible(): (string?, string, boolean)
	local lootLuck = GlobalEventService.getLootLuckMultiplier()
	if typeof(lootLuck) ~= "number" or lootLuck ~= lootLuck or lootLuck < 1 then
		lootLuck = 1
	end

	-- 1) Ultra-Rares: seltenste zuerst, der erste Treffer gewinnt.
	-- Loot-Glück verkürzt die Odds: oneIn(max(1, floor(n / lootLuck))).
	for _, entry in RarityConfig.UltraRares do
		local effectiveOneIn = math.max(1, math.floor(entry.oneIn / lootLuck))
		if WeightedRandom.oneIn(effectiveOneIn, rng) then
			local def = CollectibleConfig.Collectibles[entry.collectibleId]
			if def ~= nil then
				return entry.collectibleId, def.rarity, true
			end
			warn(`[PlanetForge] LootService: Ultra-Rare {entry.collectibleId} hat keine Collectible-Definition`)
		end
	end

	-- 2) Normaler Pool: Seltenheitsstufe gewichtet würfeln
	-- (nur Stufen mit weight > 0; Mythic/Cosmic bleiben außen vor).
	local tierEntries: { WeightedRandom.WeightedEntry<string> } = {}
	for _, tierName in RarityConfig.TierOrder do
		local tierDef = RarityConfig.Tiers[tierName]
		if tierDef ~= nil and tierDef.weight > 0 then
			table.insert(tierEntries, { value = tierName, weight = tierDef.weight })
		end
	end
	if #tierEntries == 0 then
		return nil, "Common", false
	end

	local tierName = WeightedRandom.pick(tierEntries, rng)

	-- 3) Zufälliges Objekt aus dem Pool der gewürfelten Stufe.
	local ids = CollectibleConfig.getIdsByRarity(tierName)
	if #ids == 0 then
		return nil, tierName, false
	end

	return ids[rng:NextInteger(1, #ids)], tierName, false
end

function LootService.init()
	local lootObtainedEvent = Remotes.getEvent("LootObtained")
	local notificationEvent = Remotes.getEvent("Notification")

	local rollFunction = Remotes.getFunction("RollLoot")
	rollFunction.OnServerInvoke = function(player: Player): (boolean, any?)
		local profile: Types.PlayerProfile? = DataService.getProfile(player)
		if profile == nil then
			return false, "Dein Spielstand wird noch geladen."
		end

		-- Einsatz abbuchen; der Server ist autoritativ über das Guthaben.
		if not EnergyService.trySpend(player, GameConfig.LOOT_ROLL_COST) then
			return false, "Nicht genug Energie."
		end

		local collectibleId, rarity, isUltraRare = rollCollectible()
		if collectibleId == nil then
			-- Konfigurationsfehler: Einsatz erstatten statt Energie zu verbrennen.
			warn(`[PlanetForge] LootService: kein Sammelobjekt für Stufe {rarity} verfügbar`)
			EnergyService.addRaw(player, GameConfig.LOOT_ROLL_COST)
			return false, "Beim Fund-Wurf ist etwas schiefgelaufen. Deine Energie wurde erstattet."
		end

		local owned: Types.OwnedCollectible = {
			uid = HttpService:GenerateGUID(false),
			collectibleId = collectibleId,
			obtainedAt = os.time(),
			source = "loot",
		}
		table.insert(profile.collectibles, owned)
		DataService.markDirty(player)

		lootObtainedEvent:FireClient(player, collectibleId, rarity, owned.uid)
		PlanetService.sendSnapshot(player)

		-- Ultra-Rare-Funde werden serverweit gefeiert.
		if isUltraRare then
			local announcement = ULTRA_RARE_ANNOUNCEMENTS[collectibleId]
			if announcement == nil then
				local def = CollectibleConfig.Collectibles[collectibleId]
				local displayName = if def ~= nil then def.displayName else collectibleId
				announcement = `hat {displayName} gefunden!`
			end
			notificationEvent:FireAllClients(`{player.Name} {announcement}`, "success")
		end

		return true, {
			collectibleId = collectibleId,
			rarity = rarity,
			uid = owned.uid,
		}
	end
end

return LootService
