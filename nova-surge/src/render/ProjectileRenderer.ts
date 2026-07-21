// Projektil-Darstellung: EIN InstancedMesh für alle fliegenden Geschosse
// (Shooter-/Boss-Schüsse violett, Shotgun-Pellets orange). Ohne diesen
// Renderer wären Projektile unsichtbar — "ausweichbar" setzt sichtbar voraus.

import * as THREE from "three";
import type { Projectiles } from "../core/Projectiles";
import { lerp } from "../core/math";

const CAPACITY = 128;
const _dummy = new THREE.Object3D();
const _color = new THREE.Color();

const ENEMY_COLOR = 0xc887ff; // violett, hebt sich überall ab
const PLAYER_COLOR = 0xffc46b; // warmes Orange (Pellets)

export class ProjectileRenderer {
  private readonly mesh: THREE.InstancedMesh;

  constructor(scene: THREE.Scene) {
    this.mesh = new THREE.InstancedMesh(
      new THREE.SphereGeometry(1, 8, 6),
      new THREE.MeshBasicMaterial({ color: 0xffffff }), // Basic: leuchtet ohne Licht
      CAPACITY
    );
    this.mesh.instanceMatrix.setUsage(THREE.DynamicDrawUsage);
    this.mesh.frustumCulled = false;
    for (let i = 0; i < CAPACITY; i++) {
      hide(i, this.mesh);
      this.mesh.setColorAt(i, _color.setHex(ENEMY_COLOR));
    }
    scene.add(this.mesh);
  }

  update(projectiles: Projectiles, alpha: number): void {
    const slots = projectiles.slots;
    for (let i = 0; i < CAPACITY && i < slots.length; i++) {
      const s = slots[i]!;
      if (!s.active) {
        hide(i, this.mesh);
        continue;
      }
      _dummy.position.set(lerp(s.prevX, s.x, alpha), lerp(s.prevY, s.y, alpha), lerp(s.prevZ, s.z, alpha));
      _dummy.scale.setScalar(s.fromPlayer ? 0.07 : 0.16);
      _dummy.rotation.set(0, 0, 0);
      _dummy.updateMatrix();
      this.mesh.setMatrixAt(i, _dummy.matrix);
      this.mesh.setColorAt(i, _color.setHex(s.fromPlayer ? PLAYER_COLOR : ENEMY_COLOR));
    }
    this.mesh.instanceMatrix.needsUpdate = true;
    if (this.mesh.instanceColor) this.mesh.instanceColor.needsUpdate = true;
  }
}

function hide(i: number, mesh: THREE.InstancedMesh): void {
  _dummy.position.set(0, -100, 0);
  _dummy.scale.setScalar(0.0001);
  _dummy.updateMatrix();
  mesh.setMatrixAt(i, _dummy.matrix);
}
