-- StarterPlayerScripts/World/RouteMarkers.client.luau
--!strict
-- GHOSTNET :: Die Leuchtspur auf der Strasse, die Lichtsaeule und die
-- Bezirks-Einblendung.
--
-- WARUM DAS DER WICHTIGSTE TEIL DER ORIENTIERUNG IST
--   Ein Marker am Kartenrand reicht nicht, weil niemand Karten liest. Was
--   funktioniert, ist eine Linie auf der Fahrbahn, der man einfach
--   hinterherlaeuft, und eine Lichtsaeule, die man ueber die Daecher sieht.
--
-- WARUM DER CLIENT DIE TEILE BAUT
--   Eine Route gehoert genau EINEM Spieler. Serverseitige Parts saehe jeder,
--   und man liefe durch fremde Wegweiser. Lokal erzeugte Parts sieht nur der,
--   dem sie gehoeren, und sie kosten den Server nichts.
--   Gerechnet wird die Route trotzdem serverseitig (RouteService) - der
--   Client bekommt nur eine fertige Punktliste und legt Bretter darauf.
--
-- DAS IST REINE ANZEIGE
--   Eine Linie ist kein Zugang und keine Belohnung. Wer sie manipuliert,
--   sieht einen falschen Weg und sonst nichts.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local M = Config.Map
local S = Config.Signage
local player = Players.LocalPlayer

local folder = Instance.new("Folder")
folder.Name = "GhostNet_RouteLokal"
folder.Parent = workspace

--==========================================================================
-- Die Spur
--==========================================================================

local segments: { BasePart } = {}
local routePoints: { Vector3 } = {}

local function clearRoute()
	for _, part in segments do
		part:Destroy()
	end
	table.clear(segments)
	table.clear(routePoints)
end

local function addSegment(from: Vector3, to: Vector3)
	local delta = to - from
	local length = delta.Magnitude
	if length < 0.5 then
		return
	end

	local part = Instance.new("Part")
	part.Name = "Route"
	part.Size = Vector3.new(M.RouteWidth, 0.12, length)
	part.CFrame = CFrame.lookAt(from + delta * 0.5, to) * CFrame.Angles(0, 0, 0)
	part.Color = M.RouteColour
	part.Material = Enum.Material.Neon
	part.Transparency = M.RouteTransparency
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Parent = folder
	table.insert(segments, part)
end

-- Die Punktliste in kurze Stuecke zerlegen, damit die Spur der Strasse folgt
-- und einzelne Stuecke hinter dem Spieler verblassen koennen.
local function buildRoute(points: { Vector3 })
	clearRoute()
	if #points < 2 then
		return
	end

	local height = Config.City.RoadThickness * 0.5 + M.RouteHeight

	for index = 1, #points - 1 do
		local a = Vector3.new(points[index].X, height, points[index].Z)
		local b = Vector3.new(points[index + 1].X, height, points[index + 1].Z)
		local length = (b - a).Magnitude
		local steps = math.max(1, math.floor(length / M.RouteSegment))
		for step = 0, steps - 1 do
			local from = a:Lerp(b, step / steps)
			local to = a:Lerp(b, (step + 1) / steps)
			addSegment(from, to)
			table.insert(routePoints, (from + to) * 0.5)
		end
	end
end

--==========================================================================
-- Lichtsaeule ueber dem Ziel
--==========================================================================

local pillar: BasePart? = nil

local function setPillar(position: Vector3?)
	if not position then
		if pillar then
			pillar:Destroy()
			pillar = nil
		end
		return
	end

	if not pillar then
		local part = Instance.new("Part")
		part.Name = "Lichtsaeule"
		part.Shape = Enum.PartType.Cylinder
		part.Size = Vector3.new(S.PillarHeight, S.PillarRadius * 2, S.PillarRadius * 2)
		part.Color = M.RouteColour
		part.Material = Enum.Material.Neon
		part.Transparency = S.PillarTransparency
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.Parent = folder
		pillar = part
	end

	-- Zylinder liegen entlang ihrer X-Achse: aufrichten.
	;(pillar :: BasePart).CFrame = CFrame.new(position + Vector3.new(0, S.PillarHeight * 0.5, 0))
		* CFrame.Angles(0, 0, math.rad(90))
end

--==========================================================================
-- Empfangen
--==========================================================================

local target: Vector3? = nil

Remotes.RouteSync.OnClientEvent:Connect(function(payload)
	if typeof(payload) ~= "table" or typeof(payload.Points) ~= "table" or #payload.Points < 2 then
		clearRoute()
		setPillar(nil)
		target = nil
		return
	end

	buildRoute(payload.Points)
	target = payload.Points[#payload.Points]
	setPillar(target)
end)

--==========================================================================
-- Verblassen hinter dem Spieler, Aufloesen bei Ankunft
--==========================================================================

local function alivePosition(): Vector3?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root.Position
	end
	return nil
end

local accumulator = 0

RunService.Heartbeat:Connect(function(deltaTime)
	-- Gestaffelt statt jeden Frame: die Spur muss nicht 60x pro Sekunde
	-- neu bewertet werden, und sie hat bis zu hundert Stuecke.
	accumulator += deltaTime
	if accumulator < Config.Traffic.Tick then
		return
	end
	accumulator = 0

	if #segments == 0 then
		return
	end
	local position = alivePosition()
	if not position then
		return
	end

	-- Angekommen: die Spur loest sich auf. Ohne das bleibt sie liegen und
	-- der Spieler laeuft im Kreis.
	if target and (Vector3.new(target.X, position.Y, target.Z) - position).Magnitude <= M.RouteArrivalRange then
		clearRoute()
		setPillar(nil)
		target = nil
		return
	end

	-- Naechstes Stueck der Spur suchen. Alles davor liegt hinter dem
	-- Spieler und wird blass - sonst sehen Hin- und Rueckweg gleich aus.
	local nearest = 1
	local best = math.huge
	for index, point in routePoints do
		local distance = (Vector3.new(point.X, position.Y, point.Z) - position).Magnitude
		if distance < best then
			nearest, best = index, distance
		end
	end

	for index, part in segments do
		part.Transparency = if index < nearest then M.RouteFadeBehind else M.RouteTransparency
	end
end)

--==========================================================================
-- Bezirksname beim Betreten
--==========================================================================

local UITheme = require(ReplicatedStorage.Shared.UITheme)

local toastGui = UITheme.Screen("GhostNetDistrict", 4)
toastGui.Parent = player:WaitForChild("PlayerGui")

local toast = UITheme.Label({
	Name = "Bezirk",
	Text = "",
	TextColor3 = UITheme.Color.Text,
	TextSize = 22,
	TextTransparency = 1,
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.new(0, 24, 1, -120),
	Size = UDim2.fromOffset(420, 28),
	ZIndex = 5,
})
toast.Parent = toastGui

local toastToken = 0

Remotes.DistrictEnter.OnClientEvent:Connect(function(payload)
	if typeof(payload) ~= "table" or typeof(payload.Name) ~= "string" then
		return
	end

	toastToken += 1
	local token = toastToken
	toast.Text = payload.Name:upper()
	toast.TextTransparency = 0

	task.delay(S.DistrictToastSeconds, function()
		if token ~= toastToken then
			return
		end
		-- Ausblenden in kleinen Schritten statt per Tween: ein Tween auf
		-- TextTransparency waere hier derselbe Aufwand mit mehr Zeilen.
		for step = 1, 10 do
			if token ~= toastToken then
				return
			end
			toast.TextTransparency = step / 10
			task.wait(S.DistrictToastFade / 10)
		end
	end)
end)
