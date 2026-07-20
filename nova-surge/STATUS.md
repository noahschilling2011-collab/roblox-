# Nova Surge — Projektstand

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
  (Ergebnis siehe unten), Konsole fehlerfrei.

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
