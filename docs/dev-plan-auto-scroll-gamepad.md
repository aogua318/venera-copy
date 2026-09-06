# 开发文档：条漫恒速平滑自动滚动 + Android 手柄/按键映射

> 状态：迭代 1 已实现并进入真机测试；迭代 2 需求已澄清，待开发
> 涉及范围：阅读器（reader）、设置（settings）、输入事件（foundation）、首页/本地（pages）、数据（foundation/local）
> 平台目标：Android（手柄 + 蓝牙/USB 键盘 + 媒体键）

---

## 0. 迭代记录

- **迭代 1（已完成）**：恒速平滑自动滚动、手柄/键盘/媒体键映射、映射设置页。已过 `flutter analyze` 与 APK 构建。
- **迭代 2（本文档第 9–11 节）**：测试问题修复（P0）、模式切换设置、汉化、书架、阅读页切本。
- **迭代 3（本文档第 12 节，已完成）**：书架合并、封面设置、视图模式；真机回归问题修复（手柄按键码分类、书架全屏进入、返回键、末页判定、切本跟随排序等）；移除手动拖拽排序。
- **迭代 4（本文档第 13 节，已完成）**：手柄通道引用计数（切本后失效根因）+ 默认映射开箱生效；章末→切本逻辑全局统一；书架三种视图落地与视觉修正；选择工具栏补齐。
- **迭代 5（本文档第 14 节，已完成）**：合并进度百分比（isolate 文件粒度，修 ANR 闪退）；导入跳过同名（全路径）+ 导入进度条百分比；书架列表/网格封面 aspectFit；映射新增返回键；本地删除修复（等待完成+进度框）。
- **迭代 6（已完成，随 v1.7.0 发布）**：SAF 删除根因终修（主线程 overrideIO + 原生递归删除）、rhttp 版本锁定、markAsRead 空指针修复（上游 bug）、SAF 授权丢失专项提示；版本号升至 1.7.0 并发布 GitHub Release（代码+APK+Windows 包）。
- **迭代 7（本文档第 15 节，随 v1.7.2 发布）**：结构化导入（压缩包/目录自动判断嵌套与分支，拍平或章节化）、本地阅读递归收集页面、合并命名 bug 修复；滚动速度手动输入、视图选择自动关闭、长操作保持屏幕常亮。

---

## 9. 迭代 2 · P0：测试问题修复

### 9.1 手柄按键不触发映射动作（只有方向键/摇杆有反应）

**现象**：连接手柄后，只有 DPAD 和摇杆的上下有反应；A/B/Y/肩键不触发映射。

**诊断**：手柄的按键事件被 Android/Flutter 的**焦点导航**接管（用户可观察到手柄能移动焦点、A 键触发焦点控件），没有到达阅读器的 `KeyboardListener` 分发链。迭代 1 依赖 Flutter KeyEvents 传递手柄按键的方案在真机上不成立。

**修复方案**：回到迭代 1 文档中放弃的平台通道方案（现在有了必须用它的事实依据）：

> 迭代 3 修订：按键分类最终改为**按键码优先**（手柄/媒体/DPAD 的按键码区间），`SOURCE_*` 标志仅作兜底，详见 12.2 #5。

1. `MainActivity` 重写 `dispatchKeyEvent`：
   - 手柄按键（`InputDevice.SOURCE_GAMEPAD`）与媒体键：直接转发到新 `EventChannel("venera/keys")` 并**消费**（返回 true），阻止进入焦点导航；
   - DPAD：阅读器内转发+消费（防止焦点移动），阅读器外放行；
   - 音量键：保持原版音量键翻页逻辑优先；
   - Back/Menu：永远放行。
2. 键盘按键继续走 Flutter `KeyboardListener`（迭代 1 的 Dart 分发逻辑保留）。
3. Dart 侧 `hardware_keys.dart` 增加通道监听（迭代 1 已写好 `HardwareKeyListener` 类似物，需恢复），事件归一化为 `HardwareKey`（手柄/媒体键来自通道，键盘来自 Flutter 事件），统一进 `inputKeyMap` 分发。
4. 映射页的"监听绑定"弹窗需同时订阅通道与 Flutter 按键，任意来源都可绑定。

### 9.2 Hardware Key Mapping 页崩溃

**现象**：进入映射页抛 `RenderSliverToBoxAdapter is not a subtype of RenderBox?`。

**原因**：映射页把 `ListTile.toSliver()` 等塞进 `SmoothCustomScrollView` 时与其他盒级组件混用（页面未按该组件要求的 Sliver 结构组织）。

**修复**：改为普通 `ListView`（每行一个动作 ListTile，绑定用 ActionChip），不依赖 SmoothCustomScrollView；配合 9.1 的双来源监听重构绑定弹窗。

### 9.3 新功能未汉化

**修复**：迭代 1 新增的所有字符串（"Auto Scroll"、"Hardware Key Mapping"、动作名、设置项标题等）补充 zh-CN / zh-TW 翻译，走项目现有 `translations.dart` 机制。

---

## 10. 迭代 2 · 功能 A：自动播放模式切换（设置项）

**需求**：条漫（连续模式）下，"自动播放"支持两种模式并可在设置中切换：

- `smoothScroll`（迭代 1 实现，默认）：恒速平滑滚动
- `pageTurning`：原版行为，按 `autoPageTurningInterval` 定时整屏翻页

**设计**：

