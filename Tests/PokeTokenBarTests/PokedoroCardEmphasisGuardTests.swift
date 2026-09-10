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

/// **채운 버튼의 색은 테마 팔레트에서만 온다.**
///
/// 친구 탭 상대 카드는 채운 버튼(`borderedProminent`) 셋을 시스템 원색 `.red` · `.purple` · `.blue`
/// 로 나란히 두고 있었다. 시스템 원색은 채도가 최대치라 셋이 서로 소리를 지르고, 그 줄에서
/// 무엇이 기본 동작인지가 사라진다(사용자 지적: "너무 쨍하다").
///
/// 규칙은 둘이다 — ⓐ 채움은 그 화면의 주 동작에만, ⓑ 색은 `PokedoroTheme` 의 낮은 채도 팔레트에서만.
/// ⓑ 만 기계로 지킨다. ⓐ 는 "무엇이 주 동작인가" 라는 화면의 판단이라 소스에서 셀 수 없다.
///
/// 게이지(`ProgressView`)는 규칙 밖이다 — 채운 면적이 작고 값의 상태(위험·완료)를 색으로
/// 말하는 자리라, 버튼 채움과 같은 예산을 쓰지 않는다.
final class ProminentButtonTintGuardTests: XCTestCase {

    private static let systemColors = ["red", "blue", "green", "orange", "purple", "pink",
                                        "yellow", "mint", "teal", "indigo", "brown", "cyan"]

    func testFilledButtonsAreTintedFromTheThemePalette() throws {
        let files = SwiftSourceScan.files(under: "UI", from: #filePath)
        XCTAssertGreaterThan(files.count, 10, "UI 소스를 못 찾았다 — 경로가 깨지면 가드가 무력해진다")

        var checkedButtonTints = 0
        var offenders: [String] = []
        for file in files {
            let lines = try String(contentsOf: file, encoding: .utf8).components(separatedBy: .newlines)
            for (index, line) in lines.enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.hasPrefix("//"), trimmed.contains(".tint(") else { continue }
                // 버튼에 붙은 tint 인가 — 같은 줄이거나 바로 위 두 줄에 `buttonStyle` 이 있다.
                let window = lines[max(0, index - 2)...index].joined(separator: "\n")
                guard window.contains("buttonStyle") else { continue }
                checkedButtonTints += 1
                if Self.systemColors.contains(where: { trimmed.contains(".tint(.\($0))") }) {
                    offenders.append("\(file.lastPathComponent):\(index + 1)")
                }
            }
        }
        // 대조군: 버튼 tint 를 하나도 못 찾았으면 위 판정 창(2줄)이 낡은 것이다.
        XCTAssertGreaterThanOrEqual(checkedButtonTints, 3, "버튼 tint 를 못 찾았다 — 판정 창이 낡았다")
        XCTAssertEqual(offenders, [], "시스템 원색으로 채운 버튼: \(offenders)")
    }
}
