import XCTest
@testable import LiveHimeAdapter

final class BilibiliLiveClientTests: XCTestCase {
    func testFetchCurrentRoomSendsCookieAndParsesFixture() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FixtureURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let base = URL(string: "https://fixture.invalid")!
        let endpoints = BilibiliLiveEndpoints(
            roomInfoURL: base.appendingPathComponent("room"),
            areaListURL: base.appendingPathComponent("areas"),
            upstreamURL: base.appendingPathComponent("upstream"),
            liveInfoURL: base.appendingPathComponent("liveinfo"))
        let client = BilibiliLiveClient(cookieHeader: "SESSDATA=session", biliJct: "csrf", session: session, endpoints: endpoints)
        let room = try await client.fetchCurrentRoom(mid: 42)
        XCTAssertEqual(room.roomID, 123)
        XCTAssertEqual(FixtureURLProtocol.lastRequest?.value(forHTTPHeaderField: "Cookie"), "SESSDATA=session; bili_jct=csrf")
    }

    func testParseStreamConfigFromUpstreamFixture() throws {
        let data = Data(#"{"code":0,"message":"0","data":{"rtmp":{"addr":"rtmp://live.example/app/","code":"abc123"}}}"#.utf8)
        XCTAssertEqual(try BilibiliLiveClient.parseStreamConfig(from: data),
                       BilibiliStreamConfig(server: URL(string: "rtmp://live.example/app/")!, key: "abc123"))
    }

    func testParseStreamConfigFromStartLiveNestedFixture() throws {
        let data = Data(#"{"code":0,"data":{"room_id":123,"rtmp":{"addr":"rtmp://x/live","code":"key"},"change":0}}"#.utf8)
        XCTAssertEqual(try BilibiliLiveClient.parseStreamConfig(from: data).key, "key")
    }

    func testParseErrorsAreMapped() {
        let data = Data(#"{"code":-101,"message":"账号未登录"}"#.utf8)
        XCTAssertThrowsError(try BilibiliLiveClient.parseStreamConfig(from: data)) { error in
            XCTAssertEqual(error as? BilibiliLiveError, .notLoggedIn)
        }
    }

    func testFaceAuthErrorPreservesVoucher() {
        let data = Data(#"{"code":60043,"message":"需要身份验证","data":{"risk_extra":{"v_voucher":"voucher-test"}}}"#.utf8)
        XCTAssertThrowsError(try BilibiliLiveClient.parseStreamConfig(from: data)) { error in
            XCTAssertEqual(error as? BilibiliLiveError, .faceAuthRequired(voucher: "voucher-test"))
        }
    }

    func testRoomAndAreaModelsArePublicAndStable() {
        let room = BilibiliRoomInfo(roomID: 1, title: "测试", liveStatus: 0)
        XCTAssertEqual(room.roomID, 1)
        let area = BilibiliLiveArea(areaID: 10, parentAreaID: 1, name: "游戏")
        XCTAssertEqual(area.name, "游戏")
    }

    func testRoomInfoPrefersV2AreaForStartLive() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [V2AreaFixtureURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let client = BilibiliLiveClient(cookieHeader: "SESSDATA=session; bili_jct=csrf", session: session,
                                        endpoints: BilibiliLiveEndpoints(roomInfoURL: URL(string: "https://fixture.invalid/room")!))
        let room = try await client.fetchCurrentRoom(mid: 42)
        XCTAssertEqual(room.areaID, 86)
    }

    func testFetchCurrentRoomFallsBackThroughAuthenticatedLiveInfo() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FallbackFixtureURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let base = URL(string: "https://fixture.invalid")!
        let endpoints = BilibiliLiveEndpoints(
            roomInfoURL: base.appendingPathComponent("room"),
            areaListURL: base.appendingPathComponent("areas"),
            upstreamURL: base.appendingPathComponent("upstream"),
            liveInfoURL: base.appendingPathComponent("liveinfo"))
        let client = BilibiliLiveClient(cookieHeader: "SESSDATA=session", session: session, endpoints: endpoints)
        let room = try await client.fetchCurrentRoom(mid: 42)
        XCTAssertEqual(room.roomID, 9876)
        XCTAssertEqual(room.title, "Fallback Room")
        XCTAssertEqual(FallbackFixtureURLProtocol.paths, ["/room", "/room/v2/Room/room_id_by_uid", "/liveinfo", "/room/v1/Room/get_info"])
    }
}

private final class V2AreaFixtureURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let path = request.url?.path ?? ""
        let payload: Data
        if path == "/room" {
            payload = Data(#"{"code":0,"data":{"roomid":123,"title":"Legacy"}}"#.utf8)
        } else {
            payload = Data(#"{"code":0,"data":{"room_id":123,"title":"Canonical","area_id":2,"area_v2_id":86,"live_status":0}}"#.utf8)
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                                       headerFields: ["Content-Type":"application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: payload)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private final class FixtureURLProtocol: URLProtocol {
    static var lastRequest: URLRequest?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lastRequest = request
        // getRoomInfoOld's production response uses the legacy `roomid` key.
        let payload = Data(#"{"code":0,"data":{"roomid":123,"uid":42,"title":"Fixture Room","liveStatus":0,"area_id":9}}"#.utf8)
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type":"application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: payload); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private final class FallbackFixtureURLProtocol: URLProtocol {
    static var paths: [String] = []
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let path = request.url?.path ?? ""
        Self.paths.append(path)
        let payload: Data
        switch path {
        case "/room":
            payload = Data(#"{"code":0,"data":{"room_info":{"room_id":0}}}"#.utf8)
        case "/room/v2/Room/room_id_by_uid":
            payload = Data(#"{"code":-404,"message":"fixture fallback"}"#.utf8)
        case "/liveinfo":
            payload = Data(#"{"code":0,"data":{"roomid":9876}}"#.utf8)
        default:
            payload = Data(#"{"code":0,"data":{"room_id":9876,"title":"Fallback Room","live_status":0,"area_id":9}}"#.utf8)
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type":"application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: payload); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
