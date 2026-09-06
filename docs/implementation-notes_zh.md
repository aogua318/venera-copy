# Venera Mod 实施记录（追溯文档）

> 本文档记录本仓库相对上游 [venera-app/venera](https://github.com/venera-app/venera)（基线：上游 master，"项目已停止维护"版本）的全部功能性改动与工程适配，按模块组织。每项改动说明**背景与目的**、**实现方式**、**影响面**（用户可见行为变化 / 兼容性 / 风险），供后续维护者追溯。
>
> 功能设计过程与真机问题的根因分析另见 [dev-plan-auto-scroll-gamepad.md](dev-plan-auto-scroll-gamepad.md)（按迭代 1–4 组织的开发文档）。
>
> 状态：全部改动已实现并通过 `flutter analyze`（0 error），已在 Android 真机完成主要功能验证。

---

## 1. 变更总览

### 新增文件

| 文件 | 类型 | 所属功能 |
|---|---|---|
| `lib/pages/reader/auto_scroll.dart` | Dart（reader 库 part） | 恒速平滑自动滚动引擎 |
| `lib/utils/hardware_keys.dart` | Dart | 硬件按键抽象：动作枚举、按键标识、平台通道监听、默认映射 |
| `lib/foundation/bookshelf.dart` | Dart | 书架数据管理（持久化、排序） |
| `lib/pages/bookshelf_page.dart` | Dart | 书架页面（视图/选择/排序/导入） |
| `lib/pages/bookshelf_merge_page.dart` | Dart | 漫画合并页 |
| `README_ZH.md` / `README_EN.md` / `README.md` | 文档 | 项目说明 |
| `docs/dev-plan-auto-scroll-gamepad.md` | 文档 | 功能开发文档（迭代 1–4） |
| `docs/implementation-notes_zh.md` / `_en.md` | 文档 | 本文档 |

### 修改文件

| 文件 | 改动主题 |
|---|---|
| `lib/pages/reader/reader.dart` | 自动滚动状态与动作分发、硬件按键分发、切本、章末判定 |
| `lib/pages/reader/images.dart` | 连续模式接入滚动引擎、触摸暂停、章末回退切本 |
| `lib/pages/reader/scaffold.dart` | 工具栏（播放/封面/首末页按钮）、章节切换统一 |
| `lib/pages/settings/reader.dart` | 新设置项 UI、按键映射页 |
| `lib/pages/settings/settings_page.dart` | 引入 hardware_keys 依赖 |
| `lib/foundation/appdata.dart` | 新增设置项默认值 |
| `lib/pages/main_page.dart` | 侧边栏书架入口 |
| `lib/pages/local_comics_page.dart` | 多选菜单"加入书架" |
| `lib/pages/home_page.dart` | 导入对话框组件公开化（供书架复用） |
| `assets/translation.json` | 新增约 50 条简繁中文翻译 |
| `android/app/build.gradle` | 包名、签名回退、NDK 版本 |
| `android/app/src/main/AndroidManifest.xml` | 应用名 Venera Mod |
| `android/app/src/main/kotlin/.../MainActivity.kt` | 手柄/媒体键平台通道 |
| `android/build.gradle` | Maven 仓库修正 |
| `android/settings.gradle` | Kotlin 插件版本 |
| `android/gradle.properties` | Kotlin 增量编译开关 |
| `android/gradle/wrapper/gradle-wrapper.properties` | Gradle 版本 |
| `lib/network/file_downloader.dart` | 修复新版 Dart 分析器的类型错误 |
| `analysis_options.yaml` | Flutter 工具自动追加 analyzer 排除目录（非人工改动） |
| `pubspec.lock` | Flutter 3.47.2 环境下的依赖重新解析（非人工改动） |

---

## 2. 阅读体验

### 2.1 恒速平滑自动滚动

- **目的**：原版条漫（连续模式）的"自动播放"是 `Timer.periodic` 定时整屏翻页，观感为跳动。需求是按恒定速度平滑滚动，速度可由用户设定。
- **实现**：
  - 新增 `AutoScrollEngine`（`auto_scroll.dart`）：以 `Ticker` 逐帧驱动连续模式的 `ScrollPosition`，每帧位移 = 视口高度 / 每屏毫秒数 × 真实帧间隔（ms），掉帧时按真实耗时补偿，保证恒速。到达滚动边界时停止并触发章末回调。
  - 速度设置 `autoScrollMsPerScreen`（毫秒/屏，1000–60000，默认 5000），运行中每帧读取，修改即时生效。
  - 由 `_ContinuousModeState` 持有引擎实例；连续模式的自动播放入口（底栏播放按钮）切换到引擎，页图（翻页）模式保留原定时翻页。
  - 页码与阅读进度：连续模式原有 `itemPositionsListener` 基于滚动位置回写页码/历史，恒速滚动下自动正确，无需额外处理。
- **影响**：
  - 仅影响连续阅读模式（条漫/左右连续）；翻页模式行为不变。
  - 触摸屏幕即暂停（用户手势优先），可选设置 `autoScrollResumeAfterTouch` 控制抬手后是否恢复（默认不恢复）。
  - 缩放、双击、长按等手势与滚动引擎共存（触摸优先暂停）。
  - 风险点：高速滚动时网络图片加载可能跟不上（出现加载占位），当前策略为不等待继续滚动，属可接受体验。

### 2.2 自动播放模式切换

- **目的**：保留原版"定时翻页"习惯，允许用户在两种自动播放方式间选择。
- **实现**：新设置 `autoPlayMode`（`smoothScroll` 默认 / `pageTurning`），支持按漫画独立设置；`toggleAutoPlay()` 按设置分发，底栏按钮 tooltip 与图标随模式与运行状态变化。
- **影响**：手柄"开/关自动播放"动作同样跟随该设置；`pageTurning` 模式下章末行为沿用原版（到最后一页停止）。

### 2.3 章末行为与末页判定

- **目的**：自动滚动到章末后应可预期地继续；同时修正连续模式末页显示不完整导致的"到不了章末"问题。
- **实现**：
  - 设置 `autoScrollOnChapterEnd`：`stop`（默认，停在章末）/ `nextChapter`（自动进入下一章继续滚动；最后一章滚动完自动切下一本继续，见 §3.5）。
  - 末页判定 `isOnLastPage`：连续模式下 `page >= maxPage - 1`（最后一页常因高度不足无法完整显示，滚动会停在倒数第二屏）；翻页模式维持 `page == maxPage`。
- **影响**：末页按钮切本、自动滚动章末共用该判定；阅读页 UI 其它部分不变。

### 2.4 设为封面

- **目的**：本地漫画导入后的封面常不理想，允许在阅读时把当前页设为封面。
- **实现**：底栏新增按钮（仅 `ComicType.local` 显示）→ 复用 `selectImageToData()` 取当前页图片字节 → 覆盖写回 `LocalComic.coverFile`；若封面文件不存在则新建 `cover.<ext>` 并通过 `LocalManager().add` 更新数据库 cover 字段。
- **影响**：书架/本地列表立即显示新封面；仅本地漫画可用（网络漫画封面由源站决定）。

---

## 3. 硬件按键与按键映射（Android）

### 3.1 按键抽象与分发

- **目的**：手柄、键盘、媒体键统一控制阅读，且用户可自定义映射。
- **实现**：
  - `InputAction` 枚举：`nextPage / prevPage / toggleAutoScroll / nextChapter / prevChapter`。
  - 按键标识 `HardwareKey`：以 Flutter `LogicalKeyboardKey` 的 keyId（`"fl:<keyId>"`）为唯一 ID；Android 手柄/DPAD/媒体键的原生按键码按 `(0x002 << 32) | keyCode` 的 Android 平面规则换算到同一 ID 空间。
  - 分发链（两条来源，统一进 `_ReaderState.handleInputAction`）：
    1. **平台通道**（`EventChannel("venera/keys")`）：`MainActivity.dispatchKeyEvent` 拦截**按键码优先分类**的手柄（96–110）、媒体（85–127）、DPAD（19–23）按键并消费（防止触发焦点导航），转发到 Dart；键盘按键不拦截，走 Flutter 自带 KeyEvents。
    2. **Flutter KeyboardListener**：键盘按键（含手柄以键盘模式上报的情况）。
  - **引用计数共享流**：通道订阅由所有 `HardwareKeyListener` 实例共享（`StreamController.broadcast`），计数归零才取消——解决"切本时新旧 Reader 监听器交替导致通道被误取消"的竞态。
  - **默认映射回退**：用户未自定义时（`inputKeyMap` 为空）自动使用 `defaultInputKeyMap`（A/B/R1/L1 翻页、R2/L2 翻章、Y 与媒体播放键开自动滚动、DPAD 方向翻页），开箱即用。
  - 调试：Kotlin `Log.d("VeneraKeys")` 与 Dart `debugPrint` 输出转发/接收/命中全链路。
- **影响**：
  - 阅读页内手柄/DPAD 不再移动焦点；阅读页外恢复系统行为。
  - 音量键不被映射体系处理（系统截留），原"音量键翻页"功能保持独立。
  - Back/Menu 永不拦截。
  - 长按连发不支持（仅 KeyDown 触发一次）。

### 3.2 按键映射 UI

- **实现**：设置 → 阅读 → "硬件按键映射"（仅 Android 显示）。`ListView` 列出全部动作，点按进入监听弹窗（同时订阅通道与键盘事件），按任意键完成绑定；一键仅可绑定一个动作（重复绑定自动转移）；点按绑定标签删除；支持恢复默认。映射数据存 `inputKeyMap`（`"fl:<keyId>" → action 名`）。
- **影响**：映射页使用普通 `ListView`（初版误用 Sliver 结构导致渲染崩溃，已重构）。

### 3.3 章末→切本逻辑统一

- **目的**：所有"上一章/下一章"入口在无章可切时自动退化为"上一本/下一本"（按书架当前排序与逆序）。
- **实现**：`toPrevChapterOrComic() / toNextChapterOrComic()` 统一封装，应用于：手柄/映射翻章动作、悬浮章节切换按钮、音量键跨章、翻页模式翻页到头、自动滚动章末策略。
- **影响**：当前漫画不在书架时回退不生效（保持原版无操作），不会误触发；切本通过根导航器 `pushReplacement` 完成，目标漫画自动恢复其阅读进度（历史记录），自动滚动状态不跨本恢复（需手动重新开启）。

---

## 4. 书架

### 4.1 数据与页面

- **目的**：提供独立的连续阅读列表（区别于收藏夹），支持排序与快速切本。
- **实现**：
  - `BookshelfManager`（`foundation/bookshelf.dart`）：有序条目列表 `{comicId, comicType, addedAt}`，持久化到 `App.dataPath/bookshelf.json`；损坏数据自动回退空列表。`sortedItems()` 为唯一排序真源（`bookshelfSortMode`：addedTime 默认 / name / lastRead；`bookshelfSortDesc` 逆序），书架页与阅读页切本共用。
  - 书架页：导航面板新入口（Home 之后）；空态引导导入；条目解析优先本地漫画、其次历史记录（网络漫画）。
  - 导入：复用首页本地导入对话框（`ImportComicsWidget` 由 home_page 私有改公开），导入成功的增量自动加入书架；本地页多选菜单新增"加入书架"。
  - 选择模式：长按进入（原菜单取消），顶栏为数量 + 合并/移出/全选/反选/全不选；返回键先退出选择模式。
  - 视图：`bookshelfViewMode` 三种——列表（原版 `ComicTile` 卡片网格）、网格（自绘 tile：固定 0.72 比例封面 + 文件名，超长省略）、瀑布流（按封面真实宽高比，尺寸异步读取并缓存）；切换即时生效。
- **影响**：
  - 书架数据与官方版完全独立；删除本地漫画后书架条目在下次进入时自动清理（`prune()`）。
  - 手动拖拽排序功能在迭代 4 中按需求**移除**（排序仅保留自动模式 + 逆序）。
  - 网格/瀑布流为自绘 tile，选中边框与内容天然对齐；条目按 `ValueKey("视图:ID:选中态")` 重建，切视图时选中标记跟随。

### 4.2 漫画合并

- **目的**：把多个单章本地漫画合并为一本连续漫画（多压缩包场景的常见需求）。
- **实现**（`bookshelf_merge_page.dart`）：选择 ≥2 本本地漫画 → 合并页拖拽排序 → 确认后：
  1. 新目录命名 `sanitizeFileName(第一本.directory + "_" + 本数 + "_Merge")`，重名自动追加 `_1`；
  2. 每本源漫画变为一章（多章漫画展开为"原书名 - 章节名"），章节目录按 `0,1,2…` 组织，页面文件**移动**（rename，跨卷回退复制）；
  3. 封面沿用第一本的封面；注册 `LocalComic`（`ComicChapters` 按序）后删除全部源漫画（`deleteComic`，因页面已移走，实际仅清理残留目录）；
  4. 书架中移出源漫画、加入新漫画。
- **影响**：**源漫画会被删除**（数据不可恢复，UI 文案已注明）；仅支持本地漫画；文件移动要求同一存储卷（跨卷自动回退复制）。

### 4.3 阅读页切本入口

- 底栏"跳首页/跳末页"按钮：已在全书第一页再按前者 → 上一本；已在全书最后一页（连续模式按 §2.3 判定）再按后者 → 下一本。不在书架时保持原版行为（跳本章首/末页）。
- 全部章节切换入口的章末回退见 §3.3。

---

## 5. 本地化

- `assets/translation.json` 新增约 50 条 `zh_CN` / `zh_TW` 词条，覆盖自动滚动、按键映射、书架、合并、切本提示等全部新 UI 字符串；英文为源语言直出。

---

## 6. 工程与构建适配

> 背景：上游停更于 Flutter 3.41 / Gradle 8.13 / AGP 8.12.3 / Kotlin 2.1.0；本地 Flutter 3.47.2 的工具链校验要求更高版本，逐项升级并修复连锁问题。

| 改动 | 文件 | 目的 | 影响 |
|---|---|---|---|
| Gradle 8.13 → 8.14 | `gradle-wrapper.properties` | Flutter 最低要求 8.14 | 保留腾讯镜像源；Flutter 提示未来需 9.1（仅警告） |
| Kotlin 2.1.0 → 2.2.20 | `settings.gradle` | Flutter 最低要求 2.2.20 | 与 AGP 8.12.3 兼容（有"未测试组合"警告） |
| NDK 28.0 → 28.2.13676358 | `android/app/build.gradle` | 插件依赖的最高 NDK 版本，消除版本不一致警告 | 首次构建自动下载 |
| 移除 jcenter 镜像 + 增加 `mavenCentral()` | `android/build.gradle` | 阿里云 jcenter 镜像缺包（如 kotlinx-coroutines）；POM 在镜像、jar 缺失时 Gradle 不会回退，故 `mavenCentral()` 必须放在镜像之前 | 国内下载速度略降，完整性优先 |
| HTTP → HTTPS（aliyun public） | `android/build.gradle` | 新 Gradle 禁止未声明的 insecure protocol | — |
| `kotlin.incremental=false` | `gradle.properties` | 插件源码在 C 盘 Pub 缓存、构建目录在 E 盘，跨盘符导致 Kotlin 增量缓存崩溃（"different roots"） | 全量编译，构建稍慢 |
| 签名回退 | `android/app/build.gradle` | 原 build.gradle 强制读取 `key.properties`，缺失时配置阶段崩溃。现缺失时自动用 `~/.android/debug.keystore`（androiddebugkey/android） | 本地构建免配签名；升级覆盖需保持同一 keystore；正式发布仍可提供 `key.properties` |
| 包名 `.mod` 后缀 | `android/app/build.gradle` | 与官方版共存 | 数据与官方版完全隔离 |
| 应用名 Venera Mod | `AndroidManifest.xml` | 桌面图标区分 | — |
| `_fetchBlock` 回调返回类型 | `lib/network/file_downloader.dart` | 新 Dart 分析器报错：`then<bool>` 推断导致 onError 必须返回 bool。改为块体使 onValue 返回 void | 行为不变 |
| analyzer 排除目录 | `analysis_options.yaml` | Flutter 工具自动追加（build/android 等目录），非人工改动 | — |
| `pubspec.lock` | — | Flutter 3.47.2 环境下 `pub get` 重新解析 | 非人工改动 |

---

## 7. 新增设置项总表

| 设置项 | 默认值 | 取值 | 说明 |
|---|---|---|---|
| `autoScrollMsPerScreen` | 5000 | 1000–60000（步进 500） | 平滑滚动每屏毫秒数（连续模式） |
| `autoScrollOnChapterEnd` | `stop` | stop / nextChapter | 滚动到章末的行为 |
| `autoScrollResumeAfterTouch` | false | bool | 触摸暂停后抬手是否恢复 |
| `autoPlayMode` | `smoothScroll` | smoothScroll / pageTurning | 自动播放方式（连续模式） |
| `inputKeyMap` | `{}`（空时回退内置默认映射） | `"fl:<keyId>" → action` | 硬件按键映射 |
| `bookshelfSortMode` | `addedTime` | addedTime / name / lastRead | 书架排序 |
| `bookshelfSortDesc` | false | bool | 书架逆序 |
| `bookshelfViewMode` | `grid` | list / grid / waterfall | 书架视图 |

以上均为全局设置；`autoScroll*` 与 `autoPlayMode` 走 `getReaderSetting` 体系，支持按漫画独立设置。

---

## 8. 用户可见行为变更清单（相对原版）

1. 连续模式"自动播放"默认为平滑滚动（原为定时整屏翻页；可在设置切回）。
2. 阅读页底栏：播放按钮图标/文案随模式变化；本地漫画新增"设为封面"按钮。
3. Android 阅读页内手柄/DPAD 按键默认可翻页、开自动滚动；阅读页外不拦截。
4. 导航面板新增"书架"。
5. 本地漫画多选菜单新增"加入书架"。
6. 书架：长按进入选择模式（原为无操作/本不存在该页）。
7. 书架内漫画：章首/章末的"跳首页/跳末页"按钮变为切上一本/下一本；所有翻章入口在章末自动接续切本。
8. 自动滚动到章末（`nextChapter` 策略）在最后一章时接续下一本。
9. 触摸自动暂停平滑滚动。

---

## 9. 已知限制与后续建议

1. 音量键被系统截留，无法参与按键映射（原版音量键翻页功能不受影响）。
2. 高速自动滚动时网络图片加载可能跟不上，出现加载占位后继续滚动；如需"等待加载"降速策略可后续迭代。
3. 书架数据（bookshelf.json）未纳入 WebDAV 同步。
4. macOS/Linux 桌面版未在本机验证；键盘映射在桌面端走 Flutter KeyEvents 路径，可工作但未承诺。
5. 合并功能仅支持本地漫画；网络漫画下载到本地后同样可用。
6. 手柄若以"键盘模式"上报（发送字母键），需在映射页手动绑定（弹窗支持两种来源）。

---

## 10. 变更文件清单

**新增（源码）**：`lib/pages/reader/auto_scroll.dart`、`lib/utils/hardware_keys.dart`、`lib/foundation/bookshelf.dart`、`lib/pages/bookshelf_page.dart`、`lib/pages/bookshelf_merge_page.dart`

**修改（源码）**：`lib/pages/reader/reader.dart`、`lib/pages/reader/images.dart`、`lib/pages/reader/scaffold.dart`、`lib/pages/settings/reader.dart`、`lib/pages/settings/settings_page.dart`、`lib/foundation/appdata.dart`、`lib/pages/main_page.dart`、`lib/pages/local_comics_page.dart`、`lib/pages/home_page.dart`、`lib/network/file_downloader.dart`

**修改（平台/构建）**：`android/app/build.gradle`、`android/app/src/main/AndroidManifest.xml`、`android/app/src/main/kotlin/com/github/wgh136/venera/MainActivity.kt`、`android/build.gradle`、`android/gradle.properties`、`android/gradle/wrapper/gradle-wrapper.properties`、`android/settings.gradle`、`analysis_options.yaml`（自动）

**资源/文档**：`assets/translation.json`、`README.md`、`README_ZH.md`、`README_EN.md`、`docs/*`

---

---

## 附录 A：关键改动代码

> 以下代码摘自仓库当前最终版本，按模块组织，与正文各节对应。完整的逐行差异可在 git 工作区用 `git diff HEAD -- <file>` 查看。

### A.1 恒速滚动引擎 —— `lib/pages/reader/auto_scroll.dart`（新增，完整）

核心思路：`Ticker` 逐帧推进，位移 = 视口高度 / 每屏毫秒数 × 真实帧间隔（ms），掉帧不影响速度；触达滚动边界时停止并回调章末策略。

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

### A.2 硬件按键抽象 —— `lib/utils/hardware_keys.dart`（新增，核心部分）

动作枚举与按键标识（`HardwareKey.fromLogicalKey` 用于键盘来源，`HardwareKey(keyId)` 用于通道来源，两者共用同一 ID 空间）：

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

引用计数共享通道监听（解决"切本时新旧 Reader 监听器交替导致通道被取消"的竞态）：

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

默认按键映射（`inputKeyMap` 为空时自动回退到该表，开箱即用）：

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

### A.3 Android 原生按键拦截 —— `MainActivity.kt`

在 `dispatchKeyEvent` 层拦截（先于 Flutter 引擎），映射过的按键不会触发焦点导航：

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

### A.4 阅读器分发与切本 —— `lib/pages/reader/reader.dart`

键盘来源的映射匹配（Flutter KeyEvents 路径）：

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

动作到实际操作的映射（连续模式翻页 = 平滑滚动一屏；翻页模式到头自动跨章/切本）：

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

统一的"章末→切本"回退：

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

连续模式末页判定（最后一页常因高度不足无法完整显示）：

```dart
bool get isOnLastPage {
  if (chapter != maxChapter) return false;
  if (mode.isContinuous) {
    return maxPage <= 1 ? page >= maxPage : page >= maxPage - 1;
  }
  return page == maxPage;
}
```

切本实现（按书架排序找相邻本，恢复目标漫画的阅读进度，根导航器替换路由）：

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

### A.5 连续模式集成 —— `lib/pages/reader/images.dart`

引擎的创建与启动（触摸暂停、章末回调）：

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

章末策略（无下一章时接续下一本）：

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

### A.6 书架排序 —— `lib/foundation/bookshelf.dart`

书架页与阅读页切本共用的唯一排序真源：

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

### A.7 漫画合并核心 —— `lib/pages/bookshelf_merge_page.dart`

多本本地漫画合并为一本多章节漫画（文件移动而非复制，重名目录自动加后缀）：

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

### A.8 阅读页工具栏 —— `lib/pages/reader/scaffold.dart`

播放按钮（启动后自动收起工具栏）：

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

首/末页按钮的切本语义：

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

设为封面（覆盖封面文件并同步数据库）：

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

### A.9 构建配置关键 diff

```gradle
// android/gradle/wrapper/gradle-wrapper.properties
distributionUrl=https\://mirrors.cloud.tencent.com/gradle/gradle-8.14-all.zip

// android/settings.gradle
id "org.jetbrains.kotlin.android" version "2.2.20" apply false

// android/build.gradle —— mavenCentral 必须在阿里云镜像之前
// （镜像存在 POM 但缺 jar 时 Gradle 不会回退到后续仓库）
allprojects {
    repositories {
        maven { url 'https://maven.aliyun.com/repository/google' }
        mavenCentral()
        maven { url 'https://maven.aliyun.com/nexus/content/groups/public' }
    }
}

// android/gradle.properties —— 跨盘符 Kotlin 增量缓存崩溃的规避
kotlin.incremental=false

// android/app/build.gradle
ndkVersion "28.2.13676358"
applicationId = "com.github.wgh136.venera.mod"
// key.properties 缺失时回退 debug.keystore（androiddebugkey/android），
// 保证本地构建可签名；提供 key.properties 时仍使用正式签名。

// android/build.gradle —— HTTP 协议仓库被新版 Gradle 拒绝，改为 HTTPS
maven { url 'https://maven.aliyun.com/nexus/content/groups/public' }
```

---

## 11. 追加迭代（v1.7.0）：合并/导入/删除打磨与修复

> 本节记录第 10 节之后的追加改动，与开发文档第 14 节对应。

### 11.1 合并：文件粒度百分比进度 + 修 ANR 闪退

- **目的**：合并大漫画时"有几率闪退"；进度只有章节粒度。
- **根因**：页面文件移动/复制为同步 IO 且全在主线程，长时间阻塞触发 ANR 被系统强杀。
- **实现**：目录扫描留在主线程（轻量）；页面文件按 100 文件/批在 `compute` isolate 中移动，批间回报进度；合并页显示大字号百分比 + 进度条 + 页数计数。
- **影响**：合并全程 UI 可响应；进度实时走动；闪退消除。

### 11.2 导入：跳过同名（全路径）+ 进度条

- **跳过规则**：按漫画名/文件夹名判断，覆盖归档导入（原为抛异常中断）、目录导入、EhViewer 导入、本地恢复导入；复制到本地目录时同名目录跳过（原版会把已存在目录改名挪走，存在数据风险，已改为跳过）。
- **进度**：多压缩包/多目录/EhViewer/本地恢复显示"导入中 i/N (xx%)"；复制阶段一本一 isolate，显示"复制中 i/N (xx%)"。
- **影响**：`ImportComic` 构造函数去 const（新增 skippedCount 计数）；`CBZ.import` 返回值改为 `LocalComic?`（null = 跳过）。

### 11.3 本地删除：三轮修复终局（重要追溯）

| 轮次 | 现象 | 根因 | 修复 |
|---|---|---|---|
| 1 | 删除后磁盘文件未删 | 删除在 `Isolate.run` 中 fire-and-forget；isolate 内 `SAFTaskWorker().init()`（平台通道调用）抛错 → 整个删除 isolate 静默死亡 | 逐本 isolate + await + 进度回调 |
| 2 | 进度框未弹、确认框未自动关闭 | `pop()` 关闭栈顶路由——先弹进度框再 `pop()` 会误关进度框 | 先关确认框、再弹进度框；进度框加 600ms 最短显示时长 |
| 3 | SAF 漫画（`android://primary:...`）删除失败 | a) `directory` 为绝对路径时拼错位置（改用 `c.baseDir`）；b) **SAF 操作必须在主线程**（flutter_saf 授权注册表在主 isolate），且应使用原生递归删除（快一个数量级）；c) 收藏/历史清理异常会阻断文件删除（包 try/catch） | `deleteDirectories` 包 `overrideIO` 并在主线程逐本 await；删完校验残留，SAF 失败弹专项提示 |

