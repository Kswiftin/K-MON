import Foundation

/// TUI 가 보여주는 화면. 판(홈·웨이브) 둘 + 목록 다섯이다.
enum TUIScreen: String, CaseIterable, Sendable {
    case home, party, dex, bag, challenge, goals
    /// 웨이브 런. 목록이 아니라 **판**이다 — 커서가 없고 숫자 키가 지금 국면의 선택지다.
    case wave

    /// 목록이 있는 화면인가 — 스크롤 키를 받을지 가르는 유일한 기준이다.
    ///
    /// `self != .home` 이 아니라 **판을 열거한다.** 부정형으로 두면 판 화면을 더할 때마다 그
    /// 화면이 조용히 목록이 되어, 아무 데도 안 쓰이는 커서가 움직인다.
    var isList: Bool {
        switch self {
        case .home, .wave: false
        case .party, .dex, .bag, .challenge, .goals: true
        }
    }

    /// 이 화면을 부르는 키. **키 표와 화면 안내가 같은 값을 읽는 자리다** — 두 벌이면 안내에
    /// 있는 키가 아무 일도 안 하거나, 먹는 키가 안내에 없다.
    var key: Character {
        switch self {
        case .home: "h"
        case .party: "p"
        case .dex: "d"
        case .bag: "b"
        // `c` 가 아니다 — 그 키는 홈에서 정산이다. 같은 키를 화면에 따라 조회와 상태 변경으로
        // 가르면 손이 먼저 움직여 누르지 않으려던 쪽이 눌린다.
        case .challenge: "m"
        case .goals: "g"
        case .wave: "w"
        }
    }

    /// 머리글·키 안내에 쓰는 이름. 케이스 옆에 두는 이유는 화면을 더할 때 이름을 빠뜨리면
    /// 컴파일이 막게 하기 위해서다.
    var title: String {
        switch self {
        case .home: "홈"
        case .party: "포켓몬"
        case .dex: "도감"
        case .bag: "가방"
        case .challenge: "도전"
        case .goals: "목표"
        case .wave: "웨이브"
        }
    }

    /// 키 → 화면. 표를 손으로 두 벌 쓰지 않는다.
    static func screen(for key: Character) -> TUIScreen? { allCases.first { $0.key == key } }
}

/// 키가 거절된 이유. `.ignored`(그 화면에 없는 키)와 반드시 구분한다 — 화면이 이유를 띄워야
/// 사용자가 "키가 안 먹는다" 와 "권한이 없다" 를 구분할 수 있다.
enum TUIRejection: Equatable, Sendable {
    /// 터미널은 세이브를 읽기만 한다. 앱과 터미널이 같은 파일에 쓰면 나중 쓰기가 앞 쓰기를
    /// 통째로 덮으므로(잠금이 없다) 쓰기는 앱에만 둔다.
    case readOnly
}

enum TUIAction: Equatable, Sendable {
    case quit
    /// 디스크의 세이브를 다시 읽는다 — 메뉴바 앱이 바꾼 진행을 TUI 로 끌어온다.
    case reload
    case show(TUIScreen)
    case startAdventure(minutes: Int)
    case claimAdventure
    case cancelAdventure
    /// 목록 커서 이동량.
    case scroll(Int)
    /// **커서가 가리키는 행**에 거는 일. 대상을 인자로 안 싣는 이유는 이 표가 로스터·가방을
    /// 모르기 때문이다 — 무엇이 그 자리에 있는지는 화면이 알고, 표는 "무엇을 할지" 만 정한다.
    case useSelected
    case switchToSelected
    case releaseSelected
    /// 웨이브 화면의 숫자 키. **무엇이 되는지는 이 표가 모른다** — 기술인지 보상인지 길인지는
    /// 판의 국면이 정하고, 그 변환은 `WaveRunScreen.action(number:in:)` 한 곳에 있다.
    case waveChoice(Int)
    case throwWaveBall
    /// 판을 버린다 — **되돌릴 수 없다.** 화면이 확인을 한 번 받는다(방생과 같은 규칙).
    case forfeitWaveRun
    /// 되돌릴 수 없는 동작의 승낙·취소.
    case confirm
    case cancelConfirmation
    /// 이 화면에 배정되지 않은 키.
    case ignored
    case rejected(TUIRejection)
}

/// raw mode 로 들어온 입력을 해석한 결과. 화살표는 한 글자가 아니라 이스케이프 시퀀스로 오므로
/// 문자와 같은 층에 둘 수 없다.
enum TUIKey: Equatable, Sendable {
    case char(Character)
    case up, down
    case escape
    /// 아직 다루지 않는 이스케이프 시퀀스(Home·PageUp 등)와 해석할 수 없는 바이트.
    /// **문자로 흘려보내지 않는다** — 예전엔 NUL 문자로 접어서 진짜 NUL 입력과 구분되지 않았다.
    case unknown
}

/// 키 → 동작. **순수 함수로 둔 이유**는 이 표가 세이브를 바꾸는 입구이기 때문이다. 터미널을
/// 띄우지 않고 전수 검증할 수 있어야 "읽기 전용인데 모험이 시작됐다" 부류를 테스트가 잡는다.
enum TUIKeymap {
    /// 세이브를 바꾸는 동작 — 쓰기 권한이 없으면 전부 `.rejected(.readOnly)` 로 돌아간다.
    ///
    /// **지금은 전부 거절된다**(터미널은 읽기 전용이다). 그래도 표를 비워 두지 않는 이유는,
    /// 앱에서 쓰던 키를 터미널에서 누른 사용자가 침묵 대신 이유를 봐야 하기 때문이다 —
    /// `.ignored` 로 접으면 "키가 안 먹는다" 와 구분되지 않는다.
    private static func mutating(_ key: Character) -> TUIAction? {
        switch key {
        case "1": .startAdventure(minutes: 25)
        case "2": .startAdventure(minutes: 50)
        case "3": .startAdventure(minutes: 90)
        case "c": .claimAdventure
        case "x": .cancelAdventure
        default: nil
        }
    }

