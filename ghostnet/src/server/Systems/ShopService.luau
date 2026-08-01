-- ServerScriptService/Systems/ShopService.luau
--!strict
-- GHOSTNET :: Rig-Upgrades. Der Grund, warum Crypto etwas wert ist.
--
-- Der Client schickt ausschliesslich, WAS er kaufen will. Den Preis rechnet
-- der Server selbst aus Config.GetUpgradeCost - ein manipuliertes "Cost"-Feld
-- aus dem Client gibt es nicht, weil keins gelesen wird.
--
-- Bezahlt wird aus Banked. Unverkauftes zaehlt nicht: wer aufruesten will,
-- muss vorher zum Hehler.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local EconomyService = require(script.Parent.EconomyService)
local RateLimiter = require(script.Parent.RateLimiter)
local SaveService = require(script.Parent.SaveService)

local ShopService = {}

local function isComponent(name: any): boolean
	if typeof(name) ~= "string" then
		return false
	end
	for _, component in Config.Rig.Components do
		if component == name then
			return true
		end
	end
	return false
end

--==========================================================================
-- Kauf
--==========================================================================

-- Antwortet IMMER mit einer Tabelle { Ok, Reason, ... }. Ein RemoteFunction-
-- Handler darf nicht durchfallen, sonst haengt der Client im Invoke.
local function purchase(player: Player, payload: any): { [string]: any }
	if not RateLimiter.Check(player, "ShopPurchase") then
		return { Ok = false, Reason = "RATE" }
	end
	if typeof(payload) ~= "table" then
		return { Ok = false, Reason = "BAD_PAYLOAD" }
	end

	local component = (payload :: any).Component
	if not isComponent(component) then
		return { Ok = false, Reason = "BAD_PAYLOAD" }
	end

	local profile = SaveService.Get(player)
	if not profile then
		return { Ok = false, Reason = "LOADING" }
	end

	local current = (profile.Rig :: any)[component] :: number
	if current >= Config.Rig.MaxLevel then
		return { Ok = false, Reason = "MAX", Level = current, MaxLevel = Config.Rig.MaxLevel }
	end

	local targetLevel = current + 1
	local cost = Config.GetUpgradeCost(component, targetLevel)
	if cost == math.huge then
		return { Ok = false, Reason = "BAD_PAYLOAD" }
	end

	if profile.Banked < cost then
		return {
			Ok = false,
			Reason = "FUNDS",
			Cost = cost,
			Missing = cost - profile.Banked,
			Level = current,
		}
	end

	if not EconomyService.SpendBanked(player, cost) then
		return { Ok = false, Reason = "FUNDS", Cost = cost, Level = current }
	end
	if not EconomyService.SetRigLevel(player, component, targetLevel) then
		-- Kann eigentlich nicht passieren; wenn doch, Geld zurueck statt weg.
		EconomyService.RefundBanked(player, cost)
		EconomyService.Sync(player)
		return { Ok = false, Reason = "INTERNAL" }
	end

	EconomyService.Sync(player)
	SaveService.RequestSave(player)

	print(("[GHOSTNET] %s kauft %s auf Stufe %d fuer %d CRY."):format(player.Name, component, targetLevel, cost))

	return {
		Ok = true,
		Reason = "OK",
		Component = component,
		Level = targetLevel,
		Cost = cost,
		Snapshot = EconomyService.Snapshot(player),
	}
end

--==========================================================================

function ShopService.Init()
	Remotes.ShopPurchase.OnServerInvoke = function(player: Player, payload: any): { [string]: any }
		local ok, result = pcall(purchase, player, payload)
		if not ok then
			warn(("[GHOSTNET] ShopPurchase ist abgestuerzt: %s"):format(tostring(result)))
			return { Ok = false, Reason = "INTERNAL" }
		end
		return result
	end

	print(("[GHOSTNET] ShopService bereit. Erstes Upgrade ab %d CRY."):format(Config.GetUpgradeCost("Cooling", 2)))
end

return ShopService
