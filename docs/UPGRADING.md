# 升级 LiveHime macOS

## 从 v0.1.x 升级到 v0.2.0

v0.2.0 把应用整个换成了带直播姬面板的 OBS，但保留了同一个应用身份：
`CFBundleIdentifier` 仍是 `local.livehime.macos`，应用名仍是 `LiveHimeMacApp.app`，登录信息
仍存在钥匙串项 `local.livehime.macos.session` 里。

1. 先结束直播，退出 LiveHime 和 v0.1.x 内置的 OBS。
2. 打开 `LiveHimeMacApp-v0.2.0-arm64.dmg`，把 LiveHime 拖到“应用程序”，选择“替换”。
3. 打开应用。如果被系统拦下，到 系统设置 → 隐私与安全性，点“仍要打开”。

升级后需要注意：

- **登录：** 通常会自动沿用。如果 v0.1.x 只保存了部分凭据，面板会提示“旧版本的登录信息无法沿用”，
  重新扫码登录即可。
- **权限：** 应用的可执行文件变了，macOS 会重新询问屏幕录制、麦克风和摄像头权限。
- **场景：** v0.2.0 的 OBS 配置放在 `~/Library/Application Support/LiveHime/obs-studio`。
  v0.1.x 内置 OBS 用的是普通 OBS 的配置目录（`~/Library/Application Support/obs-studio`），
  所以原来的场景不会自动出现。需要的话，在 v0.2.0 里用 场景集合 → 导入，选择
  `~/Library/Application Support/obs-studio/basic/scenes/` 里的 `.json` 文件。
- **回滚：** 替换前把旧的 `LiveHimeMacApp.app` 拷一份到别处，就可以换回去；两个版本不要同时运行。

## v0.1.x 之间的升级（历史）

从 `v0.1.0` 或 `v0.1.1` 升级到 `v0.1.2` 不需要重新登录，也不需要导出账号数据。这些正式版本保持同一个
`CFBundleIdentifier`（`local.livehime.macos`）和同一个 Keychain service（
`local.livehime.macos.session`）。因此替换 `/Applications/LiveHimeMacApp.app` 时，macOS
会继续使用原来的登录会话；默认 WebKit 数据目录也按同一个应用身份保留。

最简单的操作方式是：

1. 在 [Releases](https://github.com/greyoak111/livehime-macos/releases) 下载最新的
   `LiveHimeMacApp-<version>-arm64.dmg`。
2. 退出 LiveHime 和内置 OBS，双击打开 DMG。窗口中会显示 LiveHime 和“应用程序”文件夹。
3. 把 LiveHime 图标拖到“应用程序”文件夹图标上；Finder 询问替换时选择“替换”，然后从“应用程序”启动。

也可以下载 zip 手工替换。当前 v0.1.2 zip 内的 App 已经命名为 `LiveHimeMacApp.app`；如果使用旧版
资产且解压后的文件名带版本号，先重命名为 `LiveHimeMacApp.app`，避免留下两个副本。

替换前不要删除旧 App，也不要在终端里清空 `~/Library/Keychains`、
`~/Library/WebKit` 或 `~/Library/Application Support`。这些位置保存了登录会话、网页状态和
OBS 用户配置。升级脚本只移动目标 App 本身，成功后临时回滚副本会被清理，不会触碰这些数据。

熟悉终端的用户可以运行仓库内的安全替换脚本：

```sh
macos-livehime-adapter/scripts/install-release-app.sh \
  /path/to/LiveHimeMacApp-v0.1.2.app
```

默认目标是 `/Applications/LiveHimeMacApp.app`，也可以传入第二个参数指定其他安装位置。脚本会：

- 校验候选包是正式 `local.livehime.macos` 身份，并检查代码签名；
- 发现 LiveHime 或内置 OBS 正在运行时停止，不强杀进程；
- 先在同一目录暂存候选包，再原子替换旧 App，失败时尽量恢复旧包；
- 不迁移、不读取、不输出 Keychain、Cookie、Token、推流码或 OBS 配置。

首次从旧的临时/验证包迁移时，可能出现一次新的权限提示。`local.livehime.macos.validation` 是刻意隔离
的测试身份，不能用它覆盖正式包，也不会自动迁移测试登录态。

升级后如果仍显示旧版本：完全退出 LiveHime（包括菜单栏/后台进程），确认“应用程序”里只剩一个
`LiveHimeMacApp.app`，再重新打开。账号会话丢失时先检查 Keychain 中是否仍有
`local.livehime.macos.session`，不要重复登录或清理系统 Keychain。
