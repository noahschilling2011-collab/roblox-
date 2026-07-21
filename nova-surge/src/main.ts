import * as THREE from "three";
import "./style.css";
import { Sfx } from "./audio/Sfx";
import { ENEMIES, type EnemyType } from "./config/enemies";
import { getArena } from "./config/arena";
import { COIN_DIVISOR, COLOR_SCHEMES } from "./config/meta";
import { Keyboard } from "./controls/Keyboard";
import { LookControls } from "./controls/LookControls";
import { isTouchDevice, TouchControls } from "./controls/TouchControls";
import { GameLoop } from "./core/GameLoop";
import { createInput } from "./core/input";
import { Ev } from "./core/events";
import { Sim } from "./core/Sim";
import { SaveData } from "./meta/SaveData";
import { CrazySdk } from "./platform/CrazySdk";
import { CameraRig } from "./render/CameraRig";
import { createScene } from "./render/createScene";
import { EnemyRenderer } from "./render/EnemyRenderer";
import { Particles } from "./render/Particles";
import { ProjectileRenderer } from "./render/ProjectileRenderer";
import { Tracers } from "./render/Tracers";
import { WeaponView } from "./render/WeaponView";
import { DebugOverlay } from "./ui/DebugOverlay";
import { Hud } from "./ui/Hud";
import { Screens } from "./ui/Screens";

const SIM_HZ = 60;
const ENEMY_TYPES: EnemyType[] = ["rusher", "shooter", "tank", "warden"];

