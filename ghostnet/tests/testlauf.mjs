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

  // Kein Modul darf ein anderes im Kreis requiren. Der MissionService haengt
  // sich per Callback an HackService/SellService - nicht umgekehrt.
  const serverModules = new Map();
  for (const [file, src] of sources) {
    const short = relative(ROOT, file);
    if (!short.startsWith("src/server/Systems/")) continue;
    const name = short.split("/").pop().replace(/\.luau$/, "");
    const deps = [...src.matchAll(/require\(script\.Parent\.(\w+)\)/g)].map((m) => m[1]);
    serverModules.set(name, deps);
  }
  const cycle = (() => {
    const state = new Map();
    const walk = (name, trail) => {
      if (state.get(name) === 1) return [...trail, name];
      if (state.get(name) === 2) return null;
      state.set(name, 1);
      for (const dep of serverModules.get(name) ?? []) {
        const found = walk(dep, [...trail, name]);
        if (found) return found;
      }
      state.set(name, 2);
      return null;
    };
    for (const name of serverModules.keys()) {
      const found = walk(name, []);
      if (found) return found;
    }
    return null;
  })();
  check("kein Require-Kreis zwischen den Services", cycle === null, cycle ? cycle.join(" -> ") : "");

  // Der MissionService darf nirgendwo rueckwaerts requiret werden.
  for (const [name, deps] of serverModules) {
    if (name === "MissionService") continue;
    check(
      `${name} requiret den MissionService nicht`,
      !deps.includes("MissionService"),
      "rueckwaerts-Abhaengigkeit"
    );
  }

  // Jede Schema-Version braucht eine Migration.
  const schemaVersion = Number(/SchemaVersion = (\d+)/.exec(configSrc)?.[1] ?? 0);
  check("Schema-Version ist gesetzt", schemaVersion >= 1, `gelesen: ${schemaVersion}`);
  const migrationKeys = [...saveSrc.matchAll(/\[(\d+)\]\s*=\s*function\(profile/g)].map((m) => Number(m[1]));
  for (let version = 2; version <= schemaVersion; version++) {
    check(`Migration auf Schema ${version} vorhanden`, migrationKeys.includes(version), "fehlt in MIGRATIONS");
  }
  check(
    "Story-Block ist im Default-Profil",
    /Story = defaultStory\(\)/.test(saveSrc),
    "DefaultProfile hat keinen Story-Block"
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
    ["Missions", "shared/Missions.luau"],
    ["NodeBreach", "server/Systems/Minigames/NodeBreach.luau"],
  ]) {
    body += `\n__deps["${name}"] = (function()\n${loadModule(path)}\nend)()\n`;
  }

  const luaTests = `
local Config = __deps["Config"]
local Missions = __deps["Missions"]
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

--== Missionen (Phase A) ===================================================

local function story(completed, unlocks, active)
	return { Active = active or "", Completed = completed or {}, Unlocks = unlocks or {} }
end

test("Registry der echten Missionen ist gueltig", function()
	local valid, errors = Missions.Validate(nil, Config.Mission.MaxSteps)
	expect(valid, "Missionsdaten kaputt: " .. table.concat(errors, " | "))
end)

test("Das dokumentierte Beispiel haelt das eigene Schema ein", function()
	local valid, errors = Missions.Validate({ Missions.Example }, Config.Mission.MaxSteps)
	expect(valid, "Missions.Example ist selbst ungueltig: " .. table.concat(errors, " | "))
	-- Es soll jeden Schritt-Typ genau einmal zeigen.
	local seen = {}
	for _, step in Missions.Example.Steps do
		seen[step.Type] = true
	end
	for stepType in Missions.StepTypes do
		expect(seen[stepType], "Beispiel zeigt den Typ " .. stepType .. " nicht")
	end
end)

test("Validate findet kaputte Missionsdaten", function()
	local function broken(list)
		local valid = Missions.Validate(list, Config.Mission.MaxSteps)
		return not valid
	end

	local goodStep = { Type = "SELL", Amount = 1, Text = "verkaufen" }
	local function mission(id, steps, requires)
		return { Id = id, Title = "T", Briefing = "B", Requires = requires or {}, Steps = steps, Reward = {} }
	end

	expect(broken({ mission("A", { goodStep }), mission("A", { goodStep }) }), "doppelte Id durchgelassen")
	expect(broken({ mission("A", { { Type = "NOPE", Text = "x" } }) }), "unbekannter Typ durchgelassen")
	expect(broken({ mission("A", { { Type = "HACK", Text = "x" } }) }), "HACK ohne TargetId durchgelassen")
	expect(broken({ mission("A", { { Type = "GOTO", Text = "x" } }) }), "GOTO ohne Target durchgelassen")
	expect(broken({ mission("A", { { Type = "WAIT", Text = "x" } }) }), "WAIT ohne Seconds durchgelassen")
	expect(broken({ mission("A", { goodStep }, { "GIBTSNICHT" }) }), "unbekannter Vorgaenger durchgelassen")
	expect(broken({ mission("A", {}) }), "Mission ohne Schritte durchgelassen")
	expect(
		broken({ mission("A", { goodStep }, { "B" }), mission("B", { goodStep }, { "A" }) }),
		"Kreis in den Vorbedingungen durchgelassen"
	)
	-- Und die saubere Variante muss durchgehen.
	local valid = Missions.Validate({ mission("A", { goodStep }), mission("B", { goodStep }, { "A" }) })
	expect(valid, "gueltige Kette abgelehnt")
end)

test("Verfuegbarkeit haengt an den Vorgaengern", function()
	local goodStep = { Type = "SELL", Amount = 1, Text = "verkaufen" }
	local list = {
		{ Id = "M1", Title = "1", Briefing = "", Requires = {}, Steps = { goodStep }, Reward = {} },
		{ Id = "M2", Title = "2", Briefing = "", Requires = { "M1" }, Steps = { goodStep }, Reward = {} },
	}

	local fresh = story()
	expect(Missions.IsAvailable(fresh, "M1", list), "M1 nicht verfuegbar")
	expect(not Missions.IsAvailable(fresh, "M2", list), "M2 ohne Vorgaenger verfuegbar")
	expect(Missions.FirstAvailable(fresh, list).Id == "M1", "falsche erste Mission")

	local after = story({ "M1" })
	expect(not Missions.IsAvailable(after, "M1", list), "abgeschlossene Mission nochmal verfuegbar")
	expect(Missions.IsAvailable(after, "M2", list), "M2 nach Vorgaenger nicht verfuegbar")
	expect(Missions.FirstAvailable(after, list).Id == "M2", "falsche Folgemission")

	local done = story({ "M1", "M2" })
	expect(Missions.FirstAvailable(done, list) == nil, "nach allen Missionen kommt noch eine")
end)

test("Unlocks werden korrekt gelesen", function()
	local s = story({}, { "STORE_RAIDS" })
	expect(Missions.HasUnlock(s, "STORE_RAIDS"), "Unlock nicht erkannt")
	expect(not Missions.HasUnlock(s, "DARKNET"), "unbekannter Unlock als vorhanden gemeldet")
end)

test("Progress: jeder Schritt-Typ reagiert nur auf sein eigenes Ereignis", function()
	local steps = {
		GOTO = { Type = "GOTO", Target = "WP", Text = "x" },
		HACK = { Type = "HACK", TargetId = "T1", Text = "x" },
		TALK = { Type = "TALK", ContactId = "C1", Text = "x" },
		SELL = { Type = "SELL", Text = "x" },
		WAIT = { Type = "WAIT", Seconds = 3, Text = "x" },
		BUY = { Type = "BUY", GoodId = "G1", Amount = 2, Text = "x" },
	}
	local events = {
		GOTO = { Type = "GOTO", WaypointId = "WP" },
		HACK = { Type = "HACK", TargetId = "T1", Success = true },
		TALK = { Type = "TALK", ContactId = "C1" },
		SELL = { Type = "SELL" },
		WAIT = { Type = "WAIT" },
		BUY = { Type = "BUY", GoodId = "G1", Amount = 1 },
	}

	for stepType, step in steps do
		expect(Missions.Progress(step, events[stepType]) > 0, stepType .. ": passendes Ereignis zaehlt nicht")
		for otherType, event in events do
			if otherType ~= stepType then
				expect(
					Missions.Progress(step, event) == 0,
					stepType .. ": reagiert faelschlich auf " .. otherType
				)
			end
		end
	end
end)

test("Progress: falsche Ziele und Fehlschlaege zaehlen nicht", function()
	local hack = { Type = "HACK", TargetId = "T1", Text = "x" }
	expect(Missions.Progress(hack, { Type = "HACK", TargetId = "T2", Success = true }) == 0, "falsches Ziel zaehlt")
	expect(Missions.Progress(hack, { Type = "HACK", TargetId = "T1", Success = false }) == 0, "Fehlschlag zaehlt")
	expect(Missions.Progress(hack, { Type = "HACK", TargetId = "T1" }) == 0, "Hack ohne Success-Flag zaehlt")

	local goto_ = { Type = "GOTO", Target = "WP", Text = "x" }
	expect(Missions.Progress(goto_, { Type = "GOTO", WaypointId = "ANDERS" }) == 0, "falscher Wegpunkt zaehlt")

	local talk = { Type = "TALK", ContactId = "C1", Text = "x" }
	expect(Missions.Progress(talk, { Type = "TALK", ContactId = "C2" }) == 0, "falscher Kontakt zaehlt")

	expect(Missions.Progress(hack, nil) == 0, "nil-Ereignis zaehlt")
	expect(Missions.Progress(hack, "kaputt") == 0, "String-Ereignis zaehlt")
end)

test("Progress: BUY zaehlt Stueckzahlen, SELL zaehlt Verkaeufe", function()
	local buy = { Type = "BUY", GoodId = "G1", Amount = 5, Text = "x" }
	expect(Missions.Required(buy) == 5, "Required liest Amount nicht")
	expect(Missions.Progress(buy, { Type = "BUY", GoodId = "G1", Amount = 3 }) == 3, "Stueckzahl falsch")
	expect(Missions.Progress(buy, { Type = "BUY", GoodId = "G2", Amount = 3 }) == 0, "falsche Ware zaehlt")
	expect(Missions.Progress(buy, { Type = "BUY", GoodId = "G1", Amount = -2 }) == 0, "negative Menge zaehlt")
	expect(Missions.Progress(buy, { Type = "BUY", GoodId = "G1" }) == 0, "Kauf ohne Menge zaehlt")

	-- Ohne GoodId zaehlt jede Ware.
	local anyBuy = { Type = "BUY", Amount = 2, Text = "x" }
	expect(Missions.Progress(anyBuy, { Type = "BUY", GoodId = "EGAL", Amount = 2 }) == 2, "offener Kauf zaehlt nicht")

	local sell = { Type = "SELL", Amount = 3, Text = "x" }
	expect(Missions.Required(sell) == 3, "SELL-Required falsch")
	expect(Missions.Progress(sell, { Type = "SELL", Net = 9999 }) == 1, "ein Verkauf zaehlt nicht als 1")

	local plain = { Type = "SELL", Text = "x" }
	expect(Missions.Required(plain) == 1, "Standard-Required ist nicht 1")
end)

test("Eine ganze Mission laesst sich Schritt fuer Schritt durchspielen", function()
	-- Simuliert genau das, was der MissionService mit den puren Regeln macht.
	local mission = {
		Id = "M",
		Title = "T",
		Briefing = "",
		Requires = {},
		Steps = {
			{ Type = "GOTO", Target = "WP", Text = "hin" },
			{ Type = "HACK", TargetId = "T1", Text = "knacken" },
			{ Type = "SELL", Amount = 2, Text = "zweimal abliefern" },
		},
		Reward = { Crypto = 400, Unlock = "STORE_RAIDS" },
	}
	local valid, errors = Missions.Validate({ mission }, Config.Mission.MaxSteps)
	expect(valid, "Testmission ungueltig: " .. table.concat(errors, " | "))

	local index, progress = 1, 0
	local function feed(event)
		local step = mission.Steps[index]
		if not step then
			return
		end
		local gain = Missions.Progress(step, event)
		if gain <= 0 then
			return
		end
		progress += gain
		if progress >= Missions.Required(step) then
			index += 1
			progress = 0
		end
	end

	feed({ Type = "SELL" }) -- falsche Reihenfolge: darf nichts tun
	expect(index == 1, "SELL hat den GOTO-Schritt vorgezogen")

	feed({ Type = "GOTO", WaypointId = "WP" })
	expect(index == 2, "GOTO nicht abgeschlossen")

	feed({ Type = "HACK", TargetId = "T1", Success = false })
	expect(index == 2, "Fehlschlag hat den Schritt beendet")
	feed({ Type = "HACK", TargetId = "T1", Success = true })
	expect(index == 3, "HACK nicht abgeschlossen")

	feed({ Type = "SELL" })
	expect(index == 3 and progress == 1, "erster von zwei Verkaeufen falsch gezaehlt")
	feed({ Type = "SELL" })
	expect(index == 4, "Mission nicht abgeschlossen")
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
