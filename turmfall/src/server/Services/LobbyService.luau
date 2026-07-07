--!strict
-- LobbyService: die Lobby-Insel - der Hangout zwischen den Runden.
--
-- Jedes große Roblox-Rundenspiel hat eine echte Lobby, in der zwischen
-- den Runden etwas zu TUN ist. Unsere schwebt neben der Arena (man sieht
-- den Turm von hier!) und bietet:
--   🏆 Denkmal mit Wochen-/Allzeit-Rekord (RecordService schreibt drauf)
--   🛒 Shop-Stand - wer aufs blaue Pad läuft, öffnet den Shop (Client)
--   🟢 Sprungpad - katapultiert dich in die Luft (einfach weil es Spaß macht)
--   🪂 Trümmer-Parkour - schwebende Plattformen; der Gipfel gibt einmal
--      pro Session +PARKOUR_REWARD_DEBRIS Trümmer (serverseitig geprüft)
--
-- Der Spawn liegt HIER; der RoundService teleportiert zur Bauphase in die
-- Arena und nach der Wertung zurück. Die Lobby wird EINMAL beim Start
-- gebaut (geteilt, kein Per-Spieler-Aufbau).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Network = require(Shared.Network)
local GameConfig = require(Shared.Config.GameConfig)

local DataService = require(script.Parent.DataService)
local SkinService = require(script.Parent.SkinService)

local PLAZA_COLOR = Color3.fromRGB(126, 130, 142)
local ACCENT_GOLD = Color3.fromRGB(235, 186, 60)
local WOOD_COLOR = Color3.fromRGB(133, 100, 64)

local LobbyService = {}

local monumentLabel: TextLabel? = nil

-- Parkour-Belohnung: einmal pro Session und Spieler.
local parkourClaimed: { [Player]: boolean } = {}

local notificationEvent: RemoteEvent? = nil

local function lobbyOrigin(): Vector3
	return Vector3.new(GameConfig.LOBBY_OFFSET_X, GameConfig.LOBBY_Y, 0)
end

-- Oberkante der Lobby-Plattform.
local function lobbyTopY(): number
	return GameConfig.LOBBY_Y + 1
end

local function newPart(parent: Instance, name: string, collide: boolean): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = collide
	part.CanQuery = false
	part.CanTouch = false
	part.Parent = parent
	return part
end

local function addLabel(parent: BasePart, text: string, offsetY: number, color: Color3?)
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(240, 48)
	billboard.StudsOffset = Vector3.new(0, offsetY, 0)
	billboard.MaxDistance = 160
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = color or Color3.fromRGB(235, 238, 245)
	label.TextStrokeTransparency = 0.4
	label.Text = text
	label.Parent = billboard
	billboard.Parent = parent
end

--------------------------------------------------------------------------
-- Aufbau
--------------------------------------------------------------------------

