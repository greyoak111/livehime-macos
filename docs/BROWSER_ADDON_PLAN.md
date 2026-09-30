# 浏览器来源可选组件 + 更新说明弹窗：计划书 / Browser source add-on + What's New dialog: plan

2026-09-29 起草，2026-09-30 修订（组件改为独立版本、两阶段更新、状态机；新增更新说明弹窗）。组件 P0 已完成（可行），P1 起未开工。
Drafted 2026-09-29, revised 2026-09-30. Add-on P0 done (feasible); P1 onward not started.

第一部分是浏览器来源组件，第二部分是更新说明弹窗。两者互相独立，可以分开做；弹窗更小，适合先做。
Part 1 is the browser add-on, part 2 the What's New dialog. They are independent; the dialog is smaller and can come first.

---

# 第一部分：浏览器来源可选组件 / Part 1: browser source add-on

## 起因 / Why

有用户在 B 站评论里问“添加源里怎么没有浏览器”。OBS 的浏览器来源要内置整套 Chromium（CEF），
v0.2.0 起我们关掉了它（`ENABLE_BROWSER=OFF`）：体积大、签名复杂，和“不做重型软件”的初衷冲突。

A user asked on Bilibili why there is no Browser source. OBS's browser source bundles a whole Chromium (CEF);
we have built with `ENABLE_BROWSER=OFF` since v0.2.0 for size and signing reasons, and to stay lightweight.

## 决定 / Decision

做成**可选、可拔插的组件**：主程序保持现在的体积，需要的人在应用里一键下载安装，不需要的人完全不受影响。
A **pluggable, optional add-on**: the app keeps its size; those who want it install it from inside the app.

放弃的做法 / Rejected:
- 直接打进主程序：应用从约 181 MB 涨到约 400 MB 以上（待实测），每个浏览器来源还会额外启动几个 Chromium 进程。
  Bundling it: the app grows from about 181 MB to roughly 400 MB or more (to be measured), plus Chromium processes per source.
- 用系统 WKWebView 自己实现：macOS 没有把网页逐帧渲染进直播画面的接口，只能绕路，帧率和稳定性难保证。
  A WKWebView version: macOS has no API to render a page frame by frame into the canvas.
- 组件与应用同版本发布（初稿的做法）：每次发版都要重新下载约 90 MB 的 CEF，而且主体和组件必须同步更新，容易出现半截状态。
  Versioning the add-on with the app (first draft): about 90 MB of CEF re-downloaded every release, and app and add-on must update in lockstep.

## 已查明的事实 / Facts established

- **CEF 版本**：OBS 32.2.2 在 `CMakePresets.json` 里固定为 `6533`，revision 5；官方 CDN 上
  `cef_binary_6533_macos_arm64_v5.tar.xz` 88.5 MB、`…_x86_64_v5.tar.xz` 98.7 MB，SHA-256 也在 `CMakePresets.json` 里。
  CEF 6533 revision 5 is pinned by OBS 32.2.2; the official archives are 88.5 MB (arm64) and 98.7 MB (x86_64), hashes in `CMakePresets.json`.
- **插件搜索路径**：`frontend/widgets/OBSBasic.cpp` 会扫描用户目录
  `GetAppConfigPath("obs-studio/plugins/%module%.plugin")` 下的 `Contents/MacOS` 与 `Contents/Resources`。
  组件放在这里就能被加载，不用改主程序的加载逻辑。LiveHime 隔离了配置目录，实际路径预计是
  `~/Library/Application Support/LiveHime/obs-studio/plugins/obs-browser.plugin`，**P0 实测确认**。
  OBS already scans a per-user plugin folder; with LiveHime's isolated config it should be the path above (confirm in P0).
- **签名**：已发布的应用没有开 Hardened Runtime（`codesign` flags 为 none，无 entitlements），
  所以没有库校验，加载外部插件不会被系统拦；CEF 需要的 JIT 也不受限。
  The released app has no Hardened Runtime, so no library validation blocks an external plugin and JIT is not restricted.
- **更新器下载的是应用包，不是源码**：`AppUpdater` 取 Release 附件 `LiveHimeMacApp-v<版本>-<架构>.zip`，
  校验 SHA-256（与 GitHub digest 一致）、bundle id、版本号和签名证书，并已有 `obsVersion(of:)` / `obsMajor(_:)`
  读取应用内 libobs 版本。组件的兼容检查可以复用这些。
  The updater downloads the release asset (the packaged app), not the source zip; it already reads the libobs version inside an app, which the add-on check can reuse.

## 设计 / Design

