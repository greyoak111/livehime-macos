import XCTest
@testable import LiveHimeAdapter

final class AuthWebViewBridgeTests: XCTestCase {
    final class Sink: AuthWebViewBridgeDelegate {
        var events: [AuthWebViewEvent] = []
        func authBridge(_ bridge: AuthWebViewBridge, didEmit event: AuthWebViewEvent) { events.append(event) }
    }

    func testLoginEventsAndInvalidResize() {
        let sink = Sink()
        let bridge = AuthWebViewBridge(delegate: sink)
        bridge.loginSuccess(["type": "scan", "refresh_token": "opaque", "timestamp": 123, "url": "https://example.invalid/ok"])
        bridge.cancel()
        bridge.secondaryValidationResult()
        bridge.switchLogin(width: 800, height: 600)
        bridge.switchLogin(width: .nan, height: 600)
        XCTAssertEqual(sink.events.count, 4)
        XCTAssertEqual(sink.events[1], .cancelled)
        XCTAssertEqual(sink.events[2], .secondaryValidationReturned)
        XCTAssertEqual(sink.events[3], .resize(width: 800, height: 600))
    }

    func testWKWebViewShimExposesExpectedMethods() {
        for method in ["LoginSuccess", "Cancel", "SecondaryValidationResult", "SwitchLogin"] {
            XCTAssertTrue(AuthWebViewBridge.wkWebViewShim.contains(method))
        }
        XCTAssertTrue(AuthWebViewBridge.wkWebViewShim.contains("webkit.messageHandlers.livehime_login"))
    }

    func testLoginSuccessAcceptsTokenAlias() {
        let sink = Sink()
        let bridge = AuthWebViewBridge(delegate: sink)
        bridge.loginSuccess(["type": "scan", "token": "opaque-token"])
        guard case let .succeeded(result) = sink.events.first else {
            return XCTFail("expected success event")
        }
        XCTAssertEqual(result.refreshToken, "opaque-token")
    }
}
