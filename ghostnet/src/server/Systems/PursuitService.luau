-- ServerScriptService/Systems/PursuitService.luau
--!strict
-- GHOSTNET :: Die Polizei.
--
-- KEIN SCHUSSWECHSEL, KEINE WAFFEN. Das ist eine bewusste Design-Entscheidung
-- und kein Rueckstand: Ein Spiel ohne Waffen macht die FLUCHT interessant,
-- unterscheidet sich sofort von jedem GTA-Klon, und erspart die gesamte
-- Kampf-Balance, die man als Einzelner nie sauber hinbekommt.
--
-- Die Polizei rammt, blockiert und verfolgt. Mehr nicht.
--
-- WIE ES ANS BESTEHENDE SYSTEM HAENGT
--   Die Fahndungsstufe kommt aus dem Trace. Gefasstwerden ist ein Bust ueber
--   die vorhandene Kette - kein zweites Straf-System daneben.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Geometry = require(ReplicatedStorage.Shared.Geometry)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local AssetLibrary = require(ReplicatedStorage.Shared.AssetLibrary)

local RoadNetwork = require(script.Parent.RoadNetwork)
local SaveService = require(script.Parent.SaveService)
local TraceService = require(script.Parent.TraceService)

local PursuitService = {}

local P = Config.Pursuit
local rng = Random.new()

type Unit = {
	Model: Model,
	Body: BasePart,
	GroundOffset: number, -- aus der Modellhoehe gerechnet, nicht geraten
	From: number,
	To: number,
	Alpha: number,
	Active: boolean,
}

type Chase = {
	Level: number,
	Bonus: number, -- Stufen aus Taten (Diebstahl, Alarm), nicht aus dem Trace
	OutOfSight: number, -- Sekunden ohne Sichtkontakt
	InRange: number, -- Sekunden dicht dran am Streifenwagen
	Units: { Unit },
}

local chases: { [Player]: Chase } = {}
local container: Folder? = nil

local function ensureContainer(): Folder
	if container and container.Parent then
		return container
	end
	local folder = Instance.new("Folder")
	folder.Name = "GhostNet_Police"
	folder.Parent = workspace
	container = folder
	return folder
end

--==========================================================================
-- Streifenwagen
--==========================================================================

local function buildUnit(): Unit
	-- Derselbe Weg wie beim Verkehr: Vorlage klonen, nicht bauen. Fehlt sie,
	-- steht hier ein magenta Platzhalter - unuebersehbar, aber fahrbereit.
	local model = AssetLibrary.Clone("Vehicles", P.UnitAsset, P.UnitSize)
	model.Name = "Streifenwagen"

	local pivot = model.PrimaryPart
	if not pivot then
		local chassis = AssetLibrary.Find(model, "Chassis")
		if chassis and chassis:IsA("BasePart") then
			pivot = chassis
		else
			warn(("[GHOSTNET] Streifenwagenvorlage '%s' hat weder PrimaryPart noch Chassis."):format(P.UnitAsset))
			pivot = model:FindFirstChildWhichIsA("BasePart", true)
		end
	end
	local body = pivot :: BasePart
	model.PrimaryPart = body

	-- Kulisse: Anchored, keine Physik, keine Abfrage.
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanTouch = false
			descendant.CanQuery = false
			descendant.CanCollide = descendant == body
			if descendant ~= body then
				descendant.CastShadow = false
			end
		end
	end

	-- Blaulicht. Neonflaechen statt Lichtquellen fuer die Farbe, EIN
	-- PointLight fuer den Schein - mehr braucht es nicht und mehr kostet
	-- zu viel. Bringt die Vorlage schon Lichter mit, bleibt es dabei.
	if not AssetLibrary.Find(model, "Lights/Blau") then
		local lights = model:FindFirstChild("Lights")
		if not lights then
			local folder = Instance.new("Folder")
			folder.Name = "Lights"
			folder.Parent = model
			lights = folder
		end
		for index, side in { -1, 1 } do
			local bar = Instance.new("Part")
			bar.Name = if index == 1 then "Blau" else "Rot"
			bar.Size = P.LightBarSize
			bar.Color = if side < 0 then P.LightBlue else P.LightRed
			bar.Material = Enum.Material.Neon
			bar.Anchored = true
			bar.CanCollide = false
			bar.CanQuery = false
			bar.CanTouch = false
			bar.CastShadow = false
			-- Bauposition relativ zur Karosserie. KEINE WeldConstraint -
			-- beide Teile sind Anchored, bewegt wird per PivotTo.
			bar.CFrame = body.CFrame * CFrame.new(side * 1.4, body.Size.Y * 0.5 + 0.4, 0)
			bar.Parent = lights
		end

		local light = Instance.new("PointLight")
		light.Color = P.LightBlue
		light.Brightness = P.LightBrightness
		light.Range = P.LightRange
		light.Parent = body
	end

	model.Parent = ensureContainer()
	CollectionService:AddTag(model, Config.SmoothTag)
	return {
		Model = model,
		Body = body,
		GroundOffset = Config.City.RoadThickness * 0.5
			+ model:GetExtentsSize().Y * 0.5
			+ Config.Traffic.GroundClearance,
		From = 1,
		To = 1,
		Alpha = 0,
		Active = true,
	}
