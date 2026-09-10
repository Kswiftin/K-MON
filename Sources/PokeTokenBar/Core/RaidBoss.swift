import Foundation

/// 레이드 티어 — 파티 규모에 맞춘 세 단계.
///
/// **보스 HP 는 참가 인원으로 스케일하지 않는다.** 스케일하면 뭉칠 이유가 사라진다(포켓몬 GO 도
/// 스케일하지 않는다). 대신 티어가 필요한 머릿수를 정하고, LAN 이라 사람이 안 모일 수 있으니
/// 1★ 는 혼자서도 잡히게 둔다 — 그게 "이웃이 없으면 콘텐츠가 0" 을 막는 자리다.
enum RaidTier: Int, Codable, Sendable, CaseIterable {
    case one = 1, three = 3, five = 5, six = 6

    /// 보스 레벨. **HP 가 절대값이라 레벨은 보스의 화력만 정한다** — 손잡이가 둘로 갈리지 않는다.
    /// 파티 레벨(50)을 넘지 않게 둔다. 넘기면 화력이 HP 표와 무관하게 튀어 5★ 가 첫 턴에 한 명을
    /// 지우고, 그 순간 "셋이면 잡힌다"는 산수가 무의미해진다.
    var bossLevel: Int {
        switch self {
        case .one: 10
        case .three: 25
        case .five: 40
        case .six: 50
        }
    }

    /// 보스 HP — **종족값에서 파생하지 않는 절대값**이다. 파생시키면 그날 뽑힌 종에 따라 같은
    /// 티어의 난이도가 널뛰고, 받는 쪽이 "이 HP 가 맞는 값인가"를 검증할 기준도 없어진다.
    /// 검증이 정확한 등호가 되는 것(`RaidBoss.validBoss`)이 절대값을 고른 두 번째 이유다.
    var bossHP: Int {
        switch self {
        case .one: 400
        case .three: 1_600
        case .five: 2_800
        // 2026-09-10 완화: 6,000 → 5,200. 난이도가 너무 높다는 피드백 — 레벨(화력)은 그대로 두고
        // 그라인드만 줄인다(`testTierHPGatesPartySize` 의 상한·하한 안에서).
        case .six: 5_200
        }
    }

    /// 잡았을 때의 기본급(별의조각). 기여도 항이 여기에 비율로 붙으므로 이 값이 곧 티어의 단가다.
    /// 기준선 — 알(보증 없음) 20,000.
    ///
    /// **세 티어를 혼자 다 돌아도(협동 보너스 없이) 알 하나 값이 나오게 잡았다(#270).** 티어를
    /// 나눠 각자 원장을 준 뒤로 세 번 다 도는 유인이 생겼는데, 예전 기본급(300+800+2,000=3,100)
    /// 으로는 반나절 다 채워도 알 값의 15% 뿐이었다 — 비율(1 : 2.5 : 6.5)은 옛 값과 거의 같게
    /// 유지하고 절대값만 올렸다.
    var baseReward: Int {
        switch self {
        case .one: 2_000
        case .three: 5_000
        case .five: 13_000
        case .six: 20_000
        }
    }

    /// 모든 티어는 성공 시 등급별 포획 판정을 연다. 티어는 난이도·재화량만 가른다.
    var grantsCatch: Bool { true }

    /// 어느 티어에서도 넘지 못하는 보스 HP 천장. 와이어 디코딩이 이 값을 상한으로 쓴다 —
    /// 티어를 모르는 자리라 개별 티어 값을 쓸 수 없다.
    static var maxBossHP: Int { allCases.map(\.bossHP).max() ?? 0 }

    /// 방 목록이 그리는 권장 인원. **표에서 파생한다** — 따로 적어 두면 HP 를 조정할 때 한쪽만
    /// 바뀌어 화면이 거짓말을 한다.
    var recommendedRunners: Int {
        if self == .six { return 5 }
        return max(1, Int((Double(bossHP) / Double(RaidBoss.runnerDamageBudget)).rounded(.up)))
    }
}

