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
local TweenService = game:GetService("TweenService")
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
local CORE_HEIGHT_OFFSET = 10 -- Schwebehöhe des Insel-Kristalls über dem Boden
local PLAZA_RADIUS = 16 -- Radius der Spawn-Plaza in der Inselmitte
local SPAWN_OFFSET = Vector3.new(0, 5, -10) -- Spawnpunkt relativ zur Inselmitte
local SELL_PAD_OFFSET = Vector3.new(0, 0, 26) -- Verkaufs-Pad südlich der Plaza

local BASE_COLOR = Color3.fromRGB(126, 158, 96)
local LOCKED_FLOOR_COLOR = Color3.fromRGB(110, 110, 116)
local FOG_COLOR = Color3.fromRGB(190, 195, 205)
local SELL_PAD_COLOR = Color3.fromRGB(226, 176, 44)
local SHOP_PAD_COLOR = Color3.fromRGB(72, 118, 200)
local CORE_COLOR = Color3.fromRGB(150, 210, 235)
local GOLD_COLOR = Color3.fromRGB(255, 210, 90)
local RIM_GLOW_COLOR = Color3.fromRGB(120, 225, 255) -- türkiser Magie-Ring am Inselrand
local DIRT_COLOR = Color3.fromRGB(124, 92, 62)
local STONE_COLOR = Color3.fromRGB(96, 94, 100)

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

-- Spieler, die die Spawn-Villa bereits verlassen haben (pro Session):
-- erst ab dann landen Respawns direkt auf der eigenen Insel.
local enteredWorld: { [Player]: boolean } = {}

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

local function createZoneLabel(parent: BasePart, text: string, big: boolean?)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "ZoneLabel"
	billboard.Size = if big == true then UDim2.fromOffset(240, 52) else UDim2.fromOffset(160, 36)
	billboard.StudsOffset = Vector3.new(0, if big == true then 10 else 7, 0)
	billboard.AlwaysOnTop = false
	billboard.MaxDistance = if big == true then 300 else 220

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

local function clearLockedZone(zonePart: BasePart, animated: boolean?)
	for _, child in zonePart:GetChildren() do
		if child.Name == "Fog" or string.sub(child.Name, 1, 5) == "Rock_" then
			if animated == true and child:IsA("BasePart") then
				-- Nebel/Felsen lösen sich sichtbar auf (Freischaltungs-Moment).
				local tween = TweenService:Create(child, TweenInfo.new(1), { Transparency = 1 })
				tween:Play()
				tween.Completed:Once(function()
					child:Destroy()
				end)
			else
				child:Destroy()
			end
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

	clearLockedZone(zonePart, withPop)
	zonePart.Color = def.color
	zonePart.Material = Enum.Material.Grass
	setZoneLabel(zonePart, `{def.displayName} (Lv. {placed.level})`)
	-- Prozedurales Deko-Set (mehr Objekte pro Level); Pop-Tween nur bei Aktionen.
	BiomeVisuals.build(zonePart, placed.biomeId, placed.level, withPop == true)
end

-- Deko-Part ohne Kollision/Query (für die vielen Schmuck-Elemente der Insel).
local function newDecoPart(parent: Instance, name: string): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Parent = parent
	return part
end

-- Endloses, sanftes Auf-und-Ab-Schweben (Server-Tween wie bei der Biom-Deko).
-- Die Verschiebung wird VOR-multipliziert, damit sie immer entlang der
-- Welt-Y-Achse zeigt - auch bei zufällig rotierten Felsen.
local function addFloatTween(part: BasePart, height: number, seconds: number)
	local tween = TweenService:Create(
		part,
		TweenInfo.new(seconds, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ CFrame = CFrame.new(0, height, 0) * part.CFrame }
	)
	tween:Play()
end

-- Liegender Zylinder (Scheibe/Ring) - Kurzform für die vielen Plaza-Ebenen.
local function newDisc(parent: Instance, name: string, radius: number, thickness: number, cframe: CFrame): Part
	local disc = newDecoPart(parent, name)
	disc.Shape = Enum.PartType.Cylinder
	disc.Size = Vector3.new(thickness, radius * 2, radius * 2)
	disc.CFrame = cframe * CFrame.Angles(0, 0, math.rad(90))
	return disc
end

