# 发布与维护规则 / Releasing and maintenance

适用于 v0.2.8 起（带自动更新的版本）。/ From v0.2.8, the first version that updates itself.

## 发布通道 / Channels

- **正式版 / Stable：** GitHub 上普通的 Release。所有用户默认只收正式版。
  A normal GitHub release; everyone gets these by default.
- **测试版 / Beta：** 勾选 Pre-release 的 Release。只有在“更新”页打开“参与测试版”的用户才会收到。
  A release marked Pre-release; only users who turned on “参与测试版” get it.
- 应用只接受这样的更新：zip 的 SHA-256 和 GitHub 公布的 digest 一致；里面的应用和当前应用的
  Bundle ID 相同（`local.livehime.macos`）、版本号和 Release 一致、签名有效且由同一张证书签名。
  The app installs an update only when the zip matches GitHub's SHA-256 digest and the app inside has
  the same bundle id, the release's version and a valid signature by the same certificate.
- 每个版本要同时发 Apple 芯片和 Intel 两份，附件名必须是 `LiveHimeMacApp-v<版本>-arm64.zip` 和
  `LiveHimeMacApp-v<版本>-x86_64.zip`（更新器按自己的架构找对应的包），DMG 给手动下载用。Intel 版在
  Apple 芯片的 Mac 上交叉编译：`ARCH=x86_64 BUNDLE_ID=local.livehime.macos build-aux/livehime/build-macos.sh`，
  并在 Rosetta 下启动检查。
  Every release ships both `LiveHimeMacApp-v<version>-arm64.zip` and `-x86_64.zip` (each build's updater
  looks for its own architecture), plus DMGs for manual downloads. Intel apps are cross-built with
  `ARCH=x86_64` and checked under Rosetta.
- 另外发一个装两个架构的安装包 `LiveHime-v<版本>-Installer.pkg`，这是给普通用户的**首选下载**：双击后一路“继续”，
  自动按芯片安装到“应用程序”，不用分辨芯片。它的名字不能以 `LiveHimeMacApp-` 开头、以 `.zip` 结尾，免得更新器误认。
  Also ship `LiveHime-v<version>-Installer.pkg` with both architectures, the **recommended download**: it
  installs the right build into Applications. Its name must never look like an updater zip.

## 打包 / Packaging

每个版本的附件（`dist/v<版本>/`），都从同一次构建出来：/ Every release's files, from the same builds:

| 附件 / File | 做法 / How |
|---|---|
| `LiveHimeMacApp-v<版本>-arm64.zip`、`-x86_64.zip` | `ditto -c -k --keepParent`，app 改名为 `LiveHimeMacApp.app` / the renamed app, zipped |
| `LiveHimeMacApp-v<版本>-arm64.dmg`、`-x86_64.dmg` | `build-aux/livehime/package-dmg.sh <app> <版本> <out.dmg>` |
| `LiveHime-v<版本>-Installer.pkg` | 见下 / below |
| `DEPENDENCY-INVENTORY-v<版本>.txt`、`-x86_64.txt` | `scripts/generate-bundle-inventory.py <app> <out>` |

安装包**从刚打好的两个 zip 里解出来的 app 打**，保证 pkg 里的和更新器下载的是同一份：
Build the pkg **from the apps unpacked from the two zips**, so it holds exactly what the updater installs:

```sh
v=<版本>; w=$(mktemp -d)
ditto -x -k dist/v$v/LiveHimeMacApp-v$v-arm64.zip  $w/arm64
ditto -x -k dist/v$v/LiveHimeMacApp-v$v-x86_64.zip $w/x86_64
obs-studio-clean/build-aux/livehime/package-pkg.sh $w/arm64/LiveHimeMacApp.app $w/x86_64/LiveHimeMacApp.app \
  $v dist/v$v/LiveHime-v$v-Installer.pkg
scripts/verify-installer-pkg.sh dist/v$v/LiveHime-v$v-Installer.pkg $w/arm64/LiveHimeMacApp.app $w/x86_64/LiveHimeMacApp.app
```

pkgbuild 会打印几行 `write: Permission denied`：它想复制系统保护的 `com.apple.provenance` 属性，不影响结果，
以检查脚本为准。/ pkgbuild prints a few `write: Permission denied` lines while copying the protected
`com.apple.provenance` attribute; harmless, the check script is what counts.

安装包没有签名（需要 Apple 的 Developer ID Installer 证书），所以用户第一次打开会被 Gatekeeper 拦下，
要在“隐私与安全性”点“仍要打开”；README 和发布说明里要一直写着这一步。
The pkg is unsigned (that needs a Developer ID Installer certificate), so Gatekeeper blocks the first open;
README and release notes must keep explaining Open Anyway.

