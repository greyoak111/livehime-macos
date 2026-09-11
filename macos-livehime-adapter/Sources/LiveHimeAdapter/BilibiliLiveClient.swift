import Foundation
import CryptoKit
import CoreFoundation

public struct BilibiliRoomInfo: Equatable, Sendable {
    public let roomID: Int64
    public let uid: Int64
    public let shortRoomID: Int64
    public let title: String
    public let liveStatus: Int
    public let areaID: Int

    public init(roomID: Int64, uid: Int64 = 0, shortRoomID: Int64 = 0, title: String = "", liveStatus: Int = 0, areaID: Int = 0) {
        self.roomID = roomID; self.uid = uid
        self.shortRoomID = shortRoomID
        self.title = title
        self.liveStatus = liveStatus
        self.areaID = areaID
    }
}

public struct BilibiliLiveArea: Equatable, Sendable {
    public let areaID: Int64
    public let parentAreaID: Int64
    public let name: String
    public let parentName: String
    public init(areaID: Int64, parentAreaID: Int64 = 0, name: String, parentName: String = "") {
        self.areaID = areaID; self.parentAreaID = parentAreaID; self.name = name; self.parentName = parentName
    }
}

public struct BilibiliLiveEndpoints: Equatable, Sendable {
    public var roomInfoURL: URL
    public var roomIDByUIDURL: URL
    public var areaListURL: URL
    public var upstreamURL: URL
    public var liveVersionURL: URL
    /// Legacy endpoint which resolves the authenticated user's room id.
    /// Kept injectable so the fallback can be tested without hitting Bilibili.
    public var liveInfoURL: URL
    public init(roomInfoURL: URL = URL(string: "https://api.live.bilibili.com/room/v1/Room/getRoomInfoOld")!,
                roomIDByUIDURL: URL = URL(string: "https://api.live.bilibili.com/room/v2/Room/room_id_by_uid")!,
                areaListURL: URL = URL(string: "https://api.live.bilibili.com/room/v1/Area/getList")!,
                upstreamURL: URL = URL(string: "https://api.live.bilibili.com/xlive/app-blink/v1/live/GetUpStreamRtmp")!,
                liveVersionURL: URL = URL(string: "https://api.live.bilibili.com/xlive/app-blink/v1/liveVersionInfo/getHomePageLiveVersion")!,
                liveInfoURL: URL = URL(string: "https://api.live.bilibili.com/i/api/liveinfo")!) {
        self.roomInfoURL = roomInfoURL; self.roomIDByUIDURL = roomIDByUIDURL; self.areaListURL = areaListURL; self.upstreamURL = upstreamURL; self.liveVersionURL = liveVersionURL; self.liveInfoURL = liveInfoURL
    }
}

public struct BilibiliStreamConfig: Equatable, Sendable {
    public let server: URL
    public let key: String

    public init(server: URL, key: String) {
        self.server = server
        self.key = key
    }
    public var address: String { server.absoluteString }
    public var code: String { key }

    public init(address: String, code: String) {
        self.server = URL(string: address)!
        self.key = code
    }
}

public struct BilibiliLiveVersion: Equatable, Sendable {
    public let version: String
    public let build: Int
    public init(version: String, build: Int) { self.version = version; self.build = build }
}

public enum BilibiliLiveError: Error, Equatable {
    case invalidResponse
    case api(code: Int, message: String)
    case missingCSRF
    case missingRoom
    case transport
    case network(code: Int)
    case http(status: Int, retryAfterSeconds: Int?)
    case notLoggedIn
    case missingStreamConfig
    case faceAuthRequired(voucher: String?)
}

/// Cookie-authenticated live-room operations. The mutating methods are kept
/// explicit and are never called automatically by the login flow.
public struct BilibiliLiveClient: Sendable {
    public let session: URLSession
    public let endpoints: BilibiliLiveEndpoints
    public let diagnostics: BilibiliDiagnosticStore?
    private let defaultCookieHeader: String

