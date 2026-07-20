// Arenen-Config: DREI Maps, alle nach denselben Layout-Prinzipien —
// klare Sichtachsen, Deckung, 2 Höhenebenen, kein toter Winkel ohne zweiten
// Ausgang. Höhen sind bewusst überall gleich (Gameplay bleibt lernbar):
//   TALL (2,4 m) = echte Deckung, blockiert Sicht, nicht besteigbar
//   LOW  (1,1 m) = besteigbar (Sprung ~1,4 m), blockiert Sicht NICHT
// Rusher können auf LOW springen (Anti-Camping).

export const HEIGHTS = {
  wall: 5,
  tall: 2.4,
  low: 1.1,
} as const;

export interface ArenaPalette {
  sky: number;
  fogNear: number;
  fogFar: number;
  floor: number;
  wall: number;
  tall: number;
  low: number;
  accent: number;
  grid1: number;
  grid2: number;
}

export interface ArenaBox {
  x: number;
  z: number;
  sx: number;
  sz: number;
  h: number;
  kind: "wall" | "tall" | "low";
}

export interface ArenaDef {
  id: string;
  name: string; // Anzeigename EN
  sub: string; // Kurzbeschreibung fürs Menü
  size: number; // Kantenlänge, Mitte (0,0)
  palette: ArenaPalette;
  boxes: ArenaBox[];
  enemySpawns: { x: number; z: number }[];
  playerSpawn: { x: number; z: number };
}

/** Außenwände + Spawn-Tore an den Wandmitten für eine gegebene Größe. */
function perimeter(size: number): ArenaBox[] {
  const s = size / 2;
  return [
    { x: 0, z: -s, sx: size, sz: 1, h: HEIGHTS.wall, kind: "wall" },
    { x: 0, z: s, sx: size, sz: 1, h: HEIGHTS.wall, kind: "wall" },
    { x: -s, z: 0, sx: 1, sz: size, h: HEIGHTS.wall, kind: "wall" },
    { x: s, z: 0, sx: 1, sz: size, h: HEIGHTS.wall, kind: "wall" },
  ];
}

function gates(size: number): { x: number; z: number }[] {
  const s = size / 2 - 2.5;
  return [
    { x: 0, z: -s },
    { x: 0, z: s },
    { x: -s, z: 0 },
    { x: s, z: 0 },
  ];
}

// ---- Map 1: Foundry — Industriehof, vier L-Deckungen, symmetrisch ----
const FOUNDRY: ArenaDef = {
  id: "foundry",
  name: "Foundry",
  sub: "Balanced · symmetric",
  size: 64,
  palette: {
    sky: 0x9fd8ff,
    fogNear: 55,
    fogFar: 140,
    floor: 0x6b7480,
    wall: 0x525b66,
    tall: 0x5c6672,
    low: 0x7a8490,
    accent: 0xff8b3d,
    grid1: 0x8b95a1,
    grid2: 0x79828e,
  },
  boxes: [
    ...perimeter(64),
    { x: -10, z: -10, sx: 8, sz: 2, h: HEIGHTS.tall, kind: "tall" },
    { x: -13, z: -7, sx: 2, sz: 8, h: HEIGHTS.tall, kind: "tall" },
    { x: 10, z: -10, sx: 8, sz: 2, h: HEIGHTS.tall, kind: "tall" },
    { x: 13, z: -7, sx: 2, sz: 8, h: HEIGHTS.tall, kind: "tall" },
    { x: -10, z: 10, sx: 8, sz: 2, h: HEIGHTS.tall, kind: "tall" },
    { x: -13, z: 7, sx: 2, sz: 8, h: HEIGHTS.tall, kind: "tall" },
    { x: 10, z: 10, sx: 8, sz: 2, h: HEIGHTS.tall, kind: "tall" },
    { x: 13, z: 7, sx: 2, sz: 8, h: HEIGHTS.tall, kind: "tall" },
    { x: 0, z: 0, sx: 6, sz: 6, h: HEIGHTS.low, kind: "low" },
    { x: -22, z: 0, sx: 4, sz: 4, h: HEIGHTS.low, kind: "low" },
    { x: 22, z: 0, sx: 4, sz: 4, h: HEIGHTS.low, kind: "low" },
    { x: 0, z: -22, sx: 4, sz: 4, h: HEIGHTS.low, kind: "low" },
    { x: 0, z: 22, sx: 4, sz: 4, h: HEIGHTS.low, kind: "low" },
  ],
  enemySpawns: gates(64),
  playerSpawn: { x: 0, z: 12 },
};

