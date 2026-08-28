import XCTest
@testable import PokeTokenBar

// MARK: 소유 포켓몬 탭 — 상세정보 팝오버 앵커

/// 정보(`i`) 버튼을 누르면 팝오버가 **하단에 한 번 떴다가 오른쪽으로 튀었다.**
///
/// 원인은 앵커 위치다. `.popover(item: $infoTarget)` 이 카드가 아니라 **탭 전체를 감싸는
/// 520pt VStack** 에 붙어 있었다 — 첫 프레임엔 그 큰 뷰의 경계를 기준으로 위치를 잡았다가(주로
/// 하단), 실제 소스 앵커(눌린 버튼)를 알게 되는 다음 프레임에 재계산되며 튀었다.
///
/// 처방은 팝오버를 **정보 아이콘 자체**에 앵커를 거는 것이다. 곁들여 요청받은 두 번째 동작 —
/// "열어 둔 채 다른 개체를 눌러도 상세창이 유지된다" — 도 같은 구조 변경에서 공짜로 따라온다.
/// 모든 카드가 **같은 `infoTarget` 바인딩**을 공유하므로, 다른 카드가 그 값을 바꾸면 이 카드의
/// `isPresented` 는 자동으로 false 로, 그 카드의 것은 true 로 동시에 바뀐다 — 손으로 먼저 닫을
/// 필요가 없다.
///
/// 렌더 없이는 팝오버의 실제 화면 위치를 잴 수 없으므로, 이 파일은 **그 앵커가 실제로 어디 걸려
/// 있는지**를 소스에서 확인한다. 주석은 뺀다(가드가 자기 설명에 걸리지 않도록).
final class RosterDetailPopoverTests: XCTestCase {

    private func rosterSource() throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/PokeTokenBar/UI/PokemonRosterView.swift")
        return try String(contentsOf: url, encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                guard let comment = line.range(of: "//") else { return String(line) }
                return String(line[..<comment.lowerBound])
            }
            .joined(separator: "\n")
    }

    /// **재발 방지의 핵심.** 예전 결함의 정확한 형태 — `.popover(item: $infoTarget)` 가 탭
    /// 콘텐츠 레벨(전체 body)에 붙는 것 — 이 코드에 다시 나타나면 안 된다.
    func testThePopoverIsNotAttachedAtTheWholeTabLevel() throws {
        let code = try rosterSource()
        XCTAssertFalse(code.contains(".popover(item: $infoTarget)"),
                       "탭 전체에 붙은 팝오버는 첫 프레임에 잘못된 앵커(전체 뷰 경계)를 쓴다")
    }

    /// 팝오버는 정보 아이콘(`info.circle`)과 **같은 오버레이 블록 안**에서 `isPresented:` 로
    /// 붙는다. 카드나 그리드처럼 더 큰 뷰에 붙으면 앵커가 부정확해 같은 부류의 결함이 재발한다.
    func testThePopoverIsAnchoredToTheInfoIcon() throws {
        let code = try rosterSource()
        let iconRange = try XCTUnwrap(code.range(of: "Image(systemName: \"info.circle\")"))
        // 아이콘 바로 다음 오버레이 블록이 끝나는 자리(짧게, 이 카드 안에서만)까지만 본다.
        let nearby = code[iconRange.upperBound...].prefix(500)
        XCTAssertTrue(nearby.contains(".popover(isPresented: showsDetail)"),
                      "팝오버가 정보 아이콘 근처에 없다 — 앵커가 다른 곳으로 옮겨졌을 수 있다")
    }

    /// 정보 버튼(그리드 아이콘·컨텍스트 메뉴 둘 다) 은 **같은 바인딩**(`infoTarget`)을 직접
    /// 쓴다. 카드마다 별도 상태를 두면 "다른 개체를 눌러도 유지" 가 깨진다 — 그 카드는 자기
    /// 상태만 true 가 되고, 정작 눌린 값은 다른 카드가 봐야 하는 `infoTarget` 이 아니게 된다.
    func testBothInfoTriggersWriteTheSharedBinding() throws {
        let code = try rosterSource()
        let occurrences = code.components(separatedBy: "infoTarget = mon").count - 1
        XCTAssertEqual(occurrences, 2, "정보 아이콘과 컨텍스트 메뉴 둘 다 같은 공유 바인딩을 써야 한다")
    }

    /// `showsDetail` 은 **정확한 id 비교**다 — `infoTarget != nil` 처럼 느슨하게 판정하면
    /// 모든 카드의 팝오버가 동시에 뜬다(공유 바인딩 하나에 모든 카드가 반응하므로).
    func testShowsDetailComparesTheExactIdentity() throws {
        let code = try rosterSource()
        XCTAssertTrue(code.contains("infoTarget?.id == mon.id"),
                      "정확한 id 비교가 아니면 여러 카드가 동시에 팝오버를 연다")
    }
}
