import XCTest
@testable import PokeTokenBar

/// 방생(#88). 박스는 지금까지 늘기만 했다 — 줄어드는 경로는 동행 교체와 디버그 훅뿐이었다.
@MainActor
final class MonReleaseTests: XCTestCase {

    private let line = EvoLine(baseID: 1, tree: EvoNode(speciesID: 1, children: []),
                               rarity: .common, names: [1: ["en": "One", "ko": "하나"]])

    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("poke-release-\(UUID().uuidString).json")
    }

    private func store(at url: URL) -> CompanionStore {
        CompanionStore(provider: StubProvider(value: line), clock: { Date() },
                       fileURL: url, rng: SeededRNG(seed: 7))
    }

    private func boxed(_ id: Int, graduated: Bool = false) -> MonState {
        MonState(baseID: id, pathIDs: [id], stageIndex: 0, usedAtStage: 0,
                 rarity: .common, totalForms: 1,
                 names: [id: ["en": "P\(id)", "ko": "포\(id)"]], isGraduated: graduated)
    }

    func testReleasingABoxedMonRemovesOnlyThatOne() {
        let s = store(at: tempURL())
        let (a, b) = (boxed(4), boxed(7))
        s.debugSetBoxedMons([a, b])

        XCTAssertTrue(s.releaseMon(a.id))
        XCTAssertEqual(s.boxedMons.map(\.id), [b.id])
    }

    /// 되돌릴 수 없는 조작이라 대상이 없으면 조용히 아무 일도 없어야 한다 — 박스를 통째로 비우거나
    /// 엉뚱한 개체를 놓아주면 안 된다.
    func testReleasingAnUnknownIdChangesNothing() {
        let s = store(at: tempURL())
        s.debugSetBoxedMons([boxed(4)])

        XCTAssertFalse(s.releaseMon(UUID()))
        XCTAssertEqual(s.boxedMons.count, 1)
    }

    /// 동행 개체는 방생 대상이 아니다 — 사라지면 성장 tick 이 붙을 곳이 없어진다.
    /// (트리거 브랜치: id 는 실재하지만 박스가 아니라 `state.active` 에 있는 경우.)
    func testTheActiveMonCannotBeReleased() async {
        let s = store(at: tempURL())
        await s.hatch(baseID: 1)
        let activeID = s.state.active?.id
        XCTAssertNotNil(activeID)

        XCTAssertFalse(s.releaseMon(activeID!))
        XCTAssertEqual(s.state.active?.id, activeID, "동행은 그대로 남는다")
    }

    /// 저장하지 않으면 앱을 다시 열었을 때 놓아준 개체가 돌아온다.
    func testReleaseIsPersisted() {
        let url = tempURL()
        let s = store(at: url)
        let a = boxed(4)
        s.debugSetBoxedMons([a, boxed(7)])
        XCTAssertTrue(s.releaseMon(a.id))

        XCTAssertEqual(store(at: url).boxedMons.map(\.currentID), [7])
    }

    /// 졸업분의 영구 도감 기록은 개체와 별개다(#27/#28) — 놓아줘도 남는다.
    /// 남지 않으면 방생이 도감 달성도를 지우는 경로가 된다.
    func testReleasingAGraduatedMonKeepsItsDexRecord() throws {
        let url = tempURL()
        let graduated = boxed(1, graduated: true)
        let entry = DexEntry(baseID: 1, finalID: 1, chainOrder: [1], rarity: .common,
                             caughtAt: Date(timeIntervalSince1970: 1_700_000_000))
        let encoder = JSONEncoder()
        let dexJSON = String(decoding: try encoder.encode([entry]), as: UTF8.self)
        let boxJSON = String(decoding: try encoder.encode([graduated]), as: UTF8.self)
        try Data("""
        {"economyVersion":2,"forcedResetVersion":1,"language":"en",\
        "dex":\(dexJSON),"boxedMons":\(boxJSON)}
        """.utf8).write(to: url)

        let s = store(at: url)
        XCTAssertEqual(s.state.dex.count, 1, "전제: 영구 기록이 하나 있다")
        XCTAssertEqual(s.boxedMons.count, 1, "전제: 그 개체가 박스에 남아 있다")

        XCTAssertTrue(s.releaseMon(s.boxedMons[0].id))
        XCTAssertEqual(s.state.dex.count, 1, "영구 기록은 방생과 무관하다")
        XCTAssertTrue(s.dexEntries.contains { $0.baseID == 1 })
    }

    /// 대조군 — 미졸업 개체의 도감 줄은 "박스에 있는 동안만" 합성된 것이라 개체와 함께 사라진다.
    /// 위 테스트만 두면 "도감이 아무 일에도 안 변한다"도 통과한다.
    func testReleasingANonGraduatedMonDropsItsLivingDexRow() {
        let s = store(at: tempURL())
        let mon = boxed(4)
        s.debugSetBoxedMons([mon])
        XCTAssertTrue(s.dexEntries.contains { $0.baseID == 4 }, "전제: 박스 개체도 도감에 잡힌다")

        XCTAssertTrue(s.releaseMon(mon.id))
        XCTAssertFalse(s.dexEntries.contains { $0.baseID == 4 })
        XCTAssertTrue(s.state.dex.isEmpty, "영구 기록이 애초에 없었다")
    }
}
