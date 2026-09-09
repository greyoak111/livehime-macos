import Foundation

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

    public init(session: URLSession = .shared) { self.session = session }

    public func fetchIdentity(cookieHeader: String) async throws -> BilibiliIdentity {
        var request = URLRequest(url: URL(string: "https://api.bilibili.com/x/web-interface/nav")!)
        request.httpMethod = "GET"
        request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        // Match the browser-like headers used by the Windows CEF host. A
        // bespoke UA is more likely to be treated as an unsupported client by
        // the nav endpoint after a risk-control login.
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
        request.setValue("https://www.bilibili.com/", forHTTPHeaderField: "Referer")
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        let (data, response): (Data, URLResponse)
        do { (data, response) = try await session.data(for: request) }
        catch { throw BilibiliControlError.transport }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw BilibiliControlError.transport
        }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let code = root["code"] as? Int,
              code == 0,
              let body = root["data"] as? [String: Any],
              let isLogin = body["isLogin"] as? Bool else {
            if let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let code = root["code"] as? Int {
                throw BilibiliControlError.api(code: code, message: "身份接口返回失败")
            }
            throw BilibiliControlError.invalidResponse
        }
        guard isLogin else { throw BilibiliControlError.notLoggedIn }
        let mid: Int64
        if let value = body["mid"] as? Int64 { mid = value }
        else if let value = body["mid"] as? NSNumber { mid = value.int64Value }
        else { mid = 0 }
        return BilibiliIdentity(mid: mid, username: body["uname"] as? String ?? "", isLogin: true)
    }
}