// ---- Map 2: Frostworks — enge Lanes zwischen zwei langen Mauern ----
const FROSTWORKS: ArenaDef = {
  id: "frostworks",
  name: "Frostworks",
  sub: "Tight lanes · risky",
  size: 56,
  palette: {
    sky: 0xd8ecff,
    fogNear: 45,
    fogFar: 120,
    floor: 0x93a5b5,
    wall: 0x7d92a6,
    tall: 0xa2b8cc,
    low: 0xbcccdb,
    accent: 0x2fb7ff,
    grid1: 0xb3c4d4,
    grid2: 0xa0b2c3,
  },
  boxes: [
    ...perimeter(56),
    // Zwei lange Mauern -> drei Lanes; Enden bleiben offen (zweiter Ausgang)
    { x: -8, z: 0, sx: 2, sz: 22, h: HEIGHTS.tall, kind: "tall" },
    { x: 8, z: 0, sx: 2, sz: 22, h: HEIGHTS.tall, kind: "tall" },
    // Querriegel oben/unten, versetzt
    { x: 0, z: -17, sx: 10, sz: 2, h: HEIGHTS.tall, kind: "tall" },
    { x: 0, z: 17, sx: 10, sz: 2, h: HEIGHTS.tall, kind: "tall" },
    // Besteigbare Blöcke in den Lanes + Ecken
    { x: 0, z: 0, sx: 5, sz: 5, h: HEIGHTS.low, kind: "low" },
    { x: -18, z: -10, sx: 4, sz: 4, h: HEIGHTS.low, kind: "low" },
    { x: 18, z: -10, sx: 4, sz: 4, h: HEIGHTS.low, kind: "low" },
    { x: -18, z: 10, sx: 4, sz: 4, h: HEIGHTS.low, kind: "low" },
    { x: 18, z: 10, sx: 4, sz: 4, h: HEIGHTS.low, kind: "low" },
  ],
  enemySpawns: gates(56),
  playerSpawn: { x: 0, z: 21 },
};

// ---- Map 3: Sunreach — offener Canyon, versetzte Felsriegel ----
const SUNREACH: ArenaDef = {
  id: "sunreach",
  name: "Sunreach",
  sub: "Wide open · sniper heaven",
  size: 72,
  palette: {
    sky: 0xffe0ad,
    fogNear: 60,
    fogFar: 160,
    floor: 0xc7a468,
    wall: 0xa8854d,
    tall: 0xb08d55,
    low: 0xdcc08a,
    accent: 0xff5636,
    grid1: 0xd4b57c,
    grid2: 0xc3a56d,
  },
  boxes: [
    ...perimeter(72),
    // Versetzte Riegel ("Felsen") — Diagonale Rotations-Routen
    { x: -14, z: -6, sx: 7, sz: 2, h: HEIGHTS.tall, kind: "tall" },
    { x: -6, z: -14, sx: 2, sz: 7, h: HEIGHTS.tall, kind: "tall" },
    { x: 14, z: 6, sx: 7, sz: 2, h: HEIGHTS.tall, kind: "tall" },
    { x: 6, z: 14, sx: 2, sz: 7, h: HEIGHTS.tall, kind: "tall" },
    { x: 14, z: -12, sx: 5, sz: 2, h: HEIGHTS.tall, kind: "tall" },
    { x: -14, z: 12, sx: 5, sz: 2, h: HEIGHTS.tall, kind: "tall" },
    // Zentraler Felsturm + besteigbare Plateaus
    { x: 0, z: 0, sx: 4, sz: 4, h: HEIGHTS.tall, kind: "tall" },
    { x: -24, z: 0, sx: 5, sz: 5, h: HEIGHTS.low, kind: "low" },
    { x: 24, z: 0, sx: 5, sz: 5, h: HEIGHTS.low, kind: "low" },
    { x: 0, z: -24, sx: 5, sz: 5, h: HEIGHTS.low, kind: "low" },
    { x: 0, z: 24, sx: 5, sz: 5, h: HEIGHTS.low, kind: "low" },
    { x: -10, z: 8, sx: 3, sz: 3, h: HEIGHTS.low, kind: "low" },
    { x: 10, z: -8, sx: 3, sz: 3, h: HEIGHTS.low, kind: "low" },
  ],
  enemySpawns: gates(72),
  playerSpawn: { x: 0, z: 16 },
};

export const ARENAS: ArenaDef[] = [FOUNDRY, FROSTWORKS, SUNREACH];

export function getArena(id: string): ArenaDef {
  return ARENAS.find((a) => a.id === id) ?? FOUNDRY;
}
