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

## Nebenprojekt im selben Repo 📦
- Unter `turmfall/` liegt ein zweites, eigenständiges Spiel (TURMFALL, physik-basiertes
  Rundenspiel) mit eigener `Turmfall.rbxlx`. Es ist von PlanetForge unabhängig und wird
  von diesem Bauplan NICHT abgedeckt.

## Konzept-Notizen (kein Code) 📝
- `docs/KEYCAP_RUSH_BEWERTUNG.md` — kritische Bewertung des KEYCAP-RUSH-Konzepts
  (eigenes Spielkonzept, liegt NICHT im Repo). Enthält am Ende einen Nachtrag mit den
  Schwachstellen der Bewertung selbst. Kein Einfluss auf PlanetForge oder TURMFALL.
- `keycap/` — Ökonomie-Kern von KEYCAP RUSH (Config + reine Rechenlogik + 21 Tests in
  echter Luau-VM, `cd keycap/tests && npm install && npm test`). Schließt die zwei
  Balancing-Lücken aus der Bewertung. **Noch kein Spiel:** keine Plots, kein Parcours,
  kein Klau-Ablauf, kein DataStore, keine UI — dafür fehlt das Konzeptdokument.
  Offene Zahl: `STAGE_RUN_SECONDS` ist geschätzt und muss in Studio gemessen werden.

## Manuelle Schritte außerhalb des Codes (Noah) 🔑
- Publishing + Creator Dashboard: Gamepässe/Produkte anlegen, echte IDs in
  `src/shared/Config/MonetizationConfig.luau` eintragen (statt der 0-Platzhalter).
  Läuft über das Konto des Vaters.

## Entscheidungen / Notizen 📌
- Core Loop = physisches Sammeln auf eigener Insel (nicht Button-Klicken).
- Design hell/freundlich, kein Navy-Dashboard.
- Server-autoritativ; alle Balancing-Werte in `src/shared/Config`.
