# Lebenslinie — Ausbau 2

Du arbeitest an `lebenslinie/index.html` (eine eigenständige Datei, kein Build-Step, kein npm,
Vanilla JS in einem IIFE, aktuell 174 KB). Test-API: `window.Lebenslinie` mit `getState`,
`nextYear`, `choose`, `eventCount`.

Vor jeder Phase: die laufende Datei als `index-funktioniert.html` wegkopieren.
Eine Phase pro Durchgang. Nach jeder Phase: messen, liefern, warten.

## Ausgangslage — gemessen, nicht geschätzt

Stand nach Ausbau 1 (Playwright headless, `Math.random` geseedet, 10–24 Läufe je Messung):

| | Wert |
|---|---|
| Berufe | 28, höchstes Gehalt 85.000 € |
| Hobbys | 18 |
| Vermögen nach 40 Jahren, beste Strategie | 1.571.297 € Median, bis 4.012.701 € |
| Alles Große einmal gekauft (größtes Auto, drei teuerste Immobilien, alle 18 Möbel) | **618.000 € Eigenkapital** |
| Wiederkehrende Ausgaben außer Lebenshaltung | Auto-Unterhalt, Instandhaltung, Hypothek — sonst nichts |

**Das ist das Kernproblem dieses Ausbaus:** Geld hat kein Ziel. Wer gut spielt, hat ab etwa
45 alles gekauft, was es zu kaufen gibt, und häuft danach nur noch an. Zusätzliche einmalige
Kaufobjekte lösen das nicht — sie verschieben den Zeitpunkt um ein paar Jahre. Es braucht
**wiederkehrende** Ausgaben, die eine echte Entscheidung sind.

Zweiter Befund: die letzten dreißig Lebensjahre sind leer. Ab 45 sinkt Gesundheit, ab 67 gibt
es halbes Gehalt, sonst passiert nichts Neues. Ein 80-Jahre-Leben hat ab etwa 50 kaum noch
Entscheidungen.

## Reihenfolge und warum

Steuern zuerst. Ohne sie sind alle neuen Preise gegen ein zu großes Budget balanciert, und
jede Zahl in Phase 7 bis 9 müsste später nochmal angefasst werden. Danach Berufswege, weil
die politische Laufbahn auf Ruf und Kontakten aufbaut, die dort entstehen. Gesundheit zuletzt,
weil sie das Spätspiel füllt, das ohne die anderen Phasen noch nicht existiert.

---

## Phase 6 — Geld bekommt ein Ziel

**Ist-Zustand:** `annualLife()` bucht das Bruttogehalt eins zu eins aufs Konto. Es gibt keine
Steuer. Die Lebenshaltung ist ein fester Betrag (9.600 €), unabhängig davon, ob jemand
22.000 € oder 190.000 € im Jahr verdient.

**Auftrag:**

1. **Einkommensteuer.** Progressiv, auf Gehalt, Creator- und Mieteinnahmen. Grobe Zielwerte:
   22.000 € brutto → rund 17.000 € netto, 45.000 € → rund 31.000 €, 85.000 € → rund 52.000 €,
   190.000 € → rund 105.000 €. Eine einzige monotone Formel reicht, keine Steuertabelle.
   Netto muss im UI sichtbar sein — im Karriere-Bereich und in der Seitenleiste.
2. **Lebensstil als Stufe** (0 bis 4), nicht als Einmalkauf. Jede Stufe kostet jedes Jahr Geld
   und gibt jedes Jahr Glück und Aussehen. Hochstufen ist eine Aktion, Runterstufen auch —
   und Runterstufen kostet Glück, weil man sich an Dinge gewöhnt. Das ist der wichtigste
   Punkt der Phase: eine Ausgabe, die nie aufhört.
3. **Drei bis vier weitere wiederkehrende Senken**, jede mit eigener Wirkung:
   - Spenden: kostet Geld, gibt Glück und Ruf, sonst nichts. Bewusst ohne Gegenwert.
   - Reisen: teurer als der bestehende Urlaub, mit Zielen und eigenen Ereignissen.
   - Weiterbildung für richtig viel Geld: schaltet Berufe aus Phase 7 frei.
   - Sammlerstücke (Kunst): dürfen als einziges Wert halten, sind aber illiquide —
     Verkauf dauert oder geht nur mit Abschlag.

**Akzeptanz:** Ein Lauf über 60 Jahre, der jedes Jahr so viel wie sinnvoll möglich ausgibt,
kommt auf über 3 Mio € Gesamtausgaben. Ein Lauf, der nichts davon nutzt, liegt beim Vermögen
weiterhin dort, wo er heute liegt — die Senken sind Angebot, keine Zwangsabgabe.
Beides über `window.Lebenslinie` messen und die Zahlen nennen.

