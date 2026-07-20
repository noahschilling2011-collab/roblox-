// Gegner-Darstellung: vorgebaute Mesh-Pools pro Typ (keine Allokationen beim
// Spawnen), klare Silhouetten aus Primitiven, Hitreact-Weißblitz, Tod als
// Umkippen + Ausblenden. Positionen werden zwischen Sim-Ticks interpoliert.

import * as THREE from "three";
import { ENEMIES, ENEMY_AI, type EnemyType } from "../config/enemies";
import type { Enemy, EnemyManager } from "../core/Enemy";
import { lerp } from "../core/math";

interface EnemyVisual {
  group: THREE.Group;
  materials: THREE.MeshLambertMaterial[];
  assigned: Enemy | null;
}

const POOL_PER_TYPE = ENEMY_AI.maxAlive + 6;

export class EnemyRenderer {
  private readonly pools: Record<EnemyType, EnemyVisual[]> = { rusher: [], shooter: [], tank: [] };
  private readonly byEnemy = new Map<Enemy, EnemyVisual>();

  constructor(scene: THREE.Scene) {
    const types: EnemyType[] = ["rusher", "shooter", "tank"];
    for (const type of types) {
      for (let i = 0; i < POOL_PER_TYPE; i++) {
        const visual = buildVisual(type);
        visual.group.visible = false;
        scene.add(visual.group);
        this.pools[type].push(visual);
      }
    }
  }

  update(enemies: EnemyManager, alpha: number, playerX: number, playerZ: number, time: number): void {
    // Freigeben, was nicht mehr aktiv ist
    for (const [enemy, visual] of this.byEnemy) {
      if (!enemy.active) {
        visual.assigned = null;
        visual.group.visible = false;
        this.byEnemy.delete(enemy);
      }
    }

    for (const e of enemies.slots) {
      if (!e.active) continue;
      let visual = this.byEnemy.get(e);
      if (!visual) {
        visual = this.pools[e.def.type].find((v) => v.assigned === null) ?? null!;
        if (!visual) continue; // Pool erschöpft (sollte durch maxAlive nie passieren)
        visual.assigned = e;
        this.byEnemy.set(e, visual);
        visual.group.visible = true;
      }

      const g = visual.group;
      g.position.set(
        lerp(e.prevPos.x, e.pos.x, alpha),
        lerp(e.prevPos.y, e.pos.y, alpha),
        lerp(e.prevPos.z, e.pos.z, alpha)
      );
      // Immer zum Spieler drehen (sie wollen zu ihm)
      g.rotation.y = Math.atan2(playerX - e.pos.x, playerZ - e.pos.z);

      if (e.fsm === "death") {
        // Umkippen + ausblenden
        const t = 1 - e.stateTimer / ENEMY_AI.deathDuration; // 0..1
        g.rotation.x = t * (Math.PI / 2) * 0.9;
        const opacity = 1 - t * t;
        for (const m of visual.materials) {
          m.transparent = true;
          m.opacity = opacity;
          m.emissiveIntensity = 0;
        }
      } else {
        g.rotation.x = 0;
        // Idle-Puls + Hitreact-Zucken
        const pulse = 1 + Math.sin(time * 4 + e.pos.x) * 0.015;
        // Flinch: kurz zusammenzucken (vertikal stauchen, horizontal leicht breiter)
        const flinch = e.fsm === "hitreact" ? 1 - 0.12 * Math.sin((e.stateTimer / ENEMY_AI.hitreactDuration) * Math.PI) : 1;
        g.scale.set(pulse * (2 - flinch), flinch, pulse * (2 - flinch));
        // Weißblitz beim Treffer
        for (const m of visual.materials) {
          if (m.opacity !== 1) {
            m.opacity = 1;
            m.transparent = false;
          }
          m.emissiveIntensity = e.flash * 0.9;
        }
      }
    }
  }

  clear(): void {
    for (const [, visual] of this.byEnemy) {
      visual.assigned = null;
      visual.group.visible = false;
    }
    this.byEnemy.clear();
  }
}

function buildVisual(type: EnemyType): EnemyVisual {
  const def = ENEMIES[type];
  const group = new THREE.Group();
  const materials: THREE.MeshLambertMaterial[] = [];
  const mat = (): THREE.MeshLambertMaterial => {
    const m = new THREE.MeshLambertMaterial({ color: def.color, emissive: 0xffffff, emissiveIntensity: 0 });
    materials.push(m);
    return m;
  };
  const darkMat = (): THREE.MeshLambertMaterial => {
    const m = new THREE.MeshLambertMaterial({ color: 0x1c2026, emissive: 0xffffff, emissiveIntensity: 0 });
    materials.push(m);
    return m;
  };
  const box = new THREE.BoxGeometry(1, 1, 1);

  if (type === "rusher") {
    // Schmaler roter Kegel mit "Auge" — schnell & spitz
    const body = new THREE.Mesh(new THREE.ConeGeometry(0.42, 1.5, 8), mat());
    body.position.y = 0.75;
    group.add(body);
    const eye = new THREE.Mesh(box, darkMat());
    eye.scale.set(0.3, 0.09, 0.1);
    eye.position.set(0, 1.05, 0.22);
    group.add(eye);
  } else if (type === "shooter") {
    // Eckiger violetter Turm mit sichtbarem Lauf
    const body = new THREE.Mesh(box, mat());
    body.scale.set(0.75, 1.25, 0.55);
    body.position.y = 0.8;
    group.add(body);
    const head = new THREE.Mesh(box, mat());
    head.scale.set(0.45, 0.4, 0.45);
    head.position.y = 1.65;
    group.add(head);
    const barrel = new THREE.Mesh(box, darkMat());
    barrel.scale.set(0.12, 0.12, 0.7);
    barrel.position.set(0, 1.55, 0.5);
    group.add(barrel);
  } else {
    // Breiter dunkelgrüner Block mit Schultern — massiv
    const body = new THREE.Mesh(box, mat());
    body.scale.set(1.5, 1.9, 1.1);
    body.position.y = 0.95;
    group.add(body);
    const shoulderL = new THREE.Mesh(box, darkMat());
    shoulderL.scale.set(0.45, 0.6, 0.7);
    shoulderL.position.set(-0.95, 1.7, 0);
    group.add(shoulderL);
    const shoulderR = new THREE.Mesh(box, darkMat());
    shoulderR.scale.set(0.45, 0.6, 0.7);
    shoulderR.position.set(0.95, 1.7, 0);
    group.add(shoulderR);
    const visor = new THREE.Mesh(box, darkMat());
    visor.scale.set(0.9, 0.18, 0.1);
    visor.position.set(0, 1.55, 0.58);
    group.add(visor);
  }
  return { group, materials, assigned: null };
}