**运维知识（重要）**：SAF 授权（`android://primary:...`）随应用重装而清空。本仓库包名为 `.mod`，与官方版授权互不继承；开发期反复重装导致授权频繁丢失，表现为该目录读取/写入/删除全部失败（日志特征 `Cannot create directory specified`）。恢复方式：首页导入中重新选择该目录（重新授权）。

### 11.4 其他修复与改进

| 改动 | 文件 | 说明 |
|---|---|---|
| 映射动作新增 `back`（返回） | `hardware_keys.dart`、`reader.dart` | 触发关闭阅读页 |
| 设为封面后图片缓存未失效 | `reader/scaffold.dart` | 缓存键不含文件内容，封面更新后调用 `imageCache.clear()` 立即生效 |
| 书架选择模式新增删除 | `bookshelf_page.dart` | 本地漫画连磁盘删除（进度框），网络漫画仅移出书架 |
| 列表/网格封面 aspectFit | `bookshelf_page.dart` | `BoxFit.contain` 长边贴边完整展示，不再裁切；封面比例缓存提升为模块级共享 |
| `markAsRead` 空指针（上游 bug） | `favorites.dart` | `followUpdatesFolder` 为 null 时提前返回 |
| rhttp 版本不匹配 | `pubspec.yaml` | `dependency_overrides: flutter_rust_bridge: 2.11.1`，修复 `Rhttp.init` 失败 |
| 自动播放熄屏 | `reader.dart` + 既有 `setScreenOn` 通道 | 自动滚动/定时翻页期间保持屏幕常亮，停止/退出恢复 |

### 11.5 版本历史

| 版本 | 说明 |
|---|---|
| 1.6.3+163 | 迭代 1–4 功能集，首次发布 GitHub Release（4 APK + Windows zip） |
| 1.6.4+164 / 1.6.5+165 | 迭代 5 修复（未发布，内部构建） |
| 1.7.0+170 | 迭代 5–6 全部内容，正式发布 |
