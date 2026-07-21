# Nova Surge (Arbeitstitel)

Singleplayer-Wave-Shooter für den Browser (Ziel: CrazyGames).
Tech: Vite + three + TypeScript. Einzige Runtime-Dependency: three.

## Starten

```bash
cd nova-surge
npm install
npm run dev        # Entwicklung: http://localhost:5173
```

## Bauen & Build testen

```bash
npm run build      # Typecheck + Production-Build nach dist/
npm run preview    # dist/ lokal serven: http://localhost:4173
```

## Steuerung

**Desktop:** WASD bewegen · Shift Sprint · Space Sprung (Doppelsprung als
Upgrade) · Maus zielen · Linksklick feuern · R nachladen · 1/2/3 Upgrade
wählen · ESC Pause · F3 Debug-Overlay

**Mobile:** linke Hälfte Move-Stick · rechte Hälfte Blick-Drag · Feuer-Button
oder Auto-Fire (im Menü umschaltbar) · Sprung-/Reload-Buttons

## Spielablauf

Wellen überleben → nach jeder Welle 1 aus 3 Upgrades → **jede 5. Welle ein
Boss** (Warden: Projektil-Ring, drüberspringen!) → Tod → Münzen nach
Score → im Menü Waffen (Scatter Gun, Longshot DMR) und 8 Farbschemata
freischalten. Perfect-Wave-Bonus (+500 ohne eigenen Schaden), Musik
abschaltbar im Menü. **5 Arenen** zur Wahl: Foundry (ausgewogen), Frostworks
(enge Lanes), Sunreach (offener Canyon), Azure Deck (Yacht bei
Sonnenuntergang) und Grand Gallery (Einkaufszentrum mit Neon-Läden).
Highscore und Fortschritt liegen in localStorage.

## Projekt-Doku

- `CLAUDE.md` — Projektregeln und Constraints (oberste Instanz)
- `PHASEN.md` — der Bauplan (Phase 0–6 mit Gates)
- `STATUS.md` — aktueller Stand, Gate-Checks, offene Punkte
- `SUBMISSION.md` — fertiges Abgabe-Material für das CrazyGames-Portal

## Architektur (Kurzfassung)

- `src/core/` — Simulation, fester 60-Hz-Takt, kein three-Import
- `src/render/` — three-Szene, liest Sim-Zustand + Events, interpoliert
- `src/config/` — ALLE Balancing-Werte (Waffen, Gegner, Wellen, Preise)
- `src/ui/` — DOM-HUD und Menüs · `src/audio/` — prozeduraler WebAudio-Sound
- `src/platform/CrazySdk.ts` — SDK-Adapter, lokal komplett no-op
