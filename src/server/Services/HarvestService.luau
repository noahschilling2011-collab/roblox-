--!strict
-- HarvestService: physisches Sammeln auf der Insel.
--
-- Spawnt Sammel-Objekte in den freigeschalteten Biom-Zonen (Spawn-Rate und
-- Max-Anzahl aus BiomeConfig.Harvest), prüft SERVERSEITIG per Distanz, ob
-- ein Spieler nah genug ist (Magnet-Radius aus dem Profil) und füllt den
-- Rucksack. Die Verkaufs-Zone (SellPad) wandelt den Rucksack-Inhalt in
-- Energie um. Dem Client wird NIEMALS vertraut - er bekommt nur Events
-- für Effekte (ObjectCollected/BackpackChanged/SoldBackpack).
--
-- Außerdem: BuyUpgrade-Handler für die Insel-Upgrades (Magnet, Rucksack)
-- aus ProgressionConfig.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local BiomeConfig = require(ReplicatedStorage.Shared.Config.BiomeConfig)
local ProgressionConfig = require(ReplicatedStorage.Shared.Config.ProgressionConfig)

local DataService = require(script.Parent.DataService)
local EnergyService = require(script.Parent.EnergyService)
local EquipService = require(script.Parent.EquipService)
local PlanetService = require(script.Parent.PlanetService)

local SELL_COOLDOWN_SECONDS = 1.5 -- Mindestabstand zwischen zwei Verkäufen

-- Ein aktives Sammel-Objekt auf einer Insel.
type ActiveObject = {
	part: BasePart,
	value: number,
	color: Color3,
}

-- Spawn-Zustand pro Spieler und Zone.
type ZoneSpawnState = {
	lastSpawnAt: number,
	objects: { ActiveObject },
}

local zoneStates: { [Player]: { [number]: ZoneSpawnState } } = {}
local lastSellAt: { [Player]: number } = {}

local objectCollectedEvent: RemoteEvent? = nil
local backpackChangedEvent: RemoteEvent? = nil
local soldBackpackEvent: RemoteEvent? = nil
local upgradesUpdatedEvent: RemoteEvent? = nil

local rng = Random.new()

local HarvestService = {}

--------------------------------------------------------------------------
-- Abgeleitete Werte aus dem Profil
--------------------------------------------------------------------------

-- Einsammel-Radius eines Spielers (Basis + Magnet-Upgrades).
function HarvestService.getMagnetRadius(profile: Types.PlayerProfile): number
	return GameConfig.BASE_MAGNET_RADIUS + profile.upgrades.magnet * GameConfig.MAGNET_RADIUS_PER_LEVEL
end

-- Rucksack-Kapazität eines Spielers (Basis + Rucksack-Upgrades).
function HarvestService.getBackpackCapacity(profile: Types.PlayerProfile): number
	return GameConfig.BASE_BACKPACK_CAPACITY + profile.upgrades.backpack * GameConfig.BACKPACK_CAPACITY_PER_LEVEL
end

--------------------------------------------------------------------------
-- Client-Events
--------------------------------------------------------------------------

local function fireBackpackChanged(player: Player, profile: Types.PlayerProfile)
	if backpackChangedEvent ~= nil then
		(backpackChangedEvent :: RemoteEvent):FireClient(
			player,
			profile.backpack.items,
			HarvestService.getBackpackCapacity(profile),
			profile.backpack.value
		)
	end
end

local function fireUpgradesUpdated(player: Player, profile: Types.PlayerProfile)
	if upgradesUpdatedEvent ~= nil then
		(upgradesUpdatedEvent :: RemoteEvent):FireClient(player, {
			magnet = profile.upgrades.magnet,
			backpack = profile.upgrades.backpack,
		})
	end
end

--------------------------------------------------------------------------
-- Objekt-Spawner
--------------------------------------------------------------------------

-- Erzeugt das sichtbare Sammel-Objekt einer Zone.
local function createObjectPart(zonePart: BasePart, harvest: BiomeConfig.HarvestDef): BasePart
	local part = Instance.new("Part")
	part.Name = "Sammelobjekt"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Color = harvest.color

	-- Zufällige Position innerhalb der Zone (mit Rand).
	local halfX = zonePart.Size.X / 2 - 2
	local halfZ = zonePart.Size.Z / 2 - 2
	local offset = Vector3.new(rng:NextNumber(-halfX, halfX), 0, rng:NextNumber(-halfZ, halfZ))
	local basePosition = zonePart.Position + offset + Vector3.new(0, zonePart.Size.Y / 2, 0)

	if harvest.orb then
		-- Schwebender Energie-Orb.
		part.Shape = Enum.PartType.Ball
		part.Size = Vector3.new(1.6, 1.6, 1.6)
		part.Material = Enum.Material.Neon
		part.CFrame = CFrame.new(basePosition + Vector3.new(0, 2.2, 0))
		local light = Instance.new("PointLight")
		light.Color = harvest.color
		light.Range = 8
		light.Brightness = 0.8
		light.Parent = part
	else
		-- Boden-Objekt (Büschel/Frucht/Stein): flachgedrückte Kugel.
		part.Shape = Enum.PartType.Ball
		part.Size = Vector3.new(1.7, 1.2, 1.7)
		part.Material = Enum.Material.Grass
		part.CFrame = CFrame.new(basePosition + Vector3.new(0, 0.5, 0))
			* CFrame.Angles(0, rng:NextNumber() * 2 * math.pi, 0)
	end

	part.Parent = zonePart
	return part
