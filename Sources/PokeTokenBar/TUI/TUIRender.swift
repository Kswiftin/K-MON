import Foundation

/// 화면 한 프레임을 문자열 배열로 만든다. **부수효과 없음** — 터미널 출력은 `TUITerminal` 이 맡는다.
///
/// 모든 반환 줄은 요청한 폭을 넘지 않아야 한다. 넘치면 터미널이 줄을 접어 다음 줄을 밀어내고,
/// 전체 다시 그리기 방식에서는 그 밀림이 복구되지 않는다.
enum TUIRender {
    private static let solid = "█"
    private static let hollow = "░"

    /// 목록에서 **지금 커서가 있는 줄**을 가리키는 표식. `list` 만 쓴다.
    ///
    /// 행을 만드는 쪽(`PokedoroCLI.partyRows` 등)은 이 글자를 쓰면 안 된다 — 같은 열에 뜻이 다른
    /// 표식이 겹쳐 `▸ ▸ 고디탱` 처럼 찍히고, 어느 쪽이 커서인지 알 수 없게 된다. 행이 자기 상태를
    /// 표시할 때는 `activeMark` 를 쓴다.
    static let cursorMark = "▸"
    /// 행이 "지금 함께 다니는 개체" 임을 표시하는 글자. 커서와 반드시 달라야 한다.
    static let activeMark = "◆"

    /// 진행 막대. 길이는 진행도와 무관하게 항상 `width` 다.
    static func bar(progress: Double, width: Int) -> String {
        guard width > 0 else { return "" }
        // 클램프가 없으면 반복 횟수가 음수가 되어 크래시한다. 진행도는 시계에서 오는 계산값이라
        // 되감김·0 길이 모험에서 범위를 벗어날 수 있다.
        let ratio = min(1, max(0, progress))
        let filled = Int((Double(width) * ratio).rounded(.down))
        return String(repeating: solid, count: filled)
            + String(repeating: hollow, count: width - filled)
    }

    /// 남은 시간. 한 시간을 넘으면 시 자리를 붙인다 — 90분 모험이 "30:00" 으로 보이면
    /// 남은 시간이 한 시간 줄어든 것처럼 읽힌다.
    static func duration(_ seconds: Int) -> String {
        let total = max(0, seconds)
        let (hours, minutes, secs) = (total / 3600, (total % 3600) / 60, total % 60)
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%02d:%02d", minutes, secs)
    }

