# LiveHime macOS v0.1.0：开发思路与技术路线

本文记录 LiveHime macOS 第一个可用版本的完整开发路径，重点解释我们怎样从 Windows 版行为和静态证据中恢复出一个足够稳定的 macOS 控制链路。

本文的目标是帮助维护者理解工程方法，而不是提供绕过 Bilibili 验证、实名、风控或账号资格限制的方法。实现复用了平台已经提供的官方登录页和正常开播流程；验证码、极验、二次验证、人脸验证和账号资格检查仍然由 Bilibili 完成。

## 1. 先定义问题：我们要移植的是什么

一开始最容易犯的错误，是把“直播姬”理解成一个单独的 UI 程序，或者把它误认为 Electron 应用。实际考察后，问题被拆成了四层：

1. **登录层**：展示 Bilibili 官方登录页面，承接账号密码、二维码、短信、图片验证码/极验、二次验证和必要的人脸验证。
2. **会话层**：把网页产生的 Cookie/刷新信息转换成 macOS 上可恢复、可退出、不可被日志泄漏的本地会话。
3. **直播控制层**：读取当前主播、房间、分区，按当前账号的授权状态请求开播参数和关闭直播。
4. **媒体引擎层**：把 Bilibili 返回的 RTMP server/key 写进 OBS，并可靠地启动、停止和查询 OBS。

因此目标不是“把 Windows 窗口搬到 Mac”，而是恢复这条状态链：

```text
官方登录页
  -> 网页回调 / Cookie
  -> 本地会话
  -> 当前用户与直播间
  -> Bilibili 开播请求
  -> RTMP server/key
  -> OBS WebSocket
  -> 开始/停止推流
```

如果其中任意一段只做了界面模拟，表面上会显示“登录成功”或“可以开播”，但实际状态仍然没有闭合。

## 2. 证据优先：先建立可审计的输入边界

### 2.1 不把下载的 Windows 包直接当作源码

Windows 版本是通过公开版本接口取得的 Inno Setup 包。我们先记录版本号、构建号、文件大小和哈希，然后只在本机取证，不把安装包、解包 DLL、CEF 资源或用户运行数据放进公开仓库。

处理过程的原则是：

- 先计算哈希和文件清单；
- 不执行未知 Windows 二进制；
- 用 `innoextract` 解包，避免运行安装器；
- 只对 PE 头、导入表、字符串、符号路径和交叉引用做静态分析；
- 把原始取证目录放在 Git 忽略路径中；
- 公开仓库只提交脱敏后的结论、测试和重建脚本。

### 2.2 识别进程边界

解包后得到的结构表明，旧版客户端并不是 Electron：

- `livehime.exe`：主启动器和窗口进程；
- `bililive.dll`：直播业务、账号状态和 OBS 控制相关逻辑；
- `bililive_secret.dll`：账号和直播服务连接层；
- `plugins/bililive_browser.exe`：CEF 子进程，负责登录页和网页渲染；
- `plugins/libcef.dll`：CEF runtime；
- `plugins/bililive_obs_plugin.dll`：把直播姬控制消息接到 OBS 的原生插件；
- 其他 OBS 插件：弹幕、滤镜、美颜、输出和采集能力。

这个识别结果直接改变了移植路线：不再尝试“复刻一个 Electron 壳”，而是使用 `WKWebView + AppKit` 承接网页，使用官方 OBS upstream 提供媒体引擎。

### 2.3 交叉验证，而不是相信单个字符串

静态字符串只能说明“某个名字曾经出现在二进制里”，不能单独证明调用关系。因此我们组合使用：

- PE 架构和节区检查；
- 符号路径和函数名；
- 字符串引用交叉引用；
- 导入表/API 调用；
- 相邻日志文本；
- 运行时可观察的官方网页行为；
- 自己编写的最小协议 fixture。

