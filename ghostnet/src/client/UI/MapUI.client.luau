-- StarterPlayerScripts/UI/MapUI.client.luau
--!strict
-- GHOSTNET :: Minikarte und grosse Karte.
--
-- ZWEI ANSICHTEN, EINE DATENQUELLE
--   Minikarte    klein unten rechts, folgt dem Spieler, zeigt die Umgebung.
--   Grosse Karte [M] oder Tippen auf die Minikarte: die ganze Stadt mit
--                Bezirksnamen und Legende. Das ist die Antwort auf
--                "wo ist eigentlich was".
--
-- Beide zeichnen dieselben Daten aus Remotes.MapSync. Es gibt keine zweite
-- Karte, die auseinanderlaufen koennte.
--
-- KEINE BILDER, KEINE ASSET-IDS
--   Strassen sind gedrehte Frames, Symbole sind kleine Quadrate. Damit
--   braucht die Karte keine einzige hochgeladene Textur - und Noah muss
--   nichts eintragen, damit sie funktioniert.
--
-- LEISTUNG
--   Der ganze Karteninhalt wird EINMAL gebaut, wenn die Daten ankommen.
--   Pro Bild wird nur die Position des Inhalts-Containers und das
--   Spielersymbol angefasst - nicht jede der rund hundert Strassen.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Districts = require(ReplicatedStorage.Shared.Districts)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local UITheme = require(ReplicatedStorage.Shared.UITheme)

local M = Config.Map
local player = Players.LocalPlayer

--==========================================================================
-- Kartenarten nachschlagen
--==========================================================================

local kindById: { [string]: any } = {}
for _, kind in M.Kinds do
	kindById[kind.Id] = kind
end

local function kindColour(id: string): Color3
	local kind = kindById[id]
	return if kind then kind.Colour else UITheme.Color.TextDim
end

local function kindOrder(id: string): number
	local kind = kindById[id]
	return if kind then kind.Order else 1
end

--==========================================================================
-- Ausmasse der Stadt
--
-- Aus Config gerechnet, nicht aus den empfangenen Knoten: so passt die
-- Karte auch dann, wenn gerade nur ein Teil der Stadt getaggt ist.
--==========================================================================

local CITY_HALF = (Config.City.Grid - 1) * 0.5 * Config.City.BlockSize + Config.City.BlockSize * 0.5

--==========================================================================
-- Ein Kartenfenster (Minikarte oder grosse Karte)
--==========================================================================

type Surface = {
	Holder: GuiObject,
	World: Frame, -- verschiebbarer Inhalt
	Scale: number, -- Pixel pro Stud
	Icons: number,
	RoadWidth: number,
	Marker: Frame?, -- Auftrags-Wegpunkt
	Player: Frame,
}

-- Weltkoordinate -> Pixel innerhalb des Inhalts-Containers.
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

	if surface.Icons >= M.BigIcon then
		local label = UITheme.Label({
			Name = "Name",
			Text = district.Name:upper(),
			TextColor3 = district.Neon,
			TextSize = M.DistrictLabelSize,
			TextTransparency = 0.25,
			TextXAlignment = Enum.TextXAlignment.Center,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(x, z - extent * surface.Scale * 0.5 + 12),
			Size = UDim2.fromOffset(160, 16),
			ZIndex = 3,
		})
		label.Parent = surface.World
	end
end

local function drawPoi(surface: Surface, poi: { [string]: any })
	local x, z = toPixels(surface, poi.X, poi.Z)
	local size = surface.Icons

	local dot = UITheme.Frame({
		Name = poi.Kind,
		BackgroundColor3 = kindColour(poi.Kind),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(x, z),
		Size = UDim2.fromOffset(size, size),
		ZIndex = 4 + kindOrder(poi.Kind),
	})
	UITheme.Corner(dot, math.floor(size * 0.5))
	UITheme.Stroke(dot, UITheme.Color.Background, 1)
	dot.Parent = surface.World

	-- Namen nur auf der grossen Karte: auf der Minikarte waere das Kleisterei.
	if surface.Icons >= M.BigIcon and poi.Kind ~= "TARGET" and poi.Kind ~= "EXPOSED" then
		local label = UITheme.Label({
			Name = "Name",
			Text = poi.Name,
			TextColor3 = kindColour(poi.Kind),
			TextSize = 11,
			TextXAlignment = Enum.TextXAlignment.Center,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromOffset(x, z + size * 0.7),
			Size = UDim2.fromOffset(150, 14),
			ZIndex = 12,
		})
		label.Parent = surface.World
	end
end

