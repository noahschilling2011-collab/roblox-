# KEYCAP RUSH — Ökonomie-Kern

Eigenständiges Projekt im selben Repo (wie `turmfall/`). Berührt PlanetForge nicht.

## Was hier drin ist — und was nicht

Gebaut ist **nur die Ökonomie-Rechnung**, nicht das Spiel. Grund: das
KEYCAP-RUSH-Konzeptdokument liegt nicht im Repo. Bekannt sind daraus nur die
Formeln, die in `docs/KEYCAP_RUSH_BEWERTUNG.md` wörtlich zitiert werden. Plots,
Parcours, Klau-Ablauf, DataStore und UI stehen deshalb noch nicht hier — die
würden zu großen Teilen erfunden.

Die Bewertung hat zwei Löcher benannt. Beide sind hier geschlossen:

| Loch aus der Bewertung | Antwort hier |
|---|---|
| Tastenpreis und `speedPerSecond` fehlen | `EconomyConfig.RARITIES` — 5 Stufen mit Rate und Preis |
| 0,01 / 0,025 / 0,05 macht Stage 3 alternativlos (5× für 3,5× Zeit) | Faktoren werden aus den Rundlaufzeiten **abgeleitet** statt gesetzt |

## Die abgeleiteten Zahlen

Auszahlungsfaktoren kommen aus `EconomyLogic.payoutFactors()`. Grundgedanke:
Wären alle Pads gleich viel wert, entschiede nur noch das Risiko — genau das
will das Design. Also Gleichstellung als Basis, plus 12 % Bonus pro Stage,
damit der Umweg sich lohnt, ohne zu dominieren.

| | Stage 1 | Stage 2 | Stage 3 |
|---|---|---|---|
| Faktor (abgeleitet) | 0,0200 | 0,0250 | 0,0325 |
| Konzept-Faktor | 0,01 | 0,025 | 0,05 |
| Wins bei Vorrat 4.200 | 84 | 105 | 136 |
| Wins/h je Produktionseinheit (300 s halten) | 63,5 | 71,2 | 79,7 |

Stage 3 gibt jetzt ~25 % mehr statt 400 % mehr. Stage 1 bleibt spielbar.
Stage 2 landet fast exakt auf dem Konzept-Wert 0,025 — gutes Zeichen.

Tasten (Preis pro Produktionseinheit steigt bewusst, damit **Steckplätze** der
Engpass sind, nicht Wins):

| Seltenheit | Vorrat/s | Preis | amortisiert nach |
|---|---|---|---|
| Common | 1 | 10 | 500 s |
| Uncommon | 3 | 40 | 667 s |
| Rare | 9 | 150 | 833 s |
| Epic | 30 | 600 | 1.000 s |
| Legendary | 100 | 2.500 | 1.250 s |

Schild: **140 s Schutz / 280 s Abklingzeit** statt 45 / 180. Das Konzept-Schild
war kürzer als ein Stage-3-Rundlauf und schützte damit genau die Situation
nicht, für die es da ist. Jetzt deckt es einen kompletten Lauf ab, aber nur
jeden zweiten — welchen Lauf du schützt, ist eine Entscheidung.

Klau (Änderung aus Abschnitt 6 der Bewertung): jede Taste hält ihren eigenen
Vorrat, der Plot-Vorrat ist die Summe. Ein Dieb bekommt 50 % des Tastenvorrats,
gedeckelt bei 5.000 — der Rest verfällt. Damit ist Horten nicht mehr gratis.

## Die eine Zahl, die noch fehlt

`EconomyConfig.STAGE_RUN_SECONDS = { 40, 80, 140 }` ist **geschätzt**. Sobald der
Parcours in Studio steht: einmal mit der Stoppuhr Plot → Pad → Plot messen und
eintragen. Alle Faktoren und die Schilddauer rechnen sich daraus neu, es muss
sonst nichts angefasst werden.

## Tests

```bash
cd keycap/tests
npm install
npm test
```

Lädt die echten Module in eine echte Luau-VM (WASM). Exit-Code 0 = alles grün.
Prüft unter anderem die Zahlen aus der Bewertung gegen: Gates bei 700 / 1.700 /
2.950 Vorrat, Deckel bei 4.200, und die Stützwerte 90R / 150R / 174R.
