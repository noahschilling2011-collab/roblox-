// Testlauf fuer GHOSTNET.
//
// Drei Stufen, in dieser Reihenfolge:
//   1. SYNTAX   - jede .luau-Datei wird von der echten Luau-VM uebersetzt.
//                 Das ist der "luau-compile"-Durchlauf aus der Definition of Done.
//   2. STRUKTUR - Regeln, die der Compiler nicht kennt: --!strict ueberall,
//                 keine veralteten wait()/spawn(), jede benutzte Remote ist
//                 angemeldet, jedes Rate-Limit ist konfiguriert.
//   3. LOGIK    - die echten Shared-Module laufen in der VM: Config-Formeln,
//                 Balancing-Vorgaben und das komplette Node-Breach-Minispiel.
//
// Ausfuehren:  cd ghostnet/tests && npm install && node testlauf.mjs
import { LuauState } from "luau-web";
import { readFileSync, readdirSync, statSync } from "fs";
import { join, relative } from "path";

const ROOT = new URL("..", import.meta.url).pathname.replace(/\/$/, "");
const SRC = join(ROOT, "src");

let passed = 0;
let failed = 0;
const lines = [];

function ok(name) {
  passed += 1;
  lines.push(`OK   | ${name}`);
}

function bad(name, detail) {
  failed += 1;
  lines.push(`FAIL | ${name} -> ${detail}`);
}

function check(name, condition, detail) {
  if (condition) ok(name);
  else bad(name, detail ?? "Bedingung nicht erfuellt");
}

function allLuauFiles(dir) {
  const out = [];
  for (const entry of readdirSync(dir).sort()) {
    const full = join(dir, entry);
    if (statSync(full).isDirectory()) out.push(...allLuauFiles(full));
    else if (entry.endsWith(".luau")) out.push(full);
  }
  return out;
}

const files = allLuauFiles(SRC);
const sources = new Map(files.map((f) => [f, readFileSync(f, "utf8")]));

const state = await LuauState.createAsync();

