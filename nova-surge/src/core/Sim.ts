// Die komplette Spiel-Simulation: Run-Phasen, Spieler, Waffe, Gegner,
// Projektile, Wellen, Score. Läuft mit festem 60-Hz-Takt, kennt kein
// Rendering — die Präsentation liest Zustand + Events.

import { COMBO, PLAYER, REROLL, RUN } from "../config/tuning";
import { PERK_VALUES } from "../config/meta";
import { UPGRADES } from "../config/upgrades";
import type { PerkLevels } from "../meta/SaveData";
import { EVENT_RULES, isBossWave, type WaveEventId } from "../config/waves";
import { ELITE_RULES } from "../config/enemies";
import { ARENAS, type ArenaDef } from "../config/arena";
import { COIN_DIVISOR } from "../config/meta";
import type { WeaponId } from "../config/weapons";
import { VALUES, type UpgradeId } from "../config/upgrades";
import { RunStats } from "./Stats";
import { ENEMY_TYPE_INDEX, EnemyManager, type Enemy } from "./Enemy";
import { EventQueue, Ev } from "./events";
import { buildCollisionWorld } from "./collision";
import { NavSystem } from "./Nav";
import { PickupManager } from "./Pickups";
import type { InputState } from "./input";
import { rayVsAabb, rayVsSphere, vec3, type Vec3 } from "./math";
import { Player } from "./Player";
import { Projectiles, type ProjectileSlot } from "./Projectiles";
import { UpgradeState } from "./Upgrades";
import { WaveSpawner } from "./Waves";
import { Weapon } from "./Weapon";

export type RunPhase = "menu" | "prewave" | "wave" | "upgrade" | "break" | "dead";

const MULTIPLIER_PER_HIT = 0.1;
const MULTIPLIER_MAX = 5;
const _eye = vec3();
const _hitPoint = vec3();

export class Sim {
  arena: ArenaDef = ARENAS[0]!;
  world = buildCollisionWorld(this.arena);
  /** Wegpunkt-Navigation (Multi-Level Phase 2), pro Arena neu gebaut. */
  nav = new NavSystem(this.arena, this.world);
  readonly player = new Player();
  readonly weapon = new Weapon();
  readonly enemies = new EnemyManager();
  readonly projectiles = new Projectiles();
  readonly spawner = new WaveSpawner();
  readonly pickups = new PickupManager();
  readonly upgrades = new UpgradeState();
  readonly events = new EventQueue();
  readonly stats = new RunStats();

  tick = 0;
  phase: RunPhase = "menu";
  phaseTimer = 0;
  waveNumber = 0;
  score = 0;
  multiplier = 1;
  kills = 0;
  coinsEarned = 0;
  /** Coin-Stash-Pickups: zusätzliche Run-Coins (zählen am Run-Ende dazu). */
  bonusCoins = 0;
  /** Supply-Crate-Draft: Phase, in die chooseUpgrade() danach zurückkehrt. */
  private supplyReturnPhase: RunPhase | null = null;
  /** Angebot für die 1-aus-3-Wahl (gefüllt beim Wellenende). */
  upgradeOffer: UpgradeId[] = [];
  /** true, wenn das Fadenkreuz gerade auf einem Gegner liegt (Mobile-Auto-Fire). */
  aimOnTarget = false;
  /** Einmal pro Run: Revive über Rewarded Ad (Phase 6). */
  reviveUsed = false;
  /** Vom Pellet-Raycast getroffener Gegner (hitTest -> onHit, gleicher Tick). */
  private pelletTarget: Enemy | null = null;
  /** Schaden, den der Spieler in der laufenden Welle kassiert hat (Perfect Wave). */
  private damageTakenThisWave = 0;
  /** Combo-Verfall: Sekunden seit dem letzten eigenen Treffer. */
  private sinceLastHit = 999;
  /** Kettenblitz: zählt eigene Treffer. */
  private hitCounter = 0;
  /** Reroll-Kosten (verdoppeln sich pro Nutzung im Run). */
  rerollCost: number = REROLL.baseCost;
  /** Ändert sich bei jedem neuen Angebot (HUD baut Karten neu). */
  offerNonce = 0;
  /** Aktives Wave-Event dieser Welle (RC Phase 2) oder null. */
  currentEvent: WaveEventId | null = null;
  /** Test-Hook: erzwingt das Event der nächsten Welle. */
  forcedEvent: WaveEventId | null = null;
  private nextEventWave = 0;

