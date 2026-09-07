import Foundation

/// 소스를 전수로 훑는 가드들이 함께 쓰는 최소 스캐너.
///
/// 화면 밖에서만 볼 수 있는 규칙(닫기 버튼이 한 벌인가 · 아이콘 버튼에 이름이 있는가)이 둘 이상이
/// 되면서, 각 테스트가 같은 파싱을 따로 들고 있었다. 한쪽만 고쳐지면 두 가드가 서로 다른 코드를
/// 보게 되므로 한 벌로 둔다.
enum SwiftSourceScan {

    /// `Sources/PokeTokenBar/<subpath>` 아래 `.swift` 전부.
    static func files(under subpath: String, from filePath: String) -> [URL] {
        let root = URL(fileURLWithPath: filePath)
            .deletingLastPathComponent()                // Tests/PokeTokenBarTests
            .deletingLastPathComponent()                // Tests
            .deletingLastPathComponent()                // 저장소 루트
            .appendingPathComponent("Sources/PokeTokenBar")
            .appendingPathComponent(subpath)
        let found = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" } ?? []
        return found.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// `Button` 이 시작된 줄부터 그 블록이 닫히는 줄, 그리고 이어 붙은 modifier 줄까지.
    ///
    /// modifier 줄까지 함께 보는 이유는 `accessibilityLabel` 이 블록 **뒤에** 붙기 때문이다 —
    /// 블록만 보면 이미 달아 둔 것도 없는 것으로 읽는다.
    ///
    /// 한계: 중괄호 깊이로만 끊으므로 한 줄에 버튼을 여럿 겹쳐 쓰면 뒤엣것을 놓친다. 놓친 것은
    /// 가드를 넓힐 때 잡고, 그때까지 **통과가 곧 전수 통과는 아니다**.
    static func buttonBlocks(in lines: [String]) -> [(start: Int, text: String)] {
        var blocks: [(Int, String)] = []
        var index = 0
        while index < lines.count {
            let line = lines[index]
            guard !line.trimmingCharacters(in: .whitespaces).hasPrefix("//"),
                  line.contains("Button(") || line.contains("Button {") else {
                index += 1
                continue
            }
            var depth = 0
            var collected: [String] = []
            var cursor = index
            repeat {
                let current = lines[cursor]
                collected.append(current)
                depth += current.filter { $0 == "{" }.count - current.filter { $0 == "}" }.count
                cursor += 1
            } while cursor < lines.count && depth > 0
            // 이어 붙은 modifier 를 모은다. 사이에 낀 주석에서 멈추면 안 된다 — modifier 는
            // "왜 이렇게 두었나" 를 바로 위에 적는 자리라, 주석에서 끊으면 그 아래 달아 둔
            // `accessibilityLabel` 을 못 보고 없다고 신고한다(실제로 한 번 그랬다).
            var pendingComments: [String] = []
            while cursor < lines.count {
                let trimmed = lines[cursor].trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix(".") {
                    collected.append(contentsOf: pendingComments)
                    pendingComments.removeAll()
                    collected.append(lines[cursor])
                    cursor += 1
                } else if trimmed.hasPrefix("//") {
                    pendingComments.append(lines[cursor])
                    cursor += 1
                } else {
                    // 주석이 modifier 로 이어지지 않았다 — 다음 코드에 딸린 것이므로 되돌린다.
                    cursor -= pendingComments.count
                    break
                }
            }
            blocks.append((index, collected.joined(separator: "\n")))
            index = max(cursor, index + 1)
        }
        return blocks
    }

    /// 라벨에 글자가 없는 버튼인가 — 아이콘만 있어 스스로 이름을 말하지 못하는 부류.
    static func isIconOnly(_ block: String) -> Bool {
        block.contains("Image(systemName:") && !block.contains("Text(") && !block.contains("Label(")
    }
}
