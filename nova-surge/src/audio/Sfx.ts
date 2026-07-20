// Kompletter Spiel-Sound, 100% prozedural über WebAudio — kein einziges
// Audio-File (Constraint). Ein geteilter Noise-Buffer + kurzlebige
// Oszillatoren/BufferSources pro Ereignis, alles über einen Kompressor.

import type { WeaponDef } from "../config/weapons";

export class Sfx {
  private ctx: AudioContext | null = null;
  private master: GainNode | null = null;
  private noiseBuffer: AudioBuffer | null = null;

  /** Muss aus einer User-Geste heraus aufgerufen werden (Browser-Autoplay-Regel). */
  init(): void {
    if (this.ctx) {
      if (this.ctx.state === "suspended") void this.ctx.resume();
      return;
    }
    this.ctx = new AudioContext();
    const comp = this.ctx.createDynamicsCompressor();
    comp.threshold.value = -18;
    comp.ratio.value = 6;
    comp.connect(this.ctx.destination);
    this.master = this.ctx.createGain();
    this.master.gain.value = 0.55;
    this.master.connect(comp);
    // 1 s weißes Rauschen, wird von allen Noise-Sounds geteilt
    const len = this.ctx.sampleRate;
    this.noiseBuffer = this.ctx.createBuffer(1, len, this.ctx.sampleRate);
    const data = this.noiseBuffer.getChannelData(0);
    for (let i = 0; i < len; i++) data[i] = Math.random() * 2 - 1;
  }

  /** Für Ad-Pausen (CrazyGames-Vorgabe: Audio stumm, solange die Ad läuft). */
  setMuted(muted: boolean): void {
    if (this.master) this.master.gain.value = muted ? 0 : 0.55;
  }

  private noise(duration: number, filterFreq: number, gain: number, pitch = 1, filterSweepTo = 0): void {
    if (!this.ctx || !this.master || !this.noiseBuffer) return;
    const t = this.ctx.currentTime;
    const src = this.ctx.createBufferSource();
    src.buffer = this.noiseBuffer;
    src.playbackRate.value = pitch;
    const filter = this.ctx.createBiquadFilter();
    filter.type = "lowpass";
    filter.frequency.setValueAtTime(filterFreq, t);
    if (filterSweepTo > 0) filter.frequency.exponentialRampToValueAtTime(filterSweepTo, t + duration);
    const g = this.ctx.createGain();
    g.gain.setValueAtTime(gain, t);
    g.gain.exponentialRampToValueAtTime(0.001, t + duration);
    src.connect(filter).connect(g).connect(this.master);
    src.start(t, Math.random() * 0.5, duration + 0.05);
  }

  private tone(
    freq: number,
    duration: number,
    gain: number,
    type: OscillatorType = "sine",
    sweepTo = 0,
    delay = 0
  ): void {
    if (!this.ctx || !this.master) return;
    const t = this.ctx.currentTime + delay;
    const osc = this.ctx.createOscillator();
    osc.type = type;
    osc.frequency.setValueAtTime(freq, t);
    if (sweepTo > 0) osc.frequency.exponentialRampToValueAtTime(sweepTo, t + duration);
    const g = this.ctx.createGain();
    g.gain.setValueAtTime(gain, t);
    g.gain.exponentialRampToValueAtTime(0.001, t + duration);
    osc.connect(g).connect(this.master);
    osc.start(t);
    osc.stop(t + duration + 0.02);
  }

  // ---- Waffen ----

  shot(def: WeaponDef): void {
    // Knall: Noise-Burst mit Lowpass-Sweep + Bass-Punch, Charakter aus der Config
    const p = def.soundPitch;
    this.noise(0.09 / p, 5200 * p, 0.5, 1.6 * p, 380);
    this.tone(150 * p, 0.1, 0.5 * def.soundBody, "triangle", 55 * p);
    if (def.soundBody > 0.8) this.noise(0.22 / p, 900, 0.35, 0.8 * p, 120); // Wumms für Shotgun/DMR
  }

  dryFire(): void {
    this.tone(1900, 0.03, 0.12, "square");
  }

  reload(duration: number): void {
    // zwei mechanische Klicks: Magazin raus / rein
    this.noise(0.04, 2600, 0.2, 2.4);
    if (!this.ctx) return;
    this.tone(320, 0.05, 0.18, "square", 0, duration * 0.55);
    this.tone(480, 0.05, 0.2, "square", 0, duration * 0.85);
  }

  // ---- Treffer-Feedback ----

  hitTick(): void {
    this.tone(2300, 0.045, 0.16, "square", 1600);
  }

  killConfirm(): void {
    this.tone(1500, 0.07, 0.2, "square", 900);
    this.tone(750, 0.12, 0.18, "triangle", 500, 0.05);
  }

  // ---- Gegner / Spieler ----

  enemyShot(distance: number): void {
    const vol = Math.max(0.05, 0.28 - distance * 0.004);
    this.noise(0.08, 2400, vol, 1.1, 300);
  }

  meleeHit(): void {
    this.noise(0.12, 700, 0.4, 0.7);
    this.tone(90, 0.14, 0.4, "sine", 45);
  }

  playerHurt(): void {
    this.tone(140, 0.18, 0.4, "sawtooth", 70);
  }

  playerDied(): void {
    this.tone(300, 0.7, 0.3, "sawtooth", 60);
    this.tone(150, 0.9, 0.25, "triangle", 40, 0.15);
  }

  heal(): void {
    this.tone(900, 0.08, 0.06, "sine", 1300);
  }

  jump(): void {
    this.tone(300, 0.08, 0.08, "sine", 480);
  }

  land(intensity: number): void {
    this.noise(0.07, 500, Math.min(0.25, intensity * 0.02), 0.8);
  }

  // ---- Spielfluss ----

  waveStart(): void {
    this.tone(440, 0.12, 0.22, "square", 0, 0);
    this.tone(660, 0.18, 0.22, "square", 0, 0.13);
  }

  waveCleared(): void {
    this.tone(523, 0.1, 0.2, "triangle", 0, 0);
    this.tone(659, 0.1, 0.2, "triangle", 0, 0.09);
    this.tone(784, 0.2, 0.22, "triangle", 0, 0.18);
  }

  upgradePicked(): void {
    this.tone(660, 0.09, 0.2, "triangle", 0, 0);
    this.tone(990, 0.16, 0.2, "triangle", 0, 0.08);
  }

  uiClick(): void {
    this.tone(700, 0.04, 0.12, "square");
  }

  newHighscore(): void {
    this.tone(523, 0.1, 0.2, "triangle", 0, 0);
    this.tone(659, 0.1, 0.2, "triangle", 0, 0.1);
    this.tone(784, 0.1, 0.2, "triangle", 0, 0.2);
    this.tone(1046, 0.3, 0.24, "triangle", 0, 0.3);
  }
}
