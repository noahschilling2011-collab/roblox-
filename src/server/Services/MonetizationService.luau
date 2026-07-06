--!strict
-- MonetizationService: Robux-Käufe (Gamepässe + Developer Products) und
-- Verwaltung der Kauf-Kosmetik.
--
-- GRUNDSATZ: Für Robux gibt es ausschließlich Kosmetik (siehe
-- docs/MONETARISIERUNG.md und MonetizationConfig). Dieser Service vergibt
-- daher niemals Energie, Funde oder andere Spielvorteile.
--
-- Ablauf:
--   - Beim Beitritt werden alle konfigurierten Gamepässe geprüft
--     (UserOwnsGamePassAsync) und deren Kosmetik dauerhaft freigeschaltet.
--   - Kauf im Spiel: Der Client öffnet den Roblox-Kaufdialog selbst
--     (MarketplaceService.Prompt...); der Server verarbeitet das Ergebnis über
--     PromptGamePassPurchaseFinished bzw. ProcessReceipt.
--   - EquipCosmetic rüstet besessene Kosmetik pro Kategorie aus/ab.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local MonetizationConfig = require(ReplicatedStorage.Shared.Config.MonetizationConfig)

local DataService = require(script.Parent.DataService)
local PlanetService = require(script.Parent.PlanetService)

local PET_FOLLOW_OFFSET = Vector3.new(4, 3, 0) -- rechts neben und über dem Kopf
local PET_LERP_ALPHA = 0.25
local PET_UPDATE_SECONDS = 0.05
local PET_SIZE = 1.6

local cosmeticsUpdatedEvent: RemoteEvent? = nil
local notificationEvent: RemoteEvent? = nil

-- Aktive Haustier-Parts pro Spieler.
local activePets: { [Player]: BasePart } = {}

local MonetizationService = {}

local function fireCosmeticsUpdated(player: Player)
	local profile = DataService.getProfile(player)
	if profile == nil or cosmeticsUpdatedEvent == nil then
		return
	end
	cosmeticsUpdatedEvent:FireClient(player, profile.ownedCosmetics, profile.equippedCosmetics)
end

local function notify(player: Player, message: string, kind: string)
	if notificationEvent ~= nil then
		notificationEvent:FireClient(player, message, kind)
	end
end

local function ownsCosmetic(profile: Types.PlayerProfile, cosmeticId: string): boolean
	for _, owned in profile.ownedCosmetics do
		if owned == cosmeticId then
			return true
		end
	end
	return false
end

-- Entfernt und (falls ausgerüstet) erzeugt das Haustier eines Spielers neu.
local function applyPet(player: Player)
	local existing = activePets[player]
	if existing ~= nil then
		existing:Destroy()
		activePets[player] = nil
	end

	local profile = DataService.getProfile(player)
	if profile == nil then
		return
	end

	local petId = profile.equippedCosmetics.haustier
	local petDef = if petId ~= nil then MonetizationConfig.Cosmetics[petId] else nil
	if petDef == nil or petDef.category ~= "haustier" then
		return
	end

	local pet = Instance.new("Part")
	pet.Name = `Pet_{player.UserId}`
	pet.Shape = Enum.PartType.Ball
	pet.Size = Vector3.new(PET_SIZE, PET_SIZE, PET_SIZE)
	pet.Anchored = true
	pet.CanCollide = false
	pet.CanQuery = false
	pet.Material = petDef.visual.material or Enum.Material.Neon
	pet.Color = petDef.visual.color or Color3.new(1, 1, 1)

	if petDef.visual.glow == true then
		local light = Instance.new("PointLight")
		light.Color = pet.Color
		light.Range = 12
		light.Brightness = 1
		light.Parent = pet
	end

	-- Startposition: direkt beim Charakter (falls vorhanden), sonst beim Plot.
	local character = player.Character
	local root = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
	if root ~= nil and root:IsA("BasePart") then
		pet.CFrame = (root :: BasePart).CFrame * CFrame.new(PET_FOLLOW_OFFSET)
	else
		local origin = PlanetService.getPlotOrigin(player)
		if origin ~= nil then
			pet.CFrame = origin * CFrame.new(PET_FOLLOW_OFFSET)
		end
	end

	pet.Parent = workspace
	activePets[player] = pet
end

-- Schaltet Kosmetik dauerhaft frei und meldet dem Client den neuen Stand.
local function grantCosmetics(player: Player, cosmeticIds: { string }, sourceName: string)
	local profile = DataService.getProfile(player)
	if profile == nil then
		return
	end

	local grantedAny = false
	for _, cosmeticId in cosmeticIds do
		local def = MonetizationConfig.Cosmetics[cosmeticId]
		if def == nil then
			warn(`[PlanetForge] Unbekannte Kosmetik in Konfiguration: {cosmeticId}`)
		elseif not ownsCosmetic(profile, cosmeticId) then
			table.insert(profile.ownedCosmetics, cosmeticId)
			grantedAny = true
		end
	end

	if grantedAny then
		DataService.markDirty(player)
		fireCosmeticsUpdated(player)
		notify(player, `Freigeschaltet: {sourceName} – öffne den Shop zum Ausrüsten!`, "success")
	end
