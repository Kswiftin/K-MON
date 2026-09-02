import Foundation

/// 레이드 티어 — 파티 규모에 맞춘 세 단계.
///
/// **보스 HP 는 참가 인원으로 스케일하지 않는다.** 스케일하면 뭉칠 이유가 사라진다(포켓몬 GO 도
/// 스케일하지 않는다). 대신 티어가 필요한 머릿수를 정하고, LAN 이라 사람이 안 모일 수 있으니
/// 1★ 는 혼자서도 잡히게 둔다 — 그게 "이웃이 없으면 콘텐츠가 0" 을 막는 자리다.
enum RaidTier: Int, Codable, Sendable, CaseIterable {
    case one = 1, three = 3, five = 5

    /// 보스 레벨. **HP 가 절대값이라 레벨은 보스의 화력만 정한다** — 손잡이가 둘로 갈리지 않는다.
    /// 파티 레벨(50)을 넘지 않게 둔다. 넘기면 화력이 HP 표와 무관하게 튀어 5★ 가 첫 턴에 한 명을
    /// 지우고, 그 순간 "셋이면 잡힌다"는 산수가 무의미해진다.
    var bossLevel: Int {
        switch self {
        case .one: 10
        case .three: 25
        case .five: 40
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
        }
    }

    /// 잡았을 때의 기본급(별의조각). 기여도 항이 여기에 비율로 붙으므로 이 값이 곧 티어의 단가다.
    /// 기준선 — 일일 미션 합 800 · 이상한 사탕 5,000 · 알 20,000.
    var baseReward: Int {
        switch self {
        case .one: 300
        case .three: 800
        case .five: 2_000
        }
    }

    /// 방 목록이 그리는 권장 인원. **표에서 파생한다** — 따로 적어 두면 HP 를 조정할 때 한쪽만
    /// 바뀌어 화면이 거짓말을 한다.
    var recommendedRunners: Int {
        max(1, Int((Double(bossHP) / Double(RaidBoss.runnerDamageBudget)).rounded(.up)))
    }
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
    /// 러너 한 명이 상한까지 넣는 기대 피해. 레벨 50 끼리 한 턴 약 60 × 20턴 = 1,200 이다.
    /// **티어 HP 표가 이 값을 기준으로 머릿수를 가른다** — 400(혼자) · 1,600(둘) · 2,800(셋).
    static let runnerDamageBudget = 1_200
    /// 부화한 보스가 살아 있는 시간(분).
    static let activeMinutes = 45
    /// 남은 턴 1 당 보너스.
    static let turnBonusPerTurn = 10
    /// 살아남은 러너 1명당 보너스.
    static let survivorBonusPerRunner = 50

    /// 예약 부화는 항상 5★ 다 — 예약이 존재하는 이유가 "혼자서는 못 여는 티어를 위해 사람을 모으는
    /// 것" 이라서다. 아무 때나 여는 방은 1★·3★ 만 고를 수 있다.
    static let hatchTier = RaidTier.five
    static let adHocTiers: [RaidTier] = [.one, .three]

    /// 방 안에서 보스를 가리키는 고정 id. 참가자 UUID 와 겹칠 일이 없고, 고정이라 화면·정산·로그가
    /// 팀 색이 아니라 이름으로 보스를 짚을 수 있다.
    static let bossID = UUID(uuidString: "B0550000-0000-4000-A000-00000000B055")!

    /// 보스가 될 수 있는 종. **큐레이션이다** — 전 범위 균등 추첨은 "오늘의 보스: 캐터피" 를 만든다.
    /// 1~5세대(PokéAPI 1...649) 안에서 고른다.
    static let speciesPool = [
        3, 6, 9, 65, 94, 130, 131, 143, 149, 150,
        212, 229, 248, 249, 250, 257, 260, 282, 289, 373,
        376, 384, 392, 445, 448, 483, 484, 487, 635, 643,
        644, 646
    ]

