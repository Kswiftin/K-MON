import XCTest
@testable import PokeTokenBar

// MARK: 친구 탭 유도 신호 — 한 번 쓰면 꺼져야 한다

/// 홈 탭을 보다 창을 닫고 다시 열면 **계속 친구 탭**으로 튀는 증상이 있었다.
///
/// `pendingAttention` 은 "팝오버를 열 때 친구 탭으로 데려가라" 는 일회성 신호다. 이걸 끄는 자리가
/// `BattleView.onAppear` 였는데, 친구 탭에 관문(`FriendView`)이 생기면서 그 화면은 **배틀이
/// 진행 중일 때만**(`phase != .ready`) 그려지게 됐다. 체육관 한 판을 끝내면 신호는 켜진 채
/// `phase` 가 `.ready` 로 돌아가고, 관문은 선택 화면을 그린다 — 신호를 끌 화면이 영영 안 뜬다.
/// 그래서 열 때마다 친구 탭으로 튀었다.
///
/// 처방은 **읽는 자리에서 끄는 것**이다. 끄는 일을 아래 화면에 맡기면 그 화면이 조건부로 그려지는
/// 순간 같은 사고가 다시 난다. 두 일을 한 호출로 묶어 "읽고 안 끄는" 경로 자체를 없앤다.
@MainActor
final class PendingAttentionTests: XCTestCase {

    private func center() -> BattleCenter {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("attention-\(UUID().uuidString).json")
        let store = CompanionStore(provider: StubProvider(value: line), clock: { Date() },
                                   fileURL: url, rng: SeededRNG(seed: 7))
        return BattleCenter(companion: store)
    }

    private let line = EvoLine(baseID: 1, tree: EvoNode(speciesID: 1, children: []),
                               rarity: .common, names: [1: ["ko": "포1", "en": "P1"]])

    /// 신호가 없으면 아무 데도 안 데려간다 — 늘 true 를 주면 홈 탭이 존재하지 않는 것과 같다.
    func testNoSignalMeansNoRedirect() {
        XCTAssertFalse(center().consumePendingAttention())
    }

    /// **두 번째 열 때는 안 튄다.** 이게 증상 그 자체다.
    func testTheSignalOnlyRedirectsOnce() {
        let battleCenter = center()
        battleCenter.debugRaisePendingAttention()

        XCTAssertTrue(battleCenter.consumePendingAttention(), "한 번은 데려간다")
        XCTAssertFalse(battleCenter.consumePendingAttention(), "두 번째부터는 홈에 머문다")
        XCTAssertFalse(battleCenter.consumePendingAttention())
    }

    /// 읽으면 그 자리에서 꺼진다 — 끄는 일을 다른 화면에 맡기지 않는다.
    func testReadingTheSignalClearsIt() {
        let battleCenter = center()
        battleCenter.debugRaisePendingAttention()
        XCTAssertTrue(battleCenter.pendingAttention)
        battleCenter.consumePendingAttention()
        XCTAssertFalse(battleCenter.pendingAttention)
    }

    /// 새 신호는 다시 데려간다 — 한 번 소비했다고 영영 죽으면 배틀 신청이 와도 화면이 안 바뀐다.
    func testAFreshSignalRedirectsAgain() {
        let battleCenter = center()
        battleCenter.debugRaisePendingAttention()
        battleCenter.consumePendingAttention()

        battleCenter.debugRaisePendingAttention()
        XCTAssertTrue(battleCenter.consumePendingAttention())
    }

    /// **끄는 자리가 화면 밖에 있어야 한다.** 화면이 끄면 그 화면이 조건부로 그려지는 순간
    /// 신호가 갇힌다 — 이번 사고가 정확히 그거였다. 주석은 뺀다(가드가 자기 설명에 걸린다).
    func testNoViewTurnsTheSignalOffOnItsOwn() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/PokeTokenBar/UI")
        let files = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" } ?? []
        XCTAssertGreaterThan(files.count, 5, "소스를 못 찾았다 — 경로가 깨지면 가드가 무력해진다")

        var offenders: [String] = []
        for file in files {
            let code = try String(contentsOf: file, encoding: .utf8)
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map { line -> String in
                    guard let comment = line.range(of: "//") else { return String(line) }
                    return String(line[..<comment.lowerBound])
                }
                .joined(separator: "\n")
            if code.contains("pendingAttention = false") { offenders.append(file.lastPathComponent) }
        }
        XCTAssertEqual(offenders, [], "신호는 `consumePendingAttention()` 으로만 꺼야 한다")
    }
}