/// 포획이 어디서 끝났나. **불리언으로는 화면이 반드시 한 번 거짓말을 한다** — 실패와 "오늘은 이미
/// 잡았다" 가 같은 값이면 문구가 둘 중 하나를 틀리고, 성공도 상자와 빈 동행 자리를 구별하지 못해
/// 사용자가 빈 상자를 열게 된다.
enum RaidCatchResult: Sendable, Equatable {
    /// 상자로 들어갔다(동행이 있는 평소의 판).
    case box
    /// 비어 있던 동행 자리를 채웠다 — 졸업 직후 등.
    case companion
    /// 오늘의 한 마리를 이미 데려왔다. **불러오기 실패가 아니다**: 네트워크를 건드리지도 않았고,
    /// 오늘 다시 도전해도 결과가 같다.
    case claimedToday
    /// 보스를 세울 수 없었다(라인 조회 실패·그릴 수 없는 번호). 원장을 태우지 않아 오늘 다시 된다.
    case unavailable
    /// 포획 판정에는 참여했지만 등급별 확률을 넘지 못했다.
    case escaped

    var isCaught: Bool { self == .box || self == .companion }
}

/// 하루를 정오 기준 두 레이드로 나누는 키. 보스·보상·포획이 모두 이 키를 공유한다.
enum RaidHalfDay: String, Sendable, CaseIterable {
    case morning = "am", afternoon = "pm"

    static func at(_ date: Date, calendar: Calendar = .current) -> Self {
        calendar.component(.hour, from: date) < 12 ? .morning : .afternoon
    }

    static func satisfiesEvolution(_ condition: String, at date: Date,
                                   calendar: Calendar = .current) -> Bool {
        switch condition {
        case "day": Self.at(date, calendar: calendar) == .morning
        case "night": Self.at(date, calendar: calendar) == .afternoon
        default: false
        }
    }
}

struct RaidCatchAttempt: Identifiable, Sendable, Equatable {
    let id: UUID
    let trainerName: String
    let succeeded: Bool
}

/// 한 판의 정산 내역. **항을 나눠 들고 다니는 이유는 완전설명이다** — 지갑을 늘린 값은 화면이
/// 그 자리에서 설명할 수 있어야 한다(defect-log: 한 지갑에 지급하는 경로가 여럿일 때).
struct RaidSettlement: Sendable, Equatable {
    let base: Int
    let contribution: Int
    let turnBonus: Int
    let survivorBonus: Int

    var total: Int { base + contribution + turnBonus + survivorBonus }
}

/// 오늘의 보스와 해치 시각, 그리고 정산 — 전부 `dayKey` 하나에서 나오는 순수 계산이다.
///
/// **서버가 없다.** 모든 클라이언트가 같은 날짜 키에서 같은 답을 뽑기 때문에 협의 없이 같은 보스와
/// 같은 시각표를 본다(`MissionBoard` 의 날짜 키 비교와 같은 계열).
///
/// 그래서 **받는 쪽도 스스로 계산해 대조한다.** 보상은 각 클라이언트가 자기 지갑에 넣으므로,
/// 호스트가 보낸 보스를 그대로 믿으면 조작된 호스트가 약한 보스에 5★ 딱지를 붙여 방 전원에게
/// 5★ 보상을 뿌린다. `validBoss` 가 그 경계다.
enum RaidBoss {
    /// 파티는 전부 이 레벨로 눕는다(체육관·토너먼트와 같은 규칙). 눕히지 않으면 레벨 100 파티가
    /// 5★ 를 세 턴에 끝내고 티어 표가 뜻을 잃는다.
    static let partyLevel = 50
    /// 턴 상한. 벽시계가 아니라 턴으로 재는 이유는 이 배틀이 턴제라서다 — GO 의 3·5분 타이머는
    /// 생각할 시간과 싸운다. GO 의 "남은 시간" 보상 항은 여기서 "남은 턴"이 된다.
    static let turnCap = 20
    /// 진 판이 **턴 상한**으로 끝났나 — 상한과 전멸은 다음에 할 일이 다르다(티어를 낮추는 것과
    /// 화력을 올리는 것). `round` 는 판이 멈춘 시점의 다음 라운드 번호다.
    static func endedByTurnCap(round: Int) -> Bool { round > turnCap }

