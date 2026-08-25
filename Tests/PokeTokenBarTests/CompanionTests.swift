import XCTest
@testable import PokeTokenBar

// MARK: 경제

final class PokemonBalanceTests: XCTestCase {
    func testGraduationTotalIsConstantPerRarityRegardlessOfStages() {
        for rarity in [Rarity.common, .uncommon, .rare, .legendary] {
            let T = PokemonBalance.graduationTotal(rarity)
            for k in 1...3 {
                let sum = (0..<k).reduce(0) { $0 + PokemonBalance.phaseThreshold(rarity: rarity, totalForms: k, stageIndex: $1) }
                // 반올림 오차 허용
                XCTAssertLessThanOrEqual(abs(sum - T), 2, "rarity=\(rarity) k=\(k) sum=\(sum) T=\(T)")
            }
        }
    }
    func testHigherStageCostsMore() {
        for k in 2...3 {
            for i in 0..<(k - 1) {
                XCTAssertLessThan(
                    PokemonBalance.phaseThreshold(rarity: .common, totalForms: k, stageIndex: i),
                    PokemonBalance.phaseThreshold(rarity: .common, totalForms: k, stageIndex: i + 1))
            }
        }
    }
    func testRarerCostsMore() {
        XCTAssertLessThan(PokemonBalance.graduationTotal(.common), PokemonBalance.graduationTotal(.uncommon))
        XCTAssertLessThan(PokemonBalance.graduationTotal(.uncommon), PokemonBalance.graduationTotal(.rare))
        XCTAssertLessThan(PokemonBalance.graduationTotal(.rare), PokemonBalance.graduationTotal(.legendary))
    }
    func testRarityDerivation() {
        XCTAssertEqual(Rarity.from(captureRate: 255, isLegendary: false, isMythical: false), .common)
        XCTAssertEqual(Rarity.from(captureRate: 90, isLegendary: false, isMythical: false), .uncommon)
        XCTAssertEqual(Rarity.from(captureRate: 45, isLegendary: false, isMythical: false), .rare)
        XCTAssertEqual(Rarity.from(captureRate: 3, isLegendary: true, isMythical: false), .legendary)
    }
}

// (부화 풀 하드코딩 제거 — 선정 로직 테스트는 CompanionIdentityTests 의 샘플러 테스트로 대체)

// MARK: 헬퍼

struct SeededRNG: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

final class CountingRNG: RandomNumberGenerator {
    private var base: SeededRNG
    private(set) var callCount = 0

    init(seed: UInt64) { base = SeededRNG(seed: seed) }

    func next() -> UInt64 {
        callCount += 1
        return base.next()
    }
}

@MainActor
private func waitUntil(timeout: TimeInterval = 1, _ condition: @escaping () -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() { return true }
        try? await Task.sleep(nanoseconds: 1_000_000)
    }
    return condition()
}

struct StubProvider: PokeProviding {
    let value: EvoLine
    func line(baseSpeciesID: Int) async throws -> EvoLine { value }
    // 인덱스 = 자기 라인 base 단일 항목 → 선택 롤 1회 소비 후 항상 그 base (테스트 rng 재생 단순화)
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [BaseSpecies(id: value.baseID, captureRate: 255)] }
}

private actor SuspendedLineProvider: PokeProviding {
    private let value: EvoLine
    private var continuation: CheckedContinuation<EvoLine, Never>?
    private var suspended = false

    init(value: EvoLine) { self.value = value }

    func line(baseSpeciesID: Int) async throws -> EvoLine {
        await withCheckedContinuation { continuation in
            precondition(self.continuation == nil, "only one line request may be suspended")
            self.continuation = continuation
            suspended = true
        }
    }

    func baseSpeciesIndex() async throws -> [BaseSpecies] {
        [BaseSpecies(id: value.baseID, captureRate: 255)]
    }

    func isSuspended() -> Bool { suspended }

    func resume() {
        let pending = continuation
        continuation = nil
        suspended = false
        pending?.resume(returning: value)
    }
}

// 테스트 스텁 공통 — base 판정을 주입 인덱스에서 파생. REST 폴백 경로는 실클라이언트만 override.
extension PokeProviding {
    func baseSpecies(id: Int) async throws -> BaseSpecies? {
        try await baseSpeciesIndex().first { $0.id == id }
    }
}

private enum PokeStubError: Error { case boom }

/// GraphQL base 인덱스 장애 시뮬 — baseSpeciesIndex 는 throw(엔드포인트 다운), REST 폴백(baseSpecies)은 성공.
private struct FallbackOnlyProvider: PokeProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine { makeLine(base: baseSpeciesID, tree: node(baseSpeciesID)) }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { throw PokeStubError.boom }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { BaseSpecies(id: id, captureRate: 100) }
}

/// line() 호출 횟수를 센다 — 이미 저장된 항목에 불필요한 조회가 붙는지 검증용.
private final class CountingLineProvider: PokeProviding, @unchecked Sendable {
    let value: EvoLine
    nonisolated(unsafe) private(set) var lineCalls = 0
    init(value: EvoLine) { self.value = value }
    func line(baseSpeciesID: Int) async throws -> EvoLine { lineCalls += 1; return value }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [BaseSpecies(id: value.baseID, captureRate: 255)] }
}

/// line() 자체가 실패(오프라인) — 도감 이름 조회 폴백 검증용.
private struct LineThrowsProvider: PokeProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine { throw PokeStubError.boom }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
}

/// 샘플러 테스트용 — 주입한 base 인덱스 + 요청 id 그대로의 무진화 라인 반환.
final class IndexProvider: PokeProviding, @unchecked Sendable {
    nonisolated(unsafe) var index: [BaseSpecies] = []
    nonisolated(unsafe) var failAll = false
    func line(baseSpeciesID: Int) async throws -> EvoLine {
        makeLine(base: baseSpeciesID, tree: node(baseSpeciesID))
    }
    func baseSpeciesIndex() async throws -> [BaseSpecies] {
        if failAll { throw PokeStubError.boom }
        return index
    }
}

private func allIDs(_ n: EvoNode) -> [Int] { [n.speciesID] + n.children.flatMap(allIDs) }
private func makeLine(base: Int, tree: EvoNode, rarity: Rarity = .common) -> EvoLine {
    var names: [Int: [String: String]] = [:]
    for id in allIDs(tree) { names[id] = ["en": "P\(id)", "ko": "포\(id)", "ja": "ポ\(id)"] }
    return EvoLine(baseID: base, tree: tree, rarity: rarity, names: names)
}
private func node(_ id: Int, _ children: [EvoNode] = []) -> EvoNode { EvoNode(speciesID: id, children: children) }
// 3단 선형: 1→2→3
private let linear3 = makeLine(base: 1, tree: node(1, [node(2, [node(3)])]))
// 분기: 10 → {11,12,13}
private let branch3 = makeLine(base: 10, tree: node(10, [node(11), node(12), node(13)]))
// Wurmple: 265 → {266 → 267, 268 → 269}
private let wurmpleLine = makeLine(base: 265, tree: node(265, [node(266, [node(267)]), node(268, [node(269)])]))
// Oddish: 43 → 44 → {45, 182}
private let delayedBranchLine = makeLine(base: 43, tree: node(43, [node(44, [node(45), node(182)])]))
// 무진화: 20
private let noEvo = makeLine(base: 20, tree: node(20))
// 돌 진화: 30 → 31. `useEvolutionItem` 은 레벨을 보지 않으므로 레벨 관문이 없는 유일한 경로다.
private let stoneLine = makeLine(base: 30, tree: node(30, [
    EvoNode(speciesID: 31, children: [], evolutionTrigger: "use-item", evolutionItem: "fire-stone"),
]))
private let fixedNow = Date(timeIntervalSince1970: 1_700_000_000)

// MARK: 스토어

@MainActor
final class CompanionStoreTests: XCTestCase {
    private func store(_ line: EvoLine, seed: UInt64 = 7) -> CompanionStore {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("poke-\(UUID().uuidString).json")
        return CompanionStore(provider: StubProvider(value: line), clock: { fixedNow }, fileURL: url, rng: SeededRNG(seed: seed))
    }

    // MARK: 상태 파일 decode 복원력 (회귀)

    /// [회귀] 도감 항목 하나가 손상돼도(구버전/필드 누락) 나머지 도감·companion·인벤토리를 지킨다 —
    /// 예전엔 `[DexEntry]` 배열 전체 decode 가 throw 돼 상태가 전면 초기화됐다(항목별 격리로 수정).
    func testCorruptDexEntryDroppedWhileRestSurvives() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("poke-dex-\(UUID().uuidString).json")
        // 유효 2개 + 손상 1개(finalID/chainOrder 누락).
        let json = #"{"economyVersion":2,"forcedResetVersion":1,"dex":[{"baseID":1,"finalID":3,"chainOrder":[1,2,3],"rarity":"common"},"#
            + #"{"baseID":99,"rarity":"rare"},"#
            + #"{"baseID":7,"finalID":9,"chainOrder":[7,8,9],"rarity":"uncommon"}],"inventory":{"rareCandy":2}}"#
        try Data(json.utf8).write(to: url)

        let s = CompanionStore(provider: StubProvider(value: linear3), clock: { fixedNow },
                               fileURL: url, rng: SeededRNG(seed: 7))

