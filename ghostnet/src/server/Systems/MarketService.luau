-- ServerScriptService/Systems/MarketService.luau
--!strict
-- GHOSTNET :: Die Preise im Darknet.
--
-- WARUM SICH DIE PREISE BEWEGEN MUESSEN
--   Ein fester Kurs macht aus Handel einen Knopf, der 100 in 120 verwandelt.
--   Das ist kein Spiel. Erst wenn ein Preis steigen UND fallen kann, wird
--   aus "kaufen" eine Entscheidung.
--
-- MEAN REVERSION
--   Ein reiner Zufallslauf driftet nach ein paar Stunden ins Absurde -
--   irgendwann kostet ein Datenpaket 40.000. Deshalb zieht jeder Tick den
--   Kurs ein Stueck zum Basispreis zurueck. Der Kurs schwankt, aber er
--   entgleist nicht.
--
-- SERVERWEIT, NICHT PRO SPIELER
--   Alle sehen denselben Kurs. Nur so kann jemand "Ausweise sind gerade
--   oben" in den Chat schreiben, und nur so wirkt ein Event wie ein
--   Ereignis statt wie ein Zufall.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Goods = require(ReplicatedStorage.Shared.Goods)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local MarketService = {}

type Quote = {
	Factor: number, -- Kursfaktor, 1.0 = Basispreis
	History: { number }, -- die letzten Faktoren, fuer den Mini-Chart
}

type MarketEvent = {
	Group: string,
	Strength: number, -- positiv = Preise hoch
	TicksLeft: number,
	Text: string,
}

local quotes: { [string]: Quote } = {}
local activeEvent: MarketEvent? = nil
local rng = Random.new()

--==========================================================================
-- Preise
--==========================================================================

function MarketService.GetFactor(goodId: string): number
	local quote = quotes[goodId]
	return if quote then quote.Factor else 1.0
end

-- Was der Spieler beim Kauf zahlt bzw. beim Verkauf bekommt. Diese beiden
-- Funktionen sind die EINZIGE Preisquelle; der InventoryService fragt hier
-- und liest niemals einen Preis aus einem Client-Paket.
function MarketService.GetBuyPrice(goodId: string): number?
	local good = Goods.Get(goodId)
	if not good then
		return nil
	end
	return Config.GetBuyPrice(good.Base, MarketService.GetFactor(goodId))
end

function MarketService.GetSellPrice(goodId: string): number?
	local good = Goods.Get(goodId)
	if not good then
		return nil
	end
	return Config.GetSellPrice(good.Base, MarketService.GetFactor(goodId))
end

-- Vollstaendige Marktlage fuer die UI.
function MarketService.Snapshot(): { [string]: any }
	local entries: { { [string]: any } } = {}
	for _, good in Goods.List do
		local quote = quotes[good.Id]
		table.insert(entries, {
			Id = good.Id,
			Name = good.Name,
			Blurb = good.Blurb,
			Group = good.Group,
			Base = good.Base,
			Risk = good.Risk,
			Factor = if quote then quote.Factor else 1.0,
			Buy = Config.GetBuyPrice(good.Base, if quote then quote.Factor else 1.0),
			Sell = Config.GetSellPrice(good.Base, if quote then quote.Factor else 1.0),
			History = if quote then table.clone(quote.History) else { 1.0 },
		})
	end

	return {
		Goods = entries,
		Event = if activeEvent
			then { Group = activeEvent.Group, Text = activeEvent.Text, TicksLeft = activeEvent.TicksLeft }
			else nil,
		TickSeconds = Config.Market.TickSeconds,
	}
end

local function broadcast()
	local snapshot = MarketService.Snapshot()
	for _, player in Players:GetPlayers() do
		Remotes.MarketSync:FireClient(player, snapshot)
	end
end

function MarketService.SyncTo(player: Player)
	if player.Parent then
		Remotes.MarketSync:FireClient(player, MarketService.Snapshot())
	end
