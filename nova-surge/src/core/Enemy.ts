// Gegner-Simulation: fester Pool, FSM pro Bot
// (Spawn -> Alert -> Attack -> Hitreact -> Death), Steering ohne Navmesh:
// Ziel anlaufen, Hindernisse per Raycast umfließen, Separation untereinander.

import { ELITES, ELITE_RULES, ENEMIES, ENEMY_AI, type EliteType, type EnemyDef, type EnemyType } from "../config/enemies";
import { waveHpScale } from "../config/waves";
import { moveBody, type CollisionWorld } from "./collision";
import { rayVsAabb, segmentClear, vec3, type Aabb, type Vec3 } from "./math";
import { EventQueue, Ev } from "./events";

export type EnemyFsm = "alert" | "attack" | "hitreact" | "death";

export const ENEMY_TYPE_INDEX: Record<EnemyType, number> = { rusher: 0, shooter: 1, tank: 2, warden: 3 };

export interface EnemyCallbacks {
  /** attacker nur bei Nahkampf gesetzt (für Dornen-Upgrade). */
  damagePlayer(amount: number, sourceX: number, sourceZ: number, attacker?: Enemy): void;
  spawnEnemyProjectile(origin: Vec3, dir: Vec3, speed: number, damage: number): void;
}

export class Enemy {
  active = false;
  def: EnemyDef = ENEMIES.rusher;
  readonly pos: Vec3 = vec3();
  readonly prevPos: Vec3 = vec3();
  readonly vel: Vec3 = vec3();
  hp = 1;
  maxHp = 1;
  fsm: EnemyFsm = "alert";
  stateTimer = 0;
  attackCooldown = 0;
  burstShotsLeft = 0;
  burstTimer = 0;
  strafeDir = 1;
  strafeTimer = 0;
  radialTimer = 0; // Boss-Ring-Angriff
  // Anti-Hänger: Anker + Timer erkennen "will laufen, kommt nicht voran"
  anchorX = 0;
  anchorZ = 0;
  stuckTimer = 0;
  unstickTimer = 0;
  unstickX = 0;
  unstickZ = 0;
  hitreactCooldown = 0;
  onGround = true;
  /** 1 direkt nach Treffer, klingt ab — Renderer nutzt das für den Weiß-Flash. */
  flash = 0;
  /** Elite-Modifikator (RC Phase 2) oder null. */
  elite: EliteType | null = null;
  speedScale = 1;
  scoreScale = 1;

  get eyeY(): number {
    return this.pos.y + this.def.height * 0.85;
  }
  get centerY(): number {
    return this.pos.y + this.def.height * 0.55;
  }
}

const MAX_SLOTS = 28;
const _toPlayer = vec3();
const _desired = vec3();
const _rayOrigin = vec3();
const _rayDir = vec3();
const _eye = vec3();
const _target = vec3();
const _shotDir = vec3();

export class EnemyManager {
  readonly slots: Enemy[] = [];

  constructor() {
    for (let i = 0; i < MAX_SLOTS; i++) this.slots.push(new Enemy());
  }

  clear(): void {
    for (const e of this.slots) e.active = false;
  }

  aliveCount(): number {
    let n = 0;
    for (const e of this.slots) if (e.active && e.fsm !== "death") n++;
    return n;
  }

  spawn(type: EnemyType, x: number, z: number, waveNumber: number, elite: EliteType | null = null): boolean {
    for (const e of this.slots) {
      if (e.active) continue;
      e.active = true;
      e.def = ENEMIES[type];
      e.elite = elite;
      const eliteDef = elite ? ELITES[elite] : null;
      e.speedScale = eliteDef ? eliteDef.speedMult : 1;
      e.scoreScale = eliteDef ? eliteDef.scoreMult : 1;
      e.pos.x = x;
      e.pos.y = 0;
      e.pos.z = z;
      e.prevPos.x = x;
      e.prevPos.y = 0;
      e.prevPos.z = z;
      e.vel.x = e.vel.y = e.vel.z = 0;
      e.maxHp = Math.round(e.def.hp * waveHpScale(waveNumber) * (eliteDef ? eliteDef.hpMult : 1));
      e.hp = e.maxHp;
      e.fsm = "alert";
      e.stateTimer = ENEMY_AI.alertDelay;
      e.attackCooldown = 0.5; // kein Instant-Hit beim Spawnen
      e.burstShotsLeft = 0;
      e.burstTimer = 0;
      e.strafeDir = Math.random() < 0.5 ? 1 : -1;
      e.strafeTimer = 1 + Math.random() * 2;
      e.radialTimer = 2; // Boss: erste Ring-Salve kommt mit Vorwarnzeit
      e.anchorX = x;
      e.anchorZ = z;
      e.stuckTimer = 0;
      e.unstickTimer = 0;
      e.hitreactCooldown = 0;
      e.flash = 0;
      return true;
    }
    return false;
  }

