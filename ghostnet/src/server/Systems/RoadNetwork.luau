-- ServerScriptService/Systems/RoadNetwork.luau
--!strict
-- GHOSTNET :: Der Strassengraph.
--
-- WARUM DAS EIN GRAPH IST UND KEINE PATHFINDING-ABFRAGE
--   Ein Pfad pro Auto, mehrfach pro Sekunde neu berechnet, frisst den Server
--   bei zweistelliger Fahrzeugzahl auf. Stattdessen liegt hier ein fester
--   Graph aus Kreuzungen und gerichteten Kanten. Ein Verkehrsauto folgt
--   Kante fuer Kante und wuerfelt an jeder Kreuzung - das kostet praktisch
--   nichts und sieht trotzdem lebendig aus.
--
--   Derselbe Graph traegt in Phase 6 die Streifenwagen. Deshalb liegt er
--   hier und nicht im TrafficService.
--
-- Der Graph wird BERECHNET, nicht aus der Welt gelesen. Kein Suchen nach
-- getaggten Parts, keine Instanzen fuer Wegpunkte - nur Zahlen.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Districts = require(ReplicatedStorage.Shared.Districts)

local RoadNetwork = {}

export type Node = {
	Id: number,
	GridX: number,
	GridZ: number,
	Position: Vector3,
	Links: { number }, -- Ids der erreichbaren Nachbarkreuzungen
}

local nodes: { Node } = {}
local byGrid: { [string]: number } = {}
local half = 0

local function key(gridX: number, gridZ: number): string
	return ("%d,%d"):format(gridX, gridZ)
end

--==========================================================================
-- Aufbau
--==========================================================================

function RoadNetwork.Build()
	if #nodes > 0 then
		return
	end

	local grid = Config.City.Grid
	local block = Config.City.BlockSize
	half = math.floor(grid / 2)

	-- Kreuzungen als Gitter. Die Mitte liegt bei (0,0), damit der Spawn im
	-- Zentrum der Altstadt steht.
	for gz = -half, half do
		for gx = -half, half do
			local node: Node = {
				Id = #nodes + 1,
				GridX = gx,
				GridZ = gz,
				Position = Vector3.new(gx * block, 0, gz * block),
				Links = {},
			}
			table.insert(nodes, node)
			byGrid[key(gx, gz)] = node.Id
		end
	end

	-- Kanten zu den vier direkten Nachbarn. Beide Richtungen, damit der
	-- Verkehr an einer Kreuzung immer weiterkommt und nie feststeckt.
	for _, node in nodes do
		for _, offset in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
			local neighbour = byGrid[key(node.GridX + offset[1], node.GridZ + offset[2])]
			if neighbour then
				table.insert(node.Links, neighbour)
			end
		end
	end
end

--==========================================================================
-- Abfragen
--==========================================================================

function RoadNetwork.Count(): number
	return #nodes
end

function RoadNetwork.Get(id: number): Node?
	return nodes[id]
end

function RoadNetwork.All(): { Node }
	return nodes
end

function RoadNetwork.Links(id: number): { number }
	local node = nodes[id]
	return if node then node.Links else {}
end

-- Naechste Kreuzung zu einer Weltposition. Ueber das Gitter gerechnet statt
-- durch Durchsuchen aller Knoten - das laeuft im Verkehrstakt.
function RoadNetwork.NearestNode(position: Vector3): Node?
	if #nodes == 0 then
		return nil
	end
	local block = Config.City.BlockSize
	local gx = math.clamp(math.round(position.X / block), -half, half)
	local gz = math.clamp(math.round(position.Z / block), -half, half)
	local id = byGrid[key(gx, gz)]
	return if id then nodes[id] else nil
end

