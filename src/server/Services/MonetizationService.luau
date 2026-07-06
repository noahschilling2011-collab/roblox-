--!strict
-- MonetizationService: Robux-Käufe (Gamepässe + Developer Products).
--
-- Kauf-Kette: Kosmetik (einmalig), Währungspakete und Sofort-Rebirth
-- (wiederholt kaufbar, idempotent über ein PurchaseId-Log im Profil) sowie
-- Gamepässe mit dauerhafter Wirkung (2x Multiplikator, +2 Pet-Slots, VIP).
-- Gekaufte Energie zählt bewusst NICHT zur Gesamt-Energie (keine gekauften
-- Freischaltungen). Studio-Testmodus simuliert Käufe NUR in Studio.
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
local RunService = game:GetService("RunService")

local Types = require(ReplicatedStorage.Shared.Types)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local MonetizationConfig = require(ReplicatedStorage.Shared.Config.MonetizationConfig)

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)

local DataService = require(script.Parent.DataService)
local EnergyService = require(script.Parent.EnergyService)
local EquipService = require(script.Parent.EquipService)
local PlanetService = require(script.Parent.PlanetService)
local ProgressionService = require(script.Parent.ProgressionService)

local PET_FOLLOW_OFFSET = Vector3.new(4, 3, 0) -- rechts neben und über dem Kopf
local PET_LERP_ALPHA = 0.25
local PET_UPDATE_SECONDS = 0.05
local PET_SIZE = 1.6

local cosmeticsUpdatedEvent: RemoteEvent? = nil
local notificationEvent: RemoteEvent? = nil

-- Aktive Haustier-Modelle pro Spieler.
local activePets: { [Player]: Model } = {}

local MonetizationService = {}

-- Gamepass-Besitz pro Spieler (beim Join geprueft, im Testmodus simulierbar).
local ownedPasses: { [Player]: { [string]: boolean } } = {}

-- Besitzt der Spieler den Gamepass mit diesem Config-Key?
function MonetizationService.hasPass(player: Player, key: string): boolean
	local passes = ownedPasses[player]
	return passes ~= nil and passes[key] == true
end

local function fireCosmeticsUpdated(player: Player)
	local profile = DataService.getProfile(player)
	if profile == nil or cosmeticsUpdatedEvent == nil then
		return
	end
	local passKeys: { [string]: boolean } = {}
	local passes = ownedPasses[player]
	if passes ~= nil then
		for key, owned in passes do
			if owned then
				passKeys[key] = true
			end
		end
	end
	cosmeticsUpdatedEvent:FireClient(player, profile.ownedCosmetics, profile.equippedCosmetics, passKeys)
end

local function notify(player: Player, message: string, kind: string)
	if notificationEvent ~= nil then
		notificationEvent:FireClient(player, message, kind)
	end
end

-- Goldener VIP-Trail am Charakter (unabhaengig vom Equip-System).
local function applyVipTrail(player: Player)
	local character = player.Character
	if character == nil then
		return
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if root == nil or not root:IsA("BasePart") then
		return
	end
	if root:FindFirstChild("VIPTrail") ~= nil then
		return
	end

	local top = Instance.new("Attachment")
	top.Name = "VIPTrailTop"
	top.Position = Vector3.new(0, 1, 0)
	top.Parent = root
	local bottom = Instance.new("Attachment")
	bottom.Name = "VIPTrailBottom"
	bottom.Position = Vector3.new(0, -1, 0)
	bottom.Parent = root

	local trail = Instance.new("Trail")
	trail.Name = "VIPTrail"
	trail.Attachment0 = top
	trail.Attachment1 = bottom
	trail.Color = ColorSequence.new(Color3.fromRGB(255, 210, 90))
	trail.Transparency = NumberSequence.new(0.1, 1)
	trail.Lifetime = 0.8
	trail.LightEmission = 1
	trail.Parent = root
end

