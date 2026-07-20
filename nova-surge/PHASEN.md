# Nova Surge — Bauplan

Regeln: genau EINE Phase pro Arbeitsauftrag. Kein Feature aus einer späteren Phase
beginnen, bevor das Gate der aktuellen Phase in STATUS.md dokumentiert erfüllt ist.
Jedes Feature zahlt auf Conversion, Spielzeit oder Retention ein — sonst streichen.

## Phase 0 — Setup & Loop
Vite-Projekt mit three. Pointer-Lock (Klick = fangen, ESC = Pause-Menü).
Fixed-Timestep-Gameloop (Simulation 60 Hz, Rendering entkoppelt, Interpolations-Alpha).
Resize-Handling. Debug-Overlay: FPS, Draw Calls, aktive Entities (per Taste togglebar).

**Gate:** Leere Szene mit Boden + Licht läuft stabil 60 FPS, Pause/Resume sauber,
kein Speicherleck nach 5 Min Laufzeit (Heap-Check).

## Phase 1 — Gunfeel (wichtigste Phase des Projekts)
Movement: WASD, Sprint, Sprung. Beschleunigung/Reibung so tunen, dass Richtungswechsel
sofort reagieren. Leichtes Head-Bob, FOV-Kick beim Sprint.
Eine Waffe (Hitscan-Sturmgewehr): Raycast mit Spread, Rückstoß als Kamera-Kick mit
Recovery, Muzzle-Flash, Tracer-Linie, Hülsen-Partikel, Einschlag-Partikel an Wänden.
Hitmarker (UI-Kreuz + Klick-Sound). Magazin + Nachladen mit Animation (Waffe kippt
aus dem Bild).
Sound komplett über WebAudio prozedural: Schuss (Noise-Burst + Lowpass), Treffer-Tick,
Nachladen. Kein einziges Audio-File.
Schießstand: statische Ziel-Dummies, die umfallen und nach 2 s respawnen.

**Gate — der 30-Sekunden-Test:** Nur auf Dummies schießen muss sich bereits
befriedigend anfühlen. Prüffrage: Würde jemand freiwillig 2 Minuten auf Ziele ballern,
ohne dass es Gegner gibt? Wenn nein: Feel iterieren (Recoil, Sound, Hitmarker-Timing)
— NICHTS Neues bauen, bis ja.

## Phase 2 — Gegner
Drei Bot-Typen, visuell klar unterscheidbar (Form + Farbe, Low-Poly aus Primitiven):
- **Rusher:** schnell, Nahkampf, wenig HP
- **Shooter:** hält Distanz, strafed seitlich, feuert Bursts mit sichtbaren
  Projektilen (ausweichbar)
- **Tank:** langsam, viel HP, Dauerdruck

FSM pro Bot: Idle → Alert → Attack → Hitreact → Death. Sichtlinien-Check per Raycast.
Navigation ohne Navmesh: offene Arena + Steering (Ziel anlaufen, Hindernisse umfließen,
Separation von anderen Bots).
Trefferfeedback: Flinch, kurzer Weiß-Flash am Material, Tod = Zerplatzen in Partikel
oder Umkippen mit Fade. Spieler: HP, Schadens-Vignette, Tod, Restart-Screen mit Score.

**Gate:** Ein 1-gegen-5-Kampf ist lesbar (man weiß immer, woher Schaden kommt), fair
(Shooter-Projektile ausweichbar), kein Bot bleibt je in Geometrie stecken
(10-Minuten-Beobachtungstest).

## Phase 3 — Arena & Wave-Loop
Eine Arena. Erst Graybox aus Boxen: klare Sichtachsen, Deckung, maximal 2 Höhenebenen,
kein toter Winkel ohne zweiten Ausgang. Dann Low-Poly-Verkleidung mit konsistenter
Farbpalette (2–3 Grundfarben + 1 Akzent).
Wellensystem: Welle n skaliert Anzahl und Typ-Mix nach fester Tabelle (in eigener
Config-Datei, leicht tunebar). 5 s Pause zwischen Wellen mit Ankündigungs-UI.
Score: Kills, Multiplikator steigt bei Treffern ohne eigenen Schaden, resettet bei Hit.
Highscore in localStorage.