function RoadNetwork.RandomNode(rng: Random): Node?
	if #nodes == 0 then
		return nil
	end
	return nodes[rng:NextInteger(1, #nodes)]
end

-- Ein zufaelliger Nachbar, moeglichst nicht der, aus dem man gerade kam.
-- Ohne das drehen die Autos an jeder Kreuzung um und der Verkehr wirkt kaputt.
function RoadNetwork.NextNode(fromId: number, cameFrom: number?, rng: Random): number?
	local links = RoadNetwork.Links(fromId)
	if #links == 0 then
		return nil
	end
	if #links == 1 then
		return links[1]
	end

	local options: { number } = {}
	for _, id in links do
		if id ~= cameFrom then
			table.insert(options, id)
		end
	end
	if #options == 0 then
		return links[rng:NextInteger(1, #links)]
	end
	return options[rng:NextInteger(1, #options)]
end

-- Ein Schritt Richtung Ziel. Kein A*, nur "welcher Nachbar liegt naeher" -
-- das reicht auf einem Gitter voellig und kostet nichts. Damit fahren die
-- Streifenwagen in Phase 6 zum Spieler.
function RoadNetwork.StepToward(fromId: number, target: Vector3): number?
	local links = RoadNetwork.Links(fromId)
	local best: number? = nil
	local bestDistance = math.huge
	for _, id in links do
		local node = nodes[id]
		if node then
			local distance = (node.Position - target).Magnitude
			if distance < bestDistance then
				best, bestDistance = id, distance
			end
		end
	end
	return best
end

-- Fahrspur: rechts der Mitte, damit Gegenverkehr nicht ineinander faehrt.
function RoadNetwork.LanePosition(fromId: number, toId: number, alpha: number): (Vector3?, Vector3?)
	local a = nodes[fromId]
	local b = nodes[toId]
	if not a or not b then
		return nil, nil
	end
	local direction = (b.Position - a.Position)
	local length = direction.Magnitude
	if length < 0.01 then
		return nil, nil
	end
	local unit = direction / length
	local right = Vector3.new(-unit.Z, 0, unit.X)
	local offset = right * Config.City.LaneOffset
	return a.Position + offset + unit * (length * alpha), unit
end

-- In welchem Bezirk liegt diese Position?
function RoadNetwork.DistrictAt(position: Vector3): Districts.District?
	local block = Config.City.BlockSize
	return Districts.At(math.round(position.X / block), math.round(position.Z / block))
end

--==========================================================================
-- Wegsuche
--
-- Dijkstra ueber denselben Graphen, auf dem Verkehr und Polizei fahren. Es
-- gibt keinen zweiten, abweichenden Wegenetz-Datensatz - und weil das Netz
-- ein Raster mit wenigen Dutzend Knoten ist, reicht Dijkstra locker; A*
-- waere hier nur mehr Code fuer denselben Weg.
--
-- Laeuft nur, wenn jemand ein Ziel setzt. Kein Takt, keine Dauerlast.
--==========================================================================

function RoadNetwork.FindPath(fromId: number, toId: number): { number }?
	if not nodes[fromId] or not nodes[toId] then
		return nil
	end
	if fromId == toId then
		return { fromId }
	end

	local distance: { [number]: number } = {}
	local previous: { [number]: number } = {}
	local visited: { [number]: boolean } = {}
	distance[fromId] = 0

	while true do
		-- Kleinster offener Knoten. Lineare Suche ist bei dieser Groesse
		-- schneller als eine Halde und deutlich einfacher zu lesen.
		local current: number? = nil
		local best = math.huge
		for id, cost in distance do
			if not visited[id] and cost < best then
				current, best = id, cost
			end
		end
		if not current then
			return nil -- nicht erreichbar
		end
		if current == toId then
			break
		end
		visited[current] = true

		local node = nodes[current]
		for _, linkId in node.Links do
			if visited[linkId] then
				continue
			end
			local neighbour = nodes[linkId]
			if not neighbour then
				continue
			end
			local step = best + (neighbour.Position - node.Position).Magnitude
			if step < (distance[linkId] or math.huge) then
				distance[linkId] = step
				previous[linkId] = current
			end
		end
	end

	local path: { number } = { toId }
	local walk = toId
	while walk ~= fromId do
		local before = previous[walk]
		if not before then
			return nil
		end
		table.insert(path, 1, before)
		walk = before
	end
	return path
end

-- Bequemer Einstieg: von einer Weltposition zur naechsten. Gibt die
-- Stuetzpunkte als Weltpositionen zurueck, inklusive Start und Ziel selbst,
-- damit die Linie nicht erst auf halber Strecke anfaengt.
function RoadNetwork.RouteBetween(from: Vector3, to: Vector3): { Vector3 }?
	local startNode = RoadNetwork.NearestNode(from)
	local goalNode = RoadNetwork.NearestNode(to)
	if not startNode or not goalNode then
		return nil
	end

	local ids = RoadNetwork.FindPath(startNode.Id, goalNode.Id)
	if not ids then
		return nil
	end

	local points: { Vector3 } = { Vector3.new(from.X, 0, from.Z) }
	for _, id in ids do
		local node = nodes[id]
		if node then
			table.insert(points, node.Position)
		end
	end
	table.insert(points, Vector3.new(to.X, 0, to.Z))
	return points
end

function RoadNetwork.Init()
	local valid, errors = Districts.Validate()
	if not valid then
		for _, message in errors do
			warn(("[GHOSTNET] Bezirke: %s"):format(message))
		end
	end

	RoadNetwork.Build()
	local edges = 0
	for _, node in nodes do
		edges += #node.Links
	end
	print(("[GHOSTNET] RoadNetwork bereit. %d Kreuzungen, %d Kanten, %d Bezirke."):format(
		#nodes,
		edges,
		Districts.Count()
	))
end

return RoadNetwork