例如，`MiniLoginSuccess`、`SecondaryValidationResult`、`SetMiniLoginCookies` 等字符串说明登录系统存在这些状态，但只有当网页回调、Cookie 变化和 `/x/web-interface/nav` 身份查询全部对应起来，才能把它们写成 macOS 状态机。

## 3. 登录页：复用官方网页，而不是重造密码和验证码

### 3.1 选择官方 Mini Login 页面

登录页包含密码登录、二维码轮询、短信、图片验证码/极验和二次校验。自行制作密码表单会带来三个问题：

- 密码加密和设备参数容易失配；
- 验证码和风控页面会被破坏；
- 页面升级后，客户端会立即失效。

所以 macOS 端只做一个宿主：

- 用 `WKWebView` 加载官方页面；
- 负责窗口尺寸、导航和网页消息桥；
- 让页面自己完成密码、扫码、验证码和二次验证；
- 只接收登录完成、取消、二次校验完成和窗口尺寸变化等事件。

### 3.2 兼容 Windows 的 bridge

静态资源和旧版字符串共同显示，网页会探测两类宿主对象：

- `livehime_login`：页面完成、取消、二次验证和切换登录方式时使用；
- `biliBridgePc`：网页向桌面客户端写入刷新信息和 Cookie 时使用。

macOS 端没有把整个 Windows bridge 原样复制，而是实现最小兼容面：

```text
页面回调
  -> WKScriptMessageHandler
  -> AuthWebViewBridge
  -> LoginSessionCoordinator
```

桥接层只做类型归一化和事件转发，不记录密码、验证码、Cookie 或刷新令牌。

### 3.3 白屏问题的真正原因

早期版本在 `WKUserScriptInjectionTime.atDocumentStart` 暴露了过多的 Windows bridge。页面初始化时看到宿主对象后，会选择 Windows 原生宿主路径；但此时 DOM 和 Vue 页面尚未完成初始化，WKWebView 最终只剩白屏。

修复方法不是增加延时，而是调整注入时机：

1. `documentStart` 只注入页面初始化必须的 `window.browser` 元数据；
2. 等 `WKNavigationDelegate.didFinish` 确认首屏完成；
3. 再安装 `biliBridgePc.callNative` 和登录回调桥；
4. 页面提交登录时仍然走兼容调用。

这是一条很通用的经验：网页宿主兼容问题，先区分“页面选择了错误运行模式”和“网络没有加载”，不要用盲目重试掩盖初始化时序错误。

### 3.4 登录成功却回到起始页

登录成功最初没有被保存，原因不是账号密码错误，而是结果链路没有闭合：

- WKWebView 消息不总是桥接成 Swift 原生字典；
- 成功结果可能只有 `type`，刷新字段稍后才通过 Cookie 写入；
- 某些流程使用 `token`、`refreshToken` 或 `refresh_token` 不同别名；
- 登录页完成后会回到入口 URL，必须重新验证 Cookie，而不是把回跳当作失败。

修复后的顺序是：

```text
收到网页事件
  -> 归一化 NSDictionary/JSON
  -> 写入网页 Cookie（如果页面提供）
  -> 等待 Cookie store 落盘
  -> 请求 /x/web-interface/nav
  -> 确认用户身份
  -> 写入 Keychain
  -> 切换原生控制面
```

如果只有刷新信息而 Cookie 尚未出现，则等待官方页面的 Cookie handoff 完成，再重试身份查询。重试有明确上限；不会无限刷新页面。

## 4. 会话层：把“登录成功”变成可恢复状态

### 4.1 显式状态机

会话状态被建模为：

```text
signedOut
  -> signedIn
  -> secondaryValidationPending
  -> signedIn
  -> signedOut
```

其中 `secondaryValidationPending` 不是错误，而是等待网页二次验证完成的中间态。这样做可以避免：

