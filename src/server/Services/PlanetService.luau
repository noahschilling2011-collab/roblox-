--!strict
-- PlanetService: verwaltet die Planeten-Plots der Spieler sowie Bau und
-- Ausbau von Biomen. Der Server ist autoritativ: alle Client-Eingaben
-- (PlaceBiome/UpgradeBiome) werden hier vollständig validiert.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Types = require(ReplicatedStorage.Shared.Types)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local BiomeConfig = require(ReplicatedStorage.Shared.Config.BiomeConfig)

local DataService = require(script.Parent.DataService)
local EnergyService = require(script.Parent.EnergyService)

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
local function updateSlotVisual(player: Player, slotNumber: number, placed: Types.PlacedBiome?)
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
		return
	end

	local def = BiomeConfig.Biomes[placed.biomeId]
	if def == nil then
		warn(`[PlanetForge] Unbekanntes Biom im Profil von {player.Name}: {placed.biomeId}`)
		return
	end
	setSlotAppearance(slotPart, def.color, Enum.Material.Grass, `{def.displayName} (Lv. {placed.level})`)
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

	updateSlotVisual(player, slot, placed)
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

	updateSlotVisual(player, slot, placed)
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

function PlanetService.init()
	planetUpdatedEvent = Remotes.getEvent("PlanetUpdated")

	Remotes.getFunction("PlaceBiome").OnServerInvoke = handlePlaceBiome
	Remotes.getFunction("UpgradeBiome").OnServerInvoke = handleUpgradeBiome

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
