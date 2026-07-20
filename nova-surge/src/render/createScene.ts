import * as THREE from "three";
import { ARENAS, type ArenaDef } from "../config/arena";
import { FEEL } from "../config/tuning";

export interface SceneSetup {
  scene: THREE.Scene;
  camera: THREE.PerspectiveCamera;
  /** Zeigt die gewählte Arena (Meshes, Fog, Himmel); alle anderen versteckt. */
  showArena(def: ArenaDef): void;
}

// Alle Arenen werden EINMAL beim Boot gebaut und per Sichtbarkeit
// umgeschaltet — kein Aufbau/Abbau zur Laufzeit, keine Leaks.

export function createScene(aspect: number): SceneSetup {
  const scene = new THREE.Scene();

  const hemi = new THREE.HemisphereLight(0xe8f4ff, 0x4d5560, 1.0);
  scene.add(hemi);
  const sun = new THREE.DirectionalLight(0xfff2dc, 1.5);
  sun.position.set(35, 60, 25);
  scene.add(sun);

  const camera = new THREE.PerspectiveCamera(FEEL.baseFov, aspect, 0.05, 300);
  camera.position.set(0, 1.7, 12);

  const groups = new Map<string, THREE.Group>();
  for (const def of ARENAS) {
    const g = buildArenaGroup(def);
    g.visible = false;
    scene.add(g);
    groups.set(def.id, g);
  }

  const fog = new THREE.Fog(0xffffff, 50, 150);
  scene.fog = fog;

  function showArena(def: ArenaDef): void {
    for (const [id, g] of groups) g.visible = id === def.id;
    scene.background = new THREE.Color(def.palette.sky);
    fog.color.setHex(def.palette.sky);
    fog.near = def.palette.fogNear;
    fog.far = def.palette.fogFar;
  }

  showArena(ARENAS[0]!);
  return { scene, camera, showArena };
}

const unitBox = new THREE.BoxGeometry(1, 1, 1);

function buildArenaGroup(def: ArenaDef): THREE.Group {
  const group = new THREE.Group();
  const p = def.palette;

  const floor = new THREE.Mesh(
    new THREE.PlaneGeometry(def.size + 40, def.size + 40),
    new THREE.MeshLambertMaterial({ color: p.floor })
  );
  floor.rotation.x = -Math.PI / 2;
  group.add(floor);

  const grid = new THREE.GridHelper(def.size, def.size / 4, p.grid1, p.grid2);
  grid.position.y = 0.02;
  group.add(grid);

  const materials = {
    wall: new THREE.MeshLambertMaterial({ color: p.wall }),
    tall: new THREE.MeshLambertMaterial({ color: p.tall }),
    low: new THREE.MeshLambertMaterial({ color: p.low }),
  };
  const trimMaterial = new THREE.MeshLambertMaterial({ color: p.accent });
  const gateMaterial = new THREE.MeshLambertMaterial({
    color: p.accent,
    emissive: p.accent,
    emissiveIntensity: 0.35,
  });

  for (const b of def.boxes) {
    const mesh = new THREE.Mesh(unitBox, materials[b.kind]);
    mesh.scale.set(b.sx, b.h, b.sz);
    mesh.position.set(b.x, b.h / 2, b.z);
    group.add(mesh);
    // Akzentkante oben auf Deckungen (Low-Poly-"Trim")
    if (b.kind === "tall" || b.kind === "low") {
      const trim = new THREE.Mesh(unitBox, trimMaterial);
      trim.scale.set(b.sx + 0.06, 0.09, b.sz + 0.06);
      trim.position.set(b.x, b.h + 0.045, b.z);
      group.add(trim);
    }
  }

  // Spawn-Tore: Akzent-Rahmen an den Wandmitten
  for (const sp of def.enemySpawns) {
    const gate = new THREE.Mesh(unitBox, gateMaterial);
    const onXWall = Math.abs(sp.x) > Math.abs(sp.z);
    gate.scale.set(onXWall ? 0.4 : 6, 3.4, onXWall ? 6 : 0.4);
    gate.position.set(sp.x * 1.06, 1.7, sp.z * 1.06);
    group.add(gate);
  }

  return group;
}
