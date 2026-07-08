# PHASEN.md — Bauplan PlanetForge v1

**Regel:** Immer nur EINE Phase. Erst wenn ihre Abnahme-Checkliste komplett grün ist,
kommt die nächste. Jede Phase muss am Ende ein spielbares Spiel hinterlassen.

Wie du eine Phase startest: In Claude Code schreibst du sinngemäß
> „Arbeite Phase X aus PHASEN.md ab. Halte dich an CLAUDE.md. Nichts außerhalb des
> Phasenauftrags. Am Ende: Studio-Test-Anleitung + STATUS.md aktualisieren.“

---

## PHASE 0 — Struktur & Rojo-Fundament
**Warum zuerst:** Ohne saubere Ordnerstruktur + `default.project.json` synct nichts nach
Studio. Das ist der reale Blocker, an dem du zuletzt hängengeblieben bist.

Auftrag:
- Bestehende Scripts in die Struktur aus CLAUDE.md überführen (Endungen korrekt setzen).
- `default.project.json` erzeugen/prüfen: partielles Mapping, nur `src/` → Services.
  Map, Parts und in Studio gebaute UI bleiben in der Place-Datei und werden NICHT von
  Rojo verwaltet (sonst löscht ein Sync deine Welt).
- `STATUS.md` und diese `PHASEN.md` im Projekt-Root anlegen, falls nicht vorhanden.
- Ein Smoke-Test-Print im Server-Init und im Client-Init, damit man beim Connect sofort
  sieht, dass beide Seiten laufen.

Abnahme:
- [ ] `rojo serve` startet fehlerfrei, Studio verbindet, beide Prints erscheinen im Output.
- [ ] Kein Script liegt am falschen Ort (kein Server-Code als LocalScript o. Ä.).
- [ ] Keine Rot-Fehler im Studio-Output beim Play-Test.

---

## PHASE 1 — Datenlayer (das Fundament unter allem)
**Warum vor dem Gameplay:** Gameplay ohne sicheres Speichern produziert Frust-Reviews
(„mein Fortschritt ist weg“) und offene Dupe-Lücken. Erst der Tresor, dann der Inhalt.

Auftrag:
- Profil-Schema als Single Source of Truth (Default-Tabelle + `schemaVersion`).
  Felder mindestens: Energie, freigeschaltete Biome + Level, Upgrade-Level
  (Sammelradius, Rucksackgröße), Rebirth-Count, Inventar (Loot-Items mit Anzahl),
  ausgerüstete Items, PurchaseId-Log, letzter Daily-Claim.
- DataService: Laden bei Join, Session-Lock gegen Doppel-Sessions, Autosave-Intervall,
  Speichern bei Leave + `game:BindToClose`. Alle Zugriffe in `pcall` mit Retry.
- Fehlerfall sauber: Wenn Laden nach Retries scheitert → Spieler mit Hinweis kicken,
  NICHT mit leerem Profil weiterlaufen lassen (sonst Überschreiben echter Daten).

Abnahme:
- [ ] Wert ändern (per temporärem Test-Command) → Rejoin → Wert ist noch da.
- [ ] Zwei Studio-Test-Clients gleichzeitig überschreiben sich nicht.
- [ ] Studio-Stop schreibt final (BindToClose greift).

---

## PHASE 2 — Core Loop: Sammeln & Verkaufen
**Warum das Herzstück:** Das ist das Spiel. Wenn diese Schleife sich nicht gut anfühlt,
retten weder Shop noch Cosmetics irgendetwas.

Auftrag:
- Pro Spieler eine Insel-Instanz mit festem Spawn; fremde Inseln in der Ferne sichtbar.
- Sammel-Objekte spawnen (Spawn-Rate + Max-Anzahl je Biom in Config). Einsammeln bei
  Nähe/Berührung, **serverseitig distanzvalidiert** — Client zeigt nur Effekte.
- Sammelradius („Magnet“) als upgradebarer Profilwert.
- Inventar füllt sich bis zur Rucksack-Obergrenze (upgradebar). Verkaufszone auf der
  Insel wandelt Gesammeltes in Energie. Live-HUD: Energie, Rucksack-Füllstand.
- Ein erstes Upgrade kaufbar (z. B. Sammelradius), Kosten aus Config.

Abnahme:
- [ ] Laufen → sammeln → Rucksack füllt sich → verkaufen → Energie steigt → Upgrade kaufen.
- [ ] Manipulierter Client (Einsammeln aus der Ferne erzwingen) wird vom Server abgelehnt.
- [ ] Alle Beträge/Preise stammen aus Config, keine im Code verstreut.

---

