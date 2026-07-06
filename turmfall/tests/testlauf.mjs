// Testlauf für TURMFALL: lädt die puren Shared-Module (Schuld-Algorithmus,
// Punkteberechnung, Konfiguration, Teilkatalog) in eine echte Luau-VM
// (luau-web/WASM) und prüft die Spielregeln. Zusätzlich ein statischer
// Abgleich: Jedes im Code benutzte Remote muss in Network.luau deklariert sein.
//
// Ausführen (vom Repo-Root):  node turmfall/tests/testlauf.mjs
import { LuauState } from "../../tests/node_modules/luau-web/src/index.js";
import { readFileSync, readdirSync, statSync } from "fs";
import { join } from "path";

const ROOT = new URL("..", import.meta.url).pathname.replace(/\/$/, "");

function loadModule(relPath) {
  let src = readFileSync(`${ROOT}/${relPath}`, "utf8");
  src = src.replace(/^--!strict\s*$/m, "");
  src = src.replace(/^local (\w+) = require\(.+\)$/gm, 'local $1 = __deps["$1"]');
  src = src.replace(/^export type/gm, "type");
  return src;
}

// ---------------------------------------------------------------------------
// Statischer Remote-Abgleich (JavaScript, kein Luau nötig)
// ---------------------------------------------------------------------------

function collectLuauFiles(dir) {
  const files = [];
  for (const entry of readdirSync(dir)) {
    const full = join(dir, entry);
    if (statSync(full).isDirectory()) {
      files.push(...collectLuauFiles(full));
    } else if (entry.endsWith(".luau")) {
      files.push(full);
    }
  }
  return files;
}

function extractDeclared(networkSource, listName) {
  // Bis zur schließenden Klammer am Zeilenanfang lesen (Kommentare in der
  // Liste dürfen selbst geschweifte Klammern enthalten).
  const match = networkSource.match(new RegExp(`local ${listName} = \\{([\\s\\S]*?)\\n\\}`));
  if (!match) return [];
  return [...match[1].matchAll(/^\s*"(\w+)"/gm)].map((m) => m[1]);
}

