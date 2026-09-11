import Foundation
import CoreFoundation

public struct BilibiliIdentity: Equatable, Sendable {
    public let mid: Int64
    public let username: String
    public let isLogin: Bool

    public init(mid: Int64, username: String, isLogin: Bool) {
        self.mid = mid
        self.username = username
        self.isLogin = isLogin
    }
}

public enum BilibiliControlError: Error, Equatable {
    case invalidResponse
    case api(code: Int, message: String)
    case notLoggedIn
    case transport
}

/// Cookie-authenticated, read-only first step after the official login page.
public struct BilibiliControlClient: Sendable {
    public let session: URLSession

    public let diagnostics: BilibiliDiagnosticStore?
    public init(session: URLSession = .shared, diagnostics: BilibiliDiagnosticStore? = nil) {
        self.session = session; self.diagnostics = diagnostics
    }

    public func fetchIdentity(cookieHeader: String) async throws -> BilibiliIdentity {
        var request = URLRequest(url: URL(string: "https://api.bilibili.com/x/web-interface/nav")!)
        request.httpMethod = "GET"
        request.timeoutInterval = 12
        let started = Date()
        func record(_ kind: BilibiliDiagnosticErrorKind? = nil, http: Int? = nil, api: Int? = nil, network: Int? = nil) {
            diagnostics?.record(.init(stage: .identity, httpStatus: http, apiCode: api, networkCode: network,
                durationMilliseconds: Int(max(0, Date().timeIntervalSince(started)) * 1000), errorKind: kind))
        }
        request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        // Match the browser-like headers used by the Windows CEF host. A
        // bespoke UA is more likely to be treated as an unsupported client by
        // the nav endpoint after a risk-control login.
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
        request.setValue("https://www.bilibili.com/", forHTTPHeaderField: "Referer")
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        let (data, response): (Data, URLResponse)
        do { (data, response) = try await session.data(for: request) }
        catch {
            let network = error as? URLError
            record(network?.code == .timedOut ? .timeout : network?.code == .cancelled ? .cancelled : .transport, network: network?.errorCode)
            throw BilibiliControlError.transport
        }
        guard let http = response as? HTTPURLResponse else {
            record(.schema); throw BilibiliControlError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            record(.http, http: http.statusCode); throw BilibiliControlError.transport
        }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let number = root["code"] as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite, number.doubleValue.rounded() == number.doubleValue,
              abs(number.doubleValue) <= Double(Int32.max) else {
            record(.schema, http: http.statusCode); throw BilibiliControlError.invalidResponse
        }
        let code = number.intValue
        guard code == 0 else {
            record(code == -101 ? .auth : .api, http: http.statusCode, api: code)
            if code == -101 { throw BilibiliControlError.notLoggedIn }
            throw BilibiliControlError.api(code: code, message: "身份接口返回失败")
        }
        guard let body = root["data"] as? [String: Any], let isLogin = body["isLogin"] as? Bool else {
            record(.schema, http: http.statusCode, api: code); throw BilibiliControlError.invalidResponse
        }
        guard isLogin else { record(.auth, http: http.statusCode, api: code); throw BilibiliControlError.notLoggedIn }
        let mid: Int64
        if let value = body["mid"] as? Int64 { mid = value }
        else if let value = body["mid"] as? NSNumber { mid = value.int64Value }
        else { mid = 0 }
        guard mid > 0 else { record(.schema, http: http.statusCode, api: code); throw BilibiliControlError.invalidResponse }
        record(http: http.statusCode, api: code)
        return BilibiliIdentity(mid: mid, username: body["uname"] as? String ?? "", isLogin: true)
    }
}
