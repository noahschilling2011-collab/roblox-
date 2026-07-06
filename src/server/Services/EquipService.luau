--!strict
-- EquipService: Ausrüsten von Loot-Items (Pets, Trails, Skins).
--
-- Gezogene Sammelobjekte (profile.collectibles) lassen sich ausrüsten:
--   - Pets (Tiere): folgen sichtbar mit Schwebe-Bobbing und geben ihren
--     Multiplikator-Bonus NUR solange sie ausgerüstet sind. Max. Slots:
--     GameConfig.BASE_PET_SLOTS (+ Gamepass-Bonus über setBonusPetSlots).
--   - Trails (Artefakte): sichtbare Leuchtspur hinter dem Charakter.
--   - Skins (Pflanzen): farbiger Glow um den Charakter.
--
-- Ausgerüstetes wird serverseitig im Profil gespeichert (equipped) und beim
-- Join wiederhergestellt. Der Server validiert Besitz und Slot-Grenzen.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local CollectibleConfig = require(ReplicatedStorage.Shared.Config.CollectibleConfig)
local RarityConfig = require(ReplicatedStorage.Shared.Config.RarityConfig)

local DataService = require(script.Parent.DataService)

local PET_UPDATE_SECONDS = 0.05
local PET_LERP_ALPHA = 0.22
local PET_SIZE = 1.5

-- Positionen der bis zu 5 Pets relativ zum Charakter.
local PET_OFFSETS = {
	Vector3.new(3.5, 2.5, 1),
	Vector3.new(-3.5, 2.5, 1),
	Vector3.new(0, 3.2, 3.5),
	Vector3.new(5, 2.5, 3),
	Vector3.new(-5, 2.5, 3),
}

local equipmentUpdatedEvent: RemoteEvent? = nil

-- Aktive Pet-Modelle pro Spieler (Index entspricht equipped.pets-Index).
local activePets: { [Player]: { Model } } = {}
local characterConnections: { [Player]: RBXScriptConnection } = {}

local EquipService = {}

-- Gamepass-Bonus-Slots; Phase 4 (MonetizationService) ersetzt diese Funktion.
EquipService.getBonusPetSlots = function(_player: Player): number
	return 0
end

-- Maximale gleichzeitige Pets eines Spielers.
function EquipService.getMaxPetSlots(player: Player): number
	return GameConfig.BASE_PET_SLOTS + EquipService.getBonusPetSlots(player)
end

-- Sammelobjekt per uid im Profil finden.
local function findOwned(profile: Types.PlayerProfile, uid: string): Types.OwnedCollectible?
	for _, owned in profile.collectibles do
		if owned.uid == uid then
			return owned
		end
	end
	return nil
end

-- Produkt der Boni aller ausgerüsteten Pets (1 = kein Pet).
function EquipService.getPetBonus(profile: Types.PlayerProfile): number
	local bonus = 1
	for _, uid in profile.equipped.pets do
		local owned = findOwned(profile, uid)
		if owned ~= nil then
			local def = CollectibleConfig.Collectibles[owned.collectibleId]
			if def ~= nil then
				bonus *= def.bonusMultiplier or 1
			end
		end
	end
	return bonus
end

local function rarityColor(rarity: string): Color3
	local tier = RarityConfig.Tiers[rarity]
	return if tier ~= nil then tier.color else Color3.new(1, 1, 1)
end

--------------------------------------------------------------------------
-- Sichtbare Effekte (Pets, Trail, Skin)
--------------------------------------------------------------------------

-- Baut das Mini-Modell eines Pets (Körper in Rarity-Farbe + Augen).
local function buildPetModel(player: Player, index: number, def: CollectibleConfig.CollectibleDef): Model
	local color = rarityColor(def.rarity)
	local pet = Instance.new("Model")
	pet.Name = `EquipPet_{player.UserId}_{index}`

	local function petPart(name: string, size: Vector3, partColor: Color3, material: Enum.Material, offset: CFrame): BasePart
		local part = Instance.new("Part")
		part.Name = name
		part.Shape = Enum.PartType.Ball
		part.Size = size
		part.Color = partColor
		part.Material = material
		part.CFrame = offset
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Parent = pet
		return part
	end

	local body = petPart("Body", Vector3.new(PET_SIZE, PET_SIZE, PET_SIZE), color, Enum.Material.Neon, CFrame.new())
	for side = -1, 1, 2 do
		local eyeOffset = CFrame.new(side * PET_SIZE * 0.22, PET_SIZE * 0.12, -PET_SIZE * 0.38)
		petPart(`Eye{side}`, Vector3.new(0.4, 0.4, 0.4), Color3.new(1, 1, 1), Enum.Material.SmoothPlastic, eyeOffset)
		petPart(
			`Pupil{side}`,
			Vector3.new(0.18, 0.18, 0.18),
			Color3.fromRGB(25, 25, 30),
			Enum.Material.SmoothPlastic,
			eyeOffset * CFrame.new(0, 0, -0.13)
		)
	end

	-- Namensschild mit Rarity-Farbe.
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(120, 20)
	billboard.StudsOffset = Vector3.new(0, 1.4, 0)
	billboard.MaxDistance = 80
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBold
	label.TextSize = 12
	label.TextColor3 = color
	label.TextStrokeTransparency = 0.5
	label.Text = def.displayName
	label.Parent = billboard
	billboard.Parent = body

	pet.PrimaryPart = body
	return pet