### 组件的形态 / Shape
- 一个独立的 `obs-browser.plugin` 包：`Contents/MacOS/obs-browser`，`Contents/Frameworks/` 里放
  `Chromium Embedded Framework.framework` 和四个辅助程序（Helper、GPU、Plugin、Renderer），`Contents/Resources/` 放资源。
- 用同一张本地签名证书签名，和主程序一致。
- 主程序继续用 `ENABLE_BROWSER=OFF` 构建；组件在单独的构建目录里用 `ENABLE_BROWSER=ON` 编出来，只取插件那部分。

### 要改的地方 / Changes
- obs-browser 默认去**主程序**的 `Contents/Frameworks` 找 CEF 和辅助程序。要改成从**插件自己的包**里找
  （CefSettings 的 `framework_dir_path`、`browser_subprocess_path`、`main_bundle_path`），可能需要一个小补丁。**这是 P0 的最大风险。**
  obs-browser looks for CEF in the app bundle; it must find it inside its own plugin bundle. Biggest P0 risk.
- OBS 分支的启动流程里，在加载所有模块**之前**，加一步“处理待生效 / 待移除”（见下文）。

### 版本：组件跟 OBS 底座走，不跟 LiveHime 走 / Versioning follows the OBS base, not LiveHime
- 组件依赖的是 libobs 的接口，不是 LiveHime 插件的代码。LiveHime 平时发版大多只改自己的插件，OBS 底座不变，组件就不用动。
- 组件有**自己的版本号**，并在清单里声明它要求的 OBS 版本（例如 `32.2`，比对到“主版本.次版本”）。
- 只有升级 OBS 底座时，才需要发新组件。这样绝大多数版本里，主体和组件根本不存在同步问题。
  The add-on has its own version and declares the OBS version it needs; only an OBS base upgrade requires a new add-on.

### 清单文件 / Manifest
组件包内 `Contents/Resources/addon.json`：

```json
{ "id": "browser-source", "version": "1.0.0", "obs": "32.2", "arch": "arm64", "cef": "6533.5" }
```

Release 附件里另有一份 `addons.json`（给更新器看）：每个组件的版本、要求的 OBS 版本、各架构附件名和 SHA-256。

### 状态 / States

| 状态 | 判定 | 界面按钮 |
|---|---|---|
| 未安装 / Not installed | 插件目录里没有组件 | 下载安装（约 N MB） |
| 已安装 / Installed | 清单完整、签名有效、`obs` 与当前 libobs 相符 | 移除 |
| 需要更新 / Update needed | `obs` 与当前 libobs 不符 | 更新 |
| 重启后生效 / Pending restart | “待生效”或“待移除”目录里有内容 | 立即重启 |
| 已损坏 / Damaged | 清单缺失、签名无效或证书不同 | 重新安装 |

**只有“已安装”状态才会被加载**；其余状态一律不加载，主程序照常工作，“添加源”里就是没有浏览器，和现在一样。
Only the Installed state is loaded; in every other state the app works as it does today.

### 两阶段：先备齐，再一次性切换 / Two phases: stage everything, then switch once
所有安装和更新都分两步，任何一步失败都不动现有文件：

1. **备料 / Stage**：下载到临时目录 → 校验（SHA-256 对照 `addons.json`、签名证书与主程序相同、清单 `obs`/`arch` 正确）
   → 放进“待生效”目录 `…/LiveHime/addons-pending/obs-browser.plugin`。
2. **切换 / Switch**：下次启动时，在加载模块之前，把“待生效”的组件原子地换进插件目录
   （同一卷上 `rename`；旧组件先移到废纸篓）。换上之后再按上表判定状态。

**和应用更新合在一起时 / Together with an app update**
- 更新器先查 `addons.json`：新版本如果要求新的组件（OBS 底座变了），且用户装了组件，就把组件也列进这次更新。
- 主体和组件**都备齐、都校验通过**之后，才替换主体并重启；组件留在“待生效”目录，重启时换上。
- 组件下载失败时，给用户两个选择：**重试**（默认）/ **先只更新主体**（重启后组件显示“需要更新”，不加载，稍后再装）。
- 绝不会出现“主体已重启、组件还在下载”：没备齐就不进入切换。
  The app is replaced and relaunched only after both are staged and verified; a failed add-on download never interrupts a working app.

### 移除 / Removal
- 组件在运行时（CEF 已在进程里）不能直接删除。点“移除”只做标记：写入 `…/LiveHime/addons-pending/remove-browser-source`。
- 下次启动、加载模块之前，把组件**移到废纸篓**（不直接删除），再清掉标记。

