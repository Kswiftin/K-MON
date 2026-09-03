import Foundation
import Testing

/// 팝오버 본체가 이미 `ScrollView` 다. 그 안에 그려지는 화면이 자기 안에 또 하나를 두면 중첩이
/// 되어 **안쪽이 스크롤되지 않는다** — 한 화면에 들어가는 만큼만 보이고 나머지는 볼 방법이 없다.
/// 소유 포켓몬 화면이 그 결함으로 21마리째부터 도달 불가였고(격자 높이를 260 → 520 으로 늘렸을
/// 때는 잘리는 지점만 옮겨졌다), 상점·가방에 같은 모양이 남아 있었다.
///
/// 화면 코드를 읽어 막는다: 렌더링 테스트로는 "안쪽이 스크롤되지 않는다" 를 볼 수 없다.
///
/// **검사 대상을 손으로 적지 않는다.** 예전엔 탭 본문 네 파일만 적어 놨는데, 결함은 탭 본문이
/// 아니라 그 **자식**에서 다시 났다(`FriendView` → `RoomBattleView`). 그래서 `PopoverView` 의
/// 탭 전환에서 시작해 UI 안에서 닿는 화면을 **전부 따라간다** — 새 화면을 붙이면 목록을 고치지
/// 않아도 자동으로 검사된다.
@Suite struct NestedScrollGuardTests {

    /// 팝오버 스크롤 **밖에** 그려지는 화면. 자기 스크롤을 가져야 맞다.
    /// - `PopoverView` 자신이 바깥 `ScrollView` 의 주인이다.
    /// - 별도 창·시트로 뜨는 화면은 팝오버 높이에 갇히지 않는다.
    private static let ownsItsOwnScroll: Set<String> = [
        "PopoverView.swift", "SettingsView.swift", "MemoryHomePresenter.swift",
        "PokemonChatView.swift", "RogueRunView.swift", "RaidView.swift",
    ]

