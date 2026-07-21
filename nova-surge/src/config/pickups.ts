// Pickup-System (Recovery-Prompt Phase 3b): feste, map-authorbare Punkte.
// coin  = Coin-Stash: +Coins direkt auf den Run-Zähler
// medkit = +40 HP
// supply = Supply Crate: öffnet sofort einen Upgrade-Draft (bestehendes
//          Overlay — nach dem Phase-0-Fix klickbar)
// once:true = 1x pro Run, respawnt nie (neuer Run = wieder da).

export type PickupType = "coin" | "medkit" | "supply";

export interface PickupDef {
  x: number;
  y: number; // Boden-Höhe der Ebene (Anzeige schwebt etwas darüber)
  z: number;
  type: PickupType;
  once?: boolean;
}

export const PICKUP_TYPE_ORDER: PickupType[] = ["coin", "medkit", "supply"];

export const PICKUP_RULES = {
  radius: 1.5, // Aufnahme-Distanz horizontal
  verticalTolerance: 1.6, // |Δy| zur Ebene des Pickups
  respawnSeconds: 30, // nur für Pickups ohne once
  coinStash: 25, // Coins direkt auf den Run-Zähler
  medkitHeal: 40,
} as const;

export const PICKUP_COLORS: Record<PickupType, number> = {
  coin: 0xffc93a,
  medkit: 0x4dff88,
  supply: 0xb07dff,
};