  private readonly input: InputState;

  constructor(input: InputState) {
    this.input = input;
    this.weapon.stats = this.stats; // eine gemeinsame Stats-Instanz
  }

  entityCount(): number {
    let n = 0;
    for (const e of this.enemies.slots) if (e.active) n++;
    for (const p of this.projectiles.slots) if (p.active) n++;
    return n;
  }

  setArena(arena: ArenaDef): void {
    this.arena = arena;
    this.world = buildCollisionWorld(arena);
    this.nav = new NavSystem(arena, this.world);
    this.pickups.setArena(arena.pickups);
  }

  startRun(weaponId: WeaponId, arena: ArenaDef, perks: PerkLevels | null = null): void {
    this.setArena(arena);
    // Vitality-Perk: Max-HP vor dem Reset setzen
    this.player.maxHp = PLAYER.maxHp + (perks ? PERK_VALUES.vitalityHpPerLevel * perks.vitality : 0);
    this.player.reset(arena.playerSpawn);
    this.upgrades.reset();
    this.upgrades.perks = perks;
    this.upgrades.recompute(this.stats, this.player);
    this.weapon.equip(weaponId);
    // Kickstart-Perk: Gratis-Upgrades zum Run-Start (Stufe 1-5)
    if (perks && perks.kickstart > 0) this.grantKickstart(perks.kickstart);
    this.enemies.clear();
    this.projectiles.clear();
    this.spawner.clear();
    this.sinceLastHit = 999;
    this.hitCounter = 0;
    this.rerollCost = REROLL.baseCost;
    this.currentEvent = null;
    this.forcedEvent = null;
    this.nextEventWave =
      EVENT_RULES.firstEventWave + Math.floor(Math.random() * (EVENT_RULES.maxGap - EVENT_RULES.minGap + 1));
    this.score = 0;
    this.multiplier = 1;
    this.kills = 0;
    this.coinsEarned = 0;
    this.bonusCoins = 0;
    this.supplyReturnPhase = null;
    this.pickups.reset();
    this.waveNumber = 0;
    this.upgradeOffer = [];
    this.reviveUsed = false;
    this.phase = "prewave";
    this.phaseTimer = RUN.firstWaveDelay;
  }

  /** Kickstart: Stufen 1/2/4 = zufälliges Common, Stufen 3/5 = zufälliges Rare. */
  private grantKickstart(level: number): void {
    const ids = Object.keys(UPGRADES) as UpgradeId[];
    const pick = (rarity: "common" | "rare"): void => {
      const pool = ids.filter((id) => {
        const def = UPGRADES[id];
        return def.rarity === rarity && !(def.unique && this.upgrades.count(id) > 0);
      });
      const id = pool[Math.floor(Math.random() * pool.length)];
      if (id) this.upgrades.apply(id, this.weapon, this.player, this.stats);
    };
    const plan: ("common" | "rare")[] = ["common", "common", "rare", "common", "rare"];
    for (let i = 0; i < Math.min(level, plan.length); i++) pick(plan[i]!);
  }

  quitToMenu(): void {
    this.phase = "menu";
    this.enemies.clear();
    this.projectiles.clear();
    this.spawner.clear();
  }

  chooseUpgrade(index: number): void {
    if (this.phase !== "upgrade") return;
    const id = this.upgradeOffer[index];
    if (!id) return;
    this.upgrades.apply(id, this.weapon, this.player, this.stats);
    this.upgradeOffer = [];
    // Supply-Crate-Draft: zurück in die LAUFENDE Welle (kein Wellen-Skip!)
    if (this.supplyReturnPhase !== null) {
      this.phase =
        this.supplyReturnPhase === "wave" && (this.spawner.pendingCount() > 0 || this.enemies.aliveCount() > 0)
          ? "wave"
          : "break";
      this.supplyReturnPhase = null;
      if (this.phase === "break") this.phaseTimer = RUN.waveBreak;
      return;
    }
    this.phase = "break";
    this.phaseTimer = RUN.waveBreak;
  }

