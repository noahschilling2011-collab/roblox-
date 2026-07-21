// Meta-Progression (Phase 4, persistent in localStorage).
// Preise so gesetzt, dass der erste Unlock (Scatter Gun) nach ~3
// durchschnittlichen Runs erreichbar ist — Kalibrierung siehe STATUS.md.

import type { WeaponId } from "./weapons";

/** Münzen = Score / COIN_DIVISOR (abgerundet), gutgeschrieben am Run-Ende. */
export const COIN_DIVISOR = 60;

export const WEAPON_PRICES: Record<WeaponId, number> = {
  pulse: 0, // Startwaffe
  scatter: 140,
  longshot: 320,
};

export interface ColorScheme {
  id: string;
  name: string;
  price: number;
  body: number; // Waffenkörper
  accent: number; // Akzentteile (Magazin, Visier)
  hands: number;
}

export const COLOR_SCHEMES: ColorScheme[] = [
  { id: "default", name: "Standard Issue", price: 0, body: 0x3a4250, accent: 0x7dd3ff, hands: 0xd9b38c },
  { id: "ember", name: "Ember", price: 80, body: 0x40342e, accent: 0xff8b3d, hands: 0x8c6f5a },
  { id: "toxin", name: "Toxin", price: 80, body: 0x2e4034, accent: 0x7dff8b, hands: 0x5a8c6f },
  { id: "royal", name: "Royal", price: 120, body: 0x342e40, accent: 0xd37dff, hands: 0xc9a9e8 },
  { id: "midnight", name: "Midnight", price: 120, body: 0x1c2233, accent: 0x3f6dff, hands: 0x39415c },
  { id: "bubblegum", name: "Bubblegum", price: 150, body: 0xf2e6ee, accent: 0xff6fb0, hands: 0xffd9ea },
  { id: "neon", name: "Neon Circuit", price: 180, body: 0x101410, accent: 0x39ff5c, hands: 0x1f2b1f },
  { id: "goldrush", name: "Gold Rush", price: 250, body: 0x201d16, accent: 0xffc93a, hands: 0x3c342a },
];

// ---- Account-Perks (RC Phase 3): permanenter Coin-Sink, bewusst schwächer
// als In-Run-Upgrades. Vollausbau ≈ 19.250 Coins ≈ 15–20 gute Late-Runs.
export type PerkId = "vitality" | "kickstart" | "treasure" | "ammodepot" | "sprinter";

export interface PerkDef {
  id: PerkId;
  name: string;
  desc: string; // EN, {n} = Stufenzahl
  icon: string;
}

export const PERKS: Record<PerkId, PerkDef> = {
  vitality: { id: "vitality", name: "Vitality", desc: "+10 max HP per level", icon: "❤️" },
  kickstart: { id: "kickstart", name: "Kickstart", desc: "Start runs with free upgrades", icon: "🎁" },
  treasure: { id: "treasure", name: "Treasure Hunter", desc: "+6% coins per level", icon: "🪙" },
  ammodepot: { id: "ammodepot", name: "Ammo Depot", desc: "+8% mag size per level", icon: "📦" },
  sprinter: { id: "sprinter", name: "Sprinter", desc: "+3% move speed per level", icon: "💨" },
};

export const PERK_MAX_LEVEL = 5;
export const PERK_PRICES = [100, 250, 500, 1000, 2000]; // Stufe 1..5

export const PERK_VALUES = {
  vitalityHpPerLevel: 10,
  treasurePerLevel: 0.06,
  ammodepotPerLevel: 0.08,
  sprinterPerLevel: 0.03,
} as const;

export const SAVE_KEY = "nova-surge-save-v1";
export const SAVE_SCHEMA_VERSION = 2;