        XCTAssertEqual(s.state.dex.count, 2, "손상 항목만 드롭, 유효 2개 유지")
        XCTAssertEqual(Set(s.state.dex.map(\.baseID)), [1, 7])
        XCTAssertEqual(s.state.inventory["rareCandy"], 2, "도감 손상이 다른 상태(인벤토리)를 날리지 않음")
    }

    /// [회귀] 전면 손상 상태 파일은 fresh 로 시작하되, 다음 save() 가 덮어써 영구 유실되기 전에
    /// 원본을 `.corrupt` 로 백업해 수동 복구 여지를 남긴다.
    func testCorruptStateFileBackedUpBeforeReset() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("poke-corrupt-\(UUID().uuidString).json")
        let garbage = "this is not valid json {{{ 손상"
        try Data(garbage.utf8).write(to: url)

        let s = CompanionStore(provider: StubProvider(value: linear3), clock: { fixedNow },
                               fileURL: url, rng: SeededRNG(seed: 7))

        XCTAssertTrue(s.state.dex.isEmpty)
        XCTAssertNil(s.state.active)
        XCTAssertEqual(s.state.usedSinceInstall, 0, "fresh state 로 시작")

        let backup = url.appendingPathExtension("corrupt")
        XCTAssertTrue(FileManager.default.fileExists(atPath: backup.path), "손상 원본이 .corrupt 로 백업돼야 한다")
        XCTAssertEqual(try String(contentsOf: backup, encoding: .utf8), garbage, "백업 내용 = 원본 그대로")
        // 핵심 보장은 손상 원본이 그대로 백업되는 것이다. fresh state 가 이후 저장되면 같은 원래
        // 경로에 정상 JSON 이 다시 생길 수 있으므로, 원래 경로의 부재까지 요구하면 실행 순서에 따라
        // 복구가 성공했는데도 실패하는 테스트가 된다.
        try? FileManager.default.removeItem(at: backup)
        try? FileManager.default.removeItem(at: url)
    }

    /// [회귀] active(현재 포켓몬)가 손상돼도(pathIDs 누락 등) 알로 폴백하되 도감·인벤토리·누적은 보존한다 —
    /// 예전엔 active decode 실패가 CompanionState 전체를 throw 시켜 전면 초기화됐다(필드별 관대화로 수정).
    func testCorruptActiveFallsBackToEggWhileRestSurvives() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("poke-active-corrupt-\(UUID().uuidString).json")
        // active 는 pathIDs 누락 → MonState decode 실패. dex/inventory/usedSinceInstall 은 유효.
        let json = #"{"economyVersion":2,"forcedResetVersion":1,"active":{"baseID":1},"#
            + #""dex":[{"baseID":1,"finalID":3,"chainOrder":[1,2,3],"rarity":"common"}],"#
            + #""inventory":{"rareCandy":3},"usedSinceInstall":5000}"#
        try Data(json.utf8).write(to: url)

        let s = CompanionStore(provider: StubProvider(value: linear3), clock: { fixedNow },
                               fileURL: url, rng: SeededRNG(seed: 7))

        XCTAssertNil(s.state.active, "손상 active 는 nil(알)로 폴백")
        XCTAssertEqual(s.state.dex.count, 1, "도감 보존")
        XCTAssertEqual(s.state.inventory["rareCandy"], 3, "인벤토리 보존")
        XCTAssertEqual(s.state.usedSinceInstall, 5000, "누적 토큰 보존")
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.appendingPathExtension("corrupt").path),
                       "부분 복원 — 전면 리셋/백업 아님")
    }

    // MARK: 도감 이름 (컬렉션 표시)

    /// 저장된 체인 종별 다국어 이름을 현재 언어로 해석 — 없으면 nil(뷰가 async 조회로 폴백).
    func testDexStoredChainNamesResolvePerLanguage() {
        let s = store(linear3)
        let named = DexEntry(baseID: 1, finalID: 3, chainOrder: [1, 2, 3], rarity: .common, caughtAt: nil,
                             names: [1: ["ko": "포1", "en": "P1"], 2: ["ko": "포2", "en": "P2"], 3: ["ko": "포3", "en": "P3"]])
        s.setLanguage(.ko); XCTAssertEqual(s.dexStoredChainNames(named), [1: "포1", 2: "포2", 3: "포3"])
        s.setLanguage(.en); XCTAssertEqual(s.dexStoredChainNames(named), [1: "P1", 2: "P2", 3: "P3"])
        // 저장 이름 없음 → nil
        XCTAssertNil(s.dexStoredChainNames(DexEntry(baseID: 1, finalID: 3, chainOrder: [1, 2, 3],
                                                    rarity: .common, caughtAt: nil)))
    }

    /// 이름 미저장(구버전) 항목은 line 조회로 체인 전 종의 이름을 얻는다(chainOrder 전부 채움).
    func testDexResolveChainNamesFetchesWhenUnstored() async {
        let s = store(linear3)   // line 이름: 포1/포2/포3
        s.setLanguage(.ko)
        let bare = DexEntry(baseID: 1, finalID: 3, chainOrder: [1, 2, 3], rarity: .common, caughtAt: nil)
        let names = await s.dexResolveChainNames(bare)
        XCTAssertEqual(names, [1: "포1", 2: "포2", 3: "포3"])
    }

    /// 졸업 시 체인 각 종의 다국어 이름이 도감 항목에 저장된다 → 단계별 표시가 네트워크 없이 즉시.
    func testGraduationStoresChainNames() async {
        let s = store(linear3)
        await s.hatch(baseID: 1)
        s.applyUsage(PokemonBalance.phaseThreshold(rarity: .common, totalForms: 3, stageIndex: 0))  // →2
        s.applyUsage(PokemonBalance.phaseThreshold(rarity: .common, totalForms: 3, stageIndex: 1))  // →3(최종)
        XCTAssertTrue(s.graduateCompanion(), "졸업은 이제 사용자가 직접 누른다(#19)")
        XCTAssertEqual(s.state.dex.count, 1)
        XCTAssertEqual(s.state.dex.first?.chainOrder, [1, 2, 3])
        XCTAssertEqual(s.state.dex.first?.names?[1]?["ko"], "포1")   // 초기 단계도 저장
        XCTAssertEqual(s.state.dex.first?.names?[3]?["ja"], "ポ3")   // 최종 단계도 저장
        s.setLanguage(.ko)
        XCTAssertEqual(s.state.dex.first.map { s.dexStoredChainNames($0) }, [1: "포1", 2: "포2", 3: "포3"])
    }

    /// 백필(트리거 브랜치): 이름 미저장(구버전) 항목을 조회하면 line 에서 체인 이름을 얻어 **항목에 저장**
    /// 한다. 구버전 저장 JSON(“names” 키 없음)을 로드해 실제 마이그레이션 경로를 재현한다.
    func testDexResolveChainNamesBackfillsLegacyEntry() async {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("poke-\(UUID().uuidString).json")
        let json = #"{"economyVersion":2,"forcedResetVersion":1,"dex":[{"id":"e1","baseID":1,"finalID":3,"chainOrder":[1,2,3],"rarity":"common"}]}"#
        try? json.data(using: .utf8)!.write(to: url)
        let s = CompanionStore(provider: StubProvider(value: linear3), clock: { fixedNow },
                               fileURL: url, rng: SeededRNG(seed: 7))
        s.setLanguage(.ko)
        XCTAssertEqual(s.state.dex.count, 1)                        // 구버전 JSON 로드 성공
        XCTAssertNil(s.state.dex.first?.names)                      // 이름 없음(구버전)
        let names = await s.dexResolveChainNames(s.state.dex[0])
        XCTAssertEqual(names, [1: "포1", 2: "포2", 3: "포3"])       // fetch 로 체인 전부
        XCTAssertEqual(s.state.dex.first?.names?[2]?["ko"], "포2")  // 항목에 백필 저장됨(트리거 브랜치)
    }

    // MARK: 도감 (종 단위 집계 — 로그의 개체 단위와 축이 다르다)

    /// 같은 라인을 두 번 졸업해도 종은 한 칸으로 접힌다 — 로그가 2행인 게 정상이고, 중복은 도감
    /// 쪽에서 구조적으로 사라진다. 도감은 종 정보만 담으므로 성격·획득 횟수는 여기서 보지 않는다.
    func testDexSpeciesFoldsDuplicateLinesToOneCellPerSpecies() throws {
        let entries = [
            DexEntry(baseID: 1, finalID: 3, chainOrder: [1, 2, 3], rarity: .common, caughtAt: fixedNow,
                     nature: .rash,
                     names: [1: ["ko": "포1"], 2: ["ko": "포2"], 3: ["ko": "포3"]]),
            DexEntry(baseID: 1, finalID: 3, chainOrder: [1, 2, 3], rarity: .common, caughtAt: fixedNow,
                     nature: .lax),
        ]
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("poke-\(UUID().uuidString).json")
        let dexJSON = String(decoding: try JSONEncoder().encode(entries), as: UTF8.self)
        try Data(#"{"economyVersion":2,"forcedResetVersion":1,"dex":\#(dexJSON),"language":"ko"}"#.utf8).write(to: url)

        let s = CompanionStore(provider: StubProvider(value: linear3), clock: { fixedNow },
                               fileURL: url, rng: SeededRNG(seed: 7))
        XCTAssertEqual(s.state.dex.count, 2, "로그(개체 단위)는 2건")

        let folded = s.dexSpecies
        XCTAssertEqual(folded.map(\.id), [1, 2, 3], "6칸이 아니라 종별 1칸, 도감 번호 오름차순")
        XCTAssertEqual(folded.map(\.name), ["포1", "포2", "포3"], "저장된 이름을 현재 언어로")
        XCTAssertEqual(folded.map(\.rarity), [.common, .common, .common])
    }

    /// 현재 개체는 **도달분**만 보유로 잡힌다. 졸업분을 비워 두면 누수가 종 목록에 그대로 드러난다 —
    /// pathIDs 전체를 쓰면 [1,2], plannedPathIDs(계획 경로)를 쓰면 [1,2,3] 이 되므로 한 상태로
    /// 두 오용을 동시에 가드한다.
    func testDexSpeciesCountsOnlyReachedStagesOfActive() throws {
        let active = MonState(baseID: 1, pathIDs: [1, 2], plannedPathIDs: [1, 2, 3], stageIndex: 0,
                              usedAtStage: 0, rarity: .common, totalForms: 3, nature: .brave)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("poke-\(UUID().uuidString).json")
        let json = String(decoding: try JSONEncoder().encode(active), as: UTF8.self)
        try Data(#"{"economyVersion":2,"forcedResetVersion":1,"active":\#(json),"language":"ko"}"#.utf8).write(to: url)

        let s = CompanionStore(provider: StubProvider(value: linear3), clock: { fixedNow },
                               fileURL: url, rng: SeededRNG(seed: 7))
        XCTAssertTrue(s.state.dex.isEmpty)
        XCTAssertEqual(s.state.active?.stageIndex, 0)
        XCTAssertEqual(s.dexSpecies.map(\.id), [1], "미도달 단계가 보유로 새지 않는다")
    }

    /// 이로치는 종 단위 플래그다 — 개체 하나가 이로치면 그 개체가 지나온 체인 전 종에 표식이 선다.
    /// 일반 개체와 이로치 개체를 둘 다 가진 종도 한 칸으로 접히되 플래그가 서고, 칸은 기본 일반색으로
    /// 그려 두었다가 선택하면 이로치색으로 바꾼다(두 모습을 다 볼 수 있게).
    func testDexSpeciesMarksShinyAcrossTheChain() throws {
        let entries = [
            DexEntry(baseID: 1, finalID: 2, chainOrder: [1, 2], rarity: .common, caughtAt: fixedNow,
                     isShiny: false),
            DexEntry(baseID: 1, finalID: 2, chainOrder: [1, 2], rarity: .common, caughtAt: fixedNow,
                     isShiny: true),
        ]
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("poke-\(UUID().uuidString).json")
        let dexJSON = String(decoding: try JSONEncoder().encode(entries), as: UTF8.self)
        try Data(#"{"economyVersion":2,"forcedResetVersion":1,"dex":\#(dexJSON),"language":"ko"}"#.utf8).write(to: url)
        let s = CompanionStore(provider: StubProvider(value: linear3), clock: { fixedNow },
                              fileURL: url, rng: SeededRNG(seed: 7))

        let folded = s.dexSpecies
        XCTAssertEqual(folded.map(\.id), [1, 2], "이로치 개체가 지나온 체인 전 종")
        XCTAssertEqual(folded.map(\.isShiny), [true, true], "한 개체라도 이로치면 종에 플래그")
    }

    /// 위장 메타몽은 리빌 전까지 이로치를 숨긴다 — 도감도 그 규칙을 따라야 한다
    /// (currentIsShiny 를 재사용하는 지점. 직접 isShiny 를 읽으면 정체가 미리 새어 나간다).
    func testDexSpeciesHidesShinyWhileDittoIsDisguised() throws {
        func store(revealed: Bool) throws -> CompanionStore {
            let active = MonState(baseID: 1, pathIDs: [1], stageIndex: 0, usedAtStage: 0,
                                  rarity: .common, totalForms: 3, isShiny: true,
                                  dittoDisguise: 1, dittoRevealed: revealed)
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("poke-\(UUID().uuidString).json")
            let json = String(decoding: try JSONEncoder().encode(active), as: UTF8.self)
            try Data(#"{"economyVersion":2,"forcedResetVersion":1,"active":\#(json),"language":"ko"}"#.utf8).write(to: url)
            return CompanionStore(provider: StubProvider(value: linear3), clock: { fixedNow },
                                  fileURL: url, rng: SeededRNG(seed: 7))
        }
        let disguised = try store(revealed: false)
        XCTAssertTrue(disguised.state.active?.isShiny ?? false, "내부적으론 이로치")
        XCTAssertEqual(disguised.dexSpecies.first?.isShiny, false, "위장 중엔 도감에도 숨김")

        let revealed = try store(revealed: true)
        XCTAssertEqual(revealed.dexSpecies.first?.isShiny, true, "리빌 후엔 도감에 공개")
    }

    /// 지금 키우는 종의 이름은 **로드된 라인**에서 온다 — 졸업분이 아직 없어도 `#id` 로 떨어지지 않는다.
    /// (부화 직후가 이 경로다. 파일 주입 테스트는 currentLine 이 nil 이라 이 분기를 밟지 못한다.)
    func testDexSpeciesNamesActiveSpeciesFromLoadedLine() async {
        let s = store(linear3)
        s.setLanguage(.ko)
        await s.hatch(baseID: 1)
        let sp = s.dexSpecies
        XCTAssertEqual(sp.map(\.id), [1], "도달분만 — 아직 진화 전이라 2·3 은 미보유")
        XCTAssertEqual(sp.first?.name, "포1")
    }

    // MARK: 도감 이름 백필 (격자는 저장분만 읽는다)

    /// 이름이 저장되기 전 버전의 졸업분은 격자에서 `#id` 로 뜬다 — 격자 진입 시 백필이 이를 채운다.
    /// 백필 전/후를 한 테스트에서 함께 본다: 백필 호출을 지우면 첫 단언에서 멈추므로 가드가 살아 있다.
    func testBackfillFillsNamesForEntriesSavedBeforeNamesExisted() async throws {
        let s = try storeWithNamelessEntry()
        XCTAssertNil(s.state.dex.first?.names, "구버전 저장분엔 이름이 없다")
        XCTAssertEqual(s.dexSpecies.map(\.name), ["#1", "#2", "#3"], "백필 전엔 종 번호")

        await s.backfillMissingDexNames()

        XCTAssertEqual(s.dexSpecies.map(\.name), ["포1", "포2", "포3"])
        XCTAssertNotNil(s.state.dex.first?.names, "항목에 저장돼 다음 실행부터 네트워크 0")
    }

    /// 이미 이름이 저장된 항목은 조회하지 않는다 — 격자를 열 때마다 도감 전체를 다시 받아오면 안 된다.
    func testBackfillDoesNotFetchWhenNamesAreAlreadyStored() async throws {
        let entry = DexEntry(baseID: 1, finalID: 3, chainOrder: [1, 2, 3], rarity: .common, caughtAt: fixedNow,
                             names: [1: ["ko": "포1"], 2: ["ko": "포2"], 3: ["ko": "포3"]])
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("poke-\(UUID().uuidString).json")
        let dexJSON = String(decoding: try JSONEncoder().encode([entry]), as: UTF8.self)
        try Data(#"{"economyVersion":2,"forcedResetVersion":1,"dex":\#(dexJSON),"language":"ko"}"#.utf8).write(to: url)
        let provider = CountingLineProvider(value: linear3)
        let s = CompanionStore(provider: provider, clock: { fixedNow }, fileURL: url, rng: SeededRNG(seed: 7))

        await s.backfillMissingDexNames()

        XCTAssertEqual(provider.lineCalls, 0, "저장분은 건너뛴다")
        XCTAssertEqual(s.dexSpecies.map(\.name), ["포1", "포2", "포3"])
    }

    /// 오프라인이면 폴백(`#id`)을 **저장하지 않는다** — 저장해 버리면 이름이 영원히 번호로 굳는다.
    /// 다음 진입(온라인)에서 다시 시도해 채워지는 것까지 확인한다.
    func testBackfillRetriesAfterAnOfflineAttempt() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("poke-\(UUID().uuidString).json")
        let bare = DexEntry(baseID: 1, finalID: 3, chainOrder: [1, 2, 3], rarity: .common, caughtAt: fixedNow)
        let dexJSON = String(decoding: try JSONEncoder().encode([bare]), as: UTF8.self)
        try Data(#"{"economyVersion":2,"forcedResetVersion":1,"dex":\#(dexJSON),"language":"ko"}"#.utf8).write(to: url)

        let offline = CompanionStore(provider: LineThrowsProvider(), clock: { fixedNow },
                                     fileURL: url, rng: SeededRNG(seed: 7))
        await offline.backfillMissingDexNames()
        XCTAssertNil(offline.state.dex.first?.names, "폴백은 저장하지 않는다")
        XCTAssertEqual(offline.dexSpecies.map(\.name), ["#1", "#2", "#3"])

        // 같은 저장 파일을 온라인 provider 로 다시 연다(= 다음 진입).
        let online = CompanionStore(provider: StubProvider(value: linear3), clock: { fixedNow },
                                    fileURL: url, rng: SeededRNG(seed: 7))
        await online.backfillMissingDexNames()
        XCTAssertEqual(online.dexSpecies.map(\.name), ["포1", "포2", "포3"])
    }

    // MARK: 도감 "키우는 중" 표식 (아직 확정이 아닌 칸)

    /// 졸업 기록이 없는 종은 현재 개체가 사라지면 함께 사라진다 — **도달 단계 전부**에 표식이 선다.
    /// (진화 3단까지 왔으면 3칸 모두. 알을 새로 사면 실제로 3칸이 다 빠진다.)
    func testDexSpeciesMarksEveryUnsecuredStageAsRaising() async {
        let s = store(linear3)
        s.setLanguage(.ko)
        await s.hatch(baseID: 1)
        s.applyUsage(PokemonBalance.phaseThreshold(rarity: .common, totalForms: 3, stageIndex: 0))
        XCTAssertEqual(s.state.active?.stageIndex, 1, "2단계까지 진화")

        let sp = s.dexSpecies
        XCTAssertEqual(sp.map(\.id), [1, 2])
        XCTAssertEqual(sp.map(\.isRaising), [true, true], "졸업 기록이 없으니 둘 다 미확정")
    }

    /// 트리거 브랜치 — 같은 라인을 졸업한 뒤 **다시 키우는 중**. 종은 이미 영구 보존분이라 사라지지 않으므로
    /// 표식이 서면 안 된다. "현재 개체에 속하면 표식"으로 판정하면 여기서 깨진다.
    func testAlreadyGraduatedSpeciesIsNotMarkedWhileRaisedAgain() throws {
        let graduated = DexEntry(baseID: 1, finalID: 3, chainOrder: [1, 2, 3], rarity: .common, caughtAt: fixedNow,
                                 names: [1: ["ko": "포1"], 2: ["ko": "포2"], 3: ["ko": "포3"]])
        let active = MonState(baseID: 1, pathIDs: [1, 2, 3], stageIndex: 1,
                              usedAtStage: 0, rarity: .common, totalForms: 3, nature: .brave)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("poke-\(UUID().uuidString).json")
        let dexJSON = String(decoding: try JSONEncoder().encode([graduated]), as: UTF8.self)
        let activeJSON = String(decoding: try JSONEncoder().encode(active), as: UTF8.self)
        try Data(#"{"economyVersion":2,"forcedResetVersion":1,"dex":\#(dexJSON),"active":\#(activeJSON),"language":"ko"}"#.utf8).write(to: url)

        let s = CompanionStore(provider: StubProvider(value: linear3), clock: { fixedNow },
                               fileURL: url, rng: SeededRNG(seed: 7))
        XCTAssertEqual(s.dexSpecies.map(\.isRaising), [false, false, false],
                       "졸업분이 있는 종은 현재 키우는 중이어도 확정분")
    }

    /// 졸업분만 있고 현재 개체가 없으면 표식은 하나도 없다(모두 영구 기록).
    func testGraduatedOnlyDexHasNoRaisingMark() throws {
        let s = try storeWithNamelessEntry()
        XCTAssertNil(s.state.active)
        XCTAssertEqual(s.dexSpecies.map(\.isRaising), [false, false, false])
    }

    /// 이름 없는 구버전 졸업분 1건(체인 1→2→3)만 담긴 store — 백필/표식 테스트 공용.
    private func storeWithNamelessEntry() throws -> CompanionStore {
        let bare = DexEntry(baseID: 1, finalID: 3, chainOrder: [1, 2, 3], rarity: .common, caughtAt: fixedNow)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("poke-\(UUID().uuidString).json")
        let dexJSON = String(decoding: try JSONEncoder().encode([bare]), as: UTF8.self)
        try Data(#"{"economyVersion":2,"forcedResetVersion":1,"dex":\#(dexJSON),"language":"ko"}"#.utf8).write(to: url)
        return CompanionStore(provider: StubProvider(value: linear3), clock: { fixedNow },
                              fileURL: url, rng: SeededRNG(seed: 7))
    }

    /// 오프라인(line fetch 실패) + 저장 없음 → chainOrder 전 종을 종 번호(#id)로 폴백.
    func testDexResolveChainNamesOfflineFallback() async {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("poke-\(UUID().uuidString).json")
        let s = CompanionStore(provider: LineThrowsProvider(), clock: { fixedNow },
                               fileURL: url, rng: SeededRNG(seed: 7))
        let bare = DexEntry(baseID: 1, finalID: 3, chainOrder: [1, 2, 3], rarity: .common, caughtAt: nil)
        let names = await s.dexResolveChainNames(bare)
        XCTAssertEqual(names, [1: "#1", 2: "#2", 3: "#3"])
    }

    // 방치형 경제 전환(2026-08-13): 성장은 update() 가 아니라 tick/accrue 경로로 주입된다.
    // base 는 더 이상 baseline 개념이 없어 no-op, use 는 델타 생산분을 직접 적립한다.
    private func base(_ s: CompanionStore) { }
    private func use(_ s: CompanionStore, _ amount: Int, hasUsageData: Bool = true) {
        s.debugAccrue(amount)
    }

    func testEggDoesNotHatchBelowThreshold() async {
        let s = store(linear3)
        base(s)
        use(s, 500_000)   // < 1M
        XCTAssertEqual(s.state.eggUsage, 500_000)
        XCTAssertTrue(s.isEgg)
        await s.hatchIfNeeded()
        XCTAssertNil(s.state.active)   // 임계 미만 → 미부화
    }

    func testEggHatchesAtThreshold() async {
        let s = store(linear3)
        base(s)
        use(s, PokemonBalance.eggHatchThreshold)   // = 1M
        XCTAssertEqual(s.state.eggUsage, PokemonBalance.eggHatchThreshold)
        await s.hatchIfNeeded()
        XCTAssertNotNil(s.state.active)
        XCTAssertEqual(s.state.eggUsage, 0)
    }

    /// [회귀] 부화한 현재 포켓몬은 졸업 전에도 도감에 보여야 한다. 영구 dex 에 미리 저장하지 않고
    /// 화면용 엔트리로 합쳐, 진화 경로는 즉시 갱신되고 졸업 시 중복이 생기지 않는다.
    func testActiveCompanionAppearsInDexBeforeGraduationWithoutDuplicate() async {
        let s = store(linear3)
        await s.hatch(baseID: 1)

        XCTAssertTrue(s.state.dex.isEmpty, "졸업 전 영구 dex 는 비어 있어야 함")
        XCTAssertEqual(s.dexEntries.count, 1, "현재 포켓몬도 도감 화면에는 즉시 보여야 함")
        XCTAssertEqual(s.dexEntries[0].chainOrder, [1])
        XCTAssertEqual(s.dexEntries[0].finalID, 1)

        s.applyUsage(PokemonBalance.phaseThreshold(rarity: .common, totalForms: 3, stageIndex: 0))
        XCTAssertEqual(s.dexEntries.count, 1)
        XCTAssertEqual(s.dexEntries[0].chainOrder, [1, 2], "진화한 현재 경로가 도감에 반영돼야 함")
        XCTAssertEqual(s.dexEntries[0].finalID, 2)

        s.applyUsage(PokemonBalance.phaseThreshold(rarity: .common, totalForms: 3, stageIndex: 1))
        XCTAssertTrue(s.graduateCompanion(), "졸업은 이제 사용자가 직접 누른다(#19)")
        XCTAssertNil(s.state.active)
        XCTAssertEqual(s.state.dex.count, 1, "졸업 시 영구 엔트리 하나만 저장")
        XCTAssertEqual(s.dexEntries.count, 1, "화면용 active 가 영구 엔트리와 중복되면 안 됨")
        XCTAssertEqual(s.dexEntries[0].chainOrder, [1, 2, 3])
    }

    /// 사용자 리포트와 같은 재시작 상태: active 는 저장돼 있지만 dex=[] 인 기존 상태 파일도
    /// 도감 빈 화면으로 떨어지지 않는다.
    func testLoadedActiveCompanionPreventsEmptyDexState() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("poke-active-\(UUID().uuidString).json")
        let json = #"{"economyVersion":2,"forcedResetVersion":1,"active":{"baseID":529,"pathIDs":[529],"stageIndex":0,"usedAtStage":148344233,"rarity":"uncommon","totalForms":2,"isShiny":false,"nature":"timid"},"dex":[]}"#
        try json.data(using: .utf8)!.write(to: url)

        let s = CompanionStore(provider: StubProvider(value: linear3), clock: { fixedNow },
                               fileURL: url, rng: SeededRNG(seed: 7))
        XCTAssertTrue(s.state.dex.isEmpty)
        XCTAssertEqual(s.dexEntries.count, 1)
        XCTAssertEqual(s.dexEntries[0].baseID, 529)
        XCTAssertEqual(s.dexCount(.uncommon), 1)
    }

    /// [회귀] 현재 키우는 common 포켓몬은 더 희귀한 졸업 항목보다도 위에 고정된다.
    /// caughtAt 이 없는 구버전 졸업 항목은 active 로 오인하지 않는다.
    func testActiveCompanionPinnedBeforeGraduatedEntries() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("poke-active-sort-\(UUID().uuidString).json")
        let json = #"{"economyVersion":2,"forcedResetVersion":1,"active":{"baseID":1,"pathIDs":[1],"stageIndex":0,"usedAtStage":5,"rarity":"common","totalForms":3},"dex":[{"id":"legacy-graduated","baseID":150,"finalID":150,"chainOrder":[150],"rarity":"legendary"}]}"#
        try json.data(using: .utf8)!.write(to: url)

        let s = CompanionStore(provider: StubProvider(value: linear3), clock: { fixedNow },
                               fileURL: url, rng: SeededRNG(seed: 7))
        let sorted = s.dexEntriesSorted

        XCTAssertEqual(sorted.map(\.id), ["active-1-1", "legacy-graduated"])
        XCTAssertTrue(s.isActiveDexEntry(sorted[0]))
        XCTAssertFalse(s.isActiveDexEntry(sorted[1]), "caughtAt=nil 만으로 active 를 판별하면 안 됨")
    }

    func testDexRaisingLabelLocalized() {
        XCTAssertEqual(L(.en).dexRaising, "Raising")
        XCTAssertEqual(L(.ko).dexRaising, "키우는 중")
        XCTAssertEqual(L(.ja).dexRaising, "育成中")
    }

    func testUnknownNextEvolutionAccessibilityLabelLocalized() {
        XCTAssertEqual(L(.ko).unknownNextEvolution, "알 수 없는 다음 진화")
        XCTAssertEqual(L(.en).unknownNextEvolution, "Unknown next evolution")
        XCTAssertEqual(L(.ja).unknownNextEvolution, "次の進化先は不明")
    }

    func testEggOverflowCarriesToHatchedMon() async {
        let s = store(linear3)
        base(s)
        use(s, PokemonBalance.eggHatchThreshold + 500_000)   // 임계 초과 0.5M
        await s.hatchIfNeeded()
        XCTAssertEqual(s.state.active?.usedAtStage, 500_000)   // 초과분 이월
    }

    /// GraphQL base 인덱스 엔드포인트가 죽어도 REST 폴백으로 부화한다 (2026-07 실장애 회귀 방지).
    func testEggHatchesViaRESTFallbackWhenIndexDown() async {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("poke-\(UUID().uuidString).json")
        let s = CompanionStore(provider: FallbackOnlyProvider(),
                               clock: { fixedNow }, fileURL: url, rng: SeededRNG(seed: 7))
        base(s)
        use(s, PokemonBalance.eggHatchThreshold)
        await s.hatchIfNeeded()
        XCTAssertNotNil(s.state.active, "인덱스 장애 시 REST 폴백으로 부화해야 함")
        XCTAssertEqual(s.state.eggUsage, 0)
    }

    func testNewEggAfterGraduationReincubates() async {
        let s = store(noEvo)
        base(s)
        use(s, PokemonBalance.eggHatchThreshold)
        await s.hatchIfNeeded()
        XCTAssertNotNil(s.state.active)
        s.debugAccrueLevelExperience(300_000_000)   // 무진화 종은 레벨 30 게이트(#19)
        XCTAssertTrue(s.graduateCompanion())
        XCTAssertNil(s.state.active)
        XCTAssertEqual(s.state.eggUsage, 0)                     // 새 알 인큐베이션 리셋
        await s.hatchIfNeeded()                                 // eggUsage=0 → 즉시 부화 안 함
        XCTAssertNil(s.state.active)
    }

    func testStateDecodesWithoutEggUsage() throws {
        // 기존 저장(필드 없음)도 깨지지 않고 eggUsage=0 으로 로드
        let json = #"{"installBaselineSet":true,"usedSinceInstall":5,"claimedTodayTokens":5,"lastDate":"d","active":null,"dex":[],"collectedFinals":[],"language":"ko"}"#
        let state = try JSONDecoder().decode(CompanionState.self, from: Data(json.utf8))
        XCTAssertEqual(state.eggUsage, 0)
        XCTAssertEqual(state.usedSinceInstall, 5)
    }

    func testEvolvesThroughLineAndGraduatesWithFullChain() async {
        let s = store(linear3)
        s.setLanguage(.ko)   // 로케일 무관하게 한국어 표시명("포3") 검증 (CI 는 영어 로케일)
        await s.hatch(baseID: 1)
        XCTAssertEqual(s.currentSpeciesID, 1)
        XCTAssertEqual(s.state.active?.totalForms, 3)
        s.applyUsage(PokemonBalance.phaseThreshold(rarity: .common, totalForms: 3, stageIndex: 0)) // →2
        XCTAssertEqual(s.currentSpeciesID, 2)
        s.applyUsage(PokemonBalance.phaseThreshold(rarity: .common, totalForms: 3, stageIndex: 1)) // →3 (final)
        XCTAssertEqual(s.currentSpeciesID, 3)
        XCTAssertTrue(s.isFinalStage)
        XCTAssertTrue(s.graduateCompanion(), "졸업은 이제 사용자가 직접 누른다(#19)")
        XCTAssertNil(s.state.active)
        XCTAssertEqual(s.dexEntries.count, 1)
        XCTAssertEqual(s.dexEntries[0].chainOrder, [1, 2, 3])   // 라인 전체 보존
        XCTAssertEqual(s.justGraduated, "포3")
    }

    func testNoEvolutionGraduatesAtSingleThreshold() async {
        let s = store(noEvo)
        await s.hatch(baseID: 20)
        XCTAssertTrue(s.isFinalStage)
        s.debugAccrueLevelExperience(300_000_000)   // 무진화 종은 레벨 30 게이트(#19)
        XCTAssertTrue(s.graduateCompanion())
        XCTAssertEqual(s.dexEntries.count, 1)
        XCTAssertEqual(s.dexEntries[0].chainOrder, [20])
    }

    /// 졸업은 자동으로 일어나지 않는다(#19) — 최종형에 도달해도 사용자가 누르기 전엔 그대로 남는다.
    /// 예전엔 진화 수락 직후 자동 졸업이라, 방금 진화시킨 최종형을 한 순간도 못 데리고 있었다.
    func testReachingFinalFormDoesNotGraduateOnItsOwn() async {
        let s = store(linear3)
        await s.hatch(baseID: 1)
        s.applyUsage(PokemonBalance.phaseThreshold(rarity: .common, totalForms: 3, stageIndex: 0))
        s.applyUsage(PokemonBalance.phaseThreshold(rarity: .common, totalForms: 3, stageIndex: 1))
        XCTAssertEqual(s.currentSpeciesID, 3, "최종형에 도달했지만")
        XCTAssertNotNil(s.state.active, "사용자가 누르기 전엔 졸업하지 않는다")
        XCTAssertTrue(s.state.dex.isEmpty)
        XCTAssertTrue(s.canGraduate, "이제 졸업 버튼이 뜬다")
    }

    /// 돌 진화 종은 `nextEvolutionLevel` 이 nil 이라 파트너 카드의 "Lv.N 에 진화" 자리가 비어 있었다 —
    /// 화면이 아무 말도 안 하니 레벨만 올리며 오지 않을 진화를 기다리게 된다. 이제 필요한 돌을 말한다.
    func testStoneEvolvingCompanionNamesTheItemItNeeds() async {
        let s = store(stoneLine)
        await s.hatch(baseID: 30)

        XCTAssertNil(s.nextEvolutionLevel, "레벨로는 진화하지 않는 종이라 이 자리가 비어 있었다")
        XCTAssertEqual(s.nextEvolutionItem, .fireStone)
        // 언어는 신규 설치 기본값이 `.systemDefault` 라 CI 로케일에 딸려간다 — `store.l` 로 재면
        // 로컬(한국어)만 통과하고 CI(영어)에서 깨진다. 문구는 언어를 고정해 잰다.
        XCTAssertEqual(L(.ko).evolutionNeedsItem(L(.ko).itemName(.fireStone)), "불꽃의돌 필요")
        XCTAssertEqual(L(.en).evolutionNeedsItem(L(.en).itemName(.fireStone)), "Needs Fire Stone")
    }

    /// 대조군: 레벨 진화 종에는 아이템 안내가 붙지 않는다 — 두 안내가 같이 뜨면 어느 쪽을 따라야
    /// 하는지 알 수 없다. 이게 없으면 "항상 첫 자식의 아이템을 보여준다" 로 잘못 짜도 위 테스트는 통과한다.
    func testLevelEvolvingCompanionNeedsNoItem() async {
        let s = store(linear3)
        await s.hatch(baseID: 1)

        XCTAssertNil(s.nextEvolutionItem, "레벨로 진화하는 종이다")
    }

    // MARK: 알 등급 보증

    /// 상점은 보증 알을 팔지 않는다(`shopTiers` 가 `[nil]`). `canBuyEgg` 가 그걸 강제하므로
    /// 구매로는 보증을 만들 수 없다 — 만족 불가능한 보증을 사면 알이 영영 안 깨지기 때문이다.
    /// 보증을 세우는 경로가 생기면 이 전제부터 다시 본다.
    func testGuaranteedEggsAreNotPurchasable() {
        let s = store(noEvo)
        XCTAssertFalse(s.canBuyEgg(.rare), "팔지 않는 등급은 값이 계산돼도 구매를 막는다")
        XCTAssertFalse(s.canBuyEgg(.legendary), "capture_rate 로 표현 못 하는 등급은 특히")
    }

    /// 보증은 상태에 하나뿐이라 덮어쓰기 규칙이 필요하다 — 낮은 쪽으로 덮이면 이미 얻은 게 깎인다.
    func testGuaranteeKeepsTheStrongerOfTwo() {
        XCTAssertEqual(CompanionStore.strongerGuarantee(.rare, .uncommon), .rare, "낮은 쪽으로 깎이지 않는다")
        XCTAssertEqual(CompanionStore.strongerGuarantee(.uncommon, .rare), .rare)
        XCTAssertEqual(CompanionStore.strongerGuarantee(nil, .rare), .rare)
        XCTAssertEqual(CompanionStore.strongerGuarantee(.rare, nil), .rare, "보증 없는 알이 보증을 지우지 않는다")
        XCTAssertNil(CompanionStore.strongerGuarantee(nil, nil))
    }

    // MARK: 체육관 배지

    /// 인덱스가 아니라 타입으로 집는다 — 카탈로그 순서는 밸런스에 따라 바뀐다.
    private func gym(_ type: PokemonType) -> Gym {
        GymLeague.catalog.first { $0.type == type } ?? GymLeague.catalog[0]
    }
    private var bugGym: Gym { gym(.bug) }

    /// 첫 승리에만 배지와 별의조각이 나간다.
    func testFirstGymVictoryAwardsTheBadgeAndReward() {
        let s = store(noEvo)
        let before = s.availableTokens

        let paid = s.recordGymVictory(bugGym)

        XCTAssertEqual(paid, bugGym.firstClearReward)
        XCTAssertTrue(s.hasBadge(bugGym))
        XCTAssertEqual(s.availableTokens, before + bugGym.firstClearReward.starPieces)
        XCTAssertEqual(s.focusEggCount, bugGym.firstClearReward.eggs, "알도 함께 들어온다")
    }

    /// 트리거 재현: 체육관은 몇 번이고 다시 갈 수 있으므로 승리 지점을 반복해서 지난다.
    /// 졸업이 바로 그 구조로 알을 무한히 뱉었다 — 여기서는 배지가 가드다.
    func testRepeatGymVictoryPaysNothing() {
        let s = store(noEvo)
        s.recordGymVictory(bugGym)
        let afterFirst = s.availableTokens

        let eggsAfterFirst = s.focusEggCount
        let paid = s.recordGymVictory(bugGym)

        XCTAssertNil(paid, "두 번째 승리는 지급이 없다")
        XCTAssertEqual(s.availableTokens, afterFirst, "지갑도 그대로다")
        XCTAssertEqual(s.focusEggCount, eggsAfterFirst, "알도 더 들어오지 않는다")
        XCTAssertEqual(s.earnedGymBadges.count, 1, "배지도 하나뿐이다")
    }

    /// 배지는 체육관마다 따로다 — 하나를 땄다고 다른 곳 보상이 막히면 안 된다.
    func testBadgesAreTrackedPerGym() {
        let s = store(noEvo)
        s.recordGymVictory(bugGym)

        let rockGym = gym(.rock)
        XCTAssertFalse(s.hasBadge(rockGym))
        XCTAssertEqual(s.recordGymVictory(rockGym), rockGym.firstClearReward)
        XCTAssertEqual(s.earnedGymBadges, [bugGym.id, rockGym.id])
    }

    /// 배지 키는 팀 구성이 아니라 타입에서 나온다 — 관장 팀을 나중에 손봐도 딴 배지가 사라지면 안 된다.
    func testBadgeKeysAreStableAndUnique() {
        let ids = GymLeague.catalog.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "체육관 키가 겹치면 배지 하나가 둘을 덮는다")
        XCTAssertEqual(Set(ids), Set(GymLeague.catalog.map(\.type.rawValue)),
                       "키는 타입에서 나온다 — 순서를 바꿔도 배지가 딴 데로 가지 않는다")
        for gym in GymLeague.catalog {
            XCTAssertEqual(GymLeague.gym(id: gym.id), gym, "키로 되찾을 수 있어야 화면이 이름을 그린다")
        }
    }

    /// 관장 팀은 카탈로그가 약속한 머릿수를 채워야 한다 — 모자라면 도전자만 머릿수가 많아진다.
    func testEveryGymFieldsAFullTeam() {
        for gym in GymLeague.catalog {
            XCTAssertEqual(gym.teamSpeciesIDs.count, GymLeague.teamSize, "\(gym.id) 팀 크기")
            XCTAssertEqual(Set(gym.teamSpeciesIDs).count, gym.teamSpeciesIDs.count, "\(gym.id) 종 중복")
            XCTAssertGreaterThan(gym.level, 0)
            XCTAssertFalse(gym.firstClearReward.isEmpty, "\(gym.id): 보상이 비어 있다")
        }
    }

    /// 관장은 넷을 다 들고 나온다. 자동 선발에 맡겼을 땐 종에 따라 둘밖에 못 채워 PP 가 금방
    /// 떨어졌다 — 지정으로 바꾼 이유가 그것이라, 지정한 쪽이 모자라면 되돌아간 것과 같다.
    func testEveryLeaderCarriesFourNamedMoves() {
        for gym in GymLeague.catalog {
            XCTAssertEqual(gym.teamMoveNames.count, gym.teamSpeciesIDs.count,
                           "\(gym.id): 기술 목록이 팀과 짝이 맞지 않는다")
            for (slot, moves) in gym.teamMoveNames.enumerated() {
                XCTAssertEqual(moves.count, 4, "\(gym.id) \(slot)번: 기술 4개")
                XCTAssertEqual(Set(moves).count, moves.count, "\(gym.id) \(slot)번: 같은 기술이 둘")
                for name in moves {
                    XCTAssertFalse(name.isEmpty)
                    XCTAssertEqual(name, name.lowercased(),
                                   "PokéAPI move 이름은 소문자 하이픈 표기다")
                    XCTAssertFalse(name.contains(" "), "\(name): 공백이 아니라 하이픈을 쓴다")
                }
            }
        }
    }

    /// 관장은 전부 같은 레벨에 선다. 레벨이 갈리면 낮은 곳부터 순서가 **강제**되고, 그 격차가
    /// 타입 상성을 덮어 이 컨텐츠의 공략 자체가 사라진다(`GymLeague.leaderLevel` 주석의 계산).
    func testEveryLeaderStandsAtTheSameLevel() {
        XCTAssertEqual(Set(GymLeague.catalog.map(\.level)).count, 1)
        XCTAssertEqual(GymLeague.catalog.first?.level, GymLeague.leaderLevel)
    }

    /// 보상은 목록 순서를 따라 무거워진다 — 뒤로 갈수록 어렵다는 신호가 목록과 어긋나면 안 된다.
    /// 등급 보증이 오르거나(없음 → 고급 → 희귀) 별의조각이 늘어야 한다.
    func testRewardsRiseWithTheListedOrder() {
        let rewards = GymLeague.catalog.map(\.firstClearReward)
        for gym in GymLeague.catalog {
            XCTAssertGreaterThan(gym.firstClearReward.eggs, 0, "\(gym.id): 체육관 보상은 알이 중심이다")
        }
        let ranks = rewards.map { $0.eggGuarantee?.sortRank ?? 0 }
        XCTAssertEqual(ranks, ranks.sorted(), "등급 보증이 뒤로 갈수록 낮아지면 안 된다")
        let pieces = rewards.map(\.starPieces)
        XCTAssertEqual(pieces, pieces.sorted(), "별의조각도 마찬가지")
    }

    /// 마지막 배지를 딴 순간 완주 보상이 함께 나간다 — 이로치 확정은 여기서만 나온다.
    func testCompletingEveryGymGrantsTheShinyCharge() {
        let s = store(noEvo)
        for gym in GymLeague.catalog.dropLast() {
            s.recordGymVictory(gym)
            XCTAssertEqual(s.state.shinyEggCharges, 0, "\(gym.id) 까지는 확정이 없다")
        }
        let last = try! XCTUnwrap(GymLeague.catalog.last)

        let final = s.recordGymVictory(last)

        XCTAssertEqual(s.state.shinyEggCharges, GymLeague.completionReward.shinyCharges)
        XCTAssertEqual(final?.shinyCharges, GymLeague.completionReward.shinyCharges,
                       "결과 화면이 보여줄 값에도 실려야 한다")
    }

    /// 완주 보상도 배지가 가드다 — 다 모은 뒤 아무 체육관이나 다시 이겨도 확정이 또 나오면 안 된다.
    func testCompletionRewardDoesNotRepeat() {
        let s = store(noEvo)
        for gym in GymLeague.catalog { s.recordGymVictory(gym) }
        let charges = s.state.shinyEggCharges

        for gym in GymLeague.catalog { s.recordGymVictory(gym) }

        XCTAssertEqual(s.state.shinyEggCharges, charges, "재도전으로 확정이 늘지 않는다")
    }

    /// 보증은 상태에 하나뿐이라, 낮은 등급 보상이 이미 가진 높은 보증을 깎으면 안 된다.
    func testWeakerGymRewardDoesNotDowngradeAnExistingGuarantee() {
        let s = store(noEvo)
        let rare = try! XCTUnwrap(GymLeague.catalog.first { $0.firstClearReward.eggGuarantee == .rare })
        let plain = try! XCTUnwrap(GymLeague.catalog.first { $0.firstClearReward.eggGuarantee == nil })

        s.recordGymVictory(rare)
        XCTAssertEqual(s.state.eggTier, .rare)
        s.recordGymVictory(plain)

        XCTAssertEqual(s.state.eggTier, .rare, "보증 없는 알이 희귀 보증을 지우지 않는다")
    }

    /// 체육관 화면에서 고를 땐 정원이 관장 팀 크기다 — 화면에서 고른 1/3/6 과 무관하다.
    /// 정원을 화면마다 달리 주지 않으면, 6vs6 을 켜 둔 채 체육관에 들어가 여섯을 고르고
    /// 앞 셋만 나가는 일이 생긴다.
    func testGymPickerCapsAtTheLeaderTeamSize() {
        let (center, mons) = teamPickCenterForGym(monCount: 6)
        center.rankedTeamSize = 6

        for mon in mons { center.toggleTeamPick(mon.id, limit: GymLeague.teamSize) }

        XCTAssertEqual(center.pickedTeam.count, GymLeague.teamSize)
    }

    /// 같은 목록을 두 화면이 공유한다 — 체육관에서 고른 팀이 모의전에도 그대로 나간다.
    /// 목록이 둘이면 "내 출전 팀" 이 둘이 되어 어느 쪽이 나가는지 알 수 없다.
    func testBothScreensShareOnePickedTeam() {
        let (center, mons) = teamPickCenterForGym(monCount: 6)
        center.rankedTeamSize = 6

        center.toggleTeamPick(mons[3].id, limit: GymLeague.teamSize)

        XCTAssertEqual(center.battleTeamMons(size: GymLeague.teamSize).first?.id, mons[3].id)
        XCTAssertEqual(center.battleTeamMons.first?.id, mons[3].id, "모의전 팀도 같은 선봉을 본다")
    }

    /// 체육관은 관장 팀 머릿수로 나간다 — 화면에서 고른 1/3/6 과 무관하다.
    /// 머릿수가 다르면 이겨도 이긴 것 같지 않다.
    func testGymChallengeFieldsTheLeaderTeamSize() {
        let (center, mons) = teamPickCenterForGym(monCount: 6)
        center.rankedTeamSize = 6
        center.toggleTeamPick(mons[4].id)

        let team = center.battleTeamMons(size: GymLeague.teamSize)

        XCTAssertEqual(team.count, GymLeague.teamSize)
        XCTAssertEqual(team.first?.id, mons[4].id, "고른 개체가 선봉인 건 그대로다")
    }

    private func teamPickCenterForGym(monCount: Int) -> (center: BattleCenter, mons: [MonState]) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("poke-\(UUID().uuidString).json")
        let store = CompanionStore(provider: StubProvider(value: noEvo), clock: { fixedNow },
                                   fileURL: url, rng: SeededRNG(seed: 7))
        store.debugSetBoxedMons((0..<monCount).map { index in
            MonState(baseID: 20 + index, pathIDs: [20 + index], plannedPathIDs: [20 + index],
                     stageIndex: 0, usedAtStage: 0, rarity: .common, totalForms: 1)
        })
        return (BattleCenter(companion: store), store.ownedMons)
    }

    /// 돌로 진화시킨 최종형은 졸업 관문이 화면에 떠야 한다. 그 자리는 원래 "Lv.N 에 진화"·
    /// "○○돌 필요" 가 쓰던 곳인데, 최종형에 닿으면 둘 다 사라져 빈 채로 남았다 —
    /// 졸업 버튼은 조건을 채워야 나타나므로 왜 못 하는지 알 방법이 없었다.
    func testStoneEvolvedFinalFormAnnouncesItsGraduationLevel() async {
        let s = store(stoneLine)
        await s.hatch(baseID: 30)
        s.debugAddItem(.fireStone)
        XCTAssertTrue(s.useEvolutionItem(.fireStone))

        XCTAssertNil(s.nextEvolutionLevel, "최종형이라 진화 안내는 없고")
        XCTAssertNil(s.nextEvolutionItem, "쓸 돌도 남지 않았다")
        XCTAssertEqual(s.graduationLevelRequirement, PokemonBalance.graduationRequiredLevel,
                       "그 빈 자리에 졸업 관문이 들어가야 한다")
    }

    /// 관문을 채우면 안내가 사라진다 — 졸업 버튼이 그 자리를 대신한다.
    func testGraduationLevelHintDisappearsOnceReached() async {
        let s = store(stoneLine)
        await s.hatch(baseID: 30)
        s.debugAddItem(.fireStone)
        XCTAssertTrue(s.useEvolutionItem(.fireStone))
        s.debugAccrueLevelExperience(300_000_000)

        XCTAssertTrue(s.canGraduate)
        XCTAssertNil(s.graduationLevelRequirement, "졸업할 수 있으면 관문 문구는 필요 없다")
    }

    /// 대조군: 레벨 진화로 최종형이 된 개체는 면제라 관문이 없다. 이게 없으면 "최종형이면 무조건
    /// Lv.30 안내" 로 잘못 짜도 위 두 테스트는 통과한다.
    func testLevelEvolvedFinalFormShowsNoGraduationGate() async {
        let s = store(linear3)
        await s.hatch(baseID: 1)
        s.applyUsage(PokemonBalance.phaseThreshold(rarity: .common, totalForms: 3, stageIndex: 0))
        s.applyUsage(PokemonBalance.phaseThreshold(rarity: .common, totalForms: 3, stageIndex: 1))

        XCTAssertEqual(s.currentSpeciesID, 3, "최종형이지만")
        XCTAssertTrue(s.canGraduate, "면제를 받았으므로")
        XCTAssertNil(s.graduationLevelRequirement)
    }

    /// 트리거 재현: 500 짜리 돌 하나면 레벨 1 개체가 최종형이 된다(`useEvolutionItem` 은 레벨을
    /// 보지 않는다). 예전엔 그 상태로 졸업돼 20,000 짜리 알과 도감·트레이너 포인트·주간 미션을
    /// 한 번에 받아냈고, 개체는 박스에 버리면 그만이었다 — 이 앱의 육성 루프를 통째로 건너뛰는 값이다.
    func testStoneEvolvedCompanionCannotGraduateBeforeLevelThirty() async {
        let s = store(stoneLine)
        await s.hatch(baseID: 30)
        let eggsBefore = s.focusEggCount
        s.debugAddItem(.fireStone)

        XCTAssertTrue(s.useEvolutionItem(.fireStone), "돌 진화 자체는 막지 않는다")
        XCTAssertEqual(s.currentSpeciesID, 31, "최종형에 도달했지만")
        XCTAssertLessThan(s.state.active!.level, PokemonBalance.graduationRequiredLevel)

        XCTAssertFalse(s.canGraduate, "레벨 관문을 지나온 개체가 아니다")
        XCTAssertFalse(s.graduateCompanion())
        XCTAssertTrue(s.state.dex.isEmpty, "도감도")
        XCTAssertEqual(s.focusEggCount, eggsBefore, "졸업 보상 알도 나가지 않는다")
    }

    /// 관문을 채우면 열린다 — 돌 진화를 금지하는 게 아니라 졸업 보상에 레벨을 요구하는 것이다.
    func testStoneEvolvedCompanionGraduatesOnceItReachesLevelThirty() async {
        let s = store(stoneLine)
        await s.hatch(baseID: 30)
        s.debugAddItem(.fireStone)
        XCTAssertTrue(s.useEvolutionItem(.fireStone))

        s.debugAccrueLevelExperience(300_000_000)
        XCTAssertTrue(s.canGraduate)
        XCTAssertTrue(s.graduateCompanion())
        XCTAssertEqual(s.dexEntries.count, 1)
    }

    /// 대조군: 레벨로 진화해 온 개체의 면제는 그대로다. 최종형에 닿았다는 것 자체가 그 종의 마지막
    /// 진화 요구 레벨을 통과했다는 뜻이므로(#19), 아이템 경로를 막으면서 이쪽까지 막으면 과잉이다.
    /// 이 대조군이 없으면 "전부 레벨 30 요구" 로 고쳐 놓고도 위 두 테스트는 초록이다.
    func testLevelEvolvedCompanionKeepsItsExemption() async {
        let s = store(linear3)
        await s.hatch(baseID: 1)
        s.applyUsage(PokemonBalance.phaseThreshold(rarity: .common, totalForms: 3, stageIndex: 0))
        s.applyUsage(PokemonBalance.phaseThreshold(rarity: .common, totalForms: 3, stageIndex: 1))

        XCTAssertEqual(s.currentSpeciesID, 3)
        XCTAssertLessThan(s.state.active!.level, PokemonBalance.graduationRequiredLevel)
        XCTAssertTrue(s.canGraduate, "레벨 진화 경로의 면제는 유지된다")
    }

    /// 졸업해도 개체는 박스로 간다 — 도감(DexEntry)엔 레벨·경험치가 안 남으므로, 개체를 버리면
    /// 그 포켓몬을 영영 다시 키울 수 없다. 졸업은 "다음 알로 넘어가는 버튼"이지 삭제가 아니다.
    func testGraduationKeepsTheCompanionInTheBox() async {
        let s = store(noEvo)
        await s.hatch(baseID: 20)
        let graduatedID = s.state.active?.id
        s.debugAccrueLevelExperience(300_000_000)
        XCTAssertTrue(s.graduateCompanion())

        XCTAssertNil(s.state.active, "활성 슬롯은 비고 새 알이 시작된다")
        XCTAssertEqual(s.state.dex.count, 1, "도감에 기록은 남고")
        XCTAssertEqual(s.boxedMons.map(\.id), [graduatedID], "개체 자체는 박스에 보관된다")

        // 박스에서 다시 데려와 계속 키울 수 있어야 한다.
        s.switchCompanion(to: try! XCTUnwrap(graduatedID))
        XCTAssertEqual(s.state.active?.id, graduatedID)
        XCTAssertEqual(s.currentSpeciesID, 20)
    }

    /// [회귀] 기동 시 조정할 게 없으면 세이브를 다시 쓰지 않는다. reconcileStoredEggDates() 가
    /// 무조건 save() 하던 동안엔 손상 세이브를 .corrupt 로 옮긴 자리에 파일이 즉시 되살아나
    /// testCorruptStateFileBackedUpBeforeReset 이 지키는 복구 장치가 무력화됐다.
    func testStartupDoesNotRewriteAnUnchangedSave() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("poke-nowrite-\(UUID().uuidString).json")
        let s1 = CompanionStore(provider: StubProvider(value: linear3), clock: { fixedNow },
                                fileURL: url, rng: SeededRNG(seed: 7))
        s1.debugMarkStarterChosen()   // 파일 생성
        let before = try Data(contentsOf: url)

        try FileManager.default.removeItem(at: url)   // 지운 뒤 재로드 — 다시 쓰면 파일이 되살아난다
        try before.write(to: url)
        _ = CompanionStore(provider: StubProvider(value: linear3), clock: { fixedNow },
                           fileURL: url, rng: SeededRNG(seed: 7))
        XCTAssertEqual(try Data(contentsOf: url), before, "변경이 없으면 세이브를 다시 쓰지 않는다")
    }

    /// [회귀] 졸업 보상 알은 5분 타이머로 부화한다. 예전엔 eggUsage(누적 임계) 알을 줬는데 그 값을
    /// 채우는 생산 경로가 없어(accrue 는 호출자 없음) 영원히 안 깨졌다 — 졸업이 곧 진행 정지였다.
    func testGraduationGrantsATimedEggInsteadOfADeadThresholdEgg() async {
        let s = store(noEvo)
        await s.hatch(baseID: 20)
        s.debugAccrueLevelExperience(300_000_000)
        let eggsBefore = s.focusEggCount
        XCTAssertTrue(s.graduateCompanion())

        XCTAssertEqual(s.focusEggCount, eggsBefore + 1, "타이머가 붙은 알을 받는다")
        XCTAssertNotNil(s.nextStoredEggHatchAt, "부화 예정 시각이 있어야 카운트다운이 뜬다")
        XCTAssertEqual(s.state.eggUsage, 0, "누적 임계 알은 더 이상 쓰지 않는다")
    }

    /// [회귀 #28] 동행을 유지한 채 박스로 들어간 개체도 도감에 보여야 한다. 예전엔 도감 접근자가
    /// state.dex + 활성 개체만 읽어, 박스 개체는 활성으로 바꿔야만 나타나고 다시 바꾸면 사라졌다.
    func testBoxedCompanionsAppearInTheDexWithoutSwitching() async {
        let s = store(linear3)
        await s.hatch(baseID: 1)
        let activeID = s.state.active?.id

        // 동행이 있는 상태에서 다른 개체를 박스에 넣는다(보관 알 부화가 만드는 상태와 같다).
        let boxed = MonState(baseID: 4, pathIDs: [4], stageIndex: 0, usedAtStage: 0,
                             rarity: .common, totalForms: 1,
                             names: [4: ["ko": "포4", "en": "P4"]])
        s.debugSetBoxedMons([boxed])

        XCTAssertEqual(s.state.active?.id, activeID, "동행은 그대로")
        XCTAssertTrue(s.dexSpecies.map(\.id).contains(4), "박스 개체도 도감에 잡혀야 한다")
        XCTAssertTrue(s.dexEntries.contains { $0.baseID == 4 })
    }

    /// 박스 개체는 currentLine 이 없다 — 개체에 저장된 이름으로 그려야 종 번호(#4)로 안 떨어진다.
    func testBoxedCompanionUsesItsStoredNames() async {
        let s = store(linear3)
        s.setLanguage(.ko)
        await s.hatch(baseID: 1)
        s.debugSetBoxedMons([MonState(baseID: 4, pathIDs: [4], stageIndex: 0, usedAtStage: 0,
                                      rarity: .common, totalForms: 1,
                                      names: [4: ["ko": "포4", "en": "P4"]])])
        XCTAssertEqual(s.dexSpecies.first { $0.id == 4 }?.name, "포4")
    }

    /// [회귀] 졸업한 개체를 박스에서 다시 꺼내도 재졸업은 불가하다. 졸업해도 개체는 박스에 남으므로(#27)
    /// 최종형·레벨 조건은 그대로 만족한다 — 막지 않으면 졸업 → 스위치 → 졸업 반복으로 알이 무한 생성된다.
    func testGraduatedCompanionCannotGraduateAgainForAnotherEgg() async {
        let s = store(noEvo)
        await s.hatch(baseID: 20)
        let monID = try! XCTUnwrap(s.state.active?.id)
        s.debugAccrueLevelExperience(300_000_000)
        XCTAssertTrue(s.graduateCompanion())
        let eggsAfterFirst = s.focusEggCount
        let dexAfterFirst = s.state.dex.count

        // 박스에서 그 개체를 다시 동행으로 —  조건은 그대로 충족되지만 재졸업은 막혀야 한다.
        s.switchCompanion(to: monID)
        s.tick()   // 라인 재로드 트리거(switchCompanion 이 currentLine 을 비운다)
        let lineLoaded = await waitUntil { s.currentLine != nil }
        XCTAssertTrue(lineLoaded, "라인이 로드돼야 졸업 조건을 평가한다")
        XCTAssertEqual(s.state.active?.id, monID)
        XCTAssertFalse(s.canGraduate, "이미 졸업한 개체는 버튼이 다시 뜨면 안 된다")
        XCTAssertFalse(s.graduateCompanion())
        XCTAssertEqual(s.focusEggCount, eggsAfterFirst, "알이 추가로 생기면 안 된다")
        XCTAssertEqual(s.state.dex.count, dexAfterFirst, "도감 기록도 개체당 한 번")
    }

    /// [회귀] 기술 학습 카드는 그 제안을 받은 개체에게만 떠야 한다. 예전엔 동행을 바꿔도 이전 개체의
    /// 카드가 그대로 남아, 다른 포켓몬 화면에 "새 기술을 배울까요?" 가 계속 떠 있었다(수락은 monID
    /// 검사에 막혀 동작도 안 했다 — 눌러도 아무 일이 없는 카드).
    func testMoveLearningPromptDoesNotFollowACompanionSwitch() async {
        let s = store(linear3)
        await s.hatch(baseID: 1)
        let firstID = try! XCTUnwrap(s.state.active?.id)
        s.debugQueueMoveLearning(monID: firstID)
        XCTAssertNotNil(s.moveLearningPrompt, "제안을 받은 개체에겐 뜬다")

        // 다른 개체를 동행으로 —  이전 개체의 카드는 사라져야 한다.
        let other = MonState(baseID: 4, pathIDs: [4], stageIndex: 0, usedAtStage: 0,
                             rarity: .common, totalForms: 1)
        s.debugSetBoxedMons([other])
        s.switchCompanion(to: other.id)
        XCTAssertNil(s.moveLearningPrompt, "다른 포켓몬에게 이전 개체의 학습 카드가 뜨면 안 된다")
    }

    /// [회귀] 같은 기술이 여러 장 쌓이면 안 된다. queueMoveLearning 이 개체를 값으로 한 번만
    /// 캡처해 두고 그 낡은 learnedMoves 와만 대조하던 동안, 배치 도중 배운 기술이 다시 제안됐고
    /// 큐에 이미 든 것과도 대조하지 않아 중복 카드가 쌓였다.
    func testAlreadyPendingMoveIsNotQueuedTwice() async {
        let s = store(linear3)
        await s.hatch(baseID: 1)
        let monID = try! XCTUnwrap(s.state.active?.id)

        s.debugQueueMoveLearning(monID: monID)
        let firstMove = try! XCTUnwrap(s.moveLearningPrompt?.move.id)
        // 같은 기술을 다시 세워도 대기분이 늘어나면 안 된다.
        s.debugQueueMoveLearning(monID: monID)
        XCTAssertEqual(s.moveLearningPrompt?.move.id, firstMove)
        XCTAssertEqual(s.debugMoveLearningQueueCount, 0, "같은 기술이 큐에 또 쌓이면 안 된다")
    }

    /// 최종형이 아니면 졸업 버튼 자체가 안 뜬다.
    func testCannotGraduateBeforeTheFinalForm() async {
        let s = store(linear3)
        await s.hatch(baseID: 1)
        XCTAssertFalse(s.canGraduate)
        XCTAssertFalse(s.graduateCompanion())
        XCTAssertNotNil(s.state.active)
    }

    func testLineNodesPreviewsCompleteLinearEvolution() async {
        let s = store(linear3)
        await s.hatch(baseID: 1)

        XCTAssertEqual(s.lineNodes, [
            EvoLineItem(.species(1), .current),
            EvoLineItem(.species(2), .future),
            EvoLineItem(.species(3), .future),
        ])
    }

    func testRealizedLineItemsUsesStageIndexForCurrentMarker() {
        XCTAssertEqual(CompanionStore.realizedLineItems(pathIDs: [1, 2], stageIndex: 0), [
            EvoLineItem(.species(1), .current),
            EvoLineItem(.species(2), .done),
        ])
    }

    func testRepairedPlanAppendsFallbackRouteToCurrentPath() {
        XCTAssertEqual(CompanionStore.repairedPlan(
            realizedPath: [265], stageIndex: 0, fallbackRoute: [265, 266, 267]),
            [265, 266, 267])
    }

    func testLineNodesHidesUnresolvedWurmpleBranchAsSingleMystery() async {
        let s = store(wurmpleLine)
        await s.hatch(baseID: 265)

        XCTAssertEqual(s.lineNodes, [
            EvoLineItem(.species(265), .current),
            EvoLineItem(.mystery, .future),
        ])
    }

    func testLineNodesShowsKnownPrefixBeforeDownstreamBranchAsMystery() async {
        let s = store(delayedBranchLine)
        await s.hatch(baseID: 43)

        XCTAssertEqual(s.lineNodes, [
            EvoLineItem(.species(43), .current),
            EvoLineItem(.species(44), .future),
            EvoLineItem(.mystery, .future),
        ])
    }

    func testLineNodesRevealsChosenWurmpleBranchAfterEvolution() async throws {
        let s = store(wurmpleLine)
        await s.hatch(baseID: 265)
        let plan = try XCTUnwrap(s.state.active?.plannedPathIDs)
        XCTAssertEqual(plan.count, 3)
        guard plan.count == 3 else { return }

        s.applyUsage(PokemonBalance.phaseThreshold(
            rarity: .common, totalForms: plan.count, stageIndex: 0))

        XCTAssertEqual(s.lineNodes, [
            EvoLineItem(.species(265), .done),
            EvoLineItem(.species(plan[1]), .current),
            EvoLineItem(.species(plan[2]), .future),
        ])
    }

    func testBranchingPrefersUncollectedFinals() async {
        let s = store(branch3)
        let evo = PokemonBalance.phaseThreshold(rarity: .common, totalForms: 2, stageIndex: 0)
        var finals: [Int] = []
        for _ in 0..<3 {
            await s.hatch(baseID: 10)
            s.applyUsage(evo)    // 분기 진화
            XCTAssertTrue(s.graduateCompanion())   // 졸업(사용자 액션)
            finals.append(s.dexEntries.last!.finalID)
        }
        XCTAssertEqual(Set(finals).count, 3)   // 같은 base 재부화 시 매번 다른 분기
        XCTAssertEqual(Set(finals), [11, 12, 13])
    }

    func testHatchPreselectsWurmpleRouteAndEvolutionDoesNotConsumeRNG() async {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("poke-\(UUID().uuidString).json")
        let rng = CountingRNG(seed: 7)
        let s = CompanionStore(provider: StubProvider(value: wurmpleLine), clock: { fixedNow }, fileURL: url, rng: rng)

        await s.hatch(baseID: 265)

        guard let hatched = s.state.active else { return XCTFail("Wurmple should hatch") }
        let plan = hatched.plannedPathIDs
        XCTAssertTrue([[265, 266, 267], [265, 268, 269]].contains(plan), "plan must be one complete root-to-leaf route")
        XCTAssertEqual(hatched.pathIDs, [265], "realized path starts at the base only")
        XCTAssertEqual(hatched.totalForms, plan.count)

        guard plan.count > 1 else { return }

        let callsAfterHatch = rng.callCount
        s.applyUsage(PokemonBalance.phaseThreshold(rarity: hatched.rarity, totalForms: hatched.totalForms, stageIndex: 0))

        XCTAssertEqual(rng.callCount, callsAfterHatch, "evolution must consume the stored plan without rolling RNG")
        XCTAssertEqual(s.state.active?.pathIDs, Array(plan.prefix(2)))
        XCTAssertEqual(s.currentSpeciesID, plan[1])
    }

    func testPersistenceRoundTrip() async {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("poke-persist-\(UUID().uuidString).json")
        let s1 = CompanionStore(provider: StubProvider(value: linear3), clock: { fixedNow }, fileURL: url, rng: SeededRNG(seed: 1))
        await s1.hatch(baseID: 1)
        s1.applyUsage(PokemonBalance.phaseThreshold(rarity: .common, totalForms: 3, stageIndex: 0))
        s1.setLanguage(.ja)
        let s2 = CompanionStore(provider: StubProvider(value: linear3), clock: { fixedNow }, fileURL: url, rng: SeededRNG(seed: 1))
        XCTAssertEqual(s2.state.active?.currentID, 2)
        XCTAssertEqual(s2.state.active?.stageIndex, 1)
        XCTAssertEqual(s2.language, .ja)
    }

    func testReloadPreservesCompleteShortPlannedRouteLength() async {
        let line = makeLine(base: 1, tree: node(1, [node(2), node(3, [node(4)])]))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("poke-reload-plan-\(UUID().uuidString).json")
        let s1 = CompanionStore(provider: StubProvider(value: line), clock: { fixedNow }, fileURL: url, rng: SeededRNG(seed: 7))
        await s1.hatch(baseID: 1)
        XCTAssertEqual(s1.state.active?.plannedPathIDs, [1, 2], "seed selects the short complete route")

        var opposing = SeededRNG(seed: 1)
        XCTAssertEqual(opposing.next() % 2, 1, "a reroll would select the opposite branch (3)")
        let rng = CountingRNG(seed: 1)
        let s2 = CompanionStore(provider: StubProvider(value: line), clock: { fixedNow }, fileURL: url, rng: rng)
        s2.tick()
        let loaded = await waitUntil { s2.currentLine != nil }
        XCTAssertTrue(loaded, "line should load before evolution")

        XCTAssertNotNil(s2.currentLine)
        XCTAssertEqual(s2.state.active?.plannedPathIDs, [1, 2])
        XCTAssertEqual(s2.state.active?.totalForms, 2)
        let callsAfterLoad = rng.callCount
        s2.applyUsage(PokemonBalance.phaseThreshold(rarity: .common, totalForms: 2, stageIndex: 0))
        XCTAssertEqual(s2.currentSpeciesID, 2, "persisted route must beat the post-restart RNG branch")
        XCTAssertEqual(rng.callCount, callsAfterLoad, "load and evolution must not reroll the persisted route")
    }

    func testReloadLegacyIncompletePlanMigratesToPersistedCompleteRoute() async throws {
        let line = wurmpleLine
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("poke-reload-legacy-\(UUID().uuidString).json")
        let legacy = #"{"economyVersion":2,"forcedResetVersion":1,"active":{"baseID":265,"pathIDs":[265],"stageIndex":0,"usedAtStage":0,"rarity":"common","totalForms":1}}"#
        try Data(legacy.utf8).write(to: url)
        let rng = CountingRNG(seed: 7)
        let s = CompanionStore(provider: StubProvider(value: line), clock: { fixedNow }, fileURL: url, rng: rng)

        s.tick()
        let loaded = await waitUntil { s.currentLine != nil }
        XCTAssertTrue(loaded, "line should load legacy state")

        let migratedPlan = s.state.active?.plannedPathIDs
        XCTAssertTrue([[265, 266, 267], [265, 268, 269]].contains(migratedPlan ?? []))
        XCTAssertEqual(s.state.active?.pathIDs, [265], "realized path must remain intact")
        XCTAssertEqual(s.state.active?.totalForms, migratedPlan?.count)
        XCTAssertEqual(rng.callCount, 2, "Wurmple suffix selection rolls once per evolution edge")

        let reloadRNG = CountingRNG(seed: 1)
        let reloaded = CompanionStore(provider: StubProvider(value: line), clock: { fixedNow }, fileURL: url, rng: reloadRNG)
        reloaded.tick()
        let reloadedLine = await waitUntil { reloaded.currentLine != nil }
        XCTAssertTrue(reloadedLine)
        XCTAssertEqual(reloaded.state.active?.plannedPathIDs, migratedPlan, "migration must persist its one-time choice")
        XCTAssertEqual(reloadRNG.callCount, 0, "a persisted complete route must not reroll on restart")
    }

    func testReloadRepairsInvalidPlanSuffixWithoutRewindingRealizedPath() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("poke-invalid-plan-\(UUID().uuidString).json")
        let saved = #"{"economyVersion":2,"forcedResetVersion":1,"active":{"baseID":265,"pathIDs":[265,266],"plannedPathIDs":[265,266,269],"stageIndex":1,"usedAtStage":42,"rarity":"common","totalForms":3}}"#
        try Data(saved.utf8).write(to: url)
        let s = CompanionStore(provider: StubProvider(value: wurmpleLine), clock: { fixedNow }, fileURL: url, rng: SeededRNG(seed: 9))

        s.tick()
        let loaded = await waitUntil { s.currentLine != nil }
        XCTAssertTrue(loaded)

        XCTAssertEqual(s.state.active?.pathIDs, [265, 266])
        XCTAssertEqual(s.state.active?.plannedPathIDs, [265, 266, 267])
        XCTAssertEqual(s.state.active?.stageIndex, 1)
        XCTAssertEqual(s.state.active?.totalForms, 3)
        XCTAssertEqual(s.state.active?.usedAtStage, 42)
    }

    func testReloadWrongRootNormalizesPathWithoutChangingIdentityOrDisguise() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("poke-wrong-root-\(UUID().uuidString).json")
        let saved = #"{"economyVersion":2,"forcedResetVersion":1,"active":{"baseID":265,"pathIDs":[999],"plannedPathIDs":[999],"stageIndex":0,"usedAtStage":42,"rarity":"common","totalForms":1,"isShiny":true,"nature":"timid","dittoDisguise":265}}"#
        try Data(saved.utf8).write(to: url)
        let s = CompanionStore(provider: StubProvider(value: wurmpleLine), clock: { fixedNow }, fileURL: url, rng: SeededRNG(seed: 9))

        s.tick()
        let loaded = await waitUntil { s.currentLine != nil }
        XCTAssertTrue(loaded)

        XCTAssertEqual(s.state.active?.pathIDs, [265])
        XCTAssertTrue([[265, 266, 267], [265, 268, 269]].contains(s.state.active?.plannedPathIDs ?? []))
        XCTAssertEqual(s.state.active?.usedAtStage, 42)
        XCTAssertTrue(s.state.active?.isShiny ?? false)
        XCTAssertEqual(s.state.active?.nature, .timid)
        XCTAssertEqual(s.state.active?.dittoDisguise, 265)
        XCTAssertFalse(s.state.active?.dittoRevealed ?? true)
    }

    func testReloadLeafCurrentPlanDoesNotConsumeRNG() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("poke-leaf-plan-\(UUID().uuidString).json")
        let saved = #"{"economyVersion":2,"forcedResetVersion":1,"active":{"baseID":265,"pathIDs":[265,266,267],"plannedPathIDs":[265,266,267],"stageIndex":2,"usedAtStage":42,"rarity":"common","totalForms":3}}"#
        try Data(saved.utf8).write(to: url)
        let rng = CountingRNG(seed: 9)
        let s = CompanionStore(provider: StubProvider(value: wurmpleLine), clock: { fixedNow }, fileURL: url, rng: rng)

        s.tick()
        let loaded = await waitUntil { s.currentLine != nil }
        XCTAssertTrue(loaded)

        XCTAssertEqual(s.state.active?.pathIDs, [265, 266, 267])
        XCTAssertEqual(s.state.active?.plannedPathIDs, [265, 266, 267])
        XCTAssertEqual(rng.callCount, 0)
    }

    func testLineLoadPreservesUpdatesMadeWhileProviderIsSuspended() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("poke-load-race-\(UUID().uuidString).json")
        let saved = #"{"economyVersion":2,"forcedResetVersion":1,"active":{"baseID":1,"pathIDs":[1],"stageIndex":0,"usedAtStage":0,"rarity":"common","totalForms":1,"nature":"adamant"},"inventory":{"mint":1}}"#
        try Data(saved.utf8).write(to: url)
        let provider = SuspendedLineProvider(value: linear3)
        let s = CompanionStore(provider: provider, clock: { fixedNow }, fileURL: url, rng: SeededRNG(seed: 7))

        s.tick()
        let suspensionDeadline = Date().addingTimeInterval(1)
        while !(await provider.isSuspended()), Date() < suspensionDeadline {
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        let isSuspended = await provider.isSuspended()
        XCTAssertTrue(isSuspended, "line fetch should be suspended")

        s.applyUsage(42)
        let changedNature = try XCTUnwrap(s.useMint())
        XCTAssertEqual(s.state.active?.usedAtStage, 42)
        XCTAssertEqual(s.state.active?.nature, changedNature)

        await provider.resume()
        let loaded = await waitUntil { s.currentLine != nil }
        XCTAssertTrue(loaded)

        XCTAssertEqual(s.state.active?.usedAtStage, 42)
        XCTAssertEqual(s.state.active?.nature, changedNature)
        let persisted = try JSONDecoder().decode(CompanionState.self, from: Data(contentsOf: url))
        XCTAssertEqual(persisted.active?.usedAtStage, 42)
        XCTAssertEqual(persisted.active?.nature, changedNature)
    }

    func testLocalizedName() async {
        let s = store(linear3)
        await s.hatch(baseID: 1)
        s.setLanguage(.ko); XCTAssertEqual(s.displayName, "포1")
        s.setLanguage(.en); XCTAssertEqual(s.displayName, "P1")
        s.setLanguage(.ja); XCTAssertEqual(s.displayName, "ポ1")
    }

    /// [문서화] 비대칭 깊이 분기에서도 부화 시 선택한 경로 길이를 totalForms 로 고정한다.
    /// 크래시·무한루프 없이 최종체에서 졸업하고 실제 경로가 보존됨을 잠근다.
    func testAsymmetricBranchGraduatesSafely() async {
        let line = makeLine(base: 1, tree: node(1, [node(2), node(3, [node(4)])]))   // depth=3, 분기 {2, 3→4}
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("poke-asym-\(UUID().uuidString).json")
        let s = CompanionStore(provider: StubProvider(value: line), clock: { fixedNow }, fileURL: url, rng: SeededRNG(seed: 7))
        await s.hatch(baseID: 1)
        XCTAssertEqual(s.state.active?.totalForms, s.state.active?.plannedPathIDs.count,
                       "totalForms = 선택된 계획 경로 길이")
        var guardCount = 0
        while s.state.active != nil, guardCount < 12 {
            guardCount += 1
            let stage = s.state.active!.stageIndex
            s.applyUsage(PokemonBalance.phaseThreshold(rarity: .common, totalForms: s.state.active!.totalForms, stageIndex: stage))
            if s.canGraduate { s.graduateCompanion() }   // 졸업은 사용자 액션(#19)
        }
        XCTAssertNil(s.state.active, "어느 분기든 최종체에서 졸업(크래시·무한루프 없음)")
        XCTAssertEqual(s.dexEntries.count, 1)
        let chain = s.dexEntries[0].chainOrder
        XCTAssertTrue(chain == [1, 2] || chain == [1, 3, 4], "실제 진화 경로 보존: \(chain)")
    }
}

