// Screen-Verwaltung: Home (mit Shop), Pause, Todes-Screen — plus die
// Pointer-Lock-Logik auf Desktop. Regel Desktop: Sim läuft genau dann, wenn
// der Pointer gelockt ist. Auf Touch gibt es keinen Lock — dort steuert der
// Pause-Button die Modi.

import { ARENAS } from "../config/arena";
import { COLOR_SCHEMES, PERKS, PERK_MAX_LEVEL, PERK_PRICES, WEAPON_PRICES, type PerkId } from "../config/meta";
import { WEAPONS, type WeaponId } from "../config/weapons";
import type { SaveData } from "../meta/SaveData";

export type ScreenMode = "home" | "playing" | "pause" | "death";

const el = <T extends HTMLElement>(id: string): T => document.getElementById(id) as T;

export interface ScreensCallbacks {
  onPlay(): void;
  onResume(): void;
  onQuit(): void;
  onRevive(): void;
  onCoinsX2(): void;
  onSelectionChanged(): void; // Waffe/Farbe gewechselt oder gekauft
  onUiClick(): void; // für Klick-Sound
}

export class Screens {
  mode: ScreenMode = "home";
  private readonly isTouch: boolean;
  private readonly lockTarget: HTMLElement;
  private readonly save: SaveData;
  private readonly cb: ScreensCallbacks;

  private readonly overlay = el<HTMLDivElement>("menu-overlay");
  private readonly homePanel = el<HTMLDivElement>("menu-home");
  private readonly pausePanel = el<HTMLDivElement>("menu-pause");
  private readonly deathPanel = el<HTMLDivElement>("menu-death");
  private readonly subtitle = el<HTMLParagraphElement>("menu-subtitle");
  private readonly statCoins = el<HTMLSpanElement>("stat-coins");
  private readonly statHighscore = el<HTMLSpanElement>("stat-highscore");
  private readonly mapRow = el<HTMLDivElement>("map-select");
  private readonly weaponRow = el<HTMLDivElement>("weapon-select");
  private readonly schemeRow = el<HTMLDivElement>("scheme-select");
  private readonly perkRow = el<HTMLDivElement>("perk-select");
  private readonly autofireRow = el<HTMLLabelElement>("autofire-row");
  private readonly autofireToggle = el<HTMLInputElement>("autofire-toggle");
  private readonly musicToggle = el<HTMLInputElement>("music-toggle");
  private readonly menuHint = el<HTMLParagraphElement>("menu-hint");
  private readonly btnRevive = el<HTMLButtonElement>("btn-revive");
  private readonly btnCoins2 = el<HTMLButtonElement>("btn-coins2");
  private readonly deathHighscore = el<HTMLDivElement>("death-highscore");

  /** Wird bei jedem echten Moduswechsel gerufen (für Loop-Pause + SDK-Events). */
  onModeChanged: (mode: ScreenMode) => void = () => {};

  constructor(lockTarget: HTMLElement, isTouch: boolean, save: SaveData, cb: ScreensCallbacks) {
    this.lockTarget = lockTarget;
    this.isTouch = isTouch;
    this.save = save;
    this.cb = cb;

    el<HTMLButtonElement>("btn-play").addEventListener("click", () => {
      cb.onUiClick();
      cb.onPlay();
    });
    el<HTMLButtonElement>("btn-resume").addEventListener("click", () => {
      cb.onUiClick();
      cb.onResume();
    });
    el<HTMLButtonElement>("btn-quit").addEventListener("click", () => {
      cb.onUiClick();
      cb.onQuit();
    });
    el<HTMLButtonElement>("btn-again").addEventListener("click", () => {
      cb.onUiClick();
      cb.onPlay();
    });
    el<HTMLButtonElement>("btn-menu").addEventListener("click", () => {
      cb.onUiClick();
      cb.onQuit();
    });
    this.btnRevive.addEventListener("click", () => cb.onRevive());
    this.btnCoins2.addEventListener("click", () => cb.onCoinsX2());
    this.autofireToggle.addEventListener("change", () => {
      this.save.state.autoFire = this.autofireToggle.checked;
      this.save.save();
    });
    this.musicToggle.addEventListener("change", () => {
      this.save.state.musicOn = this.musicToggle.checked;
      this.save.save();
    });

    if (isTouch) {
      this.menuHint.textContent = "Left side: move stick · Right side: look · Buttons: fire, jump, reload";
      this.autofireRow.hidden = false;
    }

    document.addEventListener("pointerlockchange", () => this.handleLockChange());
    document.addEventListener("pointerlockerror", () => {
      this.subtitle.textContent = "One moment — click again!";
    });
  }

