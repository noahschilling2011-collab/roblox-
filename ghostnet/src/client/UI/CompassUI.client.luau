-- StarterPlayerScripts/UI/CompassUI.client.luau
--!strict
-- GHOSTNET :: Die Kompassleiste oben.
--
-- WOFUER
--   Die Minikarte sagt, WO etwas liegt. Die Kompassleiste sagt, ob man
--   gerade in die richtige Richtung schaut - und wie weit es noch ist.
--   Zusammen braucht ein neuer Spieler niemanden mehr zu fragen.
--
-- WAS DRAUFSTEHT
--   Himmelsrichtungen als Raster, darauf jeder bekannte Ort, der im
--   Blickfeld liegt, mit Entfernung in Metern. Das aktuelle Missionsziel
--   ist hervorgehoben und laeuft nie aus dem Bild - es klebt am Rand, wenn
--   es hinter einem liegt.
--
-- LEISTUNG
--   Feste Anzahl Marker, die recycelt werden. Es wird nie eine Instanz
--   erzeugt oder geloescht, waehrend man laeuft - nur Position, Text und
--   Sichtbarkeit geaendert.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Icons = require(ReplicatedStorage.Shared.Icons)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local UITheme = require(ReplicatedStorage.Shared.UITheme)

local M = Config.Map
local player = Players.LocalPlayer

local kindById: { [string]: any } = {}
for _, kind in M.Kinds do
	kindById[kind.Id] = kind
end

--==========================================================================
-- Aufbau
--==========================================================================

local gui = UITheme.Screen("GhostNetCompass", 5)
gui.Parent = player:WaitForChild("PlayerGui")

local bar = UITheme.Frame({
	Name = "Kompass",
	BackgroundColor3 = UITheme.Color.Background,
	BackgroundTransparency = 0.35,
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 8),
	Size = UDim2.new(M.CompassWidth, 0, 0, M.CompassHeight),
	ClipsDescendants = true,
	ZIndex = 3,
})
UITheme.Corner(bar, 4)
UITheme.Stroke(bar, UITheme.Color.Line, 1)
bar.Parent = gui

-- Mittelstrich: die Blickrichtung.
local centreTick = UITheme.Frame({
	Name = "Mitte",
	BackgroundColor3 = UITheme.Color.Cyan,
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.fromScale(0.5, 0),
	Size = UDim2.new(0, 2, 1, 0),
	ZIndex = 8,
})
centreTick.Parent = bar

--== Himmelsrichtungen =====================================================

local CARDINALS = {
	{ Text = "N", Bearing = 0 },
	{ Text = "NO", Bearing = 45 },
	{ Text = "O", Bearing = 90 },
	{ Text = "SO", Bearing = 135 },
	{ Text = "S", Bearing = 180 },
	{ Text = "SW", Bearing = 225 },
	{ Text = "W", Bearing = 270 },
	{ Text = "NW", Bearing = 315 },
}

local cardinalLabels: { TextLabel } = {}
for _, entry in CARDINALS do
	local label = UITheme.Label({
		Name = entry.Text,
		Text = entry.Text,
		TextColor3 = UITheme.Color.TextDim,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Center,
		AnchorPoint = Vector2.new(0.5, 0),
		Size = UDim2.fromOffset(28, M.CompassHeight),
		ZIndex = 4,
	})
	label.Parent = bar
	table.insert(cardinalLabels, label)
end

--== Marker-Pool ===========================================================

type Slot = {
	Holder: Frame,
	Icon: Frame?,
	Label: TextLabel,
	Kind: string,
}

local slots: { Slot } = {}
for index = 1, M.CompassMaxMarkers do
	local holder = UITheme.Frame({
		Name = ("Marker%d"):format(index),
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Size = UDim2.fromOffset(70, M.CompassHeight),
		Visible = false,
		ZIndex = 6,
	})
	holder.Parent = bar

	local label = UITheme.Label({
		Name = "Entfernung",
		Text = "",
		TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Center,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, 0),
		Size = UDim2.new(1, 0, 0, 12),
		ZIndex = 7,
	})
	label.Parent = holder

	table.insert(slots, { Holder = holder, Icon = nil, Label = label, Kind = "" })
end

--==========================================================================
-- Daten
--==========================================================================

type Point = {
	Kind: string,
	X: number,
	Z: number,
	Priority: number,
}

local points: { Point } = {}
local waypoint: Vector3? = nil

