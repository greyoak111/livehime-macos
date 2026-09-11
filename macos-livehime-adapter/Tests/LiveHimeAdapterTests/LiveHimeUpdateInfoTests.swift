import XCTest
@testable import LiveHimeAdapter

final class LiveHimeUpdateInfoTests: XCTestCase {
    func testReleaseURLTargetsPublicRepositoryReleases() {
        XCTAssertEqual(LiveHimeUpdateInfo.releasesURL.absoluteString,
                       "https://github.com/greyoak111/livehime-macos/releases")
        XCTAssertEqual(LiveHimeUpdateInfo.releasesURL.scheme, "https")
        XCTAssertEqual(LiveHimeUpdateInfo.releasesURL.host, "github.com")
        XCTAssertEqual(LiveHimeUpdateInfo.releasesURL.path, "/greyoak111/livehime-macos/releases")
    }

    func testCurrentVersionMatchesStableRelease() {
        XCTAssertEqual(LiveHimeUpdateInfo.currentVersion, "0.1.2")
    }
}
