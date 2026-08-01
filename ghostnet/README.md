# GHOSTNET

Roblox-Hacking-Spiel. Nachts in einer Stadt: an ein Objekt herangehen, im
Terminal ein Rätsel lösen, Crypto kassieren — die ist aber erstmal **heiß**.
Jeder Einbruch treibt den **Trace**. Bei 100 ist alles Unverkaufte weg. Beim
**Hehler** wird es gegen Gebühr zu sicherem Guthaben und der Trace sinkt.
Vom Guthaben kauft man **Rig-Upgrades**, die schwerere Ziele öffnen.

Die Frage jeder Runde: *noch ein Ziel mitnehmen oder jetzt abliefern?*

> Eigenständiges Spiel im Repo — unabhängig von PlanetForge (Wurzelverzeichnis)
> und TURMFALL (`turmfall/`). Projektregeln stehen in `CLAUDE.md`, der Bauplan
> in `PHASEN.md`, der aktuelle Stand in `STATUS.md`.

## In Studio öffnen

**Weg A — fertige Datei (am schnellsten)**

```
node tools/build-rbxlx.mjs      # erzeugt ghostnet/GhostNet.rbxlx
```

Danach `GhostNet.rbxlx` doppelklicken.

**Weg B — Rojo**

Rojo mit `ghostnet/default.project.json` verbinden. Das Mapping:

| Ordner       | Ziel in Studio                     |
| ------------ | ---------------------------------- |
| `src/shared` | `ReplicatedStorage.Shared`         |
| `src/server` | `ServerScriptService`              |
| `src/client` | `StarterPlayer.StarterPlayerScripts` |

Die Dateiendung bestimmt den Script-Typ:
`Name.server.luau` = Script · `Name.client.luau` = LocalScript ·
`Name.luau` = ModuleScript.

## Vor dem ersten Test einschalten

**Game Settings → Security → Enable Studio Access to API Services.**
Ohne das erreicht der `SaveService` keinen DataStore. Das Spiel läuft dann zwar
weiter (Notbetrieb mit Profil im Arbeitsspeicher, laute Warnung in der Ausgabe),
speichert aber **nichts** — Fortschritt und Cooldowns wären nach dem Rejoin weg.

## Tests

```
cd tests && npm install && node testlauf.mjs
```

Drei Stufen:

1. **Syntax** — jede `.luau`-Datei wird von einer echten Luau-VM übersetzt
   (der `luau-compile`-Durchlauf).
2. **Struktur** — `--!strict` überall, keine veralteten `wait()`/`spawn()`,
   jede benutzte Remote ist angemeldet, jedes Rate-Limit ist konfiguriert,
   nur der `SaveService` fasst DataStores an.
3. **Logik** — die echten Module laufen in der VM: Config-Formeln,
   Balancing-Vorgaben und das komplette Node-Breach-Minispiel (Lösbarkeit auf
   jeder Schwierigkeit, und der Client bekommt die Lösung nie zu sehen).

## Aufbau

```
src/shared/          -> ReplicatedStorage.Shared
  Config.luau          ALLE Balancing-Zahlen. Sonst nirgendwo welche.
  Remotes.luau         der einzige Ort, an dem Remotes entstehen
  Types.luau           gemeinsame Typen, inkl. Profil-Schema
  Geometry.luau        die eine Abstandsrechnung für Server und Client
  UITheme.luau         Bausteine fürs Fake-OS
src/server/          -> ServerScriptService
  GhostNetServer.server.luau   Bootstrap, feste Init-Reihenfolge
  Systems/
    SaveService.luau     Profil + DataStore + Session-Lock (einziger DataStore-Zugriff)
    EconomyService.luau  Crypto und Rig — einzige Stelle, die beides ändert
    TraceService.luau    Trace, Abkühlung, Bust
    HackService.luau     Sessions, Watchdog, Server-Autorität
    HackTargets.luau     Registry aller Ziele über CollectionService-Tag
    HackEffects.luau     Welteffekte bei Erfolg (Attribut `OnSuccess`)
    SellService.luau     Hehler
    ShopService.luau     Rig-Upgrades
    RateLimiter.luau     Token-Bucket pro Spieler und Remote
    Minigames/NodeBreach.luau
  World/TestTargets.server.luau   Kamera (D2), Tür (D4), Automat (D6), Hehler
src/client/UI/       -> StarterPlayerScripts.UI
  HUD.client.luau      Wallet, Trace-Balken, Prompt, Meldungen
  HackUI.client.luau   das Fake-OS während eines Hacks
  ShopUI.client.luau   Rig-Shop
```

## Neue Objekte in der Welt

Kein Code nötig:

- **Hack-Ziel:** BasePart mit Tag `GhostNetHackable`. Alles Weitere sind
  Attribute (`Difficulty`, `HackType`, `Reward`, `TraceGain`, `Cooldown`,
  `RequiredLevel`, `OnSuccess`, `DownTime`, `DisplayName`). Was fehlt, kommt aus
  `Config.TargetDefaults`.
- **Hehler:** BasePart mit Tag `GhostNetFence`, optional Attribut `DisplayName`.
- **Missions-Wegpunkt:** BasePart mit Tag `GhostNetWaypoint` und Attribut
  `WaypointId`. Löst `GOTO`-Schritte aus, wenn der Spieler nah genug ist.
- **Kontakt:** BasePart mit Tag `GhostNetContact` und Attribut `ContactId`.
  Löst `TALK`-Schritte aus, wenn der Spieler `[E]` drückt.

## Eine Mission schreiben

Missionen sind **Daten**, keine Skripte. Neue Mission = ein Eintrag in
`src/shared/Missions.luau` unter `Missions.List`, sonst nichts. Das Schema
steht in derselben Datei als `Missions.Example` und zeigt jeden Schritt-Typ
genau einmal:

| Typ | Feld | Fertig, wenn … |
| --- | --- | --- |
| `GOTO` | `Target` = WaypointId | der Spieler nah genug am Wegpunkt steht |
| `HACK` | `TargetId` | dieses Ziel **erfolgreich** geknackt wurde |
| `SELL` | `Amount` (Verkäufe) | so oft beim Hehler verkauft wurde |
| `BUY`  | `GoodId?`, `Amount` (Stück) | so viel gekauft wurde (ab Phase C) |
| `WAIT` | `Seconds` | die Zeit abgelaufen ist |
| `TALK` | `ContactId` | der Spieler den Kontakt angesprochen hat |

Der Testlauf prüft die Registry beim Start mit: doppelte Ids, unbekannte
Schritt-Typen, fehlende Pflichtfelder, Vorgänger, die es nicht gibt, und Kreise
in den Vorbedingungen. Fehler tauchen beim Serverstart als `warn()` auf.

## Steuerung

| Eingabe             | Wirkung                                      |
| ------------------- | -------------------------------------------- |
| `E` / Prompt tippen | Ziel hacken bzw. beim Hehler verkaufen        |
| `B` / Knopf unten links | Rig-Shop öffnen                          |
| `Esc`               | Hack abbrechen (kostet halben Trace) / Shop schließen |