    private static var uiDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()    // Tests/PokeTokenBarLocalTests
            .deletingLastPathComponent()    // Tests
            .deletingLastPathComponent()    // 저장소 루트
            .appendingPathComponent("Sources/PokeTokenBar/UI")
    }

    @Test func nothingDrawnInsideThePopoverScrollNestsItsOwnScrollView() throws {
        let sources = try Self.uiSources()
        let reachable = try Self.filesReachableFromPopoverTabs(sources)
        // 경로나 파싱이 깨지면 빈 집합을 훑고 조용히 통과한다 — 그걸 막는 단언.
        #expect(reachable.count > 8, "팝오버에서 닿는 화면을 못 찾았다: \(reachable.sorted())")
        #expect(reachable.contains("FriendView.swift") && reachable.contains("RoomBattleView.swift"),
                "탭 본문의 자식까지 따라가지 못했다 — 결함이 난 자리가 바로 거기다")

        var offenders: [String: [String]] = [:]
        for name in reachable.subtracting(Self.ownsItsOwnScroll) {
            let uses = Self.verticalScrollViews(in: sources[name] ?? "")
            if !uses.isEmpty { offenders[name] = uses }
        }
        #expect(offenders.isEmpty, "팝오버 안쪽에서 자기 ScrollView 를 갖는 화면: \(offenders)")
    }

    // MARK: 훑기

    private static func uiSources() throws -> [String: String] {
        guard let enumerator = FileManager.default.enumerator(at: uiDirectory,
                                                              includingPropertiesForKeys: nil)
        else { return [:] }
        var sources: [String: String] = [:]
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            sources[url.lastPathComponent] = try String(contentsOf: url, encoding: .utf8)
        }
        return sources
    }

    /// `PopoverView` 의 탭 전환에서 시작해 **UI 안에서 닿는 화면 파일**을 전부 모은다.
    /// 한 단계만 보면 `FriendView` 아래의 `RoomBattleView` 를 놓친다 — 그게 #209 였다.
    private static func filesReachableFromPopoverTabs(_ sources: [String: String]) throws -> Set<String> {
        // 화면 이름 → 그 화면이 사는 파일.
        var fileOfView: [String: String] = [:]
        for (file, text) in sources {
            for name in declaredViewNames(in: text) { fileOfView[name] = file }
        }

        guard let popover = sources["PopoverView.swift"] else { return [] }
        var frontier = viewsMentioned(in: tabSwitchBody(of: popover), among: fileOfView)
        var reachable: Set<String> = ["PopoverView.swift"]
        while let view = frontier.popFirst() {
            guard let file = fileOfView[view], reachable.insert(file).inserted else { continue }
            for next in viewsMentioned(in: sources[file] ?? "", among: fileOfView) {
                if !reachable.contains(fileOfView[next] ?? "") { frontier.insert(next) }
            }
        }
        return reachable
    }

    /// 탭 전환 블록만 잘라낸다. `PopoverView` 전체를 훑으면 팝오버 스크롤 **밖**에 그려지는
    /// 조각(트레이너 바·설정 창)까지 대상에 들어간다.
    private static func tabSwitchBody(of popover: String) -> String {
        let lines = popover.components(separatedBy: "\n")
        guard let start = lines.firstIndex(where: { $0.contains("switch nav.tab {") }) else { return "" }
        let rest = lines[start...]
        let end = rest.firstIndex { $0.trimmingCharacters(in: .whitespaces) == "}" } ?? rest.endIndex
        return lines[start..<end].joined(separator: "\n")
    }

    /// 이 소스가 **그리는** 화면 이름들. `Name(` 형태의 호출만 센다.
    private static func viewsMentioned(in text: String, among known: [String: String]) -> Set<String> {
        var found: Set<String> = []
        for name in known.keys where text.contains("\(name)(") {
            // 자기 선언은 호출이 아니다.
            if text.contains("struct \(name)(") { continue }
            found.insert(name)
        }
        return found
    }

    /// **높이가 묶이지 않은** 세로 스크롤 컨테이너를 여는 줄.
    ///
    /// 예외 셋을 뺀다.
    /// - `ScrollViewReader`·`ScrollViewProxy` — 스크롤을 만들지 않고 이미 있는 것을 가리킨다.
    /// - 가로 스크롤 — 세로 팝오버와 축이 달라 중첩이 아니다.
    /// - **높이가 정해진 판** — `.frame(height:)` / `.frame(maxHeight:)` 가 걸리면 그 안에서
    ///   실제로 스크롤된다(전투 채팅 82pt, 대표 포켓몬 고르기 300pt). 중첩 자체가 죄가 아니라
    ///   **크기가 안 정해진 중첩**이 죄다 — 그때만 안쪽이 제 크기로 부풀어 스크롤을 잃는다.
    ///   높이는 같은 멤버 어디에 걸려도 인정한다(모디파이어가 바깥 컨테이너에 붙는다).
    private static func verticalScrollViews(in code: String) -> [String] {
        let lines = code.components(separatedBy: .newlines).map { line -> String in
            // 주석에서 이 결함을 설명하는 줄은 세지 않는다 — 설명이 곧 위반이 되면 아무도 안 적는다.
            // 줄 끝 주석도 잘라낸다: `.id(i)   // ScrollViewProxy 대상` 처럼 코드 뒤에 붙은
            // 설명까지 세면 규칙을 지킨 화면이 자기 주석 때문에 걸린다.
            guard let comment = line.range(of: "//") else { return line }
            return String(line[line.startIndex..<comment.lowerBound])
        }
        var offenders: [String] = []
        for (index, line) in lines.enumerated() {
            guard line.contains("ScrollView {") || line.contains("ScrollView(") else { continue }
            guard !line.contains("ScrollView(.horizontal") else { continue }
            guard !boundsHeight(lines, from: index) else { continue }
            offenders.append(line.trimmingCharacters(in: .whitespaces))
        }
        return offenders
    }

    /// 이 `ScrollView` 가 사는 **멤버 안 어딘가에** 높이를 묶는 모디파이어가 있는가.
    /// 멤버의 끝은 다음 선언 줄로 본다 — 들여쓰기 네 칸에서 시작하는 `var`/`func`.
    private static func boundsHeight(_ lines: [String], from index: Int) -> Bool {
        for line in lines[index...].dropFirst() {
            if startsAMember(line) { return false }
            if line.contains("height:") { return true }
        }
        return false
    }

    private static func startsAMember(_ line: String) -> Bool {
        guard line.hasPrefix("    "), !line.hasPrefix("     ") else { return false }
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("var ") || trimmed.hasPrefix("func ")
            || trimmed.contains(" var ") || trimmed.contains(" func ")
    }

    /// `struct Foo: View {` / `struct Foo: View, Sendable` 형태의 선언 이름.
    private static func declaredViewNames(in text: String) -> [String] {
        text.components(separatedBy: "\n").compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.contains("struct "), trimmed.contains(": View") else { return nil }
            let parts = trimmed.split(separator: " ")
            guard let index = parts.firstIndex(of: "struct"), parts.count > index + 1 else { return nil }
            let name = parts[index + 1].split(separator: ":").first.map(String.init) ?? ""
            return name.isEmpty ? nil : name
        }
    }
}