Remotes.MapSync.OnClientEvent:Connect(function(payload)
	if typeof(payload) ~= "table" or typeof(payload.Pois) ~= "table" then
		return
	end
	table.clear(points)
	for _, poi in payload.Pois do
		local kind = kindById[poi.Kind]
		if not kind then
			continue
		end
		-- Hack-Ziele bleiben von der Leiste weg: davon gibt es Dutzende und
		-- sie wuerden alles zukleistern, was wirklich wichtig ist.
		if poi.Kind == "TARGET" or poi.Kind == "EXPOSED" then
			continue
		end
		table.insert(points, { Kind = poi.Kind, X = poi.X, Z = poi.Z, Priority = kind.Order })
	end
end)

Remotes.WaypointSync.OnClientEvent:Connect(function(payload)
	waypoint = if typeof(payload) == "table" and typeof(payload.Position) == "Vector3"
		then payload.Position
		else nil
end)

--==========================================================================
-- Zeichnen
--==========================================================================

local function alivePosition(): Vector3?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root.Position
	end
	return nil
end

-- Winkeldifferenz auf -180..180 bringen, damit ein Marker hinter einem nicht
-- ploetzlich am falschen Rand auftaucht.
local function wrap(angle: number): number
	return (angle + 180) % 360 - 180
end

local function setSlot(slot: Slot, kind: any, offset: number, distance: number, highlight: boolean)
	if slot.Kind ~= kind.Id then
		if slot.Icon then
			slot.Icon:Destroy()
		end
		local icon = Icons.Build(kind.Shape, kind.Colour, 14)
		icon.Position = UDim2.new(0.5, 0, 0, 10)
		icon.ZIndex = 7
		icon.Parent = slot.Holder
		slot.Icon = icon
		slot.Kind = kind.Id
	end

	slot.Holder.Position = UDim2.new(offset, 0, 0, 0)
	slot.Holder.Visible = true
	-- Meter statt Studs: der Spieler denkt nicht in Studs.
	slot.Label.Text = ("%dm"):format(math.round(distance))
	slot.Label.TextColor3 = if highlight then UITheme.Color.Text else UITheme.Color.TextDim
	if slot.Icon then
		Icons.SetTransparency(slot.Icon, if highlight then 0 else 0.35)
	end
end

RunService.RenderStepped:Connect(function()
	local position = alivePosition()
	local camera = workspace.CurrentCamera
	if not position or not camera then
		bar.Visible = false
		return
	end
	bar.Visible = true

	local look = camera.CFrame.LookVector
	local heading = math.deg(math.atan2(look.X, look.Z))

	-- Himmelsrichtungen aufs Band legen.
	for index, entry in CARDINALS do
		local delta = wrap(entry.Bearing - heading)
		local label = cardinalLabels[index]
		if math.abs(delta) > M.CompassFov * 0.5 then
			label.Visible = false
		else
			label.Visible = true
			label.Position = UDim2.fromScale(0.5 + delta / M.CompassFov, 0)
		end
	end

	-- Kandidaten einsammeln: alles im Blickfeld und in Reichweite.
	type Candidate = { Kind: any, Offset: number, Distance: number, Highlight: boolean, Sort: number }
	local candidates: { Candidate } = {}

	local function consider(kindId: string, x: number, z: number, highlight: boolean)
		local kind = kindById[kindId]
		if not kind then
			return
		end
		local dx, dz = x - position.X, z - position.Z
		local distance = math.sqrt(dx * dx + dz * dz)
		if not highlight and distance > M.CompassRange then
			return
		end
		local bearing = math.deg(math.atan2(dx, dz))
		local delta = wrap(bearing - heading)
		if not highlight and math.abs(delta) > M.CompassFov * 0.5 then
			return
		end
		-- Das Missionsziel klebt am Rand, statt zu verschwinden: sonst
		-- weiss man nicht, in welche Richtung man sich drehen muss.
		local clamped = math.clamp(delta, -M.CompassFov * 0.5, M.CompassFov * 0.5)
		table.insert(candidates, {
			Kind = kind,
			Offset = 0.5 + clamped / M.CompassFov,
			Distance = distance,
			Highlight = highlight,
			-- Wichtiges zuerst, danach das Naechste.
			Sort = (if highlight then -1e9 else 0) - kind.Order * 1000 + distance,
		})
	end

	if waypoint then
		consider("WAYPOINT", waypoint.X, waypoint.Z, true)
	end
	for _, point in points do
		consider(point.Kind, point.X, point.Z, false)
	end

	table.sort(candidates, function(a, b)
		return a.Sort < b.Sort
	end)

	for index, slot in slots do
		local candidate = candidates[index]
		if candidate then
			setSlot(slot, candidate.Kind, candidate.Offset, candidate.Distance, candidate.Highlight)
		else
			slot.Holder.Visible = false
		end
	end
end)
