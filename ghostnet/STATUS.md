# STATUS.md — Projektstand GhostNet

> Wird am Ende jeder Session aktualisiert. Erstes, was eine neue Session liest.

## Aktuelle Phase
**Phase A abgeschlossen** (`Config.Version = "0.3.0"`). Das Missions-Rückgrat
steht. Der Spielkreislauf aus Phase 1 läuft unverändert weiter.

**Nächster Schritt: Phase B (Mission 1 bis 3).** Erst dort entstehen
Missionsinhalte — die Registry in `Shared/Missions.luau` ist absichtlich leer.
Vorher nichts aus Phase C–G anfangen.

## Fertig ✅

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

### ⚠️ Schema-Migration 1 → 2
Das Profil hat einen `Story`-Block bekommen (`Config.Save.SchemaVersion = 2`).
`SaveService.MIGRATIONS` zieht Altprofile beim Laden nach, **bevor** geschrieben
wird. Bank, Rig, Trace, Cooldowns und Statistik bleiben erhalten; nur die Story
startet bei null. Ein Altprofil wird nie verworfen. Jede weitere Schema-Version
braucht einen eigenen Eintrag in `MIGRATIONS` — der Testlauf prüft das.

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
`cd ghostnet/tests && npm install && node testlauf.mjs` → **160/160 grün**.
Drei Stufen:
1. **Syntax** — `luau-compile` über jede `.luau`-Datei.
2. **Struktur** — `--!strict` überall, keine veralteten APIs, jede Remote
   angemeldet, jedes Rate-Limit konfiguriert, nur SaveService am DataStore,
   Cooldowns auf `os.time()`, **kein Require-Kreis zwischen den Services**,
   zu jeder Schema-Version eine Migration.
3. **Logik** — echte Module in der Luau-VM: Config-Formeln, Balancing-Vorgaben,
   das komplette Missions-Regelwerk (Validierung inkl. Kreiserkennung,
   Verfügbarkeit, jeder Schritt-Typ, eine ganze Mission durchgespielt) und das
   Node-Breach-Minispiel (lösbar auf jeder Schwierigkeit, Lösung leckt nie).

## Build
`node ghostnet/tools/build-rbxlx.mjs` → `ghostnet/GhostNet.rbxlx`,
direkt in Studio öffenbar. Alternativ Rojo mit `ghostnet/default.project.json`.

## Offen / bewusst nicht gebaut ➡️
- **Missionsinhalte.** Die Registry ist leer, das ist die Definition of Done
  von Phase A („MissionService läuft, ohne dass eine einzige Mission
  existiert"). M01–M03 sind Phase B, M04–M05 Phase D.
- **Phase C** (Darknet, Markt, Lager) — `MissionService.NotifyBuy` steht als
  Haken bereit und wird bis dahin von niemandem aufgerufen.
- **Phase E–G** (Admin-Panel, Robux-Store, Optik und Sound).
- Der HUD zeigt Ablehnungen noch in Kurzform. Die ausführlichen Sätze mit
  konkreten Zahlen („Braucht Tier 3 — dein schwächstes Bauteil ist RAM 1")
  gehören zu Phase C.
- Es gibt **keine Sounds**. Bewusst: `SoundCatalog` ist Phase G, und Asset-IDs
  werden nicht erfunden.

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
- In Studio: **Game Settings → Security → Enable Studio Access to API Services**
  einschalten, sonst wird nichts gespeichert.
- Publishing, Gamepässe und Produkt-IDs: erst in Phase 5 relevant.

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
