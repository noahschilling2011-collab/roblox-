# Nova Surge (Arbeitstitel)

Singleplayer-Wave-Shooter für den Browser (Ziel: CrazyGames).
Tech: Vite + three + TypeScript. Keine weiteren Runtime-Dependencies.

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

## Steuerung (Stand Phase 0)

- Klick auf „CLICK TO PLAY" → Maus wird gefangen (Pointer Lock), Spiel läuft
- Maus → umsehen
- ESC → Pause-Menü
- F3 → Debug-Overlay (FPS, Frame-Zeit, Sim-Ticks, Draw Calls, Entities, Heap)

## Projekt-Doku

- `CLAUDE.md` — Projektregeln und Constraints (oberste Instanz)
- `PHASEN.md` — der Bauplan (Phase 0–6 mit Gates)
- `STATUS.md` — aktueller Stand, Gate-Checks, offene Punkte