  /** Neues 3er-Angebot würfeln — Coin-Abbuchung macht der Aufrufer (main). */
  reroll(): void {
    if (this.phase !== "upgrade") return;
    this.upgradeOffer = this.upgrades.rollOffer(this.waveNumber);
    this.offerNonce++;
    this.rerollCost *= REROLL.costMultiplier;
  }

  /** Rewarded-Ad-Belohnung (Phase 6): Weiterspielen nach Tod. */
  revive(): void {
    if (this.phase !== "dead" || this.reviveUsed) return;
    this.reviveUsed = true;
    this.player.alive = true;
    this.player.hp = 60;
    this.player.sinceDamage = 0;
    // Druck rausnehmen: alles Aktive stirbt, Welle läuft danach weiter
    for (const e of this.enemies.slots) {
      if (e.active && e.fsm !== "death") this.enemies.damage(e, 99999);
    }
    this.projectiles.clear();
    // Eine bereits verdiente Upgrade-Wahl darf durch den Tod nicht verfallen
    if (this.upgradeOffer.length > 0) {
      this.phase = "upgrade";
    } else {
      this.phase = this.spawner.pendingCount() > 0 || this.enemies.aliveCount() > 0 ? "wave" : "break";
    }
    this.phaseTimer = RUN.waveBreak;
  }

