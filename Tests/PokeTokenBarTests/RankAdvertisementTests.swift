import Network
import XCTest
@testable import PokeTokenBar

/// 근처 트레이너 목록의 랭크는 Bonjour TXT 레코드로 전달된다.
///
/// 회귀(#85): 그 레코드를 **리스너를 만드는 순간에 한 번만** 굽고 있었다. 랭크전에서 이기든 지든
/// 광고에는 옛 점수가 그대로 남아, 상대 화면엔 세션이 끝날 때까지 stale 랭크가 보였다.
/// 리스너 생성 직후만 확인하는 테스트는 이 결함이 그대로 있는데도 통과한다 — 그래서 여기서는
/// **랭크가 바뀐 뒤** 광고된 값을 본다.
@MainActor
final class RankAdvertisementTests: XCTestCase {

    /// TXT 레코드 재발행을 기록한다. 실제 `NWListener` 는 띄우지 않는다(테스트에 로컬 네트워크
    /// 권한을 요구하지 않으려고 BattleCenter 에 발행 지점 주입 seam 을 뒀다).
    private final class Recorder {
        var points: [Int] = []
        func record(_ record: NWTXTRecord) {
            if let raw = record["rankPoints"], let value = Int(raw) { points.append(value) }
        }
    }

    private func makeStore() -> CompanionStore {
        let line = EvoLine(baseID: 1, tree: EvoNode(speciesID: 1, children: []),
                           rarity: .common, names: [:])
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("poke-rank-ad-\(UUID().uuidString).json")
        return CompanionStore(provider: StubProvider(value: line), clock: { Date() },
                              fileURL: fileURL, rng: SeededRNG(seed: 7))
    }

    /// 관찰 콜백이 `Task { @MainActor }` 로 미뤄지므로 값이 도착할 때까지 몇 틱 양보한다.
    private func waitForPublish(_ recorder: Recorder, count: Int) async {
        for _ in 0..<20 where recorder.points.count < count { await Task.yield() }
    }

    func testRankChangeRepublishesTheAdvertisedRecord() async {
        let store = makeStore()
        let recorder = Recorder()
        let net = BattleCenter(companion: store, rankRecordPublisher: recorder.record)
        net.refreshAdvertisedRank()   // 리스너 생성 시점의 첫 광고에 해당
        XCTAssertEqual(recorder.points, [store.battleRank.points], "전제: 현재 랭크가 한 번 광고된다")

        let before = store.battleRank.points
        _ = store.settleRankedBrawl(won: true, opponent: BattleRank(points: 0))
        XCTAssertNotEqual(store.battleRank.points, before, "전제: 승리로 LP 가 움직였다")

        await waitForPublish(recorder, count: 2)
        XCTAssertEqual(recorder.points.last, store.battleRank.points, "바뀐 랭크가 다시 광고돼야 한다")
        XCTAssertEqual(net.advertisedRankPoints, store.battleRank.points)
    }

    /// 랭크와 무관한 상태 변화(별의조각 적립)까지 재발행하면 광고가 쉴 새 없이 갱신된다.
    /// 같은 값이면 굽지 않는다.
    func testUnchangedRankDoesNotRepublish() async {
        let store = makeStore()
        let recorder = Recorder()
        let net = BattleCenter(companion: store, rankRecordPublisher: recorder.record)
        net.refreshAdvertisedRank()

        store.creditStarPieces(100)
        await Task.yield()
        net.refreshAdvertisedRank()

        XCTAssertEqual(recorder.points.count, 1, "랭크가 그대로면 재발행하지 않는다")
    }
}