local function buildPlaza(folder: Folder)
	local origin = lobbyOrigin()

	-- Bodenplatte mit Gold-Rand und Mittelkreis.
	local floor = newPart(folder, "LobbyBoden", true)
	floor.Size = Vector3.new(GameConfig.LOBBY_SIZE, 2, GameConfig.LOBBY_SIZE)
	floor.Position = origin
	floor.Material = Enum.Material.Slate
	floor.Color = PLAZA_COLOR

	local ring = newPart(folder, "LobbyMitte", false)
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.2, 14, 14)
	ring.CFrame = CFrame.new(origin + Vector3.new(0, 1.1, 0)) * CFrame.Angles(0, 0, math.rad(90))
	ring.Material = Enum.Material.Neon
	ring.Color = ACCENT_GOLD
	ring.Transparency = 0.5

	for _, side in { -1, 1 } do
		local trimX = newPart(folder, "LobbyKante", false)
		trimX.Size = Vector3.new(GameConfig.LOBBY_SIZE, 0.4, 0.8)
		trimX.Position = origin + Vector3.new(0, 1.1, side * (GameConfig.LOBBY_SIZE / 2 - 0.4))
		trimX.Material = Enum.Material.Neon
		trimX.Color = ACCENT_GOLD
		trimX.Transparency = 0.35
		local trimZ = newPart(folder, "LobbyKante", false)
		trimZ.Size = Vector3.new(0.8, 0.4, GameConfig.LOBBY_SIZE)
		trimZ.Position = origin + Vector3.new(side * (GameConfig.LOBBY_SIZE / 2 - 0.4), 1.1, 0)
		trimZ.Material = Enum.Material.Neon
		trimZ.Color = ACCENT_GOLD
		trimZ.Transparency = 0.35
	end

	-- Vier Laternen in den Ecken.
	for index, corner in
		{
			Vector3.new(-1, 0, -1),
			Vector3.new(1, 0, -1),
			Vector3.new(-1, 0, 1),
			Vector3.new(1, 0, 1),
		}
	do
		local offset = corner * (GameConfig.LOBBY_SIZE / 2 - 5)
		local post = newPart(folder, `Laterne_{index}`, true)
		post.Size = Vector3.new(0.8, 7, 0.8)
		post.Position = origin + offset + Vector3.new(0, 4.5, 0)
		post.Material = Enum.Material.Metal
		post.Color = Color3.fromRGB(60, 62, 74)
		local lamp = newPart(folder, `LaternenLicht_{index}`, false)
		lamp.Shape = Enum.PartType.Ball
		lamp.Size = Vector3.new(1.6, 1.6, 1.6)
		lamp.Position = origin + offset + Vector3.new(0, 8.5, 0)
		lamp.Material = Enum.Material.Neon
		lamp.Color = Color3.fromRGB(255, 220, 130)
		local light = Instance.new("PointLight")
		light.Color = lamp.Color
		light.Range = 18
		light.Brightness = 0.9
		light.Parent = lamp
	end

	-- Hinweisschild Richtung Arena (die man von hier sieht).
	local sign = newPart(folder, "ArenaSchild", false)
	sign.Size = Vector3.new(0.4, 3, 6)
	sign.Position = origin + Vector3.new(-GameConfig.LOBBY_SIZE / 2 + 2, 4, 0)
	sign.Material = Enum.Material.WoodPlanks
	sign.Color = WOOD_COLOR
	addLabel(sign, "⬅️ ARENA – gleich geht's los!", 2.5, ACCENT_GOLD)

	-- Spawn auf der Lobby (vorhandenen SpawnLocation umziehen oder anlegen).
	local spawnLocation = Workspace:FindFirstChildWhichIsA("SpawnLocation", true)
	if spawnLocation == nil then
		spawnLocation = Instance.new("SpawnLocation")
		spawnLocation.Name = "LobbySpawn"
		spawnLocation.Anchored = true
		spawnLocation.Parent = folder
	end
	local spawnPad = spawnLocation :: SpawnLocation
	spawnPad.Size = Vector3.new(10, 0.4, 10)
	spawnPad.CFrame = CFrame.new(origin + Vector3.new(0, 1.4, GameConfig.LOBBY_SIZE / 2 - 8))
		* CFrame.Angles(0, math.rad(180), 0)
	spawnPad.Color = Color3.fromRGB(60, 62, 74)
	spawnPad.Duration = 0
end

local function buildMonument(folder: Folder)
	local origin = lobbyOrigin()
	local base = origin + Vector3.new(GameConfig.LOBBY_SIZE / 2 - 8, 0, -GameConfig.LOBBY_SIZE / 2 + 8)

	local pedestal = newPart(folder, "DenkmalSockel", true)
	pedestal.Shape = Enum.PartType.Cylinder
	pedestal.Size = Vector3.new(3, 8, 8)
	pedestal.CFrame = CFrame.new(base + Vector3.new(0, 2.5, 0)) * CFrame.Angles(0, 0, math.rad(90))
	pedestal.Material = Enum.Material.Marble
	pedestal.Color = Color3.fromRGB(210, 206, 196)

	local trophy = newPart(folder, "DenkmalTrophaee", false)
	trophy.Size = Vector3.new(2, 2.6, 2)
	trophy.CFrame = CFrame.new(base + Vector3.new(0, 5.4, 0)) * CFrame.Angles(0, math.rad(45), 0)
	trophy.Material = Enum.Material.Metal
	trophy.Color = ACCENT_GOLD
	trophy.Reflectance = 0.3

	local plaque = Instance.new("BillboardGui")
	plaque.Name = "DenkmalSchild"
	plaque.Size = UDim2.fromOffset(240, 66)
	plaque.StudsOffset = Vector3.new(0, 3.5, 0)
	plaque.MaxDistance = 140
	local plaqueText = Instance.new("TextLabel")
	plaqueText.Size = UDim2.fromScale(1, 1)
	plaqueText.BackgroundTransparency = 1
	plaqueText.Font = Enum.Font.GothamBold
	plaqueText.TextScaled = true
	plaqueText.TextColor3 = ACCENT_GOLD
	plaqueText.TextStrokeTransparency = 0.4
	plaqueText.Text = "🏆 Höchster Turm der Woche\n– bald verewigt –"
	plaqueText.Parent = plaque
	plaque.Parent = trophy
	monumentLabel = plaqueText
