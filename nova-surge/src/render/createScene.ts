import * as THREE from "three";

export interface SceneSetup {
  scene: THREE.Scene;
  camera: THREE.PerspectiveCamera;
}

// Phase-0-Szene: Boden + Licht, sonst nichts. Low-Poly-Look kommt aus
// flachen Farben und Fog, nicht aus Texturen.

const SKY_COLOR = 0x9fd8ff;
const GROUND_COLOR = 0x5e6a75;
const EYE_HEIGHT = 1.7;

export function createScene(aspect: number): SceneSetup {
  const scene = new THREE.Scene();
  scene.background = new THREE.Color(SKY_COLOR);
  scene.fog = new THREE.Fog(SKY_COLOR, 60, 160);

  const ground = new THREE.Mesh(
    new THREE.PlaneGeometry(200, 200),
    new THREE.MeshLambertMaterial({ color: GROUND_COLOR })
  );
  ground.rotation.x = -Math.PI / 2;
  scene.add(ground);

  // Grid als Orientierung, damit Mouse-Look/Bewegung sichtbar prüfbar ist.
  const grid = new THREE.GridHelper(200, 50, 0x3c454f, 0x4a545f);
  grid.position.y = 0.01;
  scene.add(grid);

  const hemi = new THREE.HemisphereLight(0xdfefff, 0x46505a, 0.9);
  scene.add(hemi);

  const sun = new THREE.DirectionalLight(0xfff4dd, 1.4);
  sun.position.set(30, 50, 20);
  scene.add(sun);

  const camera = new THREE.PerspectiveCamera(75, aspect, 0.1, 300);
  camera.position.set(0, EYE_HEIGHT, 0);

  return { scene, camera };
}