// MARK: 이름 폴백 (AppLanguage.resolveName)

/// [회귀] `resolveName` 의 폴백 순서(요청 언어 → 영어)를 재는 유일한 단언이 삭제된 대화 테스트
/// 파일 안에 있었다. 이 함수는 종·기술·특성·체육관 이름 전부가 지나는 길이라, 커버는 붙어 있던
/// 기능이 아니라 함수 쪽에 있어야 한다. 대조군까지 둬 "언제나 영어"·"언제나 nil" 을 배제한다.
final class NameFallbackTests: XCTestCase {
    func testResolveNameFallsBackToEnglishButPrefersTheRequestedLanguage() {
        let englishOnly = ["en": "Static"]
        XCTAssertEqual(AppLanguage.ko.resolveName(englishOnly), "Static")
        XCTAssertEqual(AppLanguage.ja.resolveName(englishOnly), "Static")

        // 요청 언어가 있으면 영어를 쓰지 않는다.
        let both = ["en": "Static", "ko": "정전기", "ja": "せいでんき"]
        XCTAssertEqual(AppLanguage.ko.resolveName(both), "정전기")
        XCTAssertEqual(AppLanguage.ja.resolveName(both), "せいでんき")

        // 폴백 대상조차 없으면 nil — 빈 문자열이나 아무 값이나 고르지 않는다.
        XCTAssertNil(AppLanguage.ko.resolveName(["de": "Statik"]))
    }
}