- 二次验证过程中误删旧会话；
- 页面回跳时错误显示“登录失败”；
- 没有令牌时提前进入控制面；
- 退出登录时把仍在直播的账号状态清掉。

### 4.2 Keychain 边界

本地保存的是恢复登录所需的 opaque token 元数据，以及经 nav 验证后的必要会话信息。实现原则是：

- 使用独立 Keychain service/account；
- 不把 Cookie、刷新令牌、推流密钥写进日志；
- 测试使用隔离 service；
- 退出登录时清理 Keychain 和 Bilibili WebView 数据；
- 只有在直播停止状态被确认后才清理会话。

Keychain 解决的是本机持久化问题，不代表可以绕过 Bilibili 的账号校验；账号资格和风控仍由服务端决定。

## 5. Bilibili 直播控制：先读取状态，再做有条件的写操作

### 5.1 读取链路

登录完成后，原生控制面依次读取：

1. 当前用户身份；
2. 当前用户对应的直播间；
3. 可用直播分区；
4. 当前房间状态；
5. 若允许开播，再获取本次开播的上行配置。

解析器需要兼容接口返回的平铺结构和嵌套结构，例如分区可能出现在 `area_list`、`list` 或 `children` 中。解析层不直接把服务端 JSON 暴露给 UI，而是先转换成稳定的 Swift 模型。

### 5.2 开播状态机

开始直播不是“按一下按钮后立即启动 OBS”，而是：

```text
检查已登录
  -> 检查当前房间状态
  -> 选择分区
  -> 请求 Bilibili start-live/upstream
  -> 得到 RTMP server/key
  -> 配置 OBS service
  -> StartStream
  -> 轮询 OBS 状态
  -> 轮询房间状态
  -> 显示已开播
```

这样做有两个好处：

- 不会让 OBS 使用旧账号或旧房间的推流参数；
- 如果 Bilibili 返回账号资格、人脸验证或风控错误，UI 能明确告诉用户，而不是误报 OBS 故障。

常见错误应按类型处理：

- `-400`：请求参数、平台选择或服务端输入不匹配；
- `60043` 等身份/人脸验证错误：打开官方验证页面，用户完成验证后重试；
- OBS WebSocket 错误：保留 Bilibili 返回信息，不把它伪装成成功；
- 网络超时：保持当前会话，不清除账号状态。

### 5.3 停播和退出登录

停播必须同时处理两个状态：

```text
OBS output stopped
Bilibili room offline
```

只有 WebSocket 返回 `StopStream` 成功并不够，因为 OBS 可能仍处于 reconnecting 或状态查询不完整。当前实现会再次读取 `GetStreamStatus`，直到确认没有 active/reconnecting output。

Bilibili 侧也要重新查询房间状态。两边都确认结束后，UI 才显示“已关闭直播间”。

退出登录是同一套逻辑的复用：

```text
点击退出登录
  -> 如果未直播：直接清理会话
  -> 如果正在直播：并行停 OBS + 请求关闭房间
  -> 等两边都确认离线
  -> 清理 WebView Cookie 和 Keychain
  -> 回到登录页
```

如果停播状态不明确，应用保留当前登录态，避免用户失去关闭直播所需的凭据。

## 6. OBS 集成：用官方 WebSocket，而不是复刻 Windows 私有 IPC

### 6.1 为什么没有直接移植旧 OBS fork

旧版 `biliobs` 混合了 OBS、Qt、Win32、D3D、CEF 和多个第三方库，根目录没有一个可以直接套用的统一许可证。直接移植会同时承担：

- Windows 采集和音频路径重写；
- Qt/CEF 窗口重写；
- 老版本 OBS API 兼容；
- 混合第三方依赖的许可证核对；
- 旧账号和 IPC 代码的可维护性风险。

更稳定的做法是使用官方 OBS Studio arm64 构建，并把 LiveHime 做成控制面。

### 6.2 WebSocket v5 控制链

当前适配器实现了以下最小操作：

