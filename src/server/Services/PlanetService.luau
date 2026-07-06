--!strict
-- PlanetService: verwaltet die begehbare Insel jedes Spielers.
--
-- Jeder Spieler besitzt eine schwebende Insel mit festem Spawn. Biome sind
-- sichtbare ZONEN auf der Insel (12 Zonen im Ring um den Insel-Kern):
-- gesperrte Zonen liegen unter Nebel und Felsen, ein Biom-Kauf (PlaceBiome)
-- legt die Zone frei. Der Server ist autoritativ: alle Client-Eingaben
-- (PlaceBiome/UpgradeBiome/RenamePlanet) werden hier vollständig validiert.
--
-- Die Sammel-Objekte in den Zonen verwaltet der HarvestService; er nutzt
-- getZonePart/getSellPadPosition dieses Services.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")
local Workspace = game:GetService("Workspace")

local Types = require(ReplicatedStorage.Shared.Types)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local BiomeConfig = require(ReplicatedStorage.Shared.Config.BiomeConfig)
local MonetizationConfig = require(ReplicatedStorage.Shared.Config.MonetizationConfig)

local DataService = require(script.Parent.DataService)
local EnergyService = require(script.Parent.EnergyService)
local BiomeVisuals = require(script.Parent.BiomeVisuals)

local PLOTS_FOLDER_NAME = "PlanetPlots"
local POSITIONS_PER_RING = 12 -- Inseln pro Ring; danach beginnt ein weiterer Ring

-- Insel-Geometrie (Studs).
local BASE_RADIUS = 68 -- Radius der begehbaren Inselscheibe
local BASE_THICKNESS = 4
local ZONE_RING_RADIUS = 48 -- Abstand der Zonen-Mitten vom Inselzentrum
local ZONE_WIDTH = 22 -- tangentiale Breite einer Biom-Zone
local ZONE_DEPTH = 16 -- radiale Tiefe einer Biom-Zone
local CORE_HEIGHT_OFFSET = 7 -- Schwebehöhe des Insel-Kristalls über dem Boden
local SPAWN_OFFSET = Vector3.new(0, 5, -8) -- Spawnpunkt relativ zur Inselmitte
local SELL_PAD_OFFSET = Vector3.new(0, 0, 16) -- Verkaufs-Pad südlich der Mitte

local BASE_COLOR = Color3.fromRGB(126, 158, 96)
local LOCKED_FLOOR_COLOR = Color3.fromRGB(110, 110, 116)
local FOG_COLOR = Color3.fromRGB(190, 195, 205)
local SELL_PAD_COLOR = Color3.fromRGB(226, 176, 44)
local CORE_COLOR = Color3.fromRGB(150, 210, 235)

-- Snapshot-Form für das Remote-Event PlanetUpdated.
export type PlanetSnapshot = {
	biomes: { Types.PlacedBiome },
	collectibles: { Types.OwnedCollectible },
	visits: number,
	likes: number,
}

local plotIndices: { [Player]: number } = {}
local plotOrigins: { [Player]: CFrame } = {}
local usedIndices: { [number]: boolean } = {}
local characterConnections: { [Player]: RBXScriptConnection } = {}

local planetUpdatedEvent: RemoteEvent? = nil

local PlanetService = {}

-- Tiefe Kopie eines (JSON-artigen) Wertes.
local function deepCopy(value: any): any
	if typeof(value) == "table" then
		local copy = {}
		for key, child in value do
			copy[key] = deepCopy(child)
		end
		return copy
	end
	return value
end

local function buildSnapshot(profile: Types.PlayerProfile): PlanetSnapshot
	return {
		biomes = deepCopy(profile.biomes),
		collectibles = deepCopy(profile.collectibles),
		visits = profile.visits,
		likes = profile.likes,
	}
end

local function getPlotsRoot(): Folder
	local existing = Workspace:FindFirstChild(PLOTS_FOLDER_NAME)
	if existing ~= nil and existing:IsA("Folder") then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = PLOTS_FOLDER_NAME
	folder.Parent = Workspace
	return folder
end

local function getPlotFolder(player: Player): Folder?
	local root = Workspace:FindFirstChild(PLOTS_FOLDER_NAME)
	if root == nil then
		return nil
	end
	local folder = root:FindFirstChild(`Plot_{player.UserId}`)
	if folder ~= nil and folder:IsA("Folder") then
		return folder
	end
	return nil
end

