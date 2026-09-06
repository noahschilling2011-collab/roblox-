--!strict
-- NPC-Plots: Klau-Ziele, die immer da sind.
--
-- Die Bewertung: "Der Loop braucht Mitspieler und du hast keine." Auf einem
-- frischen Server mit zwei Leuten waere KEYCAP RUSH ein Farm-Spiel mit
-- gelegentlichem Aergern. Diese Plots ueberbruecken das - bewusst schwach,
-- damit sie den Wettbewerb zwischen echten Spielern nicht ersetzen.

local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local EconomyConfig = require(Shared.Config.EconomyConfig)
local EconomyLogic = require(Shared.EconomyLogic)
local WorldConfig = require(Shared.Config.WorldConfig)
local PlotService = require(script.Parent.PlotService)

local NpcPlotService = {}

type NpcKey = { rarity: string, vorrat: number }
type NpcPlot = { plot: PlotService.Plot, keys: { NpcKey }, respawnAt: { [number]: number } }

local npcPlots: { [number]: NpcPlot } = {} -- plotIndex -> NpcPlot
local LABEL_INTERVAL = 2

local function makeKeys(): { NpcKey }
	local keys: { NpcKey } = {}
	for index = 1, EconomyConfig.NPC_KEY_COUNT do
		local rarity = EconomyConfig.NPC_RARITIES[index] or "Common"
		table.insert(keys, { rarity = rarity, vorrat = 0 })
	end
	return keys
end

function NpcPlotService.isNpcPlot(plotIndex: number): boolean
	return npcPlots[plotIndex] ~= nil
end

function NpcPlotService.keysOf(plotIndex: number): { NpcKey }?
	local entry = npcPlots[plotIndex]
	return if entry then entry.keys else nil
end

-- Eine NPC-Taste wird geklaut: Vorrat wandert anteilig mit, die Taste
-- selbst bleibt als leerer Platzhalter stehen und fuellt sich wieder.
-- So gehen dem Server nie die Ziele aus.
function NpcPlotService.takeKey(plotIndex: number, keyIndex: number): NpcKey?
	local entry = npcPlots[plotIndex]
	if not entry then
		return nil
	end
	local key = entry.keys[keyIndex]
	if not key then
		return nil
	end
	if (entry.respawnAt[keyIndex] or 0) > os.clock() then
		return nil -- diese Taste wurde gerade erst geleert
	end

	local taken = { rarity = key.rarity, vorrat = EconomyLogic.stealTransfer(key.vorrat) }
	key.vorrat = 0
	entry.respawnAt[keyIndex] = os.clock() + EconomyConfig.NPC_RESPAWN_SECONDS
	return taken
end

function NpcPlotService.start()
	for slot = 1, WorldConfig.NPC_PLOT_COUNT do
		local name = WorldConfig.NPC_NAMES[slot] or ("NPC " .. slot)
		local plot = PlotService.claimForNpc(slot, name)
		if plot then
			local entry: NpcPlot = { plot = plot, keys = makeKeys(), respawnAt = {} }
			npcPlots[plot.index] = entry
			PlotService.renderKeys(plot, entry.keys)
		end
	end

	local sinceLabel = 0
	RunService.Heartbeat:Connect(function(deltaTime)
		local now = os.clock()
		for _, entry in npcPlots do
			for keyIndex, key in entry.keys do
				if (entry.respawnAt[keyIndex] or 0) > now then
					continue -- pausiert nach dem Klau
				end
				local rate = EconomyLogic.rarity(key.rarity).vorratPerSecond
				key.vorrat = math.min(key.vorrat + rate * deltaTime, EconomyConfig.NPC_VORRAT_CAP)
			end
		end

		sinceLabel += deltaTime
		if sinceLabel >= LABEL_INTERVAL then
			sinceLabel = 0
			for _, entry in npcPlots do
				PlotService.refreshLabels(entry.plot, entry.keys)
			end
		end
	end)

	local count = 0
	for _ in npcPlots do
		count += 1
	end
	print(("[KEYCAP] NpcPlotService: %d NPC-Plots, Vorrat gedeckelt bei %d"):format(count, EconomyConfig.NPC_VORRAT_CAP))
end

return NpcPlotService
