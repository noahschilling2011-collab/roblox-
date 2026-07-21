// Upgrade-Zustand (RC Phase 1): Zähler pro Upgrade, Rarity-Draft mit
// Wellen-Skalierung, komplette Stats-Neuberechnung bei jeder Wahl.

import { DRAFT, UPGRADES, UPGRADE_CHOICES, VALUES, type Rarity, type UpgradeId } from "../config/upgrades";
import { PERK_VALUES } from "../config/meta";
import type { PerkLevels } from "../meta/SaveData";
import type { Player } from "./Player";
import type { RunStats } from "./Stats";
import type { Weapon } from "./Weapon";

const ALL_IDS = Object.keys(UPGRADES) as UpgradeId[];

export class UpgradeState {
  readonly counts = new Map<UpgradeId, number>();
  /** Phoenix ist 1x pro Run — nach Verbrauch darf recompute() ihn nicht zurückgeben. */
  phoenixConsumed = false;
  /** Account-Perk-Stufen (RC Phase 3), von der Sim beim Run-Start gesetzt. */
  perks: PerkLevels | null = null;

  reset(): void {
    this.counts.clear();
    this.phoenixConsumed = false;
  }

  count(id: UpgradeId): number {
    return this.counts.get(id) ?? 0;
  }

  /** Zieht 3 Karten: Rarity pro Slot würfeln (Epic steigt pro Welle), dann
   *  zufälliges Upgrade dieser Stufe. Fallback auf niedrigere Stufe, keine
   *  Duplikate im selben Angebot, unique nur wenn noch nicht genommen. */
  rollOffer(waveNumber: number): UpgradeId[] {
    const epicChance = Math.min(DRAFT.epicCap, DRAFT.epicBase + DRAFT.epicPerWave * waveNumber);
    const offer: UpgradeId[] = [];
    for (let slot = 0; slot < UPGRADE_CHOICES; slot++) {
      const roll = Math.random();
      const wanted: Rarity = roll < epicChance ? "epic" : roll < epicChance + DRAFT.rareChance ? "rare" : "common";
      const order: Rarity[] =
        wanted === "epic" ? ["epic", "rare", "common"] : wanted === "rare" ? ["rare", "common", "epic"] : ["common", "rare", "epic"];
      for (const rarity of order) {
        const pool = ALL_IDS.filter((id) => {
          const def = UPGRADES[id];
          if (def.rarity !== rarity) return false;
          if (def.unique && this.count(id) > 0) return false;
          return !offer.includes(id);
        });
        if (pool.length > 0) {
          offer.push(pool[Math.floor(Math.random() * pool.length)]!);
          break;
        }
      }
    }
    return offer;
  }

  /** Wendet ein Upgrade an: Zähler hoch, Stats komplett neu berechnen. */
  apply(id: UpgradeId, weapon: Weapon, player: Player, stats: RunStats): void {
    this.counts.set(id, this.count(id) + 1);
    const magBefore = weapon.magSize();
    this.recompute(stats, player);
    // Magazin-Upgrade: Differenz sofort auffüllen (fühlt sich belohnend an)
    const magAfter = weapon.magSize();
    if (magAfter > magBefore) weapon.ammo += magAfter - magBefore;
  }

  /** Stats von Grund auf aus den Zählern berechnen (idempotent). */
  recompute(stats: RunStats, player: Player): void {
    stats.reset();

    const c = (id: UpgradeId): number => this.count(id);
    const extra = (n: number): number => Math.max(0, n - 1);

    stats.damageMult = 1 + VALUES.damageMult * c("damage");
    stats.fireRateMult = 1 + VALUES.firerateMult * c("firerate");
    stats.magSizeMult = 1 + VALUES.magsizeMult * c("magsize");
    stats.moveSpeedMult = 1 + VALUES.speedMult * c("speed");
    stats.lifesteal = VALUES.lifestealPerStack * c("lifesteal");
    stats.critChance = VALUES.critChancePerStack * c("crit");
    stats.reloadMult = Math.pow(VALUES.reloadFactorPerStack, c("fastreload"));
    stats.damageTakenMult = Math.pow(VALUES.armorFactorPerStack, c("armor"));
    if (c("adrenaline") > 0) {
      stats.adrenalineDuration =
        VALUES.adrenalineBaseDuration + VALUES.adrenalineDurationPerExtraStack * extra(c("adrenaline"));
    }
    stats.scavengerChance = VALUES.scavengerChancePerStack * c("scavenger");
    stats.scoreMult = 1 + VALUES.bountyPerStack * c("bounty");

    stats.pierceTargets = Math.min(VALUES.pierceCap, c("pierce"));
    stats.ricochetBounces = Math.min(VALUES.ricochetCapBounces, c("ricochet"));
    if (c("shatter") > 0) stats.shatterCount = VALUES.shatterBase + VALUES.shatterPerExtraStack * extra(c("shatter"));
    if (c("thorns") > 0) stats.thornsPct = VALUES.thornsBase + VALUES.thornsPerExtraStack * extra(c("thorns"));
    if (c("overkill") > 0)
      stats.overkillHealPct = VALUES.overkillBase + VALUES.overkillPerExtraStack * extra(c("overkill"));
    if (c("coldblood") > 0)
      stats.coldbloodBonus = VALUES.coldbloodBase + VALUES.coldbloodPerExtraStack * extra(c("coldblood"));
    if (c("laststand") > 0)
      stats.laststandBonus = VALUES.laststandBase + VALUES.laststandPerExtraStack * extra(c("laststand"));
    stats.comboHoldBonus = VALUES.flowstatePerStack * c("flowstate");

    stats.chainEnabled = c("chain") > 0;
    stats.extraProjectiles = c("twinlink") > 0 ? 1 : 0;
    stats.bullettimeEnabled = c("bullettime") > 0;
    stats.phoenixCharges = this.count("phoenix") > 0 && !this.phoenixConsumed ? 1 : 0;
    stats.hasDoubleJump = c("doublejump") > 0;

    // Account-Perks: multiplikativ auf die In-Run-Werte (bewusst schwächer)
    if (this.perks) {
      stats.magSizeMult *= 1 + PERK_VALUES.ammodepotPerLevel * this.perks.ammodepot;
      stats.moveSpeedMult *= 1 + PERK_VALUES.sprinterPerLevel * this.perks.sprinter;
    }

    // Spieler-Felder synchronisieren (Player liest nicht direkt aus Stats)
    player.speedMult = stats.moveSpeedMult;
    player.lifesteal = stats.lifesteal;
    player.hasDoubleJump = stats.hasDoubleJump;
  }
}
