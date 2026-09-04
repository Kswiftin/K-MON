import Foundation

/// Memory Home 을 터미널에 보여 주기 위한 **값 한 벌.**
///
/// 형제 넷(대전·방·교환·경매)과 갈리는 지점: 이 값은 **앱이 보내 주지 않는다.** 앨범은 세이브
/// 옆 파일(`memory.json`)에 저장되므로 터미널이 읽기 전용으로 직접 읽어 조립한다
/// (`CompanionStore.homeTerminalState`) — 웨이브 런과 같은 쪽이고, 그래서 `pokedoro home` 은
/// 앱이 꺼져 있어도 답한다.
///
/// **픽셀 아트는 옮기지 않는다.** 방의 그림·창밖 배색·스프라이트 위치는 터미널이 그릴 수 있는
/// 물건이 아니다. 남는 것은 사람이 읽는 사실 — 무엇이 놓여 있고, 어느 스타일이며, 누가 같이
/// 살고, 무엇이 기억에 남았는지다.
struct HomeTerminalState {
    var nickname: String
    /// 대문 문구. `nil` 은 아직 안 적었다는 뜻이다.
    var message: String?
    var visitToday = 0
    var visitTotal = 0
    /// 계절 이름. **달력 월에서 파생**하므로 저장 필드가 없다(이 홈의 설계 원칙).
    var seasonName = ""
    var isLANOpen = false

    /// 동행. `nil` 이면 아직 알을 품고 있다 — 앱은 "동행을 기다리고 있어요" 를 띄운다.
    var companionName: String?
    var daysTogether = 0
    var memoryCount = 0
    /// 다섯 칸 하트. 판정은 앨범이 하고(`pokeLog`) 여기선 개수만 든다.
    var closenessHearts = 0
    /// 오늘의 기분. `nil` 은 아직 안 골랐다 — 방 문구가 이 값으로 갈리므로 화면이 먼저 권한다.
    var moodName: String?

    var styleName: String
    var styles: [HomeScreen.Style] = []
    var placed: [HomeScreen.Placed] = []
    /// 배치 상한(12). 화면과 실행기가 같은 값을 본다.
    var decorLimit = 0
    var roommates: [String] = []
    /// §5 §17 §24 한 줄. 판정은 전부 `MemoryHomeRoomLife` 에 있다.
    var roomLine = ""

    var pinned: String?
    var recent: [String] = []
    /// 열린 추억 카드 제목.
    var cards: [String] = []
    var canUndo = false
    var canRedo = false

    init(nickname: String, styleName: String) {
        self.nickname = nickname
        self.styleName = styleName
    }
}

/// Memory Home 을 터미널 한 판으로 접는다. **부수효과 없음.**
enum HomeScreen {
    /// 방 스타일 한 줄. 잠긴 것도 **조건을 달고** 나온다 — 고를 수 있는 것처럼 찍으면 쳐도
    /// 아무 일이 없고, 그건 안내가 아니라 함정이다.
    struct Style: Equatable, Sendable {
        var name: String
        var isUnlocked: Bool
        var isActive: Bool
        var requirement: String
    }

    /// 놓인 가구 하나. **번호와 id 를 함께 든다** — 화면은 번호를 찍고 실행기는 id 로 치우는데,
    /// 두 값을 따로 구하면 목록이 다시 읽히는 사이 다른 가구가 사라진다.
    struct Placed: Equatable, Sendable {
        var number: Int
        var id: UUID
        /// 격자 칸 번호(1–48).
        var cell: Int
        var label: String
    }

    // MARK: 격자

    static let columns = 8
    static let rowCount = 6
    /// 방 격자의 칸 수. **번호 공간을 하나로 두기 위해** 열·행이 아니라 칸 번호로 받는다 —
    /// 두 인자로 받으면 터미널에 "서로 다른 뜻의 번호" 자리가 하나 더 늘어난다(경매에서 넷까지
    /// 겪었고, 그때마다 사용자가 고른 것과 다른 것이 움직였다).
    static let cellCount = columns * rowCount

    /// 칸 번호 → 격자 좌표. **접는 자리가 여기 하나뿐이다.** 격자 밖은 접지 않는다 — 그대로
    /// 좌표로 쓰면 방 밖에 가구가 놓인다.
    static func gridPoint(cell: Int) -> (Int, Int)? {
        guard (1...cellCount).contains(cell) else { return nil }
        let index = cell - 1
        return (index % columns, index / columns)
    }

    /// 격자 좌표 → 칸 번호. 화면이 놓인 가구의 칸을 찍을 때 쓴다 — 위 함수의 역이라, 둘이
    /// 어긋나면 사용자가 본 칸과 실제 칸이 다르다(왕복을 테스트가 전 칸에서 확인한다).
    static func cell(column: Int, row: Int) -> Int { row * columns + column + 1 }

    /// 놓인 가구 번호 → id.
    static func placedID(number: Int, in state: HomeTerminalState) -> UUID? {
        state.placed.first { $0.number == number }?.id
    }

