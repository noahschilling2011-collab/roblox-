-- ServerScriptService/Systems/MonetizationService.luau
--!strict
-- GHOSTNET :: Gamepaesse und Entwicklerprodukte.
--
-- WAS NICHT VERKAUFT WIRD
--   Nichts, das ein Raetsel loest. Keine Auto-Solves, keine Loesungshinweise.
--   Die einzige Faehigkeit, um die es in diesem Spiel geht, darf nicht
--   kaufbar sein. Nichts, das anderen Spielern schadet.
--   Erlaubt sind: Zeitersparnis, Kosmetik, Komfort, Kapazitaet.
--
-- DOPPELVERGABE
--   Roblox liefert einen Beleg WIEDERHOLT aus, solange der Server nicht
--   bestaetigt hat. Deshalb: verarbeitete PurchaseId im Profil merken, erst
--   gutschreiben UND speichern, dann PurchaseGranted zurueckgeben. Kommt
--   derselbe Beleg nochmal, wird sofort PurchaseGranted gemeldet, ohne
--   nochmal zu vergeben.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local EconomyService = require(script.Parent.EconomyService)
local RateLimiter = require(script.Parent.RateLimiter)
local SaveService = require(script.Parent.SaveService)
local TraceService = require(script.Parent.TraceService)

local MonetizationService = {}

--==========================================================================
-- ALLE IDs SIND 0 UND MUESSEN VON NOAH IM CREATOR DASHBOARD ANGELEGT UND
-- HIER EINGETRAGEN WERDEN. ERFINDE KEINE IDs - eine falsche ID schlaegt
-- stumm fehl und ist schwer zu finden.
--
-- Gamepass anlegen:  Creator Dashboard -> Spiel -> Monetization -> Passes
-- Produkt anlegen:   Creator Dashboard -> Spiel -> Monetization -> Developer Products
-- Die Zahl aus der Adresszeile ist die ID.
--==========================================================================

local IDS = {
	Gamepass = {
		ColdRig = 0, -- dauerhaft -25 % Trace-Anstieg
		BigStash = 0, -- +50 % Lagerplatz im Darknet
		VIPTerminal = 0, -- kosmetische Terminal-Themes
		ExtraSlot = 0, -- zweite parallele Mission
	},
	Product = {
		Crypto1k = 0,
		Crypto5k = 0,
		TraceReset = 0, -- Trace sofort auf 0
		CooldownWipe = 0, -- alle Ziel-Cooldowns loeschen
	},
}

MonetizationService.IDS = IDS

-- Was ein Pass bzw. Produkt bewirkt und kostet. Die Zahlen stehen in Config,
-- die Texte hier, weil sie zum Produkt gehoeren und nicht zum Balancing.
local PASS_INFO: { [string]: { Name: string, Text: string } } = {
	ColdRig = {
		Name = "COLD RIG",
		Text = ("Dauerhaft %d%% weniger Trace pro Hack."):format(math.floor(Config.Monetization.ColdRigTrace * 100)),
	},
	BigStash = {
		Name = "BIG STASH",
		Text = ("%d%% mehr Lagerplatz im Darknet."):format(math.floor(Config.Monetization.BigStashBonus * 100)),
	},
	VIPTerminal = { Name = "VIP TERMINAL", Text = "Kosmetische Terminal-Themes. Kein Spielvorteil." },
	ExtraSlot = { Name = "ZWEITER AUFTRAG", Text = "Ein zweiter Auftrag parallel." },
}

local PRODUCT_INFO: { [string]: { Name: string, Text: string } } = {
	Crypto1k = { Name = "1.000 CRY", Text = "Direkt auf die Bank." },
	Crypto5k = { Name = "5.000 CRY", Text = "Direkt auf die Bank." },
	TraceReset = { Name = "SPUR LOESCHEN", Text = "Trace sofort auf 0. Loest kein Raetsel." },
	CooldownWipe = { Name = "COOLDOWNS LOESCHEN", Text = "Alle Ziele sofort wieder frei." },
}

--==========================================================================
-- Besitz von Gamepaessen
--==========================================================================

-- Cache pro Spieler. UserOwnsGamePassAsync ist teuer und kann fehlschlagen -
-- bei einem Fehler darf NICHT angenommen werden, der Spieler besitze nichts.
local owned: { [Player]: { [string]: boolean } } = {}
local checkFailed: { [Player]: { [string]: boolean } } = {}

function MonetizationService.Owns(player: Player, passKey: string): boolean
	local perPlayer = owned[player]
	return perPlayer ~= nil and perPlayer[passKey] == true
end