    /// 러너 한 명이 상한까지 넣는 기대 피해. 레벨 50 끼리 한 턴 약 60 × 20턴 = 1,200 이다.
    /// **티어 HP 표가 이 값을 기준으로 머릿수를 가른다** — 400(혼자) · 1,600(둘) · 2,800(셋).
    static let runnerDamageBudget = 1_200
    /// 남은 턴 1 당 보너스.
    static let turnBonusPerTurn = 10
    /// 살아남은 러너 1명당 보너스.
    static let survivorBonusPerRunner = 50
    /// 협동 항이 붙기 시작하는 머릿수. 이 값 미만이면 정산은 기본급 하나로 접힌다.
    ///
    /// **포획은 이 값과 무관하다.** 예전엔 이 자리에 "포획도 없다" 고 적혀 있었는데, 그걸 실제로
    /// 막는 코드가 없었다 — `drawRaidCatcher` 는 인원수를 안 보고 이탈자(`hasLeft`)만 거른다.
    /// `testASoloWinGetsTheSameRarityCatchChance` 가 혼자 3★ 를 깨고도 잡히는 것을 이미 검증하고
    /// 있었다. 별·인원과 무관하게 클리어(그 반나절·그 티어의 첫 승리)만 하면 포획 추첨이 돈다.
    static let minimumCoopRunners = 2

    static func isShinyBoss(tier: RaidTier) -> Bool { tier == .six }

    /// 이 머릿수에 협동 항이 붙나. **정산과 화면이 같은 술어를 본다** — 화면이 "협동 보너스는 2명
    /// 이상부터" 를 그리는 조건을 따로 적으면, 머릿수 기준을 옮긴 날 문구와 실제 정산이 갈린다.
    static func coopTermsApply(runnerCount: Int) -> Bool { runnerCount >= minimumCoopRunners }

    /// 방 안에서 보스를 가리키는 고정 id. 참가자 UUID 와 겹칠 일이 없고, 고정이라 화면·정산·로그가
    /// 팀 색이 아니라 이름으로 보스를 짚을 수 있다.
    static let bossID = UUID(uuidString: "B0550000-0000-4000-A000-00000000B055")!

    /// 보스가 될 수 있는 종. **큐레이션이다** — 전 범위 균등 추첨은 "오늘의 보스: 캐터피" 를 만든다.
    /// 1~5세대(PokéAPI 1...649) 안에서 고른다.
    ///
    /// **티어마다 다른 풀을 쓴다(#270).** 예전엔 티어와 무관하게 반나절 보스가 하나였다 — 1★로도
    /// 5★와 같은 종·같은 포획 확률을 얻으니, 사람을 더 모아야 하는 것 말고는 5★를 돌 이유가
    /// 없었다. 이제 1★=고급, 3★=희귀, 5★=전설로 갈라 티어마다 고유한 포획 기회를 준다.
    static let uncommonSpeciesPool = [
        3, 6, 9, 18, 31, 34, 36, 45, 51, 55, 59, 68, 71, 76, 94, 103, 112, 121,
        127, 131, 134, 135, 136, 143, 154, 157, 160, 182, 186, 195, 199, 205, 208,
        212, 217, 221, 224, 229, 230, 232, 237, 242, 254, 257, 260, 272, 275, 282,
        286, 295, 297, 306, 308, 310, 319, 321, 323, 324, 326, 330, 332, 334, 350,
        354, 357, 362, 365, 389, 392, 395, 398, 405, 407, 409, 416, 419, 423, 426,
        430, 432, 435, 437, 450, 452, 454, 460, 461, 462, 463, 465, 469, 470, 471,
        497, 500, 503, 508, 514, 516, 518, 521, 523, 526, 530, 534, 537, 542, 545,
        549, 553, 555, 560, 563, 565, 567, 569, 571, 573, 576, 579, 581, 584, 586,
        589, 591, 593, 596, 598, 601, 604, 609, 612, 614, 617, 621, 623, 625, 628,
        630, 632
    ]
    static let rareSpeciesPool = [
        65, 130, 149, 169, 248, 289, 373, 376, 445, 448, 464, 466, 467, 468, 472,
        473, 474, 475, 476, 477, 478, 635, 637
    ]
    static let legendarySpeciesPool = [
        144, 145, 146, 150, 243, 244, 245, 249, 250, 377, 378, 379, 380, 381, 382,
        383, 384, 480, 481, 482, 483, 484, 485, 486, 487, 488, 638, 639, 640, 641,
        642, 643, 644, 645, 646
    ]
    /// 주간 6성은 일반 티어와 별도 로테이션이다. 강한 최종 진화체를 넓게 섞어 같은 보스가
    /// 몇 주 간격으로 되풀이되는 느낌을 줄인다.
    static let weeklySpeciesPool = [
        28, 38, 40, 49, 53, 57, 62, 73, 78, 80, 82, 85, 87, 89, 91, 97, 99,
        101, 105, 110, 113, 119, 122, 123, 124, 125, 126, 128, 139, 141, 142, 164,
        168, 171, 178, 181, 184, 185, 189, 192, 201, 202, 203, 206, 210, 211, 213,
        214, 215, 216, 219, 222, 225, 226, 227, 234, 235, 241, 262, 267, 269, 277,
        279, 291, 301, 303, 317, 320, 335, 336, 337, 338, 340, 342, 344, 346, 348,
        352, 356, 358, 364, 367, 368, 369, 370, 411, 413, 414, 417, 424, 428, 429,
        431, 442, 455, 457, 479, 512, 547, 556, 558, 561, 566, 575, 578, 583, 587, 594,
        606, 615, 620, 624, 631
    ]

