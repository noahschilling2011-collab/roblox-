// Pickup-Zustand in der Sim: pro Arena-Punkt ein Slot. once-Pickups bleiben
// nach der Aufnahme für den REST DES RUNS weg (reset() beim Run-Start bringt
// sie zurück); alle anderen respawnen nach Timer. Effekte laufen über
// Callbacks der Sim — dieses Modul kennt weder Rendering noch three.

import { PICKUP_RULES, PICKUP_TYPE_ORDER, type PickupDef } from "../config/pickups";
import { EventQueue, Ev } from "./events";
import type { Vec3 } from "./math";

export interface PickupCallbacks {
  heal(amount: number): void;
  addCoins(amount: number): void;
  openSupplyDraft(): void;
}

export class PickupManager {
  defs: readonly PickupDef[] = [];
  readonly active: boolean[] = [];
  readonly timers: number[] = [];

  setArena(defs: readonly PickupDef[] | undefined): void {
    this.defs = defs ?? [];
    this.active.length = this.defs.length;
    this.timers.length = this.defs.length;
    this.reset();
  }

  reset(): void {
    for (let i = 0; i < this.defs.length; i++) {
      this.active[i] = true;
      this.timers[i] = 0;
    }
  }

  update(dt: number, playerPos: Vec3, playerAlive: boolean, events: EventQueue, cb: PickupCallbacks): void {
    for (let i = 0; i < this.defs.length; i++) {
      const d = this.defs[i]!;
      if (!this.active[i]) {
        if (d.once) continue; // bleibt bis zum nächsten Run weg
        this.timers[i] = this.timers[i]! - dt;
        if (this.timers[i]! <= 0) this.active[i] = true;
        continue;
      }
      if (!playerAlive) continue;
      const dx = playerPos.x - d.x;
      const dz = playerPos.z - d.z;
      if (dx * dx + dz * dz > PICKUP_RULES.radius * PICKUP_RULES.radius) continue;
      if (Math.abs(playerPos.y - d.y) > PICKUP_RULES.verticalTolerance) continue;
      this.active[i] = false;
      this.timers[i] = PICKUP_RULES.respawnSeconds;
      if (d.type === "medkit") cb.heal(PICKUP_RULES.medkitHeal);
      else if (d.type === "coin") cb.addCoins(PICKUP_RULES.coinStash);
      else cb.openSupplyDraft();
      events.emit(Ev.Pickup, d.x, d.y + 1, d.z, PICKUP_TYPE_ORDER.indexOf(d.type));
    }
  }
}
