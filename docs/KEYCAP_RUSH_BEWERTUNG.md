# KEYCAP RUSH — Bewertung

Stand 6. September 2026. Bewertet wird das Konzept, nicht der Prompt-Stil.
Alle Spielerzahlen sind aus Trackern gezogen und unten verlinkt; alle Rechnungen
benutzen ausschließlich die Zahlen aus deinem eigenen Dokument.

---

## Kurzfassung

Das Dokument ist als Arbeitsanweisung stark — besser als das, was Leute normalerweise
an Claude Code schicken. Als Spielentwurf hat es zwei Probleme, die beide vor der
ersten Zeile Code gelöst gehören:

1. **Die zentrale Entscheidung ist keine.** Nach ca. einer Stunde Spielzeit findet
   jeder Spieler dieselbe optimale Routine und wiederholt sie. Ich kann das mit
   deinen eigenen Zahlen zeigen — siehe unten.
2. **Der Markt für genau dieses Ding ist bereits vermessen worden**, mehrfach, mit
   ziemlich eindeutigem Ergebnis.

Punkt 2 heißt nicht „bau es nicht". Es heißt: bau es mit der richtigen Erwartung.

---

## 1. Der härteste Einwand: das gibt es schon, und die Zahlen liegen vor

Das ist der Teil, den ich vor allem anderen loswerden will, weil er alle
Design-Feinheiten relativiert.

**Das Spiel, von dem KEYCAP RUSH abgeleitet ist, lebt und ist gerade in den Top 5
von Roblox.** `+1 Speed Keyboard Escape` (SecretVerse Studio) steht heute bei rund
**267.000 gleichzeitigen Spielern**. Seine Mechanik: du läufst über Riesen-Tasten,
jeder Schritt gibt +1 Speed, Stages haben Mindest-Speed-Gates (World 1 Stage 1 ab 65,
World 2 ab 140, World 3 Stage 10 ab 765), dazu Rebirths, Auras und Trails. Also:
Tastatur-Optik, Speed als Währung, Speed-Gates pro Stage — die drei Dinge, die auch
bei dir den Kern bilden. Der Umbenennen-Fix aus deiner Änderungstabelle löst das
Rechtsrisiko vielleicht; das Auffindbarkeits-Problem löst er nicht. Wer auf Roblox
„keyboard speed" sucht, landet bei einem Spiel mit 267k CCU, nicht bei dir.

**Die Keycap-Nische selbst ist schon durchprobiert.** Was es dort gibt:

| Spiel | Alter | Allzeit-Peak CCU | jetzt |
|---|---|---|---|
| `Press a Keycap!` | ~7 Wochen | 6.090 (vor 1 Woche) | ~440 live, 974 24h-Peak |
| `Collect a Keycap!` | 11 Monate | 2.874 (Jan 2026) | 1–3 Spieler |

`Press a Keycap!` hat 6,7 Mio. Visits eingesammelt und ist sieben Wochen nach Launch
schon eine Größenordnung unter seinem Peak. `Collect a Keycap!` hat 8,1 Mio. Visits
und ist tot. Beide haben übrigens genau die Systeme drin, die du explizit ausschließt:
Rebirth, passives Einkommen durch Worker, Rolling für bessere Keycaps.

**Das Steal-Genre lebt, aber es rotiert schnell.** `Steal a Brainrot` hatte im
Oktober 2025 den Rekord von 25,4 Mio. gleichzeitigen Spielern und steht heute je
nach Tracker bei 80.000–135.000. Das sind rund 99,5 % Rückgang in elf Monaten.
Gleichzeitig steht `Steal An Egg` heute auf Platz 1 mit ~1,87 Mio. CCU. Das Format
funktioniert weiter — aber der Gewinner wird alle paar Monate neu gewürfelt, und
es ist nie der Klon, sondern die nächste Neuverpackung.

