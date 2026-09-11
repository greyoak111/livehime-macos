import Foundation
import CryptoKit

public struct ObsStreamStatus: Equatable, Sendable {
    public let active: Bool
    public let reconnecting: Bool

    public init(active: Bool, reconnecting: Bool) {
        self.active = active
        self.reconnecting = reconnecting
    }

    /// Whether OBS still owns an output and must be treated as live for stop/logout safety.
    public var outputting: Bool { active || reconnecting }

    /// Whether OBS has an active output which is not in its reconnect loop.
    public var stable: Bool { active && !reconnecting }
}

public protocol ObsControlTransport: Sendable {
    func setStreamingService(url: URL, key: String, metadata: [String: String]) async throws
    func startStreaming() async throws
    func stopStreaming() async throws
    func streamStatus() async throws -> ObsStreamStatus
    func streamingActive() async throws -> Bool
    func recordingActive() async throws -> Bool
}

public enum ObsControlError: Error, Equatable {
    case unavailable
    case rejected(String)
}

private final class ObsTimeoutState: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    func markTimedOut() {
        lock.lock()
        value = true
        lock.unlock()
    }

    var timedOut: Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

/// Bridges Swift task cancellation to URLSessionWebSocketTask.cancel().
/// Cancellation can race socket creation, so the box records the cancelled
/// bit and cancels immediately when a task is installed afterwards.
private final class ObsSocketCancellationBox: @unchecked Sendable {
    private let lock = NSLock()
    private var task: URLSessionWebSocketTask?
    private var cancelled = false

    func install(_ task: URLSessionWebSocketTask) {
        lock.lock()
        self.task = task
        let shouldCancel = cancelled
        lock.unlock()
        if shouldCancel { task.cancel(with: .goingAway, reason: nil) }
    }

    func clear() {
        lock.lock()
        task = nil
        lock.unlock()
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let task = self.task
        lock.unlock()
        task?.cancel(with: .goingAway, reason: nil)
    }
}

