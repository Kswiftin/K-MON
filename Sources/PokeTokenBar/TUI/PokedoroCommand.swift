import Foundation

/// `pokedoro <명령>` 파싱 결과. 실행과 분리해 둔 이유는 인자 해석이 **어느 프런트엔드가 뜰지**
/// 가르는 입구라 터미널 없이 전수 검증할 수 있어야 하기 때문이다(`TUIKeymap` 과 같은 이유).
///
/// 조회 명령은 세이브를 읽기 전용으로 열고, 집중 세션 세 동작은 **앱에 요청을 보낸다**
/// (`PokedoroRequestBus`). 터미널이 세이브에 직접 쓰는 경로는 여전히 없다 — 두 프로세스가 같은
/// 파일에 쓰면 나중 쓰기가 앞 쓰기를 통째로 덮는다(잠금이 없다).
enum PokedoroCommand: Equatable, Sendable {
    case status(oneline: Bool)
    case party
    case dex
    case bag
    /// 도전 — 던전 실적·배지·미션·시즌. 앱의 도전 탭이 한 화면에 두는 것과 같은 묶음이다.
    case challenge
    /// 도감 목표·업적. 둘 다 "다음에 무엇을 노릴까" 를 답하는 값이라 한 화면이다.
    case goals
    /// 개체 상세. 번호는 `party` 가 찍는 값(1부터)이고, 없으면 파트너다.
    case mon(number: Int?)
    case watch
    case help
    /// 분을 안 적으면 `nil` 이다 — 기본 길이는 실행기가 고른다. 여기서 25 를 박으면 기본값이
    /// 두 곳이 되고, 한쪽만 바뀌면 화면과 터미널이 다른 길이를 켠다.
    case start(minutes: Int?)
    case claim
    case stop

    /// 앱에 요청을 보내는 명령인가. 나머지는 세이브를 읽기 전용으로 열고 끝난다.
    var request: PokedoroRequest.Verb? {
        switch self {
        case .start: .start
        case .claim: .claim
        case .stop: .stop
        case .status, .party, .dex, .bag, .challenge, .goals, .mon, .watch, .help: nil
        }
    }
}

/// 파싱 실패. 화면이 이유를 그대로 띄운다 — "알 수 없는 명령" 하나로 뭉개면 오타와 "여기서는
/// 못 하는 일" 을 구분할 수 없어 사용자가 무엇을 고쳐야 할지 모른다.
enum PokedoroCommandError: Equatable, Error {
    case unknownCommand(String)
    /// 앱 화면에만 있는 기능. 이름은 알지만 터미널에서는 할 수 없다.
    case appOnlyFeature(String)
    /// 숫자가 아닌 집중 길이. **조용히 접지 않는다** — 기본값으로 접으면 사용자는 자기가 무엇을
    /// 켰는지 모른 채 같은 오타를 반복한다.
    case invalidMinutes(String)
    /// 숫자가 아닌 개체 번호. 같은 부류지만 오류를 나눠 두는 이유는 **다음에 할 일이 다르기**
    /// 때문이다 — 길이는 정해진 셋 중 하나를 골라야 하고, 번호는 `party` 가 찍어 준 값을 봐야 한다.
    case invalidMonNumber(String)

    var message: String {
        switch self {
        case .unknownCommand(let name): "알 수 없는 명령: \(name)"
        case .appOnlyFeature(let name):
            "`\(name)` 은 앱 화면에서 한다. 터미널이 다루는 것은 조회와 집중 세션이다."
        case .invalidMinutes(let raw):
            "집중 길이가 숫자가 아니다: \(raw) — "
                + PokemonChatTool.focusMinutes.map(String.init).joined(separator: "·")
                + " 중 하나를 쓴다."
        case .invalidMonNumber(let raw):
            "개체 번호가 숫자가 아니다: \(raw) — `party` 가 찍는 번호를 쓴다."
        }
    }
}

enum PokedoroCommandParser {
    /// 이 인자로 뜬 프로세스가 터미널 프런트엔드인가.
    ///
    /// **파싱 성공 여부로 가르면 안 된다.** 명령 이름을 잘못 치면 파싱이 실패하는데, 그때 메뉴바
    /// 앱이 뜨면 사용자는 오타를 알 방법이 없다(실제로 `pokedoro bogus` 가 앱을 띄웠다). 대신
    /// **어디서 불렸는지**로 가른다: 셸에서 친 인자는 `-` 로 시작하지 않고, macOS 가 앱 번들에
    /// 붙이는 인자(`-NSDocumentRevisionsDebugMode`·`-psn_…`)는 항상 `-` 로 시작한다. 모르는 `-`
    /// 인자는 앱으로 보낸다 — 시스템 인자 때문에 앱이 안 뜨는 쪽이 훨씬 나쁜 고장이다.
    ///
    /// AppKit 을 import 하는 파일이 아니라 여기 두는 이유는 이 규칙을 터미널 없이 검증하기
    /// 위해서다. 진입 판별은 앱이 뜨느냐 마느냐를 가르는 분기라 테스트가 닿아야 한다.
    static func isTerminalInvocation(_ arguments: [String]) -> Bool {
        guard let first = arguments.first else { return false }
        if terminalFlags.contains(first) { return true }
        return !first.hasPrefix("-")
    }

