import XCTest
@testable import PokeTokenBar

/// 사파리존(4세대 그레이트 마쉬식)의 순수 코어 — 단계 배율·포획/도망률·조우 진행·등급 가중 추첨.
final class SafariZoneTests: XCTestCase {

    // MARK: 단계 배율

    /// 본가 명중률/회피율 공식(`(3+n)/3`, `3/(3-n)`) 을 그대로 옮겼는지 정수 일곱 자리로 확인.
    func testStageMultiplierMatchesAccuracyEvasionFormula() {
        XCTAssertEqual(SafariZone.stageMultiplier(-3), 0.5, accuracy: 0.0001)
        XCTAssertEqual(SafariZone.stageMultiplier(-2), 0.6, accuracy: 0.0001)
        XCTAssertEqual(SafariZone.stageMultiplier(-1), 0.75, accuracy: 0.0001)
        XCTAssertEqual(SafariZone.stageMultiplier(0), 1.0, accuracy: 0.0001)
        XCTAssertEqual(SafariZone.stageMultiplier(1), 4.0 / 3.0, accuracy: 0.0001)
        XCTAssertEqual(SafariZone.stageMultiplier(2), 5.0 / 3.0, accuracy: 0.0001)
        XCTAssertEqual(SafariZone.stageMultiplier(3), 2.0, accuracy: 0.0001)
    }

    /// 범위 밖 입력(±3 을 넘는 단계)도 경계로 클램프되는지 — 호출부가 실수로 범위를 넘겨도 안전.
    func testStageMultiplierClampsOutOfRangeStages() {
        XCTAssertEqual(SafariZone.stageMultiplier(-10), SafariZone.stageMultiplier(-3), accuracy: 0.0001)
        XCTAssertEqual(SafariZone.stageMultiplier(10), SafariZone.stageMultiplier(3), accuracy: 0.0001)
    }

    // MARK: 기저 포획률·도망률

    /// 0단계는 `RaidBoss.catchPercent(for:)` 기저값과 정확히 같아야 한다 — 재사용이지 근사가 아니다.
    func testCatchPercentMatchesRaidBossBaseAtZeroStage() {
        for rarity: Rarity in [.common, .uncommon, .rare, .legendary] {
            XCTAssertEqual(SafariZone.catchPercent(rarity: rarity, catchStage: 0),
                           RaidBoss.catchPercent(for: rarity),
                           "\(rarity) 0단계는 레이드 기저값과 같아야 한다")
        }
    }

    /// 5~95 클램프가 실제로 발동하는 경계 — legendary(5%) 는 -3단계(×0.5=2.5)에서도 5% 밑으로
    /// 못 내려간다. uncommon(25%) 은 +3단계(×2=50%) 로 클램프 없이 그대로 오른다.
    func testCatchPercentClampsAtLowerBound() {
        XCTAssertEqual(SafariZone.catchPercent(rarity: .legendary, catchStage: -3), 5)
        XCTAssertEqual(SafariZone.catchPercent(rarity: .uncommon, catchStage: 3), 50)
    }

    /// 모든 등급 × 모든 단계 조합이 5~95 범위 안에 있는지 전수 확인 — `catchPercent`/
    /// `fleePercent` 의 `min(95, max(5, ...))` 클램프를 지우면 이 테스트가 실패해야 한다.
    func testCatchPercentStaysWithinBoundsAcrossAllRaritiesAndStages() {
        for rarity: Rarity in [.common, .uncommon, .rare, .legendary] {
            for stage in SafariZone.stageRange {
                let value = SafariZone.catchPercent(rarity: rarity, catchStage: stage)
                XCTAssertTrue((5...95).contains(value), "\(rarity) stage \(stage): \(value) 가 5~95 밖")
            }
        }
    }