local function makePlayerIcon(surface: Surface): Frame
	-- Ein gedrehtes Quadrat als Pfeilersatz: ohne Bild-Asset geht kein
	-- richtiger Pfeil, und ein gekipptes Viereck liest sich gut genug.
	local icon = UITheme.Frame({
		Name = "Spieler",
		BackgroundColor3 = UITheme.Color.Text,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(M.PlayerIcon, M.PlayerIcon),
		Rotation = 45,
		ZIndex = 20,
	})
	UITheme.Stroke(icon, UITheme.Color.Background, 2)
	icon.Parent = surface.Holder
	return icon
end

--==========================================================================
-- Aufbau der Fenster
--==========================================================================

local gui = UITheme.Screen("GhostNetMap", 6)
gui.Parent = player:WaitForChild("PlayerGui")

--== Minikarte =============================================================

local miniButton = UITheme.Button({
	Name = "Minikarte",
	BackgroundColor3 = M.Background,
	-- Unten rechts: oben rechts sitzen schon Wallet, Trace und die
	-- Fahndungssterne, unten links die Knoepfe fuer Shop und Store.
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, -M.MiniMargin, 1, -M.MiniMargin),
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
	Size = UDim2.fromScale(1, 1),
	ZIndex = 2,
})
miniWorld.Parent = miniButton

local miniHint = UITheme.Label({
	Name = "Hinweis",
	Text = "[M] KARTE",
	TextColor3 = UITheme.Color.TextDim,
	TextSize = 11,
	TextXAlignment = Enum.TextXAlignment.Center,
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -3),
	Size = UDim2.new(1, 0, 0, 14),
	ZIndex = 25,
})
miniHint.Parent = miniButton

local mini: Surface = {
	Holder = miniButton,
	World = miniWorld,
	Scale = (M.MiniSize * 0.5) / M.MiniRange,
	Icons = M.MiniIcon,
	RoadWidth = M.MiniRoadWidth,
	Player = nil :: any,
}
mini.Player = makePlayerIcon(mini)
mini.Player.Position = UDim2.fromScale(0.5, 0.5) -- die Minikarte folgt dem Spieler

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

local bigSize = 0
local bigScale = 0

local bigPanel = UITheme.Frame({
	Name = "Blatt",
	BackgroundColor3 = M.Background,
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromScale(0.72, 0.86),
	ClipsDescendants = true,
	ZIndex = 31,
})
UITheme.Corner(bigPanel, 6)
UITheme.Stroke(bigPanel, UITheme.Color.Cyan, 1)
bigPanel.Parent = backdrop

local bigWorld = UITheme.Frame({
	Name = "Inhalt",
	BackgroundTransparency = 1,
	Size = UDim2.fromScale(1, 1),
	ZIndex = 31,
})
bigWorld.Parent = bigPanel

local bigTitle = UITheme.Label({
	Name = "Titel",
	Text = "VANTORRA",
	TextColor3 = UITheme.Color.Cyan,
	TextSize = 18,
	Position = UDim2.fromOffset(14, 10),
	Size = UDim2.fromOffset(300, 22),
	ZIndex = 40,
})
bigTitle.Parent = bigPanel

local closeButton = UITheme.Button({
	Name = "Schliessen",
	Text = "[M] SCHLIESSEN",
	TextColor3 = UITheme.Color.TextDim,
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -10, 0, 10),
	Size = UDim2.fromOffset(160, 34), -- gross genug fuer Touch
	ZIndex = 40,
})
UITheme.Corner(closeButton, 4)
closeButton.Parent = bigPanel

local big: Surface = {
	Holder = bigPanel,
	World = bigWorld,
	Scale = 1,
	Icons = M.BigIcon,
	RoadWidth = M.BigRoadWidth,
	Player = nil :: any,
}
big.Player = makePlayerIcon(big)

--== Legende ===============================================================
-- "Wo alles ist" braucht auch: was bedeutet welcher Punkt.

