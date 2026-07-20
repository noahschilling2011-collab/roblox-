// Sim -> Präsentation: Ereignis-Ringpuffer mit festen Slots.
// Sound, Partikel, HUD-Effekte reagieren auf diese Events, ohne dass die
// Simulation Rendering kennt. Feste Slots = keine Allokationen im Loop.

export const enum Ev {
  Shot, // Waffe abgefeuert: x,y,z = Mündungs-Blickpunkt (Kick/Sound/Flash)
  Tracer, // pro Strahl/Pellet: x,y,z = Endpunkt, a = 1 wenn Gegner getroffen
  DamageDealt, // a = Schaden, b = 1 wenn Kill (Hitmarker/Tick)
  EnemyDied, // x,y,z, a = EnemyType-Index, b = Score-Gewinn
  EnemyShot, // Shooter feuert: x,y,z (Sound räumlich leiser nach Distanz)
  PlayerHurt, // a = Schaden, b = Winkel zur Quelle relativ zur Blickrichtung
  PlayerDied,
  ReloadStart,
  DryFire,
  Jump,
  Land, // a = Fallgeschwindigkeit
  WaveStart, // a = Wellennummer
  WaveCleared, // a = Wellennummer
  MeleeHit, // Gegner-Nahkampf trifft: x,y,z
  Heal, // a = Menge (Lifesteal-Feedback)
  NewHighscore,
}

export interface EventSlot {
  type: Ev;
  x: number;
  y: number;
  z: number;
  a: number;
  b: number;
}

const CAPACITY = 256;

export class EventQueue {
  private readonly slots: EventSlot[] = [];
  count = 0;

  constructor() {
    for (let i = 0; i < CAPACITY; i++) {
      this.slots.push({ type: Ev.Shot, x: 0, y: 0, z: 0, a: 0, b: 0 });
    }
  }

  emit(type: Ev, x = 0, y = 0, z = 0, a = 0, b = 0): void {
    if (this.count >= CAPACITY) return; // Überlauf: Event verwerfen statt allozieren
    const s = this.slots[this.count++]!;
    s.type = type;
    s.x = x;
    s.y = y;
    s.z = z;
    s.a = a;
    s.b = b;
  }

  get(i: number): EventSlot {
    return this.slots[i]!;
  }

  /** Nach der Präsentation jedes Frames aufrufen. */
  clear(): void {
    this.count = 0;
  }
}
