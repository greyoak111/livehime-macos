import Foundation

/// Privileged login callbacks are accepted only from our top-level official page.
/// The face-auth window has no native login handler; its origin cannot inherit one.
public enum AuthBridgeOriginPolicy {
    public static func allows(scheme: String, host: String, port: Int, isMainFrame: Bool) -> Bool {
        isMainFrame && scheme.lowercased() == "https" &&
            host.lowercased() == "live.bilibili.com" && (port == 0 || port == 443)
    }
}

public enum AuthBridgeContractError: String, Error {
    case malformedPayload = "malformed_payload"
    case unsupportedAction = "unsupported_action"
    case untrustedOrigin = "untrusted_origin"
}

public enum NativeAuthRequest {
    case login([String: Any])
    case cookies(AuthCookieBatch)

    public static func parse(action: String?, payload: Any?) throws -> NativeAuthRequest {
        switch action {
        case "auth/setRefreshToken":
            let object: [String: Any]?
            if let text = payload as? String, let data = text.data(using: .utf8) {
                object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            } else {
                object = payload as? [String: Any]
            }
            guard let object, !object.isEmpty else { throw AuthBridgeContractError.malformedPayload }
            return .login(object)
        case "auth/setCookies": return .cookies(try AuthCookieBatch(payload: payload))
        default: throw AuthBridgeContractError.unsupportedAction
        }
    }
}

/// Validate the whole batch before writing anything. Cookies remain confined to
/// bilibili.com; no source domain, payload, or value is sent to diagnostics.
public struct AuthCookieBatch {
    public struct Operation {
        public let cookie: HTTPCookie
        public let remove: Bool
    }
    public let operations: [Operation]

    public init(payload: Any?, now: Date = Date()) throws {
        guard let items = payload as? [[String: Any]], items.count <= 128 else {
            throw AuthBridgeContractError.malformedPayload
        }
        operations = try items.map { item in
            guard let name = item["name"] as? String, let value = item["value"] as? String,
                  !name.isEmpty, name.utf8.count <= 256, value.utf8.count <= 16384,
                  name.rangeOfCharacter(from: .controlCharacters) == nil,
                  value.rangeOfCharacter(from: .controlCharacters) == nil,
                  !name.contains(";"), !name.contains("=") else {
                throw AuthBridgeContractError.malformedPayload
            }
            var properties: [HTTPCookiePropertyKey: Any] = [
                .domain: ".bilibili.com", .path: "/", .name: name, .value: value,
                .secure: "TRUE"
            ]
            var remove = false
            if let expiry = item["expirationDate"] as? NSNumber {
                guard expiry.doubleValue.isFinite else { throw AuthBridgeContractError.malformedPayload }
                properties[.expires] = Date(timeIntervalSince1970: expiry.doubleValue)
                remove = expiry.doubleValue <= now.timeIntervalSince1970 &&
                    (item["isExpiredRemove"] as? Bool) == true
            }
            guard let cookie = HTTPCookie(properties: properties) else {
                throw AuthBridgeContractError.malformedPayload
            }
            return Operation(cookie: cookie, remove: remove)
        }
    }
}

extension AuthWebViewBridge {
    /// Inject after navigation finishes, preserving the v0.1.0 render order.
    /// WKScriptMessageHandlerWithReply acknowledges completed cookie writes.
    /// Acknowledgement means host handling finished, not that login is valid.
    public static let nativeAuthBridgeScript = """
    (() => {
      if (window.biliBridgePc) return false;
      window.biliBridgePc = {
        callNative: (action, payload) => {
          if (!['auth/setRefreshToken', 'auth/setCookies'].includes(action)) {
            return Promise.reject(new Error('unsupported_action'));
          }
          return window.webkit.messageHandlers.livehime_native.postMessage({action, payload});
        }
      };
      return true;
    })();
    """
}