  isLocked(): boolean {
    return document.pointerLockElement === this.lockTarget;
  }

  /** Desktop: Pointer anfordern; Touch: direkt in den Playing-Modus. */
  enterPlaying(): void {
    if (this.isTouch) {
      this.setMode("playing");
    } else if (this.isLocked()) {
      this.setMode("playing");
    } else {
      try {
        const r = this.lockTarget.requestPointerLock() as unknown;
        if (r instanceof Promise) r.catch(() => (this.subtitle.textContent = "One moment — click again!"));
      } catch {
        this.subtitle.textContent = "One moment — click again!";
      }
      // setMode("playing") passiert im pointerlockchange-Handler
    }
  }

  /** Tod/Menü: Lock kontrolliert freigeben, ohne dass der Pause-Screen aufpoppt. */
  releaseLock(): void {
    if (!this.isTouch && this.isLocked()) document.exitPointerLock();
  }

  showHome(): void {
    this.setMode("home");
    this.refreshHome();
  }

  showPause(): void {
    this.setMode("pause");
  }

  showDeath(opts: {
    score: number;
    wave: number;
    bestWave: number;
    kills: number;
    coins: number;
    newHighscore: boolean;
    canRevive: boolean;
    canCoinsX2: boolean;
  }): void {
    el<HTMLSpanElement>("death-score").textContent = String(opts.score);
    el<HTMLSpanElement>("death-wave").textContent = String(opts.wave);
    el<HTMLSpanElement>("death-bestwave").textContent = String(Math.max(opts.bestWave, opts.wave));
    el<HTMLSpanElement>("death-kills").textContent = String(opts.kills);
    el<HTMLSpanElement>("death-coins").textContent = `🪙 ${opts.coins}`;
    this.deathHighscore.hidden = !opts.newHighscore;
    this.btnRevive.hidden = !opts.canRevive;
    this.btnCoins2.hidden = !opts.canCoinsX2;
    this.setMode("death");
  }

  updateDeathCoins(coins: number, canCoinsX2: boolean): void {
    el<HTMLSpanElement>("death-coins").textContent = `🪙 ${coins}`;
    this.btnCoins2.hidden = !canCoinsX2;
  }

  hideReviveButton(): void {
    this.btnRevive.hidden = true;
  }

  private setMode(mode: ScreenMode): void {
    if (this.mode === mode) return;
    this.mode = mode;
    this.overlay.hidden = mode === "playing";
    this.homePanel.hidden = mode !== "home";
    this.pausePanel.hidden = mode !== "pause";
    this.deathPanel.hidden = mode !== "death";
    if (mode === "home") this.subtitle.textContent = "Fast-paced arena wave shooter";
    this.onModeChanged(mode);
  }

  private handleLockChange(): void {
    if (this.isTouch) return;
    if (this.isLocked()) {
      this.setMode("playing");
    } else if (this.mode === "playing") {
      // ESC während des Spiels -> Pause. (Tod/Menü setzen den Modus vorher um.)
      this.setMode("pause");
    }
  }

  // ---- Home-Screen: Stats + Shop ----

  refreshHome(): void {
    const s = this.save.state;
    this.statCoins.textContent = `🪙 ${s.coins}`;
    this.statHighscore.textContent = `🏆 ${s.highscore}`;
    this.autofireToggle.checked = s.autoFire;
    this.musicToggle.checked = s.musicOn;
    this.buildMapRow();
    this.buildWeaponRow();
    this.buildSchemeRow();
    this.buildPerkRow();
  }

  private buildMapRow(): void {
    const s = this.save.state;
    this.mapRow.replaceChildren();
    for (const arena of ARENAS) {
      const btn = document.createElement("button");
      btn.type = "button";
      btn.className = "select-item";
      if (arena.id === s.selectedArena) btn.classList.add("selected");
      btn.innerHTML = `${arena.name}<span class="sub">${arena.sub}</span>`;
      btn.addEventListener("click", () => {
        s.selectedArena = arena.id;
        this.save.save();
        this.cb.onUiClick();
        this.cb.onSelectionChanged();
        this.refreshHome();
      });
      this.mapRow.append(btn);
    }
  }