let staticErrors = [];
{
  const networkSource = readFileSync(`${ROOT}/src/shared/Network.luau`, "utf8");
  const declaredEvents = new Set(extractDeclared(networkSource, "EVENT_NAMES"));
  const declaredFunctions = new Set(extractDeclared(networkSource, "FUNCTION_NAMES"));

  for (const file of collectLuauFiles(`${ROOT}/src`)) {
    const source = readFileSync(file, "utf8");
    for (const m of source.matchAll(/getEvent\("(\w+)"\)/g)) {
      if (!declaredEvents.has(m[1])) {
        staticErrors.push(`${file}: RemoteEvent "${m[1]}" ist nicht in Network.EVENT_NAMES deklariert`);
      }
    }
    for (const m of source.matchAll(/getFunction\("(\w+)"\)/g)) {
      if (!declaredFunctions.has(m[1])) {
        staticErrors.push(`${file}: RemoteFunction "${m[1]}" ist nicht in Network.FUNCTION_NAMES deklariert`);
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Luau-VM-Tests der puren Logik
// ---------------------------------------------------------------------------

const modules = [
  ["Types", "src/shared/Types.luau"],
  ["GameConfig", "src/shared/Config/GameConfig.luau"],
  ["PartCatalog", "src/shared/Config/PartCatalog.luau"],
  ["SkinCatalog", "src/shared/Config/SkinCatalog.luau"],
  ["MonetizationCatalog", "src/shared/Config/MonetizationCatalog.luau"],
  ["ReceiptLogic", "src/shared/ReceiptLogic.luau"],
  ["LevelLogic", "src/shared/LevelLogic.luau"],
  ["BlameLogic", "src/shared/BlameLogic.luau"],
  ["ScoreLogic", "src/shared/ScoreLogic.luau"],
];

const prelude = `
local __deps = {}
`;

let body = prelude;
for (const [name, path] of modules) {
  body += `\n__deps["${name}"] = (function()\n${loadModule(path)}\nend)()\n`;
}

const tests = `
local GameConfig = __deps["GameConfig"]
local PartCatalog = __deps["PartCatalog"]
local SkinCatalog = __deps["SkinCatalog"]
local MonetizationCatalog = __deps["MonetizationCatalog"]
local ReceiptLogic = __deps["ReceiptLogic"]
local LevelLogic = __deps["LevelLogic"]
local BlameLogic = __deps["BlameLogic"]
local ScoreLogic = __deps["ScoreLogic"]

local results = {}
local passed = 0
local failed = 0

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

local function expect(condition, message)
	if not condition then
		error(message, 0)
	end
end

-- Hilfen zum Bauen synthetischer Schuld-Szenarien.
local function pos(x, y, z) return { x = x, y = y, z = z } end
local function placement(pieceId, owner, at) return { pieceId = pieceId, ownerUserId = owner, placedAt = at } end

-- 1) Konfigurations-Canon
test("GameConfig: Kern-Konstanten des Konzepts", function()
	expect(GameConfig.BUILD_SECONDS == 180, "Bauphase != 3 Minuten")
	expect(GameConfig.LOBBY_MIN_PLAYERS == 2, "Start nicht ab 2 Spielern")
	expect(GameConfig.PART_DROP_INTERVAL_SECONDS == 15, "Teilvergabe != alle 15 s")
	expect(GameConfig.HOTBAR_MAX_ITEMS == 3, "Hotbar != max. 3")
	expect(GameConfig.PLACE_REACH_STUDS == 12, "Reichweite != 12 Studs")
	expect(GameConfig.MAX_PHYSICS_PARTS == 400, "Physik-Limit != 400")
	expect(GameConfig.FALL_WINDOW_SECONDS == 5, "Kollaps-Fenster != 5 s")
	expect(math.abs(GameConfig.FALL_COLLAPSE_RATIO - 0.3) < 1e-9, "Kollaps-Schwelle != 30%")
	expect(GameConfig.RING_BUFFER_SECONDS == 10, "Ringpuffer != 10 s")
	expect(GameConfig.RING_BUFFER_HZ == 4, "Ringpuffer != 4 Hz")
	expect(GameConfig.REPLAY_SECONDS == 5, "Replay != 5 s")
	expect(GameConfig.PETRIFY_TARGET_RATIO > 0 and GameConfig.PETRIFY_TARGET_RATIO < 1, "Petrify-Ziel unplausibel")
end)

-- 2) Teilkatalog
test("PartCatalog: vier Typen mit sinnvollen Werten", function()
	local ids = PartCatalog.getSortedIds()
	expect(#ids == 4, "Teiltypen != 4")
	for _, id in { "schwerblock", "leichtblock", "schraegkeil", "federblock" } do
		local def = PartCatalog.Parts[id]
		expect(def ~= nil, "Teiltyp fehlt: " .. id)
		expect(def.dropWeight > 0, id .. ": dropWeight <= 0")
		expect(def.density > 0, id .. ": density <= 0")
		expect(def.size.x > 0 and def.size.y > 0 and def.size.z > 0, id .. ": Groesse unplausibel")
	end
	expect(
		PartCatalog.Parts.schwerblock.density > PartCatalog.Parts.leichtblock.density,
		"Schwerblock muss dichter sein als Leichtblock"
	)
	expect(PartCatalog.getApproxRadius("schwerblock") == 2, "Radius-Naeherung Schwerblock falsch")
	expect(PartCatalog.getApproxRadius("unbekannt") == 2, "Fallback-Radius falsch")
end)

-- 3) Schuld-Algorithmus: Verursacher ist selbst Teil der Kaskade
test("BlameLogic: gefallenes zuletzt platziertes Teil ist schuld", function()
	local placements = { placement(1, 100, 10), placement(2, 200, 20), placement(3, 300, 30) }
	local samples = { { t = 29, positions = { [1] = pos(0, 5, 0), [2] = pos(0, 8, 0), [3] = pos(0, 11, 0) } } }
	local fallen = { [2] = true, [3] = true }
	local radii = { [1] = 2, [2] = 2, [3] = 2 }
	local pieceId, userId = BlameLogic.findCulprit(placements, samples, fallen, radii, 1)
	expect(pieceId == 3, "falsches Verursacher-Teil: " .. tostring(pieceId))
	expect(userId == 300, "falscher Verursacher: " .. tostring(userId))
end)

-- 4) Schuld-Algorithmus: Kontakt zur Kaskade ohne selbst zu fallen
test("BlameLogic: Kontakt-Teil wird schuldig, entferntes nicht", function()
	-- Teil 3 zuletzt platziert, aber weit weg; Teil 2 beruehrte das gefallene Teil 1.
	local placements = { placement(1, 100, 10), placement(2, 200, 20), placement(3, 300, 30) }
	local samples = {
		{ t = 28, positions = { [1] = pos(0, 5, 0), [2] = pos(0, 8.5, 0), [3] = pos(50, 5, 50) } },
		{ t = 29, positions = { [1] = pos(0, -10, 0), [2] = pos(0, 8.5, 0), [3] = pos(50, 5, 50) } },
	}
	local fallen = { [1] = true }
	local radii = { [1] = 2, [2] = 2, [3] = 2 }
	local pieceId, userId = BlameLogic.findCulprit(placements, samples, fallen, radii, 1)
	expect(pieceId == 2, "Kontakt-Teil nicht erkannt: " .. tostring(pieceId))
	expect(userId == 200, "falscher Besitzer: " .. tostring(userId))
end)

-- 5) Schuld-Algorithmus: Kontaktradius + Toleranz entscheidet
test("BlameLogic: Kontakt haengt an Radien plus Toleranz", function()
	-- Teil 1 (aelter) ist gefallen; Teil 2 (juenger) steht daneben.
	local placements = { placement(1, 100, 10), placement(2, 200, 20) }
	local fallen = { [1] = true }
	local radii = { [1] = 2, [2] = 2 }
	-- Abstand 5.5 > 2+2+1: Teil 2 hat KEINEN Kontakt -> das Kaskaden-Mitglied
	-- selbst (Teil 1) ist der juengste Treffer der Regel.
	local farSamples = { { t = 1, positions = { [1] = pos(0, 0, 0), [2] = pos(5.5, 0, 0) } } }
	local farPieceId, farUserId = BlameLogic.findCulprit(placements, farSamples, fallen, radii, 1)
	expect(farPieceId == 1 and farUserId == 100, "ohne Kontakt muss das Kaskaden-Mitglied schuld sein")
	-- Abstand 4.8 <= 5: Teil 2 hat Kontakt und ist juenger -> Teil 2 ist schuld.
	local nearSamples = { { t = 1, positions = { [1] = pos(0, 0, 0), [2] = pos(4.8, 0, 0) } } }
	local nearPieceId, nearUserId = BlameLogic.findCulprit(placements, nearSamples, fallen, radii, 1)
	expect(nearPieceId == 2 and nearUserId == 200, "Kontakt bei Abstand 4.8 nicht erkannt")
end)

-- 6) Schuld-Algorithmus: ohne Kontakt kein Verursacher
test("BlameLogic: kein Kontakt -> niemand ist schuld", function()
	local placements = { placement(1, 100, 10), placement(2, 200, 20) }
	local samples = { { t = 1, positions = { [1] = pos(0, 0, 0), [2] = pos(100, 0, 100) } } }
	local fallen = { [1] = true }
	-- Teil 1 ist gefallen, aber Teil 1 wurde ZUERST platziert; Teil 2 hat keinen Kontakt.
	-- Erwartung: Teil 1 selbst (Kaskaden-Mitglied) ist der juengste Treffer.
	local pieceId, userId = BlameLogic.findCulprit(placements, samples, fallen, { [1] = 2, [2] = 2 }, 1)
	expect(pieceId == 1 and userId == 100, "Kaskaden-Mitglied muss gefunden werden")
	-- Und wenn NICHTS gefallen ist und nichts Kontakt hat: nil.
	local none = BlameLogic.findCulprit(placements, samples, {}, { [1] = 2, [2] = 2 }, 1)
	expect(none == nil, "ohne Kaskade darf es keinen Schuldigen geben")
end)

-- 7) Punkteberechnung
test("ScoreLogic: Hoehe zaehlt, Gefallene nicht, Verursacher = 0", function()
	local pieces = {
		{ ownerUserId = 100, heightAboveBase = 4.9, fallen = false },
		{ ownerUserId = 100, heightAboveBase = 10.2, fallen = false },
		{ ownerUserId = 100, heightAboveBase = 99, fallen = true },
		{ ownerUserId = 200, heightAboveBase = 55, fallen = false },
		{ ownerUserId = 300, heightAboveBase = 0.2, fallen = false },
	}
	local scores = ScoreLogic.computeScores(pieces, { [200] = true })
	expect(scores[100] == 4 + 10, "Spieler 100: " .. tostring(scores[100]))
	expect(scores[200] == 0, "Verursacher muss 0 Punkte haben")
	expect(scores[300] == 1, "Bodenteil muss mindestens 1 Punkt geben")
end)

-- 8) Punkteberechnung: Randfaelle
test("ScoreLogic: leere Runde und nur-gefallene Teile", function()
	local empty = ScoreLogic.computeScores({}, {})
	expect(next(empty) == nil, "leere Runde muss leeres Ergebnis geben")
	local onlyFallen = ScoreLogic.computeScores({ { ownerUserId = 100, heightAboveBase = 0, fallen = true } }, {})
	expect(onlyFallen[100] == 0, "nur gefallene Teile -> 0 Punkte (aber Eintrag vorhanden)")
end)

-- 9) Skin-Katalog (Meilenstein 2)
test("SkinCatalog: 12 Teil-Skins, 2 Kollaps-Effekte, alle Raritaeten", function()
	SkinCatalog.validate() -- wirft bei jedem Regelverstoss
	local teilCount, kollapsCount = 0, 0
	local raritiesSeen = {}
	for _, skin in SkinCatalog.Skins do
		if skin.category == "teil" then
			teilCount += 1
		else
			kollapsCount += 1
		end
		raritiesSeen[skin.rarity] = true
	end
	expect(teilCount == 12, "Teil-Skins != 12 (Starter-Katalog): " .. teilCount)
	expect(kollapsCount == 2, "Kollaps-Effekte != 2: " .. kollapsCount)
	for _, rarity in { "Common", "Rare", "Epic", "Legendary" } do
		expect(raritiesSeen[rarity] == true, "Raritaet fehlt im Katalog: " .. rarity)
	end
	-- Mindestens ein Start-Skin, damit jeder sofort etwas besitzt.
	local hasStart = false
	for _, skin in SkinCatalog.Skins do
		if skin.unlockCondition == "start" then
			hasStart = true
		end
	end
	expect(hasStart, "kein Start-Skin vorhanden")
end)

-- 10) Kosmetik-Guard: Physik-Felder fliegen sofort auf
test("SkinCatalog: Guard blockiert Physik-Felder in visualData", function()
	local holz = SkinCatalog.Skins.holz
	local visual = holz.visualData
	visual.density = 99 -- Sabotage-Versuch: kaufbarer Physik-Vorteil
	local ok = pcall(SkinCatalog.validate)
	visual.density = nil -- aufräumen
	expect(ok == false, "validate() muss Physik-Felder ablehnen")
	expect(pcall(SkinCatalog.validate) == true, "Katalog muss nach Aufräumen wieder gueltig sein")
end)

-- 11) Teil-Skins referenzieren nur echte Teiltypen
test("SkinCatalog: partType-Verweise sind gueltig", function()
	for id, skin in SkinCatalog.Skins do
		if skin.category == "teil" and skin.partType ~= "alle" then
			expect(PartCatalog.Parts[skin.partType] ~= nil, id .. ": unbekannter partType " .. tostring(skin.partType))
		end
	end
end)

-- 12) Monetarisierungs-Guard (Meilenstein 3)
test("MonetizationCatalog: Guard laesst nur Kosmetik zu", function()
	MonetizationCatalog.validate() -- wirft bei jedem Regelverstoss
	-- Platzhalter-IDs (0) duerfen NIE matchen (sonst greift ProcessReceipt ins Leere).
	expect(MonetizationCatalog.findProductByProductId(0) == nil, "Platzhalter-ID 0 darf nie matchen")
	expect(MonetizationCatalog.findProductByProductId(999999) == nil, "unbekannte ID darf nicht matchen")
	-- Sabotage: ein Produkt, das etwas Nicht-Kosmetisches vergibt, fliegt auf.
	MonetizationCatalog.DEVPRODUCT_IDS.hack = {
		key = "hack",
		productId = 0,
		displayName = "Punkte-Boost",
		grantsSkins = { "punkte_boost_9000" }, -- existiert nicht im SkinCatalog
	}
	local ok = pcall(MonetizationCatalog.validate)
	MonetizationCatalog.DEVPRODUCT_IDS.hack = nil
	expect(ok == false, "Guard muss Nicht-Kosmetik-Produkte ablehnen")
	expect(pcall(MonetizationCatalog.validate) == true, "Katalog muss nach Aufraeumen wieder gueltig sein")
end)

-- 13) Receipt-Idempotenz (der haeufigste Anfaengerfehler)
test("ReceiptLogic: kein Beleg wird doppelt gutgeschrieben", function()
	local log = {}
	expect(ReceiptLogic.alreadyProcessed(log, "r1") == false, "leeres Log darf nichts kennen")
	ReceiptLogic.remember(log, "r1")
	expect(ReceiptLogic.alreadyProcessed(log, "r1") == true, "r1 muss bekannt sein")
	ReceiptLogic.remember(log, "r1") -- Doppel-Merken ist ein No-Op
	expect(#log == 1, "Doppel-Merken darf keinen zweiten Eintrag anlegen")
	-- Limit: aelteste Belege fliegen raus, neueste bleiben.
	for index = 2, ReceiptLogic.LOG_LIMIT + 5 do
		ReceiptLogic.remember(log, "r" .. index)
	end
	expect(#log == ReceiptLogic.LOG_LIMIT, "Log muss auf das Limit gedeckelt sein")
	expect(ReceiptLogic.alreadyProcessed(log, "r1") == false, "aeltester Beleg muss rausrotiert sein")
	expect(ReceiptLogic.alreadyProcessed(log, "r" .. (ReceiptLogic.LOG_LIMIT + 5)) == true, "neuester Beleg muss bekannt sein")
end)

-- 14) Truemmer-Oekonomie: erspielt, nicht kaufbar
test("MonetizationCatalog: Truemmer sind erspielt und fair", function()
	expect(MonetizationCatalog.DEBRIS_PER_POINTS > 0, "DEBRIS_PER_POINTS <= 0")
	expect(MonetizationCatalog.DEBRIS_ROUND_BONUS > 0, "DEBRIS_ROUND_BONUS <= 0")
	-- Kein Produkt darf Truemmer vergeben (grantsSkins kann nur Skins tragen,
	-- aber wir pruefen zusaetzlich, dass kein Skin-Feld Truemmer heisst).
	for key, def in MonetizationCatalog.DEVPRODUCT_IDS do
		for _, skinId in def.grantsSkins do
			expect(string.find(skinId, "truemmer") == nil, key .. " versucht Truemmer zu verkaufen")
		end
	end
	-- Mindestens ein Skin ist fuer Truemmer erhaeltlich (Free-Progression).
	local debrisSkins = 0
	for _, skin in SkinCatalog.Skins do
		if skin.priceDebris ~= nil then
			debrisSkins += 1
		end
	end
	expect(debrisSkins >= 4, "zu wenige Truemmer-Skins fuer Free-Spieler: " .. debrisSkins)
end)

-- 15) Solo-Modus
test("GameConfig: Solo-Modus ist an und startet zuegig", function()
	expect(GameConfig.SOLO_MODE_ENABLED == true, "Solo-Modus muss aktiviert sein")
	expect(GameConfig.SOLO_START_WAIT_SECONDS > 0, "Solo-Wartezeit <= 0")
	expect(
		GameConfig.SOLO_START_WAIT_SECONDS <= GameConfig.LOBBY_COUNTDOWN_SECONDS,
		"Solo-Start darf nicht laenger warten als der Multiplayer-Countdown"
	)
	expect(GameConfig.LOBBY_MIN_PLAYERS == 2, "Multiplayer-Start bleibt bei 2 Spielern")
end)

-- 16) Polish-Konstanten (Meilenstein 4)
test("GameConfig: Finale, Sabotage und Stabilitaets-Feedback", function()
	expect(GameConfig.FINALE_SECONDS == 15, "Finale != letzte 15 s")
	expect(GameConfig.FINALE_SECONDS < GameConfig.BUILD_SECONDS, "Finale laenger als die Bauphase")
	expect(GameConfig.SABOTAGE_COOLDOWN_SECONDS == 10, "Sabotage-Cooldown != 10 s")
	expect(GameConfig.SABOTAGE_SUPPORT_MAX_DROP > 0, "Sabotage-Stuetzhoehe unplausibel")
	expect(GameConfig.STABILITY_BROADCAST_SECONDS > 0, "Stabilitaets-Takt unplausibel")
	expect(GameConfig.STABILITY_SPEED_FOR_ZERO > 0, "Stabilitaets-Skala unplausibel")
end)

-- 17) Level-Kurve
test("LevelLogic: Kurve steigt monoton und startet bei Level 1", function()
	expect(LevelLogic.levelForXp(0) == 1, "0 XP muss Level 1 sein")
	expect(LevelLogic.levelForXp(99) == 1, "99 XP muss noch Level 1 sein")
	expect(LevelLogic.levelForXp(100) == 2, "100 XP muss Level 2 sein")
	expect(LevelLogic.levelForXp(250) == 3, "100+150 XP muss Level 3 sein")
	expect(LevelLogic.levelForXp(-50) == 1, "negative XP duerfen nicht crashen")
	-- Monotonie-Stichprobe.
	local last = 0
	for xp = 0, 5000, 100 do
		local level = LevelLogic.levelForXp(xp)
		expect(level >= last, "Level darf nie sinken")
		last = level
	end
	-- Fortschritts-Anzeige liefert plausible Werte.
	local current, needed = LevelLogic.progressInLevel(120)
	expect(current == 20 and needed == 150, "progressInLevel(120) falsch")
end)

-- 18) Goldrausch: goldene Teile zaehlen mehrfach
test("ScoreLogic: Gold-Multiplikator wirkt nur auf ueberlebende Teile", function()
	local pieces = {
		{ ownerUserId = 100, heightAboveBase = 10, fallen = false, multiplier = 3 },
		{ ownerUserId = 100, heightAboveBase = 10, fallen = false },
		{ ownerUserId = 100, heightAboveBase = 10, fallen = true, multiplier = 3 },
	}
	local scores = ScoreLogic.computeScores(pieces, {})
	expect(scores[100] == 30 + 10, "Gold muss 3-fach zaehlen, gefallenes Gold gar nicht: " .. tostring(scores[100]))
end)

-- 19) Katastrophen- und XP-Konstanten
test("GameConfig: Katastrophen und XP sind plausibel konfiguriert", function()
	expect(GameConfig.DISASTER_WARNING_SECONDS >= 2, "Vorwarnzeit zu kurz (unfair)")
	expect(GameConfig.DISASTER_MIN_GAP_SECONDS >= 20, "Events zu dicht")
	expect(GameConfig.DISASTER_CHANCE_PER_CHECK > 0 and GameConfig.DISASTER_CHANCE_PER_CHECK < 1, "Event-Chance ausserhalb (0,1)")
	expect(GameConfig.DISASTER_BLAME_GRACE_SECONDS > 0, "Schuld-Schonfrist fehlt")
	expect(GameConfig.GOLD_SCORE_MULTIPLIER >= 2, "Gold-Multiplikator zu klein")
	expect(GameConfig.GOLDRUSH_WINDOW_SECONDS > 0, "Goldrausch-Fenster fehlt")
	expect(GameConfig.XP_ROUND_BONUS > 0 and GameConfig.XP_PER_POINT > 0, "XP-Vergabe unplausibel")
end)

table.insert(results, "")
table.insert(results, "ERGEBNIS: " .. passed .. " bestanden, " .. failed .. " fehlgeschlagen (" .. (passed + failed) .. " Tests)")
return table.concat(results, "\\n"), failed
`;

const state = await LuauState.createAsync();
try {
  const fn = state.loadstring(body + tests, "turmfall-tests", true);
  const [report, failedCount] = await fn();
  console.log(report);
  if (staticErrors.length > 0) {
    console.log("\nSTATISCHER REMOTE-ABGLEICH:");
    for (const line of staticErrors) console.log("FAIL | " + line);
  } else {
    console.log("Remote-Abgleich: alle benutzten Remotes sind deklariert.");
  }
  process.exit(failedCount > 0 || staticErrors.length > 0 ? 1 : 0);
} finally {
  state.free?.();
}