### 与 pkg / 自动更新的关系 / With the pkg and auto-update
- 组件在用户目录里，不在应用包里。pkg 重装、自动更新替换应用、回滚，都不会动它。
- 回滚到旧版本时，如果旧版本的 OBS 底座和组件不符，组件自动显示“需要更新”，不会被加载。

### 应用内界面 / In the app
- “更新”页新增“可选组件”一栏：显示组件名、版本、状态和上表的按钮；下载时显示进度。
- 组件不存在时，所有相关界面保持现状，主程序行为完全不变。

### 发布 / Release
- 附件：`LiveHime-BrowserAddon-v<组件版本>-arm64.zip`、`-x86_64.zip`，以及 `addons.json`。
  名字故意不以 `LiveHimeMacApp-` 开头，避免被更新器当成应用包。
- 组件只在 OBS 底座变化时重新发布；其余版本的 Release 里，`addons.json` 继续指向上一版组件的附件（跨 Release 引用）。
- 发布流程（`docs/RELEASING.md`）加 `verify-browser-addon.sh`，与 pkg 的检查同样处理。

## P0 结果（2026-09-30，可行）/ P0 results (feasible)

在已发布的 v0.2.10（arm64）上实测，**组件方案可行**：浏览器来源能创建、能渲染网页进画面，退出干净、无崩溃。
Tested on the released v0.2.10 (arm64): the add-on works, renders pages into the canvas, and quits cleanly.

**做法 / How**
- 单独的构建目录 `build_macos_browser`（与正式构建相同的参数，只把 `ENABLE_BROWSER` 设为 ON），只编 `obs-browser` 和四个 `OBS Helper` 目标。
- 组件包 = 编出的 `obs-browser.plugin`，在其 `Contents/Frameworks/` 里放入 CEF 框架和四个 Helper，用本地开发证书签名，`codesign --verify --deep --strict` 通过。
- 组件链接的 libobs、Qt、obs-frontend-api 都通过 `@executable_path/../Frameworks` 解析到应用自己的，无需携带。

**需要的补丁（都在 obs-browser 子模块里，见 `obs-fork/browser-addon/0001-…patch`）/ Patches needed**
1. 组件自带 CEF 时，从组件包加载 CEF（`cef_load_library`），不走 `LoadInMain`。
2. 设置 `framework_dir_path`、`browser_subprocess_path`（组件包里的 `OBS Helper`），以及 **`main_bundle_path` = 应用本身**。
   不设最后这一项，子进程会把组件包当成主包，找不到浏览器进程，启动即退出（实测：页面全黑，Helper 反复重启）。
3. **在 `obs_module_post_load` 里、主线程上启动 CEF**。原版 OBS 由前端在启动时初始化 CEF；我们的前端不带浏览器，
   第一次初始化会落到创建来源的线程（例如 obs-websocket 的线程），macOS 上的 CEF 在那里无法启动，退出时还会崩溃（实测）。
- 没有自带 CEF 的组件包时，行为与原版完全一致。

**实测数字 / Measurements**

| 项 | 值 |
|---|---|
| 插件目录 | `~/Library/Application Support/LiveHime/obs-studio/plugins/obs-browser.plugin`（已确认） |
| 组件解包大小 | 262 MB |
| 组件 zip（`ditto -c -k`） | 108.4 MB（RelWithDebInfo，未剥离符号；P1 剥离后应更小） |
| 装了组件、没有浏览器来源时 | GPU Helper 约 80 MB + 网络 Helper 约 73 MB，常驻 |
| 一个浏览器来源时 | 另加两个 Renderer（约 84 MB、106 MB）和一个 Helper（约 70 MB），Helper 合计约 430 MB |
| 渲染 | 纯色页像素精确（`rgb(255, 0, 170)`）；`https://example.com` 正常显示 |

**P0 留下的问题，放进 P2 / Open items for P2**
- 目前装了组件就会在启动时拉起 CEF，常驻约 150 MB。更好的做法是：**只在确实有浏览器来源时才启动**，并且保证在主线程上启动（从其他线程创建来源时，切到主线程初始化）。
- P1 打包时剥离调试符号，重新测量下载大小。

## 分阶段 / Phases

| 阶段 | 内容 | 完成标准 |
|---|---|---|
| **P0 可行性** ✅ 2026-09-30 | 下载 CEF（arm64，88.5 MB，按 SHA-256 核对）；单独目录编出 obs-browser；手动放进插件目录；测试实例里加浏览器来源打开网页 | 网页能显示在画面里；记下组件大小、每个来源的内存占用；确认插件目录路径和需要的补丁 |
| P1 打包 | `package-browser-addon.sh`、签名、`addon.json`、`addons.json`、`verify-browser-addon.sh`，写进发布流程 | 检查脚本全部通过，解包后签名有效 |
| P2 应用内管理 | 启动前的“待生效/待移除”处理（OBS 分支补丁）；Swift 核心的下载/校验/备料；Qt “可选组件”界面；与应用更新合并的两阶段流程 | 端到端测试覆盖：安装、重启后可用、移除、组件下载失败时主体不受影响、OBS 版本不符时不加载、损坏时不加载 |
| P3 发布 | Intel 构建（98.7 MB 的 CEF）、README 与发布说明，按发布规则先作为测试版发 v0.3.0 | 测试版无问题反馈后转正式版 |

