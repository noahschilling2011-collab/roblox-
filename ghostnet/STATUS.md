# STATUS.md — Projektstand GhostNet

> Wird am Ende jeder Session aktualisiert. Erstes, was eine neue Session liest.

## Aktuelle Phase
**Alles abgearbeitet: Phase 0–G plus Open-World-Abschnitt 2 und Phase 1–7**
(`Config.Version = "2.0.0"`). Aus dem Hacking-Spiel ist ein Hacking-Spiel mit
offener Stadt geworden — Bezirke, Verkehr, Autobesitz, ein Bankraub mit drei
Wegen, eine Polizei ohne Waffen und eine 10-Missionen-Story mit Entscheidung
am Ende. Alles Bisherige läuft unverändert darunter weiter.

**Nächster Schritt: kein Code, sondern Messen und Spielen.** Siehe die
Warnung direkt darunter und Punkt 0 am Ende von `PHASEN.md`.

## ⚠️ Was ich NICHT prüfen konnte
Der Bauplan verlangt nach jeder Phase eine **gemessene Bildrate**. Das kann ich
nicht liefern und erfinde die Zahl auch nicht: Ich habe keine Roblox-Laufzeit,
nur eine Luau-VM für Syntax und Logik. Die 569 Prüfungen sagen **nichts** über
Bildrate, Fahrverhalten oder Physikstabilität aus. Das muss Noah im
MicroProfiler messen, und zwar besonders jetzt — Verkehr, Fußgänger,
Streifenwagen und eine gebaute Stadt sind zusammen der teuerste Teil des
Projekts.

Die Regler dafür stehen alle in `Config.luau` und sind bewusst niedrig
gesetzt. In dieser Reihenfolge drehen, wenn es ruckelt:
`Traffic.MaxActive` (20) → `Traffic.MaxPedestrians` (16) →
`Traffic.ActiveRadius` (320) → `City.LightChance` (0.25) →
`World`-Streamingradien.

## Fertig ✅

### Open-World Phase 2 — Die Stadt
- **`Shared/Districts.luau`** (neu) — fünf Bezirke als Daten: Altstadt, Hafen,
  Finanzviertel, Höhenzug, Industriegebiet, jeder mit Schwierigkeitsspanne
  und Gitterplatz. **Nur die Altstadt hat `Dense = true`.** Der Testlauf prüft
  das ausdrücklich: eine große leere Stadt ist schlimmer als ein voller Block,
  also darf nicht versehentlich ein zweiter Bezirk ausgebaut werden.
- **`Systems/RoadNetwork.luau`** (neu) — das Straßenraster wird aus
  `Config.City` *gerechnet*, nicht von Hand gesetzt. Kreuzungen, Kanten,
  Nachbarn und `LanePosition(fromId, toId, alpha)` (gibt Position **und**
  Fahrtrichtung zurück). Damit ist dieselbe Datenstruktur die Straße für den
  Spieler, die Spur für den Verkehr und die Route für die Polizei — es gibt
  keine zweite Version, die auseinanderlaufen könnte.
- **`World/City.server.luau`** (neu) — baut Fahrbahnen, Gehwege, Häuser,
  Leuchtreklamen und Feuerleitern aus diesem Graphen. `RoofAccessChance` der
  Häuser bekommt eine Leiter aufs Dach, damit „von oben" ein echter Weg ist.
- `StreamingEnabled` ist an; die Radien sind plausibel gesetzt, aber
  **ungemessen**.

### Open-World Phase 3 — Verkehr und Fußgänger
- **`Systems/TrafficService.luau`** (neu). Die drei harten Regeln aus dem
  Auftrag sind im Testlauf verdrahtet, nicht nur im Kommentar:
  **kein `PathfindingService`**, **kein `Humanoid`** für Hintergrund-NPCs,
  **kein `Heartbeat`** über die ganze Stadt.
- Autos und Fußgänger sind `Anchored` und werden alle `Config.Traffic.Tick`
  Sekunden per `CFrame` zwischen zwei Graph-Knoten interpoliert. Wer aus dem
  `ActiveRadius` fällt, wird angehalten und in den Pool zurückgelegt —
  `Instance.new` läuft nur beim Auffüllen des Pools, nie im Sekundentakt.
