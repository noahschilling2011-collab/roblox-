// Persistenz in localStorage (Phase 4): Münzen, Unlocks, Highscore,
// Einstellungen. Ein Schema mit Version für spätere Migrationen.

import { SAVE_KEY, SAVE_SCHEMA_VERSION } from "../config/meta";
import { STARTING_WEAPON, type WeaponId } from "../config/weapons";

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
  };
}

export class SaveData {
  state: SaveState = defaults();

  load(): void {
    try {
      const raw = localStorage.getItem(SAVE_KEY);
      if (!raw) return;
      const parsed = JSON.parse(raw) as Partial<SaveState>;
      // Defaults + gespeicherte Werte mischen (robust gegen fehlende Felder)
      this.state = { ...defaults(), ...parsed };
    } catch {
      // Defekter/blockierter Storage: mit Defaults weiterspielen
      this.state = defaults();
    }
  }

  save(): void {
    try {
      localStorage.setItem(SAVE_KEY, JSON.stringify(this.state));
    } catch {
      // Storage voll/blockiert (Inkognito): Spiel läuft ohne Persistenz weiter
    }
  }
}