### 浏览器组件 / Browser add-on

从浏览器组件正式上线起执行（计划见 [BROWSER_ADDON_PLAN.md](BROWSER_ADDON_PLAN.md)，应用内管理完成之前不发布组件）。
Applies once the browser add-on ships (see the plan; it is not published before in-app management is done).

组件跟 **OBS 底座**走，不跟 LiveHime 走：/ The add-on follows the **OBS base**, not LiveHime:
- **OBS 底座变了**（或组件本身有修复）：重新构建两个架构的组件，版本号递增，附件里放新的两个 zip 和新生成的 `addons.json`。
  **OBS base changed** (or the add-on has a fix): rebuild both architectures, bump its version, attach the two zips and a fresh `addons.json`.
- **OBS 底座没变**：不重建组件，把上一个版本的 `addons.json` 原样附上；里面的下载地址继续指向第一次发布那两个 zip 的 Release。
  **OBS base unchanged**: no rebuild; attach the previous release's `addons.json` unchanged. Its URLs keep pointing at the release that first carried the zips.

```sh
# obs-browser 子模块要先打上 obs-fork/browser-addon/0001（见该目录的 README）
# The obs-browser submodule must carry obs-fork/browser-addon/0001 (see that folder's README)
v=<版本>; a=<组件版本>
obs-studio-clean/build-aux/livehime/package-browser-addon.sh arm64  $a dist/v$v
obs-studio-clean/build-aux/livehime/package-browser-addon.sh x86_64 $a dist/v$v
scripts/verify-browser-addon.sh dist/v$v/LiveHime-BrowserAddon-v$a-arm64.zip  $w/arm64/LiveHimeMacApp.app
scripts/verify-browser-addon.sh dist/v$v/LiveHime-BrowserAddon-v$a-x86_64.zip $w/x86_64/LiveHimeMacApp.app
obs-studio-clean/build-aux/livehime/addons-manifest.py v$v dist/v$v/addons.json dist/v$v/LiveHime-BrowserAddon-v$a-*.zip
```

`$w` 是上面打 pkg 时解出来的两个 app：组件要对着**要发布的那个 app** 检查（OBS 底座、签名证书）。
CEF 放在 `obs-studio-clean/.deps`（arm64 约 90 MB，x86_64 约 100 MB），下载前征得维护者同意。
`$w` holds the two apps unpacked for the pkg: the add-on is checked against **the app being released** (OBS base, certificate).
CEF lives in `obs-studio-clean/.deps` (about 90 MB for arm64, 100 MB for x86_64); ask the maintainer before downloading.

## 什么时候发、走哪个通道 / What goes where

| 类型 / Kind | 通道 / Channel | 转正式版 / Promote to stable |
|---|---|---|
| B 站接口变动的紧急修复 / Fix for a Bilibili change | 测试版 → 正式版 | 维护者真实验证后，几小时内（旧版已经坏了，快比稳重要） / within hours, once verified for real |
| 普通功能和修复 / Features and fixes | 测试版 → 正式版 | 几天内没有问题反馈 / after a few quiet days |
| OBS 上游升级 / OBS upstream upgrade | 测试版 → 正式版 | 至少 1–2 周，并且维护者本人真实开播过几次 / 1–2 weeks and a few real streams by the maintainer |

**OBS 跟进节奏 / OBS cadence：**
- 大版本等到 x.y.1 或之后再跟，不追 x.y.0。/ Follow a major version from x.y.1 on, not x.y.0.
- 小版本只在修了我们用到的部分的安全问题时跟（FFmpeg、TLS、SRT、RTMP 等）。
  Minor versions only for security fixes in parts we use (FFmpeg, TLS, SRT, RTMP…).
- OBS 大版本会把场景和配置向前迁移，退回旧版可能读不了。更新器在每次安装前都会备份设置，回退时如果
  OBS 大版本不同会恢复更新前的场景和配置；发布说明里要写明“这次升级了 OBS”。
  OBS migrates scenes and settings forward only. The updater backs up settings before every install and
  restores them on a rollback across OBS major versions; release notes must say when OBS is upgraded.

## 发布前关卡 / Release gate

1. Swift core：`swift test` 全部通过。/ All Swift core tests pass.
2. 端到端测试（`obs-studio-clean/build-aux/livehime/tests`）全部通过，至少包括推流、字幕、SRT、
   悬浮聊天、全屏置顶和更新（`e2e-update.mjs`）。/ The end-to-end tests pass, including streaming,
   captions, SRT, floating chat, full screen and updates.
