# LiveHime macOS v0.3.0

## 下载哪个文件 / Which file to download

| 文件 / File | 给谁用 / For |
|---|---|
| **`LiveHime-v0.3.0-Installer.pkg`** | **不知道选哪个就下载这个。** 所有 Mac，双击后一路“继续”，自动选芯片 / Not sure? This one. Any Mac |
| `LiveHimeMacApp-v0.3.0-arm64.dmg` | Apple 芯片（M 系列），打开后拖进“应用程序” / Apple silicon, drag to install |
| `LiveHimeMacApp-v0.3.0-x86_64.dmg` | Intel 芯片，打开后拖进“应用程序” / Intel, drag to install |
| `LiveHimeMacApp-v0.3.0-*.zip` | 应用内更新用的，不用手动下载 / for the in-app updater |
| `LiveHime-BrowserAddon-v1.0.0-*.zip`、`addons.json` | 浏览器组件，在应用里安装，不用手动下载 / the browser add-on, installed from inside the app |
| Source code (zip / tar.gz) | 源代码，**不是软件**，装软件不要下载 / source code, **not the app** |

安装包没有 Apple 的付费开发者签名。双击时如果提示“无法打开”，到 **系统设置 → 隐私与安全性** 点“仍要打开”，
第一次打开应用时如果被拦也一样。详细步骤见 [README](../README.md#下载与安装--download-and-install)。
Not signed by Apple: if macOS blocks the installer or the app, click **Open Anyway** in System Settings → Privacy & Security.

## 新功能 / What's new

- **浏览器来源（可选组件）/ Browser source (optional add-on)**：在画面里显示网页，比如弹幕、礼物特效这类网页工具。
  主程序不变，需要的人在“直播姬”面板 → 更新 → **可选组件** 里一键下载（约 100 MB），装在你的用户目录里；
  重启 LiveHime 后，在“添加来源”里选“浏览器”。随时可以移除（移到废纸篓）。
  下载前会核对校验值，并确认组件和应用由同一张证书签名；组件和当前 OBS 版本对不上、或文件被改动过时不会加载。
  以后更新 LiveHime 时如果换了 OBS 底座，对应的组件会随更新一起下载好。
  Shows web pages in your scenes, such as danmaku or gift-effect web tools. The app is unchanged; install it from
  Updates → **Optional add-ons** (about 100 MB, into your user folder), restart, then choose Browser in Add Source.
  It can be removed at any time (to the Trash). Downloads are checked against their checksum and must be signed by the
  app's certificate; an add-on that does not match this OBS or was changed is not loaded. When a later update moves to
  another OBS base, the matching add-on comes with it.
- **更新说明 / What's new**：更新后第一次打开时，在主窗口正中显示这次更新了什么（最多最近三个版本，内容多时可以滚动）。
  全新安装不显示。
  After an update, the first start shows what changed (up to the three newest versions, scrolling when long),
  centered on the main window. Not shown on a fresh install.

## 修复 / Fixes

- 浏览器组件下载期间如果检查了更新（手动点“检查更新”或自动检查），安装会失败，要重试一次才能装上。
  现在组件下载到单独的文件夹，检查更新不会再打断它。
  Checking for updates while the browser add-on was downloading made the install fail until retried. The add-on
  now downloads into a folder of its own, out of the way of the update check.

## 升级 / Upgrade

v0.2.8 及以后的版本会在应用里收到这次更新，也可以手动下载安装包或 DMG 替换。
没有升级 OBS，不迁移设置，登录和设置都会保留。
From v0.2.8 on the app offers this update, or install the pkg or DMG by hand.
OBS is not upgraded; no settings migrate; your login and settings are kept.

装了浏览器组件后，即使画面里没有浏览器来源，它也会在后台常驻约 150 MB 内存；不需要时可以移除。
With the browser add-on installed, it keeps about 150 MB of memory in the background even without a browser
source; remove it if you do not need it.

## 使用提示 / Tips

- **在浏览器来源里登录或点击网页**：画面里的浏览器来源只负责显示，不接受点击和输入。在“来源”列表里右键它 → **交互**，
  会打开一个可以操作的窗口，在里面登录、点按钮都行；登录会被记住，所有浏览器来源共用。
  交互窗口里的操作会同时出现在画面上，登录前先点“眼睛”把来源隐藏（隐藏时交互窗口照样能用），或者在没开播时登录。
  **Logging in or clicking in a browser source**: the source in your scene only displays the page. Right-click it in
  Sources → **Interact** to open a window you can click and type in; logins are remembered and shared by all browser
  sources. What you do there also shows in the scene, so hide the source first (the eye icon; Interact still works)
  or log in while not streaming.

## 验证 / Validation

- 维护者用真实账号开播正常；用 pkg 把 0.2.10 升级到 0.3.0，登录、设置和屏幕录制授权都保留，更新说明弹窗正常出现。
  A real stream by the maintainer; the pkg upgraded 0.2.10 to 0.3.0 keeping the login, settings and screen
  recording permission, and the What's New dialog appeared.
- 端到端测试：更新说明 15/15、浏览器组件 19/19、组件随更新 9/9、应用更新 21/21、推流 14/14、字幕 26/26、
  SRT 16/16、悬浮弹幕 16/16（屏幕采集开关“隐藏 OBS”两种模式）、全屏置顶 5/5。
  End-to-end: What's New 15/15, add-on 19/19, add-on with an update 9/9, updates 21/21, streaming 14/14,
  captions 26/26, SRT 16/16, floating chat 16/16 (with and without "Hide OBS"), full-screen pinning 5/5.
- 浏览器组件两个架构的检查全部通过（架构、从组件自身加载 CEF、只含中英文语言、附 CEF 许可、和应用同一张签名证书）；
  安装包检查、更新说明检查通过；补丁 0001–0063 在上游 `32.2.2` 上还原出发布用的代码树。
  Add-on checks pass for both architectures (architecture, CEF loaded from the add-on, en/zh locales only, CEF
  license included, same signing certificate as the app); installer and release-notes checks pass; patches
  0001–0063 reproduce the released tree on upstream `32.2.2`.
- 维护者从 GitHub 发布页真实安装了浏览器组件，浏览器来源正常显示网页；安装失败的问题由此发现并修复（见“修复”）。
  The maintainer installed the browser add-on from the published release and a browser source showed a page;
  this is how the failed-install issue above was found and fixed.
- Swift core：112 个测试，111 个通过，1 个需要联网的测试跳过。
  Swift core: 112 tests, 111 passed, 1 network-gated skipped.
- 签名、架构、Bundle ID 检查通过，和 v0.2.10 使用同一张签名证书；应用包里没有账号数据。
  Signature, architecture and bundle id checks passed; same signing certificate as v0.2.10; no account data in
  the bundle.

## 源码 / Source

基于上游 OBS Studio `32.2.2`（`ba2f32bdf`）的补丁系列在 [`obs-fork/`](../obs-fork/)：两个架构都对应补丁 0001–0063（0060、0061 只改测试）。
浏览器组件另外对 `plugins/obs-browser` 子模块打了 [`obs-fork/browser-addon`](../obs-fork/browser-addon/) 里的补丁，
组件内含的 Chromium Embedded Framework 的许可见 [`ThirdPartyLicenses/CEF`](../ThirdPartyLicenses/CEF/)。
The patch series on upstream OBS Studio `32.2.2` (`ba2f32bdf`) is in [`obs-fork/`](../obs-fork/): patches 0001–0063
for both architectures (0060 and 0061 change only tests). The browser add-on also patches the `plugins/obs-browser` submodule (see
[`obs-fork/browser-addon`](../obs-fork/browser-addon/)); the license of the Chromium Embedded Framework it contains is
in [`ThirdPartyLicenses/CEF`](../ThirdPartyLicenses/CEF/).
