--!strict
-- Misst, wie lange ein Rundlauf Plot -> Pad -> Plot wirklich dauert.
--
-- Die Bewertung: "Miss zuerst, wie lange Stage 1 und Stage 3 hin und zurueck
-- wirklich dauern, und setz die Faktoren dann knapp unter dieses Verhaeltnis."
-- STAGE_RUN_SECONDS ist der einzige geschaetzte Wert im Balancing - alle
-- Auszahlungsfaktoren und die Schilddauer haengen daran. Statt Stoppuhr
-- misst der Server selbst und schreibt das Ergebnis ins Output-Fenster.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local EconomyConfig = require(Shared.Config.EconomyConfig)
local PlotService = require(script.Parent.PlotService)

local RunTimerService = {}

local CHECK_INTERVAL = 0.5
local REPORT_EVERY = 3 -- nach so vielen Laeufen je Stage einmal berichten

type Run = { away: boolean, leftAt: number, stage: number?, cashOuts: number }

local runs: { [number]: Run } = {}
local samples: { [number]: { number } } = {} -- stageIndex -> Rundlaufzeiten

-- Wird von CourseService nach einer erfolgreichen Auszahlung gerufen.
function RunTimerService.markCashOut(player: Player, stageIndex: number)
	local run = runs[player.UserId]
	if run and run.away then
		run.stage = stageIndex
		run.cashOuts += 1
	end
end

function RunTimerService.average(stageIndex: number): (number?, number)
	local list = samples[stageIndex]
	if not list or #list == 0 then
		return nil, 0
	end
	local sum = 0
	for _, value in list do
		sum += value
	end
	return sum / #list, #list
end

-- Gibt die gemessenen Zeiten als fertige Config-Zeile aus, damit sie ohne
-- Nachdenken in EconomyConfig.STAGE_RUN_SECONDS uebernommen werden kann.
function RunTimerService.report(): string
	local parts = {}
	for stageIndex = 1, #EconomyConfig.STAGE_RUN_SECONDS do
		local average, count = RunTimerService.average(stageIndex)
		if average then
			table.insert(parts, ("%d (%d Laeufe)"):format(math.floor(average + 0.5), count))
		else
			table.insert(parts, "? (0 Laeufe)")
		end
	end
	return "STAGE_RUN_SECONDS = { " .. table.concat(parts, ", ") .. " }"
end

local function record(userId: number, stageIndex: number, seconds: number)
	samples[stageIndex] = samples[stageIndex] or {}
	table.insert(samples[stageIndex], seconds)
	local list = samples[stageIndex]
	if #list % REPORT_EVERY == 0 then
		local average = RunTimerService.average(stageIndex)
		print(("[KEYCAP] Messung Stage %d: %.1fs dieser Lauf, Schnitt %.1fs aus %d Laeufen"):format(
			stageIndex,
			seconds,
			average or seconds,
			#list
		))
		print("[KEYCAP] " .. RunTimerService.report())
	end
end

function RunTimerService.start()
	local accumulator = 0

	RunService.Heartbeat:Connect(function(deltaTime)
		accumulator += deltaTime
		if accumulator < CHECK_INTERVAL then
			return
		end
		accumulator = 0
		local now = os.clock()

		for _, player in Players:GetPlayers() do
			local home = PlotService.isOwnerHome(player.UserId)
			local run = runs[player.UserId]

			if not run then
				runs[player.UserId] = { away = false, leftAt = now, stage = nil, cashOuts = 0 }
				continue
			end

			if home and run.away then
				-- Nur zaehlen, wenn unterwegs GENAU EINMAL ausgezahlt wurde.
				-- Wer erst an Stage 1 und dann an Stage 3 kassiert, liefert
				-- fuer beide eine zu lange Zeit - so eine Runde ist als
				-- Messwert unbrauchbar und wird verworfen.
				if run.stage and run.cashOuts == 1 then
					record(player.UserId, run.stage, now - run.leftAt)
				end
				run.away = false
				run.stage = nil
				run.cashOuts = 0
			elseif not home and not run.away then
				run.away = true
				run.leftAt = now
				run.stage = nil
				run.cashOuts = 0
			end
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		runs[player.UserId] = nil
	end)

	print("[KEYCAP] RunTimerService misst Rundlaufzeiten")
end

return RunTimerService