---

## Phase 7 — Berufswege statt Berufsliste

**Ist-Zustand:** 28 Berufe in einer flachen Liste. Bewerben, Zufallswürfel, dann steigt das
Gehalt per Zufall um 14 % pro Beförderung ohne Obergrenze. Ein Berufswechsel kostet nichts
und bringt nichts — Berufserfahrung existiert nicht.

**Auftrag:**

1. **Branchen mit Stufen.** Jeder Beruf gehört zu einer Branche (IT, Gesundheit, Handwerk,
   Medien, Bildung, Finanzen, Gastronomie, Sport, …). Innerhalb einer Branche gibt es drei bis
   vier Stufen mit eigenen Titeln — nicht „Stufe 3", sondern „Senior", „Teamleitung",
   „Bereichsleitung". Die Spitzenstufe hat eine harte Gehaltsobergrenze.
2. **Berufserfahrung zählt.** Jahre in einer Branche werden gezählt. Wer die Branche wechselt,
   fängt bei der Erfahrung fast von vorn an. Wer bleibt, steigt schneller.
3. **Von 28 auf mindestens 40 Berufe.** Jeder neue Beruf braucht einen Grund: eine Branche,
   die noch dünn ist, eine Anforderung, die es sonst nirgends gibt, oder einen Weg, der über
   ein Hobby oder eine teure Weiterbildung aus Phase 6 führt.
4. **Kündigung und Arbeitslosigkeit** bekommen Gewicht: nach einer Kündigung ist die nächste
   Zusage schwerer, je länger die Lücke ist.

**Akzeptanz:** Ein Lauf, der 40 Jahre in einer Branche bleibt, erreicht die Spitzenstufe.
Ein Lauf, der alle fünf Jahre die Branche wechselt, liegt beim Endgehalt unter der Hälfte.
Und: das höchste erreichbare Jahresgehalt liegt bei höchstens 160.000 € — heute sind es im
Spitzenlauf 190.824 €, weil Beförderungen keinen Deckel haben.

---

## Phase 8 — Politische Laufbahn

**Wichtig vorher:** Das hier gehört **nicht** in `JOBS`. Ein Eintrag „Präsident" mit
`int:95, edu:4` wäre ein Listeneintrag ohne Bedeutung — genau das, was in Ausbau 1 bei den
Hobbys verboten war. Politik ist eine Leiter mit Wahlen, und Wahlen kann man verlieren.

**Zweitens, damit es stimmt:** In Deutschland ist der Bundespräsident weitgehend zeremoniell
und wird nicht vom Volk gewählt, sondern von der Bundesversammlung. Die Spitze der Macht ist
das Kanzleramt. Bau die Leiter deshalb bis **Bundeskanzler** und setze das Amt des
Bundespräsidenten als seltene Ehrung danach obendrauf, erreichbar nur nach einer langen
Laufbahn.

**Auftrag:**

1. `state.politik = { partei, stufe, ruf, mandateSeit, skandale }` als eigenes System.
2. **Leiter:** Parteieintritt → Gemeinderat → Bürgermeister → Landtag → Bundestag → Minister
   → Bundeskanzler → (Ehrung) Bundespräsident. Jede Stufe hat ein Mindestalter und braucht
   eine Amtszeit auf der Stufe darunter.
3. **Wahlen.** Bei jedem Aufstieg wird gewählt. Die Chance kommt aus politischem Ruf,
   Aussehen, Intelligenz, Zahl der Kontakte und einem Wahlkampfbudget, das man selbst
   festlegt. **Verlieren ist der Normalfall** — eine Niederlage kostet Geld und Glück und man
   darf es wieder versuchen.
4. **Fiktive Parteien.** Erfinde drei bis vier Parteien mit erfundenen Namen und einer groben
   Ausrichtung. Keine echten Parteien, keine echten Politikernamen, keine realen Positionen zu
   Streitthemen. Das Spiel ist für Jugendliche und soll niemanden politisch erziehen.
5. **Skandale** als Ereignisse: alte Aussagen, Spendenaffäre, Plagiat in der Abschlussarbeit.
   Ein Skandal kann die Laufbahn beenden. Wer viel Geld hat, kommt leichter davon — und genau
   das soll sich unangenehm anfühlen.
6. Ein Amt zahlt ein Gehalt und kostet Zeiteinheiten, konkurriert also mit allem anderen.

