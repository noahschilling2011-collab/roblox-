# STATUS.md — Projektstand GhostNet

> Wird am Ende jeder Session aktualisiert. Erstes, was eine neue Session liest.

## Aktuelle Phase
**Alles abgearbeitet, zuletzt v2.5.0 „Fahrzeuge"**
(`Config.Version = "2.5.0"`). Aus dem Hacking-Spiel ist ein Hacking-Spiel mit
offener Stadt geworden — Bezirke, Verkehr, Autobesitz, ein Bankraub mit drei
Wegen, eine Polizei ohne Waffen und eine 10-Missionen-Story mit Entscheidung
am Ende. Seit v2.1.0 spielt das Ganze bei **hellem Tag**.

**Nächster Schritt: kein Code, sondern Messen und Spielen.** Siehe die
Warnung direkt darunter und Punkt 0 am Ende von `PHASEN.md`.

## ⚠️ Was ich NICHT prüfen konnte
Der Bauplan verlangt nach jeder Phase eine **gemessene Bildrate**. Das kann ich
nicht liefern und erfinde die Zahl auch nicht: Ich habe keine Roblox-Laufzeit,
nur eine Luau-VM für Syntax und Logik. Die 725 Prüfungen sagen **nichts** über
Bildrate, Fahrverhalten oder Physikstabilität aus. Das muss Noah im
MicroProfiler messen, und zwar besonders jetzt — Verkehr, Fußgänger,
Streifenwagen und eine gebaute Stadt sind zusammen der teuerste Teil des
Projekts.

Die Regler dafür stehen alle in `Config.luau` und sind bewusst niedrig
gesetzt. In dieser Reihenfolge drehen, wenn es ruckelt:
**`City.Grid` (7)** → `Traffic.MaxActive` (20) → `Traffic.MaxPedestrians`
(16) → `Assets.PropChance` (0.55) → `Traffic.ActiveRadius` (320) →
`World`-Streamingradien.

**Seit v2.1.0 wichtiger als vorher:** früher startete der Server nachts und
fuhr damit auf halber Verkehrsdichte. Bei dauerhaftem Tag läuft die Stadt
dauerhaft am vollen `Traffic.MaxActive` — also auf der doppelten Last
gegenüber dem alten Standardzustand. Gegengerechnet: die PointLights an den
Neonschildern entfallen bei Tag komplett.

## Fertig ✅

### v2.5.0 — Fahrzeuge sehen aus wie Fahrzeuge (Noahs Fassung)
Noah hat eine komplette `VehicleChassis` geliefert und damit zwei Dinge
korrigiert, die ich falsch hatte.

**1. Die Räder sind weggeflogen — drei Fehler auf einmal:**
- Zylinderräder wurden um 90° um Z gedreht. Ein Roblox-Zylinder dreht um seine
  **lokale X-Achse**, und die seitliche Achse des Fahrzeugs *ist* X. Die
  Drehung hat das Rad flach wie einen Teller gelegt und die Antriebsachse nach
  oben gekippt — der Motor drehte das Rad um die falsche Achse.
- `SpringConstraint` und `CylindricalConstraint` hingen am **selben
  Attachment-Paar**, beide mit `LimitsEnabled`. Zwei Limit-Solver auf einem
  Freiheitsgrad schaukeln sich auf. Jetzt führt nur der Cylindrical die
  Grenzen, die Feder liefert nur Kraft.
- `MotorMaxAngularAcceleration = math.huge` — unendlich ist im Solver ein
  NaN-Generator, und ein NaN schleudert die ganze Baugruppe ins Nichts.

**2. Die Asset-Regel war zu streng.** Ich hatte alles auf fertige Modelle
umgestellt und den Platzhalterpfad als Absperrung gebaut. Nur: die Ordner
blieben leer, also lief *jedes* Auto über den Platzhalter. Jetzt baut
`buildBody()` eine echte Silhouette — Motorhaube, abfallende Dachlinie,
Kotflügel, Fenster, Grill, Lichter — aus einem Profil je Klasse. Ein
hochgeladenes Modell hat weiter Vorrang.

**Zwei Ergänzungen von mir:**
- Die zwei neuen Zahlen (`90000`, `500`) stehen jetzt als
  `Config.Vehicle.SteerServoTorque` und `MotorMaxAcceleration` in Config —
  Regel 3 gilt auch für Bugfixes.
- **`VehicleChassis.BuildShell`**: Verkehr und Streifenwagen holen ihre
  Karosserie aus demselben Bauplan. Ohne das hätte der Spieler ein richtiges
  Auto und der Verkehr weiter magenta Klötze — und ein gestohlenes Auto hätte
  beim Kurzschließen sichtbar die Form gewechselt. Der Streifenwagen bekommt
  dabei einen hellen Polizeilack (`Config.Pursuit.UnitColour`).

Projektgedächtnis Regel 7 ist entsprechend umgeschrieben, Regel 8 hält die drei
Physik-Fallen fest. Fünf neue Testlauf-Einträge verhindern, dass die
Radrotation, `math.huge` oder das geteilte Attachment-Paar zurückkommen.

### v2.4.0 — Orientierung, Story, Polizei
Drei Probleme, in dieser Reihenfolge: niemand wusste, wo etwas ist; die Story
war gebaut, aber unsichtbar; die Polizei verfolgte, nahm aber niemanden fest.

#### Phase 1 — Orientierung
- **Minikarte oben rechts, dauerhaft.** Dreht sich mit der Blickrichtung
  (genordet ist sie beim Fahren unlesbar), Nordpfeil bleibt fest, zwei
  Zoomstufen automatisch: zu Fuß nah, im Auto weit. HUD-Wallet und Trace sind
  darunter gewandert — die Position wird aus `Config.Map` gerechnet, damit
  sich beide nie überlappen.
- **Ein Symbol je Bedeutung** (`Shared/Icons.luau`, neu): Haus, Banknote,
  Schlüssel, Tresor, Chip, Stern, Auto, Schild — auf Minikarte, großer Karte,
  Legende und Kompass dasselbe. Aus Frames gezeichnet, **keine Asset-IDs**.
- **Route auf der Straße** — der wichtigste Einzelpunkt. `RoadNetwork.FindPath`
  (Dijkstra über denselben Graphen, auf dem Verkehr und Polizei fahren) +
  `RouteService` (Server rechnet) + `Client/World/RouteMarkers` (Client
  zeichnet). **Der Client zeichnet, weil eine Route genau einem Spieler
  gehört** — serverseitige Parts sähe jeder. Die Spur verblasst hinter dem
  Spieler und löst sich bei Ankunft auf.
- **Kompassleiste oben Mitte** mit Himmelsrichtungen und Entfernung in Metern.
  Das Missionsziel klebt am Rand, statt zu verschwinden.
- **Beschilderung** (`World/Signage`, neu): Leuchtschrift über Bank, Autohaus,
  Apartment, Pfandleihe und Garage; Straßenschilder an jeder Kreuzung mit
  echten Namen aus zwei kurzen Listen; Apartment mit Hausnummer und eigenem
  Licht; Bezirksname beim Betreten als Einblendung.
- **„Wo ist mein Auto"**: orangener Marker plus *Fahrzeug rufen* gegen Gebühr,
  mit Cooldown und nur an einer Straße.

