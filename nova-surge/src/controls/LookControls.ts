import * as THREE from "three";

// Maus-Look bei aktivem Pointer Lock: Yaw um die Weltachse, Pitch geklemmt.
// Nur Kamera-Rotation — Bewegung (WASD) ist Phase 1.

const SENSITIVITY = 0.0022;
const MAX_PITCH = Math.PI / 2 - 0.01;

export class LookControls {
  private readonly camera: THREE.PerspectiveCamera;
  private readonly euler = new THREE.Euler(0, 0, 0, "YXZ");
  enabled = false;

  constructor(camera: THREE.PerspectiveCamera) {
    this.camera = camera;
    document.addEventListener("mousemove", this.onMouseMove);
  }

  private onMouseMove = (event: MouseEvent): void => {
    if (!this.enabled) return;
    this.euler.y -= event.movementX * SENSITIVITY;
    this.euler.x -= event.movementY * SENSITIVITY;
    this.euler.x = Math.max(-MAX_PITCH, Math.min(MAX_PITCH, this.euler.x));
    this.camera.quaternion.setFromEuler(this.euler);
  };
}
