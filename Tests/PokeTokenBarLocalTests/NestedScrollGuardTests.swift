import Foundation
import Testing

/// 팝오버 본체가 이미 `ScrollView` 다. 탭 화면이 자기 안에 또 하나를 두면 중첩이 되어 **안쪽이
/// 스크롤되지 않는다** — 한 화면에 들어가는 만큼만 보이고 나머지는 볼 방법이 없다. 소유 포켓몬
/// 화면이 그 결함으로 21마리째부터 도달 불가였고(격자 높이를 260 → 520 으로 늘렸을 때는 잘리는
/// 지점만 옮겨졌다), 상점·가방에 같은 모양이 남아 있었다.
///
/// 화면 코드를 읽어 막는다: 렌더링 테스트로는 "안쪽이 스크롤되지 않는다" 를 볼 수 없다.
@Suite struct NestedScrollGuardTests {
    /// 팝오버 탭 본문을 그리는 화면들. 여기 새 탭을 더할 때 같은 함정을 다시 밟지 않게 한다.
    /// `CompanionView` 는 대상이 아니다 — 가로 스크롤(진화 라인)과 높이를 묶은 기술 재습득
    /// 후보 목록을 갖고 있다. 그 목록도 같은 부류로 의심되지만 확인 전이라 여기서 막지 않는다
    /// (`docs/reference/defect-log.md` 의 미완 스윕).
    private static let tabScreens = ["ShopView.swift", "BagView.swift", "PokemonRosterView.swift"]

    private var uiDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()    // Tests/PokeTokenBarLocalTests
            .deletingLastPathComponent()    // Tests
            .deletingLastPathComponent()    // 저장소 루트
            .appendingPathComponent("Sources/PokeTokenBar/UI")
    }

    @Test func popoverTabScreensDoNotNestTheirOwnScrollView() throws {
        for name in Self.tabScreens {
            let code = try String(contentsOf: uiDirectory.appendingPathComponent(name), encoding: .utf8)
            // 주석에서 이 결함을 설명하는 줄은 세지 않는다 — 설명이 곧 위반이 되면 아무도 안 적는다.
            let uses = code.components(separatedBy: .newlines)
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
                // 가로 스크롤은 세로 팝오버와 축이 달라 중첩 문제가 없다.
                .filter { $0.contains("ScrollView") && !$0.contains("ScrollView(.horizontal") }
            #expect(uses.isEmpty, "\(name) 이 자기 ScrollView 를 갖고 있다: \(uses)")
        }
    }
}
