# TURMFALL – Entscheidungs-Log

Offene Design-Fragen werden hier entschieden und dokumentiert (statt bei
jedem Detail nachzufragen), wie in der Arbeitsweise vereinbart.

## Meilenstein 1

**D1 – Rastermaß der Teilgrößen.** Das Konzept nennt Größen wie „2x1x2".
Entscheidung: 1 Rastereinheit = 2 Studs (Schwerblock also 4×2×4 Studs),
damit die Teile zur Roblox-Charaktergröße passen und Türme sichtbar wachsen.

**D2 – Kollaps beendet die Runde NICHT.** Nach einem Kollaps werden die
gefallenen Teile entfernt, der Verursacher ist markiert (0 Punkte am Ende),
und die Runde läuft weiter. Grund: Eine 3-Minuten-Runde sofort zu beenden
bestraft 11 Unschuldige; weiterbauen hält alle im Spiel. Mehrere Kollapse
pro Runde sind möglich – jeder Verursacher verliert seinen Einsatz.

**D3 – „Kontakt zur Kaskade" wird über den Ringpuffer angenähert.** Statt
teurer Kollisions-Historie gilt: Zwei Teile hatten Kontakt, wenn ihre
Mittelpunkte in irgendeinem 4-Hz-Sample näher beieinander waren als die
Summe ihrer Näherungsradien plus 1,25 Studs Toleranz. Das ist deterministisch,
billig und pur testbar (BlameLogic + Tests).

**D4 – Ist das jüngste Teil ohne Kontakt, wandert die Prüfung weiter.**
Der Algorithmus prüft Platzierungen von neu nach alt und nimmt das erste
Teil mit Kaskaden-Kontakt (Kaskaden-Mitglieder zählen trivialerweise als
Kontakt). Findet sich keines, gibt es KEINEN Verursacher – fair bleiben,
statt zwanghaft jemanden zu bestrafen.

**D5 – Federblock als Zwei-Platten-Konstrukt.** PrismaticConstraint führt
die Bewegung senkrecht, SpringConstraint federt. Ein einzelner Part mit
hoher Elastizität wäre einfacher, aber das Konzept verlangt ausdrücklich
„SpringConstraint-basiert" – und das Wippen zweier Platten liest sich im
Spiel deutlich besser.

**D6 – Client-Rotation nur um die Y-Achse.** Der Server extrahiert aus dem
Client-CFrame ausschließlich Position + Gieren (auf 45° gerastert) und baut
den CFrame selbst neu. Verhindert schräg „hineingedrehte" Exploits und hält
die Validierung einfach.

**D7 – Punkte-Minimum 1 pro überlebendem Teil.** Auch ein Teil direkt auf
der Plattform gibt 1 Punkt. Sonst wäre die sichere Spielweise in den ersten
Sekunden komplett wertlos und niemand würde unten anfangen.

**D8 – Tests als Luau-VM-Suite statt TestEZ.** Die reine Logik (Schuld,
Punkte, Kataloge) läuft in einer echten Luau-VM (luau-web) über
`tests/testlauf.mjs` – gleiche Idee wie TestEZ-Specs, aber ohne
Studio-Abhängigkeit ausführbar (CI-tauglich). Zusätzlich prüft ein
statischer Abgleich, dass jedes benutzte Remote in Network.luau deklariert ist.

**D9 – Einzelne Fälle räumen sich selbst auf.** Ein einzeln gefallenes Teil
(kein Kollaps) verschwindet nach 2 Sekunden und zählt nicht mehr für Punkte.
So sammelt sich unter der Arena kein Physik-Müll.

## Meilenstein 2

**D10 – Session-Locking selbst gebaut statt ProfileService.** Das Projekt
soll ohne externe Libraries auskommen (Option laut Konzept). Der Lock lebt
als `{ lock = {jobId, at}, data = profil }` im DataStore: UpdateAsync
übernimmt ihn atomar, ein Heartbeat verlängert ihn, abgelaufene Locks
(>120 s) gelten als tot. Bekommt ein Server den Lock nicht, läuft die
Session READ-ONLY - lieber eine Session nichts speichern als Käufe
überschreiben.

**D11 – Universal-Skins belegen alle vier Teil-Slots gleichzeitig.** Ein
Klick auf einen "alle"-Skin rüstet ihn für jeden Teiltyp aus; teilgebundene
Skins (z. B. Eiskeil) überschreiben danach gezielt einzelne Slots. Das hält
die UI bei einem Klick statt vier Dropdowns.

**D12 – Skins wirken ab der nächsten Platzierung.** Bereits im Turm
stehende Teile werden beim Umrüsten nicht umgefärbt: Die Optik eines Teils
friert bei der Platzierung ein. Das spart Replikations-Traffic und macht
den Turm zur sichtbaren "Geschichte" der Runde.

