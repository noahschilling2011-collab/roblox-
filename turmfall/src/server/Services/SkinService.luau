--!strict
-- SkinService: Besitz, Ausrüsten und Anwenden der (rein kosmetischen) Skins.
--
-- Der Server ist die einzige Wahrheit über Besitz und Ausrüstung; der
-- Client bekommt beides über SkinsChanged gespiegelt. Beim Platzieren
-- dekoriert dieser Service die Teile über den decoratePiece-Hook des
-- TowerService (nur Optik: Material, Farbe, Partikel - NIEMALS Physik,
-- siehe Kosmetik-Guard in SkinCatalog.validate()).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Network = require(Shared.Network)
local PartCatalog = require(Shared.Config.PartCatalog)
local SkinCatalog = require(Shared.Config.SkinCatalog)

local DataService = require(script.Parent.DataService)
local TowerService = require(script.Parent.TowerService)

local SkinService = {}

local skinsChangedEvent: RemoteEvent? = nil

local function fireSkinsChanged(player: Player)
	local profile = DataService.getProfile(player)
	if profile == nil or skinsChangedEvent == nil then
		return
	end
	(skinsChangedEvent :: RemoteEvent):FireClient(
		player,
		table.clone(profile.ownedSkins),
		table.clone(profile.equipped),
		profile.truemmer
	)
end

function SkinService.ownsSkin(player: Player, skinId: string): boolean
	local profile = DataService.getProfile(player)
	return profile ~= nil and table.find(profile.ownedSkins, skinId) ~= nil
end

-- Schaltet einen Skin dauerhaft frei (Kauf/Belohnung). Idempotent.
function SkinService.grantSkin(player: Player, skinId: string): boolean
	local profile = DataService.getProfile(player)
	if profile == nil or SkinCatalog.Skins[skinId] == nil then
		return false
	end
	if table.find(profile.ownedSkins, skinId) == nil then
		table.insert(profile.ownedSkins, skinId)
		DataService.markDirty(player)
		fireSkinsChanged(player)
	end
	return true
end

--------------------------------------------------------------------------
-- Ausrüsten
--------------------------------------------------------------------------

local function isValidSlot(slot: string): boolean
	return slot == "kollaps" or PartCatalog.Parts[slot] ~= nil
end

-- Handler für EquipSkin(slot, skinId?). slot "alle" rüstet einen
-- Universal-Skin in alle vier Teil-Slots gleichzeitig.
local function handleEquipSkin(player: Player, slotArg: unknown, skinIdArg: unknown): (boolean, any?)
	if typeof(slotArg) ~= "string" then
		return false, "Ungültiger Slot."
	end
	local slot = slotArg :: string
	if slot ~= "alle" and not isValidSlot(slot) then
		return false, "Unbekannter Slot."
	end

	local profile = DataService.getProfile(player)
	if profile == nil then
		return false, "Dein Profil ist noch nicht geladen."
	end

	-- Abrüsten (skinId = nil).
	if skinIdArg == nil then
		if slot == "alle" then
			for _, partTypeId in PartCatalog.getSortedIds() do
				profile.equipped[partTypeId] = nil
			end
		else
			profile.equipped[slot] = nil
		end
		DataService.markDirty(player)
		fireSkinsChanged(player)
		return true, nil
	end

	if typeof(skinIdArg) ~= "string" then
		return false, "Ungültiger Skin."
	end
	local skin = SkinCatalog.Skins[skinIdArg]
	if skin == nil then
		return false, "Diesen Skin gibt es nicht."
	end
	if not SkinService.ownsSkin(player, skin.id) then
		return false, "Diesen Skin besitzt du noch nicht."
	end

	if skin.category == "kollaps" then
		if slot ~= "kollaps" then
			return false, "Kollaps-Effekte gehören in den Kollaps-Slot."
		end
		profile.equipped.kollaps = skin.id
	else
		-- Teil-Skin: muss zum Slot passen ("alle" passt überall).
		if slot == "alle" then
			if skin.partType ~= "alle" then
				return false, `{skin.name} passt nur auf einen Teiltyp.`
			end
			for _, partTypeId in PartCatalog.getSortedIds() do
				profile.equipped[partTypeId] = skin.id
			end
		else
			if skin.partType ~= "alle" and skin.partType ~= slot then
				return false, `{skin.name} passt nicht auf diesen Teiltyp.`
			end
			profile.equipped[slot] = skin.id
		end
	end

	DataService.markDirty(player)
	fireSkinsChanged(player)
	return true, nil
end

--------------------------------------------------------------------------
-- Anwenden auf platzierte Teile (nur Optik!)
--------------------------------------------------------------------------

local function applySkinToModel(model: Model, skin: SkinCatalog.SkinDef)
	local visual = skin.visualData
	local material: Enum.Material? = nil
	if visual.material ~= nil then
		local ok, resolved = pcall(function()
			return (Enum.Material :: any)[visual.material :: string] :: Enum.Material
		end)
		if ok then
			material = resolved
		end
	end

	for _, descendant in model:GetDescendants() do
		if not descendant:IsA("BasePart") then
			continue
		end
		if material ~= nil then
			descendant.Material = material
		end
		if visual.color ~= nil then
			local color = visual.color :: { r: number, g: number, b: number }
			descendant.Color = Color3.fromRGB(color.r, color.g, color.b)
		end
	end

	if visual.sparkle == true then
		local primaryPart = model.PrimaryPart
		if primaryPart ~= nil then
			local sparkle = Instance.new("ParticleEmitter")
			sparkle.Name = "SkinGlanz"
			sparkle.Color = ColorSequence.new(Color3.new(1, 1, 1))
			sparkle.LightEmission = 1
			sparkle.Rate = 3
			sparkle.Lifetime = NumberRange.new(0.6, 1.2)
			sparkle.Speed = NumberRange.new(0.5, 1.5)
			sparkle.SpreadAngle = Vector2.new(180, 180)
			sparkle.Size = NumberSequence.new(0.25)
			sparkle.Parent = primaryPart
		end
	end
end

-- Hook-Implementierung für TowerService.decoratePiece.
local function decoratePiece(player: Player, model: Model, partTypeId: string)
	local profile = DataService.getProfile(player)
	if profile == nil then
		return
	end
	local skinId = profile.equipped[partTypeId]
	local skin = if skinId ~= nil then SkinCatalog.Skins[skinId] else nil
	if skin ~= nil and skin.category == "teil" then
		applySkinToModel(model, skin)
	end
end

function SkinService.init()
	-- Katalog-Integrität + Kosmetik-Guard hart beim Start erzwingen.
	SkinCatalog.validate()

	skinsChangedEvent = Network.getEvent("SkinsChanged")
	Network.getFunction("EquipSkin").OnServerInvoke = handleEquipSkin

	-- Optik-Hook beim TowerService einhängen (wir requiren ihn, nicht umgekehrt).
	TowerService.decoratePiece = decoratePiece

	local function onPlayerAdded(player: Player)
		task.spawn(function()
			local profile = DataService.waitForProfile(player)
			if profile ~= nil then
				fireSkinsChanged(player)
			end
		end)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
end

-- Für andere Services (Monetarisierung/Wertung): UI-Refresh anstoßen.
SkinService.refresh = fireSkinsChanged

return SkinService