end

local function releaseUnit(unit: Unit)
	unit.Active = false
	if unit.Model.Parent then
		unit.Model:Destroy()
	end
end

--==========================================================================
-- Fahndungsstufe
--==========================================================================

function PursuitService.GetLevel(player: Player): number
	local chase = chases[player]
	return if chase then chase.Level else 0
end

-- Taten erhoehen die Stufe direkt, unabhaengig vom Trace: Autodiebstahl,
-- ausgeloester Alarm, spaeter Unfaelle.
function PursuitService.AddHeat(player: Player, amount: number)
	local chase = chases[player]
	if not chase then
		chase = { Level = 0, Bonus = 0, OutOfSight = 0, InRange = 0, Units = {} }
		chases[player] = chase
	end
	chase.Bonus = math.clamp(chase.Bonus + amount, 0, P.MaxLevel)
end

local function computeLevel(player: Player, chase: Chase): number
	local trace = TraceService.Get(player)
	local fromTrace = math.floor(trace / P.TracePerLevel)
	return math.clamp(math.floor(fromTrace + chase.Bonus), 0, P.MaxLevel)
end

--==========================================================================
-- Verfolgung
--==========================================================================

local function sees(unit: Unit, position: Vector3): boolean
	return (unit.Body.Position - position).Magnitude <= P.SpotRange
end

local function moveUnit(unit: Unit, target: Vector3, dt: number)
	-- Streifenwagen fahren auf demselben Graphen wie der Verkehr. Kein
	-- Pathfinding: ein Schritt Richtung Ziel reicht auf einem Gitter.
	local position, direction = RoadNetwork.LanePosition(unit.From, unit.To, unit.Alpha)
	if not position or not direction then
		local node = RoadNetwork.NearestNode(target)
		if node then
			unit.From = node.Id
			unit.To = RoadNetwork.StepToward(node.Id, target) or node.Id
			unit.Alpha = 0
		end
		return
	end

	-- PivotTo, damit das Blaulicht mitfaehrt statt an der Kreuzung zu bleiben.
	local lift = Vector3.new(0, unit.GroundOffset, 0)
	unit.Model:PivotTo(CFrame.lookAt(position + lift, position + direction + lift))

	unit.Alpha += (P.UnitSpeed * dt) / Config.City.BlockSize
	if unit.Alpha >= 1 then
		unit.From = unit.To
		unit.To = RoadNetwork.StepToward(unit.From, target) or unit.From
		unit.Alpha = 0
	end
end

local function syncChase(player: Player, chase: Chase)
	if not player.Parent then
		return
	end
	Remotes.PursuitSync:FireClient(player, {
		Level = chase.Level,
		MaxLevel = P.MaxLevel,
		Escaping = chase.OutOfSight > 0 and chase.Level > 0,
		EscapeSeconds = math.max(0, P.EscapeSeconds - chase.OutOfSight),
		Roadblock = chase.Level >= P.RoadblockLevel,
		Helicopter = chase.Level >= P.HelicopterLevel,
	})
end

local function clearChase(player: Player)
	local chase = chases[player]
	if not chase then
		return
	end
	for _, unit in chase.Units do
		releaseUnit(unit)
	end
	table.clear(chase.Units)
	chase.Level = 0
	chase.Bonus = 0
	chase.OutOfSight = 0
	chase.InRange = 0
	syncChase(player, chase)
