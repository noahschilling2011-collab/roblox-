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
      });
    }
  }

  clear(): void {
    for (const s of this.slots) s.active = false;
  }

  spawn(fromPlayer: boolean, origin: Vec3, dir: Vec3, speed: number, life: number, damage: number): void {
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
    solids: readonly Aabb[],
    hitTest: (s: ProjectileSlot, dist: number, dirX: number, dirY: number, dirZ: number) => number,
    onHit: (s: ProjectileSlot) => void
  ): void {
    for (let i = 0; i < CAPACITY; i++) {
      const s = this.slots[i]!;
      if (!s.active) continue;
      s.life -= dt;
      if (s.life <= 0) {
        s.active = false;
        continue;
      }
      s.prevX = s.x;
      s.prevY = s.y;
      s.prevZ = s.z;
      const stepX = s.vx * dt;
      const stepY = s.vy * dt;
      const stepZ = s.vz * dt;
      const stepLen = Math.sqrt(stepX * stepX + stepY * stepY + stepZ * stepZ);
      if (stepLen > 1e-8) {
        _origin.x = s.x;
        _origin.y = s.y;
        _origin.z = s.z;
        _dir.x = stepX / stepLen;
        _dir.y = stepY / stepLen;
        _dir.z = stepZ / stepLen;
        // Nächste Wand auf der Strecke
        let wallT = stepLen;
        for (let b = 0; b < solids.length; b++) {
          const t = rayVsAabb(_origin, _dir, solids[b]!, wallT);
          if (t < wallT) wallT = t;
        }
        // Ziel-Treffer (Gegner bzw. Spieler) davor?
        const targetT = hitTest(s, wallT, _dir.x, _dir.y, _dir.z);
        if (targetT < wallT) {
          onHit(s);
          s.active = false;
          continue;
        }
        if (wallT < stepLen) {
          s.active = false; // Wand getroffen — verschwindet (Partikel via Renderer optional)
          continue;
        }
      }
      s.x += stepX;
      s.y += stepY;
      s.z += stepZ;
      if (s.y < 0.03) s.active = false; // Boden
    }
  }
}

export { rayVsSphere };
