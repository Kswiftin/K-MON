import Foundation

/// 사파리존(#?) — 4세대 그레이트 마쉬 방식의 스테이지 포획. 뷰·소켓·`CompanionStore` 의존 0인
/// 순수 판정만 여기 산다(`RaidArena` 의 "뷰 밖 enum" 컨벤션과 같다). 전투 엔진을 안 쓰는 이유는
/// 그레이트 마쉬 자체가 HP·기술·스피드 없이 미끼/진흙/볼/도망 네 선택지뿐이기 때문이다.
enum SafariZone {
    // MARK: 단계(stage) 배율

    /// 미끼·진흙이 오르내리는 범위. 본가 명중률/회피율 랭크(±6)의 절반이다 — 사파리존 조우는
    /// 몇 턴 안에 끝나야 하므로 상한을 낮게 잡아 "몇 번 던지면 사실상 잡힌다"를 짧게 만든다.
    static let stageRange = -3...3

    /// 본가가 3세대부터 명중률/회피율 랭크에 쓰는 공식 그대로: 상승은 `(3+n)/3`, 하강은
    /// `3/(3-n)`. 임의 숫자를 새로 짓지 않고 이미 검증된 값을 재사용한다.
    static func stageMultiplier(_ stage: Int) -> Double {
        let clamped = max(stageRange.lowerBound, min(stageRange.upperBound, stage))
        return clamped >= 0 ? Double(3 + clamped) / 3 : 3 / Double(3 - clamped)
    }

    // MARK: 기저 포획률·도망률

    /// 기저 포획률은 `RaidBoss.catchPercent(for:)` 를 그대로 재사용한다 — 종별 실제
    /// `capture_rate` 를 쓰지 않는 이유는 `wave-run-design.md` 의 포획 절과 같다(희귀도 축
    /// 중복, 종마다 API 왕복 추가).
    static func catchPercent(rarity: Rarity, catchStage: Int) -> Int {
        let value = Double(RaidBoss.catchPercent(for: rarity)) * stageMultiplier(catchStage)
        return Int(min(95, max(5, value.rounded())))
    }

    /// 도망률은 **등급 없이 균일** 기저값을 쓴다. 등급을 또 개입시키면 "귀한 종일수록 도망도 잘
    /// 간다"는 이중 페널티가 생겨 희귀 포획이 사실상 불가능해진다.
    static let baseFleePercent = 20
    static func fleePercent(fleeStage: Int) -> Int {
        let value = Double(baseFleePercent) * stageMultiplier(fleeStage)
        return Int(min(95, max(5, value.rounded())))
    }

    // MARK: 조우 예산

    /// 조우당 턴 상한. 단계가 ±3 에서 포화되면 더 던져도 득이 없으므로 충분히 여유롭고, 무한
    /// 루프 가능성(저장·테스트 모두에 나쁘다)을 원천 차단한다.
    static let maxTurnsPerEncounter = 20

    // MARK: 방문 예산 (PR2 이후 `SafariVisit`/`CompanionStore` 가 쓰지만, 규칙과 값을 한 곳에
    // 두는 `RaidBoss` 관례를 따라 여기 둔다)

    /// 하루 방문(참여) 상한 — 걷기·조우 세션 자체를 몇 번 열 수 있는지. `catchesPerVisitCap`
    /// (2) × 이 값(3) = `dailyCatchCap`(6) 으로 정확히 맞물린다.
    static let dailyVisitCap = 3
    /// 방문당 사파리 볼. 방문당 잡을 수 있는 건 최대 `catchesPerVisitCap`(2)뿐이라 30개는커녕
    /// 15개도 대부분 못 쓰고 버려진다 — 몇 번 실패·도망당해도 2마리는 넉넉히 노려볼 수 있는 선.
    static let ballsPerVisit = 10
    /// 방문당 걸음. 원본의 "500걸음"을 그대로 옮긴다 — 실전에서는 포획 상한이 걸음보다 훨씬 먼저
    /// 닿을 것이므로 걸음 소진은 "운이 나빠 계속 놓친 경우"에나 실제로 발동하는 안전판에 가깝다.
    static let stepsPerVisit = 500
    /// 칸 도착마다 굴리는 인카운터 확률(%). 본가처럼 지형·타일별로 정교하게 나누지 않는다.
    static let stepEncounterPercent = 12
    /// 방문당 포획 상한. 하루 방문 3회 × 이 값 = `dailyCatchCap` 과 정확히 맞물린다.
    static let catchesPerVisitCap = 2
    /// 하루 포획 상한. 레이드의 하루 최대 6마리(티어 3 × 반나절 2)와 같은 자리 — 전투 없이
    /// 걷기만 하는 채널이 레이드보다 많이 주면 안 된다.
    static let dailyCatchCap = 6