-- Kleinsten freien Insel-Index vergeben.
local function assignPlotIndex(player: Player): number
	local index = 1
	while usedIndices[index] do
		index += 1
	end
	usedIndices[index] = true
	plotIndices[player] = index
	return index
end

-- Insel-Ursprung: Kreis um den Weltursprung; bei mehr als POSITIONS_PER_RING
-- Spielern folgt ein zweiter (dritter, ...) Ring mit größerem Radius.
local function computePlotOrigin(index: number): CFrame
	local ring = math.floor((index - 1) / POSITIONS_PER_RING)
	local slotInRing = (index - 1) % POSITIONS_PER_RING
	local radius = GameConfig.PLOT_SPACING_STUDS * (ring + 1)
	local angle = (slotInRing / POSITIONS_PER_RING) * 2 * math.pi
	return CFrame.new(math.cos(angle) * radius, GameConfig.PLOT_HEIGHT_STUDS, math.sin(angle) * radius)
end

-- Oberkante der Inselscheibe (Welt-Y) für eine Insel.
local function baseTopY(origin: CFrame): number
	return origin.Position.Y + BASE_THICKNESS / 2
end

-- Mittelpunkt einer Zone (Welt-Position, auf Bodenhöhe).
local function zoneCenter(origin: CFrame, slot: number): (Vector3, number)
	local angle = ((slot - 1) / GameConfig.PLANET_SLOTS) * 2 * math.pi
	local position = origin.Position
		+ Vector3.new(math.cos(angle) * ZONE_RING_RADIUS, BASE_THICKNESS / 2, math.sin(angle) * ZONE_RING_RADIUS)
	return position, angle
end

local function createZoneLabel(parent: BasePart, text: string)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "ZoneLabel"
	billboard.Size = UDim2.fromOffset(160, 36)
	billboard.StudsOffset = Vector3.new(0, 7, 0)
	billboard.AlwaysOnTop = false
	billboard.MaxDistance = 220

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.5
	label.Text = text
	label.Parent = billboard

	billboard.Parent = parent
end

local function setZoneLabel(part: BasePart, text: string)
	local billboard = part:FindFirstChild("ZoneLabel")
	if billboard ~= nil then
		local label = billboard:FindFirstChild("Label")
		if label ~= nil and label:IsA("TextLabel") then
			label.Text = text
		end
	end
end

--------------------------------------------------------------------------
-- Namensschild und Umbenennen
--------------------------------------------------------------------------

-- Aktualisiert das Namensschild über dem Insel-Kristall.
local function updateNameTag(player: Player)
	local plotFolder = getPlotFolder(player)
	if plotFolder == nil then
		return
	end
	local core = plotFolder:FindFirstChild("Core")
	if core == nil or not core:IsA("BasePart") then
		return
	end

	local profile = DataService.getProfile(player)
	local customName = if profile ~= nil then profile.planetName else ""
	local displayText = if customName ~= "" then customName else `{player.DisplayName}s Insel`

	local billboard = core:FindFirstChild("NameTag")
	local nameLabel: TextLabel
	local ownerLabel: TextLabel
	if billboard ~= nil and billboard:IsA("BillboardGui") then
		nameLabel = billboard:FindFirstChild("PlanetName") :: TextLabel
		ownerLabel = billboard:FindFirstChild("OwnerName") :: TextLabel
	else
		local gui = Instance.new("BillboardGui")
		gui.Name = "NameTag"
		gui.Size = UDim2.new(0, 260, 0, 56)
		gui.StudsOffset = Vector3.new(0, 6, 0)
		gui.AlwaysOnTop = false
		gui.MaxDistance = 400

		nameLabel = Instance.new("TextLabel")
		nameLabel.Name = "PlanetName"
		nameLabel.BackgroundTransparency = 1
		nameLabel.Size = UDim2.new(1, 0, 0, 32)
		nameLabel.Font = Enum.Font.GothamBold
		nameLabel.TextSize = 24
		nameLabel.TextColor3 = Color3.fromRGB(235, 238, 245)
		nameLabel.TextStrokeTransparency = 0.4
		nameLabel.Parent = gui

		ownerLabel = Instance.new("TextLabel")
		ownerLabel.Name = "OwnerName"
		ownerLabel.BackgroundTransparency = 1
		ownerLabel.Position = UDim2.new(0, 0, 0, 32)
		ownerLabel.Size = UDim2.new(1, 0, 0, 20)
		ownerLabel.Font = Enum.Font.GothamMedium
		ownerLabel.TextSize = 14
		ownerLabel.TextColor3 = Color3.fromRGB(158, 164, 186)
		ownerLabel.TextStrokeTransparency = 0.6
		ownerLabel.Parent = gui

		gui.Parent = core
	end

	nameLabel.Text = displayText
	ownerLabel.Text = `von {player.DisplayName}`