- 新设置项 `autoPlayMode`（`getReaderSetting` 体系，支持按漫画设置）：`smoothScroll | pageTurning`，仅连续模式显示。
- `toggleAutoPlay()` 按当前设置分发：连续模式且 `smoothScroll` → 引擎开关；否则走原 `autoPageTurning()` 定时器。
- 章末行为、触摸暂停/恢复仅对 `smoothScroll` 模式有意义；`pageTurning` 沿用原版"到 maxPage 停止"。
- 手柄 `toggleAutoScroll` 动作同样按该设置分发。
- 底栏按钮 tooltip 显示当前模式（"自动滚动" / "自动翻页"）。

## 11. 迭代 2 · 功能 B：书架 + 阅读页切本

### 11.1 书架（独立容器）

> ⚠️ 迭代 3 修订：手动拖拽排序已移除，新增合并/视图模式/选择模式，详见第 12 节。

- **入口**：首页侧边栏新增"书架"项。
- **数据**：新建 `BookshelfManager`（仿 `LocalFavoritesManager`），持久化为有序漫画 id 列表（`{comicId, comicType, addedAt, sortOrder}`），存 `appdata` 旁的独立 JSON，支持 WebDAV 同步可后议。
- **导入**：书架页顶部按钮复用首页"本地导入"的导入流程（目录/压缩包选择 → `LocalManager` 导入），导入成功后自动加入书架；另支持从本地列表/收藏页多选加入（长按/多选菜单，实现时确认现有页面多选能力）。
- **排序**：
  - 手动：长按拖拽，顺序持久化（`sortOrder`）；
  - 自动：添加时间 / 名称 / 最近阅读时间，选一种为当前排序模式（`sortMode` 设置），手动排序仅在 `manual` 模式下可用，切换自动模式不破坏手动顺序的存储。
- **页面能力**：封面网格展示（复用现有漫画 tile 组件）、点击进入阅读（带历史进度）、移出书架。

### 11.2 阅读页切本（首/末页按钮扩展）

**现状**：阅读器底栏进度条两端的按钮 = 跳第一页 / 最后一页。

**扩展**：
- 已在第一页再按左按钮 → 切到书架顺序中的**上一本**；已在最后一页（或章末评论页）再按右按钮 → **下一本**。
- **顺序来源**：书架 `sortOrder`。当前阅读的漫画不在书架中时，两按钮保持原行为（无切本），不弹提示。
- **切本实现**：`Navigator.pushReplacement` 新的 `Reader`（加载目标漫画的 `History`，有进度则恢复到上次看到的位置；无历史从第 1 页开始）。
- 切本时终止自动滚动/定时翻页，切过去的章节页为 1；是否在新漫画自动恢复滚动：**不做**（保持手动）。
- 到书架头/尾再按：toast 提示"已经是第一本/最后一本"。

### 11.3 任务拆分（迭代 2）

| # | 任务 | 预估 |
|---|---|---|
| T10 | 手柄平台通道 + 双来源按键分发 + 焦点策略（P0 修复 9.1） | 1.5d |
| T11 | 映射页重构（修复 9.2 崩溃）+ 绑定弹窗双来源 | 0.5d |
| T12 | 新增字符串汉化（修复 9.3） | 0.5d |
| T13 | autoPlayMode 设置与分发改造（功能 A） | 0.5d |
| T14 | BookshelfManager + 书架页 + 导入 + 排序（功能 B-1） | 2d |
| T15 | 阅读页切本（功能 B-2） | 1d |
| T16 | 回归测试（手柄焦点、书架排序、切本边界） | 1d |

约 6.5 人日。T10/T11 是 P0，先于新功能。

### 11.4 验收标准（迭代 2）

> ⚠️ 迭代 3 对其中 5、8 两条做了修订（拖拽排序已移除、切本改为跟随排序顺序），现行版本以第 12 节为准。

1. 手柄 A/B/Y/R1/L1/R2/L2 在阅读页触发映射动作；DPAD/摇杆不再移动阅读页内焦点。
2. 映射页可正常打开、绑定、删除、恢复默认，不崩溃；手柄按键可在弹窗中完成绑定。
3. 所有新设置/动作名在中文界面显示为中文。
4. 连续模式下可在设置中把自动播放切为定时翻页并正常工作。
5. ~~书架可导入本地漫画、拖拽排序、切换自动排序~~（迭代 3：拖拽排序移除，排序=添加时间/名称/最近阅读+逆序）；重启后排序保持。
6. 阅读书架内漫画时，第一页按左按钮切上一本、最后一页按右按钮切下一本，进度正确恢复；不在书架的漫画按钮行为与原版一致。

---

## 12. 迭代 3：书架合并/封面/视图模式 + 真机回归修复

### 12.1 新功能

#### 12.1.1 阅读页"设为封面"

- 底栏工具栏新增按钮（仅 `type == ComicType.local` 显示）。
- 实现：`selectImageToData()` 取当前页图片字节 → 覆盖写回 `LocalComic.coverFile`（存在则直接覆盖；不存在则写 `cover.<ext>` 并通过 `LocalManager().add` 更新数据库 cover 字段）。
- 状态：已完成（`reader/scaffold.dart` `setAsCover()`）。

#### 12.1.2 书架合并（多本合成一本连续漫画）

