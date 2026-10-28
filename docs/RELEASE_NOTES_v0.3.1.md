# LiveHime macOS v0.3.1

v0.3.0 的修复版。/ A fix on top of v0.3.0.

## 下载哪个文件 / Which file to download

| 文件 / File | 给谁用 / For |
|---|---|
| **`LiveHime-v0.3.1-Installer.pkg`** | **不知道选哪个就下载这个。** 所有 Mac，双击后一路“继续”，自动选芯片 / Not sure? This one. Any Mac |
| `LiveHimeMacApp-v0.3.1-arm64.dmg` | Apple 芯片（M 系列），打开后拖进“应用程序” / Apple silicon, drag to install |
| `LiveHimeMacApp-v0.3.1-x86_64.dmg` | Intel 芯片，打开后拖进“应用程序” / Intel, drag to install |
| `LiveHimeMacApp-v0.3.1-*.zip` | 应用内更新用的，不用手动下载 / for the in-app updater |
| `addons.json` | 浏览器组件的清单，应用自己读取，不用手动下载 / the browser add-on list, read by the app |
| Source code (zip / tar.gz) | 源代码，**不是软件**，装软件不要下载 / source code, **not the app** |

安装包没有 Apple 的付费开发者签名。双击时如果提示“无法打开”，到 **系统设置 → 隐私与安全性** 点“仍要打开”，
第一次打开应用时如果被拦也一样。详细步骤见 [README](../README.md#下载与安装--download-and-install)。
Not signed by Apple: if macOS blocks the installer or the app, click **Open Anyway** in System Settings → Privacy & Security.

## 修复 / Fixes

- 在 macOS 27 上点击屏幕顶部菜单栏里的 LiveHime 图标，应用会直接退出（“LiveHime 意外退出”）。
  原因在应用自带的 Qt 6.11.1：macOS 27 改变了菜单栏按钮处理点击的方式，Qt 却仍把当时的事件当作鼠标事件读取。
  现在应用带的是打了 Qt 官方修复的版本，菜单栏图标和它的菜单（显示/隐藏、开始直播、退出等）恢复正常。
  感谢 @wutongyuonce 在 [#1](https://github.com/greyoak111/livehime-macos/issues/1) 里附上崩溃报告和上游修复的线索。
  On macOS 27, clicking LiveHime's icon in the menu bar quit the app ("LiveHime quit unexpectedly"). The cause was the
  bundled Qt 6.11.1: macOS 27 changed how menu bar buttons handle clicks, and Qt still read the event of the moment as a
  mouse event. The app now bundles Qt with the official Qt fix, and the menu bar icon and its menu (Show/Hide, Start
  Streaming, Quit…) work again. Thanks to @wutongyuonce for the crash reports and the pointer to the upstream fix in #1.

## 升级 / Upgrade

v0.2.8 及以后的版本会在应用里收到这次更新，也可以手动下载安装包或 DMG 替换。
没有升级 OBS，不迁移设置，登录和设置都会保留；已安装的浏览器组件继续可用，不用重新下载。
From v0.2.8 on the app offers this update, or install the pkg or DMG by hand.
OBS is not upgraded; no settings migrate; your login and settings are kept. An installed browser add-on keeps
working and is not downloaded again.

## 验证 / Validation

- 维护者在 macOS 27 上反复左键、右键点击菜单栏图标，没有崩溃，菜单正常展开，显示/隐藏正常。
  The maintainer clicked the menu bar icon repeatedly (left and right) on macOS 27: no crash, the menu opened,
  Show/Hide worked.
- 修复后的 Cocoa 插件与 obs-deps 原版导出、导入的符号完全一致，同为 Qt 6.11.1；两个架构的应用里都确认是打过补丁的版本。
  The patched Cocoa plugin exports and imports exactly the same symbols as the obs-deps original (both Qt 6.11.1),
  and both apps were checked to bundle the patched one.
- 端到端测试：更新说明 15/15、应用更新 21/21、浏览器组件 18/18、推流 14/14、悬浮弹幕 16/16（“隐藏 OBS”两种模式）。
  更新说明第一次运行有 6 项因测试时序失败，手动复现正常，重跑全部通过；浏览器组件第一次运行因本机已装组件不满足前提，重跑全部通过。
  End-to-end: What's New 15/15, updates 21/21, add-on 18/18, streaming 14/14, floating chat 16/16 (with and without
  "Hide OBS"). What's New failed 6 checks on its first run from test timing (fine by hand, all passed on a rerun); the
  add-on test first ran with the add-on already installed, against its precondition, and passed on a rerun.
- Swift core：112 个测试，111 个通过，1 个需要联网的测试跳过。
  Swift core: 112 tests, 111 passed, 1 network-gated skipped.
- 签名、架构、Bundle ID 检查通过，和 v0.3.0 使用同一张签名证书；应用包里没有账号数据；安装包检查通过；
  v0.3.0 的浏览器组件对两个新应用的检查都通过；补丁 0001–0065 在上游 `32.2.2` 上还原出发布用的代码树。
  Signature, architecture and bundle id checks passed; same signing certificate as v0.3.0; no account data in the
  bundle; the installer check passed; the v0.3.0 browser add-on checks pass against both new apps; patches 0001–0065
  reproduce the released tree on upstream `32.2.2`.
- 本次没有重跑字幕、SRT、全屏置顶测试（改动只涉及菜单栏图标）。
  The captions, SRT and full-screen pinning tests were not rerun for this release (the change only concerns the menu
  bar icon).

## 源码 / Source

基于上游 OBS Studio `32.2.2`（`ba2f32bdf`）的补丁系列在 [`obs-fork/`](../obs-fork/)：两个架构都对应补丁 0001–0065（0060、0061 只改测试）。
0064 的构建脚本从 Qt 官方源码 qtbase 6.11.1 编出打了补丁的 Cocoa 插件（补丁在 `build-aux/livehime/qt/`）。
浏览器组件没有变化，仍是 v0.3.0 发布的 v1.0.0。
The patch series on upstream OBS Studio `32.2.2` (`ba2f32bdf`) is in [`obs-fork/`](../obs-fork/): patches 0001–0065
for both architectures (0060 and 0061 change only tests). 0064's build script builds the patched Qt Cocoa plugin from the
official qtbase 6.11.1 source (the patch is in `build-aux/livehime/qt/`). The browser add-on is unchanged: v1.0.0 from
the v0.3.0 release.
