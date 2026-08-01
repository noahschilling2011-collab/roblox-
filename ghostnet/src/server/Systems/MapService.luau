-- ServerScriptService/Systems/MapService.luau
--!strict
-- GHOSTNET :: Was steht wo - einmal serverseitig gesammelt.
--
-- WARUM DER SERVER DAS SCHICKT UND NICHT DER CLIENT ES SELBST SUCHT
--   Mit StreamingEnabled hat der Client entfernte Teile gar nicht geladen.
--   Eine Karte, die per CollectionService im Workspace nachschaut, wuerde
--   also genau das zeigen, was ohnehin schon zu sehen ist - und damit nichts
--   nuetzen. Deshalb sammelt der Server einmal alles ein und schickt eine
--   Liste aus Position, Art und Name.
--
-- WAS HIER NICHT DRINSTEHT
--   Keine Loesungen, keine Schwierigkeitsdetails, keine Cooldowns. Die Karte
--   verraet WO etwas steht, nicht WIE man es knackt. Ein Hack-Ziel ist ohnehin
--   ein sichtbares Objekt in der Welt - das ist kein Geheimnis.
--
-- KEIN EIGENER TAKT
--   Die Welt aendert sich fast nie: Objekte werden beim Serverstart gebaut.
--   Deshalb wird nur bei Tag-Aenderungen neu gesammelt, und das gebuendelt
--   (Config.Map.SyncDebounce) - sonst feuert der Weltaufbau hunderte Pakete.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local RoadNetwork = require(script.Parent.RoadNetwork)

local MapService = {}

local M = Config.Map

type Poi = {
	Kind: string,
	Name: string,
	X: number,
	Z: number,
}

-- Einmal gerechnet und dann wiederverwendet: die Liste aendert sich nur,
-- wenn jemand ein getaggtes Objekt hinzufuegt oder entfernt.
local cached: { [string]: any }? = nil
local dirty = true
local pending = false

--==========================================================================
-- Sammeln
--==========================================================================

local function positionOf(instance: Instance): Vector3?
	if instance:IsA("BasePart") then
		return instance.Position
	end
	if instance:IsA("Model") then
		local ok, pivot = pcall(function()
			return instance:GetPivot()
		end)
		if ok then
			return pivot.Position
		end
	end
	return nil
end

local function labelOf(instance: Instance, fallback: string): string
	local display = instance:GetAttribute("DisplayName")
	if typeof(display) == "string" and display ~= "" then
		return display
	end
	return fallback
end

local function collect(tag: string, kind: string, fallback: string, into: { Poi }, limit: number?)
	local count = 0
	for _, instance in CollectionService:GetTagged(tag) do
		if limit and count >= limit then
			break
		end
		if not instance:IsDescendantOf(workspace) then
			continue
		end
		local position = positionOf(instance)
		if not position then
			continue
		end

		-- Offen stehende Ziele bekommen eine eigene Farbe: der Spieler soll
		-- auf der Karte sehen koennen, wo mehr Geld und mehr Risiko liegt.
		local resolved = kind
		if kind == "TARGET" and instance:GetAttribute("Exposed") == true then
			resolved = "EXPOSED"
		end

		table.insert(into, {
			Kind = resolved,
			Name = labelOf(instance, fallback),
			-- Nur X und Z. Die Karte ist zweidimensional, und jedes Feld,
			-- das nicht geschickt wird, ist gespartes Netzwerk.
			X = math.round(position.X),
			Z = math.round(position.Z),
		})
		count += 1
	end
end

local function build(): { [string]: any }
	local pois: { Poi } = {}

	collect(Config.FenceTag, "FENCE", "Hehler", pois)
	collect(Config.DealerTag, "DEALER", "Autohaus", pois)
	collect(Config.VehicleSpawnTag, "GARAGE", "Garage", pois)
	collect(Config.ContactTag, "CONTACT", "Kontakt", pois)
	-- Ziele zuletzt und begrenzt: davon gibt es die meisten, und bei einer
	-- Punktwolke sieht man die wichtigen Orte nicht mehr.
	collect(Config.HackableTag, "TARGET", "Ziel", pois, M.MaxTargets)

	-- Strassennetz. Kommt aus demselben Graphen, auf dem Verkehr und Polizei
	-- fahren - es kann also gar keine zweite, abweichende Karte geben.
	local nodes: { { number } } = {}
	local edges: { { number } } = {}
	local seen: { [string]: boolean } = {}

	for _, node in RoadNetwork.All() do
		nodes[node.Id] = { math.round(node.Position.X), math.round(node.Position.Z) }
		for _, linkId in node.Links do
			local key = if node.Id < linkId
				then ("%d-%d"):format(node.Id, linkId)
				else ("%d-%d"):format(linkId, node.Id)
			if seen[key] then
				continue
			end
			seen[key] = true
			table.insert(edges, { node.Id, linkId })
		end
	end

	return {
		Nodes = nodes,
		Edges = edges,
		Pois = pois,
	}
end

local function data(): { [string]: any }
	if dirty or not cached then
		cached = build()
		dirty = false
	end
	return cached :: { [string]: any }
end

--==========================================================================
-- Senden
--==========================================================================

function MapService.SyncTo(player: Player)
	if player.Parent then
		Remotes.MapSync:FireClient(player, data())
	end
end

local function broadcast()
	local payload = data()
	for _, player in Players:GetPlayers() do
		Remotes.MapSync:FireClient(player, payload)
	end
end

-- Gebuendelt: der Weltaufbau taggt hunderte Objekte hintereinander, und
-- jedes einzeln zu senden waere sinnlos teuer.
local function markDirty()
	dirty = true
	if pending then
		return
	end
	pending = true
	task.delay(M.SyncDebounce, function()
		pending = false
		broadcast()
	end)
end

--==========================================================================

function MapService.Init()
	for _, tag in { Config.HackableTag, Config.FenceTag, Config.DealerTag, Config.VehicleSpawnTag, Config.ContactTag } do
		CollectionService:GetInstanceAddedSignal(tag):Connect(markDirty)
		CollectionService:GetInstanceRemovedSignal(tag):Connect(markDirty)
	end

	Players.PlayerAdded:Connect(function(player)
		-- Kurz warten: beim Beitritt waehrend des Weltaufbaus waere die
		-- Liste sonst halb leer, und nachgeliefert wird erst beim naechsten
		-- Tag-Ereignis.
		task.delay(M.SyncDebounce, MapService.SyncTo, player)
	end)
	for _, player in Players:GetPlayers() do
		task.defer(MapService.SyncTo, player)
	end

	print("[GHOSTNET] MapService bereit.")
end

return MapService
