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

    func testCookieLoginCompletesAfterSecondaryValidation() throws {
        let store = MemoryStore()
        let coordinator = LoginSessionCoordinator(store: store)
        try coordinator.handle(.secondaryValidationReturned)
        try coordinator.completeCookieLogin(cookieValue: "sessdata")
        XCTAssertEqual(coordinator.state, .signedIn(StoredLoginSession(type: "cookie", refreshToken: "sessdata")))
        XCTAssertEqual(store.value?.refreshToken, "sessdata")
    }

    func testRealKeychainRoundTripWithIsolatedService() throws {
        let store = KeychainLoginSessionStore(service: "local.livehime.test.\(UUID().uuidString)", account: "test")
        defer { try? store.remove() }
        let session = StoredLoginSession(type: "scan", refreshToken: "test-token", timestamp: "1")
        try store.save(session)
        XCTAssertEqual(try store.load(), session)
        try store.remove()
        XCTAssertNil(try store.load())
    }
}
