import AppKit
import CryptoKit
import WebKit
import LiveHimeAdapter
import UniformTypeIdentifiers

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, WKNavigationDelegate, WKScriptMessageHandler, WKScriptMessageHandlerWithReply {
    private let diagnostics = BilibiliDiagnosticStore()
    private var pageLoadTasks: [ObjectIdentifier: Task<Void, Never>] = [:]
    private var faceAuthStatusLabel: NSTextField?
    private var window: NSWindow!
    private var webView: WKWebView!
    private var statusLabel: NSTextField?
    private let bridge = AuthWebViewBridge()
    private lazy var sessionCoordinator = LoginSessionCoordinator(
        store: KeychainLoginSessionStore(service: KeychainLoginSessionStore.service(for: Bundle.main.bundleIdentifier))
    )
    private lazy var bilibili = BilibiliControlClient(diagnostics: diagnostics)
    private var obsTransport: any ObsControlTransport = ObsWebSocketTransport(password: BundledOBSLauncher.configuredWebSocketPassword)
    private var webSessionAuthenticated = false
    private var obsStreaming = false
    private var obsRecording = false
    private var obsRecordingKnown = false
    private var obsStatusLabel: NSTextField?
    private var obsToggleButton: NSButton?
    private var roomStatusLabel: NSTextField?
    private var areaPopup: NSPopUpButton?
    private var currentCookieHeader = ""
    private var currentRoom: BilibiliRoomInfo?
    private var currentIdentityMid: Int64 = 0
    private var availableAreas: [BilibiliLiveArea] = []
    private var didAutoLaunchOBS = false
    private var faceAuthWindow: NSWindow?
    private var endLiveButton: NSButton?
    private var closingRoom = false
    private var startingStream = false
    private var streamOperation = UUID()
    private var obsConnected = false
    private var statusTask: Task<Void, Never>?
    private let closeOnRestore = CommandLine.arguments.contains("--end-live-now")
    private var didCloseOnRestore = false
    private var stoppingOBS = false
    private var statusRefreshInFlight = false
    private var forceStopButton: NSButton?
    private var capturePermissions: CapturePermissionsView?
    private var restartingForPermissions = false
    private var pendingLogout = false
    private var pendingLogoutRoomConfirmed = false
    private var pendingLogoutOBSConfirmed = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        installDiagnosticsMenu()
        let contentController = WKUserContentController()
        // The Windows CEF host defines this object before loading the official
        // page. mini-login-v2 copies it into bilibili.com cookies; leaving it
        // undefined can make the final auth validity check fail after a
        // successful CAPTCHA or second-factor step.
        contentController.addUserScript(WKUserScript(
            source: makeBrowserContextScript(),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        ))
        let shim = WKUserScript(
            source: AuthWebViewBridge.wkWebViewShim,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        contentController.addUserScript(shim)
        contentController.add(self, name: "livehime_login")
        contentController.addScriptMessageHandler(self, contentWorld: .page, name: "livehime_native")

        let configuration = WKWebViewConfiguration()
        configuration.userContentController = contentController
        configuration.websiteDataStore = .default()

        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        webView.allowsBackForwardNavigationGestures = false
        bridge.onEvent = { [weak self] event in
            Task { @MainActor in self?.handle(event) }
        }

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 520),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Bilibili LiveHime 登录"
        window.contentMinSize = NSSize(width: 820, height: 460)
        window.contentView = webView
        window.center()
        window.makeKeyAndOrderFront(nil)

        if CommandLine.arguments.contains("--permissions-only") {
            let permissions = CapturePermissionsView()
            capturePermissions = permissions
            permissions.onRestart = { [weak self] in self?.restartForCapturePermissions() }
            let container = NSView()
            container.addSubview(permissions)
            permissions.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                permissions.centerXAnchor.constraint(equalTo: container.centerXAnchor),
                permissions.centerYAnchor.constraint(equalTo: container.centerYAnchor)
            ])
            window.contentView = container
            window.title = "LiveHime macOS · 采集权限"
            return
        }

        do {
            try sessionCoordinator.restore()
            switch sessionCoordinator.state {
            case let .signedIn(session):
                showControlPanel(message: "正在恢复登录会话…")
                if session.type == "cookie" {
                    restoreSessdataCookie(session.refreshToken) { [weak self] in
                        self?.loadIdentityFromWebViewCookies(promoteCookieSession: false)
                    }
                } else {
                    loadIdentityFromWebViewCookies(promoteCookieSession: false)
                }
            default:
                updateWindowTitle()
                loadLoginPage()
            }
        } catch {
            window.title = "Bilibili LiveHime 登录（会话恢复失败）"
            loadLoginPage()
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        capturePermissions?.refresh()
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard acceptsLoginMessage(message), message.name == "livehime_login", let body = dictionary(from: message.body), let method = body["method"] as? String else { return }
        switch method {
        case "LoginSuccess":
            // The payload is intentionally not logged. The session coordinator handles persistence.
            bridge.loginSuccess(dictionary(from: body["data"]) ?? [:])
        case "SetCookies":
            if let batch = try? AuthCookieBatch(payload: body["data"]) { applyWebCookies(batch) {} }
        case "Cancel":
            bridge.cancel()
        case "SecondaryValidationResult":
            bridge.secondaryValidationResult()
        case "SwitchLogin":
            bridge.switchLogin(width: body["width"] as? Double ?? 0, height: body["height"] as? Double ?? 0)
        case "NativeAction":
            handleNativeAction(action: body["action"] as? String, payload: body["payload"]) { _, _ in }
        default:
            break
        }
    }

    private func acceptsLoginMessage(_ message: WKScriptMessage) -> Bool {
        let origin = message.frameInfo.securityOrigin
        return message.webView === webView && AuthBridgeOriginPolicy.allows(
            scheme: origin.protocol, host: origin.host, port: origin.port,
            isMainFrame: message.frameInfo.isMainFrame)
    }

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage,
                               replyHandler: @escaping (Any?, String?) -> Void) {
        guard acceptsLoginMessage(message), message.name == "livehime_native" else {
            diagnostics.record(.init(stage: .webBridge, operation: .callback, errorKind: .untrusted))
            replyHandler(nil, AuthBridgeContractError.untrustedOrigin.rawValue)
            return
        }
        guard let body = dictionary(from: message.body) else {
            replyHandler(nil, AuthBridgeContractError.malformedPayload.rawValue)
            return
        }
        handleNativeAction(action: body["action"] as? String, payload: body["payload"], completion: replyHandler)
    }

    private func handleNativeAction(action: String?, payload: Any?, completion: @escaping (Any?, String?) -> Void) {
        do {
            switch try NativeAuthRequest.parse(action: action, payload: payload) {
            case .login(let result):
                diagnostics.record(.init(stage: .webBridge, operation: .callback))
                bridge.loginSuccess(result)
                completion(["accepted": true], nil)
            case .cookies(let batch):
                applyWebCookies(batch) { [weak self] in
                    self?.diagnostics.record(.init(stage: .webBridge, operation: .callback))
                    completion(["accepted": true], nil)
                }
            }
        } catch let error as AuthBridgeContractError {
            diagnostics.record(.init(stage: .webBridge, operation: .callback, errorKind: error == .unsupportedAction ? .unsupported : .schema))
            completion(nil, error.rawValue)
        } catch {
            completion(nil, AuthBridgeContractError.malformedPayload.rawValue)
        }
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        let id = ObjectIdentifier(webView)
        pageLoadTasks[id]?.cancel()
        pageLoadTasks[id] = Task { @MainActor [weak self, weak webView] in
            do { try await Task.sleep(nanoseconds: 20_000_000_000) } catch { return }
            guard let self, let webView else { return }
            self.pageFailed(webView, kind: .timeout)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        pageLoadTasks.removeValue(forKey: ObjectIdentifier(webView))?.cancel()
        let isLogin = webView === self.webView
        diagnostics.record(.init(stage: isLogin ? .loginPage : .faceAuthPage, operation: .navigation))
        if !isLogin {
            faceAuthStatusLabel?.stringValue = "页面已载入，请完成页面内的身份验证"
            return
        }
        guard let url = webView.url, AuthBridgeOriginPolicy.allows(scheme: url.scheme ?? "",
            host: url.host ?? "", port: url.port ?? 0, isMainFrame: true) else { return }
        // Preserve the working render order; verify the bridge separately from page navigation.
        webView.evaluateJavaScript(AuthWebViewBridge.nativeAuthBridgeScript) { [weak self] _, error in
            if error != nil {
                self?.diagnostics.record(.init(stage: .webBridge, operation: .callback, errorKind: .schema))
                self?.window.title = "Bilibili LiveHime · 登录桥接初始化失败（可导出诊断）"
            }
        }
        updateWindowTitle()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        if (error as? URLError)?.code != .cancelled { pageFailed(webView, kind: .transport) }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if (error as? URLError)?.code != .cancelled { pageFailed(webView, kind: .transport) }
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { pageFailed(webView, kind: .transport) }

    private func pageFailed(_ view: WKWebView, kind: BilibiliDiagnosticErrorKind) {
        pageLoadTasks.removeValue(forKey: ObjectIdentifier(view))?.cancel()
        let isLogin = view === webView
        diagnostics.record(.init(stage: isLogin ? .loginPage : .faceAuthPage, operation: .navigation, errorKind: kind))
        if isLogin {
            window.title = "Bilibili LiveHime · 页面加载失败（可在诊断菜单重试）"
        } else {
            faceAuthStatusLabel?.stringValue = "验证页面加载失败，请关闭后重新打开；可从诊断菜单导出记录"
        }
        // Page failure never removes a previously valid session or retries a live mutation.
    }

    private func installDiagnosticsMenu() {
        let menu = NSMenu()
        let app = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "退出 LiveHime", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        app.submenu = appMenu
        menu.addItem(app)
        let edit = NSMenuItem(title: "编辑", action: nil, keyEquivalent: "")
        let editMenu = NSMenu(title: "编辑")
        for (title, action, key) in [("剪切", #selector(NSText.cut(_:)), "x"), ("复制", #selector(NSText.copy(_:)), "c"),
                                     ("粘贴", #selector(NSText.paste(_:)), "v"), ("全选", #selector(NSText.selectAll(_:)), "a")] {
            editMenu.addItem(withTitle: title, action: action, keyEquivalent: key)
        }
        edit.submenu = editMenu
        menu.addItem(edit)
        let item = NSMenuItem(title: "诊断", action: nil, keyEquivalent: "")
        let diagnosticsMenu = NSMenu(title: "诊断")
        for (title, action) in [("导出脱敏诊断…", #selector(exportDiagnostics)), ("清空诊断记录", #selector(clearDiagnostics)), ("重新加载登录页", #selector(retryLoginPage))] {
            let entry = NSMenuItem(title: title, action: action, keyEquivalent: "")
            entry.target = self
            diagnosticsMenu.addItem(entry)
        }
        item.submenu = diagnosticsMenu
        menu.addItem(item)
        NSApplication.shared.mainMenu = menu
    }

    @objc private func clearDiagnostics() { diagnostics.clear() }
    @objc private func retryLoginPage() {
        guard window.contentView === webView else { return }
        loadLoginPage()
    }
    @objc private func exportDiagnostics() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "LiveHime-diagnostics.json"
        panel.allowedContentTypes = [.json]
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let self, let url = panel.url else { return }
            do {
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                try encoder.encode(self.diagnostics.snapshot()).write(to: url, options: .atomic)
            } catch {
                let alert = NSAlert()
                alert.messageText = "诊断文件写入失败"
                alert.informativeText = "请检查所选文件夹是否可写。"
                alert.beginSheetModal(for: self.window)
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Keep a live backend from surviving the one user-facing app. The
        // independent in-app end-live action remains available while this
        // reply is cancelled.
        if obsStreaming || obsRecording || stoppingOBS {
            let alert = NSAlert()
            alert.messageText = "OBS 仍有输出任务"
            alert.informativeText = "请先停止直播或录制，再退出应用。"
            alert.addButton(withTitle: "好")
            alert.beginSheetModal(for: window)
            return .terminateCancel
        }
        if BundledOBSLauncher.runningBundledApp != nil && !obsRecordingKnown {
            let alert = NSAlert()
            alert.messageText = "无法确认 OBS 输出状态"
            alert.informativeText = "请先刷新 OBS 状态，确认直播和录制都已停止，再退出应用。"
            alert.addButton(withTitle: "好")
            alert.beginSheetModal(for: window)
            return .terminateCancel
        }
        return .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        statusTask?.cancel()
        // No output is active here (the delegate above blocks that case), so
        // terminate only the exact bundled backend. A separately installed
        // OBS process is never touched.
        _ = BundledOBSLauncher.runningBundledApp?.terminate()
    }

    private func handle(_ event: AuthWebViewEvent) {
        do {
            try sessionCoordinator.handle(event)
            switch event {
            case let .succeeded(result):
                showControlPanel(message: "登录成功，正在读取主播身份…")
                // In the biliBridgePc path the official page often emits only
                // `{ type }`; the actual auth material arrives through
                // auth/setCookies. Promote the cookie session after nav
                // succeeds in that case.
                if let token = result.refreshToken, let timestamp = result.timestamp {
                    seedCookiesFromRefreshToken(token: token, timestamp: timestamp)
                }
                loadIdentityFromWebViewCookies(promoteCookieSession: result.refreshToken == nil)
            case .secondaryValidationReturned:
                // Password risk verification returns to this same HTML page.
                // Windows then validates the already-authenticated cookie jar
                // and advances to the main window.  Do that explicitly here;
                // leaving the WebView visible makes the flow look like a
                // failed login even though the verification succeeded.
                showControlPanel(message: "二次验证成功，正在确认登录…")
                loadIdentityFromWebViewCookies(promoteCookieSession: true)
            default:
                break
            }
            if case let .resize(width, height) = event {
                let targetWidth = max(820, min(width, 1200))
                let targetHeight = max(460, min(height, 900))
                window.setContentSize(NSSize(width: targetWidth, height: targetHeight))
            }
            updateWindowTitle()
        } catch {
            window.title = "Bilibili LiveHime 登录（会话无效）"
        }
    }

    private func updateWindowTitle() {
        if webSessionAuthenticated {
            window.title = "Bilibili LiveHime 已登录"
            return
        }
        switch sessionCoordinator.state {
        case .signedOut:
            window.title = "Bilibili LiveHime 登录"
        case .signedIn:
            window.title = "Bilibili LiveHime 已登录"
        case .secondaryValidationPending:
            window.title = "Bilibili LiveHime 等待二次验证"
        }
    }

    private func dictionary(from value: Any?) -> [String: Any]? {
        if let value = value as? [String: Any] { return value }
        guard let value = value as? NSDictionary else { return nil }
        var result: [String: Any] = [:]
        for (key, item) in value {
            if let key = key as? String { result[key] = item }
        }
        return result
    }

    private func showControlPanel(message: String) {
        let label = NSTextField(labelWithString: message)
        label.alignment = .center
        label.font = .systemFont(ofSize: 16, weight: .medium)
        statusLabel = label

        let obsLabel = NSTextField(labelWithString: "OBS：正在连接…")
        obsLabel.alignment = .center
        obsStatusLabel = obsLabel

        let toggle = NSButton(title: "开始直播", target: self, action: #selector(toggleOBSStreaming))
        toggle.bezelStyle = .rounded
        toggle.isEnabled = false
        obsToggleButton = toggle

        let refresh = NSButton(title: "刷新 OBS 状态", target: self, action: #selector(refreshOBSStatus))
        refresh.bezelStyle = .rounded

        let roomLabel = NSTextField(labelWithString: "直播间：正在读取…")
        roomLabel.alignment = .center
        roomStatusLabel = roomLabel

        let area = NSPopUpButton()
        area.addItem(withTitle: "直播分区：正在读取…")
        area.isEnabled = false
        areaPopup = area

        let launchOBS = NSButton(title: "启动内置 OBS", target: self, action: #selector(launchBundledOBS))
        launchOBS.bezelStyle = .rounded

        let endLive = NSButton(title: "结束直播（关闭直播间）", target: self, action: #selector(endLiveNow))
        endLive.bezelStyle = .rounded
        endLive.isEnabled = false
        endLiveButton = endLive
        let reloadAreas = NSButton(title: "重新读取分区", target: self, action: #selector(reloadLiveAreas))
        reloadAreas.bezelStyle = .rounded
        let forceStop = NSButton(title: "强制退出卡住的内置 OBS", target: self, action: #selector(forceStopBundledOBS))
        forceStop.bezelStyle = .rounded
        forceStop.isHidden = true
        forceStopButton = forceStop
        let permissions = CapturePermissionsView()
        capturePermissions = permissions
        permissions.onRestart = { [weak self] in self?.restartForCapturePermissions() }
        let streamActions = NSStackView(views: [toggle, endLive])
        streamActions.spacing = 12
        let obsActions = NSStackView(views: [refresh, launchOBS])
        obsActions.spacing = 12
        let logout = NSButton(title: "退出登录（自动关播）", target: self, action: #selector(signOut))
        logout.bezelStyle = .rounded
        let accountActions = NSStackView(views: [logout])
        accountActions.spacing = 12
        let panel = NSStackView(views: [label, roomLabel, area, reloadAreas, obsLabel, streamActions, forceStop, obsActions, permissions, accountActions])
        panel.orientation = .vertical
        panel.alignment = .centerX
        panel.spacing = 12
        panel.translatesAutoresizingMaskIntoConstraints = false
        let container = NSView(frame: .zero)
        container.addSubview(panel)
        NSLayoutConstraint.activate([
            panel.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            panel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            panel.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: 24),
            panel.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -24)
        ])
        window.contentView = container
        window.setContentSize(NSSize(width: 900, height: 660))
        window.contentMinSize = NSSize(width: 900, height: 660)
        window.styleMask.insert(.resizable)
        updateWindowTitle()
        // The OBS runtime is part of this app bundle. Start it as the
        // backend for the native panel so the user does not have to open a
        // second application and manually wire the WebSocket connection.
        if !closeOnRestore {
            didAutoLaunchOBS = true
            launchBundledOBS()
        }
    }

    private func loadIdentityFromWebViewCookies() {
        loadIdentityFromWebViewCookies(promoteCookieSession: false)
    }

    private func restoreSessdataCookie(_ value: String, completion: @escaping () -> Void) {
        guard let cookie = HTTPCookie(properties: [
            .domain: ".bilibili.com",
            .path: "/",
            .name: "SESSDATA",
            .value: value,
            .secure: "TRUE"
        ]) else {
            completion()
            return
        }
        webView.configuration.websiteDataStore.httpCookieStore.setCookie(cookie) {
            DispatchQueue.main.async { completion() }
        }
    }

    private func loadIdentityFromWebViewCookies(promoteCookieSession: Bool) {
        loadIdentityFromWebViewCookies(attempt: 0, promoteCookieSession: promoteCookieSession)
    }

    private func loadIdentityFromWebViewCookies(attempt: Int, promoteCookieSession: Bool) {
        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
            let header = cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
            guard !header.isEmpty else {
                if attempt < 5 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        self?.loadIdentityFromWebViewCookies(attempt: attempt + 1, promoteCookieSession: promoteCookieSession)
                    }
                } else {
                    Task { @MainActor in self?.setControlStatus("登录已保存，但网页会话没有 Cookie") }
                }
                return
            }
            Task {
                do {
                    guard let self else { return }
                    let identity = try await self.bilibili.fetchIdentity(cookieHeader: header)
                    await MainActor.run {
                        self.webSessionAuthenticated = true
                        if promoteCookieSession,
                           let sessdata = cookies.first(where: { $0.name == "SESSDATA" })?.value {
                            // The secondary-verification branch does not emit
                            // LoginSuccess data. Persist the authenticated
                            // SESSDATA cookie as the opaque local credential
                            // so the next launch can restore the session.
                            try? self.sessionCoordinator.completeCookieLogin(cookieValue: sessdata)
                        }
                        self.setControlStatus("已登录：\(identity.username)")
                    }
                    self.loadRoomSummary(identity: identity, cookieHeader: header)
                } catch let error as BilibiliControlError {
                    if attempt < 5 {
                        try? await Task.sleep(for: .milliseconds(500))
                        self?.loadIdentityFromWebViewCookies(attempt: attempt + 1, promoteCookieSession: promoteCookieSession)
                    } else {
                        await MainActor.run { self?.setControlStatus(self?.controlErrorMessage(error) ?? "登录已保存，身份读取失败（可稍后重试）") }
                    }
                } catch {
                    if attempt < 5 {
                        try? await Task.sleep(for: .milliseconds(500))
                        self?.loadIdentityFromWebViewCookies(attempt: attempt + 1, promoteCookieSession: promoteCookieSession)
                    } else {
                        await MainActor.run { self?.setControlStatus("登录已保存，身份读取失败（可稍后重试）") }
                    }
                }
            }
        }
    }

    private func controlErrorMessage(_ error: BilibiliControlError) -> String {
        switch error {
        case .notLoggedIn:
            return "登录已保存，但网页会话尚未被 Bilibili 认可"
        case .http(let status, let retryAfter):
            if let retryAfter { return "登录已保存，身份接口暂时限流（HTTP \(status)，约 \(retryAfter) 秒后重试）" }
            return "登录已保存，身份接口暂时不可用（HTTP \(status)）"
        case .api(_, let message):
            return "登录已保存，身份接口返回失败：\(message)"
        case .invalidResponse:
            return "登录已保存，但身份接口返回格式异常"
        case .transport:
            return "登录已保存，但身份接口暂时无法连接"
        }
    }

    private func setControlStatus(_ message: String) {
        statusLabel?.stringValue = message
        updateWindowTitle()
    }

    private func loadRoomSummary(identity: BilibiliIdentity, cookieHeader: String) {
        currentIdentityMid = identity.mid
        roomStatusLabel?.stringValue = "直播间：正在读取…"
        currentCookieHeader = cookieHeader
        currentRoom = nil
        availableAreas = []
        areaPopup?.removeAllItems()
        areaPopup?.addItem(withTitle: "直播分区：正在读取…")
        areaPopup?.isEnabled = false
        let client = BilibiliLiveClient(cookieHeader: cookieHeader, diagnostics: diagnostics)
        Task { [weak self] in
            do {
                let room = try await client.fetchCurrentRoom(mid: identity.mid)
                await MainActor.run {
                    self?.currentRoom = room
                    let state = room.liveStatus == 1 ? "直播中" : "未开播"
                    self?.roomStatusLabel?.stringValue = "直播间：\(room.title.isEmpty ? String(room.roomID) : room.title)（\(state)）"
                    self?.updateLiveButtonEnabled()
                }
                if let self, self.closeOnRestore, !self.didCloseOnRestore {
                    self.didCloseOnRestore = true
                    self.endLiveNow()
                }
                self?.reloadLiveAreas()
                self?.startStatusPolling()
            } catch let error as BilibiliLiveError {
                await MainActor.run { self?.roomStatusLabel?.stringValue = self?.roomErrorMessage(error) ?? "直播间：读取失败" }
            } catch {
                await MainActor.run { self?.roomStatusLabel?.stringValue = "直播间：读取失败" }
            }
        }
    }

    @objc private func reloadLiveAreas() {
        guard currentRoom != nil else { return }
        areaPopup?.removeAllItems()
        areaPopup?.addItem(withTitle: "直播分区：正在读取…")
        areaPopup?.isEnabled = false
        availableAreas = []
        updateLiveButtonEnabled()
        Task { [weak self] in
            guard let self else { return }
            do {
                let areas = try await BilibiliLiveClient(cookieHeader: self.currentCookieHeader, diagnostics: self.diagnostics).fetchAreas()
                self.setAvailableAreas(areas, preferredID: self.currentRoom?.areaID ?? 0)
            } catch {
                self.areaPopup?.removeAllItems()
                self.areaPopup?.addItem(withTitle: "分区读取失败，请点重新读取分区")
                self.updateLiveButtonEnabled()
            }
        }
    }

    private func startStatusPolling() {
        guard statusTask == nil else { return }
        statusTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled, let self else { return }
                if !self.startingStream && !self.closingRoom && !self.stoppingOBS {
                    self.refreshOBSStatus()
                }
            }
        }
    }

    private func setAvailableAreas(_ areas: [BilibiliLiveArea], preferredID: Int) {
        availableAreas = areas
        areaPopup?.removeAllItems()
        guard !areas.isEmpty else {
            areaPopup?.addItem(withTitle: "直播分区：未读取到可用分区")
            areaPopup?.isEnabled = false
            updateLiveButtonEnabled()
            return
        }
        for item in areas {
            let title = item.parentName.isEmpty ? item.name : "\(item.parentName) / \(item.name)"
            areaPopup?.addItem(withTitle: title)
        }
        let index = areas.firstIndex(where: { $0.areaID == Int64(preferredID) }) ?? 0
        areaPopup?.selectItem(at: index)
        areaPopup?.isEnabled = true
        updateLiveButtonEnabled()
    }

    private func updateLiveButtonEnabled() {
        obsToggleButton?.title = "开始直播"
        obsToggleButton?.isEnabled = !restartingForPermissions && !startingStream && !closingRoom && !stoppingOBS && !obsStreaming && obsConnected && currentRoom != nil && !availableAreas.isEmpty
        areaPopup?.isEnabled = !availableAreas.isEmpty && !startingStream && !closingRoom
        endLiveButton?.isEnabled = currentRoom != nil && !currentCookieHeader.isEmpty && !closingRoom
        endLiveButton?.title = closingRoom ? "正在关闭直播间…" : "结束直播（关闭直播间）"
    }

    private func roomErrorMessage(_ error: BilibiliLiveError) -> String {
        switch error {
        case .missingRoom: return "直播间：未找到当前房间"
        case .missingCSRF: return "直播间：Cookie 缺少 CSRF"
        case .api(_, let message): return "直播间：\(message)"
        default: return "直播间：接口暂不可用"
        }
    }

    @objc private func refreshOBSStatus() {
        guard !restartingForPermissions, !statusRefreshInFlight, !startingStream, !closingRoom, !stoppingOBS else { return }
        guard !BundledOBSLauncher.otherOBSRunning else {
            obsConnected = false
            obsStatusLabel?.stringValue = "OBS：请先退出单独安装的 OBS，再启动内置版本"
            updateLiveButtonEnabled()
            return
        }
        statusRefreshInFlight = true
        let operation = streamOperation
        Task { [weak self] in
            guard let self else { return }
            defer { self.statusRefreshInFlight = false }
            do {
                let active = try await obsTransport.streamingActive()
                let recording = try await obsTransport.recordingActive()
                guard self.streamOperation == operation else { return }
                await MainActor.run {
                    self.obsStreaming = active
                    self.obsRecording = recording
                    self.obsRecordingKnown = true
                    self.obsConnected = true
                    if active && recording {
                        self.obsStatusLabel?.stringValue = "OBS：直播中（录制中）"
                    } else if active {
                        self.obsStatusLabel?.stringValue = "OBS：直播中"
                    } else if recording {
                        self.obsStatusLabel?.stringValue = "OBS：已连接，未直播（录制中）"
                    } else {
                        self.obsStatusLabel?.stringValue = "OBS：已连接，未直播"
                    }
                    self.updateLiveButtonEnabled()
                }
            } catch let error as ObsControlError {
                guard self.streamOperation == operation else { return }
                await MainActor.run {
                    self.obsConnected = false
                    self.obsRecordingKnown = false
                    self.obsStatusLabel?.stringValue = self.obsErrorMessage(error)
                    self.obsToggleButton?.isEnabled = false
                    self.updateLiveButtonEnabled()
                    // A fresh LiveHime launch should be self-contained. Start
                    // the staged OBS once when no WebSocket endpoint is up;
                    // retain the button for retry after an explicit failure.
                    if !self.didAutoLaunchOBS && !self.closeOnRestore {
                        self.didAutoLaunchOBS = true
                        self.launchBundledOBS()
                    }
                }
            } catch {
                guard self.streamOperation == operation else { return }
                await MainActor.run {
                    self.obsConnected = false
                    self.obsRecordingKnown = false
                    self.obsStatusLabel?.stringValue = "OBS：连接失败"
                    self.obsToggleButton?.isEnabled = false
                    self.updateLiveButtonEnabled()
                    if !self.didAutoLaunchOBS && !self.closeOnRestore {
                        self.didAutoLaunchOBS = true
                        self.launchBundledOBS()
                    }
                }
            }
        }
    }

    @objc private func launchBundledOBS() {
        guard !restartingForPermissions else { return }
        guard !BundledOBSLauncher.otherOBSRunning else {
            obsStatusLabel?.stringValue = "OBS：请先退出单独安装的 OBS，再启动内置版本"
            return
        }
        if BundledOBSLauncher.runningBundledApp == nil,
           BundledOBSLauncher.savedScenesRequireScreenPermission,
           !CapturePermissionsView.screenAuthorized {
            obsStatusLabel?.stringValue = "OBS：已暂停自动启动，请先完成下方屏幕录制授权"
            capturePermissions?.refresh()
            return
        }
        obsStatusLabel?.stringValue = "OBS：正在启动内置 OBS…"
        Task { [weak self] in
            do {
                let prepared = try BundledOBSLauncher.prepareConfiguration()
                self?.obsTransport = ObsWebSocketTransport(password: prepared.password)
                _ = try await BundledOBSLauncher.launch()
                // OBS loads obs-websocket during startup; retry for a short
                // window instead of assuming the process is ready after one
                // fixed sleep.
                for _ in 0..<12 {
                    try? await Task.sleep(for: .milliseconds(500))
                    do {
                        _ = try await self?.obsTransport.streamingActive()
                        break
                    } catch { continue }
                }
                await MainActor.run { self?.refreshOBSStatus() }
            } catch {
                await MainActor.run { self?.obsStatusLabel?.stringValue = "OBS：内置 OBS 启动失败" }
            }
        }
    }

    private func restartForCapturePermissions() {
        guard !restartingForPermissions, !startingStream, !closingRoom, !stoppingOBS else { return }
        restartingForPermissions = true
        updateLiveButtonEnabled()
        Task { [weak self] in
            guard let self else { return }
            defer { self.restartingForPermissions = false; self.updateLiveButtonEnabled() }
            if let backend = BundledOBSLauncher.runningBundledApp {
                let transport = ObsWebSocketTransport(password: BundledOBSLauncher.configuredWebSocketPassword)
                do {
                    let streaming = try await transport.streamingActive()
                    let recording = try await transport.recordingActive()
                    guard !streaming, !recording else {
                        self.showRestartMessage("请先结束直播和录制，再重启应用以应用授权。")
                        return
                    }
                } catch {
                    self.showRestartMessage("暂时无法确认 OBS 是否仍在直播或录制。请先在 OBS 中停止输出并退出，然后重试。")
                    return
                }
                guard backend.terminate() else {
                    self.showRestartMessage("OBS 尚未退出。请处理 OBS 的弹窗并退出，然后重试。")
                    return
                }
                for _ in 0..<40 where !backend.isTerminated {
                    try? await Task.sleep(for: .milliseconds(200))
                }
                guard backend.isTerminated else {
                    self.showRestartMessage("OBS 仍在退出中，请稍后重试；本次没有强制结束它。")
                    return
                }
            }
            // A short-lived launcher waits until this process has fully exited,
            // then uses LaunchServices to reopen the same signed bundle.
            let launcher = Process()
            launcher.executableURL = URL(fileURLWithPath: "/bin/sh")
            launcher.arguments = ["-c", "i=0; while kill -0 \"$1\" 2>/dev/null; do i=$((i+1)); [ \"$i\" -le 100 ] || exit 1; sleep 0.2; done; exec /usr/bin/open \"$2\"", "livehime-relaunch", String(ProcessInfo.processInfo.processIdentifier), Bundle.main.bundleURL.path]
            do {
                try launcher.run()
                NSApp.terminate(nil)
            } catch {
                self.showRestartMessage("自动重启失败，请退出 LiveHime 后重新打开。")
            }
        }
    }

    private func showRestartMessage(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "采集权限"
        alert.informativeText = message
        alert.addButton(withTitle: "好")
        alert.beginSheetModal(for: window)
    }

    @objc private func signOut() {
        guard !startingStream, !closingRoom, !stoppingOBS else {
            showRestartMessage("当前有直播操作正在进行，请完成后再退出登录。")
            return
        }
        // A live OBS output without a confirmed room is an unsafe logout
        // state: endLiveNow needs the room id to send Bilibili's stop request.
        // Do not enter the pending-logout state and leave the account stuck;
        // refresh the room summary first so the next attempt can close both
        // sides and then clear the session.
        if obsStreaming && currentRoom == nil {
            showRestartMessage("OBS 仍在推流，但当前直播间尚未确认。请先刷新 OBS 状态和直播间信息，再退出登录。")
            refreshOBSStatus()
            return
        }
        if obsStreaming || currentRoom?.liveStatus == 1 {
            pendingLogout = true
            pendingLogoutRoomConfirmed = false
            pendingLogoutOBSConfirmed = false
            endLiveNow()
            return
        }
        performSignOut()
    }

    private func performSignOut() {
        do {
            try sessionCoordinator.signOut()
        } catch {
            showRestartMessage("退出登录失败：本地会话没有清除，请稍后重试。")
            return
        }

        statusTask?.cancel()
        statusTask = nil
        streamOperation = UUID()
        webSessionAuthenticated = false
        currentCookieHeader = ""
        currentRoom = nil
        currentIdentityMid = 0
        availableAreas = []
        obsStreaming = false
        obsRecording = false
        obsRecordingKnown = false
        obsConnected = false
        areaPopup = nil
        roomStatusLabel = nil
        obsStatusLabel = nil
        obsToggleButton = nil
        endLiveButton = nil
        forceStopButton = nil
        webView.stopLoading()
        let loginView = webView!
        window.contentView = loginView
        loginView.frame = window.contentView?.bounds ?? .zero
        loginView.autoresizingMask = [.width, .height]
        window.title = "Bilibili LiveHime 登录"
        clearBilibiliWebData { [weak self] in
            self?.loadLoginPage()
        }
    }

    private func clearBilibiliWebData(completion: @escaping () -> Void) {
        let store = webView.configuration.websiteDataStore
        store.httpCookieStore.getAllCookies { cookies in
            let bilibiliCookies = cookies.filter { $0.domain.contains("bilibili.com") }
            let deletionGroup = DispatchGroup()
            for cookie in bilibiliCookies {
                deletionGroup.enter()
                store.httpCookieStore.delete(cookie) {
                    deletionGroup.leave()
                }
            }
            // WKHTTPCookieStore deletion is asynchronous. Wait for every
            // cookie completion before removing website records and loading
            // the login page, otherwise the old SESSDATA can repopulate the
            // next account screen during a fast account switch.
            deletionGroup.notify(queue: .main) {
                store.fetchDataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes()) { records in
                    let recordsToRemove = records.filter { record in
                        let name = record.displayName.lowercased()
                        return name.contains("bilibili") || name.contains("biliapi")
                    }
                    store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), for: recordsToRemove) {
                        DispatchQueue.main.async { completion() }
                    }
                }
            }
        }
    }

    @objc private func endLiveNow() {
        guard !closingRoom, let room = currentRoom else { return }
        streamOperation = UUID() // invalidate a pending start before it can reach OBS
        closingRoom = true
        stoppingOBS = true
        updateLiveButtonEnabled()
        roomStatusLabel?.stringValue = "直播间：正在向 Bilibili 发送关播请求…"
        // These two operations must be independent: a hung OBS must never
        // prevent the authenticated stopLive request from reaching Bilibili.
        Task { [weak self] in
            guard let self else { return }
            defer {
                self.stoppingOBS = false
                self.updateLiveButtonEnabled()
                self.maybeCompletePendingLogout()
            }
            do {
                try await self.obsTransport.stopStreaming()
                self.obsStreaming = try await self.obsTransport.streamingActive()
                self.obsStatusLabel?.stringValue = self.obsStreaming ? "OBS：正在停止输出，请稍后刷新" : "OBS：已停止推流"
                self.pendingLogoutOBSConfirmed = !self.obsStreaming
            } catch {
                self.obsStatusLabel?.stringValue = "OBS：停止未确认；B站关播独立执行，可重试结束直播"
                self.obsConnected = false
                self.forceStopButton?.isHidden = false
                self.pendingLogoutOBSConfirmed = false
            }
            self.updateLiveButtonEnabled()
        }
        Task { [weak self] in
            guard let self else { return }
            defer {
                self.closingRoom = false
                self.updateLiveButtonEnabled()
                self.maybeCompletePendingLogout()
            }
            let client = BilibiliLiveClient(cookieHeader: self.currentCookieHeader, diagnostics: self.diagnostics)
            do {
                try await client.stopLive(roomID: room.roomID, cookieHeader: self.currentCookieHeader)
                var verifiedRoom: BilibiliRoomInfo?
                for attempt in 0..<3 {
                    if attempt > 0 { try await Task.sleep(for: .seconds(1)) }
                    let result = try await client.fetchRoomInfo(roomID: room.roomID, cookieHeader: self.currentCookieHeader)
                    self.currentRoom = result
                    if result.liveStatus != 1 { verifiedRoom = result; break }
                }
                if let verifiedRoom {
                    self.roomStatusLabel?.stringValue = "直播间：\(room.title)（已关播，服务器已确认）"
                    self.recordStopResult(roomID: room.roomID, result: "verified_offline", liveStatus: verifiedRoom.liveStatus)
                    self.pendingLogoutRoomConfirmed = true
                } else {
                    self.roomStatusLabel?.stringValue = "直播间：关播请求已接收，但服务器仍显示直播中，请重试"
                    self.recordStopResult(roomID: room.roomID, result: "still_live", liveStatus: 1)
                    self.pendingLogoutRoomConfirmed = false
                }
            } catch {
                self.roomStatusLabel?.stringValue = "直播间：关播未确认，请再次点击结束直播"
                self.recordStopResult(roomID: room.roomID, result: "unconfirmed", liveStatus: nil)
                self.pendingLogoutRoomConfirmed = false
            }
        }
    }

    private func maybeCompletePendingLogout() {
        guard pendingLogout, !closingRoom, !stoppingOBS else { return }
        pendingLogout = false
        guard pendingLogoutRoomConfirmed, pendingLogoutOBSConfirmed else {
            showRestartMessage("自动关播没有完全确认，账号仍保持登录。请处理 OBS 停止状态后，再点退出登录。")
            return
        }
        performSignOut()
    }

    private func recordStopResult(roomID: Int64, result: String, liveStatus: Int?) {
        // Only non-secret status goes to this diagnostic file. No cookies,
        // stream addresses, credentials or verification vouchers are logged.
        let folder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/LiveHime", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var data: [String: Any] = ["room_id": roomID, "result": result, "time": ISO8601DateFormatter().string(from: Date())]
        if let liveStatus { data["live_status"] = liveStatus }
        if let encoded = try? JSONSerialization.data(withJSONObject: data, options: [.sortedKeys]) {
            try? encoded.write(to: folder.appendingPathComponent("last-stop.json"), options: .atomic)
        }
    }

    @objc private func toggleOBSStreaming() {
        guard !restartingForPermissions, !startingStream, !closingRoom, !stoppingOBS,
              let room = currentRoom, !availableAreas.isEmpty else { return }
        if obsStreaming { endLiveNow(); return }
        startingStream = true
        streamOperation = UUID()
        let operation = streamOperation
        let index = max(0, min(areaPopup?.indexOfSelectedItem ?? 0, availableAreas.count - 1))
        let area = availableAreas[index]
        updateLiveButtonEnabled()
        Task { [weak self] in
            guard let self else { return }
            defer {
                self.startingStream = false
                self.updateLiveButtonEnabled()
            }
            let client = BilibiliLiveClient(cookieHeader: self.currentCookieHeader, diagnostics: self.diagnostics)
            do {
                self.obsStatusLabel?.stringValue = "Bilibili：正在读取最新直播间状态…"
                let latest = try await client.fetchRoomInfo(roomID: room.roomID, cookieHeader: self.currentCookieHeader)
                guard self.streamOperation == operation else { return }
                self.currentRoom = latest
                let stream: BilibiliStreamConfig
                if latest.liveStatus == 1 {
                    self.obsStatusLabel?.stringValue = "Bilibili：正在读取现有推流地址…"
                    stream = try await client.fetchUpstream(roomID: room.roomID)
                } else {
                    self.obsStatusLabel?.stringValue = "Bilibili：正在申请推流地址（分区 \(area.areaID)）…"
                    stream = try await client.startLive(roomID: room.roomID, areaID: Int(area.areaID), parentAreaID: area.parentAreaID, cookieHeader: self.currentCookieHeader)
                }
                // Ending while startLive is in flight must also close a room
                // that the server opened AFTER our earlier stopLive request.
                guard self.streamOperation == operation else {
                    await self.closeLateStartedRoom(roomID: room.roomID)
                    return
                }
                self.currentRoom = BilibiliRoomInfo(roomID: latest.roomID, uid: latest.uid, shortRoomID: latest.shortRoomID, title: latest.title, liveStatus: 1, areaID: Int(area.areaID))
                self.roomStatusLabel?.stringValue = "直播间：\(latest.title)（已开播）"
                self.obsStatusLabel?.stringValue = "OBS：正在写入 Bilibili 推流配置…"
                try await self.obsTransport.setStreamingService(url: stream.server, key: stream.key, metadata: ["service": "Bilibili LiveHime", "room_id": String(room.roomID)])
                guard self.streamOperation == operation else { return }
                try await self.obsTransport.startStreaming()
                guard self.streamOperation == operation else {
                    try? await self.obsTransport.stopStreaming()
                    await self.closeLateStartedRoom(roomID: room.roomID)
                    return
                }
                self.obsStreaming = try await self.obsTransport.streamingActive()
                self.obsConnected = true
                self.obsStatusLabel?.stringValue = self.obsStreaming ? "OBS：正在推流" : "OBS：已提交启动，等待输出状态"
            } catch {
                if self.streamOperation != operation {
                    // A timeout is ambiguous: the POST may have reached the
                    // server. Reissue shutdown instead of assuming it failed.
                    await self.closeLateStartedRoom(roomID: room.roomID)
                    return
                }
                if let error = error as? BilibiliLiveError {
                    self.obsStatusLabel?.stringValue = self.bilibiliLiveErrorMessage(error)
                    if case .faceAuthRequired(let voucher) = error { self.presentFaceAuth(voucher: voucher) }
                } else if let error = error as? ObsControlError {
                    self.obsStatusLabel?.stringValue = self.obsErrorMessage(error) + "；可点结束直播关闭房间"
                } else {
                    self.obsStatusLabel?.stringValue = "开播状态未确认，可点结束直播关闭房间"
                }
            }
        }
    }

    private func closeLateStartedRoom(roomID: Int64) async {
        let client = BilibiliLiveClient(cookieHeader: currentCookieHeader, diagnostics: diagnostics)
        do {
            try await client.stopLive(roomID: roomID, cookieHeader: currentCookieHeader)
            let room = try await client.fetchRoomInfo(roomID: roomID, cookieHeader: currentCookieHeader)
            currentRoom = room
            roomStatusLabel?.stringValue = room.liveStatus == 1 ? "直播间：仍在直播，请再次点击结束直播" : "直播间：已关播，服务器已确认"
            recordStopResult(roomID: roomID, result: room.liveStatus == 1 ? "still_live" : "verified_offline", liveStatus: room.liveStatus)
        } catch {
            roomStatusLabel?.stringValue = "直播间：关播未确认，请再次点击结束直播"
        }
    }

    @objc private func forceStopBundledOBS() {
        guard let bundledURL = BundledOBSLauncher.bundledAppURL?.resolvingSymlinksInPath() else { return }
        let matches = NSWorkspace.shared.runningApplications.filter { $0.bundleURL?.resolvingSymlinksInPath() == bundledURL }
        if matches.isEmpty {
            obsStatusLabel?.stringValue = "OBS：内置进程已退出"
        } else {
            let requested = matches.map { $0.forceTerminate() }.allSatisfy { $0 }
            // NSWorkspace can report a process that did not honor the force
            // request. Never clear the streaming bit until the exact bundled
            // app path has disappeared from the running application list.
            let remaining = NSWorkspace.shared.runningApplications.filter { $0.bundleURL?.resolvingSymlinksInPath() == bundledURL }
            guard requested, remaining.isEmpty else {
                obsStatusLabel?.stringValue = "OBS：强制退出未确认，请检查活动监视器后重试"
                forceStopButton?.isHidden = false
                obsConnected = false
                updateLiveButtonEnabled()
                return
            }
            obsStatusLabel?.stringValue = "OBS：已强制退出内置进程"
        }
        obsConnected = false
        obsStreaming = false
        obsRecording = false
        obsRecordingKnown = true
        forceStopButton?.isHidden = true
        if pendingLogout { pendingLogoutOBSConfirmed = true }
        updateLiveButtonEnabled()
        maybeCompletePendingLogout()
    }

    private func obsErrorMessage(_ error: ObsControlError) -> String {
        switch error {
        case .unavailable:
            return "OBS：未连接（请在 OBS 开启 WebSocket 服务器）"
        case .rejected(let message):
            return "OBS：\(message)"
        }
    }

    private func bilibiliLiveErrorMessage(_ error: BilibiliLiveError) -> String {
        switch error {
        case .notLoggedIn: return "Bilibili：登录会话已失效，请重新登录"
        case .missingCSRF: return "Bilibili：Cookie 缺少 bili_jct，无法开播"
        case .missingStreamConfig: return "Bilibili：开播接口未返回推流地址"
        case .faceAuthRequired: return "Bilibili：需要完成身份验证"
        case .api(let code, let message): return "Bilibili：开播失败（\(code)）\(message)"
        case .http(let status, let retry):
            return "Bilibili：HTTP \(status)" + (retry.map { "，建议等待 \($0) 秒后手动重试" } ?? "，请查看诊断记录")
        case .network(let code): return "Bilibili：网络请求失败（\(code)），可导出诊断"
        case .transport: return "Bilibili：开播接口网络请求失败"
        default: return "Bilibili：开播参数或返回数据无效"
        }
    }

    /// Bilibili gates some accounts behind the same face-auth page used by
    /// LiveHime. Present it inside this app's WKWebView data store so the
    /// authenticated cookies are available, then let the user explicitly
    /// retry the start request after the verification page reports success.
    private func presentFaceAuth(voucher: String?) {
        if faceAuthWindow != nil {
            faceAuthWindow?.makeKeyAndOrderFront(nil)
            return
        }
        // This is the current LiveHime face-auth entry point. The older
        // blackboard/face-auth-middle page renders a pink loading shell in
        // WKWebView and never mounts the actual verification component.
        var components = URLComponents(string: "https://live.bilibili.com/p/html/bilili-page-face-auth/index.html")!
        components.queryItems = [
            URLQueryItem(name: "is_live_webview", value: "1"),
            URLQueryItem(name: "app_common", value: "open"),
            URLQueryItem(name: "pc_ui", value: "500,428,17181a,2")
        ]
        if let voucher, !voucher.isEmpty {
            components.queryItems?.append(URLQueryItem(name: "v_voucher", value: voucher))
        }
        let authURL = components.url!
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let authWebView = WKWebView(frame: .zero, configuration: configuration)
        authWebView.navigationDelegate = self
        authWebView.load(URLRequest(url: authURL))

        let retry = NSButton(title: "验证完成，重试开播", target: self, action: #selector(faceAuthRetry))
        retry.bezelStyle = .rounded
        let close = NSButton(title: "关闭", target: self, action: #selector(closeFaceAuth))
        close.bezelStyle = .rounded
        let buttons = NSStackView(views: [retry, close])
        buttons.orientation = .horizontal
        buttons.spacing = 12
        let pageStatus = NSTextField(labelWithString: "正在载入官方身份验证页面…")
        faceAuthStatusLabel = pageStatus
        let root = NSStackView(views: [pageStatus, authWebView, buttons])
        root.orientation = .vertical
        root.spacing = 10
        root.edgeInsets = NSEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        authWebView.translatesAutoresizingMaskIntoConstraints = false
        authWebView.heightAnchor.constraint(greaterThanOrEqualToConstant: 560).isActive = true
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 700), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "Bilibili 开播身份验证"
        window.contentView = root
        window.center()
        window.makeKeyAndOrderFront(nil)
        faceAuthWindow = window
    }

    @objc private func faceAuthRetry() {
        closeFaceAuth()
        toggleOBSStreaming()
    }

    @objc private func closeFaceAuth() {
        faceAuthWindow?.orderOut(nil)
        faceAuthWindow = nil
        faceAuthStatusLabel = nil
    }

    /// Reproduces the official Safari handoff used by mini-login when a host
    /// does not provide the full account service. The page hashes the
    /// `set_<timestamp>_<refresh_token>` marker and loads a hidden
    /// `/correspond/0/<sha256>` iframe; that response installs the Bilibili
    /// cookies. This never handles the password or CAPTCHA itself.
    private func seedCookiesFromRefreshToken(token: String, timestamp: String) {
        let marker = "set_\(timestamp)_\(token)"
        let codeHex = marker.unicodeScalars.map { String($0.value, radix: 16) }.joined()
        let digest = SHA256.hash(data: Data(codeHex.utf8)).map { String(format: "%02x", $0) }.joined()
        guard let urlData = try? JSONSerialization.data(withJSONObject: "https://www.bilibili.com/correspond/0/\(digest)"),
              let urlLiteral = String(data: urlData, encoding: .utf8) else { return }
        let script = "(() => { const f=document.createElement('iframe'); f.style.display='none'; f.src=\(urlLiteral); document.body.appendChild(f); })();"
        webView.evaluateJavaScript(script, completionHandler: nil)
    }

    private func makeBrowserContextScript() -> String {
        let defaults = UserDefaults.standard
        let key = "livehime.buvid3"
        let buvid3: String
        if let saved = defaults.string(forKey: key), !saved.isEmpty {
            buvid3 = saved
        } else {
            let generated = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
            defaults.set(generated, forKey: key)
            buvid3 = generated
        }
        let context: [String: String] = [
            // This is the public pc_link appkey recovered from the Windows
            // package's OAuth request construction.
            "appkey": "aae92bc66f3edfab",
            "buvid3": buvid3,
            "device_name": "macOS",
            "device_platform": "mac"
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: context),
              let json = String(data: data, encoding: .utf8) else {
            return "window.browser = {appkey:'aae92bc66f3edfab',buvid3:'',device_name:'macOS',device_platform:'mac'};"
        }
        return "window.browser = Object.assign({}, window.browser || {}, \(json));"
    }

    private func applyWebCookies(_ batch: AuthCookieBatch, completion: @escaping () -> Void) {
        let store = webView.configuration.websiteDataStore.httpCookieStore
        Task { @MainActor in
            // Ordered, awaited writes prevent acknowledgement from racing the
            // next login callback. Legacy events keep their existing behavior.
            for operation in batch.operations {
                if operation.remove { await store.deleteCookie(operation.cookie) }
                else { await store.setCookie(operation.cookie) }
            }
            completion()
        }
    }

    private func loadLoginPage() {
        let url = URL(string: "https://live.bilibili.com/p/html/live-pc-blink/mini-login-v2/")!
        var request = URLRequest(url: url)
        // A sign-out must not resurrect the previous account from WebKit's
        // in-memory page/cache state after the cookie store has been cleared.
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        webView.load(request)
    }
}

@main
struct LiveHimeMacAppMain {
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.regular)
        application.activate(ignoringOtherApps: true)
        application.run()
    }
}
