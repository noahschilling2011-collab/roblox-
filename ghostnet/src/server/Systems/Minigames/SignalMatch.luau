-- ServerScriptService/Systems/Minigames/SignalMatch.luau
--!strict
-- GHOSTNET :: Signal angleichen.
--
-- WAS DER SPIELER TUT
--   Auf dem Terminal liegen zwei Wellen uebereinander: die Zielwelle und
--   die eigene. Er stellt drei Regler ein - Frequenz, Amplitude, Phase -
--   bis seine Welle die Zielwelle trifft. Trifft sie nahe genug, ist das
--   Signal uebernommen.
--
-- WARUM DAS NEBEN DEN ANDEREN BEIDEN STEHT
--   Node-Breach ist raeumlich, CodeCrack ist logisch. SignalMatch ist
--   feinmotorisch: man schiebt, sieht sofort, ob es besser wird, und
--   korrigiert. Drei Raetsel, die drei verschiedene Sachen von einem
--   verlangen.
--
-- DIE SCHNITTSTELLE IST BINDEND
--   Generate(difficulty, rng) -> publicState, serverState
--   Input(serverState, payload) -> InputResult
--   Label() -> string
--   publicState enthaelt NIEMALS die Loesung. Der Client bekommt die
--   Zielwelle als ABGETASTETE PUNKTE zum Zeichnen - aus denen liesse sich
--   die Loesung theoretisch zurueckrechnen, praktisch ist das aber genau
--   die Aufgabe. Die Parameter selbst bleiben auf dem Server, und geprueft
--   wird ausschliesslich dort.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Types = require(ReplicatedStorage.Shared.Types)

type InputResult = Types.InputResult

local SignalMatch = {}

local S = Config.SignalMatch

export type State = {
	Frequency: number,
	Amplitude: number,
	Phase: number,
	Tolerance: number, -- wie nah man dran sein muss
	Attempts: number,
	MaxAttempts: number,
}

function SignalMatch.Label(): string
	return "SIGNALABGLEICH"
end

--==========================================================================

