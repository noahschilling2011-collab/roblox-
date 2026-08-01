-- ServerScriptService/Systems/SellService.luau
--!strict
-- GHOSTNET :: Der Hehler. Der Moment, der aus Zahlen eine Entscheidung macht.
--
-- Unverkauftes ist heiss und beim Bust weg. Gebankt ist sicher. Der Weg zum
-- Hehler kostet Zeit, und der Trace laeuft waehrenddessen weiter. Genau
-- deshalb ist "noch ein Ziel mitnehmen oder jetzt abliefern?" die zentrale
-- Frage jeder Runde - und nicht bloss ein Knopf.
--
-- Ein Hehler ist genau wie ein Hack-Ziel nur ein BasePart mit einem Tag
-- ("GhostNetFence"). Kein Code noetig, um einen zweiten aufzustellen.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Geometry = require(ReplicatedStorage.Shared.Geometry)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local EconomyService = require(script.Parent.EconomyService)
local RateLimiter = require(script.Parent.RateLimiter)
local SaveService = require(script.Parent.SaveService)
local TraceService = require(script.Parent.TraceService)

local SellService = {}

--==========================================================================
-- Hehler finden
--==========================================================================

-- Naechster Hehler zum Spieler. Liefert (part, distanz) oder (nil, math.huge).
function SellService.NearestFence(player: Player): (BasePart?, number)
	local position = Geometry.AlivePosition(player)
	if not position then
		return nil, math.huge
	end

	local best: BasePart? = nil
	local bestDistance = math.huge

	for _, inst in CollectionService:GetTagged(Config.FenceTag) do
		if inst:IsA("BasePart") and inst:IsDescendantOf(workspace) then
			local distance = Geometry.SurfaceDistance(inst, position)
			if distance < bestDistance then
				best, bestDistance = inst, distance
			end
		end
	end

	return best, bestDistance
end

--==========================================================================
-- Verkauf
--==========================================================================

local function reply(player: Player, ok: boolean, reason: string, extra: { [string]: any }?)
	if not player.Parent then
		return
	end
	local payload: { [string]: any } = { Ok = ok, Reason = reason }
	if extra then
		for key, value in extra do
			payload[key] = value
		end
	end
	Remotes.SellResult:FireClient(player, payload)
end

local function onSellRequest(player: Player, payload: any)
	if not RateLimiter.Check(player, "SellRequest") then
		return
	end
	-- Der Client schickt hier bewusst nichts Inhaltliches. Kommt trotzdem
	-- etwas anderes als eine Tabelle an, ist das kein gueltiger Aufruf.
	if payload ~= nil and typeof(payload) ~= "table" then
		return
	end

	if not SaveService.IsReady(player) then
		reply(player, false, "LOADING")
		return
	end

	local fence, distance = SellService.NearestFence(player)
	if not fence then
		reply(player, false, "NO_FENCE")
		return
	end

	-- Distanz wird serverseitig geprueft, exakt wie beim Hacken.
	local range = Config.Sell.Range + Config.Sell.Tolerance
	if distance > range then
		reply(player, false, "RANGE", { Distance = math.floor(distance), Range = Config.Sell.Range })
		return
	end

	local unsold = EconomyService.GetUnsold(player)
	if unsold < Config.Sell.MinAmount then
		reply(player, false, "EMPTY")
		return
	end

	-- Gerechnet und gebucht wird ausschliesslich im EconomyService.
	local gross, fee, net = EconomyService.SellUnsold(player, Config.Sell.FeePercent)
	if net <= 0 and gross <= 0 then
		reply(player, false, "EMPTY")
		return
	end

	-- Der Hehler ist nicht nur eine Bank, sondern der sichere Hafen.
	TraceService.Relieve(player, Config.Sell.TraceRelief)
	SaveService.RequestSave(player)

	reply(player, true, "OK", {
		Gross = gross,
		Fee = fee,
		Net = net,
		Relief = Config.Sell.TraceRelief,
		FenceName = fence:GetAttribute("DisplayName") or fence.Name,
	})
end

--==========================================================================

function SellService.Init()
	Remotes.SellRequest.OnServerEvent:Connect(onSellRequest)

	local count = 0
	for _, inst in CollectionService:GetTagged(Config.FenceTag) do
		if inst:IsA("BasePart") then
			count += 1
		end
	end

	print(("[GHOSTNET] SellService bereit. %d Hehler, Gebuehr %d%%, Trace -%d."):format(
		count,
		math.floor(Config.Sell.FeePercent * 100),
		Config.Sell.TraceRelief
	))
end

return SellService