/// A small OBS WebSocket v5 transport.  It intentionally keeps the protocol
/// behind `ObsControlTransport`, so the UI does not depend on a third-party
/// WebSocket package and can be replaced by OBS frontend IPC later.
public actor ObsWebSocketTransport: ObsControlTransport {
    public let host: String
    public let port: Int
    private let password: String?
    // Keep the owning URLSession alive for the lifetime of the actor.  The
    // WebSocket task normally retains enough of its session to work, but
    // retaining it here also prevents silent cancellation when Foundation
    // tears down a short-lived local session.
    private let session: URLSession
    private var nextRequestID = 1
    private let requestTimeout: TimeInterval

    public init(host: String = "127.0.0.1", port: Int = 4455, password: String? = nil, requestTimeout: TimeInterval = 8) {
        self.host = host
        self.port = port
        self.password = password
        self.requestTimeout = max(0.1, requestTimeout)
        self.session = URLSession(configuration: .default)
    }

    public func setStreamingService(url: URL, key: String, metadata: [String: String]) async throws {
        var settings = metadata
        settings["server"] = url.absoluteString
        settings["key"] = key
        // OBS WebSocket v5 calls this request SetStreamServiceSettings.
        // SetStreamService is a response/request name from older forks and
        // is rejected by current obs-websocket builds.
        _ = try await request(type: "SetStreamServiceSettings", data: [
            "streamServiceType": "rtmp_custom",
            "streamServiceSettings": settings
        ])
    }

    public func startStreaming() async throws {
        _ = try await request(type: "StartStream")
    }

    public func stopStreaming() async throws {
        let deadline = ProcessInfo.processInfo.systemUptime + requestTimeout
        func remaining() throws -> TimeInterval {
            let seconds = deadline - ProcessInfo.processInfo.systemUptime
            guard seconds > 0 else { throw ObsControlError.rejected("OBS 停止直播超时") }
            return seconds
        }
        var alreadyStopped = false
        do {
            _ = try await request(type: "StopStream", timeout: remaining())
        } catch let error as ObsControlError {
            // OBS returns code 501 (AlreadyStopped) when the output has
            // already ended.  Treat that as success only after status confirms
            // that no output is active; this avoids hiding a real stop failure.
            let text: String
            if case .rejected(let message) = error { text = message } else { throw error }
            if text.contains("[501]") {
                alreadyStopped = true
            } else {
                throw error
            }
        }

        while true {
            let rawStatus = try await fetchStreamStatus(timeout: remaining())
            let status = ObsStreamStatus(active: rawStatus.active, reconnecting: rawStatus.reconnecting)
            if !status.outputting { return }
            if ProcessInfo.processInfo.systemUptime >= deadline {
                if alreadyStopped { throw ObsControlError.rejected("OBS 仍在重连，停止直播超时") }
                throw ObsControlError.rejected("OBS 停止直播超时")
            }
            try await Task.sleep(for: .seconds(min(0.25, try remaining())))
        }
    }

    public func streamStatus() async throws -> ObsStreamStatus {
        let status = try await fetchStreamStatus()
        return ObsStreamStatus(active: status.active, reconnecting: status.reconnecting)
    }

    public func streamingActive() async throws -> Bool {
        let status = try await streamStatus()
        return status.outputting
    }

    public func recordingActive() async throws -> Bool {
        let response = try await request(type: "GetRecordStatus")
        guard let active = response["outputActive"] as? Bool else {
            throw ObsControlError.rejected("OBS 录制状态无效")
        }
        return active
    }

    private func fetchStreamStatus(timeout: TimeInterval? = nil) async throws -> (active: Bool, reconnecting: Bool) {
        let response = try await request(type: "GetStreamStatus", timeout: timeout)
        guard let active = response["outputActive"] as? Bool,
              let reconnecting = response["outputReconnecting"] as? Bool else {
            throw ObsControlError.rejected("OBS 推流状态无效")
        }
        return (active, reconnecting)
    }

    private func connect(on task: URLSessionWebSocketTask) async throws {
        // Every public operation owns its socket.  URLSessionWebSocketTask only
        // supports one outstanding receive; sharing one task between actor
        // calls lets a reentrant actor invocation consume another invocation's
        // response (the old implementation could therefore hang StopStream).
        // A short-lived socket also makes a failed OBS request self-healing.

        do {
            let hello = try await receiveObject(task)
            guard (hello["op"] as? Int) == 0,
                  let data = hello["d"] as? [String: Any],
                  let rpcVersion = data["rpcVersion"] as? Int else {
                throw ObsControlError.rejected("OBS 握手响应无效")
            }
            var identify: [String: Any] = ["rpcVersion": rpcVersion, "eventSubscriptions": 0]
            if let auth = data["authentication"] as? [String: Any] {
                guard let password, let salt = auth["salt"] as? String,
                      let challenge = auth["challenge"] as? String else {
                    throw ObsControlError.rejected("OBS WebSocket 需要密码")
                }
                identify["authentication"] = Self.makeAuthentication(password: password, salt: salt, challenge: challenge)
            }
            try await sendObject(["op": 1, "d": identify], on: task)
            let identified = try await receiveObject(task)
            guard (identified["op"] as? Int) == 2 else {
                throw ObsControlError.rejected("OBS 认证失败")
            }
        } catch let error as ObsControlError {
            throw error
        } catch {
            throw ObsControlError.unavailable
        }
    }

    private func request(type: String, data: [String: Any] = [:], timeout: TimeInterval? = nil) async throws -> [String: Any] {
        guard let url = URL(string: "ws://\(host):\(port)") else { throw ObsControlError.unavailable }
        let task = session.webSocketTask(with: url)
        task.resume()
        let timeoutState = ObsTimeoutState()
        let timeoutWork = DispatchWorkItem {
            timeoutState.markTimedOut()
            task.cancel(with: .goingAway, reason: Data("request timeout".utf8))
        }
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + (timeout ?? requestTimeout), execute: timeoutWork)
        defer {
            timeoutWork.cancel()
            task.cancel(with: .goingAway, reason: nil)
        }

        let cancellation = ObsSocketCancellationBox()
        do {
            return try await withTaskCancellationHandler(operation: {
                cancellation.install(task)
                defer { cancellation.clear() }
                try await connect(on: task)
                let requestID = String(nextRequestID)
                nextRequestID += 1
                var payload: [String: Any] = ["requestType": type, "requestId": requestID]
                if !data.isEmpty { payload["requestData"] = data }
                try await sendObject(["op": 6, "d": payload], on: task)
                while true {
                    let response = try await receiveObject(task)
                    guard (response["op"] as? Int) == 7,
                          let responseData = response["d"] as? [String: Any],
                          responseData["requestId"] as? String == requestID else { continue }
                    guard let status = responseData["requestStatus"] as? [String: Any],
                          status["result"] as? Bool == true else {
                        let status = responseData["requestStatus"] as? [String: Any]
                        let comment = (status?["comment"] as? String) ?? "OBS 请求被拒绝"
                        if let code = status?["code"] as? Int {
                            throw ObsControlError.rejected("\(comment) [\(code)]")
                        }
                        throw ObsControlError.rejected(comment)
                    }
                    return (responseData["responseData"] as? [String: Any]) ?? [:]
                }
            }, onCancel: {
                cancellation.cancel()
            })
        } catch {
            if Task.isCancelled { throw CancellationError() }
            if timeoutState.timedOut {
                throw ObsControlError.rejected("OBS 请求超时")
            }
            if let error = error as? ObsControlError { throw error }
            // A cancelled/closed URLSession task is not necessarily reported
            // as a non-running task.  Do not reuse it: this operation's socket
            // is always torn down by the defer above.
            throw ObsControlError.unavailable
        }
    }

    private func sendObject(_ object: [String: Any], on task: URLSessionWebSocketTask) async throws {
        let data = try JSONSerialization.data(withJSONObject: object)
        guard let text = String(data: data, encoding: .utf8) else { throw ObsControlError.unavailable }
        try await task.send(.string(text))
    }

    private func receiveObject(_ task: URLSessionWebSocketTask) async throws -> [String: Any] {
        let message = try await task.receive()
        let data: Data
        switch message {
        case .string(let text): data = Data(text.utf8)
        case .data(let value): data = value
        @unknown default: throw ObsControlError.unavailable
        }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ObsControlError.rejected("OBS 返回了无效数据")
        }
        return object
    }

    /// Computes the OBS WebSocket v5 authentication response.  This is kept
    /// as a pure helper so the protocol implementation can be checked against
    /// OBS's published test vectors without opening a socket.
    nonisolated static func makeAuthentication(password: String, salt: String, challenge: String) -> String {
        let secret = SHA256.hash(data: Data((password + salt).utf8))
        let secretBase64 = Data(secret).base64EncodedString()
        let auth = SHA256.hash(data: Data((secretBase64 + challenge).utf8))
        return Data(auth).base64EncodedString()
    }
}