end

-- Räumt zerstörte Parts aus einer Objektliste.
local function pruneObjects(objects: { ActiveObject })
	for index = #objects, 1, -1 do
		if objects[index].part.Parent == nil then
			table.remove(objects, index)
		end
	end
end

-- Ein Spawn-Durchlauf für einen Spieler: pro freigeschalteter Zone maximal
-- ein neues Objekt pro Takt, begrenzt durch maxActive und respawnSeconds.
local function spawnTick(player: Player)
	local profile = DataService.getProfile(player)
	if profile == nil then
		return
	end

	local states = zoneStates[player]
	if states == nil then
		states = {}
		zoneStates[player] = states
	end

	local now = os.clock()
	for _, placed in profile.biomes do
		local harvest = BiomeConfig.Harvest[placed.biomeId]
		if harvest == nil then
			continue
		end

		local state = states[placed.slot]
		if state == nil then
			state = { lastSpawnAt = 0, objects = {} }
			states[placed.slot] = state
		end

		pruneObjects(state.objects)

		local maxActive = BiomeConfig.getMaxActive(placed.biomeId, placed.level)
		if #state.objects >= maxActive then
			continue
		end
		if now - state.lastSpawnAt < harvest.respawnSeconds then
			continue
		end

		local zonePart = PlanetService.getZonePart(player, placed.slot)
		if zonePart == nil then
			continue
		end

		state.lastSpawnAt = now
		table.insert(state.objects, {
			part = createObjectPart(zonePart, harvest),
			value = harvest.value,
			color = harvest.color,
		})
	end
end

--------------------------------------------------------------------------
-- Einsammeln und Verkaufen (serverseitige Distanz-Prüfung)
--------------------------------------------------------------------------

local function collectTick(player: Player)
	local profile = DataService.getProfile(player)
	local states = zoneStates[player]
	if profile == nil or states == nil then
		return
	end

	local character = player.Character
	if character == nil then
		return
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if root == nil or not root:IsA("BasePart") then
		return
	end
	local playerPosition = (root :: BasePart).Position

	-- Verkaufs-Zone: Rucksack zu Energie machen.
	local padPosition = PlanetService.getSellPadPosition(player)
	if
		padPosition ~= nil
		and profile.backpack.items > 0
		and (playerPosition - padPosition).Magnitude <= GameConfig.SELL_PAD_RADIUS
		and os.clock() - (lastSellAt[player] or 0) >= SELL_COOLDOWN_SECONDS
	then
		lastSellAt[player] = os.clock()
		local itemsSold = profile.backpack.items
		local sellValue = profile.backpack.value
		profile.backpack.items = 0
		profile.backpack.value = 0
		profile.stats.sales += 1

		-- Progressions-Multiplikator (Biome/Upgrades/Rebirth/Pets) auf den
		-- Verkaufswert; grantEnergy legt Event-Multiplikatoren obendrauf.
		local multiplier = ProgressionConfig.getTotalMultiplier(
			profile.biomes,
			profile.upgrades,
			profile.rebirths,
			EquipService.getPetBonus(profile)
		)
		local gained = EnergyService.grantEnergy(player, sellValue * multiplier)
		DataService.markDirty(player)
		fireBackpackChanged(player, profile)
		if soldBackpackEvent ~= nil then
			(soldBackpackEvent :: RemoteEvent):FireClient(player, gained or sellValue, itemsSold)
		end
	end

	-- Einsammeln per Näherung (Magnet-Radius).
	local capacity = HarvestService.getBackpackCapacity(profile)
	if profile.backpack.items >= capacity then
		return
	end
	local radius = HarvestService.getMagnetRadius(profile)

	local collectedAny = false
	for _, state in states do
		for index = #state.objects, 1, -1 do
			local object = state.objects[index]
			if object.part.Parent == nil then
				table.remove(state.objects, index)
				continue
			end
			if (object.part.Position - playerPosition).Magnitude > radius then
				continue
			end

			-- Einsammeln.
			table.remove(state.objects, index)
			profile.backpack.items += 1
			profile.backpack.value += object.value
			profile.stats.collected += 1
			collectedAny = true

			if objectCollectedEvent ~= nil then
				(objectCollectedEvent :: RemoteEvent):FireClient(player, object.part.Position, object.value, object.color)
			end
			object.part:Destroy()

			if profile.backpack.items >= capacity then
				break
			end
		end
		if profile.backpack.items >= capacity then
			break
		end
	end

	if collectedAny then
		DataService.markDirty(player)
		fireBackpackChanged(player, profile)
	end
