import XCTest
@testable import LiveHimeAdapter

final class LoginSessionTests: XCTestCase {
    final class MemoryStore: LoginSessionStore, @unchecked Sendable {
        var value: StoredLoginSession?
        func save(_ session: StoredLoginSession) throws { value = session }
        func load() throws -> StoredLoginSession? { value }
        func remove() throws { value = nil }
    }

    func testCoordinatorPersistsSuccessAndSignsOut() throws {
        let store = MemoryStore()
        let coordinator = LoginSessionCoordinator(store: store)
        try coordinator.handle(.succeeded(LoginResult(type: "scan", refreshToken: "opaque", timestamp: "1")))
        XCTAssertEqual(coordinator.state, .signedIn(StoredLoginSession(type: "scan", refreshToken: "opaque", timestamp: "1")))
        try coordinator.signOut()
        XCTAssertEqual(coordinator.state, .signedOut)
    }

    func testCoordinatorDefersSuccessWithoutTokenToCookieValidation() throws {
        let coordinator = LoginSessionCoordinator(store: MemoryStore())
        try coordinator.handle(.succeeded(LoginResult(type: "pwd")))
        XCTAssertEqual(coordinator.state, .secondaryValidationPending)
    }

    func testSecondaryValidationIsExplicitState() throws {
        let coordinator = LoginSessionCoordinator(store: MemoryStore())
        try coordinator.handle(.secondaryValidationReturned)
        XCTAssertEqual(coordinator.state, .secondaryValidationPending)
    }

    func testValidationBundleUsesSeparateKeychainService() {
        XCTAssertEqual(KeychainLoginSessionStore.service(for: "local.livehime.macos"), KeychainLoginSessionStore.defaultService)
        XCTAssertEqual(KeychainLoginSessionStore.service(for: "local.livehime.macos.validation"), "local.livehime.macos.validation.session")
        XCTAssertEqual(KeychainLoginSessionStore.service(for: nil), KeychainLoginSessionStore.defaultService)
    }

    func testCookieLoginCompletesAfterSecondaryValidation() throws {
        let store = MemoryStore()
        let coordinator = LoginSessionCoordinator(store: store)
        try coordinator.handle(.secondaryValidationReturned)
        try coordinator.completeCookieLogin(cookieValue: "sessdata")
        XCTAssertEqual(coordinator.state, .signedIn(StoredLoginSession(type: "cookie", refreshToken: "sessdata")))
        XCTAssertEqual(store.value?.refreshToken, "sessdata")
    }

    func testIncompleteOrRepeatedCallbacksKeepStoredSessionForRecovery() throws {
        let store = MemoryStore()
        let coordinator = LoginSessionCoordinator(store: store)
        try coordinator.completeCookieLogin(cookieValue: "synthetic-session")
        let saved = store.value
        try coordinator.handle(.succeeded(LoginResult(type: "fixture")))
        try coordinator.handle(.secondaryValidationReturned)
        try coordinator.handle(.cancelled)
        XCTAssertEqual(store.value, saved, "A navigation or partial callback must not erase the working credential")
    }

    func testFailedLogoutStoreRemovalDoesNotClaimSignedOut() throws {
        final class FailingStore: LoginSessionStore, @unchecked Sendable {
            var value: StoredLoginSession?
            func save(_ session: StoredLoginSession) throws { value = session }
            func load() throws -> StoredLoginSession? { value }
            func remove() throws { throw LoginSessionStoreError.invalidData }
        }
        let coordinator = LoginSessionCoordinator(store: FailingStore())
        try coordinator.completeCookieLogin(cookieValue: "synthetic-session")
        let state = coordinator.state
        XCTAssertThrowsError(try coordinator.signOut())
        XCTAssertEqual(coordinator.state, state)
    }

    func testRealKeychainRoundTripWithIsolatedService() throws {
        guard ProcessInfo.processInfo.environment["LIVEHIME_TEST_KEYCHAIN"] == "1" else {
            throw XCTSkip("Opt in to isolated Keychain integration with LIVEHIME_TEST_KEYCHAIN=1")
        }
        let store = KeychainLoginSessionStore(service: "local.livehime.test.\(UUID().uuidString)", account: "test")
        defer { try? store.remove() }
        let session = StoredLoginSession(type: "scan", refreshToken: "test-token", timestamp: "1")
        try store.save(session)
        XCTAssertEqual(try store.load(), session)
        try store.remove()
        XCTAssertNil(try store.load())
    }
}
