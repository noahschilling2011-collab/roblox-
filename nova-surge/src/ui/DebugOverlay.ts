import type * as THREE from "three";
import type { GameLoop } from "../core/GameLoop";
import type { Sim } from "../core/Sim";

// Debug-Overlay (Taste F3, wie in bekannten Blockspielen):
// FPS, Frame-Zeit, Sim-Ticks/s, Draw Calls, Dreiecke, Entities, JS-Heap.

const UPDATE_INTERVAL_MS = 250;

// Nicht-Standard-API, nur in Chromium vorhanden.
interface PerformanceMemory {
  usedJSHeapSize: number;
}

export class DebugOverlay {
  private readonly element = document.getElementById("debug-overlay") as HTMLDivElement;
  private lastUpdate = 0;

  constructor() {
    document.addEventListener("keydown", (event) => {
      if (event.code === "F3") {
        event.preventDefault();
        this.element.hidden = !this.element.hidden;
      }
    });
  }

  /** Jeden Frame aufrufen — aktualisiert den Text aber nur alle 250 ms. */
  update(loop: GameLoop, sim: Sim, renderer: THREE.WebGLRenderer): void {
    if (this.element.hidden) return;
    const now = performance.now();
    if (now - this.lastUpdate < UPDATE_INTERVAL_MS) return;
    this.lastUpdate = now;

    const stats = loop.getStats();
    const memory = (performance as unknown as { memory?: PerformanceMemory }).memory;
    const heapLine = memory
      ? `heap      ${(memory.usedJSHeapSize / 1048576).toFixed(1)} MB`
      : "heap      n/a";

    this.element.textContent = [
      `fps       ${stats.fps.toFixed(0)}`,
      `frame     ${stats.frameMs.toFixed(2)} ms`,
      `sim       ${stats.simTicksPerSecond}/s (tick ${stats.simTicksTotal})`,
      `draws     ${renderer.info.render.calls}`,
      `tris      ${renderer.info.render.triangles}`,
      `entities  ${sim.entities.length}`,
      heapLine,
    ].join("\n");
  }
}
