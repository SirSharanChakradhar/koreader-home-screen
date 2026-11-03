# KOReader Home Screen

A launcher-style home screen for KOReader on e-readers. It replaces the file browser as KOReader's home: it appears when KOReader starts, every time you close a book, and when you tap the home icon in the file browser.

## What's on it

- **Clock and date**, battery and Wi-Fi status
- **Weather** for your location: current temperature, conditions, today's high and low (from [Open-Meteo](https://open-meteo.com), free, no account)
- **Panchang:** today's tithi, nakshatra and Rahu Kalam, computed on the device (Telugu or English)
- **Now playing:** works with [koreader-navidrome-player](https://github.com/SirSharanChakradhar/koreader-navidrome-player). It shows what the device is playing, with previous / play-pause / next, or what you're playing on another Navidrome client. It's hidden if that plugin isn't installed.
- **Continue reading:** your last book with its cover and progress, plus a row of recent books
- **Dock:** Library, Music, Kavita, Settings and Apps (configurable with the `dock` setting)
- **Apps pages:** swipe left (or tap Apps) for every KOReader feature as an app, grouped into Everyday (the mini apps below), Reading (Library, Search, History, Collections, Favorites, Statistics, Today, Vocabulary, Dictionary, Wikipedia), Online (OPDS/Kavita, Calibre, Cloud, News, Wallabag, Progress sync, Music), Tools (Text editor, Terminal, Read timer, Battery, System, Screenshot, Network, SSH, Calibre wireless, Profiles, Export highlights, Book shortcuts, Gestures, QR code, Sun times, Warmth, Auto dim, HTTP inspector) and Device (Light, Night, Wi-Fi, Settings, Home settings, Sleep, Restart, exit). Plugins that only have a menu open it as a full-screen list. Apps for plugins you don't have are hidden. Swipe right to go back.
- **Reading today:** time and pages read today, from KOReader's reading statistics
- **Built-in mini apps** (in the Everyday group):
  - **Calendar:** month view with each day's tithi and full/new moon marks; swipe for other months
  - **Panchang:** tithi and nakshatra with end times, sunrise/sunset, Rahu Kalam, Yamaganda, Gulika, Brahma muhurta, Abhijit
  - **Weather:** current conditions and a 7-day forecast (rain chance, sunrise/sunset, UV)
  - **World clock:** configurable with the `world_zones` setting
  - **Calculator**
  - **Stopwatch & timer** (keeps the device awake while running)
  - **Notes:** read and add notes on a [Memos](https://usememos.com) server (asks for the address and an access token the first time)
- The Apps section spans several pages; swipe left/right

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