## PHASE 3 — Progression & Rebirth (der Langzeit-Motor)
Auftrag:
- Multiplikator-Formel zentral in `ProgressionConfig`:
  `Gesamt = Basis × (1 + Biome-Bonus) × (1 + Upgrade-Bonus) × Pet-Bonus × Rebirth-Mult`.
  Mehr Biome/Biom-Level ⇒ spürbar mehr Ertrag, live im HUD.
- Upgrade-Kosten exponentiell (Faktor ~1.15–1.25/Stufe), damit es nicht flach wird.
- Biome als sichtbare Zonen: neues Biom kaufen = vernebelte Zone der Insel wird freigelegt.
- Rebirth ab Schwelle: Biome/Währung reset, dafür permanenter Multiplikator (+X% pro
  Rebirth, stapelnd) + exklusive Rebirth-Deko. Bestätigungsdialog mit Vorher/Nachher.

Abnahme:
- [ ] Ertrag/Sekunde steigt nachvollziehbar mit jedem freigeschalteten Biom.
- [ ] Rebirth resettet korrekt und der Multiplikator bleibt nach Rejoin erhalten.
- [ ] Kein Zustand, in dem der Spieler sich „festkauft“ und nicht mehr weiterkommt.

---

## PHASE 4 — Onboarding (entscheidet über Day-1-Retention)
Auftrag:
- Geführter Erst-Spieler-Flow: „Lauf zum Gras → sammle 5 → verkaufe in der Zone →
  kauf dein erstes Upgrade.“ Highlight-Pfeil/Marker führt zum jeweils nächsten Schritt.
- Fortschritt serverseitig speichern (Tutorial nur einmal, kein Nerven bei Rejoin).
- Abschlussbelohnung als kleiner Energie-Boost.

Abnahme:
- [ ] Jemand, der das Spiel nie gesehen hat, kommt ohne Erklärung durch den Loop.
- [ ] Nach Abschluss + Rejoin startet das Tutorial nicht erneut.

---

## PHASE 5 — Monetarisierung (Ende-zu-Ende)
Auftrag:
- `ProcessReceipt` idempotent fertigstellen (PurchaseId-Log, erst gutschreiben+speichern,
  dann `PurchaseGranted`). Gamepass-Check beim Join.
- Produkte: Währungspakete (klein/mittel/groß), Instant-Rebirth.
  Gamepässe: 2× Multiplikator, +Pet-Slots, VIP (Trail + Chat-Tag + Tagesbonus).
- IDs bleiben in `MonetizationConfig` (aktuell 0). Studio-Testmodus wie in CLAUDE.md,
  live doppelt abgesichert.
- Shop-UI (Insel-Bereich + Button). Kaufanreize kontextuell und dezent (Rucksack voll →
  einmaliger Hinweis, max. 1×/Session).
- **Dein manueller Schritt:** Spiel publishen und im Creator Dashboard die Produkte/Pässe
  anlegen, echte IDs in `MonetizationConfig` eintragen. Ohne das bleibt der Shop „Bald…“.

Abnahme:
- [ ] Kauf im Studio-Testmodus schreibt genau einmal gut (kein Doppel bei Retry).
- [ ] Gamepass-Effekt (z. B. 2× Mult) greift ab Join und übersteht Rejoin.

---

## PHASE 6 — Game Feel & Mobile-Feinschliff (nur wenn 0–5 stehen)
Auftrag:
- Sammeln: Objekt tweent zum Spieler, Pop-Sound, HUD-Zahl steigt sichtbar, Partikel-Burst.
- Verkaufen: Münz-Regen + aufsteigender Zähler. Biom-Freischaltung: Kamera-Schwenk,
  Nebel löst sich, Fanfare. Loot-Roll: ~1,5 s Spannung + Rarity-Reveal.
- Lighting: Atmosphere, dezentes Bloom. Sounds zentral in Config regelbar.
- Touch-Steuerung final prüfen: Ziele groß genug, HUD nicht überladen, stabile FPS
  auf schwachem Gerät (unnötige Effekte auf Mobile reduzierbar).

Abnahme:
- [ ] Jede Kern-Interaktion hat sichtbares + hörbares Feedback.
- [ ] Auf dem Handy flüssig spielbar, nichts verdeckt wichtige Buttons.

---

## Danach — erst validieren, dann erweitern
Bevor irgendetwas von der „NICHT in v1“-Liste (Trading, Clans, Battle Pass, Events…)
gebaut wird: v1 mit echten Spielern testen. Retention-Zahlen und Feedback entscheiden,
was als Nächstes kommt — nicht das Bauchgefühl im Editor. Ideen, die dir währenddessen
kommen, wandern in eine IDEEN.md, nicht in den laufenden Build.
