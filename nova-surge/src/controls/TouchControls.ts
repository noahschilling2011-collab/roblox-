// Touch-Steuerung (Phase 5): linke Bildschirmhälfte = virtueller Move-Stick
// (erscheint am Touchpunkt), rechte Hälfte = Blick per Drag. Feuern in zwei
// Varianten (Auto-Fire bei Ziel unterm Fadenkreuz ODER Feuer-Button) —
// umschaltbar im Menü, Endauswahl trifft der Playtest (siehe STATUS.md).

import type { InputState } from "../core/input";

const STICK_RADIUS = 55; // px, entspricht #stick-base
const LOOK_SENSITIVITY = 0.0042;
const MAX_PITCH = Math.PI / 2 - 0.01;

export function isTouchDevice(): boolean {
  return window.matchMedia("(pointer: coarse)").matches || "ontouchstart" in window;
}

export class TouchControls {
  private readonly input: InputState;
  enabled = false;
  /** Auto-Fire-Modus (aus SaveData); der Feuer-Button funktioniert immer. */
  autoFire = true;
  /** Wird von der Sim gesetzt: Fadenkreuz liegt auf Gegner. */
  aimOnTarget = false;
  /** Aktuelle Waffe ist Dauerfeuer (sonst braucht Auto-Fire Puls-Flanken). */
  weaponIsAuto = true;

  private moveTouchId: number | null = null;
  private lookTouchId: number | null = null;
  private stickOriginX = 0;
  private stickOriginY = 0;
  private fireHeld = false;

  private readonly ui = document.getElementById("touch-ui") as HTMLDivElement;
  private readonly stickBase = document.getElementById("stick-base") as HTMLDivElement;
  private readonly stickNub = document.getElementById("stick-nub") as HTMLDivElement;

  constructor(input: InputState) {
    this.input = input;

    const surface = document.getElementById("game-canvas") as HTMLCanvasElement;
    surface.addEventListener("touchstart", this.onTouchStart, { passive: false });
    surface.addEventListener("touchmove", this.onTouchMove, { passive: false });
    surface.addEventListener("touchend", this.onTouchEnd);
    surface.addEventListener("touchcancel", this.onTouchEnd);

    this.bindButton("btn-fire", (down) => {
      this.fireHeld = down;
    });
    this.bindButton("btn-jump", (down) => {
      if (down) this.input.jumpQueued = true;
    });
    this.bindButton("btn-touch-reload", (down) => {
      if (down) this.input.reloadQueued = true;
    });
  }

  showUi(visible: boolean): void {
    this.ui.hidden = !visible;
    if (!visible) this.resetTouches();
  }

  /** Pro Sim-Tick: Auto-Fire anwenden. */
  update(): void {
    if (!this.enabled) return;
    if (this.fireHeld) {
      this.input.fire = true;
    } else if (this.autoFire && this.aimOnTarget) {
      // Semi-Waffen (Scatter/DMR) feuern nur auf Flanke: Puls statt Dauer-True,
      // sonst schießt Auto-Fire genau einmal und dann nie wieder.
      this.input.fire = this.weaponIsAuto ? true : !this.input.fire;
    } else {
      this.input.fire = false;
    }
  }

  private bindButton(id: string, handler: (down: boolean) => void): void {
    const btn = document.getElementById(id) as HTMLButtonElement;
    btn.addEventListener("touchstart", (e) => {
      e.preventDefault();
      if (this.enabled) handler(true);
    });
    btn.addEventListener("touchend", (e) => {
      e.preventDefault();
      handler(false);
    });
    btn.addEventListener("touchcancel", () => handler(false));
  }

  private onTouchStart = (e: TouchEvent): void => {
    if (!this.enabled) return;
    e.preventDefault();
    for (const t of Array.from(e.changedTouches)) {
      if (t.clientX < window.innerWidth / 2 && this.moveTouchId === null) {
        this.moveTouchId = t.identifier;
        this.stickOriginX = t.clientX;
        this.stickOriginY = t.clientY;
        this.stickBase.hidden = false;
        this.stickBase.style.left = `${t.clientX}px`;
        this.stickBase.style.top = `${t.clientY}px`;
        this.setNub(0, 0);
      } else if (this.lookTouchId === null) {
        this.lookTouchId = t.identifier;
        this.lastLookX = t.clientX;
        this.lastLookY = t.clientY;
      }
    }
  };

  private lastLookX = 0;
  private lastLookY = 0;

  private onTouchMove = (e: TouchEvent): void => {
    if (!this.enabled) return;
    e.preventDefault();
    for (const t of Array.from(e.changedTouches)) {
      if (t.identifier === this.moveTouchId) {
        let dx = t.clientX - this.stickOriginX;
        let dy = t.clientY - this.stickOriginY;
        const len = Math.hypot(dx, dy);
        if (len > STICK_RADIUS) {
          dx = (dx / len) * STICK_RADIUS;
          dy = (dy / len) * STICK_RADIUS;
        }
        this.setNub(dx, dy);
        this.input.moveX = dx / STICK_RADIUS;
        this.input.moveZ = -dy / STICK_RADIUS;
        // Stick voll ausgelenkt = Sprint (kein extra Button nötig)
        this.input.sprint = len >= STICK_RADIUS * 0.95;
      } else if (t.identifier === this.lookTouchId) {
        const dx = t.clientX - this.lastLookX;
        const dy = t.clientY - this.lastLookY;
        this.lastLookX = t.clientX;
        this.lastLookY = t.clientY;
        this.input.yaw -= dx * LOOK_SENSITIVITY;
        this.input.pitch -= dy * LOOK_SENSITIVITY;
        if (this.input.pitch > MAX_PITCH) this.input.pitch = MAX_PITCH;
        if (this.input.pitch < -MAX_PITCH) this.input.pitch = -MAX_PITCH;
      }
    }
  };

  private onTouchEnd = (e: TouchEvent): void => {
    for (const t of Array.from(e.changedTouches)) {
      if (t.identifier === this.moveTouchId) {
        this.moveTouchId = null;
        this.stickBase.hidden = true;
        this.input.moveX = 0;
        this.input.moveZ = 0;
        this.input.sprint = false;
      } else if (t.identifier === this.lookTouchId) {
        this.lookTouchId = null;
      }
    }
  };

  private setNub(dx: number, dy: number): void {
    this.stickNub.style.transform = `translate(${dx}px, ${dy}px)`;
  }

  private resetTouches(): void {
    this.moveTouchId = null;
    this.lookTouchId = null;
    this.stickBase.hidden = true;
    this.fireHeld = false;
    this.input.moveX = 0;
    this.input.moveZ = 0;
    this.input.sprint = false;
    this.input.fire = false;
  }
}
