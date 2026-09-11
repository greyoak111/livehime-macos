import Foundation

/// Public update destination shared by the native host and lightweight tools.
///
/// Releases are intentionally opened in the user's default browser instead of
/// downloading or replacing an installed app in the background. This keeps the
/// update boundary explicit while still making upgrades from an older bundle
/// one click away.
public enum LiveHimeUpdateInfo {
    public static let releasesURL = URL(string: "https://github.com/greyoak111/livehime-macos/releases")!
    public static let currentVersion = "0.1.2"
}
