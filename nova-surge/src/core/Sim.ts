// Die komplette Spiel-Simulation: Run-Phasen, Spieler, Waffe, Gegner,
// Projektile, Wellen, Score. Läuft mit festem 60-Hz-Takt, kennt kein
// Rendering — die Präsentation liest Zustand + Events.

import { RUN } from "../config/tuning";
import { ARENAS, type ArenaDef } from "../config/arena";
import { COIN_DIVISOR } from "../config/meta";
import type { WeaponId } from "../config/weapons";
import type { UpgradeId } from "../config/upgrades";
import { ENEMY_TYPE_INDEX, EnemyManager, type Enemy } from "./Enemy";
import { EventQueue, Ev } from "./events";
import { buildCollisionWorld } from "./collision";
import type { InputState } from "./input";
import { rayVsAabb, rayVsSphere, vec3, type Vec3 } from "./math";
import { Player } from "./Player";
import { Projectiles, type ProjectileSlot } from "./Projectiles";
import { UpgradeState } from "./Upgrades";
import { WaveSpawner } from "./Waves";
import { Weapon } from "./Weapon";

export type RunPhase = "menu" | "prewave" | "wave" | "upgrade" | "break" | "dead";

const MULTIPLIER_PER_HIT = 0.1;
const MULTIPLIER_MAX = 5;
const _eye = vec3();
const _hitPoint = vec3();

export class Sim {
  arena: ArenaDef = ARENAS[0]!;
  world = buildCollisionWorld(this.arena);
  readonly player = new Player();
  readonly weapon = new Weapon();
  readonly enemies = new EnemyManager();
  readonly projectiles = new Projectiles();
  readonly spawner = new WaveSpawner();
  readonly upgrades = new UpgradeState();
  readonly events = new EventQueue();

  tick = 0;
  phase: RunPhase = "menu";
  phaseTimer = 0;
  waveNumber = 0;
  score = 0;
  multiplier = 1;
  kills = 0;
  coinsEarned = 0;
  /** Angebot für die 1-aus-3-Wahl (gefüllt beim Wellenende). */
  upgradeOffer: UpgradeId[] = [];
  /** true, wenn das Fadenkreuz gerade auf einem Gegner liegt (Mobile-Auto-Fire). */
  aimOnTarget = false;
  /** Einmal pro Run: Revive über Rewarded Ad (Phase 6). */
  reviveUsed = false;
  /** Vom Pellet-Raycast getroffener Gegner (hitTest -> onHit, gleicher Tick). */
  private pelletTarget: Enemy | null = null;

  private readonly input: InputState;

  constructor(input: InputState) {
    this.input = input;
  }

  entityCount(): number {
    let n = 0;
    for (const e of this.enemies.slots) if (e.active) n++;
    for (const p of this.projectiles.slots) if (p.active) n++;
    return n;
  }

  setArena(arena: ArenaDef): void {
    this.arena = arena;
    this.world = buildCollisionWorld(arena);
  }

  startRun(weaponId: WeaponId, arena: ArenaDef): void {
    this.setArena(arena);
    this.player.reset(arena.playerSpawn);
    this.weapon.mods.damageMult = 1;
    this.weapon.mods.fireRateMult = 1;
    this.weapon.mods.magSizeMult = 1;
    this.weapon.equip(weaponId);
    this.enemies.clear();
    this.projectiles.clear();
    this.spawner.clear();
    this.upgrades.reset();
    this.score = 0;
    this.multiplier = 1;
    this.kills = 0;
    this.coinsEarned = 0;
    this.waveNumber = 0;
    this.upgradeOffer = [];
    this.reviveUsed = false;
    this.phase = "prewave";
    this.phaseTimer = RUN.firstWaveDelay;
  }

  quitToMenu(): void {
    this.phase = "menu";
    this.enemies.clear();
    this.projectiles.clear();
    this.spawner.clear();
  }

  chooseUpgrade(index: number): void {
    if (this.phase !== "upgrade") return;
    const id = this.upgradeOffer[index];
    if (!id) return;
    this.upgrades.apply(id, this.weapon, this.player);
    this.upgradeOffer = [];
    this.phase = "break";
    this.phaseTimer = RUN.waveBreak;
  }