    // MARK: 구역(zone)

    /// 사파리존 구역. 존마다 다른 종 풀·지형 팔레트를 쓴다.
    enum ZoneID: String, CaseIterable, Codable, Sendable {
        case grassland, wetland, cave
    }

    /// 존 하나의 등급별 서브풀. 전설은 없다 — 알(`FreshEgg`)이 "전설 전용 알은 안 판다"는
    /// 원칙과 같은 자리(전설은 레이드와 알의 몫으로 남긴다).
    private struct GradePools {
        let common: [Int]
        let uncommon: [Int]
        let rare: [Int]
    }

    /// 존 테마에 맞춘 라인업(초원: 벌레·노멀·풀, 습지: 물, 동굴: 바위·땅·독) — 존당 30종
    /// (일반·고급·희귀 정확히 10종씩), 1~9세대를 고루 담되 6~9세대(오픈한 지 얼마 안 된 세대)
    /// 비중을 의식적으로 늘렸다. 미진화체를 넣어도 안전하다 — `CompanionStore.commitCaughtMon`
    /// 은 `pathIDs: [speciesID], totalForms: 1` 로 잡은 개체를 만들지만, 그 개체가 동행으로
    /// 오르면 `loadCurrentLine()` → `normalizedEvolutionState()` 가 실제 진화 트리를 기준으로
    /// `pathIDs`/`totalForms`/`plannedPathIDs` 를 다시 계산한다(레이드가 체인 중간에서 잡은
    /// 개체·위장 메타몽 리빌을 다루려고 이미 갖고 있던 범용 복구 로직이라, 여기도 같은 경로를
    /// 그대로 탄다). 레이드 풀(`RaidBoss.swift`)과 겹치지 않게 골랐다.
    ///
    /// **등급은 진화 단계·capture_rate 가 아니라 종족값 총합(BST) 기준으로 매겼다.**
    /// `capture_rate`(`Rarity.captureRateCeiling`, `CompanionModel.swift`)는 본가에서 "그 폼
    /// 그대로 필드에 얼마나 흔히 나타나는가" 를 뜻하는데, 이 게임엔 사파리존 전까지 그런 "필드
    /// 조우 밀도" 개념 자체가 없었다(알은 항상 baseID 로 부화, 레이드는 그날 정해진 특정 개체) —
    /// 그 수치로 니드킹·퍼퓨돈 같은 흔한 최종진화체까지 희귀로 몰렸다. 대신 레이드 티어별 BST 를
    /// 조사하니 레이드에 뽑히는 종은 전부 BST 500 이상이라는 뚜렷한 하한이 있어("이 게임에서
    /// 특별하게 느껴지는 종" 을 BST 가 훨씬 잘 설명한다), 사파리존 90종을 PokéAPI 로 전수조사해
    /// BST 오름차순 순위 10번째·20번째를 그대로 등급 경계로 썼다(레이드 500+ 보다 낮은 대역에서
    /// 사파리존 자체의 상위권을 가른다). 전설(`is_legendary`/`is_mythical`)은 전수조사에서 0종.
    private static func gradePools(for zone: ZoneID) -> GradePools {
        switch zone {
        case .grassland:
            return GradePools(
                common: [10, 13, 161, 659, 263, 396, 16, 915, 504, 731],
                uncommon: [133, 918, 666, 162, 735, 505, 651, 723, 811, 907],
                rare: [660, 733, 128, 115, 862, 652, 908, 826, 763, 738])
        case .wetland:
            return GradePools(
                common: [746, 129, 270, 960, 60, 98, 170, 656, 728, 816],
                uncommon: [72, 120, 961, 171, 99, 845, 847, 657, 729, 817],
                rare: [537, 658, 730, 818, 914, 977, 882, 902, 883, 768])
        case .cave:
            return GradePools(
                common: [41, 524, 744, 74, 66, 843, 304, 769, 848, 837],
                uncommon: [408, 696, 95, 75, 185, 950, 770, 745, 409, 749],
                rare: [844, 839, 526, 949, 697, 699, 306, 750, 703, 970])
        }
    }