end

-- Handler für RenamePlanet(name): validiert, filtert (Roblox-Pflicht) und speichert.
local function handleRenamePlanet(player: Player, nameArg: unknown): (boolean, any?)
	if typeof(nameArg) ~= "string" then
		return false, "Ungültiger Name."
	end

	local trimmed = string.gsub(nameArg :: string, "^%s*(.-)%s*$", "%1")
	if #trimmed < 3 then
		return false, "Der Name braucht mindestens 3 Zeichen."
	end
	if #trimmed > GameConfig.PLANET_NAME_MAX_LENGTH then
		return false, `Maximal {GameConfig.PLANET_NAME_MAX_LENGTH} Zeichen.`
	end

	local profile = DataService.getProfile(player)
	if profile == nil then
		return false, "Dein Profil ist noch nicht geladen."
	end

	local okFilter, filtered = pcall(function()
		local result = TextService:FilterStringAsync(trimmed, player.UserId)
		return result:GetNonChatStringForBroadcastAsync()
	end)
	if not okFilter or typeof(filtered) ~= "string" then
		warn(`[PlanetForge] Namensfilter fehlgeschlagen: {filtered}`)
		return false, "Der Name konnte gerade nicht geprüft werden - versuche es gleich noch einmal."
	end

	profile.planetName = filtered
	DataService.markDirty(player)
	updateNameTag(player)
	return true, filtered
end

--------------------------------------------------------------------------
-- Kauf-Kosmetik (Skins/Auren/Wetter aus dem Shop)
--------------------------------------------------------------------------

local function ensureEmitter(parent: Instance, name: string): ParticleEmitter
	local existing = parent:FindFirstChild(name)
	if existing ~= nil and existing:IsA("ParticleEmitter") then
		return existing
	end
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = name
	emitter.Parent = parent
	return emitter
end