// MARK: 표시 로케일 (자동 생성 문장)

/// 앱 언어와 시스템 로케일이 다를 때 `Text(_, style: .relative)` 같은 자동 문장이 시스템을 따라가면
/// 한 화면에 두 언어가 섞인다(한국어 Mac + 영어 앱 → "Catch log" 옆에 "3시간 46분").
/// 팝오버 루트가 `\.locale` 로 앱 언어를 내려주므로, 그 매핑이 실제로 해당 언어의 상대 시각을
/// 만들어내는지까지 고정한다 — 코드만 비교하면 잘못 매핑해도 통과한다.
final class DisplayLocaleTests: XCTestCase {
    func testDisplayLocaleMatchesLanguageCode() {
        XCTAssertEqual(AppLanguage.ko.displayLocale.identifier, "ko")
        XCTAssertEqual(AppLanguage.en.displayLocale.identifier, "en")
        XCTAssertEqual(AppLanguage.ja.displayLocale.identifier, "ja")
    }

    func testRelativeTimeFollowsAppLanguageNotSystem() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let past = now.addingTimeInterval(-3 * 3600)

        func relative(_ lang: AppLanguage) -> String {
            let f = RelativeDateTimeFormatter()
            f.locale = lang.displayLocale
            return f.localizedString(for: past, relativeTo: now)
        }

