--!strict
-- Kauf von Tasten und Steckplaetzen. Der Client schickt nur eine Absicht -
-- Preis, Kontostand und Platz prueft ausschliesslich der Server.

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local EconomyConfig = require(Shared.Config.EconomyConfig)
local EconomyLogic = require(Shared.EconomyLogic)
local Remotes = require(Shared.Remotes)
local RateLimit = require(Shared.RateLimit)
local DataService = require(script.Parent.DataService)
local PlotService = require(script.Parent.PlotService)

local ShopService = {}

local function notify(player: Player, text: string)
	Remotes.get("Notify"):FireClient(player, text)
end

local function isKnownRarity(name: any): boolean
	if type(name) ~= "string" then
		return false
	end
	return EconomyConfig.RARITIES[name] ~= nil
end

local function onBuyKey(player: Player, rarityName: any)
	if not RateLimit.allow(player.UserId, "buyKey", EconomyConfig.REMOTE_RATE_LIMIT) then
		return
	end
	if not isKnownRarity(rarityName) then
		return -- Typ-Check am Server-Eingang: unbekannte Werte still verwerfen
	end
	local profile = DataService.get(player)
	if not profile then
		return
	end
	if #profile.keys >= profile.slots then
		notify(player, "Alle Steckplaetze belegt - erst einen Slot kaufen.")
		return
	end
	local price = EconomyLogic.rarity(rarityName).price
	if profile.wins < price then
		notify(player, ("Zu wenig Wins: %d von %d."):format(profile.wins, price))
		return
	end

	profile.wins -= price
	table.insert(profile.keys, { rarity = rarityName, vorrat = 0 })
	PlotService.rebuildKeys(player.UserId)
	DataService.syncLeaderstats(player)
	notify(player, ("%s gekauft (-%d Wins)."):format(rarityName, price))
end

local function onBuySlot(player: Player)
	if not RateLimit.allow(player.UserId, "buySlot", EconomyConfig.REMOTE_RATE_LIMIT) then
		return
	end
	local profile = DataService.get(player)
	if not profile then
		return
	end
	local price = EconomyLogic.slotPrice(profile.slots)
	if not price then
		notify(player, "Du hast schon alle Steckplaetze.")
		return
	end
	if profile.wins < price then
		notify(player, ("Zu wenig Wins: %d von %d."):format(profile.wins, price))
		return
	end

	profile.wins -= price
	profile.slots += 1
	DataService.syncLeaderstats(player)
	notify(player, ("Steckplatz %d gekauft (-%d Wins)."):format(profile.slots, price))
end

function ShopService.start()
	Remotes.get("BuyKey").OnServerEvent:Connect(onBuyKey)
	Remotes.get("BuySlot").OnServerEvent:Connect(onBuySlot)
	Players.PlayerRemoving:Connect(function(player)
		RateLimit.forget(player.UserId)
	end)
	print("[KEYCAP] ShopService laeuft")
end

return ShopService