-- Wendet die ausgerüstete Kauf-Kosmetik (Skin/Aura/Wetter) auf die Insel an.
-- Idempotent; Haustiere verwaltet der MonetizationService selbst.
function PlanetService.applyCosmetics(player: Player)
	local profile = DataService.getProfile(player)
	local plotFolder = getPlotFolder(player)
	if profile == nil or plotFolder == nil then
		return
	end
	local coreInstance = plotFolder:FindFirstChild("Core")
	if coreInstance == nil or not coreInstance:IsA("BasePart") then
		return
	end
	local core = coreInstance :: BasePart
	local equipped = profile.equippedCosmetics

	-- Skin: Farbe und Material des Insel-Kristalls.
	local skinId = equipped.skin
	local skinDef = if skinId ~= nil then MonetizationConfig.Cosmetics[skinId] else nil
	if skinDef ~= nil and skinDef.category == "skin" then
		core.Color = skinDef.visual.color or CORE_COLOR
		core.Material = skinDef.visual.material or Enum.Material.Glass
	else
		skinDef = nil
		core.Color = CORE_COLOR
		core.Material = Enum.Material.Glass
	end

	local light = core:FindFirstChild("CosmeticLight")
	if skinDef ~= nil and skinDef.visual.glow == true then
		local pointLight: PointLight
		if light ~= nil and light:IsA("PointLight") then
			pointLight = light
		else
			pointLight = Instance.new("PointLight")
			pointLight.Name = "CosmeticLight"
			pointLight.Range = 40
			pointLight.Brightness = 1.5
			pointLight.Parent = core
		end
		pointLight.Color = skinDef.visual.color or Color3.new(1, 1, 1)
	elseif light ~= nil then
		light:Destroy()
	end

	-- Aura: Partikel am Kristall.
	local auraId = equipped.aura
	local auraDef = if auraId ~= nil then MonetizationConfig.Cosmetics[auraId] else nil
	if auraDef ~= nil and auraDef.category == "aura" then
		local emitter = ensureEmitter(core, "AuraEmitter")
		local mainColor = auraDef.visual.color or Color3.new(1, 1, 1)
		emitter.Color = ColorSequence.new(mainColor, auraDef.visual.secondaryColor or mainColor)
		emitter.LightEmission = 0.8
		emitter.Rate = 14
		emitter.Lifetime = NumberRange.new(1.5, 2.5)
		emitter.Speed = NumberRange.new(3, 6)
		emitter.Size = NumberSequence.new(0.6)
		emitter.SpreadAngle = Vector2.new(180, 180)
	else
		local emitter = core:FindFirstChild("AuraEmitter")
		if emitter ~= nil then
			emitter:Destroy()
		end
	end

	-- Wetter: Partikel regnen aus einer unsichtbaren Fläche über der Insel.
	local wetterId = equipped.wetter
	local wetterDef = if wetterId ~= nil then MonetizationConfig.Cosmetics[wetterId] else nil
	local weatherInstance = plotFolder:FindFirstChild("WeatherPart")
	if wetterDef ~= nil and wetterDef.category == "wetter" then
		local weatherPart: BasePart
		if weatherInstance ~= nil and weatherInstance:IsA("BasePart") then
			weatherPart = weatherInstance
		else
			weatherPart = Instance.new("Part")
			weatherPart.Name = "WeatherPart"
			weatherPart.Size = Vector3.new(BASE_RADIUS * 1.6, 1, BASE_RADIUS * 1.6)
			weatherPart.Transparency = 1
			weatherPart.Anchored = true
			weatherPart.CanCollide = false
			weatherPart.CanQuery = false
			local origin = plotOrigins[player]
			weatherPart.CFrame = (if origin ~= nil then origin else core.CFrame) * CFrame.new(0, 40, 0)
			weatherPart.Parent = plotFolder
		end
		local emitter = ensureEmitter(weatherPart, "WeatherEmitter")
		local mainColor = wetterDef.visual.color or Color3.new(1, 1, 1)
		emitter.Color = ColorSequence.new(mainColor, wetterDef.visual.secondaryColor or mainColor)
		emitter.LightEmission = 0.6
		emitter.Rate = 20
		emitter.Lifetime = NumberRange.new(2, 3)
		emitter.Speed = NumberRange.new(8, 14)
		emitter.Size = NumberSequence.new(0.8)
		emitter.EmissionDirection = Enum.NormalId.Bottom
	elseif weatherInstance ~= nil then
		weatherInstance:Destroy()
	end
end

--------------------------------------------------------------------------
-- Insel-Aufbau und Zonen-Visuals
--------------------------------------------------------------------------

local function newIslandPart(parent: Instance, name: string): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.Parent = parent
	return part
end

-- Gesperrten Look einer Zone aufbauen (Nebel + Felsen).
local function buildLockedZone(zonePart: BasePart)
	if zonePart:FindFirstChild("Fog") ~= nil then
		return
	end

	local fog = Instance.new("Part")
	fog.Name = "Fog"
	fog.Size = Vector3.new(ZONE_WIDTH - 1, 7, ZONE_DEPTH - 1)
	fog.Color = FOG_COLOR
	fog.Material = Enum.Material.SmoothPlastic
	fog.Transparency = 0.45
	fog.Anchored = true
	fog.CanCollide = false
	fog.CanQuery = false
	fog.CFrame = zonePart.CFrame * CFrame.new(0, 4, 0)
	fog.Parent = zonePart

	-- Felsen unter dem Nebel.
	local rng = Random.new(math.floor(zonePart.Position.X + zonePart.Position.Z))
	for i = 1, 3 do
		local size = 2 + rng:NextNumber() * 2.5
		local rock = Instance.new("Part")
		rock.Name = `Rock_{i}`
		rock.Shape = Enum.PartType.Ball
		rock.Size = Vector3.new(size, size * 0.75, size)
		rock.Color = Color3.fromRGB(96, 96, 102)
		rock.Material = Enum.Material.Slate
		rock.Anchored = true
		rock.CanCollide = false
		rock.CanQuery = false
		rock.CFrame = zonePart.CFrame
			* CFrame.new(rng:NextNumber(-ZONE_WIDTH / 3, ZONE_WIDTH / 3), size * 0.3, rng:NextNumber(-ZONE_DEPTH / 3, ZONE_DEPTH / 3))
		rock.Parent = zonePart
	end
end

local function clearLockedZone(zonePart: BasePart)
	for _, child in zonePart:GetChildren() do
		if child.Name == "Fog" or string.sub(child.Name, 1, 5) == "Rock_" then
			child:Destroy()
		end
	end
