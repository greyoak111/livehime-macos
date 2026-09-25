# LiveHime macOS v0.2.8

## 新功能 / What's new

- **字幕保存为 SRT / Captions saved as SRT：** 语音字幕开着时，每次录制结束会在录像旁边保存同名的 `.srt`；
  直播结束会在录像文件夹保存“直播字幕 开播时间.srt”。时间取自识别引擎给出的说话时刻，从录制（不含暂停）或
  开播算起，可以直接导入剪辑软件或配合录播使用。可在“字幕”页关闭。
  With captions on, each recording gets a `.srt` with the same name next to it, and each stream a
  “直播字幕 <start>.srt” in the recording folder, timed from the start of the recording (pauses left out) or
  stream. Can be turned off on the Captions tab.
- **应用内更新 / In-app updates：** 面板新增“更新”页。默认自动检查、后台下载、退出时安装；也可以改成手动，
  走同一个下载通道。可选“参与测试版”，可以跳过某个版本，更新后可以回退到上一版本；每次安装前自动备份场景和
  设置。下载的安装包必须和 GitHub 公布的校验值一致、并由同一张证书签名才会安装；直播或录制时不会重启。
  A new Updates tab: automatic checks and background downloads installed on quit, or manual through the same
  path; an opt-in beta channel; skip a version or roll back; settings backed up before every install. Updates
  must match GitHub's checksum and be signed by the same certificate; LiveHime never restarts while streaming
  or recording.
- **B 站接口巡检 / Bilibili interface check：** “更新”页的“B 站接口巡检…”逐项检查 LiveHime 用到的 B 站
  接口、弹幕连接和官方页面（只读，登录后也检查账号的只读接口），报告可以直接贴到 Issue，不含账号信息。
  A read-only check of the Bilibili interfaces LiveHime uses; the report can go into an issue.

## Intel Mac 版 / Intel Macs

从 v0.2.8 起同时提供 Intel 版（`LiveHimeMacApp-v0.2.8-x86_64.dmg`），功能和 Apple 芯片版相同，以后也能在
应用里自动更新（Intel 版只会下载 Intel 的安装包）。语音字幕需要 macOS 26 或更高版本；Intel Mac 上能否使用
取决于系统是否提供本机语音识别，不支持时字幕页会提示。Intel 版在 Apple 芯片的 Mac 上交叉编译，在 Rosetta 下
检查过启动、插件加载和更新器，建议在真实的 Intel Mac 上也试一试，有问题欢迎反馈。
From v0.2.8 there is also an Intel build, with the same features and in-app updates (it only takes Intel
archives). Captions need macOS 26 and on-device speech recognition from the system. It was cross-built and
checked under Rosetta (launch, plugin, updater); reports from real Intel Macs are welcome.

## 升级 / Upgrade

**这一次需要手动升级：** 打开 DMG，把 LiveHime 拖到“应用程序”，选择“替换”。登录和设置都会保留。
从 v0.2.8 开始，以后的版本可以在应用里直接更新。
**Upgrade by hand this once:** open the DMG, drag LiveHime onto Applications and choose Replace. From v0.2.8
on, later versions update from inside the app.

## 验证 / Validation

- 端到端测试：字幕 SRT（与录像对齐误差约 0.06 秒，录制暂停 4 秒时正确扣除）；更新（校验值不符和其他证书
  签名的安装包被拒绝、正式版 / 测试版选择、跳过、下载校验安装并重启、跨 OBS 大版本回退并恢复设置，共 20 项）；
  正式版包对模拟的 0.2.9 完成检查、下载、校验和退出时安装；接口巡检（未登录时 11 项通过）。
  End to end: SRT timing and pauses; updates (rejected checksum and signer, stable/beta, skip, download,
  verify, install and relaunch, rollback across OBS major versions); the release build against a mock 0.2.9
  including install on quit; the interface check.
- Swift core：93 个测试通过，1 个需要联网的测试跳过。签名、arm64、Bundle ID 检查通过，和 v0.2.7 使用同一张
  签名证书；应用包里没有账号数据。
  Swift core: 93 passed, 1 network-gated skipped. Signature, arm64 and bundle id checks passed; same signing
  certificate as v0.2.7; no account data in the bundle.

## 源码 / Source

基于上游 OBS Studio `32.2.2`（`ba2f32bdf`）的补丁系列在 [`obs-fork/`](../obs-fork/)：Apple 芯片版对应补丁 0001–0048，
Intel 版对应 0001–0049（0049 只增加构建架构选项，并让更新器按架构选择安装包）。
The patch series on upstream OBS Studio `32.2.2` (`ba2f32bdf`) is in [`obs-fork/`](../obs-fork/): patches
0001–0048 for the Apple silicon app, 0001–0049 for the Intel app (0049 only adds the architecture option and
makes the updater pick the archive for its architecture).