-- Der Inselkörper: statt einer flachen Scheibe eine echte Schwebeinsel mit
-- Erd- und Felsschichten, die nach unten spitz zuläuft, einem glühenden
-- Kristall an der Unterseite, Magie-Ring am Rand und schwebenden Felsen.
local function buildIslandBody(folder: Folder, origin: CFrame)
	local topY = BASE_THICKNESS / 2

	-- Begehbare Grasscheibe (Name "Base" ist Konvention, bleibt kollidierbar).
	local base = newIslandPart(folder, "Base")
	base.Shape = Enum.PartType.Cylinder
	base.Size = Vector3.new(BASE_THICKNESS, BASE_RADIUS * 2, BASE_RADIUS * 2)
	base.Color = BASE_COLOR
	base.Material = Enum.Material.Grass
	base.CFrame = origin * CFrame.Angles(0, 0, math.rad(90))

	-- Üppiger Grasüberhang: etwas breiterer, dunklerer Ring direkt unter der Kante.
	local overhang = newDisc(folder, "GrassOverhang", BASE_RADIUS + 1.6, 1.4, origin * CFrame.new(0, topY - 1.2, 0))
	overhang.Color = Color3.fromRGB(96, 128, 72)
	overhang.Material = Enum.Material.Grass

	-- Erd- und Felsschichten, nach unten schmaler (klassische Schwebeinsel-Silhouette).
	local layers = {
		{ radius = 58, thickness = 7, y = -BASE_THICKNESS / 2 - 3.5, color = DIRT_COLOR, material = Enum.Material.Ground },
		{ radius = 44, thickness = 9, y = -BASE_THICKNESS / 2 - 11.5, color = STONE_COLOR, material = Enum.Material.Slate },
		{ radius = 30, thickness = 9, y = -BASE_THICKNESS / 2 - 20.5, color = STONE_COLOR, material = Enum.Material.Slate },
		{ radius = 17, thickness = 8, y = -BASE_THICKNESS / 2 - 29, color = STONE_COLOR, material = Enum.Material.Slate },
		{ radius = 8, thickness = 7, y = -BASE_THICKNESS / 2 - 36.5, color = STONE_COLOR, material = Enum.Material.Slate },
	}
	for index, layer in layers do
		local disc = newDisc(folder, `BodyLayer_{index}`, layer.radius, layer.thickness, origin * CFrame.new(0, layer.y, 0))
		disc.Color = layer.color
		disc.Material = layer.material
	end

	-- Glühender Kristall an der Insel-Spitze: die "Energiequelle", die die
	-- Insel schweben lässt - von unten und von Nachbarinseln aus sichtbar.
	local tip = newDecoPart(folder, "TipCrystal")
	tip.Size = Vector3.new(5, 9, 5)
	tip.Color = RIM_GLOW_COLOR
	tip.Material = Enum.Material.Neon
	tip.CFrame = origin * CFrame.new(0, -BASE_THICKNESS / 2 - 43, 0) * CFrame.Angles(0, math.rad(45), 0)
	local tipLight = Instance.new("PointLight")
	tipLight.Color = RIM_GLOW_COLOR
	tipLight.Range = 34
	tipLight.Brightness = 1.4
	tipLight.Parent = tip
	addFloatTween(tip, 1.4, 4.5)

	-- Magie-Ring: 12 türkise Neon-Segmente um die Inselkante.
	for index = 1, 12 do
		local angle = (index / 12) * 2 * math.pi
		local segment = newDecoPart(folder, `RimGlow_{index}`)
		segment.Size = Vector3.new(16, 0.7, 0.7)
		segment.Color = RIM_GLOW_COLOR
		segment.Material = Enum.Material.Neon
		segment.Transparency = 0.25
		segment.CFrame = origin
			* CFrame.Angles(0, angle, 0)
			* CFrame.new(0, topY - 0.5, BASE_RADIUS + 0.9)
	end

	-- Schwebende Felsbrocken unter und neben der Insel (deterministisch pro
	-- Insel-Position), jeder mit eigenem, langsamem Schwebe-Tween.
	local rng = Random.new(math.floor(origin.Position.X * 7 + origin.Position.Z * 13))
	for index = 1, 6 do
		local angle = rng:NextNumber(0, 2 * math.pi)
		local distance = rng:NextNumber(BASE_RADIUS - 16, BASE_RADIUS + 14)
		local size = rng:NextNumber(3, 6.5)
		local rock = newDecoPart(folder, `FloatRock_{index}`)
		rock.Size = Vector3.new(size, size * rng:NextNumber(0.7, 1.1), size * rng:NextNumber(0.8, 1.2))
		rock.Color = STONE_COLOR
		rock.Material = Enum.Material.Slate
		rock.CFrame = origin
			* CFrame.new(math.cos(angle) * distance, rng:NextNumber(-26, -8), math.sin(angle) * distance)
			* CFrame.Angles(rng:NextNumber(0, math.pi), rng:NextNumber(0, math.pi), rng:NextNumber(0, math.pi))
		addFloatTween(rock, rng:NextNumber(1.2, 2.4), rng:NextNumber(4, 8))
	end
