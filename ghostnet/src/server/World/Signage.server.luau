-- ServerScriptService/World/Signage.server.luau
--!strict
-- GHOSTNET :: Die Welt beschriften.
--
-- WARUM DAS NOETIG IST
--   Eine Karte hilft nur dem, der hinsieht. Ein neuer Spieler sieht nicht
--   hin - er laeuft los. Also muss die Stadt selbst sagen, was wo ist:
--   grosse Schrift an den Fassaden, Strassenschilder an den Kreuzungen,
--   Lichtsaeulen ueber dem, was gerade zaehlt.
--
-- WAS HIER ERZEUGT WIRD
--   Nur Schilder und Beschriftung - flache Bretter mit SurfaceGui und
--   unsichtbare Kartenpunkte. Das faellt unter die Ausnahme in Regel 7:
--   ein Schild ist Text auf einer Flaeche, kein Modell, das jemand haette
--   bauen muessen. Gebaeude, Fahrzeuge und Menschen kommen weiter aus
--   ReplicatedStorage/Assets.
--
-- KARTENPUNKTE
--   Jedes beschriftete Gebaeude bekommt zusaetzlich den Tag GhostNetPoi mit
--   dem Attribut MapKind. Damit taucht es auf Karte und Kompass auf, ohne
--   dass MapService irgendein Gebaeude kennen muesste.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Config = require(ReplicatedStorage.Shared.Config)

local RoadNetwork = require(ServerScriptService:WaitForChild("Systems"):WaitForChild("RoadNetwork"))

local FOLDER_NAME = "GhostNet_Signage"

if workspace:FindFirstChild(FOLDER_NAME) then
	return
end

RoadNetwork.Build()

local folder = Instance.new("Folder")
folder.Name = FOLDER_NAME
folder.Parent = workspace

local S = Config.Signage
local C = Config.City

--==========================================================================
-- Bausteine
--==========================================================================

-- Ein Brett mit Leuchtschrift auf beiden Seiten. Von weitem lesbar, weil die
-- Schrift auf der FLAECHE sitzt und nicht als Billboard mitskaliert.
local function signBoard(name: string, text: string, colour: Color3, cframe: CFrame, width: number)
	local board = Instance.new("Part")
	board.Name = name
	board.Size = Vector3.new(width, S.SignHeight, S.SignDepth)
	board.CFrame = cframe
	board.Color = Config.Palette.MetallDunkel
	board.Material = Enum.Material.Metal
	board.Anchored = true
	board.CanCollide = false
	board.CanQuery = false
	board.CanTouch = false
	board.CastShadow = false
	board.Parent = folder

	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local surface = Instance.new("SurfaceGui")
		surface.Name = "Schrift"
		surface.Face = face
		surface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		surface.PixelsPerStud = 50
		surface.MaxDistance = S.MaxDistance
		surface.LightInfluence = 0

		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.Font = Enum.Font.Code
		label.Text = text
		label.TextColor3 = colour
		label.TextScaled = true
		label.Parent = surface

		surface.Parent = board
	end

	return board
end

-- Unsichtbarer Kartenpunkt. Traegt nur Tag und Attribute - kein Aussehen.
local function mapPoint(id: string, kind: string, displayName: string, position: Vector3)
	local marker = Instance.new("Part")
	marker.Name = "POI_" .. id
	marker.Size = Vector3.new(2, 2, 2)
	marker.CFrame = CFrame.new(position)
	marker.Transparency = 1
	marker.Anchored = true
	marker.CanCollide = false
	marker.CanQuery = false
	marker.CanTouch = false
	marker:SetAttribute("MapKind", kind)
	marker:SetAttribute("DisplayName", displayName)
	marker.Parent = folder
	CollectionService:AddTag(marker, Config.PoiTag)
	return marker
end

--==========================================================================
-- 1) Die wichtigen Gebaeude beschriften
--
-- Positionen stammen aus StoryWorld und Dealership. Sie stehen hier bewusst
-- als Konstanten und nicht als Suche im Workspace: eine Suche waere von der
-- Ladereihenfolge der World-Skripte abhaengig und damit fragil.
--==========================================================================

type Place = {
	Id: string,
	Kind: string,
	Text: string,
	Name: string,
	Colour: Color3,
	At: Vector3,
	Facing: number, -- Grad
	Width: number,
}

