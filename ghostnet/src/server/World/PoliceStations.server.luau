-- ServerScriptService/World/PoliceStations.server.luau
--!strict
-- GHOSTNET :: Zwei Polizeiwachen als echte Orte.
--
-- WARUM DAS NOETIG IST
--   Eine Festnahme ohne Ort ist nur ein Bildschirmtext. Erst wenn es einen
--   Platz gibt, an dem Festgenommene landen und von dem Streifenwagen
--   losfahren, wird die Polizei Teil der Stadt statt eine Zahl im HUD.
--
-- WAS HIER STEHT
--   Gebaeudehuelle, Zellenbereich hinter Gittern und zwei markierte Punkte:
--   die Zelle (wo man aufwacht) und der Ausgang (wo man entlassen wird).
--   Beides als Attribut am Modell, damit ArrestService keine Koordinaten
--   kennen muss.
--
--   Ausnahme von Regel 7 wie bei der Beschilderung: das sind Waende und
--   Marker, keine Modelle, die jemand haette bauen muessen. Sobald es ein
--   Wachen-Modell in Assets/Buildings gibt, ersetzt es die Huelle - Tag und
--   Attribute bleiben gleich.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local FOLDER_NAME = "GhostNet_Polizei"

if workspace:FindFirstChild(FOLDER_NAME) then
	return
end

local folder = Instance.new("Folder")
folder.Name = FOLDER_NAME
folder.Parent = workspace

local function part(parent: Instance, name: string, size: Vector3, cframe: CFrame, colour: Color3, material: Enum.Material): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cframe
	p.Color = colour
	p.Material = material
	p.Anchored = true
	p.CanCollide = true
	p.CanQuery = false
	p.CanTouch = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function sign(target: BasePart, text: string)
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local surface = Instance.new("SurfaceGui")
		surface.Face = face
		surface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		surface.PixelsPerStud = 50
		surface.MaxDistance = Config.Signage.MaxDistance
		surface.LightInfluence = 0

		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.Font = Enum.Font.Code
		label.Text = text
		label.TextColor3 = Config.Theme.Blue
		label.TextScaled = true
		label.Parent = surface

		surface.Parent = target
	end
end

--==========================================================================

local STATIONS = {
	{ Id = "NORD", Name = "Revier Nord", At = Vector3.new(-140, 0, -180) },
	{ Id = "SUED", Name = "Revier Sued", At = Vector3.new(170, 0, 190) },
}

for _, station in STATIONS do
	local model = Instance.new("Model")
	model.Name = ("Revier_%s"):format(station.Id)

	local base = station.At

	local floor = part(
		model,
		"Boden",
		Vector3.new(40, 1, 30),
		CFrame.new(base + Vector3.new(0, 0.5, 0)),
		Config.Palette.InnenBoden,
		Enum.Material.Concrete
	)
	model.PrimaryPart = floor

	part(
		model,
		"Rueckwand",
		Vector3.new(40, 16, 1),
		CFrame.new(base + Vector3.new(0, 8, -15)),
		Config.Palette.BetonHell,
		Enum.Material.Concrete
	)
	for _, side in { -1, 1 } do
		part(
			model,
			"Seitenwand",
			Vector3.new(1, 16, 30),
			CFrame.new(base + Vector3.new(side * 20, 8, 0)),
			Config.Palette.BetonHell,
			Enum.Material.Concrete
		)
	end
	part(
		model,
		"Dach",
		Vector3.new(41, 1, 31),
		CFrame.new(base + Vector3.new(0, 16, 0)),
		Config.Palette.Dach,
		Enum.Material.Metal
	)

	-- Schild ueber dem Eingang.
	local board = part(
		model,
		"Schild",
		Vector3.new(24, Config.Signage.SignHeight, Config.Signage.SignDepth),
		CFrame.new(base + Vector3.new(0, 18, 15)),
		Config.Palette.MetallDunkel,
		Enum.Material.Metal
	)
	board.CanCollide = false
	sign(board, ("POLIZEI // %s"):format(station.Name:upper()))

	-- Blaue Leuchtleiste. Neonflaeche statt Lichtquelle: sichtbar und gratis.
	local strip = part(
		model,
		"Leuchtband",
		Vector3.new(40, 0.5, 1.2),
		CFrame.new(base + Vector3.new(0, 15.4, 14.6)),
		Config.Theme.Blue,
		Enum.Material.Neon
	)
	strip.CanCollide = false

	--== Zellenbereich =====================================================
	-- Hinten links, mit Gitterstaeben davor. Wer drin steht, sieht die
	-- Wache - das ist der Unterschied zu einem schwarzen Bildschirm.
	local cellCentre = base + Vector3.new(-13, 4, -9)

	part(
		model,
		"Zellenwand",
		Vector3.new(1, 12, 12),
		CFrame.new(base + Vector3.new(-6, 6, -9)),
		Config.Palette.BetonDunkel,
		Enum.Material.Concrete
	)
	for index = 0, 6 do
		local bar = part(
			model,
			"Gitter",
			Vector3.new(0.4, 11, 0.4),
			CFrame.new(base + Vector3.new(-20 + index * 2.3, 6, -3)),
			Config.Palette.Metall,
			Enum.Material.Metal
		)
		bar.CanCollide = true
	end

	--== Punkte, die der ArrestService braucht =============================
	model:SetAttribute("StationId", station.Id)
	model:SetAttribute("DisplayName", station.Name)
	model:SetAttribute("CellPosition", cellCentre)
	model:SetAttribute("ExitPosition", base + Vector3.new(0, 4, 22))

	model.Parent = folder
	CollectionService:AddTag(model, Config.PoliceStationTag)
end

print(("[GHOSTNET] %d Polizeiwachen gebaut."):format(#STATIONS))