  /** Rewarded-Ad-Belohnung (Phase 6): Weiterspielen nach Tod. */
  revive(): void {
    if (this.phase !== "dead" || this.reviveUsed) return;
    this.reviveUsed = true;
    this.player.alive = true;
    this.player.hp = 60;
    this.player.sinceDamage = 0;
    // Druck rausnehmen: alles Aktive stirbt, Welle läuft danach weiter
    for (const e of this.enemies.slots) {
      if (e.active && e.fsm !== "death") this.enemies.damage(e, 99999);
    }
    this.projectiles.clear();
    // Eine bereits verdiente Upgrade-Wahl darf durch den Tod nicht verfallen
    if (this.upgradeOffer.length > 0) {
      this.phase = "upgrade";
    } else {
      this.phase = this.spawner.pendingCount() > 0 || this.enemies.aliveCount() > 0 ? "wave" : "break";
    }
    this.phaseTimer = RUN.waveBreak;
  }

  update(dt: number): void {
    this.tick++;
    if (this.phase === "menu") return;

    const p = this.player;

    // Phasen-Steuerung
    if (this.phase === "prewave" || this.phase === "break") {
      this.phaseTimer -= dt;
      if (this.phaseTimer <= 0) {
        this.waveNumber++;
        this.spawner.start(this.waveNumber);
        this.phase = "wave";
        this.events.emit(Ev.WaveStart, 0, 0, 0, this.waveNumber);
      }
    } else if (this.phase === "wave") {
      this.spawner.update(dt, this.enemies, p.pos, this.waveNumber, this.arena.enemySpawns);
      if (this.spawner.pendingCount() === 0 && this.enemies.aliveCount() === 0) {
        this.events.emit(Ev.WaveCleared, 0, 0, 0, this.waveNumber);
        // Noch fliegende Gegner-Projektile verfallen — kein Tod im Upgrade-Screen
        this.projectiles.clearEnemyProjectiles();
        this.upgradeOffer = this.upgrades.rollOffer();
        this.phase = this.upgradeOffer.length > 0 ? "upgrade" : "break";
        this.phaseTimer = RUN.waveBreak;
      }
    }

    // Spieler + Waffe (auch in Pausenphasen — Bewegung bleibt flüssig)
    p.update(dt, this.input, this.world, this.events);
    _eye.x = p.pos.x;
    _eye.y = p.eyeY;
    _eye.z = p.pos.z;
    if (p.alive && this.phase !== "upgrade") {
      this.weapon.update(dt, this.input, _eye, this.events, this.resolveHitscan, this.spawnPellet);
    }

    // Gegner
    this.enemies.update(dt, p.pos, p.eyeY, p.alive, this.world, this.events, this.enemyCallbacks);

    // Projektile
    this.projectiles.update(dt, this.world.solids, this.projectileHitTest, this.projectileOnHit);

    this.updateAimOnTarget();
  }

  // ---- Hitscan (AR/DMR) ----

  private resolveHitscan = (origin: Vec3, dir: Vec3, damage: number, range: number): void => {
    let wallT = range;
    for (const b of this.world.solids) {
      const t = rayVsAabb(origin, dir, b, wallT);
      if (t < wallT) wallT = t;
    }
    let bestT = Infinity;
    let bestEnemy: Enemy | null = null;
    for (const e of this.enemies.slots) {
      if (!e.active || e.fsm === "death") continue;
      const t = rayVsSphere(origin, dir, e.pos.x, e.centerY, e.pos.z, e.def.radius * 1.4);
      if (t < bestT) {
        bestT = t;
        bestEnemy = e;
      }
    }
    if (bestEnemy && bestT < wallT) {
      _hitPoint.x = origin.x + dir.x * bestT;
      _hitPoint.y = origin.y + dir.y * bestT;
      _hitPoint.z = origin.z + dir.z * bestT;
      this.events.emit(Ev.Tracer, _hitPoint.x, _hitPoint.y, _hitPoint.z, 1);
      this.applyPlayerDamage(bestEnemy, damage);
    } else {
      _hitPoint.x = origin.x + dir.x * wallT;
      _hitPoint.y = origin.y + dir.y * wallT;
      _hitPoint.z = origin.z + dir.z * wallT;
      // a=0: Wand/Luft — Renderer setzt Einschlag-Partikel nur bei Wandtreffern (t < range)
      this.events.emit(Ev.Tracer, _hitPoint.x, _hitPoint.y, _hitPoint.z, 0, wallT < range ? 1 : 0);
    }
  };

  private spawnPellet = (origin: Vec3, dir: Vec3, speed: number, life: number, damage: number): void => {
    this.projectiles.spawn(true, origin, dir, speed, life, damage);
  };

