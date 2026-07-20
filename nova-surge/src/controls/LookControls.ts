// Maus-Look bei aktivem Pointer Lock. Schreibt Yaw/Pitch in den InputState —
// die Kamera liest daraus (CameraRig), die Sim nutzt dieselben Winkel zum
// Schießen. Eine Quelle der Wahrheit für die Blickrichtung.

import type { InputState } from "../core/input";

const SENSITIVITY = 0.0022;
const MAX_PITCH = Math.PI / 2 - 0.01;

export class LookControls {
  private readonly input: InputState;
  enabled = false;

  constructor(input: InputState) {
    this.input = input;
    document.addEventListener("mousemove", (event) => {
      if (!this.enabled) return;
      this.input.yaw -= event.movementX * SENSITIVITY;
      this.input.pitch -= event.movementY * SENSITIVITY;
      if (this.input.pitch > MAX_PITCH) this.input.pitch = MAX_PITCH;
      if (this.input.pitch < -MAX_PITCH) this.input.pitch = -MAX_PITCH;
    });
  }
}
