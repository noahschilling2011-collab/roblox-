// Testlauf fuer KEYCAP RUSH: laedt die echten Shared-Module in eine echte
// Luau-VM (luau-web/WASM) und prueft die Oekonomie - ohne Roblox Studio.
import { LuauState } from "luau-web";
import { readFileSync } from "fs";
import { execSync } from "child_process";

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
  ["WorldConfig", "src/shared/Config/WorldConfig.luau"],
  ["RateLimit", "src/shared/RateLimit.luau"],
  ["TutorialConfig", "src/shared/Config/TutorialConfig.luau"],
  ["Theme", "src/shared/Theme.luau"],
  ["WorldLayout", "src/shared/WorldLayout.luau"],
];

// Stubs fuer die Roblox-Globals, die die Shared-Module anfassen.
let body = `
local Vector3 = { new = function(x, y, z) return { X = x or 0, Y = y or 0, Z = z or 0 } end }
local Color3 = {
	fromRGB = function(r, g, b) return { R = r / 255, G = g / 255, B = b / 255, kind = "Color3" } end,
	new = function(r, g, b) return { R = r, G = g, B = b, kind = "Color3" } end,
}
local UDim = { new = function(scale, offset) return { Scale = scale, Offset = offset } end }
local Enum = setmetatable({}, { __index = function(_, class)
	return setmetatable({}, { __index = function(_, item) return class .. "." .. item end })
end })
local __deps = {}
`;
for (const [name, path] of modules) {
  body += `\n__deps["${name}"] = (function()\n${loadModule(path)}\nend)()\n`;
}