**D13 – Kollaps-Effekte laufen auf dem eigenen Client.** Konfetti/Zeitlupe
spielt der Client ab, der den Skin ausgerüstet hat - niemandem sonst wird
Optik aufgezwungen, und der Server bleibt davon komplett unberührt.

## Meilenstein 3

**D14 – Der Kosmetik-Guard ist strukturell, nicht nur eine Prüfung.**
Produkte besitzen genau EIN Vergabe-Feld (`grantsSkins`), das nur Skin-IDs
tragen kann; es existiert kein Feld für Punkte, Teile, Slots oder Trümmer.
validate() prüft zusätzlich jeden Verweis gegen den SkinCatalog und läuft
beim Serverstart UND in den Tests (inklusive Sabotage-Test). Gameplay-Werte
an Käufe zu koppeln erfordert damit eine bewusste Architektur-Änderung
statt eines versehentlichen Einzeilers.

**D15 – Read-only-Sessions blockieren Käufe komplett.** Hat ein Server den
Session-Lock nicht bekommen, gibt ProcessReceipt NotProcessedYet zurück und
der Trümmer-Kauf lehnt ab. Roblox wiederholt den Beleg später automatisch -
so geht kein Kauf verloren UND keiner wird auf einem veralteten Profil
gutgeschrieben und anschließend überschrieben.

**D16 – Trümmer-Ausschüttung ist bewusst simpel.** 10 pro Runde plus
1 je 5 Punkte. Die günstigsten Skins (150) gibt es nach wenigen Runden,
Rares (600) nach einem Abend - Free-Progression ohne Grind-Wand. Balancing
lebt als Konstanten im MonetizationCatalog.

## Meilenstein 4

**D17 – "Primär gegnerisch belastet" = nächstes Stütz-Teil gehört einem
Gegner.** Eine echte Lastverteilungs-Analyse wäre teuer und schwer erklärbar.
Die Näherung "das nächste Teil unterhalb der Platzierung" ist billig,
deterministisch und für Spieler intuitiv: Wer direkt auf fremde Teile baut,
zahlt den Cooldown; wer auf Plattform oder eigene Teile baut, nie.

**D18 – Zeitlupe ist ausschließlich Optik.** Eine echte globale Zeitlupe
(Physik-Timescale) würde die Simulation aller Clients und das Schuld-System
verzerren. Farbkorrektur + FOV liefern das Gefühl, ohne die Fairness
anzufassen - deshalb steht "nur visuell" auch im Konzept.

**D19 – Touch platziert über einen Button, nicht per Tipp.** Auf Mobile
dreht man die Kamera durch Ziehen/Tippen - ein Tipp, der gleichzeitig baut,
produziert Fehlplatzierungen (und die kosten im Finale die einzige
Platzierung). Deshalb: Tippen zielt, der 🧱-Button baut.

**D20 – Stabilitäts-Score ist die mittlere Assembly-Geschwindigkeit.**
Simpel, ein Wert pro Sekunde über ein Remote, keine Per-Teil-Replikation.
100 = alles ruht, 0 = mittlere Geschwindigkeit >= STABILITY_SPEED_FOR_ZERO.

## Nach Release-Feedback

**D22 – Katastrophen setzen die Schuld aus.** Wind und Erdbeben können
den Turm kippen; das Schuld-System würde dann den letzten Bauer bestrafen,
der nichts falsch gemacht hat. Deshalb ist die Schuld-Zuweisung während
eines Events plus Schonfrist ausgesetzt - das Replay läuft trotzdem, mit
dem Banner "Die Katastrophe war schuld". Der Goldrausch ist bewusst das
Gegenstück: ein reines Belohnungs-Event, damit "Event" nicht nur "Gefahr"
bedeutet.

**D23 – Level sind rein kosmetische Progression.** XP/Level schalten
NICHTS frei, was Physik oder Punkte beeinflusst (gleiche Regel wie bei
Skins/Käufen). Sie sind die sichtbare "Ich war fleißig"-Zahl im
Leaderboard - der stärkste kostenlose Bindungs-Treiber der Topspiele.

**D21 – Solo-Modus als automatischer Fallback statt Button.** Wer allein
im Server ist (Studio-Play, leere Server zur Randzeit), startet nach 8
Sekunden automatisch eine Übungsrunde - ohne Menü, ohne Extra-Klick. Der
Multiplayer-Einstieg bleibt unverändert bei 2 Spielern mit Countdown;
joint während der Solo-Wartezeit jemand, übernimmt sofort der normale
Countdown. Alle Systeme (Kollaps, Schuld, Punkte, Trümmer) funktionieren
solo identisch - man kann sich selbst den Turm zerlegen und verliert dann
genauso seinen Einsatz.