end

-- Die Spawn-Plaza in der Inselmitte: gestufte Steinkreise mit goldenem
-- Leucht-Inlay, 12 Radialwege zu den Zonen und 4 Kristall-Laternen.
local function buildHubPlaza(folder: Folder, origin: CFrame)
	local topY = BASE_THICKNESS / 2

	local outer = newDisc(folder, "PlazaOuter", PLAZA_RADIUS, 0.6, origin * CFrame.new(0, topY + 0.3, 0))
	outer.Color = Color3.fromRGB(176, 172, 162)
	outer.Material = Enum.Material.Slate
	outer.CanCollide = true

	-- Gold-Inlay: schmaler Neon-Ring zwischen äußerer und mittlerer Ebene.
	local inlay = newDisc(folder, "PlazaInlay", 13.6, 0.7, origin * CFrame.new(0, topY + 0.34, 0))
	inlay.Color = GOLD_COLOR
	inlay.Material = Enum.Material.Neon
	inlay.Transparency = 0.1

	local mid = newDisc(folder, "PlazaMid", 12.4, 0.8, origin * CFrame.new(0, topY + 0.42, 0))
	mid.Color = Color3.fromRGB(118, 116, 124)
	mid.Material = Enum.Material.Slate
	mid.CanCollide = true

	local center = newDisc(folder, "PlazaCenter", 7, 0.9, origin * CFrame.new(0, topY + 0.5, 0))
	center.Color = Color3.fromRGB(206, 184, 130)
	center.Material = Enum.Material.Marble
	center.CanCollide = true

	-- 12 Radialwege: je einer zeigt exakt auf eine Biom-Zone.
	for slotNumber = 1, GameConfig.PLANET_SLOTS do
		local _, angle = zoneCenter(origin, slotNumber)
		local innerRadius = PLAZA_RADIUS + 1.5
		local outerRadius = ZONE_RING_RADIUS - ZONE_DEPTH / 2 - 1
		local length = outerRadius - innerRadius
		local path = newDecoPart(folder, `Path_{slotNumber}`)
		path.Size = Vector3.new(3, 0.25, length)
		path.Color = Color3.fromRGB(188, 184, 174)
		path.Material = Enum.Material.Slate
		path.CFrame = origin
			* CFrame.Angles(0, -angle - math.rad(90), 0)
			* CFrame.new(0, topY + 0.13, -(innerRadius + length / 2))
	end

	-- 4 Kristall-Laternen auf der Plaza (diagonal, damit die Wege frei bleiben).
	for index = 0, 3 do
		local angle = index * math.pi / 2 + math.pi / 4
		local offset = CFrame.Angles(0, angle, 0) * CFrame.new(0, 0, -(PLAZA_RADIUS - 2))

		local column = newDecoPart(folder, `LanternColumn_{index + 1}`)
		column.Size = Vector3.new(1.4, 6, 1.4)
		column.Color = Color3.fromRGB(140, 136, 144)
		column.Material = Enum.Material.Slate
		column.CFrame = origin * offset * CFrame.new(0, topY + 3.3, 0)

		local crystal = newDecoPart(folder, `LanternCrystal_{index + 1}`)
		crystal.Size = Vector3.new(1.5, 2.2, 1.5)
		crystal.Color = GOLD_COLOR
		crystal.Material = Enum.Material.Neon
		crystal.CFrame = origin * offset * CFrame.new(0, topY + 7.3, 0) * CFrame.Angles(0, math.rad(45), 0)
		local light = Instance.new("PointLight")
		light.Color = GOLD_COLOR
		light.Range = 18
		light.Brightness = 0.9
		light.Parent = crystal
		addFloatTween(crystal, 0.4, 3 + index * 0.35)
	end
