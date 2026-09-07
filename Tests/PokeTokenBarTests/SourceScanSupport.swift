import Foundation

/// 소스 텍스트를 증거로 쓰는 가드들의 공용 입구.
///
/// **왜 있어야 하는가.** 스캔이 `text.contains("orderingSpeed")` 로 물으면 호출을 지워도 바로 위
/// 설명 주석이 남아 통과한다(순풍 작업에서 결함 주입으로 실제로 확인했다 —
/// `docs/reference/defect-log.md` "소스를 문자열로 스캔하는 가드" 절). 주석은 호출과 함께 지워지지
/// 않으므로, 스캔은 **주석을 뗀 코드**만 봐야 한다.
enum SourceScan {

    /// `Sources/` 아래 모든 `.swift` 의 (파일명, 주석 뗀 코드).
    ///
    /// 줄 주석(`//`)으로 시작하는 줄을 빈 줄로 바꾼다 — 줄 수를 유지해야 오류 메시지의 줄 번호가
    /// 원본과 맞는다. 줄 끝 주석과 블록 주석은 남는다(지금 가드들이 찾는 이름이 그 자리에 오지
    /// 않아서다 — 오게 되면 여기를 늘린다).
    static func sources(relativeTo file: StaticString = #filePath) throws -> [(name: String, code: String)] {
        let root = URL(fileURLWithPath: "\(file)")
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources")
        guard let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else {
            return []
        }
        var out: [(name: String, code: String)] = []
        for case let url as URL in files where url.pathExtension == "swift" {
            let code = try String(contentsOf: url, encoding: .utf8)
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces).hasPrefix("//") ? "" : String($0) }
                .joined(separator: "\n")
            out.append((url.lastPathComponent, code))
        }
        return out.sorted { $0.name < $1.name }
    }
}