  update(dt: number): void {
    this.tick++;
    if (this.phase === "menu") return;

    // Selbstheilung: Ein Draft ohne Angebot darf NIE vorkommen (gemeldeter
    // "CHOOSE AN UPGRADE ohne Karten"-Hänger) — zur Sicherheit neu würfeln.
    if (this.phase === "upgrade" && this.upgradeOffer.length === 0) {
      this.upgradeOffer = this.upgrades.rollOffer(Math.max(1, this.waveNumber));
      this.offerNonce++;
    }

    const p = this.player;

    // Phasen-Steuerung
    if (this.phase === "prewave" || this.phase === "break") {
      this.phaseTimer -= dt;
      if (this.phaseTimer <= 0) {
        this.waveNumber++;
        // Wave-Event? (nie auf Boss-Wellen; Test-Hook forcedEvent hat Vorrang)
        this.currentEvent = null;
        if (!isBossWave(this.waveNumber)) {
          if (this.forcedEvent) {
            this.currentEvent = this.forcedEvent;
            this.forcedEvent = null;
          } else if (this.waveNumber >= this.nextEventWave) {
            const pool: WaveEventId[] = ["goldrush", "blackout", "stampede", "heavyduty"];
            this.currentEvent = pool[Math.floor(Math.random() * pool.length)]!;
          }
          if (this.currentEvent) {
            this.nextEventWave =
              this.waveNumber + EVENT_RULES.minGap + Math.floor(Math.random() * (EVENT_RULES.maxGap - EVENT_RULES.minGap + 1));
          }
        }
        this.spawner.start(this.waveNumber, this.currentEvent);
        this.phase = "wave";
        this.damageTakenThisWave = 0;
        this.events.emit(Ev.WaveStart, 0, 0, 0, this.waveNumber, isBossWave(this.waveNumber) ? 1 : 0);
        if (this.currentEvent) {
          const pool: WaveEventId[] = ["goldrush", "blackout", "stampede", "heavyduty"];
          this.events.emit(Ev.WaveEvent, 0, 0, 0, pool.indexOf(this.currentEvent));
        }
      }
    } else if (this.phase === "wave") {
      this.spawner.update(dt, this.enemies, p.pos, this.waveNumber, this.arena.enemySpawns);
      if (this.spawner.pendingCount() === 0 && this.enemies.aliveCount() === 0) {
        this.events.emit(Ev.WaveCleared, 0, 0, 0, this.waveNumber);
        // Perfect Wave: komplette Welle ohne eigenen Schaden -> Bonuspunkte
        if (this.damageTakenThisWave === 0) {
          this.score += RUN.perfectWaveBonus;
          this.events.emit(Ev.PerfectWave, 0, 0, 0, RUN.perfectWaveBonus);
        }
        // Noch fliegende Gegner-Projektile verfallen — kein Tod im Upgrade-Screen
        this.projectiles.clearEnemyProjectiles();
        this.upgradeOffer = this.upgrades.rollOffer(this.waveNumber);
        this.offerNonce++;
        this.phase = this.upgradeOffer.length > 0 ? "upgrade" : "break";
        this.phaseTimer = RUN.waveBreak;
      }
    }

    // Dynamische Stats: Last Stand (unter 30% HP)
    this.stats.laststandActive = p.alive && p.hp < p.maxHp * VALUES.laststandHpThreshold;

    // Combo-Verfall: nach Haltezeit sinkt der Multiplikator Richtung ×1
    this.sinceLastHit += dt;
    if (this.multiplier > 1 && this.sinceLastHit > COMBO.holdSeconds + this.stats.comboHoldBonus) {
      this.multiplier = Math.max(1, this.multiplier - COMBO.decayPerSecond * dt);
    }

    // Spieler + Waffe (auch in Pausenphasen — Bewegung bleibt flüssig)
    p.update(dt, this.input, this.world, this.events);
    _eye.x = p.pos.x;
    _eye.y = p.eyeY;
    _eye.z = p.pos.z;
    if (p.alive && this.phase !== "upgrade") {
      this.weapon.update(dt, this.input, _eye, this.events, this.resolveHitscan, this.spawnPellet);
    }

    // Bullet Time (Epic): Gegner + deren Projektile laufen langsamer beim Nachladen
    const enemyScale = this.stats.bullettimeEnabled && this.weapon.isReloading() ? VALUES.bullettimeScale : 1;

    // Gegner (inkl. Wegpunkt-Navigation — Repath-Budget gilt pro Tick)
    this.nav.beginTick(dt);
    this.enemies.update(dt * enemyScale, p.pos, p.eyeY, p.alive, this.world, this.events, this.enemyCallbacks, this.nav);

    // Projektile
    this.projectiles.update(dt, enemyScale, this.world.solids, this.projectileHitTest, this.projectileOnHit);

    // Pickups (Recovery Phase 3b) — nicht im Menü/Tod, nicht während eines Drafts
    if (this.phase === "wave" || this.phase === "break" || this.phase === "prewave") {
      this.pickups.update(dt, p.pos, p.alive, this.events, this.pickupCallbacks);
    }

    this.updateAimOnTarget();
  }

  private pickupCallbacks = {
    heal: (amount: number): void => this.player.heal(amount),
    addCoins: (amount: number): void => {
      this.bonusCoins += amount;
    },
    openSupplyDraft: (): void => {
      if (this.phase !== "wave" && this.phase !== "break" && this.phase !== "prewave") return;
      this.supplyReturnPhase = this.phase === "wave" ? "wave" : "break";
      this.upgradeOffer = this.upgrades.rollOffer(Math.max(1, this.waveNumber));
      this.offerNonce++;
      this.phase = "upgrade";
    },
  };

  // ---- Hitscan (AR/DMR) ----

