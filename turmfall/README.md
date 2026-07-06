# TURMFALL 🏗️💥

12 Spieler bauen gleichzeitig am **selben** physikbasierten Turm. Runden dauern
3 Minuten. Stabil bauen bringt sichere Punkte, riskant hoch bauen viele Punkte –
und wer den Turm kollabieren lässt, verliert seinen kompletten Einsatz. Ein
Schuld-Replay zeigt allen, wer es war.

## Projektstruktur (Rojo)

```
turmfall/
├── default.project.json      Rojo-Mapping
├── src/
│   ├── shared/               ReplicatedStorage.Shared
│   │   ├── Network.luau      DAS zentrale Remote-Modul (keine verstreuten Remotes)
│   │   ├── Types.luau        gemeinsame Typen (--!strict überall)
│   │   ├── BlameLogic.luau   purer Schuld-Algorithmus (getestet)
│   │   ├── ScoreLogic.luau   pure Punkteberechnung (getestet)
│   │   └── Config/           GameConfig (Canon), PartCatalog (4 Teiltypen)
│   ├── server/               ServerScriptService.Server
│   │   └── Services/         Tower, Deck, Collapse, Score, Round
│   └── client/               StarterPlayerScripts.Client
│       └── Controllers/      UI, Placement (Ghost-Preview), Replay
├── tests/testlauf.mjs        Logik-Tests in echter Luau-VM + Remote-Abgleich
└── tools/build-rbxlx.mjs     baut die direkt öffnbare Turmfall.rbxlx
```

## Technische Eckpfeiler

- **Server-owned Physik:** Jedes Turm-Teil bekommt `SetNetworkOwner(nil)`.
  Ohne das könnten manipulierte Clients die Simulation naher Teile steuern
  und die Schuldzuweisung beim Kollaps verfälschen (Details im Kopfkommentar
  von `TowerService.luau`).
- **Niemals dem Client trauen:** Der Client zeigt nur eine Ghost-Preview
  (grün/rot); der Server validiert jede Platzierung komplett (Phase, Cooldown,
  Teilbesitz, Reichweite 12 Studs, Nachbarschaft, Überlappung).
- **Physik-Budget von Anfang an:** Maximal 400 aktive Teile. Darüber werden
  die untersten, ruhigen Teile „versteinert" (geankert) – eingebaut ab Tag 1,
  nicht nachgerüstet.
- **Eine StateMachine:** `RoundService` (Lobby → Aufbau → Bauphase → Wertung)
  ist die einzige Source of Truth; Clients spiegeln nur.

## Meilenstein 1 – Kern-Loop ✅

- 3-Minuten-Runden, Start ab 2 Spielern, Countdown- und Phasen-UI
- 4 Bauteil-Typen: Schwerblock, Leichtblock, Schrägkeil (45°),
  Federblock (PrismaticConstraint + SpringConstraint)
- Teilvergabe alle 15 s (Hotbar max. 3, Tasten 1–3)
- Ghost-Preview-Platzierung (R = drehen) mit voller Server-Validierung
- Kollaps-Erkennung: Teil „gefallen" unter Plattform-Y; >30 % in 5 s → Kollaps
- Schuld-System: Platzierer-Log + Ringpuffer (10 s, 4 Hz); das zuletzt
  platzierte Teil mit Kontakt zur Kaskade bestimmt den Verursacher
- Punkte = Y-Höhe der überlebenden eigenen Teile; Verursacher = 0 Punkte
- 5-Sekunden-Schuld-Replay aus dem Ringpuffer mit Kamera-Fokus und Namen

### So testest du Meilenstein 1 in Roblox Studio

**Variante A – direkt öffnen (am einfachsten):**
1. `node turmfall/tools/build-rbxlx.mjs` ausführen (oder die fertige
   `Turmfall.rbxlx` aus dem Repo-Root nehmen).
