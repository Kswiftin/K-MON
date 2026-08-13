import XCTest
@testable import PokeTokenBar

final class UpdateCheckerTests: XCTestCase {
    func testNewerPatch() {
        XCTAssertTrue(UpdateChecker.isNewer("2.0.2", than: "2.0.1"))
    }
    func testSameIsNotNewer() {
        XCTAssertFalse(UpdateChecker.isNewer("2.0.1", than: "2.0.1"))
    }
    func testOlderIsNotNewer() {
        XCTAssertFalse(UpdateChecker.isNewer("2.0.0", than: "2.0.1"))
        XCTAssertFalse(UpdateChecker.isNewer("2.0.9", than: "2.1.0"))
    }
    func testNumericNotLexical() {
        // "2.0.10" 은 "2.0.9" 보다 높다 (문자열 비교면 반대로 틀림)
        XCTAssertTrue(UpdateChecker.isNewer("2.0.10", than: "2.0.9"))
    }
    func testMinorAndMajor() {
        XCTAssertTrue(UpdateChecker.isNewer("2.1.0", than: "2.0.9"))
        XCTAssertTrue(UpdateChecker.isNewer("3.0.0", than: "2.9.9"))
    }
    func testDifferentComponentCounts() {
        XCTAssertTrue(UpdateChecker.isNewer("2.0.1", than: "2.0"))   // 2.0.1 > 2.0.0
        XCTAssertFalse(UpdateChecker.isNewer("2.0", than: "2.0.0"))  // 동일
    }

    func testKMONStableReleaseCandidate() {
        let release = UpdateChecker.ReleaseInfo(tag_name: "v2.6.0",
            html_url: "https://github.com/2giduck/K-MON/releases/tag/v2.6.0",
            target_commitish: "abcdef123456", draft: false, prerelease: false,
            assets: [.init(name: "PokeTokenBar.zip",
                browser_download_url: "https://github.com/2giduck/K-MON/releases/download/v2.6.0/PokeTokenBar.zip")])
        let candidate = UpdateChecker.releaseCandidate(from: release, channel: .stable)
        XCTAssertEqual(candidate?.version, "2.6.0")
        XCTAssertEqual(candidate?.channel, .stable)
        XCTAssertNotNil(candidate?.downloadURL)
    }

    func testDevelopmentCandidateUsesCommitPrefixAndRejectsForeignURL() {
        let release = UpdateChecker.ReleaseInfo(tag_name: "development",
            html_url: "https://github.com/2giduck/K-MON/releases/tag/development",
            target_commitish: "1234567890abcdef", draft: false, prerelease: true,
            assets: [.init(name: "PokeTokenBar.zip", browser_download_url: "https://evil.example/app.zip")])
        let candidate = UpdateChecker.releaseCandidate(from: release, channel: .development)
        XCTAssertEqual(candidate?.version, "main-1234567")
        XCTAssertEqual(candidate?.channel, .development)
        XCTAssertNil(candidate?.downloadURL)
    }
}
