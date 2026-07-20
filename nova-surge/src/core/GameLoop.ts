// Fixed-Timestep-Gameloop: Simulation läuft mit konstanter Rate (SIM_HZ),
// Rendering läuft mit Monitor-Refreshrate und interpoliert per Alpha.
// Referenz-Muster: "Fix Your Timestep" (Accumulator).

export interface LoopCallbacks {
  /** Wird 0..n-mal pro Frame mit konstantem dt (Sekunden) aufgerufen. */
  simulate(dt: number): void;
  /** Wird 1x pro Frame aufgerufen. alpha = Anteil [0..1) zwischen letztem und nächstem Sim-Tick. */
  render(alpha: number): void;
}

export interface LoopStats {
  /** Geglättete Frames pro Sekunde (Rendering). */
  fps: number;
  /** Dauer des letzten Frames in Millisekunden. */
  frameMs: number;
  /** Gemessene Simulations-Ticks der letzten Sekunde. */
  simTicksPerSecond: number;
  /** Sim-Ticks insgesamt seit Start. */
  simTicksTotal: number;
}

// Frames länger als das werden gekappt (Tab-Wechsel, Ruckler) — verhindert
// die "Spiral of Death" aus immer mehr Nachhol-Ticks.
const MAX_FRAME_SECONDS = 0.25;

export class GameLoop {
  readonly simDt: number;

  private readonly callbacks: LoopCallbacks;
  private accumulator = 0;
  private lastFrameTime: number | null = null;
  private rafId = 0;
  private running = false;
  private paused = true;

  private stats: LoopStats = { fps: 0, frameMs: 0, simTicksPerSecond: 0, simTicksTotal: 0 };
  private tickWindowCount = 0;
  private tickWindowStart = 0;

  constructor(simHz: number, callbacks: LoopCallbacks) {
    this.simDt = 1 / simHz;
    this.callbacks = callbacks;
  }

  start(): void {
    if (this.running) return;
    this.running = true;
    this.lastFrameTime = null;
    this.rafId = requestAnimationFrame(this.onFrame);
  }

  stop(): void {
    this.running = false;
    cancelAnimationFrame(this.rafId);
  }

  /** Pausiert nur die Simulation — gerendert wird weiter (Menü liegt als DOM darüber). */
  setPaused(paused: boolean): void {
    if (this.paused === paused) return;
    this.paused = paused;
    if (!paused) {
      // Zeitsprung der Pause nicht als riesiges Frame-Delta verrechnen.
      this.lastFrameTime = null;
      this.accumulator = 0;
    }
  }

  isPaused(): boolean {
    return this.paused;
  }

  getStats(): Readonly<LoopStats> {
    return this.stats;
  }

  private onFrame = (now: number): void => {
    if (!this.running) return;
    this.rafId = requestAnimationFrame(this.onFrame);

    if (this.lastFrameTime === null) {
      this.lastFrameTime = now;
      this.tickWindowStart = now;
    }
    const frameSeconds = Math.min((now - this.lastFrameTime) / 1000, MAX_FRAME_SECONDS);
    this.lastFrameTime = now;

    this.stats.frameMs = frameSeconds * 1000;
    if (frameSeconds > 0) {
      const instantFps = 1 / frameSeconds;
      // Exponentielle Glättung, damit die Anzeige nicht flackert.
      this.stats.fps = this.stats.fps === 0 ? instantFps : this.stats.fps * 0.95 + instantFps * 0.05;
    }

    if (!this.paused) {
      this.accumulator += frameSeconds;
      while (this.accumulator >= this.simDt) {
        this.callbacks.simulate(this.simDt);
        this.accumulator -= this.simDt;
        this.stats.simTicksTotal++;
        this.tickWindowCount++;
      }
    }

    if (now - this.tickWindowStart >= 1000) {
      this.stats.simTicksPerSecond = this.tickWindowCount;
      this.tickWindowCount = 0;
      this.tickWindowStart = now;
    }

    this.callbacks.render(this.paused ? 0 : this.accumulator / this.simDt);
  };
}