end

function PursuitService.Clear(player: Player)
	clearChase(player)
end

local function step(dt: number)
	for _, player in Players:GetPlayers() do
		local chase = chases[player]
		if not chase then
			continue
		end

		local position = Geometry.AlivePosition(player)
		if not position then
			-- Tot oder nicht geladen: keine Verfolgung, aber die Stufe bleibt.
			for _, unit in chase.Units do
				releaseUnit(unit)
			end
			table.clear(chase.Units)
			continue
		end

		chase.Level = computeLevel(player, chase)

		if chase.Level <= 0 then
			if #chase.Units > 0 then
				clearChase(player)
			end
			continue
		end

		-- Anzahl der Wagen aus der Stufe.
		local wanted = math.clamp(chase.Level * P.UnitsPerLevel, 0, P.MaxUnits)
		while #chase.Units < wanted do
			local unit = buildUnit()
			local node = RoadNetwork.NearestNode(position)
			if node then
				-- Startet eine Kreuzung entfernt, damit er nicht im Spieler steht.
				local links = RoadNetwork.Links(node.Id)
				unit.From = if #links > 0 then links[rng:NextInteger(1, #links)] else node.Id
				unit.To = RoadNetwork.StepToward(unit.From, position) or unit.From
			end
			table.insert(chase.Units, unit)
		end
		while #chase.Units > wanted do
			local unit = table.remove(chase.Units)
			if unit then
				releaseUnit(unit)
			end
		end

		local spotted = false
		local closest = math.huge
		for _, unit in chase.Units do
			moveUnit(unit, position, dt)
			local distance = (unit.Body.Position - position).Magnitude
			closest = math.min(closest, distance)
			if sees(unit, position) then
				spotted = true
			end
		end

		if spotted then
			chase.OutOfSight = 0
		else
			chase.OutOfSight += dt
			-- Entkommen: lange genug ausser Sicht, dann faellt die Stufe.
			if chase.OutOfSight >= P.EscapeSeconds then
				chase.Bonus = math.max(0, chase.Bonus - 1)
				chase.OutOfSight = 0
				if computeLevel(player, chase) <= 0 then
					print(("[GHOSTNET] %s ist entkommen."):format(player.Name))
					clearChase(player)
					continue
				end
			end
		end

		-- Gefasst: lange genug dicht dran. Das ist ein Bust ueber die
		-- bestehende Kette, kein neues Straf-System.
		if closest <= P.CatchRange then
			chase.InRange += dt
			if chase.InRange >= P.CatchSeconds then
				warn(("[GHOSTNET] %s wurde gefasst."):format(player.Name))
				local profile = SaveService.Get(player)
				if profile then
					profile.Trace = 0
				end
				TraceService.Add(player, Config.Trace.Max)
				clearChase(player)
				continue
			end
		else
			chase.InRange = math.max(0, chase.InRange - dt)
		end

		-- Passiver Abbau, damit eine alte Tat nicht ewig nachhaengt.
		chase.Bonus = math.max(0, chase.Bonus - P.Decay * dt)

		syncChase(player, chase)
	end
end

--==========================================================================

function PursuitService.Init()
	RoadNetwork.Build()

	SaveService.OnReady(function(player)
		chases[player] = { Level = 0, Bonus = 0, OutOfSight = 0, InRange = 0, Units = {} }
	end)

	Players.PlayerRemoving:Connect(function(player)
		clearChase(player)
		chases[player] = nil
	end)

	-- Nach einem Bust ist die Fahndung vorbei - man ist ja schon dran gewesen.
	TraceService.OnBust(function(player)
		clearChase(player)
	end)

	task.spawn(function()
		local last = os.clock()
		while true do
			task.wait(P.Tick)
			local now = os.clock()
			local dt = now - last
			last = now
			local ok, err = pcall(step, dt)
			if not ok then
				warn(("[GHOSTNET] Verfolgungstakt fehlgeschlagen: %s"):format(tostring(err)))
			end
		end
	end)

	print(("[GHOSTNET] PursuitService bereit. Stufen 1-%d, Entkommen nach %d s ausser Sicht."):format(
		P.MaxLevel,
		P.EscapeSeconds
	))
end

return PursuitService
