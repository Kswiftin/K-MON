import Foundation

/// TUI 가 보여주는 화면. 홈 하나 + 목록 둘이다.
enum TUIScreen: String, CaseIterable, Sendable {
    case home, party, dex

    /// 목록이 있는 화면인가 — 스크롤 키를 받을지 가르는 유일한 기준이다.
    var isList: Bool { self != .home }
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

    static func action(for key: TUIKey, screen: TUIScreen, canWrite: Bool) -> TUIAction {
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
        case "h": return .show(.home)
        case "p": return .show(.party)
        case "d": return .show(.dex)
        default: break
        }
        if screen.isList {
            // vi 키는 목록에서만 산다. 홈에서 j/k 를 받으면 아무 데도 안 쓰이는 커서가 움직인다.
            switch character {
            case "j": return .scroll(1)
            case "k": return .scroll(-1)
            default: return .ignored
            }
        }
        // 모험 키는 홈 전용이다. 도감을 넘기다 실수로 세션이 시작되면 안 된다.
        guard let action = mutating(character) else { return .ignored }
        return canWrite ? action : .rejected(.readOnly)
    }

    /// 목록 커서 이동. 범위를 벗어난 인덱스는 그대로 배열 첨자로 쓰이므로 여기서 막는다.
    /// 빈 목록의 선택은 0 이다 — -1 을 돌려주면 렌더가 그 값으로 인덱싱해 크래시한다.
    static func clamp(selection: Int, delta: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return min(count - 1, max(0, selection + delta))
    }
}