    public init(session: URLSession = .shared, diagnostics: BilibiliDiagnosticStore? = nil) { self.session = session; self.endpoints = .init(); self.defaultCookieHeader = ""; self.diagnostics = diagnostics }
    public init(cookieHeader: String, biliJct: String? = nil, session: URLSession = .shared,
                endpoints: BilibiliLiveEndpoints = .init(), diagnostics: BilibiliDiagnosticStore? = nil) {
        self.diagnostics = diagnostics
        self.session = session; self.endpoints = endpoints
        if let biliJct, !biliJct.isEmpty, !cookieHeader.contains("bili_jct=") {
            self.defaultCookieHeader = cookieHeader + (cookieHeader.isEmpty ? "" : "; ") + "bili_jct=" + biliJct
        } else { self.defaultCookieHeader = cookieHeader }
    }

    public func fetchCurrentRoom(mid: Int64) async throws -> BilibiliRoomInfo {
        do {
            let legacy = try await fetchRoomInfo(url: endpoints.roomInfoURL, query: [URLQueryItem(name: "mid", value: String(mid))], cookieHeader: defaultCookieHeader)
            // getRoomInfoOld omits the v2 child-area id. Fetch the canonical
            // record so startLive receives the required area_v2 value.
            if legacy.areaID == 0 {
                if let canonical = try? await fetchRoomInfo(roomID: legacy.roomID, cookieHeader: defaultCookieHeader), canonical.areaID != 0 {
                    return canonical
                }
            }
            return legacy
        } catch BilibiliLiveError.missingRoom {
            // The current web client resolves the anchor room through this
            // endpoint. getRoomInfoOld can return an empty room_info object
            // even for a valid account, which otherwise disables Start.
            if let roomID = try? await resolveRoomIDByUID(mid: mid) {
                return try await fetchRoomInfo(roomID: roomID, cookieHeader: defaultCookieHeader)
            }
            // Some accounts return an empty `room_info` from getRoomInfoOld
            // until the live page has been opened. The authenticated legacy
            // endpoint still knows the room id, so resolve it and fetch the
            // canonical room record as a fallback.
            let roomID = try await resolveCurrentRoom(cookieHeader: defaultCookieHeader)
            return try await fetchRoomInfo(roomID: roomID, cookieHeader: defaultCookieHeader)
        }
    }

    public func resolveRoomIDByUID(mid: Int64) async throws -> Int64 {
        let root = try await requestJSON(
            url: withQuery(endpoints.roomIDByUIDURL, [URLQueryItem(name: "uid", value: String(mid))]),
            cookieHeader: defaultCookieHeader,
            body: nil
        )
        let data = root["data"] as? [String: Any]
        let roomID = int64(data?["room_id"] ?? root["room_id"])
        guard roomID > 0 else { throw BilibiliLiveError.missingRoom }
        return roomID
    }

    public func fetchAreas(parentID: Int64? = nil, platform: String = "pc_link") async throws -> [BilibiliLiveArea] {
        var query = [URLQueryItem(name: "platform", value: platform)]
        if let parentID { query.append(URLQueryItem(name: "parent_id", value: String(parentID))) }
        let root = try await requestJSON(url: withQuery(endpoints.areaListURL, query), cookieHeader: defaultCookieHeader, body: nil)
        guard let data = root["data"] else { throw BilibiliLiveError.invalidResponse }
        var list: [[String: Any]] = []
        func flatten(_ value: Any, inheritedParentID: Int64 = 0, inheritedParentName: String = "") {
            if let items = value as? [[String: Any]] {
                items.forEach { flatten($0, inheritedParentID: inheritedParentID, inheritedParentName: inheritedParentName) }
                return
            }
            guard let d = value as? [String: Any] else { return }
            let childValues = ["list", "area_list", "children", "areas"].compactMap { d[$0] }
            let ownID = int64(d["id"] ?? d["area_id"])
            let ownName = d["name"] as? String ?? d["area_name"] as? String ?? ""
            // Parent areas are containers only. `startLive.area_v2` must use
            // a leaf/sub-area id; exposing a parent id (for example “网游”)
            // produces Bilibili's generic -400 request error.
            if childValues.isEmpty,
               (d["id"] != nil || d["area_id"] != nil),
               d["name"] != nil || d["area_name"] != nil {
                var leaf = d
                if leaf["parent_id"] == nil && leaf["parent_area_id"] == nil && inheritedParentID > 0 {
                    leaf["parent_id"] = inheritedParentID
                }
                if leaf["parent_name"] == nil && leaf["parent_area_name"] == nil && !inheritedParentName.isEmpty {
                    leaf["parent_name"] = inheritedParentName
                }
                list.append(leaf)
            }
            childValues.forEach {
                flatten($0,
                        inheritedParentID: ownID > 0 ? ownID : inheritedParentID,
                        inheritedParentName: !ownName.isEmpty ? ownName : inheritedParentName)
            }
        }
        flatten(data)
        guard !list.isEmpty else { throw BilibiliLiveError.invalidResponse }
        return list.compactMap { d in
            let id = int64(d["id"] ?? d["area_id"]); guard id > 0, let name = d["name"] as? String ?? d["area_name"] as? String else { return nil }
            return BilibiliLiveArea(areaID: id, parentAreaID: int64(d["parent_id"] ?? d["parent_area_id"]), name: name, parentName: d["parent_name"] as? String ?? d["parent_area_name"] as? String ?? "")
        }
    }

