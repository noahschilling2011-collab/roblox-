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
local TweenService = game:GetService("TweenService")

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

-- Performance: außerhalb dieses Radius um die eigene Insel (Villa, Besuch
-- bei anderen) wird die Sammel-/Verkaufs-Prüfung komplett übersprungen.
local ISLAND_ACTIVITY_RADIUS = 110

-- Glut-Optik für Vulkan-Objekte, solange sie zu heiß zum Anfassen sind.
local HOT_COLOR = Color3.fromRGB(255, 176, 70)

-- Gold-Optik für die seltenen Glücks-Objekte.
local GOLDEN_COLOR = Color3.fromRGB(255, 208, 70)

-- Ein aktives Sammel-Objekt auf einer Insel.
type ActiveObject = {
	part: BasePart,
	value: number,
	color: Color3,
	meltAt: number?, -- Eiswelt: os.clock()-Zeitpunkt, an dem es schmilzt
	hotUntil: number?, -- Vulkan: bis dahin glühend heiß (nicht sammelbar)
	golden: boolean?, -- seltenes Gold-Objekt (mehrfacher Wert)
}

-- Sammel-Kette pro Spieler: schnelles Sammeln stapelt einen Wert-Bonus.
type ComboState = {
	count: number,
	lastCollectAt: number,
}

-- Spawn-Zustand pro Spieler und Zone.
type ZoneSpawnState = {
	lastSpawnAt: number,
	objects: { ActiveObject },
}

local zoneStates: { [Player]: { [number]: ZoneSpawnState } } = {}
local lastSellAt: { [Player]: number } = {}
local combos: { [Player]: ComboState } = {}

local objectCollectedEvent: RemoteEvent? = nil
local backpackChangedEvent: RemoteEvent? = nil
local soldBackpackEvent: RemoteEvent? = nil
local upgradesUpdatedEvent: RemoteEvent? = nil

local rng = Random.new()

local HarvestService = {}

-- Auto-Harvest-Gamepass (Hook): der MonetizationService ersetzt diese
-- Funktion beim Start (vermeidet eine zyklische Service-Abhängigkeit).
HarvestService.hasAutoHarvest = function(_player: Player): boolean
	return false
end

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

	-- Vulkan-Mechanik: frisch gespawnte Glutsteine glühen sichtbar und
	-- sind erst nach dem Abkühlen sammelbar (Timing statt Schaden).
	if harvest.hotSeconds ~= nil then
		part.Material = Enum.Material.Neon
		part.Color = HOT_COLOR
		local heat = Instance.new("PointLight")
		heat.Name = "HeatLight"
		heat.Color = HOT_COLOR
		heat.Range = 7
		heat.Brightness = 1
		heat.Parent = part
	end

	part.Parent = zonePart
	return part
end

-- Verwandelt ein frisch gespawntes Objekt in ein seltenes GOLD-Objekt:
-- deutlich größer Wert, goldene Neon-Optik, Funkeln und Licht.
local function makeGolden(part: BasePart)
	part.Color = GOLDEN_COLOR
	part.Material = Enum.Material.Neon
	part.Size = part.Size * 1.25

	local light = Instance.new("PointLight")
	light.Name = "GoldLight"
	light.Color = GOLDEN_COLOR
	light.Range = 10
	light.Brightness = 1.2
	light.Parent = part

	local sparkle = Instance.new("ParticleEmitter")
	sparkle.Name = "GoldSparkle"
	sparkle.Color = ColorSequence.new(GOLDEN_COLOR, Color3.new(1, 1, 1))
	sparkle.LightEmission = 1
	sparkle.Rate = 6
	sparkle.Lifetime = NumberRange.new(0.8, 1.4)
	sparkle.Speed = NumberRange.new(1.5, 3)
	sparkle.SpreadAngle = Vector2.new(180, 180)
	sparkle.Size = NumberSequence.new(0.35)
	sparkle.Parent = part
end

-- Aktuelle Ketten-Stufe eines Spielers; zählt weiter, wenn der letzte Fund
-- innerhalb des Zeitfensters lag, sonst beginnt die Kette neu bei 1.
local function bumpCombo(player: Player, now: number): number
	local state = combos[player]
	if state == nil then
		state = { count = 0, lastCollectAt = 0 }
		combos[player] = state
	end
	if now - state.lastCollectAt <= GameConfig.COMBO_WINDOW_SECONDS then
		state.count = math.min(state.count + 1, GameConfig.COMBO_MAX_STACKS)
	else
		state.count = 1
	end
	state.lastCollectAt = now
	return state.count
end

