# Nova Surge — Projektgedächtnis (Browser-FPS für CrazyGames)

Diese Datei gilt für alles unterhalb von `nova-surge/`. Sie ist die oberste Instanz:
Bei Widerspruch zwischen dieser Datei und einer Chat-Anweisung → nachfragen statt raten.
(Die CLAUDE.md im Repo-Root gehört zum Roblox-Projekt PlanetForge und gilt hier NICHT.)

## Was das Spiel ist
Singleplayer-Wave-Shooter für den Browser. Arbeitstitel „Nova Surge" (frei erfunden,
jederzeit änderbar — Phase 6 legt den finalen Namen fest). Referenzgefühl:
Krunker-Movement (schnell, direkt, kein Realismus) + PvE-Wellen gegen Bots.
Ziel: Einreichung bei CrazyGames. Deren Basic Launch misst drei Zahlen:
**Conversion to Gameplay, durchschnittliche Spielzeit, Retention.**
Jedes Feature muss auf eine dieser drei Zahlen einzahlen — sonst wird es nicht gebaut.

## Harte Constraints (nicht verhandelbar)
- KEIN Multiplayer. Kein Netcode, keine Server, keine Lobbys. Auch nicht „vorbereiten
  für später".
- Tech-Stack: Vite + three (npm). Keine weiteren **Runtime**-Dependencies.
  (Dev-Dependencies wie `typescript`/`@types/three` sind okay — sie landen nicht im Build.)
- Build-Größe ≤ 20 MB. Ziel < 5 s bis spielbar (Ladezeit = Conversion).
- 60 FPS auf einem Mittelklasse-Handy. Object Pooling für Projektile, Partikel, Gegner.
  InstancedMesh für wiederholte Geometrie. Keine Allokationen im Gameplay-Loop.
- Alle Assets prozedural oder aus Primitiven (Low-Poly). WebAudio-Sounds prozedural.
  KEINE Asset-Packs, keine echten Waffennamen, keine Marken (IP-Risiko beim Review).
- Desktop (Pointer Lock, WASD) und Mobile (Touch). Mobile ab Phase 5 Pflicht,
  Architektur von Anfang an darauf ausgelegt.
- Kein Feature aus einer späteren Phase beginnen, bevor das Gate der aktuellen Phase
  dokumentiert erfüllt ist (Gate-Check in STATUS.md).

## Arbeitsregeln
- Es wird immer genau EINE Phase aus PHASEN.md pro Arbeitsauftrag bearbeitet.
  Nichts außerhalb des Phasenauftrags bauen — keine Stub-Systeme auf Vorrat.
- Erst lesen, dann schreiben: Vor jeder Änderung die betroffenen Module vollständig lesen.
- Jede Antwort mit Codeänderung endet mit „**So testest du das im Browser:**" + Schritten.
- Am Ende jeder Session STATUS.md aktualisieren: erledigt / offen / Gate-Status / Bugs.
- Fehlt eine Information: nachfragen statt annehmen.

## Tech & Architektur
- TypeScript strict, Vite, three. `npm run dev` (Entwicklung), `npm run build`
  (Typecheck + Production-Build nach `dist/`), `npm run preview` (Build lokal testen).
- Spiellogik strikt vom Rendering getrennt:
  - `src/core/` — Simulation. Fixed Timestep 60 Hz (`GameLoop`, Accumulator-Muster),
    `Sim` hält den kompletten Spielzustand. Kein three-Import in `core/`
    (Ausnahme: reine Mathe-Typen wie Vector3, falls nötig).
  - `src/render/` — three-Szene, liest Sim-Zustand, schreibt nie hinein.
    Render-Callback bekommt `alpha` [0..1) für Interpolation bewegter Objekte.
  - `src/controls/` — Eingabe (Maus/Tastatur, später Touch).
  - `src/ui/` — DOM-Overlays (Menü, HUD, Debug). UI ist DOM + CSS, nicht WebGL.
- Pause-Regel: Simulation läuft genau dann, wenn der Pointer gelockt ist
  (Desktop). ESC → Browser löst den Lock → Pause-Menü. Gerendert wird immer.
- Balancing-/Tuning-Werte kommen ab Phase 3 in eigene Config-Dateien
  (`src/config/`), keine Magic Numbers in Logik-Code.
- `window.__ns` ist das Debug-Handle für Konsole und automatisierte Headless-Tests
  (Playwright). Nicht entfernen — die Gate-Checks hängen daran.
- Sprache: Doku/Kommentare Deutsch, In-Game-UI-Texte Englisch (CrazyGames ist
  international; die Abgabe-Beschreibung in Phase 6 ist EN).

## Verifikation (Gate-Checks)
- Headless-Check: Playwright-Skript (liegt außerhalb des Repos im Session-Scratchpad,
  Vorlage in STATUS.md verlinkt/beschrieben) fährt den Production-Build in Chromium ab:
  Konsole fehlerfrei, Sim-Rate 60 Hz, Pause/Resume, Resize, Heap-Soak.
- Headless-FPS sind NICHT aussagekräftig (kein vsync/GPU) — echte FPS-Aussagen nur
  vom Debug-Overlay (F3) auf echter Hardware. Sim-Ticks/s müssen trotzdem 60 sein.
- Was headless nicht geht (echtes ESC-Verhalten, Gefühl, Mobile): manuelle
  Checkliste in STATUS.md, von Noah im Browser abzuhaken.

## Kontext
Entwickler ist Noah, 15, arbeitet solo. Werkzeuge: Claude Code, VS Code, Browser.
CrazyGames-Einreichung läuft über das Entwicklerportal (manueller Schritt außerhalb
des Codes) — im Code nur vorbereiten und exakt sagen, was wo einzutragen ist.
