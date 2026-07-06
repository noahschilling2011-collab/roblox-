--!strict
-- BiomeVisuals: prozedurale Deko-Sets für die Biom-Slots (KEIN Service,
-- reine Bau-Hilfe für den PlanetService).
--
-- Jedes Biom bekommt ein kleines Set aus 3-6 einfachen Parts (Wald =
-- Stämme + Kronen, Wüste = Dünen + Kaktus, Ozean = Wasserscheibe usw.).
-- Höhere Level erzeugen sichtbar mehr Objekte. Die Platzierung ist pro
-- Slot und Level deterministisch (gleicher Seed -> gleicher Look), damit
-- der Planet nach einem Rejoin identisch aussieht.
--
-- BiomeVisuals.build(slotPart, biomeId, level, withPop) ersetzt das
-- Deko-Model unter dem Slot; withPop = true lässt die Teile mit einem
-- Scale-Pop-Tween erscheinen (beim Bauen/Upgraden).

local TweenService = game:GetService("TweenService")

local DEFAULT_SCATTER_RADIUS = 4.6 -- Fallback-Streuradius
local POP_SECONDS = 0.3

export type BuilderFn = (model: Model, top: Vector3, level: number, rng: Random) -> ()

local BiomeVisuals = {}

-- Wird pro build()-Aufruf aus der Zonen-Größe gesetzt (Zonen sind Rechtecke).
local activeScatterRadius = DEFAULT_SCATTER_RADIUS

-- Anzahl Deko-Objekte je Level (Level 1 = 4, Level 5 = 12).
local function objectCount(level: number): number
	return math.clamp(2 + level * 2, 4, 12)
end

local function newPart(
	model: Model,
	shape: Enum.PartType,
	size: Vector3,
	color: Color3,
	material: Enum.Material,
	cframe: CFrame,
	transparency: number?
): BasePart
	local part = Instance.new("Part")
	part.Shape = shape
	part.Size = size
	part.Color = color
	part.Material = material
	part.CFrame = cframe
	part.Transparency = transparency or 0
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Parent = model
	return part
end

-- Hellt eine Farbe um den Faktor auf bzw. dunkelt sie ab (Palette-Abstufungen).
local function shade(color: Color3, factor: number): Color3
	return Color3.new(
		math.clamp(color.R * factor, 0, 1),
		math.clamp(color.G * factor, 0, 1),
		math.clamp(color.B * factor, 0, 1)
	)
end

-- Subtiler Wind-Sway: Part pendelt minimal um seine Position (Endlos-Tween).
local function addSway(part: BasePart, rng: Random)
	local offset = Vector3.new(rng:NextNumber(-0.18, 0.18), rng:NextNumber(0.04, 0.1), rng:NextNumber(-0.18, 0.18))
	local tween = TweenService:Create(
		part,
		TweenInfo.new(rng:NextNumber(2.4, 3.6), Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ CFrame = part.CFrame * CFrame.new(offset) }
	)
	tween:Play()
end

-- Unsichtbarer Anker mit ParticleEmitter für Ambient-Effekte einer Zone.
local function addAmbientEmitter(
	model: Model,
	position: Vector3,
	color: Color3,
	rate: number,
	speed: NumberRange,
	size: number,
	lightEmission: number
): ParticleEmitter
	local anchor = newPart(model, Enum.PartType.Block, Vector3.new(0.2, 0.2, 0.2),
		Color3.new(1, 1, 1), Enum.Material.SmoothPlastic, CFrame.new(position), 1)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(color)
	emitter.LightEmission = lightEmission
	emitter.Rate = rate
	emitter.Lifetime = NumberRange.new(1.2, 2.4)
	emitter.Speed = speed
	emitter.Size = NumberSequence.new(size)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Parent = anchor
	return emitter
end

-- Zufälliger Punkt auf der Zonen-Oberfläche (deterministisch über rng).
local function scatter(top: Vector3, rng: Random, radius: number?): Vector3
	local r = (radius or activeScatterRadius) * math.sqrt(rng:NextNumber())
	local angle = rng:NextNumber() * 2 * math.pi
	return top + Vector3.new(math.cos(angle) * r, 0, math.sin(angle) * r)
end

local function yaw(rng: Random): CFrame
	return CFrame.Angles(0, rng:NextNumber() * 2 * math.pi, 0)
end

--------------------------------------------------------------------------
-- Bausteine
--------------------------------------------------------------------------

