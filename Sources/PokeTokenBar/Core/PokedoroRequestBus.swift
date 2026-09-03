import Foundation

/// 터미널이 앱에 보내는 요청 한 건.
///
/// **왜 터미널이 직접 세이브를 바꾸지 않나.** 두 프로세스 사이에 잠금이 없어 나중 쓰기가 앞
/// 쓰기를 통째로 덮고, 세이브를 여는 것 자체가 "앱이 죽은 사이 밀린 일"(랭크전 패배 정산)을
/// 실행한다(`ReadOnlyStoreTests`). 잠금을 들이면 메뉴바 앱이 항상 떠 있으므로 터미널이 잠금을
/// 잡을 일이 사실상 없다 — 기능이 죽은 채로 태어난다. 그래서 **터미널은 부탁하고 앱이 한다**.
struct PokedoroRequest: Codable, Equatable, Sendable {
    /// 터미널이 부탁하는 일 하나. **이름과 인자가 한 값이다** — 예전엔 `verb` 와 `minutes` 가 따로
    /// 실려 "stop 인데 90분" 같은 요청을 타입이 허락했고, 파일은 손으로 고칠 수 있으니 그 조합은
    /// 실제로 들어온다. 표현할 수 없는 상태는 걸러 낼 필요도 없다.
    ///
    /// 인자는 **닫힌 타입만** 받는다(지금은 분 하나). 임의 문자열을 인자로 받는 동작은 이 목록에
    /// 넣지 않는다 — 요청 파일이 신뢰경계라 그 문자열이 곧 앱으로 들어오는 입력이 된다.
    enum Action: Equatable, Sendable {
        /// 분을 안 적으면 `nil` 이다 — 기본 길이는 실행기가 고른다. 여기서 25 를 채우면 기본값이
        /// 두 곳이 되고, 한쪽만 바뀌면 화면과 터미널이 다른 길이를 켠다.
        case start(minutes: Int?)
        case claim
        case stop

        /// 파일에 적히는 이름.
        var name: String {
            switch self {
            case .start: "start"
            case .claim: "claim"
            case .stop: "stop"
            }
        }

        /// 파일에 적히는 인자. 시작만 값을 갖는다.
        var minutes: Int? {
            switch self {
            case .start(let minutes): minutes
            case .claim, .stop: nil
            }
        }

        /// 파일에 적힌 이름·인자 → 동작. 모르면 `nil` 이다.
        ///
        /// **인자를 받지 않는 동작에 인자가 붙었으면 추측하지 않는다**(대화 도구 파서와 같은 규칙).
        /// 인자를 버리고 실행하면 사용자는 자기가 적은 값이 무시된 걸 모른 채 다른 일이 벌어진
        /// 것을 본다. 목록 밖 이름도 거절이 아니라 **요청으로 읽히지 않는 것**이다.
        init?(name: String, minutes: Int?) {
            switch name {
            case "start": self = .start(minutes: minutes)
            case "claim" where minutes == nil: self = .claim
            case "stop" where minutes == nil: self = .stop
            default: return nil
            }
        }
    }

    var id: UUID
    var action: Action
    var requestedAt: Date
}

/// 요청 파일의 모양. **평평한 JSON 을 손으로 유지한다** — 인자를 든 enum 을 Swift 에 그냥 맡기면
/// `{"action":{"start":{"minutes":25}}}` 같은 중첩이 나오는데, 그 파일은 사람이 고치기 어렵고
/// 문서가 약속한 모양도 아니다(고친 파일이 조용히 무시된다).
extension PokedoroRequest {
    private enum CodingKeys: String, CodingKey { case id, action, minutes, requestedAt }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        requestedAt = try container.decode(Date.self, forKey: .requestedAt)
        let name = try container.decode(String.self, forKey: .action)
        let minutes = try container.decodeIfPresent(Int.self, forKey: .minutes)
        // 이름과 인자가 어긋난 파일은 **요청이 아니다**. 던지면 `pendingRequest()` 가 nil 을
        // 돌려주므로 깨진 파일과 같은 취급이 된다 — 그 경로는 이미 앱을 죽이지 않는다.
        guard let action = Action(name: name, minutes: minutes) else {
            throw DecodingError.dataCorruptedError(forKey: .action, in: container,
                                                   debugDescription: "unknown action \(name)")
        }
        self.action = action
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(action.name, forKey: .action)
        // 인자 칸을 **아예 안 쓴다**. 남겨 두면 `{"action":"stop","minutes":null}` 이 정상으로
        // 보이고, 손으로 고치는 사용자가 그 칸이 뭔가 한다고 믿는다.
        try container.encodeIfPresent(action.minutes, forKey: .minutes)
        try container.encode(requestedAt, forKey: .requestedAt)
    }
}

