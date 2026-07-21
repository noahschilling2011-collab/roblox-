// Wellen-Spawner: arbeitet die Tabelle aus config/waves.ts ab und tröpfelt
// Gegner an den vier Toren ein — nie direkt neben dem Spieler.

import { ELITE_RULES, ENEMY_AI, type EliteType, type EnemyType } from "../config/enemies";
import { NAV } from "../config/nav";
import { applyWaveEvent, getWave, isBossWave, SPAWN_TRICKLE, type WaveEventId } from "../config/waves";
import type { EnemyManager } from "./Enemy";
import type { Vec3 } from "./math";

const MIN_SPAWN_DIST = 14; // Meter Abstand zum Spieler beim Spawnen

export class WaveSpawner {
  private pendingRusher = 0;
  private pendingShooter = 0;
  private pendingTank = 0;
  private pendingWarden = 0;
  private spawnTimer = 0;
  private nextTypeIdx = 0;

  private waveNumber = 1;
  private wardensSpawned = 0;

  start(waveNumber: number, event: WaveEventId | null = null): void {
    this.waveNumber = waveNumber;
    const w = applyWaveEvent(getWave(waveNumber), event);
    this.pendingRusher = w.rusher;
    this.pendingShooter = w.shooter;
    this.pendingTank = w.tank;
    this.pendingWarden = w.warden ?? 0;
    this.wardensSpawned = 0;
    // Boss-Inszenierung: 1 s Vorlauf für "WARDEN INBOUND" + Warn-Marker
    this.spawnTimer = isBossWave(waveNumber) ? 1.0 : 0.5;
    this.nextTypeIdx = 0;
  }

  /** Elite-Chance dieser Welle (ab Welle 6, 5% -> 25%). */
  private rollElite(type: EnemyType): EliteType | null {
    if (type === "warden") {
      // Bosse: der ZWEITE Warden einer Welle kommt als Elite (Qualität statt Masse)
      if (this.wardensSpawned >= 1) {
        const pool: EliteType[] = ["swift", "armored", "volatile", "vampiric"];
        return pool[Math.floor(Math.random() * pool.length)]!;
      }
      return null;
    }
    if (this.waveNumber < ELITE_RULES.startWave) return null;
    const chance = Math.min(
      ELITE_RULES.chanceCap,
      ELITE_RULES.chanceBase + ELITE_RULES.chancePerWave * (this.waveNumber - ELITE_RULES.startWave)
    );
    if (Math.random() >= chance) return null;
    const pool: EliteType[] = ["swift", "armored", "volatile", "vampiric"];
    return pool[Math.floor(Math.random() * pool.length)]!;
  }

  clear(): void {
    this.pendingRusher = this.pendingShooter = this.pendingTank = this.pendingWarden = 0;
  }

  pendingCount(): number {
    return this.pendingRusher + this.pendingShooter + this.pendingTank + this.pendingWarden;
  }

  update(
    dt: number,
    enemies: EnemyManager,
    playerPos: Vec3,
    waveNumber: number,
    spawns: readonly { x: number; z: number; y?: number }[]
  ): void {
    if (this.pendingCount() === 0) return;
    if (enemies.aliveCount() >= ENEMY_AI.maxAlive) return;
    this.spawnTimer -= dt;
    if (this.spawnTimer > 0) return;
    this.spawnTimer = SPAWN_TRICKLE;

    const type = this.pickType();
    if (!type) return;

    // 60/40-Regel (Multi-Level Phase 2): 60% der Spawns bevorzugen die
    // Spieler-Ebene (Druck bleibt oben), 40% andere Ebenen (Flanken).
    // Auf flachen Maps sind alle Spawns "gleiche Ebene" -> Verhalten wie bisher.
    const preferSame = Math.random() < NAV.spawnSameLevelWeight;
    // Spawnpunkt: rotierend, aber nicht direkt beim Spieler; Pass 0 filtert
    // nach Ebenen-Präferenz, Pass 1 nimmt jeden ausreichend fernen Punkt.
    for (let pass = 0; pass < 2; pass++) {
      for (let attempt = 0; attempt < spawns.length; attempt++) {
        const sp = spawns[(this.nextTypeIdx + attempt) % spawns.length]!;
        if (pass === 0) {
          const sameLevel = Math.abs((sp.y ?? 0) - playerPos.y) < NAV.spawnLevelTolerance;
          if (sameLevel !== preferSame) continue;
        }
        const dx = sp.x - playerPos.x;
        const dz = sp.z - playerPos.z;
        if (dx * dx + dz * dz < MIN_SPAWN_DIST * MIN_SPAWN_DIST) continue;
        if (
          enemies.spawn(
            type,
            sp.x + (Math.random() - 0.5) * 2,
            sp.z + (Math.random() - 0.5) * 2,
            waveNumber,
            this.rollElite(type),
            sp.y ?? 0
          )
        ) {
          this.decrement(type);
          if (type === "warden") this.wardensSpawned++;
          this.nextTypeIdx++;
        }
        return;
      }
    }
    // Alle Tore zu nah (Spieler campt ein Tor): nimm das gegenüberliegende
    const far = spawns.reduce((best, sp) => {
      const d = (sp.x - playerPos.x) ** 2 + (sp.z - playerPos.z) ** 2;
      const bd = (best.x - playerPos.x) ** 2 + (best.z - playerPos.z) ** 2;
      return d > bd ? sp : best;
    });
    if (enemies.spawn(type, far.x, far.z, waveNumber, this.rollElite(type), far.y ?? 0)) {
      this.decrement(type);
      if (type === "warden") this.wardensSpawned++;
    }
  }

  /** Mischt die Typen: Boss zuerst (großer Auftritt), dann Rusher-lastig. */
  private pickType(): EnemyType | null {
    if (this.pendingWarden > 0) return "warden";
    const order: EnemyType[] = ["rusher", "shooter", "rusher", "tank"];
    for (let i = 0; i < order.length; i++) {
      const t = order[(this.nextTypeIdx + i) % order.length]!;
      if (t === "rusher" && this.pendingRusher > 0) return t;
      if (t === "shooter" && this.pendingShooter > 0) return t;
      if (t === "tank" && this.pendingTank > 0) return t;
    }
    if (this.pendingRusher > 0) return "rusher";
    if (this.pendingShooter > 0) return "shooter";
    if (this.pendingTank > 0) return "tank";
    return null;
  }

  private decrement(type: EnemyType): void {
    if (type === "rusher") this.pendingRusher--;
    else if (type === "shooter") this.pendingShooter--;
    else if (type === "warden") this.pendingWarden--;
    else this.pendingTank--;
  }
}