async function boot(): Promise<void> {
  const sdk = new CrazySdk();
  await sdk.init(); // no-op außerhalb der CrazyGames-Umgebung

  const isTouch = isTouchDevice();
  const canvas = document.getElementById("game-canvas") as HTMLCanvasElement;
  const renderer = new THREE.WebGLRenderer({ canvas, antialias: !isTouch });
  const basePixelRatio = Math.min(window.devicePixelRatio, 2);
  renderer.setPixelRatio(basePixelRatio);
  renderer.setSize(window.innerWidth, window.innerHeight);

  const { scene, camera, showArena } = createScene(window.innerWidth / window.innerHeight);
  scene.add(camera); // nötig, damit die kamera-gebundene Waffe gerendert wird

  const input = createInput();
  const sim = new Sim(input);
  const save = new SaveData();
  save.load();

  const sfx = new Sfx();
  const keyboard = new Keyboard(input);
  const look = new LookControls(input);
  const touch = new TouchControls(input);
  const rig = new CameraRig(camera);
  const weaponView = new WeaponView(camera);
  const enemyRenderer = new EnemyRenderer(scene);
  const particles = new Particles(scene);
  const tracers = new Tracers(scene);
  const projectileRenderer = new ProjectileRenderer(scene);
  const hud = new Hud();
  const debugOverlay = new DebugOverlay();

  // ---- Run-Belohnungen (Münzen/Highscore) — einmal pro Run beim Verlassen ----
  let rewardsGranted = true;
  let coinsDoubled = false;
  let wasNewHighscore = false;

  function grantRunRewards(): void {
    if (rewardsGranted) return;
    rewardsGranted = true;
    const coins = sim.phase === "dead" ? sim.coinsEarned : Math.floor(sim.score / COIN_DIVISOR);
    save.state.coins += coins;
    save.state.runsPlayed++;
    if (sim.score > save.state.highscore) save.state.highscore = sim.score;
    if (sim.waveNumber > save.state.bestWave) save.state.bestWave = sim.waveNumber;
    save.save();
  }

  function applyCosmetics(): void {
    const scheme = COLOR_SCHEMES.find((c) => c.id === save.state.selectedScheme) ?? COLOR_SCHEMES[0]!;
    weaponView.applyScheme(scheme);
    weaponView.equip(save.state.selectedWeapon);
    // Arena-Optik sofort umschalten (auch im Menü-Hintergrund sichtbar)
    showArena(getArena(save.state.selectedArena));
  }

  // ---- Screens (Menü/Pause/Tod) ----
  const screens = new Screens(canvas, isTouch, save, {
    onPlay() {
      grantRunRewards();
      sfx.init();
      coinsDoubled = false;
      wasNewHighscore = false;
      rewardsGranted = false;
      sim.startRun(save.state.selectedWeapon, getArena(save.state.selectedArena));
      applyCosmetics();
      screens.enterPlaying();
    },
    onResume() {
      screens.enterPlaying();
    },
    onQuit() {
      grantRunRewards();
      sim.quitToMenu();
      screens.releaseLock();
      screens.showHome();
    },
    onRevive() {
      void sdk.requestRewarded().then((granted) => {
        if (!granted) return;
        sim.revive();
        screens.hideReviveButton();
        screens.showPause(); // ein Klick auf RESUME — sauberer Lock-Neustart
      });
    },
    onCoinsX2() {
      void sdk.requestRewarded().then((granted) => {
        if (!granted) return;
        sim.coinsEarned *= 2;
        coinsDoubled = true;
        screens.updateDeathCoins(sim.coinsEarned, false);
      });
    },
    onSelectionChanged() {
      applyCosmetics();
    },
    onUiClick() {
      sfx.init(); // frühester User-Gesten-Moment
      sfx.uiClick();
    },
  });

  screens.onModeChanged = (mode) => {
    const playing = mode === "playing";
    hud[playing ? "show" : "hide"]();
    keyboard.enabled = playing && !isTouch;
    look.enabled = playing && !isTouch;
    touch.enabled = playing && isTouch;
    touch.showUi(playing && isTouch);
    if (!playing) keyboard.releaseAll();
    loop.setPaused(mode === "pause");
    if (playing) {
      sdk.gameplayStart();
      if (save.state.musicOn) sfx.startMusic();
    } else {
      sdk.gameplayStop();
      sfx.stopMusic();
    }
  };

  // Mobile hat kein ESC: der Pause-Button oben rechts übernimmt das
  document.getElementById("btn-touch-pause")!.addEventListener("click", () => {
    if (screens.mode === "playing") screens.showPause();
  });

  sdk.onAdPause = (paused) => {
    sfx.setMuted(paused);
    if (paused) loop.setPaused(true);
    else loop.setPaused(screens.mode === "pause");
  };

  // Upgrade-Wahl: Tasten 1–3 (Desktop, Pointer bleibt gelockt) + Karten-Klick
  hud.onChooseUpgrade = (i) => {
    sim.chooseUpgrade(i);
    sfx.upgradePicked();
  };
  document.addEventListener("keydown", (e) => {
    if (sim.phase !== "upgrade") return;
    const idx = e.code === "Digit1" ? 0 : e.code === "Digit2" ? 1 : e.code === "Digit3" ? 2 : -1;
    if (idx >= 0) {
      sim.chooseUpgrade(idx);
      sfx.upgradePicked();
    }
  });

  // ---- Tod erkennen (Phasenwechsel) ----
  let prevPhase = sim.phase;
  function handlePhaseTransitions(): void {
    if (sim.phase === prevPhase) return;
    const from = prevPhase;
    prevPhase = sim.phase;
    if (sim.phase === "dead") {
      wasNewHighscore = sim.score > save.state.highscore && sim.score > 0;
      if (wasNewHighscore) {
        sfx.newHighscore();
        sdk.happytime();
      }
      sfx.playerDied();
      screens.showDeath({
        score: sim.score,
        wave: sim.waveNumber,
        bestWave: save.state.bestWave,
        kills: sim.kills,
        coins: sim.coinsEarned,
        newHighscore: wasNewHighscore,
        canRevive: sdk.available && !sim.reviveUsed,
        canCoinsX2: sdk.available && !coinsDoubled,
      });
      screens.releaseLock();
    }
    // Midgame-Ad NUR in der Wellenpause (nach der Upgrade-Wahl)
    if (from === "upgrade" && sim.phase === "break") {
      sdk.maybeMidgameAd(sim.waveNumber);
    }
  }

  // ---- Events -> Präsentation ----
  const _fwd = new THREE.Vector3();
  const _right = new THREE.Vector3();
  const _up = new THREE.Vector3();
  const _muzzle = new THREE.Vector3();
  const _proj = new THREE.Vector3();

  /** Weltpunkt -> Bildschirm-Pixel; false, wenn hinter der Kamera. */
  function projectToScreen(x: number, y: number, z: number): { x: number; y: number } | null {
    _proj.set(x, y, z).project(camera);
    if (_proj.z > 1) return null;
    return {
      x: ((_proj.x + 1) / 2) * window.innerWidth,
      y: ((1 - _proj.y) / 2) * window.innerHeight,
    };
  }

  function computeMuzzle(): THREE.Vector3 {
    _fwd.set(0, 0, -1).applyQuaternion(camera.quaternion);
    _right.set(1, 0, 0).applyQuaternion(camera.quaternion);
    _up.set(0, 1, 0).applyQuaternion(camera.quaternion);
    return _muzzle
      .copy(camera.position)
      .addScaledVector(_fwd, 0.62)
      .addScaledVector(_right, 0.26)
      .addScaledVector(_up, -0.22);
  }

  function drainEvents(): void {
    const events = sim.events;
    for (let i = 0; i < events.count; i++) {
      const e = events.get(i);
      switch (e.type) {
        case Ev.Shot: {
          sfx.shot(sim.weapon.def);
          weaponView.notifyShot(0.4 + sim.weapon.def.recoilPitch * 18);
          const m = computeMuzzle();
          // Hülse: 1 kleines goldenes Teil nach rechts raus
          particles.burst(m.x, m.y, m.z, 0xd9b45a, 1, 2.4, 0.5, 0.035, 1, 0.5);
          break;
        }
        case Ev.Tracer: {
          const m = computeMuzzle();
          tracers.spawn(m.x, m.y, m.z, e.x, e.y, e.z);
          if (e.a === 1) {
            particles.burst(e.x, e.y, e.z, 0xd8604f, 5, 3.5, 0.35, 0.05);
          } else if (e.b === 1) {
            particles.burst(e.x, e.y, e.z, 0xcfd6de, 6, 2.8, 0.4, 0.045);
          }
          break;
        }
        case Ev.DamageDealt:
          hud.notifyHit(e.b === 1);
          if (e.b === 1) sfx.killConfirm();
          else sfx.hitTick();
          break;
        case Ev.EnemyDied: {
          const type = ENEMY_TYPES[e.a] ?? "rusher";
          const isBoss = type === "warden";
          particles.burst(e.x, e.y, e.z, ENEMIES[type].color, isBoss ? 60 : 22, isBoss ? 10 : 6.5, isBoss ? 1.1 : 0.7, isBoss ? 0.14 : 0.09, 1, 0.55);
          if (isBoss) {
            sfx.bossDown();
            rig.notifyShake(0.8);
            sdk.happytime(); // Boss-Kill = Jubel-Moment
          }
          // Score-Popup an der Kill-Stelle
          const screen = projectToScreen(e.x, e.y + 1, e.z);
          if (screen) hud.spawnPopup(screen.x, screen.y, `+${e.b}`, isBoss);
          break;
        }
        case Ev.PerfectWave:
          hud.flashBanner(`PERFECT WAVE +${e.a}`, 2.2);
          sfx.perfectWave();
          break;
        case Ev.EnemyShot: {
          const d = Math.hypot(e.x - sim.player.pos.x, e.z - sim.player.pos.z);
          sfx.enemyShot(d);
          break;
        }
        case Ev.PlayerHurt:
          sfx.playerHurt();
          hud.notifyHurt(e.b);
          rig.notifyShake(0.25 + Math.min(0.35, e.a / 80));
          break;
        case Ev.MeleeHit:
          sfx.meleeHit();
          particles.burst(e.x, e.y, e.z, 0xffffff, 6, 4, 0.3, 0.06);
          break;
        case Ev.ReloadStart:
          sfx.reload(e.a);
          break;
        case Ev.DryFire:
          sfx.dryFire();
          break;
        case Ev.Jump:
          sfx.jump();
          break;
        case Ev.Land:
          sfx.land(e.a);
          rig.notifyLand(e.a);
          break;
        case Ev.WaveStart:
          if (e.b === 1) {
            hud.flashBanner("⚠ BOSS WAVE ⚠", 2.5);
            sfx.bossWaveSting();
          } else {
            sfx.waveStart();
          }
          sfx.setMusicIntensity(e.a / 10);
          break;
        case Ev.WaveCleared:
          sfx.waveCleared();
          break;
        case Ev.Heal:
        case Ev.PlayerDied:
        case Ev.NewHighscore:
          break;
      }
    }
    events.clear();
  }

  // ---- Dynamische Auflösungsskalierung (Phase 5) ----
  let renderScale = 1;
  let lowFpsTime = 0;
  let highFpsTime = 0;

  function updateResolutionScale(dt: number, fps: number): void {
    if (fps < 55 && fps > 1) {
      lowFpsTime += dt;
      highFpsTime = 0;
    } else if (fps > 58) {
      highFpsTime += dt;
      lowFpsTime = 0;
    }
    if (lowFpsTime > 2 && renderScale > 0.55) {
      renderScale = Math.max(0.55, renderScale * 0.85);
      lowFpsTime = 0;
      applySize();
    } else if (highFpsTime > 4 && renderScale < 1) {
      renderScale = Math.min(1, renderScale * 1.1);
      highFpsTime = 0;
      applySize();
    }
  }

  function applySize(): void {
    renderer.setPixelRatio(basePixelRatio * renderScale);
    renderer.setSize(window.innerWidth, window.innerHeight);
    camera.aspect = window.innerWidth / window.innerHeight;
    camera.updateProjectionMatrix();
  }

  // ---- Loop ----
  const loop = new GameLoop(SIM_HZ, {
    simulate(dt) {
      touch.aimOnTarget = sim.aimOnTarget;
      touch.autoFire = save.state.autoFire;
      touch.weaponIsAuto = sim.weapon.def.auto;
      touch.update();
      sim.update(dt);
    },
    render(alpha) {
      const dt = Math.min(0.1, loop.getStats().frameMs / 1000);
      handlePhaseTransitions();
      rig.update(dt, alpha, sim.player, input, sim.weapon);
      weaponView.update(dt, sim.weapon, input, rig.bobPhase, sim.player.moveIntensity);
      enemyRenderer.update(sim.enemies, alpha, dt, sim.player.pos.x, sim.player.pos.z, performance.now() / 1000);
      particles.update(dt);
      tracers.update(dt);
      projectileRenderer.update(sim.projectiles, alpha);
      drainEvents();
      if (screens.mode === "playing") hud.update(dt, sim, isTouch);
      updateResolutionScale(dt, loop.getStats().fps);
      renderer.render(scene, camera);
      debugOverlay.update(loop, sim, renderer);
    },
  });

  window.addEventListener("resize", applySize);

  screens.showHome();
  applyCosmetics(); // gewählte Arena/Waffe/Farben aus dem Save anwenden
  loop.setPaused(false); // Menü-Hintergrund rendert; Sim idlet in "menu"
  loop.start();
  sdk.loadingDone();

  // Debug-Handle für automatisierte Tests (Headless) und die Konsole
  window.__ns = { loop, sim, renderer, input, save, screens };
}

declare global {
  interface Window {
    __ns: {
      loop: GameLoop;
      sim: Sim;
      renderer: THREE.WebGLRenderer;
      input: ReturnType<typeof createInput>;
      save: SaveData;
      screens: Screens;
    };
  }
}

void boot();