  /** true, wenn der Treffer getötet hat. Punktevergabe macht die Sim. */
  damage(e: Enemy, amount: number): boolean {
    if (!e.active || e.fsm === "death") return false;
    e.hp -= amount;
    e.flash = 1;
    if (e.hp <= 0) {
      e.fsm = "death";
      e.stateTimer = ENEMY_AI.deathDuration;
      return true;
    }
    if (e.hitreactCooldown <= 0) {
      e.fsm = "hitreact";
      e.stateTimer = ENEMY_AI.hitreactDuration;
      // Tanks lassen sich nicht dauerhaft stunlocken
      e.hitreactCooldown = e.def.type === "tank" ? 0.9 : 0.25;
    }
    return false;
  }

  update(
    dt: number,
    playerPos: Vec3,
    playerEyeY: number,
    playerAlive: boolean,
    world: CollisionWorld,
    events: EventQueue,
    callbacks: EnemyCallbacks
  ): void {
    const solids = world.solids;
    const losBlockers = world.losBlockers;
    for (let i = 0; i < MAX_SLOTS; i++) {
      const e = this.slots[i]!;
      if (!e.active) continue;
      e.prevPos.x = e.pos.x;
      e.prevPos.y = e.pos.y;
      e.prevPos.z = e.pos.z;
      e.flash = Math.max(0, e.flash - dt * 8);
      e.hitreactCooldown -= dt;
      e.attackCooldown -= dt;

      if (e.fsm === "death") {
        e.stateTimer -= dt;
        if (e.stateTimer <= 0) e.active = false;
        // Schwerkraft wirkt weiter — in der Luft Getötete fallen zu Boden
        this.applyPhysics(e, 0, 0, dt, world);
        continue;
      }
      if (e.fsm === "hitreact") {
        e.stateTimer -= dt;
        this.applyPhysics(e, 0, 0, dt, world);
        if (e.stateTimer <= 0) e.fsm = "attack";
        continue;
      }
      if (e.fsm === "alert") {
        e.stateTimer -= dt;
        if (e.stateTimer <= 0) e.fsm = "attack";
        this.applyPhysics(e, 0, 0, dt, world);
        continue;
      }

      // ---- Attack-Verhalten nach Typ ----
      if (!playerAlive) {
        this.applyPhysics(e, 0, 0, dt, world);
        continue;
      }

      _toPlayer.x = playerPos.x - e.pos.x;
      _toPlayer.y = 0;
      _toPlayer.z = playerPos.z - e.pos.z;
      const distXZ = Math.hypot(_toPlayer.x, _toPlayer.z);
      if (distXZ > 1e-4) {
        _toPlayer.x /= distXZ;
        _toPlayer.z /= distXZ;
      }

      let moveX = 0;
      let moveZ = 0;
      const d = e.def;
      // Elite "Flink"/"Gepanzert": Tempo skaliert
      const spd = d.speed * e.speedScale;
      const strafeSpd = d.strafeSpeed * e.speedScale;

      if (d.type === "shooter") {
        // Distanz halten + seitlich strafen
        e.strafeTimer -= dt;
        if (e.strafeTimer <= 0) {
          e.strafeDir = -e.strafeDir;
          e.strafeTimer = 1.2 + Math.random() * 1.8;
        }
        const side = e.strafeDir;
        const strafeX = -_toPlayer.z * side;
        const strafeZ = _toPlayer.x * side;
        if (distXZ > d.preferredRange + 3) {
          moveX = _toPlayer.x * spd + strafeX * strafeSpd * 0.4;
          moveZ = _toPlayer.z * spd + strafeZ * strafeSpd * 0.4;
        } else if (distXZ < d.preferredRange - 4) {
          moveX = -_toPlayer.x * spd * 0.8 + strafeX * strafeSpd * 0.6;
          moveZ = -_toPlayer.z * spd * 0.8 + strafeZ * strafeSpd * 0.6;
        } else {
          moveX = strafeX * strafeSpd;
          moveZ = strafeZ * strafeSpd;
        }

        // Burst-Feuer bei Sichtlinie
        _eye.x = e.pos.x;
        _eye.y = e.eyeY;
        _eye.z = e.pos.z;
        _target.x = playerPos.x;
        _target.y = playerEyeY - 0.3;
        _target.z = playerPos.z;
        const hasLos = segmentClear(_eye, _target, losBlockers);
        if (e.burstShotsLeft > 0) {
          e.burstTimer -= dt;
          if (e.burstTimer <= 0) {
            e.burstShotsLeft--;
            e.burstTimer = d.burstInterval;
            if (hasLos) {
              _shotDir.x = _target.x - _eye.x;
              _shotDir.y = _target.y - _eye.y;
              _shotDir.z = _target.z - _eye.z;
              const l = Math.hypot(_shotDir.x, _shotDir.y, _shotDir.z) || 1;
              // leichte Streuung, damit Stillstehen trotzdem bestraft, Ausweichen belohnt wird
              _shotDir.x = _shotDir.x / l + (Math.random() - 0.5) * 0.06;
              _shotDir.y = _shotDir.y / l + (Math.random() - 0.5) * 0.03;
              _shotDir.z = _shotDir.z / l + (Math.random() - 0.5) * 0.06;
              callbacks.spawnEnemyProjectile(_eye, _shotDir, d.projectileSpeed, d.projectileDamage);
              events.emit(Ev.EnemyShot, _eye.x, _eye.y, _eye.z);
            }
          }
        } else if (hasLos && distXZ < d.preferredRange * 1.8 && e.attackCooldown <= 0) {
          e.burstShotsLeft = d.burstCount;
          e.burstTimer = 0.12;
          e.attackCooldown = d.burstCooldown;
        }
      } else {
        // Rusher, Tank & Warden: anlaufen, kurz vor Nahkampfreichweite stoppen
        // (sonst schieben sie sich in die Kamera)
        if (distXZ > d.meleeRange * 0.75) {
          moveX = _toPlayer.x * spd;
          moveZ = _toPlayer.z * spd;
        }
        // Boss: flacher Projektil-Ring auf Brusthöhe — drüberspringen!
        if (d.radialCount > 0) {
          e.radialTimer -= dt;
          if (e.radialTimer <= 0 && distXZ < 24) {
            e.radialTimer = d.radialCooldown;
            _eye.x = e.pos.x;
            _eye.y = e.pos.y + 1.4;
            _eye.z = e.pos.z;
            const offset = Math.random() * Math.PI * 2;
            for (let r = 0; r < d.radialCount; r++) {
              const a = offset + (r / d.radialCount) * Math.PI * 2;
              _shotDir.x = Math.sin(a);
              _shotDir.y = 0;
              _shotDir.z = Math.cos(a);
              callbacks.spawnEnemyProjectile(_eye, _shotDir, d.projectileSpeed, d.projectileDamage);
            }
            events.emit(Ev.EnemyShot, _eye.x, _eye.y, _eye.z);
          }
        }
        const heightDiff = playerPos.y - e.pos.y;
        if (d.canJump && e.onGround && heightDiff > 0.6 && distXZ < 3.5) {
          e.vel.y = d.jumpVelocity;
        }
        if (distXZ < d.meleeRange && Math.abs(heightDiff) < 1.6 && e.attackCooldown <= 0) {
          // Nur zuschlagen, wenn nichts dazwischen ist — kein Schlagen durch
          // Blöcke (Spieler oben auf LOW-Deckung) oder um Deckungsecken.
          _eye.x = e.pos.x;
          _eye.y = e.centerY;
          _eye.z = e.pos.z;
          _target.x = playerPos.x;
          _target.y = playerPos.y + 1.0;
          _target.z = playerPos.z;
          if (segmentClear(_eye, _target, solids)) {
            e.attackCooldown = d.meleeCooldown;
            callbacks.damagePlayer(d.meleeDamage, e.pos.x, e.pos.z, e);
            events.emit(Ev.MeleeHit, e.pos.x, e.centerY, e.pos.z);
          }
        }
      }

      // Anti-Hänger: wer sich trotz Bewegungswunsch >1,6 s kaum bewegt,
      // weicht kurz senkrecht aus (Shooter in Wand-Strafe, Tank vor Block).
      // Nahe am Spieler ist Stillstehen Absicht (Stoppdistanz/Ring-Phase).
      if (e.unstickTimer > 0) {
        e.unstickTimer -= dt;
        moveX = e.unstickX * spd;
        moveZ = e.unstickZ * spd;
      } else if (distXZ > 4 && Math.hypot(moveX, moveZ) > 0.5) {
        const ax = e.pos.x - e.anchorX;
        const az = e.pos.z - e.anchorZ;
        if (ax * ax + az * az > 0.36) {
          e.anchorX = e.pos.x;
          e.anchorZ = e.pos.z;
          e.stuckTimer = 0;
        } else {
          e.stuckTimer += dt;
          if (e.stuckTimer > 1.6) {
            e.stuckTimer = 0;
            e.unstickTimer = 1.1;
            const side = Math.random() < 0.5 ? 1 : -1;
            e.unstickX = -_toPlayer.z * side;
            e.unstickZ = _toPlayer.x * side;
          }
        }
      } else {
        e.stuckTimer = 0;
        e.anchorX = e.pos.x;
        e.anchorZ = e.pos.z;
      }

      // Hindernis-Umfließen + Separation
      this.steer(e, moveX, moveZ, solids, dt);
      this.separate(e);
      this.applyPhysics(e, _desired.x, _desired.z, dt, world);
    }

    // Elite "Vampirisch": heilt nahe Gegner (nicht sich selbst)
    for (const v of this.slots) {
      if (!v.active || v.fsm === "death" || v.elite !== "vampiric") continue;
      const r2 = ELITE_RULES.vampiricRadius * ELITE_RULES.vampiricRadius;
      for (const o of this.slots) {
        if (o === v || !o.active || o.fsm === "death" || o.hp >= o.maxHp) continue;
        const dx = o.pos.x - v.pos.x;
        const dz = o.pos.z - v.pos.z;
        if (dx * dx + dz * dz <= r2) {
          o.hp = Math.min(o.maxHp, o.hp + ELITE_RULES.vampiricHealPerSecond * dt);
        }
      }
    }
  }

