# STATUS.md — Projektstand GhostNet

> Wird am Ende jeder Session aktualisiert. Erstes, was eine neue Session liest.

## Aktuelle Phase
**Phase 0 bis G plus Open-World-Abschnitt 2 und Phase 1**
(`Config.Version = "1.1.0"`). Das Spiel hat jetzt einen Tag-/Nachtzyklus, der
Mechanik ist, und fünf fahrbare Fahrzeugklassen. Alles Bisherige läuft
unverändert darunter weiter.

**Nächster Schritt: Open-World-Phase 2 (die Stadt).** Erst *ein* Bezirk fertig
und dicht, dann der nächste — eine große leere Stadt ist schlimmer als ein
kleiner voller Block.

## ⚠️ Was ich NICHT prüfen konnte
Der Bauplan verlangt nach jeder Phase eine **gemessene Bildrate**. Das kann ich
nicht liefern: Ich habe keine Roblox-Laufzeit, nur eine Luau-VM für Syntax und
Logik. Die 462 Prüfungen sagen nichts über Bildrate, Fahrverhalten oder
Physikstabilität aus. Beides muss Noah im MicroProfiler messen —
besonders vor Open-World-Phase 3 (Verkehr), wo genau das entscheidet.

## Fertig ✅

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

### ⚠️ Schema-Migrationen 1 → 4
`Config.Save.SchemaVersion = 4`. `SaveService.MIGRATIONS` zieht Altprofile beim
Laden nach, **bevor** geschrieben wird — ein Altprofil wird nie verworfen.
| Version | Neu | Für Altprofile |
|---|---|---|
| 2 | `Story` (Missionsfortschritt) | Story startet bei null |
| 3 | `Stash` (Darknet-Lager) | Lager startet leer |
| 4 | `PurchaseLog` (gegen Doppelvergabe) | Log startet leer |
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
`cd ghostnet/tests && npm install && node testlauf.mjs` → **462/462 grün**.
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
3. **Logik** — echte Module in der Luau-VM: Config-Formeln, Balancing-Vorgaben,
   das komplette Missions-Regelwerk (Validierung inkl. Kreiserkennung,
   Verfügbarkeit, jeder Schritt-Typ, eine ganze Mission durchgespielt), der
   Markt (Kauf immer über Verkauf, Mean Reversion holt einen entgleisten Kurs
   zurück, Lager wächst und Risiko sinkt mit dem Rig) und das Node-Breach-
   Minispiel (lösbar auf jeder Schwierigkeit, Lösung leckt nie).

## Build
`node ghostnet/tools/build-rbxlx.mjs` → `ghostnet/GhostNet.rbxlx`,
direkt in Studio öffenbar. Alternativ Rojo mit `ghostnet/default.project.json`.

## Offen / bewusst nicht gebaut ➡️
Der Bauplan aus dem Prompt ist abgearbeitet. Was fehlt, fehlt mit Absicht:
- **Alle IDs sind Platzhalter** (Sounds `""`, Gamepässe und Produkte `0`,
  Admin-Liste leer). Erfundene IDs schlagen stumm fehl — deshalb keine.
  Das Spiel läuft ohne sie, es ist nur stumm und der Store leer.
- **Zwei weitere Minispiele**, **prozeduraler Weltgenerator**, **Tagesziele**
  und **Ranglisten** — Details am Ende von `PHASEN.md`.
- **Kein echter Spielertest.** Alles unten in „So testest du das" ist im Code
  umgesetzt und durch 392 automatische Prüfungen abgesichert, aber noch nicht
  von einem Menschen in Studio durchgespielt.

## Bekannte Einschränkungen ⚠️
- **Studio-Notbetrieb:** Ist „Studio Access to API Services" aus, kann kein
  DataStore erreicht werden. Dann läuft das Spiel mit einem Profil im
  Arbeitsspeicher weiter (laute Warnung in der Ausgabe) und **speichert nichts**.
  Der Pfad ist doppelt abgesichert (`Config.Save.StudioMemoryFallback` UND
  `RunService:IsStudio()`) und live nie erreichbar. Zum Testen der Persistenz
  muss der API-Zugriff an sein.
- Session-Lock nach dem Prinzip „die jüngere Sitzung gewinnt": wechselt jemand
  sehr schnell den Server, können bis zu 60 Sekunden (ein Autosave-Takt) fehlen.

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
