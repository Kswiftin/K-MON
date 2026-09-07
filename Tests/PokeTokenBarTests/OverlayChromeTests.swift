import XCTest
@testable import PokeTokenBar

/// 오버레이와 탭이 **어디로 돌아가는지 · 지금 어디인지**를 화면마다 같은 방식으로 말하게 한다.
///
/// 두 결함이 같은 뿌리에서 나왔다. 오버레이는 팝오버 전체를 갈아 끼우고 탭은 탭바가 그리는데,
/// 그 크롬(닫기 버튼 · 선택 표시)을 화면마다 손으로 베껴 두었다. 그래서 설정만 좌상단
/// "‹ 뒤로", 레이드만 `xmark.circle.fill`, 나머지는 우상단 `xmark` 가 됐고, 상점 · 가방은
/// 탭이면서 탭바에 자리가 없어 그 화면에 들어가면 선택 표시가 통째로 사라졌다.
///
/// 왜 기존 테스트가 못 걸렀나: 화면별 테스트는 자기 화면 안에서만 옳은지를 본다. "화면들이
/// 서로 같은가" 는 어느 한 화면의 테스트에도 속하지 않아 아무도 안 봤다. 그래서 가드를
/// 화면 밖 — 목록과 소스 전수 — 에 둔다.
final class OverlayChromeTests: XCTestCase {

    // MARK: 모든 탭은 어딘가에서 선택 표시를 받는다

    /// 탭을 새로 더하면서 탭바에도 footer 에도 안 올리면, 그 탭에 들어간 사용자는 자기가 어디
    /// 있는지 알 방법이 없다 — 상점 · 가방이 실제로 그 상태였다.
    ///
    /// 두 목록의 합집합이 아니라 **정확히 한 번씩** 을 요구한다. 양쪽에 다 올리면 같은 화면으로
    /// 가는 길이 두 개인데 서로 다르게 보이는, 처음 문제와 같은 부류가 된다.
    func testEveryTabIsSurfacedExactlyOnce() {
        let surfaced = PopoverTab.tabBarTabs + PopoverTab.footerTabs
        for tab in PopoverTab.allCases {
            XCTAssertEqual(surfaced.filter { $0 == tab }.count, 1,
                           "\(tab) 이 탭바 · footer 중 정확히 한 곳에 있어야 한다")
        }
        XCTAssertEqual(surfaced.count, PopoverTab.allCases.count)
    }

    /// footer 가 그리는 탭에 있으면 footer 가 그걸 표시해야 한다. 이 판정이 뷰 안에 인라인으로
    /// 있으면 다음 탭을 더할 때 한쪽만 고치고 끝난다.
    func testFooterKnowsWhenItIsTheCurrentLocation() {
        for tab in PopoverTab.footerTabs {
            XCTAssertTrue(tab.isFooterDestination, "\(tab) 은 footer 에서 열린다")
        }
        for tab in PopoverTab.tabBarTabs {
            XCTAssertFalse(tab.isFooterDestination, "\(tab) 은 탭바가 표시한다")
        }
    }

    // MARK: 닫기 버튼은 한 벌뿐이다

    private var uiSourceRoot: URL {
        URL(fileURLWithPath: #filePath)                 // Tests/PokeTokenBarTests/이 파일
            .deletingLastPathComponent()                // Tests/PokeTokenBarTests
            .deletingLastPathComponent()                // Tests
            .deletingLastPathComponent()                // 저장소 루트
            .appendingPathComponent("Sources/PokeTokenBar/UI")
    }

    /// 닫기 버튼을 화면마다 직접 만들면 아이콘 · 위치 · 라벨이 갈라진다. 갈라진 뒤에는 어느 쪽이
    /// 정본인지 코드만 봐서는 알 수 없어, 다음 오버레이도 가장 가까운 것을 베낀다.
    ///
    /// 접근성이 이 규칙에 얹혀 있다: 아이콘만 있는 버튼은 `help`(마우스 툴팁) 로는 VoiceOver 에
    /// 안 읽힌다. 공용 버튼 한 곳에서 `accessibilityLabel` 까지 달아야 화면이 늘어도 안 샌다.
    ///
    /// 검사 대상은 `Button(action: onClose)` 라는 **아이콘 버튼 표기**뿐이다. 본문에 라벨이 있는
    /// `Button(l.battleClose) { … onClose() }`(웨이브 런 결산의 '확인') 는 헤더 닫기가 아니라
    /// 그 화면의 결론 버튼이라 규칙 밖이다.
    func testNoScreenBuildsItsOwnCloseButton() throws {
        let files = FileManager.default.enumerator(at: uiSourceRoot, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" } ?? []
        // 경로가 깨지면 빈 목록을 훑고 조용히 통과한다 — 그걸 막는 단언.
        XCTAssertGreaterThan(files.count, 10, "UI 소스를 못 찾았다 — 경로가 깨지면 가드가 무력해진다")

        var offenders: [String] = []
        for file in files where file.lastPathComponent != "PokedoroTheme.swift" {
            for (index, line) in try String(contentsOf: file, encoding: .utf8)
                .components(separatedBy: .newlines).enumerated()
            where !line.trimmingCharacters(in: .whitespaces).hasPrefix("//")
                && line.contains("Button(action: onClose)") {
                offenders.append("\(file.lastPathComponent):\(index + 1)")
            }
        }
        XCTAssertEqual(offenders, [],
                       "닫기 버튼은 PokedoroOverlayCloseButton 하나뿐이다 — 직접 만든 자리: \(offenders)")
    }
}
