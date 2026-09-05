import Foundation

/// 진행도를 가진 목록 한 행 — 미션·시즌·도감 목표·업적이 화면에서 같은 모양이다.
///
/// 렌더가 스토어를 직접 읽지 않게 하는 자리다(`TUIHomeModel` 과 같은 이유). 네 원장의 타입이
/// 서로 다르고 진행도는 `@MainActor` 스토어에서만 나오는데, 화면 조립은 그것과 무관하게 검증돼야 한다.
struct TUIProgressRow: Equatable, Sendable {
    var label: String
    var value: Int
    var target: Int
    /// 목표에 닿았는가. `>=` 인 이유는 목표를 넘긴 진행도가 세이브에 남아 있을 수 있어서다
    /// (손편집·구버전). `==` 로 보면 그 행이 영영 미완료로 보인다.
    var isDone: Bool { value >= target }
}

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

    /// 커서 표식이 먹는 칸(`list` 가 붙이는 `"▸ "`).
    static let listMarkerWidth = 2

    /// 목록 행을 조립할 폭. **목록에 들어갈 행은 이 폭으로 만들어야 한다** — 전체 폭으로 만들면
    /// `list` 가 표식을 앞에 붙인 뒤 `pad` 가 오른쪽을 잘라 내 값(개수·진행도)이 사라지고,
    /// 라벨만 남으므로 사용자는 무엇이 잘렸는지도 모른다.
    ///
    /// 하한이 있는 이유는 아주 좁은 터미널에서 0 이하가 되면 `rows` 가 빈 줄만 내놓기 때문이다.
    static func listRowWidth(_ width: Int) -> Int { max(1, width - listMarkerWidth) }

    /// 완료 표식. 커서·활성 표식과 달리 **한 칸짜리**여야 한다 — 두 칸 기호를 쓰면 완료된 행만
    /// 오른끝이 한 칸 밀린다.
    static let doneMark = "✓"

    /// 목록이 찍는 개체 번호(1부터). 사람이 세는 대로 찍는다 — 0 번 포켓몬을 보여 주면 사용자가
    /// 무엇을 칠지 모른다.
    static func printedRosterNumber(index: Int) -> Int { index + 1 }

    /// 사용자가 친 번호 → 로스터 인덱스. **찍는 쪽과 받는 쪽이 이 한 쌍을 쓴다** — 한쪽만 0 부터
    /// 세면 사용자는 자기가 고른 것과 다른 개체를 보고, 화면과 입력을 손으로 맞대 보기 전엔 모른다.
    static func rosterIndex(printed number: Int) -> Int { number - 1 }

    /// 라벨 + 오른끝 값 목록. 가방·개체 상세처럼 목표가 없는 값이 쓴다.
    static func rows(_ entries: [(label: String, value: String)], width: Int) -> [String] {
        entries.map { row(left: $0.label, right: $0.value, width: width) }
    }

    /// 진행 목록. 값 문자열을 만들어 `rows` 에 넘긴다 — 오른끝 정렬 규칙을 두 벌로 쓰지 않는다.
    static func progress(_ entries: [TUIProgressRow], width: Int) -> [String] {
        rows(entries.map { entry in
            (label: entry.label,
             value: "\(entry.value)/\(entry.target)" + (entry.isDone ? " \(doneMark)" : ""))
        }, width: width)
    }

    /// 안내 조각들을 **폭에 맞게 여러 줄로** 접는다.
    ///
    /// 한 줄로 이어 붙이고 `truncate` 에 맡기면 넘친 오른쪽이 **조용히 사라진다.** 화면을 하나
    /// 더한 순간 실제로 그랬다: 이동 키 목록이 70칸을 넘겨 `q 종료` 가 잘려 나가, 나가는 방법이
    /// 화면에서 없어졌다. 조각 하나가 폭보다 길면 그 조각만 잘린다(그건 줄일 수 있는 값이 아니다).
    static func hintLines(_ entries: [String], width: Int) -> [String] {
        guard width > 0 else { return [] }
        let gap = "  "
        var lines: [String] = []
        var current = ""
        for entry in entries {
            let candidate = current.isEmpty ? entry : current + gap + entry
            if current.isEmpty || TUIText.displayWidth(candidate) <= width {
                current = candidate
            } else {
                lines.append(current)
                current = entry
            }
        }
        if !current.isEmpty { lines.append(current) }
        return lines.map { TUIText.truncate($0, to: width) }
    }

    /// 이동 키 안내 조각. **지금 화면 키는 뺀다** — 눌러도 아무 일도 안 하는 키를 권하는 셈이다.
    ///
    /// 키와 이름을 `TUIScreen` 에서 읽는 이유는 키 표(`TUIKeymap`)와 같은 값을 보게 하기
    /// 위해서다. 손으로 적으면 안내에 있는 키가 안 먹거나, 먹는 키가 안내에 없다.
    ///
    /// **나가는 키를 앞에 둔다.** 폭이 아주 좁아 한 조각씩 잘릴 때도 `q 종료` 는 첫 줄에 남는다.
    static func screenHintEntries(current: TUIScreen) -> [String] {
        ["q 종료", "r 새로고침"]
            + TUIScreen.allCases.filter { $0 != current }.map { "\($0.key) \($0.title)" }
    }

    static func screenHintLines(current: TUIScreen, width: Int) -> [String] {
        hintLines(screenHintEntries(current: current), width: width)
    }

    /// 목록 화면의 키 안내. **지금 누를 수 있는 것만** 보여 준다(홈의 `sessionHints` 와 같은 규칙).
    ///
    /// `canActOnSelection` 이 거짓이면 커서 동작 키를 뺀다 — 빈 목록이거나, 커서가 이미 나와 있는
    /// 개체를 가리키는 경우다. 눌러도 거절만 돌아오는 키를 권하면 그건 안내가 아니라 함정이다.
    static func listHintLines(screen: TUIScreen, canActOnSelection: Bool,
                              width: Int) -> [String] {
        var keys = ["↑↓/jk 이동"]
        if canActOnSelection {
            switch screen {
            case .party: keys += ["s 교체", "R 놓아주기"]
            case .bag: keys += ["u 쓰기"]
            // 판 화면(홈·웨이브·대전)은 목록이 아니라 이 안내를 쓰지 않는다. 그쪽 키 안내는
            // 국면마다 달라서 각자의 화면 투영이 만든다.
            case .home, .dex, .challenge, .goals, .wave, .battle: break
            }
        }
        return hintLines(keys + screenHintEntries(current: screen), width: width)
    }

    /// 되돌릴 수 없는 동작이 답을 기다리는 줄. **다른 키를 함께 띄우지 않는다** — 그 키를 누르면
    /// 확인이 조용히 취소되는데, 사용자는 자기가 취소했다는 것을 모른다.
    static func confirmationHint(question: String) -> String {
        "\(question). 정말이면 y, 아니면 아무 키나."
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
            lines += screenHintLines(current: .home, width: inner)
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
