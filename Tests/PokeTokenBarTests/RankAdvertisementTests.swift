import Network
import XCTest
@testable import PokeTokenBar

/// 근처 트레이너 목록이 보는 값은 Bonjour TXT 로 전달된다. 랭크, 트레이너 레벨, 업적 단계다.
///
/// 회귀(#85): 그 레코드를 리스너를 만드는 순간에 한 번만 굽고 있었다. 랭크전에서 이기든 지든
/// 광고에는 옛 점수가 남아 상대 화면엔 세션이 끝날 때까지 stale 랭크가 보였다. 리스너 생성
/// 직후만 확인하는 테스트는 결함이 그대로 있는데도 통과하니, 여기서는 값이 바뀐 뒤 광고된 것을
/// 본다. 레벨·업적도 같은 부류라 각자 자기 트리거로 검증한다.
@MainActor
final class RankAdvertisementTests: XCTestCase {

    /// TXT 레코드 재발행을 기록한다. 실제 `NWListener` 는 띄우지 않는다(테스트에 로컬 네트워크
    /// 권한을 요구하지 않으려고 BattleCenter 에 발행 지점 주입 seam 을 뒀다).
    /// 구운 레코드를 다시 파싱해서 담는다. 발행 경로가 실제로 왕복하는지까지 함께 본다.
    private final class Recorder {
        var published: [PeerAdvertisement] = []
        func record(_ record: NWTXTRecord) { published.append(PeerAdvertisement(record)) }
    }

    private func makeStore(_ clock: TestClock) -> CompanionStore {
        let line = EvoLine(baseID: 1, tree: EvoNode(speciesID: 1, children: []),
                           rarity: .common, names: [:])
        let fileURL = storeStateURL("rank-ad")
        return CompanionStore(provider: StubProvider(value: line), clock: clock.closure,
                              fileURL: fileURL, rng: SeededRNG(seed: 7))
    }

    /// 관찰 콜백이 `Task { @MainActor }` 로 미뤄지므로 값이 도착할 때까지 몇 틱 양보한다.
    private func waitForPublish(_ recorder: Recorder, count: Int) async {
        for _ in 0..<40 where recorder.published.count < count { await Task.yield() }
    }

    // MARK: 첫 광고

    /// 첫 광고부터 세 값이 다 실려야 한다. 바뀔 때만 실으면 앱을 켜고 아무것도 하지 않은 상대는
    /// 카드에서 영원히 빈 칸으로 보인다.
    func testTheFirstAdvertisementCarriesAllThreeValues() {
        let store = makeStore(TestClock())
        let recorder = Recorder()
        let net = BattleCenter(companion: store, advertisementPublisher: recorder.record)

        net.refreshAdvertisedProfile()   // 리스너 생성 시점의 첫 광고에 해당

        XCTAssertEqual(recorder.published.count, 1)
        XCTAssertEqual(recorder.published.last?.rankPoints, store.battleRank.points)
        XCTAssertEqual(recorder.published.last?.trainerLevel, store.trainerLevel.level)
        XCTAssertEqual(recorder.published.last?.achievementTiers, store.achievementTierTotal)
    }

    // MARK: 값이 바뀐 뒤 (세 축을 각각 단독으로)

    func testRankChangeRepublishesTheAdvertisedRecord() async {
        let store = makeStore(TestClock())
        let recorder = Recorder()
        let net = BattleCenter(companion: store, advertisementPublisher: recorder.record)
        net.refreshAdvertisedProfile()

        let before = store.battleRank.points
        _ = store.settleRankedBrawl(won: true, opponent: BattleRank(points: 0))
        XCTAssertNotEqual(store.battleRank.points, before, "전제: 승리로 LP 가 움직였다")

        await waitForPublish(recorder, count: 2)
        XCTAssertEqual(recorder.published.last?.rankPoints, store.battleRank.points,
                       "바뀐 랭크가 다시 광고돼야 한다")
        XCTAssertEqual(net.advertisedProfile?.rankPoints, store.battleRank.points)
    }