- Hinter einem langsameren Auto wird ab `StopDistance` gebremst, sonst fahren
  sie ineinander und es sieht kaputt aus.
- **Autodiebstahl:** [E] halten für `StealHoldSeconds`. Kostet `StealTrace`
  und gibt sofort eine Fahndungsstufe — der Diebstahl hängt damit an der
  zentralen Risiko-Mechanik statt daneben zu stehen.

### Open-World Phase 4 — Händler, Besitz, Garage
- **`Systems/VehicleService.luau`** (neu) — Besitz steht im Profil
  (`Profile.Garage`), Kauf und Preis ausschließlich serverseitig,
  `Config.Vehicle.MaxSpawned` erlaubt genau ein ausgeparktes Fahrzeug,
  Ausparken nur auf einem Part mit Tag `GhostNetVehicleSpawn`.
- **`World/Dealership.server.luau`** (neu) — Showroom mit **physisch
  ausgestellten**, fahrbaren Fahrzeugen statt eines Menüs mit Bildern, plus
  Garage mit Ausparkplatz. Öffnungszeiten
  (`Config.Dealer.OpenHour`/`CloseHour`) hängen am Tag-/Nachtzyklus — damit
  bekommt der Tag zum ersten Mal einen eigenen Zweck.
- Anpassung ist **nur Lackierung**. Keine Leistungsteile, sonst wäre die
  Klassenwahl aus Phase 1 sofort entwertet.
- Einziger Punkt, an dem ein Auto Werte anfasst: ein eigener Transporter gibt
  über `VehicleService.StashBonus` zusätzliche Darknet-Lagerplätze.

### Open-World Phase 5 — Die Bank
- **`World/BankInterior.server.luau`** (neu) — drei Ebenen (Schalterhalle,
  Sicherheitsbereich, Tresorraum) und **drei Wege hinein**:
  *leise* (Kameras vorher aus, wenig Trace, volle Beute),
  *schnell* (direkt an die Schleuse, `AlarmStarts = true`, die Uhr entscheidet,
  wie viele der `Config.Bank.VaultBoxes` Fächer man noch schafft),
  *von oben* (Lüftung, ohne Alarm — kostet dafür
  `Config.Bank.VentRequiredTier`, sonst wäre er immer die beste Wahl und die
  anderen zwei Wege tot).
- **`Systems/GuardService.luau`** (neu) — Wachen patrouillieren zwischen zwei
  Attribut-Punkten und prüfen Sicht per `workspace:Raycast` innerhalb
  `GuardSightAngle`. Sie **melden über `RaidService.RaiseAlarm` und greifen
  nie an**; nachts sehen sie über `TimeService.SightFactor` kürzer.
- Die Beute ist normales Unsold. Der Raub braucht kein eigenes Regelwerk —
  Trace und Hehler tragen ihn komplett.

### Open-World Phase 6 — Polizei statt Kampf
- **`Systems/PursuitService.luau`** (neu). Stufe = `floor(Trace /
  TracePerLevel)` plus Aufschlag für frische Taten, gedeckelt auf 5.
  `TracePerLevel = 20`, weil `20 × 5 = 100 = Config.Trace.Max` — mit 22 wäre
  Stufe 5 aus dem Trace allein nie erreichbar gewesen (hat der Testlauf
  gefunden).
- Streifenwagen fahren auf dem `RoadNetwork`-Graphen, ab `RoadblockLevel` (4)
  kommen Straßensperren, ab `HelicopterLevel` (5) ein Hubschrauber.
  Entkommen: `EscapeSeconds` außer Sicht. Abbau: `Decay` pro Sekunde.
- Gefasst zu werden ruft `TraceService.Add(player, Config.Trace.Max)` auf —
  also **exakt die bestehende Bust-Kette**. Kein zweites Strafsystem daneben,
  keine doppelte Buchführung.
- **Keine Waffe, kein Schaden, kein Kampf.** Der Testlauf lehnt jedes
  `Tool`/`Damage`/`Fire(` in dieser Datei ab.

### Open-World Phase 7 — Die Story
- Zehn Missionen (`M01_FIRSTHACK` … `M10_WREN`) als **Kette ohne
  Verzweigung**, jede mit dauerhaftem Unlock — der Testlauf prüft beides.
  Briefings höchstens drei Sätze; M01, M09 und M10 mussten dafür gekürzt
  werden.
