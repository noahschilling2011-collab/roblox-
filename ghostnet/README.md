# GHOSTNET

Roblox-Hacking-Spiel in der offenen Stadt Vantorra, bei hellem Tag: an ein
Objekt herangehen, im Terminal ein Rätsel lösen, Crypto kassieren — die ist
aber erstmal **heiß**.
Jeder Einbruch treibt den **Trace**. Bei 100 ist alles Unverkaufte weg. Beim
**Hehler** wird es gegen Gebühr zu sicherem Guthaben und der Trace sinkt.
Vom Guthaben kauft man **Rig-Upgrades**, die schwerere Ziele öffnen.

Die Frage jeder Runde: *noch ein Ziel mitnehmen oder jetzt abliefern?*

Ziele auf **offener Straße** (Attribut `Exposed`) zahlen 35 % mehr und kosten
30 % mehr Trace. Gedeckte Ziele — drinnen, im Hinterhof, auf dem Dach — zahlen
normal und sind sicherer. Das ist die Entscheidung, um die es beim *Wohin*
geht.

**Kein GTA-Klon mit Hacking, sondern ein Hacking-Spiel mit offener Stadt.**
Daraus folgt der Rest: keine Schusswaffen, kein Kampfsystem. Autos sind
Werkzeug — schneller da, mehr Lager, schneller weg. Die Polizei verfolgt, sie
schießt nicht; gefasst zu werden ist derselbe Bust wie ein Trace von 100.

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
   nur der `SaveService` fasst DataStores an, kein Require-Kreis zwischen den
   Services, zu jeder Schema-Version eine Migration. Für die offene Welt
   zusätzlich: kein `PathfindingService` und kein `Humanoid` im Verkehr, kein
   `Heartbeat` über die ganze Stadt, keine Waffen in der Verfolgung.
3. **Logik** — die echten Module laufen in der VM: Config-Formeln,
   Balancing-Vorgaben, die Missionskette, der Darknet-Markt, Bezirke,
   Verkehrsgrenzen, Fahndungsstufen und das komplette Node-Breach-Minispiel
   (Lösbarkeit auf jeder Schwierigkeit, und der Client bekommt die Lösung nie
   zu sehen).

**Was der Testlauf nicht kann:** Bildrate, Fahrgefühl, Physikstabilität. Dafür
gibt es keine Roblox-Laufzeit, nur eine Luau-VM — das muss im MicroProfiler in
Studio gemessen werden. Die Regler dafür stehen in `Config.Traffic` und
`Config.City`.

## Aufbau

