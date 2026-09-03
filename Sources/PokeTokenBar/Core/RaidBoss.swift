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

    /// 이 티어를 잡으면 보스가 박스로 따라오나. **1★ 는 안 연다** — 400 HP 는 둘이 몇 턴에
    /// 깨는데 추첨 풀이 전부 전설·유사전설이라, 열면 알 부화(20,000 별의조각)가 뜻을 잃는다.
    /// 3★ 부터가 "뭉쳐야 잡힌다" 의 시작이고, HP 표가 이미 그 머릿수를 강제한다.
    var grantsCatch: Bool {
        switch self {
        case .one: false
        case .three, .five: true
        }
    }

    /// 어느 티어에서도 넘지 못하는 보스 HP 천장. 와이어 디코딩이 이 값을 상한으로 쓴다 —
    /// 티어를 모르는 자리라 개별 티어 값을 쓸 수 없다.
    static var maxBossHP: Int { allCases.map(\.bossHP).max() ?? 0 }

    /// 방 목록이 그리는 권장 인원. **표에서 파생한다** — 따로 적어 두면 HP 를 조정할 때 한쪽만
    /// 바뀌어 화면이 거짓말을 한다.
    var recommendedRunners: Int {
        max(1, Int((Double(bossHP) / Double(RaidBoss.runnerDamageBudget)).rounded(.up)))
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

    var isCaught: Bool { self == .box || self == .companion }
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
    /// 부화한 보스가 살아 있는 시간(분).
    static let activeMinutes = 45
    /// 남은 턴 1 당 보너스.
    static let turnBonusPerTurn = 10
    /// 살아남은 러너 1명당 보너스.
    static let survivorBonusPerRunner = 50
    /// 협동 항이 붙기 시작하는 머릿수. 이 값 미만이면 정산은 기본급 하나로 접히고 포획도 없다.
    static let minimumCoopRunners = 2

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

    /// 하루에 걸리는 부화 알림 개수. **평일·주말 중 많은 쪽**이다 — 한쪽 수로만 알림을 지우면
    /// 블록이 더 많은 요일에 건 예약이 다음 날 안 지워져, 껐는데도 어제 알림이 살아 터진다.
    static var hatchBlocksPerDay: Int { max(weekdayBlocks.count, weekendBlocks.count) }

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
        guard runnerCount >= minimumCoopRunners else {
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