        XCTAssertTrue(relative(.en).contains("hour"), "영어: \(relative(.en))")
        XCTAssertTrue(relative(.ko).contains("시간"), "한국어: \(relative(.ko))")
        XCTAssertTrue(relative(.ja).contains("時間"), "일본어: \(relative(.ja))")
        // 세 언어가 서로 달라야 한다 — 하나로 고정돼 있으면 매핑이 죽은 것이다.
        XCTAssertEqual(Set([relative(.en), relative(.ko), relative(.ja)]).count, 3)
    }
}

// MARK: 포획 로그 정렬 / 요약

@MainActor
final class DexSortingTests: XCTestCase {
    /// sortRank 는 목록 정렬 키가 아니지만(로그는 시각순) 프리미엄 알의 등급 게이트가
    /// `line.rarity.sortRank < tier.sortRank` 로 쓴다 — 순서가 뒤집히면 고급/희귀 알이 조용히
    /// 낮은 등급을 통과시킨다. 그래서 순서 보증만 여기 남긴다.
    func testSortRankOrdersRarityAscendingByValue() {
        XCTAssertLessThan(Rarity.common.sortRank, Rarity.uncommon.sortRank)
        XCTAssertLessThan(Rarity.uncommon.sortRank, Rarity.rare.sortRank)
        XCTAssertLessThan(Rarity.rare.sortRank, Rarity.legendary.sortRank)
    }

