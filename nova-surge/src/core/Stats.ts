// Zentrales Run-Stats-Objekt (RC Phase 1): EIN Ort, an dem alle Upgrade-
// Effekte landen. Waffe, Spieler und Sim lesen NUR von hier — keine
// verstreute Effekt-Logik. Wird von UpgradeState.apply() komplett neu
// berechnet (idempotent, stapel-sicher).

export class RunStats {
  // Multiplikatoren
  damageMult = 1;
  fireRateMult = 1;
  magSizeMult = 1;
  reloadMult = 1; // < 1 = schneller
  moveSpeedMult = 1;
  damageTakenMult = 1; // < 1 = Panzerung
  scoreMult = 1;
  // Chancen / Beträge
  lifesteal = 0;
  critChance = 0;
  scavengerChance = 0;
  adrenalineDuration = 0; // 0 = Upgrade nicht gewählt
  // Rare-Verhalten
  pierceTargets = 0; // zusätzliche Hitscan-Ziele
  ricochetBounces = 0;
  shatterCount = 0;
  thornsPct = 0;
  overkillHealPct = 0;
  coldbloodBonus = 0;
  laststandBonus = 0;
  comboHoldBonus = 0; // Sekunden extra Combo-Haltezeit
  // Epics
  chainEnabled = false;
  extraProjectiles = 0;
  bullettimeEnabled = false;
  phoenixCharges = 0;
  // Bewegung
  hasDoubleJump = false;
  /** Dynamisch pro Tick von der Sim gesetzt (Last Stand aktiv?). */
  laststandActive = false;

  reset(): void {
    this.damageMult = 1;
    this.fireRateMult = 1;
    this.magSizeMult = 1;
    this.reloadMult = 1;
    this.moveSpeedMult = 1;
    this.damageTakenMult = 1;
    this.scoreMult = 1;
    this.lifesteal = 0;
    this.critChance = 0;
    this.scavengerChance = 0;
    this.adrenalineDuration = 0;
    this.pierceTargets = 0;
    this.ricochetBounces = 0;
    this.shatterCount = 0;
    this.thornsPct = 0;
    this.overkillHealPct = 0;
    this.coldbloodBonus = 0;
    this.laststandBonus = 0;
    this.comboHoldBonus = 0;
    this.chainEnabled = false;
    this.extraProjectiles = 0;
    this.bullettimeEnabled = false;
    this.phoenixCharges = 0;
    this.hasDoubleJump = false;
    this.laststandActive = false;
  }
}
