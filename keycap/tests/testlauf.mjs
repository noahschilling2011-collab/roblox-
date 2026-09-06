// Testlauf fuer KEYCAP RUSH: laedt die echten Shared-Module in eine echte
// Luau-VM (luau-web/WASM) und prueft die Oekonomie - ohne Roblox Studio.
import { LuauState } from "luau-web";
import { readFileSync } from "fs";

const ROOT = new URL("..", import.meta.url).pathname.replace(/\/$/, "");

function loadModule(relPath) {
  let src = readFileSync(`${ROOT}/${relPath}`, "utf8");
  src = src.replace(/^--!strict\s*$/m, "");
  src = src.replace(/^local (\w+) = require\(.+\)$/gm, 'local $1 = __deps["$1"]');
  src = src.replace(/^export type/gm, "type");
  return src;
}

const modules = [
  ["EconomyConfig", "src/shared/Config/EconomyConfig.luau"],
  ["EconomyLogic", "src/shared/EconomyLogic.luau"],
];

let body = "local __deps = {}\n";
for (const [name, path] of modules) {
  body += `\n__deps["${name}"] = (function()\n${loadModule(path)}\nend)()\n`;
}

const tests = `
local Config = __deps["EconomyConfig"]
local Logic = __deps["EconomyLogic"]

local results = {}
local passed, failed = 0, 0

local function test(name, fn)
	local ok, err = pcall(fn)
	if ok then
		passed += 1
		table.insert(results, "OK   | " .. name)
	else
		failed += 1
		table.insert(results, "FAIL | " .. name .. " -> " .. tostring(err))
	end
end

local function expect(cond, msg)
	if not cond then error(msg, 2) end
end

local function near(a, b, tol)
	return math.abs(a - b) <= tol
end

-- 1) Speed-Kurve trifft exakt die Zahlen aus der Bewertung.
test("Speed-Gates brauchen 700 / 1700 / 2950 Vorrat", function()
	expect(Logic.vorratForStage(1) == 700, "Stage 1: " .. Logic.vorratForStage(1))
	expect(Logic.vorratForStage(2) == 1700, "Stage 2: " .. Logic.vorratForStage(2))
	expect(Logic.vorratForStage(3) == 2950, "Stage 3: " .. Logic.vorratForStage(3))
end)

test("Speed-Deckel bei WalkSpeed 100, erreicht mit Vorrat 4200", function()
	expect(Logic.walkSpeed(4200) == 100, "bei 4200: " .. Logic.walkSpeed(4200))
	expect(Logic.walkSpeed(100000) == 100, "Deckel haelt nicht: " .. Logic.walkSpeed(100000))
	expect(Logic.walkSpeed(0) == 16, "Startgeschwindigkeit falsch")
end)

test("Tragen macht 40% langsamer", function()
	expect(near(Logic.carryWalkSpeed(4200), 60, 0.001), "Tragespeed: " .. Logic.carryWalkSpeed(4200))
end)

test("Gate-Pruefung stimmt mit der Speed-Kurve ueberein", function()
	expect(not Logic.canEnterStage(699, 3), "699 Vorrat kommt in Stage 3")
	expect(Logic.canEnterStage(700, 1), "700 Vorrat kommt nicht in Stage 1")
	expect(not Logic.canEnterStage(2949, 3), "2949 Vorrat kommt in Stage 3")
	expect(Logic.canEnterStage(2950, 3), "2950 Vorrat kommt nicht in Stage 3")
end)

-- 2) Die Rechnung aus Abschnitt 2 der Bewertung, mit deren eigenen Zahlen.
test("Bewertung Abschnitt 2: 90R / 150R / 174R sind korrekt nachgerechnet", function()
	local function winsPerHour(rate, hold, run, factor)
		return factor * rate * hold / (hold + run) * 3600
	end
	expect(near(winsPerHour(1, 120, 120, 0.05), 90, 0.5), "2 Min: " .. winsPerHour(1, 120, 120, 0.05))
	expect(near(winsPerHour(1, 600, 120, 0.05), 150, 0.5), "10 Min: " .. winsPerHour(1, 600, 120, 0.05))
	expect(near(winsPerHour(1, 3600, 120, 0.05), 174, 0.5), "60 Min: " .. winsPerHour(1, 3600, 120, 0.05))
end)

test("Wins/h steigt streng monoton im Halten - es gibt KEIN Optimum bei 10 Minuten", function()
	local prev = -1
	for _, hold in { 60, 120, 300, 600, 1800, 3600, 7200 } do
		local w = Logic.winsPerHour(1, hold, 3)
		expect(w > prev, "nicht monoton bei hold=" .. hold)
		prev = w
	end
	-- Asymptote: laenger halten bringt irgendwann fast nichts mehr.
	local asymptote = Logic.payoutFactors()[3] * 3600
	expect(Logic.winsPerHour(1, 3600, 3) < asymptote, "Asymptote ueberschritten")
	expect(Logic.winsPerHour(1, 3600, 3) > asymptote * 0.95, "Asymptote nicht erreicht")
end)

-- 3) Auszahlungsfaktoren: abgeleitet, nicht geraten.
test("Auszahlungsfaktoren steigen mit der Entfernung", function()
	local f = Logic.payoutFactors()
	expect(f[1] < f[2] and f[2] < f[3], "Faktoren nicht steigend")
end)

test("Stage 3 gibt keinen 5x-Vorsprung mehr, sondern 20-45%", function()
	-- Das ist die Reparatur aus der Bewertung: mit 0.01/0.025/0.05 war
	-- Stage 3 bei gleichem Vorrat 5x so viel wert und damit alternativlos.
	local hold = Config.REFERENCE_HOLD_SECONDS
	local ratio = Logic.winsPerHour(1, hold, 3) / Logic.winsPerHour(1, hold, 1)
	expect(ratio > 1.15, "Stage 3 lohnt sich gar nicht: " .. ratio)
	expect(ratio < 1.45, "Stage 3 dominiert wieder: " .. ratio)
end)

test("Stage 1 bleibt eine echte Option (>70% von Stage 3)", function()
	local hold = Config.REFERENCE_HOLD_SECONDS
	local share = Logic.winsPerHour(1, hold, 1) / Logic.winsPerHour(1, hold, 3)
	expect(share > 0.70, "Stage 1 ist tot: " .. share)
end)

test("Auszahlung schneidet auf ganze Wins ab", function()
	local p = Logic.payout(4200, 1)
	expect(p == math.floor(p), "Auszahlung nicht ganzzahlig")
	expect(Logic.payout(0, 1) == 0, "Auszahlung bei leerem Vorrat")
	expect(Logic.payout(4200, 3) > Logic.payout(4200, 1), "Stage 3 zahlt nicht mehr")
end)

-- 4) Tasten: die Zahlen, die im Konzept fehlten.
test("Jede Seltenheit hat Rate und Preis, Reihenfolge stimmt", function()
	local lastRate, lastPrice = 0, 0
	for _, name in Config.RARITY_ORDER do
		local r = Logic.rarity(name)
		expect(r.vorratPerSecond > lastRate, name .. ": Rate nicht steigend")
		expect(r.price > lastPrice, name .. ": Preis nicht steigend")
		lastRate, lastPrice = r.vorratPerSecond, r.price
	end
end)

test("Bessere Tasten kosten mehr pro Produktionseinheit - Slots sind der Engpass", function()
	local last = 0
	for _, name in Config.RARITY_ORDER do
		local ppr = Logic.pricePerRate(name)
		expect(ppr > last, name .. ": Preis pro Rate nicht steigend (" .. ppr .. ")")
		last = ppr
	end
end)

test("Amortisation liegt zwischen 3 und 25 Minuten und steigt mit der Seltenheit", function()
	local last = 0
	for _, name in Config.RARITY_ORDER do
		local pb = Logic.paybackSeconds(name)
		expect(pb > 180, name .. ": zu schnell bezahlt (" .. pb .. "s)")
		expect(pb < 1500, name .. ": zu lange bis Amortisation (" .. pb .. "s)")
		expect(pb > last, name .. ": Amortisation nicht steigend")
		last = pb
	end
end)

test("Slot-Preise steigen und enden bei MAX_KEY_SLOTS", function()
	local first = Logic.slotPrice(Config.START_KEY_SLOTS)
	local second = Logic.slotPrice(Config.START_KEY_SLOTS + 1)
	expect(first == Config.SLOT_PRICE_BASE, "erster Zusatzslot: " .. tostring(first))
	expect(second > first, "Slot-Preis steigt nicht")
	expect(Logic.slotPrice(Config.MAX_KEY_SLOTS) == nil, "Slot ueber dem Maximum kaufbar")
end)

-- 5) Diebstahl: Horten ist nicht mehr gratis.
test("Klau nimmt anteilig Vorrat mit und ist gedeckelt", function()
	expect(Logic.stealTransfer(1000) == 500, "50%-Anteil falsch: " .. Logic.stealTransfer(1000))
	expect(Logic.stealTransfer(100000) == Config.STEAL_VORRAT_CAP, "Deckel greift nicht")
	expect(Logic.stealTransfer(0) == 0, "Klau aus leerer Taste gibt Vorrat")
end)

test("Ein Klau ist ein Erfolg, aber kein Sofortsieg", function()
	-- Der maximale Klau, in Wins an Stage 1 umgerechnet, darf keinen
	-- Legendary-Kauf auf einen Schlag finanzieren.
	local maxWins = Logic.payout(Config.STEAL_VORRAT_CAP, 1)
	local legendary = Logic.rarity("Legendary").price
	expect(maxWins > 0, "Klau bringt nichts")
	expect(maxWins < legendary * 0.25, "ein Klau finanziert zu viel: " .. maxWins .. " von " .. legendary)
end)

test("Plot-Vorrat ist die Summe der Tastenvorraete", function()
	expect(Logic.plotVorrat({ 100, 250, 0, 7 }) == 357, "Summe falsch")
	expect(Logic.plotVorrat({}) == 0, "leerer Plot hat Vorrat")
end)

test("Plot-Rate ist die Summe der Tastenraten", function()
	local rate = Logic.plotRate({ "Common", "Common", "Legendary" })
	expect(rate == 102, "Rate falsch: " .. rate)
end)

test("Voller Plot aus Common-Tasten erreicht das Stage-1-Gate in unter 15 Minuten", function()
	local rate = 0
	for _ = 1, Config.START_KEY_SLOTS do
		rate += Logic.rarity("Common").vorratPerSecond
	end
	local seconds = Logic.vorratForStage(1) / rate
	expect(seconds < 900, "Stage 1 zu weit weg: " .. seconds .. "s")
end)

-- 6) Schild: deckt jetzt den Lauf ab, fuer den es da ist.
test("Schild haelt mindestens einen kompletten Stage-3-Rundlauf durch", function()
	local duration, cooldown = Logic.shieldWindow()
	local longest = 0
	for _, t in Config.STAGE_RUN_SECONDS do
		longest = math.max(longest, t)
	end
	expect(duration >= longest, "Schild (" .. duration .. "s) kuerzer als Rundlauf (" .. longest .. "s)")
	expect(cooldown > duration, "Abklingzeit kuerzer als Schilddauer")
	-- Zum Vergleich die Konzept-Zahlen 45 s / 180 s:
	expect(45 < longest, "Konzept-Schild waere doch lang genug - Annahme pruefen")
end)

test("Schild schuetzt hoechstens jeden zweiten Lauf", function()
	local duration, cooldown = Logic.shieldWindow()
	expect(duration / cooldown <= 0.5, "Schild deckt zu viel ab")
end)

table.insert(results, "")
table.insert(results, "ERGEBNIS: " .. passed .. " bestanden, " .. failed .. " fehlgeschlagen (" .. (passed + failed) .. " Tests)")
return table.concat(results, "\\n"), failed
`;

const state = await LuauState.createAsync();
try {
  const fn = state.loadstring(body + tests, "keycap-rush-tests", true);
  const [report, failedCount] = await fn();
  console.log(report);
  process.exit(failedCount > 0 ? 1 : 0);
} catch (e) {
  console.error("HARNESS-FEHLER:", e.message ?? e);
  process.exit(2);
} finally {
  state.destroy();
}