end

-- Zonen-Visual an den Profilstand angleichen (placed = nil -> gesperrte Zone).
local function updateZoneVisual(player: Player, slotNumber: number, placed: Types.PlacedBiome?, withPop: boolean?)
	local plotFolder = getPlotFolder(player)
	if plotFolder == nil then
		return
	end
	local zonePart = plotFolder:FindFirstChild(`Zone_{slotNumber}`)
	if zonePart == nil or not zonePart:IsA("BasePart") then
		return
	end

	if placed == nil then
		zonePart.Color = LOCKED_FLOOR_COLOR
		zonePart.Material = Enum.Material.Slate
		setZoneLabel(zonePart, `❓ Freie Zone {slotNumber}`)
		BiomeVisuals.clear(zonePart)
		buildLockedZone(zonePart)
		return
	end

	local def = BiomeConfig.Biomes[placed.biomeId]
	if def == nil then
		warn(`[PlanetForge] Unbekanntes Biom im Profil von {player.Name}: {placed.biomeId}`)
		return
	end

	clearLockedZone(zonePart)
	zonePart.Color = def.color
	zonePart.Material = Enum.Material.Grass
	setZoneLabel(zonePart, `{def.displayName} (Lv. {placed.level})`)
	-- Prozedurales Deko-Set (mehr Objekte pro Level); Pop-Tween nur bei Aktionen.
	BiomeVisuals.build(zonePart, placed.biomeId, placed.level, withPop == true)
end

-- Baut die komplette Insel eines Spielers auf.
local function buildIsland(player: Player, origin: CFrame)
	local folder = Instance.new("Folder")
	folder.Name = `Plot_{player.UserId}`

	-- Begehbare Inselscheibe.
	local base = newIslandPart(folder, "Base")
	base.Shape = Enum.PartType.Cylinder
	base.Size = Vector3.new(BASE_THICKNESS, BASE_RADIUS * 2, BASE_RADIUS * 2)
	base.Color = BASE_COLOR
	base.Material = Enum.Material.Grass
	base.CFrame = origin * CFrame.Angles(0, 0, math.rad(90))

	-- Insel-Kristall in der Mitte (Ziel für Skins/Auren, trägt das Namensschild).
	local core = newIslandPart(folder, "Core")
	core.Size = Vector3.new(3, 7, 3)
	core.Color = CORE_COLOR
	core.Material = Enum.Material.Glass
	core.CanCollide = false
	core.CFrame = origin * CFrame.new(0, BASE_THICKNESS / 2 + CORE_HEIGHT_OFFSET, 0) * CFrame.Angles(0, math.rad(45), 0)

	-- Verkaufs-Pad: betretbarer Bereich, der den Rucksack zu Energie macht.
	local sellPad = newIslandPart(folder, "SellPad")
	sellPad.Shape = Enum.PartType.Cylinder
	sellPad.Size = Vector3.new(0.5, 11, 11)
	sellPad.Color = SELL_PAD_COLOR
	sellPad.Material = Enum.Material.Metal
	sellPad.CFrame = origin * CFrame.new(SELL_PAD_OFFSET + Vector3.new(0, BASE_THICKNESS / 2 + 0.25, 0)) * CFrame.Angles(0, 0, math.rad(90))
	createZoneLabel(sellPad, "💰 Verkaufen")

	-- Die 12 Biom-Zonen im Ring.
	for slotNumber = 1, GameConfig.PLANET_SLOTS do
		local center, angle = zoneCenter(origin, slotNumber)
		local zone = newIslandPart(folder, `Zone_{slotNumber}`)
		zone.Size = Vector3.new(ZONE_WIDTH, 0.4, ZONE_DEPTH)
		zone.Color = LOCKED_FLOOR_COLOR
		zone.Material = Enum.Material.Slate
		zone.CFrame = CFrame.new(center + Vector3.new(0, 0.2, 0)) * CFrame.Angles(0, -angle + math.rad(90), 0)
		createZoneLabel(zone, `❓ Freie Zone {slotNumber}`)
		buildLockedZone(zone)
	end

	folder.Parent = getPlotsRoot()
end

local function teleportToPlot(player: Player, character: Model)
	local origin = plotOrigins[player]
	if origin == nil then
		return
	end
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if root ~= nil and root:IsA("BasePart") then
		character:PivotTo(origin * CFrame.new(SPAWN_OFFSET))
	end
