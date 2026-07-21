// Gemeinsamer Projektil-Pool: Shooter-Bot-Geschosse UND Shotgun-Pellets.
// Feste Slot-Anzahl, keine Allokationen im Loop. Kollisionsprüfung als
// Strecke pro Tick (kein Tunneln bei 60 Hz und <= 42 m/s).

import { rayVsAabb, rayVsSphere, vec3, type Aabb, type Vec3 } from "./math";

export interface ProjectileSlot {
  active: boolean;
  fromPlayer: boolean;
  x: number;
  y: number;
  z: number;
  prevX: number;
  prevY: number;
  prevZ: number;
  vx: number;
  vy: number;
  vz: number;
  life: number;
  damage: number;
  /** Ricochet-Upgrade: verbleibende Wand-Abpraller. */
  bounces: number;
}

const CAPACITY = 128;
const _dir = vec3();
const _origin = vec3();

export class Projectiles {
  readonly slots: ProjectileSlot[] = [];

  constructor() {
    for (let i = 0; i < CAPACITY; i++) {
      this.slots.push({
        active: false,
        fromPlayer: false,
        x: 0, y: 0, z: 0,
        prevX: 0, prevY: 0, prevZ: 0,
        vx: 0, vy: 0, vz: 0,
        life: 0,
        damage: 0,
        bounces: 0,
      });
    }
  }

  clear(): void {
    for (const s of this.slots) s.active = false;
  }

  /** Nur Gegner-Projektile entfernen (Wellenende: keine Nachzügler-Treffer). */
  clearEnemyProjectiles(): void {
    for (const s of this.slots) if (s.active && !s.fromPlayer) s.active = false;
  }

  spawn(fromPlayer: boolean, origin: Vec3, dir: Vec3, speed: number, life: number, damage: number, bounces = 0): void {
    for (let i = 0; i < CAPACITY; i++) {
      const s = this.slots[i]!;
      if (s.active) continue;
      s.active = true;
      s.fromPlayer = fromPlayer;
      s.x = s.prevX = origin.x;
      s.y = s.prevY = origin.y;
      s.z = s.prevZ = origin.z;
      s.vx = dir.x * speed;
      s.vy = dir.y * speed;
      s.vz = dir.z * speed;
      s.life = life;
      s.damage = damage;
      s.bounces = bounces;
      return;
    }
  }

  /**
   * Bewegt alle Projektile. `onHit` wird mit dem Slot aufgerufen, wenn die
   * Strecke dieses Ticks ein Ziel trifft (Sim entscheidet, was passiert);
   * Rückgabewert true = Projektil verbraucht. Wände löschen immer.
   */
  update(
    dt: number,
    enemyTimeScale: number,
    solids: readonly Aabb[],
    hitTest: (s: ProjectileSlot, dist: number, dirX: number, dirY: number, dirZ: number) => number,
    onHit: (s: ProjectileSlot) => void
  ): void {
    for (let i = 0; i < CAPACITY; i++) {
      const s = this.slots[i]!;
      if (!s.active) continue;
      // Bullet Time (Epic): nur GEGNER-Projektile werden verlangsamt
      const slotDt = s.fromPlayer ? dt : dt * enemyTimeScale;
      s.life -= slotDt;
      if (s.life <= 0) {
        s.active = false;
        continue;
      }
      s.prevX = s.x;
      s.prevY = s.y;
      s.prevZ = s.z;
      const stepX = s.vx * slotDt;
      const stepY = s.vy * slotDt;
      const stepZ = s.vz * slotDt;
      const stepLen = Math.sqrt(stepX * stepX + stepY * stepY + stepZ * stepZ);
      if (stepLen > 1e-8) {
        _origin.x = s.x;
        _origin.y = s.y;
        _origin.z = s.z;
        _dir.x = stepX / stepLen;
        _dir.y = stepY / stepLen;
        _dir.z = stepZ / stepLen;
        // Nächste Wand auf der Strecke (Box merken für Ricochet-Normale)
        let wallT = stepLen;
        let wallBox: Aabb | null = null;
        for (let b = 0; b < solids.length; b++) {
          const t = rayVsAabb(_origin, _dir, solids[b]!, wallT);
          if (t < wallT) {
            wallT = t;
            wallBox = solids[b]!;
          }
        }
        // Ziel-Treffer (Gegner bzw. Spieler) davor?
        const targetT = hitTest(s, wallT, _dir.x, _dir.y, _dir.z);
        if (targetT < wallT) {
          onHit(s);
          s.active = false;
          continue;
        }
        if (wallT < stepLen && wallBox) {
          if (s.fromPlayer && s.bounces > 0) {
            // Ricochet: Geschwindigkeit an der getroffenen Fläche spiegeln
            s.bounces--;
            const hx = _origin.x + _dir.x * wallT;
            const hy = _origin.y + _dir.y * wallT;
            const hz = _origin.z + _dir.z * wallT;
            const eps = 0.02;
            if (Math.abs(hx - wallBox.minX) < eps || Math.abs(hx - wallBox.maxX) < eps) s.vx = -s.vx;
            else if (Math.abs(hy - wallBox.minY) < eps || Math.abs(hy - wallBox.maxY) < eps) s.vy = -s.vy;
            else s.vz = -s.vz;
            s.x = hx + Math.sign(s.vx) * 0.01;
            s.y = hy;
            s.z = hz + Math.sign(s.vz) * 0.01;
            continue;
          }
          s.active = false; // Wand getroffen — verschwindet
          continue;
        }
      }
      s.x += stepX;
      s.y += stepY;
      s.z += stepZ;
      if (s.y < 0.03) {
        if (s.fromPlayer && s.bounces > 0) {
          s.bounces--;
          s.y = 0.04;
          s.vy = Math.abs(s.vy);
        } else {
          s.active = false; // Boden
        }
      }
    }
  }
}

export { rayVsSphere };
