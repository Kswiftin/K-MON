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
    /// 아이템 하나 사용. 파서가 **닫힌 목록**(`ItemKind.named`)을 이미 지났으므로 여기 담긴
    /// 종류는 늘 실행할 수 있는 값이다 — 문자열을 담으면 실행 못 하는 명령이 통과하고, 그 명령의
    /// 요청은 `nil` 이 되어 조용한 무동작이 된다.
    case use(item: ItemKind)
    case evolve
    /// `party` 가 찍는 번호(1부터).
    case switchCompanion(number: Int)
    case rename(nickname: String)
    /// 상점 재고. 조회라 세이브를 읽기만 한다.
    case shop
    case buy(good: ShopGood, quantity: Int)
    case hatch
    /// **되돌릴 수 없다.** `confirmed` 가 거짓이면 요청이 되지 않고, 화면이 무엇을 잃는지 먼저
    /// 보여 준 뒤 거절한다 — 오타 한 번이 개체를 영영 지우면 안 된다.
    case release(number: Int, confirmed: Bool)

    // MARK: 웨이브 런
    //
    // 하위 명령이 하나의 접두어(`wave`) 아래 산다. `move`·`pick` 같은 흔한 낱말을 최상위에 두면
    // 다음 라이브 기능(PvP·레이드)이 같은 낱말을 쓰고 싶을 때 이름이 이미 팔려 있다.

    /// 진행 중인 판. **조회다** — 판은 세이브에 남으므로(`CompanionStore.rogueRun`) 터미널이
    /// 스스로 읽는다. 화면 채널(`PokedoroViewChannel`)은 세이브에 **없는** 값을 위한 통로다.
    case wave
    case waveStart(starter: Int?)
    case waveMove(move: Int, target: Int?)
    case waveSwitch(number: Int)
    case waveBall(target: Int?)
    case wavePick(number: Int)
    case waveRoute(RunRoute)
    /// **되돌릴 수 없다.** 판이 사라지므로 방생과 같은 규칙으로 `--yes` 를 받는다.
    case waveForfeit(confirmed: Bool)

    /// 앱에 부탁할 일. `nil` 이면 세이브를 읽기 전용으로 열고 끝나는 조회 명령이다.
    ///
    /// **인자를 여기서 함께 넘긴다.** 예전엔 동작만 돌려주고 부르는 쪽이 분을 다시 꺼냈는데,
    /// 그러면 명령을 더할 때 인자 꺼내는 자리를 빠뜨려도 컴파일이 통과한다.
    var request: PokedoroRequest.Action? {
        switch self {
        case .start(let minutes): .start(minutes: minutes)
        case .claim: .claim
        case .stop: .stop
        case .use(let item): .use(item: item)
        case .evolve: .evolve
        case .switchCompanion(let number): .switchCompanion(number: number)
        case .rename(let nickname): .rename(nickname: nickname)
        case .buy(let good, let quantity): .buy(good: good, quantity: quantity)
        case .hatch: .hatch
        // 확인 없는 방생은 **요청이 아니다.** 여기서 nil 을 돌려주면 CLI 가 읽기 전용 경로로
        // 내려가 무엇을 잃는지 보여 주고 거절한다.
        case .release(let number, let confirmed): confirmed ? .release(number: number) : nil
        case .waveStart(let starter): .waveStart(starter: starter)
        case .waveMove(let move, let target): .waveMove(move: move, target: target)
        case .waveSwitch(let number): .waveSwitch(number: number)
        case .waveBall(let target): .waveBall(target: target)
        case .wavePick(let number): .wavePick(number: number)
        case .waveRoute(let route): .waveRoute(route)
        // 확인 없는 포기는 방생과 같이 **요청이 아니다** — 무엇을 잃는지 먼저 보여 주고 거절한다.
        case .waveForfeit(let confirmed): confirmed ? .waveForfeit : nil
        case .status, .party, .dex, .bag, .challenge, .goals, .mon, .shop, .watch, .help, .wave: nil
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
    /// 인자가 필요한 명령을 인자 없이 쳤다. 조용히 아무것도 안 하면 사용자는 명령이 먹었는지조차
    /// 모른다.
    case missingArgument(String)
    /// 인자를 받지 않는 명령에 인자가 붙었다. 버리고 실행하면 사용자는 그 값이 뭔가 했다고 믿는다.
    case unexpectedArgument(String)
    /// 인자는 받지만 **개수가 많다**. `unexpectedArgument` 로 접으면 "인자를 받지 않는다" 고
    /// 말하게 되는데 `wave move 1 2` 는 정상 입력이다 — 문구가 사실이 아닌 것을 주장하면
    /// 사용자는 맞는 사용법을 의심한다(`switch 0` 의 "숫자가 아니다" 와 같은 부류).
    case tooManyArguments(String)
    /// 목록 밖 아이템 이름. **어디서 이름을 얻는지** 같이 말한다.
    case unknownItem(String)
    /// 상점이 팔지 않는 물건.
    case unknownGood(String)
    /// 웨이브 런의 번호가 아니다. 개체 번호와 오류를 나눠 두는 이유와 같다 — **어디서 번호를
    /// 얻는지가 다르다**(`party` 가 아니라 `wave` 가 찍는다).
    case invalidWaveNumber(String)
    /// 목록 밖 길 이름. 안전한 길로 접지 않는 이유는 사용자가 위험한 길을 골랐다고 믿은 채
    /// 보상 한 장을 잃기 때문이다.
    case unknownRoute(String)

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
            "개체 번호가 아니다: \(raw) — `party` 가 찍는 번호(1부터)를 쓴다."
        case .missingArgument(let name):
            "`\(name)` 은 인자가 필요하다. `pokedoro help` 로 쓰는 법을 본다."
        case .unexpectedArgument(let name):
            "`\(name)` 은 인자를 받지 않는다."
        case .tooManyArguments(let name):
            "`\(name)` 에 인자가 너무 많다. `pokedoro help` 로 쓰는 법을 본다."
        case .unknownItem(let raw):
            "그런 아이템이 없다: \(raw) — `pokedoro bag` 이 찍는 이름을 쓴다."
        case .unknownGood(let raw):
            "상점에 그런 물건이 없다: \(raw) — `pokedoro shop` 이 찍는 이름을 쓴다."
        case .invalidWaveNumber(let raw):
            "웨이브 런의 번호가 아니다: \(raw) — `pokedoro wave` 가 찍는 번호(1부터)를 쓴다."
        case .unknownRoute(let raw):
            "그런 길이 없다: \(raw) — "
                + RunRoute.allCases.map(\.rawValue).joined(separator: "·") + " 중 하나를 쓴다."
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
    static let appOnlyCommands: Set<String> = ["battle", "trade", "auction", "home", "raid"]

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
        case "mon": return .mon(number: try rosterNumber(in: tail))
        case "watch", "top": return .watch
        case "help", "--help", "-h": return .help
        case "start", "go":
            return .start(minutes: try number(in: tail, orThrow: PokedoroCommandError.invalidMinutes))
        case "claim": return .claim
        case "stop", "cancel": return .stop
        case "use":
            let raw = try text(in: tail, command: name)
            guard let item = ItemKind.named(raw) else { throw PokedoroCommandError.unknownItem(raw) }
            return .use(item: item)
        case "evolve":
            try rejectArgument(in: tail, command: name)
            return .evolve
        case "switch":
            return .switchCompanion(number: try requiredRosterNumber(in: tail, command: name))
        case "name", "nickname":
            return .rename(nickname: try text(in: tail, command: name))
        case "shop":
            return .shop
        case "buy":
            return try purchase(in: tail, command: name)
        case "hatch":
            try rejectArgument(in: tail, command: name)
            return .hatch
        case "release":
            return .release(number: try requiredRosterNumber(in: tail, command: name),
                            confirmed: options.contains("--yes"))
        case "wave":
            return try waveCommand(in: tail, options: options)
        default:
            if appOnlyCommands.contains(name) { throw PokedoroCommandError.appOnlyFeature(name) }
            throw PokedoroCommandError.unknownCommand(name)
        }
    }

    /// 명령 뒤의 글자 인자. 조각을 **다시 이어 붙인다** — 셸은 `use 이상한 사탕` 을 인자 두 개로
    /// 주므로, 첫 조각만 읽으면 아이템 이름의 절반으로 목록을 뒤지고 늘 실패한다(따옴표를 쳐야만
    /// 되는 명령은 안내 없이는 아무도 모른다).
    private static func text(in arguments: [String], command: String) throws -> String {
        let words = arguments.filter { !$0.hasPrefix("--") }
        guard !words.isEmpty else { throw PokedoroCommandError.missingArgument(command) }
        return words.joined(separator: " ")
    }

    /// `buy <이름> [수량]`. 수량은 이름 **뒤**에 붙는다 — 이름이 여러 조각인 물건이 있으므로
    /// 마지막 조각이 숫자일 때만 수량으로 본다(요청 파일 파서와 같은 규칙).
    private static func purchase(in arguments: [String], command: String) throws -> PokedoroCommand {
        var words = arguments.filter { !$0.hasPrefix("--") }
        guard !words.isEmpty else { throw PokedoroCommandError.missingArgument(command) }
        var quantity = 1
        if words.count > 1, let last = words.last, let value = Int(last), last.allSatisfy(\.isNumber) {
            guard value >= 1 else { throw PokedoroCommandError.invalidMonNumber(last) }
            quantity = value
            words.removeLast()
        }
        let raw = words.joined(separator: " ")
        guard let good = ShopCatalog.named(raw) else { throw PokedoroCommandError.unknownGood(raw) }
        return .buy(good: good, quantity: quantity)
    }

    /// `wave <하위 명령> [번호…]`. 하위 명령이 없으면 조회다 — 인자 없이 친 사용자가 가장 원하는
    /// 것이 지금 판의 상태이기 때문이다(최상위 `pokedoro` 가 `status` 인 것과 같은 규칙).
    private static func waveCommand(in arguments: [String],
                                    options: Set<String>) throws -> PokedoroCommand {
        let words = arguments.filter { !$0.hasPrefix("--") }
        guard let sub = words.first else { return .wave }
        let rest = Array(words.dropFirst())
        let command = "wave \(sub)"
        switch sub {
        case "start":
            try rejectExtra(rest, beyond: 1, command: command)
            return .waveStart(starter: try waveNumber(in: rest))
        case "move":
            try rejectExtra(rest, beyond: 2, command: command)
            guard let move = try waveNumber(in: rest) else {
                throw PokedoroCommandError.missingArgument(command)
            }
            return .waveMove(move: move, target: try waveNumber(in: Array(rest.dropFirst())))
        case "switch":
            try rejectExtra(rest, beyond: 1, command: command)
            return .waveSwitch(number: try requiredWaveNumber(in: rest, command: command))
        case "ball":
            try rejectExtra(rest, beyond: 1, command: command)
            return .waveBall(target: try waveNumber(in: rest))
        case "pick":
            try rejectExtra(rest, beyond: 1, command: command)
            return .wavePick(number: try requiredWaveNumber(in: rest, command: command))
        case "route":
            try rejectExtra(rest, beyond: 1, command: command)
            guard let raw = rest.first else { throw PokedoroCommandError.missingArgument(command) }
            guard let route = RunRoute(rawValue: raw) else {
                throw PokedoroCommandError.unknownRoute(raw)
            }
            return .waveRoute(route)
        case "forfeit":
            try rejectExtra(rest, beyond: 0, command: command)
            return .waveForfeit(confirmed: options.contains("--yes"))
        // **오타로 말한다.** `wave` 를 통째로 모르는 명령으로 접으면 사용자는 기능 자체가 없다고 읽는다.
        default:
            throw PokedoroCommandError.unknownCommand(command)
        }
    }

    /// 남는 인자는 버리지 않는다 — 버리고 실행하면 사용자는 그 값이 뭔가 했다고 믿는다.
    ///
    /// 인자를 **하나도** 안 받는 하위 명령과 **개수가 넘친** 경우를 갈라 말한다. 하나로 뭉개면
    /// `wave move 1 2 3` 에 "인자를 받지 않는다" 고 답하는데, 그건 사실이 아니라 사용자가
    /// 맞는 사용법(`wave move 1 2`)까지 의심하게 된다.
    private static func rejectExtra(_ words: [String], beyond limit: Int,
                                    command: String) throws {
        guard words.count > limit else { return }
        throw limit == 0 ? PokedoroCommandError.unexpectedArgument(command)
                         : PokedoroCommandError.tooManyArguments(command)
    }

    /// `wave` 가 찍는 번호(1부터). 오류를 개체 번호와 나눠 두는 이유는 **어디서 번호를 얻는지가
    /// 다르기** 때문이다 — `party` 를 보라고 하면 다른 목록을 뒤지게 된다.
    private static func waveNumber(in arguments: [String]) throws -> Int? {
        guard let value = try number(in: arguments, orThrow: PokedoroCommandError.invalidWaveNumber)
        else { return nil }
        guard value >= 1 else { throw PokedoroCommandError.invalidWaveNumber(String(value)) }
        return value
    }

    private static func requiredWaveNumber(in arguments: [String], command: String) throws -> Int {
        guard let value = try waveNumber(in: arguments) else {
            throw PokedoroCommandError.missingArgument(command)
        }
        return value
    }

    /// 인자를 받지 않는 명령의 인자 검사.
    private static func rejectArgument(in arguments: [String], command: String) throws {
        guard arguments.allSatisfy({ $0.hasPrefix("--") }) else {
            throw PokedoroCommandError.unexpectedArgument(command)
        }
    }

    /// `party` 가 찍는 개체 번호. **1 미만은 그 목록에 없으므로 여기서 막는다** — 요청으로
    /// 내보내면 앱까지 갔다가 거절로 돌아오고, 앱이 꺼져 있으면 "응답 없음" 으로 끝나 사용자는
    /// 자기 오타를 영영 못 본다.
    private static func rosterNumber(in arguments: [String]) throws -> Int? {
        guard let value = try number(in: arguments, orThrow: PokedoroCommandError.invalidMonNumber)
        else { return nil }
        guard value >= 1 else { throw PokedoroCommandError.invalidMonNumber(String(value)) }
        return value
    }

    /// 반드시 있어야 하는 개체 번호. 없으면 "빠졌다", 번호가 아니면 "번호가 아니다" 로 갈라
    /// 말한다 — 사용자가 고쳐야 하는 것이 다르다.
    private static func requiredRosterNumber(in arguments: [String], command: String) throws -> Int {
        guard let value = try rosterNumber(in: arguments) else {
            throw PokedoroCommandError.missingArgument(command)
        }
        return value
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
    ///
    /// 상수 대신 **표에서 잰다.** 손으로 적은 21 은 `wave route <…>` 를 더하는 순간 모자랐고,
    /// `TUIText.pad` 는 넘치면 자르므로 도움말이 없는 명령을 알려 주게 된다.
    private static let commandColumn = (rows.map { TUIText.displayWidth($0.0) }.max() ?? 0) + 2

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
        ("use <아이템>", "아이템 하나 쓰기 (bag 이 찍는 이름)"),
        ("evolve", "대기 중인 진화 승인"),
        ("switch <번호>", "함께 다닐 포켓몬 바꾸기"),
        ("name <별명>", "파트너 별명 바꾸기"),
        ("shop", "상점 재고와 값"),
        ("buy <이름> [수량]", "상점에서 사기 (shop 이 찍는 이름)"),
        ("hatch", "부화 조건이 찬 알 부화시키기"),
        ("release <번호> --yes", "포켓몬 놓아주기 — 되돌릴 수 없다"),
        ("wave", "웨이브 런 — 지금 판"),
        ("wave start [번호]", "새 판 (번호 = 스타터, 생략하면 무작위)"),
        ("wave move <n> [상대]", "기술 쓰기 (상대 생략하면 1번 칸)"),
        ("wave switch <번호>", "교체 — 쓰러진 칸이 있으면 그 칸을 채운다"),
        ("wave ball [상대]", "몬스터볼 던지기"),
        ("wave pick <번호>", "보상 고르기"),
        ("wave route <\(routes)>", "다음 웨이브로 갈 길"),
        ("wave forfeit --yes", "판 포기 — 되돌릴 수 없다"),
        ("help", "이 도움말"),
    ]

    /// 길 이름은 **목록에서 나온다** — 손으로 적으면 길을 더할 때 도움말만 옛말이 된다.
    private static let routes = RunRoute.allCases.map(\.rawValue).joined(separator: "|")

    static let usage = """
    pokedoro — Pokédoro 를 터미널에서 본다.

    \(rows.map { "  " + TUIText.pad($0.0, to: commandColumn) + $0.1 }.joined(separator: "\n"))

    조회(status·party·wave…)는 세이브를 읽기만 한다. 상태를 바꾸는 명령은 전부 **메뉴바 앱에
    요청을 보내고** 앱이 실행한다 — 세이브에 쓰는 프로세스를 하나로 두기 위해서다. 앱이 꺼져
    있으면 그 요청은 실행되지 않는다.
    """
}
