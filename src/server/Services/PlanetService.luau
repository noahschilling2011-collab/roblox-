--!strict
-- PlanetService: verwaltet die Planeten-Plots der Spieler sowie Bau und
-- Ausbau von Biomen. Der Server ist autoritativ: alle Client-Eingaben
-- (PlaceBiome/UpgradeBiome) werden hier vollständig validiert.

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
local POSITIONS_PER_RING = 12 -- Plots pro Ring; danach beginnt ein weiterer Ring
local CORE_DIAMETER = 24 -- Durchmesser des Planetenkerns in Studs
local SLOT_DIAMETER = 14 -- Durchmesser einer Slot-Plattform in Studs
local SLOT_THICKNESS = 1
local SLOT_RING_RADIUS = 22 -- Abstand der Slot-Plattformen vom Planetenzentrum
local SLOT_Y_OFFSET = -2 -- Plattformen leicht unterhalb des Kern-Äquators (begehbar)
local SPAWN_HEIGHT_OFFSET = CORE_DIAMETER / 2 + 4 -- Spawnpunkt oberhalb des Kerns

local CORE_COLOR = Color3.fromRGB(105, 100, 95)
local EMPTY_SLOT_COLOR = Color3.fromRGB(120, 120, 120)

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
	local child = getPlotsRoot():FindFirstChild(`Plot_{player.UserId}`)
	if child ~= nil and child:IsA("Folder") then
		return child
	end
	return nil
end

-- Kleinster freier Plot-Index (Indizes werden beim Verlassen wieder frei).
local function assignPlotIndex(player: Player): number
	local index = 1
	while usedIndices[index] do
		index += 1
	end
	usedIndices[index] = true
	plotIndices[player] = index
	return index
end

-- Plot-Ursprung: Kreis um den Weltursprung; bei mehr als POSITIONS_PER_RING
-- Spielern folgt ein zweiter (dritter, ...) Ring mit größerem Radius.
local function computePlotOrigin(index: number): CFrame
	local ring = math.floor((index - 1) / POSITIONS_PER_RING)
	local slotInRing = (index - 1) % POSITIONS_PER_RING
	local radius = GameConfig.PLOT_SPACING_STUDS * (ring + 1)
	local angle = (slotInRing / POSITIONS_PER_RING) * 2 * math.pi
	return CFrame.new(math.cos(angle) * radius, GameConfig.PLOT_HEIGHT_STUDS, math.sin(angle) * radius)
end

