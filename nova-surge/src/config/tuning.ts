// Movement- und Game-Feel-Werte (Phase 1). Referenzgefühl: Krunker —
// schnell, direkt, sofortige Richtungswechsel. Alles hier, nichts hardcoden.

export const MOVE = {
  walkSpeed: 6.5, // m/s
  sprintSpeed: 9.0,
  accel: 60, // wie schnell die Zielgeschwindigkeit erreicht wird (hoch = direkt)
  airAccel: 18,
  friction: 10, // Abbremsen am Boden ohne Input
  gravity: 24,
  jumpVelocity: 8.2,
  playerRadius: 0.4, // Kollisions-Kapsel
  playerHeight: 1.7, // Augenhöhe
  coyoteTime: 0.1, // Sprung kurz nach Kantenverlassen noch erlaubt
} as const;

export const FEEL = {
  headBobFrequency: 9.5, // Hz bei vollem Lauftempo
  headBobAmplitude: 0.028, // Meter, vertikal
  headBobSway: 0.015, // Meter, horizontal
  baseFov: 78,
  sprintFovKick: 8, // Grad zusätzlich beim Sprinten
  fovLambda: 9, // wie schnell FOV nachzieht
  recoilRecoverLambda: 14, // Kamera-Kick-Erholung (höher = schneller zurück)
  landingDipAmount: 0.05, // Kamera-Dip bei Landung (Meter)
} as const;

export const PLAYER = {
  maxHp: 100,
  regenDelay: 4.0, // Sekunden ohne Schaden, bis Regeneration startet
  regenPerSecond: 12,
} as const;

// Erste Welle startet erst nach kurzer Schonfrist — Zeit zum Umsehen
// und Probeschießen ("Schießstand-Moment", zahlt auf Conversion ein).
export const RUN = {
  firstWaveDelay: 6.0, // Sekunden
  waveBreak: 5.0, // Pause zwischen Wellen
} as const;