    func testFleePercentIsUniformAcrossRaritiesAndClamps() {
        XCTAssertEqual(SafariZone.fleePercent(fleeStage: 0), SafariZone.baseFleePercent)
        XCTAssertEqual(SafariZone.fleePercent(fleeStage: -3), 10)
        XCTAssertEqual(SafariZone.fleePercent(fleeStage: 3), 40)
        for stage in SafariZone.stageRange {
            let value = SafariZone.fleePercent(fleeStage: stage)
            XCTAssertTrue((5...95).contains(value), "stage \(stage): \(value) 가 5~95 밖")
        }
    }

    // MARK: 확률 분기 — 극단값이 아니라 중간값 seed 순회로 검증

    /// uncommon(25%) 기저 포획률로 볼을 던졌을 때, 대량 seed 에서 성공 비율이 기대값 근처로
    /// 수렴하는지 — 극단(0%/100%) 만 보면 "늘 성공/늘 실패"로 굳은 오구현을 놓친다.
    func testCatchProbabilityConvergesToExpectedRateAcrossSeeds() {
        let trials = 4000
        var successes = 0
        for seed: UInt64 in 0..<UInt64(trials) {
            var rng = SplitMix64(seed: seed)
            var encounter = SafariEncounter(speciesID: 1, rarity: .uncommon)
            if encounter.act(.ball, rng: &rng) == .caught { successes += 1 }
        }
        let ratio = Double(successes) / Double(trials)
        XCTAssertGreaterThan(ratio, 0.20, "포획 성공 비율이 기대값(25%)보다 너무 낮다")
        XCTAssertLessThan(ratio, 0.30, "포획 성공 비율이 기대값(25%)보다 너무 높다")
    }

    /// 미끼의 90% 부작용(도망률도 같이 오름)이 실제로 그 비율로 발생하는지.
    func testBaitSideEffectOccursAboutNinetyPercentOfTheTime() {
        let trials = 4000
        var withSideEffect = 0
        for seed: UInt64 in 0..<UInt64(trials) {
            var rng = SplitMix64(seed: seed)
            var encounter = SafariEncounter(speciesID: 1, rarity: .common)
            _ = encounter.act(.bait, rng: &rng)
            if encounter.fleeStage > 0 { withSideEffect += 1 }
        }
        let ratio = Double(withSideEffect) / Double(trials)
        XCTAssertGreaterThan(ratio, 0.85, "미끼 부작용 비율이 기대값(90%)보다 너무 낮다")
        XCTAssertLessThan(ratio, 0.95, "미끼 부작용 비율이 기대값(90%)보다 너무 높다")
    }

    /// 진흙의 90% 부작용(포획률도 같이 내림)이 실제로 그 비율로 발생하는지.
    func testMudSideEffectOccursAboutNinetyPercentOfTheTime() {
        let trials = 4000
        var withSideEffect = 0
        for seed: UInt64 in 0..<UInt64(trials) {
            var rng = SplitMix64(seed: seed)
            var encounter = SafariEncounter(speciesID: 1, rarity: .common)
            _ = encounter.act(.mud, rng: &rng)
            if encounter.catchStage < 0 { withSideEffect += 1 }
        }
        let ratio = Double(withSideEffect) / Double(trials)
        XCTAssertGreaterThan(ratio, 0.85, "진흙 부작용 비율이 기대값(90%)보다 너무 낮다")
        XCTAssertLessThan(ratio, 0.95, "진흙 부작용 비율이 기대값(90%)보다 너무 높다")
    }

    // MARK: 조우 진행 — 턴 상한·게이트

