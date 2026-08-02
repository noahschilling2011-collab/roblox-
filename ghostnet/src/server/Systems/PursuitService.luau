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
local PathfindingService = game:GetService("PathfindingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AssetLibrary = require(ReplicatedStorage.Shared.AssetLibrary)
local Config = require(ReplicatedStorage.Shared.Config)
local Geometry = require(ReplicatedStorage.Shared.Geometry)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local AssetLibrary = require(ReplicatedStorage.Shared.AssetLibrary)

local ArrestService = require(script.Parent.ArrestService)
local RoadNetwork = require(script.Parent.RoadNetwork)
local VehicleChassis = require(script.Parent.VehicleChassis)
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
	Officers: { Officer }, -- ausgestiegene Polizisten (ab ExitLevel)
	Standing: number, -- Sekunden, die der Spieler kaum bewegt ist
	StartedAt: number, -- os.clock() beim Beginn - fuer MaxDuration
}

-- Vorwaertsdeklaration: der Officer-Typ steht weiter unten, weil er den
-- Container und den ArrestService braucht.
export type Officer = any

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
	-- Gibt es ein eigenes Polizeimodell in Assets/Vehicles, wird das benutzt.
	-- Sonst kommt die Karosserie aus demselben Bauplan wie jedes andere Auto -
	-- ein Streifenwagen soll aussehen wie ein Fahrzeug, nicht wie ein Klotz.
	local model: Model?
	if AssetLibrary.Has("Vehicles", P.UnitAsset) then
		model = AssetLibrary.Clone("Vehicles", P.UnitAsset, P.UnitSize)
		if model then
			for _, descendant in model:GetDescendants() do
				if descendant:IsA("BasePart") then
					descendant.Anchored = true
					descendant.CanTouch = false
					descendant.CanQuery = false
				end
			end
		end
	else
		model = VehicleChassis.BuildShell(P.UnitClass)
	end

	if not model then
		warn("[GHOSTNET] Streifenwagen: keine Karosserie verfuegbar.")
		model = Instance.new("Model")
	end
	local unitModel = model :: Model
	unitModel.Name = "Streifenwagen"

	local pivot = unitModel.PrimaryPart or unitModel:FindFirstChildWhichIsA("BasePart", true)
	if not pivot then
		local fallback = Instance.new("Part")
		fallback.Size = P.UnitSize
		fallback.Anchored = true
		fallback.Parent = unitModel
		pivot = fallback
	end
	local body = pivot :: BasePart
	unitModel.PrimaryPart = body
	model = unitModel

	-- Polizeilack: die geliehene Karosserie wird umgefaerbt, sonst faehrt
	-- eine zivile Limousine mit Blaulicht durch die Stadt.
	local bodyParts = unitModel:FindFirstChild("BodyParts")
	if bodyParts then
		for _, part in bodyParts:GetChildren() do
			if part:IsA("BasePart") and (part.Name == "Body" or part.Name == "Cabin" or part.Name == "Hood") then
				part.Color = P.UnitColour
			end
		end
	end

	-- Blaulicht. Neonflaechen statt Lichtquellen fuer die Farbe, EIN
	-- PointLight fuer den Schein - mehr braucht es nicht und mehr kostet
	-- zu viel. Bringt die Vorlage schon Lichter mit, bleibt es dabei.
	if not AssetLibrary.Find(unitModel, "Lights/Blau") then
		local lights = unitModel:FindFirstChild("Lights")
		if not lights then
			local folder = Instance.new("Folder")
			folder.Name = "Lights"
			folder.Parent = unitModel
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

	unitModel.Parent = ensureContainer()
	CollectionService:AddTag(unitModel, Config.SmoothTag)
	return {
		Model = unitModel,
		Body = body,
		GroundOffset = Config.City.RoadThickness * 0.5
			+ unitModel:GetExtentsSize().Y * 0.5
			+ Config.Traffic.GroundClearance,
		From = 1,
		To = 1,
		Alpha = 0,
		Active = true,
	}
end

--==========================================================================
-- POLIZISTEN ZU FUSS
--
-- Ab Config.Pursuit.ExitLevel steigen sie aus. Das ist der Punkt, an dem
-- eine Verfolgung erst zur Bedrohung wird: solange nur Autos hinterherfahren,
-- steigt man aus und geht durch eine Gasse.
--
-- HIER IST PathfindingService RICHTIG
--   Fuer Verkehrsautos ist er verboten - Dutzende Pfade pro Sekunde fressen
--   den Server. Hier laufen hoechstens eine Handvoll Polizisten, und ein
--   Mensch, der um eine Hausecke geht, braucht einen echten Weg.
--   Neu gerechnet wird nur alle Config.Pursuit.OfficerRepath Sekunden.
--
-- KEIN KAMPF. Ein Polizist greift zu, er schlaegt nicht.
--==========================================================================

