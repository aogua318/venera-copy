# Venera Mod

<p>
  <a href="README_ZH.md">简体中文</a> |
  <a href="README_EN.md"><strong>English</strong></a>
</p>

> This project is a fork of [venera-app/venera](https://github.com/venera-app/venera) (GPL-3.0). The original project is a comic reader that supports reading local and network comics, and has been archived by its author. This repository continues development on top of it, adding auto scrolling, gamepad support, bookshelf management and more.

[![License](https://img.shields.io/github/license/venera-app/venera)](https://github.com/venera-app/venera/blob/master/LICENSE)

## Changes on top of the original

### Reading Experience

- **Constant-speed smooth auto scroll for webtoon mode**: in continuous reading mode, auto play has been upgraded from timed full-screen page turning to smooth scrolling at a constant speed (per-frame compensation with real elapsed time, unaffected by frame drops)
  - Adjustable speed: configured as "milliseconds per screen" (1000–60000 ms)
  - Auto pause on touch, with an optional "resume after touch" setting
  - Configurable end-of-chapter behavior: stop and wait / continue with the next chapter (when the last chapter finishes, it can continue with the next comic)
  - Auto play mode is switchable in settings: smooth scroll / original timed page turning
- **Set as cover**: one tap in the reader to set the current page as the cover of a local comic
- **Last page detection**: in continuous mode the second-to-last screen counts as the end of a chapter (the last page often cannot be displayed fully due to its height)

### Hardware Device Support

- **Gamepad / keyboard / media key control** (Android): Bluetooth or USB gamepads, keyboards and wired headset buttons can all control reading
  - Mappable actions: next page, previous page, toggle auto play, next chapter, previous chapter
  - Custom key mapping: Settings → Reading → Hardware Key Mapping. Tap an action and press any key to bind it; bindings can be removed or reset to defaults
  - Sensible default bindings that work out of the box (A/B/shoulder buttons for page turns, Y and headset play button for auto scroll, DPad for direction paging)
  - Gamepad keys are intercepted via a platform channel and do not interfere with system focus navigation; original features such as volume key page turning are unaffected

### Bookshelf Management

- **Standalone bookshelf**: a bookshelf page has been added to the navigation pane, reusing the local comic import flow from the home page; imported comics are added to the shelf automatically
- **Multiple sort modes**: added time / name / last read time, with ascending and descending order; sort settings are persisted
- **Three view modes**: list (the original card view) / grid (uniform size + file name) / waterfall (by the real aspect ratio of each cover)
- **Multi-select operations**: long press to enter selection mode, with select all / invert selection / select none, and removal from the shelf
- **Comic merging**: select multiple local comics, drag to adjust the order and merge them into one continuous comic — each source comic becomes a chapter of the merged one, files are moved instead of copied (no double disk usage), and the source comics are cleaned up automatically after merging
- **Continuous reading**: while reading a comic from the bookshelf, pressing the "first page" button again on the first page switches to the previous comic, and the "last page" button on the last page switches to the next one (following the current shelf sort, restoring reading progress automatically); all chapter-switching entries (gamepad chapter keys, the floating button, volume keys, auto scroll at chapter end) fall back to comic switching when there is no previous/next chapter

### Localization

- All the new features above are available in Simplified Chinese / Traditional Chinese / English

## Differences from the Official Build

- The package name is `com.github.wgh136.venera.mod`, so it can be installed alongside the official app
- When no release signing key is configured, a debug keystore is used automatically (friendly for local builds; keep the same key for upgrade installs)
- Data is fully isolated from the official app (history, favorites and comic source settings are not shared); use the original app's data sync feature to migrate

## Build from Source

1. Clone this repository
2. Install Flutter (≥3.41, see [flutter.dev](https://flutter.dev/docs/get-started/install)) and Rust (see [rustup.rs](https://rustup.rs/))
3. Building for Android requires the Android SDK (including the NDK)
4. Build: `flutter build apk --release` (or target a single architecture with `--target-platform android-arm64`)

> For detailed feature design and development notes, see [docs/dev-plan-auto-scroll-gamepad.md](docs/dev-plan-auto-scroll-gamepad.md). For the full implementation traceability (motivation / implementation / impact of every change), see [docs/implementation-notes_en.md](docs/implementation-notes_en.md) ([Chinese version](docs/implementation-notes_zh.md)).

## License

This project inherits the [GPL-3.0](LICENSE) license of the original project.

## Thanks

- [venera-app/venera](https://github.com/venera-app/venera) — the base of this project
- [EhTagTranslation](https://github.com/EhTagTranslation/Database) — Chinese translation of comic tags
