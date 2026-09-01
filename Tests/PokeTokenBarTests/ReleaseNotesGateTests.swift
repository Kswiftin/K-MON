import XCTest
@testable import PokeTokenBar

/// 업데이트 뒤 릴리스 노트를 띄우는 판정. 창·네트워크와 떼어 둔 이유가 여기 있다 —
/// 판정이 프레젠터 안에 있으면 "신규 설치는 안 띄운다"·"버전당 한 번" 을 테스트가 못 밟는다.
final class ReleaseNotesGateTests: XCTestCase {
    /// 새로 깐 사용자에게 남의 릴리스 노트를 던지지 않는다. 도장만 찍어 다음 업데이트부터 센다.
    func testFreshInstallStampsWithoutShowing() {
        XCTAssertEqual(ReleaseNotesGate.decide(current: "2.9.0", lastSeen: nil, enabled: true), .stampOnly)
    }

    func testUpgradeShows() {
        XCTAssertEqual(ReleaseNotesGate.decide(current: "2.9.0", lastSeen: "2.8.3", enabled: true), .show)
    }

    /// 같은 버전으로 재실행 — 앱을 열 때마다 창이 뜨면 안 된다.
    func testSameVersionDoesNothing() {
        XCTAssertEqual(ReleaseNotesGate.decide(current: "2.9.0", lastSeen: "2.9.0", enabled: true), .none)
    }

    /// 옛 빌드를 도로 실행한 경우. 도장을 낮춰 찍으면 다시 올라올 때 이미 본 노트가 또 뜬다.
    func testDowngradeDoesNothing() {
        XCTAssertEqual(ReleaseNotesGate.decide(current: "2.8.0", lastSeen: "2.9.0", enabled: true), .none)
    }

    /// 꺼 둔 동안에도 도장은 찍힌다. 안 찍으면 나중에 다시 켰을 때 묵은 버전 노트가 튀어나온다.
    func testDisabledUpgradeStampsWithoutShowing() {
        XCTAssertEqual(ReleaseNotesGate.decide(current: "2.9.0", lastSeen: "2.8.3", enabled: false), .stampOnly)
    }

    func testDisabledFreshInstallStamps() {
        XCTAssertEqual(ReleaseNotesGate.decide(current: "2.9.0", lastSeen: nil, enabled: false), .stampOnly)
    }

    /// 두 자리 패치는 문자열 비교로 뒤집힌다("2.0.9" > "2.0.10"). 판정은 semver 비교를 써야 한다.
    func testNumericVersionOrdering() {
        XCTAssertEqual(ReleaseNotesGate.decide(current: "2.0.10", lastSeen: "2.0.9", enabled: true), .show)
        XCTAssertEqual(ReleaseNotesGate.decide(current: "2.0.9", lastSeen: "2.0.10", enabled: true), .none)
    }

    /// 키 이름이 한 곳에만 있어야 읽는 쪽과 쓰는 쪽이 어긋나지 않는다.
    func testStampRoundTrip() {
        let suite = "ReleaseNotesGateTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertNil(ReleaseNotesGate.lastSeenVersion(in: defaults))
        ReleaseNotesGate.stamp("2.9.0", in: defaults)
        XCTAssertEqual(ReleaseNotesGate.lastSeenVersion(in: defaults), "2.9.0")
    }

    /// 릴리스 본문(`body`)을 DTO 가 안 읽으면 창이 늘 빈 채로 뜬다 — 에러도 안 난다.
    func testReleaseInfoDecodesBody() throws {
        let json = """
        {"tag_name":"v2.9.0","html_url":"https://github.com/Kswiftin/K-MON/releases/tag/v2.9.0",
         "target_commitish":"abc123","draft":false,"prerelease":false,
         "body":"## What's Changed\\n* 릴리스 노트 창 추가","assets":[]}
        """
        let info = try JSONDecoder().decode(UpdateChecker.ReleaseInfo.self, from: Data(json.utf8))
        XCTAssertEqual(info.body, "## What's Changed\n* 릴리스 노트 창 추가")
    }

    /// `body` 가 빠진 옛 응답도 디코딩돼야 한다 — 여기서 throw 하면 업데이트 확인 전체가 죽는다.
    func testReleaseInfoWithoutBodyStillDecodes() throws {
        let json = """
        {"tag_name":"v2.9.0","html_url":"https://github.com/Kswiftin/K-MON/releases/tag/v2.9.0",
         "target_commitish":"abc123","draft":false,"prerelease":false,"assets":[]}
        """
        let info = try JSONDecoder().decode(UpdateChecker.ReleaseInfo.self, from: Data(json.utf8))
        XCTAssertNil(info.body)
    }

    /// 버전 문자열은 그대로 URL 에 박히므로 semver 가 아니면 만들지 않는다.
    /// (`CFBundleShortVersionString` 은 손으로 빌드한 앱에서 무엇이든 될 수 있다.)
    func testReleaseTagURLOnlyForSemver() {
        XCTAssertEqual(UpdateChecker.releaseTagURL(version: "2.9.0")?.absoluteString,
                       "https://github.com/Kswiftin/K-MON/releases/tag/v2.9.0")
        XCTAssertNil(UpdateChecker.releaseTagURL(version: "2.9"))
        XCTAssertNil(UpdateChecker.releaseTagURL(version: "2.9.0 or die"))
        XCTAssertNil(UpdateChecker.releaseTagURL(version: "../../../etc"))
    }
}
