// Waffen-Simulation: Feuerlogik, Spread, Rückstoß, Magazin/Nachladen.
// Hitscan-Treffer werden hier aufgelöst; die Shotgun übergibt Pellets an den
// Projektil-Pool. Alle Zahlen kommen aus config/weapons.ts + Upgrade-Mods.

import { WEAPONS, type WeaponDef, type WeaponId } from "../config/weapons";
import { damp, type Vec3, vec3 } from "./math";
import type { InputState } from "./input";
import { EventQueue, Ev } from "./events";

export interface WeaponMods {
  damageMult: number;
  fireRateMult: number;
  magSizeMult: number;
}

/** Callback der Sim: löst einen Hitscan-Strahl auf (Treffer + Events). */
export type HitscanFn = (origin: Vec3, dir: Vec3, damage: number, range: number) => void;
/** Callback der Sim: spawnt ein Spieler-Projektil (Shotgun-Pellet). */
export type SpawnPelletFn = (origin: Vec3, dir: Vec3, speed: number, life: number, damage: number) => void;

const _dir = vec3();

export class Weapon {
  def: WeaponDef = WEAPONS.pulse;
  ammo = this.def.magSize;
  reloadTimer = 0;
  fireCooldown = 0;
  spread = this.def.spreadBase;
  // Rückstoß-Offset der Kamera (erholt sich exponentiell)
  recoilPitch = 0;
  recoilYaw = 0;
  private prevFire = false;
  mods: WeaponMods = { damageMult: 1, fireRateMult: 1, magSizeMult: 1 };

  equip(id: WeaponId): void {
    this.def = WEAPONS[id];
    this.ammo = this.magSize();
    this.reloadTimer = 0;
    this.fireCooldown = 0;
    this.spread = this.def.spreadBase;
    this.recoilPitch = 0;
    this.recoilYaw = 0;
    this.prevFire = false;
  }

  magSize(): number {
    return Math.round(this.def.magSize * this.mods.magSizeMult);
  }

  isReloading(): boolean {
    return this.reloadTimer > 0;
  }

  update(
    dt: number,
    input: InputState,
    eye: Vec3,
    events: EventQueue,
    hitscan: HitscanFn,
    spawnPellet: SpawnPelletFn
  ): void {
    const recoverLambda = 14;
    this.recoilPitch = damp(this.recoilPitch, 0, recoverLambda, dt);
    this.recoilYaw = damp(this.recoilYaw, 0, recoverLambda, dt);
    this.spread = Math.max(this.def.spreadBase, this.spread - this.def.spreadRecover * dt);
    this.fireCooldown = Math.max(0, this.fireCooldown - dt);

    if (this.reloadTimer > 0) {
      this.reloadTimer -= dt;
      if (this.reloadTimer <= 0) {
        this.reloadTimer = 0;
        this.ammo = this.magSize();
      }
    }

    if (input.reloadQueued) {
      input.reloadQueued = false;
      if (this.reloadTimer === 0 && this.ammo < this.magSize()) {
        this.reloadTimer = this.def.reloadTime;
        events.emit(Ev.ReloadStart, 0, 0, 0, this.def.reloadTime);
      }
    }

    const firePressed = input.fire && (this.def.auto || !this.prevFire);
    this.prevFire = input.fire;
    if (!firePressed || this.fireCooldown > 0 || this.reloadTimer > 0) return;

    if (this.ammo <= 0) {
      events.emit(Ev.DryFire);
      // Auto-Reload bei leerem Magazin (Komfort, besonders Mobile)
      this.reloadTimer = this.def.reloadTime;
      events.emit(Ev.ReloadStart, 0, 0, 0, this.def.reloadTime);
      return;
    }

    // --- Schuss ---
    this.ammo--;
    this.fireCooldown = this.def.fireInterval / this.mods.fireRateMult;
    const damage = this.def.damage * this.mods.damageMult;
    const aimPitch = input.pitch + this.recoilPitch;
    const aimYaw = input.yaw + this.recoilYaw;

    for (let p = 0; p < this.def.pellets; p++) {
      // Streuung: gleichverteilt im Kegel
      const angle = Math.random() * Math.PI * 2;
      const radius = Math.sqrt(Math.random()) * this.spread;
      const offPitch = aimPitch + Math.sin(angle) * radius;
      const offYaw = aimYaw + Math.cos(angle) * radius;
      const cp = Math.cos(offPitch);
      _dir.x = -Math.sin(offYaw) * cp;
      _dir.y = Math.sin(offPitch);
      _dir.z = -Math.cos(offYaw) * cp;
      if (this.def.hitscan) {
        hitscan(eye, _dir, damage, this.def.range);
      } else {
        spawnPellet(eye, _dir, this.def.projectileSpeed, this.def.projectileLife, damage);
      }
    }

    this.spread = Math.min(this.def.spreadMax, this.spread + this.def.spreadGrowth);
    this.recoilPitch += this.def.recoilPitch;
    this.recoilYaw += (Math.random() - 0.5) * 2 * this.def.recoilYaw;
    events.emit(Ev.Shot);
  }
}
