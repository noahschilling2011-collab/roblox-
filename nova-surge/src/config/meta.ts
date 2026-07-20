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
];

export const SAVE_KEY = "nova-surge-save-v1";
export const SAVE_SCHEMA_VERSION = 1;