  /** Schaden des Spielers an einem Gegner inkl. Score/Multiplikator/Lifesteal. */
  private applyPlayerDamage(e: Enemy, damage: number): void {
    const killed = this.enemies.damage(e, damage);
    this.multiplier = Math.min(MULTIPLIER_MAX, this.multiplier + MULTIPLIER_PER_HIT);
    if (this.player.lifesteal > 0) {
      this.player.heal(damage * this.player.lifesteal);
      this.events.emit(Ev.Heal, 0, 0, 0, damage * this.player.lifesteal);
    }
    if (killed) {
      const gained = Math.round(e.def.score * this.multiplier);
      this.score += gained;
      this.kills++;
      this.events.emit(Ev.EnemyDied, e.pos.x, e.centerY, e.pos.z, ENEMY_TYPE_INDEX[e.def.type], gained);
      this.events.emit(Ev.DamageDealt, 0, 0, 0, damage, 1);
    } else {
      this.events.emit(Ev.DamageDealt, 0, 0, 0, damage, 0);
    }
  }

  // ---- Projektile ----

  private projectileHitTest = (
    s: ProjectileSlot,
    maxDist: number,
    dirX: number,
    dirY: number,
    dirZ: number
  ): number => {
    _eye.x = s.x;
    _eye.y = s.y;
    _eye.z = s.z;
    _hitPoint.x = dirX;
    _hitPoint.y = dirY;
    _hitPoint.z = dirZ;
    if (s.fromPlayer) {
      let best = Infinity;
      this.pelletTarget = null;
      for (const e of this.enemies.slots) {
        if (!e.active || e.fsm === "death") continue;
        const t = rayVsSphere(_eye, _hitPoint, e.pos.x, e.centerY, e.pos.z, e.def.radius * 1.4);
        if (t < best && t <= maxDist) {
          best = t;
          this.pelletTarget = e;
        }
      }
      return best;
    }
    const p = this.player;
    if (!p.alive) return Infinity;
    const t = rayVsSphere(_eye, _hitPoint, p.pos.x, p.pos.y + 1.1, p.pos.z, 0.55);
    return t <= maxDist ? t : Infinity;
  };

  private projectileOnHit = (s: ProjectileSlot): void => {
    if (s.fromPlayer) {
      // Exakt der Gegner, dessen Hitbox der Raycast in hitTest getroffen hat —
      // keine Nächster-Nachbar-Suche (die traf im Pulk den Falschen).
      if (this.pelletTarget) {
        this.applyPlayerDamage(this.pelletTarget, s.damage);
        this.pelletTarget = null;
      }
    } else {
      this.damagePlayer(s.damage, s.x, s.z);
    }
  };

  // ---- Gegner-Callbacks ----

  private damagePlayer = (amount: number, sourceX: number, sourceZ: number): void => {
    // In Menü-Phasen (Upgrade-Wahl) ist der Spieler unverwundbar
    if (this.phase === "dead" || this.phase === "upgrade") return;
    this.multiplier = 1;
    const died = this.player.takeDamage(amount, sourceX, sourceZ, this.input.yaw, this.events);
    if (died) {
      this.phase = "dead";
      this.coinsEarned = Math.floor(this.score / COIN_DIVISOR);
    }
  };

  private enemyCallbacks = {
    damagePlayer: this.damagePlayer,
    spawnEnemyProjectile: (origin: Vec3, dir: Vec3, speed: number, damage: number): void => {
      this.projectiles.spawn(false, origin, dir, speed, 3.5, damage);
    },
  };

  /** Liegt das Fadenkreuz auf einem Gegner? (Mobile-Auto-Fire, Phase 5) */
  private updateAimOnTarget(): void {
    this.aimOnTarget = false;
    if (!this.player.alive) return;
    _eye.x = this.player.pos.x;
    _eye.y = this.player.eyeY;
    _eye.z = this.player.pos.z;
    const cp = Math.cos(this.input.pitch);
    _hitPoint.x = -Math.sin(this.input.yaw) * cp;
    _hitPoint.y = Math.sin(this.input.pitch);
    _hitPoint.z = -Math.cos(this.input.yaw) * cp;
    let wallT = 80;
    for (const b of this.world.losBlockers) {
      const t = rayVsAabb(_eye, _hitPoint, b, wallT);
      if (t < wallT) wallT = t;
    }
    for (const e of this.enemies.slots) {
      if (!e.active || e.fsm === "death") continue;
      const t = rayVsSphere(_eye, _hitPoint, e.pos.x, e.centerY, e.pos.z, e.def.radius * 1.8);
      if (t < wallT) {
        this.aimOnTarget = true;
        return;
      }
    }
  }
}