end

-- Der große Insel-Kristall über der Plaza: schwebt und pulsiert, trägt das
-- Namensschild, zwei Splitter-Kristalle, zwei Halo-Ringe, eine Lichtsäule
-- in den Himmel und Funkel-Partikel. "Core" bleibt das Ziel für Skins/Auren.
local function buildCoreCrystal(folder: Folder, origin: CFrame)
	local coreCenter = origin * CFrame.new(0, BASE_THICKNESS / 2 + CORE_HEIGHT_OFFSET, 0)

	local core = newIslandPart(folder, "Core")
	core.Size = Vector3.new(4, 10, 4)
	core.Color = CORE_COLOR
	core.Material = Enum.Material.Glass
	core.CanCollide = false
	core.CanQuery = false
	core.CFrame = coreCenter * CFrame.Angles(0, math.rad(45), 0)
	addFloatTween(core, 1.4, 5)

	local glow = Instance.new("PointLight")
	glow.Name = "CoreGlow"
	glow.Color = CORE_COLOR
	glow.Range = 26
	glow.Brightness = 1.1
	glow.Parent = core

	local sparkle = Instance.new("ParticleEmitter")
	sparkle.Name = "CoreSparkle"
	sparkle.Color = ColorSequence.new(Color3.new(1, 1, 1), CORE_COLOR)
	sparkle.LightEmission = 1
	sparkle.Rate = 5
	sparkle.Lifetime = NumberRange.new(1.2, 2)
	sparkle.Speed = NumberRange.new(1, 2.5)
	sparkle.SpreadAngle = Vector2.new(180, 180)
	sparkle.Size = NumberSequence.new(0.35)
	sparkle.Parent = core

	-- Zwei kleinere Splitter-Kristalle, die versetzt mitschweben.
	for index = 1, 2 do
		local side = if index == 1 then 1 else -1
		local shard = newDecoPart(folder, `CoreShard_{index}`)
		shard.Size = Vector3.new(1.7, 5, 1.7)
		shard.Color = CORE_COLOR
		shard.Material = Enum.Material.Glass
		shard.Transparency = 0.15
		shard.CFrame = coreCenter
			* CFrame.new(side * 4.6, -1.5 + index * 0.8, side * 1.6)
			* CFrame.Angles(math.rad(side * 14), math.rad(45), math.rad(-side * 8))
		addFloatTween(shard, 1, 3.6 + index)
	end

	-- Zwei gekippte Halo-Ringe um den Kristall.
	for index = 1, 2 do
		local side = if index == 1 then 1 else -1
		local halo = newDisc(
			folder,
			`CoreHalo_{index}`,
			5.5 + index * 2,
			0.35,
			coreCenter * CFrame.Angles(math.rad(side * 22), 0, 0)
		)
		halo.Color = if index == 1 then RIM_GLOW_COLOR else GOLD_COLOR
		halo.Material = Enum.Material.Neon
		halo.Transparency = 0.45
		addFloatTween(halo, side * 0.8, 4 + index * 0.7)
	end

	-- Lichtsäule in den Himmel: macht jede Insel schon von Weitem erkennbar.
	local beam = newDecoPart(folder, "CoreBeam")
	beam.Shape = Enum.PartType.Cylinder
	beam.Size = Vector3.new(80, 2.6, 2.6)
	beam.Color = CORE_COLOR
	beam.Material = Enum.Material.Neon
	beam.Transparency = 0.78
	beam.CFrame = coreCenter * CFrame.new(0, 42, 0) * CFrame.Angles(0, 0, math.rad(90))
end

