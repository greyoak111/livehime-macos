import Foundation
import Security

public struct StoredLoginSession: Codable, Equatable, Sendable {
    public let type: String?
    public let refreshToken: String
    public let timestamp: String?
    public let url: URL?

    public init(type: String? = nil, refreshToken: String, timestamp: String? = nil, url: URL? = nil) {
        self.type = type
        self.refreshToken = refreshToken
        self.timestamp = timestamp
        self.url = url
    }
}

public protocol LoginSessionStore: Sendable {
    func save(_ session: StoredLoginSession) throws
    func load() throws -> StoredLoginSession?
    func remove() throws
}

public enum LoginSessionStoreError: Error, Equatable {
    case invalidData
    case keychain(OSStatus)
}

/// Keychain-backed storage for the opaque session result returned by the official page.
/// The token is never logged and is not exposed through diagnostics.
public final class KeychainLoginSessionStore: LoginSessionStore, @unchecked Sendable {
    public static let defaultService = "local.livehime.macos.session"
    private let service: String
    private let account: String

    public init(service: String = KeychainLoginSessionStore.defaultService, account: String = "default") {
        self.service = service
        self.account = account
    }

    public func save(_ session: StoredLoginSession) throws {
        let data: Data
        do { data = try JSONEncoder().encode(session) }
        catch { throw LoginSessionStoreError.invalidData }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            let addStatus = SecItemAdd(item as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw LoginSessionStoreError.keychain(addStatus) }
        } else if updateStatus != errSecSuccess {
            throw LoginSessionStoreError.keychain(updateStatus)
        }
    }

    public func load() throws -> StoredLoginSession? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw LoginSessionStoreError.keychain(status) }
        guard let data = result as? Data else { throw LoginSessionStoreError.invalidData }
        do { return try JSONDecoder().decode(StoredLoginSession.self, from: data) }
        catch { throw LoginSessionStoreError.invalidData }
    }

    public func remove() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw LoginSessionStoreError.keychain(status)
        }
    }
}

public enum LoginSessionState: Equatable, Sendable {
    case signedOut
    case signedIn(StoredLoginSession)
    case secondaryValidationPending
}

/// Small state machine kept separate from WebKit and Bilibili API code.
public final class LoginSessionCoordinator: @unchecked Sendable {
    public private(set) var state: LoginSessionState = .signedOut
    private let store: any LoginSessionStore

    public init(store: any LoginSessionStore) { self.store = store }

    public func restore() throws {
        state = try store.load().map(LoginSessionState.signedIn) ?? .signedOut
    }

    public func handle(_ event: AuthWebViewEvent) throws {
        switch event {
        case let .succeeded(result):
            if let token = result.refreshToken, !token.isEmpty {
                let session = StoredLoginSession(type: result.type, refreshToken: token, timestamp: result.timestamp, url: result.url)
                try store.save(session)
                state = .signedIn(session)
            } else {
                // mini-login-v2 deliberately emits only `{ type }` after its
                // hidden SSO iframe has written the authenticated cookies.
                // The host must validate that cookie jar before persisting a
                // SESSDATA-backed session.
                state = .secondaryValidationPending
            }
        case .secondaryValidationReturned:
            state = .secondaryValidationPending
        case .cancelled, .resize:
            break
        }
    }

    /// Completes the password secondary-verification path.  The official
    /// login page redirects back to itself after the verification page and
    /// only emits `SecondaryValidationResult`; the authenticated cookie jar
    /// is therefore the credential we have at that point (there is no
    /// refresh_token payload to persist).
    public func completeCookieLogin(cookieValue: String, timestamp: String? = nil, url: URL? = nil) throws {
        guard !cookieValue.isEmpty else { throw LoginSessionStoreError.invalidData }
        let session = StoredLoginSession(type: "cookie", refreshToken: cookieValue, timestamp: timestamp, url: url)
        try store.save(session)
        state = .signedIn(session)
    }

    public func signOut() throws {
        try store.remove()
        state = .signedOut
    }
}
