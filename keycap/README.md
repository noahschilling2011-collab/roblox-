# KEYCAP RUSH

Eigenständiges Spiel im selben Repo (wie `turmfall/`). Berührt PlanetForge nicht.

## Warnung vorweg

Das KEYCAP-RUSH-Konzeptdokument liegt **nicht** im Repo. Bekannt sind daraus nur die
Formeln, die `docs/KEYCAP_RUSH_BEWERTUNG.md` wörtlich zitiert. Alles andere — Kartenaufbau,
Klau-Ablauf, Datenschema, UI — ist **von mir entschieden**, nicht aus deinem Konzept.
Im Code steht an jedem Wert, woher er kommt: `[KONZEPT]`, `[GEMESSEN]`, `[ABGELEITET]`,
`[ENTSCHEIDUNG]`.

**Nichts davon lief je in Roblox.** Geprüft sind: Syntax aller 23 Dateien im echten
Luau-Compiler, und 45 Logik-/Balancing-Tests in einer echten Luau-VM. Nicht geprüft ist
jeder Roblox-API-Aufruf zur Laufzeit — Instanzen, Prompts, Welds, DataStore, Replikation.
Der erste Studio-Start wird Fehler zeigen.

## Was gebaut ist

| Datei | Was sie macht |
|---|---|
| `shared/Config/EconomyConfig` | alle Balancing-Werte, mit Herkunftsmarkierung |
| `shared/Config/WorldConfig` | Plot-Raster, Torpositionen, Padpositionen |
| `shared/EconomyLogic` | reine Rechenlogik, läuft in Server und Test identisch |
| `shared/Remotes` | einziger Ort, an dem RemoteEvents entstehen |
| `shared/RateLimit` | Token-Eimer pro Spieler und Kanal |
| `shared/Theme` | Farben und Font, nichts wird in Controllern hardcodiert |
| `server/DataService` | Profil, **Session-Lock**, Autosave 45 s, `BindToClose` |
| `server/PlotService` | baut Plots, vergibt sie, hält Tasten-Parts synchron |
| `server/ProductionService` | jede Taste produziert ihren eigenen Vorrat |
| `server/SpeedService` | setzt WalkSpeed aus dem Vorrat, Trage-Malus |
| `server/CourseService` | Speed-Tore und Cash-Out-Pads (ProximityPrompt) |
| `server/StealService` | Klau mit Paar-Cooldown, Anwesenheit, Schild |
| `server/CarryService` | geklaute Taste sichtbar über dem Kopf des Diebes |
| `server/NpcPlotService` | NPC-Plots als Klau-Ziele auf leeren Servern |
| `server/RunTimerService` | misst Rundlaufzeiten und gibt die Config-Zeile aus |
| `server/TutorialService` | vier Onboarding-Schritte, Fortschritt im Profil |
| `server/ShopService` | Tasten und Steckplätze kaufen |
| `server/StateService` | schickt den Zustand an die Clients |
| `client/HudController` | Vorrat, Rate, Wins, Schild-Knopf |
| `client/ShopController` | Laden-Panel |
| `shared/Config/TutorialConfig` | die vier Schritte samt Texten |

Server-autoritativ: der Client schickt nur `BuyKey`, `BuySlot`, `ActivateShield` — ohne
Beträge. Preis, Kontostand, Distanz, Besitz, Cooldown und Rate-Limit prüft der Server.

## Was NICHT gebaut ist

Monetarisierung (kein `ProcessReceipt`, keine Gamepässe), Tutorial, Sounds, Effekte,
Tageslogin, Rebirth. Das Konzept schließt Rebirth aus, der Rest ist schlicht nicht drin.

## Drei Entscheidungen, die du kippen kannst

1. **Vorrat wird beim Verlassen nicht gespeichert** (`PERSIST_VORRAT = false`).
   Sonst wäre Horten offline risikofrei — genau das Loch, das die Taste-hält-Vorrat-
   Änderung schließen soll. Gespeichert werden Wins, Slots und Tasten.
2. **Verlassene Plots verschwinden mit dem Besitzer.** Sonst wären sie unbewachte
   Beutekisten und der Anwesenheits-Bonus wäre wertlos. Im Konzept war das undefiniert.
3. **Leaderstats zeigen `Wins` und `Beute`** (Zahl geklauter Tasten), nicht den Vorrat.
   Die Rangliste eines Klau-Spiels soll Beute zeigen.

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

## Die eine Zahl, die noch fehlt — und wie du sie bekommst

`EconomyConfig.STAGE_RUN_SECONDS = { 40, 80, 140 }` ist **geschätzt**. Alle
Auszahlungsfaktoren und die Schilddauer hängen daran.

Du brauchst dafür keine Stoppuhr: `RunTimerService` misst mit. Er startet die Uhr,
wenn du deinen Plot verlässt, und stoppt sie, wenn du zurück bist — aber nur, wenn du
unterwegs **genau einmal** ausgezahlt hast (wer erst an Stage 1 und dann an Stage 3
kassiert, liefert für beide eine zu lange Zeit; solche Runden wirft er weg). Nach je
drei sauberen Läufen pro Stage schreibt er die fertige Zeile ins Output-Fenster:

```
[KEYCAP] STAGE_RUN_SECONDS = { 44 (3 Laeufe), 91 (3 Laeufe), 152 (3 Laeufe) }
```

Die Zahlen aus den Klammern in `EconomyConfig` eintragen, fertig. Sonst muss nichts
angefasst werden.

## NPC-Plots

Die Bewertung: *„Der Loop braucht Mitspieler und du hast keine."* Drei Plots am Ende
der Reihe gehören NPCs (`Alte Tastatur`, `Fundbüro`, `Schrottplatz`) und sind immer
beklaubar. Bewusst schwach gehalten, damit sie echte Spieler nicht ersetzen: nur
Common und Uncommon, Vorrat gedeckelt bei 1.200, eigene Abklingzeit von 45 s, und eine
geklaute Taste bleibt 60 s leer stehen statt zu verschwinden — so gehen dem Server nie
die Ziele aus. Ein NPC-Klau bringt an Stage 1 rund 12 Wins: genug für eine
Common-Taste, zu wenig, um damit hochzukommen.

## Part-Budget

Der schlimmste Fall — 12 Plots, alle Steckplätze voll, jeder Spieler trägt Beute —
liegt bei rund 240 Parts von 3.000. Der Server gibt die tatsächliche Zahl beim Start
aus. *Ungeprüft:* auf dem Handy ist vermutlich die Zahl gleichzeitiger
ProximityPrompts (~200 im Vollausbau) das engere Limit als die Part-Zahl. Nicht
gemessen — nur eine Schranke im Test, damit ein Zuwachs auffällt.

## Tests

```bash
cd keycap/tests
npm install
npm test
```

45 Tests in einer echten Luau-VM (WASM) plus Syntaxprüfung aller `src/`-Dateien im
echten Luau-Compiler. Exit-Code 0 = alles grün. Geprüft werden unter anderem die Zahlen
aus der Bewertung: Gates bei 700 / 1.700 / 2.950 Vorrat, Deckel bei 4.200, Stützwerte
90R / 150R / 174R — und dass jedes Tor vor seinem Pad steht und alle Steckplätze auf
den Plot passen.

## In Studio starten

1. In VS Code die Rojo-Extension auf `keycap/default.project.json` zeigen lassen
   (**nicht** auf die PlanetForge-Datei im Wurzelverzeichnis) und `Serve` starten.
2. Neues, leeres Place in Studio öffnen, im Rojo-Plugin `Connect`.
3. Play drücken. Im Output müssen diese Zeilen stehen:

```
[KEYCAP] Server startet ...
[KEYCAP] DataService bereit (Schema 2)
[KEYCAP] NpcPlotService: 3 NPC-Plots, Vorrat gedeckelt bei 1200
[KEYCAP] PlotService: 12 Plots gebaut
[KEYCAP] TutorialService: 4 Schritte, 50 Wins Belohnung
[KEYCAP] CourseService: 3 Stages gebaut, Schild 140s/280s
[KEYCAP] ProductionService laeuft (Label-Takt 2s)
[KEYCAP] SpeedService laeuft
[KEYCAP] CarryService laeuft (8s sichtbar)
[KEYCAP] StealService laeuft
[KEYCAP] ShopService laeuft
[KEYCAP] RunTimerService misst Rundlaufzeiten
[KEYCAP] StateService sendet alle 0.5s
[KEYCAP] Parts in workspace: ... von 3000 erlaubt
[KEYCAP] Server bereit.
[KEYCAP] Client bereit.
```

4. Erster Sichtcheck: du stehst auf einem creme-weißen Plot, zwei graue Tasten stehen
   drauf, links oben zählt „Vorrat" hoch, unten steht die Tutorial-Karte mit
   „Schritt 1: Deine Tasten sammeln von selbst …". Nach etwa 6 Minuten öffnet sich Stage 1.
   Zum Testen `START_KEY_SLOTS`-Tasten vorab geben oder `Common.vorratPerSecond`
   kurzzeitig hochsetzen — sonst dauert der erste Durchlauf zu lang zum Debuggen.
5. Klauen testen: du brauchst dafür **keinen** zweiten Spieler mehr — lauf ans Ende
   der Plotreihe zu `Alte Tastatur` und halte dort den Klau-Prompt. Über deinem Kopf
   muss danach eine farbige Taste mit „BEUTE: …" hängen und du läufst sichtbar
   langsamer. Für Klau zwischen echten Spielern: **Test → Players → 2**.

**Wichtig:** Studio-DataStores brauchen *Studio Access to API Services* in den
Spieleinstellungen. Ohne das schlägt jedes Speichern fehl und du wirst mit
„Deine Daten werden noch von einem anderen Server benutzt" gekickt.

## Servergröße

Stell die Platzgröße im Creator Dashboard auf **8–12**. `WorldConfig.PLOT_COUNT` ist 12,
davon gehen 3 an NPC-Plots — es bleiben 9 Spielerplots. Wer als zehnter joint, wird
mit „Der Server ist voll" abgewiesen, stell die Platzgröße also nicht höher als 9.
