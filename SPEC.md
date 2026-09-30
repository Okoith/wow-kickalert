# KickAlert – Spezifikation v1.0

Stand: 30.09.2026 · WoW Retail 12.1.0 (Interface `120100`)

## 1. Ziel

KickAlert spielt einen Sound, sobald ein Gegner einen Zauber beginnt, damit man rechtzeitig unterbrechen kann. Optional folgt ein zweiter Sound, wenn eine Unterbrechung erfolgreich war. Für alle Klassen. Nur Sound, keine Anzeige auf dem Bildschirm.

## 2. Getestete Fakten (Testaddon `docs/reference/InterruptTest.lua`, Paladin, Dungeon normal, 3 Sitzungen)

| Was | Ergebnis | Folge |
|---|---|---|
| `UNIT_SPELLCAST_START` / `UNIT_SPELLCAST_CHANNEL_START` für `target`, `focus`, `nameplateN` | kommen zuverlässig, auch für Gegner, die nicht im Ziel sind. Der Unit-Token ist lesbar. | **Auslöser** |
| Spell-ID, Name, `castGUID` im Ereignis | geheim | nicht verwenden |
| `UnitCastingInfo` / `UnitChannelInfo`: Name, Spell-ID, `notInterruptible`, Start/Ende | alles geheim | Filter „unterbrechbar“ **nicht möglich** |
| `UNIT_SPELLCAST_INTERRUPTIBLE` / `NOT_INTERRUPTIBLE` | kamen nie | nicht verwenden |
| `UnitCanAttack("player", unit)` | lesbar (`true` bei Gegnern) | Filter „nur Gegner“ |
| `UnitName` des Gegners | geheim | nicht verwenden |
| `UNIT_SPELLCAST_INTERRUPTED` für Gegner | kommt, Unit-Token lesbar | Auslöser für „Erfolg“ |
| `UNIT_SPELLCAST_SUCCEEDED` für `player` | Spell-ID lesbar (eigene Unterbrechung erkannt) | eigene Unterbrechung erkennen |
| Abklingzeit der eigenen Unterbrechung (`C_Spell.GetSpellCooldown`) | im Kampf geheim | „nur wenn Kick bereit“ **nicht möglich** |
| `C_Spell.IsSpellUsable` der Unterbrechung | `true` auch während der Abklingzeit | nicht verwenden |
| `frame:SetShown(secret)` | Fehler: nur bei untainted Ausführung erlaubt | – |
| Derselbe Zauber | kommt gleichzeitig als `target` und `nameplateN` (gleicher Zeitstempel) | Doppelsperre nötig |

Blizzard bietet mit „Audio Assist“ eine eigene Ansage für unterbrechbare Zauber, laut Spielern nur für das Ziel und als Text-to-Speech. KickAlert ist die Alternative mit eigenen Sounds, für Fokus und Namensplaketten.

**Offen (nicht Teil von v1.0):** „Wichtige Zauber“ getrennt erkennen. Wird mit InterruptTest v0.3.0 noch geprüft. Nicht einbauen, bis der Koordinator das freigibt.

## 3. Erkennung

### 3.1 Zauberbeginn
- Ereignisse: `UNIT_SPELLCAST_START`, `UNIT_SPELLCAST_CHANNEL_START`, `UNIT_SPELLCAST_EMPOWER_START`
- Unit prüfen: `issecretvalue(unit)` → ignorieren; sonst nur `target`, `focus`, `nameplate%d+`, je nach Einstellung
- Nur Gegner: `UnitCanAttack("player", unit)` in `pcall`, nur wenn lesbar und `true`
- Doppelsperre: nach einem Sound werden weitere Zauberbeginne für die eingestellte Dauer ignoriert (Standard 0,5 s)
- Keine Unterscheidung nach unterbrechbar/nicht unterbrechbar (geheim). In README und Menü klar sagen: „Der Sound kommt bei jedem gegnerischen Zauber.“

### 3.2 Erfolg
- Eigene Unterbrechung merken: `UNIT_SPELLCAST_SUCCEEDED` mit `unit == "player"` und Spell-ID aus der Unterbrechungsliste (Spell-ID vorher mit `issecretvalue` prüfen). Zeitpunkt speichern.
- `UNIT_SPELLCAST_INTERRUPTED` für eine Einheit aus 3.1 (Gegner), innerhalb von 1,0 s nach der eigenen Unterbrechung → Erfolg-Sound
- Option „Erfolg auch bei Unterbrechung durch andere“ (Standard aus): dann jedes `INTERRUPTED` eines Gegners
- Eigene Sperre 0,5 s, damit `target` und `nameplateN` nicht doppelt klingen
- Unsicher: Ob `INTERRUPTED` auch durch Betäubung oder Bewegung ausgelöst wird, ist nicht getestet. Im Debug-Log jeden Fall mit Abstand zur eigenen Unterbrechung loggen.