**Was ich daraus ableite:** die realistische Obergrenze für ein Keycap-Steal-Spiel
von einer Person liegt bei einigen tausend CCU für ein paar Wochen, nicht bei
sechsstellig. Wenn das für dich okay ist — als erstes fertiges Roblox-Spiel, um
Luau, DataStores und Server-Autorität an einem echten Ding zu lernen — ist das ein
gutes Projekt. Wenn die stille Erwartung „das könnte einschlagen" ist, sagen die
Zahlen nein, und dann triffst du Design-Entscheidungen aus dem falschen Grund.

---

## 2. Das Loch im Loop: die Cash-Out-Entscheidung entscheidet nichts

Dein Dokument sagt, alles drehe sich um „früh am Stage-1-Pad auszahlen (sicher, wenig)
oder bis Stage 3 durchziehen (viel mehr, aber lange weg)". Rechne ich das mit deinen
Zahlen durch, existiert diese Abwägung nicht.

**Speed-Kurve** `WalkSpeed = 16 + min(vorrat * 0.02, 84)`:

| Ziel | nötiger Vorrat |
|---|---|
| Stage-1-Gate (30) | 700 |
| Stage-2-Gate (50) | 1.700 |
| Stage-3-Gate (75) | 2.950 |
| Speed-Cap (100) | 4.200 |

**Auszahlung** `Wins = floor(vorrat * faktor)`, bei Vorrat 4.200:

| Pad | Faktor | Wins |
|---|---|---|
| Stage 1 | 0,01 | 42 |
| Stage 2 | 0,025 | 105 |
| Stage 3 | 0,05 | 210 |

Derselbe Vorrat, fünffache Auszahlung. Der einzige Preis für Stage 3 ist Laufzeit.
Damit Stage 1 überhaupt konkurrieren könnte, müsste der Stage-3-Rundlauf **mehr als
fünfmal so lange** dauern wie der Stage-1-Rundlauf. Bei drei ungefähr gleich langen
Stages plus Rückweg landest du eher bei Faktor 2,5–3,5. Stage 3 gewinnt immer.
Es sei denn, der Umweg kostet dich real etwas — und das tut er nicht, siehe Punkt 3.

**Und der Vorrat hat keine Obergrenze.** Der Deckel sitzt auf der WalkSpeed, nicht
auf dem Vorrat. Bei Vorrat 100.000 läufst du weiter mit 100, kassierst aber 5.000 Wins.
Der Vorrat ist diebstahlsicher und todessicher. Also ist Horten risikofrei.

Wie schlimm ist das? Rechnen wir Wins pro Stunde bei Produktionsrate `R` und
Rundlaufzeit `t`, wenn du alle `T` Sekunden auszahlst:

`Wins/h = 0,05 · R · T / (T + t) · 3600`

Mit t = 120 s: auszahlen alle 2 Min → 90·R. Alle 10 Min → 150·R. Alle 60 Min → 174·R.

Das ist die gute Nachricht: es läuft nicht ins Unendliche, sondern in eine Asymptote.
Die schlechte: die optimale Strategie ist damit **„alle ~10 Minuten, immer Stage 3"**,
für jeden Spieler, in jeder Situation, für immer. Ein Spieler findet das in etwa einer
Stunde, und danach ist deine Kernentscheidung eine Routine. Genau das, was du in
Änderung #1 an v1 kritisiert hast, ist über die Zahlen wieder reingekommen.

Was dabei fehlt: **die beiden Zahlen, die die Ökonomie tatsächlich entscheiden, stehen
nicht im Prompt** — Preis einer Taste in Wins, und `speedPerSecond` pro Seltenheit.
Ob Reinvestieren das Horten schlägt, hängt allein an deren Verhältnis. Schritt 2 der
Baureihenfolge ist der Schritt, in dem sich das Spiel entscheidet, und er hat keine
Zahlen. Die Faktoren, die du festgelegt hast (0,01 / 0,025 / 0,05, der 0,02-Speedfaktor),
sind die, die am wenigsten bestimmen.

---

