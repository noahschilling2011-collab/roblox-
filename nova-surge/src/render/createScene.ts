import * as THREE from "three";
import { ARENA, ARENA_BOXES, ENEMY_SPAWNS, PALETTE } from "../config/arena";
import { FEEL } from "../config/tuning";

export interface SceneSetup {
  scene: THREE.Scene;
  camera: THREE.PerspectiveCamera;
}

// Arena-Szene (Phase 3): Boxen aus der Config, Low-Poly-Look über flache
// Farben + Fog. Spawn-Tore mit Akzentfarbe markiert (Lesbarkeit: da kommen
// die Gegner her).

export function createScene(aspect: number): SceneSetup {
  const scene = new THREE.Scene();
  scene.background = new THREE.Color(PALETTE.sky);
  scene.fog = new THREE.Fog(PALETTE.sky, PALETTE.fogNear, PALETTE.fogFar);

  const floor = new THREE.Mesh(
    new THREE.PlaneGeometry(ARENA.size + 40, ARENA.size + 40),
    new THREE.MeshLambertMaterial({ color: PALETTE.floor })
  );
  floor.rotation.x = -Math.PI / 2;
  scene.add(floor);

  const grid = new THREE.GridHelper(ARENA.size, ARENA.size / 4, 0x8b95a1, 0x79828e);
  grid.position.y = 0.02;
  scene.add(grid);

  const materials = {
    wall: new THREE.MeshLambertMaterial({ color: PALETTE.wall }),
    tall: new THREE.MeshLambertMaterial({ color: PALETTE.tall }),
    low: new THREE.MeshLambertMaterial({ color: PALETTE.low }),
  };
  const unitBox = new THREE.BoxGeometry(1, 1, 1);
  for (const b of ARENA_BOXES) {
    const mesh = new THREE.Mesh(unitBox, materials[b.kind]);
    mesh.scale.set(b.sx, b.h, b.sz);
    mesh.position.set(b.x, b.h / 2, b.z);
    scene.add(mesh);
    // Akzentkante oben auf hohen Deckungen (Low-Poly-"Trim")
    if (b.kind === "tall" || b.kind === "low") {
      const trim = new THREE.Mesh(unitBox, trimMaterial);
      trim.scale.set(b.sx + 0.06, 0.09, b.sz + 0.06);
      trim.position.set(b.x, b.h + 0.045, b.z);
      scene.add(trim);
    }
  }

  // Spawn-Tore: Akzent-Rahmen an den Wandmitten
  for (const sp of ENEMY_SPAWNS) {
    const gate = new THREE.Mesh(unitBox, gateMaterial);
    const onXWall = Math.abs(sp.x) > Math.abs(sp.z);
    gate.scale.set(onXWall ? 0.4 : 6, 3.4, onXWall ? 6 : 0.4);
    gate.position.set(sp.x * 1.06, 1.7, sp.z * 1.06);
    scene.add(gate);
  }

  const hemi = new THREE.HemisphereLight(0xe8f4ff, 0x4d5560, 1.0);
  scene.add(hemi);
  const sun = new THREE.DirectionalLight(0xfff2dc, 1.5);
  sun.position.set(35, 60, 25);
  scene.add(sun);

  const camera = new THREE.PerspectiveCamera(FEEL.baseFov, aspect, 0.05, 300);
  camera.position.set(0, 1.7, 12);

  return { scene, camera };
}

const trimMaterial = new THREE.MeshLambertMaterial({ color: PALETTE.accent });
const gateMaterial = new THREE.MeshLambertMaterial({
  color: PALETTE.accent,
  emissive: PALETTE.accent,
  emissiveIntensity: 0.35,
});
