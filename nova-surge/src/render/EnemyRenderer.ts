// Gegner-Darstellung: vorgebaute Mesh-Pools pro Typ (keine Allokationen beim
// Spawnen), detaillierte Silhouetten aus Primitiven mit prozeduraler
// Animation: Beine schwingen mit dem Lauftempo, Shooter-Lauf hat Rückstoß,
// Glow-Augen/-Kerne, Hitreact-Weißblitz, Tod = Umkippen + Ausblenden.

import * as THREE from "three";
import { ENEMY_AI, type EnemyType } from "../config/enemies";
import type { Enemy, EnemyManager } from "../core/Enemy";
import { lerp } from "../core/math";

interface EnemyVisual {
  group: THREE.Group;
  /** Flashbare Materialien (Weißblitz bei Treffern). */
  materials: THREE.MeshLambertMaterial[];
  /** Dauerhaft leuchtende Materialien (Augen/Kerne) — nur Fade beim Tod. */
  glowMats: THREE.MeshLambertMaterial[];
  parts: {
    legL?: THREE.Mesh;
    legR?: THREE.Mesh;
    armL?: THREE.Mesh;
    armR?: THREE.Mesh;
    barrel?: THREE.Mesh;
    body?: THREE.Mesh;
  };
  walkPhase: number;
  assigned: Enemy | null;
}

const POOL_SIZE: Record<EnemyType, number> = {
  rusher: ENEMY_AI.maxAlive + 6,
  shooter: ENEMY_AI.maxAlive + 6,
  tank: ENEMY_AI.maxAlive + 6,
  warden: 4, // Bosse: nie mehr als eine Handvoll gleichzeitig
};

export class EnemyRenderer {
  private readonly pools: Record<EnemyType, EnemyVisual[]> = { rusher: [], shooter: [], tank: [], warden: [] };
  private readonly byEnemy = new Map<Enemy, EnemyVisual>();

  constructor(scene: THREE.Scene) {
    const types: EnemyType[] = ["rusher", "shooter", "tank", "warden"];
    for (const type of types) {
      for (let i = 0; i < POOL_SIZE[type]; i++) {
        const visual = buildVisual(type);
        visual.group.visible = false;
        scene.add(visual.group);
        this.pools[type].push(visual);
      }
    }
  }

  update(enemies: EnemyManager, alpha: number, dt: number, playerX: number, playerZ: number, time: number): void {
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
        if (!visual) continue;
        visual.assigned = e;
        visual.walkPhase = Math.random() * Math.PI * 2;
        this.byEnemy.set(e, visual);
        visual.group.visible = true;
      }

      const g = visual.group;
      g.position.set(
        lerp(e.prevPos.x, e.pos.x, alpha),
        lerp(e.prevPos.y, e.pos.y, alpha),
        lerp(e.prevPos.z, e.pos.z, alpha)
      );
      g.rotation.y = Math.atan2(playerX - e.pos.x, playerZ - e.pos.z);

      if (e.fsm === "death") {
        const t = 1 - e.stateTimer / ENEMY_AI.deathDuration; // 0..1
        g.rotation.x = t * (Math.PI / 2) * 0.9;
        const opacity = 1 - t * t;
        for (const m of visual.materials) {
          m.transparent = true;
          m.opacity = opacity;
          m.emissiveIntensity = 0;
        }
        for (const m of visual.glowMats) {
          m.transparent = true;
          m.opacity = opacity;
        }
        continue;
      }

      g.rotation.x = 0;
      const speed = Math.hypot(e.vel.x, e.vel.z);
      visual.walkPhase += dt * (2.2 + speed * 1.6);
      const swing = Math.sin(visual.walkPhase * 3);
      const speedFactor = Math.min(1, speed / 4);