    /// Returns the current LiveHime-compatible client version/build markers
    /// required by startLive on accounts that reject stale hard-coded values.
    public func fetchLiveVersion() async throws -> BilibiliLiveVersion {
        let root = try await requestJSON(
            url: withQuery(endpoints.liveVersionURL, [URLQueryItem(name: "system_version", value: "2")]),
            cookieHeader: defaultCookieHeader,
            body: nil
        )
        let data = root["data"] as? [String: Any] ?? root
        let version = data["curr_version"] as? String ?? data["version"] as? String ?? ""
        let build = int(data["build"])
        guard !version.isEmpty, build > 0 else { throw BilibiliLiveError.invalidResponse }
        return BilibiliLiveVersion(version: version, build: build)
    }

    public func fetchUpstream(roomID: Int64? = nil) async throws -> BilibiliStreamConfig {
        var query: [URLQueryItem] = [URLQueryItem(name: "platform", value: "pc_link")]
        if let roomID { query.append(URLQueryItem(name: "room_id", value: String(roomID))) }
        let root = try await requestJSON(url: withQuery(endpoints.upstreamURL, query), cookieHeader: defaultCookieHeader, body: nil)
        return try parseStreamConfig(root, stage: .upstream)
    }

    public func resolveCurrentRoom(cookieHeader: String) async throws -> Int64 {
        let root = try await requestJSON(
            url: endpoints.liveInfoURL,
            cookieHeader: cookieHeader,
            body: nil
        )
        func findRoomID(_ value: Any?) -> Int64? {
            if let dict = value as? [String: Any] {
                // Prefer explicit room keys. `id` is accepted only when it is
                // nested under room_info/live_info to avoid treating an area
                // or unrelated object id as a room id.
                for key in ["roomid", "room_id", "roomId"] {
                    let id = int64(dict[key]); if id > 0 { return id }
                }
                for key in ["room_info", "live_info", "room", "data"] {
                    if let id = findRoomID(dict[key]) { return id }
                }
                if dict["room_id"] == nil, dict["roomid"] == nil,
                   (dict["room_info"] != nil || dict["live_info"] != nil),
                   let id = int64(dict["id"]) as Int64?, id > 0 { return id }
                for child in dict.values { if let id = findRoomID(child) { return id } }
            } else if let array = value as? [Any] {
                for child in array { if let id = findRoomID(child) { return id } }
            }
            return nil
        }
        if let roomID = findRoomID(root["data"]) { return roomID }
        throw BilibiliLiveError.missingRoom
    }

