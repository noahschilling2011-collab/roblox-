# Nova Surge — Release-Candidate-Plan (Original-Auftrag)

Dieser Plan ersetzt für die RC-Arbeit die Phasenliste in PHASEN.md
(die dokumentiert den ursprünglichen Aufbau). Arbeitsregel: Phasen strikt
sequenziell, nach jeder Phase STATUS.md aktualisieren und **auf Freigabe
warten**. Nichts bauen, was hier nicht steht; Ideen darüber hinaus nur als
Vorschlag in STATUS.md unter „Nach Release".

## Ziel-Metriken (jede Änderung muss eine verbessern)
1. Session-Länge (noch ein Run)
2. D1-Retention (morgen wiederkommen)
3. Rewarded-Ad-Nutzung (Coins dauerhaft wertvoll)

## Harte Regeln (Anti-Scope)
- KEINE neuen Arenen/Waffen/Gegner-Meshes, KEIN Multiplayer.
  Vielfalt nur über Modifikatoren (Tint + Stats + max. 1 Verhalten).
- KEIN Coin-Revive — Revive bleibt exklusiv Rewarded Ad.
- Kein Schönheits-Refactoring. Balancing nur als benannte Konstanten.
- Keine neuen Dependencies.

## Phasen (Kurzfassung, Details im Original-Prompt)
- **Phase 0 — Codebase-Mapping:** ARCHITEKTUR.md, Ist-Zahlen verifizieren,
  Build-Baseline. ✅ erledigt, siehe ARCHITEKTUR.md
- **Phase 1 — Upgrades 6 → 24:** Rarity Common/Rare/Epic (65/28/7, Epic
  steigt pro Welle), 18 neue Upgrades laut Liste (Magnetfeld → Ersatz
  „Combo hält 2 s länger", da keine Coin-Pickups existieren), Karten-Styling
  nach Rarity, Reroll-Button (10 Coins, verdoppelnd pro Run).
  DoD: alle 24 funktional, 3 Testläufe bis Welle 12+, jedes Epic getestet.
- **Phase 2 — Wave-Director:** 4 Elite-Modifikatoren (Flink/Gepanzert/
  Explosiv/Vampirisch, 5→25 % ab Welle 6, Material-Reset beim Pool-Release!),
  4 Wave-Events (GOLD RUSH/BLACKOUT/STAMPEDE/HEAVY DUTY, alle 4–6 Wellen,
  Banner), Boss-Inszenierung (WARDEN INBOUND, Warn-Marker, HP-Balken,
  max. 2 Wardens — spätere mit Elite-Mods statt mehr Masse).
  DoD: alles bis Welle 20 gesehen, kein klebender Elite-Tint, stabile FPS.
- **Phase 3 — Permanente Ökonomie:** 5 Account-Perks à 5 Stufen (Vitalität/
  Kickstart/Schatzsucher/Munitionslager/Sprinter; Vollausbau ≈ 15–20 gute
  Runs), Save-Schema v2 mit v1-Migration, CrazyGames-`data`-Modul als
  Primär-Save (localStorage-Fallback).
  DoD: Perks wirken nachweislich (F3 zeigt effektive Stats), Migration sauber,
  Save überlebt Reload mit und ohne ?cg.
- **Phase 4 — Release-Checkliste:** FTUE (3 Einmal-Hinweise beim allerersten
  Run), happytime bei Epic-Pick ergänzen, QA-Matrix (Chrome/Firefox/Touch/
  Ad-Flows/Tab-Wechsel/Lock-Verlust) in STATUS.md, Performance-Budget
  (60 FPS Mobile @ Welle 15), finaler Build + Submission-README.
