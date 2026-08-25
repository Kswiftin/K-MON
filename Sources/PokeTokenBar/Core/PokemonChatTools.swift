import Foundation

/// 대화가 앱 바깥과 닿는 **유일한** 통로.
///
/// 모델은 도구를 갖지 않는다. CLI 는 `PokemonChatProviderSafety.arguments` 의 도구 0개 계약으로
/// 돌고, 앱이 답변 텍스트의 `[[tool:...]]` 마커를 읽어 이 목록에 있는 이름일 때만 실행한다.
/// 그래서 코딩·검색·컴퓨터 제어는 "거부되는 기능" 이 아니라 **존재하지 않는 기능**이다 —
/// 목록 밖 이름은 판정을 통과하지 못하는 게 아니라 호출로 파싱되지 않는다.
///
/// 이름 목록은 여기 한 벌뿐이다. 프롬프트가 광고하는 이름과 파서가 받는 이름이 갈라지면 모델이
/// 없는 도구를 부르거나 있는 도구를 영영 모른다.
enum PokemonChatTool: String, CaseIterable, Sendable {
    case pokedexLookup = "pokedex.lookup"
    case pokedoroStatus = "pokedoro.status"
    case pokedoroStart = "pokedoro.start"
    case pokedoroStop = "pokedoro.stop"

    /// 화면이 제시하는 집중 길이. 모델이 말한 값은 이 셋 중 가장 가까운 것으로 접힌다.
    static let focusMinutes = [25, 50, 90]
    /// 도감 번호 상한. 범위를 두는 이유는 주입이 아니라(인자는 이미 `Int` 다) 404 를 부르는
    /// 무의미한 왕복을 막기 위해서다.
    static let highestDexNumber = 1_025

    /// 모델에게 보여 주는 한 줄. 문법과 제약을 여기 같이 적어야 프롬프트와 파서가 함께 움직인다.
    var promptLine: String {
        switch self {
        case .pokedexLookup:
            return "[[tool:\(rawValue)(<national dex number 1-\(Self.highestDexNumber)>)]] — look up another Pokémon's Pokédex entry"
        case .pokedoroStatus:
            return "[[tool:\(rawValue)]] — check the focus timer"
        case .pokedoroStart:
            let lengths = Self.focusMinutes.map(String.init).joined(separator: "|")
            return "[[tool:\(rawValue)(<\(lengths)>)]] — ask the trainer to start a focus session"
        case .pokedoroStop:
            return "[[tool:\(rawValue)]] — ask the trainer to stop the focus session"
        }
    }
}

/// 인자까지 검증을 마친 호출. 잘못된 값을 담은 `PokemonChatToolCall` 은 만들 수 없다 —
/// 클램프가 생성 시점에 한 번만 있고, 실행기는 다시 검사하지 않아도 된다.
enum PokemonChatToolCall: Equatable, Sendable {
    case pokedexLookup(speciesID: Int)
    case pokedoroStatus
    case pokedoroStart(minutes: Int)
    case pokedoroStop

    /// 상태를 바꾸는 도구는 사용자의 명시 승인 뒤에만 실행된다. 읽기는 그냥 돈다.
    /// 이 한 줄이 "시스템 영향도" 의 전부다 — 나머지는 아예 실행 경로가 없는 것들이다.
    var needsApproval: Bool {
        switch self {
        case .pokedoroStart, .pokedoroStop: return true
        case .pokedexLookup, .pokedoroStatus: return false
        }
    }

    /// 승인 카드에 실을 사람 문장. enum 슬러그를 그대로 보여 주지 않는다.
    func approvalQuestion(_ language: AppLanguage) -> String {
        switch self {
        case .pokedoroStart(let minutes):
            return L(language).t("\(minutes)분 집중을 시작할까?",
                                 "Shall we start a \(minutes)-minute focus session?",
                                 "\(minutes)分の集中を始める？")
        case .pokedoroStop:
            return L(language).t("집중을 여기서 끝낼까?", "Shall we stop the focus session?", "集中をここで終える？")
        case .pokedexLookup, .pokedoroStatus:
            return L(language).t("확인해 볼까?", "Shall I check?", "確認してみる？")
        }
    }