- **入口**：书架长按进入选择模式，选中 ≥2 本本地漫画后顶栏出现合并按钮。
- **合并页** `BookshelfMergePage`：拖拽调整合并顺序（`ReorderableBuilder`），确认后执行合并。
- **合并规则**：
  - 每本源漫画变成新漫画的一个章节，章节标题 = 原漫画名；多章漫画展开为"原书名 - 章节名"多个章节。
  - 页面文件**移动**（`rename`，跨卷失败回退复制）到新目录的章节子目录 `0,1,2…`，不占双倍空间。
  - 新目录命名：`sanitizeFileName(第一本漫画的 directory + "_" + 本数 + "_Merge")`，重名自动追加 `_1` 后缀。
  - 封面沿用第一本漫画的封面文件。
  - 合并完成后：`LocalManager().add` 注册新漫画，`deleteComic(source, true)` 删除源漫画及其残留目录，书架中移出源漫画并加入新漫画。
- 状态：已完成（`pages/bookshelf_merge_page.dart`）。

#### 12.1.3 书架视图模式

- 设置项 `bookshelfViewMode`：`list | grid | waterfall`（默认 grid），右上角图标选择。
- 列表 = ListTile 行；网格 = `SliverGridDelegateWithComics`；瀑布流 = `MasonryGridView`。
- 状态：已完成。

### 12.2 Bug 修复（真机回归）

| # | 问题 | 修复 |
|---|---|---|
| 1 | 播放后工具栏不隐藏 | 开始自动滚动时若顶/底栏展开则自动收起 |
| 2 | 书架进漫画不全屏（侧边栏仍显示） | `Reader` 改为经 `App.rootContext` 推到根导航器（与漫画详情页路径一致） |
| 3 | 切章后虚拟返回键无反应/系统返回退出到桌面 | 同 #2，根级路由后返回键行为正确 |
| 4 | 连续模式末页显示不完整，停在倒数第二页导致"下一章按钮多次按" | `isOnLastPage` 在连续模式下按 `page >= maxPage - 1` 判定（`maxPage<=1` 时按 `>= maxPage`）；末页按钮切本、自动滚动章末共用该判定 |
| 5 | 手柄按键仍无反应 | 按键分类改为**按键码优先**（`BUTTON_A..BUTTON_MODE`=96–110、`MEDIA`=85–127、`DPAD`=19–23），不再依赖 `SOURCE_GAMEPAD` 等标志；新增 `Log.d("VeneraKeys")` 便于 `adb logcat -s VeneraKeys` 排查 |
| 6 | 长按书架弹菜单而非进入选择 | 长按进入选择模式（不弹菜单）；顶栏=数量+合并/移出/全选/关闭；点按勾选；返回键先退出选择模式 |
| 7 | 排序不能逆序 | 排序对话框中再次点击同一排序项即反转；`bookshelfSortDesc` 持久化 |
| 8 | 上一本/下一本不跟随排序 | `BookshelfManager.sortedItems()` 作为唯一排序真源（含逆序），书架页与阅读页切本共用 |

### 12.3 行为变更（破坏性）

- **移除手动拖拽排序**：书架排序仅剩 添加时间 / 名称 / 最近阅读 + 逆序；`BookshelfManager.reorder/applyManualOrder` 已删除，设置默认值 `bookshelfSortMode` 由 `manual` 改为 `addedTime`。
- 书架长按行为从"弹出菜单"变为"进入选择模式"。

### 12.4 新增/变更设置项汇总

| 设置项 | 取值 | 说明 |
|---|---|---|
| `bookshelfSortMode` | addedTime(默认) / name / lastRead | 书架排序（迭代 2 为 manual/addedTime/name/lastRead） |
| `bookshelfSortDesc` | false(默认) / true | 同项再点切换 |
| `bookshelfViewMode` | grid(默认) / list / waterfall | 书架视图 |

### 12.5 验收标准（迭代 3）

> ⚠️ 迭代 4 修订了手柄通道、网格视图样式与章末→切本逻辑，现行版本以第 13 节为准。

1. 本地漫画阅读页可将当前页设为封面，书架/本地页立即显示新封面。
2. 选择 ≥2 本本地漫画合并后：新漫画章节连续可读、顺序与拖拽一致、源漫画（目录+记录）被删除、书架替换为新漫画；重名目录自动加后缀。
3. 书架三种视图切换正常且持久；列表模式封面点击行为与行点击一致。
4. 书架进入阅读器为全屏；切章后虚拟/系统返回键都能回到书架。
5. 手柄 A/B/Y/R1/L1/R2/L2/DPAD 触发映射动作（若仍无效，通过 `adb logcat -s VeneraKeys` 判断按键是否到达原生层）。
6. 自动滚动开始后工具栏自动收起；连续模式滚到倒数第二屏即视为章末（末页按钮可切本）。
7. 排序同项再点逆序；上一本/下一本按当前排序（含逆序）顺序切换。

---

## 13. 迭代 4：手柄通道稳定性 + 视图/选择/切本逻辑打磨

### 13.1 手柄修复（两项根因）

#### 13.1.1 默认映射开箱生效

- 根因：`inputKeyMap` 默认为空 Map，`defaultInputKeyMap` 只在映射页点"重置"后才写入——未进过映射页时所有手柄/DPAD 按键无绑定。
- 修复：读取映射时，用户无自定义绑定则自动回退 `defaultInputKeyMap`（`_ReaderState._inputKeyMap`）。

#### 13.1.2 切本后按键失效（EventChannel 竞态）