    /// `-` 로 시작하지만 터미널 진입으로 봐야 하는 인자. 이 목록 밖의 `-` 인자는 macOS 가 앱
    /// 번들에 붙인 것으로 보고 메뉴바 앱으로 보낸다.
    static let terminalFlags: Set<String> = ["--tui", "--cli", "--help", "-h"]

    /// 앱 화면에만 있는 기능. 이름을 알아보고 이유를 말하기 위해 목록으로 남긴다 — "알 수 없는
    /// 명령" 으로 답하면 사용자는 오타를 의심하며 같은 명령을 다시 친다.
    ///
    /// 집중 세션(`start`·`claim`·`stop`)은 이제 여기 없다. 터미널이 요청을 보내고 앱이 실행한다.
    static let appOnlyCommands: Set<String> = ["battle", "trade", "auction", "home", "raid", "shop"]

    /// 실행 파일 이름을 뺀 인자 배열을 받는다. 빈 배열은 `status` 다 — 인자 없이 친 사용자가
    /// 가장 원하는 것이 현재 상태이기 때문이다.
    static func parse(_ arguments: [String]) throws -> PokedoroCommand {
        var rest = arguments
        // TUI 진입 플래그는 명령 이름 앞에 올 수도 있다(앱 번들 실행 파일을 직접 부르는 경로).
        rest.removeAll { $0 == "--tui" || $0 == "--cli" }
        guard let name = rest.first else { return .status(oneline: false) }
        let tail = Array(rest.dropFirst())
        let options = Set(tail.filter { $0.hasPrefix("--") })

        switch name {
        case "status", "st":
            return .status(oneline: options.contains("--oneline"))
        case "party", "mons": return .party
        case "dex": return .dex
        case "bag", "items": return .bag
        case "challenge", "ch": return .challenge
        case "goals", "goal": return .goals
        case "mon": return .mon(number: try number(in: tail, orThrow: PokedoroCommandError.invalidMonNumber))
        case "watch", "top": return .watch
        case "help", "--help", "-h": return .help
        case "start", "go":
            return .start(minutes: try number(in: tail, orThrow: PokedoroCommandError.invalidMinutes))
        case "claim": return .claim
        case "stop", "cancel": return .stop
        default:
            if appOnlyCommands.contains(name) { throw PokedoroCommandError.appOnlyFeature(name) }
            throw PokedoroCommandError.unknownCommand(name)
        }
    }

    /// 명령 뒤의 숫자 인자. **없으면 `nil`, 숫자가 아니면 오류다.** 조용히 기본값으로 접으면
    /// `start 5o` 가 25분을 켜고, 사용자는 자기 오타를 영영 못 본다.
    ///
    /// 검사는 한 곳이고 **오류는 부르는 쪽이 준다** — 길이와 번호는 다음에 할 일이 다르므로
    /// 문구도 달라야 하지만, 자릿수 검사가 두 벌이 되면 한쪽만 관대해진다.
    ///
    /// 범위는 여기서 안 본다 — 집중 길이를 접는 표는 `PokemonChatTool.nearestFocusLength` 하나이고,
    /// 그 표는 요청 파일을 손으로 고친 경우까지 막아야 해서 실행기 쪽에 있어야 한다. 개체 번호의
    /// 상한도 로스터를 아는 쪽(`PokedoroCLI`)이 본다.
    private static func number(in arguments: [String],
                               orThrow error: (String) -> PokedoroCommandError) throws -> Int? {
        guard let raw = arguments.first(where: { !$0.hasPrefix("--") }) else { return nil }
        guard raw.allSatisfy(\.isASCII), raw.allSatisfy(\.isNumber), let value = Int(raw) else {
            throw error(raw)
        }
        return value
    }

    private static let lengths = PokemonChatTool.focusMinutes.map(String.init).joined(separator: "|")

    /// 왼쪽 칸을 **손으로 맞추지 않는다** — `start [25|50|90]` 은 길이 목록에서 나오므로 목록이
    /// 바뀌면 손으로 맞춘 공백은 그 자리에서 어긋난다(실제로 2칸 어긋난 채로 나갔다).
    private static let commandColumn = 21

    private static let rows: [(String, String)] = [
        ("status [--oneline]", "파트너·모험·잔액. --oneline 은 상태줄용 한 줄"),
        ("party", "보유 포켓몬 목록"),
        ("mon [번호]", "개체 상세 (생략하면 파트너)"),
        ("dex", "도감"),
        ("bag", "가방 — 보유 아이템"),
        ("challenge", "도전 — 던전 실적·배지·미션·시즌"),
        ("goals", "도감 목표·업적"),
        ("watch", "전체 화면 실시간 보기"),
        ("start [\(lengths)]", "집중 세션 시작 (생략하면 \(PokemonChatTool.focusMinutes[0])분)"),
        ("claim", "끝난 모험의 보상 받기"),
        ("stop", "집중 세션 끝내기"),
        ("help", "이 도움말"),
    ]

    static let usage = """
    pokedoro — Pokédoro 를 터미널에서 본다.

    \(rows.map { "  " + TUIText.pad($0.0, to: commandColumn) + $0.1 }.joined(separator: "\n"))

    조회는 세이브를 읽기만 한다. 집중 세션 세 동작은 **메뉴바 앱에 요청을 보내고** 앱이 실행한다
    — 세이브에 쓰는 프로세스를 하나로 두기 위해서다. 앱이 꺼져 있으면 요청은 실행되지 않는다.
    """
}
