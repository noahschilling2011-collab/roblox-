// Kollisionswelt der Simulation: aus einer Arena-Definition gebaute AABBs.
// Ein gemeinsamer Body-Mover für Spieler UND Bots (Kapsel als Box angenähert,
// Achsen nacheinander aufgelöst — stabil und billig).

import type { ArenaDef } from "../config/arena";
import type { Aabb, Vec3 } from "./math";

export interface CollisionWorld {
  /** Alles Feste (Wände, hohe + niedrige Blöcke) — blockiert Bewegung & Schüsse. */
  solids: readonly Aabb[];
  /** Nur Sicht-Blocker (Wände + hohe Blöcke) — für LOS-Checks auf Augenhöhe. */
  losBlockers: readonly Aabb[];
  /** Halbe Arena-Kantenlänge (Sicherheitsnetz-Klammer). */
  halfSize: number;
}

export function buildCollisionWorld(arena: ArenaDef): CollisionWorld {
  const solids: Aabb[] = [];
  const losBlockers: Aabb[] = [];
  for (const b of arena.boxes) {
    const box: Aabb = {
      minX: b.x - b.sx / 2,
      minY: 0,
      minZ: b.z - b.sz / 2,
      maxX: b.x + b.sx / 2,
      maxY: b.h,
      maxZ: b.z + b.sz / 2,
    };
    solids.push(box);
    if (b.kind !== "low") losBlockers.push(box);
  }
  return { solids, losBlockers, halfSize: arena.size / 2 };
}

/**
 * Bewegt einen stehenden Körper (Fußpunkt `pos`, Radius, Höhe) um vel*dt und
 * löst Kollisionen mit allen Solids + Boden auf. Schreibt pos/vel, liefert
 * true, wenn der Körper am Boden steht.
 */
export function moveBody(
  pos: Vec3,
  vel: Vec3,
  radius: number,
  height: number,
  dt: number,
  world: CollisionWorld
): boolean {
  const solids = world.solids;
  const half = world.halfSize;
  // --- X ---
  pos.x += vel.x * dt;
  for (let i = 0; i < solids.length; i++) {
    const b = solids[i]!;
    if (!overlapsYZ(pos, radius, height, b)) continue;
    if (pos.x + radius > b.minX && pos.x - radius < b.maxX) {
      if (vel.x > 0) pos.x = b.minX - radius;
      else if (vel.x < 0) pos.x = b.maxX + radius;
      vel.x = 0;
    }
  }
  // --- Z ---
  pos.z += vel.z * dt;
  for (let i = 0; i < solids.length; i++) {
    const b = solids[i]!;
    if (!overlapsYX(pos, radius, height, b)) continue;
    if (pos.z + radius > b.minZ && pos.z - radius < b.maxZ) {
      if (vel.z > 0) pos.z = b.minZ - radius;
      else if (vel.z < 0) pos.z = b.maxZ + radius;
      vel.z = 0;
    }
  }
  // Sicherheitsnetz: nie aus der Arena fallen
  if (pos.x < -half + 0.5) pos.x = -half + 0.5;
  if (pos.x > half - 0.5) pos.x = half - 0.5;
  if (pos.z < -half + 0.5) pos.z = -half + 0.5;
  if (pos.z > half - 0.5) pos.z = half - 0.5;

  // --- Y (Boden = höchste Blockoberkante unter dem Körper, sonst 0) ---
  pos.y += vel.y * dt;
  let floor = 0;
  for (let i = 0; i < solids.length; i++) {
    const b = solids[i]!;
    if (pos.x + radius <= b.minX || pos.x - radius >= b.maxX) continue;
    if (pos.z + radius <= b.minZ || pos.z - radius >= b.maxZ) continue;
    // Block zählt als Boden, wenn wir von oben kommen
    if (b.maxY <= pos.y + 0.01 + Math.max(0, -vel.y * dt) && b.maxY > floor) floor = b.maxY;
    // Kopf stoßen
    if (vel.y > 0 && pos.y + height > b.minY && pos.y < b.minY && b.maxY > pos.y + height) {
      pos.y = b.minY - height;
      vel.y = 0;
    }
  }
  if (pos.y <= floor) {
    pos.y = floor;
    if (vel.y < 0) vel.y = 0;
    return true;
  }
  return false;
}

function overlapsYZ(pos: Vec3, radius: number, height: number, b: Aabb): boolean {
  return pos.y < b.maxY && pos.y + height > b.minY && pos.z + radius > b.minZ && pos.z - radius < b.maxZ;
}

function overlapsYX(pos: Vec3, radius: number, height: number, b: Aabb): boolean {
  return pos.y < b.maxY && pos.y + height > b.minY && pos.x + radius > b.minX && pos.x - radius < b.maxX;
}
