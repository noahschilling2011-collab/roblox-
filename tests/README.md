# Planet Forge – Testlauf

Führt die **echten Shared-Module** des Spiels (`src/shared/`) in einer echten
Luau-VM (WASM, Paket [`luau-web`](https://www.npmjs.com/package/luau-web)) aus
und prüft Logik und Balancing – ganz ohne Roblox Studio:

- Canon-Konstanten (12 Slots, Kosten, Cooldowns, Schema-Version)
- alle 10 Biome exakt (Kosten, Freischaltung, Einkommen) + Upgrade-Formel
- Seltenheits-Gewichte und die Ultra-Rare-Chancen (1:10.000 / 1:100.000 / 1:1.000.000)
- Sammelobjekt-Pools (Ultra-Rares nie im normalen Pool)
- alle 5 globalen Events exakt
- Monetarisierungs-Katalog (alle Verweise gültig, Platzhalter-IDs matchen nie)
- `WeightedRandom`: statistische Verteilungstests mit 300.000 Würfen
- Loot-Wurf-Simulation (50.000 Würfe) und Loot-Glücks-Formel
- Tagesbonus-Logik (Streak, Reset, Deckelung, kein Doppel-Bonus)

## Ausführen

Voraussetzung: [Node.js](https://nodejs.org) 18+

```bash
cd tests
npm install
npm test
```

Exit-Code 0 = alles grün. Zusätzlich prüft der `SelfCheckService` dieselben
Invarianten bei jedem Serverstart direkt in Roblox Studio (Output-Fenster).