- Die Wendung steht in M09: In den Protokollen steht dein eigener Name.
  Wren hat nie für dich gearbeitet — du hast für sie gearbeitet.
- **M10 ist eine Entscheidung, keine Mission:** *Kassieren* (halber Trace,
  25 % weniger Ertrag) oder *Verbrennen* (30 % mehr Ertrag, 40 % härtere
  Fahndung, bessere Kurse). Als `Profile.Story.Allegiance` gespeichert und
  nach `Config.Endgame.SwitchCooldown` (eine Woche) umstellbar — ohne das
  fühlen sich Spieler eingesperrt.
- Technisch hängt die Entscheidung über
  `HackService.AddTraceModifier` / `AddRewardModifier` am Hack. Andersherum
  gebaut, weil `HackService` sonst `MissionService` aufrufen müsste und
  dadurch ein Require-Kreis entstünde — den hat der Testlauf gefunden, bevor
  Studio ihn hätte finden können.

### Open-World Abschnitt 2 — Tag und Nacht
- **`TimeService`** (neu) — voller Zyklus in 24 Minuten, Server ist die Uhr.
  `Lighting.ClockTime`, Nebel, Ambient, Atmosphere und Bloom werden über eine
  weiche Rampe um Sonnenauf- und -untergang interpoliert, nichts springt.
- **Der Zyklus ist Mechanik, keine Kulisse:** nachts +35 % auf jeden
  Hack-Ertrag (`TimeService.RewardMultiplier`) und kürzere NPC-Sichtweite
  (`SightFactor`, ab OW-Phase 5 genutzt); tagsüber schwanken die Darknet-Kurse
  nur zu 60 %. Der Testlauf prüft, dass diese drei Unterschiede existieren.
- `Lighting.Technology` steht in `Config.World` und ist auf `ShadowMap`
  umstellbar, falls `Future` auf dem Handy einbricht.
- Tagsüber kühles Blaugrau statt sattem Blau — die Stadt soll auch bei Tag
  nicht freundlich wirken.

### Open-World Phase 1 — Fahrzeuge
- **`Shared/Vehicles.luau`** (neu) — fünf Klassen als Daten. Jede hat einen
  mechanischen Grund: Kompakt am unauffälligsten, Limousine beste Straßenlage,
  Sportwagen am schnellsten (und mit 1,6× Fahndungszuschlag), Transporter das
  größte Lager, Motorrad der größte Lenkeinschlag.
  Der Testlauf prüft, dass **jede Klasse in mindestens einem Wert die beste
  ist** — genau daran ist die Limousine beim ersten Durchlauf gescheitert, sie
  war „ausgewogen" und damit in nichts die beste Wahl. Jetzt hat sie den besten
  Grip, und der Sportwagen ist dafür zickiger geworden.
- **`VehicleChassis`** (neu) — ein Chassis, viele Karosserien, gebaut aus dem
  Datensatz. Pro Rad: `SpringConstraint` für die Federung,
  `CylindricalConstraint` senkrecht für Federweg und Lenkung (Servo),
  `CylindricalConstraint` seitlich für den Antrieb (Motor). Der Radträger
  dazwischen ist nötig, weil eine Achse nicht gleichzeitig Federweg und
  Raddrehung sein kann.
- **Netzwerkbesitz** geht beim Einsteigen an den Fahrer und beim Aussteigen,
  Tod oder Rausfliegen zurück an den Server. Ohne das fährt sich das Auto wie
  durch Sirup.
- **`VehicleController`** (neu, Client) — die Steuerung läuft beim Fahrer,
  weil ihm die Physik gehört. Kamera weicht mit Tempo zurück (FOV 70 → 85),
  Motor-Tonhöhe steigt, Reifen quietschen beim Seitwärtsdrift, Bremsspuren,
  Rückleuchten, Tacho. Lenkeinschlag sinkt mit dem Tempo, sonst überschlägt
  sich jedes Auto auf der Geraden.
- **`World/TestVehicles`** (neu) — ein Fahrzeug jeder Klasse am Spawn.
- `StreamingEnabled` ist in der Place-Datei und in `Config.World` gesetzt,
  Radien 128/512 — **noch ungetestet**, siehe oben.


