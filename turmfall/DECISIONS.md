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
