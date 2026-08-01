-- ServerScriptService/Systems/InventoryService.luau
--!strict
-- GHOSTNET :: Das Lager und der Handel.
--
-- SICHERHEIT - der Kern dieses Moduls
--   Der Client schickt ausschliesslich { GoodId, Amount, Action }. Den Preis
--   holt sich der Server selbst beim MarketService. Ein vom Client
--   geschickter Preis wird NIRGENDS gelesen - genau darueber werden
--   Handelssysteme in Roblox-Spielen sonst leergeraeumt.
--   Zusaetzlich: Menge muss eine positive Ganzzahl unter der Obergrenze
--   sein, Lagerplatz und Guthaben werden geprueft, bevor irgendetwas gebucht
--   wird.
--
-- RISIKO - sonst ist Handel nur Warten
--   * Lagerplatz ist begrenzt: man muss sich entscheiden.
--   * Ware im Lager ist heiss. Ein Bust kostet auch davon einen Teil, damit
--     der Handel am Trace-System haengt statt danebenher zu laufen.
--   * Ware mit hohem Risikowert ist manchmal Ausschuss. Das Rig-Tier senkt
--     die Quote - damit bekommt das Upgrade-System einen zweiten Zweck.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Goods = require(ReplicatedStorage.Shared.Goods)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local EconomyService = require(script.Parent.EconomyService)
local MarketService = require(script.Parent.MarketService)
local MissionService = require(script.Parent.MissionService)
local RateLimiter = require(script.Parent.RateLimiter)
local SaveService = require(script.Parent.SaveService)
local TraceService = require(script.Parent.TraceService)

local InventoryService = {}

local rng = Random.new()

--==========================================================================
-- Lager lesen
--==========================================================================

function InventoryService.Used(player: Player): number
	local profile = SaveService.Get(player)
	if not profile then
		return 0
	end
	local used = 0
	for _, amount in profile.Stash do
		used += amount
	end
	return used
end

function InventoryService.Slots(player: Player): number
	return Config.GetStashSlots(EconomyService.GetTier(player))
end

function InventoryService.Snapshot(player: Player): { [string]: any }
	local profile = SaveService.Get(player)
	local stash: { { [string]: any } } = {}

	if profile then
		for _, good in Goods.List do
			local amount = profile.Stash[good.Id]
			if amount and amount > 0 then
				table.insert(stash, {
					Id = good.Id,
					Name = good.Name,
					Amount = amount,
					Sell = MarketService.GetSellPrice(good.Id) or 0,
				})
			end
		end
	end

	return {
		Stash = stash,
		Used = InventoryService.Used(player),
		Slots = InventoryService.Slots(player),
		-- Fuer die Anzeige "wie oft ist die Ware Ausschuss" - abhaengig vom
		-- eigenen Rig, deshalb pro Spieler und nicht im Marktpaket.
		Tier = EconomyService.GetTier(player),
	}
end

function InventoryService.Sync(player: Player)
	if player.Parent then
		Remotes.InventorySync:FireClient(player, InventoryService.Snapshot(player))
	end
end

--==========================================================================
-- Bust: das Lager ist genauso heiss wie das Bargeld
--==========================================================================

local function onBust(player: Player)
	if Config.Market.BustStashLossPercent <= 0 then
		return
	end
	local profile = SaveService.Get(player)
	if not profile then
		return
	end

	local lost = 0
	for goodId, amount in profile.Stash do
		local remove = math.floor(amount * Config.Market.BustStashLossPercent + 0.5)
		if remove > 0 then
			profile.Stash[goodId] = math.max(0, amount - remove)
			if profile.Stash[goodId] == 0 then
				profile.Stash[goodId] = nil
			end
			lost += remove
		end
	end

	if lost > 0 then
		warn(("[GHOSTNET] Bust kostet %s zusaetzlich %d Einheiten Ware."):format(player.Name, lost))
		InventoryService.Sync(player)
		SaveService.RequestSave(player)
	end
end

--==========================================================================
-- Handel
--==========================================================================

local function result(ok: boolean, reason: string, extra: { [string]: any }?): { [string]: any }
	local payload: { [string]: any } = { Ok = ok, Reason = reason }
	if extra then
		for key, value in extra do
			payload[key] = value
		end
	end
	return payload
end

local function validAmount(value: any): number?
	if typeof(value) ~= "number" or value ~= value then
		return nil
	end
	if value % 1 ~= 0 or value < 1 or value > Config.Market.MaxPerTrade then
		return nil
	end
	return value
end

