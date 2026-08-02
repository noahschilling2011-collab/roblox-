-- ServerScriptService/Systems/VehicleService.luau
--!strict
-- GHOSTNET :: Fahrzeugbesitz, Garage und Haendler.
--
-- BESITZ LIEGT IM PROFIL, NICHT IN DER WELT. Ein Fahrzeug in der Stadt ist
-- nur eine Ausleihe: es verschwindet nach Config.Vehicle.IdleDespawn ohne
-- Fahrer, und beim naechsten Join parkt man es neu aus.
--
-- NUR EIN FAHRZEUG GLEICHZEITIG AUSGEPARKT. Ohne diese Grenze stellt jeder
-- Spieler zehn Autos in die Stadt und der Server erstickt.
--
-- PREISE HOLT DER SERVER SELBST. Der Client schickt nur { Action, ClassId }.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Geometry = require(ReplicatedStorage.Shared.Geometry)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Types = require(ReplicatedStorage.Shared.Types)
local Vehicles = require(ReplicatedStorage.Shared.Vehicles)

local EconomyService = require(script.Parent.EconomyService)
local RoadNetwork = require(script.Parent.RoadNetwork)
local RateLimiter = require(script.Parent.RateLimiter)
local SaveService = require(script.Parent.SaveService)
local TimeService = require(script.Parent.TimeService)
local VehicleChassis = require(script.Parent.VehicleChassis)

local VehicleService = {}

local spawned: { [Player]: Model } = {}

local COLOURS: { [string]: Color3 } = {
	Schwarz = Color3.fromRGB(22, 23, 26),
	Anthrazit = Color3.fromRGB(58, 62, 70),
	Weiss = Color3.fromRGB(214, 218, 224),
	Rot = Color3.fromRGB(168, 34, 48),
	Cyan = Color3.fromRGB(0, 168, 190),
	Gold = Color3.fromRGB(186, 150, 62),
}

local function colourOf(name: string): Color3
	return COLOURS[name] or COLOURS.Schwarz
end

-- Oeffnungszeiten. Bei dauerhaftem Tag gibt es keinen Abend mehr, an dem
-- zugesperrt werden koennte - der Haendler hat dann immer auf. Schaltet man
-- Config.World.PermanentDay wieder aus, gelten sofort wieder die Zeiten.
local function dealerOpen(): boolean
	if Config.World.PermanentDay then
		return true
	end
	local clock = TimeService.GetClock()
	return clock >= Config.Dealer.OpenHour and clock < Config.Dealer.CloseHour
end

--==========================================================================
-- Lesen
--==========================================================================

function VehicleService.Owns(player: Player, classId: string): boolean
	local profile = SaveService.Get(player)
	if not profile then
		return false
	end
	for _, entry in profile.Garage do
		if entry.ClassId == classId then
			return true
		end
	end
	return false
end

-- Zusaetzlicher Darknet-Lagerplatz durch das gerade ausgeparkte Fahrzeug.
-- Genau das ist der mechanische Grund fuer den Transporter.
function VehicleService.StashBonus(player: Player): number
	local model = spawned[player]
	if not model or not model.Parent then
		return 0
	end
	local classId = model:GetAttribute("ClassId")
	if typeof(classId) ~= "string" then
		return 0
	end
	return Vehicles.StashBonus(classId)
end

function VehicleService.Sync(player: Player)
	if not player.Parent then
		return
	end
	local profile = SaveService.Get(player)
	local owned: { { [string]: any } } = {}
	if profile then
		for _, entry in profile.Garage do
			local class = Vehicles.Get(entry.ClassId)
			table.insert(owned, {
				ClassId = entry.ClassId,
				Name = if class then class.Name else entry.ClassId,
				Colour = entry.Colour,
			})
		end
	end

	local current = spawned[player]
	Remotes.GarageSync:FireClient(player, {
		Owned = owned,
		Spawned = if current and current.Parent then current:GetAttribute("ClassId") else "",
		-- Damit die Karte einen orangenen Marker setzen kann: wo steht mein Auto?
		SpawnedAt = if current and current.Parent then current:GetPivot().Position else nil,
		CallFee = Config.Vehicle.CallFee,
		MaxSpawned = Config.Vehicle.MaxSpawned,
		DealerOpen = dealerOpen(),
		Colours = Config.Dealer.ColourOptions,
		RepaintCost = Config.Dealer.RepaintCost,
	})
end

--==========================================================================
-- Ausparken
--==========================================================================

local function nearestSpawnPoint(player: Player): (BasePart?, number)
	local position = Geometry.AlivePosition(player)
	if not position then
		return nil, math.huge
	end
	local best: BasePart? = nil
	local bestDistance = math.huge
	for _, inst in CollectionService:GetTagged(Config.VehicleSpawnTag) do
		if inst:IsA("BasePart") and inst:IsDescendantOf(workspace) then
			local distance = Geometry.SurfaceDistance(inst, position)
			if distance < bestDistance then
				best, bestDistance = inst, distance
			end
		end
	end
	return best, bestDistance