## 3. Das Loch im Diebstahl: Klauen tut nicht weh

Bei `Steal a Brainrot` wird dir das Ding weggenommen, das du gerade angeschaut hast,
und es steht zehn Sekunden später sichtbar bei jemand anderem. Der Verlust ist sofort,
konkret und ansehbar. Das ist der ganze Motor des Genres.

Bei dir wird eine **Produktionsquelle** geklaut. Der Verlust ist eine Rate, die minimal
sinkt. Der Bestand bleibt unangetastet — steht so explizit im Dokument. Das vermeidet
das Feel-Bad, aber es nimmt dem einzigen sozialen System des Spiels jede Wucht. Ein
Risiko, das man im Moment nicht spürt, steuert kein Verhalten.

Drei Folgeeffekte:

- **Der Anwesenheits-Bonus wird zur Leerlauf-Belohnung.** Zuhause stehen verdoppelt die
  Hold-Dauer, kostet aber nichts, weil der Vorrat ortsunabhängig weiterläuft. Die
  optimale Defensive ist also: rumstehen und zuschauen. Du hast AFK-Farmen auf die
  Nicht-Liste gesetzt und über den Bonus wieder eingebaut.
- **Leaderstats zeigen die falsche Zahl.** Vorrat und Wins sind beide nicht klaubar.
  Was ein Dieb wissen will — wer hat gute Tasten, wer ist gerade weg — steht nirgends.
  Die Rangliste eines Klau-Spiels sollte Beute anzeigen.
- **Das Schild passt zeitlich nicht.** 45 s Schutz bei 180 s Abklingzeit sind 25 %
  Abdeckung. Ein Rundlauf bis Stage 3 dauert vermutlich länger als 45 s — dann schützt
  das Schild genau die Situation nicht, für die es da ist. Diese Zahl kannst du erst
  setzen, wenn du den Rundlauf einmal gestoppt hast.

---

## 4. Was trägt

Kein Pflicht-Lob, das sind die Stellen, die ich beim Prüfen nicht angreifen konnte:

- **Cash-Out als ProximityPrompt statt Touch-Trigger.** Richtig, und die Begründung
  stimmt: ein Vorrat-Reset per Versehen wäre der schlimmste denkbare Bug-artige Moment.
- **Klau-Cooldown pro Dieb-Opfer-Paar.** Löst ein echtes Problem, das die meisten
  Spiele des Genres nicht lösen. Zwei Zeilen für einen der wenigen Gründe, warum
  schwächere Spieler nicht sofort aufhören.
- **Sichtbares Tragen plus 40 % langsamer.** Das ist der Clip-Moment. Diebstahl muss
  für Umstehende lesbar sein, sonst passiert er sozial gar nicht.
- **Overshoot-Fail gestrichen.** Für Mobile richtig entschieden. Nebenwirkung: der
  Parcours ist damit kein Können mehr, sondern ein Stat-Check — beim zwanzigsten Mal
  eine Mautstation. Das ist der Preis, und er ist vertretbar, solange der Lauf kurz ist.
- **Der Abschnitt Server-Autorität.** Die aufgezählten Prüfungen sind genau die
  richtigen, und die Reihenfolge stimmt.
- **Die Regeln 1–8.** Besonders Regel 1. Für deine Lage — Code lesen können, aber
  nicht schreiben — ist das die wichtigste Regel im ganzen Dokument.

---

## 5. Technische Lücken im Spec

- **ProfileService verboten + „Datenverlust ist der Tod" ist ein Widerspruch.**
  Was ProfileService löst, ist Session-Locking: verhindern, dass zwei Server dieselben
  Spielerdaten schreiben, wenn jemand Server hoppt. Das ist genau der Duplikations- und
  Verlust-Vektor in einem Spiel mit klaubaren Objekten. Handgeschrieben geht das mit
  `UpdateAsync`, aber es ist echte Arbeit und steht in keinem deiner sechs Schritte.
  Entweder Ausnahme für ProfileService, oder Schritt 6 wird deutlich größer als geplant.
