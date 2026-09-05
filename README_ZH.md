# Venera Mod

> 本项目 fork 自 [venera-app/venera](https://github.com/venera-app/venera)（GPL-3.0）。原项目是一个支持阅读本地与网络漫画的阅读器，现已被作者归档停止维护。本仓库在其基础上继续开发，新增了自动滚动、手柄支持与书架管理等功能。

[![License](https://img.shields.io/github/license/venera-app/venera)](https://github.com/venera-app/venera/blob/master/LICENSE)

## 在原版基础上的改动

### 阅读体验

- **条漫恒速平滑自动滚动**：连续阅读模式下，自动播放从定时整屏翻页升级为按恒定速度平滑滚动（每帧按真实耗时补偿，不受掉帧影响）
  - 滚动速度可调：以"每滚动一屏所需毫秒数"设置（1000–60000 ms）
  - 触摸自动暂停，可选"抬手后自动恢复"
  - 章末行为可配置：停下等待 / 自动进入下一章（最后一章滚动完可接续下一本）
  - 自动播放模式可在设置中切换：平滑滚动 / 原版定时翻页
- **设为封面**：本地漫画阅读页可一键将当前页设为漫画封面
- **末页判定优化**：连续模式下倒数第二屏即视为章末（末页常因高度不足无法完整显示）

### 外设支持

- **手柄/键盘/媒体键控制**（Android）：蓝牙或 USB 手柄、键盘、耳机线控均可控制阅读
  - 可映射动作：上一页、下一页、开/关自动播放、上一章、下一章
  - 自定义按键映射：设置 → 阅读 → 硬件按键映射，点按动作后按任意键即完成绑定，支持删除与恢复默认
  - 开箱即用的默认映射（A/B/肩键翻页、Y 与耳机播放键开自动滚动、DPAD 方向翻页）
  - 通过平台通道拦截手柄按键，不干扰系统焦点导航；音量键翻页等原功能不受影响

### 书架管理

- **独立书架**：导航面板新增书架页，支持与首页一致的本地漫画导入流程，导入后自动加入书架
- **多种排序**：添加时间 / 名称 / 最近阅读时间，支持正序与逆序，排序设置持久化
- **三种视图**：列表（原版卡片视图）/ 网格（统一尺寸 + 文件名）/ 瀑布流（按封面真实宽高比）
- **多选操作**：长按进入选择模式，支持全选 / 反选 / 全不选、移出书架
- **漫画合并**：多选本地漫画后可拖拽调整顺序并合并为一本连续漫画——每本源漫画成为新漫画的一个章节，文件直接移动不占双倍空间，合并后自动清理源漫画
- **连续阅读**：阅读书架内漫画时，第一页再按"跳首页"切上一本、最后一页再按"跳末页"切下一本（跟随书架当前排序，自动恢复阅读进度）；所有章节切换入口（手柄翻章键、悬浮按钮、音量键、自动滚动章末）在没有上一章/下一章时自动变为切本

### 界面

- 上述所有新功能均提供简体中文 / 繁体中文 / 英文界面

## 与官方版的差异

- 包名为 `com.github.wgh136.venera.mod`，可与官方版共存
- 无发布签名时自动使用 debug 密钥签名（本地构建友好；升级覆盖安装需保持同一密钥）
- 与官方版数据完全独立（历史记录、收藏、漫画源配置不互通），可使用原版的数据同步功能迁移

## 从源码构建

1. 克隆本仓库
2. 安装 Flutter（≥3.41，参见 [flutter.dev](https://flutter.dev/docs/get-started/install)）与 Rust（参见 [rustup.rs](https://rustup.rs/)）
3. Android 构建需安装 Android SDK（含 NDK）
4. 构建：`flutter build apk --release`（或指定架构 `--target-platform android-arm64`）

> 详细的功能设计与开发记录见 [docs/dev-plan-auto-scroll-gamepad.md](docs/dev-plan-auto-scroll-gamepad.md)；全部改动的实施明细（目的 / 实现 / 影响追溯）见 [docs/implementation-notes_zh.md](docs/implementation-notes_zh.md)（[英文版](docs/implementation-notes_en.md)）。

## 许可证

本项目沿用原项目的 [GPL-3.0](LICENSE) 许可证。

## 致谢

- [venera-app/venera](https://github.com/venera-app/venera) —— 本项目的基座
- [EhTagTranslation](https://github.com/EhTagTranslation/Database) —— 漫画标签中文翻译
