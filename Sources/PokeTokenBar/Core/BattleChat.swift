import Foundation

/// 전투와 완전히 분리된, 현재 세션 안에서만 존재하는 채팅 한 줄.
struct BattleChatMessage: Codable, Sendable, Equatable, Identifiable {
    let id: UUID
    let senderID: UUID
    let senderName: String
    let body: String
    let sentAt: Date

    init(id: UUID = UUID(), senderID: UUID, senderName: String, body: String, sentAt: Date = Date()) {
        self.id = id; self.senderID = senderID; self.senderName = senderName
        self.body = body; self.sentAt = sentAt
    }
}

/// 상대가 보낸 글의 정규화·상한 정본. 네트워크 경계와 화면이 같은 정책을 쓴다.
///
/// **채팅만의 규칙이 아니다.** 표시 이름 자르기(`displayName`)와 본문 정규화(`normalizedBody`)는
/// 교환·경매·방 배틀·체육관이 함께 쓴다 — 상대가 보낸 글은 어느 기능으로 들어오든 같은 규칙을
/// 지나야 한다. 예전 이름이 `BattleChatPolicy` 라, 교환 쪽을 짜는 사람이 이 정본을 찾지 못하고
/// 자기 자리에 다시 짜기 좋은 자리였다.
enum PeerTextPolicy {
    static let maximumLength = 200
    static let historyLimit = 50

    static let maximumNameLength = 40

    /// 공백류는 한 칸으로 접고 제어문자는 버린다. 고정 높이 칸에 놓이는 본문은 길이만 재서는
    /// 안 된다 — 개행과 BEL·bidi 재정의는 칸을 넘치게 하거나 글자 순서를 뒤집는다.
    ///
    /// **문자(grapheme) 단위로 돈다.** 유니코드 스칼라로 훑으면 ZWJ(U+200D)가 제어문자 범주(Cf)에
    /// 들어 있어 `👨‍👩‍👧` 가 낱개 셋으로 쪼개진다 — 보이는 것도 망가지고 글자 수가 부풀어 정상
    /// 본문이 상한 밖으로 밀려난다. 그래서 "스칼라가 **전부** 제어문자인 문자"만 버린다.
    ///
    /// `limit` 은 부르는 쪽이 정한다. 교환 추억은 앨범의 계약(180자)을, 채팅은 자기 상한을 쓴다 —
    /// 같은 소켓의 형제 경계가 서로 다른 정규화를 갖지 않게 하려고 한 자리에 모아 둔다.
    static func normalizedBody(_ value: String, limit: Int = maximumLength) -> String? {
        let body = value.split(whereSeparator: \.isWhitespace)
            .map { $0.filter { !$0.unicodeScalars.allSatisfy(CharacterSet.controlCharacters.contains) } }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard !body.isEmpty, body.count <= limit else { return nil }
        return body
    }

    /// 상대가 부르는 표시 이름. **길이를 재는 게 아니라 자른다** — 이름은 본문과 달리 핸드셰이크가
    /// 정하는 값이라, 거부하면 교환·대전 자체가 성립하지 않는다. 채팅 행과 협상 헤더는 둘 다
    /// `lineLimit` 이 없어서, 프레임 상한(1MB)까지 채운 이름 하나가 패널 레이아웃을 무너뜨린다.
    static func displayName(_ value: String) -> String? {
        let name = value.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        guard !name.isEmpty else { return nil }
        return String(name.prefix(maximumNameLength))
    }
}

/// 발신자마다 3개까지 쌓이고 초당 하나 회복하는 토큰 버킷.
struct BattleChatRateLimiter: Sendable {
    private struct Bucket: Sendable { var tokens: Double = 3; var updatedAt: Date }
    private var buckets: [UUID: Bucket] = [:]

    mutating func allows(_ senderID: UUID, now: Date = Date()) -> Bool {
        var bucket = buckets[senderID] ?? Bucket(updatedAt: now)
        bucket.tokens = min(3, bucket.tokens + max(0, now.timeIntervalSince(bucket.updatedAt)))
        bucket.updatedAt = now
        guard bucket.tokens >= 1 else { buckets[senderID] = bucket; return false }
        bucket.tokens -= 1; buckets[senderID] = bucket
        return true
    }

    mutating func reset() { buckets.removeAll() }
}

/// 세션 종료 때 통째로 버려지는 메모리 저장소.
struct BattleChatHistory: Sendable {
    private(set) var messages: [BattleChatMessage] = []
    mutating func append(_ message: BattleChatMessage) {
        messages.append(message)
        if messages.count > PeerTextPolicy.historyLimit {
            messages.removeFirst(messages.count - PeerTextPolicy.historyLimit)
        }
    }
    mutating func reset() { messages.removeAll() }
}
