// Simulationszustand, komplett getrennt vom Rendering.
// Phase 0: nur Tick-Zähler und eine (noch leere) Entity-Liste,
// damit das Debug-Overlay echte Zahlen anzeigen kann.

export class Sim {
  /** Anzahl ausgeführter Simulations-Ticks seit Start. */
  tick = 0;
  /** Aktive Spielobjekte (Gegner, Projektile, ...) — ab Phase 1/2 gefüllt. */
  readonly entities: unknown[] = [];

  update(_dt: number): void {
    this.tick++;
  }
}
