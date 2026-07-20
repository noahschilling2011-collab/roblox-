// Start-/Pause-Menü + Pointer-Lock-Verwaltung.
// Regel: Simulation läuft genau dann, wenn der Pointer gelockt ist.
// ESC löst den Lock (Browser-Verhalten) -> Menü erscheint, Spiel pausiert.

export interface PauseMenuCallbacks {
  onResume(): void;
  onPause(): void;
}

export class PauseMenu {
  private readonly lockTarget: HTMLElement;
  private readonly callbacks: PauseMenuCallbacks;
  private readonly overlay = document.getElementById("menu-overlay") as HTMLDivElement;
  private readonly button = document.getElementById("menu-button") as HTMLButtonElement;
  private readonly subtitle = document.getElementById("menu-subtitle") as HTMLParagraphElement;
  private started = false;

  constructor(lockTarget: HTMLElement, callbacks: PauseMenuCallbacks) {
    this.lockTarget = lockTarget;
    this.callbacks = callbacks;

    this.button.addEventListener("click", () => this.requestLock());
    document.addEventListener("pointerlockchange", this.onLockChange);
    document.addEventListener("pointerlockerror", this.onLockError);
  }

  isLocked(): boolean {
    return document.pointerLockElement === this.lockTarget;
  }

  private requestLock(): void {
    // Chrome liefert ein Promise und wirft z.B. während der ~1s-Sperre
    // direkt nach einem ESC-Unlock. Firefox liefert undefined + error-Event.
    try {
      const result = this.lockTarget.requestPointerLock() as unknown;
      if (result instanceof Promise) {
        result.catch(() => this.showRetryHint());
      }
    } catch {
      this.showRetryHint();
    }
  }

  private onLockChange = (): void => {
    if (this.isLocked()) {
      this.started = true;
      this.overlay.hidden = true;
      this.callbacks.onResume();
    } else {
      this.showPaused();
      this.callbacks.onPause();
    }
  };

  private onLockError = (): void => {
    this.showRetryHint();
  };

  private showPaused(): void {
    if (!this.started) return;
    this.overlay.hidden = false;
    this.button.textContent = "RESUME";
    this.subtitle.textContent = "Paused";
  }

  private showRetryHint(): void {
    this.overlay.hidden = false;
    // Browser blockt Pointer Lock kurz nach ESC — einfach nochmal klicken.
    this.subtitle.textContent = "One moment — click again!";
  }
}
