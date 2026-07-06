--!strict
-- MonetizationService: Robux-Käufe (Developer Products + Season-Pass) und
-- die erspielte Zweitwährung "Trümmer".
--
-- Grundsätze (siehe MonetizationCatalog-Guard):
--   - Verkauft wird NUR Kosmetik. Der Katalog KANN strukturell nichts
--     anderes vergeben als Skin-IDs, und validate() prüft jeden Verweis.
--   - ProcessReceipt ist IDEMPOTENT: Receipt-IDs werden im Profil
--     (DataStore) geloggt; ein bekannter Beleg wird nur bestätigt, nie
--     doppelt gutgeschrieben (ReceiptLogic, pur getestet).
--   - Read-only-Sessions (Session-Lock verpasst) bekommen NIE Käufe
--     gutgeschrieben -> NotProcessedYet, Roblox versucht es später erneut,
--     wenn das Profil wieder speicherbar ist.
--   - Trümmer sind erspielt und NICHT kaufbar (Free-Progression).

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Network = require(Shared.Network)
local GameConfig = require(Shared.Config.GameConfig)
local SkinCatalog = require(Shared.Config.SkinCatalog)
local MonetizationCatalog = require(Shared.Config.MonetizationCatalog)
local ReceiptLogic = require(Shared.ReceiptLogic)
local LevelLogic = require(Shared.LevelLogic)
local Types = require(Shared.Types)

local DataService = require(script.Parent.DataService)
local SkinService = require(script.Parent.SkinService)

local MonetizationService = {}

local notificationEvent: RemoteEvent? = nil

local function notify(player: Player, message: string, kind: string)
	if notificationEvent ~= nil then
		(notificationEvent :: RemoteEvent):FireClient(player, message, kind)
	end
end

--------------------------------------------------------------------------
-- Gutschrift (der EINZIGE Weg, auf dem Käufe etwas vergeben)
--------------------------------------------------------------------------

-- Vergibt die Skins eines Produkts. Gibt false zurück, wenn das Profil
-- gerade nicht bereit/speicherbar ist (dann NICHT bestätigen!).
local function grantProduct(player: Player, def: MonetizationCatalog.ProductDef): boolean
	local profile = DataService.getProfile(player)
	if profile == nil or not DataService.isSaveable(player) then
		return false
	end
	for _, skinId in def.grantsSkins do
		SkinService.grantSkin(player, skinId)
	end
	notify(player, `Freigeschaltet: {def.displayName} - viel Spaß! 🎨`, "success")
	return true
end

--------------------------------------------------------------------------
-- ProcessReceipt (idempotent)
--------------------------------------------------------------------------

local function processReceipt(receiptInfo: { [string]: any }): Enum.ProductPurchaseDecision
	local def = MonetizationCatalog.findProductByProductId(receiptInfo.ProductId)
	if def == nil then
		warn(`[Turmfall] Unbekanntes Developer Product: {receiptInfo.ProductId}`)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
	if player == nil then
		return Enum.ProductPurchaseDecision.NotProcessedYet -- Spieler offline: später erneut
	end

	local profile = DataService.getProfile(player)
	if profile == nil or not DataService.isSaveable(player) then
		return Enum.ProductPurchaseDecision.NotProcessedYet -- lädt noch / read-only
	end

	-- Idempotenz: bekannter Beleg -> nur bestätigen, NICHT erneut vergeben.
	local receiptId = tostring(receiptInfo.PurchaseId)
	if ReceiptLogic.alreadyProcessed(profile.receiptIds, receiptId) then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	if not grantProduct(player, def) then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	ReceiptLogic.remember(profile.receiptIds, receiptId)
	DataService.markDirty(player)
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

--------------------------------------------------------------------------
-- Season-Pass (Gamepass, rein kosmetisch)
--------------------------------------------------------------------------

local function checkSeasonPass(player: Player)
	if MonetizationCatalog.SEASON_PASS_GAMEPASS_ID == 0 then
		return -- Platzhalter: Pass ist im Dashboard noch nicht angelegt
	end
	local ok, owns = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(player.UserId, MonetizationCatalog.SEASON_PASS_GAMEPASS_ID)
	end)
	if ok and owns == true then
		for _, skinId in MonetizationCatalog.SEASON_PASS_SKINS do
			SkinService.grantSkin(player, skinId)
		end
	elseif not ok then
		warn(`[Turmfall] UserOwnsGamePassAsync fehlgeschlagen: {owns}`)
	end
end

--------------------------------------------------------------------------
-- Trümmer: erspielte Zweitwährung
--------------------------------------------------------------------------