local function checkPass(player: Player, passKey: string, id: number)
	if id == 0 then
		return -- noch nicht im Dashboard angelegt
	end

	for attempt = 1, Config.Monetization.OwnershipRetries do
		local ok, result = pcall(function()
			return MarketplaceService:UserOwnsGamePassAsync(player.UserId, id)
		end)
		if ok then
			local perPlayer = owned[player]
			if perPlayer then
				perPlayer[passKey] = result == true
			end
			if checkFailed[player] then
				checkFailed[player][passKey] = nil
			end
			return
		end
		warn(("[GHOSTNET] Besitzpruefung '%s' fuer %s fehlgeschlagen (%d/%d): %s"):format(
			passKey,
			player.Name,
			attempt,
			Config.Monetization.OwnershipRetries,
			tostring(result)
		))
		task.wait(Config.Monetization.OwnershipRetryDelay * attempt)
	end

	-- Endgueltig gescheitert: gemerkt, damit ein spaeterer Versuch es
	-- nachholt. NICHT als "besitzt nichts" behandeln.
	if checkFailed[player] then
		checkFailed[player][passKey] = true
	end
end

local function checkAllPasses(player: Player)
	owned[player] = owned[player] or {}
	checkFailed[player] = checkFailed[player] or {}
	for key, id in IDS.Gamepass do
		task.spawn(checkPass, player, key, id)
	end
end

--==========================================================================
-- Effekte der Paesse
-- Alle laufen ueber EconomyService bzw. SaveService, nirgends direkt.
--==========================================================================

-- Wird vom HackService ueber Config gelesen; hier nur die Abfrage.
function MonetizationService.TraceFactor(player: Player): number
	if MonetizationService.Owns(player, "ColdRig") then
		return 1 - Config.Monetization.ColdRigTrace
	end
	return 1
end

function MonetizationService.StashBonus(player: Player): number
	if MonetizationService.Owns(player, "BigStash") then
		return Config.Monetization.BigStashBonus
	end
	return 0
end

--==========================================================================
-- Produkte
--==========================================================================

local function grantProduct(player: Player, productKey: string): boolean
	if productKey == "Crypto1k" then
		EconomyService.AwardBanked(player, Config.Monetization.Crypto1k)
		return true
	elseif productKey == "Crypto5k" then
		EconomyService.AwardBanked(player, Config.Monetization.Crypto5k)
		return true
	elseif productKey == "TraceReset" then
		local profile = SaveService.Get(player)
		if not profile then
			return false
		end
		profile.Trace = 0
		TraceService.Sync(player, true)
		return true
	elseif productKey == "CooldownWipe" then
		local profile = SaveService.Get(player)
		if not profile then
			return false
		end
		table.clear(profile.Cooldowns)
		EconomyService.Sync(player)
		return true
	end
	return false
end

local function productKeyFor(productId: number): string?
	for key, id in IDS.Product do
		if id ~= 0 and id == productId then
			return key
		end
	end
	return nil
end

--==========================================================================
-- ProcessReceipt - der Teil, den man nicht falsch machen darf
--==========================================================================

local function processReceipt(receiptInfo: any): Enum.ProductPurchaseDecision
	local userId = receiptInfo.PlayerId
	local purchaseId = tostring(receiptInfo.PurchaseId)
	local player = Players:GetPlayerByUserId(userId)

	if not player then
		-- Spieler ist weg. NICHT bestaetigen - Roblox liefert den Beleg beim
		-- naechsten Join erneut aus, und dann bekommt er seine Ware.
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local profile = SaveService.Get(player)
	if not profile then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	-- Schon verarbeitet? Dann sofort bestaetigen, ohne nochmal zu vergeben.
	if table.find(profile.PurchaseLog, purchaseId) then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	local key = productKeyFor(receiptInfo.ProductId)
	if not key then
		warn(("[GHOSTNET] Unbekanntes Produkt %s gekauft - Beleg bleibt offen."):format(
			tostring(receiptInfo.ProductId)
		))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local ok, granted = pcall(grantProduct, player, key)
	if not ok or not granted then
		warn(("[GHOSTNET] Produkt '%s' konnte nicht vergeben werden: %s"):format(key, tostring(granted)))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	-- Erst merken, dann speichern, dann bestaetigen.
	table.insert(profile.PurchaseLog, purchaseId)
	while #profile.PurchaseLog > Config.Monetization.PurchaseLogLimit do
		table.remove(profile.PurchaseLog, 1)
	end

	local saved = SaveService.SaveNow(player)
	if not saved then
		-- Nicht bestaetigen: sonst waere die Ware vergeben, aber nicht
		-- gespeichert - beim naechsten Join waere sie weg und der Beleg
		-- verbraucht.
		warn(("[GHOSTNET] Kauf '%s' konnte nicht gespeichert werden - Beleg bleibt offen."):format(key))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	print(("[GHOSTNET] Kauf vergeben: %s an %s (Beleg %s)"):format(key, player.Name, purchaseId))
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