    /// 로그는 시간순 기록이다 — 희귀도가 높아도 오래되면 아래로 내려간다.
    /// legendary 를 **가장 먼저** 졸업시켜, 희귀도 우선 정렬이면 통과하지 못하게 한다
    /// (과거 정렬은 legendary 를 맨 앞에 고정해 오래된 상위 희귀도가 최신 일반 위에 남았다).
    func testDexEntriesSortedByRecencyRegardlessOfRarity() async {
        // legendary 1개 + common 라인 2개(시각 다름)를 같은 store 에 졸업시킨다.
        // StubProvider 는 라인 1개만 주므로, 라인별로 store 를 분리하지 않고
        // 직접 졸업 흐름을 재현: 무진화(단일 임계) 라인을 hatch→applyUsage 로 졸업.
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("poke-\(UUID().uuidString).json")
        var tick = 0
        // 라인을 바꿔가며 졸업시키기 위해 가변 provider 사용.
        let provider = MutableProvider()
        let s = CompanionStore(provider: provider,
                               clock: { fixedNow.addingTimeInterval(TimeInterval(tick)) },
                               fileURL: url, rng: SeededRNG(seed: 3))

        // legendary (가장 먼저 — 희귀도 우선 정렬이면 맨 앞으로 올라온다)
        provider.line = makeLine(base: 200, tree: node(200), rarity: .legendary)
        tick = 1; await s.hatch(baseID: 200)
        s.debugAccrueLevelExperience(300_000_000)
        XCTAssertTrue(s.graduateCompanion())

        // common #1
        provider.line = makeLine(base: 100, tree: node(100), rarity: .common)
        tick = 2; await s.hatch(baseID: 100)
        s.debugAccrueLevelExperience(300_000_000)
        XCTAssertTrue(s.graduateCompanion())

        // common #2 (가장 나중)
        provider.line = makeLine(base: 101, tree: node(101), rarity: .common)
        tick = 3; await s.hatch(baseID: 101)
        s.debugAccrueLevelExperience(300_000_000)
        XCTAssertTrue(s.graduateCompanion())

        XCTAssertEqual(s.dexEntries.count, 3)
        let sorted = s.dexEntriesSorted
        // 순수 시간 역순 — 희귀도는 순서에 관여하지 않는다.
        XCTAssertEqual(sorted.map(\.finalID), [101, 100, 200])
        XCTAssertEqual(sorted[2].rarity, .legendary, "가장 오래된 legendary 는 맨 뒤")

        // 희귀도별 카운트(요약 헤더 — 정렬과 무관하게 개체 수 기준)
        XCTAssertEqual(s.dexCount(.common), 2)
        XCTAssertEqual(s.dexCount(.legendary), 1)
        XCTAssertEqual(s.dexCount(.rare), 0)
    }
}

/// 테스트용 — 라인을 호출 전에 갈아끼울 수 있는 provider. 단일 스레드 테스트 한정.
private final class MutableProvider: PokeProviding, @unchecked Sendable {
    nonisolated(unsafe) var line: EvoLine = makeLine(base: 1, tree: node(1))
    func line(baseSpeciesID: Int) async throws -> EvoLine { line }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [BaseSpecies(id: line.baseID, captureRate: 255)] }
}

// MARK: 개체 아이덴티티 (shiny / nature) — v2.2.0

@MainActor
final class CompanionIdentityTests: XCTestCase {
    private func store(_ line: EvoLine, seed: UInt64) -> CompanionStore {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("poke-\(UUID().uuidString).json")
        return CompanionStore(provider: StubProvider(value: line), clock: { fixedNow }, fileURL: url, rng: SeededRNG(seed: seed))
    }

    /// 직접 hatch(baseID:) 는 rng 를 shiny → nature 순으로 소비한다. 같은 시드 재생으로 기대값 산출.
    private func expectedRoll(seed: UInt64) -> (shiny: Bool, nature: PokemonNature) {
        var rng = SeededRNG(seed: seed)
        let shiny = rng.next() % PokemonOdds.shinyDenominator == 0
        let nature = PokemonNature.allCases[Int(rng.next() % UInt64(PokemonNature.allCases.count))]
        return (shiny, nature)
    }

    /// 임의 시드에서 부화 롤이 결정적이고 성격이 항상 부여되는지.
    func testHatchAssignsDeterministicShinyAndNature() async {
        for seed: UInt64 in [1, 7, 42, 12345] {
            let s = store(linear3, seed: seed)
            let expected = expectedRoll(seed: seed)
            await s.hatch(baseID: 1)
            XCTAssertEqual(s.state.active?.isShiny, expected.shiny, "seed \(seed)")
            XCTAssertEqual(s.state.active?.nature, expected.nature, "seed \(seed)")
        }
    }

    /// shiny 가 실제로 나오는 시드를 탐색해 true 경로를 검증(1/64 확률이 코드에 존재함을 보장).
    func testShinyPathReachable() async {
        var shinySeed: UInt64?
        for seed: UInt64 in 0..<5000 where expectedRoll(seed: seed).shiny { shinySeed = seed; break }
        guard let seed = shinySeed else { return XCTFail("5000개 시드 중 shiny 없음 — 분모 확인") }
        let s = store(linear3, seed: seed)
        await s.hatch(baseID: 1)
        XCTAssertEqual(s.state.active?.isShiny, true)
        XCTAssertTrue(s.currentIsShiny)
    }

    /// 진화를 거쳐 졸업해도 shiny/nature 가 도감 항목에 보존되는지.
    func testGraduateCarriesIdentityToDex() async {
        let s = store(noEvo, seed: 3)   // 무진화 → 임계 도달 시 바로 졸업
        await s.hatch(baseID: 20)
        let shiny = s.state.active!.isShiny
        let nature = s.state.active!.nature
        XCTAssertNotNil(nature)
        s.debugAccrueLevelExperience(300_000_000)   // 무진화 종은 레벨 30 게이트(#19)
        XCTAssertTrue(s.graduateCompanion())
        XCTAssertNil(s.state.active)   // 졸업
        XCTAssertEqual(s.state.dex.count, 1)
        XCTAssertEqual(s.state.dex[0].isShiny, shiny)
        XCTAssertEqual(s.state.dex[0].nature, nature)
    }

    /// 구버전 저장(shiny/nature 키 없음) 디코딩 — 기본값(false/nil)으로 로드.
    func testBackwardCompatibleDecode() throws {
        let old = """
        {"installBaselineSet":true,"usedSinceInstall":100,"eggUsage":0,
         "claimedTodayTokens":100,"lastDate":"d1",
         "active":{"baseID":1,"pathIDs":[1],"stageIndex":0,"usedAtStage":5,"rarity":"common","totalForms":3},
         "dex":[{"id":"x","baseID":4,"finalID":6,"chainOrder":[4,5,6],"rarity":"rare"}],
         "collectedFinals":["4:6"],"language":"ko"}
        """
        let s = try JSONDecoder().decode(CompanionState.self, from: Data(old.utf8))
        XCTAssertEqual(s.active?.plannedPathIDs, [1])
        XCTAssertEqual(s.active?.isShiny, false)
        XCTAssertNil(s.active?.nature)
        XCTAssertEqual(s.dex[0].isShiny, false)
        XCTAssertNil(s.dex[0].nature)
        // 재인코딩 후 재디코딩도 안정적(라운드트립)
        let round = try JSONDecoder().decode(CompanionState.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(round.active?.isShiny, false)
    }

    /// [출시 안전] 손상된 상태 파일: active.pathIDs 가 비면 그 active 만 nil(알)로 폴백하되 나머지 상태는
    /// 보존한다(필드별 관대화). 깨진 active 를 살려두면 currentID out-of-bounds 위험이므로 nil 이어야 한다
    /// (예전엔 전체 디코드를 throw 시켜 상태 전면 초기화 → 도감·인벤토리까지 유실됐다).
    func testEmptyPathIDsActiveFallsBackToNilPreservingRest() {
        let corrupt = """
        {"installBaselineSet":true,"eggUsage":0,"lastDate":"d1",
         "active":{"baseID":1,"pathIDs":[],"stageIndex":0,"usedAtStage":0,"rarity":"common","totalForms":3}}
        """
        let state = try? JSONDecoder().decode(CompanionState.self, from: Data(corrupt.utf8))
        XCTAssertNotNil(state, "빈 pathIDs 는 active 만 무효화 — 전체 디코드는 성공(부분 복원)")
        XCTAssertNil(state?.active, "빈 pathIDs active 는 nil(알)로 폴백 — 깨진 active 를 살려두지 않는다")
        XCTAssertEqual(state?.eggUsage, 0, "나머지 필드는 보존")
    }

    /// currentID 는 pathIDs 가 비어도(방어) baseID 로 폴백 — 크래시 없음.
    func testCurrentIDFallsBackToBaseWhenPathEmpty() {
        let m = MonState(baseID: 42, pathIDs: [], stageIndex: 0, usedAtStage: 0, rarity: .common, totalForms: 1)
        XCTAssertEqual(m.currentID, 42)
    }

    /// 신규 설치 기본 언어는 시스템 로케일에서 유추 — 유효한 케이스이고 크래시 없음(한국어 강제 아님).
    func testSystemDefaultLanguageResolves() {
        XCTAssertTrue(AppLanguage.allCases.contains(AppLanguage.systemDefault))
        XCTAssertEqual(CompanionState().language, AppLanguage.systemDefault)
    }

    /// 부화/진화가 연출 트리거(celebrationSeq)를 올리고, consume 후 비워지는지.
    func testCelebrationFiresOnHatchAndEvolve() async {
        let s = store(linear3, seed: 9)
        XCTAssertEqual(s.celebrationSeq, 0)
        await s.hatch(baseID: 1)
        XCTAssertEqual(s.celebrationSeq, 1)
        if case .hatch = s.celebration {} else { XCTFail("hatch 연출이어야 함: \(String(describing: s.celebration))") }
        s.consumeCelebration()
        XCTAssertNil(s.celebration)
        // 1단계 임계 도달 → 진화 연출
        let thr = PokemonBalance.phaseThreshold(rarity: .common, totalForms: 3, stageIndex: 0)
        s.applyUsage(thr)
        XCTAssertEqual(s.celebrationSeq, 2)
        XCTAssertEqual(s.celebration, .evolve)
    }

    /// [회귀] 라인 미로딩(재시작 직후/오프라인) 중 델타가 유실되지 않고 적립, 라인 로드 후 진화 판정.
    func testUsageAccruesWhileLineUnloadedThenEvolvesOnLoad() async {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("poke-\(UUID().uuidString).json")
        // 1차 스토어: 부화 후 저장
        let s1 = CompanionStore(provider: StubProvider(value: linear3), clock: { fixedNow },
                                fileURL: url, rng: SeededRNG(seed: 5))
        s1.tick()
        await s1.hatch(baseID: 1)
        XCTAssertNotNil(s1.state.active)

        // 2차 스토어(재시작 시뮬레이션): active 는 로드됐지만 currentLine 은 nil
        let s2 = CompanionStore(provider: StubProvider(value: linear3), clock: { fixedNow },
                                fileURL: url, rng: SeededRNG(seed: 5))
        XCTAssertNotNil(s2.state.active)
        XCTAssertNil(s2.currentLine)
        // 라인 없는 상태에서 stage0 임계(125M) 초과 델타 → 유실 없이 적립, 진화는 보류
        s2.applyUsage(300_000_000)
        XCTAssertEqual(s2.state.active?.usedAtStage, 300_000_000, "라인 미로딩 중 델타가 유실되면 안 된다")
        XCTAssertEqual(s2.state.active?.stageIndex, 0)
        // update → loadCurrentLine 완료 시 적립분으로 진화 판정(드레인)
        s2.tick()
        for _ in 0..<50 where s2.currentLine == nil { await Task.yield() }
        XCTAssertNotNil(s2.currentLine)
        XCTAssertEqual(s2.state.active?.stageIndex, 1, "라인 로드 후 적립분으로 진화해야 한다")
        XCTAssertEqual(s2.state.active?.usedAtStage, 300_000_000 - 125_000_000)   // 초과분 이월
    }

    /// [회귀] 구버전 상태가 GIF 미지원 후대 진화형까지 진행했어도, 라인 재로딩 시 마지막 지원 형태로
    /// 복구하고 단계 수를 현재 에셋 개수에 맞춘다. 그렇지 않으면 트리에서 현재 종을 못 찾아 성장이 멈춘다.
    func testLineLoadMigratesPersistedUnsupportedEvolution() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("poke-assets-\(UUID().uuidString).json")
        let json = #"{"economyVersion":2,"forcedResetVersion":1,"active":{"baseID":56,"pathIDs":[56,57,979],"stageIndex":2,"usedAtStage":123,"rarity":"common","totalForms":3},"dex":[]}"#
        try Data(json.utf8).write(to: url)
        let supportedLine = makeLine(base: 56, tree: node(56, [node(57, [node(979)])]))
        let s = CompanionStore(provider: StubProvider(value: supportedLine), clock: { fixedNow },
                               fileURL: url, rng: SeededRNG(seed: 5))

        s.tick()
        for _ in 0..<50 where s.currentLine == nil { await Task.yield() }

        XCTAssertNotNil(s.currentLine)
        XCTAssertEqual(s.state.active?.pathIDs, [56, 57])
        XCTAssertEqual(s.state.active?.plannedPathIDs, [56, 57])
        XCTAssertEqual(s.state.active?.stageIndex, 1)
        XCTAssertEqual(s.state.active?.totalForms, 2)
        XCTAssertEqual(s.state.active?.usedAtStage, 123)
    }