-- Rundenabschluss: Trümmer + XP aus Punkten und Teilnahme (RoundService).
-- Level-Aufstiege werden gefeiert - sichtbare Progression nach JEDER Runde
-- ist einer der stärksten Bindungs-Treiber der Roblox-Topspiele.
function MonetizationService.awardRoundDebris(entries: { Types.ScoreEntry })
	for _, entry in entries do
		local player = Players:GetPlayerByUserId(entry.userId)
		if player == nil then
			continue
		end
		local profile = DataService.getProfile(player)
		if profile == nil then
			continue
		end
		local earned = MonetizationCatalog.DEBRIS_ROUND_BONUS
			+ math.floor(entry.points / MonetizationCatalog.DEBRIS_PER_POINTS)
		profile.truemmer += earned
		profile.roundsPlayed += 1

		-- XP + Level-Aufstieg.
		local earnedXp = GameConfig.XP_ROUND_BONUS + entry.points * GameConfig.XP_PER_POINT
		local levelBefore = LevelLogic.levelForXp(profile.xp)
		profile.xp += earnedXp
		local levelAfter = LevelLogic.levelForXp(profile.xp)

		DataService.markDirty(player)
		SkinService.refresh(player)
		notify(player, `+{earned} 🧱 Trümmer und +{earnedXp} XP verdient!`, "info")
		if levelAfter > levelBefore then
			notify(player, `⬆️ LEVEL-AUFSTIEG! Du bist jetzt Level {levelAfter}! 🎉`, "success")
		end
	end
end

-- Handler: BuySkinWithDebris(skinId) -> (ok, err?).
local function handleBuyWithDebris(player: Player, skinIdArg: unknown): (boolean, any?)
	if typeof(skinIdArg) ~= "string" then
		return false, "Ungültiger Skin."
	end
	local skin = SkinCatalog.Skins[skinIdArg]
	if skin == nil or skin.priceDebris == nil then
		return false, "Diesen Skin gibt es nicht für Trümmer."
	end
	local profile = DataService.getProfile(player)
	if profile == nil then
		return false, "Dein Profil ist noch nicht geladen."
	end
	if not DataService.isSaveable(player) then
		return false, "Dein Spielstand ist gerade schreibgeschützt - versuche es später erneut."
	end
	if SkinService.ownsSkin(player, skin.id) then
		return false, "Diesen Skin besitzt du schon."
	end
	local price = skin.priceDebris :: number
	if profile.truemmer < price then
		return false, `Nicht genug Trümmer ({price} benötigt).`
	end

	profile.truemmer -= price
	SkinService.grantSkin(player, skin.id)
	DataService.markDirty(player)
	notify(player, `Gekauft: {skin.name} für {price} 🧱!`, "success")
	return true, nil
end

--------------------------------------------------------------------------
-- Studio-Testmodus
--------------------------------------------------------------------------

-- Test-Käufe sind AUSSCHLIESSLICH in Roblox Studio möglich und nur für
-- Produkte mit Platzhalter-ID (0). In einem veröffentlichten Spiel hat
-- dieser Pfad NIE eine Wirkung.
local function handleSimulatePurchase(player: Player, productKeyArg: unknown): (boolean, any?)
	if not RunService:IsStudio() then
		return false, "Test-Käufe sind nur in Roblox Studio möglich."
	end
	if typeof(productKeyArg) ~= "string" then
		return false, "Ungültige Anfrage."
	end
	local def = MonetizationCatalog.DEVPRODUCT_IDS[productKeyArg]
	if def == nil then
		return false, "Unbekanntes Produkt."
	end
	if def.productId ~= 0 then
		return false, "Dieses Produkt hat eine echte ID - bitte regulär kaufen."
	end
	if not grantProduct(player, def) then
		return false, "Dein Profil ist gerade nicht speicherbar."
	end
	return true, nil
end

function MonetizationService.init()
	-- GUARD hart beim Start: nur Kosmetik ist verkäuflich (wirft sonst).
	MonetizationCatalog.validate()

	notificationEvent = Network.getEvent("Notification")
	Network.getFunction("BuySkinWithDebris").OnServerInvoke = handleBuyWithDebris
	Network.getFunction("SimulatePurchase").OnServerInvoke = handleSimulatePurchase

	MarketplaceService.ProcessReceipt = processReceipt

	local function onPlayerAdded(player: Player)
		task.spawn(function()
			local profile = DataService.waitForProfile(player)
			if profile ~= nil then
				checkSeasonPass(player)
			end
		end)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
end

return MonetizationService