### 3.3 Unterbrechungszauber (alle Klassen)
Liste aus dem Testaddon übernehmen und zur Laufzeit mit `C_SpellBook.IsSpellKnown` / `IsPlayerSpell` prüfen (bei `PLAYER_LOGIN`, `PLAYER_SPECIALIZATION_CHANGED`, `SPELLS_CHANGED`). Gefundene IDs ins Debug-Log. Im Test bestätigt: Paladin 96231. Die übrigen IDs sind nicht im Spiel geprüft, deshalb defensiv.

## 4. Sounds (wie VoidAlert)

Eine gemeinsame Auswahlliste aus:
1. **Mitgelieferte Sprachansagen** in `sounds/`: `cast_de.ogg`, `cast_en.ogg`, `kick_de.ogg`, `kick_en.ogg`. Dominique liefert die Dateien. Solange eine Datei fehlt, wird sie nicht angeboten (`C_UIFileAsset.IsKnownFile` bzw. Rückgabe von `LSM:Register`).
2. **Eigene Sounds** in `Interface\AddOns\KickAlert_Sounds\sound1.ogg` bis `sound5.ogg`
3. **LibSharedMedia-3.0** (Typ `sound`), die mitgelieferten zusätzlich dort registrieren
4. **WoW-Sounds** über `SOUNDKIT`, nur wenn zur Laufzeit vorhanden

Standard: Sprachansage nach Client-Sprache (`deDE` → `_de`, sonst `_en`). Fehlt sie, `kit:RAID_WARNING` für Zauberbeginn und `kit:READY_CHECK` für Erfolg.

Abspielen mit `PlaySoundFile` / `PlaySound` in `pcall`, Kanal wählbar.

## 5. Einstellungen (AceConfig, Einstellungen → AddOns → KickAlert)

- **Zauberbeginn:** an/aus, Sound, Testen
- **Einheiten:** Ziel (an), Fokus (an), Namensplaketten (aus)
- **Erfolg:** an/aus (an), Sound, Testen, „auch bei Unterbrechung durch andere“ (aus)
- **Allgemein:**
  - Kanal: Master (Standard), SFX, Dialog, Music, Ambience
  - Mindestabstand zwischen zwei Sounds: Slider 0,2 bis 2,0 s, Schritt 0,1, Standard 0,5 (mit `formatter`, auf eine Nachkommastelle runden)
  - Nur im Kampf (Standard aus)
  - Nur in Instanzen (Standard aus, `IsInInstance`)
  - Chat-Meldungen (Standard aus: Login- und Testmeldung. Antworten auf Befehle und Fehlerhinweise immer sichtbar)
- **Eigene Sounds:** Hinweistext mit Pfad `KickAlert_Sounds`, Dateinamen, komplett neu starten nach neuen Dateien
- **Debug:** Debugmodus an/aus, Log leeren
- **Keine Profile-Seite.** AceDB mit einem gemeinsamen Profil für den ganzen Account (`"Default"`), weil das Addon für alle Klassen gleich gilt.
- `/kickalert` öffnet das Menü per `AceConfigDialog:Open`, `/kickalert test` spielt beide Sounds nacheinander, `/kickalert help`
- Sprachen: enUS (Standard), deDE

## 6. Debugmodus

Wie VoidAlert: Ringpuffer in `KickAlertDebugLog`, max. 5000 Einträge, Secret Values nur als `"<SECRET>"`. Inhalt: Version, Build, Klasse, Spec, gefundene Unterbrechung, jeder Zauberbeginn (Event, Unit, lesbar/geheim, Entscheidung, Grund bei Nicht-Auslösen), jede eigene Unterbrechung, jedes `INTERRUPTED` mit Abstand zur eigenen Unterbrechung, jeder Sound mit Quelle und Rückgabe.

## 7. Technik

- Kein Frame auf dem Bildschirm
- Bibliotheken per `.pkgmeta`: LibStub, CallbackHandler-1.0, AceDB-3.0, AceGUI-3.0, AceConfig-3.0, LibSharedMedia-3.0 (kein AceDBOptions)
- TOC: `## Interface: 120100`, `## Version: @project-version@`, `## SavedVariables: KickAlertDB, KickAlertDebugLog`, `## IconTexture: Interface\AddOns\KickAlert\media\icon.png`
- `media/icon.png`: aus `docs/kickalert_logo.png` erzeugen (transparente Ränder abschneiden, quadratisch, 64 × 64 px, PNG mit Alpha)
- `sounds/` und `media/` ins Paket, `docs/` nicht
- Leistung: Namensplaketten erzeugen in großen Packs viele Ereignisse. Früh abbrechen (Unit-Filter vor allen anderen Aufrufen), keine Tabellen pro Ereignis anlegen, wenn Debug aus ist.

## 8. Veröffentlichung

MIT, CHANGELOG und README auf Englisch, Release-Workflow bei Tag `v*`, CurseForge-Projekt-ID folgt (TOC-Zeile vorbereiten, auskommentiert).