#### Phase 2 — Die Story sichtbar machen
- **Das Telefon** (`PhoneService` + `PhoneUI`, neu): Knopf unten rechts,
  pulsiert bei neuer Nachricht. Chatverlauf mit Wren, Nachrichten einzeln mit
  Tippanimation, „Annehmen" setzt sofort den Wegpunkt — und damit die Route.
- **Kein neues Speicherfeld.** Der Verlauf wird bei jedem Sync aus dem
  Story-Zustand gebaut (erledigte Missionen + aktive). Damit ist er
  automatisch korrekt, überlebt jeden Serverwechsel und das **Profil-Schema
  bleibt auf Version 5 — es gibt nichts zu migrieren**. Ein zweites,
  mitgeschriebenes Chatprotokoll wäre eine zweite Wahrheit.
- **Auftrags-Tracker links oben**, dauerhaft: Titel, aktueller Schritt,
  Entfernung. Ohne Auftrag steht dort, was zu tun ist — nie eine leere Ecke.
- **Wiedereinstieg**: „Zuletzt: … Wren wartet auf Antwort."

#### Phase 3 — Polizei, die aussteigt und festnimmt
- **Zwei Polizeiwachen** (`World/PoliceStations`, neu) mit Zelle, Ausgang und
  blauem Schild auf der Karte. **Ohne Ort ist eine Festnahme nur ein
  Bildschirmtext.**
- **Ab Stufe 3 steigen Polizisten aus.** Echte NPCs mit `Humanoid`, Verfolgung
  zu Fuß über `PathfindingService`. **Hier ist er richtig** — verboten ist er
  für Verkehrsautos, wo Dutzende Pfade pro Sekunde den Server fressen; hier
  laufen ein paar Polizisten, und ein Mensch um eine Hausecke braucht einen
  echten Weg. Neu gerechnet wird nur alle `OfficerRepath` (0,5 s). Verliert
  ein Polizist die Sicht (Raycast), läuft er zur letzten bekannten Position.
- **Die Festnahme** (`ArrestService`, neu): „FESTGENOMMEN", kurze Blende,
  Zelle, Countdown, Entlassung vor der Wache. **Konsequenzen ausschließlich
  über bestehende Systeme** — `EconomyService.WipeUnsold`,
  `InventoryService.ConfiscateFraction`, Trace auf `Config.Trace.AfterBust`,
  gedeckelte Gebühr. Kein zweites Strafsystem.
