# KOReader Home Screen

A launcher-style home screen for KOReader on e-readers. It appears when KOReader starts and every time you close a book, on top of the normal file browser.

## What's on it

- **Clock and date**, battery and Wi-Fi status
- **Weather** for your location: current temperature, conditions, today's high and low (from [Open-Meteo](https://open-meteo.com), free, no account)
- **Panchang:** today's tithi, nakshatra and Rahu Kalam, computed on the device (Telugu or English)
- **Now playing:** works with [koreader-navidrome-player](https://github.com/SirSharanChakradhar/koreader-navidrome-player). It shows what the device is playing, with previous / play-pause / next, or what you're playing on another Navidrome client. It's hidden if that plugin isn't installed.
- **Continue reading:** your last book with its cover and progress, plus a row of recent books
- **App tiles:** Library, Music, Kavita/OPDS, History, Favorites, Frontlight, Night mode, Wi-Fi, Sleep, and exit to the device's own software

## Install

1. Copy `launcher.koplugin` into `koreader/plugins/` (`.adds/koreader/plugins/` on a Kobo) and restart KOReader.
2. Set your weather location: **Tools → Home screen → Weather location** (latitude, longitude and a place name).
3. Optional: under **Tools → Home screen** you can switch the panchang off, change its language, or stop the home screen from opening automatically.

The Telugu panchang needs a Telugu font. Copy `NotoSansTelugu-Regular.ttf` (from [Noto](https://fonts.google.com/noto/specimen/Noto+Sans+Telugu)) into `koreader/fonts/noto/`, or switch the panchang to English.

Settings are stored in `koreader/settings/launcher.lua`.

## Notes

- The panchang uses low-precision Sun and Moon positions (Meeus' main terms) with the Lahiri ayanamsa. Tithi and nakshatra changes land within a few minutes of a full panchang. It shows the tithi and nakshatra in effect now, not at sunrise.
- Rahu Kalam uses the sunrise and sunset from the weather service, so it needs a weather location.
- Taps are hit-tested by the screen itself rather than using KOReader Button widgets, because the screen redraws every minute.

## License

AGPL-3.0, the same license as KOReader.
