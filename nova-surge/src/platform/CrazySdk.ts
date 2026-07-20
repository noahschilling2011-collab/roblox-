// CrazyGames-SDK-Adapter (Phase 6, SDK v3 laut docs.crazygames.com):
// - Script wird NUR dynamisch geladen, wenn das Spiel in der CrazyGames-
//   Umgebung läuft (oder ?cg=1 zum Testen). Lokal/offline: alles no-op,
//   Konsole bleibt sauber.
// - gameplayStart/Stop, loadingStart/Stop, happytime, Midgame- und
//   Rewarded-Ads hinter einer Promise-API mit Pause/Mute-Hooks.

interface SdkAdCallbacks {
  adStarted?: () => void;
  adFinished?: () => void;
  adError?: (error: unknown) => void;
}

interface CrazySdkV3 {
  init(): Promise<void>;
  game: {
    loadingStart(): void;
    loadingStop(): void;
    gameplayStart(): void;
    gameplayStop(): void;
    happytime(): void;
  };
  ad: {
    requestAd(type: "midgame" | "rewarded", callbacks: SdkAdCallbacks): void;
  };
}

declare global {
  interface Window {
    CrazyGames?: { SDK: CrazySdkV3 };
  }
}

const SDK_URL = "https://sdk.crazygames.com/crazygames-sdk-v3.js";
const MIN_SECONDS_BETWEEN_MIDGAME = 120;
const MIN_WAVES_BETWEEN_MIDGAME = 3;

export class CrazySdk {
  private sdk: CrazySdkV3 | null = null;
  private lastMidgameAt = -Infinity;
  private lastMidgameWave = 0;
  private gameplayRunning = false;

  /** Wird vor/nach jeder Ad gerufen: Spiel pausieren + Audio stumm. */
  onAdPause: (paused: boolean) => void = () => {};

  /** true, wenn Ads angeboten werden können (SDK vorhanden). */
  get available(): boolean {
    return this.sdk !== null;
  }

  /** Vor dem Laden des Spiels aufrufen. Lädt das SDK nur in CG-Umgebung. */
  async init(): Promise<void> {
    const host = location.hostname;
    const inCrazyEnv =
      host.endsWith("crazygames.com") ||
      host.endsWith("1001juegos.com") || // CrazyGames-Partnerdomain
      new URLSearchParams(location.search).has("cg");
    if (!inCrazyEnv) return;

    try {
      await new Promise<void>((resolve, reject) => {
        const script = document.createElement("script");
        script.src = SDK_URL;
        script.onload = () => resolve();
        script.onerror = () => reject(new Error("SDK load failed"));
        document.head.append(script);
      });
      if (!window.CrazyGames) return;
      await window.CrazyGames.SDK.init();
      this.sdk = window.CrazyGames.SDK;
      this.sdk.game.loadingStart();
    } catch {
      this.sdk = null; // Ohne SDK weiterlaufen — Spiel funktioniert komplett
    }
  }

  loadingDone(): void {
    this.sdk?.game.loadingStop();
  }

  gameplayStart(): void {
    if (this.gameplayRunning) return;
    this.gameplayRunning = true;
    this.sdk?.game.gameplayStart();
  }

  gameplayStop(): void {
    if (!this.gameplayRunning) return;
    this.gameplayRunning = false;
    this.sdk?.game.gameplayStop();
  }

  happytime(): void {
    this.sdk?.game.happytime();
  }

  /**
   * Midgame-Ad in der Wellenpause — NIE im Gefecht. Frequenz selbst begrenzt
   * (alle >= 3 Wellen und >= 120 s), zusätzlich throttlet das SDK serverseitig.
   */
  maybeMidgameAd(waveNumber: number): void {
    if (!this.sdk) return;
    const now = performance.now() / 1000;
    if (now - this.lastMidgameAt < MIN_SECONDS_BETWEEN_MIDGAME) return;
    if (waveNumber - this.lastMidgameWave < MIN_WAVES_BETWEEN_MIDGAME) return;
    this.lastMidgameAt = now;
    this.lastMidgameWave = waveNumber;
    this.sdk.ad.requestAd("midgame", {
      adStarted: () => this.onAdPause(true),
      adFinished: () => this.onAdPause(false),
      adError: () => this.onAdPause(false),
    });
  }

  /** Rewarded Ad; resolved mit true, wenn die Belohnung fällig ist. */
  requestRewarded(): Promise<boolean> {
    if (!this.sdk) return Promise.resolve(false);
    return new Promise((resolve) => {
      this.sdk!.ad.requestAd("rewarded", {
        adStarted: () => this.onAdPause(true),
        adFinished: () => {
          this.onAdPause(false);
          resolve(true);
        },
        adError: () => {
          this.onAdPause(false);
          resolve(false);
        },
      });
    });
  }
}