const tests = `
local Config = __deps["EconomyConfig"]
local Logic = __deps["EconomyLogic"]
local World = __deps["WorldConfig"]
local RateLimit = __deps["RateLimit"]
local Tutorial = __deps["TutorialConfig"]
local Theme = __deps["Theme"]
local Layout = __deps["WorldLayout"]

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

-- 7) Karte: die Bauzahlen muessen zueinander passen.
test("Plots ueberlappen sich nicht", function()
	expect(World.PLOT_SPACING > World.PLOT_SIZE.X, "Plotabstand kleiner als Plotbreite")
end)

test("Alle Steckplaetze passen auf den Plot", function()
	local rows = math.ceil(Config.MAX_KEY_SLOTS / World.SLOT_COLUMNS)
	local breite = (World.SLOT_COLUMNS - 1) * World.SLOT_SPACING + World.KEY_SIZE.X
	local tiefe = (rows - 1) * World.SLOT_SPACING + World.KEY_SIZE.Z
	expect(breite <= World.PLOT_SIZE.X, "Tasten stehen seitlich ueber: " .. breite)
	expect(tiefe <= World.PLOT_SIZE.Z, "Tasten stehen hinten ueber: " .. tiefe)
end)

test("Zuhause-Radius bleibt auf dem eigenen Plot", function()
	expect(World.PRESENCE_RADIUS < World.PLOT_SPACING, "Zuhause-Radius reicht zum Nachbarn")
end)

test("Jedes Tor steht vor seinem Pad, Pads werden weiter", function()
	local vorher = 0
	for i = 1, #World.STAGE_PAD_POSITIONS do
		local gate = World.STAGE_GATE_POSITIONS[i]
		local pad = World.STAGE_PAD_POSITIONS[i]
		expect(gate ~= nil, "Tor " .. i .. " fehlt")
		-- Der Parcours laeuft nach -Z, das Tor muss also naeher an den Plots sein.
		expect(gate.Z > pad.Z, "Tor " .. i .. " steht hinter seinem Pad")
		local entfernung = -pad.Z
		expect(entfernung > vorher, "Pad " .. i .. " ist nicht weiter weg als das vorige")
		vorher = entfernung
	end
end)

test("Es gibt fuer jede Stage genau ein Tor und ein Pad", function()
	expect(#World.STAGE_GATE_POSITIONS == #Config.STAGE_GATES, "Torzahl passt nicht zu den Gates")
	expect(#World.STAGE_PAD_POSITIONS == #Config.STAGE_GATES, "Padzahl passt nicht zu den Gates")
	expect(#Config.STAGE_RUN_SECONDS == #Config.STAGE_GATES, "Laufzeiten fehlen fuer eine Stage")
end)

test("Plotzahl reicht fuer die Servergroesse", function()
	expect(World.PLOT_COUNT >= 8, "zu wenige Plots fuer einen vollen Server")
end)

-- 8) Rate-Limit am Server-Eingang.
test("Rate-Limit laesst einen Burst durch und blockt danach", function()
	local erlaubt = 0
	for _ = 1, 20 do
		if RateLimit.allow(4242, "test", 6) then
			erlaubt += 1
		end
	end
	expect(erlaubt >= 5 and erlaubt <= 7, "Burst falsch bemessen: " .. erlaubt)
end)

test("Rate-Limit trennt Spieler und Kanaele", function()
	for _ = 1, 20 do
		RateLimit.allow(1, "a", 3)
	end
	expect(RateLimit.allow(2, "a", 3), "anderer Spieler wird mitgeblockt")
	expect(RateLimit.allow(1, "b", 3), "anderer Kanal wird mitgeblockt")
end)

test("Rate-Limit vergisst einen Spieler beim Verlassen", function()
	for _ = 1, 20 do
		RateLimit.allow(777, "c", 2)
	end
	expect(not RateLimit.allow(777, "c", 2), "Spieler nicht geblockt")
	RateLimit.forget(777)
	expect(RateLimit.allow(777, "c", 2), "Eimer nach forget nicht zurueckgesetzt")
end)

-- 9) NPC-Plots: fuellen den leeren Server, ohne ihn zu ersetzen.
test("NPC-Plots lassen genug Platz fuer echte Spieler", function()
	expect(World.NPC_PLOT_COUNT < World.PLOT_COUNT, "NPC-Plots belegen alles")
	local frei = World.PLOT_COUNT - World.NPC_PLOT_COUNT
	expect(frei >= 8, "nur " .. frei .. " Plots fuer Spieler - Servergroesse 8-12 passt nicht")
end)

test("Jeder NPC-Plot hat einen Namen", function()
	for slot = 1, World.NPC_PLOT_COUNT do
		expect(World.NPC_NAMES[slot] ~= nil, "Name fehlt fuer NPC-Plot " .. slot)
	end
end)

test("NPC-Tastenliste passt zur Tastenzahl und kennt nur echte Seltenheiten", function()
	expect(#Config.NPC_RARITIES == Config.NPC_KEY_COUNT, "NPC_RARITIES passt nicht zu NPC_KEY_COUNT")
	for _, name in Config.NPC_RARITIES do
		expect(Config.RARITIES[name] ~= nil, "unbekannte NPC-Seltenheit: " .. name)
	end
end)

test("NPC-Tasten sind bewusst schwach", function()
	-- Sie sollen den leeren Server ueberbruecken, nicht die beste Quelle sein.
	local staerkste = 0
	for _, name in Config.NPC_RARITIES do
		staerkste = math.max(staerkste, Logic.rarity(name).vorratPerSecond)
	end
	local bestesSpielerKey = Logic.rarity(Config.RARITY_ORDER[#Config.RARITY_ORDER]).vorratPerSecond
	expect(staerkste <= bestesSpielerKey / 10, "NPC-Tasten zu stark: " .. staerkste)
end)

test("Ein NPC-Klau lohnt sich, macht aber nicht reich", function()
	local mitgenommen = Logic.stealTransfer(Config.NPC_VORRAT_CAP)
	local wins = Logic.payout(mitgenommen, 1)
	expect(wins >= Logic.rarity("Common").price, "NPC-Klau bringt weniger als eine Common-Taste: " .. wins)
	expect(wins < Logic.rarity("Rare").price, "NPC-Klau finanziert zu viel: " .. wins)
end)

test("NPC-Abklingzeit ist kuerzer als bei Spielern, aber keine Dauerquelle", function()
	expect(Config.NPC_PAIR_COOLDOWN_SECONDS < Config.STEAL_PAIR_COOLDOWN_SECONDS, "NPC-Cooldown nicht kuerzer")
	expect(Config.NPC_PAIR_COOLDOWN_SECONDS >= 30, "NPC-Plots sind eine Dauerquelle")
	expect(Config.NPC_RESPAWN_SECONDS > 0, "NPC-Tasten fuellen sich sofort wieder")
end)

-- 10) Part-Budget.
test("Die Karte bleibt im Part-Budget - auch im schlimmsten Fall", function()
	local spielerPlots = World.PLOT_COUNT - World.NPC_PLOT_COUNT
	local parts = 0
	parts += World.PLOT_COUNT * 3 -- Base + Deck + Sign je Plot
	parts += World.PLOT_COUNT * Config.MAX_KEY_SLOTS -- Steckplatz-Mulden, immer gebaut
	parts += spielerPlots * Config.MAX_KEY_SLOTS -- alle Steckplaetze voll
	parts += World.NPC_PLOT_COUNT * Config.NPC_KEY_COUNT
	parts += #World.STAGE_GATE_POSITIONS + #World.STAGE_PAD_POSITIONS * 2 -- Pad + Podest
	parts += 2 -- Promenade und Weg
	parts += World.PLOT_COUNT -- jeder Spieler traegt gleichzeitig Beute
	expect(parts <= World.PART_BUDGET, "Part-Budget gerissen: " .. parts .. " von " .. World.PART_BUDGET)
end)

test("Klau-Prompts bleiben zaehlbar", function()
	-- Auf dem Handy ist die Zahl gleichzeitiger ProximityPrompts oft das
	-- engere Limit als die Part-Zahl. UNGEPRUEFT als Zahl - hier nur eine
	-- Schranke, damit ein Zuwachs auffaellt.
	local spielerPlots = World.PLOT_COUNT - World.NPC_PLOT_COUNT
	local prompts = spielerPlots * Config.MAX_KEY_SLOTS
		+ World.NPC_PLOT_COUNT * Config.NPC_KEY_COUNT
		+ #World.STAGE_PAD_POSITIONS
	expect(prompts <= 300, "zu viele gleichzeitige Prompts: " .. prompts)
end)

-- 11) Tragen der Beute.
test("Trage-Fenster ist kuerzer als die kuerzeste Abklingzeit", function()
	-- Sonst koennte man dauerhaft als Dieb markiert herumlaufen.
	expect(Config.CARRY_SECONDS < Config.NPC_PAIR_COOLDOWN_SECONDS, "Trage-Fenster zu lang")
	expect(Config.CARRY_SECONDS > 0, "Beute ist nie sichtbar")
end)

-- 12) Onboarding.
test("Tutorial hat Schritte, jeder mit Text und Abschluss-Ereignis", function()
	expect(#Tutorial.STEPS >= 3, "zu wenige Schritte")
	expect(#Tutorial.STEPS <= 6, "zu viele Schritte - unter einer Minute soll es gehen")
	local gesehen = {}
	for index, step in Tutorial.STEPS do
		expect(type(step.id) == "string" and step.id ~= "", "Schritt " .. index .. " ohne id")
		expect(type(step.text) == "string" and #step.text > 20, "Schritt " .. index .. " ohne brauchbaren Text")
		expect(type(step.event) == "string", "Schritt " .. index .. " ohne Ereignis")
		expect(gesehen[step.id] == nil, "doppelte Schritt-id: " .. step.id)
		gesehen[step.id] = true
	end
end)

test("Nur der erste Schritt haengt an einer Zahl, der Rest an Handlungen", function()
	expect(Tutorial.STEPS[1].event == "vorrat", "erster Schritt ist keine Wartezeit")
	expect(Tutorial.STEPS[1].requiresVorratForStage ~= nil, "erstem Schritt fehlt die Stage")
	for index = 2, #Tutorial.STEPS do
		expect(Tutorial.STEPS[index].event ~= "vorrat", "Schritt " .. index .. " wartet nur")
		expect(Tutorial.STEPS[index].requiresVorratForStage == nil, "Schritt " .. index .. " haengt an einer Zahl")
	end
end)

test("Die Ereignisse decken die drei Kernhandlungen ab", function()
	local events = {}
	for _, step in Tutorial.STEPS do
		events[step.event] = true
	end
	for _, needed in { "cashout", "buy", "steal" } do
		expect(events[needed], "Tutorial erklaert '" .. needed .. "' nicht")
	end
end)

test("Der erste Schritt verlangt eine erreichbare Stage", function()
	local stage = Tutorial.STEPS[1].requiresVorratForStage
	expect(Config.STAGE_GATES[stage] ~= nil, "unbekannte Stage im ersten Schritt: " .. tostring(stage))
	expect(stage == 1, "neuer Spieler soll nicht auf Stage " .. stage .. " warten")
end)

test("Tutorial-Belohnung reicht fuer ein paar Tasten, macht aber nicht reich", function()
	local common = Logic.rarity("Common").price
	expect(Tutorial.REWARD_WINS >= common * 3, "Belohnung zu klein: " .. Tutorial.REWARD_WINS)
	expect(Tutorial.REWARD_WINS < Logic.rarity("Rare").price, "Belohnung ueberspringt das Spiel")
end)

test("Der Abschlusstext existiert", function()
	expect(type(Tutorial.DONE_TEXT) == "string" and #Tutorial.DONE_TEXT > 20, "kein Abschlusstext")
end)

-- 13) Design-System: das Theme muss vollstaendig sein, sonst faellt ein
-- Controller im Spiel auf nil zurueck statt auf eine Farbe.
test("Jede Seltenheit hat eine Farbe im Theme", function()
	for _, name in Config.RARITY_ORDER do
		expect(Theme.RARITY_COLORS[name] ~= nil, "keine Farbe fuer " .. name)
	end
end)

test("Jeder Akzent hat eine dunklere Kante fuer den 3D-Knopf", function()
	for _, name in { "GREEN", "BLUE", "GOLD", "RED" } do
		expect(Theme[name] ~= nil, "Farbe fehlt: " .. name)
		expect(Theme[name .. "_DARK"] ~= nil, "Kantenfarbe fehlt: " .. name .. "_DARK")
	end
	-- Textfarben sind eigene Rollen, nicht dieselben Werte wie die Kanten.
	for _, name in { "GOLD", "GREEN", "RED" } do
		expect(Theme[name .. "_TEXT"] ~= nil, "Textfarbe fehlt: " .. name .. "_TEXT")
	end
end)

test("Abstands-Skala steigt und faengt klein an", function()
	local reihe = { Theme.SPACE.XS, Theme.SPACE.S, Theme.SPACE.M, Theme.SPACE.L, Theme.SPACE.XL, Theme.SPACE.XXL }
	local vorher = 0
	for index, wert in reihe do
		expect(type(wert) == "number", "Abstand " .. index .. " ist keine Zahl")
		expect(wert > vorher, "Abstands-Skala steigt nicht bei " .. index)
		vorher = wert
	end
	expect(Theme.SPACE.XS <= 4, "kleinster Abstand zu gross")
end)

test("Schriftgroessen steigen und bleiben lesbar", function()
	local reihe = { Theme.TEXT_SIZE.SMALL, Theme.TEXT_SIZE.BODY, Theme.TEXT_SIZE.LEAD, Theme.TEXT_SIZE.TITLE, Theme.TEXT_SIZE.HERO }
	local vorher = 0
	for index, wert in reihe do
		expect(wert > vorher, "Schriftskala steigt nicht bei " .. index)
		vorher = wert
	end
	-- Unter 14 Pixeln liest ein Kind auf dem Handy nichts mehr, und die
	-- kleinste Groesse wird zusaetzlich von SCALE_MIN heruntergerechnet.
	expect(Theme.TEXT_SIZE.SMALL * Theme.SCALE_MIN >= 11, "kleinste Schrift wird unlesbar")
end)

test("Touch-Ziele sind gross genug, auch heruntergerechnet", function()
	expect(Theme.TOUCH_MIN >= 44, "Touch-Ziel unter 44 Pixeln: " .. Theme.TOUCH_MIN)
	expect(Theme.TOUCH_MIN * Theme.SCALE_MIN >= 38, "auf dem Handy zu klein")
end)

test("UIScale verkleinert nur, es vergroessert nicht", function()
	expect(Theme.SCALE_MAX == 1, "HUD wird auf grossen Bildschirmen aufgeblasen")
	expect(Theme.SCALE_MIN < Theme.SCALE_MAX, "Skala hat keinen Spielraum")
	expect(Theme.SCALE_MIN > 0.5, "HUD wird auf dem Handy unlesbar klein")
	expect(Theme.SCALE_REFERENCE_WIDTH > 0, "keine Referenzbreite")
end)

test("Es gibt fuer jeden Steckplatz einen Tastenbuchstaben", function()
	expect(#World.KEY_LEGENDS >= Config.MAX_KEY_SLOTS,
		#World.KEY_LEGENDS .. " Buchstaben fuer " .. Config.MAX_KEY_SLOTS .. " Steckplaetze")
	local gesehen = {}
	for _, letter in World.KEY_LEGENDS do
		expect(#letter >= 1 and #letter <= 2, "Beschriftung passt nicht auf eine Taste: " .. letter)
		expect(gesehen[letter] == nil, "doppelter Buchstabe: " .. letter)
		gesehen[letter] = true
	end
end)

test("Beleuchtung ist hell und tagsueber", function()
	local licht = World.LIGHTING
	expect(licht.BRIGHTNESS >= 2, "zu dunkel: " .. licht.BRIGHTNESS)
	expect(licht.CLOCK_TIME >= 8 and licht.CLOCK_TIME <= 17, "keine Tageszeit: " .. licht.CLOCK_TIME)
	expect(licht.BLOOM_INTENSITY <= 0.6, "Bloom blendet: " .. licht.BLOOM_INTENSITY)
	expect(licht.ATMOSPHERE_DENSITY < 0.5, "Dunst zu dicht: " .. licht.ATMOSPHERE_DENSITY)
end)

-- 14) Kontrast. Nachgerechnet statt geschaetzt: relative Leuchtdichte nach
-- WCAG, jede Text-auf-Flaeche-Kombination muss 4,5:1 schaffen. Zielgruppe
-- sind Kinder auf Handys, oft draussen im Hellen.
test("Jede Schrift-auf-Flaeche-Kombination schafft 4,5:1", function()
	local function channel(value)
		if value <= 0.03928 then
			return value / 12.92
		end
		return ((value + 0.055) / 1.055) ^ 2.4
	end
	local function luminance(color)
		return 0.2126 * channel(color.R) + 0.7152 * channel(color.G) + 0.0722 * channel(color.B)
	end
	local function contrast(front, back)
		local a, b = luminance(front), luminance(back)
		if a < b then
			a, b = b, a
		end
		return (a + 0.05) / (b + 0.05)
	end

	-- Dieselbe Rechnung wie UiKit.lift.
	local function lift(color)
		local factor = 1 + Theme.GRADIENT_LIFT
		return {
			R = math.min(1, color.R * factor),
			G = math.min(1, color.G * factor),
			B = math.min(1, color.B * factor),
		}
	end

	local kombinationen = {
		{ "Text auf Panel", Theme.TEXT, Theme.PANEL },
		{ "Tinte auf Panel", Theme.INK, Theme.PANEL },
		{ "Nebentext auf Panel", Theme.TEXT_MUTED, Theme.PANEL },
		{ "Warnung auf Panel", Theme.RED_TEXT, Theme.PANEL },
		{ "Wins auf Panel", Theme.GOLD_TEXT, Theme.PANEL },
		{ "Erfolg auf Panel", Theme.GREEN_TEXT, Theme.PANEL },
		{ "Knopfschrift auf Gruen", Theme.INK, Theme.GREEN },
		{ "Knopfschrift auf Blau", Theme.INK, Theme.BLUE },
		{ "Knopfschrift auf Gold", Theme.INK, Theme.GOLD },
		{ "Knopfschrift auf Rot", Theme.INK, Theme.RED },
		{ "Knopfschrift auf Lila", Theme.INK, Theme.PURPLE },
		{ "Knopfschrift auf Panel", Theme.INK, Theme.PANEL },
		-- Der Verlauf hellt die Flaeche oben auf. Wenn die Schrift oben
		-- durchfaellt, nuetzt der Wert unten nichts.
		{ "Knopfschrift auf Gruen (Verlauf oben)", Theme.INK, lift(Theme.GREEN) },
		{ "Knopfschrift auf Blau (Verlauf oben)", Theme.INK, lift(Theme.BLUE) },
		{ "Knopfschrift auf Gold (Verlauf oben)", Theme.INK, lift(Theme.GOLD) },
		{ "Knopfschrift auf Rot (Verlauf oben)", Theme.INK, lift(Theme.RED) },
	}
	for _, name in Config.RARITY_ORDER do
		-- Eigene Schriftfarbe je Seltenheit: die Kommentare im Theme nennen
		-- konkrete Verhaeltnisse, also werden sie auch nachgerechnet.
		table.insert(kombinationen, { "Seltenheitsschrift auf " .. name, Theme.RARITY_INK[name], Theme.RARITY_COLORS[name] })
	end

	for _, eintrag in kombinationen do
		local wert = contrast(eintrag[2], eintrag[3])
		expect(wert >= 4.5, ("%s nur %.2f:1"):format(eintrag[1], wert))
	end
end)

test("Jede Knopfkante ist dunkler als ihre Flaeche", function()
	local function channel(value)
		if value <= 0.03928 then
			return value / 12.92
		end
		return ((value + 0.055) / 1.055) ^ 2.4
	end
	local function luminance(color)
		return 0.2126 * channel(color.R) + 0.7152 * channel(color.G) + 0.0722 * channel(color.B)
	end
	for _, name in { "GREEN", "BLUE", "GOLD", "RED" } do
		local hell = luminance(Theme[name])
		local dunkel = luminance(Theme[name .. "_DARK"])
		expect(dunkel < hell, name .. "_DARK ist nicht dunkler - der 3D-Effekt kippt")
	end
	expect(luminance(Theme.PANEL_EDGE) < luminance(Theme.PANEL), "PANEL_EDGE ist nicht dunkler")
	for _, name in Config.RARITY_ORDER do
		expect(luminance(Theme.RARITY_EDGE[name]) < luminance(Theme.RARITY_COLORS[name]),
			"RARITY_EDGE." .. name .. " ist nicht dunkler als die Flaeche")
	end
end)

test("Die Welt ist dunkel und ihre Kanten hellen auf", function()
	local function channel(value)
		if value <= 0.03928 then
			return value / 12.92
		end
		return ((value + 0.055) / 1.055) ^ 2.4
	end
	local function luminance(color)
		return 0.2126 * channel(color.R) + 0.7152 * channel(color.G) + 0.0722 * channel(color.B)
	end
	local W = Theme.WORLD

	-- Ein Schreibtisch bei Nacht: jede Weltflaeche muss dunkler sein als
	-- das creme HUD-Panel, sonst kippt die Grundstimmung.
	for _, name in { "MAT", "SEAM", "PLATE", "CHASSIS", "SOCKET", "PATH" } do
		expect(luminance(W[name]) < luminance(Theme.PANEL) / 8,
			name .. " ist zu hell fuer eine Nachtszene")
	end

	-- Auf hellem Grund ist die Kante dunkel, auf dunklem Grund hell.
	-- INK (0,0074) ist HELLER als die Matte (0,0073) - die HUD-Regel
	-- laesst sich hier also nicht anwenden, deshalb SEAM.
	expect(luminance(W.SEAM) > luminance(W.MAT), "Weltkante hellt nicht auf")
	expect(luminance(W.SOCKET) < luminance(W.PLATE), "Mulde ist nicht tiefer als die Platte")
	expect(luminance(W.CHASSIS) > luminance(W.PLATE), "Rahmen hebt sich nicht von der Platte ab")

	-- Die Signalfarbe muss aus jeder Weltflaeche herausspringen.
	for _, name in { "MAT", "PLATE", "PATH", "CHASSIS" } do
		local a, b = luminance(W.SIGNAL), luminance(W[name])
		if a < b then
			a, b = b, a
		end
		expect((a + 0.05) / (b + 0.05) >= 6, "Signalfarbe hebt sich zu wenig von " .. name .. " ab")
	end
end)

test("Jede Seltenheit hat Kappe, Legende, Ring, Material und Lichtreichweite", function()
	local function channel(value)
		if value <= 0.03928 then
			return value / 12.92
		end
		return ((value + 0.055) / 1.055) ^ 2.4
	end
	local function luminance(color)
		return 0.2126 * channel(color.R) + 0.7152 * channel(color.G) + 0.0722 * channel(color.B)
	end
	local letzteReichweite = -1
	for _, name in Config.RARITY_ORDER do
		expect(Theme.RARITY_COLORS[name] ~= nil, "keine Kappe fuer " .. name)
		expect(Theme.RARITY_INK[name] ~= nil, "keine Legende fuer " .. name)
		expect(Theme.RARITY_EDGE[name] ~= nil, "kein Stem-Ring fuer " .. name)
		expect(Theme.RARITY_MATERIAL[name] ~= nil, "kein Material fuer " .. name)
		local reichweite = Theme.RARITY_LIGHT_RANGE[name]
		expect(reichweite ~= nil, "keine Lichtreichweite fuer " .. name)
		expect(reichweite >= letzteReichweite, "Lichtreichweite faellt bei " .. name)
		letzteReichweite = reichweite
		expect(luminance(Theme.RARITY_EDGE[name]) < luminance(Theme.RARITY_COLORS[name]),
			"Stem-Ring von " .. name .. " ist nicht dunkler als die Kappe")
	end
	-- Genau die Stufen bekommen Licht, die sich sonst nicht von der
	-- Tastaturplatte abheben.
	expect(Theme.RARITY_LIGHT_RANGE.Common == 0, "Common leuchtet")
	expect(Theme.RARITY_LIGHT_RANGE.Rare > 0, "Rare leuchtet nicht - sie verschwindet auf der Platte")
	expect(Theme.RARITY_LIGHT_BRIGHTNESS > 0, "Lichtstaerke fehlt")
end)

test("Der Verlauf hellt auf, er verdunkelt nicht", function()
	local function channel(value)
		if value <= 0.03928 then
			return value / 12.92
		end
		return ((value + 0.055) / 1.055) ^ 2.4
	end
	local function luminance(color)
		return 0.2126 * channel(color.R) + 0.7152 * channel(color.G) + 0.0722 * channel(color.B)
	end
	expect(Theme.GRADIENT_LIFT > 0, "kein Verlauf")
	expect(Theme.GRADIENT_LIFT < 0.4, "Verlauf so stark, dass oben eine andere Farbe steht")
	for _, name in { "GREEN", "BLUE", "GOLD", "RED", "PURPLE" } do
		local basis = Theme[name]
		local oben = {
			R = math.min(1, basis.R * (1 + Theme.GRADIENT_LIFT)),
			G = math.min(1, basis.G * (1 + Theme.GRADIENT_LIFT)),
			B = math.min(1, basis.B * (1 + Theme.GRADIENT_LIFT)),
		}
		expect(luminance(oben) >= luminance(basis), name .. ": Verlauf oben nicht heller")
	end
end)

test("Umrandung ist dick genug, um zu wirken", function()
	expect(Theme.OUTLINE_THICKNESS >= 2, "Umrandung zu duenn: " .. Theme.OUTLINE_THICKNESS)
	expect(Theme.OUTLINE_THICKNESS * Theme.SCALE_MIN >= 1.5, "Umrandung verschwindet auf dem Handy")
end)

test("Chassis und Podest stehen unter ihrer Flaeche, nicht daneben", function()
	expect(World.PLOT_DECK_OVERHANG > 0, "Chassis hat keinen Ueberstand")
	expect(World.PLOT_DECK_HEIGHT > 0, "Chassis ist flach")
	-- Der Ueberstand darf die Luecke zwischen zwei Plots nicht schliessen,
	-- sonst verschmilzt die Reihe zu einer Flaeche.
	local luecke = World.PLOT_SPACING - World.PLOT_SIZE.X
	expect(World.PLOT_DECK_OVERHANG * 2 < luecke,
		"Chassis-Ueberstand " .. World.PLOT_DECK_OVERHANG * 2 .. " schliesst die Luecke von " .. luecke)
	expect(World.PAD_RING_OVERHANG > 0 and World.PAD_RING_HEIGHT > 0, "Pad-Podest fehlt")
end)

test("Steckplatz-Mulde bleibt in ihrem Raster", function()
	expect(World.SLOT_MARKER_SCALE < 1, "Mulde ist so gross wie die Taste")
	expect(World.SLOT_MARKER_SCALE > 0.5, "Mulde ist zu klein zum Erkennen")
	expect(World.SLOT_MARKER_HEIGHT < World.KEY_SIZE.Y, "Mulde ist hoeher als eine Taste")
end)

test("Die Schildtafel passt vor den Plot", function()
	expect(World.SIGN_BOARD_SIZE.X <= World.PLOT_SIZE.X, "Schild breiter als der Plot")
	local mitte = Layout.plotPosition(1)
	local schild = Layout.signPosition(mitte)
	local hinterste = 0
	for slot = 1, Config.MAX_KEY_SLOTS do
		hinterste = math.max(hinterste, Layout.slotPosition(mitte, slot).Z + World.KEY_SIZE.Z / 2)
	end
	expect(schild.Z - World.SIGN_BOARD_SIZE.Z / 2 > hinterste, "Schildtafel steht in den Tasten")
end)

test("Seltenheit ist auch ohne Farbe erkennbar", function()
	-- Farbe allein reicht auf einem billigen Display in der Sonne nicht -
	-- Rang und Tastenhoehe muessen dieselbe Information doppelt tragen.
	local letzterRang, letzteHoehe = 0, 0
	for _, name in Config.RARITY_ORDER do
		local rang = Theme.RARITY_RANK[name]
		local hoehe = Theme.KEY_CROWN[name]
		expect(rang ~= nil, "kein Rang fuer " .. name)
		expect(hoehe ~= nil, "keine Tastenhoehe fuer " .. name)
		expect(rang > letzterRang, "Rang steigt nicht bei " .. name)
		expect(hoehe > letzteHoehe, "Tastenhoehe steigt nicht bei " .. name)
		letzterRang, letzteHoehe = rang, hoehe
	end
end)

test("Jede Tastenhoehe steht buendig auf dem Plot, keine schwebt", function()
	-- Das ist die Invariante, die KEY_CROWN brechen koennte: die Taste
	-- waechst nach oben, ihre Unterkante muss auf der Plotoberflaeche
	-- bleiben. Rechnung wie in PlotService.renderKeys.
	local mitte = Layout.plotPosition(1)
	local plotOberflaeche = mitte.Y + World.PLOT_SIZE.Y / 2
	for _, name in Config.RARITY_ORDER do
		local crown = Theme.KEY_CROWN[name]
		local extra = World.KEY_SIZE.Y * (crown - 1)
		local mittelpunkt = Layout.slotPosition(mitte, 1).Y + extra / 2
		local unterkante = mittelpunkt - World.KEY_SIZE.Y * crown / 2
		expect(math.abs(unterkante - plotOberflaeche) < 0.001,
			name .. ": Unterkante " .. unterkante .. " statt " .. plotOberflaeche)
	end
end)

test("Keine Taste ragt in das Plot-Schild", function()
	-- Das Schild steht an der Vorderkante, die Tasten stehen im Raster
	-- dahinter. Hoehe allein ist also kein Problem, solange sie sich in Z
	-- nicht ueberschneiden - genau das wird hier geprueft.
	local mitte = Layout.plotPosition(1)
	local schild = Layout.signPosition(mitte)
	local schildVorderkante = schild.Z - 0.5 -- Schild ist 1 Stud tief
	local hinterste = 0
	for slot = 1, Config.MAX_KEY_SLOTS do
		hinterste = math.max(hinterste, Layout.slotPosition(mitte, slot).Z + World.KEY_SIZE.Z / 2)
	end
	expect(hinterste < schildVorderkante,
		"Taste reicht bis Z=" .. hinterste .. ", Schild beginnt bei " .. schildVorderkante)
end)

-- 15) Boden. Ohne durchgehende Flaeche faellt der Spieler ins Leere.
test("Die Promenade verbindet alle Plots", function()
	local breite = World.PLOT_COUNT * World.PLOT_SPACING
	local reihe = (World.PLOT_COUNT - 1) * World.PLOT_SPACING + World.PLOT_SIZE.X
	expect(breite >= reihe, "Promenade (" .. breite .. ") kuerzer als die Plotreihe (" .. reihe .. ")")
	expect(World.PROMENADE_DEPTH > 0, "keine Promenade")
end)

test("Der Weg ist breit genug und reicht ueber das letzte Pad hinaus", function()
	expect(World.PATH_WIDTH >= World.STAGE_PAD_SIZE.X, "Weg schmaler als ein Pad")
	expect(World.PATH_MARGIN > 0, "Weg endet genau am Pad")
end)

test("Jedes Pad und jedes Tor liegt ueber dem Weg", function()
	local halbe = World.PATH_WIDTH / 2
	for index, pad in World.STAGE_PAD_POSITIONS do
		expect(math.abs(pad.X - World.PLOT_ORIGIN.X) + World.STAGE_PAD_SIZE.X / 2 <= halbe,
			"Pad " .. index .. " haengt neben dem Weg")
	end
	for index, gate in World.STAGE_GATE_POSITIONS do
		expect(math.abs(gate.X - World.PLOT_ORIGIN.X) <= halbe, "Tor " .. index .. " steht neben dem Weg")
	end
end)

test("Alles steht auf derselben Hoehe - keine Stufen im Parcours", function()
	local hoehe = World.PLOT_ORIGIN.Y
	for index, pad in World.STAGE_PAD_POSITIONS do
		expect(pad.Y == hoehe, "Pad " .. index .. " liegt auf anderer Hoehe: " .. pad.Y)
	end
end)

-- 16) WorldLayout ist die gemeinsame Quelle fuer Server UND Build-Script.
-- Laufen die auseinander, zeigt die Studio-Datei etwas anderes als das Spiel.
test("Die Plotreihe ist mittig und gleichmaessig", function()
	local erste = Layout.plotPosition(1)
	local letzte = Layout.plotPosition(World.PLOT_COUNT)
	expect(math.abs(erste.X + letzte.X) < 0.001, "Reihe nicht mittig: " .. erste.X .. " / " .. letzte.X)
	local abstand = Layout.plotPosition(2).X - erste.X
	expect(math.abs(abstand - World.PLOT_SPACING) < 0.001, "Abstand stimmt nicht: " .. abstand)
	expect(erste.Y == World.PLOT_ORIGIN.Y, "Plot haengt auf falscher Hoehe")
end)

test("Tasten stehen auf dem Plot, nicht daneben oder darin", function()
	local mitte = Layout.plotPosition(1)
	local halbeBreite = World.PLOT_SIZE.X / 2
	local halbeTiefe = World.PLOT_SIZE.Z / 2
	for slot = 1, Config.MAX_KEY_SLOTS do
		local position = Layout.slotPosition(mitte, slot)
		local dx = math.abs(position.X - mitte.X) + World.KEY_SIZE.X / 2
		local dz = math.abs(position.Z - mitte.Z) + World.KEY_SIZE.Z / 2
		expect(dx <= halbeBreite, "Steckplatz " .. slot .. " steht seitlich ueber")
		expect(dz <= halbeTiefe, "Steckplatz " .. slot .. " steht hinten ueber")
		local erwarteteHoehe = mitte.Y + World.PLOT_SIZE.Y / 2 + World.KEY_SIZE.Y / 2
		expect(math.abs(position.Y - erwarteteHoehe) < 0.001, "Taste schwebt oder steckt im Plot")
	end
end)

test("Promenade und Weg beruehren sich luechenlos", function()
	local promenade = Layout.promenade()
	local weg = Layout.path()
	local promenadeVorderkante = promenade.position.Z + promenade.size.Z / 2
	local wegHinterkante = weg.position.Z + weg.size.Z / 2
	expect(math.abs(promenadeVorderkante - wegHinterkante) < 0.001,
		"Luecke zwischen Promenade und Weg: " .. (promenadeVorderkante - wegHinterkante))
	expect(promenade.position.Y == weg.position.Y, "Promenade und Weg auf verschiedenen Hoehen")
end)

test("Die Promenade schliesst an die Plots an", function()
	local promenade = Layout.promenade()
	local plotVorderkante = World.PLOT_ORIGIN.Z + World.PLOT_SIZE.Z / 2
	local promenadeHinterkante = promenade.position.Z - promenade.size.Z / 2
	expect(math.abs(plotVorderkante - promenadeHinterkante) < 0.001,
		"Luecke zwischen Plot und Promenade: " .. (plotVorderkante - promenadeHinterkante))
end)

table.insert(results, "")
table.insert(results, "ERGEBNIS: " .. passed .. " bestanden, " .. failed .. " fehlgeschlagen (" .. (passed + failed) .. " Tests)")
return table.concat(results, "\\n"), failed
`;

