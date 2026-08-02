-- ServerScriptService/Systems/RouteService.luau
--!strict
-- GHOSTNET :: Die Route zum Ziel.
--
-- DER WICHTIGSTE EINZELPUNKT DER ORIENTIERUNG
--   Ein Marker am Kartenrand reicht nicht. Niemand liest Karten. Der Spieler
--   braucht eine Linie auf der Strasse, der er einfach folgen kann.
--
-- WER RECHNET, WER ZEICHNET
--   Der SERVER rechnet die Route ueber den bestehenden RoadNetwork-Graphen -
--   derselbe Graph, auf dem Verkehr und Polizei fahren. Es gibt kein zweites
--   Wegenetz, das auseinanderlaufen koennte.
--
--   Der CLIENT zeichnet die Leuchtspur. Das ist kein Detail: eine Route ist
--   PRO SPIELER verschieden. Serverseitige Parts saehe jeder - dann liefe
--   man durch fremde Wegweiser. Lokal erzeugte Parts sieht nur der, dem sie
--   gehoeren, und sie kosten den Server gar nichts.
--
-- KEIN TAKT
--   Gerechnet wird nur, wenn jemand ein Ziel setzt oder eine Mission einen
--   Wegpunkt bekommt. Ankunft prueft der Client optisch; wegnehmen tut die
--   Route der Server, wenn die Mission weiterspringt.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Geometry = require(ReplicatedStorage.Shared.Geometry)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local RateLimiter = require(script.Parent.RateLimiter)
local RoadNetwork = require(script.Parent.RoadNetwork)

local RouteService = {}

local M = Config.Map

type Route = {
	Target: Vector3,
	Label: string,
}

local routes: { [Player]: Route } = {}

--==========================================================================

local function send(player: Player, points: { Vector3 }?, label: string)
	if not player.Parent then
		return
	end
	Remotes.RouteSync:FireClient(player, {
		Points = points,
		Label = label,
	})
end

-- Setzt (oder loescht, wenn target nil ist) die Route eines Spielers.
-- Wird auch vom MissionService aufgerufen, wenn ein Auftrag startet.
function RouteService.SetTarget(player: Player, target: Vector3?, label: string?)
	if not target then
		routes[player] = nil
		send(player, nil, "")
		return
	end

	local from = Geometry.AlivePosition(player)
	if not from then
		return
	end

	local points = RoadNetwork.RouteBetween(from, target)
	if not points then
		-- Kein Weg gefunden: dann wenigstens die Luftlinie, statt dem
		-- Spieler gar nichts zu zeigen.
		points = { Vector3.new(from.X, 0, from.Z), Vector3.new(target.X, 0, target.Z) }
	end

	-- Notbremse: eine absurd lange Route waere nur eine Leuchtwand.
	while #points > M.RouteMaxNodes do
		table.remove(points)
	end

	routes[player] = { Target = target, Label = label or "" }
	send(player, points, label or "")
end

function RouteService.Clear(player: Player)
	RouteService.SetTarget(player, nil)
end

function RouteService.GetTarget(player: Player): Vector3?
	local route = routes[player]
	return if route then route.Target else nil
end

-- Neu rechnen, ohne das Ziel zu aendern. Braucht man nach einem Respawn oder
-- einer Festnahme, weil der Startpunkt dann ein ganz anderer ist.
function RouteService.Recalculate(player: Player)
	local route = routes[player]
	if route then
		RouteService.SetTarget(player, route.Target, route.Label)
	end
end

--==========================================================================

local function onRouteRequest(player: Player, payload: any)
	if not RateLimiter.Check(player, "RouteRequest") then
		return
	end
	if typeof(payload) ~= "table" then
		return
	end

	-- Leeres Paket = Route loeschen.
	if payload.X == nil and payload.Z == nil then
		RouteService.Clear(player)
		return
	end

	if typeof(payload.X) ~= "number" or typeof(payload.Z) ~= "number" then
		return
	end
	if payload.X ~= payload.X or payload.Z ~= payload.Z then
		return -- NaN
	end

	-- Der Client sagt nur "dort hin will ich". Er bekommt dadurch keinen
	-- Vorteil: eine Route ist eine Linie, keine Belohnung und kein Zugang.
	local limit = Config.City.Grid * Config.City.BlockSize
	local x = math.clamp(payload.X, -limit, limit)
	local z = math.clamp(payload.Z, -limit, limit)

	RouteService.SetTarget(player, Vector3.new(x, 0, z), "Eigenes Ziel")
end

function RouteService.Init()
	Remotes.RouteRequest.OnServerEvent:Connect(onRouteRequest)

	Players.PlayerRemoving:Connect(function(player)
		routes[player] = nil
	end)

	print("[GHOSTNET] RouteService bereit.")
end

return RouteService