-- Ein aufgewertetes Boden-Pad (Verkaufen/Shop): Leucht-Ring, sanfte
-- Lichtsäule, PointLight und aufsteigende Partikel plus großes Schild.
local function buildPad(folder: Folder, origin: CFrame, name: string, offset: Vector3, color: Color3, labelText: string): BasePart
	local padCenter = origin * CFrame.new(offset + Vector3.new(0, BASE_THICKNESS / 2 + 0.25, 0))

	local pad = newIslandPart(folder, name)
	pad.Shape = Enum.PartType.Cylinder
	pad.Size = Vector3.new(0.5, 11, 11)
	pad.Color = color
	pad.Material = Enum.Material.Metal
	pad.CFrame = padCenter * CFrame.Angles(0, 0, math.rad(90))
	createZoneLabel(pad, labelText, true)

	local ring = newDisc(folder, `{name}Ring`, 6.6, 0.22, padCenter * CFrame.new(0, -0.1, 0))
	ring.Color = color
	ring.Material = Enum.Material.Neon
	ring.Transparency = 0.2

	local beam = newDecoPart(folder, `{name}Beam`)
	beam.Shape = Enum.PartType.Cylinder
	beam.Size = Vector3.new(13, 8.4, 8.4)
	beam.Color = color
	beam.Material = Enum.Material.Neon
	beam.Transparency = 0.86
	beam.CFrame = padCenter * CFrame.new(0, 6.7, 0) * CFrame.Angles(0, 0, math.rad(90))

	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 16
	light.Brightness = 0.8
	light.Parent = pad

	local motes = Instance.new("ParticleEmitter")
	motes.Name = "PadMotes"
	motes.Color = ColorSequence.new(color)
	motes.LightEmission = 0.8
	motes.Rate = 4
	motes.Lifetime = NumberRange.new(1.5, 2.5)
	motes.Speed = NumberRange.new(2, 4)
	motes.SpreadAngle = Vector2.new(12, 12)
	motes.Size = NumberSequence.new(0.4)
	motes.Parent = pad

	return pad
end

