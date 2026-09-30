# CLAUDE.md – Arbeitsanweisung für KickCall

Du baust das WoW-Addon **KickCall** (Retail 12.1.0, Interface `120100`). Die fachliche Beschreibung steht in `SPEC.md`. Lies sie vollständig, bevor du Code schreibst.

## Rollen

- **Dominique:** testet im Spiel, mergt Pull Requests, erstellt Releases (Tags).
- **Koordinator** (Claude in Cowork): prüft Code, Builds und Debug-Logs, schreibt Folgeaufgaben.
- **Du:** setzt um, ein Pull Request pro Meilenstein. **Keine Tags pushen.**

## Referenzprojekte

Vom selben Autor, fertig und im Spiel getestet. Übernimm die bewährten Lösungen:

- https://github.com/Okoith/wow-VoidAlert (am nächsten dran: Sounds.lua mit allen Soundquellen, Options.lua, Debug.lua, Locales, Chat-Option, keine Profile-Seite)
- https://github.com/Okoith/wow-DotRange und https://github.com/Okoith/wow-ownDPS (`.pkgmeta`, Workflow)

`docs/reference/InterruptTest.lua` ist das Testaddon, mit dem die Erkennung ermittelt wurde (SPEC Abschnitt 2).

## Harte Regeln

1. Auslöser sind nur die Ereignisse aus SPEC 3. Keine Filter über geheime Werte (Spell-ID, Name, `notInterruptible`, Abklingzeit).
2. Werte, die geheim sein können, vor jedem Vergleich, jeder Verkettung und jedem Wahrheitstest mit `issecretvalue` prüfen. Auch `if value then` ist ein Wahrheitstest.
3. Alle Aufrufe von Spiel-APIs und `PlaySoundFile`/`PlaySound` in `pcall`.
4. Keine geheimen Werte in SavedVariables.
5. Nichts raten: Unklare APIs defensiv absichern und im Debugmodus loggen.
6. „Wichtige Zauber“ nicht einbauen (SPEC 2, offen).

## Meilensteine

1. **Kern und Menü:** alles aus SPEC 3 bis 7, inkl. Menü, Testbuttons, Debug, Locales, Icon, `.pkgmeta`, Release-Workflow, LICENSE (MIT, Copyright Dominique), README, CHANGELOG. Version `1.0.0-alpha.1`.
2. **Feedback:** Korrekturen nach dem Test, danach Release-Kandidat `1.0.0-beta.1`.

Nach jedem Meilenstein: Pull Request mit kurzer Testanleitung für Dominique.
