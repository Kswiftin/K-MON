import XCTest
@testable import PokeTokenBar

/// **오버레이를 여는 버튼은 글자로 자기 이름을 말한다.**
///
/// 오버레이(주간 회고 · 꾸미기 · 대화 …)는 팝오버 **전체**를 갈아 끼우는 화면인데, 여는 자리가
/// 아이콘 하나였다. 아이콘은 이름이 아니다 — `chart.bar.xaxis` 를 보고 "주간 회고" 를 떠올릴
/// 방법이 없어서, 만들어 둔 화면이 앱 안에서 이름이 불리는 자리 없이 남았다.
///
/// `accessibilityLabel` 은 이 규칙을 대신하지 못한다(`IconButtonLabelGuardTests` 와 다른 규칙이다).
/// 그건 화면 판독기에게만 들리고, 화면을 보는 사람에게는 여전히 이름 없는 아이콘이다.
///
/// 왜 화면별 테스트로 못 잡나: "이 기능을 어디서 여는가" 는 그 기능 화면의 테스트 대상이 아니고,
/// 버튼이 있는 화면의 테스트는 눌리는지만 본다 — 눌리는 것과 이름이 있는 것은 무관하다.
final class OverlayEntryLabelGuardTests: XCTestCase {

    /// 오버레이를 여는 문장. 새 오버레이를 더하면 여기도 늘린다.
    private static let openers = ["nav.showFocusRecap = true", "nav.showOutfit = true",
                                  "nav.showGymLeague = true", "nav.showDungeon = true",
                                  "nav.showRaid = true", "chatPresenter.open("]

    /// 글자 없이 두어도 되는 자리 — 관례가 이름을 대신하는 아이콘.
    ///
    /// 톱니(설정)는 macOS 어느 앱에서나 같은 뜻이라 글자가 없어도 찾는다. 로스터 격자 칸의
    /// 대화 아이콘은 칸 폭이 105pt 라 글자를 넣을 자리가 없다 — 대신 **파트너 카드**의 대화
    /// 버튼이 글자를 들고 이름을 준다(같은 기능을 여는 자리가 둘이고, 이름은 넓은 쪽이 맡는다).
    private static let exemptFiles = ["PokemonRosterView.swift"]

    func testEveryOverlayEntryPointCarriesItsNameInText() throws {
        let files = SwiftSourceScan.files(under: "UI", from: #filePath)
        XCTAssertGreaterThan(files.count, 10, "UI 소스를 못 찾았다 — 경로가 깨지면 가드가 무력해진다")

        var checked: Set<String> = []
        var offenders: [String] = []
        for file in files where !Self.exemptFiles.contains(file.lastPathComponent) {
            let lines = try String(contentsOf: file, encoding: .utf8).components(separatedBy: .newlines)
            for block in SwiftSourceScan.buttonBlocks(in: lines)
            where Self.openers.contains(where: { block.text.contains($0) }) {
                checked.insert(file.lastPathComponent)
                if SwiftSourceScan.isIconOnly(block.text) {
                    offenders.append("\(file.lastPathComponent):\(block.start + 1)")
                }
            }
        }
        // 대조군: 실제로 훑은 화면을 이름으로 확인한다. 여는 문장이 바뀌거나 스캐너가 블록을
        // 놓치면 목록이 비고, 그 상태로 두면 이 가드는 아무것도 안 지키면서 초록이다.
        // (도전 4종은 카드 뷰에 클로저로 넘기므로 여기서는 카드 쪽 `Button` 이 잡힌다.)
        XCTAssertEqual(checked, ["FocusTimerView.swift", "PopoverView.swift", "CompanionView.swift"],
                       "오버레이를 여는 버튼 목록이 낡았다")
        XCTAssertEqual(offenders, [], "아이콘만으로 오버레이를 여는 자리: \(offenders)")
    }
}
