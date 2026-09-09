import Foundation
import Testing

/// 창마다 `setFrameAutosaveName` 이 **달라야** 한다.
///
/// 같은 이름을 두 창이 쓰면 AppKit 이 한 프레임을 공유한다 — 한쪽을 옮기고 앱을 재시작하면
/// 다른 쪽이 그 자리에 뜬다. 화면에는 아무 오류도 안 뜨고, 사용자는 "창이 자기 자리를 기억
/// 못 한다" 로만 겪는다. 그래서 소스에서 센다.
///
/// 포코피아 창(`PokopiaTownPresenter`)이 Memory Home 창(`MemoryHomePresenter`)에서 갈려
/// 나오면서 생긴 가드다. 프레젠터를 베껴 새 창을 만들 때 가장 빠뜨리기 쉬운 한 줄이
/// 이 이름이다 — 나머지는 베껴도 맞지만 이것만은 반드시 바꿔야 한다.
@Suite struct WindowFrameAutosaveTests {

    private static var uiDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()    // Tests/PokeTokenBarLocalTests
            .deletingLastPathComponent()    // Tests
            .deletingLastPathComponent()    // 저장소 루트
            .appendingPathComponent("Sources/PokeTokenBar/UI")
    }

    /// `setFrameAutosaveName("…")` 의 인자를 파일과 함께 모은다.
    private static func autosaveNames() throws -> [(file: String, name: String)] {
        guard let enumerator = FileManager.default.enumerator(at: uiDirectory,
                                                              includingPropertiesForKeys: nil)
        else { return [] }
        var found: [(file: String, name: String)] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            let text = try String(contentsOf: url, encoding: .utf8)
            for line in text.components(separatedBy: .newlines) {
                guard let range = line.range(of: "setFrameAutosaveName(\"") else { continue }
                let rest = line[range.upperBound...]
                guard let close = rest.firstIndex(of: "\"") else { continue }
                found.append((url.lastPathComponent, String(rest[..<close])))
            }
        }
        return found
    }

    @Test func everyWindowHasItsOwnFrameAutosaveName() throws {
        let names = try Self.autosaveNames()
        // 경로나 파싱이 깨지면 빈 목록을 보고 조용히 통과한다 — 그걸 막는 단언.
        #expect(names.count >= 2, "창 autosave 이름을 못 찾았다: \(names)")

        var byName: [String: [String]] = [:]
        for entry in names { byName[entry.name, default: []].append(entry.file) }
        let shared = byName.filter { $0.value.count > 1 }
        #expect(shared.isEmpty, "두 창이 같은 프레임을 두고 다툰다: \(shared)")
    }

    /// 마을 창이 실제로 자기 이름을 갖는지 이름으로 못 박는다. 위 테스트만 있으면 마을 창의
    /// `setFrameAutosaveName` 줄이 통째로 사라져도(= 프레임을 아예 안 기억해도) 통과한다.
    @Test func thePokopiaWindowKeepsItsOwnFrame() throws {
        let names = try Self.autosaveNames()
        #expect(names.contains { $0.file == "PokopiaTownPresenter.swift" },
                "포코피아 창이 프레임을 기억하지 않는다: \(names)")
    }
}
