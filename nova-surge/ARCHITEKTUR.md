# Nova Surge — Architektur-Karte (Phase 0 des Release-Candidate-Plans)

Stand: 2026-07-20, alle Angaben gegen den Source verifiziert (nicht gegen den
minifizierten Build). Der RC-Plan selbst liegt in `RELEASE-PLAN.md`.

## Datei → Zuständigkeit

### Einstieg & Verdrahtung
| Datei | Zuständigkeit |
|---|---|
| `src/main.ts` | Bootstrap: SDK-Init → Renderer/Szene → alle Systeme. Event-Drain (Sim→Sound/Partikel/HUD), Screens-Callbacks (Play/Quit/Revive/Coins×2), Run-Belohnungs-Gutschrift (`grantRunRewards`, idempotent, beim Verlassen des Death-Screens), Phasenwechsel-Erkennung (Tod, Midgame-Ad-Trigger), dynamische Auflösungsskalierung, `window.__ns`-Debughandle (Headless-Tests hängen daran!) |

### Config (ALLE Balancing-Werte, keine Magic Numbers in Logik)
| Datei | Inhalt |
|---|---|
| `src/config/tuning.ts` | `MOVE` (Speed/Accel/Sprung), `FEEL` (Bob/FOV/Recoil-Recovery), `PLAYER` (HP 100, Regen 4 s → 12/s), `RUN` (Prewave 6 s, **Wave-Break 5 s**, Perfect-Bonus 500) |
| `src/config/weapons.ts` | **Weapon-Defs**: `WEAPONS` (pulse/scatter/longshot) — Schaden, Feuerrate, Spread, Recoil, Magazin, Reload, Sound-Charakter. `STARTING_WEAPON` |
| `src/config/enemies.ts` | **Enemy-Defs**: `ENEMIES` (rusher/shooter/tank/warden) + `ENEMY_AI` (**maxAlive 14**, Separation, Hitreact, Anti-Häng-Werte) |
| `src/config/waves.ts` | `WAVE_TABLE` (12 handgetunte Wellen), `getWave()` (linear danach; **Boss-Welle jede 5.**), `isBossWave()`, `waveHpScale()` (+5 %/Welle ab W5), `SPAWN_TRICKLE` |
| `src/config/upgrades.ts` | **Upgrade-Defs**: `UPGRADES` (6 Stück) + `UPGRADE_VALUES` + `UPGRADE_CHOICES=3` — hier kommt das Rarity-Feld hin (Phase 1) |
| `src/config/meta.ts` | `COIN_DIVISOR=60`, `WEAPON_PRICES` (scatter 140, longshot 320), `COLOR_SCHEMES` (8, davon 7 kaufbar), `SAVE_KEY`, `SAVE_SCHEMA_VERSION=1` |
| `src/config/arena.ts` | 5 Arena-Defs (Boxen, Paletten, Props, Spawns) — laut RC-Plan NICHT anfassen |

