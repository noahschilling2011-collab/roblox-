// In-Run-Upgrades (RC Phase 1): 24 Stück in drei Rarity-Stufen.
// Draft: ~65/28/7, Epic-Chance steigt leicht pro Welle (siehe DRAFT).
// Texte EN (In-Game-Sprache), kurz und eindeutig. Alle Effekt-Zahlen in VALUES.

export type Rarity = "common" | "rare" | "epic";

export type UpgradeId =
  // Commons (Stat-Stacks)
  | "damage"
  | "firerate"
  | "magsize"
  | "speed"
  | "lifesteal"
  | "crit"
  | "fastreload"
  | "armor"
  | "adrenaline"
  | "scavenger"
  | "bounty"
  // Rares (Spielweise)
  | "doublejump"
  | "pierce"
  | "ricochet"
  | "shatter"
  | "thorns"
  | "overkill"
  | "coldblood"
  | "laststand"
  | "flowstate"
  // Epics (unique, spürbar broken)
  | "chain"
  | "twinlink"
  | "bullettime"
  | "phoenix";

export interface UpgradeDef {
  id: UpgradeId;
  name: string;
  desc: string;
  icon: string;
  rarity: Rarity;
  unique: boolean; // nur 1x pro Run wählbar
}

export const UPGRADES: Record<UpgradeId, UpgradeDef> = {
  // ---- Common ----
  damage: { id: "damage", name: "Heavy Rounds", desc: "+15% damage", icon: "💥", rarity: "common", unique: false },
  firerate: { id: "firerate", name: "Rapid Trigger", desc: "+12% fire rate", icon: "🔥", rarity: "common", unique: false },
  magsize: { id: "magsize", name: "Extended Mag", desc: "+30% mag size", icon: "📦", rarity: "common", unique: false },
  speed: { id: "speed", name: "Light Boots", desc: "+8% move speed", icon: "👟", rarity: "common", unique: false },
  lifesteal: { id: "lifesteal", name: "Leech Rounds", desc: "Heal 3% of damage dealt", icon: "🩸", rarity: "common", unique: false },
  crit: { id: "crit", name: "Critical Hits", desc: "+10% chance for ×2 damage", icon: "🎯", rarity: "common", unique: false },
  fastreload: { id: "fastreload", name: "Quick Hands", desc: "-20% reload time", icon: "🫳", rarity: "common", unique: false },
  armor: { id: "armor", name: "Plating", desc: "-8% damage taken", icon: "🛡️", rarity: "common", unique: false },
  adrenaline: { id: "adrenaline", name: "Adrenaline", desc: "+25% speed for 2s after kills", icon: "⚡", rarity: "common", unique: false },
  scavenger: { id: "scavenger", name: "Scavenger", desc: "Kills: 15% chance for +4 ammo", icon: "🔩", rarity: "common", unique: false },
  bounty: { id: "bounty", name: "Bounty", desc: "+10% score gain", icon: "💰", rarity: "common", unique: false },
  // ---- Rare ----
  doublejump: { id: "doublejump", name: "Jump Jets", desc: "Double jump", icon: "🚀", rarity: "rare", unique: true },
  pierce: { id: "pierce", name: "Punch Through", desc: "Shots hit +1 enemy behind", icon: "🗡️", rarity: "rare", unique: false },
  ricochet: { id: "ricochet", name: "Ricochet", desc: "Projectiles bounce once", icon: "🪃", rarity: "rare", unique: false },
  shatter: { id: "shatter", name: "Shatter", desc: "Kills release 3 shard shots", icon: "💠", rarity: "rare", unique: false },
  thorns: { id: "thorns", name: "Thorns", desc: "Melee attackers take 50% back", icon: "🌵", rarity: "rare", unique: false },
  overkill: { id: "overkill", name: "Vampiric Overkill", desc: "Excess kill damage heals 25%", icon: "🧛", rarity: "rare", unique: false },
  coldblood: { id: "coldblood", name: "Cold Blood", desc: "+25% damage at full health", icon: "🧊", rarity: "rare", unique: false },
  laststand: { id: "laststand", name: "Last Stand", desc: "Below 30% HP: +20% fire & reload speed", icon: "🚨", rarity: "rare", unique: false },
  flowstate: { id: "flowstate", name: "Flow State", desc: "Combo lasts 2s longer", icon: "🌊", rarity: "rare", unique: false },
  // ---- Epic (unique) ----
  chain: { id: "chain", name: "Chain Lightning", desc: "Every 5th hit arcs to 3 enemies", icon: "🌩️", rarity: "epic", unique: true },
  twinlink: { id: "twinlink", name: "Twin Link", desc: "+1 projectile per shot, +30% spread", icon: "🔱", rarity: "epic", unique: true },
  bullettime: { id: "bullettime", name: "Bullet Time", desc: "Enemies 40% slower while you reload", icon: "⏳", rarity: "epic", unique: true },
  phoenix: { id: "phoenix", name: "Phoenix", desc: "Revive once with 40% HP", icon: "🐦‍🔥", rarity: "epic", unique: true },
};

/** Effekt-Zahlen — zentral, keine Magic Numbers in der Logik. */
export const VALUES = {
  damageMult: 0.15,
  firerateMult: 0.12,
  magsizeMult: 0.3,
  speedMult: 0.08,
  lifestealPerStack: 0.03,
  critChancePerStack: 0.1,
  reloadFactorPerStack: 0.8, // multiplikativ: 0,8^n
  armorFactorPerStack: 0.92, // multiplikativ: 0,92^n
  adrenalineSpeedBonus: 0.25,
  adrenalineBaseDuration: 2.0,
  adrenalineDurationPerExtraStack: 0.5,
  scavengerChancePerStack: 0.15,
  scavengerAmmo: 4,
  bountyPerStack: 0.1,
  pierceCap: 3, // max. zusätzliche Ziele
  ricochetCapBounces: 2,
  shatterBase: 3,
  shatterPerExtraStack: 1,
  shatterDamage: 6,
  shatterSpeed: 20,
  shatterLife: 0.4,
  thornsBase: 0.5,
  thornsPerExtraStack: 0.25,
  overkillBase: 0.25,
  overkillPerExtraStack: 0.1,
  coldbloodBase: 0.25,
  coldbloodPerExtraStack: 0.1,
  laststandBase: 0.2,
  laststandPerExtraStack: 0.08,
  laststandHpThreshold: 0.3,
  flowstatePerStack: 2.0, // Sekunden längere Combo-Haltezeit
  chainEveryNthHit: 5,
  chainTargets: 3,
  chainDamageFactor: 0.4,
  chainRange: 12,
  twinlinkSpreadPenalty: 0.3,
  bullettimeScale: 0.6, // Gegner laufen mit 60% Zeit
  phoenixReviveHp: 40,
  phoenixInvulnSeconds: 1.5,
} as const;

/** Draft-Wahrscheinlichkeiten (Epic steigt pro Welle, gedeckelt). */
export const DRAFT = {
  epicBase: 0.07,
  epicPerWave: 0.004,
  epicCap: 0.18,
  rareChance: 0.28,
} as const;

export const UPGRADE_CHOICES = 3; // 1 aus 3