end

--------------------------------------------------------------------------
-- Biome kaufen und upgraden
--------------------------------------------------------------------------

local function findBiomeAtSlot(profile: Types.PlayerProfile, slot: number): Types.PlacedBiome?
	for _, placed in profile.biomes do
		if placed.slot == slot then
			return placed
		end
	end
	return nil
end

local function parseSlot(slotArg: unknown): number?
	if typeof(slotArg) ~= "number" then
		return nil
	end
	local slot = slotArg :: number
	if slot ~= math.floor(slot) or slot < 1 or slot > GameConfig.PLANET_SLOTS then
		return nil
	end
	return slot
end

-- Juice beim Freilegen/Upgraden: Sound + Partikel-Burst an der Zone.
local function playZoneJuice(player: Player, slotNumber: number, color: Color3, level: number)
	local plotFolder = getPlotFolder(player)
	if plotFolder == nil then
		return
	end
	local zonePart = plotFolder:FindFirstChild(`Zone_{slotNumber}`)
	if zonePart == nil or not zonePart:IsA("BasePart") then
		return
	end

	local sound = Instance.new("Sound")
	sound.SoundId = "rbxasset://sounds/snap.mp3"
	sound.Volume = 0.8
	sound.PlaybackSpeed = 0.95 + level * 0.06
	sound.RollOffMaxDistance = 150
	sound.Parent = zonePart
	sound:Play()
	task.delay(3, function()
		sound:Destroy()
	end)

	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "BuildBurst"
	emitter.Color = ColorSequence.new(color)
	emitter.LightEmission = 0.6
	emitter.Rate = 0
	emitter.Lifetime = NumberRange.new(0.4, 0.8)
	emitter.Speed = NumberRange.new(6, 12)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Size = NumberSequence.new(0.6)
	emitter.Parent = zonePart
	emitter:Emit(24)
	task.delay(1.5, function()
		emitter:Destroy()
	end)
end

-- Remote-Handler: PlaceBiome(biomeId, slot) -> (ok, snapshot | Fehlermeldung)
local function handlePlaceBiome(player: Player, biomeIdArg: unknown, slotArg: unknown): (boolean, any?)
	local profile = DataService.getProfile(player)
	if profile == nil then
		return false, "Deine Daten sind noch nicht geladen. Versuche es gleich erneut."
	end

	if typeof(biomeIdArg) ~= "string" then
		return false, "Ungültiges Biom."
	end
	local slot = parseSlot(slotArg)
	if slot == nil then
		return false, "Ungültige Zone."
	end

	local def = BiomeConfig.Biomes[biomeIdArg]
	if def == nil then
		return false, "Dieses Biom existiert nicht."
	end
	if profile.lifetimeEnergy < def.unlockAtLifetimeEnergy then
		return false, `{def.displayName} ist noch nicht freigeschaltet (benötigt {def.unlockAtLifetimeEnergy} Gesamt-Energie).`
	end
	if findBiomeAtSlot(profile, slot) ~= nil then
		return false, "Diese Zone ist bereits belegt."
	end

	if not EnergyService.trySpend(player, def.baseCost) then
		return false, `Nicht genug Energie ({def.baseCost} benötigt).`
	end

	local placed: Types.PlacedBiome = {
		biomeId = def.id,
		slot = slot,
		level = 1,
		placedAt = os.time(),
	}
	table.insert(profile.biomes, placed)

	updateZoneVisual(player, slot, placed, true)
	playZoneJuice(player, slot, def.color, placed.level)
	DataService.markDirty(player)
	PlanetService.sendSnapshot(player)
	return true, buildSnapshot(profile)
end

-- Remote-Handler: UpgradeBiome(slot) -> (ok, snapshot | Fehlermeldung)
local function handleUpgradeBiome(player: Player, slotArg: unknown): (boolean, any?)
	local profile = DataService.getProfile(player)
	if profile == nil then
		return false, "Deine Daten sind noch nicht geladen. Versuche es gleich erneut."
	end

	local slot = parseSlot(slotArg)
	if slot == nil then
		return false, "Ungültige Zone."
	end

	local placed = findBiomeAtSlot(profile, slot)
	if placed == nil then
		return false, "In dieser Zone steht kein Biom."
	end

	local def = BiomeConfig.Biomes[placed.biomeId]
	if def == nil then
		return false, "Dieses Biom existiert nicht mehr."
	end
	if placed.level >= def.maxLevel then
		return false, `{def.displayName} ist bereits auf Maximalstufe.`
	end

	local cost = BiomeConfig.getUpgradeCost(placed.biomeId, placed.level)
	if not EnergyService.trySpend(player, cost) then
		return false, `Nicht genug Energie ({cost} benötigt).`
	end

	placed.level += 1

	updateZoneVisual(player, slot, placed, true)
	playZoneJuice(player, slot, def.color, placed.level)
	DataService.markDirty(player)
	PlanetService.sendSnapshot(player)
	return true, buildSnapshot(profile)
