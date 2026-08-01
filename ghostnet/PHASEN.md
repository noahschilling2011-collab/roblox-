# GHOSTNET — Bauplan

**Stand: alles abgearbeitet** — Phase 0 bis G, Open-World-Abschnitt 2 und
Phase 1 bis 7, dazu v2.1.0 „Vantorra bei Tag" (`Config.Version = "2.1.0"`).
Was jetzt ansteht, steht ganz unten unter „Offen".

Reihenfolge war bindend. Eine Phase wurde komplett fertig, bevor die nächste
anfing. Neue Minispiele ohne funktionierenden Loop sind wertlos — der Spieler
hätte dann mehr Rätsel, die zu nichts führen.

---

## Phase 0 — Prototyp ✅ (vor dieser Session vorhanden)
Config, Remotes, Types, UITheme, EconomyService, HackService, HackTargets,
HackEffects, RateLimiter, NodeBreach, TestTargets, HUD, HackUI.

---

## Phase 1 — Den Loop schließen ✅
Der Kreislauf war an vier Stellen offen: kein Verkauf, kein Shop, kein Speichern,
und der Trace wurde zwar berechnet, aber nie angewendet.

- **Bugfixes**
  - Ziel-Id-Kollision in `HackTargets.register` (Zähler prüfte die Registry nicht).
  - Cooldown-Exploit durch Rejoin (Cooldowns lagen nur im Serverspeicher).
  - `os.clock()` für Dinge, die einen Serverwechsel überleben müssen.
- `SaveService` — DataStore, Profil-Schema mit Version, Session-Lock, Autosave,
  `BindToClose`, pcall + Backoff, Kick statt leerem Profil.
- `TraceService` — Trace 0–100, passiver Abbau, Bust bei 100, `TraceSync`.
- `SellService` — Hehler-Punkte (`GhostNetFence`), Unsold → Banked abzüglich
  Gebühr, senkt den Trace.
- `ShopService` — `ShopPurchase` (RemoteFunction), vier Rig-Bauteile,
  exponentielle Preiskurve, Server rechnet den Preis selbst.

---

## Phase A — Das Missions-Rückgrat ✅
Zuerst das System, dann die Missionen.

- `Shared/Missions.luau` — Missionen sind **Daten**, kein Skript. Enthält
  Registry, Schema (`Missions.Example`) und die *puren* Regeln:
  `Validate`, `IsAvailable`, `FirstAvailable`, `Progress`, `Required`.
- `MissionService` — hält aktive Mission und Schritt im Profil, prüft
  serverseitig, schaltet Unlocks frei. Hängt sich per `HackService.OnHackResolved`
  und `SellService.OnSell` an, damit kein Modul rückwärts requiret.
- Schritt-Typen: `GOTO`, `HACK`, `SELL`, `BUY`, `WAIT`, `TALK`. Mehr nicht.
- Profil-Schema 1 → 2 (`Story`-Block) mit Migration für Altprofile.
- Remotes: `MissionSync`, `MissionAccept`, `MissionAbandon`, `MissionInteract`,
  `WaypointSync`.
- `MissionUI` — Auftragsanzeige und Wegpunkt-Marker.

Registry gefüllt in Phase B (M01–M03) und D (M04–M05).

---

## Phase B — Mission 1 bis 3: der Einstieg ✅
Leitregel für jede Mission: *sie ist gleichzeitig das Tutorial für ein System
UND schaltet dieses System dauerhaft frei.* Nie eine Mission bauen, deren
Inhalt danach verschwindet.

- **M01 „Erstes Gerät"** — Tutorial durch Tun. Übungsterminal (Difficulty 1,
  kein Trace-Risiko), HackUI erklärt sich beim ersten Öffnen im Spiel,
  Trace-Balken wird nach dem Erfolg einmalig hervorgehoben, Waypoint zum
  Hehler, Shop öffnet einmal von selbst. Skip-Button, Zustand im Profil.
  Jeder Schritt durch eine **Handlung** ausgelöst, nie durch einen Timer,
  nie zwei Hinweise gleichzeitig. → schaltet freies Hacken frei.