    /// [회귀] 부화 이월(overflow)로 즉시 진화해도 마지막 연출은 hatch(shiny) — evolve 가 버스트를 덮지 않는다.
    func testShinyBurstSurvivesOverflowEvolve() async {
        // hatchIfNeeded 경로: chooseBase(1) → shiny(2) → nature(3) 순 rng 소비. shiny 시드 탐색.
        func rollsShinyViaHatchIfNeeded(_ seed: UInt64) -> Bool {
            var r = SeededRNG(seed: seed)
            _ = r.next()   // chooseBase: 가중 선택 롤(정확히 1회)
            return r.next() % PokemonOdds.shinyDenominator == 0
        }
        var seed: UInt64?
        for s: UInt64 in 0..<20000 where rollsShinyViaHatchIfNeeded(s) { seed = s; break }
        guard let seed else { return XCTFail("shiny 시드 탐색 실패") }

        let s = store(linear3, seed: seed)
        // 알 임계 + stage0 임계 초과 생산분 → 부화 즉시 1회 진화하는 이월
        s.debugAccrue(135_000_000)
        await s.hatchIfNeeded()
        XCTAssertEqual(s.state.active?.isShiny, true)
        XCTAssertEqual(s.state.active?.stageIndex, 1, "이월로 1회 진화했어야 함")
        XCTAssertEqual(s.celebration, .hatch(shiny: true), "evolve 가 shiny 부화 버스트를 덮으면 안 된다")
    }

    /// [회귀] 이월이 졸업 총량을 넘어 부화 즉시 졸업한 극단 케이스 — hatch 연출은 생략(이미 도감행).
    /// [갱신] 원래는 "부화 즉시 오버플로로 졸업까지 이어지면 떠난 mon 의 hatch 연출이 남으면
    /// 안 된다"는 회귀 가드였다(hatch() 의 `if state.active != nil { fireCelebration(.hatch) }`
    /// 방어). 레벨 30 게이트(#19) 도입 이후 무진화 종도 부화 직후엔 항상 레벨 1이라 그 즉시
    /// 졸업은 더 이상 일어나지 않는다 — 원래 시나리오 자체가 재현 불가능해졌다. 대신 정상 경로에서
    /// hatch 연출이 뜨는지, 그리고 그 연출을 사용자가 아직 못 본 채로 이후 졸업이 나도 조용히
    /// 지워지지 않는지(소비 전 연출을 다른 이벤트가 덮어쓰면 안 된다)를 확인한다.
    func testHatchCelebrationSurvivesUntilConsumedEvenAfterGraduation() async {
        let s = store(noEvo, seed: 11)
        // 알 임계 + 졸업 총량(750M) 초과 생산분 — usedAtStage 는 즉시 임계를 넘지만 레벨은 아직 1.
        s.debugAccrue(800_000_000)
        await s.hatchIfNeeded()
        XCTAssertNotNil(s.state.active, "레벨 게이트 때문에 부화 즉시 졸업은 더 이상 일어나지 않는다")
        guard case .hatch = s.celebration else {
            return XCTFail("정상 부화 연출이 떠야 한다: \(String(describing: s.celebration))")
        }
        s.debugAccrueLevelExperience(300_000_000)   // 레벨 30 도달 → 졸업 가능
        XCTAssertTrue(s.graduateCompanion(), "졸업은 사용자가 직접 누른다(#19)")
        XCTAssertNil(s.state.active, "졸업")
        XCTAssertEqual(s.state.dex.count, 1)
        guard case .hatch = s.celebration else {
            return XCTFail("소비 전 hatch 연출을 졸업이 덮어쓰면 안 된다: \(String(describing: s.celebration))")
        }
    }

    // MARK: 부화 샘플러 (PokéAPI rejection sampling — 하드코딩 풀 대체)

    private func samplerStore(_ provider: any PokeProviding, seed: UInt64,
                              preloadState: CompanionState? = nil) -> CompanionStore {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("poke-\(UUID().uuidString).json")
        if let st = preloadState, let data = try? JSONEncoder().encode(st) { try? data.write(to: url) }
        return CompanionStore(provider: provider, clock: { fixedNow }, fileURL: url, rng: SeededRNG(seed: seed))
    }

    /// 알을 임계 이상으로 채운 상태 — rng 미소비 경로.
    private func eggReadyState(collected: Set<String> = []) -> CompanionState {
        var st = CompanionState()
        st.eggUsage = PokemonBalance.eggHatchThreshold + 1
        st.collectedFinals = collected
        return st
    }

    /// 누적 가중 선택이 결정적이다 — 정확히 1롤, 롤 값이 가중 구간에 매핑.
    func testSamplerWeightedPickDeterministic() async {
        let index = [BaseSpecies(id: 10, captureRate: 100),
                     BaseSpecies(id: 20, captureRate: 100),
                     BaseSpecies(id: 30, captureRate: 100)]
        for seed: UInt64 in [1, 7, 42, 999] {
            var r = SeededRNG(seed: seed)
            let roll = Int(r.next() % 300)
            let expected = index[roll / 100].id      // 구간: [0,100)→10, [100,200)→20, [200,300)→30
            let p = IndexProvider(); p.index = index
            let s = samplerStore(p, seed: seed, preloadState: eggReadyState())
            await s.hatchIfNeeded()
            XCTAssertEqual(s.state.active?.baseID, expected, "seed \(seed) roll \(roll)")
        }
    }

    /// capture_rate 가 곧 가중치 — cr 비율만큼 선택 구간이 좁아진다 (희귀種 낮은 확률).
    func testSamplerCaptureRateIsWeight() async {
        // [common 254, legendary 2] → roll 0..253 → common, 254..255 → legendary
        let index = [BaseSpecies(id: 100, captureRate: 254), BaseSpecies(id: 200, captureRate: 2)]
        var legendarySeed: UInt64?, commonSeed: UInt64?
        for seed: UInt64 in 0..<3000 {
            var r = SeededRNG(seed: seed)
            let roll = Int(r.next() % 256)
            if roll >= 254, legendarySeed == nil { legendarySeed = seed }
            if roll < 254, commonSeed == nil { commonSeed = seed }
            if legendarySeed != nil, commonSeed != nil { break }
        }
        for (seed, expected) in [(commonSeed!, 100), (legendarySeed!, 200)] {
            let p = IndexProvider(); p.index = index
            let s = samplerStore(p, seed: seed, preloadState: eggReadyState())
            await s.hatchIfNeeded()
            XCTAssertEqual(s.state.active?.baseID, expected)
        }
    }

    /// 이미 수집한 base 는 가중치 ½ — 경계 롤에서 선택 구간이 바뀌는 것으로 검증.
    func testSamplerHalvesCollectedWeight() async {
        // 미수집: [200, 200] → 경계 200. id=1 수집 시: [100, 200] → 경계 100.
        // roll ∈ [100, 200) 인 시드는 수집 전엔 id=1, 수집 후엔 id=2 를 뽑는다.
        let index = [BaseSpecies(id: 1, captureRate: 200), BaseSpecies(id: 2, captureRate: 200)]
        // 같은 시드 → 같은 원시 롤값 v. 미수집 총합 400 / 수집 후 총합 300 으로 모듈로만 달라진다.
        // v%400 < 200 (미수집 → id=1) 이면서 v%300 ≥ 100 (수집 후 → id=2) 인 시드를 찾는다.
        var found: UInt64?
        for seed: UInt64 in 0..<5000 {
            var r = SeededRNG(seed: seed)
            let v = r.next()
            if v % 400 < 200, v % 300 >= 100 { found = seed; break }
        }
        guard let seed = found else { return XCTFail("시드 탐색 실패") }
        // 수집 전: id=1 구간
        let p1 = IndexProvider(); p1.index = index
        let s1 = samplerStore(p1, seed: seed, preloadState: eggReadyState())
        await s1.hatchIfNeeded()
        XCTAssertEqual(s1.state.active?.baseID, 1)
        // id=1 수집 후: 같은 시드가 id=2 구간으로 밀림 (가중치 ½ 효과)
        let p2 = IndexProvider(); p2.index = index
        let s2 = samplerStore(p2, seed: seed, preloadState: eggReadyState(collected: ["1:1"]))
        await s2.hatchIfNeeded()
        XCTAssertEqual(s2.state.active?.baseID, 2, "수집済 가중치 ½ 로 선택 구간이 이동해야 한다")
    }

    /// 알 상태 프리패칭 — update 틱에 종이 pre-roll 되어 영속되고, 부화는 pending 을 그대로 사용.
    func testEggPrefetchStoresPendingAndHatchUsesIt() async {
        let p = IndexProvider()
        p.index = [BaseSpecies(id: 77, captureRate: 255)]
        var state = CompanionState()
        state.starterChosen = true
        let s = samplerStore(p, seed: 5, preloadState: state)
        // 임계 미만(알 진행 0) → 부화는 안 되지만 update 틱이 프리패칭을 돌려야 한다
        s.tick()
        let prefetched = await waitUntil { s.state.pendingHatchID == 77 }
        XCTAssertTrue(prefetched, "알 상태에서 종이 미리 롤/저장돼야 한다")
        // 임계 도달(생산 적립) → 부화는 pending 그대로 (추가 선택 롤 없음: shiny/nature 만 소비)
        s.debugAccrue(6_000_000)
        await s.hatchIfNeeded()
        XCTAssertEqual(s.state.active?.baseID, 77)
        XCTAssertNil(s.state.pendingHatchID, "부화 후 pending 은 비워져야 한다")
        XCTAssertNotNil(s.state.active?.nature)
    }

    /// 프리패칭이 오프라인으로 실패해도 부화 시점 롤로 폴백 — 알이 막히지 않는다.
    func testPrefetchOfflineFallsBackToHatchTimeRoll() async {
        let p = IndexProvider()
        p.index = [BaseSpecies(id: 88, captureRate: 255)]
        p.failAll = true
        let s = samplerStore(p, seed: 9, preloadState: eggReadyState())
        s.tick()
        for _ in 0..<10 { await Task.yield() }        // 프리패치 시도 소진(실패)
        XCTAssertNil(s.state.pendingHatchID)
        await s.hatchIfNeeded()                        // 여전히 오프라인 → 알 유지
        XCTAssertNil(s.state.active)
        p.failAll = false                              // 네트워크 복구
        // 초기 update() 가 띄운 프리패치 Task 가 아직 in-flight 면 hatchIfNeeded 가 prefetchInFlight
        // 가드로 조기 반환할 수 있다(고정 yield 횟수로는 CI 스케줄 지연에서 못 소진 — 플래키 원인).
        // 부화할 때까지 재시도해 결정적으로 만든다(in-flight 는 몇 틱 내 실패로 해제됨).
        for _ in 0..<50 where s.state.active == nil {
            await s.hatchIfNeeded()                    // 부화 시점 롤 폴백
            await Task.yield()
        }
        XCTAssertEqual(s.state.active?.baseID, 88)
    }

    /// 오프라인(인덱스 취득 실패) — 알 진행 보존, isHatching 해제, 다음 틱 재시도 가능.
    func testSamplerOfflineKeepsEgg() async {
        let p = IndexProvider()
        p.failAll = true
        let s = samplerStore(p, seed: 1, preloadState: eggReadyState())
        await s.hatchIfNeeded()
        XCTAssertNil(s.state.active)
        XCTAssertGreaterThanOrEqual(s.state.eggUsage, PokemonBalance.eggHatchThreshold, "알 진행 보존")
        XCTAssertFalse(s.isHatching)
    }

    /// 스프라이트 캐시 키 — 정적 키는 기존 형식, 애니메이션은 showdown 전용 네임스페이스.
    func testSpriteCacheKeyScheme() {
        XCTAssertEqual(SpriteStore.cacheKey(speciesID: 25, animated: true, shiny: false), "25-showdown-normal")
        XCTAssertEqual(SpriteStore.cacheKey(speciesID: 25, animated: false, shiny: false), "25-s")
        XCTAssertEqual(SpriteStore.cacheKey(speciesID: 25, animated: true, shiny: true), "25-showdown-shiny")
        XCTAssertEqual(SpriteStore.cacheKey(speciesID: 25, animated: false, shiny: true), "25-shs")
    }

    /// 성격 25종 — 3개 언어 명칭이 전부 비어있지 않고 중복 없는지.
    func testNatureNamesComplete() {
        XCTAssertEqual(PokemonNature.allCases.count, 25)
        for lang in AppLanguage.allCases {
            let names = PokemonNature.allCases.map { $0.name(lang) }
            XCTAssertEqual(Set(names).count, 25, "\(lang) 중복/누락")
            XCTAssertFalse(names.contains(where: \.isEmpty))
        }
    }
}

// MARK: PokéAPI SSRF 가드 (evolution_chain URL 검증 — 응답 변조 시 임의 호스트 fetch 방지)

final class PokeAPIGuardTests: XCTestCase {
    func testValidatedChainURLAcceptsPokeapiHttps() {
        XCTAssertNotNil(PokeAPIClient.validatedChainURL("https://pokeapi.co/api/v2/evolution-chain/1/"))
    }
    func testValidatedChainURLRejectsUntrusted() {
        XCTAssertNil(PokeAPIClient.validatedChainURL("https://evil.example.com/x"), "임의 호스트 거부(SSRF)")
        XCTAssertNil(PokeAPIClient.validatedChainURL("https://pokeapi.co.evil.com/x"), "유사 호스트 거부")
        XCTAssertNil(PokeAPIClient.validatedChainURL("http://pokeapi.co/x"), "http 거부(https 고정)")
        XCTAssertNil(PokeAPIClient.validatedChainURL(""), "빈 문자열 거부")
    }
}

/// 출전 팀 고르기 — `BattleCenter` 가 `@MainActor` 라 이 클래스도 그래야 한다.
/// (예전엔 이 테스트들이 `PokeAPIGuardTests` 안에 있었다. 파일 끝에 덧붙이면 마지막 클래스에
///  딸려 들어가는데, 그쪽은 격리가 없어 `toggleTeamPick` 호출이 컴파일되지 않았다.)
@MainActor
private final class BattleCenterReference {
    weak var value: BattleCenter?
}

@MainActor
final class BattleTeamPickTests: XCTestCase {
    private let testMove = MoveSpec(id: 33, names: ["ko": "몸통박치기"], type: .normal,
                                    power: 40, damageClass: .physical, accuracy: 100, pp: 35)

    private func teamPickCenter(monCount: Int) -> (center: BattleCenter, mons: [MonState]) {
        let (store, mons) = teamPickStore(monCount: monCount)
        return (BattleCenter(companion: store), mons)
    }

