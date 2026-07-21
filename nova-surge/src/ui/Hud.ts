// HUD: HP, Munition, Welle, Score/Multiplikator, Fadenkreuz (skaliert mit
// Spread), Hitmarker, Schadens-Vignette + Richtungsindikator, Wellen-Banner,
// Upgrade-Wahl. Alles DOM/CSS — billig, scharf, identisch auf Mobile.

import { UPGRADES, type UpgradeId } from "../config/upgrades";
import { PLAYER } from "../config/tuning";
import type { Sim } from "../core/Sim";

const el = <T extends HTMLElement>(id: string): T => document.getElementById(id) as T;

export class Hud {
  private readonly root = el<HTMLDivElement>("hud");
  private readonly crosshair = el<HTMLDivElement>("crosshair");
  private readonly hitmarker = el<HTMLDivElement>("hitmarker");
  private readonly vignette = el<HTMLDivElement>("vignette");
  private readonly dmgIndicator = el<HTMLDivElement>("dmg-indicator");
  private readonly waveLabel = el<HTMLDivElement>("wave-label");
  private readonly scoreEl = el<HTMLSpanElement>("score");
  private readonly multEl = el<HTMLSpanElement>("mult");
  private readonly hpFill = el<HTMLDivElement>("hp-fill");
  private readonly ammoBox = el<HTMLDivElement>("ammo");
  private readonly ammoCur = el<HTMLSpanElement>("ammo-cur");
  private readonly ammoMax = el<HTMLSpanElement>("ammo-max");
  private readonly banner = el<HTMLDivElement>("banner");
  private readonly upgradeOverlay = el<HTMLDivElement>("upgrade-overlay");
  private readonly upgradeCards = el<HTMLDivElement>("upgrade-cards");
  private readonly upgradeHint = el<HTMLParagraphElement>("upgrade-hint");

  private hitmarkerTimer = 0;
  private vignetteLevel = 0;
  private dmgTimer = 0;
  private lastOfferKey = "";
  private flashText: string | null = null;
  private flashTimer = 0;
  private readonly popupPool: HTMLDivElement[] = [];
  private popupCursor = 0;

  onChooseUpgrade: (index: number) => void = () => {};

  constructor() {
    // Score-Popup-Pool (kein DOM-Anlegen während des Gefechts)
    for (let i = 0; i < 10; i++) {
      const div = document.createElement("div");
      div.className = "score-popup";
      div.style.display = "none";
      this.root.append(div);
      this.popupPool.push(div);
    }
  }

  /** Kurzzeit-Banner ("BOSS WAVE", "PERFECT WAVE +500"). */
  flashBanner(text: string, seconds: number): void {
    this.flashText = text;
    this.flashTimer = seconds;
  }

  /** Fliegender Score-Text an einer Bildschirmposition. */
  spawnPopup(x: number, y: number, text: string, big: boolean): void {
    const div = this.popupPool[this.popupCursor]!;
    this.popupCursor = (this.popupCursor + 1) % this.popupPool.length;
    div.textContent = text;
    div.classList.toggle("big", big);
    div.style.left = `${x.toFixed(0)}px`;
    div.style.top = `${y.toFixed(0)}px`;
    div.style.display = "block";
    // Animation neu starten
    div.classList.remove("fly");
    void div.offsetWidth;
    div.classList.add("fly");
  }

  show(): void {
    this.root.hidden = false;
  }

  hide(): void {
    this.root.hidden = true;
    this.upgradeOverlay.hidden = true;
    this.lastOfferKey = "";
  }

  notifyHit(killed: boolean): void {
    this.hitmarkerTimer = 0.12;
    this.hitmarker.classList.toggle("kill", killed);
    this.hitmarker.classList.remove("flash");
    // Reflow erzwingen, damit die Animation neu startet
    void this.hitmarker.offsetWidth;
    this.hitmarker.classList.add("flash");
  }