end

-- Prüft alle konfigurierten Gamepässe für einen Spieler (pcall pro Pass).
local function checkGamepasses(player: Player)
	for _, def in MonetizationConfig.Gamepasses do
		if def.gamePassId == 0 then
			continue -- Platzhalter: Pass wurde im Dashboard noch nicht angelegt
		end
		local ok, owns = pcall(function()
			return MarketplaceService:UserOwnsGamePassAsync(player.UserId, def.gamePassId)
		end)
		if ok and owns == true then
			grantCosmetics(player, def.grantsCosmetics, def.displayName)
		elseif not ok then
			warn(`[PlanetForge] UserOwnsGamePassAsync fehlgeschlagen ({def.key}): {owns}`)
		end
	end
end

-- Handler für EquipCosmetic(category, cosmeticId?).
local function onEquipCosmetic(player: Player, categoryArg: any, cosmeticArg: any): (boolean, any?)
	if typeof(categoryArg) ~= "string" or MonetizationConfig.CategoryNames[categoryArg] == nil then
		return false, "Unbekannte Kosmetik-Kategorie."
	end

	local profile = DataService.getProfile(player)
	if profile == nil then
		return false, "Dein Profil ist noch nicht geladen."
	end

	if cosmeticArg == nil then
		-- Kategorie ablegen.
		profile.equippedCosmetics[categoryArg] = nil
	else
		if typeof(cosmeticArg) ~= "string" then
			return false, "Ungültige Kosmetik."
		end
		local def = MonetizationConfig.Cosmetics[cosmeticArg]
		if def == nil or def.category ~= categoryArg then
			return false, "Diese Kosmetik passt nicht zur Kategorie."
		end
		if not ownsCosmetic(profile, cosmeticArg) then
			return false, "Diese Kosmetik besitzt du noch nicht."
		end
		profile.equippedCosmetics[categoryArg] = cosmeticArg
	end

	DataService.markDirty(player)
	fireCosmeticsUpdated(player)
	PlanetService.applyCosmetics(player)
	if categoryArg == "haustier" then
		applyPet(player)
	end
	return true, nil
end

-- Verarbeitet Developer-Product-Käufe. Muss idempotent und robust sein:
-- Roblox ruft ProcessReceipt erneut auf, solange nicht PurchaseGranted
-- zurückgegeben wurde.
local function processReceipt(receiptInfo: { [string]: any }): Enum.ProductPurchaseDecision
	local productDef = MonetizationConfig.findProductByProductId(receiptInfo.ProductId)
	if productDef == nil then
		warn(`[PlanetForge] Unbekanntes Developer Product: {receiptInfo.ProductId}`)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
	if player == nil then
		return Enum.ProductPurchaseDecision.NotProcessedYet -- Spieler offline: später erneut
	end

	local profile = DataService.getProfile(player)
	if profile == nil then
		return Enum.ProductPurchaseDecision.NotProcessedYet -- Profil lädt noch
	end

	grantCosmetics(player, { productDef.grantsCosmetic }, productDef.displayName)
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

local function onPlayerAdded(player: Player)
	local profile = DataService.waitForProfile(player)
	if profile == nil then
		return -- Spieler bereits weg
	end

	checkGamepasses(player)
	fireCosmeticsUpdated(player)
	PlanetService.applyCosmetics(player)
	applyPet(player)
end

local function onPlayerRemoving(player: Player)
	local pet = activePets[player]
	if pet ~= nil then
		pet:Destroy()
	end
	activePets[player] = nil
end

function MonetizationService.init()
	cosmeticsUpdatedEvent = Remotes.getEvent("CosmeticsUpdated")
	notificationEvent = Remotes.getEvent("Notification")
	Remotes.getFunction("EquipCosmetic").OnServerInvoke = onEquipCosmetic

	-- Gamepass-Kauf im laufenden Spiel: Kosmetik sofort gutschreiben.
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(
		function(player: Player, gamePassId: number, wasPurchased: boolean)
			if not wasPurchased then
				return
			end
			for _, def in MonetizationConfig.Gamepasses do
				if def.gamePassId ~= 0 and def.gamePassId == gamePassId then
					grantCosmetics(player, def.grantsCosmetics, def.displayName)
					break
				end
			end
		end
	)

	-- Developer Products (nur ein ProcessReceipt pro Spiel möglich).
	MarketplaceService.ProcessReceipt = processReceipt

	Players.PlayerAdded:Connect(function(player)
		task.spawn(onPlayerAdded, player)
	end)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	-- Haustier-Folgeschleife: sanftes Nachschweben hinter dem Besitzer.
	task.spawn(function()
		while true do
			task.wait(PET_UPDATE_SECONDS)
			for player, pet in activePets do
				local character = player.Character
				if character == nil then
					continue
				end
				local root = character:FindFirstChild("HumanoidRootPart")
				if root == nil or not root:IsA("BasePart") then
					continue
				end
				local target = (root :: BasePart).CFrame * CFrame.new(PET_FOLLOW_OFFSET)
				pet.CFrame = pet.CFrame:Lerp(target, PET_LERP_ALPHA)
			end
		end
	end)
end

return MonetizationService
