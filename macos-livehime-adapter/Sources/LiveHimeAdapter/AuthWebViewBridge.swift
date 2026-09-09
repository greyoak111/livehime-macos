import Foundation

public enum AuthWebViewEvent: Equatable, Sendable {
    case succeeded(LoginResult)
    case cancelled
    case secondaryValidationReturned
    case resize(width: Double, height: Double)
}

public struct LoginResult: Equatable, Sendable {
    public let type: String?
    public let refreshToken: String?
    public let timestamp: String?
    public let url: URL?

    public init(type: String? = nil, refreshToken: String? = nil, timestamp: String? = nil, url: URL? = nil) {
        self.type = type
        self.refreshToken = refreshToken
        self.timestamp = timestamp
        self.url = url
    }
}

/// Host-side contract for the official mini-login page.
/// WKWebView integration should forward a JS shim through WKScriptMessageHandler.
public protocol AuthWebViewBridgeDelegate: AnyObject {
    func authBridge(_ bridge: AuthWebViewBridge, didEmit event: AuthWebViewEvent)
}

public final class AuthWebViewBridge: @unchecked Sendable {
    /// JavaScript to inject at document start when hosting the page in WKWebView.
    /// The native side receives messages through WKScriptMessageHandler named `livehime_login`.
    public static let wkWebViewShim = """
    (() => {
      window.livehime_login = {
        LoginSuccess: data => webkit.messageHandlers.livehime_login.postMessage({method: 'LoginSuccess', data}),
        Cancel: () => webkit.messageHandlers.livehime_login.postMessage({method: 'Cancel'}),
        SecondaryValidationResult: () => webkit.messageHandlers.livehime_login.postMessage({method: 'SecondaryValidationResult'}),
        SwitchLogin: (width, height) => webkit.messageHandlers.livehime_login.postMessage({method: 'SwitchLogin', width, height})
      };
    })();
    """

    public weak var delegate: AuthWebViewBridgeDelegate?
    public var onEvent: ((AuthWebViewEvent) -> Void)?

    public init(delegate: AuthWebViewBridgeDelegate? = nil) {
        self.delegate = delegate
    }

    public func loginSuccess(_ payload: [String: Any]) {
        let result = LoginResult(
            type: payload["type"] as? String,
            refreshToken: (payload["refresh_token"] as? String)
                ?? (payload["refreshToken"] as? String)
                ?? (payload["token"] as? String),
            timestamp: payload["timestamp"].map(String.init(describing:)),
            url: (payload["url"] as? String).flatMap(URL.init(string:))
        )
        emit(.succeeded(result))
    }

    public func cancel() {
        emit(.cancelled)
    }

    public func secondaryValidationResult() {
        emit(.secondaryValidationReturned)
    }

    public func switchLogin(width: Double, height: Double) {
        guard width.isFinite, height.isFinite, width > 0, height > 0 else { return }
        emit(.resize(width: width, height: height))
    }

    private func emit(_ event: AuthWebViewEvent) {
        delegate?.authBridge(self, didEmit: event)
        onEvent?(event)
    }
}
