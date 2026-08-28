import XCTest
@testable import PokeTokenBar

/// 박스 상한(#145). `SaveTransfer.sanitized` 의 100마리 절단이 **불러오기 전용 방어**인데도 매 기동
/// 로드에 걸려 있어서, 박스가 100 인 상태로 졸업·부화한 개체가 다음 실행에 말없이 사라졌다.
@MainActor
final class BoxCapacityTests: XCTestCase {

    private let line = EvoLine(baseID: 1, tree: EvoNode(speciesID: 1, children: []),
                               rarity: .common, names: [1: ["en": "One", "ko": "하나"]])

    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("poke-box-\(UUID().uuidString).json")
    }

    private func store(at url: URL) -> CompanionStore {
        CompanionStore(provider: StubProvider(value: line), clock: { Date() },
                       fileURL: url, rng: SeededRNG(seed: 7))
    }

    private func boxed(_ id: Int) -> MonState {
        MonState(baseID: id, pathIDs: [id], stageIndex: 0, usedAtStage: 0,
                 rarity: .common, totalForms: 1,
                 names: [id: ["en": "P\(id)", "ko": "포\(id)"]], isGraduated: false)
    }

    /// 결함 재현 — 자기 디스크에서 읽은 세이브는 자르지 않는다. 자르면 그 실행에서 얻은 개체가 소멸한다.
    func testLocalSaveKeepsEveryBoxedMonAboveTheImportCap() {
        let url = tempURL()
        let mons = (1...101).map(boxed)
        let s = store(at: url)
        s.debugSetBoxedMons(mons)

        let reloaded = store(at: url)
        XCTAssertEqual(reloaded.boxedMons.count, 101)
        XCTAssertEqual(reloaded.boxedMons.last?.baseID, 101, "마지막에 들어온 개체가 잘려나가면 안 된다")
    }

    /// 졸업 경로 자체를 밟는다 — 절단이 되살아나도 상한 근처의 졸업이 소멸하는 것을 잡는다.
    func testGraduatingIntoAFullBoxSurvivesReload() async {
        let url = tempURL()
        let s = store(at: url)
        s.debugSetBoxedMons((1...100).map(boxed))
        await s.hatch(baseID: 1)
        let activeID = s.state.active?.id
        s.debugAccrueLevelExperience(300_000_000)
        XCTAssertTrue(s.graduateCompanion(), "전제: 졸업이 실제로 실행된다")

        let reloaded = store(at: url)
        XCTAssertTrue(reloaded.boxedMons.contains { $0.id == activeID },
                      "졸업 개체가 다음 실행에서 사라지면 안 된다")
    }

    /// 불러오기(앱 밖에서 온 파일)는 계속 자른다 — 다만 **최신 쪽을 남긴다**.
    func testImportedSaveTruncatesToTheNewestBoxedMons() {
        var state = CompanionState()
        state.boxedMons = (1...(SaveTransfer.maxImportedBoxedMons + 50)).map(boxed)

        let clean = SaveTransfer.sanitized(state, origin: .importedFile)
        XCTAssertEqual(clean.boxedMons.count, SaveTransfer.maxImportedBoxedMons)
        XCTAssertEqual(clean.boxedMons.last?.baseID, SaveTransfer.maxImportedBoxedMons + 50,
                       "잘라도 최신 개체는 남는다")
        XCTAssertEqual(clean.boxedMons.first?.baseID, 51, "잘리는 쪽은 가장 오래된 개체다")
    }
}