```
src/shared/          -> ReplicatedStorage.Shared
  Config.luau          ALLE Balancing-Zahlen. Sonst nirgendwo welche.
  Remotes.luau         der einzige Ort, an dem Remotes entstehen
  Types.luau           gemeinsame Typen, inkl. Profil-Schema
  Geometry.luau        die eine Abstandsrechnung für Server und Client
  Config.luau/Palette  Weltfarben (hell) - getrennt vom dunklen Fake-OS-Theme
  AssetLibrary.luau    Vorlagen nachschlagen, klonen, Fehlendes melden
  Missions.luau        Missionen als Daten + die puren Regeln dazu
  Vehicles.luau        Fahrzeugklassen als Daten
  Districts.luau       die fünf Stadtbezirke als Daten
  Goods.luau           Warenkatalog fürs Darknet
  SoundCatalog.luau    alle Klänge (IDs leer)
  UITheme.luau         Bausteine fürs Fake-OS
src/server/          -> ServerScriptService
  GhostNetServer.server.luau   Bootstrap, feste Init-Reihenfolge
  AdminList.luau       UserId-Liste. Bewusst NICHT in Shared.
  Systems/
    SaveService.luau        Profil + DataStore + Session-Lock (einziger DataStore-Zugriff)
    EconomyService.luau     Crypto und Rig — einzige Stelle, die beides ändert
    TraceService.luau       Trace, Abkühlung, Bust
    HackService.luau        Sessions, Watchdog, Server-Autorität
    HackTargets.luau        Registry aller Ziele über CollectionService-Tag
    HackEffects.luau        Welteffekte bei Erfolg (Attribut `OnSuccess`)
    SellService.luau        Hehler
    ShopService.luau        Rig-Upgrades
    RaidService.luau        Alarm-Uhr für mehrstufige Ziele, Co-Op
    MissionService.luau     Story-Fortschritt, serverseitig geprüft
    TimeService.luau        Tag/Nacht - Uhr, Licht, Nachtbonus
    VehicleChassis.luau     baut Fahrzeuge aus dem Datensatz
    VehicleService.luau     Besitz, Kauf, Ausparken, Lackierung
    RoadNetwork.luau        Strassengraph, aus Config.City gerechnet
    TrafficService.luau     Verkehr und Fussgaenger, gepoolt und begrenzt
    PursuitService.luau     Fahndungsstufe, Streifen, Sperren, Hubschrauber
    GuardService.luau       Wachen mit Sichtkegel - melden, greifen nie an
    MapService.luau         sammelt, was wo steht (Karte)
    MarketService.luau      Darknet-Kurse, serverweit
    InventoryService.luau   Lager und Handel
    MonetizationService.luau Gamepässe und Produkte (IDs = 0)
    AdminService.luau       Admin-Befehle, UserId-Prüfung in Zeile 1
    RateLimiter.luau        Token-Bucket pro Spieler und Remote
    Minigames/NodeBreach.luau
  World/
    TestTargets.server.luau  Kamera (D2), Tür (D4), Automat (D6), Hehler
    StoryWorld.server.luau   Übungsterminal, Laden, Apartment, Bank
    TestVehicles.server.luau ein Fahrzeug jeder Klasse am Spawn
    City.server.luau         die Stadt: Straßen, Häuser, Dächer, Neon
    Dealership.server.luau   Autohaus mit Showroom, Garage, Bezirks-Wegpunkte
    BankInterior.server.luau Halle, Sicherheitsbereich, Tresorraum, Lüftung
src/client/World/    -> StarterPlayerScripts.World
  TrafficSmoother.client.luau  zieht servergesetzte Modelle weich nach
src/client/UI/       -> StarterPlayerScripts.UI
  HUD.client.luau          Wallet, Trace-Balken, Prompt, Meldungen
  HackUI.client.luau       das Fake-OS während eines Hacks
  ShopUI.client.luau       Rig-Shop
  MissionUI.client.luau    Auftrag und Wegpunkt
  TutorialUI.client.luau   geführter Einstieg und Alarm-Anzeige
  DarknetUI.client.luau    Markt, Chart, Lager
  StoreUI.client.luau      Robux-Store
  AdminUI.client.luau      Admin-Panel (F2)
  SoundController.client.luau  spielt den SoundCatalog
  TargetBeacons.client.luau    lässt Ziele auf Distanz pulsieren
  VehicleController.client.luau  Fahren: Steuerung, Kamera, Klang, Tacho
  CityUI.client.luau       Fahndungssterne, Garage, Endgame-Entscheidung
  MapUI.client.luau        Minikarte unten rechts + grosse Karte [M]
```

## Wo die Modelle liegen

> **Code platziert Geometrie. Code baut keine Geometrie.**

Alles, was ein Spieler bewusst ansieht, liegt als fertiges Modell unter
`ReplicatedStorage/Assets` und wird von dort geklont:

```
ReplicatedStorage/Assets/
    Vehicles/     Compact, Sedan, Sports, Van, Bike, Police
    Buildings/    Base_*, Floor_*, Roof_*
    Props/        Laterne, Ampel, Muelltonne, Poller, Verteiler, Schild, Feuerleiter
    Characters/   Pedestrian, Guard
```

Prozedural bleibt nur, wo Genauigkeit statt Aussehen zählt: Straßenverlauf,
Kollisionsboxen, unsichtbare Trigger, Wegpunkte.

**Fehlt eine Vorlage, wird sie nicht aus Parts nachgebaut.** Stattdessen
erscheint ein knallmagenta `MISSING_ASSET_<Ordner>_<Name>` in der richtigen
Größe, und beim Serverstart steht in der Ausgabe, was noch fehlt. Das Spiel
bleibt dabei fahrbar — es sieht nur absichtlich kaputt aus. Welche Modelle
gebraucht werden und welche Teile ein Fahrzeugmodell enthalten muss, steht in
`STATUS.md` unter „Manuelle Schritte".

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
- **Autohändler:** BasePart mit Tag `GhostNetDealer`. Öffnungszeiten kommen aus
  `Config.Dealer`, nicht aus dem Part.
