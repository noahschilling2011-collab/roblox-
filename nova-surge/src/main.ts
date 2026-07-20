import * as THREE from "three";
import "./style.css";
import { GameLoop } from "./core/GameLoop";
import { Sim } from "./core/Sim";
import { createScene } from "./render/createScene";
import { LookControls } from "./controls/LookControls";
import { PauseMenu } from "./ui/PauseMenu";
import { DebugOverlay } from "./ui/DebugOverlay";

const SIM_HZ = 60;

const canvas = document.getElementById("game-canvas") as HTMLCanvasElement;

const renderer = new THREE.WebGLRenderer({ canvas, antialias: true });
renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
renderer.setSize(window.innerWidth, window.innerHeight);

const { scene, camera } = createScene(window.innerWidth / window.innerHeight);
const controls = new LookControls(camera);
const sim = new Sim();
const debugOverlay = new DebugOverlay();

const loop = new GameLoop(SIM_HZ, {
  simulate(dt) {
    sim.update(dt);
  },
  render(_alpha) {
    // _alpha wird ab Phase 1 für die Interpolation bewegter Objekte genutzt.
    renderer.render(scene, camera);
    debugOverlay.update(loop, sim, renderer);
  },
});

new PauseMenu(canvas, {
  onResume() {
    controls.enabled = true;
    loop.setPaused(false);
  },
  onPause() {
    controls.enabled = false;
    loop.setPaused(true);
  },
});

window.addEventListener("resize", () => {
  camera.aspect = window.innerWidth / window.innerHeight;
  camera.updateProjectionMatrix();
  renderer.setSize(window.innerWidth, window.innerHeight);
});

loop.start();

// Debug-Handle für automatisierte Tests (Headless-Browser) und die Konsole.
declare global {
  interface Window {
    __ns: { loop: GameLoop; sim: Sim; renderer: THREE.WebGLRenderer };
  }
}
window.__ns = { loop, sim, renderer };
