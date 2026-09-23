# LiveHime macOS v0.2.1

修复版本：让沿用哔哩哔哩网页的地方（封面、人脸验证、密码 / 短信登录）按钮都能正常工作。
A fix release: the buttons on the Bilibili web pages LiveHime hosts (cover, face verification,
password/SMS login) now all work.

## 修复 / Fixes

- **更换封面 / Changing the cover：** “重新上传”现在能选本地图片，点“确定”上传的也是新图，不再把当前封面
  重新传一遍。页面里的“取消”和“确定”也能关闭窗口了。
  Re-upload now takes a local image and Confirm uploads it instead of the current cover again. The page's
  own Cancel and Confirm now close the window.
  - 原因 / Cause：这个页面是为 Windows 版里的 Chromium 写的。WebKit 里，没挂到页面上的文件输入框可能在选图
    过程中被回收；另外，页面给本地图片地址（`blob:`）加的时间戳参数 WebKit 无法加载。
    The page is written for Chromium in the Windows client. In WebKit, its detached file input can be
    collected while you choose, and the timestamp it appends to local `blob:` image URLs doesn't load.
- **人脸验证网页 / Face verification page：** 页面在验证结束后会自动关闭，这时应用会自动重试开播，不用再手动点。
  When the page closes itself after verification, going live is retried automatically.
- **登录页 / Login page：** “忘记密码”、用户协议、隐私政策改用默认浏览器打开；网页弹窗能正常显示；
  QQ / 微信 / 微博登录跳回页面后能完成登录。
  Forgot password and the agreements open in your browser, page alerts show, and QQ/WeChat/Weibo sign-in
  completes when it returns to the page.
- **外部链接 / External links：** 页面里指向其他网站的链接改用默认浏览器打开。
  Links to other sites open in your default browser.

## 诊断 / Diagnostics

这些网页现在会把失败的请求、页面错误和页面提示写进 OBS 日志。日志只记录域名、路径和返回码，不记录 Cookie、
查询参数或请求内容。
The hosted pages log failed requests, page errors and toasts to the OBS log (host, path and result code
only; never cookies, queries or request bodies).

## 验证 / Validation

- 端到端测试在真实窗口里用真实点击完成：选本地图 → 编辑器画面与所选图片一致（色差 0.0）→ 点“确定”上传
  （`code=0`）→ 直播间封面换成新图，进入哔哩哔哩审核。账号主人已同意这次测试。
  End-to-end in the real window with real clicks: pick a local image → the editor shows it (colour
  distance 0.0) → Confirm uploads it (`code=0`) → the room cover changed and went to Bilibili review.
  Run with the account owner's consent.
- Swift core：79 个测试通过，1 个需要联网的测试跳过。签名、arm64 和 Bundle ID 检查通过。
  Swift core: 79 passed, 1 network-gated skipped. Signature, arm64 and bundle ID checks passed.

## 升级 / Upgrade

打开 DMG，把 LiveHime 拖到“应用程序”，选择“替换”。登录和设置都会保留。
Open the DMG, drag LiveHime onto Applications and choose Replace. Login and settings are kept.

## 源码 / Source

基于上游 OBS Studio `32.2.2`（`ba2f32bdf`）的补丁系列在 [`obs-fork/`](../obs-fork/)（共 29 个）。
The patch series on upstream OBS Studio `32.2.2` (`ba2f32bdf`) is in [`obs-fork/`](../obs-fork/) (29 patches).