local function tierFor(difficulty: number): (number, number)
	for _, tier in S.Tiers do
		if difficulty <= tier.UpTo then
			return tier.Tolerance, tier.Attempts
		end
	end
	local last = S.Tiers[#S.Tiers]
	return last.Tolerance, last.Attempts
end

-- Die Welle an einer Stelle. Server und Client rechnen dieselbe Formel,
-- damit die gezeichnete Kurve zur Pruefung passt.
local function sample(frequency: number, amplitude: number, phase: number, t: number): number
	return amplitude * math.sin(frequency * t * math.pi * 2 + phase)
end

--==========================================================================

function SignalMatch.Generate(difficulty: number, rng: Random): ({ [string]: any }, State)
	local tolerance, attempts = tierFor(difficulty)

	-- Auf das Raster runden, auf dem auch der Regler laeuft. Sonst gibt es
	-- Ziele, die mit den erlaubten Schritten gar nicht erreichbar sind -
	-- das ist der haeufigste Weg, so ein Raetsel unloesbar zu machen.
	local function snap(value: number, step: number): number
		return math.round(value / step) * step
	end

	local frequency = snap(rng:NextNumber(S.FrequencyMin, S.FrequencyMax), S.FrequencyStep)
	local amplitude = snap(rng:NextNumber(S.AmplitudeMin, S.AmplitudeMax), S.AmplitudeStep)
	local phase = snap(rng:NextNumber(0, math.pi * 2), S.PhaseStep)

	local state: State = {
		Frequency = frequency,
		Amplitude = amplitude,
		Phase = phase,
		Tolerance = tolerance,
		Attempts = 0,
		MaxAttempts = attempts,
	}

	-- Die Zielkurve als Punkte. Der Client zeichnet sie, mehr braucht er
	-- nicht - und die Parameter selbst bekommt er nicht.
	local points: { number } = {}
	for index = 0, S.Samples - 1 do
		local t = index / (S.Samples - 1)
		table.insert(points, sample(frequency, amplitude, phase, t))
	end

	local public = {
		Kind = "SignalMatch",
		Target = points,
		Samples = S.Samples,
		MaxAttempts = attempts,
		-- Grenzen und Schrittweiten der Regler, damit der Client dieselben
		-- Werte anbietet, die der Server akzeptiert.
		FrequencyMin = S.FrequencyMin,
		FrequencyMax = S.FrequencyMax,
		FrequencyStep = S.FrequencyStep,
		AmplitudeMin = S.AmplitudeMin,
		AmplitudeMax = S.AmplitudeMax,
		AmplitudeStep = S.AmplitudeStep,
		PhaseStep = S.PhaseStep,
	}

	return public, state
end

--==========================================================================
-- Eingabe
--==========================================================================

local function result(ok: boolean, reason: string, costs: boolean, solved: boolean, feedback: { [string]: any }): InputResult
	return { Ok = ok, Reason = reason, CostsAttempt = costs, Solved = solved, Feedback = feedback }
end

function SignalMatch.Input(state: State, payload: any): InputResult
	if typeof(payload) ~= "table" then
		return result(false, "BAD_PAYLOAD", false, false, {})
	end

	local frequency = (payload :: any).Frequency
	local amplitude = (payload :: any).Amplitude
	local phase = (payload :: any).Phase

	-- Jeden Wert EINZELN pruefen. Eine Tabelle { frequency, amplitude, phase }
	-- durchzugehen sieht kuerzer aus, ist aber falsch: sind alle drei nil,
	-- ist die Tabelle leer, die Schleife laeuft nie, und nil landet
	-- ungeprueft in math.clamp. Genau das hat der Testlauf gefunden.
	local function bad(value: any): boolean
		return typeof(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge
	end
	if bad(frequency) or bad(amplitude) or bad(phase) then
		return result(false, "BAD_PAYLOAD", false, false, {})
	end

	-- Werte in die erlaubten Grenzen zwingen. Ein Client, der eine Amplitude
	-- von 10000 schickt, soll damit nichts erreichen - weder einen Treffer
	-- noch einen Fehler im Vergleich.
	frequency = math.clamp(frequency, S.FrequencyMin, S.FrequencyMax)
	amplitude = math.clamp(amplitude, S.AmplitudeMin, S.AmplitudeMax)
	phase = phase % (math.pi * 2)

	state.Attempts += 1

	-- Mittlerer Abstand ueber die ganze Kurve. Ein einzelner Punkt koennte
	-- zufaellig treffen; die ganze Welle nicht.
	local total = 0
	for index = 0, S.Samples - 1 do
		local t = index / (S.Samples - 1)
		local mine = sample(frequency, amplitude, phase, t)
		local theirs = sample(state.Frequency, state.Amplitude, state.Phase, t)
		total += math.abs(mine - theirs)
	end
	local error_ = total / S.Samples

	if error_ <= state.Tolerance then
		return result(true, "SOLVED", false, true, {
			Error = error_,
			AttemptsUsed = state.Attempts,
		})
	end

	if state.Attempts >= state.MaxAttempts then
		return result(false, "OUT_OF_TRIES", true, false, { Error = error_, TriesLeft = 0 })
	end

	-- Rueckmeldung ohne die Loesung: nur "waermer" oder "kaelter". Genau das
	-- braucht man zum Nachregeln, und mehr verraet nichts.
	return result(true, "FEEDBACK", false, false, {
		Error = error_,
		-- 0 = weit weg, 1 = fast getroffen. Der Client macht daraus einen
		-- Balken; eine nackte Fehlerzahl sagt niemandem etwas.
		Closeness = math.clamp(1 - error_ / math.max(S.MaxError, 0.001), 0, 1),
		TriesLeft = state.MaxAttempts - state.Attempts,
	})
end

return SignalMatch
