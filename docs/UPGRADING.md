# 升级 LiveHime macOS

从 `v0.1.0` 升级到 `v0.1.1` 不需要重新登录，也不需要导出账号数据。两个正式版本保持同一个
`CFBundleIdentifier`（`local.livehime.macos`）和同一个 Keychain service（
`local.livehime.macos.session`）。因此替换 `/Applications/LiveHimeMacApp.app` 时，macOS
会继续使用原来的登录会话；默认 WebKit 数据目录也按同一个应用身份保留。

最简单的操作方式是：

1. 在 [Releases](https://github.com/greyoak111/livehime-macos/releases) 下载最新的
   `LiveHimeMacApp-<version>-arm64.zip`。
2. 解压得到 `LiveHimeMacApp-<version>.app`，退出 LiveHime 和内置 OBS。
3. 如果解压后的文件名带版本号，先把它重命名为 `LiveHimeMacApp.app`，再拖入“应用程序”；
   Finder 询问替换时选择“替换”，然后从“应用程序”启动。这样不会因为文件名不同而在“应用程序”里留下两个副本。

替换前不要删除旧 App，也不要在终端里清空 `~/Library/Keychains`、
`~/Library/WebKit` 或 `~/Library/Application Support`。这些位置保存了登录会话、网页状态和
OBS 用户配置。升级脚本只移动目标 App 本身，成功后临时回滚副本会被清理，不会触碰这些数据。

熟悉终端的用户可以运行仓库内的安全替换脚本：

```sh
macos-livehime-adapter/scripts/install-release-app.sh \
  /path/to/LiveHimeMacApp-v0.1.1.app
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
