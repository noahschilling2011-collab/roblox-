--!strict
-- Schickt den Spielzustand an die Clients. Der Client rechnet nichts aus,
-- er zeigt nur an, was hier drin steht.

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local EconomyLogic = require(Shared.EconomyLogic)
local WorldConfig = require(Shared.Config.WorldConfig)
local Remotes = require(Shared.Remotes)
local DataService = require(script.Parent.DataService)
local ProductionService = require(script.Parent.ProductionService)
local SpeedService = require(script.Parent.SpeedService)
local StealService = require(script.Parent.StealService)

local StateService = {}

function StateService.start()
	local remote = Remotes.get("StateChanged")

	task.spawn(function()
		while true do
			task.wait(WorldConfig.STATE_PUSH_INTERVAL)
			for _, player in Players:GetPlayers() do
				local profile = DataService.get(player)
				if not profile then
					continue
				end
				local vorrat = ProductionService.totalVorrat(profile)
				local shieldLeft, shieldCooldown = StealService.shieldState(player.UserId)
				local nextStage = nil
				for stageIndex = 1, #EconomyLogic.payoutFactors() do
					if not EconomyLogic.canEnterStage(vorrat, stageIndex) then
						nextStage = stageIndex
						break
					end
				end

				remote:FireClient(player, {
					wins = profile.wins,
					vorrat = math.floor(vorrat),
					rate = ProductionService.rate(profile),
					speed = SpeedService.speedFor(player),
					slots = profile.slots,
					keyCount = #profile.keys,
					slotPrice = EconomyLogic.slotPrice(profile.slots),
					carrying = SpeedService.isCarrying(player.UserId),
					shieldLeft = math.floor(shieldLeft),
					shieldCooldown = math.floor(shieldCooldown),
					-- naechstes Tor, das noch nicht offen ist (nil = alle offen)
					nextStage = nextStage,
					nextStageVorrat = if nextStage then EconomyLogic.vorratForStage(nextStage) else nil,
				})
			end
		end
	end)

	print("[KEYCAP] StateService sendet alle " .. WorldConfig.STATE_PUSH_INTERVAL .. "s")
end

return StateService