- `Hello` / `Identify`；
- OBS WebSocket v5 的 SHA-256 + Base64 challenge 认证；
- `GetStreamStatus`；
- `SetStreamServiceSettings`；
- `StartStream`；
- `StopStream`。

控制顺序是：

```text
连接 127.0.0.1:4455
  -> Hello
  -> 计算认证响应
  -> Identify
  -> SetStreamServiceSettings(url, key)
  -> StartStream
  -> GetStreamStatus
```

每个操作都有超时、取消和断线处理。网络层不能复用已经失效的 URLSession/Socket；断线后要让连接对象失效，下一次操作重新建立会话。

### 6.3 单一用户可见应用

OBS 仍然是独立进程，但它位于：

```text
LiveHimeMacApp.app
└── Contents/Resources/OBS.app
```

外层应用负责启动和控制它，OBS 的 `LSUIElement` 设置为 true，使其不在 Dock 和菜单栏形成第二个用户入口。这个设计既保留了 OBS 的成熟采集/编码能力，又让用户只需要操作一个 LiveHime 应用。

从许可证角度，独立进程和 localhost Socket 通信通常比把 `libobs` 静态链接进 Swift 宿主更容易保持边界；但实际分发仍然必须遵守 OBS GPL 和所有第三方依赖的许可证。

## 7. macOS 权限：权限属于实际采集进程

“给 LiveHime 权限”不一定等于“给 OBS 权限”。macOS TCC 关注实际访问摄像头、麦克风和屏幕的进程，以及它的代码签名身份。

因此外层宿主和嵌套 OBS 都补齐：

- `NSCameraUsageDescription`；
- `NSMicrophoneUsageDescription`；
- `NSScreenCaptureUsageDescription`；
- `NSAudioCaptureUsageDescription`。

权限界面只检查和引导，不假装已经获得授权。如果 OBS 仍处于运行状态或正在推流，应用不会直接替换 bundle 或重启它，以免出现签名和 TCC 身份不一致。

实际排障顺序是：

1. 关闭 LiveHime 和嵌套 OBS；
2. 检查系统设置中的对应条目；
3. 确认 `/Applications/LiveHimeMacApp.app` 与开发目录不是两个不同 bundle；
4. 重新启动同一个签名身份的应用；
5. 用 OBS 源设置窗口验证具体采集源，而不是只看宿主状态文本。

## 8. 构建、签名和发布

### 8.1 版本与构建

v0.1.0 的构建入口是：

```sh
cd macos-livehime-adapter
swift test
swift build -c release --product LiveHimeMacApp
scripts/package-app.sh
scripts/verify-bundle.sh
```

版本号在打包脚本的 `CFBundleShortVersionString` 中统一为 `0.1.0`。发布前必须先退出正在运行的宿主和 OBS，再替换 bundle。

### 8.2 签名顺序

嵌套应用必须先签，外层应用最后签：

```text
OBS.app 深度签名
  -> LiveHimeMacApp.app 外层签名
  -> codesign --verify --deep --strict
```

当前使用本地开发证书，不是 Apple Developer ID 签名，也没有 notarization。它适合本机和研究交流，不应让用户误解为官方公证发行版。

### 8.3 为什么 Release 上传 zip

`.app` 在文件系统中是目录包，不是普通单文件。Release asset 需要单个文件，因此使用：

```sh
ditto -c -k --sequesterRsrc --keepParent LiveHimeMacApp.app LiveHimeMacApp-v0.1.0-arm64.zip
```

这种方式可以保留应用包结构、执行权限和 macOS 资源属性。DMG 也可以作为后续发行格式，但 zip 更适合第一版技术验证。

### 8.4 许可证边界

OBS Studio 主体是 GPL-2.0-or-later。公开发布时必须保留 GPL 文本、作者信息和精确构建来源；如果重新分发修改后的 OBS 二进制，还需要提供对应源码或有效源码获取方式。