// Syntaxpruefung: jede Luau-Datei des Spiels muss im echten Luau-Compiler
// durchgehen. Faengt Tippfehler, die sonst erst in Studio auffallen.
function syntaxCheck(state) {
  const files = execSync(`find ${ROOT}/src -name '*.luau'`).toString().trim().split("\n").filter(Boolean).sort();
  const broken = [];
  for (const file of files) {
    try {
      state.loadstring(readFileSync(file, "utf8"), file.split("/").pop(), true);
    } catch (e) {
      broken.push(`${file.replace(ROOT + "/", "")} -> ${(e.message ?? e).toString().split("\n")[0]}`);
    }
  }
  return { count: files.length, broken };
}

const state = await LuauState.createAsync();
try {
  const fn = state.loadstring(body + tests, "keycap-rush-tests", true);
  const [report, failedCount] = await fn();
  console.log(report);

  const syntax = syntaxCheck(state);
  console.log("");
  if (syntax.broken.length === 0) {
    console.log(`SYNTAX: ${syntax.count} Luau-Dateien kompilieren.`);
  } else {
    for (const line of syntax.broken) console.log("FAIL | " + line);
    console.log(`SYNTAX: ${syntax.broken.length} von ${syntax.count} Dateien kaputt.`);
  }
  process.exit(failedCount > 0 || syntax.broken.length > 0 ? 1 : 0);
} catch (e) {
  console.error("HARNESS-FEHLER:", e.message ?? e);
  process.exit(2);
} finally {
  state.destroy();
}