**Akzeptanz:** Über 20 Läufe, die ab 18 konsequent auf Politik spielen, wird höchstens einer
Bundeskanzler. Ein Lauf, der Politik nebenbei betreibt, kommt nie über den Landtag hinaus.
Beides messen und die Zahlen nennen.

---

## Phase 9 — Gesundheit, Alter und Ruhestand

**Ist-Zustand:** Ab 45 sinkt Gesundheit um `rnd(0,2)` pro Jahr, ab 70 um `rnd(0,4)`. Ab 67
gibt es halbes Gehalt. Der Tod kommt über eine Wahrscheinlichkeit ab 70. Zwischen 50 und dem
Ende passiert nichts, was der Spieler entscheiden könnte.

**Auftrag:**

1. **Krankheiten als Zustand**, nicht nur als Ereignis: `state.krankheiten = [...]` mit
   Verlauf. Eine unbehandelte Krankheit wird schlimmer und kostet jedes Jahr Gesundheit.
   Behandlung kostet Geld und Zeit.
2. **Krankenversicherung als Wahl** ab 18: gesetzlich oder privat, unterschiedliche
   Jahresbeiträge und unterschiedliche Behandlungskosten. Wer spart, zahlt später mehr.
3. **Vorsorge muss sich rechnen.** Die bestehende Aktivität „Vorsorge" senkt konkret die
   Wahrscheinlichkeit, dass eine Krankheit spät und teuer entdeckt wird.
4. **Ruhestand mit Inhalt:** eigene Aktivitäten ab 67, mehr Zeiteinheiten, eigene Ereignisse.
   Enkel, Ehrenamt, ein spätes Hobby, ein Umzug.
5. **Testament und Erbe** im Abschlussbildschirm: was am Ende übrig ist, geht an Partner,
   Kontakte oder eine Spende — je nach Entscheidung im letzten Lebensdrittel.

**Akzeptanz:** Zwischen Alter 60 und Tod gibt es im Schnitt mindestens zwei Entscheidungen
pro Jahr (Ereignisse mit Optionen plus verfügbare Aktionen). Ein Lauf, der ab 18 nie zur
Vorsorge geht, stirbt im Median mindestens fünf Jahre früher als einer, der jedes zweite Jahr
geht. Beides messen und die Zahlen nennen.

---

## Regeln für alle Phasen

- Eine Phase pro Durchgang. Am Ende: liefern, messen, warten. Nicht die nächste anfangen.
- **Messen statt behaupten.** Nach jeder Phase ein Simulationslauf über `window.Lebenslinie`
  und die konkrete Zahl nennen. „Sollte jetzt besser sein" zählt nicht.
- Eine Datei bleibt eine Datei. Kein Build-Step, kein npm, kein `localStorage`, keine externen
  Abhängigkeiten, keine Anthropic-API.
- `normalizeSave()` bei jeder Phase mitziehen. Jedes neue State-Feld braucht dort eine Prüfung,
  einen Default und eine Obergrenze — und einen Test mit einem absichtlich kaputten Spielstand.
- Alle Balance-Zahlen als benannte Konstanten oben in der Datei, nicht verstreut im Code.
  Bestehendes Muster: `GELD`, `ZEIT`, `GEIST`, `MARKT`, `IMMO`, `AUTO`, `PARTNER`.
- Beide Spielweisen (`state.modus` `'zeit'` und `'frei'`) müssen weiter funktionieren.
- Dateigröße im Blick: aktuell 174 KB. Über 300 KB wird die Datei auf dem Handy spürbar
  langsam — dann Ereignisse auslagern und nachladen.
- Nach jeder Phase headless prüfen bei 360, 768 und 1440 px: keine JS-Fehler, kein
  horizontales Scrollen. Der Prüf-Lauf muss Besitz, Partner und Möbel einspielen, sonst
  rutschen Überläufe durch.
- Am Ende jeder Phase: was geprüft wurde und wie, was nur geschrieben wurde, und ein Check,
  den ich in zehn Sekunden selbst sehe.

## Nicht in diesem Ausbau

Kinder (eigenes System mit eigener Balance), Mehrspieler, echte Parteien oder Politikernamen,
Krypto- oder Glücksspiel-Mechaniken, und eine Zähmung des freien Modus — der darf unbalanciert
bleiben, das ist sein Zweck.

## Offener Punkt aus Ausbau 1

Ein Lauf von 24 kommt nach 40 Jahren auf 4,01 Mio €. Treiber ist die Gehaltskurve, nicht die
Investition (Korrelation Endgehalt/Vermögen 0,49). Phase 7 setzt mit der Gehaltsobergrenze
genau da an — nach Phase 7 diese Messung wiederholen und prüfen, ob der Ausreißer weg ist.