- 根因：切本时 `pushReplacement` 使新 Reader 先 `listen`、旧 Reader 后 `cancel`，单 sink 的 `EventChannel` 在 cancel 时把原生层 keySink 置空，通道报废，按键回退焦点导航。
- 修复：`HardwareKeyListener` 改为**引用计数共享流**——所有监听器共用一个常驻通道订阅（`StreamController.broadcast` 分发），计数归零才真正取消通道；切本/翻章的新旧监听器交替期间通道保持有效。阅读页外（计数归零）仍恢复焦点导航。
- 调试日志：Kotlin `Log.d("VeneraKeys")`（转发）+ Dart `debugPrint`（通道接收、命中映射），`adb logcat -s VeneraKeys flutter` 可看到完整链路。

### 13.2 章末→切本逻辑全局统一

新增 `_ReaderState.toPrevChapterOrComic() / toNextChapterOrComic()`：有上一章/下一章则切章，**没有则自动变为上一本/下一本**（按书架当前排序与逆序；漫画不在书架时回退不生效，保持原版无操作）。统一应用到全部章节切换入口：

| 入口 | 行为 |
|---|---|
| 手柄/映射 `prevChapter / nextChapter` 动作 | 章末→切本 |
| 阅读页悬浮章节切换按钮（滑到章首/章末出现） | 章末→切本 |
| 音量键翻页跨章（`_VolumeListener.onDown/onUp`） | 最后/最先一章→切本 |
| 翻页模式下"上一页/下一页"到头（手柄/映射 nextPage/prevPage） | 跨章→再切本 |
| 自动滚动"章末继续"策略 | 最后一章滚动完→切下一本继续滚动 |

### 13.3 书架视图模式（重定义后落地）

| 模式 | 实现 |
|---|---|
| 列表 `list` | 原版漫画卡片视图（`ComicTile` + `SliverGridDelegateWithComics`），封面完整显示 |
| 网格 `grid` | 自绘 tile：固定 0.72 宽高比封面 + 下方文件名（超长省略号），`GridView.count` 统一格子（`childAspectRatio 0.62`，列数随屏宽自适应） |
| 瀑布流 `waterfall` | `_WaterfallTile` 按封面**真实宽高比**渲染高度（`ImageStream` 读取图片尺寸并按 `sourceKey@id` 缓存），`MasonryGridView`，列数随屏宽自适应 |

- 视图切换对话框改为 `showDialog` + `StatefulBuilder`，选择后即时生效（旧 `showPopUpWidget` 方案关闭路径有缺陷导致不刷新）。
- 排序对话框增加"逆序"开关（与"同项再点逆序"并存）。

### 13.4 选择模式打磨

- 选中样式改为在条目上**叠加**边框+对勾（迭代 3 曾错误地替换原 tile，导致选中项变黑块且无法取消选中）。
- 网格/瀑布流为自绘 tile，选中边框与内容天然对齐（不再依赖 ComicTile 的内部布局）。
- 每个条目以 `ValueKey("视图:ID:选中态")` 强制重建，切换视图时选中标记即时跟随新位置。
- 选择工具栏补齐全选 / **反选** / 全不选（菜单按钮）。

### 13.5 验收标准（迭代 4）

1. 未进过映射页的情况下，手柄 A/B/Y/R1/L1/R2/L2/DPAD 开箱即用（默认映射）。
2. 阅读页内切上一本/下一本后，手柄按键持续生效，不回退焦点模式。
3. 有下一章时切章、无下一章时切下一本——手柄翻章键、悬浮按钮、音量键、自动滚动行为一致。
4. 网格模式封面下方显示文件名（超长截断）；三种视图下选中边框与条目对齐；切换视图时选中标记即时跟随。
5. `adb logcat -s VeneraKeys flutter` 可观察到按键从原生转发到 Dart 分发的完整链路。

---

## 1. 需求概述

### 1.1 恒速平滑自动滚动

将条漫（`ReaderMode.continuousTopToBottom`，以及水平连续模式可选支持）下的"自动播放"从**定时整屏翻页**改为**恒定速度平滑滚动**：

- 速度以"**每滚动一个屏幕高度所需毫秒数**"设置（如 `5000` ms/屏），内部换算为像素速度：
  `speed = viewportHeight / msPerScreen`（px/ms）。
- 滚动过程中**不停顿**，直到章节末尾。
- 滚动为匀速，非缓动动画（缓动会导致长章前后速度不一致）。

### 1.2 章末行为（可配置）

滚动到达当前章节末尾时：

| 选项 | 行为 |
|---|---|
| `stop`（默认） | 停止自动滚动，停留在章末，等待用户手动翻章 |
| `nextChapter` | 自动调用现有 `toNextChapter()` 进入下一章，加载完成后继续滚动 |
| `nextComic` | 下一章不存在时自动退出阅读器（复用现有最后一章翻页的行为） |

### 1.3 外设按键控制（Android）

通过 Android 手柄（Xbox / PS / 通用 HID 手柄）、蓝牙或 USB 键盘、耳机线控/媒体键，执行以下动作：

- 上一页 / 下一页
- 自动滚动 开/关（**单个切换键**）
- （历史/切本功能：**本次不做**，见需求澄清记录）

注意：由于不做切本，"上一本/下一本"不在动作列表中；动作枚举预留扩展位即可。

### 1.4 自定义按键映射

- 设置界面中提供"按键映射"页：左侧列出全部可用动作，右侧显示当前绑定的按键，点击后进入**监听模式**，按下手柄/键盘任意键即完成绑定。
- 支持多设备统一映射（手柄 A 键和键盘 → 键可映射到同一动作）。
- 不支持长按连发（每次按下仅触发一次，见澄清记录）。
- 提供清除绑定、恢复默认操作。