## 约束 / Constraints

- 测试只用开发版测试实例，测试期间不开用户自己的 LiveHime（见 `tests/README.md` 的规则）。
- 下载 CEF 前征得维护者同意。
- 主程序体积和默认行为不变；组件是纯增量。
- 删除一律移到废纸篓。

---

# 第二部分：更新说明弹窗 / Part 2: What's New dialog

## 目标 / Goal

更新后第一次打开应用时，在主窗口正中弹出一个小窗，告诉用户这次更新了什么。
On the first launch after an update, show a small dialog centered on the main window with what changed.

## 何时显示 / When it shows
- 插件设置 `update` 对象里新增 `lastSeenVersion`（和现有的 `automatic`、`beta`、`skipped` 放在一起）。
- 启动完成（`OBS_FRONTEND_EVENT_FINISHED_LOADING`）后比较：
  - `lastSeenVersion` 为空（全新安装）：**不弹**，直接记下当前版本。全新用户不需要“更新内容”。
  - `lastSeenVersion` 比当前版本旧：**弹**，显示中间跳过的每个版本（例如从 0.2.8 直接更新到 0.2.10，就显示 0.2.9 和 0.2.10，新的在上）。
  - 相同或更新（回滚后）：不弹。
- 用户点“知道了”后才写入 `lastSeenVersion`；如果弹窗没关就退出了，下次启动还会显示。

## 内容来源 / Content
- **随应用打包，不联网获取**：构建时把 `docs/RELEASE_NOTES_v*.md` 复制进应用的 `Contents/Resources/release-notes/`
  （全部版本加起来约 30 KB）。这样离线也能显示，内容也和装上的版本严格对应。
- **只显示和已更新用户有关的段落**：取 `## 新功能 / What's new`、`## 修复 / Fixes`、`## 升级 / Upgrade` 三节；
  跳过 `下载哪个文件`、`验证`、`源码` 等只对下载者或维护者有用的段落。
- 发布流程加一条检查：新版本的发布说明里至少要有“新功能”或“修复”一节，否则弹窗会是空的。

## 外观与行为 / Look and behavior
- 模态 `QDialog`，父窗口是主窗口，**居中显示在主窗口上**；在主窗口显示之后再弹（`FINISHED_LOADING` 之后用 `QTimer::singleShot(0, …)`）。
- 标题：“LiveHime 已更新到 v<版本>”。
- 正文用 `QTextBrowser` + `setMarkdown`（更新页现在就是这么渲染发布说明的）。`QTextBrowser` 自带滚动：
  - 宽度约 520 px；
  - 高度按内容自适应，**上限为主窗口高度的 70%**，超出部分在弹窗内部滚动，按钮始终可见。
- 底部两个按钮：“查看完整发布说明”（打开 GitHub Release 页面）和“知道了”（默认按钮，按回车即可关闭）。
- 跟随浅色 / 深色主题；链接在外部浏览器打开。
- 如果浏览器组件处于“需要更新”，在弹窗顶部加一行提示，并附“去更新”按钮，跳到“更新”页的“可选组件”一栏。

## 测试 / Tests
- 单元测试：版本比较与“该显示哪些版本”的选择；从 Markdown 中提取指定段落。
- 端到端测试（测试实例，`LIVEHIME_KEYCHAIN_SERVICE=local.livehime.macos.e2e-test`，测后恢复配置）：
  全新安装不弹；从旧版本更新后弹、居中、内容可滚动；点“知道了”后不再弹；回滚后不弹。
- 长内容场景：把多个版本的说明一起塞进去，确认按钮始终可见、可以滚到底。

## 分阶段 / Phases

| 阶段 | 内容 | 完成标准 |
|---|---|---|
| W1 | 构建时打包发布说明；段落提取与版本选择（含单元测试） | 测试通过；应用包里能看到 `release-notes/` |
| W2 | 弹窗界面、`lastSeenVersion`、首次启动逻辑 | 端到端测试全部通过 |
| W3 | 发布流程加“发布说明必须有新功能或修复”检查，写进 `docs/RELEASING.md` | 下一个版本起生效 |