local function buy(player: Player, goodId: string, amount: number): { [string]: any }
	local profile = SaveService.Get(player)
	if not profile then
		return result(false, "LOADING")
	end

	local free = InventoryService.Slots(player) - InventoryService.Used(player)
	if amount > free then
		return result(false, "NO_SPACE", { Free = math.max(0, free), Slots = InventoryService.Slots(player) })
	end

	-- Preis kommt vom Server, nicht vom Client.
	local unit = MarketService.GetBuyPrice(goodId)
	if not unit then
		return result(false, "UNKNOWN_GOOD")
	end
	local total = unit * amount

	if profile.Banked < total then
		return result(false, "FUNDS", { Cost = total, Missing = total - profile.Banked, Unit = unit })
	end
	if not EconomyService.SpendBanked(player, total) then
		return result(false, "FUNDS", { Cost = total, Unit = unit })
	end

	profile.Stash[goodId] = (profile.Stash[goodId] or 0) + amount
	profile.Stats.GoodsBought += amount

	EconomyService.Sync(player)
	InventoryService.Sync(player)
	SaveService.RequestSave(player)

	-- BUY-Schritte in Missionen. Die Richtung ist bewusst
	-- InventoryService -> MissionService, nie umgekehrt.
	MissionService.NotifyBuy(player, goodId, amount)

	return result(true, "OK", { Unit = unit, Total = total, Amount = amount, GoodId = goodId })
end

local function sell(player: Player, goodId: string, amount: number): { [string]: any }
	local profile = SaveService.Get(player)
	if not profile then
		return result(false, "LOADING")
	end

	local owned = profile.Stash[goodId] or 0
	if owned < amount then
		return result(false, "NOT_OWNED", { Owned = owned })
	end

	local good = Goods.Get(goodId)
	local unit = MarketService.GetSellPrice(goodId)
	if not good or not unit then
		return result(false, "UNKNOWN_GOOD")
	end

	-- Faelschungen: pro Einheit gewuerfelt. Das Rig-Tier senkt die Quote.
	local risk = Config.GetFakeRisk(good.Risk, EconomyService.GetTier(player))
	local fakes = 0
	for _ = 1, amount do
		if rng:NextNumber() < risk then
			fakes += 1
		end
	end

	local sold = amount - fakes
	local total = unit * sold

	profile.Stash[goodId] = owned - amount
	if profile.Stash[goodId] <= 0 then
		profile.Stash[goodId] = nil
	end
	profile.Stats.GoodsSold += amount

	-- Erloes aus dem Darknet ist SAUBER: gehandelt wird vom Rechner aus, das
	-- muss nicht mehr durch den Hehler. Sonst waere Handel doppelt bestraft.
	if total > 0 then
		EconomyService.AwardBanked(player, total)
	else
		EconomyService.Sync(player)
	end

	InventoryService.Sync(player)
	SaveService.RequestSave(player)

	return result(true, "OK", {
		Unit = unit,
		Total = total,
		Amount = amount,
		Sold = sold,
		Fakes = fakes,
		GoodId = goodId,
	})
end

--==========================================================================
-- Remote
--==========================================================================

local function onTrade(player: Player, payload: any): { [string]: any }
	if not RateLimiter.Check(player, "Trade") then
		return result(false, "RATE")
	end
	if typeof(payload) ~= "table" then
		return result(false, "BAD_PAYLOAD")
	end

	-- Das Darknet ist erst ab M03 offen. Ohne diese Pruefung koennte ein
	-- Client die Remote einfach direkt feuern und den Hub ueberspringen.
	if not MissionService.HasUnlock(player, Config.Market.RequiredUnlock) then
		return result(false, "LOCKED")
	end

	local action = (payload :: any).Action
	local goodId = (payload :: any).GoodId
	if action ~= "BUY" and action ~= "SELL" then
		return result(false, "BAD_PAYLOAD")
	end
	if not Goods.Exists(goodId) then
		return result(false, "UNKNOWN_GOOD")
	end

	local amount = validAmount((payload :: any).Amount)
	if not amount then
		return result(false, "BAD_AMOUNT", { Max = Config.Market.MaxPerTrade })
	end

	if action == "BUY" then
		return buy(player, goodId, amount)
	end
	return sell(player, goodId, amount)
end

--==========================================================================

function InventoryService.Init()
	Remotes.Trade.OnServerInvoke = function(player: Player, payload: any): { [string]: any }
		local ok, response = pcall(onTrade, player, payload)
		if not ok then
			warn(("[GHOSTNET] Trade ist abgestuerzt: %s"):format(tostring(response)))
			return result(false, "INTERNAL")
		end
		return response
	end

	TraceService.OnBust(onBust)

	SaveService.OnReady(function(player)
		InventoryService.Sync(player)
	end)

	print(("[GHOSTNET] InventoryService bereit. Lager %d Plaetze, max %d pro Kauf."):format(
		Config.Market.SlotsBase,
		Config.Market.MaxPerTrade
	))
end

return InventoryService
