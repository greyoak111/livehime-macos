# 浏览器来源可选组件：计划书 / Browser source add-on: plan

2026-09-29 起草，尚未开工。/ Drafted 2026-09-29; not started.

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

## 已查明的事实（2026-09-29）/ Facts established

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

## 设计 / Design

**组件的形态 / Shape**
- 一个独立的 `obs-browser.plugin` 包：`Contents/MacOS/obs-browser`，`Contents/Frameworks/` 里放
  `Chromium Embedded Framework.framework` 和四个辅助程序（Helper、GPU、Plugin、Renderer），`Contents/Resources/` 放资源。
- 用同一张本地签名证书签名，和主程序一致。

**要改的地方 / Changes**
- obs-browser 默认去**主程序**的 `Contents/Frameworks` 找 CEF 和辅助程序。要改成从**插件自己的包**里找
  （CefSettings 的 `framework_dir_path`、`browser_subprocess_path`、`main_bundle_path`），可能需要一个小补丁。**这是 P0 的最大风险。**
  obs-browser looks for CEF in the app bundle; it must find it inside its own plugin bundle. Biggest P0 risk.
- 主程序继续用 `ENABLE_BROWSER=OFF` 构建；组件在单独的构建目录里用 `ENABLE_BROWSER=ON` 编出来，只取插件那部分。

**应用内管理 / In the app**
- “更新”页新增“可选组件”一栏：浏览器来源 —— 未安装 / 已安装 / 需要更新；按钮“下载安装（约 N MB）”和“移除”。
- 安装：从 GitHub Release 下载，**复用更新器的校验**：SHA-256 与 GitHub digest 一致、签名证书与主程序相同、
  组件版本与应用版本一致；解压到插件目录，提示重启应用。
- 移除：把组件移到废纸篓，提示重启。
- 应用更新后，组件版本对不上时提示一起更新（组件和应用同版本发布，最简单）。
- 组件不存在时，所有相关界面保持现状，主程序行为完全不变。

**发布 / Release**
- 每个版本额外附上 `LiveHime-BrowserAddon-v<版本>-arm64.zip` 与 `-x86_64.zip`。
  名字故意不以 `LiveHimeMacApp-` 开头，避免被更新器当成应用包。
- 发布流程（`docs/RELEASING.md`）加一项组件检查脚本，和 pkg 的检查同样处理。

## 分阶段 / Phases

| 阶段 | 内容 | 完成标准 |
|---|---|---|
| **P0 可行性** | 下载 CEF（arm64，88.5 MB，按 SHA-256 核对）；单独目录编出 obs-browser；手动放进插件目录；测试实例里加浏览器来源打开网页 | 网页能显示在画面里；记下组件大小、每个来源的内存占用；确认插件目录路径和需要的补丁 |
| P1 打包 | `package-browser-addon.sh`、签名、`verify-browser-addon.sh`，写进发布流程 | 检查脚本全部通过，解包后签名有效 |
| P2 应用内管理 | Swift 核心的下载/校验/安装/移除，Qt “可选组件”界面，端到端测试 | 安装、重启后可用、移除、版本不匹配提示，全部有测试 |
| P3 发布 | Intel 构建（98.7 MB 的 CEF）、README 与发布说明，按发布规则先作为测试版发 v0.3.0 | 测试版无问题反馈后转正式版 |

## 约束 / Constraints

- 测试只用开发版测试实例，测试期间不开用户自己的 LiveHime（见 `tests/README.md` 的规则）。
- 下载 CEF 前征得维护者同意。
- 主程序体积和默认行为不变；组件是纯增量。
