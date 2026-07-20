// Alle Waffen-Werte. Namen sind erfunden (keine echten Waffennamen — IP-Regel).
// AR + DMR sind Hitscan, die Shotgun verschießt echte Projektile (Phase 4).

export type WeaponId = "pulse" | "scatter" | "longshot";

export interface WeaponDef {
  id: WeaponId;
  name: string; // Anzeigename (EN, In-Game)
  hitscan: boolean;
  damage: number; // pro Kugel/Pellet
  pellets: number; // 1 außer Shotgun
  fireInterval: number; // Sekunden zwischen Schüssen
  auto: boolean; // Dauerfeuer bei gehaltener Taste
  magSize: number;
  reloadTime: number; // Sekunden
  spreadBase: number; // Radiant, Grundstreuung
  spreadMax: number; // Radiant, bei Dauerfeuer
  spreadGrowth: number; // Zuwachs pro Schuss
  spreadRecover: number; // Abbau pro Sekunde
  recoilPitch: number; // Kamera-Kick nach oben pro Schuss (Radiant)
  recoilYaw: number; // zufälliger Seiten-Kick (± Radiant)
  range: number; // Meter (Hitscan) bzw. via Projektil-Lebenszeit
  projectileSpeed: number; // nur Shotgun
  projectileLife: number; // Sekunden (Reichweite = speed * life)
  // Sound-Charakter (prozedural, siehe audio/Sfx.ts)
  soundPitch: number; // 1 = Standard; tiefer = wuchtiger
  soundBody: number; // 0..1, Anteil Bass/Punch
}

export const WEAPONS: Record<WeaponId, WeaponDef> = {
  pulse: {
    id: "pulse",
    name: "Pulse Rifle",
    hitscan: true,
    damage: 11,
    pellets: 1,
    fireInterval: 0.1, // 600 Schuss/min
    auto: true,
    magSize: 30,
    reloadTime: 1.6,
    spreadBase: 0.008,
    spreadMax: 0.035,
    spreadGrowth: 0.0035,
    spreadRecover: 0.09,
    recoilPitch: 0.011,
    recoilYaw: 0.004,
    range: 120,
    projectileSpeed: 0,
    projectileLife: 0,
    soundPitch: 1.0,
    soundBody: 0.5,
  },
  scatter: {
    id: "scatter",
    name: "Scatter Gun",
    hitscan: false, // echte Projektile mit Spread — brutal auf kurze Distanz
    damage: 9,
    pellets: 8,
    fireInterval: 0.85,
    auto: false,
    magSize: 6,
    reloadTime: 2.2,
    spreadBase: 0.085,
    spreadMax: 0.085,
    spreadGrowth: 0,
    spreadRecover: 1,
    recoilPitch: 0.045,
    recoilYaw: 0.01,
    range: 0,
    projectileSpeed: 42,
    projectileLife: 0.55, // ~23 m effektive Reichweite
    soundPitch: 0.62,
    soundBody: 0.95,
  },
  longshot: {
    id: "longshot",
    name: "Longshot DMR",
    hitscan: true,
    damage: 55,
    pellets: 1,
    fireInterval: 0.75,
    auto: false,
    magSize: 8,
    reloadTime: 1.9,
    spreadBase: 0.0015,
    spreadMax: 0.012,
    spreadGrowth: 0.006,
    spreadRecover: 0.05,
    recoilPitch: 0.042,
    recoilYaw: 0.006,
    range: 200,
    projectileSpeed: 0,
    projectileLife: 0,
    soundPitch: 0.8,
    soundBody: 0.85,
  },
};

export const STARTING_WEAPON: WeaponId = "pulse";