    private func teamPickStore(monCount: Int) -> (store: CompanionStore, mons: [MonState]) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("poke-\(UUID().uuidString).json")
        let store = CompanionStore(provider: StubProvider(value: noEvo), clock: { fixedNow },
                                   fileURL: url, rng: SeededRNG(seed: 7))
        store.debugSetBoxedMons((0..<monCount).map { index in
            MonState(baseID: 20 + index, pathIDs: [20 + index], plannedPathIDs: [20 + index],
                     stageIndex: 0, usedAtStage: 0, rarity: .common, totalForms: 1)
        })
        return (store, store.ownedMons)
    }

    private func snapshot(for mon: MonState, level: Int) -> BattleSnapshot {
        BattleSnapshot(speciesID: mon.currentID, name: mon.nickname ?? "#\(mon.currentID)",
                       trainer: "Tester", level: level, nature: mon.nature, isShiny: mon.isShiny,
                       types: [.normal], base: BattleStats(hp: 50, atk: 50, def: 50, spa: 50, spd: 50, spe: 50),
                       moves: mon.learnedMoves.isEmpty ? [testMove] : mon.learnedMoves)
    }

    private func battleCenter(store: CompanionStore,
                              builder: BattleCenter.MonSnapshotBuilder? = nil) -> BattleCenter {
        BattleCenter(
            companion: store,
            monSnapshotBuilder: builder ?? { [self] mon, level in snapshot(for: mon, level: level) },
            battleProfileLoader: { id in
                PokemonBattleProfile(speciesID: id,
                                     stats: BattleStats(hp: 50, atk: 50, def: 50, spa: 50, spd: 50, spe: 50),
                                     types: [.normal])
            },
            moveSetLoader: { [testMove] _, _, _ in [testMove] },
            moveDetailLoader: { [testMove] _ in testMove }
        )
    }

    /// 아무것도 고르지 않으면 예전 그대로 소유 목록 앞에서 채운다 — 고르는 화면이 생겼다고
    /// 매번 골라야만 시작할 수 있게 되면 안 된다.
    func testUnpickedTeamStillFillsFromTheTopOfTheList() {
        let (center, _) = teamPickCenter(monCount: 6)
        center.rankedTeamSize = 3

        XCTAssertEqual(center.battleTeamMons.map(\.baseID), [20, 21, 22])
    }

    /// 고른 순서가 곧 출전 순서다 — 첫 번째가 선봉.
    func testPickedOrderIsTheBattleOrder() {
        let (center, mons) = teamPickCenter(monCount: 6)
        center.rankedTeamSize = 3

        center.toggleTeamPick(mons[4].id)
        center.toggleTeamPick(mons[1].id)
        center.toggleTeamPick(mons[3].id)

        XCTAssertEqual(center.battleTeamMons.map(\.baseID), [24, 21, 23])
    }

    /// 정원이 차면 더 받지 않는다. 앞을 밀어내면 애써 정한 순서가 조용히 바뀐다.
    func testPickingBeyondTheTeamSizeIsIgnored() {
        let (center, mons) = teamPickCenter(monCount: 6)
        center.rankedTeamSize = 2

        center.toggleTeamPick(mons[0].id)
        center.toggleTeamPick(mons[1].id)
        center.toggleTeamPick(mons[2].id)

        XCTAssertEqual(center.pickedTeam.count, 2)
        XCTAssertEqual(center.battleTeamMons.map(\.baseID), [20, 21])
    }

    /// 같은 칩을 다시 누르면 빠진다 — 넣기만 되고 빼기가 안 되면 다시 고를 방법이 없다.
    func testTappingAPickedMonRemovesIt() {
        let (center, mons) = teamPickCenter(monCount: 6)
        center.rankedTeamSize = 3
        center.toggleTeamPick(mons[0].id)
        center.toggleTeamPick(mons[1].id)

        center.toggleTeamPick(mons[0].id)

        XCTAssertEqual(center.pickedTeam, [mons[1].id])
    }

    /// 정원보다 적게 골라도 배틀은 성립한다 — 남는 자리는 소유 순서로 채운다.
    /// 고른 것이 앞에 서고, 이미 고른 개체가 뒤쪽 채움에 다시 끼면 안 된다.
    func testPartialPickFillsTheRestWithoutDuplicating() {
        let (center, mons) = teamPickCenter(monCount: 6)
        center.rankedTeamSize = 3

        center.toggleTeamPick(mons[5].id)

        XCTAssertEqual(center.battleTeamMons.map(\.baseID), [25, 20, 21])
    }

    /// 저장돼 있지 않은 선택은 건너뛰고, 같은 UUID 가 중복돼도 한 번만 출전한다.
    func testDeletedAndDuplicatePicksAreSkippedWithoutLosingOrder() {
        let (center, mons) = teamPickCenter(monCount: 6)
        center.rankedTeamSize = 3
        center.pickedTeam = [UUID(), mons[4].id, mons[4].id]

        XCTAssertEqual(center.battleTeamMons.map(\.id), [mons[4].id, mons[0].id, mons[1].id])
    }

    /// 중복 방지는 종 번호가 아니라 개체 UUID 기준이다. 같은 종 두 마리는 둘 다 팀에 들 수 있다.
    func testDistinctMonsOfTheSameSpeciesCanBothBattle() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("poke-\(UUID()).json")
        let store = CompanionStore(provider: StubProvider(value: noEvo), clock: { fixedNow },
                                   fileURL: url, rng: SeededRNG(seed: 7))
        let first = MonState(baseID: 20, pathIDs: [20], stageIndex: 0, usedAtStage: 0,
                             rarity: .common, totalForms: 1)
        let second = MonState(baseID: 20, pathIDs: [20], stageIndex: 0, usedAtStage: 0,
                              rarity: .common, totalForms: 1)
        store.debugSetBoxedMons([first, second])
        let center = BattleCenter(companion: store)
        center.rankedTeamSize = 2
        center.pickedTeam = [second.id, first.id]

        XCTAssertEqual(center.battleTeamMons.map(\.id), [second.id, first.id])
    }

    func testSupportedTeamSizesPreserveSelectionAndAutofill() {
        for size in [1, 3, 6] {
            let (center, mons) = teamPickCenter(monCount: 6)
            center.rankedTeamSize = size
            center.pickedTeam = [mons[5].id, mons[2].id]

            let expected = Array(([mons[5], mons[2]] + mons.filter { ![mons[5].id, mons[2].id].contains($0.id) })
                .prefix(size)).map(\.id)
            XCTAssertEqual(center.battleTeamMons.map(\.id), expected, "team size \(size)")
        }
    }

    func testRankedLineupBuildsEverySupportedSizeInTheChosenOrder() async {
        let (store, mons) = teamPickStore(monCount: 6)
        let center = battleCenter(store: store)
        center.pickedTeam = [mons[5].id, mons[2].id]

        for size in [1, 3, 6] {
            let lineup = await center.buildMyLineup(size: size, levelOverride: 50)
            let expected = Array(([mons[5], mons[2]]
                + mons.filter { ![mons[5].id, mons[2].id].contains($0.id) }).prefix(size))
            XCTAssertEqual(lineup?.map(\.speciesID), expected.map(\.currentID), "team size \(size)")
            XCTAssertEqual(lineup?.map(\.level), Array(repeating: 50, count: size))
            XCTAssertTrue(lineup?.allSatisfy { !($0.trainer ?? "").isEmpty } == true)
        }
    }

    func testIncomingDraftDoesNotChangeSharedSelectionUntilCommitted() {
        let (center, mons) = teamPickCenter(monCount: 6)
        center.pickedTeam = [mons[4].id, mons[1].id, mons[5].id]

        center.prepareIncomingSelection(teamSize: 3)
        center.incomingPickedTeam = [mons[2].id]
        let confirmed = center.resolvedTeamIDs(size: 3, selection: center.incomingPickedTeam)
        XCTAssertEqual(center.pickedTeam, [mons[4].id, mons[1].id, mons[5].id],
                       "초안 편집은 기존 공용 순서를 덮어쓰지 않는다")
        XCTAssertEqual(confirmed, [mons[2].id, mons[0].id, mons[1].id],
                       "빈 슬롯은 소유 목록 순서로 보충된다")

        center.discardIncomingSelection()
        XCTAssertTrue(center.incomingPickedTeam.isEmpty)
        XCTAssertEqual(center.pickedTeam, [mons[4].id, mons[1].id, mons[5].id],
                       "거절/연결 종료에 해당하는 폐기는 공용 순서를 보존한다")

        center.commitIncomingSelection(confirmed)
        XCTAssertEqual(Array(center.pickedTeam.prefix(3)), confirmed,
                       "수락 확정 때만 실제 출전 순서가 공용 앞부분에 반영된다")
    }

    /// 신청자도 파티 편성 화면의 초안을 사용해야 한다. 예전에는 확인 화면이 이 배열을 바꿔도
    /// `confirmBattleTeam`이 오래된 `pickedTeam`을 읽어 다른 포켓몬이 선봉으로 나갔다.
    func testConfirmedBattleTeamUsesTheVisibleDraftInsteadOfTheOldSharedSelection() {
        let (center, mons) = teamPickCenter(monCount: 6)
        center.pickedTeam = [mons[0].id, mons[1].id, mons[2].id]
        center.incomingPickedTeam = [mons[5].id, mons[4].id, mons[3].id]

        let confirmed = center.confirmedBattleTeamIDs(size: 3)

        XCTAssertEqual(confirmed, [mons[5].id, mons[4].id, mons[3].id])
        XCTAssertNotEqual(confirmed, Array(center.pickedTeam.prefix(3)))
    }

    /// 스냅샷 조회가 await 하는 사이 선택이 바뀌어도, 시작할 때 확정한 배열을 끝까지 쓴다.
    func testSnapshotPreparationFreezesInitialOrder() async {
        let (store, mons) = teamPickStore(monCount: 6)
        let reference = BattleCenterReference()
        var callCount = 0
        let center = battleCenter(store: store) { [self] mon, level in
            callCount += 1
            if callCount == 1 { reference.value?.pickedTeam = [mons[0].id, mons[1].id, mons[2].id] }
            await Task.yield()
            return snapshot(for: mon, level: level)
        }
        reference.value = center
        center.rankedTeamSize = 3
        center.pickedTeam = [mons[4].id, mons[1].id, mons[3].id]

        let snapshots = await center.battleTeamSnapshots(size: 3)

        XCTAssertEqual(snapshots?.map(\.speciesID), [24, 21, 23])
    }

    /// 계승 기술 복원 뒤 앞 슬롯을 준비하는 동안 동행이 바뀌어도, 뒤 슬롯의 원래 활성 개체는
    /// UUID 로 고정해 둔 복원본을 사용해야 한다.
    func testRestoredInheritedMovesSurviveCompanionSwitchDuringSnapshotPreparation() async {
        let (store, _) = teamPickStore(monCount: 0)
        await store.hatch(baseID: 20)
        guard let originalActive = store.state.active else { return XCTFail("active mon missing") }
        let lead = MonState(baseID: 21, pathIDs: [21], stageIndex: 0, usedAtStage: 0,
                            rarity: .common, totalForms: 1)
        store.debugSetBoxedMons([lead])
        let restoredMove = MoveSpec(id: 98, names: ["ko": "전광석화"], type: .normal,
                                    power: 40, damageClass: .physical, accuracy: 100, pp: 30)
        let center = BattleCenter(
            companion: store,
            monSnapshotBuilder: { [self] mon, level in
                if mon.id == lead.id {
                    store.switchCompanion(to: lead.id)
                    await Task.yield()
                }
                return snapshot(for: mon, level: level)
            },
            inheritedMovesPreparer: {
                store.debugSetActiveLearnedMoves([restoredMove])
            }
        )
        center.pickedTeam = [lead.id]

        let snapshots = await center.battleTeamSnapshots(size: 2)

        XCTAssertEqual(store.activeMonID, lead.id, "첫 슬롯 준비 중 실제 동행이 교체돼야 경합을 재현한다")
        XCTAssertTrue(store.boxedMons.contains { $0.id == originalActive.id })
        XCTAssertEqual(snapshots?.map(\.speciesID), [21, 20])
        XCTAssertEqual(snapshots?[1].moves, [restoredMove])
    }

    /// CPU 모의전의 실제 상태가 선택 배열을 그대로 받고 0번을 선봉으로 시작한다.
    func testPracticeBattleUsesPickedSnapshotOrderAndLead() async {
        let (store, mons) = teamPickStore(monCount: 6)
        let center = battleCenter(store: store)
        center.rankedTeamSize = 3
        center.pickedTeam = [mons[4].id, mons[1].id, mons[3].id]

        center.startRankedPractice()
        let started = await waitUntil { center.phase == .battling }
        XCTAssertTrue(started)

        XCTAssertEqual(center.teamPractice?.mine.map(\.snapshot.speciesID), [24, 21, 23])
        XCTAssertEqual(center.teamPractice?.mySlot.snapshot.speciesID, 24)
        XCTAssertEqual(center.teamPractice?.myActive, 0)
    }

    /// 승부가 난 마지막 턴은 **재생 뒤에** 결과 화면으로 넘어간다. 이벤트 append 와
    /// `phase = .finished` 가 같은 동기 블록이면 SwiftUI 는 한 번만 다시 그리므로 arena 가
    /// 마지막 배치를 한 프레임도 못 보고, 결정타·기절이 결과 화면으로 스냅한다 — 재생기가 생긴
    /// 이유가 바로 그 턴이다(리뷰 #2).
    func testTheDecidingTurnWaitsForTheReplayBeforeShowingTheResult() async {
        let (store, mons) = teamPickStore(monCount: 6)
        let center = battleCenter(store: store)
        center.rankedTeamSize = 1
        center.pickedTeam = [mons[0].id]

        center.startRankedPractice()
        let started = await waitUntil { center.phase == .battling }
        XCTAssertTrue(started)

        // CPU 의 rng 는 seed 고정이 아니라 턴 수를 못 박을 수 없다 — 승부가 날 때까지 돈다.
        for _ in 0..<500 where center.pendingFinish == nil {
            center.chooseTeamPracticeMove(0)
        }

        XCTAssertNotNil(center.pendingFinish, "500턴 안에 승부가 안 났다면 픽스처가 잘못됐다")
        XCTAssertEqual(center.phase, .battling,
                       "결과 화면으로 먼저 스냅하면 결정타·기절이 재생되지 않는다")

        center.commitPendingFinish()
        guard case .finished = center.phase else {
            return XCTFail("재생이 끝났는데 결과 화면으로 넘어가지 않았다")
        }
        XCTAssertNil(center.pendingFinish, "미뤄 둔 결과가 남으면 다음 배틀에서 뒤늦게 튀어나온다")
    }

    /// 항복·새 배틀이 먼저 국면을 옮겼으면 미뤄 둔 결과는 버린다 — 안 버리면 재생기의 뒤늦은
    /// 알림(또는 마감 타이머)이 항복 화면을 실제 결과로 덮어쓴다.
    func testAForfeitDuringTheDeferredWindowKeepsItsOwnResult() async {
        let (store, mons) = teamPickStore(monCount: 6)
        let center = battleCenter(store: store)
        center.rankedTeamSize = 1
        center.pickedTeam = [mons[0].id]

        center.startRankedPractice()
        let started = await waitUntil { center.phase == .battling }
        XCTAssertTrue(started)
        for _ in 0..<500 where center.pendingFinish == nil {
            center.chooseTeamPracticeMove(0)
        }
        XCTAssertNotNil(center.pendingFinish)

        center.forfeit()
        XCTAssertEqual(center.phase, .finished(iWon: false, byForfeit: true))
        XCTAssertNil(center.pendingFinish, "국면이 넘어간 뒤에도 남으면 항복 화면이 덮인다")

        center.commitPendingFinish()
        XCTAssertEqual(center.phase, .finished(iWon: false, byForfeit: true),
                       "뒤늦은 알림이 항복 결과를 갈아치웠다")
    }

    /// 체육관도 동일한 공용 배열을 쓰며 첫 선택이 진입 직후 선봉이다.
    func testGymBattleUsesPickedSnapshotOrderAndLead() async {
        let (store, mons) = teamPickStore(monCount: 6)
        let center = battleCenter(store: store)
        center.rankedTeamSize = 6
        center.pickedTeam = [mons[5].id, mons[2].id, mons[4].id]

        center.startGymChallenge(GymLeague.catalog[0])
        let started = await waitUntil { center.phase == .battling }
        XCTAssertTrue(started)

        XCTAssertEqual(center.teamPractice?.mine.map(\.snapshot.speciesID), [25, 22, 24])
        XCTAssertEqual(center.teamPractice?.mySlot.snapshot.speciesID, 25)
        XCTAssertEqual(center.teamPractice?.myActive, 0)
    }

    /// 근거리 랭크 스냅샷은 현재 파트너가 아니라 선택 1번의 개체 정보를 Lv.50 으로 쓴다.
    /// 도전 송신과 수락은 모두 이 메서드를 호출하므로 연속 두 준비에서도 같은 결과인지 확인한다.
    func testRankedSnapshotUsesFirstPickMetadataForChallengeAndAccept() async {
        let (store, _) = teamPickStore(monCount: 0)
        await store.hatch(baseID: 20)
        guard let activeID = store.activeMonID else { return XCTFail("active mon missing") }
        var chosen = MonState(baseID: 21, pathIDs: [21], stageIndex: 0, usedAtStage: 0,
                              rarity: .rare, totalForms: 1, isShiny: true, nature: .adamant,
                              nickname: "선택한 개체")
        chosen.learnedMoves = [testMove]
        store.debugSetBoxedMons([chosen])
        let center = battleCenter(store: store)
        center.pickedTeam = [chosen.id]

        let challengeSnapshot = await center.buildMySnapshot(levelOverride: 50)
        let acceptSnapshot = await center.buildMySnapshot(levelOverride: 50)

        XCTAssertNotEqual(chosen.id, activeID)
        for result in [challengeSnapshot, acceptSnapshot] {
            XCTAssertEqual(result?.speciesID, 21)
            XCTAssertEqual(result?.name, "선택한 개체")
            XCTAssertEqual(result?.level, 50)
            XCTAssertEqual(result?.nature, .adamant)
            XCTAssertEqual(result?.isShiny, true)
            XCTAssertEqual(result?.moves, [testMove])
        }
    }
}
