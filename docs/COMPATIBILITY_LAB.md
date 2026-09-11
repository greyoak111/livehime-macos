# 兼容性测试分支与维护路线

本轮使用独立 Git worktree：`/Users/sunxifeng/livehime-macos-compat-lab`，分支
`codex/compatibility-hardening`，从 `ee56fb5` 建立。原工作目录的 `main`、已安装应用和
v0.1.0 Release 保留为基线。这条分支尚未合并、推送或发布。

## 为什么采用独立路径

worktree 共享 Git 对象和历史，拥有独立源码、索引和构建目录。相较复制一份无版本记录的
文件夹，这样能准确审阅、分步合并或撤销每个维护改动。它不复制 Windows 研究包、OBS
构建产物、签名材料或账号数据。

源码隔离不等于运行时账号隔离。`LiveHimeMacApp` 仍是待验证的真实宿主，其历史账号和
OBS 存储规则没有全部重新设计。因此本轮只运行独立的 **LiveHimeCompatLab**，不启动真实宿主。

## 运行离线测试 App

```sh
cd /Users/sunxifeng/livehime-macos-compat-lab
macos-livehime-adapter/scripts/package-compat-lab.sh
open macos-livehime-adapter/dist/LiveHimeCompatLab.app
```

测试 App 的 Bundle ID 是 `local.livehime.compat-lab`，显示名称为
`LiveHime Compatibility Lab`。它使用内存登录状态、`WKWebsiteDataStore.nonPersistent()`、
本地 HTML、内容规则和 CSP；只允许 `about:` 导航。网络阻断规则加载失败时，页面不会加载。
它没有 OBS 启动路径，不访问真实账号 Keychain，不请求采集权限。

窗口内可模拟成功、取消、二次验证返回、尺寸变化、Cookie 写入后回调，以及未知方法报错。
“重置模拟会话”清空内存会话并重载页面；关闭窗口释放临时网页数据。

打包只生成测试 App，使用 ad-hoc 签名，不使用生产签名证书、不安装到 `/Applications`。
打包时拒绝覆盖正在运行的该测试 App。重打包保留带时间戳的上一份测试 App；这仅是测试产物
回退机制，不代表已经完成生产自动更新器。

## 一次运行全部离线回归

```sh
cd /Users/sunxifeng/livehime-macos-compat-lab
scripts/test-compatibility.sh
```

## 更新前只读安全检查

在任何未来安装器出现之前，先对候选包做预检。它不会改变文件系统：

```sh
python3 scripts/bundle-update-safety.py inspect \
  macos-livehime-adapter/dist/LiveHimeCompatLab.app

# 只对本地测试 fixture 跳过签名检查；正式候选包不要使用这个选项
python3 scripts/bundle-update-safety.py --skip-signature inspect \
  macos-livehime-adapter/dist/LiveHimeCompatLab.app

python3 scripts/bundle-update-safety.py compare OLD.app NEW.app
```

预检会拒绝 Bundle 内的 symlink、私有/凭据目录和 Cookie/Token/Session/密钥文件，确认
宿主与嵌套 OBS 的 Bundle 身份不同，并检测两个进程的精确可执行路径。运行中的任一组件
都会得到 `blocked`；检测通过也只表示“可以进入人工审阅”，不会自动安装。
OBS 正常携带的固定路径 `OBSPublicRSAKey.pem` 是公开验证公钥，预检只对白名单中的这一
个路径放行；其他 PEM、KEY、Token 或会话文件仍然会被拒绝。

候选包的版本、主程序和嵌套 OBS 变化会得到 `review_required`。当前生产更新仍未实现，
因此不会因为预检通过就触碰 `/Applications` 或已安装的 v0.1.0。

Swift 测试包含真实 WKWebView 中的 JavaScript Promise、原生异步回复、旧桥接事件和
Origin 策略测试；Bilibili HTTP 使用 URLProtocol 截获全部请求；OBS 使用本机随机端口
上的 WebSocket fixture。测试不会向 Bilibili 登录或开关播，也不会连接已安装 OBS 的端口。

真实 Keychain 测试默认跳过。如后续要验证系统 Keychain，只可单独显式启用
`LIVEHIME_TEST_KEYCHAIN=1`；它使用随机服务名和虚拟 token，不访问日常会话。

## 本轮实现

| 方面 | 已落地的行为 | 证据范围 |
| --- | --- | --- |
| 脱敏诊断 | 最多 128 条内存记录，白名单字段；真实宿主增加导出/清空菜单 | HTTP 状态、API 错误、URL 错误码、阶段和耗时；不保存正文、Cookie、URL、账号、验证票据或推流密钥 |
| 错误处理 | 身份读取与直播接口统一区分网络、HTTP、API 和 JSON 结构错误；保留 Retry-After 提示 | URLProtocol fixture 覆盖身份成功、未登录、HTTP 429、结构损坏和超时；不自动重放开播 POST，`-400` 不再触发切换客户端标记后重试 |
| 网页桥接 | 登录主窗口、HTTPS、精确来源和主框架校验；两种支持的方法显式解析 | 原生 Cookie 写入完成才回复；拒绝未知方法；保留原先 document-finish 注入时机 |
| 网页加载 | 导航失败、20 秒超时和 WebContent 退出进入可诊断状态 | 导航成功不等于网页组件渲染成功，更不等于身份验证成功 |
| 官方变化观察 | 公开版本、两个入口页、HTML 与脚本/CSS引用的指纹 | 只记录观察结果；变化要求复查，不自动认定不兼容、不改客户端版本 |
| OBS 回归 | 延迟停止、重连、状态畸形、取消、并行请求和录制状态等本地测试继续通过；退出应用会保护未确认的输出状态 | 没有重新打开 OBS、采集设备或真实直播间 |

## 后续合并条件

1. 先审阅离线回归与脱敏输出，然后分步合并诊断、只读探针、网页桥接改动。
2. 官方页面需要按真实账号做人工兼容性验证，尤其来源限制、Cookie 写入顺序、二次验证
   返回和 token 别名。离线模拟不能代替这个结论。
3. 真实关播/退出流程需在可控直播测试中再次确认；仅收到接口 `code=0` 不能证明房间已关闭。
4. 生产更新必须确认宿主、内置 OBS 都已退出，且输出/录像已停止，再切换经过校验的完整包。
   保留旧包并核对签名要求、OBS 精确版本和第三方通知；直播中只提示有更新。

## 已知未完成项

- 尚未实现生产自动更新、下载签名验证、原子安装和完整回滚流程。
- `startLive` 仍保留历史代码的“读取公开版本再使用其版本字段”行为；测试分支没有将观察到的
  新版本认证为已兼容。后续应把经过人工验证的请求配置与公开版本观察拆开，并处理未知版本。
- 只读探针不下载、执行官方 JavaScript，也不比较官方 Windows 二进制。脚本 URL 不变而内容
  改变、服务端规则变化、按账号灰度发布，都可能不被当前页面指纹发现。
- 没有完整还原平台服务端放行条件，也没有获得平台对第三方客户端的授权证明。历史成功仅证明
  当时那次测试可用。验证码、人脸验证和资格判断仍由平台决定。

公开探针的命令和输出解释见 [COMPATIBILITY_CHECKER.md](COMPATIBILITY_CHECKER.md)。