**Gate:** Ein kompletter Run (Start → Tod) dauert beim ersten ernsthaften Versuch
3–6 Minuten und endet knapp genug, dass ein „einmal noch"-Impuls entsteht.
Difficulty-Tabelle entsprechend tunen und den Tuning-Stand dokumentieren.

## Phase 4 — Progression (hier sind die Vorgängerprojekte gestorben — wird fertig gebaut)
In-Run: Nach jeder Welle Wahl 1-aus-3 (zufällig gezogen): +Schaden, +Feuerrate,
+Magazin, +Movement-Speed, Lifesteal, Doppelsprung. Stapelbar, einfache Synergien.
Meta (persistent, localStorage): Münzen pro Run nach Score. Freischaltbar: zwei
weitere Waffen mit eigenem Feel (Shotgun: echte Projektil-Spread, brutal nah;
DMR: langsam, hart, präzise) und 3–4 Farbschemata für Waffe/Hände. Preise so, dass
der erste Unlock nach ~3 durchschnittlichen Runs erreichbar ist.

**Gate:** Für Run 2 und Run 5 existiert je ein konkreter, in einem Satz benennbarer
Grund weiterzuspielen („Ich will die Shotgun in 2 Runs" zählt; „es macht halt Spaß"
zählt nicht). Beide Sätze in STATUS.md eintragen.

## Phase 5 — Mobile & Performance
Touch-Steuerung: linke Bildschirmhälfte = virtueller Move-Stick (erscheint am
Touchpunkt), rechte Hälfte = Blick per Drag. Feuern: beide Varianten bauen (Auto-Fire
bei Ziel unterm Fadenkreuz vs. Feuer-Button rechts unten), 5 Testrunden spielen, eine
wählen, andere entfernen. UI-Elemente auf Daumen-Reichweite prüfen.
Performance-Pass: Pooling-Audit (null Allokationen im Gameplay-Loop), Partikel-Budget
pro Frame, Schatten auf Mobile aus, optional dynamische Auflösungsskalierung wenn
FPS < 55.

**Gate:** 60 FPS in Chrome auf Mittelklasse-Android; komplettes Spiel ohne Tastatur
durchspielbar; kein UI-Element vom Daumen verdeckt.

## Phase 6 — CrazyGames-Integration & Abgabe
SDK laut aktueller CrazyGames-Doku (docs.crazygames.com) einbauen: Init,
Loading-Events (Start/Stop), gameplayStart/gameplayStop korrekt bei Pause/Menü/Tod,
Midgame-Ad in der Wellenpause (NIE im Gefecht), Rewarded Ad an genau zwei Stellen:
1× Revive nach Tod ODER Münzen ×2 am Run-Ende. Happytime-Event bei neuem Highscore.
Abgabe-Material: eigenständiger Spielname, 1-Satz-Hook, Beschreibung (EN),
Steuerungserklärung, Thumbnail-Konzept (Spielfigur + Mündungsfeuer, bei 200 px
Breite noch lesbar).
Build-Check: Größe ≤ 20 MB, Ladezeit < 5 s, Konsole fehlerfrei, Preview im
CrazyGames-Entwicklerportal auf Desktop + Mobile getestet.

**Gate:** Build läuft im Portal-Preview fehlerfrei auf beiden Gerätetypen; alle
SDK-Events nachweislich gefeuert (Konsolen-Log).

## Definition of Done (Gesamtprojekt)
1. Kaltstart bis Gameplay in unter 10 Sekunden (Conversion).
2. Erster Run 3–6 Minuten; für Run 2 und Run 5 existiert je ein benennbarer
   Wiederspiel-Grund (Playtime/Retention).
3. 60 FPS auf Desktop und Mittelklasse-Mobile.
4. Null externe Assets, null Markenbezüge.
5. SDK-Events vollständig und korrekt.
6. STATUS.md lückenlos: jede Phase mit dokumentiertem Gate-Check.
