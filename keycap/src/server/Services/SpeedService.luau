--!strict
-- Setzt die WalkSpeed aus dem Vorrat. Server-autoritativ: der Client
-- rechnet nichts aus und schickt nichts - er sieht nur das Ergebnis.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local EconomyLogic = require(Shared.EconomyLogic)
local EconomyConfig = require(Shared.Config.EconomyConfig)
local DataService = require(script.Parent.DataService)
local ProductionService = require(script.Parent.ProductionService)

local SpeedService = {}

-- Wer eine geklaute Taste traegt, ist langsamer. Wird von StealService
-- gesetzt und laeuft nach CARRY_SECONDS aus.
local carrying: { [number]: number } = {} -- userId -> Ablaufzeitpunkt (os.clock)

function SpeedService.setCarrying(userId: number, seconds: number)
	carrying[userId] = os.clock() + seconds
end

function SpeedService.clearCarrying(userId: number)
	carrying[userId] = nil
end

function SpeedService.isCarrying(userId: number): boolean
	local until_ = carrying[userId]
	return until_ ~= nil and os.clock() < until_
end

function SpeedService.speedFor(player: Player): number
	local profile = DataService.get(player)
	if not profile then
		return EconomyConfig.BASE_WALK_SPEED
	end
	local vorrat = ProductionService.totalVorrat(profile)
	if SpeedService.isCarrying(player.UserId) then
		return EconomyLogic.carryWalkSpeed(vorrat)
	end
	return EconomyLogic.walkSpeed(vorrat)
end

function SpeedService.start()
	local accumulator = 0

	RunService.Heartbeat:Connect(function(deltaTime)
		accumulator += deltaTime
		if accumulator < 0.25 then
			return
		end
		accumulator = 0

		for _, player in Players:GetPlayers() do
			local character = player.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if humanoid then
				humanoid.WalkSpeed = SpeedService.speedFor(player)
			end
		end
	end)

	print("[KEYCAP] SpeedService laeuft")
end

return SpeedService