  private resolveHitscan = (origin: Vec3, dir: Vec3, damage: number, range: number): void => {
    let wallT = range;
    for (const b of this.world.solids) {
      const t = rayVsAabb(origin, dir, b, wallT);
      if (t < wallT) wallT = t;
    }
    // Durchschlag (Rare): bis zu 1 + pierceTargets Gegner entlang des Strahls,
    // nach Distanz sortiert — ohne Allokationen (wiederholte Nächster-Suche).
    const maxTargets = 1 + this.stats.pierceTargets;
    let lastT = -1;
    let lastHitT = -1;
    let hits = 0;
    for (let k = 0; k < maxTargets; k++) {
      let bestT = Infinity;
      let bestEnemy: Enemy | null = null;
      for (const e of this.enemies.slots) {
        if (!e.active || e.fsm === "death") continue;
        const t = rayVsSphere(origin, dir, e.pos.x, e.centerY, e.pos.z, e.def.radius * 1.4);
        if (t > lastT && t < bestT && t < wallT) {
          bestT = t;
          bestEnemy = e;
        }
      }
      if (!bestEnemy) break;
      this.applyPlayerDamage(bestEnemy, damage);
      lastT = bestT;
      lastHitT = bestT;
      hits++;
    }
    if (hits > 0) {
      _hitPoint.x = origin.x + dir.x * lastHitT;
      _hitPoint.y = origin.y + dir.y * lastHitT;
      _hitPoint.z = origin.z + dir.z * lastHitT;
      this.events.emit(Ev.Tracer, _hitPoint.x, _hitPoint.y, _hitPoint.z, 1);
    } else {
      _hitPoint.x = origin.x + dir.x * wallT;
      _hitPoint.y = origin.y + dir.y * wallT;
      _hitPoint.z = origin.z + dir.z * wallT;
      // a=0: Wand/Luft — Renderer setzt Einschlag-Partikel nur bei Wandtreffern (t < range)
      this.events.emit(Ev.Tracer, _hitPoint.x, _hitPoint.y, _hitPoint.z, 0, wallT < range ? 1 : 0);
    }
  };

  private spawnPellet = (origin: Vec3, dir: Vec3, speed: number, life: number, damage: number): void => {
    this.projectiles.spawn(true, origin, dir, speed, life, damage, this.stats.ricochetBounces);
  };

  /** Schaden des Spielers an einem Gegner: Crit/Kaltblütig/Multiplikator/
   *  Lifesteal/Kettenblitz — alle Upgrade-Procs laufen hier zusammen. */
  private applyPlayerDamage(e: Enemy, baseDamage: number): void {
    let damage = baseDamage;
    if (this.stats.critChance > 0 && Math.random() < this.stats.critChance) {
      damage *= 2;
      this.events.emit(Ev.Crit, e.pos.x, e.centerY, e.pos.z, Math.round(damage));
    }
    if (this.stats.coldbloodBonus > 0 && this.player.hp >= this.player.maxHp - 0.01) {
      damage *= 1 + this.stats.coldbloodBonus;
    }
    const hpBefore = e.hp;
    const killed = this.enemies.damage(e, damage);
    this.multiplier = Math.min(MULTIPLIER_MAX, this.multiplier + MULTIPLIER_PER_HIT);
    this.sinceLastHit = 0;
    if (this.player.lifesteal > 0) {
      this.player.heal(damage * this.player.lifesteal);
      this.events.emit(Ev.Heal, 0, 0, 0, damage * this.player.lifesteal);
    }
    // Kettenblitz (Epic): jeder 5. Treffer springt auf bis zu 3 weitere Gegner
    this.hitCounter++;
    if (this.stats.chainEnabled && this.hitCounter % VALUES.chainEveryNthHit === 0) {
      this.chainFrom(e, damage);
    }
    if (killed) {
      this.onEnemyKilled(e, damage, hpBefore);
      this.events.emit(Ev.DamageDealt, 0, 0, 0, damage, 1);
    } else {
      this.events.emit(Ev.DamageDealt, 0, 0, 0, damage, 0);
    }
  }

