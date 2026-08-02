# STATUS.md — Projektstand PlanetForge

> Diese Datei wird am Ende JEDER Claude-Code-Session aktualisiert.
> Sie ist das Erste, was eine neue Session liest, um den Stand zu kennen.

## Aktuelle Phase
**Alle Phasen 0–6 sind funktional gebaut.** PlanetForge ist im Repo ein vollständig
spielbares Spiel (Server + Client + Config + Tests + direkt öffnbare `PlanetForge.rbxlx`).
→ Nächster sinnvoller Schritt ist NICHT "Phase 0 neu", sondern: v1 mit echten Spielern
testen ODER gezielt eine Baustelle unten abarbeiten (siehe "Offen").

## Fertig ✅
- **Phase 0 – Struktur & Rojo:** `default.project.json` (partielles Mapping src/ → Services),
  `init.server.luau` / `init.client.luau` starten alle Systeme in fester Reihenfolge,
  Smoke-Prints vorhanden.
- **Phase 1 – Datenlayer:** `DataService` mit Profil-Schema (`PROFILE_SCHEMA_VERSION = 10`,
  generische Migration), Session-Locking, Autosave, Speichern bei Leave + `BindToClose`,
  `pcall`+Retry. PurchaseId-Log im Profil.
- **Phase 2 – Core Loop:** begehbare Insel je Spieler, `HarvestService` (physisches Sammeln
  serverseitig distanzvalidiert), Magnet-Radius + Rucksack als Upgrades, Verkaufszone,
  Live-HUD. Balancing in `src/shared/Config`.
- **Phase 3 – Progression & Rebirth:** `ProgressionConfig` (zentrale Multiplikator-Formel,
  exponentielle Upgrade-Kosten), sichtbare Biom-Zonen (Nebel löst sich beim Kauf),
  Rebirth mit Vorher/Nachher-Dialog + permanentem Multiplikator.
- **Phase 4 – Onboarding:** `TutorialService` + `TutorialController`, geführte Schritte
  mit Highlight, serverseitig gespeicherter Fortschritt (startet nach Rejoin nicht neu),
  Abschluss-Belohnung.
- **Phase 5 – Monetarisierung:** `MonetizationService` mit idempotentem `ProcessReceipt`
  (PurchaseId-Log), Währungspakete, Instant-Rebirth, Gamepässe (2× Mult, +Pet-Slots, VIP),
  Studio-Testmodus hart per `RunService:IsStudio()` + ID==0 abgesichert, Shop-UI.
- **Phase 6 – Game Feel & Mobile:** `EffectsController` (Fly-to-Player, Pop-Sounds,
  Münz-Regen, Count-up, Partikel), Loot-Roll-Spannung, Lighting/Bloom, Touch-Bedienung.
- **Tests:** `node tests/testlauf.mjs` → **24/24 grün** (echte Luau-VM + Remote-Abgleich).
- **Build:** `node tools/build-rbxlx.mjs` erzeugt `PlanetForge.rbxlx` (direkt in Studio öffenbar).

## In Arbeit 🔧
- (nichts aktiv)

## Offen / Nächster Schritt ➡️
- **v1 validieren:** Mit echten Spielern testen (Retention/Feedback), bevor mehr gebaut wird.
- **Theme.luau fehlt (Design-System-Lücke):** CLAUDE.md fordert eine zentrale
  `src/shared/Theme.luau` (Farben/Font). Aktuell sind UI-Farben in den Controllern
  direkt gesetzt. Wenn gewünscht: Theme.luau nachziehen und Controller darauf umstellen.
- **MonetizationConfig-IDs stehen auf 0** → siehe "Manuelle Schritte".

## ⚠️ Abweichung vom v1-Scope (bewusst prüfen)
Der aktuelle Build enthält Systeme, die in CLAUDE.md unter **"NICHT in v1"** stehen —
sie wurden in früheren Sessions auf ausdrücklichen Wunsch gebaut:
- `TradeService` (Trading), `QuestService` (Quest-System), ein Freunde-Boost.
Das ist kein Bug, aber es weicht vom dokumentierten v1-Ziel ab. Entscheiden: im Build
lassen (Scope offiziell erweitern) oder für den ersten Launch deaktivieren.

## Bekannte Bugs 🐞
- (keine offen erfasst; letzter Testlauf 24/24 grün)

## Nebenprojekte im selben Repo 📦
Beide sind von PlanetForge unabhängig und werden von diesem Bauplan NICHT abgedeckt.
Sie haben eigene `CLAUDE.md`/`PHASEN.md`/`STATUS.md` in ihrem Ordner — die gelten dort
vor dieser Datei.
- `turmfall/` — TURMFALL, physik-basiertes Rundenspiel, eigene `Turmfall.rbxlx`.
- `ghostnet/` — GHOSTNET, Hacking-Spiel (helle Stadt, dunkles Fake-OS), eigene `GhostNet.rbxlx`.
  Stand: v2.4.0 — Orientierung, Story und Polizei: drehbare Minikarte oben
  rechts, Route als Leuchtspur auf der Straße, Kompassleiste, beschilderte
  Gebäude, Telefon-Chat mit Wren als Story-Träger, und eine Polizei, die ab
  Stufe 3 aussteigt, zu Fuß verfolgt und in einer echten Wache festnimmt.
  Darunter v2.3.0 — Karte und größere Stadt (720 statt 480 Studs Kante). Darunter v2.2.0 — Rework von Optik und Verkehr: der Dach-Bug (WeldConstraint
  zwischen Anchored-Teilen) ist an allen vier Stellen behoben, Modelle bewegen
  sich über `PivotTo`, und sichtbare Geometrie kommt jetzt als Vorlage aus
  `ReplicatedStorage/Assets` statt aus Parts. Solange dort keine Modelle
  liegen, steht überall ein magenta Platzhalter — Absicht, nicht Defekt.
  Darunter v2.1.0 — helle Stadt bei dauerhaftem Tag (der Nachtbonus hängt
  am Ort statt an der Uhrzeit: offene Ziele zahlen mehr und kosten mehr Trace).
  Darunter v2.0.0, der Umbau zur offenen Stadt: Bezirke mit gerechnetem
  Straßengraph, Verkehr und Fußgänger (gepoolt, ohne PathfindingService),
  Fahrzeugbesitz mit Autohaus und Garage, Bankraub mit drei Wegen, Polizei-
  Verfolgung ohne Waffen und eine 10-Missionen-Story mit Entscheidung am Ende.
  Profil-Schema steht auf Version 5 (Migration 4 → 5: Garage + Allegiance).
  Testlauf 719/719 grün. **Bildrate ist ungemessen** — dafür braucht es den
  MicroProfiler in Studio, nicht die Luau-VM des Testlaufs.
  Alle Asset-/Produkt-IDs sind noch Platzhalter.

## Manuelle Schritte außerhalb des Codes (Noah) 🔑
- Publishing + Creator Dashboard: Gamepässe/Produkte anlegen, echte IDs in
  `src/shared/Config/MonetizationConfig.luau` eintragen (statt der 0-Platzhalter).
  Läuft über das Konto des Vaters.

## Entscheidungen / Notizen 📌
- Core Loop = physisches Sammeln auf eigener Insel (nicht Button-Klicken).
- Design hell/freundlich, kein Navy-Dashboard.
- Server-autoritativ; alle Balancing-Werte in `src/shared/Config`.
