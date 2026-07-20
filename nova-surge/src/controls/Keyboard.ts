// Desktop-Eingabe: WASD + Shift (Sprint) + Space (Sprung) + R (Nachladen),
// Maustaste = Feuer. Schreibt ausschließlich in den InputState.

import type { InputState } from "../core/input";

export class Keyboard {
  private readonly input: InputState;
  private readonly held = new Set<string>();
  /** Nur wenn true (Pointer gelockt / Run aktiv) landen Eingaben in der Sim. */
  enabled = false;

  constructor(input: InputState) {
    this.input = input;
    document.addEventListener("keydown", (e) => {
      if (e.repeat) return;
      this.held.add(e.code);
      if (!this.enabled) return;
      if (e.code === "Space") {
        this.input.jumpQueued = true;
        e.preventDefault();
      }
      if (e.code === "KeyR") this.input.reloadQueued = true;
      this.apply();
    });
    document.addEventListener("keyup", (e) => {
      this.held.delete(e.code);
      this.apply();
    });
    document.addEventListener("mousedown", (e) => {
      if (this.enabled && e.button === 0) this.input.fire = true;
    });
    document.addEventListener("mouseup", (e) => {
      if (e.button === 0) this.input.fire = false;
    });
    // Fokusverlust: alles loslassen (sonst "klemmt" eine Taste)
    window.addEventListener("blur", () => this.releaseAll());
  }

  releaseAll(): void {
    this.held.clear();
    this.input.fire = false;
    this.apply();
  }

  private apply(): void {
    if (!this.enabled) {
      this.input.moveX = 0;
      this.input.moveZ = 0;
      this.input.sprint = false;
      return;
    }
    const left = this.held.has("KeyA") || this.held.has("ArrowLeft") ? 1 : 0;
    const right = this.held.has("KeyD") || this.held.has("ArrowRight") ? 1 : 0;
    const fwd = this.held.has("KeyW") || this.held.has("ArrowUp") ? 1 : 0;
    const back = this.held.has("KeyS") || this.held.has("ArrowDown") ? 1 : 0;
    this.input.moveX = right - left;
    this.input.moveZ = fwd - back;
    this.input.sprint = this.held.has("ShiftLeft") || this.held.has("ShiftRight");
  }
}
