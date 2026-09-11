import XCTest
import WebKit
@testable import LiveHimeAdapter

final class AuthBridgeContractTests: XCTestCase {
    func testOnlyExactSecureMainFrameOriginIsPrivileged() {
        XCTAssertTrue(AuthBridgeOriginPolicy.allows(scheme: "https", host: "live.bilibili.com", port: 443, isMainFrame: true))
        for host in ["bilibili.com.attacker.invalid", "evil.live.bilibili.com", "passport.bilibili.com", ""] {
            XCTAssertFalse(AuthBridgeOriginPolicy.allows(scheme: "https", host: host, port: 443, isMainFrame: true))
        }
        XCTAssertFalse(AuthBridgeOriginPolicy.allows(scheme: "http", host: "live.bilibili.com", port: 80, isMainFrame: true))
        XCTAssertFalse(AuthBridgeOriginPolicy.allows(scheme: "https", host: "live.bilibili.com", port: 443, isMainFrame: false))
        XCTAssertFalse(AuthBridgeOriginPolicy.allows(scheme: "https", host: "live.bilibili.com", port: 8443, isMainFrame: true))
    }

    func testUnknownAndMalformedActionsAreRejected() {
        XCTAssertThrowsError(try NativeAuthRequest.parse(action: "other/operation", payload: [:]))
        XCTAssertThrowsError(try NativeAuthRequest.parse(action: "auth/setRefreshToken", payload: "not-json"))
        XCTAssertThrowsError(try NativeAuthRequest.parse(action: "auth/setCookies", payload: [["name": "missing-value"]]))
    }

    func testCookieBatchRejectsPartialAndUnboundedInput() throws {
        XCTAssertThrowsError(try AuthCookieBatch(payload: [["name": "ok", "value": "fixture"], ["name": "bad"]]))
        XCTAssertThrowsError(try AuthCookieBatch(payload: [["name": "x\r\n", "value": "fixture"]]))
        XCTAssertThrowsError(try AuthCookieBatch(payload: Array(repeating: ["name": "x", "value": "v"], count: 129)))
        let batch = try AuthCookieBatch(payload: [["name": "fixture", "value": "local", "domain": "attacker.invalid",
            "expirationDate": 1, "isExpiredRemove": true]], now: Date(timeIntervalSince1970: 2))
        XCTAssertEqual(batch.operations.first?.cookie.domain, ".bilibili.com")
        XCTAssertEqual(batch.operations.first?.remove, true)
        XCTAssertEqual(batch.operations.first?.cookie.isSecure, true)
    }

    @MainActor
    func testRealWebKitWaitsForNativeAcknowledgementAndRejectsUnknownAction() async throws {
        _ = NSApplication.shared
        let sink = WebKitFixtureSink()
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.userContentController.add(sink, name: "livehime_login")
        config.userContentController.addScriptMessageHandler(sink, contentWorld: .page, name: "livehime_native")
        config.userContentController.addUserScript(WKUserScript(source: AuthWebViewBridge.wkWebViewShim,
            injectionTime: .atDocumentStart, forMainFrameOnly: true))
        let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 820, height: 520), configuration: config)
        view.navigationDelegate = sink
        defer {
            view.stopLoading()
            config.userContentController.removeAllScriptMessageHandlers()
        }
        view.loadHTMLString("<meta http-equiv='Content-Security-Policy' content=\"default-src 'none'; script-src 'unsafe-inline'\"><p>Offline bridge fixture</p>", baseURL: nil)
        await fulfillment(of: [sink.loaded], timeout: 10)
        let first = try await view.evaluateJavaScript(AuthWebViewBridge.nativeAuthBridgeScript) as? Bool
        let repeated = try await view.evaluateJavaScript(AuthWebViewBridge.nativeAuthBridgeScript) as? Bool
        XCTAssertEqual(first, true)
        XCTAssertEqual(repeated, false)
        let supported = try await view.callAsyncJavaScript("""
            return await biliBridgePc.callNative('auth/setCookies', [{name:'fixture',value:'local'}]);
            """, arguments: [:], in: nil, contentWorld: .page) as? [String: Bool]
        XCTAssertEqual(supported?["accepted"], true)
        XCTAssertTrue(sink.completedWrite, "The Promise must not resolve before the asynchronous native work")
        let calls = sink.nativeCalls
        let error = try await view.callAsyncJavaScript("""
            try { await biliBridgePc.callNative('future/unsupported', {secret:'never-export'}); return 'wrong'; }
            catch (error) { return error.message; }
            """, arguments: [:], in: nil, contentWorld: .page) as? String
        XCTAssertEqual(error, "unsupported_action")
        XCTAssertEqual(sink.nativeCalls, calls)
        _ = try await view.evaluateJavaScript("livehime_login.LoginSuccess({type:'fixture'});livehime_login.SecondaryValidationResult();livehime_login.Cancel();livehime_login.SwitchLogin(820,520);true;")
        await fulfillment(of: [sink.legacyEvents], timeout: 5)
        XCTAssertEqual(sink.methods, ["LoginSuccess", "SecondaryValidationResult", "Cancel", "SwitchLogin"])
    }
}

@MainActor
private final class WebKitFixtureSink: NSObject, WKNavigationDelegate, WKScriptMessageHandler, WKScriptMessageHandlerWithReply {
    let loaded = XCTestExpectation(description: "local document loaded")
    let legacyEvents: XCTestExpectation = {
        let result = XCTestExpectation(description: "legacy callbacks received")
        result.expectedFulfillmentCount = 4
        return result
    }()
    var methods: [String] = []
    var nativeCalls = 0
    var completedWrite = false
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { loaded.fulfill() }
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        decisionHandler(action.request.url?.scheme == "about" ? .allow : .cancel)
    }
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        if let body = message.body as? [String: Any], let method = body["method"] as? String {
            methods.append(method); legacyEvents.fulfill()
        }
    }
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage,
                               replyHandler: @escaping (Any?, String?) -> Void) {
        nativeCalls += 1
        Task { @MainActor in
            // Simulate the asynchronous cookie-store completion without network or Keychain.
            try? await Task.sleep(nanoseconds: 100_000_000)
            completedWrite = true
            replyHandler(["accepted": true], nil)
        }
    }
}
