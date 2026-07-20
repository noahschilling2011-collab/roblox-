// In-Run-Upgrades (Phase 4): nach jeder Welle 1 aus 3, stapelbar.
// Texte EN (In-Game-Sprache), kurz und eindeutig.

export type UpgradeId =
  | "damage"
  | "firerate"
  | "magsize"
  | "speed"
  | "lifesteal"
  | "doublejump";

export interface UpgradeDef {
  id: UpgradeId;
  name: string;
  desc: string;
  icon: string; // Emoji als Icon — kein Asset nötig, überall lesbar
  unique: boolean; // nur 1x wählbar (Doppelsprung)
}

export const UPGRADES: Record<UpgradeId, UpgradeDef> = {
  damage: { id: "damage", name: "Heavy Rounds", desc: "+15% damage", icon: "💥", unique: false },
  firerate: { id: "firerate", name: "Rapid Trigger", desc: "+12% fire rate", icon: "🔥", unique: false },
  magsize: { id: "magsize", name: "Extended Mag", desc: "+30% mag size", icon: "📦", unique: false },
  speed: { id: "speed", name: "Light Boots", desc: "+8% move speed", icon: "👟", unique: false },
  lifesteal: { id: "lifesteal", name: "Leech Rounds", desc: "Heal 3% of damage dealt", icon: "🩸", unique: false },
  doublejump: { id: "doublejump", name: "Jump Jets", desc: "Double jump", icon: "🚀", unique: true },
};

export const UPGRADE_VALUES = {
  damageMult: 0.15,
  firerateMult: 0.12,
  magsizeMult: 0.3,
  speedMult: 0.08,
  lifestealPerStack: 0.03,
} as const;

export const UPGRADE_CHOICES = 3; // 1 aus 3
