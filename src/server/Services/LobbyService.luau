--!strict
-- LobbyService: die Spawn-Villa, in der jede Session beginnt.
--
-- Neue Spieler (und jeder Session-Start) landen in einer schwebenden
-- Marmor-Villa am Weltursprung: Eingangshalle mit rotem Teppich,
-- Kronleuchter, zwei großen Bestenliste-Tafeln (Energie und Likes aus dem
-- LeaderboardService), goldener Kristall-Statue, Galerie mit Treppe zum
-- Erkunden - und am Ende ein leuchtendes Portal. Erst wer durch das Portal
-- geht, kommt auf seine eigene Insel (PlanetService.teleportHome); ab dann
-- landen Respawns direkt auf der Insel.
--
-- Die Villa wird EINMAL beim Serverstart gebaut (geteilte Lobby, kein
-- Per-Spieler-Aufbau). Der SpawnLocation-Part aus der Place-Datei wird in
-- den Eingangsbereich verschoben bzw. dort erzeugt, falls er fehlt.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local LeaderboardService = require(script.Parent.LeaderboardService)
local PlanetService = require(script.Parent.PlanetService)

-- Villa-Ursprung: Mittelpunkt der Bodenplatte; Oberkante liegt bei Y=141.
local LOBBY_ORIGIN = CFrame.new(0, 140, 0)
local FLOOR_TOP = 1 -- Oberkante der Bodenplatte relativ zum Ursprung

local HALL_HALF_WIDTH = 28 -- Innenraum: X von -28 bis +28
local HALL_HALF_DEPTH = 24 -- Innenraum: Z von -24 bis +24 (Tür bei +Z)
local WALL_HEIGHT = 14

local MARBLE_COLOR = Color3.fromRGB(226, 222, 212)
local MARBLE_DARK = Color3.fromRGB(188, 182, 170)
local GOLD_COLOR = Color3.fromRGB(255, 210, 90)
local CARPET_COLOR = Color3.fromRGB(140, 42, 46)
local GLASS_COLOR = Color3.fromRGB(178, 220, 240)
local PORTAL_COLOR = Color3.fromRGB(120, 225, 255)
local WOOD_COLOR = Color3.fromRGB(112, 84, 56)
local BOARD_COLOR = Color3.fromRGB(34, 36, 48)

local LEADERBOARD_BOARD_REFRESH_SECONDS = 20
local PORTAL_COOLDOWN_SECONDS = 3

local LobbyService = {}

-- Zeilen-Labels der beiden Tafeln (werden periodisch neu befüllt).
local energyRows: { TextLabel } = {}
local likesRows: { TextLabel } = {}

local lastPortalUse: { [Player]: number } = {}

-- 1234567 -> "1.234.567" (deutsche Tausendertrennung).
local function formatNumber(value: number): string
	local text = tostring(math.floor(value))
	while true do
		local replaced: number
		text, replaced = text:gsub("^(-?%d+)(%d%d%d)", "%1.%2")
		if replaced == 0 then
			break
		end
	end
	return text
end

local function newPart(parent: Instance, name: string, collide: boolean): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = collide
	part.CanQuery = false
	part.CanTouch = false
	part.Parent = parent
	return part
end

-- Liegender Zylinder (Scheibe) - für Teppiche, Ringe und Podeste.
local function newDisc(parent: Instance, name: string, radius: number, thickness: number, cframe: CFrame, collide: boolean): Part
	local disc = newPart(parent, name, collide)
	disc.Shape = Enum.PartType.Cylinder
	disc.Size = Vector3.new(thickness, radius * 2, radius * 2)
	disc.CFrame = cframe * CFrame.Angles(0, 0, math.rad(90))
	return disc
end

--------------------------------------------------------------------------
-- Gebäude
--------------------------------------------------------------------------