### Simulation (`src/core/`, fester 60-Hz-Takt, kein three-Import)
| Datei | Zuständigkeit |
|---|---|
| `Sim.ts` | Orchestrator. Run-Phasen `menu→prewave→wave→upgrade→break→…→dead`. Hitscan-Auflösung, Score/Multiplikator (**+0,1/Treffer, Cap ×5, Reset bei Schaden**), `coinsEarned = floor(score/60)` beim Tod, Revive (Ad), Perfect-Wave, `aimOnTarget` (Mobile-Auto-Fire) |
| `Player.ts` | Movement (Kapsel-AABB), HP/Regen, Coyote-/Doppelsprung, `takeDamage` (inkl. HUD-Richtungswinkel). **Stats-Erweiterungspunkt** für Phase 1/3: `speedMult`, `lifesteal`, `hasDoubleJump` liegen hier |
| `Weapon.ts` | Feuerlogik (Auto/Semi-Flanke), Spread-Wachstum, Recoil+Recovery, Magazin/Auto-Reload. **`mods`-Objekt** (damage/fireRate/magSize-Mult) = zentraler Hook für neue Upgrades |
| `Enemy.ts` | `EnemyManager`-Pool (28 Slots). FSM Spawn→Alert→Attack→Hitreact→Death, Steering + Separation + **Anti-Hänger-Ausweichen**, Melee mit Sichtlinien-Check, **Warden-Ring** (`radialCount/Cooldown`). Elite-Flag käme an den Slot (Phase 2) |
| `Waves.ts` | `WaveSpawner`: Tröpfel-Spawn an Toren (nie <14 m am Spieler), Typ-Mix, Boss zuerst. **Wave-Events = Parametrisierung hier + in `getWave()`** (Phase 2) |
| `Projectiles.ts` | Pool 128, Strecken-Kollision pro Tick, `clearEnemyProjectiles()` (Wellenende). Ricochet/Splitter (Phase 1) docken hier an |
| `Upgrades.ts` | `UpgradeState`: Zähler, `rollOffer()` (Fisher-Yates, 3 Karten), `apply()` schreibt in `Weapon.mods`/`Player` — **zentrale Stelle für alle 24 Upgrade-Effekte** |
| `collision.ts` | Arena→AABB-Welt, `moveBody` (auch Bots), LOS-Blocker-Liste |
| `math.ts` | Vec3/AABB/Ray (GC-frei; `rayVsSphere` mit Innen-Treffer-Fix) |
| `events.ts` | Allokationsfreier Event-Ringpuffer Sim→Präsentation (`Ev`-Enum) |
| `input.ts` | `InputState` — einzige Schnittstelle Controls→Sim |

### Präsentation
| Datei | Zuständigkeit |
|---|---|
| `render/createScene.ts` | Alle 5 Arenen einmal gebaut, Umschalten per Sichtbarkeit + Fog/Sky |
| `render/CameraRig.ts` | Interpolierte Kamera, Head-Bob, FOV-Kick, Landungs-Dip, Screen-Shake |
| `render/WeaponView.ts` | First-Person-Waffe (Primitiven), Kick/Reload-Anim, Muzzle, Skin-Farben |
| `render/EnemyRenderer.ts` | Mesh-Pools je Typ (Warden: 4), Lauf-/Flinch-/Todes-Anim, Weißblitz über `emissiveIntensity`. **Elite-Tint: `material.color` ändern → beim Pool-Release resetten!** (heutiger Reset-Pfad setzt nur `opacity`/`emissiveIntensity` zurück — `color` wird bisher NIE verändert) |
| `render/ProjectileRenderer.ts` | InstancedMesh, violett (Gegner) / orange (Pellets), interpoliert |
| `render/Particles.ts` / `Tracers.ts` | InstancedMesh-Partikelpool (320) / Tracer-Pool (24) |
| `ui/Screens.ts` | Modi home/playing/pause/death + Pointer-Lock-Regie. Shop-Rows (Map/Waffe/Skin) + Toggles (Autofire/Musik). **„PERKS"-Row (Phase 3) kommt hierher** |
| `ui/Hud.ts` | HP/Ammo/Wave/Score, Fadenkreuz (Spread), Hitmarker, Vignette+Richtung, Banner + `flashBanner()`, Score-Popup-Pool, **Upgrade-Karten (`.upgrade-card`) → Rarity-Styling Phase 1, Reroll-Button hierher** |
| `ui/DebugOverlay.ts` | F3: FPS/Sim-Rate/Draws/Entities/Heap — Phase 3 will effektive Stats dazu |
| `audio/Sfx.ts` | Prozeduraler Sound + Musik (Lookahead-Scheduler, Intensität/Welle) |
| `controls/` | Keyboard, LookControls (Lock), TouchControls (Stick/Drag, Auto-Fire-Puls für Semi-Waffen) |