    /// 티어가 뽑는 풀. `speciesID(dayKey:tier:)` 가 이 풀 안에서만 고른다.
    static func speciesPool(for tier: RaidTier) -> [Int] {
        switch tier {
        case .one: uncommonSpeciesPool
        case .three: rareSpeciesPool
        case .five: legendarySpeciesPool
        case .six: weeklySpeciesPool
        }
    }

    /// 현재 큐레이션 풀의 공식 희귀도. 일반 등급은 레이드 풀에 없다 — 풀이 곧 티어를 가르므로
    /// 종만 보고도 등급이 정해진다.
    static func rarity(speciesID: Int) -> Rarity {
        if legendarySpeciesPool.contains(speciesID) { return .legendary }
        return uncommonSpeciesPool.contains(speciesID) ? .uncommon : .rare
    }

    static func catchPercent(for rarity: Rarity) -> Int {
        switch rarity {
        case .legendary: 5
        case .rare: 15
        case .uncommon, .common: 25
        }
    }

    /// 주간 6성은 보스가 이로치로 확정되는 대신 포획 확률을 3%로 제한한다.
    static func catchPercent(tier: RaidTier, speciesID: Int) -> Int {
        tier == .six ? 3 : catchPercent(for: rarity(speciesID: speciesID))
    }

