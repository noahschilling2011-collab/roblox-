// Wellentabelle — DIE Tuning-Datei für Run-Länge und Schwierigkeit (Gate
// Phase 3: erster ernsthafter Run 3–6 Minuten, Tod knapp genug für
// "einmal noch"). Ab Welle 13 wird per Formel weiterskaliert.

import type { EnemyType } from "./enemies";

export interface WaveDef {
  rusher: number;
  shooter: number;
  tank: number;
}

export const WAVE_TABLE: WaveDef[] = [
  { rusher: 3, shooter: 0, tank: 0 }, // 1 — Aufwärmen
  { rusher: 5, shooter: 0, tank: 0 }, // 2
  { rusher: 4, shooter: 2, tank: 0 }, // 3 — Shooter kommen dazu
  { rusher: 6, shooter: 3, tank: 0 }, // 4
  { rusher: 5, shooter: 3, tank: 1 }, // 5 — erster Tank
  { rusher: 7, shooter: 4, tank: 1 }, // 6
  { rusher: 8, shooter: 5, tank: 2 }, // 7 — hier sterben Erstspieler meist
  { rusher: 9, shooter: 6, tank: 2 }, // 8
  { rusher: 10, shooter: 6, tank: 3 }, // 9
  { rusher: 11, shooter: 7, tank: 3 }, // 10
  { rusher: 12, shooter: 8, tank: 4 }, // 11
  { rusher: 13, shooter: 9, tank: 4 }, // 12
];

/** Welle n (1-basiert) — jenseits der Tabelle wird linear weiterskaliert. */
export function getWave(n: number): WaveDef {
  const idx = n - 1;
  const last = WAVE_TABLE[WAVE_TABLE.length - 1]!;
  if (idx < WAVE_TABLE.length) return WAVE_TABLE[idx]!;
  const extra = idx - WAVE_TABLE.length + 1;
  return {
    rusher: last.rusher + extra * 2,
    shooter: last.shooter + extra,
    tank: last.tank + Math.ceil(extra / 2),
  };
}

/** Leichte HP-Skalierung, damit späte Wellen nicht nur "mehr" sind. */
export function waveHpScale(n: number): number {
  return 1 + 0.05 * Math.max(0, n - 4);
}

/** Spawn-Tröpfeln: Abstand zwischen Einzel-Spawns in Sekunden. */
export const SPAWN_TRICKLE = 0.55;

export const SPAWN_ORDER: EnemyType[] = ["rusher", "shooter", "tank"];
