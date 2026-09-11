import AppKit
import WebKit
import LiveHimeAdapter

/// A deliberately offline fixture for testing the host/WebKit event contract.
/// It has no Bilibili URL, no credentials, no Keychain access and no OBS
/// dependency. The only state is the in-memory event log shown in the page.
@MainActor
final class CompatLabAppDelegate: NSObject, NSApplicationDelegate, WKScriptMessageHandler, WKScriptMessageHandlerWithReply, WKNavigationDelegate {
    private var window: NSWindow!
    private var webView: WKWebView!
    private var nativeStatus: NSTextField!
    private var ruleListInstalled = false
    private let bridge = AuthWebViewBridge()
    private let session = LoginSessionCoordinator(store: LabMemorySessionStore())

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)

        let contentController = WKUserContentController()
        contentController.addUserScript(WKUserScript(
            source: AuthWebViewBridge.wkWebViewShim,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        ))
        contentController.add(self, name: "livehime_login")
        contentController.addScriptMessageHandler(self, contentWorld: .page, name: "livehime_native")
        bridge.onEvent = { [weak self] event in
            guard let self else { return }
            try? self.session.handle(event)
            self.append(event)
        }

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController = contentController
        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self

        nativeStatus = NSTextField(labelWithString: "正在准备离线网络规则…")
        nativeStatus.font = .systemFont(ofSize: 12)
        nativeStatus.textColor = .secondaryLabelColor

        let container = NSView()
        container.addSubview(webView)
        container.addSubview(nativeStatus)
        webView.translatesAutoresizingMaskIntoConstraints = false
        nativeStatus.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            webView.topAnchor.constraint(equalTo: container.topAnchor),
            webView.bottomAnchor.constraint(equalTo: nativeStatus.topAnchor, constant: -6),
            nativeStatus.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            nativeStatus.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            nativeStatus.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8),
            nativeStatus.heightAnchor.constraint(equalToConstant: 18)
        ])

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "LiveHime Compatibility Lab"
        window.contentMinSize = NSSize(width: 600, height: 440)
        window.contentView = container
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)

        installOfflineRulesAndLoadFixture()
    }

    private func installOfflineRulesAndLoadFixture() {
        let rules = #"[{"trigger":{"url-filter":".*"},"action":{"type":"block"}}]"#
        WKContentRuleListStore.default().compileContentRuleList(
            forIdentifier: "local.livehime.compat-lab.block-network",
            encodedContentRuleList: rules
        ) { [weak self] list, error in
            Task { @MainActor in
                guard let self else { return }
                if let list {
                    self.webView.configuration.userContentController.add(list)
                    self.ruleListInstalled = true
                    self.nativeStatus.stringValue = "离线 fixture · 已阻止所有网络请求"
                } else {
                    self.nativeStatus.stringValue = "离线规则未能启用，测试页面已停止加载"
                    return
                }
                self.webView.loadHTMLString(Self.fixtureHTML, baseURL: nil)
            }
        }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "livehime_login",
              let body = message.body as? [String: Any],
              let method = body["method"] as? String else { return }

        switch method {
        case "LoginSuccess": bridge.loginSuccess(body["data"] as? [String: Any] ?? [:])
        case "Cancel": bridge.cancel()
        case "SecondaryValidationResult": bridge.secondaryValidationResult()
        case "SwitchLogin": bridge.switchLogin(width: Self.doubleValue(body["width"]) ?? 0, height: Self.doubleValue(body["height"]) ?? 0)
        case "ResetFixture":
            try? session.signOut()
            webView.loadHTMLString(Self.fixtureHTML, baseURL: nil)
        default: break
        }
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage,
                               replyHandler: @escaping (Any?, String?) -> Void) {
        guard message.webView === webView, message.frameInfo.isMainFrame,
              let body = message.body as? [String: Any] else { replyHandler(nil, "invalid_fixture"); return }
        do {
            switch try NativeAuthRequest.parse(action: body["action"] as? String, payload: body["payload"]) {
            case .login(let payload):
                bridge.loginSuccess(payload)
                replyHandler(["accepted": true], nil)
            case .cookies(let batch):
                let store = webView.configuration.websiteDataStore.httpCookieStore
                Task { @MainActor in
                    for operation in batch.operations {
                        if operation.remove { await store.deleteCookie(operation.cookie) }
                        else { await store.setCookie(operation.cookie) }
                    }
                    replyHandler(["accepted": true], nil)
                }
            }
        } catch { replyHandler(nil, "invalid_fixture_payload") }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        webView.evaluateJavaScript(AuthWebViewBridge.nativeAuthBridgeScript, completionHandler: nil)
    }
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        decisionHandler(ruleListInstalled && action.request.url?.scheme == "about" ? .allow : .cancel)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    private func append(_ event: AuthWebViewEvent) {
        let text: String
        switch event {
        case let .succeeded(result):
            // Keep the fixture output intentionally non-sensitive. It proves
            // event delivery without displaying or persisting token material.
            text = "LoginSuccess(type=\(result.type ?? "nil"), token=redacted)"
        case .cancelled:
            text = "Cancel"
        case .secondaryValidationReturned:
            text = "SecondaryValidationResult"
        case let .resize(width, height):
            text = String(format: "SwitchLogin(width=%.0f, height=%.0f)", width, height)
        }
        guard let data = try? JSONSerialization.data(withJSONObject: text, options: .fragmentsAllowed),
              let json = String(data: data, encoding: .utf8) else { return }
        webView.evaluateJavaScript("window.compatLabAppend(\(json));", completionHandler: nil)
    }

    private static func loginResult(from value: Any?) -> LoginResult {
        guard let payload = value as? [String: Any] else { return LoginResult(type: "fixture") }
        return LoginResult(
            type: payload["type"] as? String ?? "fixture",
            refreshToken: payload["refresh_token"] as? String,
            timestamp: payload["timestamp"].map(String.init(describing:))
        )
    }

    private static func doubleValue(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String { return Double(string) }
        return nil
    }

    private static let fixtureHTML = """
    <!doctype html>
    <html><head><meta charset="utf-8"><meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'"><meta name="viewport" content="width=device-width, initial-scale=1">
    <style>
      :root { color-scheme: light dark; }
      body { font: -apple-system-body; margin: 0; padding: 28px 34px; background: Canvas; color: CanvasText; }
      h1 { font-size: 22px; margin: 0 0 8px; } p { color: GrayText; margin-top: 0; }
      .buttons { display: flex; flex-wrap: wrap; gap: 8px; margin: 22px 0; }
      button { font: inherit; padding: 7px 12px; border-radius: 7px; border: 1px solid GrayText; background: ButtonFace; color: ButtonText; }
      #results { min-height: 190px; padding: 12px; border: 1px solid GrayText; border-radius: 8px; white-space: pre-wrap; font-family: ui-monospace, monospace; }
      .badge { display: inline-block; padding: 3px 8px; border-radius: 10px; background: #2d7d46; color: white; font-size: 12px; }
    </style></head><body>
      <h1>兼容性测试 fixture</h1>
      <p><span class="badge">offline</span> WKWebView nonPersistent · 所有网络请求已阻止</p>
      <p>使用虚拟数据验证网页到原生宿主的回调；关闭窗口即丢弃临时网页数据。</p>
      <div class="buttons">
        <button onclick="livehime_login.LoginSuccess({type:'fixture', refresh_token:'local-only-token'})">模拟登录成功</button>
        <button onclick="livehime_login.SecondaryValidationResult()">模拟二次验证返回</button>
        <button onclick="livehime_login.SwitchLogin(820, 520)">模拟 resize</button>
        <button onclick="livehime_login.Cancel()">模拟取消</button>
        <button onclick="roundTrip()">Cookie 写入后再回调</button>
        <button onclick="biliBridgePc.callNative('future/unsupported',{}).catch(e=>compatLabAppend(e.message))">未知方法处理</button>
        <button onclick="webkit.messageHandlers.livehime_login.postMessage({method:'ResetFixture'})">重置模拟会话</button>
      </div>
      <h2>宿主收到的事件</h2><div id="results">（尚无事件）</div>
      <script>
        async function roundTrip() {
          try {
            await biliBridgePc.callNative('auth/setCookies', [{name:'lab_fixture',value:'synthetic'}]);
            compatLabAppend('Cookie 写入完成，收到原生确认');
            await biliBridgePc.callNative('auth/setRefreshToken', {type:'fixture',refresh_token:'synthetic'});
          } catch(e) { compatLabAppend('fixture error'); }
        }
        window.compatLabAppend = text => {
          const box = document.getElementById('results');
          box.textContent = box.textContent === '（尚无事件）' ? text : box.textContent + '\\n' + text;
        };
      </script>
    </body></html>
    """
}

private final class LabMemorySessionStore: LoginSessionStore, @unchecked Sendable {
    private var value: StoredLoginSession?
    func save(_ session: StoredLoginSession) throws { value = session }
    func load() throws -> StoredLoginSession? { value }
    func remove() throws { value = nil }
}

@main
struct LabMain {
    @MainActor static func main() {
        let application = NSApplication.shared
        let delegate = CompatLabAppDelegate()
        application.delegate = delegate
        application.run()
        withExtendedLifetime(delegate) {}
    }
}
