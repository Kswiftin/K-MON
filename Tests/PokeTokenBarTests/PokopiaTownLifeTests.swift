import XCTest
@testable import PokeTokenBar

// MARK: 포코피아 마을 — 화면 문구 (파생, 저장 필드 0개)
//
// 문구를 **리터럴로 기대하지 않는다.** 게이트가 테스트를 영어 로케일로 재실행하고, 문구는
// 다듬어질 값이라 문자열을 박으면 문장을 고칠 때마다 테스트가 깨진다. 대신 "어느 분기를
// 밟았는지" 를 부분 문자열(주민 이름 포함 여부 등)로 본다.

final class PokopiaTownLifeTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func resident(_ speciesID: Int, _ name: String, _ types: [PokemonType],
                          arrivedAgo: TimeInterval) -> TownResident {
        TownResident(speciesID: speciesID, name: name, types: types,
                     arrivedAt: now.addingTimeInterval(-arrivedAgo))
    }

    /// 지형 하나를 문턱 이상 깐 마을.
    private func town(_ tile: TownTerrain, count: Int = PokopiaTown.habitatThreshold) -> [TownTerrain] {
        var terrain = PokopiaTown.defaultTerrain
        for index in 0..<min(count, terrain.count) { terrain[index] = tile }
        return terrain
    }

    private func line(_ residents: [TownResident], _ terrain: [TownTerrain],
                      season: MemoryHomeSeason = .spring,
                      timeOfDay: MemoryHomeTimeOfDay = .day) -> String {
        PokopiaTownLife.line(residents: residents, terrain: terrain,
                            season: season, timeOfDay: timeOfDay, now: now)
    }

    // MARK: 우선순위 (좁은 조건이 먼저 이긴다)

    /// ① 갓 온 주민이 가장 좁다 — 세션 하나가 부른 사건이라 그것이 화면의 주인공이다.
    func testAFreshArrivalWinsOverEverythingElse() {
        let fresh = resident(7, "꼬부기", [.water], arrivedAgo: 60)
        let settled = resident(4, "파이리", [.fire], arrivedAgo: 60 * 60 * 24 * 30)
        let text = line([settled, fresh], town(.water))
        XCTAssertTrue(text.contains("꼬부기"), "갓 온 주민이 문장의 주인공이 아니다: \(text)")
        XCTAssertFalse(text.contains("파이리"))
    }

    /// 창을 여러 번 열어도 같은 문장이 나온다 — 도착 순서의 **가장 최근**을 고른다.
    func testTheMostRecentArrivalIsChosen() {
        let older = resident(7, "꼬부기", [.water], arrivedAgo: 60 * 60 * 5)
        let newer = resident(4, "파이리", [.fire], arrivedAgo: 60)
        let text = line([older, newer], town(.water))
        XCTAssertTrue(text.contains("파이리"), "더 오래된 도착을 골랐다: \(text)")
    }

    /// 창(`freshArrivalWindow`)을 넘긴 도착은 더 이상 새 소식이 아니다.
    func testAnArrivalOutsideTheWindowIsNoLongerFresh() {
        let stale = resident(7, "꼬부기", [.water],
                             arrivedAgo: PokopiaTownLife.freshArrivalWindow + 60)
        let text = line([stale], town(.water))
        // 만족한 주민 문장으로 떨어진다 — 이름은 여전히 들어가지만 "방금" 이 아니다.
        XCTAssertTrue(text.contains("꼬부기"))
        XCTAssertFalse(text.contains("방금"), "창을 넘긴 도착이 아직 새 소식이다: \(text)")
    }

    /// 미래에 도착한 주민(시계가 뒤로 간 세이브)은 갓 온 것으로 세지 않는다.
    func testAnArrivalInTheFutureIsNotFresh() {
        let future = TownResident(speciesID: 7, name: "꼬부기", types: [.water],
                                  arrivedAt: now.addingTimeInterval(60 * 60))
        let text = line([future], town(.water))
        XCTAssertFalse(text.contains("방금"), "미래 도착이 새 소식이 됐다: \(text)")
    }

    /// ② 자리를 잃은 주민이 만족한 주민보다 먼저다 — 사용자가 그 지형을 없앤 결과이므로.
    func testAnUnsettledResidentWinsOverASettledOne() {
        let unsettled = resident(7, "꼬부기", [.water], arrivedAgo: 60 * 60 * 24)
        let text = line([unsettled], PokopiaTown.defaultTerrain)   // 물이 없다
        XCTAssertTrue(text.contains("꼬부기"))
        XCTAssertTrue(text.contains("찾는"), "자리를 잃은 사실을 말하지 않는다: \(text)")
    }

    /// ③ 만족한 주민은 자기 지형 문장을 받는다.
    func testASettledResidentGetsItsTerrainSentence() {
        let settled = resident(7, "꼬부기", [.water], arrivedAgo: 60 * 60 * 24)
        let text = line([settled], town(.water))
        XCTAssertTrue(text.contains("꼬부기"))
        XCTAssertFalse(text.contains("찾는"), "만족한 주민이 자리를 잃은 것으로 나온다: \(text)")
    }

    /// 정착 문장은 **정착시킨 지형**의 것이다. 첫 타입 지형(물)이 0칸인 마을에서 "물가" 를 말하면
    /// 화면이 없는 물가를 가리킨다.
    func testASettledTwoTypeResidentSpeaksOfTheTerrainThatSettledIt() {
        let gull = resident(278, "갈모매", [.water, .flying], arrivedAgo: 60 * 60 * 24)
        let woods = town(.tree)
        XCTAssertEqual(PokopiaTown.tileCounts(woods)[.water, default: 0], 0,
                       "첫 타입 지형이 있으면 이 테스트는 아무것도 못 가른다")
        let text = line([gull], woods)
        XCTAssertTrue(text.contains("나무"), text)
        XCTAssertFalse(text.contains("물가"), text)
    }

    /// 여덟 지형 전부가 서로 다른 문장을 낸다 — 빠진 지형은 다른 지형의 문장을 물려받는다.
    func testEveryTerrainHasItsOwnSettledSentence() {
        var sentences: [String: TownTerrain] = [:]
        for tile in TownTerrain.allCases {
            // 그 지형을 만드는 타입으로 주민을 세운다(표에서 뽑는다 — 손으로 적으면 어긋난다).
            let type = PokopiaTown.typesMaking(tile).first
            guard let type else { continue }
            let text = line([resident(7, "주민", [type], arrivedAgo: 60 * 60 * 24)],
                            town(tile, count: PokopiaTown.habitatThreshold + 4))
            if let twin = sentences[text] {
                XCTFail("\(tile) 과 \(twin) 이 같은 문장을 쓴다: \(text)")
            }
            sentences[text] = tile
        }
        XCTAssertEqual(sentences.count, TownTerrain.allCases.count)
    }

    /// 밤은 낮과 다른 문장이다 — 시각을 인자로 받는 이유가 여기 있다.
    ///
    /// **여덟 지형 전부의 밤 문장을 밟는다.** 낮만 돌리면 밤 가지 일곱 개가 커버리지에
    /// `^0` 으로 남는다(실측으로 확인함) — 문장을 잘못 써도 아무도 모른다.
    func testNightDiffersFromDayForEveryTerrain() {
        for tile in TownTerrain.allCases {
            guard let type = PokopiaTown.typesMaking(tile).first else {
                XCTFail("\(tile) 을 만드는 타입이 없다"); continue
            }
            let settled = resident(7, "주민", [type], arrivedAgo: 60 * 60 * 24)
            let terrain = town(tile, count: PokopiaTown.habitatThreshold + 4)
            let day = line([settled], terrain, timeOfDay: .day)
            let night = line([settled], terrain, timeOfDay: .night)
            XCTAssertNotEqual(day, night, "\(tile): 낮과 밤이 같은 문장이다")
            XCTAssertFalse(night.trimmingCharacters(in: CharacterSet.whitespaces).isEmpty)
        }
    }

    /// ④ 주민은 없는데 부르는 환경은 됐다 — 다음에 무슨 일이 생길지 말한다.
    func testAWelcomingButEmptyTownSaysSomebodyMightCome() {
        let text = line([], town(.water))
        XCTAssertFalse(text.contains("넓혀"), "이미 부르는 마을에 지형을 넓히라고 한다: \(text)")
        XCTAssertTrue(text.contains("올까요") || text.contains("누가"),
                      "누가 올지 모른다는 기대를 말하지 않는다: \(text)")
    }

    /// ⑤ 텅 빈 마을. 계절로 갈리되 **무엇을 하면 되는지**를 담는다.
    ///
    /// 기본 마을은 풀 176칸이라 이미 부르므로, 이 분기를 밟으려면 어떤 지형도 문턱을 못 넘는
    /// 마을이 필요하다 — 여덟 지형을 다섯 칸씩만 깔고 나머지를 잘게 섞는다.
    func testAnEmptyTownTellsWhatToDo() {
        // 문턱 미달 마을을 만든다: 각 지형 5칸씩 = 40칸. 남은 152칸은 어쩔 수 없이 넘으므로,
        // 대신 주민도 없고 부르는 타입도 없는 상태를 직접 확인할 수 있는 최소 격자를 쓴다.
        let below = Array(repeating: TownTerrain.water, count: PokopiaTown.habitatThreshold - 1)
        XCTAssertTrue(PokopiaTown.welcomingTypes(below).isEmpty, "전제가 깨졌다")
        let seasons: [MemoryHomeSeason] = [.spring, .summer, .autumn, .winter]
        var sentences = Set<String>()
        for season in seasons {
            let text = line([], below, season: season)
            // **분기 식별로만 본다.** "무엇을 하면 되는지" 는 코드 주석이 적어 둔 설계 의도이고,
            // 동사 목록(`넓혀`/`심어`)으로 못 박으면 문장을 다듬을 때마다 깨진다 — 이 파일
            // 머리가 경고한 리터럴 의존이 바로 그것이다(실제로 "넓히면" 에서 한 번 깨졌다).
            XCTAssertTrue(text.contains("살지 않아요"),
                          "\(season): 텅 빈 마을 분기를 안 밟았다: \(text)")
            sentences.insert(text)
        }
        XCTAssertEqual(sentences.count, seasons.count,
                       "계절이 같은 문장을 쓴다 — 계절마다 다른 제안을 하는 것이 이 분기의 뜻이다")
    }

    // MARK: 결정성

    /// 같은 입력이 같은 문장을 낸다 — 마을을 열 때마다 문장이 바뀌면 마을이 불안해 보인다.
    func testTheSameInputAlwaysYieldsTheSameSentence() {
        let residents = [resident(7, "꼬부기", [.water], arrivedAgo: 60 * 60 * 24),
                         resident(4, "파이리", [.fire], arrivedAgo: 60 * 60 * 48)]
        let terrain = town(.water)
        let answers = Set((0..<20).map { _ in line(residents, terrain) })
        XCTAssertEqual(answers.count, 1, "같은 입력이 다른 문장을 냈다")
    }

    /// 문장이 비지 않는다 — 어느 분기든 화면에 쓸 값이 나온다.
    func testEveryBranchProducesANonEmptySentence() {
        let cases: [([TownResident], [TownTerrain])] = [
            ([], PokopiaTown.defaultTerrain),
            ([], Array(repeating: TownTerrain.water, count: 2)),
            ([resident(7, "꼬부기", [.water], arrivedAgo: 10)], town(.water)),
            ([resident(7, "꼬부기", [.water], arrivedAgo: 60 * 60 * 24)], PokopiaTown.defaultTerrain),
            ([resident(7, "꼬부기", [], arrivedAgo: 60 * 60 * 24)], PokopiaTown.defaultTerrain),
        ]
        for (residents, terrain) in cases {
            for timeOfDay in MemoryHomeTimeOfDay.allCases {
                let text = line(residents, terrain, timeOfDay: timeOfDay)
                XCTAssertFalse(text.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }
}
