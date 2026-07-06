--!strict
-- ScoreLogic: pure Punkteberechnung von Turmfall (Roblox-frei, testbar).
--
-- Regel aus dem Konzept: Am Rundenende zählt die Y-Höhe jedes überlebenden
-- eigenen Teils (über der Plattform-Oberkante). Wer einen Kollaps verursacht
-- hat, verliert seinen kompletten Einsatz -> 0 Punkte.

local Types = require(script.Parent.Types)

local ScoreLogic = {}

-- Punkte eines einzelnen überlebenden Teils: ganze Studs über der Plattform,
-- mindestens 1 (auch das unterste Teil auf der Plattform zählt).
function ScoreLogic.pointsForPiece(heightAboveBase: number): number
	return math.max(math.floor(heightAboveBase), 1)
end

-- Berechnet die Punkte aller Spieler.
--   pieces    alle in dieser Runde platzierten Teile (auch gefallene)
--   culprits  userIds, die einen Kollaps verursacht haben
-- Rückgabe: userId -> Punkte (nur Spieler, die mindestens 1 Teil platziert haben).
function ScoreLogic.computeScores(
	pieces: { Types.ScoringPiece },
	culprits: { [number]: boolean }
): { [number]: number }
	local scores: { [number]: number } = {}

	for _, piece in pieces do
		if scores[piece.ownerUserId] == nil then
			scores[piece.ownerUserId] = 0
		end
		if piece.fallen then
			continue -- gefallene Teile zählen nicht
		end
		scores[piece.ownerUserId] += ScoreLogic.pointsForPiece(piece.heightAboveBase)
	end

	-- Verursacher verlieren ihren kompletten Einsatz.
	for userId in culprits do
		if scores[userId] ~= nil then
			scores[userId] = 0
		end
	end

	return scores
end

return ScoreLogic
