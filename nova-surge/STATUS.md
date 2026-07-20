# Nova Surge — Projektstand

Letzte Session: 2026-07-20 · Aktuelle Phase: **0 (Setup & Loop)** — Gate-Check läuft

## Phase 0 — erledigt
- Vite + three + TypeScript (strict) aufgesetzt, `npm run dev/build/preview` laufen.
- Fixed-Timestep-Gameloop: Simulation fest 60 Hz (Accumulator-Muster), Rendering
  entkoppelt mit Interpolations-Alpha, Frame-Delta auf 250 ms gekappt (keine
  Spiral of Death nach Tab-Wechsel).
- Szene: Boden + Grid + Hemisphären-/Sonnenlicht, Fog, Kamera auf Augenhöhe.
- Pointer Lock: Klick fängt die Maus, ESC öffnet das Pause-Menü. Regel: Simulation
  läuft genau dann, wenn der Pointer gelockt ist. Re-Lock-Cooldown von Chrome
  (~1,25 s nach ESC) wird abgefangen („One moment — click again!").
- Maus-Look (Yaw/Pitch, Pitch geklemmt) — nötig, um Pointer Lock prüfbar zu machen.
  WASD-Movement ist bewusst NICHT drin (Phase 1).
- Resize-Handling (Canvas + Kamera-Aspect).
- Debug-Overlay auf F3: FPS, Frame-Zeit, Sim-Ticks/s, Draw Calls, Dreiecke,
  Entities, JS-Heap.
- Debug-Handle `window.__ns` für Headless-Tests und Konsole.
- Build: **532 KB** (gzip ~134 KB) — Limit 20 MB, Ziel-Ladezeit < 5 s locker erfüllt.

## Gate-Check Phase 0 (Headless-Chromium gegen Production-Build)

| Check | Ergebnis |
|---|---|
| Laden ohne Konsolen-Fehler | PASS |
| Startzustand: Menü sichtbar, Sim pausiert, Rendering aktiv | PASS |
| Klick → Pointer Lock → Menü zu, Sim läuft | PASS |
| Sim-Rate: 300–302 Ticks in 5 s (= 60 Hz) trotz ~40 Render-FPS headless | PASS |
| Unlock → Pause-Menü, 0 Sim-Ticks während Pause | PASS |
| Resume → Lock + Sim laufen weiter (60 Ticks/s) | PASS |
| Resize: Canvas + Kamera-Aspect folgen | PASS |
| 5-Min-Heap-Soak (Drift nach GC < 1 MB) | läuft — Zwischenstand: konstant 4,55–4,56 MB über 2 Min |

Hinweis: Headless-Render-FPS sind ohne GPU/vsync nicht aussagekräftig; entscheidend
ist, dass die Simulation davon unabhängig exakt 60 Hz hält (tut sie). Echte
FPS-Messung: Debug-Overlay (F3) auf echter Hardware — manuelle Checkliste unten.

## Manuelle Checkliste für Noah (Browser, echte Hardware)
- [ ] `npm run dev` → Seite lädt, Klick fängt die Maus, Umsehen flüssig
- [ ] F3: FPS stabil ~60 (bzw. Monitor-Refreshrate), draws=2, entities=0
- [ ] ESC → Pause-Menü kommt sofort, „RESUME" fängt die Maus wieder
  (direkt nach ESC blockt Chrome ~1 s — Hinweistext erscheint, zweiter Klick geht)
- [ ] Fenster resizen → Bild folgt ohne Verzerrung

## Offen / Nächster Auftrag
- Heap-Soak-Endergebnis eintragen (läuft gerade, Zwischenstand sauber).
- Danach: **Phase 1 — Gunfeel** (Movement WASD/Sprint/Sprung, Hitscan-Waffe,
  prozeduraler WebAudio-Sound, Schießstand mit Dummies). Wichtigste Phase,
  Gate = 30-Sekunden-Test.

## Bekannte Bugs
- Keine bekannt.