local function buildShell(folder: Folder)
	-- Bodenplatte (vorn 14 Studs Veranda vor der Tür).
	local floor = newPart(folder, "VillaBoden", true)
	floor.Size = Vector3.new(96, 2, 90)
	floor.Color = MARBLE_COLOR
	floor.Material = Enum.Material.Marble
	floor.CFrame = LOBBY_ORIGIN * CFrame.new(0, 0, 7)

	-- Goldene Bordüre um die Bodenplatte.
	for _, edge in
		{
			{ size = Vector3.new(96, 0.4, 1), offset = Vector3.new(0, FLOOR_TOP + 0.2, 7 + 44.5) },
			{ size = Vector3.new(96, 0.4, 1), offset = Vector3.new(0, FLOOR_TOP + 0.2, 7 - 44.5) },
			{ size = Vector3.new(1, 0.4, 90), offset = Vector3.new(47.5, FLOOR_TOP + 0.2, 7) },
			{ size = Vector3.new(1, 0.4, 90), offset = Vector3.new(-47.5, FLOOR_TOP + 0.2, 7) },
		}
	do
		local trim = newPart(folder, "VillaBorduere", false)
		trim.Size = edge.size
		trim.Color = GOLD_COLOR
		trim.Material = Enum.Material.Neon
		trim.Transparency = 0.35
		trim.CFrame = LOBBY_ORIGIN * CFrame.new(edge.offset)
	end

	-- Wände: hinten, links, rechts, vorn mit 12 Studs breiter Tür-Öffnung.
	local wallY = FLOOR_TOP + WALL_HEIGHT / 2
	local function wall(name: string, size: Vector3, offset: Vector3)
		local part = newPart(folder, name, true)
		part.Size = size
		part.Color = MARBLE_COLOR
		part.Material = Enum.Material.Marble
		part.CFrame = LOBBY_ORIGIN * CFrame.new(offset)
	end
	wall("VillaWandHinten", Vector3.new(HALL_HALF_WIDTH * 2 + 2, WALL_HEIGHT, 1), Vector3.new(0, wallY, -HALL_HALF_DEPTH - 0.5))
	wall("VillaWandLinks", Vector3.new(1, WALL_HEIGHT, HALL_HALF_DEPTH * 2 + 2), Vector3.new(-HALL_HALF_WIDTH - 0.5, wallY, 0))
	wall("VillaWandRechts", Vector3.new(1, WALL_HEIGHT, HALL_HALF_DEPTH * 2 + 2), Vector3.new(HALL_HALF_WIDTH + 0.5, wallY, 0))
	local frontSegmentWidth = (HALL_HALF_WIDTH * 2 - 12) / 2
	wall("VillaWandVornL", Vector3.new(frontSegmentWidth, WALL_HEIGHT, 1), Vector3.new(-(6 + frontSegmentWidth / 2), wallY, HALL_HALF_DEPTH + 0.5))
	wall("VillaWandVornR", Vector3.new(frontSegmentWidth, WALL_HEIGHT, 1), Vector3.new(6 + frontSegmentWidth / 2, wallY, HALL_HALF_DEPTH + 0.5))
	wall("VillaTuersturz", Vector3.new(12, WALL_HEIGHT - 10, 1), Vector3.new(0, FLOOR_TOP + 10 + (WALL_HEIGHT - 10) / 2, HALL_HALF_DEPTH + 0.5))

	-- Fenster in den Seitenwänden (Glas, von innen und außen sichtbar).
	for _, side in { -1, 1 } do
		for index = -1, 1 do
			local window = newPart(folder, `VillaFenster_{side}_{index}`, false)
			window.Size = Vector3.new(1.2, 6, 8)
			window.Color = GLASS_COLOR
			window.Material = Enum.Material.Glass
			window.Transparency = 0.45
			window.CFrame = LOBBY_ORIGIN * CFrame.new(side * (HALL_HALF_WIDTH + 0.5), FLOOR_TOP + 7.5, index * 14)
		end
	end

	-- Dach mit Glaskuppel und goldener Kante.
	local roof = newPart(folder, "VillaDach", true)
	roof.Size = Vector3.new(HALL_HALF_WIDTH * 2 + 4, 1, HALL_HALF_DEPTH * 2 + 4)
	roof.Color = MARBLE_DARK
	roof.Material = Enum.Material.Marble
	roof.CFrame = LOBBY_ORIGIN * CFrame.new(0, FLOOR_TOP + WALL_HEIGHT + 0.5, 0)

	-- Glaskuppel: sitzt auf dem Dach, nur eine flache Kappe ragt in die Halle.
	local dome = newPart(folder, "VillaKuppel", false)
	dome.Shape = Enum.PartType.Ball
	dome.Size = Vector3.new(20, 20, 20)
	dome.Color = GLASS_COLOR
	dome.Material = Enum.Material.Glass
	dome.Transparency = 0.55
	dome.CFrame = LOBBY_ORIGIN * CFrame.new(0, FLOOR_TOP + WALL_HEIGHT + 7, 0)

	for _, side in { -1, 1 } do
		local trimX = newPart(folder, "VillaDachkante", false)
		trimX.Size = Vector3.new(HALL_HALF_WIDTH * 2 + 4, 0.6, 0.6)
		trimX.Color = GOLD_COLOR
		trimX.Material = Enum.Material.Neon
		trimX.CFrame = LOBBY_ORIGIN * CFrame.new(0, FLOOR_TOP + WALL_HEIGHT + 1.2, side * (HALL_HALF_DEPTH + 1.7))
		local trimZ = newPart(folder, "VillaDachkante", false)
		trimZ.Size = Vector3.new(0.6, 0.6, HALL_HALF_DEPTH * 2 + 4)
		trimZ.Color = GOLD_COLOR
		trimZ.Material = Enum.Material.Neon
		trimZ.CFrame = LOBBY_ORIGIN * CFrame.new(side * (HALL_HALF_WIDTH + 1.7), FLOOR_TOP + WALL_HEIGHT + 1.2, 0)
	end

	-- Veranda: 4 Säulen mit Golddeckel vor dem Eingang.
	for index = 0, 3 do
		local x = -13.5 + index * 9
		local column = newPart(folder, `VillaSaeule_{index + 1}`, true)
		column.Shape = Enum.PartType.Cylinder
		column.Size = Vector3.new(12, 2.2, 2.2)
		column.Color = MARBLE_COLOR
		column.Material = Enum.Material.Marble
		column.CFrame = LOBBY_ORIGIN * CFrame.new(x, FLOOR_TOP + 6, HALL_HALF_DEPTH + 12) * CFrame.Angles(0, 0, math.rad(90))
		local cap = newPart(folder, `VillaSaeulenDeckel_{index + 1}`, false)
		cap.Size = Vector3.new(3, 0.8, 3)
		cap.Color = GOLD_COLOR
		cap.Material = Enum.Material.Metal
		cap.CFrame = LOBBY_ORIGIN * CFrame.new(x, FLOOR_TOP + 12.4, HALL_HALF_DEPTH + 12)
	end
	local porchRoof = newPart(folder, "VillaVerandadach", true)
	porchRoof.Size = Vector3.new(34, 1, 18)
	porchRoof.Color = MARBLE_DARK
	porchRoof.Material = Enum.Material.Marble
	porchRoof.CFrame = LOBBY_ORIGIN * CFrame.new(0, FLOOR_TOP + 13.3, HALL_HALF_DEPTH + 9)
