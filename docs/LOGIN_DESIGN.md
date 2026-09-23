# 登录与会话设计（v0.2，OBS 插件形态）

日期：2026-09-23。本文是 v0.2 把直播姬能力做成 OBS 插件时的登录方案。证据分三类：
【静】官方 8.6 包静态字符串（只读，不执行 PE）；【测】匿名接口实测（不含账号数据）；
【码】v0.1.2 现有代码。标注【待验】的结论需要用户用真实账号在本机验证后才能定稿。

## 1. 现状与问题（v0.1.2）

v0.1.2 在 WKWebView 中承载官方 `mini-login-v2` 页面，注入与 Windows 同名的
`livehime_login` / `biliBridgePc` bridge 接收结果【码】。它能用，但有以下问题：

| 问题 | 位置 | 后果 |
|---|---|---|
| 登录界面是一整页网页 | `AppDelegate.loadLoginPage` | 和宿主风格割裂；页面改版就可能坏 |
| Keychain 只存 `SESSDATA` 或 `refresh_token` 其中之一 | `LoginSession.swift` `StoredLoginSession` | 真正的凭据（`bili_jct` 等）留在 WebKit 数据存储里，Keychain 只是半个真相源 |
| 没有会话续期 | 全仓库无 `cookie/info`、`cookie/refresh` 调用 | SESSDATA 过期后只能重新登录 |
| 退出只清本地 | 全仓库无 `login/exit/v2` 调用 | 服务端会话仍然有效 |
| 人脸验证与风控验证混用同一个网页 | `presentFaceAuth`（60024 与 60043 同路径） | 本可以原生展示二维码的场景也弹网页 |

## 2. 官方直播姬怎么做（8.6 静态证据）

- 登录界面：CEF 中的 `mini-login-v2`，与 v0.1.2 相同【静】（`bililive_mini_login_new_window.cpp`、`MiniLogin*`）。
- 登录后有一层 **App OAuth2 令牌**【静】（`bililive_secret.dll`）：
  `passport.bilibili.com/api/v2/oauth2/{access_token,refresh_token,info,revoke}`、`/api/v3/oauth2/login`；
  响应字段 `data.token_info.{access_token,refresh_token,expires_in,mid}`、`data.cookie_info.{cookies,domains}`。
  令牌换取的输入参数静态不可见，需要动态观察，本方案**不采用**（见 §6）。
- 开播前人脸认证是**原生二维码**【静】：`livehime::FaceAuthPresenter::GenerateQRCode`、`FaceAuthView`，
  配合 `/xlive/app-blink/v1/preLive/IsUserIdentifiedByFaceAuth` 轮询；字段 `data.need_face_auth`、`face_auth_code`。
- 风控验证才用网页【静】：`RiskFaceAuthWebView`、`risk_face_auth_h5_url`。
  该页面（`bilili-page-face-auth`）的脚本只是把 `v_voucher` 交给官方风控 SDK `CaptchaLoader`【测，页面 JS 静态读取】。
- 实名认证跳 `blackboard/live/auth-middle.html?source_event=200`【静】。

## 3. 目标方案

### 3.1 登录方式

| 方式 | 形态 | 说明 |
|---|---|---|
| **扫码登录（默认）** | 原生对话框（Qt）显示二维码 | 走公开 Web 接口，无验证码；主播几乎都装了 B 站 App |
| 短信 / 密码（备选） | 用户点“其他方式”时才弹出网页窗口 | 极验/风控只能在官方页面里完成；复用 v0.1.2 的 bridge |

扫码状态机（【测】generate 返回 `url`+`qrcode_key`，poll 未扫码返回内层 `code=86101`）：

```
generate(source=live_pc) → 显示二维码
poll 每 1.5s:
  86101 未扫码         → 继续
  86090 已扫码待确认   → 提示“请在手机上确认”
  86038 已过期         → 自动重新生成
  0     成功           → 从响应 Set-Cookie 读取 SESSDATA / bili_jct / DedeUserID / DedeUserID__ckMd5 / sid，
                          data.refresh_token 一并保存                        【待验：真实扫码确认 Set-Cookie 完整】
```

二维码图片用 CoreImage `CIQRCodeGenerator` 生成，Qt 只负责显示。

### 3.2 会话（Keychain 作为唯一真相源）

- Keychain 存**一个**条目：完整 Cookie 集合 + `refresh_token` + 获取时间 + `mid`。
  不再依赖 WKWebsiteDataStore；备选网页登录成功后把 Cookie 导出进这个条目，然后清空网页数据。
