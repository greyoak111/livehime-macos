# LiveHime macOS v0.2.0

LiveHime macOS 是第三方的哔哩哔哩直播姬 macOS 版本，仅供学习、研究和社区交流，与哔哩哔哩、
OBS Project 或 Windows 版直播姬官方无关。
LiveHime macOS is an unofficial third-party macOS take on Bilibili LiveHime, for learning,
research and community exchange only.

## 重做 / Rebuilt on OBS

v0.2.0 不再是“原生外壳 + 隐藏的 OBS 后台”，而是一个 **带直播姬面板的 OBS Studio 32.2.2**。场景、
来源、滤镜、录制和 OBS 用法完全一样，直播姬功能在右侧“直播姬”停靠面板里。
v0.2.0 is OBS Studio 32.2.2 with a LiveHime dock instead of a native shell driving a hidden OBS.

## 新功能 / What's new

- **登录 / Sign-in：** 原生扫码登录，也可以通过哔哩哔哩官方页面用密码或短信登录；登录信息存在钥匙串，
  会自动续期，退出登录时会在服务器端注销。
  Native QR login, plus password/SMS through Bilibili's own page; Keychain session, automatic renewal,
  server-side sign-out.
- **开播 / Going live：** 选分区后一键开播，推流地址自动写入 OBS；OBS 自己的“开始直播 / 停止直播”按钮也走
  同一流程；结束直播会同时关闭直播间；退出应用时会关闭本程序打开的直播间。
  One-click go live with the RTMP address filled in automatically. OBS's own Start/Stop buttons use the
  same flow, and ending the stream also closes the room.
- **人脸认证 / Face verification：** 开播要求人脸认证时显示原生二维码，用哔哩哔哩 App 扫码完成。
  Shown as a native QR code to scan with the Bilibili app.
- **弹幕 / Danmaku：** 实时弹幕、礼物、醒目留言（置顶显示）、上舰、进场，可以发送弹幕、右键复制或禁言
  （本场 / 1 小时 / 永久），可以管理屏蔽词，也可以只看礼物。
  Live feed with sending, copy/mute, blocked words and a gifts-only view.
- **悬浮聊天 / Floating chat：** 可拖动的弹幕窗口，支持置顶、钉住、50–100% 不透明度，可以选择是否让它出现在
  屏幕采集里，也可以绑定快捷键。
  Draggable window with on-top, pin, 50–100% opacity, an opt-in for screen capture, and a hotkey.
- **直播间 / Room：** 修改标题，打开封面管理，查看看过人数、点赞和高能数据。
  Title, cover manager, live stats.
- **“直播姬弹幕”来源 / Danmaku overlay source：** 把弹幕叠加到直播画面上，字体、颜色、描边、行数和停留时间
  都可以调。
  An overlay source with adjustable style.

## 升级 / Upgrade

打开 DMG，把 LiveHime 拖到“应用程序”，选择“替换”。Bundle ID（`local.livehime.macos`）和钥匙串项都
和 v0.1.x 相同，所以登录通常会自动沿用。第一次打开时要重新授予屏幕录制、麦克风和摄像头权限。
OBS 配置改存到 `~/Library/Application Support/LiveHime`，v0.1.x 的场景不会自动迁移。详见
[`docs/UPGRADING.md`](UPGRADING.md)。
Open the DMG, drag LiveHime onto Applications and choose Replace. The login usually carries over.
Grant capture permissions again on first launch. Scenes from v0.1.x are not migrated.

## 已知限制 / Known limitations

- 只有 Apple Silicon 构建，需要 macOS 13 或更高版本；使用本地证书签名，没有经过 Apple 公证，首次打开需要
  在“隐私与安全性”里点“仍要打开”。
  Apple Silicon only, macOS 13+, locally signed and not notarized.
- 暂不包含浏览器来源；语音字幕在计划中（见 [`docs/ROADMAP.md`](ROADMAP.md)）。
  No browser source yet; live captions are planned.

## 源码 / Source

应用是 OBS Studio（GPL-2.0-or-later）的修改版。完整改动以补丁形式放在
[`obs-fork/`](../obs-fork/)，基于上游 `32.2.2`（`ba2f32bdf`）。
The app is a modified OBS Studio (GPL-2.0-or-later); the complete changes are the patch series in
[`obs-fork/`](../obs-fork/), based on upstream `32.2.2` (`ba2f32bdf`).

## 验证 / Validation

- Swift core：79 个测试通过，1 个需要联网的测试跳过。
  Swift core: 79 tests passed, 1 network-gated test skipped.
- 通过 obs-websocket 端到端测试：推流链路、扫码登录流程、弹幕叠加、悬浮聊天（包括屏幕采集能否看到它）。
  End-to-end tests over obs-websocket: stream path, QR login flow, overlay, floating chat (including
  whether screen capture sees it).
- 用真实账号验证过：扫码登录、登录沿用、开播推流、人脸认证页面。密码/短信登录、原生人脸二维码、禁言和屏蔽词
  还没在真实账号上验证过，欢迎反馈。
  Verified on a real account: QR login, login carry-over, going live, the face verification page.
  Password/SMS login, the native face QR, muting and blocked words have not yet been verified on a real
  account; feedback welcome.
- 签名、arm64 和 Bundle ID 检查通过；应用包里没有账号数据、Cookie、推流码或签名密钥。
  Signature, arm64 and bundle ID checks passed; no account data, cookies, stream keys or signing keys
  are included.