try {
  //========================================================================
  // 1. SYNTAX
  //========================================================================
  lines.push("--- 1. SYNTAX (luau-compile ueber jede Datei) ---");
  for (const file of files) {
    const short = relative(ROOT, file);
    const result = state.loadstring(sources.get(file), short, false);
    if (typeof result === "function") ok(`uebersetzt: ${short}`);
    else bad(`uebersetzt: ${short}`, String(result));
  }

  //========================================================================
  // 2. STRUKTUR
  //========================================================================
  lines.push("");
  lines.push("--- 2. STRUKTUR (Projektregeln) ---");

  for (const file of files) {
    const short = relative(ROOT, file);
    const src = sources.get(file);
    check(`--!strict in ${short}`, /^--!strict$/m.test(src), "fehlt");
  }

  // Veraltete APIs. task.wait/task.spawn/task.delay sind erlaubt, die blanken
  // Globals nicht.
  for (const file of files) {
    const short = relative(ROOT, file);
    const src = sources.get(file);
    const hits = [];
    for (const name of ["wait", "spawn", "delay"]) {
      const re = new RegExp(`(^|[^\\w.:])${name}\\s*\\(`, "g");
      if (re.test(src)) hits.push(name);
    }
    check(`keine veralteten APIs in ${short}`, hits.length === 0, `gefunden: ${hits.join(", ")}`);
  }

  // Liest einen Luau-Tabellenblock zeilenweise aus. Wichtig: nicht am ersten
  // "}" abschneiden - die Kommentare in Remotes.luau enthalten selbst welche.
  function tableBlock(src, header) {
    const all = src.split("\n");
    const start = all.findIndex((line) => line.includes(header));
    if (start < 0) return "";
    const out = [];
    for (let i = start + 1; i < all.length; i++) {
      if (/^\}/.test(all[i])) break;
      out.push(all[i]);
    }
    return out.join("\n");
  }

  // Jede benutzte Remote muss in Remotes.luau angemeldet sein.
  const remotesSrc = sources.get(join(SRC, "shared/Remotes.luau"));
  const declaredRemotes = new Set();
  for (const block of ["local EVENT_NAMES", "local FUNCTION_NAMES"]) {
    for (const m of tableBlock(remotesSrc, block).matchAll(/^\s*"(\w+)"/gm)) declaredRemotes.add(m[1]);
  }

  const usedRemotes = new Set();
  for (const [file, src] of sources) {
    if (file.endsWith("Remotes.luau")) continue;
    for (const m of src.matchAll(/\bRemotes\.(\w+)/g)) usedRemotes.add(m[1]);
  }
  for (const name of usedRemotes) {
    check(`Remote angemeldet: ${name}`, declaredRemotes.has(name), "fehlt in Remotes.luau");
  }

  // Jeder RateLimiter.Check-Schluessel braucht einen Eintrag in Config.RateLimits.
  const configSrc = sources.get(join(SRC, "shared/Config.luau"));
  const limitSection = tableBlock(configSrc, "Config.RateLimits = {");
  const declaredLimits = new Set([...limitSection.matchAll(/(\w+)\s*=\s*\{\s*Rate/g)].map((m) => m[1]));
  const usedLimits = new Set();
  for (const [, src] of sources) {
    for (const m of src.matchAll(/RateLimiter\.Check\([^,]+,\s*"(\w+)"\)/g)) usedLimits.add(m[1]);
  }
  check("Rate-Limits werden ueberhaupt benutzt", usedLimits.size >= 5, `nur ${usedLimits.size} gefunden`);
  for (const name of usedLimits) {
    check(`Rate-Limit konfiguriert: ${name}`, declaredLimits.has(name), "fehlt in Config.RateLimits");
  }

  // Nur der SaveService darf den DataStore anfassen.
  for (const [file, src] of sources) {
    const short = relative(ROOT, file);
    if (short.endsWith("SaveService.luau")) continue;
    check(`kein DataStore in ${short}`, !src.includes("DataStoreService"), "greift direkt auf DataStores zu");
  }

  // Gespeicherte Zeitstempel muessen os.time() sein. os.clock() ist die
  // Laufzeit dieses Serverprozesses und nach einem Rejoin wertlos.
  const saveSrc = sources.get(join(SRC, "server/Systems/SaveService.luau"));
  check("SaveService benutzt os.time()", saveSrc.includes("os.time()"), "fehlt");
  check("SaveService benutzt kein os.clock() fuer Profildaten", !/LastSeen\s*=\s*os\.clock/.test(saveSrc), "LastSeen falsch");

  const targetsSrc = sources.get(join(SRC, "server/Systems/HackTargets.luau"));
  check(
    "Cooldowns benutzen os.time()",
    /Cooldowns\[id\]\s*=\s*os\.time\(\)/.test(targetsSrc),
    "SetCooldown schreibt keine Unix-Zeit"
  );
  check(
    "Cooldowns liegen im Profil",
    targetsSrc.includes("SaveService.Get(player)") && !/local cooldowns/.test(targetsSrc),
    "es gibt noch eine Cooldown-Tabelle im Serverspeicher"
  );
  check(
    "Ziel-Ids kollidieren nicht mehr",
    /repeat[\s\S]*?until registry\[/.test(targetsSrc),
    "nextFreeId zaehlt nicht bis zur freien Id hoch"
  );

  //========================================================================
  // 3. LOGIK  (echte Module in der Luau-VM)
  //========================================================================
  lines.push("");
  lines.push("--- 3. LOGIK (echte Module in der Luau-VM) ---");

  function loadModule(relPath) {
    let src = readFileSync(join(SRC, relPath), "utf8");
    src = src.replace(/^--!strict\s*$/m, "");
    src = src.replace(/^local (\w+) = require\(.+\)$/gm, 'local $1 = __deps["$1"]');
    src = src.replace(/^export type/gm, "type");
    return src;
  }

  const prelude = `
local Color3 = {
	fromRGB = function(r, g, b) return { r = r, g = g, b = b, kind = "Color3" } end,
	new = function(r, g, b) return { r = r, g = g, b = b, kind = "Color3" } end,
}
local Random = {
	new = function(seed)
		local rng = {}
		function rng:NextNumber(a, b)
			if a == nil then return math.random() end
			return a + math.random() * (b - a)
		end
		function rng:NextInteger(a, b) return math.random(a, b) end
		return rng
	end,
}
local game = { GetService = function() return {} end }
local __deps = {}
`;

  let body = prelude;
  for (const [name, path] of [
    ["Types", "shared/Types.luau"],
    ["Config", "shared/Config.luau"],
    ["NodeBreach", "server/Systems/Minigames/NodeBreach.luau"],
  ]) {
    body += `\n__deps["${name}"] = (function()\n${loadModule(path)}\nend)()\n`;
  }

  const luaTests = `
local Config = __deps["Config"]
local NodeBreach = __deps["NodeBreach"]

-- Ergebnis geht als eine Zeichenkette zurueck ("OK|name" / "FAIL|name|grund"),
-- damit zwischen Luau und JS keine Tabelle uebersetzt werden muss.
local out = {}
local function test(name, fn)
	local success, err = pcall(fn)
	if success then
		table.insert(out, "OK|" .. name)
	else
		table.insert(out, "FAIL|" .. name .. "|" .. tostring(err))
	end
end
local function expect(cond, msg)
	if not cond then error(msg, 0) end
end

--== Config: Grundformeln ==================================================

test("Reichweite/Zeit/Versuche steigen mit der Stufe", function()
	for level = 2, Config.Rig.MaxLevel do
		expect(Config.GetRange(level) > Config.GetRange(level - 1), "Reichweite steigt nicht")
		expect(Config.GetTimeLimit(level, 3) > Config.GetTimeLimit(level - 1, 3), "Zeit steigt nicht")
		expect(Config.GetAttempts(level) >= Config.GetAttempts(level - 1), "Versuche sinken")
	end
	expect(Config.GetAttempts(99) == Config.Attempts.Cap, "Versuche werden nicht gedeckelt")
end)

test("Belohnung waechst mit der Schwierigkeit", function()
	for d = 2, 10 do
		expect(Config.GetReward(d) > Config.GetReward(d - 1), "Belohnung steigt nicht bei D" .. d)
	end
	expect(Config.GetReward(1) > 0, "D1 bringt nichts")
end)

--== Trace =================================================================

test("Kuehlung senkt den Trace-Gewinn und beschleunigt die Abkuehlung", function()
	local previousGain = math.huge
	local previousDecay = -1
	for level = 1, Config.Rig.MaxLevel do
		local gain = Config.GetTraceGain(10, level)
		local decay = Config.GetTraceDecay(level)
		expect(gain < previousGain, "Trace-Gewinn faellt nicht bei Kuehlung " .. level)
		expect(decay > previousDecay, "Abkuehlung steigt nicht bei Kuehlung " .. level)
		previousGain, previousDecay = gain, decay
	end
	expect(Config.GetTraceGain(10, 99) >= 2, "Trace-Gewinn faellt unter die 20%-Grenze")
end)

test("Trace-Schwellen sind sinnvoll gestaffelt", function()
	expect(Config.Trace.WarnAt < Config.Trace.CriticalAt, "WarnAt >= CriticalAt")
	expect(Config.Trace.CriticalAt < Config.Trace.Max, "CriticalAt >= Max")
	expect(Config.Trace.AfterBust > 0 and Config.Trace.AfterBust < Config.Trace.Max, "AfterBust unbrauchbar")
	expect(Config.Trace.BustLockSeconds > 0, "Bust sperrt gar nicht")
end)

test("Ein Bust ist erreichbar, aber nicht sofort", function()
	-- Kamera (D2) auf Kuehlung 1: so viele erfolgreiche Hacks bis 100.
	local perHack = Config.GetTraceGain(2 * Config.Trace.GainPerDifficulty, 1)
	local hacks = Config.Trace.Max / perHack
	expect(hacks >= 8, "Bust kommt zu frueh: " .. hacks .. " Kamera-Hacks")
	expect(hacks <= 30, "Bust ist praktisch unerreichbar: " .. hacks .. " Kamera-Hacks")
end)

test("Ein Verkauf schafft mehr Luft als ein Hack kostet", function()
	local perHack = Config.GetTraceGain(2 * Config.Trace.GainPerDifficulty, 1)
	expect(Config.Sell.TraceRelief > perHack, "Verkaufen lohnt sich fuer den Trace nicht")
end)

--== Verkauf ===============================================================

test("Verkaufsrechnung stimmt und verliert nichts", function()
	for _, amount in { 0, 1, 37, 100, 4321 } do
		local gross, fee, net = Config.GetSellPayout(amount)
		expect(gross == math.floor(amount), "Brutto falsch bei " .. amount)
		expect(fee >= 0, "negative Gebuehr")
		expect(net >= 0, "negativer Erloes")
		expect(fee + net == gross, "Gebuehr + Netto ist nicht Brutto bei " .. amount)
	end
	local _, fee = Config.GetSellPayout(100)
	expect(fee == math.floor(100 * Config.Sell.FeePercent), "Gebuehrensatz stimmt nicht")
end)

--== Shop / Balancing-Vorgabe ==============================================

test("Upgrade-Preise sind exponentiell und begrenzt", function()
	for _, component in Config.Rig.Components do
		local previous = 0
		for level = 2, Config.Rig.MaxLevel do
			local cost = Config.GetUpgradeCost(component, level)
			expect(cost > previous, component .. ": Preis steigt nicht auf Stufe " .. level)
			previous = cost
		end
		expect(Config.GetUpgradeCost(component, 1) == math.huge, component .. ": Stufe 1 ist kaufbar")
		expect(
			Config.GetUpgradeCost(component, Config.Rig.MaxLevel + 1) == math.huge,
			component .. ": ueber MaxLevel kaufbar"
		)
	end
	expect(Config.GetUpgradeCost("GibtsNicht", 2) == math.huge, "unbekanntes Bauteil ist kaufbar")
end)

test("Erstes Upgrade nach 2-3 erfolgreichen Hacks (Vorgabe Phase 1)", function()
	-- Startziel ist die Kamera mit Schwierigkeit 2.
	local _, _, netPerHack = Config.GetSellPayout(Config.GetReward(2))
	expect(netPerHack > 0, "Kamera bringt nach Gebuehr nichts")

	for _, component in Config.Rig.Components do
		local cost = Config.GetUpgradeCost(component, 2)
		local hacks = math.ceil(cost / netPerHack)
		expect(hacks >= 2, component .. ": schon nach " .. hacks .. " Hack bezahlbar - zu billig")
		expect(hacks <= 3, component .. ": erst nach " .. hacks .. " Hacks bezahlbar - zu teuer")
	end
end)

test("Rig-Anzeigetexte sind fuer jedes Bauteil und jede Stufe da", function()
	for _, component in Config.Rig.Components do
		expect(Config.Rig.Labels[component] ~= nil, "Label fehlt: " .. component)
		expect(Config.Rig.Blurbs[component] ~= nil, "Blurb fehlt: " .. component)
		for level = 1, Config.Rig.MaxLevel do
			local text = Config.GetRigEffect(component, level)
			expect(typeof(text) == "string" and text ~= "-" and #text > 0, "Effekttext fehlt: " .. component)
		end
	end
end)

--== Node-Breach ===========================================================

local OPEN, ICE, RELAY, START, EXIT, MASKED = 0, 1, 2, 3, 4, 5

test("Node-Breach verraet die Loesung nicht an den Client", function()
	local rng = Random.new()
	for difficulty = 1, 10 do
		for _ = 1, 20 do
			local public, serverState = NodeBreach.Generate(difficulty, rng)
			expect(#public.Cells == public.Width * public.Height, "Gitter unvollstaendig")
			expect(public.Solution == nil, "publicState enthaelt die Loesung")
			expect(public.Path == nil, "publicState enthaelt den Pfad")
			for index, cell in public.Cells do
				expect(cell ~= MASKED, "getarntes ICE ist im publicState sichtbar")
				if serverState.Cells[index] == MASKED then
					expect(cell == OPEN, "getarntes ICE ist nicht als freier Knoten getarnt")
				end
			end
			expect(public.Cells[public.Start] == START, "Start fehlt")
			expect(public.Cells[public.Exit] == EXIT, "Exit fehlt")
		end
	end
end)

test("Node-Breach ist auf jeder Schwierigkeit loesbar", function()
	local rng = Random.new()
	for difficulty = 1, 10 do
		for attempt = 1, 15 do
			local _, serverState = NodeBreach.Generate(difficulty, rng)
			local solution = serverState.Solution
			expect(#solution >= 2, "D" .. difficulty .. ": Loesungspfad zu kurz")
			expect(solution[1] == serverState.Start, "Loesung beginnt nicht am Start")
			expect(solution[#solution] == serverState.Exit, "Loesung endet nicht am Exit")

			local solved = false
			for step = 2, #solution do
				local result = NodeBreach.Input(serverState, { Node = solution[step] })
				expect(result.CostsAttempt == false, "D" .. difficulty .. ": Loesungspfad kostet einen Versuch")
				expect(result.Ok, "D" .. difficulty .. ": Schritt " .. step .. " abgelehnt (" .. result.Reason .. ")")
				solved = result.Solved
			end
			expect(solved, "D" .. difficulty .. " Versuch " .. attempt .. ": Exit nicht erreicht")
		end
	end
end)

test("Node-Breach weist ungueltige Eingaben ab", function()
	local rng = Random.new()
	local _, serverState = NodeBreach.Generate(3, rng)
	local total = serverState.Width * serverState.Height

	expect(NodeBreach.Input(serverState, nil).Reason == "BAD_PAYLOAD", "nil akzeptiert")
	expect(NodeBreach.Input(serverState, {}).Reason == "BAD_PAYLOAD", "leere Tabelle akzeptiert")
	expect(NodeBreach.Input(serverState, { Node = 0 }).Reason == "BAD_PAYLOAD", "Knoten 0 akzeptiert")
	expect(NodeBreach.Input(serverState, { Node = total + 1 }).Reason == "BAD_PAYLOAD", "Knoten ausserhalb akzeptiert")
	expect(NodeBreach.Input(serverState, { Node = 2.5 }).Reason == "BAD_PAYLOAD", "Kommazahl akzeptiert")
	expect(NodeBreach.Input(serverState, { Node = serverState.Start }).Reason == "ALREADY_HERE", "Start nochmal gesetzt")
	expect(NodeBreach.Input(serverState, { Node = serverState.Exit }).Reason == "NOT_ADJACENT", "Sprung zum Exit erlaubt")
end)

test("Getarntes ICE kostet genau einen Versuch und fliegt auf", function()
	local rng = Random.new()
	for _ = 1, 60 do
		local _, serverState = NodeBreach.Generate(6, rng)
		-- Einen getarnten Knoten suchen, der an den Start grenzt.
		local width, height = serverState.Width, serverState.Height
		local startX = (serverState.Start - 1) % width + 1
		local startY = math.floor((serverState.Start - 1) / width) + 1
		local candidates = {}
		if startX > 1 then table.insert(candidates, serverState.Start - 1) end
		if startX < width then table.insert(candidates, serverState.Start + 1) end
		if startY > 1 then table.insert(candidates, serverState.Start - width) end
		if startY < height then table.insert(candidates, serverState.Start + width) end

		for _, node in candidates do
			if serverState.Cells[node] == MASKED then
				local result = NodeBreach.Input(serverState, { Node = node })
				expect(result.CostsAttempt, "getarntes ICE kostet keinen Versuch")
				expect(result.Reason == "MASKED_ICE", "falscher Grund: " .. result.Reason)
				expect(serverState.Cells[node] == ICE, "getarntes ICE bleibt getarnt")
				expect(result.Feedback.Reveal == node, "Aufdeckung wird nicht gemeldet")
				-- Zweiter Versuch: jetzt sichtbares ICE, kostet nichts mehr.
				local again = NodeBreach.Input(serverState, { Node = node })
				expect(again.Reason == "ICE", "aufgedecktes ICE verhaelt sich falsch")
				expect(again.CostsAttempt == false, "aufgedecktes ICE kostet nochmal")
				return
			end
		end
	end
	error("in 60 Gittern kein getarntes ICE neben dem Start gefunden", 0)
end)

test("Zuruecknehmen des letzten Knotens funktioniert", function()
	local rng = Random.new()
	local _, serverState = NodeBreach.Generate(2, rng)
	local second = serverState.Solution[2]
	local first = NodeBreach.Input(serverState, { Node = second })
	expect(first.Ok, "erster Schritt abgelehnt")
	expect(#serverState.Path == 2, "Pfad nicht gewachsen")
	local back = NodeBreach.Input(serverState, { Node = serverState.Start })
	expect(back.Reason == "BACKTRACK", "Zuruecknehmen nicht erkannt")
	expect(#serverState.Path == 1, "Pfad nicht geschrumpft")
	expect(serverState.RelaysVisited == 0, "Relay-Zaehler nicht zurueckgesetzt")
end)

return table.concat(out, "\\n")
`;

  const run = state.loadstring(body + luaTests, "ghostnet-logik", true);
  const report = await run();
  for (const line of String(report).split("\n")) {
    if (line === "") continue;
    const [verdict, name, detail] = line.split("|");
    if (verdict === "OK") ok(name);
    else bad(name, detail ?? "");
  }
} catch (error) {
  bad("HARNESS", error?.message ?? String(error));
} finally {
  state.destroy();
}

lines.push("");
lines.push(`ERGEBNIS: ${passed} bestanden, ${failed} fehlgeschlagen (${passed + failed} Pruefungen)`);
console.log(lines.join("\n"));
process.exit(failed > 0 ? 1 : 0);
