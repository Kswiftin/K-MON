import Foundation

/// 혼자 3대3 연승에 도전하는 배틀프런티어 규칙.
enum BattleFrontier {
    static let teamSize = 3
    static let battleLevel = 50

    /// 연승 구간이 오를수록 종족값이 높은 풀로 이동한다. 7연승마다 강한 트레이너가 등장하고,
    /// 14연승부터는 전설 포켓몬도 섞인다. 한 팀 안에서는 같은 종을 중복시키지 않는다.
    static func opponentPool(for nextStreak: Int) -> [Int] {
        switch nextStreak {
        case ...3:
            [3, 6, 9, 26, 34, 65, 68, 76, 94, 130, 131, 143]
        case ...6:
            [59, 121, 123, 127, 142, 149, 196, 212, 229, 230, 242, 248]
        case ...13:
            [282, 306, 330, 350, 373, 376, 392, 395, 445, 448, 462, 635, 637]
        default:
            [144, 145, 146, 150, 243, 244, 245, 249, 250, 377, 378, 379, 380, 381, 382, 383, 384]
        }
    }

    /// 한 판 승리 때 즉시 받는 별의조각. 긴 연승을 잃더라도 이미 딴 보상은 사라지지 않는다.
    static func reward(for streak: Int) -> Int {
        guard streak > 0 else { return 0 }
        let base = 300 + min(streak, 20) * 100
        return streak.isMultiple(of: 7) ? base + 2_000 : base
    }

    static func trainerName(for nextStreak: Int) -> String {
        nextStreak.isMultiple(of: 7) ? "프런티어 브레인" : "프런티어 트레이너"
    }
}