    /// 승인·거절·실패를 사용자에게 알리는 한 줄. 실행 결과는 화면(타이머)에도 보이지만,
    /// 눌렀는데 아무 일도 안 일어난 경우가 대화에서 침묵으로 보이면 안 된다.
    func outcome(approved: Bool, success: Bool, language: AppLanguage) -> String {
        let l = L(language)
        guard approved else {
            return l.t("알겠어, 나중에 하자.", "Okay, let's do it later.", "わかった、あとにしよう。")
        }
        guard success else {
            return l.t("지금은 그렇게 할 수 없어.", "I can't do that right now.", "今はそれができないよ。")
        }
        switch self {
        case .pokedoroStart(let minutes):
            return l.t("\(minutes)분 집중을 시작했어. 같이 가자!",
                       "Started a \(minutes)-minute focus session. Let's go!",
                       "\(minutes)分の集中を始めたよ。いっしょにがんばろう！")
        case .pokedoroStop:
            return l.t("집중을 끝냈어. 수고했어!", "Focus session stopped. Nice work!", "集中を終えたよ。おつかれさま！")
        case .pokedexLookup, .pokedoroStatus:
            return l.t("확인했어.", "Checked.", "確認したよ。")
        }
    }
}

/// 답변 텍스트에서 호출 하나를 꺼낸다. 마커는 **언제나** 본문에서 제거된다 — 인식하지 못한
/// 마커까지 지우는 이유는, 남겨 두면 사용자가 기계 문법을 읽고 가드가 문장 수를 잘못 세기 때문이다.
enum PokemonChatToolParser {
    static func parse(_ reply: String) -> (body: String, call: PokemonChatToolCall?) {
        var body = reply
        var firstCall: PokemonChatToolCall?
        var cursor = body.startIndex
        while let start = body.range(of: "[[", range: cursor..<body.endIndex) {
            guard let end = body.range(of: "]]", range: start.upperBound..<body.endIndex) else { break }
            let payload = String(body[start.upperBound..<end.lowerBound])
            if let call = call(from: payload) {
                firstCall = firstCall ?? call
            } else {
                AppLog.write("chat tool tag ignored: \(payload)")
            }
            body.removeSubrange(start.lowerBound..<end.upperBound)
            cursor = start.lowerBound
        }
        return (body.trimmingCharacters(in: .whitespacesAndNewlines), firstCall)
    }

    /// `tool:<이름>` 또는 `tool:<이름>(<인자>)` 만 호출이 된다. 대소문자·공백·경로 조각을 관대하게
    /// 받지 않는다 — 관대함이 곧 목록 밖 이름이 들어올 틈이다.
    private static func call(from payload: String) -> PokemonChatToolCall? {
        guard payload.hasPrefix("tool:") else { return nil }
        let rest = String(payload.dropFirst(5))
        let name: String
        var argument: String?
        if let open = rest.firstIndex(of: "(") {
            guard rest.hasSuffix(")") else { return nil }
            name = String(rest[rest.startIndex..<open])
            argument = String(rest[rest.index(after: open)..<rest.index(before: rest.endIndex)])
        } else {
            name = rest
        }
        guard let tool = PokemonChatTool(rawValue: name) else { return nil }

        switch tool {
        case .pokedoroStatus, .pokedoroStop:
            // 인자를 받지 않는 도구에 인자가 붙었으면 모델이 다른 것을 의도한 것이다. 추측하지 않는다.
            guard argument == nil else { return nil }
            return tool == .pokedoroStatus ? .pokedoroStatus : .pokedoroStop
        case .pokedoroStart:
            guard let minutes = wholeNumber(argument) else { return nil }
            return .pokedoroStart(minutes: nearestFocusLength(to: minutes))
        case .pokedexLookup:
            guard let id = wholeNumber(argument), (1...PokemonChatTool.highestDexNumber).contains(id) else { return nil }
            return .pokedexLookup(speciesID: id)
        }
    }

    /// 숫자만 있는 문자열만 숫자다. `Int("25분")` 은 이미 nil 이지만 `" 25 "`·`"+25"` 는 통과하므로
    /// 자릿수 검사를 먼저 둔다 — 모델이 무엇을 붙였는지 추측하지 않겠다는 뜻이다.
    private static func wholeNumber(_ raw: String?) -> Int? {
        guard let raw, !raw.isEmpty, raw.allSatisfy(\.isASCII), raw.allSatisfy(\.isNumber) else { return nil }
        return Int(raw)
    }