    /// 진흙만 반복해 fleeStage 를 -3(도망률 최저 10%)으로 눌러 두고도, 20턴 동안 한 번도
    /// 안 도망친 시드를 찾아 정확히 20번째에 `.timedOut` 이 나는지 확인한다(무한 루프 방어).
    func testEncounterEndsAtMaxTurnsWithoutFleeingOrCatching() {
        func runsToTimeout(seed: UInt64) -> Bool {
            var rng = SplitMix64(seed: seed)
            var encounter = SafariEncounter(speciesID: 1, rarity: .common)
            var lastOutcome: SafariOutcome = .continuing
            for _ in 0..<SafariZone.maxTurnsPerEncounter {
                lastOutcome = encounter.act(.mud, rng: &rng)
                if lastOutcome != .continuing { break }
            }
            return lastOutcome == .timedOut
        }
        guard let seed = (UInt64(0)..<2000).first(where: runsToTimeout) else {
            return XCTFail("20턴 동안 안 도망치는 시드를 못 찾았다")
        }
        var rng = SplitMix64(seed: seed)
        var encounter = SafariEncounter(speciesID: 1, rarity: .common)
        for turnIndex in 0..<SafariZone.maxTurnsPerEncounter {
            let outcome = encounter.act(.mud, rng: &rng)
            if turnIndex < SafariZone.maxTurnsPerEncounter - 1 {
                XCTAssertEqual(outcome, .continuing, "턴 \(turnIndex + 1) 에 이미 끝나면 안 된다")
            } else {
                XCTAssertEqual(outcome, .timedOut, "마지막 턴은 시간초과로 끝나야 한다")
            }
        }
    }

    /// 이미 끝난 조우(도망을 직접 골라 `.ranAway`)에 다른 액션을 다시 보내도 상태가 안 바뀌고
    /// 같은 결과만 돌아오는지 — 결과 배너가 떠 있는 동안 버튼이 다시 눌려도 안전해야 한다.
    /// `SafariEncounter.act` 맨 앞의 `if let outcome { return outcome }` 가드를 지우면 이
    /// 테스트가 실패해야 한다.
    func testActIsNoOpAfterEncounterHasEnded() {
        var rng = SplitMix64(seed: 1)
        var encounter = SafariEncounter(speciesID: 1, rarity: .common)
        XCTAssertEqual(encounter.act(.run, rng: &rng), .ranAway)
        let catchBefore = encounter.catchStage
        let fleeBefore = encounter.fleeStage
        let turnBefore = encounter.turn
        let again = encounter.act(.bait, rng: &rng)
        XCTAssertEqual(again, .ranAway, "이미 끝난 조우는 마지막 결과를 그대로 돌려줘야 한다")
        XCTAssertEqual(encounter.catchStage, catchBefore)
        XCTAssertEqual(encounter.fleeStage, fleeBefore)
        XCTAssertEqual(encounter.turn, turnBefore)
    }

    // MARK: 구역 큐레이션

    /// 사파리존 존 풀에는 전설이 없어야 한다 — 알(`FreshEgg`)의 "전설 전용 알은 안 판다" 원칙과
    /// 같은 자리. 전설은 계속 레이드·알의 몫으로 남긴다.
    func testNoZonePoolContainsALegendarySpecies() {
        for zone in SafariZone.ZoneID.allCases {
            for speciesID in SafariZone.speciesPool(for: zone) {
                XCTAssertNotEqual(SafariZone.rarity(speciesID: speciesID, zone: zone), .legendary,
                                  "\(zone) 풀에 전설(\(speciesID))이 섞여 있다")
            }
        }
    }

    /// 각 존은 등급별 정확히 10종씩, 총 30종이어야 한다 — `encounterPool`의 등급 가중치
    /// (`commonWeightPercent`/10 종 등)가 이 전제에 기댄다. 6개 존으로 늘어난 뒤(화산지대·
    /// 폭풍고원·폐허 추가, 2026-09-10) 손으로 큐레이션한 배열이 실수로 9종·11종이 되지 않았는지
    /// 코드로 고정한다.
    func testEveryZoneHasExactlyTenSpeciesPerGrade() {
        for zone in SafariZone.ZoneID.allCases {
            let entries = SafariZone.encounterPool(for: zone)
            for rarity: Rarity in [.common, .uncommon, .rare] {
                XCTAssertEqual(entries.filter { $0.rarity == rarity }.count, 10,
                               "\(zone)의 \(rarity) 등급이 10종이 아니다")
            }
        }
    }