-- Biom-Spezialmechaniken pro Takt: Glutsteine kühlen sichtbar ab,
-- Eis-Objekte schmelzen nach ihrer Lebenszeit (kurzes Schrumpfen).
local function updateSpecialObjects(state: ZoneSpawnState, harvest: BiomeConfig.HarvestDef, now: number)
	for index = #state.objects, 1, -1 do
		local object = state.objects[index]
		if object.part.Parent == nil then
			continue -- räumt pruneObjects auf
		end

		if object.hotUntil ~= nil and now >= object.hotUntil then
			object.hotUntil = nil
			-- Goldene Glutsteine behalten nach dem Abkühlen ihre Gold-Optik.
			if object.golden == true then
				object.part.Color = GOLDEN_COLOR
			else
				object.part.Material = Enum.Material.Slate
				object.part.Color = harvest.color
			end
			local heat = object.part:FindFirstChild("HeatLight")
			if heat ~= nil then
				heat:Destroy()
			end
		end

		if object.meltAt ~= nil and now >= object.meltAt then
			table.remove(state.objects, index)
			local part = object.part
			local tween = TweenService:Create(
				part,
				TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{ Size = part.Size * 0.05, Transparency = 1 }
			)
			tween:Play()
			tween.Completed:Once(function()
				part:Destroy()
			end)
		end
	end
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
		updateSpecialObjects(state, harvest, now)

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
		local part = createObjectPart(zonePart, harvest)

		-- Glücksmoment: seltene GOLD-Objekte mit vielfachem Wert.
		local golden = rng:NextNumber() < GameConfig.GOLDEN_OBJECT_CHANCE
		if golden then
			makeGolden(part)
		end

		table.insert(state.objects, {
			part = part,
			value = if golden then harvest.value * GameConfig.GOLDEN_OBJECT_VALUE_FACTOR else harvest.value,
			color = if golden then GOLDEN_COLOR else harvest.color,
			meltAt = if harvest.meltSeconds ~= nil then now + harvest.meltSeconds :: number else nil,
			hotUntil = if harvest.hotSeconds ~= nil then now + harvest.hotSeconds :: number else nil,
			golden = golden,
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

	-- Performance: Wer gar nicht auf seiner Insel ist (Spawn-Villa, Besuch
	-- bei anderen), braucht weder Verkaufs- noch Distanz-Prüfungen.
	local plotOrigin = PlanetService.getPlotOrigin(player)
	if plotOrigin == nil or (playerPosition - plotOrigin.Position).Magnitude > ISLAND_ACTIVITY_RADIUS then
		return
	end

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

		-- Kritischer Verkauf: seltener Jackpot-Moment mit doppeltem Ertrag.
		local critical = rng:NextNumber() < GameConfig.CRIT_SALE_CHANCE
		if critical then
			sellValue *= GameConfig.CRIT_SALE_FACTOR
		end

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
			(soldBackpackEvent :: RemoteEvent):FireClient(player, gained or sellValue, itemsSold, critical)
		end
	end

	-- Einsammeln per Näherung (Magnet-Radius).
	local capacity = HarvestService.getBackpackCapacity(profile)
	if profile.backpack.items >= capacity then
		return
	end
	local radius = HarvestService.getMagnetRadius(profile)

	local collectedAny = false
	local now = os.clock()
	for _, state in states do
		for index = #state.objects, 1, -1 do
			local object = state.objects[index]
			if object.part.Parent == nil then
				table.remove(state.objects, index)
				continue
			end
			-- Vulkan-Mechanik: glühende Objekte sind noch nicht sammelbar.
			if object.hotUntil ~= nil and now < object.hotUntil then
				continue
			end
			if (object.part.Position - playerPosition).Magnitude > radius then
				continue
			end

			-- Einsammeln; die Sammel-Kette erhöht den Wert (schnell = mehr).
			local comboCount = bumpCombo(player, now)
			local comboBonus = 1 + comboCount * GameConfig.COMBO_BONUS_PER_STACK
			local value = math.max(math.floor(object.value * comboBonus), object.value)

			table.remove(state.objects, index)
			profile.backpack.items += 1
			profile.backpack.value += value
			profile.stats.collected += 1
			collectedAny = true

			if objectCollectedEvent ~= nil then
				(objectCollectedEvent :: RemoteEvent):FireClient(
					player,
					object.part.Position,
					value,
					object.color,
					comboCount,
					object.golden == true
				)
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

-- Auto-Harvest (Gamepass): sammelt genau EIN liegendes Objekt ein, egal
-- wie weit es entfernt ist. Verkaufen am SellPad bleibt bewusst Handarbeit,
-- damit der Besitzer trotzdem aktiv bleiben muss.
local function autoCollectOne(player: Player)
	local profile = DataService.getProfile(player)
	local states = zoneStates[player]
	if profile == nil or states == nil then
		return
	end
	if profile.backpack.items >= HarvestService.getBackpackCapacity(profile) then
		return
	end

	local now = os.clock()
	for _, state in states do
		for index = #state.objects, 1, -1 do
			local object = state.objects[index]
			if object.part.Parent == nil then
				table.remove(state.objects, index)
				continue
			end
			-- Auch der Auto-Sammler muss abgekühlte Glutsteine abwarten.
			if object.hotUntil ~= nil and now < object.hotUntil then
				continue
			end

			table.remove(state.objects, index)
			profile.backpack.items += 1
			profile.backpack.value += object.value
			profile.stats.collected += 1

			if objectCollectedEvent ~= nil then
				-- Ohne Ketten-Stufe (der Auto-Sammler ist passiv), aber mit Gold-Flag.
				(objectCollectedEvent :: RemoteEvent):FireClient(
					player,
					object.part.Position,
					object.value,
					object.color,
					nil,
					object.golden == true
				)
			end
			object.part:Destroy()

			DataService.markDirty(player)
			fireBackpackChanged(player, profile)
			return -- pro Takt nur ein Objekt
		end
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
		combos[player] = nil
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

	-- Auto-Harvest-Schleife (nur Gamepass-Besitzer, 1 Objekt pro Takt).
	task.spawn(function()
		while true do
			task.wait(GameConfig.AUTO_HARVEST_INTERVAL_SECONDS)
			for _, player in Players:GetPlayers() do
				if HarvestService.hasAutoHarvest(player) then
					autoCollectOne(player)
				end
			end
		end
	end)
end

return HarvestService