- 启动时：读 Keychain → `x/web-interface/nav` 校验身份（复用 `fetchIdentity`）。
- **续期**（Web 公开流程，社区文档 bilibili-API-collect 记载【待验】）：
  1. `GET /x/passport-login/web/cookie/info?csrf=` → `data.refresh == true` 才续期；
  2. 用公钥对 `refresh_{毫秒时间戳}` 做 RSA-OAEP(SHA-256) 得到 `correspondPath`，
     `GET www.bilibili.com/correspond/1/{correspondPath}` 取页面里的 `refresh_csrf`；
  3. `POST /x/passport-login/web/cookie/refresh`（`csrf`、`refresh_csrf`、`source=main_web`、`refresh_token`）→ 新 Cookie + 新 `refresh_token`；
  4. `POST /x/passport-login/web/confirm/refresh`（新 `csrf`、**旧** `refresh_token`）使旧会话失效。
  时机：每次启动时检查一次，常驻运行时每天检查一次；**直播中不续期**，避免推流途中 Cookie 被替换。
- **退出**：先按 v0.1.2 的顺序停止推流并关播，确认双方离线后调用 `POST /login/exit/v2`（`biliCSRF`），再删除 Keychain 条目。

### 3.3 开播时的人脸验证与风控

| startLive 返回 | 处理 |
|---|---|
| 需要人脸认证（`need_face_auth` / 60024 一类） | **原生二维码**：用户用 App 扫码完成人脸，插件轮询 `IsUserIdentifiedByFaceAuth`，通过后自动重试开播 【待验：真实账号抓取响应里的二维码字段】 |
| 风控（带 `risk_extra.v_voucher`，60043 一类） | 小网页窗口加载 `bilili-page-face-auth?v_voucher=…`，由官方 SDK 完成；关闭后重试开播（沿用 v0.1.2） |
| 需要实名 | 打开 `auth-middle.html` 引导，不做代办 |

## 4. 从 v0.1.2 复用什么

| 复用 | 来源 | 用法 |
|---|---|---|
| 开播/关播、签名顺序、版本号、服务器时间、分区叶子节点、错误码映射 | `BilibiliLiveClient.swift` | 原样复用 |
| 身份校验 | `BilibiliControlClient.fetchIdentity` | 原样复用 |
| Keychain 存取、Bundle ID → service 映射 | `LoginSession.swift` | 扩展存储结构（见 §5） |
| 备选网页的 bridge、来源白名单、Cookie 批量校验 | `AuthWebViewBridge.swift`、`AuthBridgeContract.swift` | 仅用于短信/密码备选窗口 |
| 诊断记录脱敏 | `Diagnostics.swift` | 新增 `qrLogin`、`refresh`、`logout` 阶段 |
| 退出前先关播、异步删除 Cookie 要等回调 | `AppDelegate` 退出流程 | 搬进插件的状态机 |
| buvid3 生成与持久化 | `makeBrowserContextScript` | 扫码与接口请求共用 |
| 169 项测试与假服务器 fixture | `Tests/` | 继续跑；新增扫码与续期状态机测试 |

形态：`LiveHimeAdapter` 编译成静态库，通过一层 C 接口提供给 OBS 插件；界面用 Qt。

## 5. v0.1.2 升级迁移

- 保持 Bundle ID `local.livehime.macos` 和 Keychain service `local.livehime.macos.session`。
- 首次启动时读取旧条目：如果是 `type=cookie`（只有 SESSDATA），再从同 Bundle ID 的 WebKit 默认数据存储
  一次性导出 `bili_jct` 等 Cookie，合成新格式写回 Keychain；导出失败就提示重新扫码，**绝不静默失败**。
- 新格式带 `schemaVersion`，解码失败时视为未登录，不崩溃。

## 6. 不做的事与原因

- **原生密码或短信表单**：需要自己实现 RSA 密码加密，并绕开极验，违反项目边界。
- **App OAuth2 令牌**：直播姬 appkey 调用 TV 扫码接口时返回 `-403 访问权限不足`【测】；
  官方的换取接口参数只有动态抓包才能确定。借用其他客户端的 appkey 等同冒充别的客户端，不做。
  Web Cookie + 续期已经够用；以后如果某个直播接口必须 `access_key`，再单独评估。
- 不自动完成验证码、人脸或实名。

## 7. 验证清单（需用户用真实账号在本机执行）

1. 扫码成功时，poll 响应的 Set-Cookie 包含 SESSDATA、bili_jct、DedeUserID；`refresh_token` 非空。
2. 仅凭 Keychain 恢复会话（清空 WebKit 数据后），`nav` 返回已登录，能开播和关播。
3. `cookie/info` 返回字段；如能等到 `refresh=true`，完成一次续期并确认旧会话失效。
4. 触发一次开播人脸认证，记录响应码和二维码字段（诊断导出里只记录**字段名**，不记录值）。
5. 执行 `exit/v2` 后，旧 Cookie 调用 `nav` 返回未登录。
6. v0.1.2 → v0.2 覆盖安装后无需重新登录。
