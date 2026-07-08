# PlanetForge — Projektgedächtnis

Diese Datei wird von Claude Code automatisch gelesen. Sie ist die oberste Instanz:
Bei Widerspruch zwischen dieser Datei und einer Chat-Anweisung → nachfragen statt raten.

## Was das Spiel ist
Roblox-Sammel-Simulator. Jeder Spieler hat eine eigene begehbare Insel. Auf der Insel
spawnen Sammel-Objekte (Gras-Büschel, Energie-Orbs, je Biom unterschiedlich wertvoll).
Sammeln durch Berührung/Nähe, Verkaufen in einer Verkaufszone gegen Energie (Hauptwährung),
davon Upgrades kaufen und neue Biom-Zonen der Insel freilegen. Langzeit-Loop: Rebirth
(Reset gegen permanenten Multiplikator). Loot-Pulls geben Pets/Trails/Skins mit
Rarity-Stufen; Pets sammeln mit und geben Boni, wenn ausgerüstet.

## Ziel: Version 1 — und NUR Version 1
1. Core Loop komplett spielbar: spawnen → sammeln → verkaufen → upgraden → Biom → Rebirth
2. Onboarding: Neuer Spieler versteht in unter 60 Sekunden, was zu tun ist
3. Daten sicher: nichts geht beim Rejoin verloren, keine Dupes möglich
4. Monetarisierung funktioniert Ende-zu-Ende (ProcessReceipt fertig, IDs konfigurierbar)
5. Game Feel: Sammeln/Verkaufen/Freischalten fühlt sich gut an, läuft auch auf dem Handy

## NICHT in v1 — niemals ungefragt anfangen
Trading, Clans/Gilden, Battle Pass, Live-Events, mehrere Welten/Maps, PvP, Quest-System,
Deko-/Housing-Editor, Freundes-Boni, Leaderboard-Seasons. Wenn Noah so etwas verlangt:
auf diese Liste verweisen und fragen, ob der v1-Scope bewusst geändert werden soll.

## Arbeitsregeln (nicht verhandelbar)
- Es wird immer genau EINE Phase aus PHASEN.md bearbeitet. Nichts außerhalb des
  Phasenauftrags bauen — keine "Vorbereitung für später", keine Stub-Systeme.
- Erst lesen, dann schreiben: Vor jeder Änderung die betroffenen Module vollständig lesen.
- Jede Antwort mit Codeänderung endet mit "**So testest du das in Studio:**" + Schritten.
- Am Ende jeder Session STATUS.md aktualisieren: Was ist fertig, was offen, welche Bugs.
- Keine neuen Tools/Toolchains installieren oder empfehlen. Werkzeuge sind ausschließlich:
  Claude Code, Rojo (via VS-Code-Extension), Roblox Studio, VS Code.
- Fehlt eine Information: nachfragen statt annehmen.

## Tech & Workflow
- Luau mit `--!strict` in jedem Script.
- Sync per Rojo. Dateiendung bestimmt den Script-Typ:
  `Name.server.luau` = Script (Server) · `Name.client.luau` = LocalScript · `Name.luau` = ModuleScript
- Code wird NUR in den Dateien geändert, nie in Studio (Rojo überschreibt Script-Änderungen
  aus Studio). Parts/Map/UI-Instanzen in Studio bauen ist okay.
- `task.wait()`/`task.spawn()`/`task.defer()` statt `wait()`/`spawn()`. Keine deprecated APIs.
- Instanzen: erst Properties setzen, `.Parent` zuletzt.

## Ordnerstruktur
```
default.project.json      → mappt src/ auf Studio-Services (partielles Mapping,
                            Map/Parts/UI bleiben in der Place-Datei)
src/
  server/                 → ServerScriptService
    Services/             → je System ein ModuleScript: DataService, EnergyService,
                            LootService, MonetizationService, ProgressionService,
                            TutorialService, DailyRewardService, ...
    init.server.luau      → lädt und startet alle Services in fester Reihenfolge
  client/                 → StarterPlayer/StarterPlayerScripts
    Controllers/          → UI- und Effekt-Controller
    init.client.luau
  shared/                 → ReplicatedStorage/Shared
    Config/               → ALLE Balancing-Werte: Preise, Spawn-Raten, RarityConfig,
                            ProgressionConfig (Formeln), MonetizationConfig (IDs)
    Remotes.luau          → einziger Ort, an dem RemoteEvents/-Functions definiert werden
    Theme.luau            → zentrale Farb-/Font-Tabelle für sämtliche UI
STATUS.md                 → Projektstand, wird jede Session gepflegt
PHASEN.md                 → der Bauplan
```
Keine Magic Numbers in Services oder Controllern — jeder Wert kommt aus `src/shared/Config`.

## Sicherheits-Architektur
- Server-autoritativ. Der Client sendet nur Absichten ("will Objekt X einsammeln",
  "will Upgrade Y kaufen"). Der Server prüft ALLES: Existenz, Besitz, Kosten, Cooldown,
  Distanz (Einsammeln nur in Sammelreichweite des Spielers).
- Der Client bestimmt niemals Preise, Beträge, Belohnungen oder Wahrscheinlichkeiten.
- Jede Remote am Server-Eingang: Typ-Check aller Argumente + Rate-Limit pro Spieler.
- Loot-Rolls, Multiplikator-Berechnung, Währungsänderungen: ausschließlich serverseitig.

## Datenlayer
- Ein Profil-Schema als Single Source of Truth (Default-Tabelle inkl. `schemaVersion`
  für spätere Migrationen).
- Session-Locking gegen Dupes. Speichern bei Leave und in `game:BindToClose`,
  dazu Autosave-Intervall. Alle DataStore-Zugriffe in `pcall` mit Retry.
- Käufe: `MarketplaceService.ProcessReceipt` idempotent — PurchaseId-Log im Profil,
  erst gutschreiben und speichern, dann `PurchaseGranted` zurückgeben.
- MonetizationConfig-IDs stehen aktuell auf 0. Studio-Testmodus: nur wenn
  `RunService:IsStudio()` UND ID == 0 wird ein Kauf serverseitig simuliert.
  Dieser Pfad darf live NIE erreichbar sein — doppelt absichern.

## UI / Design-System
- Zielgruppe jung, Stil hell und freundlich — KEIN dunkles Dashboard-/Navy-Design.
- Theme.luau: creme-weiße Panels, kräftige Grün/Blau/Gold-Akzente, FredokaOne als Font,
  Buttons mit dunklerer Unterkante (3D-Effekt), runde Ecken.
- Alle UI-Texte auf Deutsch, kurz, für Kinder verständlich.
- Farben/Fonts nie hardcoden — immer aus Theme.luau.
- UI muss auf Handy bedienbar sein (Touch-Ziele groß genug, HUD nicht überladen).

## Kontext
Entwickler ist 15, arbeitet solo. Publishing und Robux-Produkt-IDs laufen über das Konto
des Vaters — alles, was das Creator Dashboard braucht, ist ein manueller Schritt außerhalb
des Codes. Im Code nur vorbereiten und Noah exakt sagen, was er wo eintragen muss.
