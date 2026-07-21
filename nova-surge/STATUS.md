# Nova Surge — Projektstand

## ⏸ RELEASE-CANDIDATE-PLAN: Phase 1 fertig — WARTE AUF FREIGABE für Phase 2
Arbeitsmodus laut `RELEASE-PLAN.md`: Phasen strikt sequenziell mit
Freigabe-Stopp nach jeder Phase.

### Phase 0 ✅ (DoD erfüllt)
`ARCHITEKTUR.md` erstellt, alle Diagnose-Zahlen verifiziert (Korrekturen:
Sinks 1.440 statt 1.410; keine Coin-Pickups → Magnetfeld-Ersatz),
Build-Baseline grün.

### Phase 1 ✅ (DoD erfüllt) — Upgrades 6 → 24
Freigegeben von Noah mit den 3 Design-Entscheidungen aus ARCHITEKTUR.md.
- **24 Upgrades:** 11 Common / 9 Rare / 4 Epic (unique). RunStats als
  zentrales Effekt-Objekt (`src/core/Stats.ts`), alle Zahlen in
  `config/upgrades.ts` VALUES. Metrik-Begründung: Build-Vielfalt pro Run →
  „nächstes Mal probier ich X" → Session-Länge + D1.
- **Rarity-Draft:** gemessen 66/27/7 auf Welle 1; Epic-Chance steigt auf
  17 % @ Welle 20 (Cap 18 %). Karten mit Rarity-Rahmen/Glow + Label.
- **Reroll:** 10 Coins vom Konto, verdoppelt pro Nutzung im Run (Taste R
  oder Button). Metrik: Coins bekommen In-Run-Wert → Rewarded „Coins ×2".
- **Combo-Verfall:** nach 4 s ohne Treffer −0,5/s Richtung ×1 („Flow State"
  +2 s/Stack). Belohnt Dauerdruck.
- **DoD-Nachweis (headless, 14/15 + Einzeltest):** Draft-Verteilung ✓,
  Combo-Verfall ✓, Reroll ✓, Durchschlag ✓, Dornen ✓, Twin Link (9 Pellets) ✓,
  Bullet Time (Tank 0,56 m vs. 1,26 m Bewegung beim Reload) ✓, Phoenix
  (Revive auf 40 HP, Ladung verbraucht, Ad-Revive bleibt) ✓, Chain Lightning
  (3 Nachbarn verletzt) ✓, Ricochet separat an naher Wand verifiziert
  (Suite-Testdesign-Fehler: Wand lag außerhalb der 23-m-Pellet-Reichweite;
  Ergebnis: ohne Upgrade 0, mit Upgrade 8 überlebende Pellets) ✓,
  **3 Crash-Läufe bis Welle 12 ohne Fehler** ✓, Konsole sauber ✓.
- **Nächster Schritt:** Freigabe durch Noah → Phase 2 (Wave-Director:
  Elites, Wave-Events, Boss-Inszenierung).

Letzte Session: 2026-07-20 · Stand: **Phasen 0–6 komplett + Content-Update** ·
Code-seitige Gates bestanden, manuelle Checks für Noah unten.

## Content-Update (nach Phase 6, auf Noahs Wunsch)
Scope-Entscheidung: Multiplayer/Open World abgelehnt (harte Constraints),
stattdessen Content-Ausbau innerhalb der Regeln:
- **3 Arenen** statt 1, im Menü frei wählbar, Auswahl persistent:
  Foundry (symmetrisch, ausgewogen) · Frostworks (enge Lanes, 56 m) ·
  Sunreach (offener Canyon, 72 m, DMR-freundlich). Alle Arenen sind reine
  Config (`src/config/arena.ts`) — neue Map = neuer Eintrag, kein Code.
- **Bot-Optik überarbeitet:** Beine mit Laufanimation, Arme/Klingen,
  Schulterpanzer, Glow-Augen/-Kerne, Shooter-Lauf mit Burst-Rückstoß,
  Rusher lehnen sich beim Sprinten vor. Weiterhin 100% Primitiven.