---

## 2. 澄清结论记录（已确认）

| 问题 | 结论 |
|---|---|
| 时间(ms) 语义 | 恒定速度，设置单位为"每屏毫秒数" |
| 章末行为 | 可配置（停 / 下一章 / 退出） |
| 平台 | 仅 Android 优先；实现上尽量不写死平台，桌面端天然兼容键盘部分 |
| 上一本/下一本 | **不做**（原版无切本功能） |
| 外设范围 | 手柄 + 键盘 + 媒体键 |
| 长按连发 | 不支持 |
| 自动播放/暂停 | 单键开/关切换 |

---

## 3. 现有代码分析

| 现状 | 位置 | 说明 |
|---|---|---|
| 自动翻页 | `lib/pages/reader/reader.dart:716` `autoPageTurning()` | `Timer.periodic` + `toNextPage()`，条漫下即整屏跳动，无平滑 |
| 自动翻页开关 | `lib/pages/reader/scaffold.dart` 菜单项 | 调用 `autoPageTurning(cid, type)` 切换 |
| 条漫渲染 | `lib/pages/reader/images.dart:657` `_ContinuousModeState` | `ScrollController` 驱动的 `ListView`（`images.dart:851`） |
| 硬件按键先例 | `reader.dart` `handleVolumeEvent()` / `stopVolumeEvent()` | 音量键翻页，走 EventChannel 监听原始按键，可参考其生命周期管理 |
| 设置存储 | `lib/foundation/appdata.dart:191` | `appdata.settings`；另有按漫画的 `getReaderSetting(cid, sourceKey, key)` 分漫画设置 |
| 阅读设置 UI | `lib/pages/settings/reader.dart`（全局）、`lib/pages/reader/scaffold.dart:690` `ReaderSettings`（阅读器内侧边栏） | 两种设置入口都需加新项 |
| 翻章 | `lib/pages/reader/scaffold.dart` `toNextChapter()` 等 | 章末自动行为直接复用 |

关键结论：

1. **连续模式没有"页"的概念**，`page` 是按 `imagesPerPage` 折算的虚拟页。自动滚动基于 `ScrollController` 偏移量驱动，与 `page` 的同步需通过现有滚动监听（`images.dart` 中已有滚动位置→页码的回写逻辑）完成，进度记录/恢复不受影响。
2. 音量键事件链路证明"在阅读器页面持有原始 KeyEvent 监听"在本项目是成立的，手柄方案采用同一思路，无需第三方插件（`gamepads` 等可以避免引入）。

---

## 4. 方案设计

### 4.1 恒速平滑滚动（核心）

新增 `lib/pages/reader/auto_scroll.dart`：

```dart
/// 驱动 _ContinuousModeState 的 ScrollController 做恒速滚动。
/// 使用 Ticker (SchedulerBinding.addTimedCallbacks / vsync) 而非 Timer，
/// 逐帧 position = position + speed * dt，掉帧时按真实 dt 补偿，速度恒定。
class AutoScrollController {
  final ScrollController controller;
  final double Function() viewportHeight;   // 取 viewportDimension
  final int msPerScreen;                    // 设置项
  final VoidCallback onReachEnd;            // 章末回调（执行章末策略）
  bool get isRunning;
  void start();   // 从当前位置继续
  void pause();   // 暂停，保留位置
  void toggle();
  void stop();    // 彻底停止并重置
  void dispose();
}
```

要点：

- 每帧调用 `controller.jumpTo(position + speed * dt)`；对条漫这种连续 ListView，逐帧 jumpTo 与 `ScrollPosition` 动画相比更可控，且能即时响应手势打断。
- 到达 `position.maxScrollExtent` 时触发 `onReachEnd`。
- **与手势的冲突**：用户触摸/捏合时自动暂停（挂 `ScrollNotification` 监听，`ScrollStartNotification` 由用户拖动发起时 `pause()`，提供"触摸后是否恢复"由开关决定，默认不自动恢复）。
- **与图片加载的关系**：滚动速度过快时预加载跟不上。现有 `_ContinuousMode` 已有 `enableResize` 与预加载逻辑；若滚动中底部出现加载占位，速度不变直接滚过（图片异步加载完成后自然显示）。
- **翻页联动**：滚动过程中不调用 `toNextPage()`；页码由现有滚动回写逻辑自动更新，保证历史进度与 UI 页码指示正确。
- 旧 `autoPageTurning()`：在连续模式下改为启动平滑滚动；页图模式（galleryLeftToRight 等）保留原定时翻页行为不变。

### 4.2 章末策略

`AutoScrollController.onReachEnd` 触发后按设置项 `autoScrollOnChapterEnd`（`stop | nextChapter`）执行：

- `stop`：`stop()`，如当前是最后一章则同样停留。
- `nextChapter`：调用 `reader.toNextChapter()`；若无下一章，沿用阅读器现有的"最后一章结束"行为（提示并退出，或在章末评论区停下）。滚动状态在章切换时随 `_ContinuousModeState` 重建而重置，若设置允许则在新章 `didUpdateWidget`/首帧后自动重新 `start()`。

> 备注：澄清中选择了"做成可配置"，默认值取 `stop`，`nextComic`（退出阅读器）作为 `nextChapter` 在最后一章时的自然延伸，不单列设置项，如需独立开关在评审时提出。

