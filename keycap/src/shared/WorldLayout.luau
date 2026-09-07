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

return WorldLayout