  private buildWeaponRow(): void {
    const s = this.save.state;
    this.weaponRow.replaceChildren();
    (Object.keys(WEAPONS) as WeaponId[]).forEach((id) => {
      const def = WEAPONS[id];
      const price = WEAPON_PRICES[id];
      const unlocked = s.unlockedWeapons.includes(id);
      const btn = document.createElement("button");
      btn.type = "button";
      btn.className = "select-item";
      if (id === s.selectedWeapon) btn.classList.add("selected");
      if (!unlocked) btn.classList.add("locked");
      btn.innerHTML = `${def.name}<span class="sub">${unlocked ? weaponSub(id) : `🪙 ${price} — tap to buy`}</span>`;
      btn.addEventListener("click", () => {
        if (unlocked) {
          s.selectedWeapon = id;
        } else if (s.coins >= price) {
          s.coins -= price;
          s.unlockedWeapons.push(id);
          s.selectedWeapon = id;
        } else {
          return; // zu teuer — nichts tun
        }
        this.save.save();
        this.cb.onUiClick();
        this.cb.onSelectionChanged();
        this.refreshHome();
      });
      this.weaponRow.append(btn);
    });
  }

  private buildSchemeRow(): void {
    const s = this.save.state;
    this.schemeRow.replaceChildren();
    for (const scheme of COLOR_SCHEMES) {
      const unlocked = s.unlockedSchemes.includes(scheme.id);
      const btn = document.createElement("button");
      btn.type = "button";
      btn.className = "select-item";
      if (scheme.id === s.selectedScheme) btn.classList.add("selected");
      if (!unlocked) btn.classList.add("locked");
      const swatch = `<span style="color:#${scheme.accent.toString(16).padStart(6, "0")}">■</span> `;
      btn.innerHTML = `${swatch}${scheme.name}<span class="sub">${unlocked ? "" : `🪙 ${scheme.price} — tap to buy`}</span>`;
      btn.addEventListener("click", () => {
        if (unlocked) {
          s.selectedScheme = scheme.id;
        } else if (s.coins >= scheme.price) {
          s.coins -= scheme.price;
          s.unlockedSchemes.push(scheme.id);
          s.selectedScheme = scheme.id;
        } else {
          return;
        }
        this.save.save();
        this.cb.onUiClick();
        this.cb.onSelectionChanged();
        this.refreshHome();
      });
      this.schemeRow.append(btn);
    }
  }

  /** Account-Perks (RC Phase 3): Klick kauft die nächste Stufe, wirkt ab dem
   *  nächsten Run. Preise pro Stufe aus PERK_PRICES, Stufe 5 = MAX. */
  private buildPerkRow(): void {
    const s = this.save.state;
    this.perkRow.replaceChildren();
    (Object.keys(PERKS) as PerkId[]).forEach((id) => {
      const def = PERKS[id];
      const level = s.perks[id];
      const maxed = level >= PERK_MAX_LEVEL;
      const price = maxed ? 0 : PERK_PRICES[level]!;
      const btn = document.createElement("button");
      btn.type = "button";
      btn.className = "select-item";
      if (level > 0) btn.classList.add("selected");
      if (!maxed && s.coins < price) btn.classList.add("locked");
      const stars = "★".repeat(level) + "☆".repeat(PERK_MAX_LEVEL - level);
      btn.innerHTML =
        `${def.icon} ${def.name} <span class="perk-stars">${stars}</span>` +
        `<span class="sub">${def.desc}${maxed ? " · MAX" : ` · 🪙 ${price} — tap to buy`}</span>`;
      btn.addEventListener("click", () => {
        if (maxed || s.coins < price) return;
        s.coins -= price;
        s.perks[id] = level + 1;
        this.save.save();
        this.cb.onUiClick();
        this.refreshHome();
      });
      this.perkRow.append(btn);
    });
  }
}

function weaponSub(id: WeaponId): string {
  if (id === "pulse") return "All-round · auto";
  if (id === "scatter") return "Close range · brutal";
  return "Slow · hard · precise";
}
