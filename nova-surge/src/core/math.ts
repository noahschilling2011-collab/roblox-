// Mathe für die Simulation — bewusst OHNE three.js, damit core/ eigenständig
// und GC-frei bleibt. Alle Funktionen schreiben in vorhandene Objekte
// (out-Parameter), im Gameplay-Loop wird nichts alloziert.

export interface Vec3 {
  x: number;
  y: number;
  z: number;
}

export const vec3 = (x = 0, y = 0, z = 0): Vec3 => ({ x, y, z });

export function vset(out: Vec3, x: number, y: number, z: number): Vec3 {
  out.x = x;
  out.y = y;
  out.z = z;
  return out;
}

export function vcopy(out: Vec3, a: Vec3): Vec3 {
  out.x = a.x;
  out.y = a.y;
  out.z = a.z;
  return out;
}

export function vadd(out: Vec3, a: Vec3, b: Vec3): Vec3 {
  return vset(out, a.x + b.x, a.y + b.y, a.z + b.z);
}

export function vsub(out: Vec3, a: Vec3, b: Vec3): Vec3 {
  return vset(out, a.x - b.x, a.y - b.y, a.z - b.z);
}

export function vscale(out: Vec3, a: Vec3, s: number): Vec3 {
  return vset(out, a.x * s, a.y * s, a.z * s);
}

export function vaddScaled(out: Vec3, a: Vec3, b: Vec3, s: number): Vec3 {
  return vset(out, a.x + b.x * s, a.y + b.y * s, a.z + b.z * s);
}

export function vdot(a: Vec3, b: Vec3): number {
  return a.x * b.x + a.y * b.y + a.z * b.z;
}

export function vlen(a: Vec3): number {
  return Math.sqrt(a.x * a.x + a.y * a.y + a.z * a.z);
}

export function vdist(a: Vec3, b: Vec3): number {
  const dx = a.x - b.x;
  const dy = a.y - b.y;
  const dz = a.z - b.z;
  return Math.sqrt(dx * dx + dy * dy + dz * dz);
}

export function vdistSq(a: Vec3, b: Vec3): number {
  const dx = a.x - b.x;
  const dy = a.y - b.y;
  const dz = a.z - b.z;
  return dx * dx + dy * dy + dz * dz;
}

export function vnormalize(out: Vec3, a: Vec3): Vec3 {
  const l = vlen(a);
  return l > 1e-8 ? vscale(out, a, 1 / l) : vset(out, 0, 0, 0);
}

export function clamp(v: number, min: number, max: number): number {
  return v < min ? min : v > max ? max : v;
}

export function lerp(a: number, b: number, t: number): number {
  return a + (b - a) * t;
}

/** Exponentielles Abklingen, framerate-unabhängig (für Feder-/Recovery-Effekte). */
export function damp(current: number, target: number, lambda: number, dt: number): number {
  return lerp(current, target, 1 - Math.exp(-lambda * dt));
}

// ---- AABB (achsen-ausgerichtete Box) ----
// Die komplette Arena-Kollision läuft über AABBs: Wände, Deckung, Rampen-Stufen.

export interface Aabb {
  minX: number;
  minY: number;
  minZ: number;
  maxX: number;
  maxY: number;
  maxZ: number;
}

export function aabbFromCenter(cx: number, cy: number, cz: number, sx: number, sy: number, sz: number): Aabb {
  return {
    minX: cx - sx / 2,
    minY: cy - sy / 2,
    minZ: cz - sz / 2,
    maxX: cx + sx / 2,
    maxY: cy + sy / 2,
    maxZ: cz + sz / 2,
  };
}

/**
 * Ray gegen AABB (Slab-Methode). Liefert Distanz t >= 0 entlang der
 * (normierten) Richtung oder Infinity bei Fehlschuss.
 */
export function rayVsAabb(origin: Vec3, dir: Vec3, box: Aabb, maxDist: number): number {
  let tMin = 0;
  let tMax = maxDist;

  const invX = 1 / dir.x;
  let t1 = (box.minX - origin.x) * invX;
  let t2 = (box.maxX - origin.x) * invX;
  tMin = Math.max(tMin, Math.min(t1, t2));
  tMax = Math.min(tMax, Math.max(t1, t2));

  const invY = 1 / dir.y;
  t1 = (box.minY - origin.y) * invY;
  t2 = (box.maxY - origin.y) * invY;
  tMin = Math.max(tMin, Math.min(t1, t2));
  tMax = Math.min(tMax, Math.max(t1, t2));

  const invZ = 1 / dir.z;
  t1 = (box.minZ - origin.z) * invZ;
  t2 = (box.maxZ - origin.z) * invZ;
  tMin = Math.max(tMin, Math.min(t1, t2));
  tMax = Math.min(tMax, Math.max(t1, t2));

  return tMax >= tMin ? tMin : Infinity;
}

/**
 * Ray gegen Kugel. Liefert Distanz t >= 0 oder Infinity.
 * (Gegner-Hitboxen sind Kugeln pro Körperteil — billig und gut genug.)
 */
export function rayVsSphere(origin: Vec3, dir: Vec3, cx: number, cy: number, cz: number, radius: number): number {
  const ox = origin.x - cx;
  const oy = origin.y - cy;
  const oz = origin.z - cz;
  const b = ox * dir.x + oy * dir.y + oz * dir.z;
  const c = ox * ox + oy * oy + oz * oz - radius * radius;
  // Ursprung liegt bereits IN der Kugel (Gegner bedrängt den Spieler):
  // sofortiger Treffer — sonst gingen Punktblank-Schüsse durch ihn hindurch.
  if (c <= 0) return 0;
  const disc = b * b - c;
  if (disc < 0) return Infinity;
  const t = -b - Math.sqrt(disc);
  return t >= 0 ? t : Infinity;
}

/** Sichtlinien-Check: ist die Strecke a->b frei von allen Blocker-Boxen? */
export function segmentClear(a: Vec3, b: Vec3, blockers: readonly Aabb[]): boolean {
  const dx = b.x - a.x;
  const dy = b.y - a.y;
  const dz = b.z - a.z;
  const dist = Math.sqrt(dx * dx + dy * dy + dz * dz);
  if (dist < 1e-6) return true;
  _segDir.x = dx / dist;
  _segDir.y = dy / dist;
  _segDir.z = dz / dist;
  for (let i = 0; i < blockers.length; i++) {
    if (rayVsAabb(a, _segDir, blockers[i]!, dist) < dist) return false;
  }
  return true;
}

const _segDir = vec3();
