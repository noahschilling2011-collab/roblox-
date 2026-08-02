-- ServerScriptService/Systems/Minigames/CodeCrack.luau
--!strict
-- GHOSTNET :: Zugangscode knacken (Mastermind).
--
-- WAS DER SPIELER TUT
--   Er raet eine Ziffernfolge. Nach jedem Versuch bekommt er zurueck, wie
--   viele Stellen exakt stimmen und wie viele Ziffern zwar vorkommen, aber
--   an der falschen Stelle stehen. Mehr nicht - daraus muss er schliessen.
--
-- WARUM DAS NEBEN NODE-BREACH STEHT
--   Node-Breach ist raeumlich und schnell: man sieht ein Gitter und zieht
--   einen Pfad. CodeCrack ist das Gegenteil - langsam, rein logisch, ohne
--   Bewegung. Zwei Raetsel, die sich gleich anfuehlen, waeren ein Raetsel.
--
-- DIE SCHNITTSTELLE IST BINDEND
--   Generate(difficulty, rng) -> publicState, serverState
--   Input(serverState, payload) -> InputResult
--   Label() -> string
--   publicState enthaelt NIEMALS die Loesung. Hier heisst das konkret:
--   der Code selbst bleibt im serverState, der Client bekommt nur die
--   Laenge, den Ziffernbereich und seine eigene Rateliste zurueck.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Types = require(ReplicatedStorage.Shared.Types)

type InputResult = Types.InputResult

local CodeCrack = {}

local C = Config.CodeCrack

export type State = {
	Code: { number }, -- die Loesung. Verlaesst den Server nie.
	Length: number,
	Digits: number, -- Ziffern 1..Digits
	Guesses: number,
	MaxGuesses: number,
}

function CodeCrack.Label(): string
	return "ZUGANGSCODE"
end

--==========================================================================
-- Schwierigkeit
--
-- Zwei Regler: wie lang der Code ist und aus wie vielen Ziffern er besteht.
-- Beide gleichzeitig hochzudrehen macht das Raetsel sehr schnell unfair -
-- deshalb waechst die Laenge zuerst, der Ziffernbereich langsamer.
--==========================================================================

local function tierFor(difficulty: number): (number, number, number)
	for _, tier in C.Tiers do
		if difficulty <= tier.UpTo then
			return tier.Length, tier.Digits, tier.Guesses
		end
	end
	local last = C.Tiers[#C.Tiers]
	return last.Length, last.Digits, last.Guesses
end

--==========================================================================

function CodeCrack.Generate(difficulty: number, rng: Random): ({ [string]: any }, State)
	local length, digits, guesses = tierFor(difficulty)

	local code: { number } = {}
	for _ = 1, length do
		table.insert(code, rng:NextInteger(1, digits))
	end

	local state: State = {
		Code = code,
		Length = length,
		Digits = digits,
		Guesses = 0,
		MaxGuesses = guesses,
	}

	-- Alles, was der Client wissen darf. Der Code ist NICHT dabei.
	local public = {
		Kind = "CodeCrack",
		Length = length,
		Digits = digits,
		MaxGuesses = guesses,
		History = {}, -- fuellt sich mit jedem Versuch
	}

	return public, state
end

--==========================================================================
-- Eingabe
--==========================================================================

local function result(ok: boolean, reason: string, costs: boolean, solved: boolean, feedback: { [string]: any }): InputResult
	return { Ok = ok, Reason = reason, CostsAttempt = costs, Solved = solved, Feedback = feedback }
end

-- Wie viele Stellen sitzen, wie viele Ziffern kommen vor. Klassische
-- Mastermind-Wertung: erst die exakten Treffer rausnehmen, dann den Rest
-- ueber Haeufigkeiten zaehlen. Ohne das doppelte Rausnehmen wuerde eine
-- doppelte Ziffer zweimal gezaehlt und die Rueckmeldung waere gelogen.
local function score(code: { number }, guess: { number }): (number, number)
	local exact = 0
	local codeCounts: { [number]: number } = {}
	local guessCounts: { [number]: number } = {}

	for index = 1, #code do
		if guess[index] == code[index] then
			exact += 1
		else
			codeCounts[code[index]] = (codeCounts[code[index]] or 0) + 1
			guessCounts[guess[index]] = (guessCounts[guess[index]] or 0) + 1
		end
	end

	local partial = 0
	for digit, count in guessCounts do
		partial += math.min(count, codeCounts[digit] or 0)
	end

	return exact, partial
end

function CodeCrack.Input(state: State, payload: any): InputResult
	if typeof(payload) ~= "table" then
		return result(false, "BAD_PAYLOAD", false, false, {})
	end

	local guess = (payload :: any).Guess
	if typeof(guess) ~= "table" then
		return result(false, "BAD_PAYLOAD", false, false, {})
	end

	-- Jede Stelle einzeln pruefen. Ein Client, der eine 0 oder eine 99
	-- schickt, darf die Wertung nicht durcheinanderbringen.
	if #guess ~= state.Length then
		return result(false, "WRONG_LENGTH", false, false, { Expected = state.Length })
	end
	local clean: { number } = {}
	for index = 1, state.Length do
		local digit = guess[index]
		if typeof(digit) ~= "number" or digit ~= digit or digit % 1 ~= 0 then
			return result(false, "BAD_PAYLOAD", false, false, {})
		end
		if digit < 1 or digit > state.Digits then
			return result(false, "BAD_DIGIT", false, false, { Digits = state.Digits })
		end
		clean[index] = digit
	end

	state.Guesses += 1
	local exact, partial = score(state.Code, clean)

	if exact == state.Length then
		return result(true, "SOLVED", false, true, {
			Guess = clean,
			Exact = exact,
			Partial = partial,
			GuessesUsed = state.Guesses,
		})
	end

	-- Versuche sind aufgebraucht: der HackService zaehlt einen Fehlversuch
	-- und beendet die Session ueber seine normale Kette.
	if state.Guesses >= state.MaxGuesses then
		return result(false, "OUT_OF_GUESSES", true, false, {
			Guess = clean,
			Exact = exact,
			Partial = partial,
			GuessesLeft = 0,
		})
	end

	-- Ein Fehlversuch kostet NICHT sofort einen Rig-Versuch: das Raten ist
	-- der Kern des Raetsels. Erst wenn die Rateliste leer ist, wird es teuer.
	return result(true, "FEEDBACK", false, false, {
		Guess = clean,
		Exact = exact,
		Partial = partial,
		GuessesLeft = state.MaxGuesses - state.Guesses,
	})
end

return CodeCrack
