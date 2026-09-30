# Changelog

## 1.0.0-alpha.1

First test build.

- **Cast sound:** plays a sound when an attackable enemy starts casting, channeling or empowering a spell. Units: target and focus (on by default), nameplates (off by default). The sound plays for every enemy cast; whether a spell can be interrupted is hidden from addons.
- **Success sound:** plays when an enemy cast is interrupted within 1 second after your own interrupt. Option *Also when others interrupt* (off by default).
- **Interrupt spells of all classes** are checked on login, specialization change and spell changes; the interrupt found is shown in the settings and with `/kickalert status`.
- **Sounds:** bundled English and German voice alerts (default follows the client language; while the files are not yet included, *Raid Warning* and *Ready Check* are used), up to five own sounds in `Interface\AddOns\KickAlert_Sounds\`, all LibSharedMedia sounds and a few WoW sounds.
- **Settings** under *Settings > AddOns > KickAlert* or with `/kickalert`: sounds with *Test* buttons, units, sound channel, minimum gap between two cast sounds (0.2 to 2.0 s, default 0.5), only in combat, only in instances, chat messages, custom sounds note, debug mode. One shared profile for the whole account.
- **Chat commands:** `/kickalert`, `/kickalert test`, `/kickalert status`, `/kickalert help`, `/kickalert debug`.
- **Debug mode** (off by default) that writes a log to the SavedVariables.
- **Languages:** English and German.