  notifyHurt(relAngle: number): void {
    this.vignetteLevel = 1;
    this.dmgTimer = 0.7;
    this.dmgIndicator.style.transform = `rotate(${(-relAngle * 180) / Math.PI}deg)`;
  }

  update(dt: number, sim: Sim, isTouch: boolean): void {
    const w = sim.weapon;

    // Fadenkreuz-Spread in Pixel (grobe Projektion reicht fürs Gefühl)
    const gapPx = 5 + w.spread * 900;
    this.crosshair.style.setProperty("--gap", `${gapPx.toFixed(1)}px`);

    this.hitmarkerTimer -= dt;
    if (this.hitmarkerTimer <= 0) this.hitmarker.classList.remove("flash");

    // Vignette: aufblitzen, dann abklingen; bei wenig HP dauerhaft sichtbar
    this.vignetteLevel = Math.max(0, this.vignetteLevel - dt * 2.2);
    const lowHp = sim.player.hp < PLAYER.maxHp * 0.3 ? 0.45 : 0;
    this.vignette.style.opacity = String(Math.min(1, Math.max(this.vignetteLevel, lowHp)));

    this.dmgTimer -= dt;
    this.dmgIndicator.style.opacity = this.dmgTimer > 0 ? "1" : "0";

    // HP
    const hpFrac = sim.player.hp / PLAYER.maxHp;
    this.hpFill.style.width = `${(hpFrac * 100).toFixed(1)}%`;
    this.hpFill.classList.toggle("low", hpFrac < 0.3);

    // Munition
    this.ammoCur.textContent = String(w.ammo);
    this.ammoMax.textContent = String(w.magSize());
    this.ammoBox.classList.toggle("reloading", w.isReloading());

    // Welle / Score
    this.waveLabel.textContent = sim.waveNumber > 0 ? `WAVE ${sim.waveNumber}` : "GET READY";
    this.scoreEl.textContent = String(sim.score);
    this.multEl.textContent = `×${sim.multiplier.toFixed(1)}`;

    // Banner: Kurzzeit-Flash (Boss/Perfect) hat Vorrang vor Phasen-Banner
    this.flashTimer -= dt;
    if (this.flashText !== null && this.flashTimer > 0) {
      this.setBanner(this.flashText);
    } else if (sim.phase === "prewave") {
      this.setBanner(`WAVE 1 IN ${Math.ceil(sim.phaseTimer)}`);
    } else if (sim.phase === "break") {
      this.setBanner(`WAVE ${sim.waveNumber + 1} IN ${Math.ceil(sim.phaseTimer)}`);
    } else {
      this.setBanner(null);
      this.flashText = null;
    }

    // Upgrade-Wahl
    if (sim.phase === "upgrade") {
      const key = sim.upgradeOffer.join(",");
      if (key !== this.lastOfferKey) {
        this.lastOfferKey = key;
        this.buildUpgradeCards(sim.upgradeOffer, isTouch);
      }
      this.upgradeOverlay.hidden = false;
    } else {
      this.upgradeOverlay.hidden = true;
      this.lastOfferKey = "";
    }
  }

  private setBanner(text: string | null): void {
    if (text === null) {
      this.banner.hidden = true;
    } else {
      this.banner.hidden = false;
      if (this.banner.textContent !== text) this.banner.textContent = text;
    }
  }

  private buildUpgradeCards(offer: readonly UpgradeId[], isTouch: boolean): void {
    this.upgradeCards.replaceChildren();
    offer.forEach((id, i) => {
      const def = UPGRADES[id];
      const card = document.createElement("button");
      card.type = "button";
      card.className = "upgrade-card";
      card.innerHTML =
        `<div class="uc-icon">${def.icon}</div>` +
        `<div class="uc-name">${def.name}</div>` +
        `<div class="uc-desc">${def.desc}</div>` +
        (isTouch ? "" : `<div class="uc-key">${i + 1}</div>`);
      card.addEventListener("click", () => this.onChooseUpgrade(i));
      this.upgradeCards.append(card);
    });
    this.upgradeHint.hidden = isTouch;
  }
}
