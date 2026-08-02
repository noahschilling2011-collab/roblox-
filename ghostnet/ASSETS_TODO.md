# ASSETS_TODO — was noch gebaut oder besorgt werden muss

> `ReplicatedStorage/Assets/` ist leer. Was das heißt, ist seit v2.5.0
> **unterschiedlich**:
>
> - **Fahrzeuge sind nicht mehr magenta.** `VehicleChassis` baut eine echte
>   Silhouette aus Parts und Wedges — Motorhaube, abfallende Dachlinie,
>   Kotflügel, Fenster, Lichter, Grill. Ein hochgeladenes Modell hat trotzdem
>   Vorrang und ist die bessere Lösung; die Liste unten bleibt also gültig,
>   sie ist nur kein Notfall mehr.
> - **Gebäude, Props und Figuren sind weiter magenta.** Die werden bewusst
>   *nicht* nachgebaut: ein Platzhalter, den man übersehen kann, ist kein
>   Platzhalter.
>
> Das Spiel ist in beiden Fällen **vollständig spielbar**. Sobald ein Modell im
> richtigen Ordner unter dem richtigen Namen liegt, wird es beim nächsten
> Serverstart automatisch benutzt. Kein Code muss angefasst werden.

Beim Serverstart schreibt `AssetLibrary.Report()` genau diese Liste in die
Ausgabe — inklusive der Pflicht-Kinder je Fahrzeug.

## Zwei Wege, beide erlaubt, gerne gemischt

**A — Selbst modellieren (Blender → MeshPart).** Der bessere Weg für
Fahrzeuge, weil dann alles zusammenpasst. In Blender bauen (Roblox nutzt **Y
als Höhe**), als `.obj` oder `.fbx` exportieren, in Studio über den Asset
Manager (3D-Import) hochladen. Es gibt ein **Dreiecks-Limit pro MeshPart** —
schlag den aktuellen Wert in der offiziellen Roblox-Dokumentation nach, rate
ihn nicht. Zu dichte Modelle werden abgelehnt oder laufen auf Handys schlecht.

**B — Fertige Modelle aus dem Creator Store.** Schneller Weg für Gebäude,
Möbel und Straßenmöblierung. Nur Assets mit passender Lizenz. Vor dem Einbau
**jedes Modell prüfen**: enthaltene Skripte löschen, Teilezahl ansehen,
`Anchored` setzen. Nie ein Modell mit Skript ungeprüft ins Spiel ziehen.

Material geht über `SurfaceAppearance` (PBR) oder schlicht `Color` +
`Material`. Für den Anfang reicht Farbe und `SmoothPlastic` / `Metal` / `Glass`.

## Reihenfolge

**Erst ein einziges Fahrzeug ganz durch die Pipeline schicken** und in Studio
ansehen. Erst wenn genau ein Auto gut aussieht *und* gut fährt, die anderen
fünf. Danach der Gebäudebaukasten, und auch da erst die Altstadt komplett —
nicht fünf Bezirke halb.

---

# 1. Fahrzeuge — der größte optische Gewinn

Seit v2.5.0 baut der Code selbst ein ordentliches Auto, also ist hier nichts
mehr dringend. Ein richtiges Modell sieht trotzdem deutlich besser aus, und es
wirkt an vier Stellen gleichzeitig: Verkehr, Händler, Garage, Streifenwagen —
alle holen dieselbe Karosserie.

**Alle sechs teilen denselben Aufbau.** `Chassis` ist eine einfache,
unsichtbare Box, etwas kleiner als die Karosserie: die Physik rechnet mit
einem Kasten, der Spieler sieht ein Auto. Nur `Chassis` und die Räder
kollidieren — alles andere setzt `VehicleChassis` beim Bauen selbst auf
`CanCollide = false`.

Radnamen sind eine Regel, keine Deko: **Name beginnt mit `F` = gelenkt, mit
`R` = angetrieben.**

### Vehicles/Sedan
```
Ordner:  ReplicatedStorage/Assets/Vehicles
Model-Name: Sedan
Pflicht-Kinder (exakte Namen):
  Chassis      Part, unsichtbar, CanCollide = true  → PrimaryPart
  Body         MeshPart oder Model, CanCollide = false
  Wheels/FL    MeshPart oder Part (Cylinder)
  Wheels/FR
  Wheels/RL
  Wheels/RR
  DriveSeat    VehicleSeat
Optional:
  Glass        MeshPart, CanCollide = false
  Lights/HeadL Neon-Part
  Lights/HeadR
  Lights/TailL Neon-Part — leuchtet beim Bremsen auf
  Lights/TailR
Ungefähre Maße: 6.2 x 2.8 x 12 Studs
Woher: Toolbox („free car model") oder Blender-Export als MeshPart
```