end

function VehicleService.Despawn(player: Player)
	local model = spawned[player]
	spawned[player] = nil
	if model and model.Parent then
		VehicleChassis.Despawn(model)
	end
end

local function result(ok: boolean, reason: string, extra: { [string]: any }?): { [string]: any }
	local payload: { [string]: any } = { Ok = ok, Reason = reason }
	if extra then
		for key, value in extra do
			payload[key] = value
		end
	end
	return payload
end

local function spawnVehicle(player: Player, classId: string): { [string]: any }
	local profile = SaveService.Get(player)
	if not profile then
		return result(false, "LOADING")
	end
	if not VehicleService.Owns(player, classId) then
		return result(false, "NOT_OWNED")
	end

	local point, distance = nearestSpawnPoint(player)
	if not point then
		return result(false, "NO_SPAWN")
	end
	if distance > Config.Vehicle.SpawnRange then
		return result(false, "TOO_FAR", { Distance = math.floor(distance), Range = Config.Vehicle.SpawnRange })
	end

	-- Nur eins gleichzeitig: das alte weg, bevor das neue kommt.
	VehicleService.Despawn(player)

	local colour = "Schwarz"
	for _, entry in profile.Garage do
		if entry.ClassId == classId then
			colour = entry.Colour
			break
		end
	end

	local cframe = point.CFrame * CFrame.new(0, point.Size.Y * 0.5 + 4, 0)
	local model = VehicleChassis.Build(classId, cframe, colourOf(colour))
	if not model then
		return result(false, "INTERNAL")
	end
	model:SetAttribute("OwnerUserId", player.UserId)
	spawned[player] = model

	VehicleService.Sync(player)
	return result(true, "OK", { ClassId = classId })
end

--==========================================================================
-- Kaufen und Lackieren
--==========================================================================

local function nearDealer(player: Player): boolean
	local position = Geometry.AlivePosition(player)
	if not position then
		return false
	end
	for _, inst in CollectionService:GetTagged(Config.DealerTag) do
		if inst:IsA("BasePart") and inst:IsDescendantOf(workspace) then
			if Geometry.SurfaceDistance(inst, position) <= Config.Vehicle.SpawnRange then
				return true
			end
		end
	end
	return false
end

local function buyVehicle(player: Player, classId: string, colour: string): { [string]: any }
	local profile = SaveService.Get(player)
	if not profile then
		return result(false, "LOADING")
	end
	local class = Vehicles.Get(classId)
	if not class then
		return result(false, "UNKNOWN_CLASS")
	end
	if not nearDealer(player) then
		return result(false, "NO_DEALER")
	end
	if not dealerOpen() then
		return result(false, "CLOSED", { Open = Config.Dealer.OpenHour, Close = Config.Dealer.CloseHour })
	end
	if VehicleService.Owns(player, classId) then
		return result(false, "ALREADY_OWNED")
	end

	-- Preis kommt aus den Daten, nicht aus dem Paket.
	local price = class.Price
	if profile.Banked < price then
		return result(false, "FUNDS", { Cost = price, Missing = price - profile.Banked })
	end
	if not EconomyService.SpendBanked(player, price) then
		return result(false, "FUNDS", { Cost = price })
	end

	table.insert(profile.Garage, {
		ClassId = classId,
		Colour = if COLOURS[colour] then colour else "Schwarz",
	})

	EconomyService.Sync(player)
	SaveService.RequestSave(player)
	VehicleService.Sync(player)

	print(("[GHOSTNET] %s kauft %s fuer %d CRY."):format(player.Name, classId, price))
	return result(true, "OK", { ClassId = classId, Cost = price })
end

local function repaint(player: Player, classId: string, colour: string): { [string]: any }
	local profile = SaveService.Get(player)
	if not profile then
		return result(false, "LOADING")
	end
	if not COLOURS[colour] then
		return result(false, "BAD_PAYLOAD")
	end
	if not nearDealer(player) then
		return result(false, "NO_DEALER")
	end

	local entry: Types.OwnedVehicle? = nil
	for _, owned in profile.Garage do
		if owned.ClassId == classId then
			entry = owned
			break
		end
	end
	if not entry then
		return result(false, "NOT_OWNED")
	end

	local cost = Config.Dealer.RepaintCost
	if profile.Banked < cost then
		return result(false, "FUNDS", { Cost = cost, Missing = cost - profile.Banked })
	end
	if not EconomyService.SpendBanked(player, cost) then
		return result(false, "FUNDS", { Cost = cost })
	end

	entry.Colour = colour
	EconomyService.Sync(player)
	SaveService.RequestSave(player)
	VehicleService.Sync(player)
	return result(true, "OK", { Colour = colour, Cost = cost })