local function buildTree(model: Model, base: Vector3, rng: Random, trunkHeight: number, crownColor: Color3)
	newPart(
		model,
		Enum.PartType.Cylinder,
		Vector3.new(trunkHeight, 0.6, 0.6),
		Color3.fromRGB(96, 67, 43),
		Enum.Material.Wood,
		CFrame.new(base + Vector3.new(0, trunkHeight / 2, 0)) * CFrame.Angles(0, 0, math.rad(90))
	)

	-- 2-3 gestaffelte, leicht versetzte Kronen: unten dunkler, oben heller.
	local crownCount = 2 + rng:NextInteger(0, 1)
	local baseSize = trunkHeight * 0.95 + rng:NextNumber() * 0.5
	local topCrown: BasePart? = nil
	for layer = 1, crownCount do
		local t = (layer - 1) / crownCount
		local size = baseSize * (1 - t * 0.38)
		local crown = newPart(
			model,
			Enum.PartType.Ball,
			Vector3.new(size, size * 0.9, size),
			shade(crownColor, 0.82 + t * 0.35),
			Enum.Material.Grass,
			CFrame.new(base + Vector3.new(
				rng:NextNumber(-0.5, 0.5),
				trunkHeight + baseSize * 0.15 + t * baseSize * 0.55,
				rng:NextNumber(-0.5, 0.5)
			))
		)
		topCrown = crown
	end
	if topCrown ~= nil then
		addSway(topCrown, rng)
	end
end

-- Felsen aus 2 ineinandergeschobenen, rotierten Blöcken.
local function buildRock(model: Model, base: Vector3, rng: Random, scale: number, color: Color3)
	for i = 1, 2 do
		local size = Vector3.new(
			scale * rng:NextNumber(0.7, 1.1),
			scale * rng:NextNumber(0.5, 0.9),
			scale * rng:NextNumber(0.7, 1.1)
		)
		newPart(
			model,
			Enum.PartType.Block,
			size,
			shade(color, 0.9 + i * 0.1),
			Enum.Material.Slate,
			CFrame.new(base + Vector3.new(rng:NextNumber(-0.4, 0.4), size.Y * 0.3, rng:NextNumber(-0.4, 0.4)))
				* yaw(rng)
				* CFrame.Angles(math.rad(rng:NextNumber(-12, 12)), 0, math.rad(rng:NextNumber(-12, 12)))
		)
	end
end

local function buildCactus(model: Model, base: Vector3, rng: Random)
	local height = 1.6 + rng:NextNumber() * 1.2
	local green = Color3.fromRGB(88, 148, 82)
	newPart(
		model,
		Enum.PartType.Cylinder,
		Vector3.new(height, 0.7, 0.7),
		green,
		Enum.Material.Grass,
		CFrame.new(base + Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, 0, math.rad(90))
	)
	-- Ein kleiner Seitenarm.
	newPart(
		model,
		Enum.PartType.Cylinder,
		Vector3.new(0.9, 0.5, 0.5),
		green,
		Enum.Material.Grass,
		CFrame.new(base + Vector3.new(0.55, height * 0.6, 0)) * CFrame.Angles(0, 0, math.rad(35))
	)
end

--------------------------------------------------------------------------
-- Biom-Baumeister (einer pro Canon-Biom)
--------------------------------------------------------------------------