    /// 존마다 다른 종을 판다 — 한 종이 두 존에 겹쳐 있으면 그 종의 실제 조우 확률이 두 배로
    /// 뛴다(설계 의도 밖의 유리함). 손으로 고른 90종(기존)+90종(신규 3존) 큐레이션이 실수로
    /// 겹치지 않았는지 확인한다.
    func testNoSpeciesAppearsInMoreThanOneZone() {
        var seenIn: [Int: SafariZone.ZoneID] = [:]
        for zone in SafariZone.ZoneID.allCases {
            for speciesID in SafariZone.speciesPool(for: zone) {
                if let existing = seenIn[speciesID] {
                    XCTFail("종 \(speciesID)가 \(existing)와 \(zone) 양쪽에 있다")
                } else {
                    seenIn[speciesID] = zone
                }
            }
        }
    }

    /// 사파리존은 레이드 풀과 완전히 분리된 채널이어야 한다 — 겹치면 걷기만 해도 레이드 전용
    /// 종을 얻을 수 있어 레이드의 존재 의미가 옅어진다(설계 문서 "레이드 풀과 겹치지 않게
    /// 골랐다"의 전제를 코드로 고정).
    ///
    /// **신규 3존만 검사한다.** 이 테스트를 만들며 기존 3존(초원·습지·동굴)에서 이미 8종
    /// (99·128·171·185·306·409·526·537)이 레이드 풀과 겹치고 있다는 걸 발견했다 — 설계
    /// 문서의 "겹치지 않게 골랐다"는 주장과 어긋나는 기존 결함이다(이번 3존 추가와는 무관하게
    /// 전부터 있었다). 신규 존은 처음부터 이 겹침을 0으로 만들어 검증했지만, 기존 3존까지
    /// 이 테스트에 포함하면 기존 결함 때문에 곧바로 레드가 된다 — 그 결함은 종을 8개 맞바꾸는
    /// 별도 작업이라 여기서 같이 고치지 않는다(사용자 확인 필요).
    func testNewZonesDoNotOverlapAnyRaidPool() {
        let raidPool = Set(RaidBoss.uncommonSpeciesPool + RaidBoss.rareSpeciesPool
            + RaidBoss.legendarySpeciesPool + RaidBoss.weeklySpeciesPool)
        for zone: SafariZone.ZoneID in [.volcano, .highland, .ruins] {
            for speciesID in SafariZone.speciesPool(for: zone) {
                XCTAssertFalse(raidPool.contains(speciesID),
                               "종 \(speciesID)(\(zone))가 레이드 풀과 겹친다")
            }
        }
    }

    /// 애니메이션 스프라이트가 없는 종을 큐레이션에 넣으면 조우·박스 화면에서 그 칸만 멈춘
    /// 그림으로 보인다(`PokemonAssets.spriteGaps` 주석 참고) — 손으로 고른 id가 그 14종에
    /// 실수로 걸리지 않았는지 확인한다.
    func testEveryZoneSpeciesHasAnAnimatedSprite() {
        for zone in SafariZone.ZoneID.allCases {
            for speciesID in SafariZone.speciesPool(for: zone) {
                XCTAssertTrue(PokemonAssets.hasAnimatedSprite(speciesID: speciesID),
                              "종 \(speciesID)(\(zone))는 애니메이션 스프라이트가 없다")
            }
        }
    }