    /// 자릿수 구분 기호를 넣은 정수. 별의조각은 억 단위까지 가므로 구분이 없으면 읽을 수 없다.
    static func number(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    /// `왼쪽 ... 오른쪽` 한 줄. 오른쪽 값이 폭에 안 들어가면 왼쪽을 줄인다 — 숫자가 잘리면
    /// 자릿수가 달라 보여 잔액을 잘못 읽는다.
    static func row(left: String, right: String, width: Int) -> String {
        guard width > 0 else { return "" }
        let rightCut = TUIText.truncate(right, to: width)
        let space = width - TUIText.displayWidth(rightCut)
        return TUIText.pad(TUIText.truncate(left, to: space), to: space) + rightCut
    }

    static func rule(width: Int) -> String {
        String(repeating: "─", count: max(0, width))
    }

    /// 홈 화면.
    ///
    /// `keyHints` 는 **전체 화면 보기(`watch`)에서만** 켠다. 한 번 찍고 끝나는 `status` 에
    /// 키 안내를 붙이면 누를 곳이 없는 키를 알려 주는 셈이라, 사용자가 그 키를 셸에 친다.
    static func home(_ model: TUIHomeModel, width: Int, keyHints: Bool = false) -> [String] {
        let inner = max(1, width)
        var lines: [String] = []
        lines.append(row(left: "Pokédoro  \(model.trainerName)",
                         right: "★ \(number(model.starPieces))", width: inner))
        lines.append(rule(width: inner))
        lines.append("")

        if let name = model.partnerName {
            let shiny = model.isShiny ? " ✨" : ""
            lines.append(row(left: "파트너   \(name)\(shiny)",
                             right: "Lv.\(model.partnerLevel)", width: inner))
            // 막대는 라벨과 백분율을 뺀 나머지 폭을 쓴다. 음수가 되지 않게 하한을 둔다.
            let gaugeWidth = max(0, inner - 18)
            lines.append(TUIText.truncate(
                "경험치   \(bar(progress: model.levelProgress, width: gaugeWidth))"
                + String(format: " %3d%%", Int((min(1, max(0, model.levelProgress)) * 100).rounded())),
                to: inner))
            lines.append(TUIText.truncate("         다음 레벨까지 \(number(model.experienceToNextLevel))", to: inner))
        } else {
            // 파트너 없음도 정상 상태다(알 부화 중). 빈 화면을 그리면 고장으로 읽힌다.
            lines.append(TUIText.truncate("파트너   없음 — 알을 부화하는 중", to: inner))
        }
        lines.append("")

        if let adventure = model.adventure {
            let head = "모험     \(adventure.zone) (\(adventure.minutes)분)"
            let tail = adventure.isClaimable ? "보상 받기 가능" : "남은 시간 \(duration(adventure.remainingSeconds))"
            lines.append(row(left: head, right: tail, width: inner))
            let gaugeWidth = max(0, inner - 18)
            lines.append(TUIText.truncate(
                "         \(bar(progress: adventure.progress, width: gaugeWidth))"
                + String(format: " %3d%%", Int((min(1, max(0, adventure.progress)) * 100).rounded())),
                to: inner))
        } else {
            lines.append(TUIText.truncate("모험     쉬는 중", to: inner))
        }

        lines.append("")
        lines.append(rule(width: inner))
        if let status = model.status {
            lines.append(TUIText.truncate(status, to: inner))
        }
        if keyHints {
            // **지금 누를 수 있는 키만** 보여 준다. 상태와 무관하게 다 나열하면 사용자가 먹지도
            // 않는 키를 누르고 화면은 거절 사유로 답한다 — 그건 안내가 아니라 함정이다.
            lines.append(TUIText.truncate(sessionHints(model), to: inner))
            lines.append(TUIText.truncate("p 포켓몬  d 도감  r 새로고침  q 종료", to: inner))
        }
        return lines
    }

    /// 홈에서 지금 유효한 세션 키. 화면이 제 나름의 조건을 발명하지 않도록 `PokedoroSessionGate`
    /// 가 보는 것과 **같은 값**(모험 유무·정산 가능 여부)만 읽는다.
    static func sessionHints(_ model: TUIHomeModel) -> String {
        guard let adventure = model.adventure else {
            // 길이 목록은 화면·대화·터미널이 한 표를 쓴다 — 여기서 손으로 적으면 키와 실제
            // 길이가 갈라진다.
            return PokemonChatTool.focusMinutes.enumerated()
                .map { "\($0.offset + 1) \($0.element)분" }
                .joined(separator: "  ") + "   집중 시작"
        }
        return adventure.isClaimable ? "c 보상 받기   x 끝내기" : "x 끝내기"
    }

    /// 목록 한 창. 항상 정확히 `height` 줄을 돌려주고, 선택 행은 반드시 창 안에 들어간다 —
    /// 커서가 화면 밖으로 나가면 조작이 눈먼다.
    static func list(rows: [String], selection: Int, height: Int, width: Int) -> [String] {
        guard height > 0 else { return [] }
        guard !rows.isEmpty else {
            return [TUIText.pad("(비어 있음)", to: max(1, width))]
                + Array(repeating: "", count: height - 1)
        }
        let cursor = min(max(0, selection), rows.count - 1)
        // 선택 행을 창 가운데 두되, 목록 양 끝에서는 창을 목록 안쪽으로 밀어 빈 줄을 만들지 않는다.
        var top = cursor - height / 2
        top = min(top, rows.count - height)
        top = max(0, top)
        return (0..<height).map { offset in
            let index = top + offset
            guard index < rows.count else { return "" }
            let marker = index == cursor ? cursorMark + " " : "  "
            return TUIText.pad(marker + rows[index], to: max(1, width))
        }
    }
}
