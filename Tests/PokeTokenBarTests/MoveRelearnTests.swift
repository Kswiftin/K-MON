import XCTest
@testable import PokeTokenBar

// MARK: 하트비늘 후보 계산 (#97) — 순수 로직

final class MoveRelearnTests: XCTestCase {
    private func move(_ id: Int) -> MoveSpec {
        MoveSpec(id: id, names: ["en": "m\(id)"], type: .normal, power: 40,
                 damageClass: .physical, accuracy: 100, pp: 35)
    }

    /// 이미 배운 기술은 후보에서 빠진다 — 고르면 아무 일도 안 나는 선택지를 내놓지 않는다.
    func testCandidatesExcludeAlreadyKnownMoves() {
        let out = MoveRelearn.candidates(inherited: [[move(1), move(2), move(3)]],
                                         learned: [move(2)])
        XCTAssertEqual(out.map(\.id), [1, 3])
    }

    /// 진화 경로 여러 종의 목록을 합치고 같은 기술은 한 번만 — 지난 단계에서 놓친 기술 회수가 목적이다.
    func testCandidatesUnionAcrossEvolutionPathAndDedupeByID() {
        let out = MoveRelearn.candidates(inherited: [[move(5), move(1)], [move(1), move(9)]],
                                         learned: [])
        XCTAssertEqual(out.map(\.id), [1, 5, 9], "id 오름차순 + 중복 제거")
    }

    /// 정렬이 입력 순서에 흔들리지 않는다(조회 완료 순서가 매번 다르다).
    func testCandidateOrderIsIndependentOfInputOrder() {
        let a = MoveRelearn.candidates(inherited: [[move(9), move(3)], [move(7)]], learned: [])
        let b = MoveRelearn.candidates(inherited: [[move(7)], [move(3), move(9)]], learned: [])
        XCTAssertEqual(a.map(\.id), b.map(\.id))
        XCTAssertEqual(a.map(\.id), [3, 7, 9])
    }

    func testCandidatesEmptyWhenEverythingKnown() {
        XCTAssertTrue(MoveRelearn.candidates(inherited: [[move(1)]], learned: [move(1)]).isEmpty)
    }

    func testCandidatesEmptyInputs() {
        XCTAssertTrue(MoveRelearn.candidates(inherited: [], learned: []).isEmpty)
        XCTAssertTrue(MoveRelearn.candidates(inherited: [[]], learned: [move(1)]).isEmpty)
    }

    // MARK: 아이템 정의

    /// 하트비늘은 진화 아이템이 아니다 — 여기가 무너지면 가방·상점의 진화 분기로 흘러간다.
    func testHeartScaleIsNotAnEvolutionItem() {
        XCTAssertNil(ItemKind.heartScale.evolutionRule)
        XCTAssertFalse(ItemKind.heartScale.isEvolutionItem)
        XCTAssertFalse(ItemKind.heartScale.isPassive)
    }

    func testHeartScaleShopPriceComesFromMoveRelearn() {
        XCTAssertEqual(ItemKind.heartScale.shopPrice, MoveRelearn.price)
        XCTAssertEqual(MoveRelearn.price, 500)
    }

    func testHeartScaleHasItsOwnSpriteAndEmoji() {
        XCTAssertEqual(ItemKind.heartScale.spriteName, "heart-scale")
        XCTAssertEqual(ItemKind.heartScale.emoji, "💗")
    }
}