/// 앱이 되돌려 주는 답. `message` 는 **사람이 읽는 한국어 한 줄**이다 — 대화 도구의 영문
/// 기계 문자열과 다른 물건이고, 그래서 사유 → 문구 변환은 프런트엔드가 각자 한다.
struct PokedoroReply: Codable, Equatable, Sendable {
    var id: UUID
    var succeeded: Bool
    var message: String
}

/// 요청·답이 오가는 두 파일. **파일마다 쓰는 쪽이 하나다** — 요청은 터미널만, 답은 앱만 쓴다.
///
/// 앱이 처리한 요청 파일을 지우지 않는 이유가 그것이다. 지우려면 앱이 터미널의 파일에 손을 대야
/// 하고, 그 순간 한 파일에 쓰기 주체가 둘이 된다(정확히 이 기능이 피하려던 상태다). 대신
/// `PokedoroRequestBus` 의 나이 제한과 id 두 가드가 "이미 처리한 요청" 을 걸러 낸다.
struct PokedoroMailbox: Sendable {
    let requestURL: URL
    let replyURL: URL

    /// 세이브와 **같은 디렉터리**에 둔다 — `PTB_STATE_DIR` 하나로 프로필 전체가 격리된다는
    /// `CompanionStorageLocations` 의 계약을 요청도 지켜야 한다. 아니면 격리된 QA 세션의
    /// 터미널이 실제 사용자 앱을 조종한다.
    init(directory: URL? = nil) {
        let base = directory ?? CompanionStorageLocations().directory
        requestURL = base.appendingPathComponent("pokedoro-request.json")
        replyURL = base.appendingPathComponent("pokedoro-reply.json")
    }

    // MARK: 터미널 쪽

    /// 요청을 남긴다. 실패를 **던진다** — 조용히 삼키면 터미널이 3초를 기다린 뒤 "앱이 꺼져
    /// 있다" 고 답하는데, 실제로는 디렉터리 권한 문제라 사용자가 영영 못 고친다.
    func send(_ request: PokedoroRequest) throws {
        try Self.encoder.encode(request).write(to: requestURL, options: .atomic)
    }

    /// **내 요청의 답만** 받는다. id 를 안 보면 앞 세션의 답을 자기 것으로 착각해, 하지도 않은
    /// 일을 성공으로 보고한다.
    func reply(to id: UUID) -> PokedoroReply? {
        guard let reply: PokedoroReply = Self.load(replyURL) else { return nil }
        return reply.id == id ? reply : nil
    }

    // MARK: 앱 쪽

    /// 지금 놓여 있는 요청. **파일이 없는 것이 정상이다** — 앱은 요청이 없는 매 초에도 이
    /// 경로를 밟는다. 깨진 파일도 `nil` 이다: 여기서 죽으면 메뉴바 앱이 통째로 내려간다.
    func pendingRequest() -> PokedoroRequest? { Self.load(requestURL) }

    func post(_ reply: PokedoroReply) throws {
        try Self.encoder.encode(reply).write(to: replyURL, options: .atomic)
    }

    // MARK: 인코딩

    private static let encoder = JSONEncoder()

    private static func load<T: Decodable>(_ url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}

/// 앱이 요청을 실행해도 되는지 정하는 두 가드. 순수 함수로 둔 이유는 여기가 **터미널이 앱의
/// 세이브를 움직이는 유일한 입구**라서다 — 프로세스 둘을 띄우지 않고 전수 검증할 수 있어야 한다.
enum PokedoroRequestBus {
    /// 요청이 살아 있는 시간. 짧게 잡는 이유는 이 값이 곧 "앱이 꺼진 사이 쌓인 요청" 의 수명이기
    /// 때문이다. 터미널은 3초 기다렸다 포기하므로 그보다 여유만 있으면 된다.
    static let maximumAge: TimeInterval = 10

    /// 실행해야 하는가.
    ///
    /// ⓐ **나이**: 앱이 꺼진 사이 남은 요청을 그대로 실행하면, 사용자가 세 시간 전에 포기한
    /// 90분 집중이 앱을 켜는 순간 시작된다. 어긋남은 양쪽 대칭으로 본다 — 앞으로 어긋난 값만
    /// 통과시키면 시각을 미래로 적은 요청 하나로 이 제한을 통째로 우회할 수 있다.
    ///
    /// ⓑ **id**: 앱은 1초마다 이 파일을 보고 파일은 지워지지 않는다. 마지막으로 실행한 id 를
    /// 기억하지 않으면 같은 요청이 매 틱마다 다시 실행된다.
    static func shouldExecute(_ request: PokedoroRequest, now: Date, lastExecutedID: UUID?) -> Bool {
        guard request.id != lastExecutedID else { return false }
        return abs(now.timeIntervalSince(request.requestedAt)) <= maximumAge
    }
}