-- Das eigene Häuschen auf der Insel: Holzhaus mit Giebeldach, Fenstern,
-- Laterne und kleiner Einrichtung. Steht zwischen zwei Radialwegen und
-- die Tür zeigt zur Plaza - DAS macht die Insel zum echten Zuhause.
local function buildHomeCottage(folder: Folder, origin: CFrame)
	local topY = BASE_THICKNESS / 2
	-- Anker zwischen zwei Wegen; lokal zeigt +Z zurück zur Inselmitte.
	local anchor = origin * CFrame.Angles(0, -math.rad(15), 0) * CFrame.new(0, topY, -28)

	local WALL_COLOR = Color3.fromRGB(232, 220, 196)
	local WOOD_COLOR = Color3.fromRGB(133, 100, 64)
	local ROOF_COLOR = Color3.fromRGB(152, 72, 60)

	-- Sockel/Boden.
	local sockel = newIslandPart(folder, "HausSockel")
	sockel.Size = Vector3.new(13, 0.5, 11)
	sockel.Color = WOOD_COLOR
	sockel.Material = Enum.Material.WoodPlanks
	sockel.CFrame = anchor * CFrame.new(0, 0.25, 0)

	-- Wände (Tür-Lücke vorn Richtung Plaza).
	local function wall(name: string, size: Vector3, offset: CFrame)
		local part = newIslandPart(folder, name)
		part.Size = size
		part.Color = WALL_COLOR
		part.Material = Enum.Material.SmoothPlastic
		part.CFrame = anchor * offset
	end
	wall("HausWandHinten", Vector3.new(13, 5.5, 0.6), CFrame.new(0, 3.25, -5.2))
	wall("HausWandLinks", Vector3.new(0.6, 5.5, 11), CFrame.new(-6.2, 3.25, 0))
	wall("HausWandRechts", Vector3.new(0.6, 5.5, 11), CFrame.new(6.2, 3.25, 0))
	wall("HausWandVornL", Vector3.new(4.7, 5.5, 0.6), CFrame.new(-4.15, 3.25, 5.2))
	wall("HausWandVornR", Vector3.new(4.7, 5.5, 0.6), CFrame.new(4.15, 3.25, 5.2))
	wall("HausTuersturz", Vector3.new(3.6, 1.5, 0.6), CFrame.new(0, 5.25, 5.2))

	-- Fenster (Glas, leicht nach innen versetzt).
	for _, side in { -1, 1 } do
		local window = newDecoPart(folder, `HausFenster_{side}`)
		window.Size = Vector3.new(0.2, 2.5, 3)
		window.Color = Color3.fromRGB(178, 220, 240)
		window.Material = Enum.Material.Glass
		window.Transparency = 0.4
		window.CFrame = anchor * CFrame.new(side * 6.0, 3.4, 0)
	end

	-- Giebeldach aus zwei Keilen.
	for _, side in { -1, 1 } do
		local wedge = Instance.new("WedgePart")
		wedge.Name = `HausDach_{side}`
		wedge.Anchored = true
		wedge.Size = Vector3.new(13.8, 3.2, 6.1)
		wedge.Color = ROOF_COLOR
		wedge.Material = Enum.Material.Slate
		wedge.CFrame = anchor
			* CFrame.new(0, 7.6, side * 3.05)
			* CFrame.Angles(0, if side == 1 then math.pi else 0, 0)
		wedge.Parent = folder
	end

	-- Schornstein (trägt das Schild, damit es frei über dem Dach schwebt).
	local chimney = newIslandPart(folder, "HausSchornstein")
	chimney.Size = Vector3.new(1.4, 2.6, 1.4)
	chimney.Color = Color3.fromRGB(110, 108, 114)
	chimney.Material = Enum.Material.Slate
	chimney.CFrame = anchor * CFrame.new(4, 9.2, -2)
	createZoneLabel(chimney, "🏠 Dein Zuhause")

	-- Fußmatte und Laterne an der Tür.
	local mat = newDecoPart(folder, "HausMatte")
	mat.Size = Vector3.new(3.4, 0.15, 1.6)
	mat.Color = Color3.fromRGB(94, 70, 48)
	mat.Material = Enum.Material.Fabric
	mat.CFrame = anchor * CFrame.new(0, 0.58, 6.2)

	local post = newDecoPart(folder, "HausLaterne")
	post.Size = Vector3.new(0.5, 3, 0.5)
	post.Color = Color3.fromRGB(70, 68, 76)
	post.Material = Enum.Material.Metal
	post.CFrame = anchor * CFrame.new(5.4, 1.5, 6.4)
	local lampe = newDecoPart(folder, "HausLaternenlicht")
	lampe.Size = Vector3.new(0.9, 0.9, 0.9)
	lampe.Color = GOLD_COLOR
	lampe.Material = Enum.Material.Neon
	lampe.CFrame = anchor * CFrame.new(5.4, 3.3, 6.4)
	local lampLight = Instance.new("PointLight")
	lampLight.Color = GOLD_COLOR
	lampLight.Range = 12
	lampLight.Brightness = 0.8
	lampLight.Parent = lampe

	-- Mini-Einrichtung (durch die Tür sichtbar): Bett, Teppich, Regal.
	local bett = newDecoPart(folder, "HausBett")
	bett.Size = Vector3.new(4, 0.9, 2.2)
	bett.Color = Color3.fromRGB(90, 120, 180)
	bett.Material = Enum.Material.Fabric
	bett.CFrame = anchor * CFrame.new(-3.6, 0.95, -3.4)
	local kissen = newDecoPart(folder, "HausKissen")
	kissen.Size = Vector3.new(1, 0.5, 1.8)
	kissen.Color = Color3.new(1, 1, 1)
	kissen.Material = Enum.Material.Fabric
	kissen.CFrame = anchor * CFrame.new(-5.2, 1.65, -3.4)
	local teppich = newDisc(folder, "HausTeppich", 2, 0.12, anchor * CFrame.new(0.5, 0.56, 0.5))
	teppich.Color = Color3.fromRGB(178, 84, 76)
	teppich.Material = Enum.Material.Fabric
	local regal = newDecoPart(folder, "HausRegal")
	regal.Size = Vector3.new(0.7, 2.6, 3)
	regal.Color = WOOD_COLOR
	regal.Material = Enum.Material.WoodPlanks
	regal.CFrame = anchor * CFrame.new(5.5, 1.85, -3.2)
end