end

--------------------------------------------------------------------------
-- Reset (z. B. nach einer Wiedergeburt)
--------------------------------------------------------------------------

-- Entfernt alle liegenden Sammel-Objekte des Spielers, leert den
-- Spawn-Zustand und meldet den (bereits zurückgesetzten) Rucksack ans HUD.
function HarvestService.resetPlayer(player: Player)
	local states = zoneStates[player]
	if states ~= nil then
		for _, state in states do
			for _, object in state.objects do
				if object.part.Parent ~= nil then
					object.part:Destroy()
				end
			end
		end
	end
	zoneStates[player] = nil

	local profile = DataService.getProfile(player)
	if profile ~= nil then
		fireBackpackChanged(player, profile)
	end
end

--------------------------------------------------------------------------
-- Insel-Upgrades (Magnet, Rucksack)
--------------------------------------------------------------------------

-- Remote-Handler: BuyUpgrade(upgradeId) -> (ok, { level, nextCost } | Fehlermeldung)
local function handleBuyUpgrade(player: Player, upgradeIdArg: unknown): (boolean, any?)
	if typeof(upgradeIdArg) ~= "string" then
		return false, "Ungültiges Upgrade."
	end
	local def = ProgressionConfig.Upgrades[upgradeIdArg]
	if def == nil then
		return false, "Dieses Upgrade existiert nicht."
	end

	local profile = DataService.getProfile(player)
	if profile == nil then
		return false, "Dein Profil ist noch nicht geladen."
	end

	local currentLevel = (profile.upgrades :: { [string]: number })[def.id] or 0
	if currentLevel >= def.maxLevel then
		return false, `{def.displayName} ist bereits auf Maximalstufe.`
	end

	local cost = ProgressionConfig.getUpgradeCost(def.id, currentLevel)
	if not EnergyService.trySpend(player, cost) then
		return false, `Nicht genug Energie ({cost} benötigt).`
	end

	(profile.upgrades :: { [string]: number })[def.id] = currentLevel + 1
	DataService.markDirty(player)
	fireUpgradesUpdated(player, profile)
	fireBackpackChanged(player, profile) -- Kapazität kann sich geändert haben

	local nextCost = if currentLevel + 1 < def.maxLevel
		then ProgressionConfig.getUpgradeCost(def.id, currentLevel + 1)
		else nil
	return true, { level = currentLevel + 1, nextCost = nextCost }
end

--------------------------------------------------------------------------
-- Init
--------------------------------------------------------------------------

function HarvestService.init()
	objectCollectedEvent = Remotes.getEvent("ObjectCollected")
	backpackChangedEvent = Remotes.getEvent("BackpackChanged")
	soldBackpackEvent = Remotes.getEvent("SoldBackpack")
	upgradesUpdatedEvent = Remotes.getEvent("UpgradesUpdated")
	Remotes.getFunction("BuyUpgrade").OnServerInvoke = handleBuyUpgrade

	Players.PlayerAdded:Connect(function(player)
		task.spawn(function()
			local profile = DataService.waitForProfile(player)
			if profile ~= nil then
				fireBackpackChanged(player, profile)
				fireUpgradesUpdated(player, profile)
			end
		end)
	end)

	Players.PlayerRemoving:Connect(function(player)
		zoneStates[player] = nil
		lastSellAt[player] = nil
	end)

	for _, player in Players:GetPlayers() do
		task.spawn(function()
			local profile = DataService.waitForProfile(player)
			if profile ~= nil then
				fireBackpackChanged(player, profile)
				fireUpgradesUpdated(player, profile)
			end
		end)
	end

	-- Spawner-Schleife.
	task.spawn(function()
		while true do
			task.wait(GameConfig.SPAWN_TICK_SECONDS)
			for _, player in Players:GetPlayers() do
				spawnTick(player)
			end
		end
	end)

	-- Sammel-/Verkaufs-Schleife (serverseitige Distanz-Prüfung).
	task.spawn(function()
		while true do
			task.wait(GameConfig.HARVEST_TICK_SECONDS)
			for _, player in Players:GetPlayers() do
				collectTick(player)
			end
		end
	end)
end

return HarvestService
