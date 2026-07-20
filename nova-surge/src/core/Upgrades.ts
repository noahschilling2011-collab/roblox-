// In-Run-Upgrade-Zustand (Phase 4): Zähler pro Upgrade, Anwendung auf
// Waffe/Spieler, Ziehung von 1-aus-3-Angeboten.

import { UPGRADES, UPGRADE_CHOICES, UPGRADE_VALUES, type UpgradeId } from "../config/upgrades";
import type { Player } from "./Player";
import type { Weapon } from "./Weapon";

export class UpgradeState {
  readonly counts = new Map<UpgradeId, number>();

  reset(): void {
    this.counts.clear();
  }

  count(id: UpgradeId): number {
    return this.counts.get(id) ?? 0;
  }

  /** Zieht bis zu 3 verschiedene Upgrades (unique-Upgrades nur, wenn noch nicht genommen). */
  rollOffer(): UpgradeId[] {
    const pool: UpgradeId[] = [];
    for (const def of Object.values(UPGRADES)) {
      if (def.unique && this.count(def.id) > 0) continue;
      pool.push(def.id);
    }
    // Fisher-Yates auf Kopie, dann die ersten N
    for (let i = pool.length - 1; i > 0; i--) {
      const j = Math.floor(Math.random() * (i + 1));
      const tmp = pool[i]!;
      pool[i] = pool[j]!;
      pool[j] = tmp;
    }
    return pool.slice(0, UPGRADE_CHOICES);
  }

  apply(id: UpgradeId, weapon: Weapon, player: Player): void {
    this.counts.set(id, this.count(id) + 1);
    const magBefore = weapon.magSize();
    weapon.mods.damageMult = 1 + UPGRADE_VALUES.damageMult * this.count("damage");
    weapon.mods.fireRateMult = 1 + UPGRADE_VALUES.firerateMult * this.count("firerate");
    weapon.mods.magSizeMult = 1 + UPGRADE_VALUES.magsizeMult * this.count("magsize");
    player.speedMult = 1 + UPGRADE_VALUES.speedMult * this.count("speed");
    player.lifesteal = UPGRADE_VALUES.lifestealPerStack * this.count("lifesteal");
    player.hasDoubleJump = this.count("doublejump") > 0;
    // Magazin-Upgrade: Differenz sofort auffüllen (fühlt sich belohnend an)
    const magAfter = weapon.magSize();
    if (magAfter > magBefore) weapon.ammo += magAfter - magBefore;
  }
}