    public func fetchRoomInfo(roomID: Int64, cookieHeader: String) async throws -> BilibiliRoomInfo {
        var components = URLComponents(string: "https://api.live.bilibili.com/room/v1/Room/get_info")!
        components.queryItems = [URLQueryItem(name: "room_id", value: String(roomID))]
        let root = try await requestJSON(url: components.url!, cookieHeader: cookieHeader, body: nil)
        guard let data = root["data"] as? [String: Any],
              int64(data["room_id"]) == roomID,
              let liveStatus = Self.apiCode(data["live_status"] ?? data["liveStatus"]),
              [0, 1, 2].contains(liveStatus) else {
            diagnostics?.record(.init(stage: .room, operation: .parse, errorKind: .schema))
            throw BilibiliLiveError.invalidResponse
        }
        return BilibiliRoomInfo(
            roomID: roomID,
            uid: int64(data["uid"]),
            shortRoomID: int64(data["short_id"]),
            title: data["title"] as? String ?? "",
            liveStatus: liveStatus,
            areaID: int(data["area_v2_id"] ?? data["area_id"])
        )
    }

    public func startLive(roomID: Int64, areaID: Int, parentAreaID: Int64 = 0, cookieHeader: String) async throws -> BilibiliStreamConfig {
        let csrf = try csrf(from: cookieHeader)
        // Use the current markers from the same endpoint as the web client;
        // retain the known values as a transient-network fallback.
        let liveVersion = try? await fetchLiveVersion()
        let version = liveVersion?.version ?? "8.6.0"
        let build = String(liveVersion?.build ?? 11050)
        // The current Windows/web flow uses the server clock and places these
        // eight fields on the POST query string in insertion order. Keep that
        // exact order for the app signature; extra fields (such as
        // csrf_token/backup_stream) make newer accounts reject the request.
        let values = [
            ("appkey", "aae92bc66f3edfab"), ("area_v2", String(areaID)),
            ("build", build), ("csrf", csrf), ("platform", "pc_link"),
            ("room_id", String(roomID)), ("ts", await fetchServerTimestamp()),
            ("version", version)
        ]
        let unsigned = formString(values)
        let signedValues = values + [("sign", md5Hex(unsigned + "af125a0d5279fd576c1b4418a3e8276d"))]
        let query = signedValues.map { URLQueryItem(name: $0.0, value: $0.1) }
        let root = try await requestJSON(
            url: withQuery(URL(string: "https://api.live.bilibili.com/room/v1/Room/startLive")!, query),
            cookieHeader: cookieHeader, body: nil, httpMethod: "POST"
        )
        return try parseStreamConfig(root, stage: .start)
    }

    public func stopLive(roomID: Int64, cookieHeader: String) async throws {
        let csrf = try csrf(from: cookieHeader)
        let body = form([("room_id", String(roomID)), ("platform", "pc_link"), ("csrf", csrf), ("csrf_token", csrf)])
        _ = try await requestJSON(
            url: URL(string: "https://api.live.bilibili.com/room/v1/Room/stopLive")!,
            cookieHeader: cookieHeader, body: body
        )
    }

