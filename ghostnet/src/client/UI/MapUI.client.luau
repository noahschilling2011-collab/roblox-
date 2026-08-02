-- StarterPlayerScripts/UI/MapUI.client.luau
--!strict
-- GHOSTNET :: Minikarte, grosse Karte, Legende.
--
-- MINIKARTE
--   Oben rechts, dauerhaft an, nicht wegklickbar. Dreht sich mit der
--   Blickrichtung - eine genordete Karte ist beim Fahren praktisch nicht
--   lesbar. Ein kleiner Pfeil zeigt, wo Norden liegt.
--   Zwei Zoomstufen, automatisch: zu Fuss nah dran, im Auto weiter weg.
--
-- GROSSE KARTE  [M]
--   Ganze Stadt, Bezirksnamen, Legende. Antippen setzt ein eigenes Ziel -
--   der Server rechnet die Route und der Spieler bekommt eine Linie auf die
--   Strasse (siehe RouteMarkers).
--
-- KEIN ViewportFrame
--   Eine zweite Kamera waere teuer, und mit StreamingEnabled saehe sie
--   entfernte Teile ohnehin nicht. Gezeichnet wird 2D aus den
--   MapService-Daten: Strassen als gedrehte Frames, Orte als Symbole aus
--   Shared/Icons. Keine einzige Asset-Id noetig.
--
-- LEISTUNG
--   Der Inhalt wird EINMAL gebaut. Pro Bild werden nur Position und Drehung
--   des Inhalts-Containers gesetzt - nicht die hundert Strassen darin.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Districts = require(ReplicatedStorage.Shared.Districts)
local Icons = require(ReplicatedStorage.Shared.Icons)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local UITheme = require(ReplicatedStorage.Shared.UITheme)

local M = Config.Map
local player = Players.LocalPlayer

--==========================================================================
-- Kartenarten
--==========================================================================

local kindById: { [string]: any } = {}
for _, kind in M.Kinds do
	kindById[kind.Id] = kind
end

local function kindOf(id: string): any
	return kindById[id]
end

local CITY_HALF = (Config.City.Grid - 1) * 0.5 * Config.City.BlockSize + Config.City.BlockSize * 0.5

--==========================================================================
-- Ein Kartenfenster
--==========================================================================

type Surface = {
	Holder: GuiObject,
	World: Frame,
	Scale: number,
	Icons: number,
	RoadWidth: number,
	Rotates: boolean,
	Player: Frame,
}

local function toPixels(surface: Surface, x: number, z: number): (number, number)
	return x * surface.Scale, z * surface.Scale
end

local function drawRoad(surface: Surface, ax: number, az: number, bx: number, bz: number)
	local x1, z1 = toPixels(surface, ax, az)
	local x2, z2 = toPixels(surface, bx, bz)
	local dx, dz = x2 - x1, z2 - z1
	local length = math.sqrt(dx * dx + dz * dz)
	if length < 1 then
		return
	end

	local road = UITheme.Frame({
		Name = "Strasse",
		BackgroundColor3 = UITheme.Color.Line,
		BackgroundTransparency = M.RoadTransparency,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset((x1 + x2) * 0.5, (z1 + z2) * 0.5),
		Size = UDim2.fromOffset(length, surface.RoadWidth),
		Rotation = math.deg(math.atan2(dz, dx)),
		ZIndex = 2,
	})
	road.Parent = surface.World
end

local function drawDistrict(surface: Surface, district: Districts.District)
	local block = Config.City.BlockSize
	local extent = (district.Radius * 2 + 1) * block
	local x, z = toPixels(surface, district.GridX * block, district.GridZ * block)

	local area = UITheme.Frame({
		Name = district.Id,
		BackgroundColor3 = district.Neon,
		BackgroundTransparency = M.DistrictTransparency,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(x, z),
		Size = UDim2.fromOffset(extent * surface.Scale, extent * surface.Scale),
		ZIndex = 1,
	})
	UITheme.Corner(area, 4)
	area.Parent = surface.World

	if not surface.Rotates then
		local label = UITheme.Label({
			Name = "Name",
			Text = district.Name:upper(),
			TextColor3 = district.Neon,
			TextSize = M.DistrictLabelSize,
			TextTransparency = 0.25,
			TextXAlignment = Enum.TextXAlignment.Center,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(x, z - extent * surface.Scale * 0.5 + 12),
			Size = UDim2.fromOffset(180, 16),
			ZIndex = 3,
		})
		label.Parent = surface.World
	end
