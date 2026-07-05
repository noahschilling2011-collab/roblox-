--!strict
-- Hilfsfunktionen für gewichtete Zufallsauswahl und "1 zu n"-Würfe.
-- Alle Loot-Würfe laufen ausschließlich auf dem Server (server-autoritativ).

export type WeightedEntry<T> = {
	value: T,
	weight: number,
}

local defaultRng = Random.new()

local WeightedRandom = {}

-- Wählt einen Eintrag proportional zu seinem Gewicht aus.
function WeightedRandom.pick<T>(entries: { WeightedEntry<T> }, rng: Random?): T
	assert(#entries > 0, "WeightedRandom.pick benötigt mindestens einen Eintrag")
	local random = rng or defaultRng

	local totalWeight = 0
	for _, entry in entries do
		assert(entry.weight > 0, "Gewichte müssen positiv sein")
		totalWeight += entry.weight
	end

	local roll = random:NextNumber() * totalWeight
	for _, entry in entries do
		roll -= entry.weight
		if roll <= 0 then
			return entry.value
		end
	end

	-- Fließkomma-Restfall: letzten Eintrag zurückgeben.
	return entries[#entries].value
end

-- Gibt mit einer Chance von exakt 1 zu n `true` zurück
-- (z. B. n = 10_000 für den Leuchtenden Kristall).
function WeightedRandom.oneIn(n: number, rng: Random?): boolean
	assert(n >= 1, "n muss >= 1 sein")
	local random = rng or defaultRng
	return random:NextInteger(1, math.floor(n)) == 1
end

return WeightedRandom
