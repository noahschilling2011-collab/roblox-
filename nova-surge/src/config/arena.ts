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
  /** Basis-Höhe (Unterkante), Default 0 — Etagenböden/Decken/Plattformen. */
  y?: number;
  kind: "wall" | "tall" | "low";
}

/** Treppen-Helfer (Multi-Level Phase 1): generiert Stufen-Boxen und merkt
 *  sich die Verbindung als Nav-Kante (Phase 2). Achsen-parallel (die
 *  dominante Achse von from->to wird benutzt). */
export interface StairsDef {
  from: [number, number, number]; // x, z, y
  to: [number, number, number];
  width: number;
}

const STEP_MAX = 0.3;

/** Expandiert eine Treppe in solide Stufen-Boxen (kind "low": kein LOS-Block). */
export function expandStairs(s: StairsDef): ArenaBox[] {
  // Normalisieren: "from" ist immer das untere Ende
  const asc = s.from[2] <= s.to[2];
  const [fx, fz, fy] = asc ? s.from : s.to;
  const [tx, tz, ty] = asc ? s.to : s.from;
  const rise = ty - fy;
  const steps = Math.max(1, Math.ceil(rise / STEP_MAX));
  const stepRise = rise / steps;
  const alongX = Math.abs(tx - fx) >= Math.abs(tz - fz);
  const run = alongX ? tx - fx : tz - fz;
  const stepRun = run / steps;
  const boxes: ArenaBox[] = [];
  for (let i = 0; i < steps; i++) {
    const top = fy + stepRise * (i + 1);
    const cx = alongX ? fx + stepRun * (i + 0.5) : fx;
    const cz = alongX ? fz : fz + stepRun * (i + 0.5);
    boxes.push({
      x: cx,
      z: cz,
      sx: alongX ? Math.abs(stepRun) + 0.02 : s.width,
      sz: alongX ? s.width : Math.abs(stepRun) + 0.02,
      y: fy, // solide bis zur Treppen-Basis (keine Lücken darunter)
      h: top - fy,
      kind: "low",
    });
  }
  return boxes;
}

/** Rein dekoratives Element — KEINE Kollision, darf daher nie im Laufweg
 *  auf Körperhöhe stehen (nur flach am Boden, auf Deckungen oder über Kopf). */
export interface ArenaProp {
  x: number;
  y: number; // Mittelpunkt-Höhe
  z: number;
  sx: number;
  sy: number;
  sz: number;
  color: number;
  glow?: boolean; // leuchtet (Neonschilder, Poolwasser)
}

