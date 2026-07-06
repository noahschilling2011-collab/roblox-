--!strict
-- EnergyService: autoritative Energie-Ökonomie von Planet Forge.
-- Verwaltet Guthaben (energy) und Lebenszeit-Statistik (lifetimeEnergy),
-- das passive Biom-Einkommen. Das physische Sammeln macht der HarvestService.
-- Alle Beträge werden serverseitig validiert; der Client meldet nur Wünsche.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local BiomeConfig = require(ReplicatedStorage.Shared.Config.BiomeConfig)
local ProgressionConfig = require(ReplicatedStorage.Shared.Config.ProgressionConfig)

local DataService = require(script.Parent.DataService)
local EquipService = require(script.Parent.EquipService)
local GlobalEventService = require(script.Parent.GlobalEventService)

local EnergyService = {}

-- Zeitpunkt (os.clock) des letzten manuellen Einsammelns pro Spieler.

local energyChangedEvent: RemoteEvent? = nil

-- Prüft, ob ein Betrag eine nicht-negative, endliche Zahl ist.
local function isValidAmount(amount: any): boolean
	return typeof(amount) == "number"
		and amount == amount -- filtert NaN
		and amount ~= math.huge -- filtert +unendlich (>= 0 filtert -unendlich)
		and amount >= 0
end

-- Informiert den Besitzer über seinen aktuellen Energiestand.
local function fireEnergyChanged(player: Player, profile: Types.PlayerProfile)
	local event = energyChangedEvent
	if event == nil then
		event = Remotes.getEvent("EnergyChanged")
		energyChangedEvent = event
	end
	event:FireClient(player, profile.energy, profile.lifetimeEnergy)
end

-- Aktuelles Guthaben; 0 solange das Profil noch nicht geladen ist.
function EnergyService.getEnergy(player: Player): number
	local profile: Types.PlayerProfile? = DataService.getProfile(player)
	if profile == nil then
		return 0
	end
	return profile.energy
end

-- Schreibt Energie MIT Event-Multiplikator gut und erhöht auch lifetimeEnergy.
-- Rundet nach dem Multiplikator ab (mindestens 1, wenn baseAmount >= 1).
-- Gibt den tatsächlich gutgeschriebenen Betrag zurück (0 bei Fehlern).
function EnergyService.grantEnergy(player: Player, baseAmount: number): number
	local profile: Types.PlayerProfile? = DataService.getProfile(player)
	if profile == nil or not isValidAmount(baseAmount) then
		return 0
	end

	local multiplier = GlobalEventService.getEnergyMultiplier()
	if not isValidAmount(multiplier) or multiplier <= 0 then
		multiplier = 1
	end

	-- 2x-Gamepass/Boost und Freunde-Boost wirken auf alle Einnahmen.
	multiplier *= EnergyService.getPassMultiplier(player)
	multiplier *= EnergyService.getFriendBonus(player)

	local amount = math.floor(baseAmount * multiplier)
	if baseAmount >= 1 then
		amount = math.max(amount, 1)
	end
	if amount <= 0 then
		return 0
	end

	profile.energy += amount
	profile.lifetimeEnergy += amount
	DataService.markDirty(player)
	fireEnergyChanged(player, profile)
	return amount
end

-- Schreibt Energie OHNE Multiplikator und OHNE lifetimeEnergy gut
-- (z. B. für Handel oder Erstattungen).
function EnergyService.addRaw(player: Player, amount: number)
	local profile: Types.PlayerProfile? = DataService.getProfile(player)
	if profile == nil or not isValidAmount(amount) then
		return
	end

	local rounded = math.floor(amount)
	if rounded <= 0 then
		return
	end

	profile.energy += rounded
	DataService.markDirty(player)
	fireEnergyChanged(player, profile)
end

-- Prüft das Guthaben und zieht den Betrag ab. true = erfolgreich abgebucht.
function EnergyService.trySpend(player: Player, amount: number): boolean
	local profile: Types.PlayerProfile? = DataService.getProfile(player)
	if profile == nil or not isValidAmount(amount) then
		return false
	end

	local cost = math.floor(amount)
	if profile.energy < cost then
		return false
	end

	profile.energy -= cost
	DataService.markDirty(player)
	fireEnergyChanged(player, profile)
	return true
end

-- Gamepass-Multiplikator auf ALLE Einnahmen (2x-Pass, 20-Min-Boost); der
-- MonetizationService ersetzt diese Funktion beim Start (Hook, damit
-- keine zyklische Service-Abhängigkeit entsteht).
EnergyService.getPassMultiplier = function(_player: Player): number
	return 1
end

--------------------------------------------------------------------------
-- Freunde-Boost: +10% pro Freund, der gleichzeitig im Server spielt
-- (gedeckelt, siehe GameConfig). Die Freundschafts-Prüfung ist ein
-- Web-Aufruf, deshalb wird das Ergebnis pro Spieler-Paar gecacht und nur
-- bei Beitritt/Verlassen neu berechnet.
--------------------------------------------------------------------------

