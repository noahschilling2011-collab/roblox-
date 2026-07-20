// Tracer-Linien: Pool dünner, additiv gerenderter Boxen von der Mündung zum
// Einschlagpunkt. Kurzes Leben, schnelles Ausblenden — reine Lesbarkeit.

import * as THREE from "three";

const CAPACITY = 24;
const LIFE = 0.06;

interface TracerSlot {
  mesh: THREE.Mesh;
  material: THREE.MeshBasicMaterial;
  life: number;
}

const _from = new THREE.Vector3();
const _to = new THREE.Vector3();

export class Tracers {
  private readonly slots: TracerSlot[] = [];
  private cursor = 0;

  constructor(scene: THREE.Scene) {
    const geo = new THREE.BoxGeometry(1, 1, 1);
    for (let i = 0; i < CAPACITY; i++) {
      const material = new THREE.MeshBasicMaterial({
        color: 0xffe2a8,
        transparent: true,
        opacity: 0,
        blending: THREE.AdditiveBlending,
        depthWrite: false,
      });
      const mesh = new THREE.Mesh(geo, material);
      mesh.visible = false;
      mesh.frustumCulled = false;
      scene.add(mesh);
      this.slots.push({ mesh, material, life: 0 });
    }
  }

  spawn(fx: number, fy: number, fz: number, tx: number, ty: number, tz: number): void {
    const s = this.slots[this.cursor]!;
    this.cursor = (this.cursor + 1) % CAPACITY;
    _from.set(fx, fy, fz);
    _to.set(tx, ty, tz);
    const len = _from.distanceTo(_to);
    if (len < 0.3) return;
    s.mesh.position.copy(_from).lerp(_to, 0.5);
    s.mesh.lookAt(_to);
    s.mesh.scale.set(0.015, 0.015, len);
    s.mesh.visible = true;
    s.life = LIFE;
  }

  update(dt: number): void {
    for (const s of this.slots) {
      if (s.life <= 0) continue;
      s.life -= dt;
      if (s.life <= 0) {
        s.mesh.visible = false;
        s.material.opacity = 0;
      } else {
        s.material.opacity = (s.life / LIFE) * 0.85;
      }
    }
  }
}