### Vehicles/Compact
```
Ordner:  ReplicatedStorage/Assets/Vehicles
Model-Name: Compact
Pflicht-Kinder: wie Sedan
Ungefähre Maße: 6 x 2.6 x 11 Studs
Charakter: billig, unauffällig — das Auto, mit dem man nicht auffällt
Woher: Toolbox oder Blender
```

### Vehicles/Sports
```
Ordner:  ReplicatedStorage/Assets/Vehicles
Model-Name: Sports
Pflicht-Kinder: wie Sedan
Ungefähre Maße: 6.2 x 2.3 x 12.5 Studs, flach
Charakter: schnell und auffällig — 1,6x Fahndungszuschlag
Woher: Toolbox oder Blender
```

### Vehicles/Van
```
Ordner:  ReplicatedStorage/Assets/Vehicles
Model-Name: Van
Pflicht-Kinder: wie Sedan
Ungefähre Maße: 6.6 x 4 x 14 Studs, hoch, mit Ladefläche
Charakter: das einzige Fahrzeug mit Darknet-Lagerplatz
Woher: Toolbox („delivery van") oder Blender
```

### Vehicles/Bike
```
Ordner:  ReplicatedStorage/Assets/Vehicles
Model-Name: Bike
Pflicht-Kinder (exakte Namen):
  Chassis      Part, unsichtbar, CanCollide = true  → PrimaryPart
  Body         MeshPart, CanCollide = false
  Wheels/F     vorne, gelenkt
  Wheels/R     hinten, angetrieben
  DriveSeat    VehicleSeat
Ungefähre Maße: 2 x 2.4 x 7 Studs
Charakter: wendig, kommt durch Gassen, kein Lager
Woher: Toolbox („motorcycle") oder Blender
```

### Vehicles/Police
```
Ordner:  ReplicatedStorage/Assets/Vehicles
Model-Name: Police
Pflicht-Kinder: wie Sedan
Ungefähre Maße: 6.4 x 2.9 x 13 Studs
Hinweis: Bringt das Modell Lights/Blau und Lights/Rot mit, benutzt
         PursuitService die. Fehlen sie, setzt es selbst zwei Neonflächen
         aufs Dach — das Modell muss also kein Blaulicht haben.
Woher: Toolbox („police car") oder Blender
```

---

# 2. Figuren

### Characters/Officer — wichtiger als er klingt
```
Ordner:  ReplicatedStorage/Assets/Characters
Model-Name: Officer
Aufbau:  Ein normales R6- oder R15-Rig mit HumanoidRootPart als PrimaryPart.
         Ein Humanoid darf drin sein — hier ist er richtig, weil der
         Polizist laufen, Treppen nehmen und animiert werden soll.
Ungefähre Maße: 2 x 5.6 x 1.4 Studs
Wofür:   Steigt ab Fahndungsstufe 3 aus dem Streifenwagen und verfolgt zu
         Fuß. Ohne Modell läuft ein magenta Klotz hinter dir her — es
         funktioniert, sieht aber albern aus.
Woher:   Studio: Avatar → Rig Builder, dann Kleidung. Oder Toolbox.
```

### Characters/Pedestrian
```
Ordner:  ReplicatedStorage/Assets/Characters
Model-Name: Pedestrian
Aufbau:  KEIN Humanoid. Hintergrund-Fußgänger sind bewegte Modelle ohne
         Steuerung — ein Humanoid pro Passant kostet mehr als der ganze
         restliche Passant. Ein Rumpf, ein Kopf, PrimaryPart am Rumpf.
Ungefähre Maße: 1.8 x 5.4 x 1 Studs
Woher:   Blender oder ein vereinfachtes Rig ohne Humanoid.
```

### Characters/Guard
```
Ordner:  ReplicatedStorage/Assets/Characters
Model-Name: Guard
Aufbau:  Wie Pedestrian, ohne Humanoid — Wachen patrouillieren zwischen zwei
         Attribut-Punkten und werden per PivotTo bewegt.
Ungefähre Maße: 2 x 5.6 x 1.4 Studs
Wofür:   Bankwachen. Melden Alarm, greifen nie an.
Woher:   Blender oder Toolbox.
```

---

# 3. Gebäudebaukasten

Häuser werden gestapelt: **Sockel → n × Etage → Dach**. Alle Module brauchen
**dieselbe Grundfläche** (`Config.Assets.BuildingFootprint`, aktuell **28
Studs**) und die Höhe aus `Config.Assets`:

| Modultyp | Höhe | Config-Wert |
|---|---|---|
| Sockel | 14 Studs | `BaseHeight` |
| Etage | 11 Studs | `FloorHeight` |
| Dach | 4 Studs | `RoofHeight` |

Teile, die vom Bezirk eingefärbt werden sollen, bekommen das Attribut
**`Tintable = true`**. Alles ohne dieses Attribut behält seine eigenen
Materialien — so bleiben Fenster Glas, auch wenn die Altstadt beige ist.

