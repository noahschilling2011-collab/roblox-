--!strict
-- Jede Taste produziert ihren EIGENEN Vorrat. Der Plot-Vorrat ist die
-- Summe - es gibt keinen zweiten Zaehler daneben. Das ist die Aenderung
-- aus Abschnitt 6 der Bewertung: dadurch klaut ein Dieb echten Vorrat mit
-- und Horten ist nicht mehr gratis.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local EconomyLogic = require(Shared.EconomyLogic)
local WorldConfig = require(Shared.Config.WorldConfig)
local DataService = require(script.Parent.DataService)
local PlotService = require(script.Parent.PlotService)

local LABEL_INTERVAL = 2 -- Sekunden zwischen zwei Label-Updates

local ProductionService = {}

function ProductionService.totalVorrat(profile: DataService.Profile): number
	local sum = 0
	for _, key in profile.keys do
		sum += key.vorrat
	end
	return sum
end

function ProductionService.rate(profile: DataService.Profile): number
	local rate = 0
	for _, key in profile.keys do
		rate += EconomyLogic.rarity(key.rarity).vorratPerSecond
	end
	return rate
end

function ProductionService.start()
	local sinceLabel = 0

	RunService.Heartbeat:Connect(function(deltaTime)
		for _, player in Players:GetPlayers() do
			local profile = DataService.get(player)
			if not profile then
				continue
			end
			-- Produktion laeuft ortsunabhaengig weiter, auch waehrend des
			-- Laufs zum Pad. Nur der Vorrat auf dem Plot ist klaubar.
			for _, key in profile.keys do
				key.vorrat += EconomyLogic.rarity(key.rarity).vorratPerSecond * deltaTime
			end
		end

		sinceLabel += deltaTime
		if sinceLabel >= LABEL_INTERVAL then
			sinceLabel = 0
			for _, player in Players:GetPlayers() do
				PlotService.refreshKeyLabels(player.UserId)
			end
		end
	end)

	print("[KEYCAP] ProductionService laeuft (Label-Takt " .. LABEL_INTERVAL .. "s)")
end

-- Wie oft der Zustand an die Clients geht, steht in WorldConfig - hier nur
-- als Erinnerung, dass ProductionService selbst nichts an Clients schickt.
ProductionService.STATE_PUSH_INTERVAL = WorldConfig.STATE_PUSH_INTERVAL

return ProductionService