- **DataStore-Schreibrate.** Roblox drosselt Schreibvorgänge. Bei einem Vorrat, der
  sekündlich wächst, brauchst du eine Speicher-Kadenz (z. B. alle 60 s plus beim Leave),
  nicht Speichern bei jeder Änderung. Steht nicht im Spec.
- **Verlassene Plots sind undefiniert.** Was passiert mit Plot und Tasten, wenn der
  Besitzer geht? Bleiben sie stehen (dann sind sie herrenlose Beutekisten und der
  Anwesenheits-Bonus greift nie), oder verschwinden sie (dann gehen dem Server die
  Ziele aus)? Das ist in einem Klau-Spiel keine Randfrage.
- **Der Loop braucht Mitspieler und du hast keine.** Auf einem frischen Server mit
  zwei Leuten ist KEYCAP RUSH ein Farm-Spiel mit gelegentlichem Ärgern. Kleine
  Servergröße (8–12) hilft, NPC-Plots als Klau-Ziele wären die andere Antwort. Beides
  fehlt, und beides muss vor dem Launch entschieden sein, nicht danach.
- **3.000-Parts-Budget:** plausibel als Ziel, aber die praktische Grenze auf Mobile
  ist eher die Zahl gleichzeitig aktiver ProximityPrompts und unterschiedlicher
  Materialien als die reine Part-Zahl. *Ungeprüft — ich habe das nicht gemessen.*

---

## 6. Wenn du es baust: die eine Änderung

Nicht drei Varianten, eine. Vor Schritt 2:

> **Jede Taste hält ihren eigenen Vorrat. Der Plot-Vorrat ist die Summe.
> Wer eine Taste klaut, klaut ihren Vorrat mit. Auszahlen leert alle.**

Das ist *ein* System statt zweier und es repariert drei Löcher gleichzeitig:

- Horten ist nicht mehr gratis — je länger du sammelst, desto mehr ist jede einzelne
  Taste für einen Dieb wert. Damit wird „wann zahle ich aus" zur echten Frage, ohne
  dass du ein Verfalls- oder Decay-System dazubauen musst.
- Diebstahl tut sofort weh und ist ansehbar: „Der hat meine ANY KEY *und* 2.400 Speed
  mitgenommen." Das ist der Clip.
- Es gibt einen echten Grund, zuhause zu bleiben — und damit wird die
  Farmen-oder-Rennen-Frage die Entscheidung, als die sie im Dokument beschrieben ist.

Ehrlicher Preis: für neue Spieler wird ein schlechter Moment deutlich schlechter, und
ein Dieb bekommt einen Sofortgewinn, was die Kurve schwankig macht. Gegenmittel: nur
einen Anteil übertragen (z. B. 50 %, Rest verfällt) und die Übertragung deckeln.

Und zur Auszahlungsstufe: die Faktoren müssen sich am **Zeitverhältnis der Rundläufe**
orientieren, nicht an einer runden Zahl. Miss zuerst, wie lange Stage 1 und Stage 3
hin und zurück wirklich dauern, und setz die Faktoren dann knapp *unter* dieses
Verhältnis. Erst dann wird das Risiko zum Tiebreaker, und das ist die Entscheidung,
die du eigentlich haben willst.

---

## Quellen