    // MARK: 안내

    static func title(_ state: HomeTerminalState) -> String { "\(state.nickname) 의 포케 홈" }

    /// **누를 키가 없다.** 번호 공간이 셋이라(개체·격자 칸·놓인 가구) 숫자 한 자리로는 어느
    /// 것인지 정할 수 없다 — 경매와 같은 근거다. 칠 명령은 `hints` 가 줄에 싣는다.
    static func keys(_ state: HomeTerminalState) -> [String] { [] }

    static func hints(_ state: HomeTerminalState) -> String {
        // 기분이 먼저다 — 방 문구와 동행 반응이 이 값으로 갈린다.
        if state.moodName == nil {
            return "오늘의 기분을 고른다 — home mood <"
                + MemoryHomeMood.allCases.map(\.rawValue).joined(separator: "|") + ">"
        }
        if state.canUndo {
            return "방금 꾸민 것을 되돌린다 — home undo   (home place <가구> <칸>)"
        }
        if state.placed.isEmpty {
            return "가구를 놓는다 — home place <가구> <칸 1-\(cellCount)>   (bag 이 이름을 찍는다)"
        }
        return "home place <가구> <칸>   home remove <번호>   home note <글>"
    }

    // MARK: 줄

    static func lines(_ state: HomeTerminalState, width: Int) -> [String] {
        let inner = max(1, width)
        var lines = [TUIRender.row(left: title(state),
                                   right: "오늘 \(TUIRender.number(state.visitToday))"
                                       + " · 전체 \(TUIRender.number(state.visitTotal))",
                                   width: inner),
                     TUIRender.rule(width: inner)]
        if let message = state.message {
            lines.append(TUIText.truncate(message, to: inner))
        }
        lines.append(TUIRender.row(left: state.seasonName,
                                   right: state.isLANOpen ? "LAN 공개" : "LAN 차단", width: inner))
        lines += companionLines(state, width: inner)
        lines += roomLines(state, width: inner)
        lines += memoryLines(state, width: inner)
        lines.append(TUIText.truncate(hints(state), to: inner))
        return lines
    }

    private static func companionLines(_ state: HomeTerminalState, width: Int) -> [String] {
        guard let companion = state.companionName else {
            // 앱은 "동행을 기다리고 있어요" 를 띄운다. 빈 줄을 내면 사용자는 화면이 고장난 줄 안다.
            return [TUIText.truncate("동행을 기다리는 중이다 — 알이 부화하면 방이 채워진다", to: width)]
        }
        var lines = [TUIRender.row(left: companion,
                                   right: "함께 \(TUIRender.number(state.daysTogether))일",
                                   width: width)]
        let hearts = String(repeating: "♥", count: max(0, min(5, state.closenessHearts)))
            + String(repeating: "♡", count: max(0, 5 - state.closenessHearts))
        lines.append(TUIRender.row(left: "친밀도  " + hearts,
                                   right: "기억 \(TUIRender.number(state.memoryCount))개",
                                   width: width))
        lines.append(TUIRender.row(left: "기분", right: state.moodName ?? "아직 안 골랐다",
                                   width: width))
        return lines
    }

    private static func roomLines(_ state: HomeTerminalState, width: Int) -> [String] {
        var lines = [TUIRender.rule(width: width),
                     TUIRender.row(left: "방 스타일", right: state.styleName, width: width)]
        lines += state.styles.map { style in
            TUIRender.row(left: " " + style.name,
                          right: style.isActive ? "사용 중"
                              : (style.isUnlocked ? "고를 수 있다" : style.requirement),
                          width: width)
        }
        lines.append(TUIText.truncate(
            "놓인 가구 \(state.placed.count)/\(state.decorLimit)", to: width))
        lines += state.placed.map {
            TUIRender.row(left: " \($0.number) \($0.label)", right: "칸 \($0.cell)", width: width)
        }
        if !state.roommates.isEmpty {
            lines.append(TUIText.truncate("룸메이트  " + state.roommates.joined(separator: ", "),
                                          to: width))
        }
        if !state.roomLine.isEmpty {
            lines.append(TUIText.truncate(state.roomLine, to: width))
        }
        return lines
    }

    private static func memoryLines(_ state: HomeTerminalState, width: Int) -> [String] {
        var lines = [TUIRender.rule(width: width)]
        lines.append(TUIRender.row(left: "기억",
                                   right: state.cards.isEmpty ? "" : "카드 \(state.cards.count)장",
                                   width: width))
        if let pinned = state.pinned {
            lines.append(TUIText.truncate(" 고정  \(pinned)", to: width))
        }
        lines += state.recent.map { TUIText.truncate(" · \($0)", to: width) }
        if !state.cards.isEmpty {
            lines.append(TUIText.truncate(" " + state.cards.joined(separator: " · "), to: width))
        }
        return lines
    }
}
