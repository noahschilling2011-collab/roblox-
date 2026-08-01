-- ServerScriptService/Systems/GuardService.luau
--!strict
-- GHOSTNET :: Wachen in der Bank.
--
-- SIE MELDEN, SIE GREIFEN NICHT AN. Das haelt die Mechanik bei Flucht statt
-- Kampf - und es ist der Grund, warum es in diesem Spiel keine Waffen gibt.
-- Eine Wache, die dich sieht, loest den Alarm aus. Dann rennst du.
--
-- LEISTUNG
--   Sichtkegel werden NUR geprueft, wenn ueberhaupt ein Spieler in der Naehe
--   ist, und nur alle Config.Bank.GuardTick Sekunden. Ein Raycast pro Wache
--   und Takt, nicht pro Frame.
--
-- Eine Wache ist ein Modell mit Tag "GhostNetGuard" und Attributen:
--   PatrolA / PatrolB   Weltpositionen als Vector3-Attribute
--   AlarmGroup          welche Alarm-Gruppe sie ausloest

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Geometry = require(ReplicatedStorage.Shared.Geometry)

local RaidService = require(script.Parent.RaidService)
local TimeService = require(script.Parent.TimeService)

local GuardService = {}

local B = Config.Bank

type Guard = {
	Model: Model,
	Root: BasePart,
	A: Vector3,
	B: Vector3,
	Alpha: number,
	Direction: number,
	Seen: { [Player]: number },
}

local guards: { Guard } = {}

--==========================================================================

local function register(inst: Instance)
	if not inst:IsA("Model") then
		return
	end
	local root = inst.PrimaryPart or inst:FindFirstChild("Root")
	if not root or not root:IsA("BasePart") then
		warn(("[GHOSTNET] Wache '%s' hat keinen Root-Part."):format(inst:GetFullName()))
		return
	end

	local a = inst:GetAttribute("PatrolA")
	local b = inst:GetAttribute("PatrolB")
	table.insert(guards, {
		Model = inst,
		Root = root,
		A = if typeof(a) == "Vector3" then a else root.Position,
		B = if typeof(b) == "Vector3" then b else root.Position,
		Alpha = 0,
		Direction = 1,
		Seen = {},
	})
end

local function unregister(inst: Instance)
	for index = #guards, 1, -1 do
		if guards[index].Model == inst then
			table.remove(guards, index)
		end
	end
end

--==========================================================================
-- Sicht
--==========================================================================

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true

-- Sieht diese Wache den Spieler? Winkel UND freie Sichtlinie - Waende
-- blockieren, sonst sieht die Wache durch den halben Tresorraum.
local function canSee(guard: Guard, player: Player, position: Vector3): boolean
	local toPlayer = position - guard.Root.Position
	local distance = toPlayer.Magnitude
	local range = B.GuardSightRange * TimeService.SightFactor()
	if distance > range or distance < 0.1 then
		return false
	end

	local forward = guard.Root.CFrame.LookVector
	local angle = math.deg(math.acos(math.clamp(forward:Dot(toPlayer.Unit), -1, 1)))
	if angle > B.GuardSightAngle then
		return false
	end

	local character = player.Character
	rayParams.FilterDescendantsInstances = { guard.Model, if character then character else guard.Model }
	local hit = workspace:Raycast(guard.Root.Position, toPlayer, rayParams)
	return hit == nil
end

local function patrol(guard: Guard, dt: number)
	if (guard.A - guard.B).Magnitude < 1 then
		return
	end
	guard.Alpha += guard.Direction * (B.GuardPatrolSpeed * dt) / math.max(1, (guard.A - guard.B).Magnitude)
	if guard.Alpha >= 1 then
		guard.Alpha = 1
		guard.Direction = -1
	elseif guard.Alpha <= 0 then
		guard.Alpha = 0
		guard.Direction = 1
	end

	local target = guard.A:Lerp(guard.B, guard.Alpha)
	local look = if guard.Direction > 0 then guard.B else guard.A
	guard.Root.CFrame = CFrame.lookAt(target, Vector3.new(look.X, target.Y, look.Z))
end

--==========================================================================

function GuardService.Init()
	for _, inst in CollectionService:GetTagged(Config.GuardTag) do
		register(inst)
	end
	CollectionService:GetInstanceAddedSignal(Config.GuardTag):Connect(register)
	CollectionService:GetInstanceRemovedSignal(Config.GuardTag):Connect(unregister)

	task.spawn(function()
		local last = os.clock()
		while true do
			task.wait(B.GuardTick)
			local now = os.clock()
			local dt = now - last
			last = now

			if #guards == 0 then
				continue
			end

			-- Sammle einmal alle lebenden Spieler, statt pro Wache erneut.
			local present: { { Player: Player, Position: Vector3 } } = {}
			for _, player in Players:GetPlayers() do
				local position = Geometry.AlivePosition(player)
				if position then
					table.insert(present, { Player = player, Position = position })
				end
			end

			for _, guard in guards do
				patrol(guard, dt)

				-- Sichtpruefung NUR, wenn ueberhaupt jemand in Reichweite ist.
				for _, entry in present do
					if (entry.Position - guard.Root.Position).Magnitude > B.GuardSightRange then
						guard.Seen[entry.Player] = nil
						continue
					end

					if canSee(guard, entry.Player, entry.Position) then
						local seenFor = (guard.Seen[entry.Player] or 0) + dt
						guard.Seen[entry.Player] = seenFor
						if seenFor >= B.GuardSpotSeconds then
							guard.Seen[entry.Player] = 0
							local group = guard.Model:GetAttribute("AlarmGroup")
							warn(("[GHOSTNET] Wache hat %s entdeckt - Alarm."):format(entry.Player.Name))
							RaidService.RaiseAlarm(
								entry.Player,
								if typeof(group) == "string" then group else "BANK",
								"Wache"
							)
						end
					else
						guard.Seen[entry.Player] = nil
					end
				end
			end
		end
	end)

	print(("[GHOSTNET] GuardService bereit. Sicht %d Studs, %d Grad - Wachen melden, sie greifen nicht an."):format(
		B.GuardSightRange,
		B.GuardSightAngle
	))
end

return GuardService
