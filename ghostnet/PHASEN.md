# GHOSTNET — Bauplan

Reihenfolge ist bindend. Eine Phase wird komplett fertig, bevor die nächste
anfängt. Neue Minispiele ohne funktionierenden Loop sind wertlos — der Spieler
hätte dann mehr Rätsel, die zu nichts führen.

---

## Phase 0 — Prototyp ✅ (vor dieser Session vorhanden)
Config, Remotes, Types, UITheme, EconomyService, HackService, HackTargets,
HackEffects, RateLimiter, NodeBreach, TestTargets, HUD, HackUI.

---

## Phase 1 — Den Loop schließen ✅
Der Kreislauf war an vier Stellen offen: kein Verkauf, kein Shop, kein Speichern,
und der Trace wurde zwar berechnet, aber nie angewendet.

- **Bugfixes**
  - Ziel-Id-Kollision in `HackTargets.register` (Zähler prüfte die Registry nicht).
  - Cooldown-Exploit durch Rejoin (Cooldowns lagen nur im Serverspeicher).
  - `os.clock()` für Dinge, die einen Serverwechsel überleben müssen.
- `SaveService` — DataStore, Profil-Schema mit Version, Session-Lock, Autosave,
  `BindToClose`, pcall + Backoff, Kick statt leerem Profil.
- `TraceService` — Trace 0–100, passiver Abbau, Bust bei 100, `TraceSync`.
- `SellService` — Hehler-Punkte (`GhostNetFence`), Unsold → Banked abzüglich
  Gebühr, senkt den Trace.
- `ShopService` — `ShopPurchase` (RemoteFunction), vier Rig-Bauteile,
  exponentielle Preiskurve, Server rechnet den Preis selbst.

---

## Phase 2 — Die ersten 60 Sekunden
Auf Roblox entscheidet sich in unter einer Minute, ob jemand bleibt.

- `OnboardingService` — gescriptetes erstes Ziel statt Textwall. Übungs-Kamera
  (Difficulty 1) direkt vor dem Spawn, Markierung, ein Satz im HUD. Die HackUI
  erklärt sich im Spiel: Start/Exit hervorgehoben, erster gültiger Nachbar
  pulsiert. Nach dem Erfolg Pfeil zum Hehler, nach dem ersten Verkauf öffnet
  der Shop sich einmal von selbst. Profil-Flag `TutorialDone`.
  **Regel:** jeder Schritt wird durch eine Handlung ausgelöst, nie durch einen
  Timer, und nie erscheinen zwei Hinweise gleichzeitig.
- Fehlermeldungen in Klartext, mit der konkreten Zahl — für alle `deny`-Gründe
  (`RANGE`, `COOLDOWN`, `LEVEL`, `OFFLINE`, `BUSTED`, …) und alle
  Minispiel-Rückmeldungen (`NOT_ADJACENT`, `ICE`, `REVISIT`, `RELAYS_MISSING`,
  `MASKED_ICE`).
- `SoundCatalog` + Client-`SoundService`. **Alle IDs bleiben leere Strings mit
  Kommentar** — Noah trägt sie ein. Tonhöhe der Knoten-Klicks steigt mit der
  Pfadlänge, Countdown-Ticken unter 10 s, Ambience leiser während eines Hacks.

---

## Phase 3 — Gründe wiederzukommen
- `WorldGenerator` statt fest verdrahteter `TestTargets`: 25+ Ziele in vier
  Schwierigkeitszonen (1–2, 3–4, 5–6, 7+), räumlich getrennt, sodass
  Rig-Fortschritt neue Stadtteile aufschließt.
- Zwei weitere Minispiele über das bestehende Register:
  **SignalMatch** (Wellenform angleichen) und **CodeCrack** (Mastermind).
  Zuweisung über das vorhandene `HackType`-Attribut.
- `ContractService` — drei Tagesziele, Reset über `os.time()`, im Profil
  gespeichert. Stärkster und billigster Hebel für Wiederkehr.
- `leaderstats` (Banked, Tier), `OrderedDataStore`-Top-100 und eine
  „Ruhigste Hand"-Tafel (Hacks ohne einen einzigen Fehlversuch).

---

## Phase 4 — Warum zu zweit
GhostNet ist bisher ein Solo-Puzzle in einer sozialen Engine. **Eine** Option
bauen, nicht beide:

- **Option A — Co-Op (empfohlen):** Ziele mit `RequiresTwo = true`. Einer löst,
  der andere hält in Reichweite einen Störsender, der den Trace-Anstieg des
  ersten halbiert. Belohnung geteilt, pro Kopf aber höher als solo.
- **Option B — Asynchrones PvP:** eigene Basis mit ICE-Layout befestigen, andere
  brechen ein und nehmen einen Teil des Unsold. Deutlich mehr Aufwand,
  Griefing-Risiko. Nur wenn Phase 1–3 stabil laufen.

---

## Phase 5 — Monetarisierung (zuletzt)
Erst bauen, wenn Phase 1–3 laufen. Monetarisierung vor Retention verdient nichts.

- `MonetizationService` mit Konstantentabelle, **alle IDs `0`**.
  Gamepass: ColdRig (−25 % Trace), ExtraSlot, SkinPack.
  Produkt: Crypto1000, TraceReset.
- **Nichts verkaufen, das Rätsel löst.** Keine Auto-Solves, keine Hinweise.
  Erlaubt: Zeitersparnis, Kosmetik, Komfort.
- `ProcessReceipt` idempotent: verarbeitete `PurchaseId` im Profil merken,
  erst gutschreiben und speichern, dann `PurchaseGranted`.
- Kauf-Effekte laufen ausschließlich über `EconomyService`.
