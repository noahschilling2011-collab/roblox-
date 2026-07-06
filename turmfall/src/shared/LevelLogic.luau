--!strict
-- LevelLogic: pure XP-/Level-Kurve (Roblox-frei, testbar).
--
-- Sichtbare Langzeit-Progression ist einer der stärksten Treiber der
-- Roblox-Topspiele. Die Kurve ist bewusst einfach: Level 2 kostet 100 XP,
-- jedes weitere Level 50 XP mehr als das vorherige (100, 150, 200, ...).
-- Frühe Level kommen schnell (Erfolgserlebnis am ersten Abend), späte
-- Level bleiben Langzeitziel.

local LevelLogic = {}

-- XP-Kosten, um von `level` auf `level + 1` zu kommen.
function LevelLogic.xpForNextLevel(level: number): number
	return 100 + (math.max(level, 1) - 1) * 50
end

-- Level für einen XP-Gesamtstand (Level 1 = 0 XP).
function LevelLogic.levelForXp(xp: number): number
	local level = 1
	local remaining = math.max(xp, 0)
	while remaining >= LevelLogic.xpForNextLevel(level) do
		remaining -= LevelLogic.xpForNextLevel(level)
		level += 1
		if level >= 200 then
			break -- Sicherheitsdeckel
		end
	end
	return level
end

-- Fortschritt innerhalb des aktuellen Levels (für Anzeigen): (aktuell, benötigt).
function LevelLogic.progressInLevel(xp: number): (number, number)
	local level = 1
	local remaining = math.max(xp, 0)
	while remaining >= LevelLogic.xpForNextLevel(level) do
		remaining -= LevelLogic.xpForNextLevel(level)
		level += 1
		if level >= 200 then
			break
		end
	end
	return remaining, LevelLogic.xpForNextLevel(level)
end

return LevelLogic