  /** Kill-Abwicklung: Score (inkl. Kopfgeld), Overkill-Heilung, Adrenalin,
   *  Scavenger-Munition, Splitterschuss. */
  private onEnemyKilled(e: Enemy, damage: number, hpBefore: number): void {
    // Score: Elite-Bonus + Kopfgeld + Gold-Rush-Event (×2)
    const eventMult = this.currentEvent === "goldrush" && this.phase === "wave" ? EVENT_RULES.goldrushScoreMult : 1;
    const gained = Math.round(e.def.score * e.scoreScale * this.multiplier * this.stats.scoreMult * eventMult);
    this.score += gained;
    this.kills++;
    this.events.emit(Ev.EnemyDied, e.pos.x, e.centerY, e.pos.z, ENEMY_TYPE_INDEX[e.def.type], gained);
    // Elite "Explosiv": Detonation — Schaden nur auf den Spieler, mit Radius
    if (e.elite === "volatile") {
      const dx = this.player.pos.x - e.pos.x;
      const dz = this.player.pos.z - e.pos.z;
      const inRange = dx * dx + dz * dz < ELITE_RULES.volatileRadius * ELITE_RULES.volatileRadius;
      this.events.emit(Ev.Explosion, e.pos.x, e.centerY, e.pos.z, inRange ? 1 : 0);
      if (inRange) this.damagePlayer(ELITE_RULES.volatileDamage, e.pos.x, e.pos.z);
    }
    // Wave-Event "Heavy Duty": Kills heilen (Ersatz für Pickup-Drops —
    // es existiert kein Pickup-System; in STATUS.md dokumentiert)
    if (this.currentEvent === "heavyduty" && this.phase === "wave") {
      this.player.heal(EVENT_RULES.heavydutyHealPerKill);
      this.events.emit(Ev.Heal, 0, 0, 0, EVENT_RULES.heavydutyHealPerKill);
    }
    if (this.stats.overkillHealPct > 0) {
      const excess = damage - hpBefore;
      if (excess > 0) {
        this.player.heal(excess * this.stats.overkillHealPct);
        this.events.emit(Ev.Heal, 0, 0, 0, excess * this.stats.overkillHealPct);
      }
    }
    if (this.stats.adrenalineDuration > 0) this.player.adrenalineTimer = this.stats.adrenalineDuration;
    if (this.stats.scavengerChance > 0 && Math.random() < this.stats.scavengerChance) {
      this.weapon.ammo = Math.min(this.weapon.magSize(), this.weapon.ammo + VALUES.scavengerAmmo);
    }
    // Splitterschuss: kleine Projektile fächern horizontal aus der Leiche
    if (this.stats.shatterCount > 0) {
      _eye.x = e.pos.x;
      _eye.y = e.centerY;
      _eye.z = e.pos.z;
      const offset = Math.random() * Math.PI * 2;
      for (let i = 0; i < this.stats.shatterCount; i++) {
        const a = offset + (i / this.stats.shatterCount) * Math.PI * 2;
        _hitPoint.x = Math.sin(a);
        _hitPoint.y = 0;
        _hitPoint.z = Math.cos(a);
        this.projectiles.spawn(true, _eye, _hitPoint, VALUES.shatterSpeed, VALUES.shatterLife, VALUES.shatterDamage);
      }
    }
  }

  /** Kettenblitz: 40% Schaden auf bis zu 3 Gegner im Umkreis der Quelle. */
  private chainFrom(source: Enemy, damage: number): void {
    const chainDamage = damage * VALUES.chainDamageFactor;
    const rangeSq = VALUES.chainRange * VALUES.chainRange;
    let jumps = 0;
    for (const t of this.enemies.slots) {
      if (t === source || !t.active || t.fsm === "death") continue;
      const dx = t.pos.x - source.pos.x;
      const dz = t.pos.z - source.pos.z;
      if (dx * dx + dz * dz > rangeSq) continue;
      const hpBefore = t.hp;
      const killed = this.enemies.damage(t, chainDamage);
      this.events.emit(Ev.ChainArc, t.pos.x, t.centerY, t.pos.z, source.pos.x, source.pos.z);
      if (killed) this.onEnemyKilled(t, chainDamage, hpBefore);
      if (++jumps >= VALUES.chainTargets) break;
    }
  }

  // ---- Projektile ----

  private projectileHitTest = (
    s: ProjectileSlot,
    maxDist: number,
    dirX: number,
    dirY: number,
    dirZ: number
  ): number => {
    _eye.x = s.x;
    _eye.y = s.y;
    _eye.z = s.z;
    _hitPoint.x = dirX;
    _hitPoint.y = dirY;
    _hitPoint.z = dirZ;
    if (s.fromPlayer) {
      let best = Infinity;
      this.pelletTarget = null;
      for (const e of this.enemies.slots) {
        if (!e.active || e.fsm === "death") continue;
        const t = rayVsSphere(_eye, _hitPoint, e.pos.x, e.centerY, e.pos.z, e.def.radius * 1.4);
        if (t < best && t <= maxDist) {
          best = t;
          this.pelletTarget = e;
        }
      }
      return best;
    }
    const p = this.player;
    if (!p.alive) return Infinity;
    const t = rayVsSphere(_eye, _hitPoint, p.pos.x, p.pos.y + 1.1, p.pos.z, 0.55);
    return t <= maxDist ? t : Infinity;
  };