end

--==========================================================================
-- Fahrzeug rufen
--
-- "Wo ist mein Auto" ist der haeufigste Grund, ein Open-World-Spiel zu
-- schliessen. Der Marker auf der Karte loest das halb; das hier loest den
-- Rest - gegen Gebuehr, mit Cooldown und nur an einer Strasse, damit es
-- kein Teleport wird.
--==========================================================================

local lastCall: { [Player]: number } = {}

local function callVehicle(player: Player): { [string]: any }
	local model = spawned[player]
	if not model or not model.Parent then
		return result(false, "NO_VEHICLE")
	end

	local now = os.time()
	local since = now - (lastCall[player] or 0)
	if since < Config.Vehicle.CallCooldown then
		return result(false, "COOLDOWN", { Seconds = Config.Vehicle.CallCooldown - since })
	end

	local position = Geometry.AlivePosition(player)
	if not position then
		return result(false, "NO_CHARACTER")
	end

	-- Nur an einer Strasse. Sonst steht das Auto im Treppenhaus.
	local node = RoadNetwork.NearestNode(position)
	if not node or (node.Position - position).Magnitude > Config.Vehicle.CallRoadRange then
		return result(false, "NO_ROAD")
	end

	if not EconomyService.SpendBanked(player, Config.Vehicle.CallFee) then
		return result(false, "TOO_EXPENSIVE", { Cost = Config.Vehicle.CallFee })
	end

	lastCall[player] = now

	-- Neben den Spieler stellen, in Richtung Strasse. PivotTo, damit das
	-- ganze Modell mitkommt.
	local toRoad = node.Position - position
	local facing = if toRoad.Magnitude > 1 then toRoad.Unit else Vector3.new(0, 0, 1)
	local drop = position + facing * Config.Vehicle.CallDropDistance
	model:PivotTo(CFrame.lookAt(Vector3.new(drop.X, position.Y + 3, drop.Z), Vector3.new(drop.X, position.Y + 3, drop.Z) + facing))

	VehicleService.Sync(player)
	return result(true, "OK", { Cost = Config.Vehicle.CallFee })
end

--==========================================================================
-- Remote
--==========================================================================

local function onAction(player: Player, payload: any): { [string]: any }
	if not RateLimiter.Check(player, "VehicleAction") then
		return result(false, "RATE")
	end
	if typeof(payload) ~= "table" then
		return result(false, "BAD_PAYLOAD")
	end

	local action = (payload :: any).Action
	local classId = (payload :: any).ClassId
	local colour = (payload :: any).Colour

	if action == "DESPAWN" then
		VehicleService.Despawn(player)
		VehicleService.Sync(player)
		return result(true, "OK")
	end

	if action == "CALL" then
		return callVehicle(player)
	end

	if typeof(classId) ~= "string" or not Vehicles.Exists(classId) then
		return result(false, "UNKNOWN_CLASS")
	end

	if action == "SPAWN" then
		return spawnVehicle(player, classId)
	elseif action == "BUY" then
		return buyVehicle(player, classId, if typeof(colour) == "string" then colour else "Schwarz")
	elseif action == "REPAINT" then
		return repaint(player, classId, if typeof(colour) == "string" then colour else "Schwarz")
	end

	return result(false, "BAD_PAYLOAD")
end

--==========================================================================

function VehicleService.Init()
	Remotes.VehicleAction.OnServerInvoke = function(player: Player, payload: any): { [string]: any }
		local ok, response = pcall(onAction, player, payload)
		if not ok then
			warn(("[GHOSTNET] VehicleAction ist abgestuerzt: %s"):format(tostring(response)))
			return result(false, "INTERNAL")
		end
		return response
	end

	SaveService.OnReady(function(player)
		VehicleService.Sync(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		VehicleService.Despawn(player)
	end)

	-- Haendler auf und zu: die Anzeige muss mitbekommen, wenn es Abend wird.
	TimeService.OnPhaseChanged(function()
		for _, player in Players:GetPlayers() do
			if SaveService.IsReady(player) then
				VehicleService.Sync(player)
			end
		end
	end)

	if Config.World.PermanentDay then
		print(("[GHOSTNET] VehicleService bereit. %d gleichzeitig ausgeparkt, Haendler durchgehend offen."):format(
			Config.Vehicle.MaxSpawned
		))
	else
		print(("[GHOSTNET] VehicleService bereit. %d gleichzeitig ausgeparkt, Haendler %d-%d Uhr."):format(
			Config.Vehicle.MaxSpawned,
			Config.Dealer.OpenHour,
			Config.Dealer.CloseHour
		))
	end
end

return VehicleService