- **Ausparkplatz:** BasePart mit Tag `GhostNetVehicleSpawn`. Nur dort lässt sich
  ein eigenes Fahrzeug ausparken.
- **Wache:** Model mit Tag `GhostNetGuard` und den Attributen `PatrolA`,
  `PatrolB` (Vector3) und `AlarmGroup`. Optional `SightFactor` (0–1), damit
  eine Wache im Gebäude weniger weit sieht als eine draußen. Läuft die Strecke
  ab und meldet, was sie sieht — angreifen kann sie nicht.

Beim Hack-Ziel ist `Exposed = true` das wichtigste optionale Attribut: es
markiert ein Ziel als „steht offen auf der Straße" und schaltet damit den
Risiko-Bonus aus `Config.Cover` an. Ohne das Attribut gilt das Ziel als
gedeckt.

**Farben nie im Skript.** Jede Weltfarbe kommt aus `Config.Palette` — der
Testlauf lehnt ein `Color3.fromRGB` in `src/server/World/` ab. Die Stadt
heller oder dunkler zu machen ist eine Änderung an einer Tabelle.

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

| Eingabe | Wirkung |
| --- | --- |
| `E` / Prompt tippen | Ziel hacken, beim Hehler verkaufen, Kontakt ansprechen, Darknet öffnen |
| `B` / Knopf unten links | Rig-Shop |
| `P` / Knopf unten links | Robux-Store |
| `F2` | Admin-Panel (nur wenn autorisiert) |
| Einsteigen-Prompt | Fahrzeug betreten |
| `W`/`S`, `A`/`D` | Gas und Bremse, Lenken |
| `E` halten am Verkehrsauto | kurzschließen — kostet Trace und Fahndung |
| `G` | Garage: eigenes Fahrzeug ausparken (nur auf dem Ausparkplatz) |
| `M` / Tippen auf die Minikarte | grosse Karte mit Legende |
| `Esc` | Hack abbrechen (kostet halben Trace) / Fenster schließen |

Alles ist auch per Touch bedienbar — keine Funktion hängt nur an der Tastatur.

## Der Spielablauf

Zehn Missionen, eine Kette. Jede ist gleichzeitig das Tutorial für ein System
**und** schaltet dieses System dauerhaft frei — nichts verschwindet danach.

| # | Titel | Bringt bei |
| --- | --- | --- |
| M01 | Erster Kontakt | hacken und verkaufen — Übungsterminal ohne Risiko |
| M02 | Kalter Anlauf | Alarm-Uhr, mehrstufige Ziele (Ladenüberfälle) |
| M03 | Vier Wände | das Apartment als Hub, Darknet offen |
| M04 | Kurzschluss | ein Verkehrsauto stehlen — und dass man dabei gesehen wird |
| M05 | Auf Rädern | Autohaus, Öffnungszeiten, eigener Wagen in der Garage |
| M06 | Der Hafen | Container am Nordkai: große Ware, man braucht Ladefläche |
| M07 | Blaulicht | die Fahndung abschütteln, bevor sie einen zum ersten Mal holt |
| M08 | Glashaus | die Bank auskundschaften: Kameras, Wachen, Schleuse |
| M09 | Der Tresor | der Raub — und in den Protokollen steht dein eigener Name |
| M10 | Wren | keine Aufgabe, eine Entscheidung |

**M10 ist die Entscheidung:** *Kassieren* (bei Meridian anheuern — halber
Trace, dafür weniger Beute) oder *Verbrennen* (alles veröffentlichen — mehr
Ertrag, härtere Fahndung, bessere Darknet-Kurse). Sie steht im Profil und
lässt sich einmal pro Woche umstellen.

Nach M10 gibt es kein „durchgespielt": Stadt, Verkehr, Bank, Darknet und
Fahndung laufen weiter.

## Was Noah eintragen muss

Alle IDs im Code sind Platzhalter — erfundene IDs schlagen stumm fehl.

| Datei | Was |
| --- | --- |
| `src/shared/SoundCatalog.luau` | Asset-IDs als `"rbxassetid://ZAHL"` |
| `src/server/Systems/MonetizationService.luau` | Gamepass- und Produkt-IDs (stehen auf `0`) |
| `src/server/AdminList.luau` | die eigene UserId |

Das Spiel läuft auch ohne: es ist dann stumm, der Store leer, und Admin gibt es
nur im Studio.
