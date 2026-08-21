import Network
import XCTest
@testable import PokeTokenBar

/// 실제 Bonjour 광고·탐색을 한 프로세스 안에서 왕복시키는 하네스.
///
/// 나머지 광고 테스트는 발행 지점(`advertisementPublisher`)까지만 본다. 실 `NWListener` 는 로컬
/// 네트워크 권한이 필요해 기본 스위트에 못 넣기 때문이다. 그래서 수신 측(`NWBrowser` →
/// `updatePeers` → `BattlePeer.advertisement`)은 두 대를 띄워 눈으로 보는 길밖에 없었다.
///
/// 자기 광고는 서비스 이름의 고유 접미로만 걸러내니, 같은 프로세스의 두 센터는 서로를 남으로
/// 본다. 두 번째 기기 없이 같은 경로를 밟을 수 있다.
///
/// 권한 프롬프트와 mDNS 차단이 CI 를 막지 않게 환경변수로 잠가 둔다:
///
///     KMON_LAN_E2E=1 swift test --filter PeerDiscoveryEndToEndTests
///
/// 한계: `BattleCenter` 에 정지 API 가 없어 이 테스트가 띄운 리스너·브라우저는 프로세스가 끝날
/// 때까지 살아 있다. 기본 스위트에서 켜지 않는 이유다.
@MainActor
final class PeerDiscoveryEndToEndTests: XCTestCase {

    private func makeStore(_ clock: TestClock, trainerName: String) -> CompanionStore {
        let line = EvoLine(baseID: 1, tree: EvoNode(speciesID: 1, children: []),
                           rarity: .common, names: [:])
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("poke-lan-e2e-\(UUID().uuidString).json")
        let store = CompanionStore(provider: StubProvider(value: line), clock: clock.closure,
                                   fileURL: url, rng: SeededRNG(seed: 5))
        // 서비스 이름은 `BattleCenter.init` 이 트레이너 이름으로 굽는다. 센터보다 먼저 정해야 한다.
        store.setTrainerName(trainerName)
        return store
    }

    /// 조건이 참이 될 때까지 런루프를 돌린다. Bonjour 는 초 단위로 느리고 콜백이 메인 큐로 와서
    /// `Task.yield` 로는 부족하다.
    private func waitUntil(_ timeout: TimeInterval = 20, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return condition()
    }

    func testASecondTrainerSeesTheAdvertisedLevelAndTiers() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["KMON_LAN_E2E"] == "1",
                          "실 Bonjour 광고·탐색 — 로컬 네트워크 권한이 필요해 기본 스위트에서는 건너뛴다")

        let clock = TestClock()
        let mine = makeStore(clock, trainerName: "AlphaLanTester")
        let theirs = makeStore(clock, trainerName: "BetaLanTester")

        // 광고할 진행도를 미리 만든다. 레벨 2(25분 정산)에 업적 1단계(레이스 완주).
        await mine.hatch(baseID: 1)
        XCTAssertTrue(mine.startFocusAdventure(minutes: 25))
        clock.advance(25 * 60)
        XCTAssertNotNil(mine.claimAdventure())
        mine.recordRaceFinish()
        XCTAssertEqual(mine.trainerLevel.level, 2, "전제: 레벨이 2 여야 한다")
        XCTAssertGreaterThan(mine.achievementTierTotal, 0, "전제: 업적 1단계를 넘겨야 한다")

        let advertiser = BattleCenter(companion: mine)
        let observer = BattleCenter(companion: theirs)
        advertiser.start()
        observer.start()

        // 1) 발견: 상대 목록에 잡히는가.
        //
        // 실패했을 때 환경이 막았는지 코드가 틀렸는지 구별할 수 있어야 한다. 리스너가 포트를
        // 얻지 못했다면(`listeningPort == nil`) 광고가 시작조차 안 된 것이니 코드 문제가 아니라
        // 권한이나 mDNS 차단이다.
        let found = waitUntil { observer.peers.contains { $0.name == "AlphaLanTester" } }
        let diagnosis = """
            advertiser.listeningPort=\(advertiser.listeningPort.map(String.init) ?? "nil") \
            advertiser.advertisedProfile=\(advertiser.advertisedProfile.map(String.init(describing:)) ?? "nil") \
            advertiser.lastError=\(advertiser.lastError ?? "nil") \
            observer.listeningPort=\(observer.listeningPort.map(String.init) ?? "nil") \
            observer.peers=\(observer.peers.map(\.name)) \
            observer.lastError=\(observer.lastError ?? "nil")
            """
        XCTAssertTrue(found, "20초 안에 광고가 발견되지 않았다 — \(diagnosis)")
        guard let seen = observer.peers.first(where: { $0.name == "AlphaLanTester" }) else { return }

        // 2) 광고한 값이 그대로 도착하는가. 여기가 지금까지 무검증이던 구간이다.
        XCTAssertEqual(seen.advertisement.trainerLevel, mine.trainerLevel.level)
        XCTAssertEqual(seen.advertisement.achievementTiers, mine.achievementTierTotal)
        XCTAssertEqual(seen.rank, mine.battleRank)

        // 3) 값이 바뀌면 재시작 없이 상대 카드가 따라오는가(#85 부류의 수신 측).
        let levelBefore = mine.trainerLevel.level
        XCTAssertTrue(mine.startFocusAdventure(minutes: 90))
        clock.advance(90 * 60)
        XCTAssertNotNil(mine.claimAdventure())
        XCTAssertGreaterThan(mine.trainerLevel.level, levelBefore, "전제: 레벨이 더 올랐다")

        let updated = waitUntil {
            observer.peers.first { $0.name == "AlphaLanTester" }?
                .advertisement.trainerLevel == mine.trainerLevel.level
        }
        XCTAssertTrue(updated,
                      "TXT 재발행이 상대 목록에 반영되지 않았다 — 광고는 갱신됐는데 수신이 stale 하다")
    }
}
