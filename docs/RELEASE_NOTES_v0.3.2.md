# LiveHime macOS v0.3.2

v0.3.1 的修复版。/ A fix on top of v0.3.1.

## 下载哪个文件 / Which file to download

| 文件 / File | 给谁用 / For |
|---|---|
| **`LiveHime-v0.3.2-Installer.pkg`** | **不知道选哪个就下载这个。** 所有 Mac，双击后一路“继续”，自动选芯片 / Not sure? This one. Any Mac |
| `LiveHimeMacApp-v0.3.2-arm64.dmg` | Apple 芯片（M 系列），打开后拖进“应用程序” / Apple silicon, drag to install |
| `LiveHimeMacApp-v0.3.2-x86_64.dmg` | Intel 芯片，打开后拖进“应用程序” / Intel, drag to install |
| `LiveHimeMacApp-v0.3.2-*.zip` | 应用内更新用的，不用手动下载 / for the in-app updater |
| `addons.json` | 浏览器组件的清单，应用自己读取，不用手动下载 / the browser add-on list, read by the app |
| Source code (zip / tar.gz) | 源代码，**不是软件**，装软件不要下载 / source code, **not the app** |

安装包没有 Apple 的付费开发者签名。双击时如果提示“无法打开”，到 **系统设置 → 隐私与安全性** 点“仍要打开”，
第一次打开应用时如果被拦也一样。详细步骤见 [README](../README.md#下载与安装--download-and-install)。
Not signed by Apple: if macOS blocks the installer or the app, click **Open Anyway** in System Settings → Privacy & Security.

## 修复 / Fixes

- 在 macOS 27.2 上，LiveHime 每次打开约 2 秒后就会闪退（主窗口还没出现）。
  原因在应用自带的 Qt 6.11.1：它把图片交给系统绘制时，传过去的颜色信息已经被释放了，macOS 27.2 会因此直接终止应用
  （Qt 的已知问题 QTBUG-147602）。现在应用带的是 OBS 官方 2026-10-23 依赖包里的 Qt，已经包含 Qt 的官方修复；
  v0.3.1 修好的菜单栏图标问题仍然有效。
  感谢 @AzzzRChie 抓到崩溃栈、准确判断出是颜色信息的悬垂指针，并先做出了可用的临时修复。
  用了他那个“LiveHime 修复启动”的朋友，升级后可以直接打开 LiveHime，那个启动器可以删掉了。
  On macOS 27.2, LiveHime quit about 2 seconds after every launch, before the main window appeared. The cause was the
  bundled Qt 6.11.1: it handed the system a color space that had already been released when drawing an image, and
  macOS 27.2 terminates the app on that (Qt's known issue QTBUG-147602). The app now bundles the Qt from OBS's official
  2026-10-23 dependencies, which includes Qt's fix; v0.3.1's menu bar icon fix still applies.
  Thanks to @AzzzRChie for the crash stack, the accurate diagnosis of a dangling color space and a working stop-gap.
  If you used their "LiveHime 修复启动" launcher, open LiveHime directly after updating; the launcher can be deleted.

## 升级 / Upgrade

v0.2.8 及以后的版本会在应用里收到这次更新，也可以手动下载安装包或 DMG 替换。
**已经在 macOS 27.2 上打不开 0.3.1 的用户，应用多半来不及检查更新**，请手动下载安装包覆盖安装。
没有升级 OBS，不迁移设置，登录和设置都会保留；已安装的浏览器组件继续可用，不用重新下载。
From v0.2.8 on the app offers this update, or install the pkg or DMG by hand.
**If 0.3.1 no longer opens on macOS 27.2, the app most likely cannot check for updates in time**: download the installer and install over it.
OBS is not upgraded; no settings migrate; your login and settings are kept. An installed browser add-on keeps
working and is not downloaded again.

## 验证 / Validation

- 维护者把 Mac 升级到 macOS 27.2（26B123，和报告者相同）后：已安装的 0.3.1 启动约 3 秒闪退，崩溃栈与报告一致；
  换用新 Qt 的构建正常启动、进入主界面，菜单栏图标左右键都正常；覆盖安装 0.3.2 后正常运行。
  The maintainer upgraded to macOS 27.2 (26B123, the reporter's build): the installed 0.3.1 crashed about 3 seconds
  after launch with the reported stack; the build with the new Qt started normally with a working menu bar icon (left
  and right clicks); 0.3.2 installed over it runs normally.
- 应用里的 QtGui 与 obs-deps 2026-10-23 的完全一致（含 QTBUG-147602 修复，不再链接 Accelerate）；Cocoa 插件仍是带菜单栏修复的版本，两个架构都确认过。
  The bundled QtGui is the obs-deps 2026-10-23 one (with the QTBUG-147602 fix; it no longer links Accelerate); the
  Cocoa plugin is still the one with the menu bar fix; both checked for both architectures.
- 端到端测试：更新说明 15/15、应用更新 21/21、推流 14/14、悬浮弹幕 16/16（“隐藏 OBS”两种模式）。
  更新说明第一次运行时后台正在编译，8 项因时序失败，重跑全部通过。
  End-to-end: What's New 15/15, updates 21/21, streaming 14/14, floating chat 16/16 (with and without "Hide OBS").
  What's New failed 8 checks from timing on a first run while a build was running alongside; all passed on a rerun.
- 签名、架构、Bundle ID 检查通过，和 v0.3.1 使用同一张签名证书；安装包检查通过；v0.3.0 的浏览器组件对两个新应用的检查都通过；
  补丁 0001–0067 在上游 `32.2.2` 上还原出发布用的代码树。
  Signature, architecture and bundle id checks passed; same signing certificate as v0.3.1; the installer check
  passed; the v0.3.0 browser add-on checks pass against both new apps; patches 0001–0067 reproduce the released tree
  on upstream `32.2.2`.
- 本次没有重跑浏览器组件、字幕、SRT、全屏置顶的端到端测试，Swift core 代码没有改动。
  The add-on, captions, SRT and full-screen pinning end-to-end tests were not rerun; the Swift core is unchanged.

## 源码 / Source

基于上游 OBS Studio `32.2.2`（`ba2f32bdf`）的补丁系列在 [`obs-fork/`](../obs-fork/)：两个架构都对应补丁 0001–0067（0060、0061 只改测试）。
0066 把 Qt 依赖换成 obs-deps 2026-10-23（仍是 Qt 6.11.1），并让重新编译的 Cocoa 插件先打 obs-deps 自己的 Qt 补丁（在 `build-aux/livehime/qt/obs-deps/`）。
浏览器组件没有变化，仍是 v0.3.0 发布的 v1.0.0。
The patch series on upstream OBS Studio `32.2.2` (`ba2f32bdf`) is in [`obs-fork/`](../obs-fork/): patches 0001–0067
for both architectures (0060 and 0061 change only tests). 0066 moves the Qt dependency to obs-deps 2026-10-23 (still
Qt 6.11.1) and has the rebuilt Cocoa plugin apply obs-deps' own Qt patches first (in `build-aux/livehime/qt/obs-deps/`).
The browser add-on is unchanged: v1.0.0 from the v0.3.0 release.