end

local function buildShopStand(folder: Folder)
	local origin = lobbyOrigin()
	local base = origin + Vector3.new(-GameConfig.LOBBY_SIZE / 2 + 9, 0, GameConfig.LOBBY_SIZE / 2 - 10)

	-- Marktstand: Theke, zwei Pfosten, Dach.
	local counter = newPart(folder, "ShopTheke", true)
	counter.Size = Vector3.new(7, 3, 2)
	counter.Position = base + Vector3.new(0, 2.5, 0)
	counter.Material = Enum.Material.WoodPlanks
	counter.Color = WOOD_COLOR

	for _, side in { -1, 1 } do
		local post = newPart(folder, "ShopPfosten", false)
		post.Size = Vector3.new(0.6, 6, 0.6)
		post.Position = base + Vector3.new(side * 3.2, 4, 0)
		post.Material = Enum.Material.Wood
		post.Color = Color3.fromRGB(96, 72, 48)
	end

	local roof = newPart(folder, "ShopDach", false)
	roof.Size = Vector3.new(8.4, 0.5, 4)
	roof.Position = base + Vector3.new(0, 7.2, 0)
	roof.Material = Enum.Material.Fabric
	roof.Color = Color3.fromRGB(80, 150, 240)
	addLabel(roof, "🛒 Shop", 1.6, Color3.fromRGB(120, 190, 255))

	-- Blaues Pad davor: Betreten öffnet den Shop (macht der Client per Nähe).
	local pad = newPart(folder, "ShopPad", false)
	pad.Shape = Enum.PartType.Cylinder
	pad.Size = Vector3.new(0.3, 8, 8)
	pad.CFrame = CFrame.new(base + Vector3.new(0, 1.2, 4.5)) * CFrame.Angles(0, 0, math.rad(90))
	pad.Material = Enum.Material.Neon
	pad.Color = Color3.fromRGB(80, 150, 240)
	pad.Transparency = 0.4
end

local function buildJumpPad(folder: Folder)
	local origin = lobbyOrigin()
	local pad = newPart(folder, "Sprungpad", true)
	pad.Shape = Enum.PartType.Cylinder
	pad.Size = Vector3.new(0.6, 6, 6)
	pad.CFrame = CFrame.new(origin + Vector3.new(0, 1.4, -GameConfig.LOBBY_SIZE / 2 + 9))
		* CFrame.Angles(0, 0, math.rad(90))
	pad.Material = Enum.Material.Neon
	pad.Color = Color3.fromRGB(90, 220, 120)
	pad.CanTouch = true
	addLabel(pad, "🟢 Sprungpad", 2, Color3.fromRGB(120, 240, 150))

	local cooldown: { [Player]: number } = {}
	pad.Touched:Connect(function(hit: BasePart)
		local character = hit.Parent
		local player = if character ~= nil then Players:GetPlayerFromCharacter(character) else nil
		if player == nil or character == nil then
			return
		end
		if os.clock() - (cooldown[player] or 0) < 1 then
			return
		end
		cooldown[player] = os.clock()
		local root = character:FindFirstChild("HumanoidRootPart")
		if root ~= nil and root:IsA("BasePart") then
			(root :: BasePart).AssemblyLinearVelocity = Vector3.new(0, GameConfig.JUMP_PAD_SPEED, 0)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		cooldown[player] = nil
	end)