end

--------------------------------------------------------------------------
-- Spieler-Lebenszyklus
--------------------------------------------------------------------------

local function onPlayerAdded(player: Player)
	local index = assignPlotIndex(player)
	local origin = computePlotOrigin(index)
	plotOrigins[player] = origin

	-- Basis-Insel sofort aufbauen, damit die Welt nicht leer wirkt.
	buildIsland(player, origin)
	updateNameTag(player)

	characterConnections[player] = player.CharacterAdded:Connect(function(character)
		task.spawn(teleportToPlot, player, character)
	end)
	local currentCharacter = player.Character
	if currentCharacter ~= nil then
		task.spawn(teleportToPlot, player, currentCharacter)
	end

	-- Auf das geladene Profil warten und die Zonen darstellen.
	local profile = DataService.waitForProfile(player)
	if profile == nil then
		return -- Spieler hat den Server bereits verlassen
	end

	for _, placed in profile.biomes do
		updateZoneVisual(player, placed.slot, placed)
	end
	updateNameTag(player)
	PlanetService.applyCosmetics(player)
	PlanetService.applyRebirthDeco(player, profile.rebirths)
	PlanetService.sendSnapshot(player)
end

local function onPlayerRemoving(player: Player)
	local connection = characterConnections[player]
	if connection ~= nil then
		connection:Disconnect()
	end
	characterConnections[player] = nil

	local index = plotIndices[player]
	if index ~= nil then
		usedIndices[index] = nil
	end
	plotIndices[player] = nil
	plotOrigins[player] = nil

	local plotFolder = getPlotFolder(player)
	if plotFolder ~= nil then
		plotFolder:Destroy()
	end
end

--------------------------------------------------------------------------
-- Welt-Stimmung
--------------------------------------------------------------------------

-- Freundliche Himmel-Insel-Stimmung: Tag, weiche Atmosphäre, dezentes Bloom.
local function setupWorldAmbience()
	local Lighting = game:GetService("Lighting")

	Lighting.ClockTime = 13
	Lighting.Brightness = 2.4
	Lighting.Ambient = Color3.fromRGB(120, 130, 150)
	Lighting.OutdoorAmbient = Color3.fromRGB(140, 150, 170)

	if Lighting:FindFirstChild("PlanetForgeSky") == nil then
		local sky = Instance.new("Sky")
		sky.Name = "PlanetForgeSky"
		sky.StarCount = 1000
		sky.SunAngularSize = 14
		sky.Parent = Lighting
	end

	if Lighting:FindFirstChild("PlanetForgeAtmosphere") == nil then
		local atmosphere = Instance.new("Atmosphere")
		atmosphere.Name = "PlanetForgeAtmosphere"
		atmosphere.Density = 0.3
		atmosphere.Color = Color3.fromRGB(200, 215, 235)
		atmosphere.Decay = Color3.fromRGB(110, 130, 160)
		atmosphere.Glare = 0.25
		atmosphere.Haze = 1.6
		atmosphere.Parent = Lighting
	end

	if Lighting:FindFirstChild("PlanetForgeBloom") == nil then
		local bloom = Instance.new("BloomEffect")
		bloom.Name = "PlanetForgeBloom"
		bloom.Intensity = 0.35
		bloom.Size = 24
		bloom.Threshold = 1.2
		bloom.Parent = Lighting
	end

	if Lighting:FindFirstChild("PlanetForgeColor") == nil then
		local color = Instance.new("ColorCorrectionEffect")
		color.Name = "PlanetForgeColor"
		color.Contrast = 0.04
		color.Saturation = 0.1
		color.TintColor = Color3.fromRGB(255, 250, 240)
		color.Parent = Lighting
	end
end

--------------------------------------------------------------------------
-- Init und öffentliche API
--------------------------------------------------------------------------