      // Beine/Arme schwingen mit dem Lauftempo
      const p = visual.parts;
      if (p.legL && p.legR) {
        p.legL.rotation.x = swing * 0.65 * speedFactor;
        p.legR.rotation.x = -swing * 0.65 * speedFactor;
      }
      if (p.armL && p.armR) {
        p.armL.rotation.x = -swing * 0.45 * speedFactor;
        p.armR.rotation.x = swing * 0.45 * speedFactor;
      }
      // Shooter: Lauf zuckt beim Burst zurück
      if (p.barrel) {
        p.barrel.position.z = 0.45 + (e.burstShotsLeft > 0 ? -0.1 * Math.abs(Math.sin(time * 30)) : 0);
      }
      // Rusher lehnen sich beim Rennen nach vorn
      if (e.def.type === "rusher" && p.body) {
        p.body.rotation.x = 0.22 * speedFactor;
      }

      // Idle-Atmen + Lauf-Wippen
      const bob = Math.abs(Math.sin(visual.walkPhase * 3)) * 0.05 * speedFactor;
      g.position.y += bob;
      g.rotation.z = swing * 0.04 * speedFactor;

      // Hitreact: kurz zusammenzucken
      const flinch =
        e.fsm === "hitreact" ? 1 - 0.12 * Math.sin((e.stateTimer / ENEMY_AI.hitreactDuration) * Math.PI) : 1;
      g.scale.set(2 - flinch, flinch, 2 - flinch);

