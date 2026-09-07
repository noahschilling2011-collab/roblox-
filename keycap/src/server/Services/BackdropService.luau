--!strict
-- Der Hintergrund. Hier kommt der Massstab her: eine Kaffeetasse am
-- Horizont, so hoch wie ein Hochhaus, sagt in einer halben Sekunde, wie
-- klein man ist. Kein Text kann das.
--
-- Alles steht hinter der Spielflaeche, nichts kollidiert, nichts ist
-- betretbar. Alle Teile sind Silhouetten im Gegenlicht des Monitors -
-- deshalb nur wenig heller als die Matte.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local WorldConfig = require(Shared.Config.WorldConfig)
local Theme = require(Shared.Theme)

local BackdropService = {}

local function kulisse(name: string, size: Vector3, cframe: CFrame, farbe: Color3, parent: Instance): BasePart
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CastShadow = false
	part.Material = Enum.Material.SmoothPlastic
	part.Color = farbe
	part.Parent = parent
	return part
end

local function buildCup(parent: Instance): number
	local config = WorldConfig.BACKDROP
	local mitte = config.CUP_POSITION
	local anzahl = 1

	-- Der Becher. Part.Shape = Cylinder liegt auf der X-Achse, deshalb
	-- die Drehung um Z: aus liegend wird stehend.
	local body = kulisse("Tasse", Vector3.new(config.CUP_HEIGHT, config.CUP_RADIUS * 2, config.CUP_RADIUS * 2),
		CFrame.new(mitte) * CFrame.Angles(0, 0, math.rad(90)), Theme.WORLD.CUP, parent)
	body.Shape = Enum.PartType.Cylinder

	-- Der dunkle Kreis oben: der Kaffee. Ein flacher Zylinder knapp unter
	-- der Oberkante.
	local coffee = kulisse("Kaffee", Vector3.new(4, config.CUP_RADIUS * 1.8, config.CUP_RADIUS * 1.8),
		CFrame.new(mitte + Vector3.new(0, config.CUP_HEIGHT / 2 - 6, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Theme.WORLD.CUP_COFFEE, parent)
	coffee.Shape = Enum.PartType.Cylinder
	anzahl += 1

	-- Der Henkel als Kreisbogen aus wenigen Quadern.
	for i = 1, config.CUP_HANDLE_PARTS do
		local winkel = math.rad(-70 + (140 / (config.CUP_HANDLE_PARTS - 1)) * (i - 1))
		local versatz = Vector3.new(
			config.CUP_RADIUS + math.cos(winkel) * config.CUP_HANDLE_RADIUS,
			math.sin(winkel) * config.CUP_HANDLE_RADIUS,
			0
		)
		kulisse("Henkel" .. i, Vector3.new(26, 60, 26),
			CFrame.new(mitte + versatz) * CFrame.Angles(0, 0, winkel), Theme.WORLD.CUP, parent)
		anzahl += 1
	end
	return anzahl
end

local function buildCable(parent: Instance): number
	local config = WorldConfig.BACKDROP
	local von, bis = config.CABLE_START, config.CABLE_END
	for i = 1, config.CABLE_SEGMENTS do
		local anteil = (i - 0.5) / config.CABLE_SEGMENTS
		-- Bogen: eine Parabel ueber die Strecke, in der Mitte am hoechsten.
		local hoehe = math.sin(anteil * math.pi) * config.CABLE_ARC
		local punkt = von:Lerp(bis, anteil) + Vector3.new(0, hoehe, 0)
		local naechster = von:Lerp(bis, math.min(1, anteil + 1 / config.CABLE_SEGMENTS))
			+ Vector3.new(0, math.sin(math.min(1, anteil + 1 / config.CABLE_SEGMENTS) * math.pi) * config.CABLE_ARC, 0)
		local laenge = (naechster - punkt).Magnitude
		local segment = kulisse("Kabel" .. i,
			Vector3.new(laenge * 1.15, config.CABLE_THICKNESS, config.CABLE_THICKNESS),
			CFrame.lookAt(punkt, naechster) * CFrame.Angles(0, math.rad(90), 0),
			Theme.WORLD.CABLE, parent)
		segment.Shape = Enum.PartType.Cylinder
	end
	return config.CABLE_SEGMENTS
end

local function buildMouse(parent: Instance): number
	local config = WorldConfig.BACKDROP
	kulisse("Maus", config.MOUSE_SIZE, CFrame.new(config.MOUSE_POSITION), Theme.WORLD.MOUSE, parent)

	local wheel = kulisse("Scrollrad", config.MOUSE_WHEEL_SIZE,
		CFrame.new(config.MOUSE_POSITION + Vector3.new(0, config.MOUSE_SIZE.Y / 2, -config.MOUSE_SIZE.Z / 4))
			* CFrame.Angles(0, 0, math.rad(90)),
		Theme.WORLD.SIGNAL_DIM, parent)
	wheel.Shape = Enum.PartType.Cylinder
	wheel.Material = Enum.Material.Neon
	return 2
end

local function buildDust(parent: Instance): number
	local config = WorldConfig.BACKDROP
	local anker = kulisse("Staub", Vector3.new(1, 1, 1), CFrame.new(config.DUST_POSITION), Theme.WORLD.DUST, parent)
	anker.Transparency = 1

	-- Ohne Bewegung in der Luft wirkt jede Szene tot.
	-- ungeprueft: ob ein ParticleEmitter OHNE Texture-Asset sichtbar ist.
	-- Falls nicht, bleibt die Luft leer - es geht nichts kaputt, es fehlt
	-- nur der Staub. Eine Asset-ID wird hier NICHT erfunden.
	local emitter = Instance.new("ParticleEmitter")
	emitter.Rate = config.DUST_RATE
	emitter.Lifetime = NumberRange.new(config.DUST_LIFETIME * 0.7, config.DUST_LIFETIME)
	emitter.Speed = NumberRange.new(0, config.DUST_SPEED)
	emitter.Size = NumberSequence.new(config.DUST_SIZE)
	emitter.Transparency = NumberSequence.new(0.6)
	emitter.Color = ColorSequence.new(Theme.WORLD.DUST)
	emitter.LightEmission = 0.6
	-- Explizit, weil der Standard zwischen Studio-Insert und Instance.new
	-- unterschiedlich ist. 1 = der Staub wird vom Szenenlicht beeinflusst,
	-- er soll im Dunkeln dunkel sein.
	emitter.LightInfluence = 1
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Parent = anker
	return 1
end

function BackdropService.start()
	local alt = workspace:FindFirstChild("Backdrop")
	if alt then
		alt:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = "Backdrop"

	local anzahl = buildCup(folder) + buildCable(folder) + buildMouse(folder) + buildDust(folder)
	folder.Parent = workspace

	print(("[KEYCAP] BackdropService: %d Kulissenteile (Budget %d)"):format(anzahl, WorldConfig.BACKDROP_BUDGET))
end

return BackdropService