实际 OBS bundle 还包含 Qt、FFmpeg、x264、mbedTLS、SRT、RIST、libdatachannel、Syphon、DeckLink、AJA 和多个 OBS 插件。它们各有版权和许可证，不能全部笼统写成 MIT。v0.1.0 包内放置了 OBS 的 GPL 和构建说明，并在发布边界中明确第三方组件继续适用各自许可证。

旧 Windows `biliobs` 工程没有一个可以直接覆盖全树的根许可证，且包含 GPL、BSD、MPL 和其他第三方代码。因此它只作为本地研究参考，不作为 v0.1.0 的公开源码目录，也不发布 Windows 安装包、DLL 或 CEF 资源。

## 9. 测试策略

### 9.1 不自动化真实账号

真实登录、验证码、人脸验证、直播资格和推流状态都受账号与平台策略影响，不适合写进 CI。测试使用隔离数据和本地 fixture，不保存任何真实 Cookie 或推流密钥。

### 9.2 当前测试覆盖

v0.1.0 的 Swift 测试共 25 个，主要覆盖：

- WebView bridge 事件归一化；
- 登录 token 别名和二次验证状态；
- Keychain 隔离存储和退出登录；
- Bilibili 房间、分区、开播参数和错误解析；
- OBS WebSocket v5 认证向量；
- 独立连接、取消、超时和断线；
- StopStream 后等待 confirmed offline；
- reconnecting/recording 状态下禁止误报成功。

这类测试验证的是协议和状态机，不代表任何账号一定有开播资格，也不代表 Bilibili 页面永远不会变化。

## 10. 哪些方案被放弃，以及为什么

### 10.1 自制密码登录接口

放弃原因：密码加密、设备指纹、验证码和风控参数都属于平台动态实现。复刻它们会增加安全风险，也容易在页面升级后失效。改用官方 Mini Login 页面更稳定、更尊重平台验证边界。

### 10.2 过早注入完整 Windows bridge

放弃原因：会让网页误选原生宿主路径，造成白屏。最终只在首屏完成后注入必要 bridge。

### 10.3 把 WebSocket 成功当成停播成功

放弃原因：OBS 可能仍在 reconnecting，Bilibili 房间也可能尚未关闭。现在必须分别确认 OBS output 和服务器房间状态。

### 10.4 直接复刻旧命名管道 IPC

放弃原因：Windows IPC 的消息格式需要继续反汇编才能完整确定，而且它绑定旧 OBS fork。macOS 端使用官方 OBS WebSocket v5，接口更明确、测试更容易、跨版本维护成本更低。

### 10.5 把所有本地文件都推到 GitHub

放弃原因：工作区里有 Windows 专有分发物、解包 CEF、构建缓存、本地签名、日志和可能的账号数据。公开仓库只保留可审计源码、测试、脚本、许可证和构建边界。

## 11. 当前结论与后续方向

v0.1.0 的“打通”不是把旧 Windows 客户端逐字节搬到 Mac，而是通过证据把最小闭环恢复出来：

```text
官方网页认证
  -> Keychain 会话
  -> Bilibili 房间/开播状态
  -> RTMP 配置
  -> OBS WebSocket
  -> 可确认的开始/停止/退出登录
```

后续如果继续开发，优先级应该是：

1. 生成实际 Release bundle 的完整第三方依赖清单；
2. 让 OBS 场景、来源和采集权限配置更稳定；
3. 增加断线重连和异常恢复的可观测状态；
4. 评估 Intel Mac 支持；
5. 在需要对外分发时，准备 Apple Developer ID 签名和 notarization；
6. 对 Bilibili 页面和接口变化保持兼容测试，但不复制或绕过验证码、实名和风控实现。

这套方法的核心经验是：先建立边界，再做证据链；先把状态机闭合，再做 UI；先复用官方能力，再考虑替换底层实现。
