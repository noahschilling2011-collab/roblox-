// Die drei Bot-Typen. Silhouette + Farbe müssen auf einen Blick unterscheidbar
// sein: Rusher = schmaler roter Kegel, Shooter = eckiger violetter Turm mit
// Lauf, Tank = breiter dunkelgrüner Block.

export type EnemyType = "rusher" | "shooter" | "tank" | "warden";

export interface EnemyDef {
  type: EnemyType;
  hp: number;
  speed: number; // m/s
  radius: number; // Kollisions-/Hitbox-Radius
  height: number;
  score: number; // Punkte pro Kill (x Multiplikator)
  color: number; // Grundfarbe (three-Hex)
  // Nahkampf (Rusher/Tank)
  meleeDamage: number;
  meleeRange: number; // Meter
  meleeCooldown: number; // Sekunden
  // Fernkampf (Shooter)
  burstCount: number;
  burstInterval: number; // Abstand innerhalb des Bursts
  burstCooldown: number; // Pause zwischen Bursts
  projectileDamage: number;
  projectileSpeed: number; // langsam genug zum Ausweichen!
  preferredRange: number; // hält diese Distanz
  strafeSpeed: number;
  // Kann auf 1,1-m-Deckung springen (Anti-Camping)
  canJump: boolean;
  jumpVelocity: number;
  // Boss: Projektil-Ring (0 = kein Ring)
  radialCount: number;
  radialCooldown: number;
}

export const ENEMIES: Record<EnemyType, EnemyDef> = {
  rusher: {
    type: "rusher",
    hp: 30,
    speed: 7.2,
    radius: 0.42,
    height: 1.7,
    score: 100,
    color: 0xe8543f,
    meleeDamage: 12,
    meleeRange: 1.5,
    meleeCooldown: 0.9,
    burstCount: 0,
    burstInterval: 0,
    burstCooldown: 0,
    projectileDamage: 0,
    projectileSpeed: 0,
    preferredRange: 0,
    strafeSpeed: 0,
    canJump: true,
    jumpVelocity: 8.4,
    radialCount: 0,
    radialCooldown: 0,
  },
  shooter: {
    type: "shooter",
    hp: 60,
    speed: 4.2,
    radius: 0.5,
    height: 1.9,
    score: 150,
    color: 0x8d5fe0,
    meleeDamage: 0,
    meleeRange: 0,
    meleeCooldown: 0,
    burstCount: 3,
    burstInterval: 0.16,
    burstCooldown: 1.9,
    projectileDamage: 8,
    projectileSpeed: 16, // sichtbar & ausweichbar (Gate Phase 2)
    preferredRange: 14,
    strafeSpeed: 3.2,
    canJump: false,
    jumpVelocity: 0,
    radialCount: 0,
    radialCooldown: 0,
  },
  tank: {
    type: "tank",
    hp: 340,
    speed: 2.3,
    radius: 0.85,
    height: 2.3,
    score: 300,
    color: 0x4f7a4a,
    meleeDamage: 26,
    meleeRange: 2.3,
    meleeCooldown: 1.5,
    burstCount: 0,
    burstInterval: 0,
    burstCooldown: 0,
    projectileDamage: 0,
    projectileSpeed: 0,
    preferredRange: 0,
    strafeSpeed: 0,
    canJump: false,
    jumpVelocity: 0,
    radialCount: 0,
    radialCooldown: 0,
  },
  // Boss (alle 5 Wellen): langsamer Koloss, feuert einen flachen
  // Projektil-Ring auf Brusthöhe — überspringbar (Doppelsprung-Synergie!)
  warden: {
    type: "warden",
    hp: 850,
    speed: 2.9,
    radius: 1.05,
    height: 3.0,
    score: 2000,
    color: 0xc9a227, // Gold — unverwechselbar
    meleeDamage: 32,
    meleeRange: 2.6,
    meleeCooldown: 1.8,
    burstCount: 0,
    burstInterval: 0,
    burstCooldown: 0,
    projectileDamage: 10,
    projectileSpeed: 13,
    preferredRange: 0,
    strafeSpeed: 0,
    canJump: false,
    jumpVelocity: 0,
    radialCount: 12,
    radialCooldown: 4.0, // nach Bot-Läufen entschärft: 1. Boss soll fordern, nicht mauern
  },
};

// ---- Elite-Modifikatoren (RC Phase 2): Tint + Stats + max. 1 Verhalten ----
export type EliteType = "swift" | "armored" | "volatile" | "vampiric";

export interface EliteDef {
  type: EliteType;
  name: string; // EN, fürs HUD/Debug
  tint: number; // Material-Färbung (beim Pool-Release zurücksetzen!)
  hpMult: number;
  speedMult: number;
  scoreMult: number;
  scale: number; // visuelle Größe
}

export const ELITES: Record<EliteType, EliteDef> = {
  swift: { type: "swift", name: "Swift", tint: 0x35e0ff, hpMult: 0.8, speedMult: 1.6, scoreMult: 1.25, scale: 1 },
  armored: { type: "armored", name: "Armored", tint: 0x9aa4ad, hpMult: 2.5, speedMult: 0.75, scoreMult: 1.5, scale: 1.15 },
  volatile: { type: "volatile", name: "Volatile", tint: 0xff7a2f, hpMult: 1, speedMult: 1, scoreMult: 1.4, scale: 1 },
  vampiric: { type: "vampiric", name: "Vampiric", tint: 0xe03a3a, hpMult: 1.2, speedMult: 1, scoreMult: 1.4, scale: 1 },
};

export const ELITE_RULES = {
  startWave: 6,
  chanceBase: 0.05,
  chancePerWave: 0.01, // ab startWave, bis Cap
  chanceCap: 0.25,
  volatileRadius: 3,
  volatileDamage: 30,
  vampiricRadius: 5,
  vampiricHealPerSecond: 2,
} as const;

export const ENEMY_AI = {
  alertDelay: 0.35, // Reaktionszeit nach Sichtkontakt (Fairness)
  hitreactDuration: 0.14, // Flinch-Dauer, unterbricht Angriff kurz
  deathDuration: 0.5, // Umkippen/Fade bis Despawn
  separationRadius: 1.4, // Bots drücken sich gegenseitig auseinander
  separationForce: 6,
  avoidLookahead: 2.2, // Hindernis-Umfließen: Prüfdistanz
  repathJitter: 0.6, // leichte Zufallsablenkung gegen Verklumpen
  maxAlive: 14, // Obergrenze gleichzeitig (Lesbarkeit + Mobile-Perf)
  touchDamageCooldown: 0.6, // Rusher-Berührschaden-Takt
} as const;