local function createSlotLabel(parent: BasePart, text: string)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "SlotLabel"
	billboard.Size = UDim2.fromOffset(140, 36)
	billboard.StudsOffset = Vector3.new(0, 4, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 250

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

-- Farbe, Material und Beschriftung eines Slots setzen.
local function setSlotAppearance(part: BasePart, color: Color3, material: Enum.Material, labelText: string)
	part.Color = color
	part.Material = material
	local billboard = part:FindFirstChild("SlotLabel")
	if billboard ~= nil then
		local label = billboard:FindFirstChild("Label")
		if label ~= nil and label:IsA("TextLabel") then
			label.Text = labelText
		end
	end
end

-- Slot-Visual an den Profilstand angleichen (placed = nil -> leerer Slot).
local function updateSlotVisual(player: Player, slotNumber: number, placed: Types.PlacedBiome?, withPop: boolean?)
	local plotFolder = getPlotFolder(player)
	if plotFolder == nil then
		return
	end
	local slotPart = plotFolder:FindFirstChild(`Slot_{slotNumber}`)
	if slotPart == nil or not slotPart:IsA("BasePart") then
		return
	end

	if placed == nil then
		setSlotAppearance(slotPart, EMPTY_SLOT_COLOR, Enum.Material.Concrete, `Slot {slotNumber}`)
		BiomeVisuals.clear(slotPart)
		return
	end

	local def = BiomeConfig.Biomes[placed.biomeId]
	if def == nil then
		warn(`[PlanetForge] Unbekanntes Biom im Profil von {player.Name}: {placed.biomeId}`)
		return
	end
	setSlotAppearance(slotPart, def.color, Enum.Material.Grass, `{def.displayName} (Lv. {placed.level})`)
	-- Prozedurales Deko-Set (mehr Objekte pro Level); Pop-Tween nur bei Aktionen.
	BiomeVisuals.build(slotPart, placed.biomeId, placed.level, withPop == true)
end

-- Baut Kern und leere Slot-Plattformen für einen Spieler auf.
local function buildPlot(player: Player, origin: CFrame)
	local folder = Instance.new("Folder")
	folder.Name = `Plot_{player.UserId}`

	local core = Instance.new("Part")
	core.Name = "Core"
	core.Shape = Enum.PartType.Ball
	core.Size = Vector3.new(CORE_DIAMETER, CORE_DIAMETER, CORE_DIAMETER)
	core.Anchored = true
	core.Material = Enum.Material.Slate
	core.Color = CORE_COLOR
	core.CFrame = origin
	core.Parent = folder

	for slotNumber = 1, GameConfig.PLANET_SLOTS do
		local angle = ((slotNumber - 1) / GameConfig.PLANET_SLOTS) * 2 * math.pi
		local offset = Vector3.new(
			math.cos(angle) * SLOT_RING_RADIUS,
			SLOT_Y_OFFSET,
			math.sin(angle) * SLOT_RING_RADIUS
		)

		local part = Instance.new("Part")
		part.Name = `Slot_{slotNumber}`
		part.Shape = Enum.PartType.Cylinder
		part.Size = Vector3.new(SLOT_THICKNESS, SLOT_DIAMETER, SLOT_DIAMETER)
		part.Anchored = true
		part.Material = Enum.Material.Concrete
		part.Color = EMPTY_SLOT_COLOR
		-- Zylinderachse liegt auf X; um 90° um Z gedreht zeigt die flache Seite nach oben.
		part.CFrame = origin * CFrame.new(offset) * CFrame.Angles(0, 0, math.rad(90))
		createSlotLabel(part, `Slot {slotNumber}`)
		part.Parent = folder
	end

	folder.Parent = getPlotsRoot()
end

-- Aktualisiert das Namensschild über dem Planetenkern.
-- Ohne eigenen Namen: "<DisplayName>s Planet".
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
	local displayText = if customName ~= "" then customName else `{player.DisplayName}s Planet`

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
		gui.StudsOffset = Vector3.new(0, CORE_DIAMETER / 2 + 8, 0)
		gui.AlwaysOnTop = false
		gui.MaxDistance = 350

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

-- Handler für RenamePlanet(name): validiert, filtert (Roblox-Pflicht für
-- nutzergenerierten Text) und speichert den Planetennamen.
local function handleRenamePlanet(player: Player, nameArg: unknown): (boolean, any?)
	if typeof(nameArg) ~= "string" then
		return false, "Ungültiger Name."
	end

	-- Führende/abschließende Leerzeichen entfernen.
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

	-- Pflicht-Filterung für von Spielern eingegebenen Text.
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

-- Holt oder erstellt einen ParticleEmitter mit festem Namen unter parent.
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

-- Wendet die ausgerüstete Kauf-Kosmetik (Skin/Aura/Wetter) auf den Plot an.
-- Idempotent: stellt ohne ausgerüstete Kosmetik den Standard-Look wieder her.
-- Haustiere verwaltet der MonetizationService selbst.
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

	-- Skin: Farbe und Material des Planetenkerns.
	local skinId = equipped.skin
	local skinDef = if skinId ~= nil then MonetizationConfig.Cosmetics[skinId] else nil
	if skinDef ~= nil and skinDef.category == "skin" then
		core.Color = skinDef.visual.color or CORE_COLOR
		core.Material = skinDef.visual.material or Enum.Material.Slate
	else
		skinDef = nil
		core.Color = CORE_COLOR
		core.Material = Enum.Material.Slate
	end

	-- Glow-Licht des Skins.
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

	-- Aura: Partikel direkt am Kern.
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

	-- Wetter: Partikel regnen aus einer unsichtbaren Fläche über dem Planeten.
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
			weatherPart.Size =
				Vector3.new(SLOT_RING_RADIUS * 2 + SLOT_DIAMETER, 1, SLOT_RING_RADIUS * 2 + SLOT_DIAMETER)
			weatherPart.Transparency = 1
			weatherPart.Anchored = true
			weatherPart.CanCollide = false
			weatherPart.CanQuery = false
			weatherPart.CFrame = (plotOrigins[player] or core.CFrame) * CFrame.new(0, CORE_DIAMETER * 1.5, 0)
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

local function teleportToPlot(player: Player, character: Model)
	local origin = plotOrigins[player]
	if origin == nil then
		return
	end
	-- Auf das Root-Part warten, damit PivotTo zuverlässig greift.
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if root == nil or plotOrigins[player] == nil then
		return
	end
	character:PivotTo(origin * CFrame.new(0, SPAWN_HEIGHT_OFFSET, 0))
end

local function findBiomeAtSlot(profile: Types.PlayerProfile, slot: number): Types.PlacedBiome?
	for _, placed in profile.biomes do
		if placed.slot == slot then
			return placed
		end
	end
	return nil
end

-- Validiert einen Slot-Parameter vom Client: Integer im Bereich 1..PLANET_SLOTS.
local function parseSlot(slotArg: unknown): number?
	if typeof(slotArg) ~= "number" then
		return nil
	end
	if slotArg ~= math.floor(slotArg) then
		return nil
	end
	if slotArg < 1 or slotArg > GameConfig.PLANET_SLOTS then
		return nil
	end
	return slotArg
end

-- Remote-Handler: PlaceBiome(biomeId, slot) -> (ok, snapshot | Fehlermeldung)
-- Juice beim Bauen/Upgraden: Sound + Partikel-Burst direkt am Slot,
-- damit die Aktion sich für alle sichtbar "gut anfühlt".
local function playSlotJuice(player: Player, slotNumber: number, color: Color3, level: number)
	local plotFolder = getPlotFolder(player)
	if plotFolder == nil then
		return
	end
	local slotPart = plotFolder:FindFirstChild(`Slot_{slotNumber}`)
	if slotPart == nil or not slotPart:IsA("BasePart") then
		return
	end

	-- Pop-Sound (Engine-Sounddatei, 3D am Slot; Tonhöhe steigt leicht pro Level).
	local sound = Instance.new("Sound")
	sound.SoundId = "rbxasset://sounds/snap.mp3"
	sound.Volume = 0.8
	sound.PlaybackSpeed = 0.95 + level * 0.06
	sound.RollOffMaxDistance = 120
	sound.Parent = slotPart
	sound:Play()
	task.delay(3, function()
		sound:Destroy()
	end)

	-- Einmaliger Partikel-Burst in Biomfarbe.
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "BuildBurst"
	emitter.Color = ColorSequence.new(color)
	emitter.LightEmission = 0.6
	emitter.Rate = 0
	emitter.Lifetime = NumberRange.new(0.4, 0.8)
	emitter.Speed = NumberRange.new(6, 12)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Size = NumberSequence.new(0.6)
	emitter.Parent = slotPart
	emitter:Emit(18)
	task.delay(1.5, function()
		emitter:Destroy()
	end)
end

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
		return false, "Ungültiger Slot."
	end

	local def = BiomeConfig.Biomes[biomeIdArg]
	if def == nil then
		return false, "Dieses Biom existiert nicht."
	end
	if profile.lifetimeEnergy < def.unlockAtLifetimeEnergy then
		return false, `{def.displayName} ist noch nicht freigeschaltet (benötigt {def.unlockAtLifetimeEnergy} Gesamt-Energie).`
	end
	if findBiomeAtSlot(profile, slot) ~= nil then
		return false, "Dieser Slot ist bereits belegt."
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

	updateSlotVisual(player, slot, placed, true)
	playSlotJuice(player, slot, def.color, placed.level)
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
		return false, "Ungültiger Slot."
	end

	local placed = findBiomeAtSlot(profile, slot)
	if placed == nil then
		return false, "Auf diesem Slot steht kein Biom."
	end

	local def = BiomeConfig.Biomes[placed.biomeId]
	if def == nil then
		return false, "Dieses Biom ist unbekannt."
	end
	if placed.level >= def.maxLevel then
		return false, `{def.displayName} hat bereits die Maximalstufe erreicht.`
	end

	local cost = BiomeConfig.getUpgradeCost(placed.biomeId, placed.level)
	if not EnergyService.trySpend(player, cost) then
		return false, `Nicht genug Energie ({cost} benötigt).`
	end

	placed.level += 1

	updateSlotVisual(player, slot, placed, true)
	playSlotJuice(player, slot, def.color, placed.level)
	DataService.markDirty(player)
	PlanetService.sendSnapshot(player)
	return true, buildSnapshot(profile)
end

local function onPlayerAdded(player: Player)
	local index = assignPlotIndex(player)
	local origin = computePlotOrigin(index)
	plotOrigins[player] = origin

	-- Basis-Plot (Kern + leere Slots) sofort aufbauen, damit die Welt nicht leer wirkt.
	buildPlot(player, origin)
	updateNameTag(player) -- Standardname; nach dem Profil-Load ggf. eigener Name

	characterConnections[player] = player.CharacterAdded:Connect(function(character)
		task.spawn(teleportToPlot, player, character)
	end)
	local currentCharacter = player.Character
	if currentCharacter ~= nil then
		task.spawn(teleportToPlot, player, currentCharacter)
	end

	-- Auf das geladene Profil warten und die Biome darstellen.
	local profile = DataService.waitForProfile(player)
	if profile == nil then
		return -- Spieler hat den Server bereits verlassen (Aufräumen macht onPlayerRemoving)
	end

	for _, placed in profile.biomes do
		updateSlotVisual(player, placed.slot, placed)
	end
	updateNameTag(player)
	PlanetService.applyCosmetics(player)
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

-- Weltraum-Stimmung: Sternenhimmel, Atmosphäre, dezentes Bloom und
-- Farbkorrektur. Idempotent - vorhandene PlanetForge-Effekte bleiben.
local function setupWorldAmbience()
	local Lighting = game:GetService("Lighting")

	Lighting.ClockTime = 0 -- Mitternacht: Sterne sichtbar
	Lighting.Brightness = 2
	Lighting.Ambient = Color3.fromRGB(28, 32, 52)
	Lighting.OutdoorAmbient = Color3.fromRGB(70, 78, 110)

	if Lighting:FindFirstChild("PlanetForgeSky") == nil then
		local sky = Instance.new("Sky")
		sky.Name = "PlanetForgeSky"
		sky.StarCount = 3000
		sky.SunAngularSize = 8
		sky.MoonAngularSize = 14
		sky.Parent = Lighting
	end

	if Lighting:FindFirstChild("PlanetForgeAtmosphere") == nil then
		local atmosphere = Instance.new("Atmosphere")
		atmosphere.Name = "PlanetForgeAtmosphere"
		atmosphere.Density = 0.25
		atmosphere.Color = Color3.fromRGB(70, 80, 130)
		atmosphere.Decay = Color3.fromRGB(20, 24, 44)
		atmosphere.Glare = 0.2
		atmosphere.Haze = 1.4
		atmosphere.Parent = Lighting
	end

	if Lighting:FindFirstChild("PlanetForgeBloom") == nil then
		local bloom = Instance.new("BloomEffect")
		bloom.Name = "PlanetForgeBloom"
		bloom.Intensity = 0.4
		bloom.Size = 24
		bloom.Threshold = 1.15
		bloom.Parent = Lighting
	end

	if Lighting:FindFirstChild("PlanetForgeColor") == nil then
		local color = Instance.new("ColorCorrectionEffect")
		color.Name = "PlanetForgeColor"
		color.Contrast = 0.05
		color.Saturation = 0.08
		color.TintColor = Color3.fromRGB(235, 240, 255)
		color.Parent = Lighting
	end
end

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

-- Ursprung des Planeten dieses Spielers (nil, falls noch kein Plot vergeben).
function PlanetService.getPlotOrigin(player: Player): CFrame?
	return plotOrigins[player]
end

-- Schickt dem Besitzer einen frischen Planeten-Snapshot (tiefe Kopie).
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
