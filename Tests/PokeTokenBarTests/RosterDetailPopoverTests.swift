import XCTest
@testable import PokeTokenBar

// MARK: 소유 포켓몬 탭 — 상세정보 팝오버 앵커

/// 정보(`i`) 버튼을 누르면 팝오버가 **하단에 한 번 떴다가 오른쪽으로 튀었다.**(2026-08-28)
///
/// 원인은 앵커 위치다. `.popover(item: $infoTarget)` 이 카드가 아니라 **탭 전체를 감싸는
/// 520pt VStack** 에 붙어 있었다 — 첫 프레임엔 그 큰 뷰의 경계를 기준으로 위치를 잡았다가(주로
/// 하단), 실제 소스 앵커(눌린 버튼)를 알게 되는 다음 프레임에 재계산되며 튀었다.
/// 1차 처방은 팝오버를 정보 아이콘 자체에 앵커를 거는 것이었다.
///
/// 이후 "팝오버를 탭 오른쪽에 고정해 달라"는 요청으로 앵커를 다시 옮겼다 — 이번엔 카드가 아니라
/// **탭 오른쪽 가장자리에 박아 둔 1×1pt 짜리 고정 뷰** 하나를 모든 카드가 공유한다. 이 앵커는
/// 크지도 않고 위치도 절대 바뀌지 않으므로(어느 카드를 눌렀든 같은 자리), 첫 프레임과 재계산된
/// 프레임의 기준 뷰가 애초에 같다 — 위 결함의 원인(트리거마다 다른 실제 위치 vs 큰 컨테이너의
/// 모호한 경계)이 성립하지 않는다.
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

    /// 팝오버는 카드가 아니라 **1×1pt 짜리 고정 앵커**에 붙는다. 그 앵커가 커지거나(예: 카드
    /// 전체·격자·탭 콘텐츠) 위치가 트리거마다 달라지면, 첫 프레임 결함이 다른 모양으로 재발한다.
    func testThePopoverIsAnchoredToAFixedOnePointView() throws {
        let code = try rosterSource()
        let anchorRange = try XCTUnwrap(code.range(of: "Color.clear.frame(width: 1, height: 1)"),
                                        "고정 앵커(1×1pt)가 없다 — 팝오버가 다시 큰 뷰에 붙었을 수 있다")
        // 앵커 바로 다음에 오는 것이 팝오버여야 한다 — 그래야 이 작은 뷰가 실제 소스다.
        let nearby = code[anchorRange.upperBound...].prefix(200)
        XCTAssertTrue(nearby.contains(".popover(isPresented: infoTargetIsPresented)"),
                      "고정 앵커 바로 뒤에 팝오버가 없다 — 앵커와 프레젠테이션이 분리됐을 수 있다")
    }

    /// 그 고정 앵커는 탭 오른쪽 가장자리에 있어야 한다 — 이번 요청의 본문("탭 오른쪽에 고정")이다.
    func testTheFixedAnchorSitsAtTheTrailingEdge() throws {
        let code = try rosterSource()
        let overlayRange = try XCTUnwrap(code.range(of: ".overlay(alignment: .trailing)"),
                                         "오른쪽 정렬 오버레이가 없다 — 앵커가 다른 자리로 옮겨졌을 수 있다")
        let nearby = code[overlayRange.upperBound...].prefix(200)
        XCTAssertTrue(nearby.contains("Color.clear.frame(width: 1, height: 1)"),
                      "오른쪽 정렬 오버레이 안에 고정 앵커가 없다")
    }

    /// 정보 버튼(그리드 아이콘·컨텍스트 메뉴 둘 다)은 **같은 바인딩**(`infoTarget`)을 직접
    /// 쓴다. 카드마다 별도 상태를 두면 "다른 개체를 눌러도 유지" 가 깨진다.
    func testBothInfoTriggersWriteTheSharedBinding() throws {
        let code = try rosterSource()
        let occurrences = code.components(separatedBy: "infoTarget = mon").count - 1
        XCTAssertEqual(occurrences, 2, "정보 아이콘과 컨텍스트 메뉴 둘 다 같은 공유 바인딩을 써야 한다")
    }

    /// 앵커가 하나뿐이므로 `isPresented` 는 "지금 보여줄 대상이 있는가"(`infoTarget != nil`)면
    /// 된다 — 카드별 앵커였을 때 필요했던 정확한 id 비교(`showsDetail`)는 더 이상 없다.
    func testPresentationTracksWhetherAnyTargetIsSet() throws {
        let code = try rosterSource()
        XCTAssertTrue(code.contains("infoTarget != nil"),
                      "고정 앵커 하나를 공유하므로 대상 존재 여부만 보면 된다")
    }
}
