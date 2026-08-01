-- ServerScriptService/Systems/TrafficService.luau
--!strict
-- GHOSTNET :: Verkehr und Fussgaenger.
--
-- DER PERFORMANCEKRITISCHSTE TEIL DES PROJEKTS. Falsch gebaut ruiniert er
-- die Bildrate und damit das Spiel. Deshalb vier harte Entscheidungen:
--
--   1. KEIN PathfindingService. Die Autos folgen dem festen Graphen aus
--      RoadNetwork, Kante fuer Kante. Ein Pfad pro Auto, mehrfach pro
--      Sekunde neu berechnet, frisst den Server auf.
--   2. KEINE Physik. Verkehrsautos sind Anchored und bewegen sich per
--      CFrame. Sie kollidieren nicht echt - sie bremsen, wenn auf ihrer
--      eigenen Kante jemand vor ihnen ist.
--   3. KEIN Humanoid fuer Fussgaenger. Humanoids sind teuer. Hintergrund-
--      leute sind bewegte Modelle ohne Humanoid.
--   4. POOL statt Instance.new/Destroy im Sekundentakt, harte Obergrenze,
--      und nur im Radius um Spieler aktiv.
--
-- Abstandspruefung laeuft NUR gegen die eigene Kante, nicht gegen alle Autos.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Geometry = require(ReplicatedStorage.Shared.Geometry)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local RateLimiter = require(script.Parent.RateLimiter)
local RoadNetwork = require(script.Parent.RoadNetwork)
local TimeService = require(script.Parent.TimeService)
local PursuitService = require(script.Parent.PursuitService)
local TraceService = require(script.Parent.TraceService)
local VehicleChassis = require(script.Parent.VehicleChassis)

local TrafficService = {}

local T = Config.Traffic
local rng = Random.new()

type Car = {
	Model: Model,
	Body: BasePart,
	From: number,
	To: number,
	Alpha: number,
	Speed: number,
	Active: boolean,
	ClassId: string,
}

type Walker = {
	Model: Model,
	Body: BasePart,
	From: number,
	To: number,
	Alpha: number,
	Side: number,
	Active: boolean,
}

local cars: { Car } = {}
local walkers: { Walker } = {}
local container: Folder? = nil

-- Belegung pro Kante, damit die Abstandspruefung nicht jedes Auto gegen
-- jedes andere testen muss.
local laneOccupancy: { [string]: { number } } = {}

local function laneKey(from: number, to: number): string
	return ("%d>%d"):format(from, to)
end

--==========================================================================
-- Bauteile aus dem Pool
--==========================================================================

local function ensureContainer(): Folder
	if container and container.Parent then
		return container
	end
	local folder = Instance.new("Folder")
	folder.Name = "GhostNet_Traffic"
	folder.Parent = workspace
	container = folder
	return folder
end

local TRAFFIC_COLOURS = {
	Color3.fromRGB(52, 58, 70),
	Color3.fromRGB(84, 88, 96),
	Color3.fromRGB(36, 40, 48),
	Color3.fromRGB(70, 60, 58),
	Color3.fromRGB(44, 56, 66),
}

