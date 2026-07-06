--!strict
-- BlameLogic: der pure Schuld-Algorithmus von Turmfall.
--
-- Regel aus dem Konzept: "Das zuletzt platzierte Teil, das physischen
-- Kontakt zur Kollaps-Kaskade hatte, bestimmt den Verursacher."
--
-- Dieses Modul ist bewusst frei von Roblox-APIs (nur Zahlen und Tabellen),
-- damit der Algorithmus in einer puren Luau-VM getestet werden kann.
-- "Kontakt" wird über den Ringpuffer angenähert: Zwei Teile hatten Kontakt,
-- wenn ihre Mittelpunkte in irgendeinem Sample näher beieinander lagen als
-- die Summe ihrer Näherungsradien plus Toleranz.

local Types = require(script.Parent.Types)

local BlameLogic = {}

local function distance(a: Types.Vec3, b: Types.Vec3): number
	local dx = a.x - b.x
	local dy = a.y - b.y
	local dz = a.z - b.z
	return math.sqrt(dx * dx + dy * dy + dz * dz)
end

-- Hatte `pieceId` in irgendeinem Sample Kontakt zu einem Kaskaden-Teil?
local function hadContactWithCascade(
	pieceId: number,
	samples: { Types.RingSample },
	fallenSet: { [number]: boolean },
	radii: { [number]: number },
	margin: number
): boolean
	local ownRadius = radii[pieceId] or 2
	for _, sample in samples do
		local ownPosition = sample.positions[pieceId]
		if ownPosition == nil then
			continue
		end
		for fallenId in fallenSet do
			if fallenId == pieceId then
				continue
			end
			local fallenPosition = sample.positions[fallenId]
			if fallenPosition == nil then
				continue
			end
			local contactDistance = ownRadius + (radii[fallenId] or 2) + margin
			if distance(ownPosition, fallenPosition) <= contactDistance then
				return true
			end
		end
	end
	return false
end

-- Ermittelt das Verursacher-Teil eines Kollapses.
--
--   placements  Platzierungs-Log (Server loggt Platzierer + Zeitstempel)
--   samples     Ringpuffer-Samples der letzten Sekunden (4 Hz)
--   fallenSet   pieceIds der Kollaps-Kaskade (gefallene Teile)
--   radii       pieceId -> Näherungsradius (aus PartCatalog)
--   margin      Kontakt-Toleranz in Studs
--
-- Rückgabe: (culpritPieceId?, culpritUserId?) - nil, wenn kein Teil der
-- Regel entspricht (dann gibt es fairerweise KEINEN Verursacher).
function BlameLogic.findCulprit(
	placements: { Types.PlacementRecord },
	samples: { Types.RingSample },
	fallenSet: { [number]: boolean },
	radii: { [number]: number },
	margin: number
): (number?, number?)
	-- Neueste Platzierung zuerst prüfen (Kopie, Original nicht verändern).
	local sorted = table.clone(placements)
	table.sort(sorted, function(a, b)
		return a.placedAt > b.placedAt
	end)

	for _, record in sorted do
		-- Ein Teil, das selbst Teil der Kaskade ist, hatte trivialerweise
		-- Kontakt zur Kaskade.
		if fallenSet[record.pieceId] == true then
			return record.pieceId, record.ownerUserId
		end
		if hadContactWithCascade(record.pieceId, samples, fallenSet, radii, margin) then
			return record.pieceId, record.ownerUserId
		end
	end

	return nil, nil
end

return BlameLogic
