// Persistenz (RC Phase 3): Schema v2 mit Perks. Primär-Save ist das
// CrazyGames-Data-Modul (Cloud, überlebt iFrame-/Cookie-Clear), localStorage
// als Fallback und Spiegel. Migration v1 -> v2 verlustfrei.

import { PERK_MAX_LEVEL, SAVE_KEY, SAVE_SCHEMA_VERSION, type PerkId } from "../config/meta";
import { STARTING_WEAPON, type WeaponId } from "../config/weapons";

export type PerkLevels = Record<PerkId, number>;

export interface SaveState {
  schemaVersion: number;
  coins: number;
  highscore: number;
  bestWave: number;
  runsPlayed: number;
  unlockedWeapons: WeaponId[];
  selectedWeapon: WeaponId;
  unlockedSchemes: string[];
  selectedScheme: string;
  selectedArena: string;
  /** Mobile-Feuermodus: true = Auto-Fire, false = Feuer-Button (Phase 5). */
  autoFire: boolean;
  musicOn: boolean;
  perks: PerkLevels;
}

function defaultPerks(): PerkLevels {
  return { vitality: 0, kickstart: 0, treasure: 0, ammodepot: 0, sprinter: 0 };
}

function defaults(): SaveState {
  return {
    schemaVersion: SAVE_SCHEMA_VERSION,
    coins: 0,
    highscore: 0,
    bestWave: 0,
    runsPlayed: 0,
    unlockedWeapons: [STARTING_WEAPON],
    selectedWeapon: STARTING_WEAPON,
    unlockedSchemes: ["default"],
    selectedScheme: "default",
    selectedArena: "foundry",
    autoFire: true,
    musicOn: true,
    perks: defaultPerks(),
  };
}

/** v1 (und fehlende Felder generell) -> v2: Defaults mischen, Perks ergänzen. */
function migrate(parsed: Partial<SaveState>): SaveState {
  const merged: SaveState = { ...defaults(), ...parsed };
  merged.perks = { ...defaultPerks(), ...(parsed.perks ?? {}) };
  // Perk-Stufen absichern (defekte Saves können nichts kaputt machen)
  for (const key of Object.keys(merged.perks) as PerkId[]) {
    merged.perks[key] = Math.max(0, Math.min(PERK_MAX_LEVEL, Math.floor(merged.perks[key] ?? 0)));
  }
  merged.schemaVersion = SAVE_SCHEMA_VERSION;
  return merged;
}

/** Externe Save-Quelle (CrazyGames-Data-Modul) — synchron, localStorage-artig. */
export interface CloudStore {
  getItem(key: string): string | null;
  setItem(key: string, value: string): void;
}

export class SaveData {
  state: SaveState = defaults();
  /** Wird von main gesetzt, wenn das SDK verfügbar ist. */
  cloud: CloudStore | null = null;

  load(): void {
    // Priorität: Cloud (SDK) > localStorage > Defaults
    const raw = this.readRaw();
    if (!raw) return;
    try {
      this.state = migrate(JSON.parse(raw) as Partial<SaveState>);
    } catch {
      this.state = defaults();
    }
  }

  private readRaw(): string | null {
    if (this.cloud) {
      try {
        const cloudRaw = this.cloud.getItem(SAVE_KEY);
        if (cloudRaw) return cloudRaw;
      } catch {
        // SDK-Störung: auf localStorage zurückfallen
      }
    }
    try {
      return localStorage.getItem(SAVE_KEY);
    } catch {
      return null;
    }
  }

  save(): void {
    let raw: string;
    try {
      raw = JSON.stringify(this.state);
    } catch {
      return;
    }
    // In BEIDE Ziele schreiben (Cloud primär, localStorage als Spiegel)
    if (this.cloud) {
      try {
        this.cloud.setItem(SAVE_KEY, raw);
      } catch {
        // Cloud-Störung: localStorage reicht als Fallback
      }
    }
    try {
      localStorage.setItem(SAVE_KEY, raw);
    } catch {
      // Storage voll/blockiert (Inkognito): Spiel läuft ohne Persistenz weiter
    }
  }
}