end

local function buildInterior(folder: Folder)
	-- Roter Teppich von der Tür bis zum Portal.
	local carpet = newPart(folder, "VillaTeppich", false)
	carpet.Size = Vector3.new(10, 0.15, 46)
	carpet.Color = CARPET_COLOR
	carpet.Material = Enum.Material.Fabric
	carpet.CFrame = LOBBY_ORIGIN * CFrame.new(0, FLOOR_TOP + 0.1, 1)

	-- Kronleuchter unter der Kuppel.
	local ring = newDisc(folder, "VillaKronleuchter", 4, 0.5, LOBBY_ORIGIN * CFrame.new(0, FLOOR_TOP + 10.5, 0), false)
	ring.Color = GOLD_COLOR
	ring.Material = Enum.Material.Metal
	for index = 0, 5 do
		local angle = (index / 6) * 2 * math.pi
		local candle = newPart(folder, `VillaKerze_{index + 1}`, false)
		candle.Shape = Enum.PartType.Ball
		candle.Size = Vector3.new(0.9, 0.9, 0.9)
		candle.Color = Color3.fromRGB(255, 236, 170)
		candle.Material = Enum.Material.Neon
		candle.CFrame = LOBBY_ORIGIN * CFrame.new(math.cos(angle) * 4, FLOOR_TOP + 11, math.sin(angle) * 4)
	end
	local chandelierLight = Instance.new("PointLight")
	chandelierLight.Color = Color3.fromRGB(255, 226, 170)
	chandelierLight.Range = 42
	chandelierLight.Brightness = 1.3
	chandelierLight.Parent = ring

	-- Goldene Kristall-Statue auf Marmor-Podest (Mitte rechts).
	local pedestal = newDisc(folder, "VillaPodest", 3, 1.4, LOBBY_ORIGIN * CFrame.new(16, FLOOR_TOP + 0.7, -8), true)
	pedestal.Color = MARBLE_DARK
	pedestal.Material = Enum.Material.Marble
	local statue = newPart(folder, "VillaStatue", false)
	statue.Size = Vector3.new(2.2, 6, 2.2)
	statue.Color = GOLD_COLOR
	statue.Material = Enum.Material.Metal
	statue.Reflectance = 0.25
	statue.CFrame = LOBBY_ORIGIN * CFrame.new(16, FLOOR_TOP + 4.4, -8) * CFrame.Angles(0, math.rad(45), 0)
	local statueLight = Instance.new("PointLight")
	statueLight.Color = GOLD_COLOR
	statueLight.Range = 16
	statueLight.Brightness = 0.8
	statueLight.Parent = statue

	-- Sitzecke (links): zwei Sofas und ein Tisch auf rundem Teppich.
	local rug = newDisc(folder, "VillaSitzteppich", 7, 0.12, LOBBY_ORIGIN * CFrame.new(-14, FLOOR_TOP + 0.1, 6), false)
	rug.Color = Color3.fromRGB(120, 110, 140)
	rug.Material = Enum.Material.Fabric
	for index, offset in { CFrame.new(-14, 0, 12) * CFrame.Angles(0, math.pi, 0), CFrame.new(-14, 0, 0) } do
		local seat = newPart(folder, `VillaSofa_{index}`, true)
		seat.Size = Vector3.new(7, 1.2, 2.6)
		seat.Color = Color3.fromRGB(86, 60, 110)
		seat.Material = Enum.Material.Fabric
		seat.CFrame = LOBBY_ORIGIN * offset * CFrame.new(0, FLOOR_TOP + 0.6, 0)
		local back = newPart(folder, `VillaSofaLehne_{index}`, false)
		back.Size = Vector3.new(7, 1.6, 0.6)
		back.Color = seat.Color
		back.Material = Enum.Material.Fabric
		back.CFrame = LOBBY_ORIGIN * offset * CFrame.new(0, FLOOR_TOP + 2, -1)
	end
	local couchTable = newPart(folder, "VillaTisch", true)
	couchTable.Size = Vector3.new(3.4, 1.1, 3.4)
	couchTable.Color = WOOD_COLOR
	couchTable.Material = Enum.Material.WoodPlanks
	couchTable.CFrame = LOBBY_ORIGIN * CFrame.new(-14, FLOOR_TOP + 0.55, 6)

	-- Pflanzen in den vier Ecken.
	for index, corner in
		{
			Vector3.new(-HALL_HALF_WIDTH + 3, 0, -HALL_HALF_DEPTH + 3),
			Vector3.new(HALL_HALF_WIDTH - 3, 0, -HALL_HALF_DEPTH + 3),
			Vector3.new(-HALL_HALF_WIDTH + 3, 0, HALL_HALF_DEPTH - 3),
			Vector3.new(HALL_HALF_WIDTH - 3, 0, HALL_HALF_DEPTH - 3),
		}
	do
		local pot = newPart(folder, `VillaTopf_{index}`, true)
		pot.Shape = Enum.PartType.Cylinder
		pot.Size = Vector3.new(1.6, 2, 2)
		pot.Color = Color3.fromRGB(146, 96, 66)
		pot.Material = Enum.Material.Slate
		pot.CFrame = LOBBY_ORIGIN * CFrame.new(corner + Vector3.new(0, FLOOR_TOP + 0.8, 0)) * CFrame.Angles(0, 0, math.rad(90))
		local leaves = newPart(folder, `VillaPflanze_{index}`, false)
		leaves.Shape = Enum.PartType.Ball
		leaves.Size = Vector3.new(3, 3.6, 3)
		leaves.Color = Color3.fromRGB(96, 150, 88)
		leaves.Material = Enum.Material.Grass
		leaves.CFrame = LOBBY_ORIGIN * CFrame.new(corner + Vector3.new(0, FLOOR_TOP + 3.4, 0))
	end

	-- Drei "Gemälde" an der Rückwand (bunte Leinwände mit Goldrahmen).
	local paintingColors = { Color3.fromRGB(96, 140, 200), Color3.fromRGB(214, 130, 80), Color3.fromRGB(120, 180, 120) }
	for index, color in paintingColors do
		local x = -14 + (index - 1) * 14
		local frame = newPart(folder, `VillaRahmen_{index}`, false)
		frame.Size = Vector3.new(6.4, 4.6, 0.3)
		frame.Color = GOLD_COLOR
		frame.Material = Enum.Material.Metal
		frame.CFrame = LOBBY_ORIGIN * CFrame.new(x, FLOOR_TOP + 8, -HALL_HALF_DEPTH + 0.25)
		local canvas = newPart(folder, `VillaGemaelde_{index}`, false)
		canvas.Size = Vector3.new(5.6, 3.8, 0.2)
		canvas.Color = color
		canvas.Material = Enum.Material.SmoothPlastic
		canvas.CFrame = LOBBY_ORIGIN * CFrame.new(x, FLOOR_TOP + 8, -HALL_HALF_DEPTH + 0.1)
	end

	-- Galerie: Treppe an der linken Wand hinauf zu einem Balkon mit Geländer.
	for step = 1, 10 do
		local tread = newPart(folder, `VillaStufe_{step}`, true)
		tread.Size = Vector3.new(4, 0.8, 2.4)
		tread.Color = MARBLE_DARK
		tread.Material = Enum.Material.Marble
		tread.CFrame = LOBBY_ORIGIN * CFrame.new(-HALL_HALF_WIDTH + 2.5, FLOOR_TOP + step * 0.7 - 0.35, HALL_HALF_DEPTH - 2 - step * 2.2)
	end
	local balcony = newPart(folder, "VillaBalkon", true)
	balcony.Size = Vector3.new(10, 0.8, 24)
	balcony.Color = MARBLE_COLOR
	balcony.Material = Enum.Material.Marble
	balcony.CFrame = LOBBY_ORIGIN * CFrame.new(-HALL_HALF_WIDTH + 5.5, FLOOR_TOP + 7.35, -HALL_HALF_DEPTH + 12)
	local railing = newPart(folder, "VillaGelaender", true)
	railing.Size = Vector3.new(0.4, 2.4, 24)
	railing.Color = GOLD_COLOR
	railing.Material = Enum.Material.Metal
	railing.Transparency = 0.2
	railing.CFrame = LOBBY_ORIGIN * CFrame.new(-HALL_HALF_WIDTH + 10.3, FLOOR_TOP + 8.9, -HALL_HALF_DEPTH + 12)
