import XCTest
import Darwin
@testable import LiveHimeAdapter

final class ObsControlTransportTests: XCTestCase {
    func testOBSWebSocketV5AuthenticationVector() {
        // SHA256(base64(SHA256(password + salt)) + challenge), base64.
        // Keeping this vector here guards against the easy-to-miss second
        // hash and against hashing the decoded secret instead of its base64
        // representation.
        let actual = ObsWebSocketTransport.makeAuthentication(
            password: "abc",
            salt: "salt",
            challenge: "challenge"
        )
        XCTAssertEqual(actual, "bzh9Xp/d2iFbjL+y9kX3kW4uxgHJ1DYuYByOHcJnLD4=")
    }

    func testCancelledRequestReturnsPromptly() async throws {
        let fixture = try OBSFixture(mode: "stall")
        defer { fixture.stop() }
        let transport = ObsWebSocketTransport(port: fixture.port)
        let operation = Task { try await transport.streamingActive() }
        try await fixture.waitForRequest()
        let started = ContinuousClock.now
        operation.cancel()
        do {
            _ = try await operation.value
            XCTFail("cancelled operation succeeded")
        } catch is CancellationError {} catch { XCTFail("wrong cancellation error: \(error)") }
        XCTAssertLessThan(ContinuousClock.now - started, .seconds(1))
    }

    func testConcurrentOperationsUseIndependentSockets() async throws {
        let fixture = try OBSFixture(mode: "concurrent")
        defer { fixture.stop() }
        let transport = ObsWebSocketTransport(port: fixture.port, requestTimeout: 2)
        async let first = transport.streamingActive()
        async let second = transport.streamingActive()
        let results = try await (first, second)
        XCTAssertNotEqual(results.0, results.1, "each socket must get its own response")
    }

    func testEstablishedConnectionTimeoutIsBounded() async throws {
        let fixture = try OBSFixture(mode: "stall")
        defer { fixture.stop() }
        let transport = ObsWebSocketTransport(port: fixture.port, requestTimeout: 0.5)
        let started = ContinuousClock.now
        do { _ = try await transport.streamingActive(); XCTFail("silent server succeeded") }
        catch let error as ObsControlError { XCTAssertEqual(error, .rejected("OBS 请求超时")) }
        XCTAssertTrue(fixture.receivedRequest)
        XCTAssertLessThan(ContinuousClock.now - started, .seconds(1.5))
    }

    func testStopWaitsForConfirmedOffline() async throws {
        let fixture = try OBSFixture(mode: "stop_later")
        defer { fixture.stop() }
        let transport = ObsWebSocketTransport(port: fixture.port, requestTimeout: 2)
        let started = ContinuousClock.now
        try await transport.stopStreaming()
        XCTAssertGreaterThanOrEqual(ContinuousClock.now - started, .milliseconds(240))
    }

    func testStopCannotReportSuccessWhileReconnectingOrStatusStalls() async throws {
        for mode in ["stopping", "already_reconnecting", "stop_status_stall"] {
            let fixture = try OBSFixture(mode: mode)
            defer { fixture.stop() }
            let transport = ObsWebSocketTransport(port: fixture.port, requestTimeout: 0.5)
            let started = ContinuousClock.now
            do { try await transport.stopStreaming(); XCTFail("\(mode) falsely reported stopped") }
            catch is ObsControlError {} catch { XCTFail("unexpected error: \(error)") }
            XCTAssertLessThan(ContinuousClock.now - started, .seconds(1.5), mode)
        }
    }

    func testAlreadyStoppedIsVerified() async throws {
        let fixture = try OBSFixture(mode: "already_offline")
        defer { fixture.stop() }
        try await ObsWebSocketTransport(port: fixture.port).stopStreaming()
    }

    func testStreamStatusDistinguishesReconnectFromStableOutput() async throws {
        let fixture = try OBSFixture(mode: "already_reconnecting")
        defer { fixture.stop() }
        let status = try await ObsWebSocketTransport(port: fixture.port).streamStatus()
        XCTAssertFalse(status.active)
        XCTAssertTrue(status.reconnecting)
        XCTAssertTrue(status.outputting)
        XCTAssertFalse(status.stable)
    }

    func testMalformedStatusCannotConfirmOffline() async throws {
        let fixture = try OBSFixture(mode: "malformed")
        defer { fixture.stop() }
        do { _ = try await ObsWebSocketTransport(port: fixture.port).streamingActive(); XCTFail("missing status accepted") }
        catch let error as ObsControlError { XCTAssertEqual(error, .rejected("OBS 推流状态无效")) }
    }

    func testRecordingCheckProtectsRestart() async throws {
        let fixture = try OBSFixture(mode: "recording")
        defer { fixture.stop() }
        let active = try await ObsWebSocketTransport(port: fixture.port).recordingActive()
        XCTAssertTrue(active)
    }
}

private final class OBSFixture {
    let port: Int
    private let process = Process()
    private let directory: URL
    private let ready: URL

    init(mode: String) throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("livehime-obs-fixture-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        ready = directory.appendingPathComponent("ready")
        let fixture = Bundle.module.url(forResource: "obs_websocket", withExtension: "py", subdirectory: "Fixtures")!
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [fixture.path, mode, ready.path]
        process.standardOutput = output
        process.standardError = FileHandle.standardError
        try process.run()
        let text = String(data: output.fileHandleForReading.availableData, encoding: .utf8) ?? ""
        guard let number = Int(text.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            process.terminate()
            throw NSError(domain: "OBSFixture", code: 1)
        }
        port = number
    }

    var receivedRequest: Bool { FileManager.default.fileExists(atPath: ready.path) }

    func waitForRequest() async throws {
        for _ in 0..<100 {
            if receivedRequest { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw NSError(domain: "OBSFixture", code: 2)
    }

    func stop() {
        if process.isRunning {
            let pid = process.processIdentifier
            process.terminate()
            if pid > 0 { kill(pid, SIGKILL) }
        }
        try? FileManager.default.removeItem(at: directory)
    }
}