### Phase E — Admin-Panel (F2)
- `AdminList.luau` liegt in **ServerScriptService**, nie in ReplicatedStorage —
  eine Admin-Liste dort könnte jeder Client lesen. Noah trägt seine UserId dort
  ein; im Studio ist der Testspieler automatisch Admin.
- **Jeder** Handler prüft die UserId in der ersten Zeile, vor Rate-Limit und
  Typcheck. Dass der Knopf nur Admins gezeigt wird, ist irrelevant.
- Geld, Rig, Trace, Bust, Story und Markt-Eingriffe sind zusätzlich auf
  `RunService:IsStudio()` beschränkt — im Live-Spiel existieren sie selbst für
  echte Admins nicht.
- Jede Aktion wird mit `warn()` protokolliert: wer, was, an wem.
- Umfang: Wirtschaft, Missionen, Welt (Ziele auflisten, Cooldowns löschen,
  Teleport), Markt, Debug. Wichtigster Punkt: **Profil als JSON ausgeben** —
  ohne das debuggt man Speicherfehler blind.

### Phase F — Robux-Store (P)
- `MonetizationService` mit **allen IDs auf 0**. Der Store zeigt einen noch
  nicht eingetragenen Eintrag als „NOCH NICHT DA" an, statt still nichts zu tun.
- `ProcessReceipt`: verarbeitete `PurchaseId` im Profil, erst gutschreiben,
  **dann speichern**, dann `PurchaseGranted`. Schlägt das Speichern fehl, wird
  nicht bestätigt — sonst wäre die Ware vergeben, aber nicht gespeichert.
- `UserOwnsGamePassAsync` mit Retry; bei endgültigem Fehler wird **nicht**
  angenommen, der Spieler besitze nichts, sondern später erneut geprüft.
- `PromptGamePassPurchaseFinished` aktiviert Pässe ohne Rejoin.
- Verkauft werden nur Zeit, Kapazität und Kosmetik. Nichts löst ein Rätsel.

### Phase G — Optik und Sound
- `Cityscape.server.luau`: nächtliche Straßenzeile statt Baseplate — nasse
  Fahrbahn über `Reflectance`, Neonschilder mit echtem Licht, erleuchtete
  Fensterbänder nur als Farbe (hunderte PointLights wären auf dem Handy nicht
  bezahlbar). Fester Seed, also auf jedem Server dieselbe Stadt.
- `TargetBeacons.client.luau`: Hack-Ziele und Hehler pulsieren dezent und gehen
  aus, wenn sie offline sind — sonst läuft man an ihnen vorbei.
- `SoundCatalog.luau` + `SoundController.client.luau`: **alle IDs leer.** Die
  Tonhöhe der Knoten-Klicks steigt mit der Pfadlänge (aus Klicks wird eine
  aufsteigende Melodie), der Countdown tickt unter 10 s immer schneller, die
  Ambience wird während eines Hacks leiser und kommt beim Alarm laut zurück.

### Phase C — Darknet
- `Goods.luau`: fünf Waren mit Basispreis, Volatilität und Fälschungsrisiko.
- `MarketService`: Kurse bewegen sich **serverweit** alle 12 s, mit Mean
  Reversion gegen Drift. Mini-Chart, Trend, gelegentliche Gruppen-Events.
- `InventoryService`: Preise kommen **ausschließlich** vom Server. Menge,
  Lagerplatz und Guthaben werden vor jeder Buchung geprüft. Das Darknet ist
  serverseitig hinter dem `DARKNET`-Unlock, nicht nur in der UI ausgeblendet.
- Risiko: begrenztes Lager, Ware ist heiß (Bust kostet die Hälfte davon),
  Fälschungsquote sinkt mit dem Rig-Tier.
- Klartext-Fehlermeldungen mit Zahl — überall.

### Phase B/D — die fünf Missionen
Jede ist Tutorial für ein System **und** schaltet es dauerhaft frei:
M01 → `FREE_HACKING`, M02 → `STORE_RAIDS`, M03 → `DARKNET`, M04 → `TRADING`,
M05 → `BANK_RAIDS`. Nichts davon verschwindet nach der Mission.
- `RaidService`: Alarm-Uhr rein über Attribute (`AlarmGroup`, `AlarmStarts`,
  `AlarmEnds`, `FailBusts`, `RequiresTwo`). Läuft **pro Spieler**, sonst würde
  ein zweiter Spieler den Alarm des ersten erben und Co-Op wäre eine Strafe.
