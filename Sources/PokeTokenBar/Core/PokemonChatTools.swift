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
    case adventureClaim = "adventure.claim"
    case bagList = "bag.list"
    case rosterList = "roster.list"
    case itemUse = "item.use"
    case evolutionAccept = "evolution.accept"
    case companionSwitch = "companion.switch"
    case memoryRecord = "memory.record"

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
        case .adventureClaim:
            return "[[tool:\(rawValue)]] — ask the trainer to collect a finished adventure's reward"
        case .bagList:
            return "[[tool:\(rawValue)]] — see which items the trainer is carrying"
        case .rosterList:
            return "[[tool:\(rawValue)]] — see the other Pokémon on the team, with their index numbers"
        case .itemUse:
            // 이름을 전부 나열하지 않는다(30종 가까이다). 대신 bag.list 가 찍어 주는 이름만
            // 쓰라고 못 박는다 — 모델이 지어낸 이름은 어차피 파싱에서 떨어진다.
            return "[[tool:\(rawValue)(<item name exactly as bag.list printed it>)]] — ask the trainer to use one item"
        case .evolutionAccept:
            return "[[tool:\(rawValue)]] — ask the trainer to let you evolve (only when evolution is waiting)"
        case .companionSwitch:
            return "[[tool:\(rawValue)(<index from roster.list>)]] — ask the trainer to bring out another Pokémon"
        case .memoryRecord:
            return "[[tool:\(rawValue)]] — keep what you just said as a memory you two share"
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
    /// 끝난 모험의 정산. 인자가 없는 이유는 모험이 한 번에 하나뿐이라서다 — 지목할 것이 없다.
    case adventureClaim
    case bagList
    case rosterList
    /// 인자가 닫힌 enum 이다. 임의 문자열을 그대로 받는 인자는 이 목록에 넣지 않는다.
    case itemUse(kind: ItemKind)
    case evolutionAccept
    /// `roster.list` 가 찍은 인덱스. UUID 를 문자열로 받으면 그게 곧 임의 문자열 인자다.
    case companionSwitch(index: Int)
    /// **파서가 채우지 않는 유일한 인자.** 마커에는 인자가 없고(`[[tool:memory.record]]`),
    /// 본문은 가드를 통과한 답변으로 `PokemonChatStore` 가 채워 넣는다. 모델이 기억 내용을
    /// 직접 쓰게 하면 그게 임의 문자열 인자이고, 다음 요청의 컨텍스트로 되돌아온다.
    case memoryRecord(body: String)

    /// 상태를 바꾸는 도구는 사용자의 명시 승인 뒤에만 실행된다. 읽기는 그냥 돈다.
    /// 이 한 줄이 "시스템 영향도" 의 전부다 — 나머지는 아예 실행 경로가 없는 것들이다.
    var needsApproval: Bool {
        switch self {
        case .pokedoroStart, .pokedoroStop, .itemUse, .evolutionAccept, .companionSwitch,
             // 정산은 지갑과 경험치를 움직이고, 경험치가 진화·기술 학습 카드를 띄운다.
             .adventureClaim: return true
        case .pokedexLookup, .pokedoroStatus, .bagList, .rosterList: return false
        // 기억하기만 예외다. 남는 건 사용자가 화면에서 방금 읽은 문장뿐이고(모델이 문구를 못 정한다),
        // 앨범에 전체 삭제가 있다. 승인을 붙이면 대화가 매번 카드로 끊긴다.
        case .memoryRecord: return false
        }
    }

    /// 대상을 인자로 받지 않고 **지금 나와 있는 개체**에 작용하는가.
    ///
    /// 대화 창은 박스 개체로도 열린다(`PokemonRosterView`). 그런 창에서 이 부류가 돌면 승인 카드가
    /// 가리키는 아이("나, 진화해도 될까?")와 실제 대상이 갈라진다 — 사용자는 자기가 무엇을
    /// 승인했는지 모른 채 다른 개체를 진화시킨다. 그래서 이 부류는 **그 개체의 대화에서만** 돈다.
    ///
    /// 예외는 판단이 아니라 성질이다. `companion.switch` 는 인자로 대상을 지목하므로 남의
    /// 대화에서도 뜻이 분명하고, 읽기 도구와 `memory.record` 는 트레이너·대화 주인의 것이다
    /// (기억은 활성 개체가 아니라 **대화 주인** 앨범으로 간다).
    var actsOnTheActiveCompanion: Bool {
        switch self {
        case .pokedoroStart, .pokedoroStop, .itemUse, .evolutionAccept, .adventureClaim: return true
        case .pokedexLookup, .pokedoroStatus, .bagList, .rosterList,
             .companionSwitch, .memoryRecord: return false
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
            // 잃는 것을 말한다. 집중을 끝내면 모험이 보상 없이 취소되는데(`cancelFocusAdventure`),
            // "끝낼까?" 만 물으면 사용자는 무엇을 승인하는지 모른다. 휴식 단계에는 나가 있는 모험이
            // 없으므로 조건절로 읽힌다 — 어느 단계에서도 거짓이 되지 않는 문장이다.
            return L(language).t("집중을 끝낼까? 진행 중인 모험은 보상 없이 취소돼.",
                                 "Shall we stop the focus session? An adventure still out is cancelled with no reward.",
                                 "集中を終える？進行中の冒険は報酬なしで取り消されるよ。")
        case .adventureClaim:
            return L(language).t("모험 보상을 받아 올까?",
                                 "Shall we collect the adventure reward?",
                                 "冒険の報酬を受け取る？")
        case .itemUse(let kind):
            let name = L(language).itemName(kind)
            return L(language).t("\(name)을(를) 하나 써 볼까?",
                                 "Shall we use one \(name)?",
                                 "\(name)を1つ使ってみる？")
        case .evolutionAccept:
            return L(language).t("나, 진화해도 될까?", "May I evolve?", "ぼく、進化してもいい？")
        case .companionSwitch(let index):
            return L(language).t("\(index + 1)번째 친구를 데리고 나갈까?",
                                 "Shall we bring out teammate #\(index + 1)?",
                                 "\(index + 1)番目の子を連れて行く？")
        case .pokedexLookup, .pokedoroStatus, .bagList, .rosterList, .memoryRecord:
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
        case .adventureClaim:
            return l.t("모험 보상을 받았어. 고마워!", "Collected the adventure reward. Thank you!",
                       "冒険の報酬を受け取ったよ。ありがとう！")
        case .itemUse(let kind):
            let name = l.itemName(kind)
            return l.t("\(name)을(를) 썼어. 고마워!", "Used one \(name). Thank you!", "\(name)を使ったよ。ありがとう！")
        case .evolutionAccept:
            return l.t("나, 진화했어! 잘 부탁해.", "I evolved! Look after me.", "進化したよ！これからもよろしく。")
        case .companionSwitch:
            return l.t("친구랑 자리를 바꿨어.", "We swapped places.", "友だちと交代したよ。")
        case .memoryRecord:
            return l.t("방금 이야기를 기억해 둘게.", "I'll remember what we just said.", "いまの話、覚えておくね。")
        case .pokedexLookup, .pokedoroStatus, .bagList, .rosterList:
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
        case .pokedoroStatus, .pokedoroStop, .bagList, .rosterList, .evolutionAccept, .memoryRecord,
             .adventureClaim:
            // 인자를 받지 않는 도구에 인자가 붙었으면 모델이 다른 것을 의도한 것이다. 추측하지 않는다.
            guard argument == nil else { return nil }
            switch tool {
            case .pokedoroStatus: return .pokedoroStatus
            case .pokedoroStop: return .pokedoroStop
            case .bagList: return .bagList
            case .rosterList: return .rosterList
            case .evolutionAccept: return .evolutionAccept
            case .adventureClaim: return .adventureClaim
            // 본문은 여기서 채우지 않는다 — 가드를 통과한 답변으로 스토어가 갈아 끼운다.
            default: return .memoryRecord(body: "")
            }
        case .itemUse:
            // 닫힌 enum 만 인자가 된다. 목록 밖 이름은 거부되는 게 아니라 호출이 되지 않는다.
            guard let raw = argument, let kind = ItemKind(rawValue: raw) else { return nil }
            return .itemUse(kind: kind)
        case .companionSwitch:
            // 인덱스는 `roster.list` 가 찍은 값이다. 범위 상한은 로스터를 아는 실행기가 본다 —
            // 파서가 그때그때의 로스터 크기를 알면 파싱이 앱 상태에 의존하게 된다.
            guard let index = wholeNumber(argument) else { return nil }
            return .companionSwitch(index: index)
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
    ///
    /// `owner` 는 **이 대화의 주인**이다. 기본값을 두지 않는 이유는, 두면 부르는 자리가 활성 개체를
    /// 암묵 대상으로 삼아 박스 개체 대화가 다시 남을 건드리게 되기 때문이다 — 넘기지 않으면
    /// 컴파일이 안 되는 편이 낫다.
    func run(_ call: PokemonChatToolCall, owner: UUID) async -> (line: String, succeeded: Bool)
}

/// 실물 실행기 — 포케도로 타이머와 도감 조회만 안다.
@MainActor
struct PokemonChatToolbox: PokemonChatToolRunning {
    let timer: FocusTimer
    let companion: CompanionStore
    /// 기억 앨범. 대화 창이 이미 들고 있는 것과 **같은 인스턴스**를 받아야 한다 — 새로 만들면
    /// 도구가 적은 기억이 앨범 화면에 영영 안 보인다.
    let album: PokemonMemoryAlbum
    /// 종 정보 조회. 주입받는 이유는 실행기 자체를 네트워크 없이 시험하기 위해서다. 기본값을 두지
    /// 않는 건 프로덕션 생성 지점이 하나뿐이라서다 — 기본값은 그 하나가 무엇을 넣었는지 가린다.
    let lookup: (Int, AppLanguage) async -> PokemonSpeciesIdentity

    /// PokéAPI 를 그대로 쓰는 프로덕션 조회. 대화 창을 열 때 이 값이 주입된다.
    nonisolated static func apiLookup(_ id: Int, _ language: AppLanguage) async -> PokemonSpeciesIdentity {
        await PokeAPIClient.shared.chatSpeciesIdentity(speciesID: id, language: language)
    }

    func run(_ call: PokemonChatToolCall, owner: UUID) async -> (line: String, succeeded: Bool) {
        // 암시적으로 "지금 나와 있는 나" 에 작용하는 도구는 그 개체의 대화에서만 돈다. 가드가 여기
        // 한 곳뿐인 이유는 case 마다 두면 다음에 더하는 도구가 조용히 빠지기 때문이다 — 분류는
        // `actsOnTheActiveCompanion` 한 곳에서만 한다.
        if call.actsOnTheActiveCompanion {
            // 사유를 갈라 준다. 뭉개면 모델이 왜 안 되는지 모른 채 같은 호출을 반복하고,
            // 사용자에게는 침묵으로 보인다(분을 버리지 않고 접는 것과 같은 이유).
            guard let active = companion.activeMonID else { return ("tool refused: no active companion", false) }
            guard owner == active else { return ("tool refused: not the active companion", false) }
        }
        switch call {
        case .bagList:
            let items = companion.ownedItems
            guard !items.isEmpty else { return ("bag empty", true) }
            // 이름을 rawValue 로 돌려준다 — 모델이 `item.use` 에 그대로 되돌려 줄 값이어야 한다.
            // 현지화된 이름을 주면 모델이 그걸 인자로 써서 파싱에서 떨어진다.
            return ("bag " + items.map { "\($0.kind.rawValue)=\($0.count)" }.joined(separator: " "), true)

        case .rosterList:
            let lines = companion.chatRosterEntries.map {
                "index=\($0.index) name=\($0.name) level=\($0.level) active=\($0.isActive)"
            }
            guard !lines.isEmpty else { return ("roster empty", true) }
            return ("roster " + lines.joined(separator: " | "), true)

        case .itemUse(let kind):
            let (line, succeeded) = useItem(kind)
            return (line, succeeded)

        case .evolutionAccept:
            // 대기 중인 진화가 없으면 정직하게 실패다. 성공으로 돌려주면 모델이 진화했다고 말한다.
            guard companion.evolutionPrompt != nil else { return ("evolution none pending", false) }
            companion.acceptEvolution()
            return ("evolution accepted stage=\(companion.activeStageIndex ?? 0)", true)

        case .companionSwitch(let index):
            guard let target = companion.chatRosterEntries.first(where: { $0.index == index }),
                  !target.isActive else { return ("companion switch index=\(index) unavailable", false) }
            companion.switchCompanion(to: target.id)
            return ("companion switched to=\(target.name)", true)

        case .memoryRecord(let body):
            // 앨범 키는 활성 개체가 아니라 **이 대화의 주인**이다. 활성 개체로 적으면 박스 개체와
            // 나눈 이야기가 남의 앨범에 박히고, 정작 그 창의 앨범에는 영영 안 보인다.
            // 빈 본문은 기록하지 않는다 — 스토어가 채우기 전에 실행되면 앨범에 빈 줄이 남는다.
            guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return ("memory not recorded", false)
            }
            album.record(companionID: owner, body: body, source: .conversation)
            return ("memory recorded", true)

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
        case .adventureClaim:
            // 끝난 모험만 정산된다(`claimAdventure` 가 완료 판정을 들고 있는 유일한 자리다).
            // 없는데 성공으로 돌려주면 모델이 "보상 받았어" 라고 말한다.
            guard let reward = companion.claimAdventure() else { return ("adventure none ready", false) }
            // 지갑 증가분을 **전부** 설명한다 — 트레이너·미션·업적·시즌 보너스까지 합친 값이
            // 실제 증가분이다(`AdventureReward` 의 완전설명 계약). 숫자를 빼면 모델이 액수를 지어낸다.
            let stardust = reward.stardust + reward.trainerBonus + reward.missionBonus
                + reward.achievementBonus + reward.seasonBonus
            return ("adventure claimed stardust=\(stardust) exp=\(reward.experience) eggs=\(reward.bonusEggs)", true)

        case .pokedoroStart(let minutes):
            // 나가 있는 모험이 있으면 화면도 시작 버튼을 내주지 않는다(`FocusTimerView`). 사유를
            // 갈라 주면 모델이 다음 수(정산)로 이어 갈 수 있다 — 뭉개면 같은 호출만 반복한다.
            if companion.activeAdventure != nil {
                let reason = companion.isAdventureInProgress ? "in progress" : "reward unclaimed"
                return ("pokedoro start refused: adventure \(reason)", false)
            }
            guard timer.startFocusSession(minutes: minutes, companion: companion) else {
                return ("pokedoro start refused", false)
            }
            return (statusLine(), true)
        case .pokedoroStop:
            timer.stopFocusSession(companion: companion)
            return (statusLine(), true)
        }
    }

    /// 아이템 한 종류를 그 종류의 **진짜 사용 경로**로 보낸다. 여기서 인벤토리를 직접 깎지 않는다 —
    /// 화면 버튼과 다른 경로가 되면 한쪽만 고쳐져 소모·연출·진화가 어긋난다.
    private func useItem(_ kind: ItemKind) -> (String, Bool) {
        switch kind {
        case .rareCandy:
            let result = companion.useRareCandy()
            guard result != .unavailable else { return ("item rareCandy unavailable", false) }
            return ("item rareCandy used result=\(result)", true)
        case .mint:
            guard let nature = companion.useMint() else { return ("item mint unavailable", false) }
            return ("item mint used nature=\(nature.rawValue)", true)
        case .heartScale:
            guard companion.canUseHeartScale else { return ("item heartScale unavailable", false) }
            companion.useHeartScale()
            // 후보 목록 카드가 뜰 뿐 아직 아무것도 바뀌지 않았다. 성공으로 뭉개면 모델이
            // "기술을 바꿨어" 라고 말한다.
            return ("item heartScale opened relearn choices", true)
        case .shinyCharm, .freshWater:
            // 보유형(부적)과 던전 입장 소모품은 대화에서 "지금 쓴다" 는 개념이 없다.
            return ("item \(kind.rawValue) is not used from chat", false)
        default:
            guard companion.canUseEvolutionItem(kind) else { return ("item \(kind.rawValue) unavailable", false) }
            guard companion.useEvolutionItem(kind) else { return ("item \(kind.rawValue) refused", false) }
            return ("item \(kind.rawValue) used", true)
        }
    }

    /// 타이머만이 아니라 **모험 루프**를 싣는다. Pokedoro 의 상호작용은 여기에 있다 — 모험은
    /// 집중과 함께 나가고, 끝나면 사용자가 정산해야 하며, 정산 전에는 다음 집중이 안 켜진다.
    /// 타이머만 보고하던 동안 모델은 "보상 받기를 눌러 달라" 는 말을 할 수 없었다.
    ///
    /// 알 부화 예정 시각은 넣지 않는다 — 남은 시간을 재려면 실행기가 시계를 들어야 하고, 그러면
    /// 같은 판정이 `StoredEggCountdown` 과 두 벌이 된다. 개수만으로 할 말은 충분하다.
    private func statusLine() -> String {
        var parts = ["pokedoro state=\(timer.phase.rawValue)",
                     "remaining=\(timer.isRunning ? timer.clockText() : "00:00")",
                     "completed=\(timer.completedSessions)"]
        if let adventure = companion.activeAdventure {
            let waiting = !companion.isAdventureInProgress
            parts.append("adventure=\(waiting ? "ready" : "running")")
            parts.append("zone=\(adventure.zone.rawValue)")
            if !waiting { parts.append("progress=\(Int((companion.adventureProgress() * 100).rounded()))%") }
        } else {
            parts.append("adventure=none")
        }
        parts += ["eggs=\(companion.focusEggCount)",
                  "fragments=\(companion.eggFragmentCount)",
                  "weekly=\(companion.weeklyAdventureProgress)"]
        return parts.joined(separator: " ")
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