  private projectileOnHit = (s: ProjectileSlot): void => {
    if (s.fromPlayer) {
      // Exakt der Gegner, dessen Hitbox der Raycast in hitTest getroffen hat —
      // keine Nächster-Nachbar-Suche (die traf im Pulk den Falschen).
      if (this.pelletTarget) {
        this.applyPlayerDamage(this.pelletTarget, s.damage);
        this.pelletTarget = null;
      }
    } else {
      this.damagePlayer(s.damage, s.x, s.z);
    }
  };

  // ---- Gegner-Callbacks ----

  private damagePlayer = (amount: number, sourceX: number, sourceZ: number, attacker?: Enemy): void => {
    // In Menü-Phasen (Upgrade-Wahl) ist der Spieler unverwundbar,
    // ebenso kurz nach einem Phoenix-Revive
    if (this.phase === "dead" || this.phase === "upgrade") return;
    if (this.player.invulnTimer > 0) return;
    // Dornen (Rare): Nahkampf-Angreifer erleiden einen Teil zurück
    if (attacker && this.stats.thornsPct > 0) {
      const thornsDamage = amount * this.stats.thornsPct;
      const hpBefore = attacker.hp;
      if (this.enemies.damage(attacker, thornsDamage)) {
        this.onEnemyKilled(attacker, thornsDamage, hpBefore);
      }
    }
    const taken = amount * this.stats.damageTakenMult; // Panzerung
    this.multiplier = 1;
    this.damageTakenThisWave += taken;
    const died = this.player.takeDamage(taken, sourceX, sourceZ, this.input.yaw, this.events);
    if (died) {
      // Phoenix (Epic): 1x Selbst-Revive, VOR dem Ad-Revive
      if (this.stats.phoenixCharges > 0) {
        this.stats.phoenixCharges = 0;
        this.upgrades.phoenixConsumed = true;
        this.player.alive = true;
        this.player.hp = VALUES.phoenixReviveHp;
        this.player.sinceDamage = 0;
        this.player.invulnTimer = VALUES.phoenixInvulnSeconds;
        this.events.emit(Ev.PhoenixRevive);
        return;
      }
      this.phase = "dead";
      this.coinsEarned = Math.floor(this.score / COIN_DIVISOR) + this.bonusCoins;
    }
  };

  private enemyCallbacks = {
    damagePlayer: this.damagePlayer,
    spawnEnemyProjectile: (origin: Vec3, dir: Vec3, speed: number, damage: number): void => {
      this.projectiles.spawn(false, origin, dir, speed, 3.5, damage);
    },
  };

  /** Liegt das Fadenkreuz auf einem Gegner? (Mobile-Auto-Fire, Phase 5) */
  private updateAimOnTarget(): void {
    this.aimOnTarget = false;
    if (!this.player.alive) return;
    _eye.x = this.player.pos.x;
    _eye.y = this.player.eyeY;
    _eye.z = this.player.pos.z;
    const cp = Math.cos(this.input.pitch);
    _hitPoint.x = -Math.sin(this.input.yaw) * cp;
    _hitPoint.y = Math.sin(this.input.pitch);
    _hitPoint.z = -Math.cos(this.input.yaw) * cp;
    let wallT = 80;
    for (const b of this.world.losBlockers) {
      const t = rayVsAabb(_eye, _hitPoint, b, wallT);
      if (t < wallT) wallT = t;
    }
    for (const e of this.enemies.slots) {
      if (!e.active || e.fsm === "death") continue;
      const t = rayVsSphere(_eye, _hitPoint, e.pos.x, e.centerY, e.pos.z, e.def.radius * 1.8);
      if (t < wallT) {
        this.aimOnTarget = true;
        return;
      }
    }
  }
}
