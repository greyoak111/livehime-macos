# LiveHime macOS v0.2.10

v0.2.9 的小修复版。/ A small fix on top of v0.2.9.

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
0001–0053 for both architectures.
