// Eingabezustand — die einzige Schnittstelle zwischen Controls und Simulation.
// Desktop (Tastatur/Maus) und Touch schreiben beide in dieses Objekt.

export interface InputState {
  moveX: number; // -1..1 (links/rechts)
  moveZ: number; // -1..1 (vor/zurück, vor = -1? nein: vor = +1)
  sprint: boolean;
  jumpQueued: boolean; // wird von der Sim konsumiert (Edge-Trigger)
  fire: boolean; // gehalten
  reloadQueued: boolean; // Edge-Trigger
  yaw: number; // Blickrichtung (Radiant), von Look-Controls geschrieben
  pitch: number;
}

export function createInput(): InputState {
  return {
    moveX: 0,
    moveZ: 0,
    sprint: false,
    jumpQueued: false,
    fire: false,
    reloadQueued: false,
    yaw: 0,
    pitch: 0,
  };
}
