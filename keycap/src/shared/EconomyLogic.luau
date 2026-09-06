--!strict
-- Reine Rechenlogik der KEYCAP-RUSH-Oekonomie. Kein Roblox-API, keine
-- Instanzen - damit laeuft dieses Modul in der Test-VM (keycap/tests) und
-- auf dem Server dieselbe Rechnung. Der Client bekommt nur Ergebnisse.

local EconomyConfig = require(script.Parent.Config.EconomyConfig)

local EconomyLogic = {}

-- ---------------------------------------------------------------------
-- Speed
-- ---------------------------------------------------------------------

function EconomyLogic.walkSpeed(vorrat: number): number
	local bonus = math.min(vorrat * EconomyConfig.SPEED_PER_VORRAT, EconomyConfig.MAX_SPEED_BONUS)
	return EconomyConfig.BASE_WALK_SPEED + bonus
end

function EconomyLogic.carryWalkSpeed(vorrat: number): number
	return EconomyLogic.walkSpeed(vorrat) * EconomyConfig.CARRY_SPEED_FACTOR
end

-- Umkehrung: wie viel Vorrat braucht es fuer diese WalkSpeed?
function EconomyLogic.vorratForSpeed(speed: number): number
	local bonus = speed - EconomyConfig.BASE_WALK_SPEED
	if bonus <= 0 then
		return 0
	end
	return bonus / EconomyConfig.SPEED_PER_VORRAT
end

function EconomyLogic.vorratForStage(stageIndex: number): number
	local gate = EconomyConfig.STAGE_GATES[stageIndex]
	assert(gate ~= nil, "unbekannte Stage: " .. tostring(stageIndex))
	return EconomyLogic.vorratForSpeed(gate)
end

function EconomyLogic.canEnterStage(vorrat: number, stageIndex: number): boolean
	local gate = EconomyConfig.STAGE_GATES[stageIndex]
	if gate == nil then
		return false
	end
	return EconomyLogic.walkSpeed(vorrat) >= gate
end

-- ---------------------------------------------------------------------
-- Auszahlung
--
-- Die Faktoren werden aus den Rundlaufzeiten abgeleitet, nicht gesetzt.
-- Grundgedanke: Wins/h an Pad i sind f_i * R * T / (T + t_i) * 3600.
-- Waeren alle Pads gleich gut, gaelte f_i proportional zu (T + t_i) -
-- dann entscheidet nur noch das Risiko. Genau das will das Design, also
-- nehmen wir diese Gleichstellung und legen pro Stage einen kleinen
-- Bonus (DISTANCE_PREMIUM) drauf, damit der Umweg sich lohnt, aber
-- nicht dominiert.
-- ---------------------------------------------------------------------

function EconomyLogic.payoutFactors(): { number }
	local runs = EconomyConfig.STAGE_RUN_SECONDS
	local hold = EconomyConfig.REFERENCE_HOLD_SECONDS
	local base = EconomyConfig.BASE_PAYOUT_FACTOR
	local premium = EconomyConfig.DISTANCE_PREMIUM

	local factors = {}
	for i = 1, #runs do
		local equalised = (hold + runs[i]) / (hold + runs[1])
		factors[i] = base * equalised * premium ^ (i - 1)
	end
	return factors
end

function EconomyLogic.payout(vorrat: number, stageIndex: number): number
	local factor = EconomyLogic.payoutFactors()[stageIndex]
	assert(factor ~= nil, "unbekannte Stage: " .. tostring(stageIndex))
	return math.floor(vorrat * factor)
end

-- Wins pro Stunde bei Produktionsrate `rate`, wenn alle `holdSeconds`
-- an Pad `stageIndex` ausgezahlt wird. Das ist die Formel aus Abschnitt 2
-- der Bewertung - sie steigt streng monoton in holdSeconds und laeuft in
-- eine Asymptote, hat also KEIN Optimum bei 10 Minuten.
function EconomyLogic.winsPerHour(rate: number, holdSeconds: number, stageIndex: number): number
	local run = EconomyConfig.STAGE_RUN_SECONDS[stageIndex]
	local factor = EconomyLogic.payoutFactors()[stageIndex]
	assert(run ~= nil and factor ~= nil, "unbekannte Stage: " .. tostring(stageIndex))
	return factor * rate * holdSeconds / (holdSeconds + run) * 3600
end

-- ---------------------------------------------------------------------
-- Tasten
-- ---------------------------------------------------------------------

function EconomyLogic.rarity(name: string)
	local r = EconomyConfig.RARITIES[name]
	assert(r ~= nil, "unbekannte Seltenheit: " .. tostring(name))
	return r
end

-- Wie lange braucht eine Taste, bis sie sich bezahlt gemacht hat?
-- Gerechnet an Stage 1, weil das der Pad ist, den ein neuer Spieler nimmt.
function EconomyLogic.paybackSeconds(name: string): number
	local r = EconomyLogic.rarity(name)
	local winsPerSecond = EconomyLogic.payoutFactors()[1] * r.vorratPerSecond
	return r.price / winsPerSecond
end

-- Preis pro Produktionseinheit. Steigt bewusst mit der Seltenheit.
function EconomyLogic.pricePerRate(name: string): number
	local r = EconomyLogic.rarity(name)
	return r.price / r.vorratPerSecond
end

-- Preis fuer den naechsten Steckplatz. `owned` = aktuelle Slot-Zahl.
function EconomyLogic.slotPrice(owned: number): number?
	if owned >= EconomyConfig.MAX_KEY_SLOTS then
		return nil
	end
	local steps = owned - EconomyConfig.START_KEY_SLOTS
	if steps < 0 then
		steps = 0
	end
	return math.floor(EconomyConfig.SLOT_PRICE_BASE * EconomyConfig.SLOT_PRICE_GROWTH ^ steps)
end

-- ---------------------------------------------------------------------
-- Diebstahl
-- ---------------------------------------------------------------------

-- Wie viel Vorrat wandert beim Klau mit? Rest verfaellt (nicht an das
-- Opfer zurueck - sonst waere Klauen fuer das Opfer folgenlos).
function EconomyLogic.stealTransfer(keyVorrat: number): number
	local share = keyVorrat * EconomyConfig.STEAL_VORRAT_SHARE
	return math.floor(math.min(share, EconomyConfig.STEAL_VORRAT_CAP))
end

-- Plot-Vorrat ist die Summe der Tastenvorraete - eine einzige Quelle,
-- kein zweiter Zaehler daneben.
function EconomyLogic.plotVorrat(keyVorrats: { number }): number
	local sum = 0
	for _, v in keyVorrats do
		sum += v
	end
	return sum
end

function EconomyLogic.plotRate(keyRarities: { string }): number
	local rate = 0
	for _, name in keyRarities do
		rate += EconomyLogic.rarity(name).vorratPerSecond
	end
	return rate
end

-- ---------------------------------------------------------------------
-- Schild
--
-- Muss mindestens einen kompletten Rundlauf zum weitesten Pad abdecken,
-- sonst schuetzt es genau die Situation nicht, fuer die es da ist.
-- ---------------------------------------------------------------------

function EconomyLogic.shieldWindow(): (number, number)
	local longest = 0
	for _, t in EconomyConfig.STAGE_RUN_SECONDS do
		longest = math.max(longest, t)
	end
	local duration = math.ceil(longest / 10) * 10 -- auf 10 s aufgerundet
	return duration, duration * EconomyConfig.SHIELD_COOLDOWN_RATIO
end

return EconomyLogic
