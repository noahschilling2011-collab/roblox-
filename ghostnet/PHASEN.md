# GHOSTNET — Bauplan

Reihenfolge ist bindend. Eine Phase wird komplett fertig, bevor die nächste
anfängt. Neue Minispiele ohne funktionierenden Loop sind wertlos — der Spieler
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

Die Registry ist absichtlich **leer**: Missionsinhalte gehören in Phase B und D.

---

## Phase B — Mission 1 bis 3: der Einstieg
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

## Phase C — Das Darknet: der eigentliche Loop
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

## Phase D — Mission 4 und 5
- **M04 „Erste Ware"** — geführter erster Handel: kaufen, Preis beobachten,
  mit Gewinn verkaufen. Danach freier Handel.
- **M05 „Die Bank"** — Außenkamera → Sicherheitstür → Tresorraum, steigender
  Trace pro Stufe, Alarm-Timer über das Ganze, Fehlschlag = sofortiger Bust.
  Danach wiederholbar mit langem Cooldown. Attribut `RequiresTwo` am Tresorraum
  vorsehen, damit ein zweiter Spieler den Alarm verlangsamen kann.

---

## Phase E — Admin-Panel
Sicherheit zuerst: UserId-Liste in einem ModuleScript in `ServerScriptService`
(**nie** in `ReplicatedStorage`), Prüfung als **erste Zeile** jedes Handlers,
zusätzlich `RunService:IsStudio()` für Geld/Trace/Profil-Reset, jede Aktion mit
`warn()` geloggt, eigener Rate-Limit-Eintrag. F2 öffnet das Panel.
Umfang: Wirtschaft, Missionen, Welt, Markt, Debug — wichtigster Punkt ist
„Profil als JSON ausgeben", ohne das debuggt man Speicherfehler blind.

---

## Phase F — Robux-Store
Erst wenn A bis D laufen. `MonetizationService` mit **allen IDs auf 0**.
`UserOwnsGamePassAsync` beim Join, Ergebnis cachen; bei Fehler **nicht**
annehmen, der Spieler besitze nichts. `PromptGamePassPurchaseFinished` für
Live-Aktivierung. `ProcessReceipt` gibt `PurchaseGranted` erst zurück, **nachdem**
der Effekt gespeichert wurde; verarbeitete `PurchaseId` im Profil merken.
Nichts verkaufen, das ein Rätsel löst oder anderen schadet.

---

## Phase G — Optik
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
