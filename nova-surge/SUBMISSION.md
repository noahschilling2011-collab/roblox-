# CrazyGames-Abgabe — Material (Phase 6)

Alles hier ist copy-paste-fertig für das CrazyGames-Entwicklerportal
(https://developer.crazygames.com). Das Hochladen selbst ist ein manueller
Schritt — siehe Checkliste unten.

## Spielname
**Nova Surge**
(eigenständig, kein Markenbezug; Verfügbarkeit des Namens beim Einreichen
im Portal prüfen — bei Kollision Alternativen: "Surge Arena", "Polygon Surge")

## 1-Satz-Hook (EN)
> Blast through endless enemy waves in a lightning-fast arena shooter — stack
> upgrades, chase your highscore, and never stop moving.

## Beschreibung (EN, für die Spielseite)
Nova Surge is a fast-paced singleplayer arena shooter. Survive endless waves
of three distinct enemy types: dodge the swarming Rushers, outmaneuver the
strafing Shooters, and take down the massive Tanks before they corner you.

After every wave, pick one of three upgrades — stack damage, fire rate,
lifesteal or a double jump and build your own power fantasy. Earn coins with
every run and unlock two more weapons with completely different handling:
the brutal close-range Scatter Gun and the precise, hard-hitting Longshot DMR.

How far can you get before the arena overruns you?

- Fast, responsive movement — sprint, jump, strafe
- 3 enemy types with clear roles, endless scaling waves
- 1-of-3 upgrade choice after every wave
- 3 unlockable weapons + color schemes
- Highscore chase, quick runs, instant restarts
- Works on desktop and mobile

## Steuerungserklärung (EN)
**Desktop:**
- WASD — move · Shift — sprint · Space — jump
- Mouse — aim, Left click — shoot, R — reload
- 1/2/3 — pick upgrade · ESC — pause

**Mobile:**
- Left half — virtual joystick (move, full deflection = sprint)
- Right half — drag to look
- Fire button (or auto-fire, switchable in menu), Jump & Reload buttons

## Thumbnail-Konzept
Motiv (muss bei 200 px Breite lesbar sein):
- Nahaufnahme der Waffe aus Ego-Perspektive rechts unten, großes gelbes
  Mündungsfeuer als hellster Punkt
- Davor: 1 roter Rusher-Kegel groß im Anschnitt (Bedrohung), dahinter
  violetter Shooter + grüner Tank klein (Silhouetten-Trio = Spielversprechen)
- Hintergrund: helle Arena mit orangen Akzenten, Fluchtlinien zur Mitte
- Titel "NOVA SURGE" in Blockschrift oben, hellblau wie das Spiel-Logo
- Kontrast-Check: als 200-px-Vorschau exportieren und auf Lesbarkeit prüfen

## Upload-Checkliste (manuell, im Portal)
1. `npm run build` → Inhalt von `dist/` als ZIP packen (index.html im Root).
2. developer.crazygames.com → "Submit game" → HTML5-Upload.
3. Kategorie: Action/Shooter · Tags: shooter, arena, waves, upgrades, fps
4. Beschreibung/Steuerung von oben einfügen (EN).
5. Vorschau auf Desktop UND Mobile im Portal-Preview testen (QA-Tool:
   Ads werden dort als Test-Ads ausgespielt; Konsole muss fehlerfrei sein).
6. SDK-Check im Preview: loadingStart/Stop beim Laden, gameplayStart beim
   Run-Start, gameplayStop bei Pause/Tod, Midgame-Ad in der Wellenpause
   (frühestens Welle 3, dann alle ≥3 Wellen/≥120 s), Rewarded-Buttons auf dem
   Todes-Screen (Revive · Coins ×2), happytime bei neuem Highscore.