    /// 존에 등장하는 종 전체(등급 무관, 정렬 없음) — 큐레이션 검증(중복 없음 등)에 쓴다.
    static func speciesPool(for zone: ZoneID) -> [Int] {
        let pools = gradePools(for: zone)
        return pools.common + pools.uncommon + pools.rare
    }

    /// 이 종이 이 존에서 어느 등급인가 — `RaidBoss.rarity(speciesID:)` 와 같은 "풀에 속하면 그
    /// 등급" 규칙. 풀에 없는 종이 들어오면(큐레이션 실수) `.common` 으로 접는다.
    static func rarity(speciesID: Int, zone: ZoneID) -> Rarity {
        let pools = gradePools(for: zone)
        if pools.rare.contains(speciesID) { return .rare }
        if pools.uncommon.contains(speciesID) { return .uncommon }
        return .common
    }

    /// 등급 가중치(%, 합 100) — 알의 실측 비율(고급 ~7%, 희귀 ~7%)에 맞춰 잡았다. 알처럼
    /// 전체 ~1,000종에서 자연히 나온 값이 아니라 존 규모(10여 종)에 맞게 재현한 것이라, 정확한
    /// 알고리즘을 복제하진 않는다.
    private static let commonWeightPercent = 75
    private static let uncommonWeightPercent = 18
    private static let rareWeightPercent = 7   // commonWeightPercent + uncommonWeightPercent + rareWeightPercent == 100

    /// 등급을 먼저 가중 추첨한 뒤, 그 등급의 서브풀에서 균등하게 한 종을 고른다.
    /// `RaidBoss.catchAttempts` 처럼 결정론 RNG 를 그대로 쓴다 — 소켓 없이 테스트 가능.
    static func chooseEncounter(zone: ZoneID, rng: inout SplitMix64) -> Int {
        let pools = gradePools(for: zone)
        let gradeRoll = Int(rng.next() % 100)
        let subPool: [Int]
        if gradeRoll < commonWeightPercent {
            subPool = pools.common
        } else if gradeRoll < commonWeightPercent + uncommonWeightPercent {
            subPool = pools.uncommon
        } else {
            subPool = pools.rare
        }
        return subPool[Int(rng.next() % UInt64(subPool.count))]
    }
}

/// 조우 중 고를 수 있는 행동 — 그레이트 마쉬 원본 그대로 넷.
enum SafariAction: String, Codable, Sendable, CaseIterable {
    case bait, mud, ball, run
}

/// 조우(또는 그 행동 하나)의 결과. `.caught`/`.fled`/`.ranAway`/`.timedOut` 을 분리된 case 로
/// 두는 이유는 `defect-log.md` 가 경고하는 "쓰러짐과 이탈을 같은 값으로 뭉갠" 결함 부류를 피하기
/// 위해서다 — 잡음·도망침·시간초과는 화면이 각각 다른 문장으로 알려야 한다.
enum SafariOutcome: Sendable, Equatable, Codable {
    case caught, fled, ranAway, timedOut, continuing
}