end

-- Trail-Effekt am Charakter anbringen (oder entfernen).
local function applyTrail(player: Player, profile: Types.PlayerProfile)
	local character = player.Character
	if character == nil then
		return
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if root == nil or not root:IsA("BasePart") then
		return
	end

	local existing = root:FindFirstChild("EquipTrail")
	if existing ~= nil then
		existing:Destroy()
	end

	local trailUid = profile.equipped.trail
	if trailUid == nil then
		return
	end
	local owned = findOwned(profile, trailUid)
	if owned == nil then
		return
	end
	local def = CollectibleConfig.Collectibles[owned.collectibleId]
	if def == nil then
		return
	end

	local topAttachment = Instance.new("Attachment")
	topAttachment.Name = "EquipTrailTop"
	topAttachment.Position = Vector3.new(0, 1, 0)
	topAttachment.Parent = root
	local bottomAttachment = Instance.new("Attachment")
	bottomAttachment.Name = "EquipTrailBottom"
	bottomAttachment.Position = Vector3.new(0, -1, 0)
	bottomAttachment.Parent = root

	local color = rarityColor(def.rarity)
	local trail = Instance.new("Trail")
	trail.Name = "EquipTrail"
	trail.Attachment0 = topAttachment
	trail.Attachment1 = bottomAttachment
	trail.Color = ColorSequence.new(color)
	trail.Transparency = NumberSequence.new(0.2, 1)
	trail.Lifetime = 0.6
	trail.LightEmission = 0.8
	trail.WidthScale = NumberSequence.new(1, 0.2)
	trail.Parent = root
end

-- Skin-Glow am Charakter anbringen (oder entfernen).
local function applySkin(player: Player, profile: Types.PlayerProfile)
	local character = player.Character
	if character == nil then
		return
	end

	local existing = character:FindFirstChild("EquipSkin")
	if existing ~= nil then
		existing:Destroy()
	end

	local skinUid = profile.equipped.skin
	if skinUid == nil then
		return
	end
	local owned = findOwned(profile, skinUid)
	if owned == nil then
		return
	end
	local def = CollectibleConfig.Collectibles[owned.collectibleId]
	if def == nil then
		return
	end

	local highlight = Instance.new("Highlight")
	highlight.Name = "EquipSkin"
	highlight.FillColor = rarityColor(def.rarity)
	highlight.FillTransparency = 0.75
	highlight.OutlineColor = rarityColor(def.rarity)
	highlight.OutlineTransparency = 0.4
	highlight.Adornee = character
	highlight.Parent = character
end

-- Pet-Modelle an den Ausrüstungs-Stand angleichen.
local function applyPets(player: Player, profile: Types.PlayerProfile)
	local pets = activePets[player]
	if pets ~= nil then
		for _, model in pets do
			model:Destroy()
		end
	end
	pets = {}
	activePets[player] = pets

	for index, uid in profile.equipped.pets do
		local owned = findOwned(profile, uid)
		if owned == nil then
			continue
		end
		local def = CollectibleConfig.Collectibles[owned.collectibleId]
		if def == nil then
			continue
		end

		local model = buildPetModel(player, index, def)
		local character = player.Character
		local root = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
		if root ~= nil and root:IsA("BasePart") then
			local offset = PET_OFFSETS[index] or PET_OFFSETS[1]
			model:PivotTo((root :: BasePart).CFrame * CFrame.new(offset))
		end
		model.Parent = workspace
		table.insert(pets, model)
	end
end

-- Alle sichtbaren Effekte anwenden.
local function applyAll(player: Player)
	local profile = DataService.getProfile(player)
	if profile == nil then
		return
	end
	applyPets(player, profile)
	applyTrail(player, profile)
	applySkin(player, profile)
end

local function fireEquipmentUpdated(player: Player)
	local profile = DataService.getProfile(player)
	if profile == nil or equipmentUpdatedEvent == nil then
		return
	end
	(equipmentUpdatedEvent :: RemoteEvent):FireClient(player, {
		pets = profile.equipped.pets,
		trail = profile.equipped.trail,
		skin = profile.equipped.skin,
		maxPetSlots = EquipService.getMaxPetSlots(player),
	})
end

--------------------------------------------------------------------------
-- Remote-Handler
--------------------------------------------------------------------------