- `TutorialUI`: genau ein Hinweisfeld, jeder Schritt durch eine Handlung
  ausgelöst, Skip-Button vergibt den Unlock ohne Crypto.

### Phase A — Missions-Rückgrat
- **`Shared/Missions.luau`** (neu) — eine Mission ist ein Tabelleneintrag, kein
  Skript. Enthält die Registry (aktuell leer), das dokumentierte Schema
  `Missions.Example` und die **puren** Regeln: `Validate`, `IsAvailable`,
  `FirstAvailable`, `Progress`, `Required`, `HasUnlock`. Kennt weder Spieler
  noch Remotes noch die Welt — deshalb komplett im Testlauf prüfbar.
- **`MissionService`** (neu) — aktive Mission und Schritt-Index liegen **im
  Profil**. Der Server leitet den Fortschritt aus dem ab, was ohnehin passiert:
  gelöste Hacks, Verkäufe, Distanz zu Wegpunkten, abgelaufene Wartezeiten.
  Der Client meldet **nie** „Schritt fertig".
- **Schritt-Typen:** `GOTO` (Part mit Tag `GhostNetWaypoint` + Attribut
  `WaypointId`), `HACK` (`TargetId`), `SELL` (Anzahl Verkäufe), `BUY`
  (Ware + Stückzahl, Haken für Phase C), `WAIT` (Sekunden über `os.time()`),
  `TALK` (Part mit Tag `GhostNetContact` + Attribut `ContactId`).
- **Kein Require-Kreis:** `HackService.OnHackResolved` und `SellService.OnSell`
  sind Callback-Register nach dem Vorbild von `TraceService.OnBust`. Der
  MissionService hängt sich dort an; keiner der beiden kennt ihn.
  Der Testlauf prüft das Abhängigkeitsdiagramm auf Kreise.
- **Neue Remotes:** `MissionSync`, `MissionAccept`, `MissionAbandon`,
  `MissionInteract` (TALK), `WaypointSync` — alle mit Rate-Limit.
- **`MissionUI`** (neu) — Auftragsanzeige oben links, Wegpunkt-Marker mit
  Entfernung, Countdown bei `WAIT`, `[E]`-Prompt bei `TALK`. Reine Anzeige.
- **`EconomyService.AwardBanked`** (neu) — für Missionsbelohnungen, die
  bewusst sicher sein sollen. Standard ist `Config.Mission.RewardToBank = false`:
  Story-Geld ist heiß und muss erst zum Hehler, damit der Verkaufs-Loop
  relevant bleibt.

### ⚠️ Schema-Migrationen 1 → 5
`Config.Save.SchemaVersion = 5`. `SaveService.MIGRATIONS` zieht Altprofile beim
Laden nach, **bevor** geschrieben wird — ein Altprofil wird nie verworfen.
| Version | Neu | Für Altprofile |
|---|---|---|
| 2 | `Story` (Missionsfortschritt) | Story startet bei null |
| 3 | `Stash` (Darknet-Lager) | Lager startet leer |
| 4 | `PurchaseLog` (gegen Doppelvergabe) | Log startet leer |
| 5 | `Garage` (Fahrzeugbesitz) + `Story.Allegiance` | Garage leer, Allegiance `""` |
**Migration 4 → 5 ist neu in dieser Session** und gehört zu Open-World-Phase 4.
Ein Profil aus Version 1.1.0 lädt weiter, bekommt eine leere Garage und keine
Entscheidung — es verliert nichts.
Bank, Rig, Trace, Cooldowns und Statistik bleiben in allen Fällen erhalten.
Jede weitere Version braucht einen eigenen Eintrag in `MIGRATIONS` — der
Testlauf prüft das.

### Phase 1 — Loop geschlossen

#### Bugfixes aus dem Prototyp
- **Ziel-Id-Kollision** — `HackTargets.nextFreeId()` zählt jetzt hoch, bis die Id
  wirklich frei ist. Vorher konnte ein Part ohne `TargetId`-Attribut die Id eines
  Parts mit gespeichertem Attribut überschreiben; das erste Ziel war dann tot.