end

--==========================================================================
-- Bewegung
--==========================================================================

local function rollEvent()
	if activeEvent then
		activeEvent.TicksLeft -= 1
		if activeEvent.TicksLeft <= 0 then
			activeEvent = nil
		end
		return
	end

	if rng:NextNumber() > Config.Market.EventChancePerTick then
		return
	end

	-- Eine Gruppe zufaellig auswaehlen.
	local groups: { string } = {}
	local seen: { [string]: boolean } = {}
	for _, good in Goods.List do
		if not seen[good.Group] then
			seen[good.Group] = true
			table.insert(groups, good.Group)
		end
	end
	if #groups == 0 then
		return
	end

	local group = groups[rng:NextInteger(1, #groups)]
	local up = rng:NextNumber() < 0.5
	local strength = rng:NextNumber(Config.Market.EventStrengthMin, Config.Market.EventStrengthMax)
	if not up then
		strength = -strength
	end

	local text = if up
		then ("RAZZIA // %s knapp:  +%d%%"):format(group, math.floor(strength * 100 + 0.5))
		else ("LECK // %s ueberschwemmt:  %d%%"):format(group, math.floor(strength * 100 - 0.5))

	activeEvent = {
		Group = group,
		Strength = strength,
		TicksLeft = Config.Market.EventDurationTicks,
		Text = text,
	}

	print(("[GHOSTNET] Markt-Event: %s"):format(text))
	for _, player in Players:GetPlayers() do
		Remotes.MarketEvent:FireClient(player, { Text = text, Group = group })
	end
end

local function tickPrices()
	rollEvent()

	for _, good in Goods.List do
		local quote = quotes[good.Id]
		if not quote then
			continue
		end

		-- 1. Zufallsschritt im Rahmen der Volatilitaet.
		local drift = rng:NextNumber(-good.Volatility, good.Volatility)

		-- 2. Rueckkehr zum Basispreis (1.0). Das ist der Anker, ohne den
		--    der Kurs davonlaeuft.
		local pull = (1.0 - quote.Factor) * Config.Market.MeanReversion

		-- 3. Ein laufendes Event zieht die ganze Gruppe.
		local eventPush = 0
		if activeEvent and activeEvent.Group == good.Group then
			eventPush = activeEvent.Strength / Config.Market.EventDurationTicks
		end

		quote.Factor = math.clamp(
			quote.Factor + drift + pull + eventPush,
			Config.Market.MinFactor,
			Config.Market.MaxFactor
		)

		table.insert(quote.History, quote.Factor)
		while #quote.History > Config.Market.HistoryPoints do
			table.remove(quote.History, 1)
		end
	end

	broadcast()
end

--==========================================================================

function MarketService.Init()
	local valid, errors = Goods.Validate()
	if not valid then
		for _, message in errors do
			warn(("[GHOSTNET] Warenkatalog: %s"):format(message))
		end
	end

	for _, good in Goods.List do
		-- Kein Kaltstart auf exakt 1.0: sonst sehen alle Waren beim
		-- Serverstart gleich langweilig aus.
		local start = 1.0 + rng:NextNumber(-good.Volatility, good.Volatility)
		quotes[good.Id] = { Factor = start, History = { start } }
	end

	Players.PlayerAdded:Connect(function(player)
		task.defer(MarketService.SyncTo, player)
	end)
	for _, player in Players:GetPlayers() do
		task.defer(MarketService.SyncTo, player)
	end

	task.spawn(function()
		while true do
			task.wait(Config.Market.TickSeconds)
			local ok, err = pcall(tickPrices)
			if not ok then
				warn(("[GHOSTNET] Markt-Tick fehlgeschlagen: %s"):format(tostring(err)))
			end
		end
	end)

	print(("[GHOSTNET] MarketService bereit. %d Waren, Takt %ds."):format(
		Goods.Count(),
		Config.Market.TickSeconds
	))
end

return MarketService