export interface ArenaDef {
  id: string;
  name: string; // Anzeigename EN
  sub: string; // Kurzbeschreibung fürs Menü
  size: number; // Kantenlänge, Mitte (0,0)
  palette: ArenaPalette;
  boxes: ArenaBox[];
  stairs?: StairsDef[];
  props?: ArenaProp[];
  showGrid?: boolean; // default true (false z. B. auf Wasser)
  /** y = Spawn-Ebene (Default 0). Die 60/40-Regel bevorzugt die Spieler-Ebene. */
  enemySpawns: { x: number; z: number; y?: number }[];
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

// ---- Map 4: Azure Deck — Sonnendeck einer Luxusyacht auf offener See ----
// Spielfläche ist das Deck (26 x 40) innerhalb der Bordwände; der Boden
// außerhalb ist Wasser (nur Optik), Bug/Heck sind dekorative Props.
const YACHT: ArenaDef = {
  id: "yacht",
  name: "Azure Deck",
  sub: "Luxury yacht · close quarters",
  size: 60,
  palette: {
    sky: 0xffcf9e, // Sonnenuntergang
    fogNear: 45,
    fogFar: 130,
    floor: 0x2e7fa8, // Meer
    wall: 0xf2f4f6, // weiße Bordwand
    tall: 0xe9edf1, // Kabine
    low: 0xdfe4e9,
    accent: 0xff6a4d, // Koralle
    grid1: 0xffffff,
    grid2: 0xffffff,
  },
  showGrid: false,
  boxes: [
    // Bordwände (2,6 m: Deckung + nicht überspringbar), Deck 26 x 40
    { x: -13, z: 0, sx: 1, sz: 40, h: 2.6, kind: "wall" },
    { x: 13, z: 0, sx: 1, sz: 40, h: 2.6, kind: "wall" },
    { x: 0, z: -20, sx: 27, sz: 1, h: 2.6, kind: "wall" },
    { x: 0, z: 20, sx: 27, sz: 1, h: 2.6, kind: "wall" },
    // Kabinen-Aufbau = zentrale Deckung
    { x: 0, z: 7, sx: 10, sz: 6, h: HEIGHTS.tall, kind: "tall" },
    // Technik-Container an den Seiten
    { x: -9, z: -6, sx: 3, sz: 5, h: HEIGHTS.tall, kind: "tall" },
    { x: 9, z: -6, sx: 3, sz: 5, h: HEIGHTS.tall, kind: "tall" },
    // Besteigbares: Sonnendeck-Podest am Bug, Bar am Heck, Kisten
    { x: 0, z: -15, sx: 6, sz: 4, h: HEIGHTS.low, kind: "low" },
    { x: 0, z: 16, sx: 8, sz: 2.5, h: HEIGHTS.low, kind: "low" },
    { x: -9, z: 13, sx: 2.5, sz: 2.5, h: HEIGHTS.low, kind: "low" },
    { x: 9, z: 13, sx: 2.5, sz: 2.5, h: HEIGHTS.low, kind: "low" },
  ],
  props: [
    // Deck-Holzboden (flach, Füße stehen optisch auf Planken)
    { x: 0, y: -0.03, z: 0, sx: 25.6, sy: 0.1, sz: 39.6, color: 0xc9a06a },
    // Bug-Spitze (vor der Wand, im Wasser — nur Silhouette)
    { x: 0, y: 0.25, z: -23, sx: 20, sy: 0.6, sz: 5, color: 0xf2f4f6 },
    { x: 0, y: 0.25, z: -26.5, sx: 12, sy: 0.6, sz: 4, color: 0xf2f4f6 },
    { x: 0, y: 0.25, z: -29, sx: 5, sy: 0.6, sz: 2.5, color: 0xf2f4f6 },
    // Heck-Plattform
    { x: 0, y: 0.2, z: 22.5, sx: 18, sy: 0.5, sz: 4, color: 0xf2f4f6 },
    // Pool im Bug-Podest (leuchtendes Wasser)
    { x: 0, y: 1.16, z: -15, sx: 4.6, sy: 0.06, sz: 2.8, color: 0x35c5e8, glow: true },
    // Schornstein + Mast + Radar auf der Kabine
    { x: 0, y: 3.3, z: 8.5, sx: 2.6, sy: 1.8, sz: 1.4, color: 0xf2f4f6 },
    { x: 0, y: 3.1, z: 5.5, sx: 0.18, sy: 2.2, sz: 0.18, color: 0xd8dde2 },
    { x: 0, y: 4.3, z: 5.5, sx: 1.4, sy: 0.12, sz: 0.3, color: 0xff6a4d },
    // Handtücher/Matten auf dem Deck (ganz flach — begehbar ohne Clipping)
    { x: -6, y: 0.06, z: -11, sx: 0.9, sy: 0.08, sz: 2.2, color: 0xff6a4d },
    { x: -4, y: 0.06, z: -11, sx: 0.9, sy: 0.08, sz: 2.2, color: 0xffffff },
    { x: 6, y: 0.06, z: -11, sx: 0.9, sy: 0.08, sz: 2.2, color: 0xff6a4d },
    { x: 4, y: 0.06, z: -11, sx: 0.9, sy: 0.08, sz: 2.2, color: 0xffffff },
  ],
  // Spawns = "Enterpunkte" in den Deck-Ecken
  enemySpawns: [
    { x: -10, z: -17 },
    { x: 10, z: -17 },
    { x: -10, z: 17.5 },
    { x: 10, z: 17.5 },
  ],
  playerSpawn: { x: 0, z: 0 },
};

// ---- Map 5: Grand Gallery — helles Einkaufszentrum mit Neon-Läden ----
const MALL: ArenaDef = {
  id: "mall",
  name: "Grand Gallery",
  sub: "Shopping mall · neon lanes",
  size: 64,
  palette: {
    sky: 0xdff0ff, // Glasdach-Licht
    fogNear: 55,
    fogFar: 150,
    floor: 0xe6ded0, // Fliesen
    wall: 0xcfc6b8,
    tall: 0xb8aa96, // Ladenfronten
    low: 0xd8cfc0,
    accent: 0xff4f9a, // Pink-Neon
    grid1: 0xf2ece0, // Fliesenfugen
    grid2: 0xdcd3c4,
  },
  boxes: [
    ...perimeter(64),
    // Ladenzeilen an den Wänden (mit Lücken = Gänge, kein toter Winkel)
    { x: -26, z: -12, sx: 8, sz: 7, h: HEIGHTS.tall, kind: "tall" },
    { x: -26, z: 12, sx: 8, sz: 7, h: HEIGHTS.tall, kind: "tall" },
    { x: 26, z: -12, sx: 8, sz: 7, h: HEIGHTS.tall, kind: "tall" },
    { x: 26, z: 12, sx: 8, sz: 7, h: HEIGHTS.tall, kind: "tall" },
    { x: -12, z: -26, sx: 7, sz: 8, h: HEIGHTS.tall, kind: "tall" },
    { x: 12, z: -26, sx: 7, sz: 8, h: HEIGHTS.tall, kind: "tall" },
    { x: -12, z: 26, sx: 7, sz: 8, h: HEIGHTS.tall, kind: "tall" },
    { x: 12, z: 26, sx: 7, sz: 8, h: HEIGHTS.tall, kind: "tall" },
    // Springbrunnen in der Mitte + Kioske
    { x: 0, z: 0, sx: 7, sz: 7, h: HEIGHTS.low, kind: "low" },
    { x: -14, z: 0, sx: 3, sz: 5, h: HEIGHTS.low, kind: "low" },
    { x: 14, z: 0, sx: 3, sz: 5, h: HEIGHTS.low, kind: "low" },
    // Pflanzkübel
    { x: 0, z: -16, sx: 3, sz: 3, h: HEIGHTS.low, kind: "low" },
    { x: 0, z: 16, sx: 3, sz: 3, h: HEIGHTS.low, kind: "low" },
  ],
  props: [
    // Neonschilder über den Ladenfronten (verschiedene Farben)
    { x: -26, y: 2.9, z: -12, sx: 6.5, sy: 0.7, sz: 0.3, color: 0xff4f9a, glow: true },
    { x: -26, y: 2.9, z: 12, sx: 6.5, sy: 0.7, sz: 0.3, color: 0x37e0ff, glow: true },
    { x: 26, y: 2.9, z: -12, sx: 6.5, sy: 0.7, sz: 0.3, color: 0xffd23a, glow: true },
    { x: 26, y: 2.9, z: 12, sx: 6.5, sy: 0.7, sz: 0.3, color: 0x7dff8b, glow: true },
    { x: -12, y: 2.9, z: -26, sx: 0.3, sy: 0.7, sz: 6.5, color: 0x37e0ff, glow: true },
    { x: 12, y: 2.9, z: -26, sx: 0.3, sy: 0.7, sz: 6.5, color: 0xff4f9a, glow: true },
    { x: -12, y: 2.9, z: 26, sx: 0.3, sy: 0.7, sz: 6.5, color: 0xffd23a, glow: true },
    { x: 12, y: 2.9, z: 26, sx: 0.3, sy: 0.7, sz: 6.5, color: 0xb07dff, glow: true },
    // Springbrunnen-Wasser + Fontänen-Säule
    { x: 0, y: 1.16, z: 0, sx: 5.8, sy: 0.06, sz: 5.8, color: 0x35c5e8, glow: true },
    { x: 0, y: 1.7, z: 0, sx: 0.5, sy: 1.1, sz: 0.5, color: 0x9fdcf0 },
    // Büsche auf den Pflanzkübeln
    { x: 0, y: 1.5, z: -16, sx: 2.2, sy: 0.9, sz: 2.2, color: 0x3f9b4f },
    { x: 0, y: 1.5, z: 16, sx: 2.2, sy: 0.9, sz: 2.2, color: 0x3f9b4f },
    // Glasdach-Träger hoch über der Halle
    { x: 0, y: 7.5, z: -16, sx: 63, sy: 0.4, sz: 0.6, color: 0xffffff },
    { x: 0, y: 7.5, z: 0, sx: 63, sy: 0.4, sz: 0.6, color: 0xffffff },
    { x: 0, y: 7.5, z: 16, sx: 63, sy: 0.4, sz: 0.6, color: 0xffffff },
    // Teppich-Inseln am Brunnen (ganz flach — begehbar ohne Clipping)
    { x: -6, y: 0.04, z: 0, sx: 1.6, sy: 0.06, sz: 4, color: 0xb44f6e },
    { x: 6, y: 0.04, z: 0, sx: 1.6, sy: 0.06, sz: 4, color: 0xb44f6e },
  ],
  enemySpawns: gates(64),
  playerSpawn: { x: 0, z: 12 },
};

export const ARENAS: ArenaDef[] = [FOUNDRY, FROSTWORKS, SUNREACH, YACHT, MALL];

// ---- Debug-Arena (Multi-Level Phase 1) — NICHT im Menü, nur für Tests ----
// Plattform auf 3 m mit Treppe: Stehen, Fallen, Kopf-Anstoßen,
// Hitscan-durch-Boden-Block. Zugriff über window.__ns.debugArena.
export const DEBUG_ARENA: ArenaDef = {
  id: "debug",
  name: "Debug",
  sub: "engine test",
  size: 40,
  palette: FOUNDRY.palette,
  boxes: [
    ...perimeter(40),
    { x: 0, z: -8, sx: 8, sz: 8, y: 3, h: 0.4, kind: "tall" }, // Plattform (Decke von unten)
  ],
  stairs: [{ from: [8, -8, 0], to: [4.2, -8, 3.4], width: 2.5 }],
  // Letzter Spawn liegt AUF der Plattform (Test: Spawn-Ebenen + 60/40-Regel)
  enemySpawns: [...gates(40), { x: -2, z: -8, y: 3.4 }],
  playerSpawn: { x: 0, z: 12 },
};

export function getArena(id: string): ArenaDef {
  return ARENAS.find((a) => a.id === id) ?? FOUNDRY;
}
