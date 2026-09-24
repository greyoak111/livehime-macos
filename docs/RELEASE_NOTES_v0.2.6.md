# LiveHime macOS v0.2.6

## 新功能 / What's new

- **语音字幕 / Live captions：** 直播姬面板新增“字幕”页，可以把麦克风（或任意 OBS 音频来源）实时转成字幕，支持普通话、
  国语（繁体）、粤语和 English。语音只在这台 Mac 上识别（Apple SpeechAnalyzer），不上传音频，不登录也能用；
  需要 macOS 26 或更高版本。音频来源静音时会提示，“直播机”这类同音词会自动改成“直播姬”。
  A Captions tab turns the mic (or any OBS audio source) into live captions in Mandarin, Taiwanese Mandarin,
  Cantonese or English, recognized on the Mac and never uploaded; works signed out; needs macOS 26+.
- **“直播姬字幕”来源 / Captions source：** 默认一行、放在画面底部居中；可以调字体、颜色、描边粗细和颜色、阴影、
  半透明底板、行数和停留时间；句子太长时保留最新的一段。
  One line at the bottom centre by default, with font, colour, outline, shadow, plate, lines and linger time;
  long sentences keep the newest words.
- **“直播姬弹幕”来源改为竖版发言列表 / Danmaku source as a chat list：** 最新消息在最下面，用户名是 B 站粉色，
  礼物是金色，上舰是紫色，醒目留言带红色底条，长消息自动换行，外加半透明底板。只在有新消息或消息过期时重画。
  Newest at the bottom; pink names, gold gifts, purple guards, Super Chats on a red strip; wrapped; plate.
- **摆放 / Placement：** 字幕和弹幕都可以选“画面位置”（底部居中、左下、右下、画面中央、四个角或自由摆放），直接拖动
  红框的边就能改大小，文字按原字号重新排版，不会被拉伸；手动拖到别处会自动改为自由摆放。
  Both sources take a canvas position and are resized by dragging the frame without stretching the text.
- **直播姬面板 / LiveHime dock：** 右上角的关闭按钮去掉了，和场景、源这些主面板一致。
  The dock no longer has a close button, like the main docks.

## 修复 / Fixes

- DMG 的磁盘图标改为 LiveHime 图标。/ The DMG volume uses the LiveHime icon.

## 升级 / Upgrade

打开 DMG，把 LiveHime 拖到“应用程序”，选择“替换”。登录和设置都会保留。场景里已有的“直播姬弹幕”“直播姬字幕”
会自动换成新的画布框：弹幕默认放在左下，字幕默认放在底部居中。
Open the DMG, drag LiveHime onto Applications and choose Replace. Existing danmaku and caption sources switch
to the new box automatically (danmaku bottom left, captions bottom centre).

## 验证 / Validation

- 端到端测试：媒体源播放中文语音 → 字幕在 1.3 秒内出现、识别正确、同音词修正生效；截图检查字幕框尺寸、底部居中
  和左对齐；拖边框改大小、画面位置、手动移动后改为自由摆放；弹幕列表的顺序、换行、刷屏后只保留最新消息、贴底，
  以及改大小和改位置。
  End to end: speech from a media source becomes captions within 1.3 s, recognized correctly; screenshots check
  the box size, bottom-centre and left alignment; resizing, placement and moving by hand; the danmaku list's
  order, wrapping, overflow, bottom anchoring, resizing and placement.
- Swift core：83 个测试通过，1 个需要联网的测试跳过。签名、arm64、Bundle ID 检查通过；Speech 框架弱链接，
  macOS 13–15 上应用照常运行，只是没有字幕功能。
  Swift core: 83 passed, 1 network-gated skipped. Signature, arm64 and bundle ID checks passed; Speech is
  weak-linked, so the app still runs on macOS 13–15 without captions.

## 源码 / Source

基于上游 OBS Studio `32.2.2`（`ba2f32bdf`）的补丁系列在 [`obs-fork/`](../obs-fork/)（共 39 个）。
The patch series on upstream OBS Studio `32.2.2` (`ba2f32bdf`) is in [`obs-fork/`](../obs-fork/) (39 patches).