type Officer = {
	Model: Model,
	Humanoid: Humanoid,
	Root: BasePart,
	Path: Path,
	NextRepath: number,
	Waypoints: { PathWaypoint },
	WaypointIndex: number,
	LastSeen: Vector3?,
	SearchUntil: number,
	Warned: boolean,
	InRange: number,
}

local function buildOfficer(at: Vector3): Officer?
	-- Ein Polizist ist eine Figur, also gehoert er nach Assets/Characters.
	-- Fehlt die Vorlage, kommt ein magenta Platzhalter - der laeuft genauso,
	-- er sieht nur unuebersehbar unfertig aus.
	local model = AssetLibrary.Clone("Characters", "Officer", P.OfficerSize)
	model.Name = "Polizist"

	local root = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
	if not root then
		warn("[GHOSTNET] Polizisten-Vorlage enthaelt keinen BasePart.")
		model:Destroy()
		return nil
	end

	-- Ein Humanoid, damit er laufen, Treppen nehmen und Animationen abspielen
	-- kann. Das ist genau der Fall, fuer den ein Humanoid gedacht ist -
	-- anders als bei Hintergrund-Fussgaengern, wo er reine Verschwendung ist.
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		humanoid = Instance.new("Humanoid")
		humanoid.Parent = model
	end
	humanoid.WalkSpeed = P.OfficerSpeed
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None

	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = false
			descendant.CanQuery = false
		end
	end
	root.CFrame = CFrame.new(at + Vector3.new(0, 3, 0))
	model.Parent = ensureContainer()

	return {
		Model = model,
		Humanoid = humanoid,
		Root = root,
		Path = PathfindingService:CreatePath({
			AgentRadius = 2,
			AgentHeight = 5,
			AgentCanJump = false,
		}),
		NextRepath = 0,
		Waypoints = {},
		WaypointIndex = 1,
		LastSeen = nil,
		SearchUntil = 0,
		Warned = false,
		InRange = 0,
	}
end

local function releaseOfficer(officer: Officer)
	if officer.Model.Parent then
		officer.Model:Destroy()
	end
end

-- Sichtlinie: Waende blockieren. Ohne das laeuft der Polizist durch das
-- halbe Viertel direkt auf einen zu, obwohl er einen gar nicht sehen kann.
local officerRay = RaycastParams.new()
officerRay.FilterType = Enum.RaycastFilterType.Exclude
officerRay.IgnoreWater = true

local function officerSees(officer: Officer, character: Model, position: Vector3): boolean
	local delta = position - officer.Root.Position
	if delta.Magnitude > P.OfficerSightRange then
		return false
	end
	officerRay.FilterDescendantsInstances = { officer.Model, character }
	return workspace:Raycast(officer.Root.Position, delta, officerRay) == nil
end