end

local function drawPoi(surface: Surface, poi: { [string]: any })
	local kind = kindOf(poi.Kind)
	if not kind then
		return
	end
	local x, z = toPixels(surface, poi.X, poi.Z)

	local icon = Icons.Build(kind.Shape, kind.Colour, surface.Icons)
	icon.Position = UDim2.fromOffset(x, z)
	icon.ZIndex = 4 + kind.Order
	icon.Parent = surface.World

	-- Namen nur auf der grossen Karte, und nicht fuer Hack-Ziele: davon gibt
	-- es Dutzende, und beschriftet waere die Karte unlesbar.
	if not surface.Rotates and poi.Kind ~= "TARGET" and poi.Kind ~= "EXPOSED" then
		local label = UITheme.Label({
			Name = "Name",
			Text = poi.Name,
			TextColor3 = kind.Colour,
			TextSize = 11,
			TextXAlignment = Enum.TextXAlignment.Center,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromOffset(x, z + surface.Icons * 0.7),
			Size = UDim2.fromOffset(160, 14),
			ZIndex = 14,
		})
		label.Parent = surface.World
	end
end

--==========================================================================
-- Aufbau
--==========================================================================

local gui = UITheme.Screen("GhostNetMap", 6)
gui.Parent = player:WaitForChild("PlayerGui")

--== Minikarte, oben rechts, dauerhaft =====================================

local miniButton = UITheme.Button({
	Name = "Minikarte",
	BackgroundColor3 = M.Background,
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -M.MiniMargin, 0, M.MiniMargin),
	Size = UDim2.fromOffset(M.MiniSize, M.MiniSize),
	ClipsDescendants = true,
	ZIndex = 2,
})
UITheme.Corner(miniButton, 6)
UITheme.Stroke(miniButton, UITheme.Color.Line, 1)
miniButton.Parent = gui

local miniWorld = UITheme.Frame({
	Name = "Inhalt",
	BackgroundTransparency = 1,
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(0, 0),
	ZIndex = 2,
})
miniWorld.Parent = miniButton

-- Nordpfeil. Wenn sich die Karte dreht, muss irgendetwas fest bleiben,
-- sonst weiss man nicht mehr, wo oben ist.
local northArrow = UITheme.Label({
	Name = "Norden",
	Text = "N",
	TextColor3 = UITheme.Color.Magenta,
	TextSize = 13,
	TextXAlignment = Enum.TextXAlignment.Center,
	AnchorPoint = Vector2.new(0.5, 0.5),
	Size = UDim2.fromOffset(18, 18),
	ZIndex = 26,
})
northArrow.Parent = miniButton

local miniHint = UITheme.Label({
	Name = "Hinweis",
	Text = "[M]",
	TextColor3 = UITheme.Color.TextDim,
	TextSize = 11,
	TextXAlignment = Enum.TextXAlignment.Center,
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -2),
	Size = UDim2.new(1, 0, 0, 14),
	ZIndex = 25,
})
miniHint.Parent = miniButton

local mini: Surface = {
	Holder = miniButton,
	World = miniWorld,
	Scale = (M.MiniSize * 0.5) / M.RangeOnFoot,
	Icons = M.MiniIcon,
	RoadWidth = M.MiniRoadWidth,
	Rotates = M.Rotate,
	Player = nil :: any,
}

local function makePlayerIcon(surface: Surface): Frame
	local icon = UITheme.Frame({
		Name = "Spieler",
		BackgroundColor3 = UITheme.Color.Text,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(M.PlayerIcon, M.PlayerIcon),
		Rotation = 45,
		ZIndex = 22,
	})
	UITheme.Stroke(icon, UITheme.Color.Background, 2)
	icon.Parent = surface.Holder
	return icon
end

mini.Player = makePlayerIcon(mini)
mini.Player.Position = UDim2.fromScale(0.5, 0.5)

--== Grosse Karte ==========================================================

local backdrop = UITheme.Frame({
	Name = "Karte",
	BackgroundColor3 = UITheme.Color.Background,
	BackgroundTransparency = 0.12,
	Size = UDim2.fromScale(1, 1),
	Visible = false,
	ZIndex = 30,
})
backdrop.Parent = gui