function PlanetService.init()
	setupWorldAmbience()

	planetUpdatedEvent = Remotes.getEvent("PlanetUpdated")

	Remotes.getFunction("PlaceBiome").OnServerInvoke = handlePlaceBiome
	Remotes.getFunction("UpgradeBiome").OnServerInvoke = handleUpgradeBiome
	Remotes.getFunction("RenamePlanet").OnServerInvoke = handleRenamePlanet

	Players.PlayerAdded:Connect(function(player)
		task.spawn(onPlayerAdded, player)
	end)
	Players.PlayerRemoving:Connect(onPlayerRemoving)

	-- Spieler, die vor init() beigetreten sind (z. B. Studio-Solo-Test).
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
end

-- Ursprung der Insel dieses Spielers (nil, falls noch keine vergeben).
function PlanetService.getPlotOrigin(player: Player): CFrame?
	return plotOrigins[player]
end

-- Boden-Part einer Zone (für den HarvestService).
function PlanetService.getZonePart(player: Player, slot: number): BasePart?
	local plotFolder = getPlotFolder(player)
	if plotFolder == nil then
		return nil
	end
	local zone = plotFolder:FindFirstChild(`Zone_{slot}`)
	if zone ~= nil and zone:IsA("BasePart") then
		return zone
	end
	return nil
end

-- Welt-Position des Verkaufs-Pads (für den HarvestService).
function PlanetService.getSellPadPosition(player: Player): Vector3?
	local plotFolder = getPlotFolder(player)
	if plotFolder == nil then
		return nil
	end
	local pad = plotFolder:FindFirstChild("SellPad")
	if pad ~= nil and pad:IsA("BasePart") then
		return pad.Position
	end
	return nil
end

-- Alle 12 Zonen an den aktuellen Profilstand angleichen (z. B. nach Rebirth).
function PlanetService.refreshAllZones(player: Player)
	local profile = DataService.getProfile(player)
	if profile == nil then
		return
	end
	for slot = 1, GameConfig.PLANET_SLOTS do
		local placed: Types.PlacedBiome? = nil
		for _, candidate in profile.biomes do
			if candidate.slot == slot then
				placed = candidate
				break
			end
		end
		updateZoneVisual(player, slot, placed)
	end
end

-- Exklusive Rebirth-Deko: goldene Orbs umkreisen den Insel-Kristall
-- (einer pro Wiedergeburt, gedeckelt), ab 3 Wiedergeburten mit Licht.
function PlanetService.applyRebirthDeco(player: Player, rebirths: number)
	local plotFolder = getPlotFolder(player)
	if plotFolder == nil then
		return
	end

	local existing = plotFolder:FindFirstChild("RebirthDeco")
	if existing ~= nil then
		existing:Destroy()
	end
	if rebirths <= 0 then
		return
	end

	local core = plotFolder:FindFirstChild("Core")
	if core == nil or not core:IsA("BasePart") then
		return
	end

	local deco = Instance.new("Model")
	deco.Name = "RebirthDeco"

	local shown = math.min(rebirths, 8)
	for index = 1, shown do
		local angle = (index / shown) * 2 * math.pi
		local orb = Instance.new("Part")
		orb.Name = `RebirthOrb_{index}`
		orb.Shape = Enum.PartType.Ball
		orb.Size = Vector3.new(1.1, 1.1, 1.1)
		orb.Color = Color3.fromRGB(255, 210, 90)
		orb.Material = Enum.Material.Neon
		orb.Anchored = true
		orb.CanCollide = false
		orb.CanQuery = false
		orb.CFrame = (core :: BasePart).CFrame * CFrame.new(math.cos(angle) * 4, 0.5, math.sin(angle) * 4)
		orb.Parent = deco
		if rebirths >= 3 and index == 1 then
			local light = Instance.new("PointLight")
			light.Color = orb.Color
			light.Range = 14
			light.Brightness = 1
			light.Parent = orb
		end
	end

	deco.Parent = plotFolder
end

-- Schickt dem Besitzer einen frischen Insel-Snapshot (tiefe Kopie).
function PlanetService.sendSnapshot(player: Player)
	local profile = DataService.getProfile(player)
	if profile == nil then
		return
	end
	local event = planetUpdatedEvent
	if event == nil then
		event = Remotes.getEvent("PlanetUpdated")
		planetUpdatedEvent = event
	end
	event:FireClient(player, buildSnapshot(profile))
end

return PlanetService