- **M02 „Der Laden"** — Koordinaten statt fertigem Weg, Kompass-Marker mit
  Entfernung. Begehbares Gebäude, zwei gestaffelte Ziele (Schloss D3 → Tresor
  D5), Alarm-Timer (`Config.Raid.AlarmSeconds`) ab dem Schloss.
  → `Unlock = "STORE_RAIDS"`, Läden werden wiederholbarer Zieltyp.
- **M03 „Nach Hause"** — Apartment als echter Hub (Darknet, Lager, Rig,
  Missionsübersicht), nicht als Kulisse. → schaltet den Darknet-Zugang frei.

---

## Phase C — Das Darknet: der eigentliche Loop ✅
- `MarketService` — Preise bewegen sich **serverweit** je
  `Config.Market.TickSeconds`, mit Mean Reversion (ohne die driften Preise nach
  Stunden ins Absurde). Preisverlauf als Mini-Chart, sonst ist jeder Kauf ein
  Münzwurf. Gelegentliche Events („Razzia: Ausweise +60 %"), serverweit
  angekündigt.
- `Shared/Goods.luau` — je Ware Basispreis, Volatilität, Risikowert.
- Risiko: begrenzter Lagerplatz, Ware ist **heiß** (Bust kostet einen Teil des
  Lagers, nicht nur Bargeld), Fälschungsrisiko sinkt mit dem Analyse-Modul.
- `InventoryService` — Bestand im Profil, Kauf/Verkauf **ausschließlich**
  serverseitig gerechnet. Nie einen vom Client geschickten Preis annehmen.
- Klartext-Fehlermeldungen mit konkreten Zahlen für alle `deny`-Gründe, alle
  NodeBreach-Rückmeldungen und alle Handels-Fehler.

---

## Phase D — Mission 4 und 5 ✅
- **M04 „Erste Ware"** — geführter erster Handel: kaufen, Preis beobachten,
  mit Gewinn verkaufen. Danach freier Handel.
- **M05 „Die Bank"** — Außenkamera → Sicherheitstür → Tresorraum, steigender
  Trace pro Stufe, Alarm-Timer über das Ganze, Fehlschlag = sofortiger Bust.
  Danach wiederholbar mit langem Cooldown. Attribut `RequiresTwo` am Tresorraum
  vorsehen, damit ein zweiter Spieler den Alarm verlangsamen kann.

---

## Phase E — Admin-Panel ✅
Sicherheit zuerst: UserId-Liste in einem ModuleScript in `ServerScriptService`
(**nie** in `ReplicatedStorage`), Prüfung als **erste Zeile** jedes Handlers,
zusätzlich `RunService:IsStudio()` für Geld/Trace/Profil-Reset, jede Aktion mit
`warn()` geloggt, eigener Rate-Limit-Eintrag. F2 öffnet das Panel.
Umfang: Wirtschaft, Missionen, Welt, Markt, Debug — wichtigster Punkt ist
„Profil als JSON ausgeben", ohne das debuggt man Speicherfehler blind.

---

## Phase F — Robux-Store ✅
Erst wenn A bis D laufen. `MonetizationService` mit **allen IDs auf 0**.
`UserOwnsGamePassAsync` beim Join, Ergebnis cachen; bei Fehler **nicht**
annehmen, der Spieler besitze nichts. `PromptGamePassPurchaseFinished` für
Live-Aktivierung. `ProcessReceipt` gibt `PurchaseGranted` erst zurück, **nachdem**
der Effekt gespeichert wurde; verarbeitete `PurchaseId` im Profil merken.
Nichts verkaufen, das ein Rätsel löst oder anderen schadet.

---

## Phase G — Optik ✅
Ein Stil überall über `UITheme`, Monospace für alles Technische, dezente
Scanlines, Bewegung mit Bedeutung (0,15–0,3 s, `Quart`), Touch-Ziele ≥ 44 px.
Welt: nächtliche Straßenzeile statt Baseplate, nasse Fahrbahn, Neonschilder,
Nebel. Hack-Ziele auf Distanz an pulsierendem Akzentlicht erkennbar.
`SoundCatalog` mit **leeren IDs** — Tonhöhe der Knoten-Klicks steigt mit der
Pfadlänge, Ambience wird während eines Hacks leiser.

---

## Ältere Planung (Phase 2/3 aus dem ersten Bauplan)

Diese Punkte sind in A–G aufgegangen und stehen hier nur noch als Referenz.

### Phase 2 — Die ersten 60 Sekunden
Auf Roblox entscheidet sich in unter einer Minute, ob jemand bleibt.

- `OnboardingService` — gescriptetes erstes Ziel statt Textwall. Übungs-Kamera
  (Difficulty 1) direkt vor dem Spawn, Markierung, ein Satz im HUD. Die HackUI
  erklärt sich im Spiel: Start/Exit hervorgehoben, erster gültiger Nachbar
  pulsiert. Nach dem Erfolg Pfeil zum Hehler, nach dem ersten Verkauf öffnet
  der Shop sich einmal von selbst. Profil-Flag `TutorialDone`.
  **Regel:** jeder Schritt wird durch eine Handlung ausgelöst, nie durch einen
  Timer, und nie erscheinen zwei Hinweise gleichzeitig.
- Fehlermeldungen in Klartext, mit der konkreten Zahl — für alle `deny`-Gründe
  (`RANGE`, `COOLDOWN`, `LEVEL`, `OFFLINE`, `BUSTED`, …) und alle
  Minispiel-Rückmeldungen (`NOT_ADJACENT`, `ICE`, `REVISIT`, `RELAYS_MISSING`,
  `MASKED_ICE`).
- `SoundCatalog` + Client-`SoundService`. **Alle IDs bleiben leere Strings mit
  Kommentar** — Noah trägt sie ein. Tonhöhe der Knoten-Klicks steigt mit der
  Pfadlänge, Countdown-Ticken unter 10 s, Ambience leiser während eines Hacks.

---

### Phase 3 — Gründe wiederzukommen
- `WorldGenerator` statt fest verdrahteter `TestTargets`: 25+ Ziele in vier
  Schwierigkeitszonen (1–2, 3–4, 5–6, 7+), räumlich getrennt, sodass
  Rig-Fortschritt neue Stadtteile aufschließt.
- Zwei weitere Minispiele über das bestehende Register:
  **SignalMatch** (Wellenform angleichen) und **CodeCrack** (Mastermind).
  Zuweisung über das vorhandene `HackType`-Attribut.
- `ContractService` — drei Tagesziele, Reset über `os.time()`, im Profil
  gespeichert. Stärkster und billigster Hebel für Wiederkehr.
- `leaderstats` (Banked, Tier), `OrderedDataStore`-Top-100 und eine
  „Ruhigste Hand"-Tafel (Hacks ohne einen einzigen Fehlversuch).

---

### Phase 4 — Warum zu zweit
GhostNet ist bisher ein Solo-Puzzle in einer sozialen Engine. **Eine** Option
bauen, nicht beide:

- **Option A — Co-Op (empfohlen):** Ziele mit `RequiresTwo = true`. Einer löst,
  der andere hält in Reichweite einen Störsender, der den Trace-Anstieg des
  ersten halbiert. Belohnung geteilt, pro Kopf aber höher als solo.
- **Option B — Asynchrones PvP:** eigene Basis mit ICE-Layout befestigen, andere
  brechen ein und nehmen einen Teil des Unsold. Deutlich mehr Aufwand,
  Griefing-Risiko. Nur wenn Phase 1–3 stabil laufen.

---

### Phase 5 — Monetarisierung (zuletzt)
Erst bauen, wenn Phase 1–3 laufen. Monetarisierung vor Retention verdient nichts.

- `MonetizationService` mit Konstantentabelle, **alle IDs `0`**.
  Gamepass: ColdRig (−25 % Trace), ExtraSlot, SkinPack.
  Produkt: Crypto1000, TraceReset.
- **Nichts verkaufen, das Rätsel löst.** Keine Auto-Solves, keine Hinweise.
  Erlaubt: Zeitersparnis, Kosmetik, Komfort.
- `ProcessReceipt` idempotent: verarbeitete `PurchaseId` im Profil merken,
  erst gutschreiben und speichern, dann `PurchaseGranted`.
- Kauf-Effekte laufen ausschließlich über `EconomyService`.


---

# Open-World-Umbau

Aus dem Hacking-Spiel wird eine offene Stadt. **Kein GTA-Klon mit Hacking,
sondern ein Hacking-Spiel mit offener Stadt** — der Unterschied entscheidet
jedes Detail: keine Schusswaffen, Autos sind Werkzeug statt Selbstzweck,
NPCs sind Hindernis statt Gegner, Polizei ist Verfolgung statt Schießerei.

## OW-Abschnitt 2 — Tag und Nacht ✅ *(seit v2.1.0 abgeschaltet, siehe unten)*
`TimeService`. Voller Zyklus in `Config.World.DayLengthMinutes` (24 min).
Der Server ist die Uhr, `Lighting` wird weich interpoliert.
**Mechanisch, nicht dekorativ:** nachts +35 % auf jeden Hack-Ertrag und
kürzere NPC-Sichtweite, tagsüber ruhigere Darknet-Kurse und (ab OW-Phase 4)
geöffnete Händler. `Lighting.Technology` ist über `Config.World` umschaltbar.

Der Zyklus ist gebaut, geprüft und vollständig — er ist seit v2.1.0 nur nicht
mehr eingeschaltet. `Config.World.PermanentDay = false` holt ihn zurück, ohne
dass irgendwo Code angefasst werden muss.

## OW-Phase 1 — Fahrzeuge ✅
`Shared/Vehicles.luau` (fünf Klassen als Daten) + `VehicleChassis`
(ein Chassis, viele Karosserien) + `VehicleController` (Fahrgefühl).
SpringConstraint für die Federung, CylindricalConstraint für Antrieb und
Lenkung, `SetNetworkOwner` beim Einsteigen und zurück beim Aussteigen.

## OW-Phase 2 — Die Stadt ✅
`Shared/Districts.luau` (fünf Bezirke als Daten) + `World/City.server.luau`
(baut sie aus `Config.City`) + `Systems/RoadNetwork.luau`. Nur **Altstadt**
hat `Dense = true` — die anderen vier sind angelegt, aber bewusst dünn, weil
die Regel „erst einen fertig, dann den nächsten" sonst gebrochen wäre.
Das Straßenraster ist gleichzeitig der Wegpunkt-Graph: `RoadNetwork` rechnet
Kreuzungen, Kanten und `LanePosition(from, to, alpha)` aus `Config.City`
aus — kein einziger von Hand gesetzter Wegpunkt. Häuser aus einem Modul,
`RoofAccessChance` der Häuser bekommt eine Feuerleiter aufs Dach.
`StreamingEnabled` an, Radien in `Config.World` **noch nicht gemessen**.

## OW-Phase 3 — Verkehr und Fußgänger ✅
`Systems/TrafficService.luau`. **Kein `PathfindingService`, kein `Humanoid`** —
beides wird vom Testlauf strukturell erzwungen. Autos und Fußgänger sind
`Anchored` und werden per `CFrame` zwischen zwei Graph-Knoten interpoliert,
Takt `Config.Traffic.Tick`, harte Obergrenzen `MaxActive` / `MaxPedestrians`,
Objekt-Pool statt `Instance.new` im Sekundentakt, alles außerhalb von
`ActiveRadius` wird angehalten und recycelt. Stehlen: [E] halten für
`StealHoldSeconds`, kostet `StealTrace` und gibt sofort eine Fahndungsstufe.

## OW-Phase 4 — Autohändler, Besitz, Garage ✅
`Systems/VehicleService.luau` + `World/Dealership.server.luau`.
**Schema-Migration 4 → 5**: `Profile.Garage` (Liste besessener Fahrzeuge) und
`Profile.Story.Allegiance`. Besitz liegt im Profil, `MaxSpawned` begrenzt auf
ein ausgeparktes Fahrzeug, Ausparken nur auf einem Part mit Tag
`GhostNetVehicleSpawn`. Der Händler hat Öffnungszeiten (`Config.Dealer`), die
an `TimeService` hängen. Die Ausstellungsstücke stehen **physisch** im
Showroom und sind fahrbar. Anpassung ist nur Lackierung — keine Leistungsteile.
Ein eigener Transporter erhöht über `VehicleService.StashBonus` die
Darknet-Lagerplätze; das ist der einzige Weg, auf dem ein Auto Werte anfasst.

## OW-Phase 5 — Die Bank ✅
`World/BankInterior.server.luau` + `Systems/GuardService.luau`.
Drei Ebenen, drei Wege: **leise** (Kameras vorher aus, volle Beute),
**schnell** (direkt an die Schleuse, `AlarmStarts = true`, Wettlauf gegen die
Uhr um die `VaultBoxes` Schließfächer), **von oben** (Lüftung, ohne Alarm,
braucht aber `Config.Bank.VentRequiredTier` — sonst wäre er immer richtig).
Wachen patrouillieren und prüfen Sicht per `workspace:Raycast` innerhalb
`GuardSightAngle`; sie **melden an `RaidService.RaiseAlarm` und greifen nie
an**. Die Beute ist normales Unsold — der Raub hängt komplett am Trace-System.

## OW-Phase 6 — Polizei statt Kampf ✅
`Systems/PursuitService.luau`. Stufe = `floor(Trace / TracePerLevel)` plus
Aufschlag für frische Taten, gedeckelt auf `MaxLevel` (5).
`TracePerLevel = 20`, damit `20 × 5 = 100 = Config.Trace.Max` — die höchste
Stufe ist damit überhaupt erreichbar. Streifenwagen fahren auf dem
`RoadNetwork`-Graphen, ab Stufe 4 Straßensperren, ab 5 ein Hubschrauber.
Entkommen: `EscapeSeconds` außer Sicht. Gefasst: `TraceService.Add(player,
Config.Trace.Max)` — also exakt die bestehende Bust-Kette, kein zweites
Strafsystem daneben. **Keine Waffe, kein Schaden** — auch das prüft der Testlauf.

## OW-Phase 7 — Die Story ✅
Zehn Missionen in Vantorra (`M01_FIRSTHACK` … `M10_WREN`), eine Kette ohne
Verzweigung, jede mit dauerhaftem Unlock. Die Wendung steht in M09: Wren hat
nie für dich gearbeitet, du hast für sie gearbeitet. M10 ist die Entscheidung
**Kassieren** (halber Trace, weniger Ertrag) oder **Verbrennen** (mehr Ertrag,
härtere Fahndung) — als `Profile.Story.Allegiance` gespeichert und nach
`Config.Endgame.SwitchCooldown` (eine Woche) umstellbar. Technisch hängt sie
über `HackService.AddTraceModifier` / `AddRewardModifier` am Hack — genau
andersherum, weil `HackService` `MissionService` sonst zurückrufen müsste
und ein Require-Zyklus entstünde.

---

# v2.1.0 — Vantorra bei Tag ✅

**Entscheidung von Noah:** die Stadt soll hell sein, dauerhaft Tag. Die
Benutzeroberfläche bleibt ausdrücklich das dunkle Fake-OS — der Kontrast
zwischen heller Stadt und schwarzem Terminal ist gewollt.

## Was hell wurde
Eine neue Palette `Config.Palette` hält sämtliche Weltfarben. **Kein einziges
Skript unter `src/server/World/` enthält noch einen eigenen Farbwert** — der
Testlauf lehnt jedes `Color3.fromRGB` dort ab. Die Stadt später wieder
abzudunkeln ist damit eine Änderung an einer Tabelle, nicht an sieben Dateien.

Dazu: helle Bezirks-Grundtöne (Putz, Sandstein, Glas, Beton statt fünf
Grautönen knapp über Schwarz), spiegelnde Glasfenster statt leuchtender
Neonfenster, matte statt nasser Fahrbahn, heller Untergrund in der
Place-Datei.

## Der Nachtbonus ist umgezogen — `Config.Cover`
Der wichtigste Punkt, und kein rein optischer: Die Nacht **war** eine
Mechanik (+35 % Ertrag, NPCs sehen kürzer). Ohne Ersatz wäre mit dem
Zyklus die zentrale Risiko-Entscheidung ersatzlos verschwunden.

Der Bonus hängt jetzt am **Ort** statt an der **Uhrzeit**:

| | Ertrag | Trace | Beispiele |
| --- | --- | --- | --- |
| `Exposed = true` (offene Straße) | +35 % | ×1,3 | Geldautomat am Gehweg, Fassadenkamera, Ladenfront, Bankeingang |
| gedeckt (Standard) | normal | normal | Tresor im Laden, Bankinnenraum, Lüftung, Rückseite der Lagerhalle |

Bei dauerhaftem Tag ist das sogar der ehrlichere Ort dafür: Es gibt keine
Dunkelheit mehr, in der man verschwinden könnte. Und ein *Wann* kann man
aussitzen, ein *Wohin* nicht.

Die zweite Hälfte des alten Nachtbonus — kürzere NPC-Sicht — ist genauso
umgezogen: Wachen tragen ein Attribut `SightFactor` (Bankinnenraum 0,7).
Ort statt Uhrzeit, Attribut statt Code.

## Folgeänderungen
- **Händler:** ohne Abend keine Sperrstunde — bei `PermanentDay` immer offen.
  Das Schild am Autohaus sagt das auch, statt eine Uhrzeit zu nennen, die nie
  eintritt.
- **Darknet:** `MarketVolatilityFactor` gibt bei dauerhaftem Tag 1 zurück, nicht
  `DayMarketCalm`. Der ruhige Tag war die Gegenseite einer bewegten Nacht —
  ohne Nacht wäre daraus eine dauerhafte Drosselung geworden.
- **Verkehr:** nachts lief die Stadt auf halber Dichte. Jetzt dauerhaft auf
  `Traffic.MaxActive`. **Beim Messen beachten:** das ist die doppelte Last
  gegenüber dem alten Standardzustand.
- **PointLights** an Neonschildern entfallen bei Tag ganz — bei Tageslicht
  praktisch unsichtbar und trotzdem teuer. Geschenkte Bildrate.

## Nebenbei gefunden
`HackService.AddRewardModifier` war angemeldet, wurde aber **nie eingerechnet** —
die Endgame-Entscheidung aus Mission 10 hatte damit gar keine Wirkung auf den
Ertrag. Behoben, und ein Testlauf-Eintrag verhindert jetzt, dass so etwas
wieder stillschweigend passiert.

---

## Offen — was als Nächstes sinnvoll ist

Der Bauplan aus dem Prompt ist abgearbeitet. Nichts davon ist mehr blockiert,
also gilt jetzt: **erst mit echten Spielern testen, dann weiterbauen.**

0. **Bildrate messen** — der einzige Punkt, der hier nicht abgehakt werden
   kann. Ein Luau-Testlauf kennt keine Physik und kein Rendering; die Zahl
   muss aus dem MicroProfiler in Studio kommen. Zu drehen ist dann, in dieser
   Reihenfolge: `Config.Traffic.MaxActive` (20), `MaxPedestrians` (16),
   `ActiveRadius` (320), `Config.City.LightChance` (0.25), danach erst
   `Config.World`-Streamingradien. Fahrgefühl und Physik-Stabilität sind
   genauso ungetestet — `Config.Vehicle` und die Grip-Werte in
   `Shared/Vehicles.luau` sind Startwerte, keine gemessenen.
1. **IDs eintragen** (manuell, außerhalb des Codes): Sound-Assets in
   `SoundCatalog.luau`, Gamepässe und Produkte in `MonetizationService.luau`,
   die eigene UserId in `AdminList.luau`.
2. **Zwei weitere Minispiele** — SignalMatch (Wellenform angleichen) und
   CodeCrack (Mastermind). Das Register in `HackService` steht bereits;
   Zuweisung über das vorhandene `HackType`-Attribut.
3. **Prozeduraler Weltgenerator** — 25+ Ziele in vier Schwierigkeitszonen
   statt der handgesetzten Objekte. Die Attribut-Logik bleibt gleich.
4. **Tagesziele** (`ContractService`) — drei Aufträge pro Tag, Reset über
   `os.time()`, im Profil gespeichert. Stärkster Hebel für Wiederkehr.
5. **Ranglisten** — `leaderstats` (Banked, Tier), `OrderedDataStore`-Top-100
   und eine „Ruhigste Hand"-Tafel (Hacks ohne einen einzigen Fehlversuch).
