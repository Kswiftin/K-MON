import XCTest
@testable import PokeTokenBar

/// **강조 예산 — 한 화면에 색 테두리 카드는 하나.**
///
/// 카드 강조(`pokedoroCard(emphasis:)`)는 "지금 여기를 보라" 는 말이다. 그런데 화면마다 자기 카드를
/// 강조하면서 홈 탭 하나에 강조가 넷(업데이트 배너 · 트레이너 바 · 상점 잔액 · 친구 메시지)까지
/// 늘었고, 넷이 서로를 상쇄해 아무도 아무것도 가리키지 못했다. 색은 **상태 신호**일 때만 쓴다 —
/// 집중 중 빨강 · 휴식 중 파랑.
///
/// 왜 화면 안에서 못 잡나: 강조는 각 화면이 자기 파일에서 혼자 정하는 값이라 그 파일의 테스트는
/// 늘 통과한다. "함께 떠 있는 카드가 몇 개 강조되어 있나" 는 어느 화면의 것도 아니라 여기 둔다.
///
/// 팝오버는 탭을 갈아 끼워도 집중 카드가 늘 남으므로(스크롤 밖 크롬) 팝오버 전체의 예산 하나는
/// 집중 카드가 쓴다. Memory Home 은 **다른 창**이라 자기 예산 하나를 따로 쓴다.
final class PokedoroCardEmphasisGuardTests: XCTestCase {

    /// 강조를 쓸 수 있는 파일과, 그 파일이 강조하는 카드.
    private static let budget = ["FocusTimerView.swift": "집중 카드(팝오버)",
                                 "MemoryHomePresenter.swift": "미니룸(Memory Home 창)"]

    func testOnlyTheBudgetedScreensEmphasizeACard() throws {
        let files = SwiftSourceScan.files(under: "UI", from: #filePath)
        XCTAssertGreaterThan(files.count, 10, "UI 소스를 못 찾았다 — 경로가 깨지면 가드가 무력해진다")

        var emphasisCounts: [String: Int] = [:]
        for file in files {
            let lines = try String(contentsOf: file, encoding: .utf8).components(separatedBy: .newlines)
            let count = lines.filter {
                !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//")
                && $0.contains("pokedoroCard(emphasis:")
                && !$0.contains("func ")   // 선언(`PokedoroTheme`) 은 호출이 아니다
            }.count
            if count > 0 { emphasisCounts[file.lastPathComponent] = count }
        }

        // 대조군: 예산을 가진 화면이 강조를 **실제로** 쓰고 있어야 한다. 아무도 안 쓰면 아래
        // 검증은 빈 목록을 비교하며 조용히 통과한다(그 상태의 화면은 강조가 통째로 사라진 화면이다).
        for (file, card) in Self.budget {
            XCTAssertEqual(emphasisCounts[file], 1, "\(card): 강조가 하나여야 한다")
        }

        let unbudgeted = emphasisCounts.keys.filter { Self.budget[$0] == nil }.sorted()
        XCTAssertEqual(unbudgeted, [],
                       "예산 밖에서 카드를 강조한다 — 함께 뜨는 강조가 둘이 되면 둘 다 신호가 아니게 된다: \(unbudgeted)")
    }
}