### 4.3 输入事件层（手柄/键盘/媒体键）

新增 `lib/foundation/input_events.dart` + Android 平台通道：

- 参考 `handleVolumeEvent()` 的实现方式，通过 `EventChannel` 从 Android 侧转发 `KeyEvent`（`dispatchKeyEvent` 中未消费的按键：`KeyEvent.KEYCODE_BUTTON_*`、`KEYCODE_DPAD_*`、键盘键、媒体键 `KEYCODE_MEDIA_PLAY_PAUSE` 等）。
- Dart 侧将平台事件归一化为 `InputKey` 标识：`{ source: gamepad|keyboard|media, code: <android keycode int 或统一名> }`。
- 按键分发器 `InputActionMapper`：
  - 维护 `Map<InputKey, InputAction>`；
  - `InputAction` 枚举：`prevPage / nextPage / toggleAutoScroll / prevChapter / nextChapter`（`prev/nextComic` 预留但不实现功能）；
  - 命中映射则 `reader` 执行对应动作并**消费事件**（返回 true，避免触发系统返回等），未命中则走原有手势/按键逻辑。
- 生命周期：进入阅读器页面注册，`dispose` 注销；音量键翻页开启时与映射并存，音量键不参与映射（保持原有 `enableTurnPageByVolumeKey` 逻辑，避免双重消费）。
- 桌面端：Flutter `Focus`/`KeyboardListener` 可顺带支持键盘映射（低优先级，本次不承诺）。

### 4.4 按键映射 UI 与存储

- 设置项（全局，`appdata.settings`）：

  ```json
  "autoScrollMsPerScreen": 5000,
  "autoScrollOnChapterEnd": "stop",
  "autoScrollResumeAfterTouch": false,
  "inputKeyMap": { "<source>:<code>": "<action>", ... }
  ```

  > 说明：滚动速度属于阅读体验，若希望像 `autoPageTurningInterval` 一样支持"每本漫画独立设置"，可改存 `getReaderSetting` 体系，评审时定；默认先做全局。

- UI（`lib/pages/settings/reader.dart` 中新增区块 + 阅读器内侧边栏 `ReaderSettings` 同步展示速度项）：
  - "自动滚动速度（ms/屏）"：`Select`/滑杆，范围建议 1000–60000，步进 500；
  - "章末行为"：`stop / nextChapter` 三选一；
  - "按键映射"入口 → 新页面 `KeyMappingPage`：
    - 列表展示动作 → 当前绑定（图标化显示按键名，如 `Gamepad A`、`DPAD Left`）；
    - 点击条目进入监听弹层："请按下要绑定的按键…"，收到第一个事件即写入并返回（同键重复绑定同一动作为覆盖；同一动作允许多键绑定）；
    - 长按条目删除绑定；`恢复默认` 按钮写入默认映射表（见 §6 默认值）。

### 4.5 阅读器动作接线

`lib/pages/reader/reader.dart` 增加：

```dart
void handleInputAction(InputAction action) {
  switch (action) {
    case InputAction.nextPage: toNextPage();
    case InputAction.prevPage: toPrevPage();
    case InputAction.toggleAutoScroll: autoScroll.toggle();
    ...
  }
}
```

- 连续模式下 `toNextPage/prevPage` 保持现有语义（滚动一个视口高度，带动画）。
- 工具栏/菜单中"自动播放"按钮文案在连续模式下显示"自动滚动"，行为切到 `autoScroll.toggle()`。

---

## 5. 开发任务拆分

| # | 任务 | 涉及文件 | 预估 |
|---|---|---|---|
| T1 | 设置项与默认值（含迁移：老设置无新 key 时用默认值） | `appdata.dart` | 0.5d |
| T2 | `AutoScrollController`（Ticker 恒速滚动、暂停/恢复、章末回调、手势打断） | 新增 `reader/auto_scroll.dart` | 1.5d |
| T3 | 接入 `_ContinuousModeState` 与 `reader.dart`（连续模式下 autoPageTurning 切换为平滑滚动；页图模式不变） | `images.dart`, `reader.dart`, `scaffold.dart` | 1d |
| T4 | 章末策略（stop / nextChapter + 最后一章行为） | `reader.dart`, `scaffold.dart` | 0.5d |
| T5 | Android 平台 KeyEvent 通道 + `InputKey` 归一化 | `android/.../MainActivity.kt`(或 java), 新增 `foundation/input_events.dart` | 1.5d |
| T6 | `InputActionMapper` 分发 + 阅读器动作接线 + 与音量键链路的共存/互斥 | `foundation/input_events.dart`, `reader.dart` | 1d |
| T7 | 设置 UI（速度、章末行为）+ 阅读器内侧边栏同步 | `settings/reader.dart`, `reader/scaffold.dart` | 0.5d |
| T8 | 按键映射页（监听绑定、覆盖、删除、恢复默认） | 新增 `settings/key_mapping.dart` | 1d |
| T9 | 测试与打磨（真机手柄：Xbox 蓝牙、PS、键盘、线控；掉帧补偿；进度记录正确性） | — | 1.5d |

总计约 9 人日。T2–T4（平滑滚动）与 T5–T6（输入层）可并行开发。

### 验收标准