    /// 평일 해치 블록(자정으로부터의 분). 08:00–11:00 · 11:30–15:00 · 15:30–**18:15**.
    ///
    /// 사무실 시나리오를 전제한다 — 이 앱은 업무용 맥의 메뉴막대에 살고 LAN 은 대개 사내망이다.
    /// **마지막 블록만 창보다 일찍 닫는다**(18:15). 45분 활성이라 19:00 에 부화하면 19:45 에 끝나
    /// 아무도 없는 시간대로 넘어간다 — 이슈의 열린 질문을 캡으로 닫은 자리다.
    static let weekdayBlocks: [ClosedRange<Int>] = [480...660, 690...900, 930...1095]
    /// 주말 블록 — 사무실이 없으니 통째로 뒤로 민다. 11:00–14:00 · 14:30–18:00 · 18:30–21:15.
    /// 마지막 부화가 21:15 + 45분 = 22:00 에 닫힌다.
    static let weekendBlocks: [ClosedRange<Int>] = [660...840, 870...1080, 1110...1275]

    /// 날짜 키 → 난수 시드.
    ///
    /// **자릿값을 곱한다.** 코드포인트를 그냥 더하면 `2026-09-02` 와 `2026-09-20` 이 같은 시드가
    /// 되어 서로 다른 날이 같은 보스·같은 시각표를 받는다.
    static func seed(dayKey: String) -> UInt64 {
        dayKey.unicodeScalars.reduce(UInt64(0x9E37_79B9_7F4A_7C15)) { $0 &* 31 &+ UInt64($1.value) }
    }

    /// 오늘의 보스 종. 플레이어는 고를 수 없다 — 고르게 두면 모두가 가장 이득인 하나만 판다.
    static func speciesID(dayKey: String) -> Int {
        var rng = SplitMix64(seed: seed(dayKey: dayKey))
        return speciesPool[Int(rng.next() % UInt64(speciesPool.count))]
    }