- **8 Farbschemata** statt 4 (Preise 80–250, Gold Rush als Grind-Ziel).
- Headless verifiziert: Map-Wechsel 6/6, kompletter Bot-Run auf Frostworks
  **13/13** (Tod nach 154 s in Welle 7, kein Bot steckengeblieben trotz enger
  Lanes, Heap-Drift 1,09 MB, Konsole fehlerfrei).

## Update 2 (gleiche Session): Themen-Maps Yacht + Einkaufszentrum
- **5 Arenen** insgesamt. Neu: **Azure Deck** (Sonnendeck einer Yacht bei
  Sonnenuntergang — Deck-Spielfläche 26×40 m, Bordwände, Kabine als Deckung,
  Pool, Bugspitze im Wasser, Spawns als Leucht-Pads) und **Grand Gallery**
  (helles Einkaufszentrum — 8 Ladenfronten mit Neonschildern, Springbrunnen,
  Pflanzkübel, Glasdach-Träger).
- Neues **Props-System**: rein dekorative Elemente pro Arena (ohne Kollision;
  Regel: nie auf Körperhöhe im Laufweg — nur flach, auf Deckungen oder über
  Kopf). Grid pro Arena abschaltbar (Yacht: aus, Mall: Fliesenfugen).
- Headless: Map-Test 8/8 über alle 5 Arenen · Bot-Run auf der Yacht **13/13**
  (Tod nach 173 s in Welle 8, kein Bot steckengeblieben, Heap-Drift 1,09 MB,
  Konsole fehlerfrei).
- **Bug-Jagd (Multi-Agent + manuelle Verifikation): 6 echte Bugs gefunden
  und gefixt.** Transparenz: Die Agenten-Prüfung lief wegen Session-Limits
  nur über die Bereiche Simulation/Movement (2 von 6 Findern); die
  adversarialen Prüf-Agenten fielen komplett aus — jeder Fund wurde daher
  von Hand am Code verifiziert. UI/Render/Platform/Timing sind bisher NUR
  durch die Integrationstests abgedeckt, nicht durch Agenten-Review.
  Die Fixes:
  1. `rayVsSphere`: Ursprung in der Hitbox = Treffer (vorher gingen
     Punktblank-Schüsse durch bedrängende Tanks hindurch, und Mobile-
     Auto-Fire stoppte genau dann).
  2. Shotgun-Pellets: Schaden geht jetzt exakt an den vom Raycast
     getroffenen Gegner (vorher Nächster-Nachbar-Suche — im Pulk bekam
     regelmäßig der falsche Gegner den Schaden).
  3. Nahkampf prüft Sichtlinie: Tanks/Rusher schlagen nicht mehr durch
     Blöcke (Spieler auf LOW-Deckung) oder um Deckungsecken.
  4. Wellenende räumt fliegende Gegner-Projektile ab + Spieler ist in der
     Upgrade-Wahl unverwundbar (vorher: Tod im Upgrade-Screen möglich).
  5. Revive stellt eine noch offene Upgrade-Wahl wieder her statt sie zu
     verschlucken.
  6. In der Luft getötete Gegner fallen zu Boden statt schwebend zu
     verblassen; Schadensrichtungs-Pfeil im HUD zeigt jetzt ZUM Angreifer
     (war um 180° gedreht).
  7. Mobile-Auto-Fire mit Semi-Waffen (Scatter/DMR): feuerte genau EINMAL
     und dann nie wieder (Dauer-True erzeugt keine Tastenflanken). Auto-Fire
     pulst jetzt für Semi-Waffen. Gefunden durch den Bot-Test — der Bot
     hatte exakt dasselbe Problem wie ein Handy-Spieler gehabt hätte.
- Abschlusstest nach allen Fixes: Bot-Run mit **Scatter Gun auf Grand
  Gallery 13/13** (Tod nach 148 s in Welle 6, 36 Kills, kein Bot
  steckengeblieben, Heap-Drift 0,84 MB, Konsole fehlerfrei).

