import AppKit

/// Locates, prepares and launches the OBS.app staged by package-app.sh.
/// The preparation step enables obs-websocket before OBS starts, so the host
/// does not depend on the user opening OBS' Tools > WebSocket settings.
@MainActor
final class BundledOBSLauncher {
    enum LaunchError: Error {
        case notBundled
        case failed
        case invalidConfiguration
    }

    struct PreparedConfiguration: Sendable {
        let password: String
        let configURL: URL
    }

    static var bundledAppURL: URL? {
        Bundle.main.resourceURL?.appendingPathComponent("OBS.app", isDirectory: true)
    }

    static var runningBundledApp: NSRunningApplication? {
        guard let expected = bundledAppURL?.resolvingSymlinksInPath().path else { return nil }
        return NSRunningApplication.runningApplications(withBundleIdentifier: "com.obsproject.obs-studio")
            .first { $0.bundleURL?.resolvingSymlinksInPath().path == expected }
    }

    static var otherOBSRunning: Bool {
        let expected = bundledAppURL?.resolvingSymlinksInPath().path
        return NSRunningApplication.runningApplications(withBundleIdentifier: "com.obsproject.obs-studio")
            .contains { $0.bundleURL?.resolvingSymlinksInPath().path != expected }
    }

    /// A saved scene containing any macOS screen capture source must not be
    /// launched before the responsible LiveHime bundle has screen permission.
    /// This is deliberately conservative: an unused source can be removed by
    /// the user, and an image-only scene still works once the check passes.
    static var savedScenesRequireScreenPermission: Bool {
        let fm = FileManager.default
        let root = fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/obs-studio/basic/scenes", isDirectory: true)
        guard let files = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return false }
        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let sources = object["sources"] as? [[String: Any]] else { continue }
            if sources.contains(where: { (source: [String: Any]) -> Bool in
                let id = source["id"] as? String ?? ""
                return id == "screen_capture" || id == "display_capture" || id == "window_capture"
            }) { return true }
        }
        return false
    }

    /// The same per-user password OBS will read from obs-websocket's config.
    /// Returning nil is valid when the config has not been created yet.
    static var configuredWebSocketPassword: String? {
        guard let url = websocketConfigURL,
              let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let password = object["server_password"] as? String,
              !password.isEmpty else { return nil }
        return password
    }

    /// Creates or updates the standard OBS obs-websocket config. We preserve
    /// unrelated keys and only force the settings required by this app. The
    /// password remains local to this Mac and is passed to the host transport.
    @discardableResult
    static func prepareConfiguration() throws -> PreparedConfiguration {
        guard let url = websocketConfigURL else { throw LaunchError.invalidConfiguration }
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        // OBS records an unclean shutdown in this sentinel directory. The
        // host deliberately starts OBS as its own backend process and may be
        // terminated independently, so clear stale markers before launch to
        // avoid presenting OBS's safe-mode dialog over the native panel.
        // `obs_module_config_path` resolves to Application Support/obs-studio
        // on macOS, while CrashHandler appends `obs-studio/.sentinel` to the
        // Application Support root. The resulting marker directory is the
        // sibling of plugin_config, not inside it.
        let configRoot = directory.deletingLastPathComponent().deletingLastPathComponent()
        let sentinelDirectory = configRoot.appendingPathComponent(".sentinel", isDirectory: true)
        if let entries = try? FileManager.default.contentsOfDirectory(at: sentinelDirectory, includingPropertiesForKeys: nil) {
            for entry in entries where entry.lastPathComponent.hasPrefix("run_") {
                try? FileManager.default.removeItem(at: entry)
            }
        }

        var object: [String: Any] = [:]
        if let data = try? Data(contentsOf: url),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            object = existing
        }
        let password: String
        if let existing = object["server_password"] as? String, !existing.isEmpty {
            password = existing
        } else {
            password = randomPassword()
            object["server_password"] = password
        }
        object["server_enabled"] = true
        object["server_port"] = 4455
        object["auth_required"] = true
        if object["first_load"] == nil { object["first_load"] = false }
        if object["alerts_enabled"] == nil { object["alerts_enabled"] = false }

        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
        return PreparedConfiguration(password: password, configURL: url)
    }

    @discardableResult
    static func launch() async throws -> NSRunningApplication {
        guard let appURL = bundledAppURL else { throw LaunchError.notBundled }
        // NSWorkspace may otherwise send a second open event to an already
        // running OBS instance. That creates the very unclean-shutdown prompt
        // we are trying to avoid and can leave the WebSocket backend waiting
        // behind a modal dialog.
        if let running = runningBundledApp {
            return running
        }
        guard !otherOBSRunning else { throw LaunchError.failed }
        // This is intentionally done immediately before launching. OBS reads
        // the plugin config during startup and does not reload server_enabled
        // from disk while running.
        _ = try prepareConfiguration()
        let configuration = NSWorkspace.OpenConfiguration()
        // OBS is the bundled backend for the native panel. Keep its window
        // hidden so the user stays in one LiveHime window while the process
        // provides capture/encoding and WebSocket services underneath.
        configuration.activates = false
        configuration.hides = true
        // Keep OBS on IPv4 localhost-compatible networking and skip update or
        // missing-file dialogs that would block a first-run embedded launch.
        configuration.arguments = ["--websocket_ipv4_only", "--disable-updater", "--disable-missing-files-check"]
        return try await withCheckedThrowingContinuation { continuation in
            NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { app, error in
                if let app { continuation.resume(returning: app) }
                else { continuation.resume(throwing: error ?? LaunchError.failed) }
            }
        }
    }

    private static var websocketConfigURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("obs-studio/plugin_config/obs-websocket/config.json", isDirectory: false)
    }

    private static func randomPassword() -> String {
        let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789")
        return String((0..<24).compactMap { _ in alphabet.randomElement() })
    }
}
