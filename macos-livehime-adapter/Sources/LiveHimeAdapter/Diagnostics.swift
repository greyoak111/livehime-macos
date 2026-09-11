import Foundation

public enum BilibiliDiagnosticStage: String, Codable, Sendable {
    case room
    case identity
    case areas
    case version
    case upstream
    case start
    case stop
    case serverTime
    case http
    case webBridge
    case loginPage
    case faceAuthPage
}

public enum BilibiliDiagnosticOperation: String, Codable, Sendable {
    case request
    case parse
    case resolve
    case mutate
    case callback
    case navigation
}

public enum BilibiliDiagnosticErrorKind: String, Codable, Sendable {
    case transport
    case http
    case schema
    case api
    case auth
    case eligibility
    case faceAuth
    case cancelled
    case timeout
    case unsupported
    case untrusted
}

/// A deliberately small, export-safe diagnostic record. It never stores URL,
/// request body, response text, cookies, tokens, stream keys, or server prose.
public struct BilibiliDiagnosticEvent: Codable, Equatable, Sendable {
    public let timestamp: Date
    public let stage: BilibiliDiagnosticStage
    public let operation: BilibiliDiagnosticOperation
    public let httpStatus: Int?
    public let apiCode: Int?
    public let networkCode: Int?
    public let durationMilliseconds: Int
    public let errorKind: BilibiliDiagnosticErrorKind?
    public let retryAfterSeconds: Int?

    public init(timestamp: Date = Date(), stage: BilibiliDiagnosticStage,
                operation: BilibiliDiagnosticOperation = .request,
                httpStatus: Int? = nil, apiCode: Int? = nil, networkCode: Int? = nil,
                durationMilliseconds: Int = 0,
                errorKind: BilibiliDiagnosticErrorKind? = nil,
                retryAfterSeconds: Int? = nil) {
        self.timestamp = timestamp
        self.stage = stage
        self.operation = operation
        self.httpStatus = httpStatus
        self.apiCode = apiCode
        self.networkCode = networkCode
        self.durationMilliseconds = max(0, durationMilliseconds)
        self.errorKind = errorKind
        self.retryAfterSeconds = retryAfterSeconds
    }
}

/// Thread-safe bounded in-memory diagnostics. The default capacity is small so
/// diagnostics cannot become a persistent activity log or contain credentials.
public final class BilibiliDiagnosticStore: @unchecked Sendable {
    private let lock = NSLock()
    private let capacity: Int
    private var events: [BilibiliDiagnosticEvent] = []

    public init(capacity: Int = 128) {
        self.capacity = max(1, capacity)
        self.events.reserveCapacity(self.capacity)
    }

    public func record(_ event: BilibiliDiagnosticEvent) {
        lock.lock()
        defer { lock.unlock() }
        events.append(event)
        if events.count > capacity { events.removeFirst(events.count - capacity) }
    }

    public func snapshot() -> [BilibiliDiagnosticEvent] {
        lock.lock()
        defer { lock.unlock() }
        return events
    }

    public func clear() {
        lock.lock()
        events.removeAll(keepingCapacity: true)
        lock.unlock()
    }
}
