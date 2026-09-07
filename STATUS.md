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
- `keycap/` — KEYCAP RUSH, spielbarer Kern: Plots mit Tasten-Steckplätzen, Produktion
  pro Taste, Speed-Tore, Cash-Out-Pads, Klau mit Paar-Cooldown und Schild, Laden,
  DataService mit Session-Lock. 26 Luau-Dateien, eigenes `default.project.json`.
  Dazu NPC-Plots als Klau-Ziele, sichtbares Tragen der Beute, Rundlaufzeit-Messung,
  ein Part-Budget-Check beim Serverstart und ein vierstufiges Onboarding
  (Fortschritt im Profil, Schema-Version 2).
  Design-System: `Theme.luau` (Farben/Abstände/Schriftskala) + `UiKit.luau` (Panel,
  Text, Knopf, UIScale), Tastenbuchstaben auf den Parts, `LightingService`.
  Kontrast wird im Testlauf nach WCAG nachgerechnet — vier Lesbarkeitsfehler behoben,
  darunter die Wins-Zahl mit 2,45:1.
  `node keycap/tools/build-rbxlx.mjs` erzeugt `keycap/KeycapRush.rbxlx` (direkt in
  Studio öffenbar, kein Rojo nötig) — inklusive gebackener Weltvorschau, damit beim
  Öffnen nicht nur ein Spawn-Pad dasteht. `WorldLayout.luau` ist die gemeinsame Quelle
  für Server und Build-Script.
  `cd keycap/tests && npm install && npm test` → 66 Tests + Syntaxprüfung aller Dateien.
  **Nie in Roblox gelaufen** — nur Syntax und reine Logik geprüft.
  Nicht drin: Monetarisierung, Sounds/Effekte.
  Offene Zahl: `STAGE_RUN_SECONDS` ist geschätzt — `RunTimerService` misst sie im Spiel
  und gibt die fertige Config-Zeile ins Output-Fenster aus, sie muss nur übernommen werden.
  Das Konzeptdokument fehlt weiterhin im Repo; Kartenaufbau, Datenschema und UI sind
  daher Entscheidungen, keine Vorgaben (im Code markiert).

## Manuelle Schritte außerhalb des Codes (Noah) 🔑
- Publishing + Creator Dashboard: Gamepässe/Produkte anlegen, echte IDs in
  `src/shared/Config/MonetizationConfig.luau` eintragen (statt der 0-Platzhalter).
  Läuft über das Konto des Vaters.

## Entscheidungen / Notizen 📌
- Core Loop = physisches Sammeln auf eigener Insel (nicht Button-Klicken).
- Design hell/freundlich, kein Navy-Dashboard.
- Server-autoritativ; alle Balancing-Werte in `src/shared/Config`.