1. 条漫模式下开启自动播放后，画面以恒定速度平滑滚动，无整屏跳动；改变"ms/屏"设置立即生效（或下次开启生效，需在评审中定）。
2. 触摸屏幕时滚动暂停，不与手势缩放冲突。
3. 章末按所选策略执行；`nextChapter` 模式跨章滚动连续可用。
4. 手柄 A/B（示例默认映射）可翻页；专用键可开/关自动滚动；映射可在设置中自定义并持久化。
5. 非映射按键不干扰原有关闭菜单、返回等手势；音量键翻页功能不受影响。
6. 阅读进度（history.page）在自动滚动过程中被正确记录。

---

## 6. 默认按键映射（建议初值，可在 UI 中改）

| 按键 | 动作 |
|---|---|
| 手柄 A / 键盘 Space | 下一页 |
| 手柄 B / 键盘 ← → | B：上一页；← 上一页、→ 下一页 |
| 手柄 RT / →（DPAD Right） | 下一页 |
| 手柄 LT / ←（DPAD Left） | 上一页 |
| 手柄 Y / 键盘 P | 开/关自动滚动 |
| 手柄 RB | 下一章 |
| 手柄 LB | 上一章 |

> 具体默认值评审时定，原则：方向键翻页、肩键翻章、Y/媒体播放键控制自动滚动。

---

## 7. 可直接复用的代码清单（已核对源码）

| 复用点 | 位置 | 用法 |
|---|---|---|
| 按键 EventChannel 脚手架 | `lib/utils/volume.dart`、`MainActivity.kt:143`（`EventChannel("venera/volume")`）、`MainActivity.kt:205`（`onKeyDown`） | 照抄结构新建 `venera/keys` 通道；`onKeyDown` 的 `when` 分支扩展为转发手柄/键盘/媒体键码；Dart 侧照 `VolumeListener` 写 `InputKeyListener` |
| 章末检测 | `images.dart:805` `onScroll`（`prepareToNextChapter`/`jumpToNextChapter`/`maxScrollExtent`） | 恒速滚动触发边缘逻辑即可翻章，无需重写判断 |
| 进度同步 | `images.dart:710` `itemPositionsListener` → `onPositionChanged` | 基于滚动位置驱动，恒速滚动下进度记录自动正确，零改动 |
| 阅读器动作 | `reader.dart` `toNextPage/toPrevPage/toNextChapter/toPrevChapter` | 手柄映射的动作终点，直接调用 |
| 按漫画设置体系 | `appdata.dart` `getReaderSetting(cid, sourceKey, key)` | "ms/屏"如需按漫画记忆可直接挂入 |
| 设置项 UI 样板 | `settings/reader.dart:222` `autoPageTurningInterval` | 照抄为"自动滚动速度(ms/屏)"项 |
| 自动播放 toggle UX | `reader.dart:716` `autoPageTurning()`、`scaffold.dart` 菜单入口 | 保留入口，连续模式下内部实现换成平滑滚动 |

真正需要新写的只有三块：`AutoScrollController`（Ticker 恒速引擎）、按键码归一化 + `InputActionMapper`、按键映射页 UI 与 `inputKeyMap` 存储。

---

## 8. 风险与开放问题

1. **恒速滚动与图片预加载**：高速滚动时网络源图片加载跟不上，会出现空白占位。是否需要"检测到下方图片未加载完成时自动降速/暂停等待"的选项？（建议先不做，观察实际体验）
2. **水平连续模式**（`continuousLeftToRight/RightToLeft`）是否同样启用平滑滚动？实现对称，建议一并支持，成本 +0.5d。
3. **设置生效时机**：滚动中修改 ms/屏是立即变速还是下次生效（立即变速实现简单，建议立即）。
4. **Android 事件通道改动**：`MainActivity` 需要覆盖 `dispatchKeyEvent`，需确认项目 Android 壳工程结构（venera 的 android 目录为标准 Flutter 工程，改动小）。
5. 阅读器内侧边栏是否需要快捷"自动滚动速度"调节（建议先只放全局设置 + 侧边栏速度项）。

---

## 14. 迭代 5–6：合并/导入/删除的打磨与根因修复（v1.7.0）

### 14.1 合并：进度百分比 + 修 ANR 闪退

- 根因：合并的文件移动/复制是同步 IO 且全在主线程执行，漫画大时主线程长时间阻塞触发 ANR 被系统强杀（"有几率闪退"）。
- 修复：目录扫描留在主线程（轻量），页面文件移动按**文件粒度**分批（每 100 文件一批）在 isolate 中执行，批间回报进度；合并页显示大字号百分比 + 进度条 + "已处理页数/总页数"。

### 14.2 导入：跳过同名 + 进度条

- **跳过同名**（按文件夹/漫画名判断，覆盖全部导入路径）：归档导入从"抛异常中断"改为跳过继续；目录/EhViewer/本地恢复原本就按名跳过，现在统一计数；复制到本地目录时同名目录**跳过**（原版会把已存在目录改名挪走，有数据风险）。结束后提示"已跳过 N 个已存在的漫画"。
- **进度条**：复用 `showLoadingDialog(withProgress: true)`，多压缩包/多目录/EhViewer/本地恢复按项更新"导入中 i/N (xx%)"；复制到本地目录改为一本一 isolate，报"复制中 i/N (xx%)"。

### 14.3 本地删除：三轮修复终局