-- Wendet die Wirkung neu erworbener Gamepaesse sofort an.
local function applyPassEffects(player: Player)
	if MonetizationService.hasPass(player, "gp_vip") then
		player:SetAttribute("PlanetForgeVIP", true)
		applyVipTrail(player)
	end
	-- Pet-Slots und Multiplikator lesen die Hooks live; nur UI informieren.
	EquipService.notify(player)
	ProgressionService.notifyMultiplier(player)
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

	-- Zusammengesetztes Mini-Model: Körper + Augen mit Pupillen; die
	-- Schwebe-Animation (Sine-Bobbing) macht die Folgeschleife.
	local petColor = petDef.visual.color or Color3.new(1, 1, 1)
	local pet = Instance.new("Model")
	pet.Name = `Pet_{player.UserId}`

	local function petPart(name: string, size: Vector3, color: Color3, material: Enum.Material, offset: CFrame): BasePart
		local part = Instance.new("Part")
		part.Name = name
		part.Shape = Enum.PartType.Ball
		part.Size = size
		part.Color = color
		part.Material = material
		part.CFrame = offset
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Parent = pet
		return part
	end

	local body = petPart(
		"Body",
		Vector3.new(PET_SIZE, PET_SIZE, PET_SIZE),
		petColor,
		petDef.visual.material or Enum.Material.Neon,
		CFrame.new()
	)
	-- Augen vorn (-Z), leicht nach außen versetzt.
	for side = -1, 1, 2 do
		local eyeOffset = CFrame.new(side * PET_SIZE * 0.22, PET_SIZE * 0.12, -PET_SIZE * 0.38)
		petPart(`Eye{side}`, Vector3.new(0.42, 0.42, 0.42), Color3.new(1, 1, 1), Enum.Material.SmoothPlastic, eyeOffset)
		petPart(
			`Pupil{side}`,
			Vector3.new(0.2, 0.2, 0.2),
			Color3.fromRGB(25, 25, 30),
			Enum.Material.SmoothPlastic,
			eyeOffset * CFrame.new(0, 0, -0.14)
		)
	end

	if petDef.visual.glow == true then
		local light = Instance.new("PointLight")
		light.Color = petColor
		light.Range = 12
		light.Brightness = 1
		light.Parent = body
	end

	pet.PrimaryPart = body

	-- Startposition: direkt beim Charakter (falls vorhanden), sonst beim Plot.
	local character = player.Character
	local root = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
	if root ~= nil and root:IsA("BasePart") then
		pet:PivotTo((root :: BasePart).CFrame * CFrame.new(PET_FOLLOW_OFFSET))
	else
		local origin = PlanetService.getPlotOrigin(player)
		if origin ~= nil then
			pet:PivotTo(origin * CFrame.new(PET_FOLLOW_OFFSET))
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
	local passes = ownedPasses[player]
	if passes == nil then
		passes = {}
		ownedPasses[player] = passes
	end
	for _, def in MonetizationConfig.Gamepasses do
		if def.gamePassId == 0 then
			continue -- Platzhalter: Pass wurde im Dashboard noch nicht angelegt
		end
		local ok, owns = pcall(function()
			return MarketplaceService:UserOwnsGamePassAsync(player.UserId, def.gamePassId)
		end)
		if ok and owns == true then
			passes[def.key] = true
			if #def.grantsCosmetics > 0 then
				grantCosmetics(player, def.grantsCosmetics, def.displayName)
			end
		elseif not ok then
			warn(`[PlanetForge] UserOwnsGamePassAsync fehlgeschlagen ({def.key}): {owns}`)
		end
	end
	applyPassEffects(player)
end

-- Gutschrift eines Developer Products (Kosmetik, Energie oder Sofort-Rebirth).
-- Wird von ProcessReceipt UND vom Studio-Testmodus genutzt.
local function grantProduct(player: Player, def: MonetizationConfig.ProductDef, sourceName: string): boolean
	if def.grantsCosmetic ~= nil then
		grantCosmetics(player, { def.grantsCosmetic :: string }, sourceName)
		return true
	end
	if def.grantsEnergy ~= nil then
		-- addRaw: gekaufte Energie zaehlt bewusst NICHT zur Gesamt-Energie
		-- (keine gekauften Freischaltungen/Rebirths).
		EnergyService.addRaw(player, def.grantsEnergy :: number)
		notify(player, `+{def.grantsEnergy} Energie gutgeschrieben ({sourceName})! ⚡`, "success")
		return true
	end
	if def.perk == "instant_rebirth" then
		local ok = ProgressionService.performRebirth(player, true)
		if ok then
			notify(player, `Sofort-Wiedergeburt eingeloest ({sourceName})! 🔄`, "success")
		end
		return ok == true
	end
	warn(`[PlanetForge] Produkt {def.key} hat keine Gutschrift-Regel`)
	return false
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
-- zurückgegeben wurde. Gegen Doppelgutschrift (z. B. Wiederholung nach
-- einem Absturz zwischen Gutschrift und Antwort) führt jedes Profil ein
-- PurchaseId-Log (GameConfig.PURCHASE_LOG_LIMIT Einträge).
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

	-- Idempotenz: bereits verarbeitete PurchaseId -> nur bestätigen.
	local purchaseId = tostring(receiptInfo.PurchaseId)
	if table.find(profile.purchaseIds, purchaseId) ~= nil then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	if not grantProduct(player, productDef, productDef.displayName) then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	table.insert(profile.purchaseIds, purchaseId)
	while #profile.purchaseIds > GameConfig.PURCHASE_LOG_LIMIT do
		table.remove(profile.purchaseIds, 1)
	end
	DataService.markDirty(player)
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

-- Studio-Testmodus: Käufe dürfen NUR simuliert werden, wenn das Config-Flag
-- gesetzt ist UND der Server in Roblox Studio läuft. In einem
-- veröffentlichten Spiel gibt diese Funktion immer false zurück - das ist
-- die harte Absicherung, die der SelfCheckService zusätzlich überwacht.
function MonetizationService.isTestPurchaseAllowed(): boolean
	return MonetizationConfig.testModeInStudio == true and RunService:IsStudio()
