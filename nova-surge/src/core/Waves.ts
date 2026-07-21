// Wellen-Spawner: arbeitet die Tabelle aus config/waves.ts ab und tröpfelt
// Gegner an den vier Toren ein — nie direkt neben dem Spieler.

import { ENEMY_AI, type EnemyType } from "../config/enemies";
import { getWave, SPAWN_TRICKLE } from "../config/waves";
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

  start(waveNumber: number): void {
    const w = getWave(waveNumber);
    this.pendingRusher = w.rusher;
    this.pendingShooter = w.shooter;
    this.pendingTank = w.tank;
    this.pendingWarden = w.warden ?? 0;
    this.spawnTimer = 0.5;
    this.nextTypeIdx = 0;
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
    spawns: readonly { x: number; z: number }[]
  ): void {
    if (this.pendingCount() === 0) return;
    if (enemies.aliveCount() >= ENEMY_AI.maxAlive) return;
    this.spawnTimer -= dt;
    if (this.spawnTimer > 0) return;
    this.spawnTimer = SPAWN_TRICKLE;

    const type = this.pickType();
    if (!type) return;

    // Spawnpunkt: rotierend, aber nicht direkt beim Spieler
    for (let attempt = 0; attempt < spawns.length; attempt++) {
      const sp = spawns[(this.nextTypeIdx + attempt) % spawns.length]!;
      const dx = sp.x - playerPos.x;
      const dz = sp.z - playerPos.z;
      if (dx * dx + dz * dz < MIN_SPAWN_DIST * MIN_SPAWN_DIST) continue;
      if (enemies.spawn(type, sp.x + (Math.random() - 0.5) * 2, sp.z + (Math.random() - 0.5) * 2, waveNumber)) {
        this.decrement(type);
        this.nextTypeIdx++;
      }
      return;
    }
    // Alle Tore zu nah (Spieler campt ein Tor): nimm das gegenüberliegende
    const far = spawns.reduce((best, sp) => {
      const d = (sp.x - playerPos.x) ** 2 + (sp.z - playerPos.z) ** 2;
      const bd = (best.x - playerPos.x) ** 2 + (best.z - playerPos.z) ** 2;
      return d > bd ? sp : best;
    });
    if (enemies.spawn(type, far.x, far.z, waveNumber)) this.decrement(type);
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