end

--------------------------------------------------------------------------
-- Bestenliste-Tafeln
--------------------------------------------------------------------------

-- Baut eine Wandtafel mit Titel und 10 Zeilen; gibt die Zeilen zurück.
local function buildBoard(folder: Folder, cframe: CFrame, title: string): { TextLabel }
	local backing = newPart(folder, "VillaTafel", false)
	backing.Size = Vector3.new(14, 9, 0.6)
	backing.Color = BOARD_COLOR
	backing.Material = Enum.Material.SmoothPlastic
	backing.CFrame = cframe

	local trim = newPart(folder, "VillaTafelRahmen", false)
	trim.Size = Vector3.new(14.8, 9.8, 0.4)
	trim.Color = GOLD_COLOR
	trim.Material = Enum.Material.Metal
	trim.CFrame = cframe * CFrame.new(0, 0, 0.15)

	local gui = Instance.new("SurfaceGui")
	gui.Name = "BoardGui"
	gui.Face = Enum.NormalId.Front
	gui.CanvasSize = Vector2.new(700, 450)
	gui.LightInfluence = 0
	gui.Brightness = 1.4
	gui.Parent = backing

	local titleLabel = Instance.new("TextLabel")
	titleLabel.BackgroundTransparency = 1
	titleLabel.Size = UDim2.new(1, 0, 0, 64)
	titleLabel.Font = Enum.Font.GothamBold
	titleLabel.TextSize = 40
	titleLabel.TextColor3 = GOLD_COLOR
	titleLabel.Text = title
	titleLabel.Parent = gui

	local rows: { TextLabel } = {}
	for index = 1, 10 do
		local row = Instance.new("TextLabel")
		row.Name = `Row_{index}`
		row.BackgroundTransparency = 1
		row.Position = UDim2.new(0, 40, 0, 64 + (index - 1) * 38)
		row.Size = UDim2.new(1, -80, 0, 36)
		row.Font = Enum.Font.GothamMedium
		row.TextSize = 26
		row.TextXAlignment = Enum.TextXAlignment.Left
		row.TextColor3 = Color3.fromRGB(235, 238, 245)
		row.Text = `{index}.  –`
		row.Parent = gui
		table.insert(rows, row)
	end
	return rows