    /// 오늘의 5★ 부화 시각 — 자정으로부터의 **분**. 블록마다 하나씩 뽑아 오름차순으로 돌려준다.
    ///
    /// **분으로 돌려주고 `Date` 로 굽지 않는다.** 달력·시간대를 코어에 들이면 `TimeZone.current`
    /// 캐시(defect-log)와 DST 경계가 순수 함수 안으로 따라 들어온다. 굽는 일은 호출부 몫이다.
    ///
    /// 블록마다 하나씩 뽑는 이유는 뭉침 방지다. 하루 전체에서 셋을 균등 추첨하면 09:05·09:20·09:40
    /// 같은 날이 나와 "하나를 놓쳐도 둘이 남는다" 는 보증이 사라진다.
    static func hatchMinutes(dayKey: String, isWeekend: Bool) -> [Int] {
        var rng = SplitMix64(seed: seed(dayKey: dayKey))
        _ = rng.next()   // 첫 뽑기는 종이 썼다 — 종과 시각이 한 값에서 갈라지지 않게 건너뛴다.
        return (isWeekend ? weekendBlocks : weekdayBlocks).map { block in
            block.lowerBound + Int(rng.next() % UInt64(block.count))
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
            && fighter.side.snapshot.speciesID == speciesID(dayKey: dayKey)
            && fighter.side.snapshot.level == tier.bossLevel
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
    /// 인자는 전부 호스트가 보내오는 값이라 여기서 자른다 — 음수와 100% 초과 기여를 막는다.
    static func settlement(tier: RaidTier, myDamage: Int, totalDamage: Int,
                           turnsRemaining: Int, survivingRunners: Int) -> RaidSettlement {
        let share = totalDamage > 0 ? min(1, Double(max(0, myDamage)) / Double(totalDamage)) : 0
        return RaidSettlement(
            base: tier.baseReward,
            contribution: Int((Double(tier.baseReward) * share).rounded(.down)),
            turnBonus: turnBonusPerTurn * max(0, turnsRemaining),
            survivorBonus: survivorBonusPerRunner * max(0, survivingRunners))
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

    static func isRaidRoomName(_ name: String) -> Bool { name.hasPrefix("\(prefix) · ") }

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

/// 예약 부화의 달력 층 — `RaidBoss.hatchMinutes` 가 낸 **분**을 그날의 `Date` 로 굽는다.
///
/// 코어와 나눠 둔 이유는 시간대다. `TimeZone.current` 는 프로세스 첫 값에 캐시되므로(defect-log)
/// 달력을 순수 추첨 안에 들이면 시간대가 바뀐 뒤에도 옛 값으로 계산한다. `Calendar(identifier:)`
/// 를 매번 새로 만드는 이 자리 하나에만 달력을 둔다.
enum RaidSchedule {
    /// 부화 15분 전에 알린다. **선택이 아니라 필수다** — 시각이 무작위라 습관이 대신해 주지 못한다.
    static let reminderLeadMinutes = 15

    /// `SeasonBoard.gregorian` 과 같은 접근자 규약 — 캐시된 시간대를 물려받지 않는다.
    static var calendar: Calendar { Calendar(identifier: .gregorian) }

    /// 그날의 5★ 부화 시각 셋(오름차순). 같은 날의 어느 시각으로 물어도 같은 답이다 —
    /// 아침에 공개한 표가 오후에 바뀌면 "공개된 무작위" 가 아니다.
    static func hatches(on date: Date, calendar: Calendar = RaidSchedule.calendar) -> [Date] {
        let midnight = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: date)
        let minutes = RaidBoss.hatchMinutes(dayKey: CompanionStore.dayKey(date),
                                            isWeekend: weekday == 1 || weekday == 7)
        return minutes.compactMap { calendar.date(byAdding: .minute, value: $0, to: midnight) }
    }

    /// 지금 살아 있는 부화. 없으면 5★ 방을 열 수 없다.
    static func activeHatch(at now: Date, calendar: Calendar = RaidSchedule.calendar) -> Date? {
        hatches(on: now, calendar: calendar).last {
            $0 <= now && now < $0.addingTimeInterval(TimeInterval(RaidBoss.activeMinutes * 60))
        }
    }

    /// 다음 부화. **오늘 게 다 지났으면 내일 첫 부화를 본다** — nil 을 내면 화면이 저녁 내내
    /// "다음 5★ 없음" 을 그린다.
    static func nextHatch(after now: Date, calendar: Calendar = RaidSchedule.calendar) -> Date? {
        if let today = hatches(on: now, calendar: calendar).first(where: { $0 > now }) { return today }
        // 그레고리력에 하루를 더하는 계산은 실패할 입력이 없다 — 그래도 API 가 옵셔널이라
        // 폴백을 둔다(24시간 가산은 DST 를 가로지르는 날에만 한 시간 어긋나고, 그 어긋남은
        // 다음 날 첫 부화 시각 표시에서 흡수된다).
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now)
            ?? now.addingTimeInterval(24 * 60 * 60)
        return hatches(on: tomorrow, calendar: calendar).first
    }

    /// 오늘 남은 부화의 **알림 예약 시각**. 지나간 것과 이미 부화한 것은 빼고 돌려준다 —
    /// 과거 시각으로 예약하면 알림이 즉시 터지거나 조용히 버려진다.
    ///
    /// 내일 몫을 여기서 같이 내지 않는 이유는 재예약이다: 날짜가 바뀌면 앱이 다시 걸므로
    /// 하루치만 들고 있으면 된다(자정에 깨어날 이유를 만들지 않는다).
    static func upcomingReminders(after now: Date, calendar: Calendar = RaidSchedule.calendar) -> [Date] {
        hatches(on: now, calendar: calendar)
            .map { $0.addingTimeInterval(TimeInterval(-reminderLeadMinutes * 60)) }
            .filter { $0 > now }
    }
}