| 轮次 | 问题 | 根因 | 修复 |
|---|---|---|---|
| 1 | 删除后磁盘文件没删 | 删除在 `Isolate.run` 中 fire-and-forget，且 isolate 内 `SAFTaskWorker().init()`（平台通道）抛错导致整个删除静默死亡；错误被吞 | 改为逐本 isolate + 等待完成 + 进度回调 |
| 2 | 进度框没弹、确认框不自动关闭 | `pop()` 关闭的是栈顶路由——先弹进度框再 `pop()` 会把进度框自己关掉 | 恢复"先关确认框、再弹进度框"顺序 |
| 3 | SAF 漫画删除后文件仍在（日志见 `android://primary:...` 路径删除失败） | 两层：a) `directory` 为绝对路径时拼错位置；b) **SAF 路径删除必须在主线程**（flutter_saf 的授权注册表在主 isolate，后台 isolate 解析不到），且应使用 flutter_saf 原生递归删除 | 使用 `c.baseDir` + `overrideIO` 包裹 + flutter_saf 原生 `delete(recursive: true)`；收藏/历史清理包 try/catch 不再阻断文件删除；删完校验残留并弹专项提示 |

### 14.4 SAF 授权丢失（重要运维知识）

`android://primary:...` 路径依赖 Android 的 SAF 持久授权。**每次重装应用（含覆盖安装的某些场景）都会清空授权**——本仓库包名为 `.mod`，与官方版授权互不继承，且开发期反复重装导致授权频繁丢失。授权丢失后该目录的读取/写入/删除全部失败（日志特征：`Cannot create directory specified`）。

恢复方式：首页 → 导入 → 多本目录 → 重新选择该目录（重新授权）。已注册的同名漫画会被跳过，被删除记录的漫画会重新导入。

### 14.5 其他修复

| 问题 | 修复 |
|---|---|
| `Rhttp.init` 失败（codegen 2.11.1 vs runtime 2.13.0） | `pubspec.yaml` 增加 `dependency_overrides: flutter_rust_bridge: 2.11.1`（升级 Flutter 后 pub 解析越过了 rhttp 生成代码的兼容范围） |
| 进阅读器必现 `markAsRead` 空指针（上游 bug） | `followUpdatesFolder` 为 null 时提前返回 |
| 列表/网格封面裁切 | 网格与列表封面改 `BoxFit.contain`（长边贴边完整展示），瀑布流本为原始比例 |
| 自动播放时熄屏 | 启用原版预留的 `setScreenOn` 平台通道：自动滚动/定时翻页运行期间保持屏幕常亮，停止/退出恢复 |
| 映射动作增加返回键 | `InputAction.back`，触发关闭阅读页 |
| 合并进度/删除进度框一闪而过 | 进度对话框加最短显示时长（600ms） |

### 14.6 版本与发布

- 版本号策略：每次出包，版本号最后一位 +1、构建号 +1（`1.6.3+163` → … → `1.7.0+170`）。
- v1.6.3 已发布至 GitHub Releases（4 APK + Windows zip）；v1.7.0 发布包含本轮全部修复。
- 产物命名：`venera-<版本>-<架构>.apk`（通用版无架构后缀）、`venera-mod-windows-x64.zip`。

---

## 15. 迭代 7：结构化导入（v1.7.2）

### 15.1 结构分析工具

新增 `lib/utils/comic_structure.dart`：

- `analyzeComicStructure(dir)`：单链下钻（每层仅 1 个子目录且无图片 → 继续深入）定位内容根；内容根有 ≥2 个子目录即判定为分支（多章节）结构。
- `collectComicImages(dir)`：递归收集图片（排除 `cover.*` 与隐藏文件），自然排序（数字按数值比较，"2" < "10"）。
- `pathRelativeTo` / `naturalCompare` 等辅助。

### 15.2 压缩包导入（CBZ.import 重写）

| 压缩包结构 | 导入结果 |
|---|---|
| 多层单链嵌套（a/b/c/图片） | 拍平为单章漫画，以压缩包名为漫画名 |
| 分支结构（同级多个子目录） | 多章节漫画：第一层 = 漫画名目录，第二层 = `0,1,2...` 章节目录（与合并结果一致），章节名 = 原文件夹名，按名称排序 |
| 含 metadata.json 章节定义 | 兼容保留（按 start/end 拆分） |
| 分支层散落图片 | 并入首个章节 |

页面文件从解压缓存**移动**（跨卷回退复制）到目标目录。

### 15.3 目录导入（_checkSingleComic 重写）

- 同样的单链下钻 + 分支判断；分支 → 章节目录使用**原始文件夹名**（不移动用户文件），`ComicChapters` 以目录名为 ID。
- 取消"章节目录下还有子目录即无效"的规则。
- 漫画 `directory` 字段指向内容根（下钻后），配合递归 `getImages` 支持深层页面。

### 15.4 本地阅读递归化

`LocalManager.getImages` 改为递归收集页面文件（排除 `cover.*` 与隐藏文件），自然排序。旧格式漫画（章节内无嵌套）行为不变；新结构（嵌套单链、深层页面）可正常阅读。

### 15.5 合并命名修复

合并命名中的第一本漫画 `directory` 可能为绝对路径（未复制导入），原逻辑会生成"完整路径_2_Merge"名称。现仅取路径最后一段。

### 15.6 其他（同版本）

- 滚动速度设置：滑杆 + 点击数值手动输入（100–600000 ms，支持按漫画设置）
- 书架视图模式选择后对话框自动关闭
- 导入 / 合并 / 删除等长操作期间保持屏幕常亮（`setScreenOn`，`utils/io.dart` 通用助手）
- 本地删除进度框顺序修复（`pop()` 会关闭栈顶路由，须先关确认框再弹进度框）