end

-- Befüllt die Zeilen einer Tafel mit einem Ranglisten-Ausschnitt.
local function fillBoard(rows: { TextLabel }, entries: { LeaderboardService.LeaderboardEntry })
	for index, row in rows do
		local entry = entries[index]
		if entry ~= nil then
			local medal = if index == 1 then "🥇" elseif index == 2 then "🥈" elseif index == 3 then "🥉" else `{index}.`
			row.Text = `{medal}  {entry.name}  –  {formatNumber(entry.value)}`
			row.TextColor3 = if index <= 3 then GOLD_COLOR else Color3.fromRGB(235, 238, 245)
		else
			row.Text = `{index}.  –`
			row.TextColor3 = Color3.fromRGB(120, 126, 148)
		end
	end
end

--------------------------------------------------------------------------
-- Portal und Spawn
--------------------------------------------------------------------------

local function buildPortal(folder: Folder)
	local portalCenter = LOBBY_ORIGIN * CFrame.new(0, FLOOR_TOP, -HALL_HALF_DEPTH + 2)

	-- Goldener Torbogen.
	for _, side in { -1, 1 } do
		local pillar = newPart(folder, "PortalPfeiler", true)
		pillar.Size = Vector3.new(2, 12, 2)
		pillar.Color = MARBLE_DARK
		pillar.Material = Enum.Material.Marble
		pillar.CFrame = portalCenter * CFrame.new(side * 6, 6, 0)
	end
	local arch = newPart(folder, "PortalBogen", false)
	arch.Size = Vector3.new(14, 2, 2)
	arch.Color = GOLD_COLOR
	arch.Material = Enum.Material.Metal
	arch.CFrame = portalCenter * CFrame.new(0, 13, 0)

	-- Leuchtende Portal-Scheibe (senkrecht, Achse zeigt durch den Bogen).
	local disc = newPart(folder, "PortalScheibe", false)
	disc.Shape = Enum.PartType.Cylinder
	disc.Size = Vector3.new(0.8, 10, 10)
	disc.Color = PORTAL_COLOR
	disc.Material = Enum.Material.Neon
	disc.Transparency = 0.35
	disc.CFrame = portalCenter * CFrame.new(0, 6, 0) * CFrame.Angles(0, math.rad(90), 0)

	local swirl = Instance.new("ParticleEmitter")
	swirl.Name = "PortalPartikel"
	swirl.Color = ColorSequence.new(PORTAL_COLOR, Color3.new(1, 1, 1))
	swirl.LightEmission = 1
	swirl.Rate = 14
	swirl.Lifetime = NumberRange.new(1, 1.8)
	swirl.Speed = NumberRange.new(2, 4)
	swirl.SpreadAngle = Vector2.new(180, 180)
	swirl.Size = NumberSequence.new(0.5)
	swirl.Parent = disc

	local portalLight = Instance.new("PointLight")
	portalLight.Color = PORTAL_COLOR
	portalLight.Range = 24
	portalLight.Brightness = 1.2
	portalLight.Parent = disc

	-- Schild über dem Portal.
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(320, 60)
	billboard.StudsOffset = Vector3.new(0, 9, 0)
	billboard.MaxDistance = 120
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = PORTAL_COLOR
	label.TextStrokeTransparency = 0.4
	label.Text = "🌍 Zu deiner Insel"
	label.Parent = billboard
	billboard.Parent = disc

	-- Unsichtbarer Auslöser: Berührung teleportiert auf die eigene Insel.
	local touch = newPart(folder, "PortalAusloeser", false)
	touch.Size = Vector3.new(11, 12, 3)
	touch.Transparency = 1
	touch.CanTouch = true
	touch.CFrame = portalCenter * CFrame.new(0, 6, 0)

	touch.Touched:Connect(function(hit: BasePart)
		local character = hit.Parent
		if character == nil then
			return
		end
		local player = Players:GetPlayerFromCharacter(character)
		if player == nil then
			return
		end
		local now = os.clock()
		if now - (lastPortalUse[player] or 0) < PORTAL_COOLDOWN_SECONDS then
			return
		end
		lastPortalUse[player] = now

		if PlanetService.teleportHome(player) then
			local sound = Instance.new("Sound")
			sound.SoundId = "rbxasset://sounds/swoosh.wav"
			sound.Volume = 0.7
			sound.Parent = touch
			sound:Play()
			task.delay(2, function()
				sound:Destroy()
			end)
		end
	end)