BiomeVisuals.Builders = {
	wiese = function(model: Model, top: Vector3, level: number, rng: Random)
		for i = 1, objectCount(level) do
			local base = scatter(top, rng)
			if i % 2 == 0 then
				-- Grasbüschel: flachgedrückte grüne Kugel.
				local s = 0.7 + rng:NextNumber() * 0.6
				newPart(model, Enum.PartType.Ball, Vector3.new(s * 1.6, s, s * 1.6),
					Color3.fromRGB(96, 170, 84), Enum.Material.Grass, CFrame.new(base + Vector3.new(0, s * 0.3, 0)))
			else
				-- Blume: dünner Stiel + bunte Blüte.
				local petals = { Color3.fromRGB(235, 120, 150), Color3.fromRGB(240, 200, 90), Color3.fromRGB(150, 140, 235) }
				newPart(model, Enum.PartType.Cylinder, Vector3.new(0.9, 0.12, 0.12),
					Color3.fromRGB(90, 150, 70), Enum.Material.Grass,
					CFrame.new(base + Vector3.new(0, 0.45, 0)) * CFrame.Angles(0, 0, math.rad(90)))
				newPart(model, Enum.PartType.Ball, Vector3.new(0.4, 0.4, 0.4),
					petals[rng:NextInteger(1, #petals)], Enum.Material.SmoothPlastic,
					CFrame.new(base + Vector3.new(0, 0.95, 0)))
			end
		end
	end,

	wald = function(model: Model, top: Vector3, level: number, rng: Random)
		for _ = 1, objectCount(level) - 1 do
			buildTree(model, scatter(top, rng), rng, 1.8 + rng:NextNumber() * 1.4, Color3.fromRGB(64, 118, 62))
		end
		buildRock(model, scatter(top, rng), rng, 1.1, Color3.fromRGB(118, 115, 110))
		-- Glühwürmchen ab Level 2 (sparsam, mit Licht-Schimmer).
		if level >= 2 then
			addAmbientEmitter(model, top + Vector3.new(0, 2.2, 0), Color3.fromRGB(255, 240, 150),
				1 + level * 0.4, NumberRange.new(0.3, 0.9), 0.18, 1)
		end
	end,

	wueste = function(model: Model, top: Vector3, level: number, rng: Random)
		-- Dezenter Sandwirbel über der Zone.
		addAmbientEmitter(model, top + Vector3.new(0, 1.2, 0), Color3.fromRGB(222, 198, 150),
			1.5, NumberRange.new(1.5, 3), 1.4, 0.1)
		for i = 1, objectCount(level) do
			local base = scatter(top, rng)
			if i % 3 == 0 then
				buildCactus(model, base, rng)
			else
				-- Düne: flache Sandkugel.
				local s = 1.2 + rng:NextNumber() * 1.4
				newPart(model, Enum.PartType.Ball, Vector3.new(s * 1.8, s * 0.5, s * 1.3),
					Color3.fromRGB(214, 186, 130), Enum.Material.Sand,
					CFrame.new(base + Vector3.new(0, s * 0.12, 0)) * yaw(rng))
			end
		end
	end,

	ozean = function(model: Model, top: Vector3, level: number, rng: Random)
		-- Wasserscheibe über fast der ganzen Zone, mit Glasglanz.
		local waterSize = activeScatterRadius * 2 + 2
		newPart(model, Enum.PartType.Cylinder, Vector3.new(0.35, waterSize, waterSize),
			Color3.fromRGB(60, 140, 210), Enum.Material.Glass,
			CFrame.new(top + Vector3.new(0, 0.18, 0)) * CFrame.Angles(0, 0, math.rad(90)), 0.35)
		for _ = 1, objectCount(level) - 2 do
			-- Kleine Felsen, die aus dem Wasser ragen.
			local s = 0.5 + rng:NextNumber() * 0.7
			newPart(model, Enum.PartType.Ball, Vector3.new(s, s * 0.8, s),
				Color3.fromRGB(105, 110, 120), Enum.Material.Slate,
				CFrame.new(scatter(top, rng, 3.6) + Vector3.new(0, 0.3, 0)) * yaw(rng))
		end
		-- Dezentes Funkeln auf der Wasseroberfläche.
		local sparkleAnchor = newPart(model, Enum.PartType.Block, Vector3.new(0.2, 0.2, 0.2),
			Color3.new(1, 1, 1), Enum.Material.SmoothPlastic, CFrame.new(top + Vector3.new(0, 0.6, 0)), 1)
		local emitter = Instance.new("ParticleEmitter")
		emitter.Color = ColorSequence.new(Color3.fromRGB(220, 245, 255))
		emitter.LightEmission = 0.8
		emitter.Rate = 2
		emitter.Lifetime = NumberRange.new(0.8, 1.4)
		emitter.Speed = NumberRange.new(0.5, 1)
		emitter.Size = NumberSequence.new(0.25)
		emitter.Parent = sparkleAnchor
	end,

	dschungel = function(model: Model, top: Vector3, level: number, rng: Random)
		for _ = 1, objectCount(level) - 1 do
			buildTree(model, scatter(top, rng), rng, 2.6 + rng:NextNumber() * 1.6, Color3.fromRGB(38, 105, 44))
		end
		-- Grosses Blatt als Unterholz-Akzent.
		newPart(model, Enum.PartType.Block, Vector3.new(1.6, 0.1, 0.9),
			shade(Color3.fromRGB(52, 130, 58), 1.1), Enum.Material.Grass,
			CFrame.new(scatter(top, rng) + Vector3.new(0, 0.3, 0)) * yaw(rng) * CFrame.Angles(math.rad(20), 0, 0))
	end,

	eiswelt = function(model: Model, top: Vector3, level: number, rng: Random)
		for i = 1, objectCount(level) do
			local base = scatter(top, rng)
			if i % 2 == 0 then
				-- Eiskristall: gekippter Block.
				local h = 1.2 + rng:NextNumber() * 1.6
				newPart(model, Enum.PartType.Block, Vector3.new(0.6, h, 0.6),
					Color3.fromRGB(170, 220, 250), Enum.Material.Ice,
					CFrame.new(base + Vector3.new(0, h / 2, 0)) * yaw(rng) * CFrame.Angles(math.rad(rng:NextNumber() * 14 - 7), 0, math.rad(45)), 0.15)
			else
				-- Schneehaufen.
				local s = 0.9 + rng:NextNumber() * 0.9
				newPart(model, Enum.PartType.Ball, Vector3.new(s * 1.5, s * 0.6, s * 1.2),
					Color3.fromRGB(240, 246, 252), Enum.Material.Snow,
					CFrame.new(base + Vector3.new(0, s * 0.15, 0)) * yaw(rng))
			end
		end
	end,

	vulkan = function(model: Model, top: Vector3, level: number, rng: Random)
		-- Vulkankegel in der Slot-Mitte: zwei gestapelte Zylinder + Lavakuppe.
		newPart(model, Enum.PartType.Cylinder, Vector3.new(1.4, 4.6, 4.6),
			Color3.fromRGB(62, 58, 56), Enum.Material.Basalt,
			CFrame.new(top + Vector3.new(0, 0.7, 0)) * CFrame.Angles(0, 0, math.rad(90)))
		newPart(model, Enum.PartType.Cylinder, Vector3.new(1.2, 2.8, 2.8),
			Color3.fromRGB(52, 48, 46), Enum.Material.Basalt,
			CFrame.new(top + Vector3.new(0, 1.9, 0)) * CFrame.Angles(0, 0, math.rad(90)))
		local lava = newPart(model, Enum.PartType.Ball, Vector3.new(1.8, 1.1, 1.8),
			Color3.fromRGB(255, 96, 32), Enum.Material.Neon, CFrame.new(top + Vector3.new(0, 2.6, 0)))
		-- Glut-Partikel aus dem Krater.
		local emitter = Instance.new("ParticleEmitter")
		emitter.Color = ColorSequence.new(Color3.fromRGB(255, 140, 40), Color3.fromRGB(255, 60, 20))
		emitter.LightEmission = 1
		emitter.Rate = 3 + level
		emitter.Lifetime = NumberRange.new(0.6, 1.2)
		emitter.Speed = NumberRange.new(2, 4)
		emitter.Size = NumberSequence.new(0.3)
		emitter.Parent = lava
		-- Lavabrocken drumherum (mehr pro Level).
		for _ = 1, objectCount(level) - 2 do
			local s = 0.5 + rng:NextNumber() * 0.6
			newPart(model, Enum.PartType.Ball, Vector3.new(s, s * 0.8, s),
				Color3.fromRGB(90, 60, 50), Enum.Material.CrackedLava,
				CFrame.new(scatter(top, rng) + Vector3.new(0, s * 0.3, 0)) * yaw(rng))
		end
	end,

	pilzwald = function(model: Model, top: Vector3, level: number, rng: Random)
		local caps = { Color3.fromRGB(206, 74, 74), Color3.fromRGB(150, 96, 208) }
		for i = 1, objectCount(level) do
			local base = scatter(top, rng)
			local stemHeight = 0.9 + rng:NextNumber() * 1.3
			newPart(model, Enum.PartType.Cylinder, Vector3.new(stemHeight, 0.5, 0.5),
				Color3.fromRGB(226, 214, 190), Enum.Material.SmoothPlastic,
				CFrame.new(base + Vector3.new(0, stemHeight / 2, 0)) * CFrame.Angles(0, 0, math.rad(90)))
			local capSize = 0.9 + rng:NextNumber() * 0.8
			-- Ab Level 3 leuchtet jeder dritte Pilz.
			local glowing = level >= 3 and i % 3 == 0
			newPart(model, Enum.PartType.Ball, Vector3.new(capSize, capSize * 0.55, capSize),
				caps[rng:NextInteger(1, #caps)],
				if glowing then Enum.Material.Neon else Enum.Material.SmoothPlastic,
				CFrame.new(base + Vector3.new(0, stemHeight + capSize * 0.15, 0)))
		end
	end,

	kristallfelder = function(model: Model, top: Vector3, level: number, rng: Random)
		local colors = { Color3.fromRGB(110, 230, 230), Color3.fromRGB(170, 120, 255) }
		for i = 1, objectCount(level) do
			local base = scatter(top, rng)
			local h = 1.4 + rng:NextNumber() * 2
			local crystal = newPart(model, Enum.PartType.Block, Vector3.new(0.55, h, 0.55),
				colors[i % 2 + 1],
				if i % 2 == 0 then Enum.Material.Neon else Enum.Material.Glass,
				CFrame.new(base + Vector3.new(0, h / 2, 0)) * yaw(rng) * CFrame.Angles(math.rad(rng:NextNumber() * 16 - 8), 0, math.rad(45)), 0.1)
			if level >= 3 and i == 1 then
				local light = Instance.new("PointLight")
				light.Color = crystal.Color
				light.Range = 8
				light.Brightness = 0.8
				light.Parent = crystal
			end
		end
	end,

	kosmische_ebene = function(model: Model, top: Vector3, level: number, rng: Random)
		for i = 1, objectCount(level) do
			local base = scatter(top, rng)
			if i % 2 == 0 then
				-- Schwebender Felsbrocken.
				local s = 0.5 + rng:NextNumber() * 0.8
				newPart(model, Enum.PartType.Block, Vector3.new(s, s * 0.8, s),
					Color3.fromRGB(70, 66, 92), Enum.Material.Slate,
					CFrame.new(base + Vector3.new(0, 1.2 + rng:NextNumber() * 2, 0)) * yaw(rng) * CFrame.Angles(math.rad(20), 0, math.rad(15)))
			else
				-- Kleiner leuchtender Stern.
				newPart(model, Enum.PartType.Ball, Vector3.new(0.35, 0.35, 0.35),
					Color3.fromRGB(255, 235, 170), Enum.Material.Neon,
					CFrame.new(base + Vector3.new(0, 0.8 + rng:NextNumber() * 2.4, 0)))
			end
		end
		-- Sanftes Sternenflimmern über dem Slot.
		local anchor = newPart(model, Enum.PartType.Block, Vector3.new(0.2, 0.2, 0.2),
			Color3.new(1, 1, 1), Enum.Material.SmoothPlastic, CFrame.new(top + Vector3.new(0, 2, 0)), 1)
		local emitter = Instance.new("ParticleEmitter")
		emitter.Color = ColorSequence.new(Color3.fromRGB(200, 190, 255))
		emitter.LightEmission = 1
		emitter.Rate = 2
		emitter.Lifetime = NumberRange.new(1, 2)
		emitter.Speed = NumberRange.new(0.3, 0.8)
		emitter.Size = NumberSequence.new(0.2)
		emitter.Parent = anchor
	end,
} :: { [string]: BuilderFn }

--------------------------------------------------------------------------
-- Öffentliche API
--------------------------------------------------------------------------

-- Baut das Deko-Set eines Slots neu auf (ersetzt ein vorhandenes).
function BiomeVisuals.build(slotPart: BasePart, biomeId: string, level: number, withPop: boolean)
	local existing = slotPart:FindFirstChild("Deko")
	if existing ~= nil then
		existing:Destroy()
	end

	local builder = BiomeVisuals.Builders[biomeId]
	if builder == nil then
		warn(`[PlanetForge] Kein Deko-Set für Biom {biomeId}`)
		return
	end

	local model = Instance.new("Model")
	model.Name = "Deko"

	-- Streuradius aus der tatsächlichen Zonen-Größe ableiten.
	activeScatterRadius = math.max(3, math.min(slotPart.Size.X, slotPart.Size.Z) / 2 - 2)

	local top = slotPart.Position + Vector3.new(0, slotPart.Size.Y / 2, 0)
	-- Deterministischer Seed pro Zonen-Position und Level.
	local seed = math.floor(math.abs(slotPart.Position.X) * 7 + math.abs(slotPart.Position.Z) * 13) + level * 101
	builder(model, top, level, Random.new(seed))

	-- Höhere Level wirken prächtiger: Deko wächst pro Level leicht mit.
	local sizeScale = 1 + (level - 1) * 0.06
	if sizeScale > 1 then
		for _, child in model:GetDescendants() do
			if child:IsA("BasePart") then
				child.Size *= sizeScale
			end
		end
	end

	model.Parent = slotPart

	-- Scale-Pop: Teile wachsen mit Back-Easing auf ihre Zielgröße.
	if withPop then
		for _, child in model:GetDescendants() do
			if child:IsA("BasePart") then
				local targetSize = child.Size
				child.Size = targetSize * 0.05
				TweenService:Create(
					child,
					TweenInfo.new(POP_SECONDS, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
					{ Size = targetSize }
				):Play()
			end
		end
	end
end

-- Entfernt das Deko-Set (leerer Slot).
function BiomeVisuals.clear(slotPart: BasePart)
	local existing = slotPart:FindFirstChild("Deko")
	if existing ~= nil then
		existing:Destroy()
	end
end

return BiomeVisuals