  /** Prüft die Wunschrichtung per Raycast, weicht ggf. seitlich aus. Ergebnis in _desired. */
  private steer(e: Enemy, moveX: number, moveZ: number, solids: readonly Aabb[], dt: number): void {
    _desired.x = moveX;
    _desired.z = moveZ;
    const speed = Math.hypot(moveX, moveZ);
    if (speed < 0.1) return;

    _rayOrigin.x = e.pos.x;
    _rayOrigin.y = e.pos.y + 0.6; // Kniehöhe: niedrige Blöcke zählen als Hindernis
    _rayOrigin.z = e.pos.z;
    const lookahead = ENEMY_AI.avoidLookahead + e.def.radius;

    if (this.dirBlocked(moveX / speed, moveZ / speed, lookahead, solids)) {
      // ±45° und ±90° testen, erste freie Richtung nehmen
      const baseAngle = Math.atan2(moveX, moveZ);
      const offsets = [0.8, -0.8, 1.6, -1.6];
      for (const off of offsets) {
        const dx = Math.sin(baseAngle + off);
        const dz = Math.cos(baseAngle + off);
        if (!this.dirBlocked(dx, dz, lookahead, solids)) {
          _desired.x = dx * speed;
          _desired.z = dz * speed;
          break;
        }
      }
    }
    // Leichter Zufalls-Jitter gegen Verklumpen an Kanten
    _desired.x += (Math.random() - 0.5) * ENEMY_AI.repathJitter * speed * dt * 60 * 0.02;
    _desired.z += (Math.random() - 0.5) * ENEMY_AI.repathJitter * speed * dt * 60 * 0.02;
  }