    /// `PixelSprite.init(rows:key:)` 의 폭 판정은 **첫 줄 길이 기준 상대 비교**다
    /// (`rows.allSatisfy { $0.count == width }`, `width = rows.first?.count`) — 8줄 전부가
    /// 나란히 7자여도 서로 길이가 같으니 크래시 없이 폭 7짜리 스프라이트가 조용히 만들어진다.
    /// 손으로 고른 문자열 배열(`SafariFieldPixelArt`)이 실수로 이 함정에 걸리지 않았는지, 고정
    /// 상수(`tileSize`=8)와 직접 대조해 확인한다 — 신규 존을 늘릴 때마다 반복될 위험이라 한 번
    /// 여기 박아 둔다.
    func testEveryZonePixelArtIsExactlyTileSized() {
        for zone in SafariZone.ZoneID.allCases {
            for tile in SafariFieldPixelArt.tiles(for: zone) {
                XCTAssertEqual(tile.width, SafariFieldPixelArt.tileSize, "\(zone) 타일 폭")
                XCTAssertEqual(tile.height, SafariFieldPixelArt.tileSize, "\(zone) 타일 높이")
            }
            let obstacle = SafariFieldPixelArt.obstacle(for: zone)
            XCTAssertEqual(obstacle.width, SafariFieldPixelArt.tileSize, "\(zone) 장애물 폭")
            XCTAssertEqual(obstacle.height, SafariFieldPixelArt.tileSize, "\(zone) 장애물 높이")
        }
    }

    func testDisplayedEncounterPoolMatchesTheWeightedDrawExactly() {
        for zone in SafariZone.ZoneID.allCases {
            let entries = SafariZone.encounterPool(for: zone)
            XCTAssertEqual(entries.map(\.speciesID), SafariZone.speciesPool(for: zone))
            XCTAssertEqual(entries.reduce(0) { $0 + $1.chancePercent }, 100, accuracy: 0.0001)
            XCTAssertEqual(entries.filter { $0.rarity == .common }.map(\.chancePercent),
                           Array(repeating: 7.5, count: 10))
            XCTAssertEqual(entries.filter { $0.rarity == .uncommon }.map(\.chancePercent),
                           Array(repeating: 1.8, count: 10))
            XCTAssertEqual(entries.filter { $0.rarity == .rare }.map(\.chancePercent),
                           Array(repeating: 0.7, count: 10))
        }
    }

    /// 등급 가중 추첨이 실제로 일반 75%·고급 18%·희귀 7% 근처로 수렴하는지 — 균등 추첨으로
    /// 되돌리는 회귀가 있으면 이 테스트가 걸린다(균등이면 존마다 등급 수 비율로만 나온다).
    func testChooseEncounterGradeWeightsConverge() {
        let trials = 20_000
        var rng = SplitMix64(seed: 777)
        var commonCount = 0, uncommonCount = 0, rareCount = 0, legendaryCount = 0
        for _ in 0..<trials {
            let speciesID = SafariZone.chooseEncounter(zone: .grassland, rng: &rng)
            switch SafariZone.rarity(speciesID: speciesID, zone: .grassland) {
            case .common: commonCount += 1
            case .uncommon: uncommonCount += 1
            case .rare: rareCount += 1
            case .legendary: legendaryCount += 1
            }
        }
        XCTAssertEqual(legendaryCount, 0, "존 풀 추첨에서 전설이 나오면 안 된다")
        XCTAssertEqual(Double(commonCount) / Double(trials), 0.75, accuracy: 0.03)
        XCTAssertEqual(Double(uncommonCount) / Double(trials), 0.18, accuracy: 0.03)
        XCTAssertEqual(Double(rareCount) / Double(trials), 0.07, accuracy: 0.03)
    }

    /// 트레이너 스폰 칸((7,4) = `bounds.width/2, bounds.height/2`)은 어느 존에서도 장애물이면
    /// 안 된다 — 스폰하자마자 갇히는 결함을 원천 차단한다.
    func testObstaclesNeverBlockTheSpawnCell() {
        let bounds = SafariFieldBounds.standard
        let spawnCell = SafariCell(x: bounds.width / 2, y: bounds.height / 2)
        for zone in SafariZone.ZoneID.allCases {
            XCTAssertFalse(SafariZone.obstacles(for: zone).contains(spawnCell),
                           "\(zone): 스폰 칸이 장애물이면 안 된다")
        }
    }
}