    /// 반나절로 안 가른, 달력 하루 키(`yyyy-MM-dd`) — 6★ 주간 레이드의 보상·포획 원장이 쓴다
    /// (오전/오후 무관 하루 2회, `CompanionStore.sixStarDailyClaimLimit`).
    static func dailyKey(_ date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0,
                      components.month ?? 0, components.day ?? 0)
    }

    static func periodKey(_ date: Date, calendar: Calendar = .current) -> String {
        "\(dailyKey(date, calendar: calendar))-\(RaidHalfDay.at(date, calendar: calendar).rawValue)"
    }

    /// 날짜 키 → 난수 시드.
    ///
    /// **자릿값을 곱한다.** 코드포인트를 그냥 더하면 `2026-09-02` 와 `2026-09-20` 이 같은 시드가
    /// 되어 서로 다른 날이 같은 보스·같은 시각표를 받는다.
    static func seed(dayKey: String) -> UInt64 {
        dayKey.unicodeScalars.reduce(UInt64(0x9E37_79B9_7F4A_7C15)) { $0 &* 31 &+ UInt64($1.value) }
    }

    /// 오늘의 보스 종. 플레이어는 고를 수 없다 — 고르게 두면 모두가 가장 이득인 하나만 판다.
    ///
    /// 시드를 **티어로도 가른다**(`seed(dayKey:) ^ tier.rawValue` 대신 dayKey 에 접미를 붙인다 —
    /// 같은 시드 계열을 재사용하는 다른 자리(`seed(dayKey:)` 를 직접 쓰는 코드)와 우연히 부딪히지
    /// 않게 완전히 별도 문자열로 해시한다). 안 가르면 세 티어가 매번 같은 종을 뽑아 풀을 나눈
    /// 의미가 없어진다.
    static func speciesID(dayKey: String, tier: RaidTier) -> Int {
        let pool = speciesPool(for: tier)
        let tierKey = "\(dayKey)-t\(tier.rawValue)"
        var rng = SplitMix64(seed: seed(dayKey: tierKey))
        let index = Int(rng.next() % UInt64(pool.count))
        guard dayKey.hasSuffix("-pm") else { return pool[index] }
        let morningKey = String(dayKey.dropLast(2)) + "am-t\(tier.rawValue)"
        var morningRNG = SplitMix64(seed: seed(dayKey: morningKey))
        let morningIndex = Int(morningRNG.next() % UInt64(pool.count))
        return pool[index == morningIndex ? (index + 1) % pool.count : index]
    }

    static func speciesID(at date: Date, tier: RaidTier, calendar: Calendar = .current) -> Int {
        speciesID(dayKey: bossKey(at: date, tier: tier, calendar: calendar), tier: tier)
    }

    static func weeklyPeriodKey(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return String(format: "%04d-W%02d", parts.yearForWeekOfYear ?? 0, parts.weekOfYear ?? 0)
    }

    /// 반나절보다 잘게 자른 시간 키(`yyyy-MM-dd-HH`) — 이벤트 창(`LiveEventWindow`) 동안만
    /// `bossKey`가 이 키로 종을 뽑는다. `-am`/`-pm` 접미사와 형태가 달라 `speciesID(dayKey:tier:)`
    /// 의 "오전과 다른 종" 보정(`hasSuffix("-pm")`)은 안 타지만, 1시간짜리 이벤트 로테이션에는
    /// 그 보정이 애초에 필요 없다 — 다음 시간에 또 새로 뽑으므로 연속 반복은 감내한다.
    static func hourlyKey(_ date: Date, calendar: Calendar = .current) -> String {
        let hour = calendar.component(.hour, from: date)
        return String(format: "%@-%02d", dailyKey(date, calendar: calendar), hour)
    }

    /// 오늘의 레이드 보스를 고르는 키. 6★ 는 그 주 내내 고정(`weeklyPeriodKey`), 나머지는 평소
    /// 반나절(`periodKey`)마다 바뀌지만 이벤트 창 동안은 `hourlyKey`로 매시간 바뀐다.
    static func bossKey(at date: Date, tier: RaidTier, calendar: Calendar = .current) -> String {
        if tier == .six { return weeklyPeriodKey(date, calendar: calendar) }
        return LiveEventWindow.isActive(date, calendar: calendar)
            ? hourlyKey(date, calendar: calendar) : periodKey(date, calendar: calendar)
    }

    /// 참가자마다 독립 포획 판정을 하되 모든 피어가 같은 순서와 결과를 계산한다.
    static func catchAttempts(runners: [MultiplayerFighter], speciesID: Int, tier: RaidTier,
                              seed: UInt64, finishedRound: Int) -> [RaidCatchAttempt] {
        let percent = catchPercent(tier: tier, speciesID: speciesID)
        return runners.sorted { $0.id.uuidString < $1.id.uuidString }.enumerated().map { index, runner in
            var rng = SplitMix64(seed: seed &+ UInt64(bitPattern: Int64(finishedRound))
                                 &+ UInt64(index) &* 0x9E37_79B9_7F4A_7C15)
            return RaidCatchAttempt(id: runner.id, trainerName: runner.trainerName,
                                    succeeded: Int(rng.next() % 100) < percent)
        }
    }

    // MARK: 보스 만들기 · 검증

    /// 호스트가 방에 세울 보스 한 마리. 레벨과 HP 는 **티어가 정한다** — 넘겨받은 스냅샷의 값이
    /// 아니다(그러면 호스트가 정하는 값이 되고, 검증할 기준이 사라진다).
    static func bossFighter(tier: RaidTier, snapshot: BattleSnapshot) -> MultiplayerFighter {
        var snapshot = snapshot
        snapshot.level = tier.bossLevel
        let participant = LobbyParticipant(id: bossID, trainerName: snapshot.name,
                                           speciesID: snapshot.speciesID, team: .blue,
                                           isReady: true, isHost: false)
        var fighter = MultiplayerFighter(participant: participant, snapshot: snapshot)
        fighter.side.hp = tier.bossHP
        return fighter
    }

    /// 받은 보스가 **오늘의 그 보스**인가. 종·레벨·HP 를 전부 등호로 본다.
    ///
    /// 등호인 것이 중요하다. 상한(`hp <= ...`)으로 두면 5★ 딱지를 붙인 400 HP 보스가 통과해
    /// 방 전원이 5★ 보상을 30초 만에 받는다.
    static func validBoss(_ fighter: MultiplayerFighter, tier: RaidTier, dayKey: String) -> Bool {
        fighter.id == bossID && fighter.team == .blue
            && fighter.side.snapshot.speciesID == speciesID(dayKey: dayKey, tier: tier)
            && fighter.side.snapshot.level == tier.bossLevel
            && fighter.side.snapshot.isShiny == isShinyBoss(tier: tier)
            && fighter.side.hp == tier.bossHP
            && fighter.side.status == nil && fighter.side.confusionTurns == 0
            && fighter.side.stages.isEmpty
    }

    /// 게스트가 `.raidStart` 를 받아들일지 — **한 곳에서** 편성 모양과 오늘자 일치를 함께 본다.
    /// 두 검사를 호출부마다 따로 부르게 두면 한쪽만 부르는 경로가 반드시 생긴다.
    /// 보스를 `first(where:)` 로 꺼내 옵셔널을 가드하지 않는다 — `validStart` 가 `.blue` 정확히
    /// 한 명을 이미 보증하므로 그 가드는 **어떤 입력으로도 못 밟는 분기**가 된다(defect-log:
    /// 가드가 중복이라 하나를 지워도 아무 테스트가 안 깨지는 부류). `contains` 로 총함수로 둔다.
    static func validRaidStart(fighters: [MultiplayerFighter], tier: RaidTier, dayKey: String) -> Bool {
        MultiplayerValidation.validStart(fighters: fighters, mode: .coopBoss)
            && fighters.contains { validBoss($0, tier: tier, dayKey: dayKey) }
    }

    // MARK: 정산

    /// GO 의 프리미어볼 식을 옮긴 것 — 기본급 + 기여도 + 남은 턴 + 생존자.
    ///
    /// **기여도 항이 이 식의 존재 이유다.** 없으면 무임승차와 캐리가 같은 값을 받고, 그 순간
    /// 협동은 "누가 대신 잡아 주나"가 된다.
    ///
    /// **혼자 도는 판은 기본급만 받는다.** 나머지 셋은 협동 항이다 — 혼자면 기여 비율이 언제나
    /// 100% 라 기여도 항이 무임승차를 가르는 일을 못 하고, 남은 턴·생존도 결국 머릿수가 만드는
    /// 여유를 재는 값이다. 그 셋이 그대로 붙으면 1인 반복이 협동과 같은 값을 낸다.
    ///
    /// **지급을 통째로 0 으로 두지는 않는다.** 1★ 는 혼자 잡히도록 HP 를 고른 티어라(`RaidTier`
    /// 주석), 0 을 주면 이웃 없는 사용자에게 이 기능이 콘텐츠 0 이 된다 — 줄이되 없애지 않는 것이
    /// "뭉칠 이유" 와 "혼자서도 돌 만함" 을 동시에 지키는 자리다.
    ///
    /// 인자는 전부 호스트가 보내오는 값이라 여기서 자른다 — 음수와 100% 초과 기여를 막는다.
    static func settlement(tier: RaidTier, myDamage: Int, totalDamage: Int,
                           turnsRemaining: Int, survivingRunners: Int,
                           runnerCount: Int) -> RaidSettlement {
        guard coopTermsApply(runnerCount: runnerCount) else {
            return RaidSettlement(base: tier.baseReward, contribution: 0,
                                  turnBonus: 0, survivorBonus: 0)
        }
        let share = totalDamage > 0 ? min(1, Double(max(0, myDamage)) / Double(totalDamage)) : 0
        return RaidSettlement(
            base: tier.baseReward,
            contribution: Int((Double(tier.baseReward) * share).rounded(.down)),
            turnBonus: turnBonusPerTurn * max(0, turnsRemaining),
            survivorBonus: survivorBonusPerRunner * max(0, survivingRunners))
    }

    // MARK: 포획 추첨

    /// 보스를 데려갈 한 명. **정렬된 UUID 를 시드로 짚는다.**
    ///
    /// 정렬이 계약의 절반이다 — 배열 순서로 짚으면 피어마다 `fighters` 순서가 달라 같은 판에서
    /// 서로 다른 사람을 당첨자로 계산하고, 그러면 아무도 못 잡거나 둘이 잡는다.
    ///
    /// 시드로 짚는 나머지 절반은 **와이어를 안 늘리려는 것**이다. `.raidStart` 가 시드와 편성을
    /// 이미 함께 나르므로 모든 피어가 새 메시지 없이 같은 답에 닿는다.
    ///
    /// **끝난 라운드를 함께 섞는 것이 나머지 절반이다.** `.raidStart` 는 시드와 편성을 같이 나르므로
    /// 시드만 읽으면 아무 피어나(와이어를 읽는 사람도) 1라운드에 당첨자를 계산할 수 있다. 못 이기는
    /// 걸 아는 러너들에게 20턴의 누적 피해는 정산 말고는 아무것도 주지 않는데, 기여도 항이 지키려던
    /// 유인이 바로 그것이다. 판이 끝나야 정해지는 값을 섞으면 **와이어는 그대로 두고** 개시 시점
    /// 예측만 막는다 — 끝난 라운드는 모든 피어가 스스로 세는 값이다(`raidFinishedRound`).
    ///
    /// 시드는 호스트가 고른다 — 조작된 호스트는 자기가 뽑힐 때까지 다시 굴릴 수 있다. LAN 이고
    /// 클라이언트 권위라 여기서 막을 방법이 없고, 손해의 상한은 `raidCatchDate` 가 잡는다
    /// (조작해도 그날 가져갈 수 있는 총량은 한 마리다 — `raidRewardDate` 와 같은 규칙).
    static func catcher(runnerIDs: [UUID], seed: UInt64, finishedRound: Int) -> UUID? {
        let ordered = runnerIDs.sorted { $0.uuidString < $1.uuidString }
        guard !ordered.isEmpty else { return nil }
        var rng = SplitMix64(seed: seed &+ UInt64(bitPattern: Int64(finishedRound)))
        return ordered[Int(rng.next() % UInt64(ordered.count))]
    }
}