local friendCounts: { [Player]: number } = {}

function EnergyService.getFriendBonus(player: Player): number
	local count = math.min(friendCounts[player] or 0, GameConfig.FRIEND_BOOST_MAX_FRIENDS)
	return 1 + count * GameConfig.FRIEND_BOOST_PER_FRIEND
end

-- Zählt für jeden Spieler die Freunde im Server neu (pcall pro Paar).
local function refreshFriendCounts()
	local players = Players:GetPlayers()
	for _, player in players do
		local count = 0
		for _, other in players do
			if other ~= player then
				local ok, isFriend = pcall(function()
					return player:IsFriendsWith(other.UserId)
				end)
				if ok and isFriend == true then
					count += 1
				end
			end
		end
		friendCounts[player] = count
	end
end

-- Schickt dem Client den aktuellen Energiestand erneut (z. B. nach einem
-- Rebirth-Reset, der das Profil direkt verändert hat).
function EnergyService.notify(player: Player)
	local profile: Types.PlayerProfile? = DataService.getProfile(player)
	if profile ~= nil then
		fireEnergyChanged(player, profile)
	end
end

-- Summiert das Biom-Einkommen (Energie pro Minute) eines Profils.
local function computeIncomePerMinute(profile: Types.PlayerProfile): number
	local perMinute = 0
	for _, placed in profile.biomes do
		local def = BiomeConfig.Biomes[placed.biomeId]
		if def ~= nil then
			perMinute += def.baseEnergyPerMinute * placed.level
		end
	end
	return perMinute
end

function EnergyService.init()
	energyChangedEvent = Remotes.getEvent("EnergyChanged")

	-- Initialen Energiestand senden, sobald das Profil geladen ist,
	-- damit die UI von Anfang an korrekte Werte zeigt.
	local offlineEvent = Remotes.getEvent("OfflineEarnings")

	local function onPlayerAdded(player: Player)
		-- Freunde-Boost aktualisieren (Web-Aufrufe, deshalb entkoppelt).
		task.spawn(refreshFriendCounts)

		task.spawn(function()
			local profile: Types.PlayerProfile? = DataService.waitForProfile(player)
			if profile == nil or player.Parent == nil then
				return
			end
			fireEnergyChanged(player, profile)

			-- Offline-Earnings: Biome haben waehrend der Abwesenheit anteilig
			-- weiterproduziert (OFFLINE_EARNINGS_RATE, gedeckelt auf CAP_HOURS).
			if profile.lastSeenAt > 0 then
				local awayMinutes = (os.time() - profile.lastSeenAt) / 60
				awayMinutes = math.clamp(awayMinutes, 0, GameConfig.OFFLINE_EARNINGS_CAP_HOURS * 60)
				if awayMinutes >= 1 then
					local multiplier = ProgressionConfig.getTotalMultiplier(
						profile.biomes,
						profile.upgrades,
						profile.rebirths,
						EquipService.getPetBonus(profile)
					)
					local offline = math.floor(
						computeIncomePerMinute(profile) * awayMinutes * GameConfig.OFFLINE_EARNINGS_RATE * multiplier
					)
					if offline > 0 then
						EnergyService.addRaw(player, offline)
						profile.lifetimeEnergy += offline
						DataService.markDirty(player)
						fireEnergyChanged(player, profile)
						offlineEvent:FireClient(player, offline, math.floor(awayMinutes))
					end
				end
			end
		end)
	end

	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(function(player)
		friendCounts[player] = nil
		task.spawn(refreshFriendCounts)
	end)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end

	-- Passives Biom-Einkommen: alle PASSIVE_INCOME_INTERVAL_SECONDS wird das
	-- Minuten-Einkommen anteilig auf das Intervall skaliert und gutgeschrieben.
	task.spawn(function()
		local intervalMinutes = GameConfig.PASSIVE_INCOME_INTERVAL_SECONDS / 60
		while true do
			task.wait(GameConfig.PASSIVE_INCOME_INTERVAL_SECONDS)
			for _, player in Players:GetPlayers() do
				local profile: Types.PlayerProfile? = DataService.getProfile(player)
				if profile ~= nil then
					-- Progression (inkl. Pet-Bonus) wirkt auch aufs passive Einkommen.
					local multiplier = ProgressionConfig.getTotalMultiplier(
						profile.biomes,
						profile.upgrades,
						profile.rebirths,
						EquipService.getPetBonus(profile)
					)
					local income = computeIncomePerMinute(profile) * intervalMinutes * multiplier
					if income > 0 then
						EnergyService.grantEnergy(player, income)
					end
				end
			end
		end
	end)
end

return EnergyService
