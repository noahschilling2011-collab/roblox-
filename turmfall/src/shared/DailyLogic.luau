--!strict
-- DailyLogic: pure Tages-Bonus-Regeln (Roblox-frei, testbar).
--
-- Regeln: Ein Bonus pro UTC-Tag. Aufeinanderfolgende Tage erhöhen die
-- Serie (Streak); ein verpasster Tag setzt sie auf 1 zurück. Die Serie
-- wird auf die Länge der Belohnungstabelle gedeckelt (Tag 7+ = Maximum).

local DailyLogic = {}

-- UTC-Tagesnummer eines Unix-Zeitstempels.
function DailyLogic.dayNumber(unixTime: number): number
	return math.floor(unixTime / 86400)
end

-- Versucht, den Tages-Bonus zu beanspruchen.
--   lastClaimDay  Tagesnummer des letzten Bonus (0 = noch nie)
--   today         aktuelle Tagesnummer
--   streak        bisherige Serie
--   rewards       Belohnungstabelle (Index = Serientag)
-- Rückgabe: (reward?, newStreak) - reward nil = heute schon kassiert.
function DailyLogic.claim(
	lastClaimDay: number,
	today: number,
	streak: number,
	rewards: { number }
): (number?, number)
	if lastClaimDay >= today then
		return nil, streak -- heute schon kassiert
	end
	local newStreak = if lastClaimDay == today - 1 then streak + 1 else 1
	local index = math.clamp(newStreak, 1, #rewards)
	return rewards[index], newStreak
end

return DailyLogic
