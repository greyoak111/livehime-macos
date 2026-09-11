# LiveHime macOS

LiveHime macOS 是 **第三方的 LiveHime（直播姬）macOS 原生适配版**。它不是
Bilibili、OBS Project 或原 Windows 直播姬作者的官方产品，也不代表这些项目的
立场或承诺。

本项目仅供学习、研究和社区交流使用。项目初衷是为 macOS 用户提供一条使用
Bilibili 直播功能的本地路径，尤其方便部分账号在 Bilibili 侧能够通过直播姬获得
开播配置、但普通 OBS 流程无法直接使用推流码的场景。平台资格、粉丝门槛、实名/人脸
验证和风控规则可能变化。项目不自动完成验证码或人脸验证；历史测试成功不等于
平台认可该第三方客户端，也不能证明所有账号均满足平台的开播资格。

项目本身不提供商业服务，也没有商业盈利目的；这不改变第三方组件各自的许可证，
也不构成对 Bilibili 服务条款的豁免。使用者应自行确认账号资格、内容合规和平台
规则，并对自己的直播行为负责。

## 独立兼容性测试分支

当前 `codex/compatibility-hardening` 分支用于离线测试补强。推荐从独立 worktree 运行
`macos-livehime-adapter/scripts/package-compat-lab.sh`，打开生成的 **LiveHime Compatibility Lab**。
它不读取真实账号或启动 OBS。测试路径、诊断输出、公开页面观察和合并条件见
[兼容性实验室说明](docs/COMPATIBILITY_LAB.md)。这不是新的正式 Release。
进入真实账号验证前，先按[真实验证计划](docs/REAL_VALIDATION_PLAN.md)逐轮执行；验证由用户
在本机完成，测试代码不会读取或导出账号凭据。真实验证包必须用独立的
`local.livehime.macos.validation` Bundle ID 打包，避免复用正式包的 Keychain 和 WebKit 数据。

更新候选包前可运行只读预检：

```sh
python3 scripts/bundle-update-safety.py inspect /path/to/Candidate.app
```

预检通过不会自动替换已安装版本；它只确认包身份、签名、运行状态和敏感文件边界。

## v0.1.1 包含内容

### 从旧版本升级

正式版从 v0.1.0 起保持 `local.livehime.macos` Bundle ID 和
`local.livehime.macos.session` Keychain service。用户直接从
[Releases](https://github.com/greyoak111/livehime-macos/releases) 下载最新 arm64 zip，退出
LiveHime/内置 OBS 后把新 App 拖进“应用程序”并选择替换即可保留登录态和 OBS 用户配置。
不要删除 Keychain、WebKit 或 Application Support 数据；同 Bundle ID 覆盖安装不会清理这些
数据。需要脚本化安装时使用
[`docs/UPGRADING.md`](docs/UPGRADING.md) 中的安全替换脚本。

升级前请先停止直播，并确认 LiveHime 和内置 OBS 都已退出；不要覆盖正在运行的应用。主界面
的“检查更新”按钮只打开上面的 Releases 页面，不会后台下载、替换 `/Applications`、重启
应用或终止 OBS。下载后按 `docs/UPGRADING.md` 的 Finder 或脚本流程手动替换；这样可以在
未公证的开发签名包环境下保留文件来源、权限提示和旧版本回滚能力。

如果旧版使用了其他 Bundle ID（例如 `local.livehime.macos.validation` 验证包），或者用户
主动删除了 Keychain/WebKit 数据，则不能保证无缝恢复，需要重新登录。替换前保留旧 `.app`
副本即可回滚，但回滚同样必须先退出 LiveHime 和内置 OBS。

- AppKit + WKWebView 原生 macOS 宿主，目标 macOS 13+、Apple Silicon arm64。
- 承接 Bilibili 官方 mini-login 页面，支持账号密码、二维码、短信、图片验证码/极验、
  二次验证和开播所需的人脸验证页面；应用不自动完成或绕过这些验证。
- 使用 macOS Keychain 保存登录会话，支持恢复登录和退出登录。
- 登录后读取直播间和可用分区，开播时获取 Bilibili 返回的 RTMP server/key。
- 在同一个 LiveHimeMacApp.app 内隐藏运行 OBS backend，通过 OBS WebSocket v5 设置推流、
  开始直播、停止直播和读取状态。
- 结束直播同时请求 OBS 停止输出和 Bilibili 关闭直播间；退出登录前自动关播，确认两边
  都离线后才清理会话，便于开播前切换账号。
- 检查摄像头、麦克风、屏幕录制和系统音频权限。

## 构建与测试

适用环境是 Apple Silicon macOS 13+，需要 Swift 5.9+、Xcode Command Line Tools 和
CMake。适配器源码位于 `macos-livehime-adapter/`：

```sh
cd macos-livehime-adapter
swift test
swift build -c release --product LiveHimeMacApp
scripts/package-app.sh
scripts/verify-bundle.sh
```

打包脚本会在相邻的 OBS 构建存在时，把完整的 `OBS.app` 放进宿主的
`Contents/Resources/OBS.app`。当前公开仓库不包含生成的 `.app`、Windows 安装包、
Bilibili 客户端 DLL/CEF 文件、账号数据、日志或本地签名密钥。OBS 的精确源码版本和
构建信息见 [`ThirdPartyLicenses/OBS/BUILD-INFO.md`](ThirdPartyLicenses/OBS/BUILD-INFO.md)。

## 已知限制

- v0.1.1 是本地证书签名、未经过 Apple notarization 的开发构建；首次运行可能需要
  macOS 隐私权限。
- 当前只提供 Apple Silicon arm64 构建，不包含 Intel Mac 构建。
- Bilibili 页面、接口、账号资格、地区网络、人脸验证和风控策略都可能变化；应用不保证
  长期兼容，也不能替代官方客户端或绕过平台校验。
- 内置 OBS 是 GPL 组件，插件、Qt、FFmpeg、编码器和其他依赖各自保留版权与许可证。
  对外重新分发二进制时，必须提供对应源码/源码获取方式和完整第三方许可证清单。

## 项目性质与许可证

LiveHime macOS 宿主源码按根目录 [`LICENSE`](LICENSE) 发布。内置 OBS Studio 按 GNU
GPL v2 或更高版本发布，许可证和构建来源见 [`ThirdPartyLicenses/OBS/`](ThirdPartyLicenses/OBS/)。
LiveHime macOS 是第三方社区适配项目，名称、图标和服务接口不表示与 Bilibili、OBS
Project 或原 LiveHime 项目存在官方关联。

## 贡献与问题反馈

请提交不含账号、Cookie、Token、直播密钥、验证码内容或个人日志的最小复现信息。涉及
Bilibili 账号的数据不要上传到 Issue、讨论区或仓库。
