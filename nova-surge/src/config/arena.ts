// Die Arena (Phase 3). Layout-Prinzipien: klare Sichtachsen, Deckung,
// 2 Höhenebenen (Boden + besteigbare 1,1-m-Blöcke), kein toter Winkel ohne
// zweiten Ausgang. Farbpalette: 2 Grundtöne + 1 Akzent (Orange).
//
// Höhenregeln:
//   TALL  (2,4 m)  = echte Deckung, blockiert Sicht, nicht besteigbar
//   LOW   (1,1 m)  = besteigbar (Sprung = ~1,4 m), blockiert Sicht NICHT
//                    auf Augenhöhe -> zählt nicht als LOS-Blocker
// Rusher können auf LOW springen (Anti-Camping, siehe enemies.ts).

export const ARENA = {
  size: 64, // Meter Kantenlänge, Mitte = (0,0)
  wallHeight: 5,
  tallHeight: 2.4,
  lowHeight: 1.1,
} as const;

export const PALETTE = {
  sky: 0x9fd8ff,
  fogNear: 55,
  fogFar: 140,
  floor: 0x6b7480, // Grundton 1
  wall: 0x525b66, // Grundton 2
  tall: 0x5c6672,
  low: 0x7a8490,
  accent: 0xff8b3d, // Akzent: Spawn-Tore, Kanten, Markierungen
  platform: 0x707a86,
} as const;

/** Ein Arena-Block: Position (Mitte), Grundfläche, Höhe, Klasse. */
export interface ArenaBox {
  x: number;
  z: number;
  sx: number;
  sz: number;
  h: number;
  kind: "wall" | "tall" | "low";
}

const S = ARENA.size / 2; // 32

// Symmetrisches Layout (4-fach gespiegelt): vier hohe L-Deckungen im
// Mittelfeld, niedrige Blöcke als Sprung-Ebene, freie Sichtachsen auf
// den Diagonalen und durch die Mitte.
export const ARENA_BOXES: ArenaBox[] = [
  // Außenwände (4 Stück, leicht nach innen versetzt, damit außen Himmel bleibt)
  { x: 0, z: -S, sx: ARENA.size, sz: 1, h: ARENA.wallHeight, kind: "wall" },
  { x: 0, z: S, sx: ARENA.size, sz: 1, h: ARENA.wallHeight, kind: "wall" },
  { x: -S, z: 0, sx: 1, sz: ARENA.size, h: ARENA.wallHeight, kind: "wall" },
  { x: S, z: 0, sx: 1, sz: ARENA.size, h: ARENA.wallHeight, kind: "wall" },

  // Hohe L-Deckungen (blockieren Sicht, erzeugen Rotations-Lanes)
  { x: -10, z: -10, sx: 8, sz: 2, h: ARENA.tallHeight, kind: "tall" },
  { x: -13, z: -7, sx: 2, sz: 8, h: ARENA.tallHeight, kind: "tall" },
  { x: 10, z: -10, sx: 8, sz: 2, h: ARENA.tallHeight, kind: "tall" },
  { x: 13, z: -7, sx: 2, sz: 8, h: ARENA.tallHeight, kind: "tall" },
  { x: -10, z: 10, sx: 8, sz: 2, h: ARENA.tallHeight, kind: "tall" },
  { x: -13, z: 7, sx: 2, sz: 8, h: ARENA.tallHeight, kind: "tall" },
  { x: 10, z: 10, sx: 8, sz: 2, h: ARENA.tallHeight, kind: "tall" },
  { x: 13, z: 7, sx: 2, sz: 8, h: ARENA.tallHeight, kind: "tall" },

  // Niedrige, besteigbare Blöcke (Höhenebene 2)
  { x: 0, z: 0, sx: 6, sz: 6, h: ARENA.lowHeight, kind: "low" }, // Mitte = High Ground
  { x: -22, z: 0, sx: 4, sz: 4, h: ARENA.lowHeight, kind: "low" },
  { x: 22, z: 0, sx: 4, sz: 4, h: ARENA.lowHeight, kind: "low" },
  { x: 0, z: -22, sx: 4, sz: 4, h: ARENA.lowHeight, kind: "low" },
  { x: 0, z: 22, sx: 4, sz: 4, h: ARENA.lowHeight, kind: "low" },
];

/** Gegner-Spawnpunkte: die vier "Tore" an den Wandmitten (innen). */
export const ENEMY_SPAWNS: { x: number; z: number }[] = [
  { x: 0, z: -S + 2.5 },
  { x: 0, z: S - 2.5 },
  { x: -S + 2.5, z: 0 },
  { x: S - 2.5, z: 0 },
];

export const PLAYER_SPAWN = { x: 0, z: 12 };
