# KEYCAP RUSH — Design-Auftrag

Selbst geschrieben, nachdem das bisherige Design als „sieht kacke aus" zurückkam.
Er beschreibt, **was** geändert wird und **warum** — nicht wie es gefällt.

## Die Diagnose

Das bisherige Design ist **creme-pastell**: helle Flächen, dünne Kanten, flache
Füllungen, gedeckte Akzente. Das ist die Sprache eines gemütlichen Indie-Spiels.

Das Genre, an dem sich KEYCAP RUSH misst — Steal a Brainrot, Steal an Egg,
+1 Speed Keyboard Escape — spricht eine andere: **knallgesättigt, dicke dunkle
Umrandung um alles, große Radien, Verläufe statt flacher Flächen, fette Typo.**
Das ist kein Geschmacksunterschied, das ist eine andere Formsprache. Ein Kind, das
von Steal a Brainrot kommt, liest Pastell als „leer" und „unfertig".

Es ist ein Palette- und Kanten-Problem, kein Detailproblem. Deshalb wird nicht
nachgebessert, sondern die Formsprache getauscht.

## Was sich ändert

### 1. Tinte statt Braun
Neue Grundfarbe `INK` (24, 20, 18) — fast schwarz. Sie macht drei Jobs:
Schrift auf bunten Flächen, Umrandung um jedes Element, Kante unter jedem Knopf.
Eine einzige dunkle Farbe, die überall wiederkehrt, ist das, was den Look
zusammenhält.

Gegen das creme Panel schafft `INK` **17,4:1** statt bisher 11,7:1.

### 2. Akzente werden laut
| | vorher | nachher | Kontrast gegen INK |
|---|---|---|---|
| GREEN | 86, 190, 96 | **64, 196, 86** | 8,1:1 |
| BLUE | 108, 186, 240 | **56, 166, 246** | 6,9:1 |
| GOLD | 248, 196, 62 | **255, 190, 32** | 11,0:1 |
| RED | 230, 96, 88 | **246, 84, 74** | 5,5:1 |
| PURPLE (neu) | — | **176, 102, 244** | 5,3:1 |

Alle fünf bleiben über 4,5:1 — die Sättigung geht hoch, ohne dass die
Lesbarkeitsgarantie fällt. Nachgerechnet, nicht geschätzt.

### 3. Jedes Element bekommt eine Umrandung
`UIStroke` in `INK` auf jedem Panel und jedem Knopf. Das ist der Unterschied,
der am stärksten wirkt: Ohne Umrandung schwimmen helle Flächen im Bild,
mit Umrandung stehen sie darauf.

Nur belegte Properties: `Color`, `Thickness`, `ApplyStrokeMode`, `LineJoinMode`.
Was ein Doc-Abruf sonst noch behauptet hat (`BorderStrokePosition`, `BorderOffset`,
`UICorner.TopLeftRadius`), wird **nicht** benutzt — nicht verifizierbar.

### 4. Verlauf statt flacher Fläche
Jeder Knopf bekommt einen senkrechten `UIGradient`: oben 14 % heller als die
Grundfarbe, unten die Grundfarbe. Zusammen mit der dunkleren Unterkante und der
Umrandung ergibt das die Plastik, die Roblox-UI nicht über Schatten bekommt.

### 5. Größere Radien
`CORNER` von 12 auf 16. Kleine Radien wirken technisch, große wirken nach Spielzeug.

### 6. Die Welt zieht mit
Der Boden ist derzeit grau. Er wird kräftig grün — die Farbe, die jedes Spiel
dieses Genres unter den Füßen hat. Plots und Pads behalten ihre Rolle, bekommen
aber dieselbe dunkle Kante wie die UI.

## Was NICHT geändert wird

- Das Seltenheits-System (`RARITY_COLORS`, `RARITY_INK`, `RARITY_EDGE`,
  `RARITY_RANK`, `KEY_CROWN`). Das ist durchgerechnet und trägt.
- Die Regel „dunkle Schrift auf hellen Knöpfen". Weiße Schrift auf dem neuen
  Grün wären 2,3:1 — unlesbar. Der Simulator-Look kommt hier über Umrandung
  und Verlauf, nicht über weiße Schrift.
- Panels bleiben creme. CLAUDE.md verlangt hell und freundlich; das kollidiert
  nicht mit lauten Akzenten, sondern gibt ihnen den Grund, auf dem sie wirken.
- Geometrie. Der Parcours ist Block 0 und wartet auf Freigabe.

## Abnahme

Jede Farbkombination muss weiterhin 4,5:1 schaffen — der Testlauf rechnet das
nach und bricht sonst ab. Zusätzlich: jede Umrandung dunkler als ihre Fläche,
jeder Verlauf oben heller als unten.