/// 그레이트 마쉬 방식 조우 하나의 순수 상태.
struct SafariEncounter: Sendable, Codable, Equatable {
    let speciesID: Int
    let rarity: Rarity
    private(set) var catchStage = 0
    private(set) var fleeStage = 0
    private(set) var turn = 0
    /// 조우가 끝났을 때만 값이 있다. 진행 중에는 `nil` — 끝난 조우를 별도 Bool 로 표시하지 않고
    /// "결과가 있으면 끝난 것"으로 표현해 두 값이 어긋날 여지를 없앤다.
    private(set) var outcome: SafariOutcome?
    /// 가장 최근 미끼/진흙 사용에서 부작용(90%)이 실제로 일어났는지 — 로그 문구가 정확한 효과를
    /// 보여주기 위해서다. 볼/도망에는 의미가 없어 그 액션들에서는 매번 `nil` 로 되돌린다("이전
    /// 액션의 부작용 값이 이번 액션 로그에 잘못 새어 들어가는" 부류를 원천 차단).
    private(set) var lastSideEffect: Bool?

    init(speciesID: Int, rarity: Rarity) {
        self.speciesID = speciesID
        self.rarity = rarity
    }

    /// **네 액션의 유일한 진입점.** `bait`/`mud`/`ball`/`run` 을 각각 별도 public mutating func
    /// 으로 안 쪼갠다 — 쪼개면 나중에 새 게이트를 넣을 때 넷 중 하나를 빠뜨리기 쉽다
    /// (`defect-log.md` 가 경고하는 "새 게이트를 입력 경로 중 하나가 빠뜨리는" 결함 부류).
    ///
    /// 이미 끝난 조우(`outcome != nil`)에는 아무 상태도 안 바꾸고 이미 난 결과를 그대로 돌려준다
    /// — 결과 배너가 떠 있는 동안 버튼이 다시 눌려도 안전하다.
    @discardableResult
    mutating func act(_ action: SafariAction, rng: inout SplitMix64) -> SafariOutcome {
        if let outcome { return outcome }
        switch action {
        case .run:
            lastSideEffect = nil
            outcome = .ranAway
            return .ranAway
        case .ball:
            lastSideEffect = nil
            if rollsCatch(rng: &rng) {
                outcome = .caught
                return .caught
            }
        case .bait:
            lastSideEffect = applyBait(rng: &rng)
        case .mud:
            lastSideEffect = applyMud(rng: &rng)
        }
        // 볼 실패·미끼·진흙은 여기까지 온다 — 그 턴이 소비됐으므로 도망 판정을 돈다.
        // 도망을 직접 고르거나(.run) 볼로 잡으면(.caught) 위에서 이미 반환해 여기 안 온다.
        turn += 1
        if turn >= SafariZone.maxTurnsPerEncounter {
            outcome = .timedOut
            return .timedOut
        }
        if rollsFlee(rng: &rng) {
            outcome = .fled
            return .fled
        }
        return .continuing
    }

    /// 포획률 +1단계, 90% 확률로 도망률도 +1단계(부작용) — 그레이트 마쉬 원본 규칙.
    /// 부작용이 실제로 일어났는지를 돌려준다 — 로그가 정확한 효과를 보여주는 데 쓴다.
    @discardableResult
    private mutating func applyBait(rng: inout SplitMix64) -> Bool {
        catchStage = min(SafariZone.stageRange.upperBound, catchStage + 1)
        let triggered = Int(rng.next() % 100) < 90
        if triggered {
            fleeStage = min(SafariZone.stageRange.upperBound, fleeStage + 1)
        }
        return triggered
    }

    /// 도망률 -1단계, 90% 확률로 포획률도 -1단계(부작용) — 그레이트 마쉬 원본 규칙.
    @discardableResult
    private mutating func applyMud(rng: inout SplitMix64) -> Bool {
        fleeStage = max(SafariZone.stageRange.lowerBound, fleeStage - 1)
        let triggered = Int(rng.next() % 100) < 90
        if triggered {
            catchStage = max(SafariZone.stageRange.lowerBound, catchStage - 1)
        }
        return triggered
    }

    private func rollsCatch(rng: inout SplitMix64) -> Bool {
        Int(rng.next() % 100) < SafariZone.catchPercent(rarity: rarity, catchStage: catchStage)
    }

    private func rollsFlee(rng: inout SplitMix64) -> Bool {
        Int(rng.next() % 100) < SafariZone.fleePercent(fleeStage: fleeStage)
    }
}