end

-- Willkommensschild neben der Tür (innen).
local function buildWelcomeSign(folder: Folder)
	local sign = newPart(folder, "VillaWillkommen", false)
	sign.Size = Vector3.new(9, 5, 0.5)
	sign.Color = BOARD_COLOR
	sign.Material = Enum.Material.SmoothPlastic
	-- Identität: die Front-Fläche zeigt in Richtung -Z, also in die Halle.
	sign.CFrame = LOBBY_ORIGIN * CFrame.new(14, FLOOR_TOP + 6, HALL_HALF_DEPTH - 0.3)

	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.CanvasSize = Vector2.new(450, 250)
	gui.LightInfluence = 0
	gui.Brightness = 1.4
	gui.Parent = sign

	local text = Instance.new("TextLabel")
	text.BackgroundTransparency = 1
	text.Size = UDim2.fromScale(1, 1)
	text.Font = Enum.Font.GothamBold
	text.TextSize = 30
	text.TextWrapped = true
	text.TextColor3 = Color3.fromRGB(235, 238, 245)
	text.Text = "🏰 Willkommen in Planet Forge!\n\nSchau dich um, bestaune die Bestenliste - und spring dann durch das Portal zu deiner eigenen Insel! 🌍"
	text.Parent = gui
end

-- Verschiebt den SpawnLocation-Part in den Eingangsbereich der Villa
-- (oder erzeugt ihn, falls die Place-Datei keinen enthält).
local function ensureSpawnLocation()
	local spawnLocation = Workspace:FindFirstChildWhichIsA("SpawnLocation", true)
	if spawnLocation == nil then
		spawnLocation = Instance.new("SpawnLocation")
		spawnLocation.Name = "VillaSpawn"
		spawnLocation.Anchored = true
		spawnLocation.Parent = Workspace
	end
	local spawnPad = spawnLocation :: SpawnLocation
	spawnPad.Size = Vector3.new(12, 0.4, 12)
	spawnPad.Color = CARPET_COLOR
	spawnPad.Material = Enum.Material.Fabric
	spawnPad.CFrame = LOBBY_ORIGIN * CFrame.new(0, FLOOR_TOP + 0.25, 16)
	spawnPad.Duration = 0