## Update 3 (gleiche Session): Juice & Boss Update
Auf Noahs Freibrief („mach was du denkst") — alles zahlt auf Retention ein:
- **Boss-Wellen:** Jede 5. Welle bringt den **Warden** (golden, 850 HP ×
  Skalierung, Krone + Glutkern). Feuert alle 3,4 s einen flachen 12-Projektil-
  Ring auf Brusthöhe — überspringbar (Doppelsprung-Synergie), plus harter
  Nahkampf. Kommt mit Eskorte, ab Welle 15 mehrere. Boss-Kill: großer
  Partikel-Burst, Screen-Shake, eigener Sound, SDK-`happytime()`.
- **KRITISCHER FIX: Projektile waren unsichtbar!** Es gab keinen
  Projektil-Renderer — Shooter-Geschosse haben unsichtbar getroffen (Gate
  „sichtbar & ausweichbar" verletzt, von keinem Headless-Test erkennbar).
  Jetzt: InstancedMesh-Renderer, Gegner-Schüsse violett leuchtend,
  Shotgun-Pellets orange, interpoliert.
- **Perfect Wave:** Welle ohne eigenen Schaden = +500 Punkte + Banner + Sound.
- **Score-Popups** an der Kill-Stelle (3D→2D projiziert, DOM-Pool),
  Boss-Kills groß in Orange.
- **Screen-Shake** bei eigenem Schaden (skaliert mit Schadenshöhe) und
  Boss-Tod.
- **Prozedurale Musik:** 116-BPM-Beat (Kick/Hat/Bass) über WebAudio-
  Lookahead-Scheduler, Intensität steigt mit der Wellennummer, läuft nur
  während des Runs. Im Menü abschaltbar (persistiert). Kein Audio-File.
- Death-Screen zeigt jetzt auch „Best wave".
- Boss-Mechanik-Test headless 4/4 (Spawn auf Welle 5, Ring ≥8 Projektile
  sichtbar, stirbt unter Beschuss, Konsole sauber).
- **Anti-Hänger-Logik** nachgerüstet: Der verschärfte Stuck-Detektor fand im
  Langlauf 4 weiche Hänger (Shooter strafen in Wände, Tanks pressen gegen
  Blöcke bei campendem Spieler). Fix: Wer trotz Bewegungswunsch >1,6 s kaum
  vorankommt, weicht 1,1 s senkrecht aus. Verifiziert: Folgelauf **stuck=0**.
- **Balance-Hinweis (ehrlich):** Bot-Run-Längen streuen mit Boss-Wellen
  stark (92–307 s, je nachdem ob der zufalls-strafende Bot den ersten Boss
  überlebt — er springt nicht bewusst über Ringe, Menschen schon).
  Ring-Cooldown nach den Läufen 3,4 → 4,0 s entschärft. Die finale
  Boss-Balance-Einschätzung braucht Noahs echten Playtest (Welle 5!).

> Hinweis zur Arbeitsweise: Auf ausdrückliche Anweisung („mach alles jetzt")
> wurden Phasen 1–6 in EINEM Auftrag gebaut — abweichend von der
> Eine-Phase-Regel in CLAUDE.md. Alle automatisiert prüfbaren Gates wurden
> headless verifiziert (Playwright + Bot-Spieler); Gefühls- und Geräte-Gates
> stehen unten als manuelle Checkliste.

## Gate-Status pro Phase

### Phase 0 — Setup & Loop ✅ (bestanden am 2026-07-20)
11/11 Headless-Checks: 60-Hz-Sim entkoppelt vom Rendering, Pointer Lock,
Pause/Resume, Resize, 5-Min-Heap-Soak (Drift 0,04 MB), Konsole fehlerfrei.

### Phase 1 — Gunfeel ✅ code-seitig / 🔶 Gefühls-Gate = Noah
Gebaut: WASD/Sprint/Sprung (+Coyote-Time), Hitscan-AR mit Spread-Wachstum,
Recoil mit Recovery, Muzzle-Flash, Tracer, Hülsen-/Einschlag-Partikel,
Hitmarker (UI + Klick-Sound), Magazin/Reload mit Kipp-Animation, kompletter
Sound prozedural (WebAudio, null Audio-Files), Head-Bob + Sprint-FOV-Kick.
**Offen (30-Sekunden-Test):** „Würde jemand freiwillig 2 Minuten auf Ziele
ballern?" — kann nur ein Mensch beurteilen. Wenn nein: Tuning-Schrauben in
`src/config/weapons.ts` (recoilPitch, soundBody) und `src/config/tuning.ts`.

### Phase 2 — Gegner ✅
Drei klar unterscheidbare Typen (roter Kegel-Rusher, violetter Shooter mit
Lauf, grüner Tank-Block), FSM Spawn→Alert→Attack→Hitreact→Death,
LOS-Raycasts, Steering mit Hindernis-Umfließen + Separation, Flinch/
Weißblitz/Umkippen, Schadens-Vignette + Richtungsindikator, Death-Screen.
**Gate-Messung (Bot-Lauf, 148 s):** kein Gegner steckengeblieben (Stuck-
Detektor über kompletten Run), Shooter-Projektile 16 m/s = ausweichbar,
Rusher springen auf 1,1-m-Blöcke (kein Camping). Lesbarkeits-Endurteil: Noah.

### Phase 3 — Arena & Wave-Loop ✅ mit Tuning-Vorbehalt
Arena 64×64 aus Config (4 hohe L-Deckungen, 5 besteigbare Low-Blöcke,
4 markierte Spawn-Tore, 2 Höhenebenen), Wellentabelle in
`src/config/waves.ts`, 5-s-Pausen mit Countdown-Banner, Score mit
Multiplikator (+0,1/Treffer, Reset bei eigenem Schaden, max ×5), Highscore
in localStorage.
**Tuning-Stand:** Bot (nahezu perfektes Aim = Obergrenze) stirbt nach
**2:28 in Welle 7** (Score 23.180). Menschlicher Erst-Run wird auf 3–5 min
und Welle 4–6 geschätzt → im Gate-Fenster 3–6 min. Kalibrierung nach Noahs
ersten echten Runs ggf. in `waves.ts` nachziehen (Werte pro Welle, 1 Zeile).

### Phase 4 — Progression ✅
In-Run: 1-aus-3 nach jeder Welle (Damage/Feuerrate/Magazin/Speed/Lifesteal/
Doppelsprung, stapelbar, Wahl per 1/2/3 oder Tap). Meta: Münzen = Score/60,
Scatter Gun 140 · Longshot DMR 320 · 3 kaufbare Farbschemata (80–120),
alles persistent (localStorage, Schema v1). Headless verifiziert: Kauf,
Auswahl, Persistenz über Reload, Shotgun-Projektile real.
**Gate-Sätze (Wiederspiel-Gründe):**
- Run 2: „Ich habe ~70 Münzen — noch ein Run, dann hole ich die Scatter Gun
  für 140."
- Run 5: „Mit der Scatter Gun knacke ich Welle 8 und spare auf den Longshot
  (320) — mein letzter Run endete in Welle 7 knapp unterm Highscore."
(Münz-Schätzung menschlicher Durchschnitts-Run: 40–80 → erster Unlock nach
~2–3 Runs. Bot-Runs liegen darüber; nach echten Runs ggf. COIN_DIVISOR in
`src/config/meta.ts` anpassen.)

### Phase 5 — Mobile & Performance ✅ code-seitig / 🔶 Geräte-Gate = Noah
Touch: Move-Stick erscheint am Touchpunkt (volle Auslenkung = Sprint),
Blick-Drag rechts, Sprung-/Reload-Buttons, Pause-Button. **Beide
Feuer-Varianten gebaut** (Auto-Fire bei Ziel unterm Fadenkreuz ↔
Feuer-Button), umschaltbar im Menü. Headless-Touch-Emulation: 9/9 Checks.
Performance: feste Pools überall (Gegner/Projektile/Partikel/Tracer/Events,
Heap-Drift im Gefecht 0,85 MB), Partikel als EIN InstancedMesh, keine
Schatten, Antialias auf Touch-Geräten aus, dynamische Auflösungsskalierung
ab FPS < 55 (bis 0,55×, erholt sich automatisch).
**Offen:** 60 FPS auf echtem Mittelklasse-Android prüfen (F3-Overlay);
5 Testrunden spielen → EINE Feuer-Variante wählen, die andere entfernen
(`autoFire` in SaveData + Toggle in `Screens.ts`).

### Phase 6 — CrazyGames-Integration ✅ code-seitig / 🔶 Portal-Gate = Noah
SDK v3 laut docs.crazygames.com: Init + loadingStart/Stop,
gameplayStart/Stop an alle Modi-Wechsel gebunden, Midgame-Ad NUR in der
Wellenpause (frühestens Welle 3, dann ≥3 Wellen und ≥120 s Abstand),
Rewarded an genau zwei Stellen (Revive nach Tod, einmal pro Run · Münzen ×2
am Run-Ende), happytime bei neuem Highscore, Ad-Pause muted Audio + hält die
Sim an. Lokal/offline ist der Adapter komplett no-op (Konsole bleibt sauber,
headless verifiziert inkl. ?cg=1-Fallback). Abgabe-Material fertig in
`SUBMISSION.md` (Name, Hook, Beschreibung EN, Steuerung, Thumbnail-Konzept).
**Offen:** Upload ins Entwicklerportal + Preview-Test Desktop/Mobile + 
SDK-Events im Portal-Log nachweisen (Checkliste in SUBMISSION.md).

## Automatisierte Testläufe (Production-Build, headless Chromium)
- Bot-Gameplay: **13/13** — kompletter Run bis Tod, Restart, Quit,
  Münz-Gutschrift, Persistenz nach Reload, Shop-Kauf, Konsole fehlerfrei.
- Mobile-Emulation: **9/9** — Stick, Blick-Drag, Feuer-/Pause-Buttons,
  SDK-Fallback.
- Sim-Rate konstant 60/s über alle Läufe, unabhängig von der Render-FPS.

## Manuelle Checkliste für Noah (im Browser, `npm run dev`)
1. **Phase-1-Gate:** 2 Minuten nur ballern (erste Welle ignorieren, ESC →
   nein, einfach in der Prewave-Zeit + Welle 1 aufs Gefühl achten): Wumms
   okay? Hitmarker-Klick befriedigend? Wenn nein → sag mir was fehlt
   (z. B. „mehr Bass", „mehr Kick", „Hitmarker früher").
2. **Run-Länge:** Erster ernsthafter Run — Stoppuhr: 3–6 min bis Tod?
   Welle notieren.
3. **ESC/Pause:** ESC → Menü sofort da, RESUME klappt (nach ESC blockt
   Chrome ~1 s — zweiter Klick geht).
4. **F3-Overlay:** FPS stabil ~60 auf deinem PC?
5. **Handy** (im gleichen WLAN: `npm run dev -- --host`, dann die
   Netzwerk-URL am Handy öffnen): 60 FPS? Daumen verdeckt kein UI?
   Auto-Fire vs. Feuer-Button — 5 Runden, Favorit sagen.

## Bekannte Grenzen (bewusst, v1)
- Münzen eines Runs verfallen, wenn der Tab AUF dem Death-Screen geschlossen
  wird (Gutschrift erfolgt beim Verlassen des Screens — verhindert
  Revive-Doppelgutschrift).
- SDK-Verhalten (Ads, happytime) ist lokal nicht testbar — nur im
  CrazyGames-Portal-Preview.
- Kein Multiplayer, eine Arena, drei Waffen — per Design (siehe CLAUDE.md).
