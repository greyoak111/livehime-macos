# LiveHime macOS v0.2.10

v0.2.9 的小修复版。/ A small fix on top of v0.2.9.

## 下载哪个文件 / Which file to download

| 文件 / File | 给谁用 / For |
|---|---|
| **`LiveHime-v0.2.10-Installer.pkg`** | **不知道选哪个就下载这个。** 所有 Mac，双击后一路“继续”，自动选芯片 / Not sure? This one. Any Mac |
| `LiveHimeMacApp-v0.2.10-arm64.dmg` | Apple 芯片（M 系列），打开后拖进“应用程序” / Apple silicon, drag to install |
| `LiveHimeMacApp-v0.2.10-x86_64.dmg` | Intel 芯片，打开后拖进“应用程序” / Intel, drag to install |
| `LiveHimeMacApp-v0.2.10-*.zip` | 应用内更新用的，不用手动下载 / for the in-app updater |
| Source code (zip / tar.gz) | 源代码，**不是软件**，装软件不要下载 / source code, **not the app** |

安装包没有 Apple 的付费开发者签名。双击时如果提示“无法打开”，到 **系统设置 → 隐私与安全性** 点“仍要打开”，
第一次打开应用时如果被拦也一样。详细步骤见 [README](../README.md#下载与安装--download-and-install)。
Not signed by Apple: if macOS blocks the installer or the app, click **Open Anyway** in System Settings → Privacy & Security.

安装包（pkg）是 2026-09-28 补上的，里面的应用和同版本 DMG 完全相同。
The installer package was added on 2026-09-28; the apps inside are the same as in the DMGs.

## 修复 / Fixes

- “更新”页和“字幕”页在面板较矮时文字被挤扁，现在会像“房间”页一样出现滚动条。
  The Updates and Captions tabs squashed their text in a short dock; they now scroll like the Room tab.

v0.2.9 的新功能（表情面板、聊天里的表情图片等）见 [v0.2.9 发布说明](RELEASE_NOTES_v0.2.9.md)。
For v0.2.9's features (emoticons and more) see the [v0.2.9 notes](RELEASE_NOTES_v0.2.9.md).

## 升级 / Upgrade

v0.2.8 和 v0.2.9 会在应用里自动收到这次更新（“直播姬”面板 → 更新），也可以手动下载 DMG 替换。没有升级 OBS，不迁移设置。
v0.2.8 and v0.2.9 pick this up in the app, or replace it with the DMG. OBS is not upgraded; no settings migrate.

## 验证 / Validation

- 在测试实例里把面板压到 700px 高截图检查：“更新”页和“字幕”页出现滚动条，文字正常换行。
  Rendered the dock at 700 px high: both tabs scroll and their text wraps normally.
- Swift core：100 个测试通过，1 个需要联网的测试跳过。签名、架构、Bundle ID 检查通过，和 v0.2.9 使用同一张签名证书；
  应用包里没有账号数据。
  Swift core: 100 passed, 1 network-gated skipped. Signature, architecture and bundle id checks passed; same
  signing certificate as v0.2.9; no account data in the bundle.

## 源码 / Source

基于上游 OBS Studio `32.2.2`（`ba2f32bdf`）的补丁系列在 [`obs-fork/`](../obs-fork/)：两个架构都对应补丁 0001–0053。
The patch series on upstream OBS Studio `32.2.2` (`ba2f32bdf`) is in [`obs-fork/`](../obs-fork/): patches
0001–0053 for both architectures. 补丁 0054 只加了打包脚本 `package-pkg.sh`，不影响应用本身。
Patch 0054 only adds the `package-pkg.sh` packaging script and does not change the app.
