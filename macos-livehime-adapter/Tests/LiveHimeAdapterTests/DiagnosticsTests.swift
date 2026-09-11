import XCTest
@testable import LiveHimeAdapter

final class DiagnosticsTests: XCTestCase {
    func testBoundedStoreExportUsesOnlyAllowedFields() throws {
        let store = BilibiliDiagnosticStore(capacity: 2)
        for code in [1, 2, 3] { store.record(.init(stage: .start, apiCode: code)) }
        XCTAssertEqual(store.snapshot().compactMap(\.apiCode), [2, 3])
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(store.snapshot())) as? [[String: Any]])
        let allowed: Set<String> = ["timestamp", "stage", "operation", "httpStatus", "apiCode", "networkCode", "durationMilliseconds", "errorKind", "retryAfterSeconds"]
        XCTAssertTrue(object.allSatisfy { Set($0.keys).isSubset(of: allowed) })
        store.clear()
        XCTAssertTrue(store.snapshot().isEmpty)
    }

    func testHTTP429PreservesRetryHintWithoutReplayOrResponseLeak() async throws {
        let (client, store, session) = fixture(.rateLimited)
        defer { session.invalidateAndCancel() }
        do { _ = try await client.fetchAreas(); XCTFail("Expected HTTP error") }
        catch { XCTAssertEqual(error as? BilibiliLiveError, .http(status: 429, retryAfterSeconds: 30)) }
        XCTAssertEqual(DiagnosticURLProtocol.paths.count, 1)
        XCTAssertEqual(store.snapshot().last?.httpStatus, 429)
        XCTAssertEqual(store.snapshot().last?.stage, .areas)
        XCTAssertEqual(store.snapshot().last?.errorKind, .http)
        let exported = String(decoding: try JSONEncoder().encode(store.snapshot()), as: UTF8.self)
        for secret in ["private-cookie", "private-response", "fixture.invalid", "bili_jct"] {
            XCTAssertFalse(exported.contains(secret))
        }
    }

    func testTimeoutHasTransportCodeAndNoReplay() async throws {
        let (client, store, session) = fixture(.timeout)
        defer { session.invalidateAndCancel() }
        do { _ = try await client.fetchAreas(); XCTFail("Expected timeout") }
        catch { XCTAssertEqual(error as? BilibiliLiveError, .network(code: URLError.timedOut.rawValue)) }
        XCTAssertEqual(store.snapshot().last?.errorKind, .timeout)
        XCTAssertEqual(store.snapshot().last?.networkCode, URLError.timedOut.rawValue)
        XCTAssertEqual(DiagnosticURLProtocol.paths.count, 1)
    }

    func testMalformedCodeCannotLookLikeSuccessfulResponse() async throws {
        let (client, store, session) = fixture(.missingCode)
        defer { session.invalidateAndCancel() }
        do { _ = try await client.fetchAreas(); XCTFail("Expected schema failure") }
        catch { XCTAssertEqual(error as? BilibiliLiveError, .invalidResponse) }
        XCTAssertEqual(store.snapshot().last?.errorKind, .schema)
        for code in ["null", "false", "\"0\"", "0.5"] {
            let data = Data("{\"code\":\(code),\"data\":{\"rtmp\":{\"addr\":\"rtmp://fixture.invalid/live\",\"code\":\"fixture\"}}}".utf8)
            XCTAssertThrowsError(try BilibiliLiveClient.parseStreamConfig(from: data))
        }
    }

    func testStart400DoesNotChangeClientMarkerOrRepeatPOST() async throws {
        let (client, store, session) = fixture(.badStart)
        defer { session.invalidateAndCancel() }
        do {
            _ = try await client.startLive(roomID: 123, areaID: 86, cookieHeader: "bili_jct=fixture")
            XCTFail("Expected explicit rejection")
        } catch { XCTAssertEqual(error as? BilibiliLiveError, .api(code: -400, message: "fixture-rejection")) }
        XCTAssertEqual(DiagnosticURLProtocol.paths.filter { $0.hasSuffix("startLive") }.count, 1)
        XCTAssertEqual(store.snapshot().last?.stage, .start)
        XCTAssertEqual(store.snapshot().last?.apiCode, -400)
    }

    func testFaceAuthIsDistinctAndVoucherNeverEntersDiagnostics() async throws {
        let (client, store, session) = fixture(.faceAuth)
        defer { session.invalidateAndCancel() }
        do { _ = try await client.fetchAreas(); XCTFail("Expected challenge") }
        catch { XCTAssertEqual(error as? BilibiliLiveError, .faceAuthRequired(voucher: "private-voucher")) }
        XCTAssertEqual(store.snapshot().last?.errorKind, .faceAuth)
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(store.snapshot()), as: UTF8.self).contains("private-voucher"))
    }

    func testIdentitySchemaFailureIsRecordedWithoutExportingAccountData() async throws {
        let (_, store, session) = fixture(.missingCode)
        defer { session.invalidateAndCancel() }
        do {
            _ = try await BilibiliControlClient(session: session, diagnostics: store).fetchIdentity(cookieHeader: "SESSDATA=private-cookie")
            XCTFail("Expected invalid identity response")
        } catch { XCTAssertEqual(error as? BilibiliControlError, .invalidResponse) }
        XCTAssertEqual(store.snapshot().last?.stage, .identity)
        XCTAssertEqual(store.snapshot().last?.errorKind, .schema)
    }

    func testMissingStreamFieldsAreDiagnosedAfterHTTPBodyWasAccepted() async throws {
        let (client, store, session) = fixture(.emptyStream)
        defer { session.invalidateAndCancel() }
        do { _ = try await client.fetchUpstream(); XCTFail("Expected missing stream config") }
        catch { XCTAssertEqual(error as? BilibiliLiveError, .missingStreamConfig) }
        XCTAssertEqual(store.snapshot().last?.stage, .upstream)
        XCTAssertEqual(store.snapshot().last?.operation, .parse)
        XCTAssertEqual(store.snapshot().last?.errorKind, .schema)
    }

    func testMissingRoomStateCannotBeMisreadAsConfirmedOffline() async throws {
        let (client, store, session) = fixture(.missingRoomStatus)
        defer { session.invalidateAndCancel() }
        do { _ = try await client.fetchRoomInfo(roomID: 123, cookieHeader: "fixture"); XCTFail("Must not infer offline") }
        catch { XCTAssertEqual(error as? BilibiliLiveError, .invalidResponse) }
        XCTAssertEqual(store.snapshot().last?.stage, .room)
        XCTAssertEqual(store.snapshot().last?.errorKind, .schema)
    }

    func testRetryAfterDateAndInvalidValues() {
        let now = Date(timeIntervalSince1970: 0)
        XCTAssertEqual(BilibiliLiveClient.retryAfterSeconds("Thu, 01 Jan 1970 00:01:00 GMT", now: now), 60)
        XCTAssertEqual(BilibiliLiveClient.retryAfterSeconds("999999999", now: now), 86400)
        XCTAssertNil(BilibiliLiveClient.retryAfterSeconds("-1"))
        XCTAssertNil(BilibiliLiveClient.retryAfterSeconds("private-response"))
    }

    private func fixture(_ scenario: DiagnosticURLProtocol.Scenario) -> (BilibiliLiveClient, BilibiliDiagnosticStore, URLSession) {
        DiagnosticURLProtocol.scenario = scenario
        DiagnosticURLProtocol.paths = []
        let config = URLSessionConfiguration.ephemeral
        // Intercept every request, including fixed start/clock/version endpoints.
        config.protocolClasses = [DiagnosticURLProtocol.self]
        let session = URLSession(configuration: config)
        let store = BilibiliDiagnosticStore()
        let client = BilibiliLiveClient(cookieHeader: "SESSDATA=private-cookie", session: session, diagnostics: store)
        return (client, store, session)
    }
}