    /// 트레이너 레벨 단독. 모험을 정산해 레벨만 오른다. 랭크만 관찰하던 코드에서는 실패해야 한다.
    func testTrainerLevelChangeRepublishesTheAdvertisedRecord() async {
        let clock = TestClock()
        let store = makeStore(clock)
        await store.hatch(baseID: 1)
        XCTAssertNotNil(store.state.active, "전제: 모험을 보낼 활성 포켓몬이 있어야 한다")

        let recorder = Recorder()
        let net = BattleCenter(companion: store, advertisementPublisher: recorder.record)
        net.refreshAdvertisedProfile()
        let before = store.trainerLevel.level

        XCTAssertTrue(store.startFocusAdventure(minutes: 25))
        clock.advance(25 * 60)
        XCTAssertNotNil(store.claimAdventure())
        XCTAssertGreaterThan(store.trainerLevel.level, before, "전제: 25분 정산으로 레벨이 올랐다")

        await waitForPublish(recorder, count: 2)
        XCTAssertEqual(recorder.published.last?.trainerLevel, store.trainerLevel.level,
                       "오른 레벨이 다시 광고돼야 한다")
        XCTAssertEqual(net.advertisedProfile?.trainerLevel, store.trainerLevel.level)
    }

    /// 업적 단계 단독. 레이스 완주 한 번으로 1단계를 넘고 랭크·레벨은 그대로다.
    func testAchievementTierChangeRepublishesTheAdvertisedRecord() async {
        let store = makeStore(TestClock())
        let recorder = Recorder()
        let net = BattleCenter(companion: store, advertisementPublisher: recorder.record)
        net.refreshAdvertisedProfile()
        XCTAssertEqual(recorder.published.last?.achievementTiers, 0, "전제: 아직 넘은 단계가 없다")

        store.recordRaceFinish()
        XCTAssertGreaterThan(store.achievementTierTotal, 0, "전제: 완주 1회로 1단계를 넘는다")

        await waitForPublish(recorder, count: 2)
        XCTAssertEqual(recorder.published.last?.achievementTiers, store.achievementTierTotal,
                       "오른 업적 단계가 다시 광고돼야 한다")
        XCTAssertEqual(net.advertisedProfile?.achievementTiers, store.achievementTierTotal)
    }

    // MARK: 재발행하지 않아야 하는 경우

    /// 광고와 무관한 상태 변화(별의조각 적립)까지 재발행하면 광고가 쉴 새 없이 갱신된다.
    /// 세 값이 그대로면 굽지 않는다.
    func testUnchangedProfileDoesNotRepublish() async {
        let store = makeStore(TestClock())
        let recorder = Recorder()
        let net = BattleCenter(companion: store, advertisementPublisher: recorder.record)
        net.refreshAdvertisedProfile()

        store.creditStarPieces(100)
        await Task.yield()
        net.refreshAdvertisedProfile()

        XCTAssertEqual(recorder.published.count, 1, "세 값이 그대로면 재발행하지 않는다")
    }

    /// 한 정산이 레벨과 업적을 함께 올릴 때도 마지막 광고가 현재 상태와 일치해야 한다. 발행
    /// 횟수는 관찰이 몇 번 발화하느냐에 따라 달라지니 최종값으로 잰다.
    func testTheLastAdvertisementMatchesTheCurrentStateWhenTwoValuesMoveTogether() async {
        let clock = TestClock()
        let store = makeStore(clock)
        await store.hatch(baseID: 1)
        let recorder = Recorder()
        let net = BattleCenter(companion: store, advertisementPublisher: recorder.record)
        net.refreshAdvertisedProfile()

        // 60분 정산 = 레벨도 오르고 집중 업적 1단계(60분)도 넘는다.
        XCTAssertTrue(store.startFocusAdventure(minutes: 60))
        clock.advance(60 * 60)
        XCTAssertNotNil(store.claimAdventure())
        XCTAssertGreaterThan(store.achievementTierTotal, 0, "전제: 집중 1단계를 넘었다")

        await waitForPublish(recorder, count: 2)
        XCTAssertEqual(recorder.published.last?.trainerLevel, store.trainerLevel.level)
        XCTAssertEqual(recorder.published.last?.achievementTiers, store.achievementTierTotal)
    }
}
