import Foundation

/// 터미널이 앱에 보내는 요청 한 건.
///
/// **왜 터미널이 직접 세이브를 바꾸지 않나.** 두 프로세스 사이에 잠금이 없어 나중 쓰기가 앞
/// 쓰기를 통째로 덮고, 세이브를 여는 것 자체가 "앱이 죽은 사이 밀린 일"(랭크전 패배 정산)을
/// 실행한다(`ReadOnlyStoreTests`). 잠금을 들이면 메뉴바 앱이 항상 떠 있으므로 터미널이 잠금을
/// 잡을 일이 사실상 없다 — 기능이 죽은 채로 태어난다. 그래서 **터미널은 부탁하고 앱이 한다**.
struct PokedoroRequest: Codable, Equatable, Sendable {
    enum Verb: String, Codable, Sendable { case start, claim, stop }

    var id: UUID
    var verb: Verb
    /// `start` 만 쓴다. 다른 동작에서는 `nil` 이라 "0분 집중" 같은 값이 생기지 않는다.
    var minutes: Int?
    var requestedAt: Date
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