- **Cooldown-Exploit durch Rejoin** — Cooldowns liegen im Profil
  (`profile.Cooldowns[targetId]`), nicht mehr in einer Tabelle im Serverspeicher.
  Server verlassen und neu beitreten setzt sie nicht zurück.
- **`os.clock()` vs. `os.time()`** — alles Persistierte (Cooldowns, `LastSeen`,
  Trace-Abkühlung über die Offline-Zeit) benutzt Unix-Zeit. `os.clock()` bleibt
  nur bei serverinternen Kurzzeit-Timern: `DownUntil`, Rate-Limits, Bust-Sperre,
  Sync-Drosselung.

#### Systeme
- **`SaveService`** — ein DataStore, Key `ghostnet_player_%d`, Profil-Schema mit
  `SchemaVersion`. Session-Lock über eine `SessionId` im Profil: die jüngere
  Sitzung übernimmt, die ältere merkt es beim nächsten Schreiben, schreibt nicht
  mehr und wird beendet. Autosave alle 60 s, gedrosselte Zwischenspeicherung nach
  Verkauf/Kauf/Bust, Speichern bei `PlayerRemoving` und `BindToClose`. Alle
  Zugriffe in `pcall` mit Backoff; scheitert das Laden endgültig, wird gekickt
  statt mit leerem Profil weitergespielt.
  Kein anderes Modul fasst einen DataStore an (wird im Testlauf geprüft).
- **`TraceService`** — Trace 0–100 im Profil. `Add` wird vom `HackService` mit dem
  dort schon berechneten `traceDelta` aufgerufen. Passiver Abbau nach 3 s Ruhe,
  beschleunigt durch Kühlung; läuft auch über die Offline-Zeit. Bust bei 100:
  Unverkauftes weg, Trace auf 25, 15 s Hack-Sperre, Bildschirm-Blitz beim Client.
  Neue Remote `TraceSync`.
- **`SellService`** — Hehler ist ein BasePart mit Tag `GhostNetFence`.
  Unsold → Banked abzüglich 12 % Gebühr, dazu Trace −18. Distanz wird
  serverseitig geprüft, genau wie beim Hacken. Rate-Limit `SellRequest`.
- **`ShopService`** — RemoteFunction `ShopPurchase`, vier Rig-Bauteile bis
  Stufe 5. Preis kommt aus `Config.GetUpgradeCost` und wird ausschließlich vom
  Server berechnet; der Client schickt nur, welches Bauteil er meint.
- **`EconomyService`** liest jetzt aus dem Profil statt aus einem eigenen Wallet.
  Öffentliche Schnittstelle unverändert, dazu `SellUnsold`, `SpendBanked`,
  `RefundBanked`, `SetRigLevel`, Statistik-Zähler.
- **`Shared/Geometry.luau`** (neu) — die Abstandsrechnung lag dreimal im Projekt
  (HackTargets, HUD, neu auch SellService). Jetzt einmal, damit HUD-Anzeige und
  Server-Entscheidung nie auseinanderlaufen.
- **HUD** — Trace-Balken dauerhaft sichtbar, pulst ab 70 %, rot ab 90 %.
  Ein Prompt für beides: was näher ist, Hehler oder Hack-Ziel, gewinnt die
  `[E]`-Taste. Cooldowns kommen als Restsekunden vom Server, damit die Anzeige
  nach einem Rejoin stimmt.
- **`ShopUI`** (neu) — Terminal-Fenster, Knopf unten links oder `[B]`.
  Zeigt je Bauteil Stufe, Preis und was die Stufe konkret bringt.
- **Testwelt** — zusätzlich zu Kamera/Tür/Automat steht jetzt ein Hehler am
  Spawn, rund 46 Studs von den Zielen entfernt. Der Rückweg kostet Zeit,
  während der Trace weiterläuft — sonst wäre Verkaufen keine Entscheidung.

### Balancing (alles in `Config.luau`)
- Erstes Upgrade: 198–253 CRY, also 2–3 erfolgreiche Kamera-Hacks. Der Testlauf
  prüft diese Vorgabe für jedes Bauteil.
- Trace: Kamera (D2) = 8 pro Hack, Abkühlung 0,25/s. Ein Bust braucht rund
  12 Kamera-Hacks ohne Verkauf. Ein Verkauf (−18) schafft mehr Luft, als ein
  Hack kostet — auch das wird geprüft.