local function buildCarShell(): (Model, BasePart)
	local model = Instance.new("Model")
	model.Name = "TrafficCar"

	local body = Instance.new("Part")
	body.Name = "Body"
	body.Size = Vector3.new(6.2, 2.8, 12.5)
	body.Color = TRAFFIC_COLOURS[rng:NextInteger(1, #TRAFFIC_COLOURS)]
	body.Material = Enum.Material.SmoothPlastic
	body.Anchored = true
	body.CanCollide = true
	body.CanTouch = false
	body.Parent = model
	model.PrimaryPart = body

	local roof = Instance.new("Part")
	roof.Name = "Roof"
	roof.Size = Vector3.new(5.4, 2, 6)
	roof.Color = body.Color:Lerp(Color3.new(0, 0, 0), 0.4)
	roof.Material = Enum.Material.Glass
	roof.Transparency = 0.4
	roof.Anchored = true
	roof.CanCollide = false
	roof.CanQuery = false
	roof.CanTouch = false
	roof.CastShadow = false
	roof.Parent = model

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = body
	weld.Part1 = roof
	weld.Parent = body
	roof.CFrame = body.CFrame * CFrame.new(0, 2.2, -0.6)

	-- Der Diebstahl-Prompt. Halten statt tippen, damit es nicht aus Versehen
	-- passiert.
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "StealPrompt"
	prompt.ActionText = "Kurzschliessen"
	prompt.ObjectText = "Fremdes Auto"
	prompt.HoldDuration = T.StealHoldSeconds
	prompt.MaxActivationDistance = T.StealRange
	prompt.RequiresLineOfSight = false
	prompt.Parent = body

	-- Der Prompt feuert direkt serverseitig. Der Client meldet nichts, was
	-- geprueft werden muesste - er tippt nur.
	prompt.Triggered:Connect(function(player)
		TrafficService.HandleSteal(player)
	end)

	model.Parent = ensureContainer()
	return model, body
end

local function buildWalkerShell(): (Model, BasePart)
	local model = Instance.new("Model")
	model.Name = "Pedestrian"

	-- Bewusst KEIN Humanoid: ein Humanoid pro Fussgaenger kostet mehr als
	-- der gesamte restliche Fussgaenger zusammen.
	local body = Instance.new("Part")
	body.Name = "Body"
	body.Size = Vector3.new(1.8, 4, 1)
	body.Color = Color3.fromRGB(rng:NextInteger(30, 70), rng:NextInteger(30, 70), rng:NextInteger(40, 80))
	body.Material = Enum.Material.SmoothPlastic
	body.Anchored = true
	body.CanCollide = false
	body.CanQuery = false
	body.CanTouch = false
	body.CastShadow = false
	body.Parent = model
	model.PrimaryPart = body

	local head = Instance.new("Part")
	head.Name = "Head"
	head.Size = Vector3.new(1.1, 1.1, 1.1)
	head.Color = Color3.fromRGB(180, 150, 130)
	head.Anchored = true
	head.CanCollide = false
	head.CanQuery = false
	head.CanTouch = false
	head.CastShadow = false
	head.Parent = model

	model.Parent = ensureContainer()
	return model, head
end

--==========================================================================
-- Spieler in der Naehe?
--==========================================================================

local function nearAnyPlayer(position: Vector3, radius: number): boolean
	for _, player in Players:GetPlayers() do
		local at = Geometry.AlivePosition(player)
		if at and (at - position).Magnitude <= radius then
			return true
		end
	end
	return false
end

local function randomActiveNode(): number?
	-- Eine Kreuzung in der Naehe irgendeines Spielers - sonst spawnt Verkehr
	-- am anderen Ende der Stadt, wo ihn keiner sieht.
	local candidates: { number } = {}
	for _, player in Players:GetPlayers() do
		local at = Geometry.AlivePosition(player)
		if at then
			local node = RoadNetwork.NearestNode(at)
			if node then
				for _, linkId in node.Links do
					table.insert(candidates, linkId)
				end
			end
		end
	end
	if #candidates == 0 then
		return nil
	end
	return candidates[rng:NextInteger(1, #candidates)]
end

--==========================================================================
-- Verkehr
--==========================================================================

local function placeCar(car: Car)
	local position, direction = RoadNetwork.LanePosition(car.From, car.To, car.Alpha)
	if not position or not direction then
		car.Active = false
		return
	end
	car.Body.CFrame = CFrame.lookAt(position + Vector3.new(0, 2.4, 0), position + direction + Vector3.new(0, 2.4, 0))
end

local function spawnCar()
	local startId = randomActiveNode()
	if not startId then
		return
	end
	local toId = RoadNetwork.NextNode(startId, nil, rng)
	if not toId then
		return
	end

	local free: Car? = nil
	for _, car in cars do
		if not car.Active then
			free = car
			break
		end
	end

	if not free then
		if #cars >= T.MaxActive then
			return
		end
		local model, body = buildCarShell()
		free = {
			Model = model,
			Body = body,
			From = startId,
			To = toId,
			Alpha = 0,
			Speed = T.Speed,
			Active = true,
			ClassId = "SEDAN",
		}
		table.insert(cars, free :: Car)
	end

	local car = free :: Car
	car.From = startId
	car.To = toId
	car.Alpha = rng:NextNumber(0, 0.4)
	car.Speed = T.Speed + rng:NextNumber(-T.SpeedJitter, T.SpeedJitter)
	car.Active = true
	car.Model.Parent = ensureContainer()
	placeCar(car)
end

local function recycle(car: Car)
	car.Active = false
	car.Model.Parent = nil
end

-- Bremsen, wenn auf der eigenen Kante jemand kurz vor einem faehrt.
local function blockedAhead(car: Car, index: number): boolean
	local ids = laneOccupancy[laneKey(car.From, car.To)]
	if not ids then
		return false
	end
	for _, otherIndex in ids do
		if otherIndex == index then
			continue
		end
		local other = cars[otherIndex]
		if other and other.Active then
			local gap = (other.Alpha - car.Alpha) * Config.City.BlockSize
			if gap > 0 and gap < T.StopDistance then
				return true
			end
		end
	end
	return false
end

local function stepTraffic(dt: number)
	table.clear(laneOccupancy)
	for index, car in cars do
		if car.Active then
			local key = laneKey(car.From, car.To)
			local list = laneOccupancy[key]
			if not list then
				list = {}
				laneOccupancy[key] = list
			end
			table.insert(list, index)
		end
	end

	for index, car in cars do
		if not car.Active then
			continue
		end

		-- Ausserhalb des Radius: anhalten und recyceln statt weiterrechnen.
		if not nearAnyPlayer(car.Body.Position, T.ActiveRadius) then
			recycle(car)
			continue
		end

		if blockedAhead(car, index) then
			continue -- steht, faehrt aber nicht rueckwaerts oder verschwindet
		end

		car.Alpha += (car.Speed * dt) / Config.City.BlockSize
		if car.Alpha >= 1 then
			local nextId = RoadNetwork.NextNode(car.To, car.From, rng)
			if not nextId then
				recycle(car)
				continue
			end
			car.From = car.To
			car.To = nextId
			car.Alpha = 0
		end

		placeCar(car)
	end
end

--==========================================================================
-- Fussgaenger
--==========================================================================

local function placeWalker(walker: Walker)
	local position, direction = RoadNetwork.LanePosition(walker.From, walker.To, walker.Alpha)
	if not position or not direction then
		walker.Active = false
		return
	end
	local right = Vector3.new(-direction.Z, 0, direction.X)
	local offset = right * (walker.Side * (Config.City.RoadWidth * 0.5 + Config.City.SidewalkWidth * 0.4))
	local at = position + offset + Vector3.new(0, 3, 0)
	walker.Body.CFrame = CFrame.lookAt(at, at + direction)
	local torso = walker.Model:FindFirstChild("Body")
	if torso and torso:IsA("BasePart") then
		torso.CFrame = walker.Body.CFrame * CFrame.new(0, -2.4, 0)
	end
end

local function spawnWalker()
	local startId = randomActiveNode()
	if not startId then
		return
	end
	local toId = RoadNetwork.NextNode(startId, nil, rng)
	if not toId then
		return
	end

	local free: Walker? = nil
	for _, walker in walkers do
		if not walker.Active then
			free = walker
			break
		end
	end

	if not free then
		if #walkers >= T.MaxPedestrians then
			return
		end
		local model, head = buildWalkerShell()
		free = {
			Model = model,
			Body = head,
			From = startId,
			To = toId,
			Alpha = 0,
			Side = 1,
			Active = true,
		}
		table.insert(walkers, free :: Walker)
	end

	local walker = free :: Walker
	walker.From = startId
	walker.To = toId
	walker.Alpha = rng:NextNumber(0, 1)
	walker.Side = if rng:NextNumber() < 0.5 then -1 else 1
	walker.Active = true
	walker.Model.Parent = ensureContainer()
	placeWalker(walker)
end

local function stepWalkers(dt: number)
	for _, walker in walkers do
		if not walker.Active then
			continue
		end
		if not nearAnyPlayer(walker.Body.Position, T.ActiveRadius) then
			walker.Active = false
			walker.Model.Parent = nil
			continue
		end

		walker.Alpha += (T.PedestrianSpeed * dt) / Config.City.BlockSize
		if walker.Alpha >= 1 then
			local nextId = RoadNetwork.NextNode(walker.To, walker.From, rng)
			if not nextId then
				walker.Active = false
				walker.Model.Parent = nil
				continue
			end
			walker.From = walker.To
			walker.To = nextId
			walker.Alpha = 0
		end
		placeWalker(walker)
	end
end

--==========================================================================
-- Diebstahl
-- Aus einem Kulissenauto wird ein echtes Physikfahrzeug. Danach faehrt es
-- sich exakt wie ein gekauftes - es IST dieselbe Klasse.
--==========================================================================

function TrafficService.HandleSteal(player: Player)
	if not RateLimiter.Check(player, "StealVehicle") then
		return
	end
	local position = Geometry.AlivePosition(player)
	if not position then
		return
	end

	-- Naechstes aktives Verkehrsauto in Reichweite. Distanz serverseitig.
	local target: Car? = nil
	local bestDistance = math.huge
	for _, car in cars do
		if not car.Active then
			continue
		end
		local distance = (car.Body.Position - position).Magnitude
		if distance <= T.StealRange + Config.Range.Tolerance and distance < bestDistance then
			target, bestDistance = car, distance
		end
	end
	if not target then
		return
	end

	local cframe = CFrame.new(target.Body.Position + Vector3.new(0, 1, 0)) * (target.Body.CFrame - target.Body.Position)
	recycle(target)

	local model = VehicleChassis.Build(target.ClassId, cframe, target.Body.Color)
	if not model then
		return
	end

	-- Autodiebstahl haengt am Trace, statt danebenherzulaufen.
	TraceService.Add(player, T.StealTrace)
	PursuitService.AddHeat(player, 1)
	print(("[GHOSTNET] %s hat ein Auto kurzgeschlossen (+%d Trace)."):format(player.Name, T.StealTrace))
end

--==========================================================================

function TrafficService.ActiveCount(): (number, number)
	local carCount, walkerCount = 0, 0
	for _, car in cars do
		if car.Active then
			carCount += 1
		end
	end
	for _, walker in walkers do
		if walker.Active then
			walkerCount += 1
		end
	end
	return carCount, walkerCount
end

function TrafficService.Init()
	RoadNetwork.Build()
	Remotes.StealVehicle.OnServerEvent:Connect(TrafficService.HandleSteal)

	-- Bewegungstakt. Bewusst ein eigener, gestaffelter Tick statt eines
	-- Heartbeat-Handlers, der ueber alles laeuft.
	task.spawn(function()
		local last = os.clock()
		while true do
			task.wait(T.Tick)
			local now = os.clock()
			local dt = now - last
			last = now
			local ok, err = pcall(function()
				stepTraffic(dt)
				stepWalkers(dt)
			end)
			if not ok then
				warn(("[GHOSTNET] Verkehrstakt fehlgeschlagen: %s"):format(tostring(err)))
			end
		end
	end)

	-- Nachfuellen. Nachts duenner - das ist der zweite sichtbare Unterschied
	-- zwischen Tag und Nacht.
	task.spawn(function()
		while true do
			task.wait(T.SpawnTick)
			if #Players:GetPlayers() == 0 then
				continue
			end
			local carCount, walkerCount = TrafficService.ActiveCount()
			local carTarget = if TimeService.IsNight() then math.floor(T.MaxActive * 0.5) else T.MaxActive
			local walkerTarget = if TimeService.IsNight()
				then math.floor(T.MaxPedestrians * 0.4)
				else T.MaxPedestrians

			if carCount < carTarget then
				spawnCar()
			end
			if walkerCount < walkerTarget then
				spawnWalker()
			end
		end
	end)

	print(("[GHOSTNET] TrafficService bereit. Max %d Autos, %d Fussgaenger, Radius %d."):format(
		T.MaxActive,
		T.MaxPedestrians,
		T.ActiveRadius
	))
end

return TrafficService
