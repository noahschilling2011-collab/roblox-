# GHOSTNET — Projektgedächtnis (gilt nur für `ghostnet/`)

> Dieses Verzeichnis enthält ein **eigenständiges zweites Spiel**, unabhängig von
> PlanetForge im Repo-Wurzelverzeichnis. Wo die Wurzel-`CLAUDE.md` etwas anderes
> sagt (helles Kinder-Design, PlanetForge-Phasenplan, `src/`-Layout), gilt für
> alles unterhalb von `ghostnet/` **diese** Datei.

## Was das Spiel ist
Roblox-Hacking-Spiel in der offenen Stadt Vantorra, bei hellem Tag. Man geht an
ein Objekt heran (Kamera, Tür, Geldautomat), löst ein Terminal-Rätsel, kassiert Crypto — das ist
aber erstmal **heiß** (`Unsold`). Jeder Hack treibt den **Trace** hoch. Bei 100
ist alles Unverkaufte weg. Beim **Hehler** wird Unverkauftes gegen Gebühr zu
sicherem Guthaben (`Banked`) und senkt den Trace. Von der Bank kauft man
**Rig-Upgrades**, die schwerere Ziele öffnen. Die Frage jeder Runde ist:
*noch ein Ziel mitnehmen oder jetzt abliefern?*

Die zweite Frage ist *wohin*: Ziele auf offener Straße (Attribut `Exposed`)
zahlen mehr und kosten mehr Trace als gedeckte. Das ist der Nachfolger des
früheren Nachtbonus, seit die Stadt dauerhaft hell ist.

## Architektur-Regeln — nicht verhandelbar
1. **Server-Autorität ist absolut.** Der Client schickt nur "ich habe X
   angeklickt". Nie ein Ergebnis, nie eine Zeit, nie einen Betrag.
2. **Jeder Remote-Handler ruft als allererstes `RateLimiter.Check(player, key)`.**
   Neue Remote → neuer Eintrag in `Config.RateLimits`.
3. **Jede tunbare Zahl steht in `Config.luau`.** Keine Magic Numbers in Modulen
   oder UI.
4. **Crypto und Rig-Werte ändern sich nur über `EconomyService`.** Nirgends sonst.
5. **Nur `SaveService` spricht mit einem DataStore.** Nirgends sonst.
6. **Ein Hack-Ziel ist nur ein BasePart mit Tag `GhostNetHackable` + Attributen.**
   Ein Hehler ist nur ein BasePart mit Tag `GhostNetFence`. Neue Objekte
   brauchen keinen Code.
7. **Minispiele halten die Schnittstelle ein:**
   `Generate(difficulty, rng) -> publicState, serverState`,
   `Input(serverState, payload) -> InputResult`, `Label() -> string`.
   `publicState` enthält **nie** die Lösung.
8. **`--!strict` bleibt überall an.**
9. **Eine Kulissenänderung darf nie stillschweigend eine Mechanik mitnehmen.**
   Als der Tag-/Nachtzyklus abgeschaltet wurde, ist der Nachtbonus nicht
   verschwunden, sondern an den Ort gewandert (`Config.Cover`). Wer etwas
   Optisches abschaltet, prüft zuerst, welche Regel daran hing.
10. **Zeit:** Alles, was einen Serverwechsel überleben muss, benutzt `os.time()`.
   `os.clock()` nur für serverinterne Kurzzeit-Timer (`DownUntil`, Rate-Limits,
   Bust-Sperre).
11. `task.wait` / `task.spawn` / `task.delay` — nie `wait()` / `spawn()` / `delay()`.

## Arbeitsweise
- Eine Phase aus `PHASEN.md` komplett abarbeiten, dann erst die nächste.
- Gelieferte Dateien immer vollständig, mit Zielpfad im Kopfkommentar.
- Nach jeder Änderung: `cd ghostnet/tests && node testlauf.mjs` muss grün sein.
- Am Ende jeder Session `STATUS.md` aktualisieren.
- Keine Asset-IDs, Gamepass-IDs oder Produkt-IDs erfinden — immer `0` bzw. `""`
  mit Kommentar. Noah trägt sie im Creator Dashboard ein.
- `Config.Version` am Ende jeder Phase hochzählen.

## Look
**Zwei Paletten, und die werden nicht vermischt:**

- **Stadt** = `Config.Palette`. Hell, echte Baumaterialien, dauerhafter Tag.
  In `src/server/World/` steht **kein einziger** eigener Farbwert — der
  Testlauf lehnt dort jedes `Color3.fromRGB` ab.
- **Fake-OS** = `Config.Theme` über `UITheme`. Bleibt fast schwarz mit
  Cyan/Magenta/Amber, `Enum.Font.Code`, Scanlines. **Nicht aufhellen** — der
  Kontrast zwischen heller Stadt und schwarzem Terminal ist der Look.

UI-Texte deutsch, kurz, in Großbuchstaben im Terminal-Stil. Muss auf dem Handy
bedienbar sein (Touch-Ziele groß genug).

## Werkzeuge
Claude Code, Rojo, Roblox Studio, VS Code, Node (nur für `tests/` und
`tools/build-rbxlx.mjs`). Nichts anderes installieren oder empfehlen.
