# Venera Mod Implementation Notes (Traceability Document)

> This document records all functional changes and build adaptations in this repository relative to the upstream [venera-app/venera](https://github.com/venera-app/venera) (baseline: upstream master, the "no longer maintained" version), organized by module. Each change documents the **motivation**, **implementation**, and **impact** (user-visible behavior changes / compatibility / risks) for future maintainers.
>
> The feature design process and root-cause analysis of real-device issues are documented separately in [dev-plan-auto-scroll-gamepad.md](dev-plan-auto-scroll-gamepad.md) (organized by iterations 1–4).
>
> Status: all changes implemented, passing `flutter analyze` (0 errors), with major features verified on a real Android device.

---

## 1. Overview of Changes

### New Files

| File | Type | Feature Area |
|---|---|---|
| `lib/pages/reader/auto_scroll.dart` | Dart (part of reader library) | Constant-speed smooth auto scroll engine |
| `lib/utils/hardware_keys.dart` | Dart | Hardware key abstraction: action enum, key identity, platform channel listener, default bindings |
| `lib/foundation/bookshelf.dart` | Dart | Bookshelf data management (persistence, sorting) |
| `lib/pages/bookshelf_page.dart` | Dart | Bookshelf page (views / selection / sorting / import) |
| `lib/pages/bookshelf_merge_page.dart` | Dart | Comic merge page |
| `README_ZH.md` / `README_EN.md` / `README.md` | Docs | Project readme |
| `docs/dev-plan-auto-scroll-gamepad.md` | Docs | Feature development document (iterations 1–4) |
| `docs/implementation-notes_zh.md` / `_en.md` | Docs | This document |

### Modified Files

| File | Change Topic |
|---|---|
| `lib/pages/reader/reader.dart` | Auto scroll state & action dispatch, hardware key dispatch, comic switching, end-of-chapter detection |
| `lib/pages/reader/images.dart` | Continuous mode wired to scroll engine, touch pause, chapter-end comic fallback |
| `lib/pages/reader/scaffold.dart` | Toolbar (play / set cover / first-last page buttons), unified chapter switching |
| `lib/pages/settings/reader.dart` | New settings UI, key mapping page |
| `lib/pages/settings/settings_page.dart` | hardware_keys import |
| `lib/foundation/appdata.dart` | New setting defaults |
| `lib/pages/main_page.dart` | Bookshelf entry in the navigation pane |
| `lib/pages/local_comics_page.dart` | "Add to bookshelf" in multi-select menu |
| `lib/pages/home_page.dart` | Import dialog widget made public (reused by bookshelf) |
| `assets/translation.json` | ~50 new Simplified/Traditional Chinese strings |
| `android/app/build.gradle` | Package name, signing fallback, NDK version |
| `android/app/src/main/AndroidManifest.xml` | App label "Venera Mod" |
| `android/app/src/main/kotlin/.../MainActivity.kt` | Gamepad/media key platform channel |
| `android/build.gradle` | Maven repository fixes |
| `android/settings.gradle` | Kotlin plugin version |
| `android/gradle.properties` | Kotlin incremental compilation flag |
| `android/gradle/wrapper/gradle-wrapper.properties` | Gradle version |
| `lib/network/file_downloader.dart` | Fix type error reported by the newer Dart analyzer |
| `analysis_options.yaml` | Analyzer exclude dirs auto-added by the Flutter tool (not manual) |
| `pubspec.lock` | Dependency re-resolution under Flutter 3.47.2 (not manual) |

---

## 2. Reading Experience

### 2.1 Constant-Speed Smooth Auto Scroll

- **Motivation**: the original auto play for webtoon (continuous) mode was `Timer.periodic` timed full-screen page turning, which feels jumpy. The requirement was smooth scrolling at a constant, user-defined speed.
- **Implementation**:
  - New `AutoScrollEngine` (`auto_scroll.dart`): drives the continuous mode `ScrollPosition` frame by frame via a `Ticker`. Per-frame delta = viewport height / ms-per-screen × real frame time (ms), compensated with real elapsed time so frame drops do not change the speed. Stops and fires the chapter-end callback when the scroll boundary is reached.
  - Speed setting `autoScrollMsPerScreen` (ms per screen, 1000–60000, default 5000), read every frame so changes take effect immediately.
  - Owned by `_ContinuousModeState`; the auto play entry (toolbar play button) in continuous mode toggles the engine, while page-image (gallery) modes keep the original timed page turning.
  - Page number and reading progress: the existing `itemPositionsListener` writes page/history based on scroll position, which stays correct under constant-speed scrolling with no extra handling.
- **Impact**:
  - Only affects continuous reading modes (webtoon / horizontal continuous); gallery modes unchanged.
  - Touching the screen pauses scrolling (user gestures take priority); the optional `autoScrollResumeAfterTouch` setting controls whether scrolling resumes on release (default: no).
  - Zoom, double-tap and long-press gestures coexist with the engine (touch pauses first).
  - Known trade-off: at high speeds network images may not finish loading (loading placeholders are scrolled past); the current strategy is to keep scrolling without waiting.

### 2.2 Auto Play Mode Switch

- **Motivation**: keep the original "timed page turning" habit and let users choose between the two auto play styles.
- **Implementation**: new setting `autoPlayMode` (`smoothScroll` default / `pageTurning`), supporting per-comic settings; `toggleAutoPlay()` dispatches accordingly, and the toolbar button tooltip/icon reflect both the mode and the running state.
- **Impact**: the gamepad "toggle auto play" action follows the same setting; in `pageTurning` mode the end-of-chapter behavior matches the original (stop at the last page).

### 2.3 End-of-Chapter Behavior and Last-Page Detection

- **Motivation**: auto scrolling should behave predictably at chapter end; also fix "cannot reach the chapter end" caused by the last page not being fully displayable in continuous mode.
- **Implementation**:
  - Setting `autoScrollOnChapterEnd`: `stop` (default, halt at chapter end) / `nextChapter` (continue into the next chapter and keep scrolling; when the last chapter finishes, continue with the next comic, see §3.3).
  - Last-page detection `isOnLastPage`: in continuous mode `page >= maxPage - 1` (the last page often cannot be fully displayed due to insufficient height, so scrolling settles on the second-to-last screen); gallery modes keep `page == maxPage`.
- **Impact**: shared by the last-page button comic switch and auto scroll chapter end; no other reader UI changes.

### 2.4 Set as Cover

- **Motivation**: imported local comics often have poor covers; allow setting the current page as the cover while reading.
- **Implementation**: new toolbar button (only shown for `ComicType.local`) → reuses `selectImageToData()` to get the current page image bytes → overwrites `LocalComic.coverFile`; if the cover file does not exist, creates `cover.<ext>` and updates the database cover field via `LocalManager().add`.
- **Impact**: the bookshelf/local list shows the new cover immediately; only available for local comics (network comic covers come from the source site).

---

## 3. Hardware Keys and Key Mapping (Android)

### 3.1 Key Abstraction and Dispatch

- **Motivation**: let gamepads, keyboards and media keys control reading uniformly, with user-defined mappings.
- **Implementation**:
  - `InputAction` enum: `nextPage / prevPage / toggleAutoScroll / nextChapter / prevChapter`.
  - Key identity `HardwareKey`: the Flutter `LogicalKeyboardKey` keyId (`"fl:<keyId>"`) is the unique ID; native gamepad/DPAD/media key codes are mapped into the same ID space via the Android plane rule `(0x002 << 32) | keyCode`.
  - Dispatch chain (two sources, unified into `_ReaderState.handleInputAction`):
    1. **Platform channel** (`EventChannel("venera/keys")`): `MainActivity.dispatchKeyEvent` intercepts and consumes keys classified **primarily by key code** — gamepad (96–110), media (85–127), DPad (19–23) — preventing focus navigation, and forwards them to Dart; keyboard keys are not intercepted and flow through Flutter's own KeyEvents.
    2. **Flutter KeyboardListener**: keyboard keys (including gamepads reporting themselves as keyboards).
  - **Reference-counted shared stream**: the channel subscription is shared by all `HardwareKeyListener` instances (a `StreamController.broadcast`), and the channel is cancelled only when the count reaches zero — this fixes the race where switching comics cancelled the channel while listeners were swapping.
  - **Default binding fallback**: when the user has no custom bindings (`inputKeyMap` empty), `defaultInputKeyMap` applies automatically (A/B/R1/L1 page turns, R2/L2 chapters, Y and media play button for auto scroll, DPad directions for paging) — works out of the box.
  - Debugging: Kotlin `Log.d("VeneraKeys")` and Dart `debugPrint` log the full forwarding/reception/matching chain.
- **Impact**:
  - Inside the reader, gamepad/DPad keys no longer move focus; outside the reader, system behavior is restored.
  - Volume keys are not part of the mapping system (intercepted by the system); the original "turn pages by volume keys" feature stays independent.
  - Back/Menu are never intercepted.
  - Long-press auto-repeat is not supported (one trigger per KeyDown).

### 3.2 Key Mapping UI

- **Implementation**: Settings → Reading → "Hardware Key Mapping" (Android only). A `ListView` lists all actions; tapping one opens a capture dialog that subscribes to both the channel and keyboard events — press any key to bind. One key binds to one action (re-binding moves it); tapping a binding chip removes it; reset to defaults is supported. Mappings are stored in `inputKeyMap` (`"fl:<keyId>" → action name`).
- **Impact**: the mapping page uses a plain `ListView` (the first version mistakenly used a Sliver structure and crashed rendering; it was rebuilt).

### 3.3 Unified Chapter-End → Comic-Switch Fallback

- **Motivation**: every "previous/next chapter" entry should degrade to "previous/next comic" (following the current bookshelf sort and order) when there is no chapter to switch to.
- **Implementation**: `toPrevChapterOrComic() / toNextChapterOrComic()` wrap the logic and are applied to: gamepad/mapping chapter actions, the floating chapter switch button, volume-key chapter crossing, page-turn overflow in gallery modes, and the auto scroll chapter-end policy.
- **Impact**: if the current comic is not in the bookshelf the fallback does nothing (matching the original no-op), so it never triggers accidentally. Comic switching uses root-navigator `pushReplacement`, and the target comic restores its reading progress (history). Auto scroll state does not carry across comics (restart manually).

---

## 4. Bookshelf

### 4.1 Data and Page

- **Motivation**: a dedicated ordered reading list (distinct from favorites) supporting sorting and quick comic switching.
- **Implementation**:
  - `BookshelfManager` (`foundation/bookshelf.dart`): an ordered entry list `{comicId, comicType, addedAt}`, persisted to `App.dataPath/bookshelf.json`; broken data falls back to an empty shelf. `sortedItems()` is the single source of truth for ordering (`bookshelfSortMode`: addedTime default / name / lastRead; `bookshelfSortDesc` for descending), shared by the bookshelf page and the reader's comic switch.
  - Bookshelf page: a new navigation pane entry (after Home); an empty-state import guide; entries resolve to local comics first, then history records (network comics).
  - Import: reuses the home page's local import dialog (`ImportComicsWidget` changed from private to public in home_page); newly imported comics are added to the shelf automatically; "Add to bookshelf" was added to the local page's multi-select menu.
  - Selection mode: long press enters it (the old menu is gone); the app bar shows the count + merge/remove/select all/invert/select none; the back key exits selection first.
  - Views: `bookshelfViewMode` with three options — list (the original `ComicTile` card grid), grid (custom tile: fixed 0.72 aspect cover + file name with ellipsis), waterfall (by each cover's real aspect ratio, dimensions resolved asynchronously and cached); switching applies immediately.
- **Impact**:
  - Bookshelf data is fully independent from the official app; entries whose comics were deleted are pruned on entry (`prune()`).
  - Manual drag-to-reorder was **removed** in iteration 4 per requirements (only automatic sort modes + descending remain).
  - Grid/waterfall use custom tiles so selection borders align naturally; entries rebuild with `ValueKey("view:id:selected")` so selection marks follow when switching views.

### 4.2 Comic Merging

- **Motivation**: merge several single-chapter local comics into one continuous comic (a common need for multi-archive imports).
- **Implementation** (`bookshelf_merge_page.dart`): select ≥2 local comics → reorder by dragging on the merge page → on confirm:
  1. New directory named `sanitizeFileName(first.directory + "_" + count + "_Merge")`, with a `_1` suffix appended on name clashes;
  2. Each source comic becomes one chapter (multi-chapter comics expand into "source title - chapter title" chapters), chapter directories are organized as `0,1,2…`, and page files are **moved** (rename, falling back to copy across volumes);
  3. The cover reuses the first comic's cover; a `LocalComic` is registered (`ComicChapters` in order), then all source comics are deleted via `deleteComic` (pages were already moved, so only leftover directories are cleaned);
  4. The shelf removes the sources and adds the merged comic.
- **Impact**: **source comics are deleted** (irreversible; noted in the UI text); local comics only; file moves require the same storage volume (copy fallback handles cross-volume cases).

### 4.3 Reader Comic-Switch Entry Points

- Toolbar "first page / last page" buttons: pressing "first page" again while already on the very first page of the comic → previous comic; pressing "last page" again on the very last page (continuous mode uses §2.3 detection) → next comic. Comics not in the shelf keep the original behavior (jump to the chapter's first/last page).
- Chapter-end fallbacks for all chapter-switching entries: see §3.3.

---

## 5. Localization

- `assets/translation.json` gained ~50 `zh_CN` / `zh_TW` entries covering all new UI strings (auto scroll, key mapping, bookshelf, merging, comic-switch messages); English is the source language.

---

## 6. Build and Toolchain Adaptations

> Context: upstream stopped at Flutter 3.41 / Gradle 8.13 / AGP 8.12.3 / Kotlin 2.1.0; the local Flutter 3.47.2 toolchain enforces higher versions. Each item was upgraded in turn with the cascading issues fixed.

| Change | File | Purpose | Impact |
|---|---|---|---|
| Gradle 8.13 → 8.14 | `gradle-wrapper.properties` | Flutter minimum is 8.14 | Tencent mirror kept; Flutter warns 9.1 is coming (warning only) |
| Kotlin 2.1.0 → 2.2.20 | `settings.gradle` | Flutter minimum is 2.2.20 | Compatible with AGP 8.12.3 (an "untested combination" warning remains) |
| NDK 28.0 → 28.2.13676358 | `android/app/build.gradle` | Highest NDK required by plugins, removing the version mismatch warning | Downloaded automatically on first build |
| Removed jcenter mirror + added `mavenCentral()` | `android/build.gradle` | The Aliyun jcenter mirror lacks packages (e.g. kotlinx-coroutines); when a POM resolves on the mirror but the artifact is missing, Gradle does not fall back — so `mavenCentral()` must precede the mirrors | Slightly slower downloads in China, correctness first |
| HTTP → HTTPS (aliyun public) | `android/build.gradle` | Newer Gradle rejects undeclared insecure protocols | — |
| `kotlin.incremental=false` | `gradle.properties` | Plugin sources live on the C drive (Pub cache) while the build dir is on E; cross-drive paths crash Kotlin incremental caches ("different roots") | Full recompiles, slightly slower builds |
| Signing fallback | `android/app/build.gradle` | The original build.gradle required `key.properties` unconditionally and crashed at configuration time without it. Now a missing file falls back to `~/.android/debug.keystore` (androiddebugkey/android) | Local builds need no signing setup; upgrade installs require the same keystore; provide `key.properties` for real releases |
| `.mod` package suffix | `android/app/build.gradle` | Coexistence with the official app | Data fully isolated from the official app |
| App label "Venera Mod" | `AndroidManifest.xml` | Distinguish launcher icons | — |
| `_fetchBlock` callback return type | `lib/network/file_downloader.dart` | The newer Dart analyzer errored: `then<bool>` inference required onError to return a bool. Changed to a block body so onValue returns void | Behavior unchanged |
| Analyzer exclude dirs | `analysis_options.yaml` | Auto-added by the Flutter tool (build/android dirs), not manual | — |
| `pubspec.lock` | — | Re-resolved by `pub get` under Flutter 3.47.2 | Not manual |

---

## 7. New Settings Reference

| Setting | Default | Values | Description |
|---|---|---|---|
| `autoScrollMsPerScreen` | 5000 | 1000–60000 (step 500) | Smooth scroll ms per screen (continuous mode) |
| `autoScrollOnChapterEnd` | `stop` | stop / nextChapter | Behavior at chapter end while scrolling |
| `autoScrollResumeAfterTouch` | false | bool | Resume scrolling after touch release |
| `autoPlayMode` | `smoothScroll` | smoothScroll / pageTurning | Auto play style (continuous mode) |
| `inputKeyMap` | `{}` (empty falls back to built-in defaults) | `"fl:<keyId>" → action` | Hardware key mapping |
| `bookshelfSortMode` | `addedTime` | addedTime / name / lastRead | Bookshelf sorting |
| `bookshelfSortDesc` | false | bool | Bookshelf descending order |
| `bookshelfViewMode` | `grid` | list / grid / waterfall | Bookshelf view |

All are global settings; `autoScroll*` and `autoPlayMode` go through the `getReaderSetting` system and support per-comic overrides.

---

## 8. User-Visible Behavior Changes (vs. the original)

1. Continuous-mode "auto play" defaults to smooth scrolling (was timed full-screen page turning; switchable in settings).
2. Reader toolbar: play button icon/label follow the mode; local comics gain a "Set as Cover" button.
3. On Android, gamepad/DPad keys page and toggle auto scroll inside the reader by default; outside the reader nothing is intercepted.
4. The navigation pane gains "Bookshelf".
5. The local comics multi-select menu gains "Add to bookshelf".
6. Bookshelf: long press enters selection mode.
7. For comics on the shelf: the "first/last page" buttons at the chapter start/end switch to the previous/next comic; all chapter-switching entries fall back to comic switching at chapter ends.
8. Auto scroll with the `nextChapter` policy continues into the next comic after the last chapter.
9. Touching the screen pauses smooth scrolling.

---

## 9. Known Limitations and Suggested Follow-ups

1. Volume keys are intercepted by the system and cannot participate in key mapping (the original volume-key page turning is unaffected).
2. At high auto scroll speeds network images may lag behind, showing loading placeholders; a "wait for loading" slow-down policy could be a future iteration.
3. Bookshelf data (bookshelf.json) is not yet included in WebDAV sync.
4. macOS/Linux desktop builds were not verified locally; keyboard mapping on desktop uses the Flutter KeyEvents path and works, but is not guaranteed.
5. Merging supports local comics only; network comics work the same after being downloaded.
6. Gamepads reporting themselves as keyboards (sending letter keys) require manual binding in the mapping page (the capture dialog supports both sources).

---

## 10. Change File Inventory

**New (source)**: `lib/pages/reader/auto_scroll.dart`, `lib/utils/hardware_keys.dart`, `lib/foundation/bookshelf.dart`, `lib/pages/bookshelf_page.dart`, `lib/pages/bookshelf_merge_page.dart`

**Modified (source)**: `lib/pages/reader/reader.dart`, `lib/pages/reader/images.dart`, `lib/pages/reader/scaffold.dart`, `lib/pages/settings/reader.dart`, `lib/pages/settings/settings_page.dart`, `lib/foundation/appdata.dart`, `lib/pages/main_page.dart`, `lib/pages/local_comics_page.dart`, `lib/pages/home_page.dart`, `lib/network/file_downloader.dart`

**Modified (platform/build)**: `android/app/build.gradle`, `android/app/src/main/AndroidManifest.xml`, `android/app/src/main/kotlin/com/github/wgh136/venera/MainActivity.kt`, `android/build.gradle`, `android/gradle.properties`, `android/gradle/wrapper/gradle-wrapper.properties`, `android/settings.gradle`, `analysis_options.yaml` (automatic)

**Resources/Docs**: `assets/translation.json`, `README.md`, `README_ZH.md`, `README_EN.md`, `docs/*`

---

## Appendix A: Key Changed Code

> The code below is taken from the repository's current final version, organized by module and corresponding to the sections above. Full line-by-line diffs are available in the git working tree via `git diff HEAD -- <file>`.

### A.1 Constant-Speed Scroll Engine — `lib/pages/reader/auto_scroll.dart` (new, complete)

Core idea: a `Ticker` advances the position every frame; delta = viewport height / ms-per-screen × real frame time (ms), so frame drops do not affect the speed; stops and fires the chapter-end callback at the scroll boundary.

```dart
part of 'reader.dart';

/// Drives a [ScrollPosition] at a constant speed for auto scrolling
/// in continuous reading mode.
///
/// The speed is expressed as "milliseconds per screen height": a value of
/// 5000 means one viewport is scrolled in 5 seconds. Each frame the position
/// is advanced by `speed * deltaTime`, so frame drops do not change the speed.
class AutoScrollEngine {
  AutoScrollEngine({
    required this.getPosition,
    required this.msPerScreen,
    required this.onReachEnd,
  });

  final ScrollPosition Function() getPosition;

  /// Milliseconds needed to scroll one screen (viewport dimension).
  final int Function() msPerScreen;

  /// Called when the end of the scroll range is reached. The engine is
  /// stopped before this callback is invoked.
  final VoidCallback onReachEnd;

  Ticker? _ticker;
  Duration _lastElapsed = Duration.zero;
  bool _forward = true;

  bool get isRunning => _ticker?.isActive ?? false;

  /// Start scrolling. Returns false if the scroll position is not ready yet.
  bool start({bool forward = true}) {
    _forward = forward;
    if (isRunning) return true;
    if (!getPosition().hasContentDimensions) return false;
    _lastElapsed = Duration.zero;
    _ticker = Ticker(_onTick)..start();
    return true;
  }

  /// Stop scrolling while keeping the current position.
  void pause() {
    _ticker?.stop();
    _ticker?.dispose();
    _ticker = null;
  }

  void _onTick(Duration elapsed) {
    if (_lastElapsed == Duration.zero) {
      _lastElapsed = elapsed;
      return;
    }
    final dt = (elapsed - _lastElapsed).inMicroseconds / 1000;
    _lastElapsed = elapsed;
    if (dt <= 0) return;
    final position = getPosition();
    if (!position.hasContentDimensions) return;
    final min = position.minScrollExtent;
    final max = position.maxScrollExtent;
    if (max - min < 10) {
      pause();
      onReachEnd();
      return;
    }
    final speed = position.viewportDimension / msPerScreen();
    final target = (position.pixels + (_forward ? speed : -speed) * dt).clamp(
      min,
      max,
    );
    position.jumpTo(target);
    if (_forward ? position.pixels >= max : position.pixels <= min) {
      pause();
      onReachEnd();
    }
  }
}
```

### A.2 Hardware Key Abstraction — `lib/utils/hardware_keys.dart` (new, core parts)

Action enum and key identity (`HardwareKey.fromLogicalKey` for keyboard sources, `HardwareKey(keyId)` for channel sources — both share the same ID space):

```dart
/// An action that can be triggered by a hardware key.
enum InputAction {
  nextPage,
  prevPage,
  toggleAutoScroll,
  nextChapter,
  prevChapter;

  static InputAction? tryParse(String name) {
    for (var value in values) {
      if (value.name == name) return value;
    }
    return null;
  }

  String get displayName => switch (this) {
    nextPage => "Next Page",
    prevPage => "Previous Page",
    toggleAutoScroll => "Toggle Auto Scroll",
    nextChapter => "Next Chapter",
    prevChapter => "Previous Chapter",
  };
}

/// A hardware key identified by the key id of its [LogicalKeyboardKey].
class HardwareKey {
  const HardwareKey(this.keyId);

  HardwareKey.fromLogicalKey(LogicalKeyboardKey key) : this(key.keyId);

  final int keyId;

  String get id => "fl:$keyId";

  String get displayName {
    var key = LogicalKeyboardKey.findKeyByKeyId(keyId);
    return key?.debugName ?? "Key $keyId";
  }
}
```

Reference-counted shared channel listener (fixes the race where swapping readers on comic switch cancelled the channel):

```dart
class HardwareKeyListener {
  static const _channel = EventChannel('venera/keys');

  static StreamSubscription? _source;

  static final _events = StreamController<HardwareKey>.broadcast();

  static int _refCount = 0;

  HardwareKeyListener({this.onKey});

  final void Function(HardwareKey key)? onKey;

  StreamSubscription? _sub;

  void listen() {
    _refCount++;
    if (_source == null) {
      _source = _channel.receiveBroadcastStream().listen(_onEvent);
    }
    _sub ??= _events.stream.listen(_dispatch);
  }

  void _onEvent(event) {
    // Events are sent as "<source>:<androidKeyCode>".
    var parts = event.toString().split(':');
    if (parts.length != 2) return;
    var code = int.tryParse(parts[1]);
    if (code == null) return;
    var key = HardwareKey(_androidKeyId + code);
    debugPrint("VeneraKeys: channel event $event -> ${key.id}");
    _events.add(key);
  }

  void _dispatch(HardwareKey key) {
    onKey?.call(key);
  }

  void cancel() {
    _sub?.cancel();
    _sub = null;
    _refCount--;
    if (_refCount <= 0) {
      _refCount = 0;
      _source?.cancel();
      _source = null;
    }
  }
}
```

Default key bindings (applied automatically when `inputKeyMap` is empty, so hardware keys work out of the box):

```dart
/// Flutter assigns Android key events key ids in the Android plane
/// (0x002 << 32) | keyCode.
const int _androidKeyId = 0x00200000000;

final Map<String, String> defaultInputKeyMap = {
  "fl:${_androidKeyId + 96}": "nextPage", // Gamepad A
  "fl:${_androidKeyId + 97}": "prevPage", // Gamepad B
  "fl:${_androidKeyId + 103}": "nextPage", // Gamepad R1
  "fl:${_androidKeyId + 102}": "prevPage", // Gamepad L1
  "fl:${_androidKeyId + 105}": "nextChapter", // Gamepad R2
  "fl:${_androidKeyId + 104}": "prevChapter", // Gamepad L2
  "fl:${_androidKeyId + 100}": "toggleAutoScroll", // Gamepad Y
  "fl:${_androidKeyId + 85}": "toggleAutoScroll", // Media Play/Pause
  "fl:${_androidKeyId + 20}": "nextPage", // DPad Down
  "fl:${_androidKeyId + 19}": "prevPage", // DPad Up
  "fl:${_androidKeyId + 22}": "nextPage", // DPad Right
  "fl:${_androidKeyId + 21}": "prevPage", // DPad Left
};
```

### A.3 Android Native Key Interception — `MainActivity.kt`

Interception happens in `dispatchKeyEvent` (before the Flutter engine), so mapped keys never trigger focus navigation:

```kotlin
override fun dispatchKeyEvent(event: KeyEvent): Boolean {
    if (listening) {
        when (event.keyCode) {
            KeyEvent.KEYCODE_VOLUME_DOWN -> {
                if (event.action == KeyEvent.ACTION_DOWN) {
                    volumeListen.down()
                }
                return true
            }

            KeyEvent.KEYCODE_VOLUME_UP -> {
                if (event.action == KeyEvent.ACTION_DOWN) {
                    volumeListen.up()
                }
                return true
            }
        }
    }
    if (forwardHardwareKey(event)) {
        return true
    }
    return super.dispatchKeyEvent(event)
}

private fun forwardHardwareKey(e: KeyEvent): Boolean {
    val sink = keySink ?: return false
    if (e.action != KeyEvent.ACTION_DOWN) {
        // Consume repeat events, let unmatched key-up events pass through.
        return e.repeatCount > 0
    }
    when (e.keyCode) {
        KeyEvent.KEYCODE_BACK, KeyEvent.KEYCODE_MENU -> return false
    }
    // Classify primarily by key code so controllers that report an
    // unexpected source (keyboard/joystick) are still handled.
    val source = when (e.keyCode) {
        in KeyEvent.KEYCODE_BUTTON_A..KeyEvent.KEYCODE_BUTTON_MODE -> "gamepad"
        in KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE..KeyEvent.KEYCODE_MEDIA_RECORD -> "media"
        KeyEvent.KEYCODE_DPAD_UP,
        KeyEvent.KEYCODE_DPAD_DOWN,
        KeyEvent.KEYCODE_DPAD_LEFT,
        KeyEvent.KEYCODE_DPAD_RIGHT,
        KeyEvent.KEYCODE_DPAD_CENTER -> "dpad"
        else -> {
            val isGamepad = e.source and InputDevice.SOURCE_GAMEPAD != 0 ||
                e.source and InputDevice.SOURCE_JOYSTICK != 0
            if (isGamepad) "gamepad" else return false
        }
    }
    Log.d("VeneraKeys", "forward $source:${e.keyCode}")
    sink.success("$source:${e.keyCode}")
    return true
}
```

### A.4 Reader Dispatch and Comic Switch — `lib/pages/reader/reader.dart`

Mapping lookup for the keyboard source (Flutter KeyEvents path):

```dart
void onKeyEvent(KeyEvent event) {
  if (event is KeyDownEvent) {
    var id = "fl:${event.logicalKey.keyId}";
    var actionName = _inputKeyMap[id];
    if (actionName == null &&
        event.logicalKey.keyId >= 0x00200000000 &&
        event.logicalKey.keyId < 0x00300000000) {
      // Android-plane key ids also match the channel id space used by
      // default bindings.
      actionName = _inputKeyMap["fl:${event.logicalKey.keyId}"];
    }
    var action = actionName == null ? null : InputAction.tryParse(actionName);
    if (action != null) {
      debugPrint("VeneraKeys: keyboard $id -> $actionName");
      handleInputAction(action);
      return;
    }
  }
  if (event.logicalKey == LogicalKeyboardKey.f12 && event is KeyUpEvent) {
    fullscreen();
  }
  _imageViewController?.handleKeyEvent(event);
}
```

Action-to-behavior mapping (continuous page turn = smooth scroll by one screen; gallery overflow crosses chapters/comics):

```dart
void handleInputAction(InputAction action) {
  switch (action) {
    case InputAction.nextPage:
      if (mode.isContinuous) {
        (_imageViewController as _ContinuousModeState?)?.pageForward();
      } else if (!toNextPage()) {
        toNextChapterOrComic();
      }
    case InputAction.prevPage:
      if (mode.isContinuous) {
        (_imageViewController as _ContinuousModeState?)?.pageBackward();
      } else if (!toPrevPage()) {
        toPrevChapterOrComic(toLastPage: true);
      }
    case InputAction.toggleAutoScroll:
      toggleAutoPlay();
    case InputAction.nextChapter:
      toNextChapterOrComic();
    case InputAction.prevChapter:
      toPrevChapterOrComic();
  }
}
```

The unified "chapter end → comic switch" fallback:

```dart
/// Switch to the previous chapter. Falls back to the previous comic in the
/// bookshelf when there is no previous chapter.
Future<void> toPrevChapterOrComic({bool toLastPage = false}) async {
  if (!toPrevChapter(toLastPage: toLastPage)) {
    await toNeighborComic(false);
  }
}

/// Switch to the next chapter. Falls back to the next comic in the
/// bookshelf when there is no next chapter.
Future<void> toNextChapterOrComic() async {
  if (!toNextChapter()) {
    await toNeighborComic(true);
  }
}
```

Continuous-mode last-page detection (the last page often cannot be fully displayed):

```dart
bool get isOnLastPage {
  if (chapter != maxChapter) return false;
  if (mode.isContinuous) {
    return maxPage <= 1 ? page >= maxPage : page >= maxPage - 1;
  }
  return page == maxPage;
}
```

Comic switching (finds the neighbor by bookshelf sort, restores the target comic's progress, replaces the route on the root navigator):

```dart
Future<bool> toNeighborComic(bool next) async {
  var shelf = BookshelfManager().sortedItems();
  var index = shelf.indexWhere((e) => e.id == cid && e.type == type);
  if (index < 0) {
    return false;
  }
  var targetIndex = next ? index + 1 : index - 1;
  if (targetIndex < 0 || targetIndex >= shelf.length) {
    showToast(
      context: App.rootContext,
      message: next ? "This is the last book".tl : "This is the first book".tl,
    );
    return false;
  }
  var entry = shelf[targetIndex];
  var comic = entry.resolveComic();
  if (comic == null) {
    showToast(context: App.rootContext, message: "Comic not found".tl);
    return false;
  }
  Widget page;
  if (comic is LocalComic) {
    var history = HistoryManager().find(comic.id, ComicType.local);
    page = Reader(
      type: ComicType.local,
      cid: comic.id,
      name: comic.title,
      chapters: comic.chapters,
      initialPage: history?.page,
      initialChapter: history?.ep,
      initialChapterGroup: history?.group,
      history: history ?? History.fromModel(model: comic, ep: 0, page: 0),
      author: comic.subTitle ?? '',
      tags: comic.tags,
    );
  } else {
    var source = entry.type.comicSource;
    if (source?.loadComicInfo == null) {
      showToast(context: App.rootContext, message: "Comic not found".tl);
      return false;
    }
    var res = await source!.loadComicInfo!(entry.id);
    if (res.error) {
      showToast(context: App.rootContext, message: res.errorMessage ?? "Error");
      return false;
    }
    var details = res.data;
    var history = HistoryManager().find(entry.id, entry.type);
    page = Reader(
      type: entry.type,
      cid: entry.id,
      name: details.title,
      chapters: details.chapters,
      initialPage: history?.page,
      initialChapter: history?.ep,
      initialChapterGroup: history?.group,
      history: history ?? History.fromModel(model: details, ep: 0, page: 0),
      author: details.subTitle ?? '',
      tags: details.tags.values.expand((e) => e).toList(),
    );
  }
  App.rootContext.toReplacement(() => page);
  return true;
}
```

### A.5 Continuous Mode Integration — `lib/pages/reader/images.dart`

Engine creation and start (touch pause, chapter-end callback):

```dart
void _startAutoScroll() {
  if (!(_scrollController?.hasClients ?? false)) return;
  _autoScroll ??= AutoScrollEngine(
    getPosition: () => scrollController.position,
    msPerScreen: _getAutoScrollMsPerScreen,
    onReachEnd: onAutoScrollReachEnd,
  );
  if (_autoScroll!.start(
    forward: reader.mode != ReaderMode.continuousRightToLeft,
  )) {
    reader.setAutoScrollActive(true);
    _autoScrollPausedByTouch = false;
  } else {
    reader.setAutoScrollActive(false);
  }
}

/// Pause auto scroll when the user touches the screen.
void _pauseAutoScrollByTouch() {
  if (_autoScroll?.isRunning ?? false) {
    _autoScroll!.pause();
    reader.setAutoScrollActive(false);
    _autoScrollPausedByTouch = true;
    context.readerScaffold.update();
  }
}
```

Chapter-end policy (falls back to the next comic when there is no next chapter):

```dart
void onAutoScrollReachEnd() async {
  reader.setAutoScrollActive(false);
  var behavior = appdata.settings.getReaderSetting(
    reader.cid,
    reader.type.sourceKey,
    'autoScrollOnChapterEnd',
  );
  if (behavior == 'nextChapter') {
    // When there is no next chapter, continue with the next comic.
    if (!reader.toNextChapter()) {
      await reader.toNeighborComic(true);
    } else {
      reader.autoScrollResumeAfterChapter = true;
    }
  }
  context.readerScaffold.update();
}
```

### A.6 Bookshelf Sorting — `lib/foundation/bookshelf.dart`

The single source of truth for ordering, shared by the bookshelf page and the reader's comic switch:

```dart
List<BookshelfItem> sortedItems() {
  var mode = appdata.settings['bookshelfSortMode'] ?? 'addedTime';
  var desc = appdata.settings['bookshelfSortDesc'] == true;
  var items = List.of(_items);
  switch (mode) {
    case 'name':
      items.sort((a, b) => a.title.compareTo(b.title));
    case 'lastRead':
      items.sort((a, b) => b.lastReadTime.compareTo(a.lastReadTime));
    case 'addedTime':
    default:
      items.sort((a, b) => a.addedAt.compareTo(b.addedAt));
  }
  if (desc) {
    items = items.reversed.toList();
  }
  return items;
}
```

### A.7 Comic Merging Core — `lib/pages/bookshelf_merge_page.dart`

Merging multiple local comics into one multi-chapter comic (files are moved, not copied; name clashes get a suffix):

```dart
Future<LocalComic> _mergeComics(List<LocalComic> sources) async {
  var first = sources.first;
  var dirName = sanitizeFileName(
    "${first.directory}_${sources.length}_Merge",
    maxLength: 120,
  );
  var dest = Directory(FilePath.join(LocalManager().path, dirName));
  int suffix = 1;
  var finalName = dirName;
  while (dest.existsSync()) {
    finalName = "${dirName}_$suffix";
    dest = Directory(FilePath.join(LocalManager().path, finalName));
    suffix++;
  }
  dest.createSync(recursive: true);

  // Cover: reuse the first comic's cover file.
  var coverFile = first.coverFile;
  var coverName = "cover.${coverFile.extension}";
  if (coverFile.existsSync()) {
    await coverFile.copyMem(FilePath.join(dest.path, coverName));
  } else {
    coverName = "";
  }

  var chapters = <String, String>{};
  int chapterIndex = 0;
  for (var source in sources) {
    var sourceChapters = <(String, Directory)>[]; // (title, directory)
    if (source.hasChapters) {
      var ids = source.chapters!.ids;
      var titles = source.chapters!.titles;
      for (var i = 0; i < ids.length; i++) {
        var cid = ids.elementAt(i);
        var dir = Directory(FilePath.join(
          source.baseDir,
          LocalManager.getChapterDirectoryName(cid),
        ));
        sourceChapters.add(("${source.title} - ${titles.elementAt(i)}", dir));
      }
    } else {
      sourceChapters.add((source.title, Directory(source.baseDir)));
    }
    for (var (title, dir) in sourceChapters) {
      var files = dir.listSync().whereType<File>().toList();
      files.removeWhere((e) {
        var name = e.name;
        return name.startsWith('cover.') || name.startsWith('.');
      });
      files.sort((a, b) {
        var ai = int.tryParse(a.name.split('.').first);
        var bi = int.tryParse(b.name.split('.').first);
        if (ai != null && bi != null) return ai.compareTo(bi);
        return a.name.compareTo(b.name);
      });
      if (files.isEmpty) continue;
      var chapterDirName = chapterIndex.toString();
      var chapterDir = Directory(FilePath.join(dest.path, chapterDirName));
      chapterDir.createSync();
      for (var i = 0; i < files.length; i++) {
        var src = files[i];
        var dst =
            File(FilePath.join(chapterDir.path, '${i + 1}.${src.extension}'));
        try {
          src.renameSync(dst.path);
        } catch (_) {
          await src.copyMem(dst.path);
        }
      }
      chapters[chapterIndex.toString()] = title;
      chapterIndex++;
    }
  }
  if (chapters.isEmpty) {
    dest.deleteSync(recursive: true);
    throw Exception("No pages found in the selected comics");
  }

  var comic = LocalComic(
    id: LocalManager().findValidId(ComicType.local),
    title: finalName,
    subtitle: first.subtitle,
    tags: first.tags,
    directory: finalName,
    chapters: ComicChapters(chapters),
    cover: coverName,
    comicType: ComicType.local,
    downloadedChapters: chapters.keys.toList(),
    createdAt: DateTime.now(),
  );
  await LocalManager().add(comic, comic.id);
  // Delete the source comics. Their page directories have been moved, so
  // only the leftover directories (covers) are removed from the disk.
  for (var source in sources) {
    LocalManager().deleteComic(source, true);
  }
  return comic;
}
```

### A.8 Reader Toolbar — `lib/pages/reader/scaffold.dart`

Play button (the toolbar hides itself once scrolling starts):

```dart
IconButton(
  icon: context.reader.isAutoScrolling
      ? const Icon(Icons.pause_circle_outline)
      : const Icon(Icons.play_circle_outline),
  onPressed: () {
    context.reader.toggleAutoPlay();
    update();
    // Hide the toolbar when auto scroll starts.
    if (context.reader.isAutoScrolling && _isOpen) {
      openOrClose();
    }
  },
),
```

First/last page buttons with comic-switch semantics:

```dart
/// First page button. When already on the very first page of the comic,
/// switch to the previous comic in the bookshelf.
void _gotoFirstPage(_ReaderState reader) {
  if (reader.isOnFirstPage) {
    reader.toNeighborComic(false);
  } else if (reader.chapter > 1) {
    reader.toPrevChapter();
  } else {
    reader.toPage(1);
  }
}

/// Last page button. When already on the very last page of the comic,
/// switch to the next comic in the bookshelf.
void _gotoLastPage(_ReaderState reader) {
  if (reader.isOnLastPage) {
    reader.toNeighborComic(true);
  } else if (reader.chapter < reader.maxChapter) {
    reader.toNextChapter();
  } else {
    reader.toPage(reader.maxPage);
  }
}
```

Set as cover (overwrites the cover file and syncs the database):

```dart
void setAsCover() async {
  var reader = context.reader;
  var comic = LocalManager().find(reader.cid, ComicType.local);
  if (comic == null) {
    return;
  }
  var result = await selectImageToData();
  if (result == null) {
    return;
  }
  var (_, data) = result;
  try {
    String coverName;
    var coverFile = comic.coverFile;
    if (coverFile.existsSync()) {
      coverName = comic.cover;
      await coverFile.writeAsBytes(data);
    } else {
      var ext = detectFileType(data).ext;
      coverName = "cover$ext";
      await File(FilePath.join(comic.baseDir, coverName)).writeAsBytes(data);
    }
    // Update the cover field in the database.
    var newComic = LocalComic(
      id: comic.id,
      title: comic.title,
      subtitle: comic.subtitle,
      tags: comic.tags,
      directory: comic.directory,
      chapters: comic.chapters,
      cover: coverName,
      comicType: comic.comicType,
      downloadedChapters: comic.downloadedChapters,
      createdAt: comic.createdAt,
    );
    await LocalManager().add(newComic, comic.id);
    showToast(context: context, message: "Cover updated".tl);
  } catch (e) {
    showToast(context: context, message: e.toString());
  }
}
```

### A.9 Key Build Configuration Diffs

```gradle
// android/gradle/wrapper/gradle-wrapper.properties
distributionUrl=https\://mirrors.cloud.tencent.com/gradle/gradle-8.14-all.zip

// android/settings.gradle
id "org.jetbrains.kotlin.android" version "2.2.20" apply false

// android/build.gradle — mavenCentral must precede the Aliyun mirrors
// (Gradle does not fall back when a mirror has the POM but lacks the jar)
allprojects {
    repositories {
        maven { url 'https://maven.aliyun.com/repository/google' }
        mavenCentral()
        maven { url 'https://maven.aliyun.com/nexus/content/groups/public' }
    }
}

// android/gradle.properties — avoids the cross-drive Kotlin incremental
// cache crash
kotlin.incremental=false

// android/app/build.gradle
ndkVersion "28.2.13676358"
applicationId = "com.github.wgh136.venera.mod"
// Falls back to the debug keystore (androiddebugkey/android) when
// key.properties is missing, so local builds can be signed; provide
// key.properties to sign with a real release key.

// android/build.gradle — HTTP repositories are rejected by newer Gradle
maven { url 'https://maven.aliyun.com/nexus/content/groups/public' }
```

---

## 11. Follow-up Iterations (v1.7.0): Merge/Import/Delete Polish and Root-Cause Fixes

> This section records changes after section 10, corresponding to chapter 14 of the development document.

### 11.1 Merge: file-level percent progress + ANR crash fix

- **Motivation**: merging large comics "randomly crashed"; progress was chapter-granular.
- **Root cause**: page file moving/copying was synchronous IO entirely on the main thread; long blocks triggered ANR and the system killed the app.
- **Implementation**: directory scanning stays on the main thread (lightweight); page files are moved in batches of 100 inside `compute` isolates, reporting progress between batches; the merge page shows a large percentage + progress bar + page counter.
- **Impact**: UI stays responsive during merges; progress updates in real time; crashes eliminated.

### 11.2 Import: skip existing names (all paths) + progress bars

- **Skip rule**: by comic/folder name, across archive import (previously threw and aborted), directory import, EhViewer import and local restore import; when copying to the local directory, an existing directory is skipped (the original renamed the existing directory aside, which risked data loss).
- **Progress**: "Importing i/N (xx%)" for multi-archive/multi-directory/EhViewer/local-restore; "Copying i/N (xx%)" with one isolate per comic for the copy phase.
- **Impact**: `ImportComic` constructor lost `const` (added a skippedCount counter); `CBZ.import` now returns `LocalComic?` (null = skipped).

### 11.3 Local deletion: three rounds to a final fix (important traceability)

| Round | Symptom | Root cause | Fix |
|---|---|---|---|
| 1 | Files not removed from disk | Deletion ran fire-and-forget inside `Isolate.run`; `SAFTaskWorker().init()` (a platform-channel call) threw inside the isolate, silently killing the whole deletion | Per-comic isolates with await and progress callbacks |
| 2 | No progress dialog; confirm dialog stayed open | `pop()` closes the top-most route — opening the progress dialog first made `pop()` close the progress dialog itself | Close the confirm dialog first, then show the progress dialog; the dialog has a 600 ms minimum visible duration |
| 3 | SAF comics (`android://primary:...`) failed to delete | a) `directory` may be an absolute path, so joining it to the local path was wrong (use `c.baseDir`); b) **SAF operations must run on the main isolate** (the flutter_saf grant registry lives there), and native recursive deletion should be used (an order of magnitude faster); c) favorites/history cleanup exceptions aborted file deletion (now wrapped in try/catch) | `deleteDirectories` wrapped in `overrideIO`, awaited per comic on the main thread; leftovers verified after deletion with a dedicated message |

**Operational note (important)**: SAF grants (`android://primary:...`) are cleared whenever the app is reinstalled. This repo uses the `.mod` package name, so grants are not shared with the official app; repeated reinstalls during development kept wiping them. Symptoms: reads/writes/deletes in that directory all fail (log signature `Cannot create directory specified`). Recovery: re-select the directory in the home-page import flow (re-grants access).

### 11.4 Other fixes and improvements

| Change | File | Notes |
|---|---|---|
| New `back` mapping action | `hardware_keys.dart`, `reader.dart` | Closes the reader |
| Cover update not taking effect | `reader/scaffold.dart` | The image cache key ignores file content; `imageCache.clear()` is called after updating a cover |
| Delete action in bookshelf selection mode | `bookshelf_page.dart` | Local comics are deleted from disk (with progress); network comics are only removed from the shelf |
| List/grid cover aspectFit | `bookshelf_page.dart` | `BoxFit.contain` shows the whole image without cropping; the aspect cache was promoted to module level and shared |
| `markAsRead` null crash (upstream bug) | `favorites.dart` | Early return when `followUpdatesFolder` is null |
| rhttp version mismatch | `pubspec.yaml` | `dependency_overrides: flutter_rust_bridge: 2.11.1` fixes `Rhttp.init` |
| Screen turning off during auto play | `reader.dart` + existing `setScreenOn` channel | Keep the screen on while auto scroll / timed page turning runs; restore on stop/exit |

### 11.5 Version history

| Version | Notes |
|---|---|
| 1.6.3+163 | Iterations 1–4 feature set; first GitHub Release (4 APKs + Windows zip) |
| 1.6.4+164 / 1.6.5+165 | Iteration 5 fixes (internal builds) |
| 1.7.0+170 | Full iteration 5–6 content, official release |

---

## 12. Follow-up Iteration (v1.7.2): Structured Import and Merge Naming Fix

> Corresponds to chapter 15 of the development document.

### 12.1 New File

| File | Notes |
|---|---|
| `lib/utils/comic_structure.dart` | Comic directory structure analysis: single-chain descent, branch detection, recursive image collection, natural sorting |

### 12.2 Structured Import

- Archive import (`CBZ.import`) and directory import (`_checkSingleComic`) share `analyzeComicStructure`: descend single chains to the content root; a content root with ≥2 subdirectories is a multi-chapter comic, otherwise single-chapter.
- The multi-chapter import format matches the merge result: comic name directory on the first level, `0,1,2...` chapter directories on the second, chapter titles = original folder names (natural order); archive pages are **moved** from the extraction cache.
- Directory import no longer rejects comics whose chapter directories contain subdirectories; the comic `directory` points to the descended content root.
- metadata.json chapter definitions (start/end splits) remain supported.

### 12.3 Recursive Local Reading

`LocalManager.getImages` now collects page files recursively (excluding `cover.*` and hidden files) with natural sorting. Comics in the old format behave unchanged.

### 12.4 Merge Naming Fix

When the first comic's `directory` is an absolute path (imported without copying), only its last segment is used as the merged comic's name prefix, fixing the "full path + comic name" issue.

### 12.5 Other Changes in the Same Version

- Auto scroll speed setting: slider + tappable manual input (`_AutoScrollSpeedSetting`, input range 100–600000 ms, slider range 1000–60000)
- Bookshelf view mode dialog closes automatically after selection
- Screen stays on during long operations (import / merge / deletion) via the new shared `setScreenOn` helper in `utils/io.dart`
- Local delete dialog order fix (close the confirm dialog before showing the progress dialog)
