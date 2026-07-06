--!strict
-- ProgressionService: Live-Multiplikator fürs HUD und das Rebirth-System.
--
-- Multiplikator: Die Formel lebt in ProgressionConfig (Canon); dieser Service
-- berechnet sie pro Spieler und schickt Änderungen als MultiplierChanged an
-- den Client (beim Beitritt, nach Käufen/Upgrades über eine Watcher-Schleife
-- und sofort nach einer Wiedergeburt).
--
-- Rebirth: Ab der lifetimeEnergy-Schwelle (ProgressionConfig) setzt DoRebirth
-- Biome und Währung zurück und erhöht dafür den permanenten
-- Rebirth-Multiplikator (+50% pro Wiedergeburt, stapelnd) plus exklusive
-- Insel-Deko. Der Server validiert die Schwelle - dem Client wird nie vertraut.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local ProgressionConfig = require(ReplicatedStorage.Shared.Config.ProgressionConfig)

local DataService = require(script.Parent.DataService)
local EnergyService = require(script.Parent.EnergyService)
local PlanetService = require(script.Parent.PlanetService)

local WATCHER_INTERVAL_SECONDS = 3 -- wie oft der Multiplikator neu geprüft wird

local multiplierChangedEvent: RemoteEvent? = nil
local notificationEvent: RemoteEvent? = nil

-- Zuletzt an den Client gemeldeter Gesamt-Multiplikator (für den Watcher).
local lastSentTotal: { [Player]: number } = {}

local ProgressionService = {}

-- Pet-Bonus-Quelle; Phase 3 (EquipService) ersetzt diese Funktion.
ProgressionService.getPetBonus = function(_profile: Types.PlayerProfile): number
	return 1
end

-- Gesamt-Multiplikator eines Spielers inklusive Pet-Bonus.
function ProgressionService.getTotalMultiplier(profile: Types.PlayerProfile): number
	return ProgressionConfig.getTotalMultiplier(
		profile.biomes,
		profile.upgrades,
		profile.rebirths,
		ProgressionService.getPetBonus(profile)
	)
end

-- Schickt dem Client den aktuellen Multiplikator samt Aufschlüsselung.
function ProgressionService.notifyMultiplier(player: Player)
	local profile = DataService.getProfile(player)
	if profile == nil or multiplierChangedEvent == nil then
		return
	end

	local total = ProgressionService.getTotalMultiplier(profile)
	lastSentTotal[player] = total;
	(multiplierChangedEvent :: RemoteEvent):FireClient(player, {
		total = total,
		biomeBonus = ProgressionConfig.getBiomeBonus(profile.biomes),
		upgradeBonus = ProgressionConfig.getUpgradeBonus(profile.upgrades),
		petBonus = ProgressionService.getPetBonus(profile),
		rebirthMultiplier = ProgressionConfig.getRebirthMultiplier(profile.rebirths),
		rebirths = profile.rebirths,
		nextThreshold = ProgressionConfig.getRebirthThreshold(profile.rebirths),
		lifetimeEnergy = profile.lifetimeEnergy,
	})
end

-- Remote-Handler: DoRebirth() -> (ok, neuerMultiplikator | Fehlermeldung)
local function handleDoRebirth(player: Player): (boolean, any?)
	local profile = DataService.getProfile(player)
	if profile == nil then
		return false, "Dein Profil ist noch nicht geladen."
	end

	local threshold = ProgressionConfig.getRebirthThreshold(profile.rebirths)
	if profile.lifetimeEnergy < threshold then
		return false, `Du brauchst {threshold} Gesamt-Energie für die nächste Wiedergeburt.`
	end

	-- Reset: Biome und Währung; Sammlung, Kosmetik, Insel-Upgrades,
	-- Tutorial-Fortschritt und Name bleiben erhalten.
	profile.rebirths += 1
	profile.biomes = { { biomeId = "wiese", slot = 1, level = 1, placedAt = os.time() } }
	profile.energy = GameConfig.START_ENERGY
	profile.lifetimeEnergy = 0
	profile.backpack.items = 0
	profile.backpack.value = 0
	DataService.markDirty(player)

	-- Welt und Client synchronisieren.
	PlanetService.refreshAllZones(player)
	PlanetService.applyRebirthDeco(player, profile.rebirths)
	PlanetService.sendSnapshot(player)
	EnergyService.notify(player)
	ProgressionService.notifyMultiplier(player)

	local newMultiplier = ProgressionConfig.getRebirthMultiplier(profile.rebirths)
	if notificationEvent ~= nil then
		(notificationEvent :: RemoteEvent):FireClient(
			player,
			`Wiedergeburt {profile.rebirths}! Dein permanenter Multiplikator ist jetzt ×{string.format("%.1f", newMultiplier)}. 🔄`,
			"success"
		)
	end
	return true, newMultiplier
end

function ProgressionService.init()
	multiplierChangedEvent = Remotes.getEvent("MultiplierChanged")
	notificationEvent = Remotes.getEvent("Notification")
	Remotes.getFunction("DoRebirth").OnServerInvoke = handleDoRebirth

	local function onPlayerAdded(player: Player)
		task.spawn(function()
			local profile = DataService.waitForProfile(player)
			if profile ~= nil then
				ProgressionService.notifyMultiplier(player)
			end
		end)
	end

	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(function(player)
		lastSentTotal[player] = nil
	end)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end

	-- Watcher: meldet Multiplikator-Änderungen (Biom-Kauf, Upgrade, Pets)
	-- zeitnah ans HUD, ohne dass andere Services diesen Service kennen müssen.
	task.spawn(function()
		while true do
			task.wait(WATCHER_INTERVAL_SECONDS)
			for _, player in Players:GetPlayers() do
				local profile = DataService.getProfile(player)
				if profile ~= nil then
					local total = ProgressionService.getTotalMultiplier(profile)
					local last = lastSentTotal[player]
					-- lifetimeEnergy steckt im Event (Rebirth-Fortschritt):
					-- deshalb auch bei gleichem Multiplikator gelegentlich senden.
					if last == nil or math.abs(total - last) > 1e-6 then
						ProgressionService.notifyMultiplier(player)
					end
				end
			end
		end
	end)
end

return ProgressionService
