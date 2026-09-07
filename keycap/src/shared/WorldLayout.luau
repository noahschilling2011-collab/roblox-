--!strict
-- Wo was in der Welt steht. Reine Rechnung, kein Roblox-API - damit der
-- Server und das Build-Script (tools/build-rbxlx.mjs) dieselben Positionen
-- benutzen und die Vorschau in der Studio-Datei exakt dem entspricht, was
-- beim Druecken von Play entsteht.

local WorldConfig = require(script.Parent.Config.WorldConfig)

local WorldLayout = {}

export type Box = { size: Vector3, position: Vector3 }

function WorldLayout.plotPosition(index: number): Vector3
	local origin = WorldConfig.PLOT_ORIGIN
	local offset = (index - 1) * WorldConfig.PLOT_SPACING
	local centering = (WorldConfig.PLOT_COUNT - 1) * WorldConfig.PLOT_SPACING / 2
	return Vector3.new(origin.X + offset - centering, origin.Y, origin.Z)
end

function WorldLayout.signPosition(plotCenter: Vector3): Vector3
	return Vector3.new(plotCenter.X, plotCenter.Y + 8, plotCenter.Z + WorldConfig.PLOT_SIZE.Z / 2)
end

function WorldLayout.slotPosition(plotCenter: Vector3, slotIndex: number): Vector3
	local columns = WorldConfig.SLOT_COLUMNS
	local col = (slotIndex - 1) % columns
	local row = math.floor((slotIndex - 1) / columns)
	local spacing = WorldConfig.SLOT_SPACING
	local xOffset = (col - (columns - 1) / 2) * spacing
	local zOffset = (row - 1) * spacing
	local top = plotCenter.Y + WorldConfig.PLOT_SIZE.Y / 2 + WorldConfig.KEY_SIZE.Y / 2
	return Vector3.new(plotCenter.X + xOffset, top, plotCenter.Z + zOffset)
end

-- Streifen vor der Plotreihe. Verbindet alle Plots - zwischen zweien liegen
-- sonst PLOT_SPACING - PLOT_SIZE.X Studs Luecke.
function WorldLayout.promenade(): Box
	local origin = WorldConfig.PLOT_ORIGIN
	local z = origin.Z + WorldConfig.PLOT_SIZE.Z / 2 + WorldConfig.PROMENADE_DEPTH / 2
	return {
		size = Vector3.new(
			WorldConfig.PLOT_COUNT * WorldConfig.PLOT_SPACING,
			WorldConfig.PLOT_SIZE.Y,
			WorldConfig.PROMENADE_DEPTH
		),
		position = Vector3.new(origin.X, origin.Y, z),
	}
end

-- Weg von der Promenade bis hinter das letzte Pad.
function WorldLayout.path(): Box
	local origin = WorldConfig.PLOT_ORIGIN
	local promenade = WorldLayout.promenade()
	local startZ = promenade.position.Z + WorldConfig.PROMENADE_DEPTH / 2

	local farthestZ = 0
	for _, position in WorldConfig.STAGE_PAD_POSITIONS do
		farthestZ = math.min(farthestZ, position.Z)
	end
	local endZ = farthestZ - WorldConfig.STAGE_PAD_SIZE.Z / 2 - WorldConfig.PATH_MARGIN

	return {
		size = Vector3.new(WorldConfig.PATH_WIDTH, WorldConfig.PLOT_SIZE.Y, startZ - endZ),
		position = Vector3.new(origin.X, origin.Y, (startZ + endZ) / 2),
	}
end

-- Maximale Sprungweite bei gegebener WalkSpeed. Schiefer Wurf, gleiche
-- Hoehe: t = 2 * v0 / g, d = speed * t.
function WorldLayout.jumpDistance(speed: number): number
	local flugzeit = 2 * WorldConfig.JUMP_POWER / WorldConfig.JUMP_GRAVITY
	return speed * flugzeit
end

-- Wie schnell muss man mindestens sein, um diese Luecke zu schaffen?
function WorldLayout.speedForGap(gap: number): number
	local flugzeit = 2 * WorldConfig.JUMP_POWER / WorldConfig.JUMP_GRAVITY
	return gap / flugzeit
end

-- Die tatsaechlich zu ueberspringende Strecke einer Stage. Nicht die
-- Luecke: wer seitlich versetzt springt, legt die Diagonale zurueck.
function WorldLayout.stageJumpDistance(stageIndex: number): number
	local stage = WorldConfig.STAGES[stageIndex]
	assert(stage ~= nil, "unbekannte Stage: " .. tostring(stageIndex))
	local seitlich = stage.sideways * 2
	return math.sqrt(stage.gap ^ 2 + seitlich ^ 2)
end

-- Die Plattformen einer Stage, von der Promenade weg Richtung Pad.
-- Jede Plattform ist eine Riesen-Tastenkappe; zwischen ihnen liegt die
-- Luecke aus WorldConfig.STAGES.
export type Platform = { size: Vector3, position: Vector3, moves: boolean }

function WorldLayout.stagePlatforms(stageIndex: number): { Platform }
	local stage = WorldConfig.STAGES[stageIndex]
	assert(stage ~= nil, "unbekannte Stage: " .. tostring(stageIndex))

	local origin = WorldConfig.PLOT_ORIGIN
	-- Start: hinter der Promenade bei Stage 1, sonst hinter dem vorigen Pad.
	local startZ
	if stageIndex == 1 then
		local promenade = WorldLayout.promenade()
		startZ = promenade.position.Z - WorldConfig.PROMENADE_DEPTH / 2
	else
		local vorigesPad = WorldConfig.STAGE_PAD_POSITIONS[stageIndex - 1]
		startZ = vorigesPad.Z - WorldConfig.STAGE_PAD_SIZE.Z / 2
	end
	local endZ = WorldConfig.STAGE_PAD_POSITIONS[stageIndex].Z + WorldConfig.STAGE_PAD_SIZE.Z / 2

	local schritt = stage.depth + stage.gap
	local strecke = startZ - endZ
	local anzahl = math.max(1, math.floor(strecke / schritt))

	local platforms: { Platform } = {}
	for i = 1, anzahl do
		-- Erste Plattform eine Luecke hinter dem Start, letzte eine Luecke
		-- vor dem Pad - so ist der Ein- und Ausstieg derselbe Sprung.
		local z = startZ - stage.gap - stage.depth / 2 - (i - 1) * schritt
		local seitlich = 0
		if stage.sideways > 0 then
			seitlich = if i % 2 == 0 then stage.sideways else -stage.sideways
		end
		table.insert(platforms, {
			size = Vector3.new(stage.width, WorldConfig.PLOT_SIZE.Y, stage.depth),
			position = Vector3.new(origin.X + seitlich, origin.Y, z),
			moves = stage.moves and i % WorldConfig.MOVING_EVERY == 0,
		})
	end
	return platforms
end

return WorldLayout