- [Most Played Roblox Games — Live Player Counts, September 2026 (rblxdb)](https://rblxdb.com/charts/most-played)
- [Steal a Brainrot — Rolimon's](https://www.rolimons.com/game/109983668079237)
- [Steal a Brainrot Player Count & Revenue Stats (RoWatcher)](https://rowatcher.com/games/7709344486/steal-a-brainrot)
- [Roblox's Steal a Brainrot becomes first game to surpass 25m concurrent players (PocketGamer.biz)](https://www.pocketgamer.biz/robloxs-steal-a-brainrot-becomes-first-game-to-surpass-25m-concurrent-players/)
- [All +1 Speed Keyboard Escape Stages (TechWiser)](https://techwiser.com/1-speed-keyboard-escape-stages/)
- [+1 Speed Keyboard Escape | Candy & Chocolate (Roblox)](https://www.roblox.com/games/95082159892680/1-Speed-Keyboard-Escape-Candy-Chocolate)
- [Press a Keycap! — Rolimon's](https://www.rolimons.com/game/128363460800653)
- [Collect a Keycap! — Rolimon's](https://www.rolimons.com/game/83282933434146)

**Geprüft:** alle Spielerzahlen gegen die verlinkten Tracker, die Peak-Zahl von
`Steal a Brainrot` gegen zwei unabhängige Quellen. Alle Rechnungen in Abschnitt 2
nachgerechnet, sie benutzen nur Zahlen aus deinem Dokument.
**Nicht geprüft:** die Roblox-Performance-Aussage in Abschnitt 5 (als ungeprüft
markiert). Die Tracker widersprechen sich beim aktuellen CCU von `Steal a Brainrot`
(80k vs. 135k) — die Richtung ist eindeutig, die exakte Zahl nicht.
**Dein Zehn-Sekunden-Check:** Öffne `+1 Speed Keyboard Escape` auf Roblox und schau
dir die Startzone an. Wenn du danach immer noch findest, dass KEYCAP RUSH optisch
eigenständig wirkt, ist mein Abschnitt 1 zu hart.

---

## Nachtrag: Was an dieser Bewertung selbst wackelt

Geschrieben in einer späteren Session, in der die verlinkten Tracker nicht erneut
abgerufen wurden. Drei Stellen, die vor einer Entscheidung nachgeprüft gehören:

1. **Abschnitt 2 zieht die falsche Schlussfolgerung aus seiner eigenen Formel.**
   `Wins/h = 0,05 · R · T / (T + t) · 3600` steigt streng monoton in `T`. Es gibt kein
   Optimum bei 10 Minuten — bei t = 120 s ist die Asymptote 180·R, und 10 Minuten sind
   einfach der Punkt, ab dem sich weiteres Warten kaum noch lohnt (83 % der Asymptote).
   Die Formel sagt in Wahrheit etwas Schärferes: **gar nicht auszahlen, bis man die Wins
   braucht.** Das ist der stärkere Vorwurf, und er wird im Text abgeschwächt.
2. **Abschnitt 2 überzieht.** Er behauptet gleichzeitig, der Loop sei kaputt, *und* die
   beiden Zahlen, die ihn entscheiden (Tastenpreis, `speedPerSecond`), fehlten im
   Dokument. Beides zusammen geht nicht. Solange Wins in Tasten reinvestiert werden und
   `R` dadurch wächst, ist Horten Verzicht auf Zinseszins — dann existiert die Abwägung
   sehr wohl, nur eben zwischen *reinvestieren* und *warten* statt zwischen Stage 1 und
   Stage 3. Die korrekte Aussage ist: die Entscheidung ist unbestimmt, nicht tot.
3. **Das Auffindbarkeits-Argument in Abschnitt 1 setzt auf Suche.** Roblox-Traffic kommt
   überwiegend aus dem algorithmischen Feed und aus Empfehlungen, nicht aus der
   Stichwortsuche. Dass `+1 Speed Keyboard Escape` bei „keyboard speed" oben steht,
   schadet einem kleinen Spiel weniger als der Text nahelegt — der Feed sortiert nach
   Engagement der eigenen Sitzung, nicht nach Namensähnlichkeit. Der Genre-Sättigungs-
   Punkt bleibt trotzdem stehen; nur die Begründung über die Suche trägt ihn nicht.

Die Rechnungen der Speed-Kurve (700 / 1.700 / 2.950 / 4.200) und die drei Stützwerte
90·R / 150·R / 174·R wurden nachgerechnet und stimmen. Die Spielerzahlen wurden in
dieser Session **nicht** erneut gegen die Tracker geprüft.