local legend = UITheme.Frame({
	Name = "Legende",
	BackgroundColor3 = UITheme.Color.Panel,
	BackgroundTransparency = 0.15,
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.new(0, 10, 1, -10),
	Size = UDim2.fromOffset(230, 22 + #M.Kinds * 18),
	ZIndex = 40,
})
UITheme.Corner(legend, 4)
UITheme.Stroke(legend, UITheme.Color.Line, 1)
legend.Parent = bigPanel

do
	local heading = UITheme.Label({
		Text = "LEGENDE",
		TextColor3 = UITheme.Color.TextDim,
		TextSize = 11,
		Position = UDim2.fromOffset(8, 4),
		Size = UDim2.fromOffset(200, 14),
		ZIndex = 41,
	})
	heading.Parent = legend

	for index, kind in M.Kinds do
		local y = 20 + (index - 1) * 18

		local dot = UITheme.Frame({
			BackgroundColor3 = kind.Colour,
			Position = UDim2.fromOffset(10, y + 4),
			Size = UDim2.fromOffset(8, 8),
			ZIndex = 41,
		})
		UITheme.Corner(dot, 4)
		dot.Parent = legend

		local text = UITheme.Label({
			Text = kind.Label,
			TextSize = 12,
			Position = UDim2.fromOffset(26, y),
			Size = UDim2.fromOffset(196, 16),
			ZIndex = 41,
		})
		text.Parent = legend
	end
end

--==========================================================================
-- Zeichnen, sobald die Daten da sind
--==========================================================================

local drawn = false

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

local function onMapSync(payload: { [string]: any })
	if typeof(payload) ~= "table" or typeof(payload.Edges) ~= "table" then
		return
	end

	-- Massstab der grossen Karte: die ganze Stadt soll hineinpassen.
	bigSize = math.min(bigPanel.AbsoluteSize.X, bigPanel.AbsoluteSize.Y)
	bigScale = (bigSize - M.BigPadding * 2) / (CITY_HALF * 2)
	big.Scale = math.max(bigScale, 0.01)

	fillSurface(mini, payload)
	fillSurface(big, payload)

	-- Die grosse Karte steht fest: Stadtmitte in die Blattmitte.
	bigWorld.Position = UDim2.fromScale(0.5, 0.5)
	bigWorld.Size = UDim2.fromOffset(0, 0) -- Kinder liegen als Offset um (0,0)

	drawn = true
end

Remotes.MapSync.OnClientEvent:Connect(onMapSync)

--==========================================================================
-- Auftrags-Wegpunkt
-- Kommt aus WaypointSync, nicht aus MapSync: er wechselt staendig.
--==========================================================================

local waypoint: Vector3? = nil
local waypointIcons: { [string]: Frame } = {}

local function setWaypointIcon(surface: Surface, key: string)
	local existing = waypointIcons[key]
	if existing then
		existing:Destroy()
		waypointIcons[key] = nil
	end
	if not waypoint then
		return
	end

	local x, z = toPixels(surface, waypoint.X, waypoint.Z)
	local icon = UITheme.Frame({
		Name = "Auftrag",
		BackgroundColor3 = kindColour("WAYPOINT"),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(x, z),
		Size = UDim2.fromOffset(surface.Icons + 3, surface.Icons + 3),
		Rotation = 45,
		ZIndex = 18,
	})
	UITheme.Stroke(icon, UITheme.Color.Background, 2)
	icon.Parent = surface.World
	waypointIcons[key] = icon
end

Remotes.WaypointSync.OnClientEvent:Connect(function(payload)
	if typeof(payload) == "table" and typeof(payload.Position) == "Vector3" then
		waypoint = payload.Position
	else
		waypoint = nil
	end
	setWaypointIcon(mini, "mini")
	setWaypointIcon(big, "big")
end)

--==========================================================================
-- Bewegung
--==========================================================================

local function alivePosition(): Vector3?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root.Position
	end
	return nil
end

RunService.RenderStepped:Connect(function()
	if not drawn then
		return
	end
	local position = alivePosition()
	if not position then
		return
	end

	-- Minikarte: der Inhalt wandert unter dem festen Spielersymbol durch.
	-- Genau EINE Eigenschaft pro Bild statt hundert Frames neu zu setzen.
	local px, pz = toPixels(mini, position.X, position.Z)
	miniWorld.Position = UDim2.new(0.5, -px, 0.5, -pz)

	local camera = workspace.CurrentCamera
	if camera then
		local look = camera.CFrame.LookVector
		-- Bildschirm-Y ist Welt-Z: deshalb atan2(X, Z) und nicht umgekehrt.
		local heading = math.deg(math.atan2(look.X, look.Z))
		mini.Player.Rotation = 45 - heading
		big.Player.Rotation = 45 - heading
	end

	if backdrop.Visible then
		local bx, bz = toPixels(big, position.X, position.Z)
		big.Player.Position = UDim2.new(0.5, bx, 0.5, bz)
	end
end)

--==========================================================================
-- Auf und zu
--==========================================================================

local function setOpen(open: boolean)
	backdrop.Visible = open
end

local function toggle()
	setOpen(not backdrop.Visible)
end

miniButton.Activated:Connect(toggle)
closeButton.Activated:Connect(function()
	setOpen(false)
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	if input.KeyCode == Enum.KeyCode.M then
		toggle()
	elseif input.KeyCode == Enum.KeyCode.Escape and backdrop.Visible then
		setOpen(false)
	end
end)

-- Beim Fahren stoert die grosse Karte. Minikarte bleibt.
CollectionService:GetInstanceAddedSignal(Config.VehicleTag):Connect(function()
	setOpen(false)
end)