    /// 가장 가까운 길이로 접는다(동률이면 짧은 쪽). 값을 버리는 대신 접는 이유는, 버리면 모델이
    /// 왜 아무 일도 안 일어났는지 모른 채 같은 실수를 반복하기 때문이다. 승인 카드가 실제 분을
    /// 그대로 보여 주므로 사용자는 무엇을 켜는지 정확히 안다.
    private static func nearestFocusLength(to minutes: Int) -> Int {
        PokemonChatTool.focusMinutes.min { abs($0 - minutes) < abs($1 - minutes) } ?? PokemonChatTool.focusMinutes[0]
    }
}

/// 실행기. 프로토콜인 이유는 파싱·클램프(보안이 사는 곳)를 프로세스도 네트워크도 없이 시험하기
/// 위해서다 — 실물 실행기는 타이머와 PokéAPI 를 그대로 쓴다.
@MainActor
protocol PokemonChatToolRunning {
    /// `line` 은 모델에게 돌려줄 사실 한 줄(사용자 화면에는 실리지 않으므로 번역하지 않는다).
    /// `succeeded` 는 승인 경로가 거절과 실패를 구분하는 데 쓴다 — 문자열을 뒤져 판정하지 않는다.
    func run(_ call: PokemonChatToolCall) async -> (line: String, succeeded: Bool)
}

/// 실물 실행기 — 포케도로 타이머와 도감 조회만 안다.
@MainActor
struct PokemonChatToolbox: PokemonChatToolRunning {
    let timer: FocusTimer
    let companion: CompanionStore
    /// 종 정보 조회. 주입받는 이유는 실행기 자체를 네트워크 없이 시험하기 위해서다. 기본값을 두지
    /// 않는 건 프로덕션 생성 지점이 하나뿐이라서다 — 기본값은 그 하나가 무엇을 넣었는지 가린다.
    let lookup: (Int, AppLanguage) async -> PokemonSpeciesIdentity

    /// PokéAPI 를 그대로 쓰는 프로덕션 조회. 대화 창을 열 때 이 값이 주입된다.
    nonisolated static func apiLookup(_ id: Int, _ language: AppLanguage) async -> PokemonSpeciesIdentity {
        await PokeAPIClient.shared.chatSpeciesIdentity(speciesID: id, language: language)
    }

    func run(_ call: PokemonChatToolCall) async -> (line: String, succeeded: Bool) {
        switch call {
        case .pokedoroStatus:
            return (statusLine(), true)
        case .pokedexLookup(let id):
            let identity = await lookup(id, companion.language)
            let facts = [identity.genus.map { "genus=\($0)" },
                         identity.habitat.map { "habitat=\($0)" },
                         identity.ability.map { "ability=\($0)" },
                         identity.flavorText.map { "entry=\($0)" }].compactMap { $0 }
            // 빈 조회를 빈 줄로 돌려주면 모델이 침묵을 사실로 읽는다.
            guard !facts.isEmpty else { return ("pokedex #\(id) unavailable", false) }
            return ("pokedex #\(id) " + facts.joined(separator: " "), true)
        case .pokedoroStart(let minutes):
            guard timer.startFocusSession(minutes: minutes, companion: companion) else {
                return ("pokedoro start refused", false)
            }
            return (statusLine(), true)
        case .pokedoroStop:
            timer.stopFocusSession(companion: companion)
            return (statusLine(), true)
        }
    }

    private func statusLine() -> String {
        "pokedoro state=\(timer.phase.rawValue) remaining=\(timer.isRunning ? timer.clockText() : "00:00") completed=\(timer.completedSessions)"
    }
}

extension FocusTimer {
    /// 집중 시작의 **유일한** 경로. 타이머와 모험은 함께 움직여야 한다 — 따로 부르는 자리가
    /// 둘이 되면 한쪽만 고쳐져 "타이머는 도는데 끝나도 받을 보상이 없는" 상태가 생긴다.
    @discardableResult
    func startFocusSession(minutes: Int, companion: CompanionStore) -> Bool {
        guard companion.startFocusAdventure(minutes: minutes) else { return false }
        startFocus(minutes: minutes)
        return true
    }

    func stopFocusSession(companion: CompanionStore) {
        stop()
        companion.cancelFocusAdventure()
    }
}
