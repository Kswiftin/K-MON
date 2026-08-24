import XCTest
@testable import PokeTokenBar

// MARK: 하트비늘 (기술 다시 배우기 — #97) — 소모 시점·출처 분기

/// 라인 로딩 없는 provider — 하트비늘은 currentLine 과 무관(pathIDs·level 은 MonState 에 있다).
private struct HeartScaleNoProvider: PokeProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine { throw URLError(.notConnectedToInternet) }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
}

@MainActor
final class HeartScaleTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func move(_ id: Int) -> MoveSpec {
        MoveSpec(id: id, names: ["en": "m\(id)"], type: .normal, power: 40,
                 damageClass: .physical, accuracy: 100, pp: 35)
    }

    /// 활성 포켓몬 + 학습 기술 + 하트비늘 재고를 지정한 세이브.
    private func store(scales: Int = 1, learned: [Int] = [11, 22]) -> CompanionStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("heart-\(UUID().uuidString).json")
        let moves = learned.map {
            "{\"id\":\($0),\"names\":{\"en\":\"m\($0)\"},\"type\":\"normal\",\"power\":40,"
            + "\"damageClass\":\"physical\",\"accuracy\":100,\"pp\":35}"
        }.joined(separator: ",")
        let active = "{\"baseID\":1,\"pathIDs\":[1],\"stageIndex\":0,\"usedAtStage\":50000000,"
            + "\"rarity\":\"common\",\"totalForms\":3,\"isShiny\":false,\"learnedMoves\":[\(moves)]}"
        let inv = scales > 0 ? ",\"inventory\":{\"heartScale\":\(scales)}" : ""
        let json = "{\"economyVersion\":2,\"forcedResetVersion\":1,\"starterChosen\":true,"
            + "\"installBaselineSet\":true,\"usedSinceInstall\":1000000000,\"spentTokens\":0,"
            + "\"starPieces\":1000000000,\"lastDate\":\"d\",\"active\":\(active),\"dex\":[],"
            + "\"collectedFinals\":[]\(inv)}"
        try? json.data(using: .utf8)!.write(to: url)
        return CompanionStore(provider: HeartScaleNoProvider(), clock: { self.now },
                              fileURL: url, rng: SeededRNG(seed: 7))
    }

    // MARK: 사용 가능 판정

    func testCannotUseWithoutStock() {
        XCTAssertFalse(store(scales: 0).canUseHeartScale)
        XCTAssertTrue(store(scales: 1).canUseHeartScale)
    }

    // MARK: 소모 시점 — "무브셋이 실제로 바뀔 때만"

    func testAcceptingRelearnConsumesOneScale() {
        let s = store(scales: 2, learned: [11, 22])
        s.debugPresentRelearnPrompt(candidates: [move(33)])
        s.pickRelearnCandidate(move(33))
        XCTAssertEqual(s.moveLearningPrompt?.origin, .heartScale)
        s.acceptMoveLearning()
        XCTAssertEqual(s.state.active?.learnedMoves.map(\.id), [11, 22, 33])
        XCTAssertEqual(s.itemCount(.heartScale), 1, "하트비늘 1개만 소모")
    }

    func testCancellingCandidateListConsumesNothing() {
        let s = store(scales: 1)
        s.debugPresentRelearnPrompt(candidates: [move(33)])
        s.cancelRelearn()
        XCTAssertNil(s.relearnPrompt)
        XCTAssertEqual(s.itemCount(.heartScale), 1, "목록 취소는 무소모")
    }

    func testDecliningReplacementConsumesNothing() {
        let s = store(scales: 1, learned: [11, 22, 33, 44])
        s.debugPresentRelearnPrompt(candidates: [move(55)])
        s.pickRelearnCandidate(move(55))
        s.declineMoveLearning()
        XCTAssertEqual(s.itemCount(.heartScale), 1, "교체 거절은 무소모")
        XCTAssertEqual(s.state.active?.learnedMoves.map(\.id), [11, 22, 33, 44])
    }

    func testFullMovesetReplacesAtIndexAndConsumes() {
        let s = store(scales: 1, learned: [11, 22, 33, 44])
        s.debugPresentRelearnPrompt(candidates: [move(55)])
        s.pickRelearnCandidate(move(55))
        s.acceptMoveLearning(replacing: 1)
        XCTAssertEqual(s.state.active?.learnedMoves.map(\.id), [11, 55, 33, 44])
        XCTAssertEqual(s.itemCount(.heartScale), 0)
    }

    /// 트리거 브랜치 — 범위 밖 인덱스는 무브셋을 안 바꾸므로 **소모도 없어야** 한다.
    func testOutOfRangeIndexChangesNothingAndConsumesNothing() {
        let s = store(scales: 1, learned: [11, 22, 33, 44])
        s.debugPresentRelearnPrompt(candidates: [move(55)])
        s.pickRelearnCandidate(move(55))
        s.acceptMoveLearning(replacing: 9)
        XCTAssertEqual(s.state.active?.learnedMoves.map(\.id), [11, 22, 33, 44])
        XCTAssertEqual(s.itemCount(.heartScale), 1)
    }

    /// 트리거 브랜치 — 4개 미만인데 인덱스가 와도 append 다(교체 인자를 무시하는 기존 동작).
    func testIndexIsIgnoredWhenMovesetHasRoom() {
        let s = store(scales: 1, learned: [11])
        s.debugPresentRelearnPrompt(candidates: [move(55)])
        s.pickRelearnCandidate(move(55))
        s.acceptMoveLearning(replacing: 0)
        XCTAssertEqual(s.state.active?.learnedMoves.map(\.id), [11, 55])
        XCTAssertEqual(s.itemCount(.heartScale), 0)
    }

    /// 트리거 브랜치 — 레벨업 유래 학습은 재고와 무관하다(하트비늘 차감이 새면 여기서 잡힌다).
    func testLevelUpOriginNeverTouchesInventory() {
        let s = store(scales: 1, learned: [11])
        s.debugPresentLevelUpPrompt(move: move(77), level: 12)
        XCTAssertEqual(s.moveLearningPrompt?.origin, .levelUp)
        s.acceptMoveLearning()
        XCTAssertEqual(s.state.active?.learnedMoves.map(\.id), [11, 77])
        XCTAssertEqual(s.itemCount(.heartScale), 1, "레벨업 학습은 하트비늘을 쓰지 않는다")
    }

    /// 카드가 떠 있는 동안 재고가 0 이 되면(다른 경로 소모) 고르기가 no-op 이어야 한다.
    func testPickIsNoOpWhenStockDisappeared() {
        let s = store(scales: 1)
        s.debugPresentRelearnPrompt(candidates: [move(33)])
        s.debugSetItemCount(.heartScale, 0)
        s.pickRelearnCandidate(move(33))
        XCTAssertNil(s.moveLearningPrompt, "재고 없이 학습 카드로 넘어가면 안 된다")
        XCTAssertNil(s.relearnPrompt)
    }

    /// 표시 목록도 함께 바뀐다 — 기술 목록의 `.task(id:)` 는 레벨이 안 바뀌면 다시 돌지 않는다.
    func testAcceptingRelearnUpdatesDisplayedMoves() {
        let s = store(scales: 1, learned: [11, 22])
        s.debugPresentRelearnPrompt(candidates: [move(33)])
        s.pickRelearnCandidate(move(33))
        s.acceptMoveLearning()
        XCTAssertEqual(s.displayedMoves.map(\.id), [11, 22, 33], "화면 목록이 옛 무브셋으로 남으면 안 된다")
    }

    // MARK: 진화 경로와의 격리

    /// 가방·상점의 진화 분기로 새지 않아야 한다 — `default:` 부류 회귀 가드.
    func testHeartScaleIsNotTreatedAsEvolutionItem() {
        let s = store(scales: 1)
        XCTAssertFalse(s.canUseEvolutionItem(.heartScale))
        XCTAssertFalse(s.useEvolutionItem(.heartScale))
        XCTAssertEqual(s.itemCount(.heartScale), 1, "진화 경로로 소모되면 안 된다")
    }

    /// 상점 구매 — 가격이 500 이고 재고가 늘어난다.
    func testBuyingHeartScaleCostsFiveHundred() {
        let s = store(scales: 0)
        let before = s.availableTokens
        XCTAssertTrue(s.canBuy(.heartScale))
        XCTAssertTrue(s.buy(.heartScale))
        XCTAssertEqual(s.itemCount(.heartScale), 1)
        XCTAssertEqual(s.availableTokens, before - 500)
    }

    // MARK: 문구 (ko/en/ja 전부)

    func testHeartScaleCopyExistsInAllThreeLanguages() {
        for lang in AppLanguage.allCases {
            let l = L(lang)
            XCTAssertFalse(l.itemName(.heartScale).isEmpty, "\(lang) 이름 누락")
            XCTAssertFalse(l.itemDescription(.heartScale).isEmpty, "\(lang) 설명 누락")
            XCTAssertFalse(l.heartScaleEffectHint.isEmpty)
            XCTAssertFalse(l.relearnPickTitle.isEmpty)
            XCTAssertFalse(l.relearnEmpty.isEmpty)
            XCTAssertFalse(l.relearnHeader.isEmpty)
            XCTAssertFalse(l.relearnLoading.isEmpty)
            XCTAssertFalse(l.relearnClose.isEmpty)
        }
        XCTAssertNotEqual(L(.ko).itemName(.heartScale), L(.en).itemName(.heartScale))
        XCTAssertNotEqual(L(.ko).itemDescription(.heartScale), L(.ja).itemDescription(.heartScale))
    }

    // MARK: 후보 개수 — 무브셋 상한을 물려받지 않는다

    /// **회귀 원본.** 후보 목록을 `canonicalLevelUpMoves` 로 만들던 동안 종당 4개만 보였다.
    /// 그 함수는 기술 칸 넷을 채우는 용도라 4개에서 멈추는데(`limit: 4`), 다시 배우기는
    /// 배울 수 있었던 것 **전부**에서 고르는 기능이다.
    ///
    /// 개수 상한은 네트워크 조회 루프 안에 있어 순수 함수로 잴 수 없다. 그래서 후보를 만드는
    /// 자리가 상한 없는 쪽(`levelUpMoveHistory`)을 부르는지 소스에서 본다.
    ///
    /// **주석은 뺀다.** 규칙을 설명하는 주석이 그 함수 이름을 담게 되고(실제로 이 수정의 설명
    /// 주석이 그랬다), 빼지 않으면 가드가 자기 설명에 걸려 빨간불이 된다 —
    /// `LanguageSplitGuardTests` 가 같은 이유로 주석을 뺀다.
    func testRelearnCandidatesAreNotBuiltFromTheCappedMovesetQuery() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/PokeTokenBar/Core/CompanionStore.swift")
        let code = try String(contentsOf: sources, encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                guard let comment = line.range(of: "//") else { return String(line) }
                return String(line[..<comment.lowerBound])
            }
            .joined(separator: "\n")
        let relearn = try XCTUnwrap(code.range(of: "MoveRelearn.candidates"))
        // 후보를 만드는 Task 안에서 어느 조회를 쓰는지 — 그 호출은 `candidates` 위에 있다.
        let above = code[..<relearn.lowerBound].suffix(1_200)
        XCTAssertTrue(above.contains("levelUpMoveHistory"),
                      "다시 배우기 후보는 상한 없는 조회로 만들어야 한다")
        XCTAssertFalse(above.contains("canonicalLevelUpMoves"),
                       "무브셋용 조회는 4개에서 끊긴다 — 후보가 그 상한을 물려받는다")
    }

    /// 두 조회가 갈라지지 않게 잠근다 — 무브셋에는 들어가는데 다시 배우기에는 안 뜨는 기술이
    /// 생기면 "왜 이건 못 배우지" 가 된다. 필터·정렬은 한 함수(`levelUpMoves`)가 공유한다.
    func testBothLevelUpQueriesShareOneFilterAndOrder() throws {
        let client = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/PokeTokenBar/Core/PokeAPIClient.swift")
        let text = try String(contentsOf: client, encoding: .utf8)
        XCTAssertTrue(text.contains("levelUpMoves(speciesID: speciesID, level: level, limit: 4)"))
        XCTAssertTrue(text.contains("levelUpMoves(speciesID: speciesID, level: level, limit: nil)"))
    }
}