    /// 웨이브 화면의 키. **홈의 표와 나눠 둔다** — 두 판 화면이 한 표를 쓰면 대전 중에 기술을
    /// 고르려다 25분 집중이 시작된다(숫자 키가 홈에서는 길이다).
    ///
    /// 볼 던지기가 `b` 가 아닌 이유는 그 글자가 **가방 화면 키**라서다. 화면 이동 키가 먼저
    /// 잡히므로 `b` 를 배정하면 아무 데서도 안 먹는 키가 된다.
    private static func waveKey(_ key: Character) -> TUIAction? {
        if let number = key.wholeNumberValue, (1...4).contains(number) {
            return .waveChoice(number)
        }
        switch key {
        case "t": return .throwWaveBall
        case "f": return .forfeitWaveRun
        default: return nil
        }
    }

    /// 커서 행에 거는 동작. **그 화면의 커서가 가리키는 것이 대상이 될 수 있을 때만** 배정한다 —
    /// 가방에서 `s`(교체)가 먹으면 사용자는 무엇이 바뀌었는지 알 수 없다.
    private static func selectionAction(_ key: Character, screen: TUIScreen) -> TUIAction? {
        switch (screen, key) {
        case (.party, "s"): .switchToSelected
        // 대문자다. 소문자 `r` 은 새로고침이라 되돌릴 수 없는 동작이 한 글자 옆에 있으면 안 되고,
        // Shift 를 함께 누르는 것 자체가 "의도한 입력" 이라는 뜻이다.
        case (.party, "R"): .releaseSelected
        case (.bag, "u"): .useSelected
        default: nil
        }
    }

    /// `awaitingConfirmation` 은 되돌릴 수 없는 동작이 답을 기다리는 상태다. 그동안 **`y` 외의
    /// 모든 키는 취소**다 — 평소 먹는 키(종료·이동)가 그대로 먹으면 확인 창을 띄운 채 다른 일이
    /// 일어나고, 사용자는 자기가 무엇에 답했는지 알 수 없다.
    static func action(for key: TUIKey, screen: TUIScreen, canWrite: Bool,
                       awaitingConfirmation: Bool = false) -> TUIAction {
        if awaitingConfirmation {
            if case .char("y") = key { return .confirm }
            return .cancelConfirmation
        }
        switch key {
        case .escape:
            return screen == .home ? .quit : .show(.home)
        case .up:
            return screen.isList ? .scroll(-1) : .ignored
        case .down:
            return screen.isList ? .scroll(1) : .ignored
        case .char(let character):
            return action(forCharacter: character, screen: screen, canWrite: canWrite)
        case .unknown:
            return .ignored
        }
    }

    private static func action(forCharacter character: Character,
                               screen: TUIScreen, canWrite: Bool) -> TUIAction {
        // 화면과 무관한 키가 먼저다 — 읽기 전용이어도 보기·나가기는 막지 않는다.
        switch character {
        case "q": return .quit
        case "r": return .reload
        default: break
        }
        // 이동 키는 화면 표에서 읽는다 — 여기 손으로 적으면 화면을 더할 때 키가 빠지고,
        // 안내(`TUIRender.screenHints`)와 갈라진 걸 알아챌 방법은 손으로 맞대 보는 것뿐이다.
        if let next = TUIScreen.screen(for: character) { return .show(next) }
        // **화면마다 자기 표를 고른다.** 예전엔 "목록이 아니면 홈" 이라 새 판 화면이 홈의 키를
        // 조용히 물려받았다 — 웨이브 화면의 1·2·3 이 집중 세션을 켰다.
        switch screen {
        case .party, .dex, .bag, .challenge, .goals:
            // 커서 동작은 쓰기다 — 권한이 없으면 침묵이 아니라 거절로 돌아온다.
            if let selection = selectionAction(character, screen: screen) {
                return canWrite ? selection : .rejected(.readOnly)
            }
            // vi 키는 목록에서만 산다. 홈에서 j/k 를 받으면 아무 데도 안 쓰이는 커서가 움직인다.
            switch character {
            case "j": return .scroll(1)
            case "k": return .scroll(-1)
            default: return .ignored
            }
        case .wave:
            guard let action = waveKey(character) else { return .ignored }
            return canWrite ? action : .rejected(.readOnly)
        case .home:
            // 모험 키는 홈 전용이다. 도감을 넘기다 실수로 세션이 시작되면 안 된다.
            guard let action = mutating(character) else { return .ignored }
            return canWrite ? action : .rejected(.readOnly)
        }
    }

    /// 목록 커서 이동. 범위를 벗어난 인덱스는 그대로 배열 첨자로 쓰이므로 여기서 막는다.
    /// 빈 목록의 선택은 0 이다 — -1 을 돌려주면 렌더가 그 값으로 인덱싱해 크래시한다.
    static func clamp(selection: Int, delta: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return min(count - 1, max(0, selection + delta))
    }
}