local bigPanel = UITheme.Button({
	Name = "Blatt",
	BackgroundColor3 = M.Background,
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromScale(0.74, 0.86),
	ClipsDescendants = true,
	ZIndex = 31,
})
UITheme.Corner(bigPanel, 6)
UITheme.Stroke(bigPanel, UITheme.Color.Cyan, 1)
bigPanel.Parent = backdrop

local bigWorld = UITheme.Frame({
	Name = "Inhalt",
	BackgroundTransparency = 1,
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(0, 0),
	ZIndex = 31,
})
bigWorld.Parent = bigPanel

local bigTitle = UITheme.Label({
	Name = "Titel",
	Text = "VANTORRA  //  tippen setzt ein Ziel",
	TextColor3 = UITheme.Color.Cyan,
	TextSize = 16,
	Position = UDim2.fromOffset(14, 10),
	Size = UDim2.fromOffset(420, 22),
	ZIndex = 45,
})
bigTitle.Parent = bigPanel

local closeButton = UITheme.Button({
	Name = "Schliessen",
	Text = "[M] SCHLIESSEN",
	TextColor3 = UITheme.Color.TextDim,
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -10, 0, 10),
	Size = UDim2.fromOffset(170, 38),
	ZIndex = 45,
})
UITheme.Corner(closeButton, 4)
closeButton.Parent = bigPanel

local clearButton = UITheme.Button({
	Name = "ZielLoeschen",
	Text = "ZIEL LOESCHEN",
	TextColor3 = UITheme.Color.TextDim,
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, -10, 1, -10),
	Size = UDim2.fromOffset(170, 38),
	ZIndex = 45,
})
UITheme.Corner(clearButton, 4)
clearButton.Parent = bigPanel

-- Und die zweite Haelfte der Antwort: das Auto herrufen. Kostet Gebuehr,
-- hat einen Cooldown und geht nur an einer Strasse - alles serverseitig.
local callButton = UITheme.Button({
	Name = "FahrzeugRufen",
	Text = "FAHRZEUG RUFEN",
	TextColor3 = UITheme.Color.Amber,
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -10),
	Size = UDim2.fromOffset(200, 38),
	Visible = false,
	ZIndex = 45,
})
UITheme.Corner(callButton, 4)
callButton.Parent = bigPanel

local big: Surface = {
	Holder = bigPanel,
	World = bigWorld,
	Scale = 1,
	Icons = M.BigIcon,
	RoadWidth = M.BigRoadWidth,
	Rotates = false,
	Player = nil :: any,
}
big.Player = makePlayerIcon(big)

--== Legende ===============================================================

