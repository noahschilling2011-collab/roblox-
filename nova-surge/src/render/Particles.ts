// Partikelsystem: EIN InstancedMesh für alles (Einschläge, Hülsen,
// Gegner-Treffer, Todes-Burst). Fester Pool, Simulation rein visuell im
// Render-Takt. Tote Instanzen werden auf Skalierung 0 gesetzt.

import * as THREE from "three";

const CAPACITY = 320;
const GRAVITY = 18;

interface ParticleSlot {
  life: number;
  maxLife: number;
  x: number;
  y: number;
  z: number;
  vx: number;
  vy: number;
  vz: number;
  size: number;
  gravity: number;
}

const _dummy = new THREE.Object3D();
const _color = new THREE.Color();

export class Particles {
  private readonly mesh: THREE.InstancedMesh;
  private readonly slots: ParticleSlot[] = [];
  private cursor = 0;

  constructor(scene: THREE.Scene) {
    this.mesh = new THREE.InstancedMesh(
      new THREE.BoxGeometry(1, 1, 1),
      new THREE.MeshBasicMaterial({ color: 0xffffff }),
      CAPACITY
    );
    this.mesh.instanceMatrix.setUsage(THREE.DynamicDrawUsage);
    this.mesh.frustumCulled = false;
    for (let i = 0; i < CAPACITY; i++) {
      this.slots.push({ life: 0, maxLife: 1, x: 0, y: 0, z: 0, vx: 0, vy: 0, vz: 0, size: 0.05, gravity: 1 });
      _dummy.position.set(0, -100, 0);
      _dummy.scale.setScalar(0.0001);
      _dummy.updateMatrix();
      this.mesh.setMatrixAt(i, _dummy.matrix);
      this.mesh.setColorAt(i, _color.setHex(0xffffff));
    }
    scene.add(this.mesh);
  }

  burst(
    x: number,
    y: number,
    z: number,
    colorHex: number,
    count: number,
    speed: number,
    life: number,
    size = 0.06,
    gravityScale = 1,
    upBias = 0.4
  ): void {
    for (let n = 0; n < count; n++) {
      const s = this.slots[this.cursor]!;
      const i = this.cursor;
      this.cursor = (this.cursor + 1) % CAPACITY;
      s.life = s.maxLife = life * (0.6 + Math.random() * 0.7);
      s.x = x;
      s.y = y;
      s.z = z;
      const theta = Math.random() * Math.PI * 2;
      const phi = Math.acos(2 * Math.random() - 1);
      const v = speed * (0.4 + Math.random() * 0.8);
      s.vx = Math.sin(phi) * Math.cos(theta) * v;
      s.vy = Math.cos(phi) * v * (1 - upBias) + v * upBias;
      s.vz = Math.sin(phi) * Math.sin(theta) * v;
      s.size = size * (0.6 + Math.random() * 0.9);
      s.gravity = gravityScale;
      this.mesh.setColorAt(i, _color.setHex(colorHex));
    }
    if (this.mesh.instanceColor) this.mesh.instanceColor.needsUpdate = true;
  }

  update(dt: number): void {
    for (let i = 0; i < CAPACITY; i++) {
      const s = this.slots[i]!;
      if (s.life <= 0) continue;
      s.life -= dt;
      s.vy -= GRAVITY * s.gravity * dt;
      s.x += s.vx * dt;
      s.y += s.vy * dt;
      s.z += s.vz * dt;
      if (s.y < 0.02 && s.vy < 0) {
        s.y = 0.02;
        s.vy *= -0.3; // kleiner Bounce
        s.vx *= 0.7;
        s.vz *= 0.7;
      }
      const fade = Math.max(0, s.life / s.maxLife);
      _dummy.position.set(s.x, s.y, s.z);
      _dummy.scale.setScalar(s.life > 0 ? s.size * (0.3 + fade * 0.7) : 0.0001);
      _dummy.rotation.set(s.life * 7, s.life * 9, 0);
      _dummy.updateMatrix();
      this.mesh.setMatrixAt(i, _dummy.matrix);
    }
    this.mesh.instanceMatrix.needsUpdate = true;
  }
}