3. 维护者用真实账号开播一次：登录、开播、弹幕、下播。/ One real stream by the maintainer.
4. 签名、架构（arm64 / x86_64）、Bundle ID 检查；应用包里没有账号数据、Cookie、推流码或签名密钥。
   Signature, architecture and bundle id checks; no account data or keys in the bundle.
5. `scripts/verify-installer-pkg.sh` 全部 PASS；维护者双击安装一次，确认装进“应用程序”、应用归当前用户所有
   （`find /Applications/LiveHimeMacApp.app -not -user $USER` 没有输出），能正常打开。
   The pkg check passes; the maintainer installs it once and confirms the app is in Applications, owned by
   the user, and opens.
6. 补丁系列在干净的上游 tag 上 `git am` 后和发布用的代码树一致；更新依赖清单和 BUILD-INFO。
   The patch series reproduces the released tree on a clean upstream tag; inventory and BUILD-INFO updated.
7. 发布说明写清改了什么、是否升级 OBS、是否会迁移设置；**开头先放“下载哪个文件”的表**（pkg 推荐、DMG、
   更新用的 zip、Source code 不是软件），照 [v0.2.10 的发布说明](RELEASE_NOTES_v0.2.10.md) 的格式。
   Release notes say what changed, whether OBS was upgraded and whether settings migrate, and **open with
   the “which file to download” table**, as in the v0.2.10 notes.
8. （组件上线后）`scripts/verify-browser-addon.sh` 两个架构全部 PASS；`addons.json` 已附上，且其中组件的
   `obs` 与这次发布的 OBS 底座一致；`e2e-addon.mjs` 和 `e2e-addon-update.mjs` 全部通过。
   (Once the add-on ships) the add-on check passes for both architectures, `addons.json` is attached with an
   `obs` that matches this release's OBS base, and the two add-on end-to-end tests pass.

## 出问题时 / When a release is bad

- **撤回 / Pull it：** 在 GitHub 上把这个 Release 改回 Pre-release（或删掉它的 zip）。还没装的正式版用户
  就不会再收到。/ Turn it back into a pre-release (or remove its zip); stable users who have not
  installed it stop getting it.
- **往前修 / Fix forward：** 已经装上的用户，发一个版本号更高的修复版。不做远程降级。
  Ship a higher-numbered fix for those who installed it; no remote downgrades.
- **用户自救 / Users：** 更新页的“回退到上一版本”会换回上一个版本并跳过出问题的版本；“跳过此版本”
  可以让自动更新不装某个版本。/ “Roll back” in the Updates tab restores the previous version and skips
  the bad one; “Skip This Version” keeps automatic updates away from a version.

## B 站接口 / Bilibili interfaces

- 不做定时巡检。出问题时（或发版前）在“更新”页点“B 站接口巡检…”，逐项检查只读接口、弹幕连接和官方
  页面；登录后也检查账号的只读接口。报告可以直接贴进 Issue，不含账号信息。
  No scheduled checks. When something breaks (or before a release), run “B 站接口巡检…” on the Updates
  tab; the report can go into an issue and holds no account data.
- 开播、下播、发弹幕、禁言这类写入操作无法巡检，只能靠真实开播验证和用户反馈。
  Writes (going live, sending, muting) cannot be checked; they need a real stream and user reports.

## 签名证书 / Signing certificate

- 发布版和开发版都用同一张本地证书签名：“LiveHime Local Development”，有效期到 2036-09-06，存放在
  `~/Library/Application Support/LiveHime/DevelopmentSigning`。更新器用它来确认新版本是真的。
  Releases and development builds are signed with one local certificate (valid until 2036-09-06); the
  updater relies on it to trust new versions.
- 离线备份在“文稿”里的“LiveHime 签名证书备份 2026-09-25”（里面有恢复说明）。再备一份到加密 U 盘更稳妥。
  An offline backup is in Documents (“LiveHime 签名证书备份 2026-09-25”, with restore notes); a second
  copy on an encrypted drive is safer.
- 丢了它，所有用户的自动更新都会失败（只能手动下载，并重新授予屏幕录制等权限）。不要放进 GitHub、CI 或网盘。
  Losing it breaks every user's automatic updates. Never put it in GitHub, CI or cloud storage.
- 不要随意更换 Bundle ID、钥匙串服务名或配置目录；这类改动需要单独设计迁移，不能通过自动更新悄悄发布。
  Do not change the bundle id, Keychain service or settings folder in a normal update; that needs a
  separate migration design.