### Persistenz & Plattform
| Datei | Zuständigkeit |
|---|---|
| `meta/SaveData.ts` | **Save-State v1** in localStorage: coins, highscore, bestWave, runsPlayed, unlockedWeapons/Schemes, selected*, autoFire, musicOn. `load()` merged Defaults (robust bei fehlenden Feldern) — **Migrationspunkt für v2 (Phase 3)** |
| `platform/CrazySdk.ts` | **SDK-Wrapper** v3: dynamisches Laden NUR in CG-Umgebung (`?cg=1` zum Testen), init/loading/gameplayStart/Stop, Midgame (≥3 Wellen & ≥120 s), Rewarded (Promise<boolean>), happytime, Ad-Pause-Hook (Loop + Mute). **`data`-Modul noch NICHT angebunden (Phase 3)** |

## Diagnose-Verifikation (Ist-Zahlen gegen Source)

| Behauptung im RC-Plan | Source sagt | Status |
|---|---|---|
| 6 Upgrades, Werte wie gelistet | `upgrades.ts`: exakt so | ✅ |
| Coins = floor(score/60) | `COIN_DIVISOR=60`, `Sim.ts:301` | ✅ |
| Scatter 140 / DMR 320 | `WEAPON_PRICES` | ✅ |
| 7 Skins 80–250 | 7 kaufbare (80/80/120/120/150/180/250) | ✅ |
| **Gesamt-Sinks ≈ 1.410** | **1.440** (460 Waffen + 980 Skins) | ⚠️ korrigiert |
| Warden `1+floor(wave/15)` | `waves.ts:42` exakt | ✅ |
| Multiplikator-Cap ×5 | `MULTIPLIER_MAX=5`, +0,1/Treffer | ✅ |
| Regen, Break 5 s, maxAlive 14 | 4 s→12 HP/s · 5,0 s · 14 | ✅ |
| Save nur localStorage v1 | `SaveData.ts` | ✅ |
| „Magnetfeld falls Coin-Pickups existieren" | **Coin-Pickups existieren NICHT** (Coins nur am Run-Ende) → Ersatz laut Plan: „Combo hält 2 s länger" | ⚠️ Ersatz nötig |
| happytime bei Highscore/Boss | Bereits implementiert; **Epic-Pick fehlt noch** (Phase 4) | ✅/offen |

## Wichtige Design-Punkte für die Freigabe von Phase 1

1. **Reroll-Quelle:** Im Run verdiente Coins werden erst beim VERLASSEN des
   Death-Screens gutgeschrieben (verhindert Revive-Doppelgutschrift).
   Reroll muss daher vom **Konto** (`save.state.coins`) abbuchen — d. h.
   Reroll-Button zeigt den Kontostand, nicht die Run-Coins. (Alternative —
   Coins live im Run gutschreiben — wäre ein größerer Umbau der
   Belohnungslogik.)
2. **Combo-Dauer:** Der Multiplikator hat heute KEINEN Zeitverfall (Reset nur
   bei eigenem Schaden). Das Ersatz-Upgrade „Combo hält 2 s länger" braucht
   also erst einen Combo-Timer — Vorschlag: mit dem Rare-Upgrade zusammen
   einen sanften Verfall einführen (z. B. −0,5/s ab 4 s ohne Treffer), sonst
   ist das Upgrade wirkungslos.
3. **Zeitlupe (Epic 17):** Sim tickt fest mit 60 Hz — Umsetzung als
   Gegner-`dt`-Skalierung innerhalb von `EnemyManager.update` (Faktor am
   Sim), nicht am GameLoop. Projektile der Gegner müssten mitskalieren.

## Baseline

`npm run build` (tsc strict + vite): **grün**, Bundle 612 KB
(gzip ≈ 156 KB) — weit unter dem 20-MB-Limit. Headless-Suiten (Maps 8/8,
Boss 4/4, Bot-Läufe) zuletzt grün bis auf dokumentierte
Run-Längen-Streuung (siehe STATUS.md).