      // Weißblitz beim Treffer
      for (const m of visual.materials) {
        if (m.opacity !== 1) {
          m.opacity = 1;
          m.transparent = false;
        }
        m.emissiveIntensity = e.flash * 0.9;
      }
      for (const m of visual.glowMats) {
        if (m.opacity !== 1) {
          m.opacity = 1;
          m.transparent = false;
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

const box = new THREE.BoxGeometry(1, 1, 1);

function buildVisual(type: EnemyType): EnemyVisual {
  const group = new THREE.Group();
  const materials: THREE.MeshLambertMaterial[] = [];
  const glowMats: THREE.MeshLambertMaterial[] = [];
  const parts: EnemyVisual["parts"] = {};

  const mat = (color: number): THREE.MeshLambertMaterial => {
    const m = new THREE.MeshLambertMaterial({ color, emissive: 0xffffff, emissiveIntensity: 0 });
    materials.push(m);
    return m;
  };
  const glow = (color: number): THREE.MeshLambertMaterial => {
    const m = new THREE.MeshLambertMaterial({ color, emissive: color, emissiveIntensity: 1 });
    glowMats.push(m);
    return m;
  };
  const add = (
    material: THREE.Material,
    sx: number,
    sy: number,
    sz: number,
    x: number,
    y: number,
    z: number
  ): THREE.Mesh => {
    const mesh = new THREE.Mesh(box, material);
    mesh.scale.set(sx, sy, sz);
    mesh.position.set(x, y, z);
    group.add(mesh);
    return mesh;
  };

  if (type === "rusher") {
    // Roter Sprinter: Kegelkörper, Glutauge, Klingenarme, flinke Beine
    const body = mat(0xe8543f);
    const dark = mat(0x30201c);
    const cone = new THREE.Mesh(new THREE.ConeGeometry(0.4, 1.25, 6), body);
    cone.position.y = 0.95;
    group.add(cone);
    parts.body = cone;
    add(glow(0xffb03a), 0.3, 0.08, 0.06, 0, 1.18, 0.26); // Glutauge
    add(dark, 0.09, 0.14, 0.09, 0, 1.62, 0); // Antenne/Spitze
    const armL = add(dark, 0.07, 0.55, 0.16, -0.45, 0.95, 0);
    const armR = add(dark, 0.07, 0.55, 0.16, 0.45, 0.95, 0);
    armL.rotation.z = 0.45;
    armR.rotation.z = -0.45;
    parts.armL = armL;
    parts.armR = armR;
    parts.legL = add(dark, 0.14, 0.38, 0.14, -0.14, 0.19, 0);
    parts.legR = add(dark, 0.14, 0.38, 0.14, 0.14, 0.19, 0);
  } else if (type === "shooter") {
    // Violetter Turret-Walker: Torso, Visier, Lauf mit Rückstoß, Läufer-Beine
    const body = mat(0x8d5fe0);
    const dark = mat(0x241a38);
    add(body, 0.72, 0.9, 0.5, 0, 1.0, 0); // Torso
    add(dark, 0.78, 0.14, 0.56, 0, 1.0, 0); // Gurtband
    add(body, 0.46, 0.34, 0.46, 0, 1.62, 0); // Kopf
    add(glow(0x62e6ff), 0.34, 0.09, 0.04, 0, 1.64, 0.24); // Visier
    parts.barrel = add(dark, 0.11, 0.11, 0.75, 0, 1.42, 0.45); // Lauf
    add(dark, 0.24, 0.15, 0.42, -0.5, 1.5, 0); // Schulter L
    add(dark, 0.24, 0.15, 0.42, 0.5, 1.5, 0); // Schulter R
    add(glow(0x62e6ff), 0.16, 0.16, 0.05, 0, 0.95, 0.27); // Kern
    parts.legL = add(dark, 0.17, 0.55, 0.17, -0.2, 0.28, 0);
    parts.legR = add(dark, 0.17, 0.55, 0.17, 0.2, 0.28, 0);
  } else if (type === "warden") {
    // BOSS: goldener Koloss mit Krone, rot glühendem Kern und Bannerkap
    const gold = mat(0xc9a227);
    const dark = mat(0x2b2416);
    add(gold, 1.7, 1.9, 1.2, 0, 1.35, 0); // Torso
    add(dark, 1.8, 0.4, 1.3, 0, 2.2, 0); // Brustpanzer
    add(gold, 0.6, 0.45, 0.6, 0, 2.7, 0.05); // Kopf
    add(glow(0xff3b2f), 0.44, 0.12, 0.06, 0, 2.72, 0.36); // Glutvisier
    add(glow(0xff3b2f), 0.5, 0.4, 0.08, 0, 1.6, 0.63); // Kern
    // Krone: drei Zacken
    const spike = new THREE.ConeGeometry(0.12, 0.42, 4);
    for (const sx of [-0.2, 0, 0.2]) {
      const z = new THREE.Mesh(spike, dark);
      z.position.set(sx, 3.1, 0);
      group.add(z);
    }
    add(dark, 0.6, 0.6, 1.0, -1.15, 2.15, 0); // Schulter L
    add(dark, 0.6, 0.6, 1.0, 1.15, 2.15, 0); // Schulter R
    parts.armL = add(gold, 0.42, 1.1, 0.42, -1.18, 1.15, 0);
    parts.armR = add(gold, 0.42, 1.1, 0.42, 1.18, 1.15, 0);
    parts.legL = add(dark, 0.5, 0.85, 0.5, -0.42, 0.42, 0);
    parts.legR = add(dark, 0.5, 0.85, 0.5, 0.42, 0.42, 0);
    add(dark, 1.2, 1.6, 0.08, 0, 1.5, -0.68); // Banner-Rückenplatte
  } else {
    // Grüner Brocken: massiver Torso, Schulterpanzer, Stampf-Beine, Warnkern
    const body = mat(0x4f7a4a);
    const dark = mat(0x1e2b1c);
    const plate = mat(0x39573a);
    add(body, 1.35, 1.5, 1.0, 0, 1.15, 0); // Torso
    add(plate, 1.45, 0.35, 1.08, 0, 1.75, 0); // Brustpanzer oben
    add(body, 0.5, 0.34, 0.5, 0, 2.1, 0.1); // Kopf
    add(glow(0xffd23a), 0.4, 0.1, 0.05, 0, 2.12, 0.36); // Visier
    add(plate, 0.55, 0.5, 0.85, -0.92, 1.75, 0); // Schulter L
    add(plate, 0.55, 0.5, 0.85, 0.92, 1.75, 0); // Schulter R
    parts.armL = add(dark, 0.36, 0.85, 0.36, -0.95, 1.0, 0);
    parts.armR = add(dark, 0.36, 0.85, 0.36, 0.95, 1.0, 0);
    add(glow(0xffd23a), 0.34, 0.26, 0.06, 0, 1.25, 0.52); // Warnkern
    add(dark, 0.05, 0.5, 0.05, 0.35, 2.5, -0.2); // Antenne
    parts.legL = add(dark, 0.42, 0.72, 0.42, -0.36, 0.36, 0);
    parts.legR = add(dark, 0.42, 0.72, 0.42, 0.36, 0.36, 0);
  }
  return { group, materials, glowMats, parts, walkPhase: 0, assigned: null };
}