private final class DiagnosticURLProtocol: URLProtocol {
    enum Scenario { case rateLimited, timeout, missingCode, badStart, faceAuth, emptyStream, missingRoomStatus }
    static var scenario: Scenario = .missingCode
    static var paths: [String] = []
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let path = request.url!.path
        Self.paths.append(path)
        if Self.scenario == .timeout {
            client?.urlProtocol(self, didFailWithError: URLError(.timedOut)); return
        }
        var status = 200
        let body: String
        switch Self.scenario {
        case .missingRoomStatus: body = #"{"code":0,"data":{"room_id":123}}"#
        case .emptyStream: body = #"{"code":0,"data":{}}"#
        case .rateLimited: status = 429; body = "private-response"
        case .missingCode: body = #"{"data":[]}"#
        case .faceAuth: body = #"{"code":60043,"data":{"risk_extra":{"v_voucher":"private-voucher"}}}"#
        case .badStart:
            if path.hasSuffix("getHomePageLiveVersion") { body = #"{"code":0,"data":{"curr_version":"8.6.0","build":11050}}"# }
            else if path.hasSuffix("now") { body = #"{"code":0,"data":{"now":123456}}"# }
            else { body = #"{"code":-400,"message":"fixture-rejection"}"# }
        case .timeout: return
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil,
            headerFields: ["Content-Type": "application/json", "Retry-After": "30"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