/// 레이드 방의 Bonjour 광고 이름 — `RAID · <티어> · <트레이너>#<식별자>`.
///
/// **티어를 이름에 싣는 이유는 체육관이 재임 시각을 싣는 이유와 같다**: 방 광고에 TXT 가 없어
/// 붙기 전에 무언가를 보여 줄 통로가 이름뿐이다. 티어를 모르면 1★ 인 줄 알고 5★ 에 혼자 들어가
/// 20턴을 버리게 된다.
struct RaidRoomName: Equatable {
    let tier: RaidTier
    let trainerName: String
    let idTag: String

    static let prefix = "RAID"

    /// **접두 판정은 `LANRoomList` 한 곳에서만 한다** — 여기에 다시 적으면 표가 갈라진다.
    static func isRaidRoomName(_ name: String) -> Bool { LANRoomList.matches(name, activity: .raid) }

    /// 자를 수 있는 건 트레이너 이름뿐이다 — 접두·티어는 파싱에, 접미는 자기 판정에 쓰인다.
    static func make(trainerName: String, idTag: String, tier: RaidTier) -> String {
        LANServiceName.make(base: "\(prefix) · \(tier.rawValue) · \(trainerName)", suffix: "#\(idTag)")
    }

    /// 티어 자리가 없거나 모르는 티어면 **통째로 nil** 이다. 모르는 값을 기본 티어로 접으면
    /// 신버전이 연 티어를 구버전이 1★ 로 그려 "쉬운 줄 알고 들어갔다" 가 된다.
    static func parse(_ name: String) -> RaidRoomName? {
        guard isRaidRoomName(name) else { return nil }
        let body = name.dropFirst("\(prefix) · ".count)
        guard let hash = body.lastIndex(of: "#") else { return nil }
        let idTag = String(body[body.index(after: hash)...])
        let head = body[..<hash]
        guard let separator = head.range(of: " · "),
              let raw = Int(head[..<separator.lowerBound]),
              let tier = RaidTier(rawValue: raw) else { return nil }
        return RaidRoomName(tier: tier, trainerName: String(head[separator.upperBound...]), idTag: idTag)
    }
}