  private dirBlocked(dx: number, dz: number, lookahead: number, solids: readonly Aabb[]): boolean {
    _rayDir.x = dx;
    _rayDir.y = 0;
    _rayDir.z = dz;
    for (let b = 0; b < solids.length; b++) {
      if (rayVsAabb(_rayOrigin, _rayDir, solids[b]!, lookahead) < lookahead) return true;
    }
    return false;
  }

  /** Bots drücken sich gegenseitig auseinander (O(n²), n klein). */
  private separate(e: Enemy): void {
    for (const other of this.slots) {
      if (other === e || !other.active || other.fsm === "death") continue;
      const dx = e.pos.x - other.pos.x;
      const dz = e.pos.z - other.pos.z;
      const distSq = dx * dx + dz * dz;
      const minDist = ENEMY_AI.separationRadius;
      if (distSq > minDist * minDist || distSq < 1e-6) continue;
      const dist = Math.sqrt(distSq);
      const push = (ENEMY_AI.separationForce * (1 - dist / minDist)) / dist;
      _desired.x += dx * push;
      _desired.z += dz * push;
    }
  }

  private applyPhysics(e: Enemy, velX: number, velZ: number, dt: number, world: CollisionWorld): void {
    // Sanftes Beschleunigen Richtung Wunschgeschwindigkeit (wirkt organischer)
    e.vel.x += (velX - e.vel.x) * Math.min(1, 12 * dt);
    e.vel.z += (velZ - e.vel.z) * Math.min(1, 12 * dt);
    e.vel.y -= 24 * dt;
    e.onGround = moveBody(e.pos, e.vel, e.def.radius, e.def.height, dt, world);
  }
}
