// Navigations-Tuning (Multi-Level Phase 2). Der Waypoint-Graph wird beim
// Arena-Wechsel aus den Kollisions-Daten generiert — nichts pro Map hardcodiert.

export const NAV = {
  /** Raster-Abstand der Knoten in Metern. */
  cellSize: 1.6,
  /** Körper-Halbbreite für "hier kann jemand stehen" (deckt Tank 0,85 ab;
   *  der Warden braucht breite Wege — Map-Regel: Treppen/Gänge >= 3 m). */
  clearanceRadius: 0.6,
  /** Kopffreiheit über dem Knoten. Warden ist 3,0 m hoch — Map-Regel:
   *  über bossbegehbaren Wegen >= 3,2 m Luft lassen. */
  clearanceHeight: 2.2,
  /** Oberkanten über dieser Höhe sind Deko (Dach-Träger), keine Lauffläche. */
  maxNodeY: 12,
  /** Bis zu diesem Höhenunterschied sind Nachbarzellen direkt begehbar
   *  (muss unter der Step-Height 0,35 der Kollision liegen!). */
  stepTolerance: 0.34,
  /** Drop-Kanten: von oben nach unten bis zu dieser Höhe (kein Fallschaden). */
  dropMax: 6,
  /** Zusatzkosten pro Drop — Wege bevorzugen sanft die Treppe. */
  dropCost: 1.5,
  /** Ab diesem |Δy| Spieler<->Gegner wird gepfadet. Liegt bewusst ÜBER den
   *  1,1-m-Low-Blöcken: dort bleibt das alte Direkt-Steering + Rusher-Sprung. */
  levelThreshold: 1.4,
  /** Wegpunkt gilt als erreicht (horizontaler Abstand). */
  waypointReach: 1.0,
  /** Sekunden zwischen Pfad-Neuberechnungen pro Gegner (+ Zufalls-Jitter). */
  repathInterval: 0.7,
  /** Max. A*-Läufe pro Sim-Tick — Perf-Deckel, Rest wartet einen Tick. */
  repathBudget: 3,
  /** Pfadpuffer pro Gegner (längere Pfade werden gekappt und neu geplant). */
  maxPathNodes: 32,
  /** A*-Expansionsdeckel (Sicherheitsnetz gegen Worst-Case-Suchen). */
  maxExpand: 2500,
  /** Anteil der Spawns, die die Spieler-Ebene bevorzugen (60/40-Regel). */
  spawnSameLevelWeight: 0.6,
  /** |Δy|, bis zu dem ein Spawn als "gleiche Ebene" zählt. */
  spawnLevelTolerance: 1.5,
} as const;
