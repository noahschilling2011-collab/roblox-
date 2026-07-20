// Spieler-Simulation: Krunker-artiges Movement (hohe Beschleunigung, klare
// Reibung, sofortige Richtungswechsel), HP mit verzögerter Regeneration.

import { MOVE, PLAYER } from "../config/tuning";
import { moveBody, type CollisionWorld } from "./collision";
import { vec3, type Vec3, clamp } from "./math";
import type { InputState } from "./input";
import { EventQueue, Ev } from "./events";

export class Player {
  readonly pos: Vec3 = vec3(0, 0, 12); // Fußpunkt; echter Spawn via reset()
  readonly prevPos: Vec3 = vec3(0, 0, 12);
  readonly vel: Vec3 = vec3();
  hp: number = PLAYER.maxHp;
  alive = true;
  onGround = true;
  sprinting = false;
  /** 0..1: wie stark gerade gelaufen wird (für Head-Bob & FOV). */
  moveIntensity = 0;
  coyoteTimer = 0;
  sinceDamage = 999;
  // Doppelsprung (Upgrade Phase 4)
  hasDoubleJump = false;
  doubleJumpReady = false;
  speedMult = 1;
  lifesteal = 0;

  reset(spawn: { x: number; z: number }): void {
    this.pos.x = spawn.x;
    this.pos.y = 0;
    this.pos.z = spawn.z;
    this.prevPos.x = this.pos.x;
    this.prevPos.y = this.pos.y;
    this.prevPos.z = this.pos.z;
    this.vel.x = this.vel.y = this.vel.z = 0;
    this.hp = PLAYER.maxHp;
    this.alive = true;
    this.onGround = true;
    this.sinceDamage = 999;
    this.hasDoubleJump = false;
    this.doubleJumpReady = false;
    this.speedMult = 1;
    this.lifesteal = 0;
  }

  get eyeY(): number {
    return this.pos.y + MOVE.playerHeight;
  }

  update(dt: number, input: InputState, world: CollisionWorld, events: EventQueue): void {
    this.prevPos.x = this.pos.x;
    this.prevPos.y = this.pos.y;
    this.prevPos.z = this.pos.z;
    if (!this.alive) return;

    // Bewegungsrichtung aus Blickrichtung (nur Yaw) + Input
    const sin = Math.sin(input.yaw);
    const cos = Math.cos(input.yaw);
    // vor = -Z in Kamera-Richtung
    let wishX = input.moveX * cos - input.moveZ * sin;
    let wishZ = -input.moveZ * cos - input.moveX * sin;
    const wishLen = Math.hypot(wishX, wishZ);
    if (wishLen > 1) {
      wishX /= wishLen;
      wishZ /= wishLen;
    }
    this.moveIntensity = Math.min(1, wishLen);
    this.sprinting = input.sprint && input.moveZ > 0.1;

    const targetSpeed = (this.sprinting ? MOVE.sprintSpeed : MOVE.walkSpeed) * this.speedMult;
    const accel = this.onGround ? MOVE.accel : MOVE.airAccel;

    if (wishLen > 0.01) {
      this.vel.x += (wishX * targetSpeed - this.vel.x) * Math.min(1, (accel / targetSpeed) * dt);
      this.vel.z += (wishZ * targetSpeed - this.vel.z) * Math.min(1, (accel / targetSpeed) * dt);
    } else if (this.onGround) {
      // Reibung: schnelles, aber weiches Stoppen
      const f = Math.max(0, 1 - MOVE.friction * dt);
      this.vel.x *= f;
      this.vel.z *= f;
    }

    // Springen (mit Coyote-Time und optionalem Doppelsprung)
    this.coyoteTimer = this.onGround ? MOVE.coyoteTime : this.coyoteTimer - dt;
    if (input.jumpQueued) {
      input.jumpQueued = false;
      if (this.coyoteTimer > 0) {
        this.vel.y = MOVE.jumpVelocity;
        this.coyoteTimer = 0;
        this.doubleJumpReady = this.hasDoubleJump;
        events.emit(Ev.Jump);
      } else if (this.doubleJumpReady) {
        this.vel.y = MOVE.jumpVelocity * 0.92;
        this.doubleJumpReady = false;
        events.emit(Ev.Jump);
      }
    }

    this.vel.y -= MOVE.gravity * dt;
    const fallSpeed = -this.vel.y;
    const wasGround = this.onGround;
    this.onGround = moveBody(this.pos, this.vel, MOVE.playerRadius, MOVE.playerHeight, dt, world);
    if (this.onGround && !wasGround && fallSpeed > 6) {
      events.emit(Ev.Land, 0, 0, 0, fallSpeed);
    }
    if (this.onGround) this.doubleJumpReady = this.hasDoubleJump;

    // Regeneration
    this.sinceDamage += dt;
    if (this.sinceDamage > PLAYER.regenDelay && this.hp < PLAYER.maxHp) {
      this.hp = Math.min(PLAYER.maxHp, this.hp + PLAYER.regenPerSecond * dt);
    }
  }

  /** Liefert true, wenn dieser Schaden tödlich war. */
  takeDamage(amount: number, sourceX: number, sourceZ: number, yaw: number, events: EventQueue): boolean {
    if (!this.alive) return false;
    this.hp -= amount;
    this.sinceDamage = 0;
    // Winkel zur Schadensquelle relativ zur Blickrichtung (für HUD-Indikator)
    const angleToSource = Math.atan2(this.pos.x - sourceX, this.pos.z - sourceZ);
    let rel = angleToSource - yaw + Math.PI;
    while (rel > Math.PI) rel -= Math.PI * 2;
    while (rel < -Math.PI) rel += Math.PI * 2;
    events.emit(Ev.PlayerHurt, sourceX, 0, sourceZ, amount, rel);
    if (this.hp <= 0) {
      this.hp = 0;
      this.alive = false;
      events.emit(Ev.PlayerDied);
      return true;
    }
    return false;
  }

  heal(amount: number): void {
    this.hp = clamp(this.hp + amount, 0, PLAYER.maxHp);
  }
}
