// First-Person-Waffenmodell aus Primitiven, an die Kamera gehängt.
// Feuer-Kick, Nachlade-Animation (Waffe kippt aus dem Bild), Muzzle-Flash,
// leichtes Nachziehen (Sway) beim Umsehen. Farben aus dem gewählten Schema.

import * as THREE from "three";
import type { ColorScheme } from "../config/meta";
import type { WeaponId } from "../config/weapons";
import { damp } from "../core/math";
import type { Weapon } from "../core/Weapon";
import type { InputState } from "../core/input";

export class WeaponView {
  readonly root = new THREE.Group();
  private readonly gun = new THREE.Group();
  private readonly muzzle: THREE.Mesh;
  private readonly bodyMat = new THREE.MeshLambertMaterial({ color: 0x3a4250 });
  private readonly accentMat = new THREE.MeshLambertMaterial({ color: 0x7dd3ff });
  private readonly handMat = new THREE.MeshLambertMaterial({ color: 0xd9b38c });
  private readonly barrel: THREE.Mesh;
  private readonly magazine: THREE.Mesh;
  private kick = 0;
  private muzzleTimer = 0;
  private swayYaw = 0;
  private swayPitch = 0;
  private lastYaw = 0;
  private lastPitch = 0;

  constructor(camera: THREE.PerspectiveCamera) {
    const box = new THREE.BoxGeometry(1, 1, 1);

    // Körper, Lauf, Magazin, Visier — generisch, per equip() umgeformt
    const body = new THREE.Mesh(box, this.bodyMat);
    body.scale.set(0.09, 0.11, 0.42);
    this.gun.add(body);

    this.barrel = new THREE.Mesh(box, this.bodyMat);
    this.barrel.scale.set(0.045, 0.05, 0.3);
    this.barrel.position.set(0, 0.02, -0.32);
    this.gun.add(this.barrel);

    this.magazine = new THREE.Mesh(box, this.accentMat);
    this.magazine.scale.set(0.06, 0.16, 0.09);
    this.magazine.position.set(0, -0.12, 0.02);
    this.gun.add(this.magazine);

    const sight = new THREE.Mesh(box, this.accentMat);
    sight.scale.set(0.03, 0.05, 0.06);
    sight.position.set(0, 0.08, -0.1);
    this.gun.add(sight);

    const hand = new THREE.Mesh(box, this.handMat);
    hand.scale.set(0.08, 0.07, 0.12);
    hand.position.set(0, -0.1, -0.16);
    this.gun.add(hand);
    const hand2 = new THREE.Mesh(box, this.handMat);
    hand2.scale.set(0.08, 0.07, 0.1);
    hand2.position.set(0.01, -0.08, 0.14);
    this.gun.add(hand2);

    this.muzzle = new THREE.Mesh(
      new THREE.PlaneGeometry(0.3, 0.3),
      new THREE.MeshBasicMaterial({
        color: 0xffd27d,
        transparent: true,
        blending: THREE.AdditiveBlending,
        depthWrite: false,
      })
    );
    this.muzzle.position.set(0, 0.02, -0.5);
    this.muzzle.visible = false;
    this.gun.add(this.muzzle);

    this.gun.position.set(0.26, -0.25, -0.55);
    this.root.add(this.gun);
    camera.add(this.root);
  }

  applyScheme(scheme: ColorScheme): void {
    this.bodyMat.color.setHex(scheme.body);
    this.accentMat.color.setHex(scheme.accent);
    this.handMat.color.setHex(scheme.hands);
  }

  /** Silhouette an die Waffe anpassen (ohne neue Geometrie). */
  equip(id: WeaponId): void {
    if (id === "scatter") {
      this.barrel.scale.set(0.075, 0.075, 0.26);
      this.barrel.position.set(0, 0.015, -0.3);
      this.magazine.scale.set(0.05, 0.08, 0.16);
    } else if (id === "longshot") {
      this.barrel.scale.set(0.04, 0.045, 0.44);
      this.barrel.position.set(0, 0.025, -0.42);
      this.magazine.scale.set(0.05, 0.13, 0.08);
    } else {
      this.barrel.scale.set(0.045, 0.05, 0.3);
      this.barrel.position.set(0, 0.02, -0.32);
      this.magazine.scale.set(0.06, 0.16, 0.09);
    }
  }

  notifyShot(strength: number): void {
    this.kick = Math.min(1.6, this.kick + strength);
    this.muzzleTimer = 0.045;
  }

  update(dt: number, weapon: Weapon, input: InputState, bobPhase: number, moveIntensity: number): void {
    this.kick = damp(this.kick, 0, 16, dt);

    // Sway: Waffe zieht der Blickbewegung leicht hinterher
    const yawVel = input.yaw - this.lastYaw;
    const pitchVel = input.pitch - this.lastPitch;
    this.lastYaw = input.yaw;
    this.lastPitch = input.pitch;
    this.swayYaw = damp(this.swayYaw, yawVel * 5, 12, dt);
    this.swayPitch = damp(this.swayPitch, pitchVel * 5, 12, dt);

    // Nachladen: Waffe kippt aus dem Bild und kommt zurück
    let reloadDip = 0;
    let reloadTilt = 0;
    if (weapon.isReloading()) {
      const progress = 1 - weapon.reloadTimer / weapon.def.reloadTime; // 0..1
      const inout = Math.sin(Math.min(1, progress * 1.15) * Math.PI); // rein & raus
      reloadDip = inout * 0.22;
      reloadTilt = inout * 0.9;
    }

    const bobY = Math.abs(Math.sin(bobPhase)) * 0.008 * moveIntensity;
    const bobX = Math.sin(bobPhase) * 0.006 * moveIntensity;

    this.gun.position.set(
      0.26 + bobX + this.swayYaw * 0.4,
      -0.25 + bobY - reloadDip + this.swayPitch * 0.4,
      -0.55 + this.kick * 0.09
    );
    this.gun.rotation.set(this.kick * 0.14 + reloadTilt - this.swayPitch * 1.2, this.swayYaw * 1.4, reloadTilt * 0.35);

    this.muzzleTimer -= dt;
    if (this.muzzleTimer > 0) {
      this.muzzle.visible = true;
      this.muzzle.rotation.z = Math.random() * Math.PI;
      const s = 0.8 + Math.random() * 0.6;
      this.muzzle.scale.set(s, s, s);
    } else {
      this.muzzle.visible = false;
    }
  }
}
