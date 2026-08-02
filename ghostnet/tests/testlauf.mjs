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

// Strukturpruefungen sollen den ECHTEN Code sehen, nicht die Kommentare.
// Sonst faellt ein Test ueber seinen eigenen Kopfkommentar
// ("benutzt KEIN PathfindingService" enthaelt das verbotene Wort).
function codeOnly(src) {
  return src
    .replace(/--\[(=*)\[[\s\S]*?\]\1\]/g, "")
    .replace(/--[^\n]*/g, "");
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

  // Wen ein Modul requiret, der darf es nicht zurueckrequiren. Das ist
  // dieselbe Aussage wie die Kreissuche, nur mit einer Fehlermeldung, die
  // direkt sagt, welche zwei Module sich verhakt haben. Ein einseitiges
  // A -> B ist ausdruecklich erlaubt (z.B. InventoryService -> MissionService).
  for (const [name, deps] of serverModules) {
    for (const dep of deps) {
      const back = serverModules.get(dep) ?? [];
      check(
        `${dep} requiret ${name} nicht zurueck`,
        !back.includes(name),
        `${name} <-> ${dep} haengen gegenseitig aneinander`
      );
    }
  }

  // --- Admin-Sicherheit (Phase E) ---
  // Diese Regeln sind der Unterschied zwischen einem Admin-Panel und einem
  // Gratis-Geldautomaten fuer Exploiter.
  const adminListPath = join(SRC, "server/AdminList.luau");
  check(
    "Admin-Liste liegt in ServerScriptService",
    sources.has(adminListPath),
    "src/server/AdminList.luau fehlt"
  );
  for (const [file] of sources) {
    const short = relative(ROOT, file);
    if (!short.startsWith("src/shared/") && !short.startsWith("src/client/")) continue;
    check(
      `keine Admin-Liste in ${short}`,
      !/AdminList/.test(codeOnly(sources.get(file))),
      "Client oder Shared kennt die Admin-Liste - die kann dann jeder lesen"
    );
  }

  const adminSrc = sources.get(join(SRC, "server/Systems/AdminService.luau"));
  if (adminSrc) {
    // Die Autorisierung muss VOR Rate-Limit und Typcheck stehen.
    const handleBody = adminSrc.split("local function handle(")[1] ?? "";
    const authAt = handleBody.indexOf("AdminList.IsAdmin");
    const limitAt = handleBody.indexOf("RateLimiter.Check");
    check("Admin-Handler prueft die UserId", authAt >= 0, "keine IsAdmin-Pruefung");
    check(
      "UserId-Pruefung steht vor allem anderen",
      authAt >= 0 && (limitAt < 0 || authAt < limitAt),
      "Rate-Limit wird vor der Autorisierung geprueft"
    );
    check(
      "Admin-Befehle werden protokolliert",
      /warn\(/.test(adminSrc) && /audit\(/.test(adminSrc),
      "keine Protokollierung"
    );
    check(
      "gefaehrliche Befehle sind auf Studio beschraenkt",
      /command\.StudioOnly and not AdminList\.IsStudioOnlyAllowed\(\)/.test(adminSrc),
      "StudioOnly wird nicht durchgesetzt"
    );
    // Geld, Trace und Story duerfen live nicht anfassbar sein.
    for (const name of ["SetCrypto", "SetRig", "SetTrace", "Bust", "ResetStory", "SetMission"]) {
      const block = adminSrc.split(`COMMANDS.${name} = {`)[1]?.slice(0, 120) ?? "";
      check(`${name} ist StudioOnly`, /StudioOnly = true/.test(block), "waere live erreichbar");
    }
  }

  // Handel: der Server darf nie einen Preis vom Client uebernehmen.
  const invSrc = sources.get(join(SRC, "server/Systems/InventoryService.luau"));
  if (invSrc) {
    check(
      "InventoryService liest keinen Preis aus dem Client-Paket",
      !/payload[^\n]*\.(Price|Cost|Unit|Total)/.test(invSrc),
      "es wird ein Preisfeld aus dem Payload gelesen"
    );
    check(
      "Handelspreise kommen vom MarketService",
      /MarketService\.GetBuyPrice/.test(invSrc) && /MarketService\.GetSellPrice/.test(invSrc),
      "Preisquelle fehlt"
    );
    check(
      "Darknet ist serverseitig hinter dem Unlock",
      /MissionService\.HasUnlock\(player, Config\.Market\.RequiredUnlock\)/.test(invSrc),
      "Unlock wird nicht geprueft"
    );
  }

  // --- Fahrzeuge (Open-World Phase 1) ---
  // Der Client besitzt die Fahrzeugphysik (Netzwerkbesitz). Genau deshalb
  // darf keine Belohnung an einer gemeldeten Position oder Geschwindigkeit
  // haengen.
  for (const [file, src] of sources) {
    const short = relative(ROOT, file);
    if (!short.startsWith("src/server/")) continue;
    const suspicious = [...src.matchAll(/payload[^\n]*\.(Position|Velocity|Speed|CFrame|Distance)\b/g)];
    check(
      `${short} liest keine Position aus dem Client-Paket`,
      suspicious.length === 0,
      suspicious.map((m) => m[0]).join(", ")
    );
  }

  const chassisSrc = sources.get(join(SRC, "server/Systems/VehicleChassis.luau"));
  if (chassisSrc) {
    check(
      "Netzwerkbesitz geht beim Einsteigen an den Fahrer",
      /SetNetworkOwner\(player\)/.test(chassisSrc),
      "ohne das faehrt sich das Auto wie durch Sirup"
    );
    check(
      "Netzwerkbesitz geht beim Aussteigen zurueck",
      /setOwner\(model, nil\)/.test(chassisSrc),
      "ein weggegangener Client behielte die Kontrolle"
    );
    check(
      "Chassis vergibt selbst keine Belohnung",
      !/AwardBanked|AwardUnsold|SpendBanked/.test(codeOnly(chassisSrc)),
      "Fahrzeugcode darf kein Geld bewegen"
    );
    check(
      "Federung ueber SpringConstraint",
      /Instance\.new\("SpringConstraint"\)/.test(chassisSrc),
      "fehlt"
    );
    check(
      "Antrieb und Lenkung ueber CylindricalConstraint",
      (chassisSrc.match(/Instance\.new\("CylindricalConstraint"\)/g) ?? []).length >= 2,
      "es fehlt eine der beiden Achsen"
    );
  }

  // --- Nachschub: Minispiele, Generator, Tagesziele, Ranglisten ---
  for (const name of ["CodeCrack", "SignalMatch"]) {
    const src = sources.get(join(SRC, `server/Systems/Minigames/${name}.luau`));
    if (!src) continue;
    const code = codeOnly(src);
    check(
      `${name} haelt die Minispiel-Schnittstelle ein`,
      new RegExp(`function ${name}\\.Generate`).test(code)
        && new RegExp(`function ${name}\\.Input`).test(code)
        && new RegExp(`function ${name}\\.Label`).test(code),
      "HackService kann das Minispiel nicht aufrufen"
    );
    check(
      `${name} schickt die Loesung nicht an den Client`,
      !/public\.Code|public\.Frequency|public\.Amplitude|public\.Phase/.test(code),
      "der publicState enthaelt die Loesung"
    );
  }
  {
    const contracts = sources.get(join(SRC, "server/Systems/ContractService.luau"));
    if (contracts) {
      const code = codeOnly(contracts);
      check(
        "Tagesziele benutzen os.time(), nicht os.clock()",
        /os\.time\(\)/.test(code) && !/os\.clock\(\)/.test(code),
        "os.clock faengt bei jedem Serverstart neu an - dann gibt es nach jedem Wechsel neue Auftraege"
      );
      check(
        "Tagesziele wuerfeln pro Spieler und Tag reproduzierbar",
        /Random\.new\(player\.UserId/.test(code),
        "durch Serverwechsel liessen sich neue Auftraege erwuerfeln"
      );
      check(
        "Belohnung laeuft ueber den EconomyService",
        /EconomyService\.Award/.test(code),
        "es entsteht ein zweiter Weg, Geld zu erzeugen"
      );
    }
    const board = sources.get(join(SRC, "server/Systems/LeaderboardService.luau"));
    if (board) {
      check(
        "Die Rangliste fasst keinen DataStore selbst an",
        !/DataStoreService/.test(codeOnly(board)),
        "nur SaveService spricht mit einem DataStore"
      );
    }
    const gen = sources.get(join(SRC, "server/World/WorldGenerator.server.luau"));
    if (gen) {
      const code = codeOnly(gen);
      check(
        "Der Generator klont Vorlagen statt Ziele zu bauen",
        /AssetLibrary\.Clone\(/.test(code),
        "erzeugt sichtbare Geometrie selbst"
      );
      check(
        "Der Generator hat eine harte Obergrenze",
        /MaxTargets/.test(code),
        "eine unbegrenzte Zielzahl frisst Registry und Bildrate"
      );
    }
  }

  // --- Orientierung, Story, Polizei ---
  {
    const route = sources.get(join(SRC, "server/Systems/RouteService.luau"));
    if (route) {
      check(
        "Die Route laeuft ueber den bestehenden Strassengraphen",
        /RoadNetwork\.RouteBetween/.test(codeOnly(route)),
        "ein zweites Wegenetz wuerde vom ersten abweichen"
      );
    }
    const markers = sources.get(join(SRC, "client/World/RouteMarkers.client.luau"));
    if (markers) {
      check(
        "Die Leuchtspur wird lokal gebaut, nicht serverseitig",
        /Enum\.Material\.Neon/.test(codeOnly(markers)),
        "serverseitige Route-Parts saehe jeder Spieler"
      );
    }
    const arrest = sources.get(join(SRC, "server/Systems/ArrestService.luau"));
    if (arrest) {
      const code = codeOnly(arrest);
      check(
        "Festnahme benutzt die bestehenden Systeme",
        /EconomyService\.WipeUnsold/.test(code)
          && /InventoryService\.ConfiscateFraction/.test(code)
          && /Config\.Trace\.AfterBust/.test(code),
        "es entsteht ein zweites Straf-System neben dem Bust"
      );
      check(
        "Festnahme braucht eine echte Wache",
        /PoliceStationTag/.test(code),
        "ohne Ort ist eine Festnahme nur ein Bildschirmtext"
      );
      check(
        "Keine Waffen bei der Festnahme",
        !/Tool|Weapon|TakeDamage|Damage/i.test(code),
        "bewusste Design-Entscheidung: kein Kampf"
      );
    }
    const pursuit = sources.get(join(SRC, "server/Systems/PursuitService.luau"));
    if (pursuit) {
      const code = codeOnly(pursuit);
      check(
        "Polizisten steigen aus und verfolgen zu Fuss",
        /PathfindingService/.test(code) && /Instance\.new\("Humanoid"\)/.test(code),
        "eine Verfolgung, aus der man einfach aussteigt, ist keine"
      );
      check(
        "Der Pfad wird nur getaktet neu gerechnet",
        /OfficerRepath/.test(code),
        "eine Wegsuche pro Frame bricht den Server"
      );
      check(
        "Die Verfolgung endet spaetestens nach MaxDuration",
        /MaxDuration/.test(code),
        "niemand darf ewig gejagt werden"
      );
    }
  }

  // --- Karte ---
  {
    const map = sources.get(join(SRC, "server/Systems/MapService.luau"));
    if (map) {
      const code = codeOnly(map);
      check(
        "Die Karte kommt vom Server, nicht aus dem Workspace des Clients",
        /Remotes\.MapSync:FireClient/.test(code),
        "mit StreamingEnabled saehe der Client nur, was ohnehin geladen ist"
      );
      check(
        "Die Karte verraet keine Raetseldaten",
        !/Difficulty|solution|Solution|serverState/.test(code),
        "die Karte sagt WO etwas steht, nicht WIE man es knackt"
      );
      check(
        "Kartendaten werden gebuendelt gesendet",
        /SyncDebounce/.test(code),
        "der Weltaufbau wuerde hunderte Pakete feuern"
      );
    }
    const ui = sources.get(join(SRC, "client/UI/MapUI.client.luau"));
    if (ui) {
      const code = codeOnly(ui);
      check(
        "Die Karte braucht keine Bild-Assets",
        !/rbxassetid|Image\s*=/.test(code),
        "eine Karte, die auf eine hochgeladene Textur wartet, funktioniert nicht"
      );
      check(
        "Die Minikarte verschiebt einen Container statt hundert Frames",
        /miniWorld\.Position = /.test(code),
        "jede Strasse einzeln pro Bild zu setzen kostet unnoetig Bildrate"
      );
    }
  }

  // --- Asset-Pipeline: Code platziert Geometrie, Code baut keine ---
  // Sichtbares kommt als Vorlage aus ReplicatedStorage/Assets. Instance.new
  // fuer Parts ist nur noch erlaubt, wo es niemand ansieht: Kollisionsboxen,
  // Trigger, Wegpunkte, Radtraeger - und im ausdruecklichen Platzhalterpfad.
  {
    const chassis = sources.get(join(SRC, "server/Systems/VehicleChassis.luau"));
    if (chassis) {
      const code = codeOnly(chassis);
      check(
        "Ein fertiges Modell hat Vorrang vor der gebauten Karosserie",
        /AssetLibrary\.Has\("Vehicles"/.test(code),
        "ein hochgeladenes Modell wuerde ignoriert"
      );
      check(
        "Die gebaute Karosserie hat eine echte Silhouette",
        /Windscreen/.test(code) && /Cabin/.test(code) && /Arch/.test(code),
        "aus zwei Kaesten wird nie ein Auto"
      );
      check(
        "Raeder werden nicht fehlrotiert",
        !/Shape = Enum\.PartType\.Cylinder[\s\S]{0,400}CFrame\.Angles\(0, 0, math\.rad\(90\)\)/.test(code),
        "ein Roblox-Zylinder dreht um seine lokale X-Achse - eine Drehung legt das Rad flach"
      );
      check(
        "Keine unendliche Winkelbeschleunigung",
        !/MotorMaxAngularAcceleration = math\.huge/.test(code),
        "math.huge erzeugt im Solver ein NaN und schleudert die Baugruppe ins Nichts"
      );
      check(
        "Feder und Fuehrung teilen sich kein Attachment-Paar",
        /SpringTop/.test(code) && /GuideTop/.test(code),
        "zwei Limit-Solver auf einem Freiheitsgrad schaukeln sich auf"
      );
      check(
        "Verkehr und Polizei benutzen denselben Bauplan",
        /function VehicleChassis\.BuildShell/.test(code),
        "sonst wechselt ein gestohlenes Auto beim Kurzschliessen die Form"
      );
      check(
        "VehicleChassis prueft den Modellvertrag",
        /AssetLibrary\.Verify\(/.test(code),
        "ein Modell mit fehlendem Teil wuerde still halb funktionieren"
      );
      check(
        "VehicleChassis nennt bei fehlenden Teilen Modell und Teil",
        /Fehlende Teile/.test(chassis),
        "ohne klare Meldung sucht man den Fehler im Fahrverhalten"
      );
      check(
        "Nur das Chassis kollidiert",
        /CanCollide = false/.test(code) && /makeCosmetic/.test(code),
        "jedes Karosserieteil kollidiert - das Auto haengt an jeder Kante fest"
      );
      check(
        "Raeder haben eine eigene CollisionGroup",
        /WheelCollisionGroup/.test(code),
        "zwei Autos verhaken sich, sobald sie sich beruehren"
      );
    }
  }

  for (const [file, src] of sources) {
    const short = relative(ROOT, file);
    if (!short.startsWith("src/server/World/")) continue;
    // World-Skripte stellen hin, was AssetLibrary liefert. Eigene Geometrie
    // fuer Sichtbares gibt es dort nicht mehr - Ausnahme sind die Strassen
    // selbst (Kollision und Genauigkeit statt Aussehen) und Trigger.
    if (/City\.server/.test(short)) {
      check(
        `${short} stapelt Module statt Kloetze zu bauen`,
        /AssetLibrary\.Clone\(/.test(codeOnly(src)),
        "erzeugt Gebaeudegeometrie selbst"
      );
    }
  }

  {
    const lib = sources.get(join(SRC, "shared/AssetLibrary.luau"));
    if (lib) {
      const code = codeOnly(lib);
      check(
        "Fehlende Vorlagen werden zu erkennbaren Platzhaltern",
        /MISSING_ASSET_/.test(code),
        "eine fehlende Vorlage verschwindet stillschweigend"
      );
      check(
        "Fehlende Vorlagen werden gesammelt gemeldet",
        /function AssetLibrary\.Report/.test(code) && /function AssetLibrary\.Missing/.test(code),
        "Noah erfaehrt nie, was noch zu bauen ist"
      );
    }
  }

  // --- Bewegte Modelle: PivotTo statt Einzelteil-CFrame ---
  // Der Dach-Bug: eine WeldConstraint zwischen zwei Anchored-Teilen tut
  // nichts, und .CFrame auf einem Einzelteil nimmt den Rest des Modells
  // nicht mit. Beides darf in den bewegenden Systemen nicht wieder auftauchen.
  for (const name of ["TrafficService", "PursuitService", "GuardService"]) {
    const src = sources.get(join(SRC, `server/Systems/${name}.luau`));
    if (!src) continue;
    const code = codeOnly(src);
    check(
      `${name} bewegt Modelle ueber PivotTo`,
      /:PivotTo\(/.test(code),
      "bewegt Einzelteile statt Modelle - der Rest bleibt stehen"
    );
    check(
      `${name} setzt keine Einzelteil-CFrame beim Bewegen`,
      !/\b(car|walker|unit|guard)\.\w*\.CFrame\s*=/.test(code),
      "ein Einzelteil wird direkt bewegt, das Modell folgt nicht"
    );
    check(
      `${name} verschweisst keine Anchored-Teile`,
      !/Instance\.new\("WeldConstraint"\)/.test(code),
      "WeldConstraint zwischen Anchored-Teilen tut nichts und taeuscht Sicherheit vor"
    );
  }
  {
    const src = sources.get(join(SRC, "server/World/BankInterior.server.luau"));
    if (src) {
      check(
        "BankInterior verschweisst keine Anchored-Teile",
        !/Instance\.new\("WeldConstraint"\)/.test(codeOnly(src)),
        "die Wache wuerde ihren Kopf an der Startposition stehen lassen"
      );
    }
  }

  // --- Helle Stadt: Farben kommen aus der Palette, nicht aus dem Skript ---
  for (const [file, src] of sources) {
    const short = relative(ROOT, file);
    if (!short.startsWith("src/server/World/")) continue;
    check(
      `keine eigene Farbe in ${short}`,
      !/Color3\.(fromRGB|new)\s*\(/.test(codeOnly(src)),
      "Weltfarben gehoeren in Config.Palette - sonst muss man zum Umfaerben jede Datei anfassen"
    );
  }

  // Der Ertragsfaktor aus Mission 10 wurde einmal angemeldet und dann nie
  // angewendet. Das faellt niemandem auf - also prueft es der Testlauf.
  const hackSrc = sources.get(join(SRC, "server/Systems/HackService.luau"));
  if (hackSrc) {
    check(
      "angemeldete Ertragsfaktoren werden auch angewendet",
      /combined\(rewardModifiers, player\)/.test(codeOnly(hackSrc)),
      "AddRewardModifier existiert, wird aber nie eingerechnet"
    );
    check(
      "angemeldete Trace-Faktoren werden auch angewendet",
      /combined\(traceModifiers, player\)/.test(codeOnly(hackSrc)),
      "AddTraceModifier existiert, wird aber nie eingerechnet"
    );
    check(
      "Deckung wirkt auf Ertrag UND Trace",
      /ExposedRewardBonus/.test(codeOnly(hackSrc)) && /ExposedTraceFactor/.test(codeOnly(hackSrc)),
      "eine der beiden Seiten des Tauschs fehlt im HackService"
    );
  }

  // --- Verkehr und Polizei (Open-World 3 und 6) ---
  const trafficSrc = sources.get(join(SRC, "server/Systems/TrafficService.luau"));
  if (trafficSrc) {
    check(
      "Verkehr benutzt KEIN PathfindingService",
      !/PathfindingService/.test(codeOnly(trafficSrc)),
      "ein Pfad pro Auto frisst den Server auf"
    );
    check(
      "Verkehr benutzt keine Humanoids",
      !/Instance\.new\("Humanoid"\)/.test(codeOnly(trafficSrc)),
      "Humanoids sind fuer Hintergrund-Fussgaenger zu teuer"
    );
    check(
      "Verkehr laeuft ueber einen Pool",
      /not car\.Active/.test(trafficSrc) && /recycle\(/.test(trafficSrc),
      "kein Recycling - Instance.new im Sekundentakt"
    );
    check(
      "Verkehr ist auf einen Radius begrenzt",
      /nearAnyPlayer\([^)]*ActiveRadius\)/.test(trafficSrc),
      "Autos ausserhalb des Radius werden weiterberechnet"
    );
  }

  const pursuitSrc = sources.get(join(SRC, "server/Systems/PursuitService.luau"));
  if (pursuitSrc) {
    check(
      "Polizei benutzt die bestehende Bust-Kette",
      /TraceService\.Add\(player, Config\.Trace\.Max\)/.test(pursuitSrc),
      "es gibt ein zweites Straf-System daneben"
    );
    check(
      "Keine Waffen in der Verfolgung",
      !/Tool|Weapon|Damage|TakeDamage|Fire\(/i.test(codeOnly(pursuitSrc)),
      "bewusste Design-Entscheidung: kein Kampf"
    );
  }

  const guardSrc = sources.get(join(SRC, "server/Systems/GuardService.luau"));
  if (guardSrc) {
    check(
      "Wachen melden statt anzugreifen",
      /RaidService\.RaiseAlarm/.test(guardSrc) && !/TakeDamage/.test(codeOnly(guardSrc)),
      "eine Wache greift an"
    );
    check(
      "Sichtlinie wird per Raycast geprueft",
      /workspace:Raycast/.test(guardSrc),
      "Waende blockieren die Sicht nicht"
    );
  }

  // Kein Heartbeat-Handler, der ueber die ganze Stadt laeuft.
  for (const name of ["TrafficService", "PursuitService", "GuardService"]) {
    const src = sources.get(join(SRC, `server/Systems/${name}.luau`));
    if (!src) continue;
    check(
      `${name} benutzt einen gestaffelten Tick statt Heartbeat`,
      !/RunService\.Heartbeat/.test(codeOnly(src)),
      "laeuft jeden Frame ueber alle Objekte"
    );
  }

  // --- Monetarisierung (Phase F) ---
  const monSrc = sources.get(join(SRC, "server/Systems/MonetizationService.luau"));
  if (monSrc) {
    const idBlock = monSrc.split("local IDS = {")[1]?.split("\n}")[0] ?? "";
    const ids = [...idBlock.matchAll(/^\s*(\w+)\s*=\s*(\d+)/gm)];
    check("Gamepass- und Produkt-IDs sind vorhanden", ids.length >= 6, `nur ${ids.length} gefunden`);
    for (const [, name, value] of ids) {
      check(`${name} ist noch 0 (keine erfundene ID)`, value === "0", `steht auf ${value}`);
    }

    // ProcessReceipt: erst merken und speichern, dann bestaetigen.
    const receipt = monSrc.split("local function processReceipt(")[1]?.split("\nend")[0] ?? "";
    const logAt = receipt.indexOf("table.insert(profile.PurchaseLog");
    const saveAt = receipt.indexOf("SaveService.SaveNow");
    const grantAt = receipt.lastIndexOf("ProductPurchaseDecision.PurchaseGranted");
    check("Beleg wird vor der Bestaetigung protokolliert", logAt >= 0 && logAt < grantAt, "PurchaseLog fehlt");
    check("Es wird vor der Bestaetigung gespeichert", saveAt >= 0 && saveAt < grantAt, "SaveNow fehlt");
    check(
      "Doppelbeleg wird erkannt",
      /table\.find\(profile\.PurchaseLog, purchaseId\)/.test(receipt),
      "keine Pruefung auf bereits verarbeitete PurchaseId"
    );
    check(
      "Fehlschlag bestaetigt NICHT",
      /not saved[\s\S]{0,400}NotProcessedYet/.test(receipt),
      "ein fehlgeschlagener Save wuerde den Beleg verbrauchen"
    );
    check(
      "Besitzpruefung nimmt bei Fehler nicht 'besitzt nichts' an",
      /checkFailed\[player\]\[passKey\] = true/.test(monSrc),
      "ein Fehler wuerde als 'kein Gamepass' durchgehen"
    );
  }

  // Es darf nirgends eine erfundene Asset-Id stehen.
  for (const [file, src] of sources) {
    const short = relative(ROOT, file);
    check(`keine erfundene Asset-Id in ${short}`, !/rbxassetid:\/\/\d/.test(codeOnly(src)), "enthaelt eine konkrete Asset-Id");
  }

  // Sound-IDs bleiben leer, bis Noah sie eintraegt.
  const soundSrc = sources.get(join(SRC, "shared/SoundCatalog.luau"));
  if (soundSrc) {
    const idsBlock = soundSrc.split("SoundCatalog.Ids = {")[1]?.split("\n}")[0] ?? "";
    const entries = [...idsBlock.matchAll(/^\s*(\w+)\s*=\s*"([^"]*)"/gm)];
    check("SoundCatalog hat Eintraege", entries.length >= 15, `nur ${entries.length}`);
    for (const [, name, value] of entries) {
      check(`Sound ${name} ist leer`, value === "", `steht auf "${value}"`);
    }
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
-- Color3 wie in Roblox: R/G/B liegen zwischen 0 und 1, fromRGB rechnet von
-- 0..255 um. Der Unterschied ist wichtig, sobald ein Test rechnet statt nur
-- zu vergleichen (z.B. die Helligkeit der Weltpalette).
local Color3
local function makeColour(r, g, b)
	local colour = { R = r, G = g, B = b, kind = "Color3" }
	function colour:Lerp(other, alpha)
		return makeColour(
			self.R + (other.R - self.R) * alpha,
			self.G + (other.G - self.G) * alpha,
			self.B + (other.B - self.B) * alpha
		)
	end
	return colour
end
Color3 = {
	fromRGB = function(r, g, b) return makeColour(r / 255, g / 255, b / 255) end,
	new = function(r, g, b) return makeColour(r or 0, g or 0, b or 0) end,
}
local Vector3 = {
	new = function(x, y, z) return { X = x or 0, Y = y or 0, Z = z or 0, kind = "Vector3" } end,
	zero = { X = 0, Y = 0, Z = 0, kind = "Vector3" },
}
-- Die Module pruefen mit typeof(v) == "Vector3". In der reinen Luau-VM sind
-- die Stubs Tabellen, also muss typeof das hier wissen - sonst testen wir
-- etwas anderes als das, was in Roblox laeuft.
local rawTypeof = typeof
local function typeof(value)
	if type(value) == "table" and rawget(value, "kind") ~= nil then
		return value.kind
	end
	return rawTypeof(value)
end
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
    ["Goods", "shared/Goods.luau"],
    ["Vehicles", "shared/Vehicles.luau"],
    ["Districts", "shared/Districts.luau"],
    ["NodeBreach", "server/Systems/Minigames/NodeBreach.luau"],
    ["CodeCrack", "server/Systems/Minigames/CodeCrack.luau"],
    ["SignalMatch", "server/Systems/Minigames/SignalMatch.luau"],
  ]) {
    body += `\n__deps["${name}"] = (function()\n${loadModule(path)}\nend)()\n`;
  }

  const luaTests = `
local Config = __deps["Config"]
local Missions = __deps["Missions"]
local Goods = __deps["Goods"]
local Vehicles = __deps["Vehicles"]
local Districts = __deps["Districts"]
local NodeBreach = __deps["NodeBreach"]
local CodeCrack = __deps["CodeCrack"]
local SignalMatch = __deps["SignalMatch"]

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

--== Darknet-Markt (Phase C) ===============================================

test("Warenkatalog ist gueltig", function()
	local valid, errors = Goods.Validate()
	expect(valid, "Katalog kaputt: " .. table.concat(errors, " | "))
	expect(Goods.Count() >= 4, "zu wenige Waren fuer einen Markt")
end)

test("Validate findet kaputte Waren", function()
	local function broken(list)
		local valid = Goods.Validate(list)
		return not valid
	end
	local good = { Id = "A", Name = "A", Blurb = "", Base = 100, Volatility = 0.05, Risk = 0.1, Group = "G" }
	local function with(overrides)
		local copy = table.clone(good)
		for key, value in overrides do
			copy[key] = value
		end
		return { copy }
	end

	expect(broken({ good, table.clone(good) }), "doppelte Id durchgelassen")
	expect(broken(with({ Base = 0 })), "Base 0 durchgelassen")
	expect(broken(with({ Volatility = 0 })), "Volatility 0 durchgelassen")
	expect(broken(with({ Volatility = 0.9 })), "absurde Volatility durchgelassen")
	expect(broken(with({ Risk = 1.5 })), "Risk ueber 1 durchgelassen")
	expect(broken(with({ Group = "" })), "fehlende Group durchgelassen")
	local valid = Goods.Validate({ good })
	expect(valid, "gueltige Ware abgelehnt")
end)

test("Kaufpreis liegt immer ueber dem Verkaufspreis", function()
	-- Ohne Spanne koennte man ohne jede Kursbewegung durch reines
	-- Hin-und-Her Geld drucken.
	for _, good in Goods.List do
		for _, factor in { Config.Market.MinFactor, 0.8, 1.0, 1.4, Config.Market.MaxFactor } do
			local buy = Config.GetBuyPrice(good.Base, factor)
			local sell = Config.GetSellPrice(good.Base, factor)
			expect(buy > sell, good.Id .. ": Kauf " .. buy .. " nicht ueber Verkauf " .. sell)
			expect(sell >= 1, good.Id .. ": Verkaufspreis unter 1")
		end
	end
end)

test("Ein Kurs kann sich lohnen, ohne dass er entgleist", function()
	-- Unten kaufen und oben verkaufen muss Gewinn bringen, sonst ist Handel
	-- sinnlos. Gleichzeitig darf der Kurs nicht ins Absurde laufen.
	for _, good in Goods.List do
		local low = Config.GetBuyPrice(good.Base, Config.Market.MinFactor)
		local high = Config.GetSellPrice(good.Base, Config.Market.MaxFactor)
		expect(high > low * 1.5, good.Id .. ": Handelsspanne zu klein")
		expect(Config.Market.MaxFactor <= 3, "MaxFactor zu hoch - Kurse entgleisen")
		expect(Config.Market.MeanReversion > 0, "ohne Mean Reversion driftet der Markt")
	end
end)

test("Mean Reversion zieht einen entgleisten Kurs zurueck", function()
	-- Reine Formelprobe: ohne Zufall muss der Faktor gegen 1 laufen.
	local factor = Config.Market.MaxFactor
	for _ = 1, 200 do
		factor += (1.0 - factor) * Config.Market.MeanReversion
	end
	expect(math.abs(factor - 1.0) < 0.01, "Kurs kehrt nicht zum Basispreis zurueck: " .. factor)

	factor = Config.Market.MinFactor
	for _ = 1, 200 do
		factor += (1.0 - factor) * Config.Market.MeanReversion
	end
	expect(math.abs(factor - 1.0) < 0.01, "Kurs kehrt von unten nicht zurueck: " .. factor)
end)

test("Lagerplatz waechst mit dem Rig, Faelschungsrisiko sinkt", function()
	local previousSlots = 0
	local previousRisk = math.huge
	for tier = 1, Config.Rig.MaxLevel do
		local slots = Config.GetStashSlots(tier)
		local risk = Config.GetFakeRisk(0.5, tier)
		expect(slots > previousSlots, "Lagerplatz waechst nicht bei Tier " .. tier)
		expect(risk <= previousRisk, "Risiko sinkt nicht bei Tier " .. tier)
		expect(risk >= 0, "negatives Risiko")
		previousSlots, previousRisk = slots, risk
	end
	-- Es bleibt immer ein Restrisiko, sonst waere teure Ware ab Tier 5 gratis.
	expect(Config.GetFakeRisk(0.5, 99) > 0, "Risiko faellt auf null")
end)

test("Handelsmengen sind begrenzt", function()
	expect(Config.Market.MaxPerTrade >= 1, "MaxPerTrade unbrauchbar")
	expect(Config.Market.MaxPerTrade <= Config.GetStashSlots(Config.Rig.MaxLevel),
		"man kann mehr auf einmal kaufen, als je ins Lager passt")
	expect(Config.Market.BustStashLossPercent > 0, "Bust kostet kein Lager - Handel ohne Risiko")
	expect(Config.Market.BustStashLossPercent <= 1, "Bust kostet mehr als das ganze Lager")
end)

--== Fahrzeuge (Open-World Phase 1) ========================================

test("Fahrzeugkatalog ist gueltig", function()
	local valid, errors = Vehicles.Validate()
	expect(valid, "Katalog kaputt: " .. table.concat(errors, " | "))
	expect(Vehicles.Count() >= 5, "zu wenige Klassen")
end)

test("Keine Klasse macht eine andere ueberfluessig", function()
	-- Die Leitregel aus dem Bauplan: jede Klasse braucht einen mechanischen
	-- Grund. Ein Auto, das nur schneller ist, entwertet alle anderen.
	local good = { Id = "A", Name = "A", Blurb = "", Price = 100, MaxSpeed = 50,
		Acceleration = 100, BrakeForce = 100, TurnAngle = 30, SuspensionStiffness = 100,
		Mass = 1, Grip = 1, BodySize = Vector3.new(1, 1, 1), WheelRadius = 1, WheelWidth = 1,
		Wheels = 4, Colour = nil, StashBonus = 0, HeatFactor = 1 }
	local better = table.clone(good)
	better.Id = "B"
	better.MaxSpeed = 90
	better.Acceleration = 200
	-- B ist in allem besser und nicht teurer -> muss auffallen.
	local valid = Vehicles.Validate({ good, better })
	expect(not valid, "eine dominante Klasse wurde durchgelassen")
end)

test("Validate findet kaputte Fahrzeugdaten", function()
	local base = { Id = "A", Name = "A", Asset = "A", Blurb = "", Price = 100, MaxSpeed = 50,
		Acceleration = 100, BrakeForce = 100, TurnAngle = 30, SuspensionStiffness = 100,
		Mass = 1, Grip = 1, BodySize = Vector3.new(1, 1, 1), WheelRadius = 1, WheelWidth = 1,
		Wheels = 4, Colour = nil, StashBonus = 0, HeatFactor = 1 }
	local function with(overrides)
		local copy = table.clone(base)
		for key, value in overrides do
			copy[key] = value
		end
		local valid = Vehicles.Validate({ copy })
		return not valid
	end
	expect(with({ Wheels = 3 }), "drei Raeder durchgelassen")
	expect(with({ MaxSpeed = 0 }), "MaxSpeed 0 durchgelassen")
	expect(with({ HeatFactor = 0 }), "HeatFactor 0 durchgelassen")
	expect(with({ Id = "" }), "leere Id durchgelassen")
	expect(with({ BodySize = 5 }), "BodySize als Zahl durchgelassen")
	-- Ohne Asset-Namen findet VehicleChassis nie eine Vorlage und baut
	-- fuer diese Klasse dauerhaft nur einen Platzhalter.
	expect(with({ Asset = "" }), "Klasse ohne Asset-Namen durchgelassen")
	local valid = Vehicles.Validate({ base })
	expect(valid, "gueltige Klasse abgelehnt")
end)

test("Jede Klasse hat genau eine Staerke", function()
	-- Fuer jede Klasse muss es mindestens EINEN Wert geben, in dem sie
	-- besser ist als alle anderen. Sonst gibt es keinen Grund, sie zu fahren.
	for _, class in Vehicles.List do
		local unique = false
		local checks = {
			function(a, b) return a.MaxSpeed > b.MaxSpeed end,
			function(a, b) return Vehicles.StashBonus(a.Id) > Vehicles.StashBonus(b.Id) end,
			function(a, b) return a.HeatFactor < b.HeatFactor end,
			function(a, b) return a.TurnAngle > b.TurnAngle end,
			function(a, b) return a.Grip > b.Grip end,
			function(a, b) return a.Price < b.Price end,
		}
		for _, better in checks do
			local bestAtThis = true
			for _, other in Vehicles.List do
				if other.Id ~= class.Id and not better(class, other) then
					bestAtThis = false
					break
				end
			end
			if bestAtThis then
				unique = true
				break
			end
		end
		expect(unique, class.Id .. " ist in nichts die beste Wahl - niemand faehrt sie")
	end
end)

test("Motorrad hat kein Lager, Transporter das groesste", function()
	expect(Vehicles.StashBonus("BIKE") == 0, "Motorrad transportiert Ware")
	local vanBonus = Vehicles.StashBonus("VAN")
	for _, class in Vehicles.List do
		if class.Id ~= "VAN" then
			expect(vanBonus > Vehicles.StashBonus(class.Id), "Transporter ist nicht der beste Lastesel")
		end
	end
end)

--== Licht, Deckung, Risiko ================================================

test("Der Tageszyklus bleibt als Rueckfallebene vollstaendig", function()
	-- PermanentDay schaltet ihn ab, loescht ihn aber nicht. Wer ihn wieder
	-- anschaltet, darf keine halb gepflegten Werte vorfinden.
	expect(Config.World.NightRewardBonus > 0, "Nacht braechte keinen Vorteil")
	expect(Config.World.NightSightFactor < 1, "NPCs saehen nachts genauso weit")
	expect(Config.World.DayMarketCalm < 1, "Kurse waeren tagsueber nicht ruhiger")
	expect(Config.World.DayStartHour < Config.World.NightStartHour, "Tag und Nacht ueberschneiden sich")
	expect(Config.World.DayLengthMinutes > 0, "ein Tag dauert null Minuten")
	expect(Config.World.StartClock >= 0 and Config.World.StartClock < 24, "Startzeit ausserhalb der Uhr")
	expect(Config.World.DayClock >= 0 and Config.World.DayClock < 24, "DayClock ausserhalb der Uhr")
end)

test("Der Risiko-Hebel existiert auch ohne Nacht", function()
	-- Frueher war der Bonus die Nacht. Bei dauerhaftem Tag MUSS es einen
	-- Ersatz geben, sonst ist jeder Hack gleich viel wert und die zentrale
	-- Entscheidung des Spiels faellt ersatzlos weg.
	if Config.World.PermanentDay then
		expect(Config.Cover.ExposedRewardBonus > 0,
			"kein Tag-/Nachtbonus UND kein Deckungsbonus - es gibt gar keinen Hebel mehr")
	end
end)

test("Offene Ziele sind ein Tausch, kein Geschenk", function()
	local C = Config.Cover
	expect(C.ExposedRewardBonus > 0, "offene Ziele zahlen nicht mehr")
	-- Ohne Aufpreis waere Exposed gratis Geld und jedes gedeckte Ziel tot.
	expect(C.ExposedTraceFactor > 1, "offene Ziele kosten keinen zusaetzlichen Trace")
	expect(C.DefaultGuardSight > 0, "Wachen waeren standardmaessig blind")
	expect(C.MinGuardSight > 0 and C.MinGuardSight <= C.DefaultGuardSight,
		"Untergrenze der Sichtweite unbrauchbar")
	expect(Config.Bank.IndoorSightFactor <= 1, "drinnen sehen Wachen weiter als draussen")
	expect(Config.TargetDefaults.Exposed == false,
		"Ziele waeren standardmaessig offen - dann traegt der Aufschlag alles statt der Ausnahmen")
end)

test("Vantorra ist hell", function()
	-- Die eigentliche Anforderung: die Stadt ist hell. Das ist pruefbar -
	-- jeder Weltton muss deutlich ueber dem dunklen Fake-OS liegen.
	local function luminance(colour)
		return 0.299 * colour.R + 0.587 * colour.G + 0.114 * colour.B
	end

	local darkest, darkestName = 1, ""
	local count = 0
	for name, colour in Config.Palette do
		local value = luminance(colour)
		count += 1
		if value < darkest then
			darkest, darkestName = value, name
		end
	end

	expect(count >= 10, "die Weltpalette ist unvollstaendig")
	expect(darkest > 0.35,
		("%s ist mit %.2f zu dunkel fuer eine helle Stadt"):format(darkestName, darkest))

	-- Und der Kontrast zum Terminal muss erhalten bleiben: das Fake-OS ist
	-- ausdruecklich NICHT hell geworden.
	expect(luminance(Config.Theme.Background) < 0.15, "das Fake-OS ist nicht mehr dunkel")
	expect(luminance(Config.Palette.Gehweg) - luminance(Config.Theme.Panel) > 0.4,
		"Stadt und Terminal unterscheiden sich kaum noch")
end)

test("Die Karte ist vollstaendig und lesbar", function()
	local M = Config.Map
	expect(#M.Kinds >= 5, "zu wenige Kartenarten - dann sagt die Legende nichts")

	local seen = {}
	for _, kind in M.Kinds do
		expect(typeof(kind.Id) == "string" and kind.Id ~= "", "Kartenart ohne Id")
		expect(not seen[kind.Id], "Kartenart " .. tostring(kind.Id) .. " doppelt")
		seen[kind.Id] = true
		expect(typeof(kind.Label) == "string" and kind.Label ~= "",
			kind.Id .. ": kein Text fuer die Legende")
	end

	-- Ohne diese vier Arten kann die Karte die Frage "wo ist was" nicht
	-- beantworten - der Hehler ist der wichtigste Ort im ganzen Spiel.
	for _, needed in { "FENCE", "DEALER", "GARAGE", "TARGET" } do
		expect(seen[needed], "Kartenart " .. needed .. " fehlt")
	end

	expect(M.MiniRange > 0, "die Minikarte zeigt nichts")
	expect(M.MaxTargets > 0, "keine Ziele auf der Karte")
	expect(M.SyncDebounce > 0, "Kartendaten wuerden ungebuendelt gesendet")
end)

test("Beide neuen Minispiele sind loesbar und fair", function()
	local rng = Random.new(4242)

	for difficulty = 1, 10 do
		local public, state = CodeCrack.Generate(difficulty, rng)
		expect(#state.Code == state.Length, "Code hat die falsche Laenge")
		expect(public.Length == state.Length, "Client bekommt eine andere Laenge")
		-- Der richtige Code muss als Loesung durchgehen.
		local win = CodeCrack.Input(state, { Guess = table.clone(state.Code) })
		expect(win.Solved, "der richtige Code wird nicht akzeptiert")

		-- Und Unsinn darf nichts kaputtmachen.
		local _, fresh = CodeCrack.Generate(difficulty, rng)
		expect(not CodeCrack.Input(fresh, { Guess = { 0 } }).Ok, "zu kurze Eingabe durchgelassen")
		expect(not CodeCrack.Input(fresh, "nope").Ok, "String als Eingabe durchgelassen")
	end

	for difficulty = 1, 10 do
		local public, state = SignalMatch.Generate(difficulty, rng)
		expect(#public.Target == public.Samples, "Zielkurve hat die falsche Punktzahl")
		local hit = SignalMatch.Input(state, {
			Frequency = state.Frequency,
			Amplitude = state.Amplitude,
			Phase = state.Phase,
		})
		expect(hit.Solved, "die exakte Einstellung wird nicht akzeptiert")

		local _, fresh = SignalMatch.Generate(difficulty, rng)
		expect(not SignalMatch.Input(fresh, {}).Ok, "leere Eingabe durchgelassen")
	end
end)

test("Tagesziele sind erreichbar und lohnen sich", function()
	local C = Config.Contracts
	expect(C.PerDay >= 1 and C.PerDay <= #C.Kinds,
		"mehr Auftraege pro Tag als es Arten gibt - dann kommt einer doppelt")
	for _, kind in C.Kinds do
		expect(kind.Min >= 1 and kind.Min <= kind.Max, kind.Kind .. ": Zielspanne unbrauchbar")
		expect(kind.RewardPer > 0, kind.Kind .. ": bringt nichts ein")
		expect(string.find(kind.Text, "%%d") ~= nil, kind.Kind .. ": Text ohne Platzhalter")
	end
	expect(C.StreakBonus > 0 and C.StreakCap > 0, "die Serie bringt nichts")
end)

test("Der Generator bleibt im Rahmen", function()
	local G = Config.Generator
	expect(G.MaxTargets > 0 and G.MaxTargets <= 200, "Zielzahl unbrauchbar")
	expect(#G.Archetypes >= 3, "zu wenige Zielarten - alles sieht gleich aus")
	local kinds = {}
	for _, archetype in G.Archetypes do
		expect(archetype.Asset ~= "", archetype.Id .. ": kein Asset-Name")
		kinds[archetype.HackType] = true
	end
	-- Ueber die Archetypen muessen alle drei Raetsel vorkommen, sonst
	-- begegnet man beim freien Spielen nur einem davon.
	local distinct = 0
	for _ in kinds do
		distinct += 1
	end
	expect(distinct >= 3, "nur " .. distinct .. " Raetselart(en) im Generator")
end)

test("Die Polizei ist eine Bedrohung, aber fair", function()
	local P = Config.Pursuit
	-- Aussteigen muss VOR der hoechsten Stufe passieren, sonst sieht man es nie.
	expect(P.ExitLevel >= 1 and P.ExitLevel <= P.MaxLevel, "Aussteige-Stufe unerreichbar")
	expect(P.ArrestSeconds > P.WarnSeconds,
		"es wird festgenommen, bevor gewarnt wurde - das fuehlt sich nach Willkuer an")
	expect(P.ArrestRange > 0 and P.ArrestRange < P.SpotRange, "Zugriffsreichweite unbrauchbar")
	expect(P.JailSeconds > 0, "die Zelle dauert null Sekunden")
	expect(P.MaxDuration > P.EscapeSeconds,
		"die Verfolgung endet, bevor man ueberhaupt entkommen koennte")
	-- Ein Bust darf wehtun, aber niemanden auf null setzen.
	expect(P.JailFeeFraction > 0 and P.JailFeeFraction < 1, "Gebuehr unbrauchbar")
	expect(P.JailFeeCap > 0, "Gebuehr ist nicht gedeckelt")
	expect(P.JailStashFraction > 0 and P.JailStashFraction < 1, "Lagerverlust unbrauchbar")
	expect(P.OfficerRepath > 0, "Wegsuche jeden Frame")
end)

test("Die Route ist begrenzt und loest sich auf", function()
	local M = Config.Map
	expect(M.RouteMaxNodes > 2, "Route kann keine Strecke abbilden")
	expect(M.RouteArrivalRange > 0, "die Route loest sich nie auf")
	expect(M.RouteSegment > 0, "Segmentlaenge null - unendlich viele Teile")
	expect(M.RouteFadeBehind > M.RouteTransparency,
		"hinter dem Spieler ist die Spur nicht blasser als vor ihm")
end)

test("Jede Kartenart hat ein eigenes Symbol", function()
	local seen = {}
	for _, kind in Config.Map.Kinds do
		expect(typeof(kind.Shape) == "string" and kind.Shape ~= "",
			kind.Id .. ": kein Symbol")
		seen[kind.Shape] = (seen[kind.Shape] or 0) + 1
	end
	-- Ein Symbol darf mehrfach vorkommen (Haus fuer Apartment und Garage),
	-- aber nicht alles darf dasselbe sein - sonst sagt die Legende nichts.
	local distinct = 0
	for _ in seen do
		distinct += 1
	end
	expect(distinct >= 5, "nur " .. distinct .. " verschiedene Symbole fuer alles")
end)

test("Die Karte passt zur Stadt", function()
	-- Der Ausschnitt der Minikarte darf nicht groesser sein als die Stadt,
	-- sonst zeigt sie mehr Rand als Inhalt.
	local half = (Config.City.Grid - 1) * 0.5 * Config.City.BlockSize
	expect(Config.Map.MiniRange <= half,
		("Minikarte zeigt %d Studs, die Stadt reicht nur %d weit"):format(Config.Map.MiniRange, half))
end)

test("Streaming ist an und die Radien sind plausibel", function()
	expect(Config.World.StreamingEnabled, "ohne Streaming brechen Handys bei einer grossen Karte ein")
	expect(Config.World.StreamingMinRadius > 0, "MinRadius unbrauchbar")
	expect(Config.World.StreamingTargetRadius > Config.World.StreamingMinRadius,
		"TargetRadius muss groesser sein als MinRadius")
end)

--== Stadt, Verkehr, Polizei (Open World 2, 3, 6) ==========================

test("Bezirke sind gueltig und nur einer ist ausgebaut", function()
	local valid, errors = Districts.Validate()
	expect(valid, "Bezirke kaputt: " .. table.concat(errors, " | "))
	local dense = 0
	for _, district in Districts.List do
		if district.Dense then
			dense += 1
		end
	end
	-- Der Bauplan verbietet ausdruecklich, mehrere Bezirke gleichzeitig
	-- anzufangen: eine grosse leere Stadt ist schlimmer als ein voller Block.
	expect(dense == 1, dense .. " Bezirke gleichzeitig ausgebaut - erlaubt ist einer")
end)

test("Validate findet ueberlappende oder kaputte Bezirke", function()
	local base = { Id = "A", Name = "A", Character = "", GridX = 0, GridZ = 0, Radius = 1,
		MinDifficulty = 1, MaxDifficulty = 3, Tint = nil, Neon = nil, Dense = true }
	local function broken(list)
		local valid = Districts.Validate(list)
		return not valid
	end
	local copy = table.clone(base)
	copy.Id = "B"
	expect(broken({ base, copy }), "zwei Bezirke auf demselben Block durchgelassen")

	local badRange = table.clone(base)
	badRange.MinDifficulty = 8
	badRange.MaxDifficulty = 2
	expect(broken({ badRange }), "Min groesser als Max durchgelassen")

	local noneDense = table.clone(base)
	noneDense.Dense = false
	expect(broken({ noneDense }), "kein ausgebauter Bezirk durchgelassen")
	expect(Districts.Validate({ base }), "gueltiger Bezirk abgelehnt")
end)

test("Verkehrsgrenzen sind konservativ gesetzt", function()
	-- Der Bauplan verlangt ausdruecklich: niedrig starten, mit dem
	-- MicroProfiler hochtasten. Diese Pruefung verhindert, dass jemand
	-- versehentlich 200 Autos einstellt.
	expect(Config.Traffic.MaxActive <= 40, "MaxActive zu hoch fuer den Start")
	expect(Config.Traffic.MaxPedestrians <= 40, "zu viele Fussgaenger fuer den Start")
	expect(Config.Traffic.ActiveRadius > 0, "ActiveRadius unbrauchbar")
	expect(Config.Traffic.Tick >= 0.05, "Verkehrstakt schneller als 20 Hz - zu teuer")
	expect(Config.Traffic.StealTrace > 0, "Autodiebstahl haengt nicht am Trace")
end)

test("Fahndung ist erreichbar und man kann entkommen", function()
	local P = Config.Pursuit
	expect(P.TracePerLevel * P.MaxLevel <= Config.Trace.Max,
		"die hoechste Stufe ist mit dem Trace-Maximum gar nicht erreichbar")
	expect(P.CatchRange < P.SpotRange, "gefasst werden ist weiter als gesehen werden")
	expect(P.EscapeSeconds > 0, "man kann nie entkommen")
	expect(P.Decay > 0, "die Fahndung baut sich nie ab")
	expect(P.MaxUnits >= P.MaxLevel * P.UnitsPerLevel or P.MaxUnits >= 1, "keine Streifenwagen moeglich")
	expect(P.RoadblockLevel <= P.MaxLevel and P.HelicopterLevel <= P.MaxLevel,
		"Strassensperre oder Hubschrauber sind unerreichbar")
end)

test("Der Weg ueber das Dach kostet ein besseres Rig", function()
	-- Sonst waere er immer die beste Wahl und die anderen zwei Wege tot.
	expect(Config.Bank.VentRequiredTier >= 3, "Lueftungsweg ist zu billig")
	expect(Config.Bank.VaultBoxes >= 2, "zu wenige Schliessfaecher fuer den schnellen Weg")
	expect(Config.Bank.GuardSightAngle < 180, "Wachen sehen rundum")
	expect(Config.Bank.GuardSpotSeconds > 0, "Alarm kommt sofort beim Blickkontakt")
end)

--== Die Story (Open World 7) ==============================================

test("Zehn Missionen, sauber verkettet", function()
	expect(#Missions.List == 10, "es sind " .. #Missions.List .. " Missionen statt 10")
	local valid, errors = Missions.Validate(nil, Config.Mission.MaxSteps)
	expect(valid, "Missionsdaten kaputt: " .. table.concat(errors, " | "))

	-- Jede Mission ausser der ersten hat genau einen Vorgaenger: die Story
	-- ist eine Kette, keine Verzweigung.
	for index, mission in Missions.List do
		if index == 1 then
			expect(#mission.Requires == 0, "die erste Mission hat einen Vorgaenger")
		else
			expect(#mission.Requires == 1, mission.Id .. " hat " .. #mission.Requires .. " Vorgaenger")
			expect(mission.Requires[1] == Missions.List[index - 1].Id, mission.Id .. " haengt an der falschen Mission")
		end
	end
end)

test("Jede Mission schaltet etwas dauerhaft frei", function()
	-- Die Leitregel: nie eine Mission bauen, deren Inhalt danach verschwindet.
	local seen = {}
	for _, mission in Missions.List do
		local unlock = mission.Reward.Unlock
		expect(typeof(unlock) == "string" and unlock ~= "", mission.Id .. " schaltet nichts frei")
		expect(not seen[unlock], "Unlock doppelt vergeben: " .. tostring(unlock))
		seen[unlock] = true
	end
end)

test("Briefings sind kurz - hoechstens drei Saetze", function()
	for _, mission in Missions.List do
		local sentences = 0
		for _ in string.gmatch(mission.Briefing, "[%.%!%?]") do
			sentences += 1
		end
		expect(sentences <= 3, mission.Id .. " hat " .. sentences .. " Saetze im Briefing")
		expect(#mission.Briefing <= 220, mission.Id .. ": Briefing zu lang (" .. #mission.Briefing .. " Zeichen)")
	end
end)

test("Die Endgame-Entscheidung ist ein echter Tausch", function()
	local E = Config.Endgame
	-- Kassieren: weniger Risiko, weniger Ertrag. Verbrennen: umgekehrt.
	-- Ohne diesen Tausch waere eine der beiden Seiten immer richtig.
	expect(E.CashTraceFactor < 1, "Kassieren senkt den Trace nicht")
	expect(E.CashRewardFactor < 1, "Kassieren kostet nichts - dann waehlt es jeder")
	expect(E.BurnRewardFactor > 1, "Verbrennen bringt nichts")
	expect(E.BurnPursuitFactor > 1, "Verbrennen ist nicht haerter")
	expect(E.SwitchCooldown > 0, "man koennte beliebig oft umschalten")
	expect(E.SwitchCooldown <= 7 * 24 * 3600, "laenger als eine Woche fuehlt sich wie eingesperrt an")
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
