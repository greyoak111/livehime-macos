import XCTest
@testable import LiveHimeAdapter

final class BilibiliControlClientTests: XCTestCase {
    func testIdentitySuccessParsesFixtureWithoutNetwork() async throws {
        let (client, store, session) = fixture(.success)
        defer { session.invalidateAndCancel() }

        let identity = try await client.fetchIdentity(cookieHeader: "SESSDATA=fixture")
        XCTAssertEqual(identity, BilibiliIdentity(mid: 123, username: "fixture", isLogin: true))
        XCTAssertEqual(ControlFixtureURLProtocol.paths, ["/x/web-interface/nav"])
        XCTAssertEqual(store.snapshot().last?.stage, .identity)
        XCTAssertNil(store.snapshot().last?.errorKind)
    }

    func testHTTP429PreservesStatusAndRetryHintWithoutReplay() async throws {
        let (client, store, session) = fixture(.http429)
        defer { session.invalidateAndCancel() }

        do {
            _ = try await client.fetchIdentity(cookieHeader: "SESSDATA=fixture")
            XCTFail("Expected HTTP rejection")
        } catch {
            XCTAssertEqual(error as? BilibiliControlError, .http(status: 429, retryAfterSeconds: 17))
        }
        XCTAssertEqual(ControlFixtureURLProtocol.paths.count, 1)
        XCTAssertEqual(store.snapshot().last?.httpStatus, 429)
        XCTAssertEqual(store.snapshot().last?.retryAfterSeconds, 17)
        XCTAssertEqual(store.snapshot().last?.errorKind, .http)
    }

    func testNotLoggedInAPIResponseIsDistinctFromTransportFailure() async throws {
        let (client, store, session) = fixture(.notLoggedIn)
        defer { session.invalidateAndCancel() }

        do {
            _ = try await client.fetchIdentity(cookieHeader: "SESSDATA=fixture")
            XCTFail("Expected unauthenticated response")
        } catch {
            XCTAssertEqual(error as? BilibiliControlError, .notLoggedIn)
        }
        XCTAssertEqual(store.snapshot().last?.apiCode, -101)
        XCTAssertEqual(store.snapshot().last?.errorKind, .auth)
    }

    func testMalformedIdentityBodyIsSchemaError() async throws {
        let (client, store, session) = fixture(.malformed)
        defer { session.invalidateAndCancel() }

        do {
            _ = try await client.fetchIdentity(cookieHeader: "SESSDATA=fixture")
            XCTFail("Expected schema rejection")
        } catch {
            XCTAssertEqual(error as? BilibiliControlError, .invalidResponse)
        }
        XCTAssertEqual(store.snapshot().last?.errorKind, .schema)
    }

    func testTimeoutKeepsTransportCategoryAndNetworkCode() async throws {
        let (client, store, session) = fixture(.timeout)
        defer { session.invalidateAndCancel() }

        do {
            _ = try await client.fetchIdentity(cookieHeader: "SESSDATA=fixture")
            XCTFail("Expected timeout")
        } catch {
            XCTAssertEqual(error as? BilibiliControlError, .transport)
        }
        XCTAssertEqual(store.snapshot().last?.errorKind, .timeout)
        XCTAssertEqual(store.snapshot().last?.networkCode, URLError.timedOut.rawValue)
        XCTAssertEqual(ControlFixtureURLProtocol.paths.count, 1)
    }

    private func fixture(_ scenario: ControlFixtureURLProtocol.Scenario) -> (BilibiliControlClient, BilibiliDiagnosticStore, URLSession) {
        ControlFixtureURLProtocol.scenario = scenario
        ControlFixtureURLProtocol.paths = []
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ControlFixtureURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let store = BilibiliDiagnosticStore()
        return (BilibiliControlClient(session: session, diagnostics: store), store, session)
    }
}

private final class ControlFixtureURLProtocol: URLProtocol {
    enum Scenario { case success, http429, notLoggedIn, malformed, timeout }
    static var scenario: Scenario = .success
    static var paths: [String] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        Self.paths.append(url.path)
        if Self.scenario == .timeout {
            client?.urlProtocol(self, didFailWithError: URLError(.timedOut))
            return
        }

        let status: Int
        let body: String
        switch Self.scenario {
        case .success:
            status = 200
            body = #"{"code":0,"data":{"isLogin":true,"mid":123,"uname":"fixture"}}"#
        case .http429:
            status = 429
            body = #"{"code":-412,"message":"rate limited"}"#
        case .notLoggedIn:
            status = 200
            body = #"{"code":-101,"message":"not login"}"#
        case .malformed:
            status = 200
            body = #"{"code":0,"data":{"isLogin":true,"mid":"not-a-number"}}"#
        case .timeout:
            return
        }
        let headers = ["Content-Type": "application/json", "Retry-After": "17"]
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