-- Kleiner Garten auf der gegenüberliegenden Inselseite: Bäume, Blumen
-- und eine Bank mit Blick auf den Kristall.
local function buildGarden(folder: Folder, origin: CFrame)
	local topY = BASE_THICKNESS / 2
	local anchor = origin * CFrame.Angles(0, -math.rad(195), 0) * CFrame.new(0, topY, -27)

	-- Zwei Bäume mit rundem Stamm und zwei Kronen-Kugeln.
	for index, offset in { Vector3.new(-6, 0, -2), Vector3.new(6.5, 0, 1) } do
		local trunk = newDecoPart(folder, `GartenStamm_{index}`)
		trunk.Shape = Enum.PartType.Cylinder
		trunk.Size = Vector3.new(4.6, 1.1, 1.1)
		trunk.Color = Color3.fromRGB(110, 82, 54)
		trunk.Material = Enum.Material.Wood
		trunk.CFrame = anchor * CFrame.new(offset + Vector3.new(0, 2.3, 0)) * CFrame.Angles(0, 0, math.rad(90))
		for crown = 1, 2 do
			local leaves = newDecoPart(folder, `GartenKrone_{index}_{crown}`)
			leaves.Shape = Enum.PartType.Ball
			local size = 4.6 - crown * 1.1
			leaves.Size = Vector3.new(size, size * 0.85, size)
			leaves.Color = Color3.fromRGB(92 + crown * 18, 150 + crown * 14, 84)
			leaves.Material = Enum.Material.Grass
			leaves.CFrame = anchor * CFrame.new(offset + Vector3.new(0, 4 + crown * 1.4, 0))
		end
	end

	-- Bank mit Blick zur Inselmitte.
	local seat = newIslandPart(folder, "GartenBank")
	seat.Size = Vector3.new(4, 0.4, 1.4)
	seat.Color = Color3.fromRGB(133, 100, 64)
	seat.Material = Enum.Material.WoodPlanks
	seat.CFrame = anchor * CFrame.new(0, 1.2, 3)
	local lehne = newDecoPart(folder, "GartenBankLehne")
	lehne.Size = Vector3.new(4, 1.4, 0.3)
	lehne.Color = seat.Color
	lehne.Material = Enum.Material.WoodPlanks
	lehne.CFrame = anchor * CFrame.new(0, 2.1, 2.45)
	for _, side in { -1, 1 } do
		local leg = newDecoPart(folder, `GartenBankFuss_{side}`)
		leg.Size = Vector3.new(0.4, 1, 1.2)
		leg.Color = Color3.fromRGB(90, 68, 44)
		leg.Material = Enum.Material.Wood
		leg.CFrame = anchor * CFrame.new(side * 1.6, 0.5, 3)
	end

	-- Blumen: bunte Mini-Kugeln auf Stielen.
	local flowerColors = { Color3.fromRGB(240, 110, 130), Color3.fromRGB(255, 200, 80), Color3.fromRGB(150, 120, 230) }
	for index, color in flowerColors do
		local stem = newDecoPart(folder, `GartenStiel_{index}`)
		stem.Size = Vector3.new(0.18, 1.1, 0.18)
		stem.Color = Color3.fromRGB(88, 140, 70)
		stem.Material = Enum.Material.Grass
		stem.CFrame = anchor * CFrame.new(-3 + index * 2.1, 0.55, 5.4)
		local bloom = newDecoPart(folder, `GartenBluete_{index}`)
		bloom.Shape = Enum.PartType.Ball
		bloom.Size = Vector3.new(0.7, 0.7, 0.7)
		bloom.Color = color
		bloom.Material = Enum.Material.Neon
		bloom.CFrame = anchor * CFrame.new(-3 + index * 2.1, 1.25, 5.4)
	end
end

-- Baut die komplette Insel eines Spielers auf.
local function buildIsland(player: Player, origin: CFrame)
	local folder = Instance.new("Folder")
	folder.Name = `Plot_{player.UserId}`

	buildIslandBody(folder, origin)
	buildHubPlaza(folder, origin)
	buildCoreCrystal(folder, origin)
	buildHomeCottage(folder, origin)
	buildGarden(folder, origin)

	-- Verkaufs-Pad (Rucksack -> Energie) und Shop-Pad (öffnet den Shop).
	buildPad(folder, origin, "SellPad", SELL_PAD_OFFSET, SELL_PAD_COLOR, "💰 Verkaufen")
	buildPad(folder, origin, "ShopPad", -SELL_PAD_OFFSET, SHOP_PAD_COLOR, "🛒 Shop")

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
	-- Erster Spawn der Session: der Spieler startet in der Spawn-Villa
	-- (LobbyService) und kommt erst über deren Portal auf seine Insel.
	if not enteredWorld[player] then
		return
	end
	local origin = plotOrigins[player]
	if origin == nil then
		return
	end
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if root ~= nil and root:IsA("BasePart") then
		character:PivotTo(origin * CFrame.new(SPAWN_OFFSET))
	end
