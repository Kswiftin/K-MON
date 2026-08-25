import XCTest
@testable import PokeTokenBar

/// 로컬 네트워크 권한 창이 **언제** 떠도 되는가. macOS 는 앱이 `NWListener` 를 올리는 순간 묻고,
/// 한 번 물으면 그 대답은 앱의 서명 신원에 묶인다 — 그래서 "묻는 시점" 과 "서명 신원의 안정성" 이
/// 같은 증상(업그레이드마다 다시 뜨는 창)의 두 원인이다. 여기서는 앞의 것을 지킨다.
@MainActor
final class LocalNetworkConsentTests: XCTestCase {

    private func makeSettings() -> AppSettings {
        let suite = UserDefaults(suiteName: "local-network-consent-\(UUID().uuidString)")!
        return AppSettings(defaults: suite)
    }

    /// 기본값은 기존 동작 그대로다. 배틀 신청은 팝오버를 열지 않아도 도착해야 하므로, 이 값을
    /// 끄고 시작하면 "신청이 안 온다" 는 조용한 회귀가 된다.
    func testReceivingBattleInvitesStaysOnByDefault() {
        XCTAssertTrue(makeSettings().battleInvitesEnabled)
    }

    /// 끈 사용자는 LAN 탐색이 시작되지 않는다 — 권한 창을 두 번 다시 보지 않는 유일한 경로다.
    /// 설정값과 "리스너를 올리는가" 를 각각 판정하면 한쪽만 바뀌어도 아무 테스트가 안 깨진다.
    func testTurningBattleInvitesOffIsWhatStopsTheDiscoveryListener() {
        let settings = makeSettings()
        XCTAssertTrue(settings.shouldStartLANDiscovery)

        settings.battleInvitesEnabled = false

        XCTAssertFalse(settings.shouldStartLANDiscovery,
                       "설정만 꺼지고 리스너가 그대로면 권한 창은 계속 뜬다")
    }

    /// 선택은 재시작을 넘어 남는다. 매 기동마다 기본값으로 돌아가면 껐다는 사실이 무의미하다.
    func testTheChoiceSurvivesARestart() {
        let suiteName = "local-network-consent-\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: suiteName)!
        defer { suite.removePersistentDomain(forName: suiteName) }

        AppSettings(defaults: suite).battleInvitesEnabled = false

        XCTAssertFalse(AppSettings(defaults: suite).battleInvitesEnabled)
        XCTAssertFalse(AppSettings(defaults: suite).shouldStartLANDiscovery)
    }
}