2. Datei in Roblox Studio öffnen.
3. **Solo:** einfach ▶ Play drücken – nach kurzer Wartezeit
   („🧍 Solo-Start in 8…") beginnt automatisch eine Übungsrunde.
   **Multiplayer:** oben **TEST → Clients and Servers → 2 Players → Start**
   wählen (Local Server mit 2 Clients, normaler 2-Spieler-Countdown).
4. Mit Tasten 1–3 ein Teil wählen, mit der Maus zielen (grüner Ghost),
   klicken zum Platzieren, R zum Drehen.
5. Kollaps provozieren (z. B. weit außen an eine Kante stapeln): Das
   Schuld-Replay startet automatisch und zeigt den Verursacher.

**Variante B – mit Rojo (für Entwicklung):**
1. `cd turmfall && rojo serve` (Rojo 7+)
2. In Studio mit dem Rojo-Plugin verbinden und ein leeres Baseplate syncen.
3. Weiter wie oben ab Schritt 3.

**Logik-Tests (ohne Studio):** `node turmfall/tests/testlauf.mjs` – prüft
Schuld-Algorithmus, Punkteberechnung, Konfigurations-Canon und dass jedes
benutzte Remote in `Network.luau` deklariert ist.

## Meilenstein 2 – Skin-System ✅

- `SkinCatalog.luau`: 12 Teil-Skins (Common bis Legendary, z. B. Holz,
  Marmor, Goldbarren, Glasblock mit Glanz) + 2 Kollaps-Effekte
  (Konfetti / Zeitlupe, rein clientseitig visuell) als eigene Kategorie
- Skins sind **rein kosmetisch** – der Kommentar-Block im Katalog erklärt,
  warum kaufbare Physik-Vorteile Turmfall zerstören würden, und
  `SkinCatalog.validate()` erzwingt es (Guard, getestet)
- Inventar-/Ausrüsten-UI: 🎨-Button links oben, Grid mit
  Raritätsrahmen-Farben, Klick rüstet aus/ab
- Persistenz: `DataService` mit DataStore **und Session-Locking**
  (UpdateAsync-Lock + Heartbeat + Read-only-Fallback), Speicher-Retry,
  BindToClose-Flush

### So testest du Meilenstein 2

1. Wie bei Meilenstein 1 mit 2 Spielern starten.
2. Links oben **🎨 Skins** öffnen: Start-Skins (Holz, Backstein) sind
   sofort im Besitz – anklicken zum Ausrüsten (goldener Rahmen = aktiv).
3. Ein Teil platzieren: Es erscheint im ausgerüsteten Skin-Look.
4. Hinweis: In Studio ohne aktivierten API-Zugriff läuft die Persistenz
   im Read-only-Modus (Warnung in der Ausgabe) – im veröffentlichten
   Spiel speichert sie normal.

## Meilenstein 3 – Robux-Monetarisierung ✅

- `MonetizationCatalog.luau`: Developer Products (einzelne Skins + Bundles)
  und kosmetischer Season-Pass als **Platzhalter-Konstanten** – die echten
  IDs müssen im Creator Dashboard angelegt und bei `productId` /
  `SEASON_PASS_GAMEPASS_ID` eingetragen werden (TODO-Kommentare im Code;
  Code kann keine Produkte erstellen)
- `MonetizationService.luau`: **idempotentes** `ProcessReceipt` –
  Receipt-IDs werden im Profil (DataStore) geloggt, ein Beleg wird nie
  doppelt gutgeschrieben (`ReceiptLogic`, pur getestet); Read-only-Sessions
  bekommen `NotProcessedYet` statt riskanter Gutschriften
- **Guard:** Verkauft wird strukturell NUR Kosmetik – Produkte können
  ausschließlich Skin-IDs vergeben, `MonetizationCatalog.validate()` prüft
  jeden Verweis gegen den (selbst validierten) SkinCatalog und läuft beim
  Serverstart und in den Tests
- Zweitwährung **🧱 Trümmer**: erspielt (Punkte + Rundenbonus), NICHT
  kaufbar; ein Teil des Katalogs ist nur für Trümmer erhältlich
  (Free-Progression)
- Studio-Testmodus: Klick auf einen Robux-Skin mit Platzhalter-ID simuliert
  den Kauf – NUR in Studio

### So testest du Meilenstein 3

1. Runde zu Ende spielen → Toast `+N 🧱 Trümmer verdient!`, Stand im
   Skins-Panel oben rechts.
2. Im Skins-Panel einen 🧱-Skin anklicken → Kauf mit Trümmern.
3. Einen R$-Skin anklicken → in Studio wird der Kauf simuliert
   (im Live-Spiel öffnet sich der Roblox-Kaufdialog, sobald echte
   Produkt-IDs eingetragen sind).

## Meilenstein 4 – Polish für den ersten Release ✅

- **„Letzter Stein"-Finale:** In den letzten 15 Sekunden setzt jeder genau
  EIN Teil; die Clients spielen dazu eine rein visuelle Zeitlupe
  (Farbkorrektur + FOV – die Physik läuft überall normal weiter)
- **Sabotage-Balancing:** Liegt das nächste Stütz-Teil unter der neuen
  Platzierung und gehört einem Gegner, gibt es 10 Sekunden
  Instabilitäts-Cooldown (Sabotage bleibt möglich, kostet aber Tempo)
- **Turm-Schwank-Feedback:** Server berechnet jede Sekunde einen
  Stabilitäts-Score 0–100 aus der mittleren Teil-Geschwindigkeit; Clients
  zeigen einen Balken, wackeln mit der Kamera und knarzen proportional
- **Mobile-Support (Mobile-first):** Tippen zielt (Ghost folgt dem Finger),
  gebaut/gedreht wird über zwei große Touch-Buttons rechts unten –
  kein versehentliches Bauen beim Kamera-Drehen
- **Denkmal-Sockel** in der Arena für den höchsten Turm der Woche
  (Platzhalter – Persistenz folgt nach dem ersten Release)

### So testest du Meilenstein 4

1. Runde starten, bis 15 Sekunden vor Schluss spielen → „LETZTER STEIN!"
   erscheint, die Welt entsättigt sich kurz, jeder kann nur noch 1 Teil setzen.
2. Ein Teil direkt oben auf ein GEGNERISCHES Teil bauen → Hinweis
   „Instabilitäts-Cooldown" und 10 s Bausperre.
3. Turm zum Wackeln bringen → Stabilitäts-Balken unter dem Timer färbt sich
   gelb/rot, Kamera wackelt, es knarzt.
4. Mobile testen: In Studio **Test → Emulation → Device** wählen –
   die Touch-Buttons 🧱/🔄 erscheinen automatisch.
