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

/// 순수 입력 정규화와 전송 빈도 제한. 네트워크 경계와 UI가 같은 정책을 사용한다.
enum BattleChatPolicy {
    static let maximumLength = 200
    static let historyLimit = 50

    static func normalizedBody(_ value: String) -> String? {
        let body = value.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        guard !body.isEmpty, body.count <= maximumLength else { return nil }
        return body
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
        if messages.count > BattleChatPolicy.historyLimit {
            messages.removeFirst(messages.count - BattleChatPolicy.historyLimit)
        }
    }
    mutating func reset() { messages.removeAll() }
}