end

-- Handler für SimulatePurchase(kind, key): simuliert im Studio-Testmodus
-- den erfolgreichen Kauf eines noch nicht konfigurierten Produkts (ID 0),
-- damit Equip/Haustiere/Effekte ohne echte IDs testbar sind.
local function onSimulatePurchase(player: Player, kindArg: any, keyArg: any): (boolean, any?)
	if not MonetizationService.isTestPurchaseAllowed() then
		return false, "Test-Käufe sind nur im Studio-Testmodus möglich."
	end
	if typeof(kindArg) ~= "string" or typeof(keyArg) ~= "string" then
		return false, "Ungültige Anfrage."
	end

	if kindArg == "gamepass" then
		local def = MonetizationConfig.Gamepasses[keyArg]
		if def == nil then
			return false, "Unbekannter Gamepass."
		end
		if def.gamePassId ~= 0 then
			return false, "Dieser Gamepass hat eine echte ID - bitte regulär kaufen."
		end
		local passes = ownedPasses[player]
		if passes == nil then
			passes = {}
			ownedPasses[player] = passes
		end
		passes[def.key] = true
		if #def.grantsCosmetics > 0 then
			grantCosmetics(player, def.grantsCosmetics, `{def.displayName} (Test)`)
		else
			notify(player, `Gamepass simuliert: {def.displayName} (Test)`, "success")
		end
		applyPassEffects(player)
		fireCosmeticsUpdated(player)
		return true, nil
	elseif kindArg == "product" then
		local def = MonetizationConfig.DeveloperProducts[keyArg]
		if def == nil then
			return false, "Unbekanntes Produkt."
		end
		if def.productId ~= 0 then
			return false, "Dieses Produkt hat eine echte ID - bitte regulär kaufen."
		end
		grantProduct(player, def, `{def.displayName} (Test)`)
		return true, nil
	end

	return false, "Unbekannte Kaufart."
end

local function onPlayerAdded(player: Player)
	-- VIP-Trail nach jedem Respawn erneut anbringen (auch für Spieler,
	-- die vor dem Service-Start beigetreten sind, z. B. Studio-Solo).
	player.CharacterAdded:Connect(function()
		task.wait(0.5)
		if MonetizationService.hasPass(player, "gp_vip") then
			applyVipTrail(player)
		end
	end)

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
	ownedPasses[player] = nil
end

function MonetizationService.init()
	cosmeticsUpdatedEvent = Remotes.getEvent("CosmeticsUpdated")
	notificationEvent = Remotes.getEvent("Notification")
	Remotes.getFunction("EquipCosmetic").OnServerInvoke = onEquipCosmetic
	Remotes.getFunction("SimulatePurchase").OnServerInvoke = onSimulatePurchase

	if MonetizationService.isTestPurchaseAllowed() then
		print("[PlanetForge] Studio-Testmodus für den Shop ist AKTIV (nur in Studio wirksam).")
	end

	-- Gamepass-Wirkungen als Hooks verdrahten (vermeidet Service-Zyklen):
	-- 2x-Pass verdoppelt alle Einnahmen, +2-Pass erweitert die Pet-Slots.
	EnergyService.getPassMultiplier = function(player: Player): number
		return if MonetizationService.hasPass(player, "gp_double_mult") then 2 else 1
	end
	EquipService.getBonusPetSlots = function(player: Player): number
		return if MonetizationService.hasPass(player, "gp_pet_slots") then MonetizationConfig.PET_SLOTS_BONUS else 0
	end


	-- Gamepass-Kauf im laufenden Spiel: Kosmetik sofort gutschreiben.
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(
		function(player: Player, gamePassId: number, wasPurchased: boolean)
			if not wasPurchased then
				return
			end
			for _, def in MonetizationConfig.Gamepasses do
				if def.gamePassId ~= 0 and def.gamePassId == gamePassId then
					local passes = ownedPasses[player]
					if passes == nil then
						passes = {}
						ownedPasses[player] = passes
					end
					passes[def.key] = true
					if #def.grantsCosmetics > 0 then
						grantCosmetics(player, def.grantsCosmetics, def.displayName)
					end
					applyPassEffects(player)
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

	-- Haustier-Folgeschleife: sanftes Nachschweben hinter dem Besitzer
	-- plus Sine-Bobbing (jedes Haustier leicht phasenversetzt).
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
				local bob = math.sin(os.clock() * 2.4 + player.UserId % 7) * 0.45
				local target = (root :: BasePart).CFrame * CFrame.new(PET_FOLLOW_OFFSET + Vector3.new(0, bob, 0))
				pet:PivotTo(pet:GetPivot():Lerp(target, PET_LERP_ALPHA))
			end
		end
	end)
end

return MonetizationService