    public static func parseStreamConfig(from data: Data) throws -> BilibiliStreamConfig {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw BilibiliLiveError.invalidResponse }
        guard let code = Self.apiCode(root["code"]) else { throw BilibiliLiveError.invalidResponse }
        if code != 0 {
            if code == -101 { throw BilibiliLiveError.notLoggedIn }
            if code == 60043 || code == 60024 {
                let data = root["data"] as? [String: Any]
                let risk = data?["risk_extra"] as? [String: Any]
                throw BilibiliLiveError.faceAuthRequired(voucher: risk?["v_voucher"] as? String)
            }
            throw BilibiliLiveError.api(code: code, message: root["message"] as? String ?? root["msg"] as? String ?? "Bilibili 接口返回失败")
        }
        return try parseStreamConfig(root)
    }

    private static func parseStreamConfig(_ root: [String: Any]) throws -> BilibiliStreamConfig {
        func scan(_ value: Any?) -> (String, String)? {
            if let d = value as? [String: Any] {
                let a = d["addr"] as? String ?? d["server"] as? String ?? d["rtmp_addr"] as? String
                let k = d["code"] as? String ?? d["key"] as? String ?? d["stream_code"] as? String
                if let a, let k, !a.isEmpty, !k.isEmpty { return (a, k) }
                for v in d.values { if let x = scan(v) { return x } }
            } else if let a = value as? [Any] { for v in a { if let x = scan(v) { return x } } }
            return nil
        }
        guard let pair = scan(root["data"]), let server = URL(string: pair.0),
              ["rtmp", "rtmps"].contains(server.scheme?.lowercased() ?? ""),
              let host = server.host, !host.isEmpty else { throw BilibiliLiveError.missingStreamConfig }
        return BilibiliStreamConfig(server: server, key: pair.1)
    }

    private func parseStreamConfig(_ root: [String: Any], stage: BilibiliDiagnosticStage) throws -> BilibiliStreamConfig {
        do { return try Self.parseStreamConfig(root) }
        catch {
            diagnostics?.record(.init(stage: stage, operation: .parse, errorKind: .schema))
            throw error
        }
    }

    private func fetchRoomInfo(url: URL, query: [URLQueryItem], cookieHeader: String) async throws -> BilibiliRoomInfo {
        let root = try await requestJSON(url: withQuery(url, query), cookieHeader: cookieHeader, body: nil)
        guard let data = root["data"] as? [String: Any] else { throw BilibiliLiveError.missingRoom }
        let d = data["room_info"] as? [String: Any] ?? data
        // getRoomInfoOld uses the legacy `roomid`/`roomname` names while
        // get_info uses `room_id`/`title`; accept both response shapes.
        let rid = int64(d["room_id"] ?? d["roomid"]); guard rid > 0 else { throw BilibiliLiveError.missingRoom }
        return BilibiliRoomInfo(roomID: rid, uid: int64(d["uid"]), shortRoomID: int64(d["short_id"]), title: d["title"] as? String ?? d["roomname"] as? String ?? "", liveStatus: int(d["live_status"] ?? d["liveStatus"]), areaID: int(d["area_v2_id"] ?? d["area_id"]))
    }

    private func withQuery(_ url: URL, _ query: [URLQueryItem]) -> URL { var c = URLComponents(url: url, resolvingAgainstBaseURL: false)!; c.queryItems = query; return c.url! }

    private func requestJSON(url: URL, cookieHeader: String, body: Data?, httpMethod: String? = nil) async throws -> [String: Any] {
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.httpMethod = httpMethod ?? (body == nil ? "GET" : "POST")
        request.httpBody = body
        request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        // Match the Origin header emitted by the official LiveHime web
        // client. Some live endpoints reject otherwise well-formed native
        // requests before they reach CSRF validation.
        request.setValue("https://api.live.bilibili.com", forHTTPHeaderField: "Origin")
        request.setValue("https://live.bilibili.com/", forHTTPHeaderField: "Referer")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
        if body != nil { request.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type") }
        let started = Date()
        let stage = diagnosticStage(url)
        let operation: BilibiliDiagnosticOperation = request.httpMethod == "POST" ? .mutate : .request
        func record(_ kind: BilibiliDiagnosticErrorKind? = nil, http: Int? = nil, api: Int? = nil, retry: Int? = nil, network: Int? = nil) {
            diagnostics?.record(.init(stage: stage, operation: operation, httpStatus: http,
                apiCode: api, networkCode: network, durationMilliseconds: Int(max(0, Date().timeIntervalSince(started)) * 1000),
                errorKind: kind, retryAfterSeconds: retry))
        }
        let data: Data
        let response: URLResponse
        do { (data, response) = try await session.data(for: request) }
        catch let error as URLError {
            record(error.code == .cancelled ? .cancelled : error.code == .timedOut ? .timeout : .transport, network: error.errorCode)
            throw BilibiliLiveError.network(code: error.errorCode)
        } catch { record(.transport); throw BilibiliLiveError.transport }
        guard let http = response as? HTTPURLResponse else {
            record(.schema); throw BilibiliLiveError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let retry = Self.retryAfterSeconds(http.value(forHTTPHeaderField: "Retry-After"))
            record(.http, http: http.statusCode, retry: retry)
            throw BilibiliLiveError.http(status: http.statusCode, retryAfterSeconds: retry)
        }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let code = Self.apiCode(root["code"]) else {
            record(.schema, http: http.statusCode); throw BilibiliLiveError.invalidResponse
        }
        if code != 0 {
            let kind: BilibiliDiagnosticErrorKind = code == -101 ? .auth :
                (code == 60043 || code == 60024) ? .faceAuth : .api
            record(kind, http: http.statusCode, api: code)
            if code == -101 { throw BilibiliLiveError.notLoggedIn }
            if code == 60043 || code == 60024 {
                let data = root["data"] as? [String: Any]
                let risk = data?["risk_extra"] as? [String: Any]
                throw BilibiliLiveError.faceAuthRequired(voucher: risk?["v_voucher"] as? String)
            }
            throw BilibiliLiveError.api(code: code, message: root["message"] as? String ?? root["msg"] as? String ?? "Bilibili 接口返回失败")
        }
        record(http: http.statusCode, api: code)
        return root
    }

    private func diagnosticStage(_ url: URL) -> BilibiliDiagnosticStage {
        switch url.path {
        case endpoints.areaListURL.path: return .areas
        case endpoints.liveVersionURL.path: return .version
        case endpoints.upstreamURL.path: return .upstream
        case "/room/v1/Room/startLive": return .start
        case "/room/v1/Room/stopLive": return .stop
        case "/x/report/click/now": return .serverTime
        case endpoints.roomInfoURL.path, endpoints.roomIDByUIDURL.path,
             endpoints.liveInfoURL.path, "/room/v1/Room/get_info": return .room
        default: return .http
        }
    }

    private static func apiCode(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite, number.doubleValue.rounded() == number.doubleValue,
              abs(number.doubleValue) <= Double(Int32.max) else { return nil }
        return number.intValue
    }

    static func retryAfterSeconds(_ value: String?, now: Date = Date()) -> Int? {
        guard let value else { return nil }
        if let seconds = Int(value.trimmingCharacters(in: .whitespaces)), seconds >= 0 {
            return min(seconds, 86400)
        }
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.timeZone = TimeZone(secondsFromGMT: 0)
        format.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        guard let date = format.date(from: value) else { return nil }
        return min(86400, max(0, Int(date.timeIntervalSince(now).rounded(.up))))
    }

    private func fetchServerTimestamp() async -> String {
        guard let url = URL(string: "https://api.bilibili.com/x/report/click/now") else {
            return String(Int(Date().timeIntervalSince1970))
        }
        do {
            let root = try await requestJSON(url: url, cookieHeader: defaultCookieHeader, body: nil)
            if let data = root["data"] as? [String: Any] {
                let value = int64(data["now"])
                if value > 0 { return String(value) }
            }
        } catch { }
        return String(Int(Date().timeIntervalSince1970))
    }

    private func csrf(from cookieHeader: String) throws -> String {
        for part in cookieHeader.split(separator: ";") {
            let pair = part.split(separator: "=", maxSplits: 1).map(String.init)
            if pair.count == 2 && pair[0].trimmingCharacters(in: .whitespaces) == "bili_jct" && !pair[1].isEmpty { return pair[1] }
        }
        throw BilibiliLiveError.missingCSRF
    }

    private func form(_ values: [(String, String)]) -> Data {
        Data(formString(values).utf8)
    }

    private func formString(_ values: [(String, String)]) -> String {
        let allowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "+&="))
        return values.map { "\($0.0.addingPercentEncoding(withAllowedCharacters: allowed) ?? $0.0)=\($0.1.addingPercentEncoding(withAllowedCharacters: allowed) ?? $0.1)" }.joined(separator: "&")
    }

    private func md5Hex(_ string: String) -> String {
        Insecure.MD5.hash(data: Data(string.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func int(_ value: Any?) -> Int { (value as? NSNumber)?.intValue ?? (value as? String).flatMap(Int.init) ?? 0 }
    private func int64(_ value: Any?) -> Int64 { (value as? NSNumber)?.int64Value ?? (value as? String).flatMap(Int64.init) ?? 0 }
}
