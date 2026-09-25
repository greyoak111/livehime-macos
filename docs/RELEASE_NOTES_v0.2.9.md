# LiveHime macOS v0.2.9

## 新功能 / What's new

- **表情 / Emoticons：** 发送框旁新增 ☺ 表情面板（侧栏和悬浮聊天都有），和手机直播间一样的分页：小黄脸、
  通用表情、你账号里的个性化表情包，以及热词系列、tv_小电视。点一下直接发送；未解锁的表情是灰色的，会提示解锁
  条件。面板就在聊天窗口里面，其他应用全屏时也能正常打开。
  An emoticon panel next to the send box (dock and floating chat) with the same packs as the phone's live
  room: 小黄脸, the general stickers, your own packs, plus 热词系列 and tv_小电视. One click sends; locked
  ones are greyed out with how to unlock them. It sits inside the chat window, so it works over full-screen apps.
- **聊天里显示表情图片 / Emoticons shown in chat：** 弹幕里的表情和大表情显示成图片，不再是 `[doge]` 或
  重复的文字。图片只从 B 站图床下载、缩小后缓存在本机（最多 30 MB），不带登录信息。
  Emoticons and stickers in chat are drawn as pictures instead of `[doge]` or repeated text. Pictures come
  only from Bilibili's image hosts, without login data, and are cached small (at most 30 MB).

## 修复 / Fixes

- 没登录时，侧栏弹幕列表在大量消息下无法滚动。/ The dock's chat list could not scroll while signed out.
- B 站把“人脸认证状态”接口改成了只接受 POST，巡检里这一项报 HTTP 405，已修复。开播时的扫码认证窗口保持原来的
  流程：扫码完成后点“验证完成，重试开播”。
  Bilibili's face verification status endpoint now takes POST only (the check reported HTTP 405). The QR
  verification window keeps its flow: scan, then click “验证完成，重试开播”.
- B 站接口巡检新增“直播间表情”和“主站表情”两项。/ The interface check also covers both emoticon sources.

## 升级 / Upgrade

v0.2.8 会在应用里自动收到这次更新（“直播姬”面板 → 更新），也可以手动下载 DMG 替换。没有升级 OBS，不迁移设置。
v0.2.8 picks this up in the app (Updates tab), or replace it with the DMG. OBS is not upgraded; no settings migrate.

## 验证 / Validation

- 真实账号：小黄脸、通用大表情、热词、tv_小电视和多个个性化表情包都已实际发送，手机端显示为表情；
  接口巡检 16 项全部通过。
  Real account: every kind of emoticon was sent and shown as a picture on the phone; the interface check passed all 16.
- 端到端测试：表情（面板、插入、未解锁提示、发送失败保留草稿、悬浮聊天共用、刷屏时滚动，共 13 项）；
  悬浮聊天在全屏应用上方打开表情面板（面板在聊天窗口内，没有额外窗口）；弹幕来源。
  End to end: emoticons (13 checks, including scrolling under a flood), the panel over a full-screen app,
  the danmaku overlay.
- Swift core：100 个测试通过，1 个需要联网的测试跳过。签名、架构、Bundle ID 检查通过，和 v0.2.8 使用同一张
  签名证书；应用包里没有账号数据。
  Swift core: 100 passed, 1 network-gated skipped. Signature, architecture and bundle id checks passed; same
  signing certificate as v0.2.8; no account data in the bundle.

## 源码 / Source

基于上游 OBS Studio `32.2.2`（`ba2f32bdf`）的补丁系列在 [`obs-fork/`](../obs-fork/)：两个架构都对应补丁 0001–0051。
The patch series on upstream OBS Studio `32.2.2` (`ba2f32bdf`) is in [`obs-fork/`](../obs-fork/): patches
0001–0051 for both architectures.
