# LiveHime macOS v0.2.7

## 新功能 / What's new

- **回复观众 / Reply to viewers：** 在弹幕面板或悬浮聊天里右键一条弹幕，选“回复 @TA”（也可以直接双击），发送框上方会显示
  “回复 @某某 ×”，发出的弹幕会作为对这位观众的回复（观众端显示为 @某某）。按 Esc 或点 × 取消。别人发的回复在面板和
  “直播姬弹幕”来源里显示为“@某某 内容”。
  Right-click (or double-click) a danmaku and choose "Reply to @name"; the danmaku you send is a reply to that
  viewer, shown as @name. Esc or × cancels. Replies from others show as "@name …" in the feed and the overlay.

## 修复 / Fixes

- **悬浮聊天置顶 / Floating chat on top：** 以前只要 LiveHime 不在前台，别的应用窗口就能盖住悬浮聊天，其他应用全屏
  （比如游戏、视频）时它也显示不出来。现在“置顶”打开时，它会一直留在最上面，包括其他应用的全屏画面上。
  Other apps' windows no longer cover the floating chat while LiveHime is in the background, and it now stays
  above other apps in full screen.
- **全屏时的菜单 / Menus over full screen：** 其他应用全屏时，悬浮聊天的“⋯”菜单和弹幕右键菜单也能正常打开。
  The "⋯" menu and the danmaku right-click menu open over full-screen apps.
- 置顶打开时，点击悬浮聊天不会再把 LiveHime 主窗口切到前台，输入框照常可以打字。
  With "on top" on, clicking the floating chat no longer brings LiveHime's main window forward; typing still works.

## 升级 / Upgrade

打开 DMG，把 LiveHime 拖到“应用程序”，选择“替换”。登录和设置都会保留。
Open the DMG, drag LiveHime onto Applications and choose Replace. Login and settings are kept.

## 验证 / Validation

- 真实账号验证：回复弹幕（面板显示 @某某）、全屏应用上的悬浮聊天和“⋯”菜单。
  Verified on a real account: sending a reply, and the floating chat and its menu over a full-screen app.
- 端到端测试（新增 `e2e-float-fullscreen.mjs`）：其他应用全屏时悬浮聊天在其前面、关闭置顶时不出现；其他应用在前台
  时悬浮聊天仍在最上层；全屏时弹出“⋯”菜单。
  End to end: the chat is in front of a full-screen app (and absent with "on top" off), stays on top while another
  app is active, and its "⋯" menu opens over full screen.
- Swift core：85 个测试通过，1 个需要联网的测试跳过。签名、arm64、Bundle ID 检查通过；应用包里没有账号数据。
  Swift core: 85 passed, 1 network-gated skipped. Signature, arm64 and bundle ID checks passed; no account data.

## 源码 / Source

基于上游 OBS Studio `32.2.2`（`ba2f32bdf`）的补丁系列在 [`obs-fork/`](../obs-fork/)（共 43 个）。
The patch series on upstream OBS Studio `32.2.2` (`ba2f32bdf`) is in [`obs-fork/`](../obs-fork/) (43 patches).
