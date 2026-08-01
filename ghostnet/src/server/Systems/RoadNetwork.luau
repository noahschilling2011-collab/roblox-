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
