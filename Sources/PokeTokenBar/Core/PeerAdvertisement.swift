import Foundation
import Network

/// 근처 트레이너 카드가 보여줄 표시용 진행도 — Bonjour TXT 레코드로 오간다.
///
/// **표시 전용이다.** 판돈·해금·승패 판정은 이 값을 읽지 않는다. 스스로 신고하는 값이라 권위가
/// 없다(`BattleRank.clamped` 주석의 한계가 그대로 적용된다) — 판돈은 핸드셰이크로 받은
/// `BattleRankProfile` 에서 오고, 그 자리를 이 구조체로 바꾸면 조작 클라이언트가 자기 판돈을
/// 고를 수 있게 된다.
///
/// 굽는 쪽과 읽는 쪽이 이 한 곳을 지나야 하는 이유가 둘이다.
///  ① **키 이름이 와이어 계약이다** — 구버전이 읽는 이름을 바꾸면 상대 목록에서 그 칸이 조용히
///     비는데 컴파일은 통과한다(`PeerAdvertisementTests` 가 리터럴로 동결한다).
///  ② **클램프가 흩어지면 한 곳은 반드시 빠진다** — 값이 상대에게서 오므로 신뢰경계다.
///     이니셜라이저 하나만 자르고 파싱이 그냥 대입하면 조작된 광고가 카드 폭을 밀어낸다.
struct PeerAdvertisement: Equatable, Sendable {
    /// TXT 키. `rankPoints` 는 #85 수정과 함께 이미 배포된 이름이라 **바꾸지 않는다**.
    enum Key {
        static let rank = "rankPoints"
        static let level = "trainerLevel"
        static let tiers = "achievementTiers"
    }

    /// 랭크는 **원본 포인트**를 싣는다 — 이미 배포된 형식이고 읽는 쪽이 `BattleRank` 로 파생한다.
    private(set) var rankPoints: Int?
    /// 레벨은 **표시값**을 싣는다(포인트가 아니다). 곡선(`TrainerLevel.pointsPerStep`)은 조절
    /// 손잡이라 언제든 바뀔 수 있는데, 포인트를 실으면 곡선을 바꾼 순간 구버전이 남의 레벨을
    /// 틀리게 계산한다. "레벨"은 곡선과 무관하게 같은 뜻이다.
    private(set) var trainerLevel: Int?
    /// 도달한 업적 단계의 합계(0...`AchievementLadder.tierCeiling`). 같은 이유로 표시값이다.
    private(set) var achievementTiers: Int?

    /// 굽는 쪽 진입점. **클램프는 여기 한 곳**이고 파싱도 이 자리를 지난다.
    init(rankPoints: Int? = nil, trainerLevel: Int? = nil, achievementTiers: Int? = nil) {
        self.rankPoints = rankPoints.map { BattleRank.clamped($0) }
        // 레벨 하한은 0 이 아니라 1 이다 — `TrainerLevel.level` 이 1 부터 시작하므로 Lv.0 은
        // 존재하지 않는 값이고, 카드에 그려지면 상대가 앱을 잘못 읽는다.
        self.trainerLevel = trainerLevel.map { min(TrainerLevel.maximumLevel, max(1, $0)) }
        self.achievementTiers = achievementTiers.map { min(AchievementLadder.tierCeiling, max(0, $0)) }
    }

    /// 읽는 쪽 진입점 — **관대 파싱이고 절대 실패하지 않는다**(`init?` 가 아니다).
    /// 실패시키면 그 피어가 목록에서 사라져 대전 신청 자체가 불가능해진다. 없는 키·숫자가 아닌
    /// 값은 nil 로 남긴다(0 으로 떨어뜨리면 랭크 없는 상대가 "Iron 4 · 0 LP" 로 보인다).
    init(_ record: NWTXTRecord) {
        self.init(rankPoints: record[Key.rank].flatMap(Int.init),
                  trainerLevel: record[Key.level].flatMap(Int.init),
                  achievementTiers: record[Key.tiers].flatMap(Int.init))
    }

    /// 비어 있는 칸은 키를 싣지 않는다 — 읽는 쪽이 "없음"과 "0"을 구별해야 한다.
    var txtRecord: NWTXTRecord {
        var entries: [String: String] = [:]
        if let rankPoints { entries[Key.rank] = String(rankPoints) }
        if let trainerLevel { entries[Key.level] = String(trainerLevel) }
        if let achievementTiers { entries[Key.tiers] = String(achievementTiers) }
        return NWTXTRecord(entries)
    }

    /// 카드가 쓰는 랭크. 광고에 랭크가 없으면 nil 이어야 한다 — 빈 `BattleRank()` 를 돌려주면
    /// "랭크 정보 없음" 대신 Iron 4 가 그려져 정보 없음과 최하위가 구별되지 않는다.
    var rank: BattleRank? { rankPoints.map { BattleRank(points: $0) } }
}
