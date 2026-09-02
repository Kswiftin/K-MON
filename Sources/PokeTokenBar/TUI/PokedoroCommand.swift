import Foundation

/// `pokedoro <명령>` 파싱 결과. 실행과 분리해 둔 이유는 인자 해석이 **어느 프런트엔드가 뜰지**
/// 가르는 입구라 터미널 없이 전수 검증할 수 있어야 하기 때문이다(`TUIKeymap` 과 같은 이유).
///
/// 전부 읽기 전용이다. 모험 시작·정산·취소는 앱에만 있다 — 앱과 터미널이 같은 세이브에 쓰면
/// 나중 쓰기가 앞 쓰기를 통째로 덮는다(두 프로세스 사이에 잠금이 없다).
enum PokedoroCommand: Equatable, Sendable {
    case status(oneline: Bool)
    case party
    case dex
    case watch
    case help
}

/// 파싱 실패. 화면이 이유를 그대로 띄운다 — "알 수 없는 명령" 하나로 뭉개면 오타와 "여기서는
/// 못 하는 일" 을 구분할 수 없어 사용자가 무엇을 고쳐야 할지 모른다.
enum PokedoroCommandError: Equatable, Error {
    case unknownCommand(String)
    /// 세이브를 바꾸는 명령. 이름은 알지만 터미널에서는 할 수 없다.
    case readOnlyFrontEnd(String)

    var message: String {
        switch self {
        case .unknownCommand(let name): "알 수 없는 명령: \(name)"
        case .readOnlyFrontEnd(let name):
            """
            `\(name)` 은 앱에서 한다. 터미널은 세이브를 읽기만 한다 — 앱과 터미널이 같은 파일에
            쓰면 나중 쓰기가 앞 쓰기를 통째로 덮기 때문이다.
            """
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

    /// 앱에만 있는 명령. 이름을 알아보고 이유를 말하기 위해 목록으로 남긴다 — "알 수 없는 명령"
    /// 으로 답하면 사용자는 오타를 의심하며 같은 명령을 다시 친다.
    static let appOnlyCommands: Set<String> = ["start", "go", "claim", "cancel", "stop"]

    /// 실행 파일 이름을 뺀 인자 배열을 받는다. 빈 배열은 `status` 다 — 인자 없이 친 사용자가
    /// 가장 원하는 것이 현재 상태이기 때문이다.
    static func parse(_ arguments: [String]) throws -> PokedoroCommand {
        var rest = arguments
        // TUI 진입 플래그는 명령 이름 앞에 올 수도 있다(앱 번들 실행 파일을 직접 부르는 경로).
        rest.removeAll { $0 == "--tui" || $0 == "--cli" }
        guard let name = rest.first else { return .status(oneline: false) }
        let options = Set(rest.dropFirst().filter { $0.hasPrefix("--") })

        switch name {
        case "status", "st":
            return .status(oneline: options.contains("--oneline"))
        case "party", "mons": return .party
        case "dex": return .dex
        case "watch", "top": return .watch
        case "help", "--help", "-h": return .help
        default:
            if appOnlyCommands.contains(name) { throw PokedoroCommandError.readOnlyFrontEnd(name) }
            throw PokedoroCommandError.unknownCommand(name)
        }
    }

    static let usage = """
    pokedoro — Pokédoro 를 터미널에서 본다.

      status [--oneline]   파트너·모험·잔액. --oneline 은 상태줄용 한 줄
      party                보유 포켓몬 목록
      dex                  도감
      watch                전체 화면 실시간 보기
      help                 이 도움말

    메뉴바 앱과 같은 세이브를 **읽기만** 한다. 모험 시작·정산·취소는 앱에서 한다 — 두 프로세스가
    같은 파일에 쓰면 나중 쓰기가 앞 쓰기를 통째로 덮기 때문이다.
    """
}