Drei Kleinigkeiten machen mehr aus als jede Lichtstimmung: **Dachkante steht
über** (bündig sieht immer nach Klotz aus), **Fenster zwei Studs
zurückgesetzt** (das erzeugt die Schatten), **Sockel dunkler** (Gebäude sind
unten schmutziger — das macht der Code schon).

### Buildings/Base_Shop
```
Ordner:  ReplicatedStorage/Assets/Buildings
Model-Name: Base_Shop
Aufbau:  Erdgeschoss mit Schaufensterband. PrimaryPart in der Mitte.
Maße:    28 x 14 x 28 Studs
Woher:   Studio (Parts + Material) oder Toolbox („shop front")
```

### Buildings/Base_Entry
```
Ordner:  ReplicatedStorage/Assets/Buildings
Model-Name: Base_Entry
Aufbau:  Erdgeschoss mit Hauseingang und Vordach.
Maße:    28 x 14 x 28 Studs
```

### Buildings/Base_Garage
```
Ordner:  ReplicatedStorage/Assets/Buildings
Model-Name: Base_Garage
Aufbau:  Erdgeschoss mit Rolltor.
Maße:    28 x 14 x 28 Studs
```

### Buildings/Floor_A
```
Ordner:  ReplicatedStorage/Assets/Buildings
Model-Name: Floor_A
Aufbau:  Standardetage, schlichte Fensterreihe. Fenster zurückgesetzt.
Maße:    28 x 11 x 28 Studs
```

### Buildings/Floor_B
```
Ordner:  ReplicatedStorage/Assets/Buildings
Model-Name: Floor_B
Aufbau:  Standardetage mit Balkonen.
Maße:    28 x 11 x 28 Studs
```

### Buildings/Floor_C
```
Ordner:  ReplicatedStorage/Assets/Buildings
Model-Name: Floor_C
Aufbau:  Bürofassade, durchgehendes Glas.
Maße:    28 x 11 x 28 Studs
```

### Buildings/Roof_Flat
```
Ordner:  ReplicatedStorage/Assets/Buildings
Model-Name: Roof_Flat
Aufbau:  Flaches, BEGEHBARES Dach mit Brüstung. Überstehende Kante.
Maße:    30.4 x 4 x 30.4 Studs (Grundfläche + 2x RoofOverhang)
Wichtig: Dächer sind ein echter Weg — der Bankraub „von oben" hängt daran.
         Die Oberseite muss CanCollide = true sein.
```

### Buildings/Roof_Tech
```
Ordner:  ReplicatedStorage/Assets/Buildings
Model-Name: Roof_Tech
Aufbau:  Wie Roof_Flat, plus Lüftungskästen und Antennen.
Maße:    30.4 x 4 x 30.4 Studs
```

---

# 4. Straßenmöblierung

Eine leere Straße mit perfekten Häusern wirkt tot; eine durchschnittliche
Straße mit Kram darauf wirkt echt. Das ist der billigste Realismus, den es
gibt — und das hier sind die kleinsten Modelle der ganzen Liste.

Alle setzt der Code auf `CanCollide = false` (man soll nicht am Poller
hängenbleiben) und `CastShadow = false`.

```
Ordner:  ReplicatedStorage/Assets/Props
Model-Name: Laterne        ~1.6 x 8 x 1.6   Straßenlaterne
Model-Name: Ampel          ~1.6 x 8 x 1.6   Ampelmast
Model-Name: Muelltonne     ~2 x 3 x 2
Model-Name: Poller         ~0.8 x 3 x 0.8
Model-Name: Verteiler      ~2 x 4 x 1.4     Verteilerkasten
Model-Name: Schild         ~1.4 x 7 x 0.3   Verkehrsschild
Model-Name: Feuerleiter    ~2.6 x 1 x 1.2   EINE Sprosse, wird gestapelt
Woher: Toolbox („street props pack") oder schnell in Studio gebaut
```

**`Feuerleiter` ist keine Deko:** sie ist der Weg aufs Dach. Ohne sie sind
begehbare Dächer unerreichbar und „von oben" fällt als Weg in die Bank weg.

---

# 5. Was passiert, wenn du fertig bist

1. Modell in den richtigen Ordner unter den richtigen Namen legen.
2. `PrimaryPart` setzen — ohne den steht das Modell schief oder im Boden.
3. Play drücken. In der Ausgabe steht, was noch fehlt.
4. Ist die Liste leer, steht dort `[GHOSTNET] Alle Vorlagen gefunden.`

Danach: **Bildrate messen** (F7 → MicroProfiler). Echte Modelle haben mehr
Dreiecke als Klötze — das ist der Moment, in dem `Config.City.Grid` und
`Config.Traffic.MaxActive` wieder wichtig werden.