## Tests
`cd ghostnet/tests && npm install && node testlauf.mjs` → **569/569 grün**.
Drei Stufen:
1. **Syntax** — `luau-compile` über jede `.luau`-Datei.
2. **Struktur** — `--!strict` überall, keine veralteten APIs, jede Remote
   angemeldet, jedes Rate-Limit konfiguriert, nur SaveService am DataStore,
   Cooldowns auf `os.time()`, **kein Require-Kreis zwischen den Services**,
   zu jeder Schema-Version eine Migration.
   Dazu die Sicherheitsregeln, die man mechanisch prüfen kann: Admin-Liste
   nicht in Shared/Client, UserId-Prüfung vor allem anderen, gefährliche
   Befehle StudioOnly, kein Preis aus dem Client-Paket, alle Gamepass- und
   Produkt-IDs auf 0, alle Sound-IDs leer, nirgends eine erfundene Asset-Id,
   `ProcessReceipt` speichert vor dem Bestätigen.
   Neu für die offene Welt: kein `PathfindingService` und kein `Humanoid` im
   Verkehr, kein `Heartbeat` in Verkehr/Polizei/Wachen, Objekt-Pool und
   Aktivradius vorhanden, keine Waffen in `PursuitService`, Wachen ohne
   `TakeDamage`, Netzwerkbesitz geht beim Aussteigen zurück, das Chassis
   bewegt kein Geld. Diese Prüfungen sehen nur echten Code — Kommentare
   werden vorher entfernt, sonst fällt ein Test über seinen eigenen
   Kopfkommentar („benutzt KEIN PathfindingService").
3. **Logik** — echte Module in der Luau-VM: Config-Formeln, Balancing-Vorgaben,
   das komplette Missions-Regelwerk (Validierung inkl. Kreiserkennung,
   Verfügbarkeit, jeder Schritt-Typ, eine ganze Mission durchgespielt), der
   Markt (Kauf immer über Verkauf, Mean Reversion holt einen entgleisten Kurs
   zurück, Lager wächst und Risiko sinkt mit dem Rig) und das Node-Breach-
   Minispiel (lösbar auf jeder Schwierigkeit, Lösung leckt nie).
   Für die offene Welt zusätzlich: Bezirksdaten überlappen nicht und nur einer
   ist dicht, die Verkehrsgrenzen sind konservativ, jede Fahndungsstufe ist
   erreichbar und man kann entkommen, jede Fahrzeugklasse ist in genau einem
   Wert die beste, die Missionskette ist geschlossen und jedes Briefing hat
   höchstens drei Sätze, und die Endgame-Entscheidung ist in beide Richtungen
   ein echter Tausch statt einer offensichtlich richtigen Wahl.

Drei dieser Prüfungen sind beim ersten Durchlauf durchgefallen und haben je
einen echten Fehler gefunden: eine unerreichbare Fahndungsstufe
(`TracePerLevel` 22 statt 20), zu lange Briefings (M01/M09/M10) und einen
Require-Kreis `HackService → MissionService → HackService`. Alle drei sind
behoben — an der *Ursache*, nicht am Test.

## Build
`node ghostnet/tools/build-rbxlx.mjs` → `ghostnet/GhostNet.rbxlx`,
direkt in Studio öffenbar. Alternativ Rojo mit `ghostnet/default.project.json`.

## Offen / bewusst nicht gebaut ➡️
Der Bauplan aus dem Prompt ist abgearbeitet. Was fehlt, fehlt mit Absicht:
- **Alle IDs sind Platzhalter** (Sounds `""`, Gamepässe und Produkte `0`,
  Admin-Liste leer). Erfundene IDs schlagen stumm fehl — deshalb keine.
  Das Spiel läuft ohne sie, es ist nur stumm und der Store leer.
- **Vier von fünf Bezirken sind absichtlich dünn.** Nur die Altstadt ist
  ausgebaut. Das ist keine unfertige Arbeit, sondern die Regel „erst einen
  fertig, dann den nächsten" — und der Testlauf hält sie fest.
- **Zwei weitere Minispiele**, **prozeduraler Weltgenerator**, **Tagesziele**
  und **Ranglisten** — Details am Ende von `PHASEN.md`.
- **Kein echter Spielertest.** Alles ist im Code umgesetzt und durch 569
  automatische Prüfungen abgesichert, aber noch nicht von einem Menschen in
  Studio durchgespielt.

## Bekannte Einschränkungen ⚠️
- **Studio-Notbetrieb:** Ist „Studio Access to API Services" aus, kann kein
  DataStore erreicht werden. Dann läuft das Spiel mit einem Profil im
  Arbeitsspeicher weiter (laute Warnung in der Ausgabe) und **speichert nichts**.
  Der Pfad ist doppelt abgesichert (`Config.Save.StudioMemoryFallback` UND
  `RunService:IsStudio()`) und live nie erreichbar. Zum Testen der Persistenz
  muss der API-Zugriff an sein.
- Session-Lock nach dem Prinzip „die jüngere Sitzung gewinnt": wechselt jemand
  sehr schnell den Server, können bis zu 60 Sekunden (ein Autosave-Takt) fehlen.
- **Bildrate, Fahrgefühl und Physikstabilität sind ungemessen.** Siehe oben.
  Die Startwerte in `Config.Traffic`, `Config.City` und `Config.Vehicle` sind
  geschätzt und bewusst niedrig — nicht gemessen.
- **Die Stadt wird beim Serverstart gebaut**, nicht in der Place-Datei
  gespeichert. Vorteil: eine Änderung an `Config.City` ändert sofort die ganze
  Stadt. Nachteil: der Startvorgang dauert etwas länger, und man kann die
  Häuser in Studio nicht von Hand verschieben. Soll die Stadt später von Hand
  gebaut werden, ersetzt man `City.server.luau` durch echte Parts — Tags und
  Attribute bleiben identisch, der Rest des Codes merkt nichts davon.

## Manuelle Schritte außerhalb des Codes (Noah) 🔑
1. **Studio:** Game Settings → Security → *Enable Studio Access to API Services*
   einschalten, sonst wird nichts gespeichert.
2. **Sounds:** `src/shared/SoundCatalog.luau` — Asset-IDs aus der Roblox-
   Audiobibliothek als `"rbxassetid://ZAHL"` eintragen. Jeder leere Eintrag
   bleibt einfach stumm, es geht nichts kaputt.
3. **Store:** Creator Dashboard → Monetization → Passes bzw. Developer Products
   anlegen, dann die IDs in `src/server/Systems/MonetizationService.luau`
   eintragen (läuft über das Konto des Vaters).
4. **Admin:** die eigene UserId in `src/server/AdminList.luau` eintragen. Ohne
   Eintrag gibt es live keine Admins; im Studio bist du automatisch einer.

## Entscheidungen / Notizen 📌
- GhostNet liegt als eigenständiges Spiel unter `ghostnet/`, unabhängig von
  PlanetForge (Repo-Wurzel) und TURMFALL (`turmfall/`). Eigene `CLAUDE.md`,
  eigene `PHASEN.md`, eigener Build.
- Der Shop ist von überall aus erreichbar, nicht an den Hehler gebunden — das
  Rig ist die eigene Ausrüstung, kein Ladenregal. Bezahlt wird trotzdem nur von
  der Bank, man muss also vorher zum Hehler.
- Missionen sind Daten, keine Skripte. Wer eine neue schreibt, fasst nur
  `Shared/Missions.luau` an. Das Schema steht dort als `Missions.Example`.
- Leitregel für jede künftige Mission: sie ist gleichzeitig das Tutorial für
  ein System **und** schaltet dieses System dauerhaft frei. Keine Mission
  bauen, deren Inhalt danach verschwindet.
- **Identität der offenen Welt:** kein GTA-Klon mit Hacking, sondern ein
  Hacking-Spiel mit offener Stadt. Daraus folgt alles Weitere: keine
  Schusswaffen, kein Kampfsystem, Autos sind Werkzeug (schneller da, mehr
  Lager) statt Selbstzweck, NPCs sind Hindernis statt Gegner, und die Polizei
  ist eine Verfolgung, die im bestehenden Bust endet. Wer das später aufweicht,
  baut ein anderes Spiel.
- Verkehr, Fußgänger und Streifenwagen laufen alle auf demselben
  `RoadNetwork`-Graphen, der aus `Config.City` gerechnet wird. Es gibt keine
  zweite Karte und keine handgesetzten Wegpunkte, die auseinanderlaufen können.