end

function LobbyService.init()
	local folder = Instance.new("Folder")
	folder.Name = "SpawnVilla"

	buildShell(folder)
	buildInterior(folder)
	buildPortal(folder)
	buildWelcomeSign(folder)

	-- Bestenliste-Tafeln links und rechts vom Portal an der Rückwand
	-- (180° gedreht, damit die Front-Fläche in die Halle zeigt).
	energyRows = buildBoard(
		folder,
		LOBBY_ORIGIN * CFrame.new(-17, FLOOR_TOP + 7.5, -HALL_HALF_DEPTH + 0.8) * CFrame.Angles(0, math.rad(180), 0),
		"⚡ Bestenliste – Energie"
	)
	likesRows = buildBoard(
		folder,
		LOBBY_ORIGIN * CFrame.new(17, FLOOR_TOP + 7.5, -HALL_HALF_DEPTH + 0.8) * CFrame.Angles(0, math.rad(180), 0),
		"❤️ Bestenliste – Likes"
	)

	folder.Parent = Workspace
	ensureSpawnLocation()

	Players.PlayerRemoving:Connect(function(player)
		lastPortalUse[player] = nil
	end)

	-- Tafeln periodisch mit dem Ranglisten-Stand befüllen.
	task.spawn(function()
		while true do
			local snapshot = LeaderboardService.getSnapshot()
			fillBoard(energyRows, snapshot.energy)
			fillBoard(likesRows, snapshot.likes)
			task.wait(LEADERBOARD_BOARD_REFRESH_SECONDS)
		end
	end)
end

return LobbyService