local function stepOfficer(officer: Officer, player: Player, character: Model, position: Vector3, now: number, dt: number): boolean
	local visible = officerSees(officer, character, position)
	if visible then
		officer.LastSeen = position
		officer.SearchUntil = now + P.OfficerSearchSeconds
	end

	-- Ziel: der Spieler, wenn man ihn sieht, sonst die letzte bekannte
	-- Position. Danach gibt der Polizist auf.
	local goal = if visible then position else officer.LastSeen
	if not goal then
		return false
	end
	if not visible and now > officer.SearchUntil then
		return false
	end

	-- NUR alle OfficerRepath Sekunden neu rechnen. Jeden Frame waere das
	-- Ende des Servers.
	if now >= officer.NextRepath then
		officer.NextRepath = now + P.OfficerRepath
		local ok = pcall(function()
			officer.Path:ComputeAsync(officer.Root.Position, goal)
		end)
		if ok and officer.Path.Status == Enum.PathStatus.Success then
			officer.Waypoints = officer.Path:GetWaypoints()
			officer.WaypointIndex = 2 -- der erste Punkt ist die eigene Position
		else
			-- Kein Weg: dann wenigstens stur in die Richtung laufen.
			officer.Waypoints = {}
			officer.Humanoid:MoveTo(goal)
		end
	end

	local waypoint = officer.Waypoints[officer.WaypointIndex]
	if waypoint then
		officer.Humanoid:MoveTo(waypoint.Position)
		if (officer.Root.Position - waypoint.Position).Magnitude < 4 then
			officer.WaypointIndex += 1
		end
	end

	--== Festnahme =========================================================
	local distance = (officer.Root.Position - position).Magnitude
	if distance <= P.ArrestRange and visible then
		officer.InRange += dt

		-- Nie ohne Vorwarnung. Erst der Ruf, dann der Zugriff.
		if not officer.Warned and officer.InRange >= P.WarnSeconds then
			officer.Warned = true
			Remotes.ArrestSync:FireClient(player, {
				State = "WARNING",
				Seconds = math.ceil(P.ArrestSeconds - officer.InRange),
				Station = "",
			})
		end

		if officer.InRange >= P.ArrestSeconds then
			return ArrestService.Arrest(player)
		end
	else
		officer.InRange = math.max(0, officer.InRange - dt)
		officer.Warned = false
	end

	return false
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
		chase = { Level = 0, Bonus = 0, OutOfSight = 0, InRange = 0, Units = {}, Officers = {}, Standing = 0, StartedAt = os.clock() }
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
		-- Sichtbarer Entkommen-Fortschritt. Der Spieler muss sehen, dass er
		-- kurz davor ist - sonst gibt er auf, obwohl es fast geschafft war.
		EscapeProgress = math.clamp(chase.OutOfSight / math.max(P.EscapeSeconds, 0.01), 0, 1),
		OnFoot = #chase.Officers > 0,
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
	for _, officer in chase.Officers do
		releaseOfficer(officer)
	end
	table.clear(chase.Officers)
	chase.Standing = 0
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

		--== Aussteigen ====================================================
		-- Ab ExitLevel steigen Polizisten aus, sobald der Spieler steht oder
		-- ohnehin zu Fuss unterwegs ist. Solange nur Autos hinterherfahren,
		-- steigt man aus und geht durch eine Gasse - das ist keine Verfolgung.
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local speed = if root and root:IsA("BasePart") then root.AssemblyLinearVelocity.Magnitude else 0
		local onFoot = root ~= nil
			and character:FindFirstChildOfClass("Humanoid") ~= nil
			and (character:FindFirstChildOfClass("Humanoid") :: Humanoid).SeatPart == nil

		if speed < P.ExitSpeedThreshold or onFoot then
			chase.Standing += dt
		else
			chase.Standing = 0
		end

		if chase.Level >= P.ExitLevel and chase.Standing >= P.ExitDelay and #chase.Officers == 0 then
			for _, unit in chase.Units do
				for _ = 1, P.OfficersPerUnit do
					local officer = buildOfficer(unit.Body.Position)
					if officer then
						table.insert(chase.Officers, officer)
					end
				end
			end
		end

		--== Zu Fuss verfolgen und festnehmen ==============================
		local now = os.clock()
		local arrested = false
		for index = #chase.Officers, 1, -1 do
			local officer = chase.Officers[index]
			if not officer.Model.Parent or not character then
				releaseOfficer(officer)
				table.remove(chase.Officers, index)
				continue
			end
			local ok, result = pcall(stepOfficer, officer, player, character, position, now, dt)
			if not ok then
				warn(("[GHOSTNET] Polizist-Schritt fehlgeschlagen: %s"):format(tostring(result)))
			elseif result == true then
				arrested = true
			end
		end
		if arrested then
			clearChase(player)
			continue
		end

		-- Gefasst per Streifenwagen: nur, wenn niemand ausgestiegen ist.
		-- Sonst wird man zweimal gleichzeitig festgenommen.
		if #chase.Officers == 0 and closest <= P.CatchRange then
			chase.InRange += dt
			if chase.InRange >= P.CatchSeconds then
				if not ArrestService.Arrest(player) then
					-- Keine Wache getaggt: dann wenigstens die bestehende
					-- Bust-Kette, statt gar nichts zu tun.
					warn(("[GHOSTNET] %s wurde gefasst (Bust, keine Wache)."):format(player.Name))
					local profile = SaveService.Get(player)
					if profile then
						profile.Trace = 0
					end
					TraceService.Add(player, Config.Trace.Max)
				end
				clearChase(player)
				continue
			end
		else
			chase.InRange = math.max(0, chase.InRange - dt)
		end

		--== Fair bleiben ==================================================
		-- Spaetestens hier ist Schluss. Niemand wird ewig gejagt.
		if os.clock() - chase.StartedAt > P.MaxDuration then
			print(("[GHOSTNET] Fahndung auf %s laeuft aus (Zeitlimit)."):format(player.Name))
			clearChase(player)
			continue
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
		chases[player] = { Level = 0, Bonus = 0, OutOfSight = 0, InRange = 0, Units = {}, Officers = {}, Standing = 0, StartedAt = os.clock() }
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