local PLACES: { Place } = {
	{
		Id = "BANK",
		Kind = "BANK",
		Text = "VANTORRA BANK",
		Name = "Vantorra Bank",
		Colour = Config.Theme.Magenta,
		At = Vector3.new(78, 22, -70),
		Facing = 0,
		Width = 30,
	},
	{
		Id = "DEALER",
		Kind = "DEALER",
		Text = "AUTOHAUS MERIDIAN",
		Name = "Autohaus Meridian",
		Colour = Config.Theme.Amber,
		At = Vector3.new(-96, 21, 20),
		Facing = 0,
		Width = 34,
	},
	{
		Id = "HOME",
		Kind = "APARTMENT",
		Text = "HAUS 14",
		Name = "Dein Apartment",
		Colour = Config.Theme.Cyan,
		At = Vector3.new(46, 13, 31),
		Facing = 0,
		Width = 14,
	},
	{
		Id = "STORE",
		Kind = "TARGET",
		Text = "PFANDLEIHE",
		Name = "Pfandleihe Kreuzung Nord",
		Colour = Config.Theme.Amber,
		At = Vector3.new(-62, 14, -63),
		Facing = 0,
		Width = 18,
	},
	{
		Id = "GARAGE",
		Kind = "GARAGE",
		Text = "GARAGE",
		Name = "Deine Garage",
		Colour = Config.Theme.Cyan,
		At = Vector3.new(46, 14, 55),
		Facing = 0,
		Width = 16,
	},
}

for _, place in PLACES do
	signBoard(
		place.Id .. "_Schild",
		place.Text,
		place.Colour,
		CFrame.new(place.At) * CFrame.Angles(0, math.rad(place.Facing), 0),
		place.Width
	)
	mapPoint(place.Id, place.Kind, place.Name, place.At)
end

--==========================================================================
-- 2) Das eigene Apartment kennzeichnen
--
-- Eine Hausnummer allein sieht man nachts nicht und tagsueber uebersieht man
-- sie. Ein farbiges Licht darueber findet man auch aus dem fahrenden Auto.
--==========================================================================

do
	local home = Vector3.new(46, 13, 31)

	local lamp = Instance.new("Part")
	lamp.Name = "ApartmentLicht"
	lamp.Size = Vector3.new(2.4, 0.6, 2.4)
	lamp.CFrame = CFrame.new(home + Vector3.new(0, 2.2, 0))
	lamp.Color = Config.Theme.Cyan
	lamp.Material = Enum.Material.Neon
	lamp.Anchored = true
	lamp.CanCollide = false
	lamp.CanQuery = false
	lamp.CanTouch = false
	lamp.Parent = folder

	local light = Instance.new("PointLight")
	light.Color = Config.Theme.Cyan
	light.Brightness = 3
	light.Range = 22
	light.Parent = lamp
end

--==========================================================================
-- 3) Strassenschilder an den Kreuzungen
--
-- Die Namen entstehen aus zwei kurzen Listen: Nord-Sued mal Ost-West. Zwei
-- Dutzend Woerter ergeben ein ganzes Strassennetz mit echten Namen, und
-- niemand muss hundert Schilder von Hand beschriften.
--==========================================================================

local function streetName(list: { string }, index: number): string
	if #list == 0 then
		return "Strasse"
	end
	return list[((index - 1) % #list) + 1]
end

local half = math.floor(C.Grid / 2)
local signs = 0

for _, node in RoadNetwork.All() do
	-- Nur Kreuzungen mit mindestens drei Armen beschildern. An einer geraden
	-- Strecke braucht kein Mensch ein Schild.
	if #node.Links < 3 then
		continue
	end

	local northSouth = streetName(S.StreetsNorthSouth, node.GridX + half + 1)
	local eastWest = streetName(S.StreetsEastWest, node.GridZ + half + 1)

	local post = Instance.new("Part")
	post.Name = "Schilderpfosten"
	post.Size = Vector3.new(0.4, S.StreetSignHeight, 0.4)
	post.CFrame = CFrame.new(node.Position + Vector3.new(C.RoadWidth * 0.5 + 3, S.StreetSignHeight * 0.5, C.RoadWidth * 0.5 + 3))
	post.Color = Config.Palette.MetallDunkel
	post.Material = Enum.Material.Metal
	post.Anchored = true
	post.CanCollide = false
	post.CanQuery = false
	post.CanTouch = false
	post.CastShadow = false
	post.Parent = folder

	for index, entry in { { northSouth, 90 }, { eastWest, 0 } } do
		local text = entry[1] :: string
		local yaw = entry[2] :: number
		signBoard(
			"Strassenschild",
			text,
			Config.Theme.Text,
			CFrame.new(post.Position + Vector3.new(0, S.StreetSignHeight * 0.5 - index * 2.2, 0))
				* CFrame.Angles(0, math.rad(yaw), 0),
			S.StreetSignSize.X
		)
		signs += 1
	end
end

print(("[GHOSTNET] Beschilderung gebaut: %d Gebaeudeschilder, %d Strassenschilder."):format(#PLACES, signs))