--==========================================================================
-- Anzeige
--==========================================================================

function MonetizationService.Sync(player: Player)
	if not player.Parent then
		return
	end

	local passes: { { [string]: any } } = {}
	for key, id in IDS.Gamepass do
		local info = PASS_INFO[key]
		table.insert(passes, {
			Key = key,
			Id = id,
			Name = if info then info.Name else key,
			Text = if info then info.Text else "",
			Owned = MonetizationService.Owns(player, key),
			Available = id ~= 0,
		})
	end

	local products: { { [string]: any } } = {}
	for key, id in IDS.Product do
		local info = PRODUCT_INFO[key]
		table.insert(products, {
			Key = key,
			Id = id,
			Name = if info then info.Name else key,
			Text = if info then info.Text else "",
			Available = id ~= 0,
		})
	end

	table.sort(passes, function(a, b)
		return (a.Key :: string) < (b.Key :: string)
	end)
	table.sort(products, function(a, b)
		return (a.Key :: string) < (b.Key :: string)
	end)

	Remotes.StoreSync:FireClient(player, { Passes = passes, Products = products })
end

--==========================================================================

-- Der Client bittet nur um den Dialog. Was er kostet und ob er zustande
-- kommt, entscheidet Roblox; was er bewirkt, entscheidet ProcessReceipt.
local function onPrompt(player: Player, payload: any)
	if not RateLimiter.Check(player, "StorePrompt") then
		return
	end
	if typeof(payload) ~= "table" then
		return
	end
	local kind = (payload :: any).Kind
	local key = (payload :: any).Key
	if typeof(key) ~= "string" then
		return
	end

	if kind == "Gamepass" then
		local id = (IDS.Gamepass :: any)[key]
		if typeof(id) == "number" and id ~= 0 then
			pcall(function()
				MarketplaceService:PromptGamePassPurchase(player, id)
			end)
		end
	elseif kind == "Product" then
		local id = (IDS.Product :: any)[key]
		if typeof(id) == "number" and id ~= 0 then
			pcall(function()
				MarketplaceService:PromptProductPurchase(player, id)
			end)
		end
	end
end

function MonetizationService.Init()
	Remotes.StorePrompt.OnServerEvent:Connect(onPrompt)

	MarketplaceService.ProcessReceipt = function(receiptInfo)
		local ok, decision = pcall(processReceipt, receiptInfo)
		if not ok then
			warn(("[GHOSTNET] ProcessReceipt ist abgestuerzt: %s"):format(tostring(decision)))
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		return decision
	end

	-- Live-Aktivierung ohne Rejoin.
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, gamePassId, wasPurchased)
		if not wasPurchased then
			return
		end
		for key, id in IDS.Gamepass do
			if id ~= 0 and id == gamePassId then
				local perPlayer = owned[player]
				if perPlayer then
					perPlayer[key] = true
				end
				print(("[GHOSTNET] %s besitzt jetzt %s."):format(player.Name, key))
				MonetizationService.Sync(player)
				break
			end
		end
	end)

	SaveService.OnReady(function(player)
		checkAllPasses(player)
		task.delay(1, function()
			if player.Parent then
				MonetizationService.Sync(player)
			end
		end)
	end)

	Players.PlayerRemoving:Connect(function(player)
		owned[player] = nil
		checkFailed[player] = nil
	end)

	-- Fehlgeschlagene Besitzpruefungen spaeter nachholen.
	task.spawn(function()
		while true do
			task.wait(Config.Monetization.OwnershipRecheckSeconds)
			for player, failed in checkFailed do
				for key in failed do
					local id = (IDS.Gamepass :: any)[key]
					if typeof(id) == "number" and id ~= 0 then
						task.spawn(checkPass, player, key, id)
					end
				end
			end
		end
	end)

	local configured = 0
	for _, id in IDS.Gamepass do
		if id ~= 0 then
			configured += 1
		end
	end
	for _, id in IDS.Product do
		if id ~= 0 then
			configured += 1
		end
	end

	if configured == 0 then
		print("[GHOSTNET] MonetizationService bereit. Keine IDs eingetragen - der Store ist leer.")
	else
		print(("[GHOSTNET] MonetizationService bereit. %d IDs eingetragen."):format(configured))
	end
end

return MonetizationService
