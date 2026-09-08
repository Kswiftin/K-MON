import XCTest
@testable import PokeTokenBar

// MARK: 지닌물건이 화면에 보이는 자리

/// 지닌물건 161종을 넣고도 **화면 어디에도 무엇을 지녔는지 나오지 않았다**(2026-09-08 리포트).
/// `heldItem` 을 읽는 UI 가 가방의 "이미 지니고 있어요" 문구 하나뿐이라, 개체에 붙은 물건을
/// 확인할 방법도 벗길 방법도 없었다 — 물건을 사서 주는 것까지만 되고 그 뒤가 비어 있었다.
///
/// 렌더 없이는 배치를 잴 수 없으므로, 표시 자리는 소스에서 확인한다(`RosterDetailPopoverTests`
/// 와 같은 방식). 판정 로직이 있는 배틀 배지는 값으로 검증한다.
final class HeldItemSurfaceTests: XCTestCase {

    private func source(_ path: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(path)
        return try String(contentsOf: url, encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                guard let comment = line.range(of: "//") else { return String(line) }
                return String(line[..<comment.lowerBound])
            }
            .joined(separator: "\n")
    }

    private func snapshot(held: ItemKind?) -> BattleSnapshot {
        BattleSnapshot(speciesID: 25, name: "테스트", trainer: nil, level: 50, nature: nil,
                       isShiny: false, types: [.normal],
                       base: BattleStats(hp: 100, atk: 100, def: 100, spa: 100, spd: 100, spe: 100),
                       moves: nil, heldItem: held, weightHectograms: 100)
    }

    // MARK: 배틀 칸

    /// 내 쪽 칸은 지금 쥔 물건을 이름으로 보여 준다 — 구애 계열처럼 **선택을 묶는** 물건이
    /// 붙어 있으면 기술이 왜 잠겼는지가 그 이름 없이는 읽히지 않는다.
    func testMySideShowsTheHeldItemName() {
        let badge = CombatantBar.heldItemBadge(side: BattleSide(snapshot(held: .choiceBand)),
                                               revealsExactHP: true, l: L())
        XCTAssertEqual(badge, L().itemName(.choiceBand))
    }

    /// 상대 쪽은 보여 주지 않는다 — 본가와 같은 규칙이고, 발동하면 로그 줄로 드러난다.
    /// 실수치 HP 를 감추는 것과 같은 판정을 쓴다(같은 "상대 정보" 축이다).
    func testTheirSideHidesTheHeldItem() {
        XCTAssertNil(CombatantBar.heldItemBadge(side: BattleSide(snapshot(held: .choiceBand)),
                                                revealsExactHP: false, l: L()))
    }

    /// 빈 손이면 자리를 만들지 않는다.
    func testAnEmptyHandHasNoBadge() {
        XCTAssertNil(CombatantBar.heldItemBadge(side: BattleSide(snapshot(held: nil)),
                                                revealsExactHP: true, l: L()))
    }

    /// 배틀 중 옮겨 붙은 물건(끈적끈적바늘)도 같은 자리에 나온다 — 스냅샷이 아니라 **지금 쥔 것**
    /// 을 묻는다(`BattleSide.activeHeldItem`).
    func testTheBadgeFollowsTheItemAcquiredMidBattle() {
        var side = BattleSide(snapshot(held: nil))
        side.acquiredItem = .stickyBarb
        XCTAssertEqual(CombatantBar.heldItemBadge(side: side, revealsExactHP: true, l: L()),
                       L().itemName(.stickyBarb))
    }

    /// 그 배지가 실제로 칸에 그려져 있어야 한다 — 헬퍼만 있고 뷰가 안 쓰면 화면은 그대로 빈다.
    func testTheBattleBarDrawsTheBadge() throws {
        XCTAssertTrue(try source("Sources/PokeTokenBar/UI/BattleField.swift")
            .contains("heldItemBadge(side: side, revealsExactHP: revealsExactHP, l: l)"))
    }

    // MARK: 소유 포켓몬 탭

    /// 상세 카드가 지닌물건과 그 효과를 그린다 — 효과 힌트(`heldItemEffectHint`)까지 있어야
    /// "무엇이 붙었나" 가 이름 추측 없이 읽힌다.
    func testTheDetailCardDrawsTheHeldItem() throws {
        let code = try source("Sources/PokeTokenBar/UI/PokemonRosterView.swift")
        XCTAssertTrue(code.contains("store.heldItem(of: mon)"),
                      "상세 카드가 정본(활성 개체는 세이브 값)을 읽지 않는다 — 벗겨도 화면이 그대로다")
        XCTAssertTrue(code.contains("heldItemEffectHint"), "효과 힌트가 없다")
        // **정의만 보면 안 된다** — 줄을 그리는 호출이 body 에서 빠져도 함수 본문의 문자열은
        // 그대로 남아 가드가 통과한다(이 파일의 첫 판이 실제로 그랬다). 정의 1 + 호출 1 을 센다.
        XCTAssertGreaterThanOrEqual(code.components(separatedBy: "heldItemRow()").count - 1, 2,
                                    "지닌물건 줄이 정의만 있고 어디서도 그려지지 않는다")
    }

    /// 벗기기 버튼이 상세 카드에 있다 — 스토어에 길만 있고 버튼이 없으면 여전히 벗을 수 없다.
    func testTheDetailCardOffersTakingTheItemOff() throws {
        let code = try source("Sources/PokeTokenBar/UI/PokemonRosterView.swift")
        XCTAssertTrue(code.contains("store.takeHeldItem()"), "벗기기 동작이 없다")
        XCTAssertTrue(code.contains("store.canTakeHeldItem"), "벗길 수 없을 때 막는 판정이 없다")
    }

    /// **같은 부류의 두 번째 사례.** 테라피스로 바꾼 테라 타입도 읽는 UI 가 한 곳도 없어,
    /// 사용 직후 토스트를 놓치면 그 개체의 테라 타입을 다시 확인할 방법이 없었다. 지닌물건과
    /// 같은 줄에서 함께 그린다.
    func testTheDetailCardDrawsTheTeraType() throws {
        let code = try source("Sources/PokeTokenBar/UI/PokemonRosterView.swift")
        XCTAssertTrue(code.contains("mon.teraType"), "상세 카드가 테라 타입을 읽지 않는다")
        XCTAssertGreaterThanOrEqual(code.components(separatedBy: "teraTypeRow()").count - 1, 2,
                                    "테라 타입 줄이 정의만 있고 어디서도 그려지지 않는다")
    }

    /// 격자 칸에도 표식이 있다 — 물건은 개체마다 붙고 박스 개체도 지닌 채로 있으므로, 카드를
    /// 하나씩 열어 보지 않고 **누가 쥐고 있나**를 알 수 있어야 한다.
    func testTheGridCardMarksAHolder() throws {
        let code = try source("Sources/PokeTokenBar/UI/PokemonRosterView.swift")
        XCTAssertTrue(code.contains("if let held = mon.heldItem"), "격자 칸에 지닌물건 표식이 없다")
    }
}