- **Fair bleiben**: sichtbarer Entkommen-Balken in Prozent, Vorwarnung
  („ZUGRIFF") vor jedem Zugriff, Verfolgung endet spätestens nach
  `MaxDuration`. **Kein Kampf, keine Waffen** — der Testlauf lehnt sie ab.

#### Phase 4 — Fahrgefühl
Netzwerkbesitz, FOV-Tween 70→85, tempoabhängige Lenkung, Bremslichter,
Motor-Tonhöhe und Bremsspuren waren schon da. Neu: **tiefer Schwerpunkt** über
ein unsichtbares Gewicht unter dem Chassis — ohne das kippt in Roblox
praktisch jedes Fahrzeug in der ersten Kurve. Bremslichter erkennen jetzt auch
`Lights/TailL` / `TailR` aus dem Modellvertrag.

#### `ASSETS_TODO.md`
Neu im Projektordner: jedes fehlende Modell mit Ordner, exaktem Namen,
Pflicht-Kindern, ungefähren Maßen und Bezugsquelle — sortiert nach Wichtigkeit.
`AssetLibrary.Report()` schreibt dieselbe Liste beim Serverstart in die
Ausgabe, inklusive der erwarteten Kindteile.

### v2.3.0 — Karte und größere Stadt

#### Karte
Zwei Ansichten, **eine** Datenquelle (`Remotes.MapSync`) — es kann keine
zweite Karte geben, die von der Welt abweicht.

- **Minikarte** (in v2.4.0 nach oben rechts gewandert und drehbar geworden).
  Folgt dem Spieler, antippen öffnet die große.
- **Große Karte** auf `M`: ganze Stadt, Bezirke farbig hinterlegt mit Namen,
  **Legende** unten links. Das ist die Antwort auf „wo ist eigentlich was".
- Drauf sind: Hehler, Autohaus, Garage, Kontakte, Hack-Ziele — **offene Ziele
  in eigener Farbe**, weil dort mehr Geld *und* mehr Trace liegt — und der
  aktive Auftrags-Wegpunkt (kommt aus `WaypointSync`, nicht aus `MapSync`,
  weil er ständig wechselt).
- Beim Einsteigen ins Auto schließt sich die große Karte von selbst.

**`Systems/MapService.luau`** (neu) sammelt serverseitig. Grund: mit
`StreamingEnabled` hat der Client entfernte Teile gar nicht geladen — eine
Karte, die selbst per `CollectionService` im Workspace nachschaut, würde genau
das zeigen, was ohnehin schon zu sehen ist. Gesendet wird gebündelt
(`Config.Map.SyncDebounce`), sonst feuert der Weltaufbau hunderte Pakete.

Die Karte verrät **wo** etwas steht, nicht **wie** man es knackt: keine
Schwierigkeit, keine Cooldowns, keine Rätseldaten. Der Testlauf prüft das.

**Keine Bild-Assets.** Straßen sind gedrehte Frames, Symbole kleine Quadrate.
Die Karte funktioniert sofort, ohne dass irgendeine ID eingetragen wird — als
einziges größeres UI-Stück hat sie damit keine offene Abhängigkeit.

**Leistung:** der Inhalt wird *einmal* gebaut. Pro Bild ändern sich genau zwei
Dinge — die Position des Inhalts-Containers und der Winkel des
Spielersymbols. Nicht hundert Straßen einzeln.

#### Größer
| | vorher | jetzt |
|---|---|---|
| `Config.City.Grid` | 5 | **7** |
| Kantenlänge | 480 Studs | **720 Studs** |
| Blöcke | 16 | **36** |
| Altstadt `Radius` | 1 | **2** |

Die Altstadt wächst mit. Wäre sie bei Radius 1 geblieben, wäre der ausgebaute
Bezirk in der größeren Stadt zu einem Fleck im Rohbau geworden — und „eine
große leere Stadt ist schlimmer als ein kleiner voller Block".

⚠️ **`Config.City.Grid` ist der größte Bildraten-Hebel im Projekt.** Die
Blockzahl wächst quadratisch, und an jedem Block hängen vier Häuser aus
mehreren Modulen: von 5 auf 7 sind das rund **2,25× so viele Gebäude**. Erst
messen, dann weiter hochdrehen. Wenn es ruckelt, ist das die erste Zahl, die
wieder runtergeht.

### v2.2.0 — Rework: Optik und Verkehr

#### Der Bug hinter „der Verkehr sieht kaputt aus"
`WeldConstraint` gilt für die **Physiksimulation**. Zwischen zwei
`Anchored`-Teilen tut sie gar nichts, und ein direktes `.CFrame`-Setzen ist
keine Simulation. Verkehrsautos ließen deshalb ihr Dach an der
Spawn-Position stehen und fuhren ohne weiter.

Derselbe Fehler steckte an **vier** Stellen, nicht an einer:

| Datei | Was stehenblieb |
|---|---|
| `TrafficService` (Autos) | das Dach |
| `TrafficService` (Fußgänger) | Kopf und Rumpf einzeln gesetzt |
| `GuardService` (Bankwachen) | der Kopf, während der Rumpf patrouilliert |
| `PursuitService` (Streifen) | beide Blaulichter |

Alle vier bewegen jetzt das **Modell** über `Model:PivotTo`; die
`WeldConstraint`s zwischen Anchored-Teilen sind ersatzlos raus. Der Testlauf
lehnt beide Fehler ab, in allen vier Dateien — das kann nicht zurückkommen.

Aus derselben Ecke mit behoben:
- **Bodenhöhe wird gerechnet, nicht geraten.** Vorher stand da `2.4`. Richtig
  ist Fahrbahnoberkante + halbe Modellhöhe (`Model:GetExtentsSize`) + Spalt —
  das war um einen halben Stud daneben und wäre beim nächsten Modell ganz
  falsch gewesen.
- **Gehweghöhe** kommt jetzt aus `Config.City` und wird von `City` *und* den
  Fußgängern gelesen. Vorher: feste `0.3` in City, feste `3` im Verkehr, zu
  nichts passend.
- **Client-Interpolation** (`Client/World/TrafficSmoother.client.luau`, neu):
  der Server bleibt bei 10 Schritten/s, der Client zieht dazwischen weich
  nach. Reine Optik — Diebstahl-Reichweite und Wachsicht prüft weiter der
  Server gegen die echte Position.

#### Die Architekturänderung: Code platziert Geometrie, Code baut keine
Ein Quader mit Betonmaterial sieht aus wie ein Quader mit Betonmaterial. Kein
Material, kein Licht und keine Farbe heben diese Decke an.

- **`Shared/AssetLibrary.luau`** (neu) — schlägt Vorlagen unter
  `ReplicatedStorage/Assets` nach, klont sie, prüft den Modellvertrag und
  sammelt, was fehlt. Beim Serverstart kommt eine Liste.
- **`VehicleChassis`** baut keine Karosserie mehr, es **verdrahtet**:
  Federung, Antrieb, Lenkung, Sitz, Netzwerkbesitz. Fehlt ein Pflichtteil,
  nennt die Meldung Modell **und** Teil statt still halb zu funktionieren.
- **Kollision sauber getrennt:** nur `Chassis` kollidiert mit der Welt, alles
  Sichtbare ist `CanCollide = false`. Räder haben eine eigene
  `CollisionGroup` — sonst verhaken sich zwei Autos beim Berühren.
- **Verkehr klont dieselben Vorlagen** wie Spielerfahrzeuge. Beim
  Kurzschließen werden Pivot und Lackierung übernommen, der Übergang springt
  nicht mehr. Ein Verkehrsauto ist jetzt eine echte, kaufbare Klasse.
- **`World/City`** stapelt Module (Sockel → n × Etage → Dach). Dachkante
  steht über, Sockel dunkler, Häuser versetzt und leicht gedreht — kein
  Raster. Dazu Feuerleitern und Straßenmöblierung im ausgebauten Bezirk.
- **`World/Cityscape` gelöscht.** Die alte Kulissen-Straßenzeile lag im selben
  Koordinatenbereich wie die echte Stadt und hat sie durchschnitten.

#### ⚠️ Bis Noah Modelle einträgt, ist die Stadt magenta
Es gibt **keine einzige Vorlage** — `ReplicatedStorage/Assets` ist leer (die
Ordnerstruktur liegt aber schon in der Place-Datei). Jedes fehlende Modell
wird zu einem `MISSING_ASSET_<Kategorie>_<Name>` in Knallmagenta.

Das ist die Regel aus dem Auftrag, kein Versehen: ein Platzhalter, den man
übersehen kann, ist kein Platzhalter, und aus Parts nachgebaute Ersatzautos
sind genau das Problem, das dieses Rework beseitigt. Das Spiel bleibt dabei
vollständig **fahrbar und testbar** — die Klötze haben die richtigen Maße,
Kollisionen und Attribute. Die Liste steht unter „Manuelle Schritte".

### v2.1.0 — Vantorra bei Tag
Entscheidung von Noah: die Stadt soll hell sein, dauerhaft Tag. Die
**Benutzeroberfläche bleibt bewusst das dunkle Fake-OS** — heller Tag draußen,
schwarzes Terminal im Fenster. Der Kontrast ist gewollt und wird vom Testlauf
festgehalten.

- **`Config.Palette`** (neu) — sämtliche Weltfarben an einer Stelle: Asphalt,
  Gehweg, Beton, Putz, Ziegel, Glas, Metall, Dach, Innenräume.
  **Kein Skript unter `src/server/World/` enthält noch einen eigenen Farbwert**
  — der Testlauf lehnt dort jedes `Color3.fromRGB` ab. Die Stadt umzufärben ist
  damit eine Änderung an einer Tabelle statt an sieben Dateien.
- **Bezirks-Grundtöne** sind echte Baumaterialien geworden (Altbau-Putz,
  Stahlgrau, Glasfassade, Sandstein, Betonplatten) statt fünf Grautönen knapp
  über Schwarz.
- **Fenster** sind spiegelndes Glas statt leuchtender Neonflächen — erleuchtete
  Fenster mittags sehen falsch aus. Fahrbahn matt statt nass. Untergrund in der
  Place-Datei hell statt fast schwarz.
- **`Config.World.PermanentDay`** — ein Schalter. `true` (Standard): Sonne steht
  fest, kein Zyklus, **kein Heartbeat**, Licht wird genau einmal gesetzt.
  `false`: der komplette alte Tag-/Nachtzyklus läuft wieder, ohne dass irgendwo
  Code angefasst werden muss. Der Zyklus-Code steht deshalb noch vollständig da.

#### ⚠️ Der Nachtbonus ist umgezogen, nicht gestrichen
Das ist der eigentliche Eingriff, und er ist nicht optisch. Die Nacht **war**
eine Mechanik (+35 % Ertrag, NPCs sehen kürzer). Hätte man nur das Licht
angeschaltet, wäre die zentrale Risiko-Entscheidung des Spiels ersatzlos
verschwunden. Sie hängt jetzt am **Ort** statt an der **Uhrzeit** —
`Config.Cover`:

| | Ertrag | Trace | Beispiele |
|---|---|---|---|
| Attribut `Exposed = true` | +35 % | ×1,3 | Geldautomat am Gehweg, Fassadenkamera, Ladenfront, Bankeingang |
| gedeckt (Standard) | normal | normal | Tresor im Laden, Bankinnenraum, Lüftung, Rückseite der Lagerhalle |

Bei Tageslicht ist das sogar der ehrlichere Ort dafür: es gibt keine Dunkelheit
mehr, in der man verschwinden könnte. Und ein *Wann* kann man aussitzen, ein
*Wohin* nicht. Die zweite Hälfte des alten Nachtbonus — kürzere NPC-Sicht —
ist genauso umgezogen: Wachen tragen ein Attribut `SightFactor`
(Bankinnenraum 0,7). Ort statt Uhrzeit, Attribut statt Code.

Der Testlauf hält beide Hälften des Tauschs fest: `ExposedRewardBonus > 0`
**und** `ExposedTraceFactor > 1`. Ohne den Aufpreis wäre „offen" gratis Geld
und jedes gedeckte Ziel tot.

#### Folgeänderungen
- **Händler:** ohne Abend keine Sperrstunde — bei `PermanentDay` immer offen.
  Das Schild am Autohaus sagt das jetzt auch, statt eine Uhrzeit zu nennen,
  die nie eintritt.
- **Darknet:** `MarketVolatilityFactor` gibt bei dauerhaftem Tag 1 zurück, nicht
  `DayMarketCalm` (0,6). Der ruhige Tag war die Gegenseite einer bewegten Nacht
  — ohne Nacht wäre daraus eine dauerhafte Drosselung des Darknets geworden.
- **PointLights** an Neonschildern entfallen bei Tag: praktisch unsichtbar und
  trotzdem teuer.

#### Nebenbei gefunden
`HackService.AddRewardModifier` war angemeldet, wurde aber **nie eingerechnet**.
Die Endgame-Entscheidung aus Mission 10 hatte damit gar keine Wirkung auf den
Ertrag — nur auf den Trace. Behoben; zwei neue Testlauf-Einträge prüfen jetzt,
dass angemeldete Ertrags- *und* Trace-Faktoren auch wirklich angewendet werden.

### Open-World Phase 2 — Die Stadt
- **`Shared/Districts.luau`** (neu) — fünf Bezirke als Daten: Altstadt, Hafen,
  Finanzviertel, Höhenzug, Industriegebiet, jeder mit Schwierigkeitsspanne
  und Gitterplatz. **Nur die Altstadt hat `Dense = true`.** Der Testlauf prüft
  das ausdrücklich: eine große leere Stadt ist schlimmer als ein voller Block,
  also darf nicht versehentlich ein zweiter Bezirk ausgebaut werden.
- **`Systems/RoadNetwork.luau`** (neu) — das Straßenraster wird aus
  `Config.City` *gerechnet*, nicht von Hand gesetzt. Kreuzungen, Kanten,
  Nachbarn und `LanePosition(fromId, toId, alpha)` (gibt Position **und**
  Fahrtrichtung zurück). Damit ist dieselbe Datenstruktur die Straße für den
  Spieler, die Spur für den Verkehr und die Route für die Polizei — es gibt
  keine zweite Version, die auseinanderlaufen könnte.
- **`World/City.server.luau`** (neu) — baut Fahrbahnen, Gehwege, Häuser,
  Leuchtreklamen und Feuerleitern aus diesem Graphen. `RoofAccessChance` der
  Häuser bekommt eine Leiter aufs Dach, damit „von oben" ein echter Weg ist.
- `StreamingEnabled` ist an; die Radien sind plausibel gesetzt, aber
  **ungemessen**.

### Open-World Phase 3 — Verkehr und Fußgänger
- **`Systems/TrafficService.luau`** (neu). Die drei harten Regeln aus dem
  Auftrag sind im Testlauf verdrahtet, nicht nur im Kommentar:
  **kein `PathfindingService`**, **kein `Humanoid`** für Hintergrund-NPCs,
  **kein `Heartbeat`** über die ganze Stadt.
- Autos und Fußgänger sind `Anchored` und werden alle `Config.Traffic.Tick`
  Sekunden per `CFrame` zwischen zwei Graph-Knoten interpoliert. Wer aus dem
  `ActiveRadius` fällt, wird angehalten und in den Pool zurückgelegt —
  `Instance.new` läuft nur beim Auffüllen des Pools, nie im Sekundentakt.
- Hinter einem langsameren Auto wird ab `StopDistance` gebremst, sonst fahren
  sie ineinander und es sieht kaputt aus.
- **Autodiebstahl:** [E] halten für `StealHoldSeconds`. Kostet `StealTrace`
  und gibt sofort eine Fahndungsstufe — der Diebstahl hängt damit an der
  zentralen Risiko-Mechanik statt daneben zu stehen.

### Open-World Phase 4 — Händler, Besitz, Garage
- **`Systems/VehicleService.luau`** (neu) — Besitz steht im Profil
  (`Profile.Garage`), Kauf und Preis ausschließlich serverseitig,
  `Config.Vehicle.MaxSpawned` erlaubt genau ein ausgeparktes Fahrzeug,
  Ausparken nur auf einem Part mit Tag `GhostNetVehicleSpawn`.
- **`World/Dealership.server.luau`** (neu) — Showroom mit **physisch
  ausgestellten**, fahrbaren Fahrzeugen statt eines Menüs mit Bildern, plus
  Garage mit Ausparkplatz. Öffnungszeiten
  (`Config.Dealer.OpenHour`/`CloseHour`) hängen am Tag-/Nachtzyklus — damit
  bekommt der Tag zum ersten Mal einen eigenen Zweck.
- Anpassung ist **nur Lackierung**. Keine Leistungsteile, sonst wäre die
  Klassenwahl aus Phase 1 sofort entwertet.
- Einziger Punkt, an dem ein Auto Werte anfasst: ein eigener Transporter gibt
  über `VehicleService.StashBonus` zusätzliche Darknet-Lagerplätze.

### Open-World Phase 5 — Die Bank
- **`World/BankInterior.server.luau`** (neu) — drei Ebenen (Schalterhalle,
  Sicherheitsbereich, Tresorraum) und **drei Wege hinein**:
  *leise* (Kameras vorher aus, wenig Trace, volle Beute),
  *schnell* (direkt an die Schleuse, `AlarmStarts = true`, die Uhr entscheidet,
  wie viele der `Config.Bank.VaultBoxes` Fächer man noch schafft),
  *von oben* (Lüftung, ohne Alarm — kostet dafür
  `Config.Bank.VentRequiredTier`, sonst wäre er immer die beste Wahl und die
  anderen zwei Wege tot).
- **`Systems/GuardService.luau`** (neu) — Wachen patrouillieren zwischen zwei
  Attribut-Punkten und prüfen Sicht per `workspace:Raycast` innerhalb
  `GuardSightAngle`. Sie **melden über `RaidService.RaiseAlarm` und greifen
  nie an**; nachts sehen sie über `TimeService.SightFactor` kürzer.
- Die Beute ist normales Unsold. Der Raub braucht kein eigenes Regelwerk —
  Trace und Hehler tragen ihn komplett.

### Open-World Phase 6 — Polizei statt Kampf
- **`Systems/PursuitService.luau`** (neu). Stufe = `floor(Trace /
  TracePerLevel)` plus Aufschlag für frische Taten, gedeckelt auf 5.
  `TracePerLevel = 20`, weil `20 × 5 = 100 = Config.Trace.Max` — mit 22 wäre
  Stufe 5 aus dem Trace allein nie erreichbar gewesen (hat der Testlauf
  gefunden).
- Streifenwagen fahren auf dem `RoadNetwork`-Graphen, ab `RoadblockLevel` (4)
  kommen Straßensperren, ab `HelicopterLevel` (5) ein Hubschrauber.
  Entkommen: `EscapeSeconds` außer Sicht. Abbau: `Decay` pro Sekunde.
- Gefasst zu werden ruft `TraceService.Add(player, Config.Trace.Max)` auf —
  also **exakt die bestehende Bust-Kette**. Kein zweites Strafsystem daneben,
  keine doppelte Buchführung.
- **Keine Waffe, kein Schaden, kein Kampf.** Der Testlauf lehnt jedes
  `Tool`/`Damage`/`Fire(` in dieser Datei ab.

### Open-World Phase 7 — Die Story
- Zehn Missionen (`M01_FIRSTHACK` … `M10_WREN`) als **Kette ohne
  Verzweigung**, jede mit dauerhaftem Unlock — der Testlauf prüft beides.
  Briefings höchstens drei Sätze; M01, M09 und M10 mussten dafür gekürzt
  werden.
- Die Wendung steht in M09: In den Protokollen steht dein eigener Name.
  Wren hat nie für dich gearbeitet — du hast für sie gearbeitet.
- **M10 ist eine Entscheidung, keine Mission:** *Kassieren* (halber Trace,
  25 % weniger Ertrag) oder *Verbrennen* (30 % mehr Ertrag, 40 % härtere
  Fahndung, bessere Kurse). Als `Profile.Story.Allegiance` gespeichert und
  nach `Config.Endgame.SwitchCooldown` (eine Woche) umstellbar — ohne das
  fühlen sich Spieler eingesperrt.
- Technisch hängt die Entscheidung über
  `HackService.AddTraceModifier` / `AddRewardModifier` am Hack. Andersherum
  gebaut, weil `HackService` sonst `MissionService` aufrufen müsste und
  dadurch ein Require-Kreis entstünde — den hat der Testlauf gefunden, bevor
  Studio ihn hätte finden können.

### Open-World Abschnitt 2 — Tag und Nacht
- **`TimeService`** (neu) — voller Zyklus in 24 Minuten, Server ist die Uhr.
  `Lighting.ClockTime`, Nebel, Ambient, Atmosphere und Bloom werden über eine
  weiche Rampe um Sonnenauf- und -untergang interpoliert, nichts springt.
- **Der Zyklus ist Mechanik, keine Kulisse:** nachts +35 % auf jeden
  Hack-Ertrag (`TimeService.RewardMultiplier`) und kürzere NPC-Sichtweite
  (`SightFactor`, ab OW-Phase 5 genutzt); tagsüber schwanken die Darknet-Kurse
  nur zu 60 %. Der Testlauf prüft, dass diese drei Unterschiede existieren.
- `Lighting.Technology` steht in `Config.World` und ist auf `ShadowMap`
  umstellbar, falls `Future` auf dem Handy einbricht.
- Tagsüber kühles Blaugrau statt sattem Blau — die Stadt soll auch bei Tag
  nicht freundlich wirken.

### Open-World Phase 1 — Fahrzeuge
- **`Shared/Vehicles.luau`** (neu) — fünf Klassen als Daten. Jede hat einen
  mechanischen Grund: Kompakt am unauffälligsten, Limousine beste Straßenlage,
  Sportwagen am schnellsten (und mit 1,6× Fahndungszuschlag), Transporter das
  größte Lager, Motorrad der größte Lenkeinschlag.
  Der Testlauf prüft, dass **jede Klasse in mindestens einem Wert die beste
  ist** — genau daran ist die Limousine beim ersten Durchlauf gescheitert, sie
  war „ausgewogen" und damit in nichts die beste Wahl. Jetzt hat sie den besten
  Grip, und der Sportwagen ist dafür zickiger geworden.
- **`VehicleChassis`** (neu) — ein Chassis, viele Karosserien, gebaut aus dem
  Datensatz. Pro Rad: `SpringConstraint` für die Federung,
  `CylindricalConstraint` senkrecht für Federweg und Lenkung (Servo),
  `CylindricalConstraint` seitlich für den Antrieb (Motor). Der Radträger
  dazwischen ist nötig, weil eine Achse nicht gleichzeitig Federweg und
  Raddrehung sein kann.
- **Netzwerkbesitz** geht beim Einsteigen an den Fahrer und beim Aussteigen,
  Tod oder Rausfliegen zurück an den Server. Ohne das fährt sich das Auto wie
  durch Sirup.
- **`VehicleController`** (neu, Client) — die Steuerung läuft beim Fahrer,
  weil ihm die Physik gehört. Kamera weicht mit Tempo zurück (FOV 70 → 85),
  Motor-Tonhöhe steigt, Reifen quietschen beim Seitwärtsdrift, Bremsspuren,
  Rückleuchten, Tacho. Lenkeinschlag sinkt mit dem Tempo, sonst überschlägt
  sich jedes Auto auf der Geraden.
- **`World/TestVehicles`** (neu) — ein Fahrzeug jeder Klasse am Spawn.
- `StreamingEnabled` ist in der Place-Datei und in `Config.World` gesetzt,
  Radien 128/512 — **noch ungetestet**, siehe oben.


### Phase E — Admin-Panel (F2)
- `AdminList.luau` liegt in **ServerScriptService**, nie in ReplicatedStorage —
  eine Admin-Liste dort könnte jeder Client lesen. Noah trägt seine UserId dort
  ein; im Studio ist der Testspieler automatisch Admin.
- **Jeder** Handler prüft die UserId in der ersten Zeile, vor Rate-Limit und
  Typcheck. Dass der Knopf nur Admins gezeigt wird, ist irrelevant.
- Geld, Rig, Trace, Bust, Story und Markt-Eingriffe sind zusätzlich auf
  `RunService:IsStudio()` beschränkt — im Live-Spiel existieren sie selbst für
  echte Admins nicht.
- Jede Aktion wird mit `warn()` protokolliert: wer, was, an wem.
- Umfang: Wirtschaft, Missionen, Welt (Ziele auflisten, Cooldowns löschen,
  Teleport), Markt, Debug. Wichtigster Punkt: **Profil als JSON ausgeben** —
  ohne das debuggt man Speicherfehler blind.

### Phase F — Robux-Store (P)
- `MonetizationService` mit **allen IDs auf 0**. Der Store zeigt einen noch
  nicht eingetragenen Eintrag als „NOCH NICHT DA" an, statt still nichts zu tun.
- `ProcessReceipt`: verarbeitete `PurchaseId` im Profil, erst gutschreiben,
  **dann speichern**, dann `PurchaseGranted`. Schlägt das Speichern fehl, wird
  nicht bestätigt — sonst wäre die Ware vergeben, aber nicht gespeichert.
- `UserOwnsGamePassAsync` mit Retry; bei endgültigem Fehler wird **nicht**
  angenommen, der Spieler besitze nichts, sondern später erneut geprüft.
- `PromptGamePassPurchaseFinished` aktiviert Pässe ohne Rejoin.
- Verkauft werden nur Zeit, Kapazität und Kosmetik. Nichts löst ein Rätsel.

### Phase G — Optik und Sound
- `Cityscape.server.luau`: nächtliche Straßenzeile statt Baseplate — nasse
  Fahrbahn über `Reflectance`, Neonschilder mit echtem Licht, erleuchtete
  Fensterbänder nur als Farbe (hunderte PointLights wären auf dem Handy nicht
  bezahlbar). Fester Seed, also auf jedem Server dieselbe Stadt.
- `TargetBeacons.client.luau`: Hack-Ziele und Hehler pulsieren dezent und gehen
  aus, wenn sie offline sind — sonst läuft man an ihnen vorbei.
- `SoundCatalog.luau` + `SoundController.client.luau`: **alle IDs leer.** Die
  Tonhöhe der Knoten-Klicks steigt mit der Pfadlänge (aus Klicks wird eine
  aufsteigende Melodie), der Countdown tickt unter 10 s immer schneller, die
  Ambience wird während eines Hacks leiser und kommt beim Alarm laut zurück.

### Phase C — Darknet
- `Goods.luau`: fünf Waren mit Basispreis, Volatilität und Fälschungsrisiko.
- `MarketService`: Kurse bewegen sich **serverweit** alle 12 s, mit Mean
  Reversion gegen Drift. Mini-Chart, Trend, gelegentliche Gruppen-Events.
- `InventoryService`: Preise kommen **ausschließlich** vom Server. Menge,
  Lagerplatz und Guthaben werden vor jeder Buchung geprüft. Das Darknet ist
  serverseitig hinter dem `DARKNET`-Unlock, nicht nur in der UI ausgeblendet.
- Risiko: begrenztes Lager, Ware ist heiß (Bust kostet die Hälfte davon),
  Fälschungsquote sinkt mit dem Rig-Tier.
- Klartext-Fehlermeldungen mit Zahl — überall.

### Phase B/D — die fünf Missionen
Jede ist Tutorial für ein System **und** schaltet es dauerhaft frei:
M01 → `FREE_HACKING`, M02 → `STORE_RAIDS`, M03 → `DARKNET`, M04 → `TRADING`,
M05 → `BANK_RAIDS`. Nichts davon verschwindet nach der Mission.
- `RaidService`: Alarm-Uhr rein über Attribute (`AlarmGroup`, `AlarmStarts`,
  `AlarmEnds`, `FailBusts`, `RequiresTwo`). Läuft **pro Spieler**, sonst würde
  ein zweiter Spieler den Alarm des ersten erben und Co-Op wäre eine Strafe.
- `TutorialUI`: genau ein Hinweisfeld, jeder Schritt durch eine Handlung
  ausgelöst, Skip-Button vergibt den Unlock ohne Crypto.

### Phase A — Missions-Rückgrat
- **`Shared/Missions.luau`** (neu) — eine Mission ist ein Tabelleneintrag, kein
  Skript. Enthält die Registry (aktuell leer), das dokumentierte Schema
  `Missions.Example` und die **puren** Regeln: `Validate`, `IsAvailable`,
  `FirstAvailable`, `Progress`, `Required`, `HasUnlock`. Kennt weder Spieler
  noch Remotes noch die Welt — deshalb komplett im Testlauf prüfbar.
- **`MissionService`** (neu) — aktive Mission und Schritt-Index liegen **im
  Profil**. Der Server leitet den Fortschritt aus dem ab, was ohnehin passiert:
  gelöste Hacks, Verkäufe, Distanz zu Wegpunkten, abgelaufene Wartezeiten.
  Der Client meldet **nie** „Schritt fertig".
- **Schritt-Typen:** `GOTO` (Part mit Tag `GhostNetWaypoint` + Attribut
  `WaypointId`), `HACK` (`TargetId`), `SELL` (Anzahl Verkäufe), `BUY`
  (Ware + Stückzahl, Haken für Phase C), `WAIT` (Sekunden über `os.time()`),
  `TALK` (Part mit Tag `GhostNetContact` + Attribut `ContactId`).
- **Kein Require-Kreis:** `HackService.OnHackResolved` und `SellService.OnSell`
  sind Callback-Register nach dem Vorbild von `TraceService.OnBust`. Der
  MissionService hängt sich dort an; keiner der beiden kennt ihn.
  Der Testlauf prüft das Abhängigkeitsdiagramm auf Kreise.
- **Neue Remotes:** `MissionSync`, `MissionAccept`, `MissionAbandon`,
  `MissionInteract` (TALK), `WaypointSync` — alle mit Rate-Limit.
- **`MissionUI`** (neu) — Auftragsanzeige oben links, Wegpunkt-Marker mit
  Entfernung, Countdown bei `WAIT`, `[E]`-Prompt bei `TALK`. Reine Anzeige.
- **`EconomyService.AwardBanked`** (neu) — für Missionsbelohnungen, die
  bewusst sicher sein sollen. Standard ist `Config.Mission.RewardToBank = false`:
  Story-Geld ist heiß und muss erst zum Hehler, damit der Verkaufs-Loop
  relevant bleibt.

### ⚠️ Schema-Migrationen 1 → 5
`Config.Save.SchemaVersion = 5`. `SaveService.MIGRATIONS` zieht Altprofile beim
Laden nach, **bevor** geschrieben wird — ein Altprofil wird nie verworfen.
| Version | Neu | Für Altprofile |
|---|---|---|
| 2 | `Story` (Missionsfortschritt) | Story startet bei null |
| 3 | `Stash` (Darknet-Lager) | Lager startet leer |
| 4 | `PurchaseLog` (gegen Doppelvergabe) | Log startet leer |
| 5 | `Garage` (Fahrzeugbesitz) + `Story.Allegiance` | Garage leer, Allegiance `""` |
**v2.1.0 ändert das Profil nicht** — helle Stadt und Deckungs-Bonus brauchen
kein neues Feld, `SchemaVersion` bleibt auf 5 und es gibt nichts zu migrieren.

**Migration 4 → 5** gehört zu Open-World-Phase 4.
Ein Profil aus Version 1.1.0 lädt weiter, bekommt eine leere Garage und keine
Entscheidung — es verliert nichts.
Bank, Rig, Trace, Cooldowns und Statistik bleiben in allen Fällen erhalten.
Jede weitere Version braucht einen eigenen Eintrag in `MIGRATIONS` — der
Testlauf prüft das.

### Phase 1 — Loop geschlossen

#### Bugfixes aus dem Prototyp
- **Ziel-Id-Kollision** — `HackTargets.nextFreeId()` zählt jetzt hoch, bis die Id
  wirklich frei ist. Vorher konnte ein Part ohne `TargetId`-Attribut die Id eines
  Parts mit gespeichertem Attribut überschreiben; das erste Ziel war dann tot.
- **Cooldown-Exploit durch Rejoin** — Cooldowns liegen im Profil
  (`profile.Cooldowns[targetId]`), nicht mehr in einer Tabelle im Serverspeicher.
  Server verlassen und neu beitreten setzt sie nicht zurück.
- **`os.clock()` vs. `os.time()`** — alles Persistierte (Cooldowns, `LastSeen`,
  Trace-Abkühlung über die Offline-Zeit) benutzt Unix-Zeit. `os.clock()` bleibt
  nur bei serverinternen Kurzzeit-Timern: `DownUntil`, Rate-Limits, Bust-Sperre,
  Sync-Drosselung.

#### Systeme
- **`SaveService`** — ein DataStore, Key `ghostnet_player_%d`, Profil-Schema mit
  `SchemaVersion`. Session-Lock über eine `SessionId` im Profil: die jüngere
  Sitzung übernimmt, die ältere merkt es beim nächsten Schreiben, schreibt nicht
  mehr und wird beendet. Autosave alle 60 s, gedrosselte Zwischenspeicherung nach
  Verkauf/Kauf/Bust, Speichern bei `PlayerRemoving` und `BindToClose`. Alle
  Zugriffe in `pcall` mit Backoff; scheitert das Laden endgültig, wird gekickt
  statt mit leerem Profil weitergespielt.
  Kein anderes Modul fasst einen DataStore an (wird im Testlauf geprüft).
- **`TraceService`** — Trace 0–100 im Profil. `Add` wird vom `HackService` mit dem
  dort schon berechneten `traceDelta` aufgerufen. Passiver Abbau nach 3 s Ruhe,
  beschleunigt durch Kühlung; läuft auch über die Offline-Zeit. Bust bei 100:
  Unverkauftes weg, Trace auf 25, 15 s Hack-Sperre, Bildschirm-Blitz beim Client.
  Neue Remote `TraceSync`.
- **`SellService`** — Hehler ist ein BasePart mit Tag `GhostNetFence`.
  Unsold → Banked abzüglich 12 % Gebühr, dazu Trace −18. Distanz wird
  serverseitig geprüft, genau wie beim Hacken. Rate-Limit `SellRequest`.
- **`ShopService`** — RemoteFunction `ShopPurchase`, vier Rig-Bauteile bis
  Stufe 5. Preis kommt aus `Config.GetUpgradeCost` und wird ausschließlich vom
  Server berechnet; der Client schickt nur, welches Bauteil er meint.
- **`EconomyService`** liest jetzt aus dem Profil statt aus einem eigenen Wallet.
  Öffentliche Schnittstelle unverändert, dazu `SellUnsold`, `SpendBanked`,
  `RefundBanked`, `SetRigLevel`, Statistik-Zähler.
- **`Shared/Geometry.luau`** (neu) — die Abstandsrechnung lag dreimal im Projekt
  (HackTargets, HUD, neu auch SellService). Jetzt einmal, damit HUD-Anzeige und
  Server-Entscheidung nie auseinanderlaufen.
- **HUD** — Trace-Balken dauerhaft sichtbar, pulst ab 70 %, rot ab 90 %.
  Ein Prompt für beides: was näher ist, Hehler oder Hack-Ziel, gewinnt die
  `[E]`-Taste. Cooldowns kommen als Restsekunden vom Server, damit die Anzeige
  nach einem Rejoin stimmt.
- **`ShopUI`** (neu) — Terminal-Fenster, Knopf unten links oder `[B]`.
  Zeigt je Bauteil Stufe, Preis und was die Stufe konkret bringt.
- **Testwelt** — zusätzlich zu Kamera/Tür/Automat steht jetzt ein Hehler am
  Spawn, rund 46 Studs von den Zielen entfernt. Der Rückweg kostet Zeit,
  während der Trace weiterläuft — sonst wäre Verkaufen keine Entscheidung.

### Balancing (alles in `Config.luau`)
- Erstes Upgrade: 198–253 CRY, also 2–3 erfolgreiche Kamera-Hacks. Der Testlauf
  prüft diese Vorgabe für jedes Bauteil.
- Trace: Kamera (D2) = 8 pro Hack, Abkühlung 0,25/s. Ein Bust braucht rund
  12 Kamera-Hacks ohne Verkauf. Ein Verkauf (−18) schafft mehr Luft, als ein
  Hack kostet — auch das wird geprüft.

## Tests
`cd ghostnet/tests && npm install && node testlauf.mjs` → **725/725 grün**.
Drei Stufen:
1. **Syntax** — `luau-compile` über jede `.luau`-Datei.
2. **Struktur** — `--!strict` überall, keine veralteten APIs, jede Remote
   angemeldet, jedes Rate-Limit konfiguriert, nur SaveService am DataStore,
   Cooldowns auf `os.time()`, **kein Require-Kreis zwischen den Services**,
   zu jeder Schema-Version eine Migration.
   Dazu die Sicherheitsregeln, die man mechanisch prüfen kann: Admin-Liste
   nicht in Shared/Client, UserId-Prüfung vor allem anderen, gefährliche
   Befehle StudioOnly, kein Preis aus dem Client-Paket, alle Gamepass- und
   Produkt-IDs auf 0, alle Sound-IDs leer, nirgends eine erfundene Asset-Id,
   `ProcessReceipt` speichert vor dem Bestätigen.
   Neu für die offene Welt: kein `PathfindingService` und kein `Humanoid` im
   Verkehr, kein `Heartbeat` in Verkehr/Polizei/Wachen, Objekt-Pool und
   Aktivradius vorhanden, keine Waffen in `PursuitService`, Wachen ohne
   `TakeDamage`, Netzwerkbesitz geht beim Aussteigen zurück, das Chassis
   bewegt kein Geld. Diese Prüfungen sehen nur echten Code — Kommentare
   werden vorher entfernt, sonst fällt ein Test über seinen eigenen
   Kopfkommentar („benutzt KEIN PathfindingService").
3. **Logik** — echte Module in der Luau-VM: Config-Formeln, Balancing-Vorgaben,
   das komplette Missions-Regelwerk (Validierung inkl. Kreiserkennung,
   Verfügbarkeit, jeder Schritt-Typ, eine ganze Mission durchgespielt), der
   Markt (Kauf immer über Verkauf, Mean Reversion holt einen entgleisten Kurs
   zurück, Lager wächst und Risiko sinkt mit dem Rig) und das Node-Breach-
   Minispiel (lösbar auf jeder Schwierigkeit, Lösung leckt nie).
   Für die offene Welt zusätzlich: Bezirksdaten überlappen nicht und nur einer
   ist dicht, die Verkehrsgrenzen sind konservativ, jede Fahndungsstufe ist
   erreichbar und man kann entkommen, jede Fahrzeugklasse ist in genau einem
   Wert die beste, die Missionskette ist geschlossen und jedes Briefing hat
   höchstens drei Sätze, und die Endgame-Entscheidung ist in beide Richtungen
   ein echter Tausch statt einer offensichtlich richtigen Wahl.

Drei dieser Prüfungen sind beim ersten Durchlauf durchgefallen und haben je
einen echten Fehler gefunden: eine unerreichbare Fahndungsstufe
(`TracePerLevel` 22 statt 20), zu lange Briefings (M01/M09/M10) und einen
Require-Kreis `HackService → MissionService → HackService`. Alle drei sind
behoben — an der *Ursache*, nicht am Test.

## Build
`node ghostnet/tools/build-rbxlx.mjs` → `ghostnet/GhostNet.rbxlx`,
direkt in Studio öffenbar. Alternativ Rojo mit `ghostnet/default.project.json`.

## Offen / bewusst nicht gebaut ➡️
Der Bauplan aus dem Prompt ist abgearbeitet. Was fehlt, fehlt mit Absicht:
- **Alle IDs sind Platzhalter** (Sounds `""`, Gamepässe und Produkte `0`,
  Admin-Liste leer). Erfundene IDs schlagen stumm fehl — deshalb keine.
  Das Spiel läuft ohne sie, es ist nur stumm und der Store leer.
- **Vier von fünf Bezirken sind absichtlich dünn.** Nur die Altstadt ist
  ausgebaut. Das ist keine unfertige Arbeit, sondern die Regel „erst einen
  fertig, dann den nächsten" — und der Testlauf hält sie fest.
- **Zwei weitere Minispiele**, **prozeduraler Weltgenerator**, **Tagesziele**
  und **Ranglisten** — Details am Ende von `PHASEN.md`.
- **Kein echter Spielertest.** Alles ist im Code umgesetzt und durch 725
  automatische Prüfungen abgesichert, aber noch nicht von einem Menschen in
  Studio durchgespielt.

## Bekannte Einschränkungen ⚠️
- **Studio-Notbetrieb:** Ist „Studio Access to API Services" aus, kann kein
  DataStore erreicht werden. Dann läuft das Spiel mit einem Profil im
  Arbeitsspeicher weiter (laute Warnung in der Ausgabe) und **speichert nichts**.
  Der Pfad ist doppelt abgesichert (`Config.Save.StudioMemoryFallback` UND
  `RunService:IsStudio()`) und live nie erreichbar. Zum Testen der Persistenz
  muss der API-Zugriff an sein.
- Session-Lock nach dem Prinzip „die jüngere Sitzung gewinnt": wechselt jemand
  sehr schnell den Server, können bis zu 60 Sekunden (ein Autosave-Takt) fehlen.
- **Bildrate, Fahrgefühl und Physikstabilität sind ungemessen.** Siehe oben.
  Die Startwerte in `Config.Traffic`, `Config.City` und `Config.Vehicle` sind
  geschätzt und bewusst niedrig — nicht gemessen.
- **Die Stadt wird beim Serverstart gebaut**, nicht in der Place-Datei
  gespeichert. Vorteil: eine Änderung an `Config.City` ändert sofort die ganze
  Stadt. Nachteil: der Startvorgang dauert etwas länger, und man kann die
  Häuser in Studio nicht von Hand verschieben. Soll die Stadt später von Hand
  gebaut werden, ersetzt man `City.server.luau` durch echte Parts — Tags und
  Attribute bleiben identisch, der Rest des Codes merkt nichts davon.

## Manuelle Schritte außerhalb des Codes (Noah) 🔑

### 0. Die Modelle — das ist gerade der wichtigste Punkt
Alles hier gehört nach `ReplicatedStorage/Assets/<Ordner>/<Name>` (die Ordner
liegen schon in der Place-Datei). Zwei Wege, beide erlaubt, gerne gemischt:
**A** selbst in Blender bauen → als `.obj`/`.fbx` exportieren → in Studio über
den Asset Manager (3D-Import) hochladen. **B** fertige Modelle aus dem Creator
Store — dann vorher jedes Modell prüfen: enthaltene Skripte löschen,
Teilezahl ansehen, `Anchored` setzen. Nie ein Modell mit Skript ungeprüft
einbauen. Das Dreiecks-Limit pro MeshPart steht in der offiziellen
Roblox-Dokumentation — nachschlagen, nicht raten.

| Ordner | Name | Wofür |
|---|---|---|
| `Vehicles` | `Compact` | Kompakt |
| `Vehicles` | `Sedan` | Limousine |
| `Vehicles` | `Sports` | Sportwagen |
| `Vehicles` | `Van` | Transporter |
| `Vehicles` | `Bike` | Motorrad |
| `Vehicles` | `Police` | Streifenwagen |
| `Buildings` | `Base_Shop`, `Base_Entry`, `Base_Garage` | Erdgeschosse |
| `Buildings` | `Floor_A`, `Floor_B`, `Floor_C` | Standardetagen |
| `Buildings` | `Roof_Flat`, `Roof_Tech` | Dachabschlüsse |
| `Props` | `Laterne`, `Ampel`, `Muelltonne`, `Poller`, `Verteiler`, `Schild` | Straßenmöblierung |
| `Props` | `Feuerleiter` | eine Sprosse, wird gestapelt |
| `Characters` | `Pedestrian` | Fußgänger — **ohne Humanoid** |
| `Characters` | `Guard` | Wache |

**Fahrzeugmodelle müssen diese Teile enthalten**, sonst verweigert
`VehicleChassis` die Arbeit und sagt dir genau, welches fehlt:

```
Sedan (Model)
├── Chassis        Part, unsichtbar, PrimaryPart — die Kollisionsbox
├── Body           MeshPart, die sichtbare Karosserie
├── Glass          MeshPart, Fenster                    (optional)
├── Wheels/  FL, FR, RL, RR   (Motorrad: F, R)
├── Lights/  HeadL, HeadR, TailL, TailR                 (optional)
└── DriveSeat      VehicleSeat
```

Das `Chassis` ist ein einfacher Quader, unsichtbar, etwas kleiner als die
Karosserie: die Physik rechnet mit einem Kasten, der Spieler sieht ein Auto.
Name fängt mit `F` an = gelenkt, mit `R` = angetrieben.

**Gebäudemodule** brauchen alle dieselbe Grundfläche
(`Config.Assets.BuildingFootprint`, aktuell 28) und die Höhe aus
`BaseHeight`/`FloorHeight`/`RoofHeight`. Teile, die vom Bezirk eingefärbt
werden sollen, bekommen das Attribut `Tintable = true` — alles andere behält
seine eigenen Materialien.

**Reihenfolge:** erst **ein** Fahrzeug ganz durch die Pipeline schicken und in
Studio ansehen. Erst wenn genau ein Auto gut aussieht und gut fährt, die
anderen fünf. Danach der Gebäudebaukasten, und auch da erst die Altstadt
komplett, nicht fünf Bezirke halb.

### Der Rest
1. **Studio:** Game Settings → Security → *Enable Studio Access to API Services*
   einschalten, sonst wird nichts gespeichert.
2. **Sounds:** `src/shared/SoundCatalog.luau` — Asset-IDs aus der Roblox-
   Audiobibliothek als `"rbxassetid://ZAHL"` eintragen. Jeder leere Eintrag
   bleibt einfach stumm, es geht nichts kaputt.
3. **Store:** Creator Dashboard → Monetization → Passes bzw. Developer Products
   anlegen, dann die IDs in `src/server/Systems/MonetizationService.luau`
   eintragen (läuft über das Konto des Vaters).
4. **Admin:** die eigene UserId in `src/server/AdminList.luau` eintragen. Ohne
   Eintrag gibt es live keine Admins; im Studio bist du automatisch einer.

## Entscheidungen / Notizen 📌
- GhostNet liegt als eigenständiges Spiel unter `ghostnet/`, unabhängig von
  PlanetForge (Repo-Wurzel) und TURMFALL (`turmfall/`). Eigene `CLAUDE.md`,
  eigene `PHASEN.md`, eigener Build.
- Der Shop ist von überall aus erreichbar, nicht an den Hehler gebunden — das
  Rig ist die eigene Ausrüstung, kein Ladenregal. Bezahlt wird trotzdem nur von
  der Bank, man muss also vorher zum Hehler.
- Missionen sind Daten, keine Skripte. Wer eine neue schreibt, fasst nur
  `Shared/Missions.luau` an. Das Schema steht dort als `Missions.Example`.
- Leitregel für jede künftige Mission: sie ist gleichzeitig das Tutorial für
  ein System **und** schaltet dieses System dauerhaft frei. Keine Mission
  bauen, deren Inhalt danach verschwindet.
- **Zwei Paletten, mit Absicht:** `Config.Palette` ist die Stadt (hell),
  `Config.Theme` ist das Fake-OS (dunkel). Der Kontrast zwischen hellem Tag
  draußen und schwarzem Terminal im Fenster ist der Look des Spiels. Wer das
  Terminal aufhellt, nimmt ihm die Identität.
- **Mechanik geht nicht verloren, sie zieht um.** Als der Tag-/Nachtzyklus
  abgeschaltet wurde, ist der Nachtbonus nicht gestrichen, sondern an den Ort
  gehängt worden (`Config.Cover`). Regel für später: eine Kulissenänderung darf
  nie stillschweigend eine Spielmechanik mitnehmen.
- **Identität der offenen Welt:** kein GTA-Klon mit Hacking, sondern ein
  Hacking-Spiel mit offener Stadt. Daraus folgt alles Weitere: keine
  Schusswaffen, kein Kampfsystem, Autos sind Werkzeug (schneller da, mehr
  Lager) statt Selbstzweck, NPCs sind Hindernis statt Gegner, und die Polizei
  ist eine Verfolgung, die im bestehenden Bust endet. Wer das später aufweicht,
  baut ein anderes Spiel.
- Verkehr, Fußgänger und Streifenwagen laufen alle auf demselben
  `RoadNetwork`-Graphen, der aus `Config.City` gerechnet wird. Es gibt keine
  zweite Karte und keine handgesetzten Wegpunkte, die auseinanderlaufen können.