end

-- Trümmer-Parkour: Spiralaufstieg aus schwebenden Plattformen; der
-- goldene Gipfel gibt einmal pro Session Trümmer (serverseitig geprüft).
local function buildParkour(folder: Folder)
	local origin = lobbyOrigin()
	local center = origin + Vector3.new(0, 0, -GameConfig.LOBBY_SIZE / 2 - 16)

	local steps = 8
	for index = 1, steps do
		local angle = index * math.rad(46)
		local radius = 11
		local platform = newPart(folder, `Parkour_{index}`, true)
		platform.Size = Vector3.new(4.5, 1, 4.5)
		platform.Position = center + Vector3.new(math.cos(angle) * radius, 2 + index * 4.4, math.sin(angle) * radius)
		platform.Material = Enum.Material.Slate
		platform.Color = PLAZA_COLOR
	end

	-- Gipfel-Plattform mit Belohnungs-Kristall.
	local summit = newPart(folder, "ParkourGipfel", true)
	summit.Size = Vector3.new(6, 1, 6)
	summit.Position = center + Vector3.new(0, 2 + (steps + 1) * 4.4, 0)
	summit.Material = Enum.Material.Marble
	summit.Color = Color3.fromRGB(226, 222, 212)

	local crystal = newPart(folder, "ParkourKristall", false)
	crystal.Size = Vector3.new(1.8, 3, 1.8)
	crystal.Position = summit.Position + Vector3.new(0, 2.6, 0)
	crystal.Material = Enum.Material.Neon
	crystal.Color = ACCENT_GOLD
	crystal.CanTouch = true
	addLabel(crystal, `🪂 Parkour-Gipfel: +{GameConfig.PARKOUR_REWARD_DEBRIS} 🧱`, 2.6, ACCENT_GOLD)

	crystal.Touched:Connect(function(hit: BasePart)
		local character = hit.Parent
		local player = if character ~= nil then Players:GetPlayerFromCharacter(character) else nil
		if player == nil then
			return
		end
		if parkourClaimed[player] == true then
			return
		end
		local profile = DataService.getProfile(player)
		if profile == nil or not DataService.isSaveable(player) then
			return
		end
		parkourClaimed[player] = true
		profile.truemmer += GameConfig.PARKOUR_REWARD_DEBRIS
		DataService.markDirty(player)
		SkinService.refresh(player)
		if notificationEvent ~= nil then
			(notificationEvent :: RemoteEvent):FireClient(
				player,
				`🪂 Parkour geschafft: +{GameConfig.PARKOUR_REWARD_DEBRIS} 🧱 Trümmer!`,
				"success"
			)
		end
	end)
end

--------------------------------------------------------------------------
-- Öffentliche API
--------------------------------------------------------------------------

-- Rekord-Text aufs Denkmal schreiben (RecordService).
function LobbyService.setMonumentText(text: string)
	if monumentLabel ~= nil then
		(monumentLabel :: TextLabel).Text = text
	end
end

-- Teleportiert einen Spieler in die Lobby (Kreis um die Mitte).
function LobbyService.teleportToLobby(player: Player, index: number, totalPlayers: number)
	local character = player.Character
	if character == nil or character:FindFirstChild("HumanoidRootPart") == nil then
		return
	end
	local origin = lobbyOrigin()
	local angle = (index / math.max(totalPlayers, 1)) * 2 * math.pi
	local position = Vector3.new(origin.X + math.cos(angle) * 10, lobbyTopY() + 3, origin.Z + math.sin(angle) * 10)
	character:PivotTo(CFrame.lookAt(position, Vector3.new(origin.X, lobbyTopY() + 3, origin.Z)))
end

function LobbyService.init()
	notificationEvent = Network.getEvent("Notification")

	local folder = Instance.new("Folder")
	folder.Name = "Lobby"

	buildPlaza(folder)
	buildMonument(folder)
	buildShopStand(folder)
	buildJumpPad(folder)
	buildParkour(folder)

	folder.Parent = Workspace

	Players.PlayerRemoving:Connect(function(player)
		parkourClaimed[player] = nil
	end)
end

return LobbyService