-- EquipItem(uid, equip) -> (ok, err?)
local function handleEquipItem(player: Player, uidArg: any, equipArg: any): (boolean, any?)
	if typeof(uidArg) ~= "string" or typeof(equipArg) ~= "boolean" then
		return false, "Ungültige Anfrage."
	end

	local profile = DataService.getProfile(player)
	if profile == nil then
		return false, "Dein Profil ist noch nicht geladen."
	end

	local owned = findOwned(profile, uidArg)
	if owned == nil then
		return false, "Dieses Item besitzt du nicht."
	end
	local def = CollectibleConfig.Collectibles[owned.collectibleId]
	if def == nil then
		return false, "Unbekanntes Item."
	end
	local itemType = def.itemType or "pet"

	if itemType == "pet" then
		-- Bereits ausgerüstet?
		local existingIndex: number? = nil
		for index, uid in profile.equipped.pets do
			if uid == uidArg then
				existingIndex = index
				break
			end
		end

		if equipArg then
			if existingIndex ~= nil then
				return false, "Dieses Pet ist bereits ausgerüstet."
			end
			if #profile.equipped.pets >= EquipService.getMaxPetSlots(player) then
				return false, `Alle {EquipService.getMaxPetSlots(player)} Pet-Slots sind belegt.`
			end
			table.insert(profile.equipped.pets, uidArg)
		else
			if existingIndex == nil then
				return false, "Dieses Pet ist nicht ausgerüstet."
			end
			table.remove(profile.equipped.pets, existingIndex)
		end
	elseif itemType == "trail" then
		if equipArg then
			profile.equipped.trail = uidArg
		elseif profile.equipped.trail == uidArg then
			profile.equipped.trail = nil
		else
			return false, "Dieser Trail ist nicht ausgerüstet."
		end
	elseif itemType == "skin" then
		if equipArg then
			profile.equipped.skin = uidArg
		elseif profile.equipped.skin == uidArg then
			profile.equipped.skin = nil
		else
			return false, "Dieser Skin ist nicht ausgerüstet."
		end
	end

	DataService.markDirty(player)
	applyAll(player)
	fireEquipmentUpdated(player)
	return true, nil
end

-- Räumt Ausrüstungs-Referenzen auf, deren Item nicht mehr existiert
-- (z. B. nach einem Handel).
function EquipService.validateEquipment(player: Player)
	local profile = DataService.getProfile(player)
	if profile == nil then
		return
	end

	local changed = false
	for index = #profile.equipped.pets, 1, -1 do
		if findOwned(profile, profile.equipped.pets[index]) == nil then
			table.remove(profile.equipped.pets, index)
			changed = true
		end
	end
	if profile.equipped.trail ~= nil and findOwned(profile, profile.equipped.trail :: string) == nil then
		profile.equipped.trail = nil
		changed = true
	end
	if profile.equipped.skin ~= nil and findOwned(profile, profile.equipped.skin :: string) == nil then
		profile.equipped.skin = nil
		changed = true
	end

	if changed then
		DataService.markDirty(player)
		applyAll(player)
		fireEquipmentUpdated(player)
	end
end

--------------------------------------------------------------------------
-- Init
--------------------------------------------------------------------------

function EquipService.init()
	equipmentUpdatedEvent = Remotes.getEvent("EquipmentUpdated")
	Remotes.getFunction("EquipItem").OnServerInvoke = handleEquipItem

	local function onPlayerAdded(player: Player)
		characterConnections[player] = player.CharacterAdded:Connect(function()
			task.wait(0.5) -- Charakter fertig aufbauen lassen
			applyAll(player)
		end)
		task.spawn(function()
			local profile = DataService.waitForProfile(player)
			if profile ~= nil then
				applyAll(player)
				fireEquipmentUpdated(player)
			end
		end)
	end

	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(function(player)
		local connection = characterConnections[player]
		if connection ~= nil then
			connection:Disconnect()
		end
		characterConnections[player] = nil
		local pets = activePets[player]
		if pets ~= nil then
			for _, model in pets do
				model:Destroy()
			end
		end
		activePets[player] = nil
	end)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end

	-- Folgeschleife: Pets schweben mit Sine-Bobbing neben dem Besitzer.
	task.spawn(function()
		while true do
			task.wait(PET_UPDATE_SECONDS)
			for player, pets in activePets do
				local character = player.Character
				if character == nil then
					continue
				end
				local root = character:FindFirstChild("HumanoidRootPart")
				if root == nil or not root:IsA("BasePart") then
					continue
				end
				for index, model in pets do
					if model.Parent == nil then
						continue
					end
					local offset = PET_OFFSETS[index] or PET_OFFSETS[1]
					local bob = math.sin(os.clock() * 2.6 + index * 1.7) * 0.4
					local target = (root :: BasePart).CFrame * CFrame.new(offset + Vector3.new(0, bob, 0))
					model:PivotTo(model:GetPivot():Lerp(target, PET_LERP_ALPHA))
				end
			end
		end
	end)
end

return EquipService