end

-- Merkt sich, dass der Spieler die Villa verlassen hat (Respawns landen
-- ab jetzt direkt auf der Insel) - z. B. nach Portal, GoHome oder Besuch.
function PlanetService.markEntered(player: Player)
	enteredWorld[player] = true
end

-- Teleportiert den Spieler auf die Plaza seiner Insel (Portal/GoHome).
function PlanetService.teleportHome(player: Player): boolean
	local origin = plotOrigins[player]
	local character = player.Character
	if origin == nil or character == nil then
		return false
	end
	if character:FindFirstChild("HumanoidRootPart") == nil then
		return false
	end
	enteredWorld[player] = true
	character:PivotTo(origin * CFrame.new(SPAWN_OFFSET))
	return true
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
	enteredWorld[player] = nil

	local plotFolder = getPlotFolder(player)
	if plotFolder ~= nil then
		plotFolder:Destroy()
	end
end

--------------------------------------------------------------------------
-- Welt-Stimmung
--------------------------------------------------------------------------

-- "Goldene Stunde"-Look: warmes Licht, weiche Schatten, dezentes Bloom,
-- SunRays und leicht angehobene Sättigung (typischer Simulator-Look,
-- bewusst subtil - kein Neon-Matsch). Idempotent.
local function setupWorldAmbience()
	local Lighting = game:GetService("Lighting")

	Lighting.ClockTime = 16.4 -- goldene Stunde: lange, warme Schatten
	Lighting.Brightness = 2.6
	Lighting.GlobalShadows = true
	Lighting.ShadowSoftness = 0.25
	Lighting.EnvironmentDiffuseScale = 0.6
	Lighting.EnvironmentSpecularScale = 0.6
	Lighting.Ambient = Color3.fromRGB(118, 110, 125)
	Lighting.OutdoorAmbient = Color3.fromRGB(160, 145, 140)
	Lighting.ColorShift_Top = Color3.fromRGB(255, 226, 180) -- warme Sonnenseite
	Lighting.ColorShift_Bottom = Color3.fromRGB(120, 130, 170) -- kühle Schattenseite

	if Lighting:FindFirstChild("PlanetForgeSky") == nil then
		local sky = Instance.new("Sky")
		sky.Name = "PlanetForgeSky"
		sky.StarCount = 1500
		sky.SunAngularSize = 18
		sky.MoonAngularSize = 12
		sky.Parent = Lighting
	end

	if Lighting:FindFirstChild("PlanetForgeAtmosphere") == nil then
		local atmosphere = Instance.new("Atmosphere")
		atmosphere.Name = "PlanetForgeAtmosphere"
		atmosphere.Density = 0.32
		atmosphere.Color = Color3.fromRGB(215, 200, 215)
		atmosphere.Decay = Color3.fromRGB(130, 120, 160)
		atmosphere.Glare = 0.35
		atmosphere.Haze = 1.8
		atmosphere.Parent = Lighting
	end

	if Lighting:FindFirstChild("PlanetForgeBloom") == nil then
		local bloom = Instance.new("BloomEffect")
		bloom.Name = "PlanetForgeBloom"
		bloom.Intensity = 0.5
		bloom.Size = 28
		bloom.Threshold = 1.1 -- hoch genug, damit nur Neon/Sonne blüht
		bloom.Parent = Lighting
	end

	if Lighting:FindFirstChild("PlanetForgeColor") == nil then
		local color = Instance.new("ColorCorrectionEffect")
		color.Name = "PlanetForgeColor"
		color.Contrast = 0.08
		color.Saturation = 0.18 -- "juicy", aber unterhalb der Kitsch-Grenze
		color.TintColor = Color3.fromRGB(255, 248, 238)
		color.Parent = Lighting
	end

	if Lighting:FindFirstChild("PlanetForgeSunRays") == nil then
		local rays = Instance.new("SunRaysEffect")
		rays.Name = "PlanetForgeSunRays"
		rays.Intensity = 0.06 -- dezent: nur ein Hauch Gottesstrahlen
		rays.Spread = 0.8
		rays.Parent = Lighting
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
