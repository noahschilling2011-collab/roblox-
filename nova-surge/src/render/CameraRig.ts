// Kamera-Rig: Position aus interpoliertem Spielerzustand, Rotation aus
// Yaw/Pitch + Waffen-Rückstoß. Dazu das Game-Feel: Head-Bob, FOV-Kick beim
// Sprint, Landungs-Dip. Reines Lesen der Sim — schreibt nie hinein.

import * as THREE from "three";
import { FEEL, MOVE } from "../config/tuning";
import type { InputState } from "../core/input";
import { damp, lerp } from "../core/math";
import type { Player } from "../core/Player";
import type { Weapon } from "../core/Weapon";

export class CameraRig {
  readonly camera: THREE.PerspectiveCamera;
  private readonly euler = new THREE.Euler(0, 0, 0, "YXZ");
  bobPhase = 0;
  private bobIntensity = 0;
  private fov: number = FEEL.baseFov;
  private landDip = 0;
  private shake = 0;

  constructor(camera: THREE.PerspectiveCamera) {
    this.camera = camera;
  }

  notifyLand(fallSpeed: number): void {
    this.landDip = Math.min(0.14, FEEL.landingDipAmount * (fallSpeed / MOVE.jumpVelocity));
  }

  /** Kurzer Screen-Shake (eigener Schaden, Boss-Tod). */
  notifyShake(amount: number): void {
    this.shake = Math.min(1, this.shake + amount);
  }

  update(dt: number, alpha: number, player: Player, input: InputState, weapon: Weapon): void {
    // Interpolierte Position zwischen letztem und aktuellem Sim-Tick
    const x = lerp(player.prevPos.x, player.pos.x, alpha);
    const y = lerp(player.prevPos.y, player.pos.y, alpha);
    const z = lerp(player.prevPos.z, player.pos.z, alpha);

    // Head-Bob nur am Boden und bei Bewegung
    const targetIntensity = player.onGround ? player.moveIntensity : 0;
    this.bobIntensity = damp(this.bobIntensity, targetIntensity, 8, dt);
    const speedScale = player.sprinting ? 1.25 : 1;
    this.bobPhase += dt * FEEL.headBobFrequency * this.bobIntensity * speedScale;
    const bobY = Math.abs(Math.sin(this.bobPhase)) * FEEL.headBobAmplitude * this.bobIntensity;
    const bobX = Math.sin(this.bobPhase) * FEEL.headBobSway * this.bobIntensity;

    this.landDip = damp(this.landDip, 0, 10, dt);

    this.euler.y = input.yaw;
    this.euler.x = input.pitch + weapon.recoilPitch;
    this.euler.z = -bobX * 0.6;
    this.camera.quaternion.setFromEuler(this.euler);

    // seitlicher Bob entlang der Blick-Rechtsachse
    const rightX = Math.cos(input.yaw);
    const rightZ = -Math.sin(input.yaw);
    this.camera.position.set(
      x + rightX * bobX,
      y + MOVE.playerHeight + bobY - this.landDip,
      z + rightZ * bobX
    );

    // Screen-Shake: kleiner Positions-Jitter + Roll, klingt schnell ab
    this.shake = damp(this.shake, 0, 9, dt);
    if (this.shake > 0.01) {
      this.camera.position.x += (Math.random() - 0.5) * this.shake * 0.09;
      this.camera.position.y += (Math.random() - 0.5) * this.shake * 0.07;
      this.euler.z += (Math.random() - 0.5) * this.shake * 0.02;
      this.camera.quaternion.setFromEuler(this.euler);
    }

    // FOV: Sprint-Kick
    const targetFov = FEEL.baseFov + (player.sprinting && player.moveIntensity > 0.3 ? FEEL.sprintFovKick : 0);
    this.fov = damp(this.fov, targetFov, FEEL.fovLambda, dt);
    if (Math.abs(this.camera.fov - this.fov) > 0.01) {
      this.camera.fov = this.fov;
      this.camera.updateProjectionMatrix();
    }
  }
}