local legend = UITheme.Frame({
	Name = "Legende",
	BackgroundColor3 = UITheme.Color.Panel,
	BackgroundTransparency = 0.12,
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.new(0, 10, 1, -10),
	Size = UDim2.fromOffset(250, 24 + #M.Kinds * 20),
	ZIndex = 45,
})
UITheme.Corner(legend, 4)
UITheme.Stroke(legend, UITheme.Color.Line, 1)
legend.Parent = bigPanel

do
	local heading = UITheme.Label({
		Text = "LEGENDE",
		TextColor3 = UITheme.Color.TextDim,
		TextSize = 11,
		Position = UDim2.fromOffset(10, 5),
		Size = UDim2.fromOffset(220, 14),
		ZIndex = 46,
	})
	heading.Parent = legend

	for index, kind in M.Kinds do
		local y = 22 + (index - 1) * 20

		local icon = Icons.Build(kind.Shape, kind.Colour, 14)
		icon.Position = UDim2.fromOffset(18, y + 8)
		icon.ZIndex = 46
		icon.Parent = legend

		local text = UITheme.Label({
			Text = kind.Label,
			TextSize = 12,
			Position = UDim2.fromOffset(32, y),
			Size = UDim2.fromOffset(210, 16),
			ZIndex = 46,
		})
		text.Parent = legend
	end
end

--==========================================================================
-- Zeichnen
--==========================================================================

local drawn = false
local lastPayload: { [string]: any }? = nil

local function fillSurface(surface: Surface, payload: { [string]: any })
	for _, child in surface.World:GetChildren() do
		child:Destroy()
	end

	for _, district in Districts.List do
		drawDistrict(surface, district)
	end

	local nodes = payload.Nodes
	for _, edge in payload.Edges do
		local a = nodes[edge[1]]
		local b = nodes[edge[2]]
		if a and b then
			drawRoad(surface, a[1], a[2], b[1], b[2])
		end
	end

	for _, poi in payload.Pois do
		drawPoi(surface, poi)
	end
end

Remotes.MapSync.OnClientEvent:Connect(function(payload)
	if typeof(payload) ~= "table" or typeof(payload.Edges) ~= "table" then
		return
	end
	lastPayload = payload

	local side = math.min(bigPanel.AbsoluteSize.X, bigPanel.AbsoluteSize.Y)
	big.Scale = math.max((side - M.BigPadding * 2) / (CITY_HALF * 2), 0.01)

	fillSurface(mini, payload)
	fillSurface(big, payload)
	drawn = true
end)

--==========================================================================
-- Auftrags-Symbol und eigenes Ziel
--==========================================================================

local waypoint: Vector3? = nil
local ownTarget: Vector3? = nil
local myCar: Vector3? = nil
local markers: { [string]: Frame } = {}

local function refreshMarker(surface: Surface, key: string, position: Vector3?, shape: string, colour: Color3)
	local existing = markers[key]
	if existing then
		existing:Destroy()
		markers[key] = nil
	end
	if not position then
		return
	end
	local x, z = toPixels(surface, position.X, position.Z)
	local icon = Icons.Build(shape, colour, surface.Icons + 4)
	icon.Position = UDim2.fromOffset(x, z)
	icon.ZIndex = 19
	icon.Parent = surface.World
	markers[key] = icon
end

local function refreshAllMarkers()
	local star = kindOf("WAYPOINT")
	refreshMarker(mini, "mini_wp", waypoint, star.Shape, star.Colour)
	refreshMarker(big, "big_wp", waypoint, star.Shape, star.Colour)
	refreshMarker(mini, "mini_own", ownTarget, "Punkt", UITheme.Color.Cyan)
	refreshMarker(big, "big_own", ownTarget, "Punkt", UITheme.Color.Cyan)

	-- Das eigene Fahrzeug. "Wo ist mein Auto" ist der haeufigste Grund, ein
	-- Open-World-Spiel zu schliessen - der Marker ist die halbe Antwort.
	local car = kindOf("MYCAR")
	refreshMarker(mini, "mini_car", myCar, car.Shape, car.Colour)
	refreshMarker(big, "big_car", myCar, car.Shape, car.Colour)
end

Remotes.WaypointSync.OnClientEvent:Connect(function(payload)
	waypoint = if typeof(payload) == "table" and typeof(payload.Position) == "Vector3"
		then payload.Position
		else nil
	refreshAllMarkers()
end)

local callFee = 0

Remotes.GarageSync.OnClientEvent:Connect(function(payload)
	if typeof(payload) ~= "table" then
		return
	end
	myCar = if typeof(payload.SpawnedAt) == "Vector3" then payload.SpawnedAt else nil
	callFee = if typeof(payload.CallFee) == "number" then payload.CallFee else 0
	refreshAllMarkers()
end)

Remotes.RouteSync.OnClientEvent:Connect(function(payload)
	if typeof(payload) ~= "table" or typeof(payload.Points) ~= "table" then
		ownTarget = nil
	else
		local points = payload.Points
		ownTarget = points[#points]
	end
	refreshAllMarkers()
end)

--==========================================================================
-- Bewegung, Drehung, Zoom
--==========================================================================

local function alivePosition(): (Vector3?, boolean)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		local driving = humanoid ~= nil and humanoid.SeatPart ~= nil and humanoid.SeatPart:IsA("VehicleSeat")
		return root.Position, driving
	end
	return nil, false
end

local currentRange = M.RangeOnFoot

RunService.RenderStepped:Connect(function(deltaTime)
	if not drawn then
		return
	end
	local position, driving = alivePosition()
	if not position then
		return
	end

	-- Zoom weich umschalten. Ein harter Sprung beim Einsteigen sieht aus,
	-- als waere die Karte kaputtgegangen.
	local wanted = if driving then M.RangeDriving else M.RangeOnFoot
	currentRange += (wanted - currentRange) * math.min(1, deltaTime / math.max(M.ZoomLerp, 0.01))
	local newScale = (M.MiniSize * 0.5) / currentRange
	if math.abs(newScale - mini.Scale) > 1e-4 and lastPayload then
		mini.Scale = newScale
		fillSurface(mini, lastPayload)
		refreshAllMarkers()
	end

	local heading = 0
	local camera = workspace.CurrentCamera
	if camera then
		local look = camera.CFrame.LookVector
		-- Bildschirm-Y entspricht Welt-Z, deshalb atan2(X, Z).
		heading = math.deg(math.atan2(look.X, look.Z))
	end

	local px, pz = toPixels(mini, position.X, position.Z)
	if mini.Rotates then
		-- Der Inhalt dreht sich um den Spieler herum: erst verschieben,
		-- dann drehen. Genau zwei Eigenschaften pro Bild.
		local radians = math.rad(heading + 180)
		local cos, sin = math.cos(radians), math.sin(radians)
		local rx = -px * cos + pz * sin
		local rz = -px * sin - pz * cos
		miniWorld.Position = UDim2.new(0.5, rx, 0.5, rz)
		miniWorld.Rotation = -(heading + 180)
		mini.Player.Rotation = 45
		northArrow.Position = UDim2.new(
			0.5 + 0.42 * math.sin(math.rad(-(heading + 180))),
			0,
			0.5 - 0.42 * math.cos(math.rad(-(heading + 180))),
			0
		)
	else
		miniWorld.Position = UDim2.new(0.5, -px, 0.5, -pz)
		mini.Player.Rotation = 45 - heading
		northArrow.Position = UDim2.fromScale(0.5, 0.08)
	end

	if backdrop.Visible then
		local bx, bz = toPixels(big, position.X, position.Z)
		big.Player.Position = UDim2.new(0.5, bx, 0.5, bz)
		big.Player.Rotation = 45 - heading
	end
end)

--==========================================================================
-- Auf, zu, Ziel setzen
--==========================================================================

local function setOpen(open: boolean)
	backdrop.Visible = open
	callButton.Visible = myCar ~= nil
	if myCar then
		callButton.Text = ("FAHRZEUG RUFEN (%d CRY)"):format(callFee)
	end
end

miniButton.Activated:Connect(function()
	setOpen(not backdrop.Visible)
end)
closeButton.Activated:Connect(function()
	setOpen(false)
end)
clearButton.Activated:Connect(function()
	Remotes.RouteRequest:FireServer({})
end)

-- Tippen auf die Karte setzt ein Ziel. Der Client schickt nur eine Position -
-- den Weg dorthin rechnet der Server, und ein Ziel ist ohnehin kein Vorteil.
bigPanel.Activated:Connect(function()
	if not drawn or big.Scale <= 0 then
		return
	end
	local mouse = UserInputService:GetMouseLocation()
	local centre = bigPanel.AbsolutePosition + bigPanel.AbsoluteSize * 0.5
	-- GetMouseLocation liegt im Bildschirmraum inklusive Inset, AbsolutePosition
	-- nicht - der Versatz muss raus, sonst landet das Ziel zu weit oben.
	local inset = game:GetService("GuiService"):GetGuiInset()
	local local2d = Vector2.new(mouse.X - inset.X, mouse.Y - inset.Y) - centre

	Remotes.RouteRequest:FireServer({
		X = local2d.X / big.Scale,
		Z = local2d.Y / big.Scale,
	})
	setOpen(false)
end)

callButton.Activated:Connect(function()
	local response = Remotes.VehicleAction:InvokeServer({ Action = "CALL" })
	if typeof(response) == "table" and response.Ok then
		callButton.Text = "UNTERWEGS"
	elseif typeof(response) == "table" and response.Reason == "NO_ROAD" then
		callButton.Text = "KEINE STRASSE IN DER NAEHE"
	elseif typeof(response) == "table" and response.Reason == "COOLDOWN" then
		callButton.Text = "GERADE ERST GERUFEN"
	elseif typeof(response) == "table" and response.Reason == "TOO_EXPENSIVE" then
		callButton.Text = "ZU TEUER"
	else
		callButton.Text = "GEHT GERADE NICHT"
	end
	task.delay(2, function()
		callButton.Text = ("FAHRZEUG RUFEN (%d CRY)"):format(callFee)
	end)
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	if input.KeyCode == Enum.KeyCode.M then
		setOpen(not backdrop.Visible)
	elseif input.KeyCode == Enum.KeyCode.Escape and backdrop.Visible then
		setOpen(false)
	end
end)
