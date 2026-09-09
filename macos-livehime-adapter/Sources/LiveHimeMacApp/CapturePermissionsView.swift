import AppKit
import AVFoundation
import CoreGraphics
import ScreenCaptureKit

/// Permission requests originate in the responsible app, not a shell or a
/// temporary probe binary. Merely refreshing this view never requests access.
@MainActor
final class CapturePermissionsView: NSStackView {
    private let screenStatus = NSTextField(labelWithString: "")
    private let microphoneStatus = NSTextField(labelWithString: "")
    private let cameraStatus = NSTextField(labelWithString: "")
    private let detail = NSTextField(wrappingLabelWithString: "")
    private var screenRequested = false
    private var checking = false
    private var screenButton: NSButton!
    private var microphoneButton: NSButton!
    private var cameraButton: NSButton!
    var onRestart: (() -> Void)?

    static var screenAuthorized: Bool { CGPreflightScreenCaptureAccess() }

    init() {
        super.init(frame: .zero)
        orientation = .vertical
        alignment = .leading
        spacing = 8
        let title = NSTextField(labelWithString: "采集权限 · LiveHime macOS")
        title.font = .systemFont(ofSize: 14, weight: .semibold)
        addArrangedSubview(title)
        screenButton = button("授权屏幕录制", #selector(requestScreen))
        microphoneButton = button("授权麦克风", #selector(requestMicrophone))
        cameraButton = button("授权摄像头", #selector(requestCamera))
        for (label, action) in [(screenStatus, screenButton!), (microphoneStatus, microphoneButton!), (cameraStatus, cameraButton!)] {
            label.setContentHuggingPriority(.defaultLow, for: .horizontal)
            let row = NSStackView(views: [label, action])
            row.distribution = .fill
            row.spacing = 16
            addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: widthAnchor).isActive = true
        }
        let actions = NSStackView(views: [
            button("检查采集权限", #selector(checkCapture)),
            button("重启应用以应用授权", #selector(restart))
        ])
        actions.spacing = 8
        addArrangedSubview(actions)
        detail.font = .systemFont(ofSize: 12)
        detail.textColor = .secondaryLabelColor
        addArrangedSubview(detail)
        detail.widthAnchor.constraint(equalTo: widthAnchor).isActive = true
        widthAnchor.constraint(equalToConstant: 560).isActive = true
        refresh()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func button(_ title: String, _ action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        return button
    }

    func refresh() {
        let screenAllowed = Self.screenAuthorized
        screenStatus.stringValue = "屏幕与系统音频：" + (screenAllowed ? "已授权" : "当前进程未获授权")
        screenButton.title = screenAllowed || screenRequested ? "打开录屏设置" : "授权屏幕录制"
        let microphone = AVCaptureDevice.authorizationStatus(for: .audio)
        let camera = AVCaptureDevice.authorizationStatus(for: .video)
        microphoneStatus.stringValue = "麦克风：" + description(microphone)
        cameraStatus.stringValue = "摄像头：" + description(camera)
        microphoneButton.title = microphone == .notDetermined ? "授权麦克风" : "打开麦克风设置"
        cameraButton.title = camera == .notDetermined ? "授权摄像头" : "打开摄像头设置"
        if !checking {
            detail.stringValue = screenAllowed
                ? "使用对应采集源时才需授权麦克风或摄像头。若 OBS 仍提示未授权，请结束直播和录制后重启应用。"
                : "系统设置中请选择 LiveHime macOS。已打开开关但这里仍未授权时，请结束直播和录制后重启应用。"
        }
        writeDiagnostic(screen: screenAllowed)
    }

    private func description(_ state: AVAuthorizationStatus) -> String {
        switch state {
        case .authorized: return "已授权"
        case .notDetermined: return "尚未申请"
        case .denied: return "未授权，请在系统设置开启"
        case .restricted: return "受系统限制"
        @unknown default: return "状态未知"
        }
    }

    @objc private func requestScreen() {
        if Self.screenAuthorized || screenRequested {
            openPrivacy("ScreenCapture")
        } else {
            screenRequested = true
            _ = CGRequestScreenCaptureAccess()
            refresh()
        }
    }

    @objc private func requestMicrophone() { requestMedia(.audio, pane: "Microphone") }
    @objc private func requestCamera() { requestMedia(.video, pane: "Camera") }

    private func requestMedia(_ media: AVMediaType, pane: String) {
        guard AVCaptureDevice.authorizationStatus(for: media) == .notDetermined else {
            openPrivacy(pane)
            return
        }
        AVCaptureDevice.requestAccess(for: media) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    private func openPrivacy(_ pane: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_\(pane)") else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func restart() { onRestart?() }

    @objc func checkCapture() {
        refresh()
        // ScreenCaptureKit may itself display a request on denial. Never call
        // it automatically or use repeated enumeration as a permission probe.
        guard Self.screenAuthorized, !checking else { return }
        checking = true
        detail.stringValue = "正在检查可用显示器（不会录制或开播）…"
        Task { [weak self] in
            guard let self else { return }
            defer { self.checking = false }
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
                self.detail.stringValue = "采集权限检查通过：可读取 \(content.displays.count) 个显示器。此检查不会录制或开播。"
                self.writeDiagnostic(screen: true, displays: content.displays.count)
            } catch {
                self.detail.stringValue = "系统尚未允许读取显示器。请检查 LiveHime 的录屏授权，并重启应用后重试。"
                self.writeDiagnostic(screen: Self.screenAuthorized, captureError: (error as NSError).code)
            }
        }
    }

    private func writeDiagnostic(screen: Bool, displays: Int? = nil, captureError: Int? = nil) {
        // Only permission enums and counts; never device names, windows,
        // account cookies, stream keys, audio or screen contents.
        var object: [String: Any] = [
            "screen_authorized": screen,
            "microphone": AVCaptureDevice.authorizationStatus(for: .audio).rawValue,
            "camera": AVCaptureDevice.authorizationStatus(for: .video).rawValue,
            "bundle_id": Bundle.main.bundleIdentifier ?? "unknown",
            "time": ISO8601DateFormatter().string(from: Date())
        ]
        object["display_count"] = displays
        object["capture_error_code"] = captureError
        let directory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/LiveHime")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) {
            try? data.write(to: directory.appendingPathComponent("capture-permissions.json"), options: .atomic)
        }
    }
}
