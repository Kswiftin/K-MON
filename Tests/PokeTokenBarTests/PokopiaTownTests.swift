import XCTest
@testable import PokeTokenBar

// MARK: 포코피아 마을 — 순수 로직(격자 · 표 · 서식 · 파생 · 신뢰경계)

final class PokopiaTownTests: XCTestCase {

    private func resident(_ speciesID: Int, _ types: [PokemonType],
                          at date: Date = Date(timeIntervalSince1970: 1_000)) -> TownResident {
        TownResident(speciesID: speciesID, name: "주민\(speciesID)", types: types, arrivedAt: date)
    }

    /// 지형 하나로 채운 마을. 문턱 판정 테스트가 쓴다.
    private func town(_ tile: TownTerrain, count: Int) -> [TownTerrain] {
        var terrain = Array(repeating: TownTerrain.path, count: PokopiaTown.tileCount)
        for index in 0..<min(count, PokopiaTown.tileCount) { terrain[index] = tile }
        return terrain
    }

    // MARK: 격자

    /// 범위 밖은 **클램프가 아니라 거절**이다. 클램프하면 화면 밖 탭이 가장자리 타일을 밀어,
    /// 사용자가 누르지 않은 칸이 바뀐다.
    func testIndexRejectsOutOfBoundsInsteadOfClamping() {
        XCTAssertNil(PokopiaTown.index(col: -1, row: 0))
        XCTAssertNil(PokopiaTown.index(col: 0, row: -1))
        XCTAssertNil(PokopiaTown.index(col: PokopiaTown.columns, row: 0))
        XCTAssertNil(PokopiaTown.index(col: 0, row: PokopiaTown.rows))
        XCTAssertEqual(PokopiaTown.index(col: 0, row: 0), 0)
        XCTAssertEqual(PokopiaTown.index(col: PokopiaTown.columns - 1, row: PokopiaTown.rows - 1),
                       PokopiaTown.tileCount - 1)
    }

    /// 행 우선 평탄 배열이라는 계약. 열 우선으로 뒤집히면 마을이 90도 돌아간 채 그려진다.
    func testIndexIsRowMajor() {
        XCTAssertEqual(PokopiaTown.index(col: 1, row: 0), 1)
        XCTAssertEqual(PokopiaTown.index(col: 0, row: 1), PokopiaTown.columns)
    }

    func testDefaultTerrainIsGrassWithPathOnlyOnTheLastRow() {
        XCTAssertEqual(PokopiaTown.defaultTerrain.count, PokopiaTown.tileCount)
        XCTAssertTrue(PokopiaTown.defaultTerrain.suffix(PokopiaTown.columns).allSatisfy { $0 == .path })
        XCTAssertTrue(PokopiaTown.defaultTerrain
            .prefix(PokopiaTown.tileCount - PokopiaTown.columns).allSatisfy { $0 == .grass })
    }

    /// 주민이 설 수 있는 칸은 **절대 비지 않는다** — `residentSpot` 의 `%` 가 0으로 나누지
    /// 않는 근거다. 그리고 맨 아래 길 줄을 빼야 아바타와 겹치지 않는다.
    func testResidentSpotIndicesExcludeTheAvatarRowAndAreNeverEmpty() {
        XCTAssertEqual(PokopiaTown.residentSpotIndices.count,
                       PokopiaTown.tileCount - PokopiaTown.columns)
        XCTAssertFalse(PokopiaTown.residentSpotIndices.isEmpty)
        let lastRowStart = PokopiaTown.tileCount - PokopiaTown.columns
        XCTAssertFalse(PokopiaTown.residentSpotIndices.contains { $0 >= lastRowStart })
    }

    // MARK: 타입 ↔ 지형 (표는 하나다)

    /// **양방향**을 본다. 정방향은 전수 `switch` 가 이미 지키지만, 아무 타입도 만들지 않는
    /// 지형은 어떤 변신으로도 만들 수 없는 채 남고 그 분기는 호출부가 없어 커버리지에 안 잡힌다.
    func testEveryTerrainIsReachableFromSomeType() {
        let reached = Set(PokemonType.allCases.map(PokopiaTown.terrain(for:)))
        XCTAssertEqual(reached, Set(TownTerrain.allCases),
                       "어떤 변신으로도 만들 수 없는 지형이 있다")
    }

    /// 뒤집은 표가 원래 표와 어긋나지 않는다. 손으로 적으면 "불꽃이 모래를 만드는데 모래는
    /// 불꽃을 안 부른다" 가 생긴다.
    func testTypesByTerrainIsExactlyTheInverseOfTerrainFor() {
        for type in PokemonType.allCases {
            let tile = PokopiaTown.terrain(for: type)
            XCTAssertTrue(PokopiaTown.typesMaking(tile).contains(type),
                          "\(type) 이 \(tile) 의 부르는 타입 집합에 없다")
        }
        // 반대로, 뒤집은 표에 든 타입은 모두 그 지형을 만든다.
        for tile in TownTerrain.allCases {
            let types = PokopiaTown.typesMaking(tile)
            for type in types {
                XCTAssertEqual(PokopiaTown.terrain(for: type), tile)
            }
        }
        XCTAssertEqual(TownTerrain.allCases.reduce(0) { $0 + PokopiaTown.typesMaking($1).count },
                       PokemonType.allCases.count, "타입이 두 지형에 걸쳐 있다")
    }

    // MARK: 서식

    /// 문턱 경계. 5칸은 안 부르고 6칸은 부른다 — 실수로 두 칸 민 것이 이사를 부르면
    /// "내가 만들어서 왔다" 가 우연이 된다.
    func testWelcomingTypesNeedsTheThreshold() {
        let below = PokopiaTown.welcomingTypes(town(.water, count: PokopiaTown.habitatThreshold - 1))
        XCTAssertFalse(below.contains(.water), "문턱 미달인데 물 타입을 불렀다")

        let atThreshold = PokopiaTown.welcomingTypes(town(.water, count: PokopiaTown.habitatThreshold))
        XCTAssertTrue(atThreshold.contains(.water))
        XCTAssertTrue(atThreshold.contains(.ice), "물이 부르는 타입 둘 중 하나가 빠졌다")
    }

    /// **기본 마을도 이미 풀·벌레를 부른다**(풀 176칸). 의도다 — 1일차 마을이 아무도 부르지
    /// 않으면 첫 세션의 이사 판정이 영영 빈손이고, 사용자는 이 기능이 도는지도 모른다.
    func testDefaultTownAlreadyWelcomesGrassTypes() {
        let welcoming = PokopiaTown.welcomingTypes(PokopiaTown.defaultTerrain)
        XCTAssertTrue(welcoming.contains(.grass))
        XCTAssertTrue(welcoming.contains(.bug))
        // 길도 16칸이라 문턱을 넘는다 — 노말·전기·고스트도 온다.
        XCTAssertTrue(welcoming.contains(.normal))
        XCTAssertFalse(welcoming.contains(.water), "물 지형이 없는데 물 타입을 불렀다")
    }

    /// **꽉 찬 격자는 언제나 누군가를 부른다** — 비둘기집 원리다: 192칸을 8지형에 나누면
    /// 최소 하나가 24칸이고, 그건 문턱(6)의 네 배다.
    ///
    /// 이것이 "이사가 서식 때문에 영영 안 되는 마을" 이 없다는 구조적 근거다. 문턱을 24보다
    /// 크게 올리면 그 보장이 깨지므로, 이 테스트가 문턱의 상한도 함께 지킨다.
    func testAFullGridAlwaysWelcomesSomebody() {
        XCTAssertLessThanOrEqual(PokopiaTown.habitatThreshold,
                                 PokopiaTown.tileCount / TownTerrain.allCases.count,
                                 "문턱이 비둘기집 하한보다 크면 아무도 안 오는 마을이 생긴다")
        // 여덟 지형을 돌려 깐 마을 — 24칸씩이라 전부 문턱을 넘는다.
        let terrain = (0..<PokopiaTown.tileCount).map {
            TownTerrain.allCases[$0 % TownTerrain.allCases.count]
        }
        XCTAssertEqual(PokopiaTown.welcomingTypes(terrain), Set(PokemonType.allCases),
                       "골고루 깐 마을은 모든 타입을 부른다")
    }

    func testTileCountsSumsToTheGrid() {
        let counts = PokopiaTown.tileCounts(PokopiaTown.defaultTerrain)
        XCTAssertEqual(counts.values.reduce(0, +), PokopiaTown.tileCount)
        XCTAssertEqual(counts[.grass], PokopiaTown.tileCount - PokopiaTown.columns)
        XCTAssertEqual(counts[.path], PokopiaTown.columns)
    }

    // MARK: 이사 판정 (순수 함수)

    func testImmigrantPicksOnlyWelcomeTypesAndSkipsResidents() {
        let terrain = town(.water, count: 20)
        let typeIndex: [Int: [PokemonType]] = [1: [.grass], 7: [.water], 4: [.fire], 9: [.water]]
        let pool = [1, 4, 7, 9]

        // 물만 문턱을 넘었으므로(길 172칸도 넘지만 typeIndex 에 노말 종이 없다) 7·9 중 하나.
        let picked = PokopiaTown.immigrant(terrain: terrain, pool: pool, typeIndex: typeIndex,
                                           residents: [], roll: 0)
        XCTAssertTrue([7, 9].contains(picked), "물 타입이 아닌 종을 뽑았다: \(picked as Int?)")

        // 이미 사는 종은 후보에서 빠진다.
        let second = PokopiaTown.immigrant(terrain: terrain, pool: pool, typeIndex: typeIndex,
                                           residents: [resident(7, [.water]), resident(9, [.water])],
                                           roll: 0)
        XCTAssertNil(second, "이미 사는 종만 남았는데 또 뽑았다")
    }

    /// 후보를 **정렬하지 않으면** 같은 굴림이 다른 종을 낸다. 정렬이 결정성의 근거다.
    func testImmigrantIsStableForTheSameRoll() {
        let terrain = town(.water, count: 20)
        let typeIndex: [Int: [PokemonType]] = [7: [.water], 9: [.water], 60: [.water], 72: [.water]]
        let shuffledPools = [[7, 9, 60, 72], [72, 60, 9, 7], [9, 72, 7, 60]]
        let answers = Set(shuffledPools.map {
            PokopiaTown.immigrant(terrain: terrain, pool: $0, typeIndex: typeIndex,
                                  residents: [], roll: 5)
        })
        XCTAssertEqual(answers.count, 1, "풀 순서가 답을 바꿨다 — 정렬이 빠졌다")
    }

    /// 후보가 없으면 nil 이다 — 빈 풀, 타입 인덱스가 비었을 때, 부르는 타입에 맞는 종이
    /// 하나도 없을 때. 세 경로 전부 조용히 넘어가야 한다(굴림 소비는 호출부의 책임이다).
    func testImmigrantIsNilWhenThereIsNoCandidate() {
        let terrain = town(.water, count: 20)
        XCTAssertNil(PokopiaTown.immigrant(terrain: terrain, pool: [], typeIndex: [:],
                                           residents: [], roll: 0), "빈 풀")
        XCTAssertNil(PokopiaTown.immigrant(terrain: terrain, pool: [1, 4], typeIndex: [:],
                                           residents: [], roll: 0), "타입을 모르는 풀")
        XCTAssertNil(PokopiaTown.immigrant(terrain: terrain, pool: [4],
                                           typeIndex: [4: [.fire]],
                                           residents: [], roll: 0),
                     "물·길만 부르는 마을에 불꽃 타입만 있는 풀")
    }

    /// **아무 지형도 문턱을 못 넘는 마을**에서는 아무도 안 온다. 꽉 찬 격자로는 만들 수
    /// 없지만(비둘기집), 잘린 배열·전송된 세이브처럼 짧은 지형이 들어오는 경로가 있으므로
    /// 이 분기는 살아 있어야 한다 — 안 밟으면 커버리지에 `^0` 으로 남는다.
    func testImmigrantIsNilWhenNoTerrainReachesTheThreshold() {
        let tiny: [TownTerrain] = [.water]          // 1칸 — 문턱(6) 미달
        XCTAssertTrue(PokopiaTown.welcomingTypes(tiny).isEmpty, "전제가 깨졌다")
        XCTAssertNil(PokopiaTown.immigrant(terrain: tiny, pool: [7],
                                           typeIndex: [7: [.water]],
                                           residents: [], roll: 0),
                     "아무 지형도 문턱을 못 넘는데 이사를 받았다")
    }

    /// `TownResident.id` 는 종 번호다 — 화면의 `ForEach` 가 이 값으로 행을 가른다.
    /// 같은 종이 두 행이 되면 SwiftUI 가 경고를 내고 목록이 흔들린다.
    func testResidentIdentityIsTheSpeciesID() {
        let one = resident(7, [.water])
        XCTAssertEqual(one.id, 7)
        XCTAssertEqual(Set([resident(7, [.water]), resident(7, [.fire])].map(\.id)).count, 1,
                       "종이 같으면 같은 행이어야 한다")
    }

    /// 굴림이 후보 수를 넘어도 안전하다 — `%` 가 감싸므로 트랩이 없다.
    func testImmigrantWrapsAnOversizedRoll() {
        let terrain = town(.water, count: 20)
        let typeIndex: [Int: [PokemonType]] = [7: [.water], 9: [.water]]
        XCTAssertNotNil(PokopiaTown.immigrant(terrain: terrain, pool: [7, 9],
                                              typeIndex: typeIndex, residents: [],
                                              roll: UInt64.max))
    }

    func testImmigrantStopsAtThePopulationLimit() {
        let terrain = town(.water, count: 20)
        let full = (1...PokopiaTown.populationLimit).map { resident($0, [.water]) }
        XCTAssertNil(PokopiaTown.immigrant(terrain: terrain, pool: [900],
                                           typeIndex: [900: [.water]],
                                           residents: full, roll: 0),
                     "인구가 꽉 찼는데 또 받았다")
    }

    // MARK: 주민 자리 (파생)

    /// **서식이 화면에 보이는 근거.** 물 타입이 모래에 서 있으면 "이 마을이 마음에 들어서
    /// 왔다" 가 화면에서 거짓이 된다.
    func testResidentSpotSitsOnItsPreferredTerrain() throws {
        var terrain = PokopiaTown.defaultTerrain
        // 첫 줄을 물로 바꾼다(길 줄이 아니라 주민이 설 수 있는 자리다).
        for col in 0..<PokopiaTown.columns {
            terrain[try XCTUnwrap(PokopiaTown.index(col: col, row: 0))] = .water
        }
        let spot = PokopiaTown.residentSpot(resident(7, [.water]), terrain: terrain,
                                            dayKey: "2026-09-08")
        let index = try XCTUnwrap(PokopiaTown.index(col: spot.col, row: spot.row))
        XCTAssertEqual(terrain[index], .water, "물 타입이 물이 아닌 칸에 섰다")
    }

    /// 선호 지형이 마을에 없으면 격자 전체로 떨어진다 — **주민을 화면에서 지우지 않는다.**
    /// 자동 퇴거는 사용자가 이해할 수 없는 상실이다.
    func testResidentSpotFallsBackWhenItsTerrainIsGone() throws {
        let spot = PokopiaTown.residentSpot(resident(7, [.water]),
                                            terrain: PokopiaTown.defaultTerrain,
                                            dayKey: "2026-09-08")
        XCTAssertNotNil(PokopiaTown.index(col: spot.col, row: spot.row))
        XCTAssertLessThan(spot.row, PokopiaTown.rows - 1, "폴백이 아바타 줄로 갔다")
    }

    /// 타입이 없는 주민(정규화가 막지만 함수 자체는 안전해야 한다)도 격자 안에 선다.
    func testResidentSpotHandlesATypelessResident() {
        let spot = PokopiaTown.residentSpot(resident(7, []), terrain: PokopiaTown.defaultTerrain,
                                            dayKey: "2026-09-08")
        XCTAssertNotNil(PokopiaTown.index(col: spot.col, row: spot.row))
    }

    /// 결정론 — `hashValue` 를 쓰면 프로세스마다 시드가 달라 재시작할 때마다 주민이 순간이동한다.
    func testResidentSpotIsDeterministic() {
        let one = PokopiaTown.residentSpot(resident(7, [.water]),
                                           terrain: PokopiaTown.defaultTerrain, dayKey: "2026-09-08")
        let two = PokopiaTown.residentSpot(resident(7, [.water]),
                                           terrain: PokopiaTown.defaultTerrain, dayKey: "2026-09-08")
        XCTAssertTrue(one == two, "\(one) != \(two)")
    }

    func testResidentSpotMovesWithTheDay() {
        let today = PokopiaTown.residentSpot(resident(7, [.water]),
                                             terrain: PokopiaTown.defaultTerrain, dayKey: "2026-09-08")
        let tomorrow = PokopiaTown.residentSpot(resident(7, [.water]),
                                                terrain: PokopiaTown.defaultTerrain, dayKey: "2026-09-09")
        XCTAssertFalse(today == tomorrow, "파생이 dayKey 를 안 읽고 있다")
    }

    /// 어떤 종·어떤 날짜를 넣어도 격자 안이고 아바타 줄을 피한다.
    func testResidentSpotAlwaysInsideTheGrid() {
        for speciesID in 1...120 {
            let spot = PokopiaTown.residentSpot(resident(speciesID, [.fire]),
                                                terrain: PokopiaTown.defaultTerrain,
                                                dayKey: String(format: "2026-%02d-%02d",
                                                               speciesID % 12 + 1, speciesID % 28 + 1))
            XCTAssertNotNil(PokopiaTown.index(col: spot.col, row: spot.row), "#\(speciesID)")
            XCTAssertLessThan(spot.row, PokopiaTown.rows - 1, "#\(speciesID)")
        }
    }

    /// `isSettled` 는 문턱을 본다 — 한 칸 남은 물가는 "살던 자리" 가 아니다.
    func testIsSettledFollowsTheHabitatThreshold() {
        XCTAssertTrue(PokopiaTown.isSettled(resident(7, [.water]),
                                            terrain: town(.water, count: PokopiaTown.habitatThreshold)))
        XCTAssertFalse(PokopiaTown.isSettled(resident(7, [.water]),
                                             terrain: town(.water, count: PokopiaTown.habitatThreshold - 1)))
        XCTAssertFalse(PokopiaTown.isSettled(resident(7, []), terrain: PokopiaTown.defaultTerrain),
                       "타입 없는 주민은 만족을 판정할 수 없다")
    }

    /// 2타입 종은 **두 번째 타입만으로도** 정착한다. 첫 타입 지형은 0칸이어야 한다 — 6칸이 있으면
    /// 첫 타입이 정착시킨 것과 구별되지 않아, 이 분기는 통과만 하고 아무것도 지키지 않는다.
    func testATwoTypeResidentSettlesOnItsSecondTypeAlone() throws {
        let gull = resident(278, [.water, .flying])                     // 물·비행 — 물→물, 비행→나무
        let woods = town(.tree, count: PokopiaTown.habitatThreshold)     // 물 0칸, 나무 6칸
        XCTAssertEqual(PokopiaTown.tileCounts(woods)[.water, default: 0], 0,
                       "첫 타입 지형이 있으면 이 테스트는 아무것도 못 가른다")
        XCTAssertTrue(PokopiaTown.isSettled(gull, terrain: woods))
        XCTAssertEqual(PokopiaTown.settledTerrain(gull, terrain: woods), .tree)
        let spot = PokopiaTown.residentSpot(gull, terrain: woods, dayKey: "2026-09-09")
        let index = try XCTUnwrap(PokopiaTown.index(col: spot.col, row: spot.row))
        XCTAssertEqual(woods[index], .tree, "정착시킨 지형 위에 서지 않았다")
    }

    /// 둘 다 넘었으면 `types` 순서의 첫 것이다 — `Set` 으로 바꾸면 재시작마다 답이 갈린다.
    func testSettledTerrainPrefersTheFirstTypeWhenBothQualify() {
        var terrain = town(.water, count: PokopiaTown.habitatThreshold)
        for index in PokopiaTown.habitatThreshold..<(PokopiaTown.habitatThreshold * 2) {
            terrain[index] = .tree
        }
        XCTAssertEqual(PokopiaTown.settledTerrain(resident(278, [.water, .flying]), terrain: terrain), .water)
        XCTAssertEqual(PokopiaTown.settledTerrain(resident(278, [.flying, .water]), terrain: terrain), .tree)
    }

    /// 같은 지형을 만드는 두 타입(땅·바위 → 흙)은 지형 하나다. 호출부 둘(`residentSpot` 의 `contains`,
    /// `settledTerrain` 의 `first`)은 중복을 보지 않지만, 반환값은 "자기 지형 목록" 이라 흙이 두 번
    /// 들어가면 목록 자체가 거짓이다.
    func testHomeTerrainsDedupesTypesThatShareATerrain() {
        XCTAssertEqual(PokopiaTown.homeTerrains(resident(74, [.rock, .ground])), [.soil])
        XCTAssertEqual(PokopiaTown.homeTerrains(resident(278, [.water, .flying])), [.water, .tree])
        XCTAssertEqual(PokopiaTown.homeTerrains(resident(1, [])), [])
    }

    // MARK: 신뢰경계

    /// 세이브·전송에서 온 못 믿을 값 전부를 한 번에 본다. **인자가 없다** — 주민이 소유 개체가
    /// 아니게 되면서 외부 지식이 필요 없어졌고, 통과 인자 문제도 사라졌다.
    func testNormalizedRejectsEveryUntrustedField() {
        var state = PokopiaTownState()
        state.terrain = [.water]                                  // 길이 1
        state.dittoForm = -25                                     // 음수 종
        let spriteless = PokemonAssets.spriteGaps.min() ?? 990
        state.residents = [
            resident(7, [.water]),
            resident(7, [.water]),                                // 중복 종
            TownResident(speciesID: 0, name: "영", types: [.water], arrivedAt: Date()),
            TownResident(speciesID: 9, name: "  ", types: [.water], arrivedAt: Date()),
            TownResident(speciesID: 4, name: "파이리", types: [], arrivedAt: Date()),
            resident(spriteless, [.dragon]),                      // 그릴 수 없는 종
        ]

        let out = PokopiaTown.normalized(state)

        XCTAssertEqual(out.terrain, PokopiaTown.defaultTerrain, "길이가 틀리면 기본으로 되돌린다")
        XCTAssertNil(out.dittoForm, "음수 종으로 변신한 채 남았다")
        XCTAssertEqual(out.residents.map(\.speciesID), [7], "못 믿을 주민이 살아남았다")
    }

    func testNormalizedTrimsToThePopulationLimitKeepingArrivalOrder() {
        var state = PokopiaTownState()
        let ids = Array(1...(PokopiaTown.populationLimit + 5))
        state.residents = ids.map { resident($0, [.water]) }
        let out = PokopiaTown.normalized(state)
        XCTAssertEqual(out.residents.map(\.speciesID),
                       Array(ids.prefix(PokopiaTown.populationLimit)),
                       "상한에 걸릴 때 도착 순서를 안 지켰다")
    }

    /// 이미 정상인 마을은 정규화가 바꾸지 않는다. 멱등이 아니면 파일을 열 때마다 값이 흔들린다.
    func testNormalizedIsIdempotentOnAValidTown() {
        var state = PokopiaTownState()
        state.dittoForm = 25
        state.residents = [resident(7, [.water])]
        let once = PokopiaTown.normalized(state)
        XCTAssertEqual(once, state)
        XCTAssertEqual(PokopiaTown.normalized(once), once)
    }

    /// 상한과 문턱이 서로 어긋나지 않는다는 전제.
    func testLimitsAreCoherent() {
        XCTAssertGreaterThan(PokopiaTown.populationLimit, PokemonMemoryAlbum.roommateLimit,
                            "마을이 방보다 좁으면 기능이 뜻을 잃는다")
        XCTAssertGreaterThan(PokopiaTown.tileCount, 8 * 6, "마을은 실내 격자보다 넓다")
        XCTAssertGreaterThan(PokopiaTown.habitatThreshold, 1)
        XCTAssertLessThan(PokopiaTown.habitatThreshold, PokopiaTown.columns,
                          "문턱이 한 줄보다 크면 사용자가 한 줄을 다 밀어도 아무 일이 없다")
    }

    // MARK: 서식 현황 (화면의 목표)

    /// 8지형 전부가 한 줄씩 나온다. 빠진 지형은 사용자가 목표로 삼을 수 없는 채 남는다.
    func testHabitatsCoverEveryTerrain() {
        let habitats = PokopiaTown.habitats(PokopiaTown.defaultTerrain)
        XCTAssertEqual(habitats.count, TownTerrain.allCases.count)
        XCTAssertEqual(Set(habitats.map(\.terrain)), Set(TownTerrain.allCases))
        for habitat in habitats {
            XCTAssertFalse(habitat.types.isEmpty, "\(habitat.terrain) 를 부르는 타입이 없다")
            XCTAssertGreaterThanOrEqual(habitat.remaining, 0, "남은 칸이 음수다")
        }
    }

    /// **표가 갈리지 않는다.** 화면이 "부르는 중" 이라 적은 타입 집합은 이사 판정이 쓰는
    /// `welcomingTypes` 와 같아야 한다 — 다르면 화면이 오지 않을 손님을 약속한다.
    func testWelcomingRowsMatchTheImmigrationTable() {
        var terrain = PokopiaTown.defaultTerrain          // 풀 176 + 길 16
        for index in 0..<PokopiaTown.habitatThreshold { terrain[index] = .water }
        let fromBoard = Set(PokopiaTown.habitats(terrain).filter(\.isWelcoming).flatMap(\.types))
        XCTAssertEqual(fromBoard, PokopiaTown.welcomingTypes(terrain))
        XCTAssertTrue(fromBoard.contains(.water), "물 문턱을 채웠는데 물을 안 부른다")
    }

    /// 문턱을 넘은 지형이 위로 온다. 그 안에서는 칸이 많은 순, 동수면 `allCases` 순이다 —
    /// 딕셔너리 순회에 맡기면 같은 마을이 열 때마다 다른 순서로 보인다.
    func testHabitatsPutWelcomingFirstAndAreDeterministic() {
        var terrain = [TownTerrain](repeating: .grass, count: PokopiaTown.tileCount)
        for index in 0..<20 { terrain[index] = .rock }        // 바위 20
        for index in 20..<(20 + PokopiaTown.habitatThreshold) { terrain[index] = .water }
        let habitats = PokopiaTown.habitats(terrain)

        let welcomingPrefix = habitats.prefix { $0.isWelcoming }
        XCTAssertEqual(welcomingPrefix.count, habitats.filter(\.isWelcoming).count,
                       "문턱을 넘은 줄이 못 넘은 줄 아래로 섞였다")
        // 풀 166 > 바위 20 > 물 6 순.
        XCTAssertEqual(welcomingPrefix.map(\.terrain), [.grass, .rock, .water])
        // 0칸 지형 넷은 동수라 `allCases` 순서로 갈린다.
        XCTAssertEqual(habitats.map(\.terrain), PokopiaTown.habitats(terrain).map(\.terrain))
        XCTAssertEqual(habitats.filter { $0.tiles == 0 }.map(\.terrain),
                       TownTerrain.allCases.filter { [.soil, .sand, .path, .flower, .tree].contains($0) })
    }

    /// 문턱을 못 넘은 줄은 남은 칸을 정확히 말한다. 화면이 그 숫자를 그대로 쓴다.
    func testRemainingCountsDownToTheThreshold() {
        var terrain = [TownTerrain](repeating: .grass, count: PokopiaTown.tileCount)
        terrain[0] = .water
        terrain[1] = .water
        let water = try! XCTUnwrap(PokopiaTown.habitats(terrain).first { $0.terrain == .water })
        XCTAssertEqual(water.tiles, 2)
        XCTAssertEqual(water.remaining, PokopiaTown.habitatThreshold - 2)
        XCTAssertFalse(water.isWelcoming)
    }

    /// 화면에 쓰는 지형 이름 8개가 비지 않고 서로 다르다. 겹치면 현황표에 같은 이름의 줄이
    /// 둘 보이고, 사용자는 어느 줄이 무엇인지 가릴 수 없다.
    func testTerrainNamesAreDistinct() {
        let names = TownTerrain.allCases.map(\.name)
        XCTAssertFalse(names.contains { $0.isEmpty })
        XCTAssertEqual(Set(names).count, TownTerrain.allCases.count)
    }

    /// 현황표의 `id` 가 줄마다 유일하다. `ForEach` 는 id 가 겹치면 **줄을 조용히 하나만 그린다** —
    /// 8지형을 다 넣었는데 화면에 일곱 줄만 보이는 부류다.
    func testHabitatRowIdentifiersAreUnique() {
        let habitats = PokopiaTown.habitats(PokopiaTown.defaultTerrain)
        XCTAssertEqual(Set(habitats.map(\.id)).count, habitats.count)
        XCTAssertEqual(habitats.map(\.id), habitats.map(\.terrain))
    }

    // MARK: 마을 개발도

    /// 문턱을 넘은 지형이 정확히 `count` 종인 마을.
    ///
    /// **0종 마을은 만들 수 없다.** 192칸을 8종에 나누면 비둘기집 원리로 적어도 한 종이 24칸을
    /// 갖고, 24 > 문턱 6 이다 — 그래서 `count` 는 1부터다. 화면의 "아직 아무 타입도 부르지
    /// 않아요" 분기가 실전에서 안 밟히는 근거가 이것이다.
    private func terrain(welcomingHabitats count: Int) -> [TownTerrain] {
        precondition((1...TownTerrain.allCases.count).contains(count))
        var out = [TownTerrain](repeating: TownTerrain.allCases[0], count: PokopiaTown.tileCount)
        var index = 0
        for tile in TownTerrain.allCases[1..<count] {
            for _ in 0..<PokopiaTown.habitatThreshold {
                out[index] = tile
                index += 1
            }
        }
        return out
    }

    /// **8종 × 자리 = 절대 상한** 이라는 등식. 어긋나면 모든 지형을 다 밀어도 상한에 못 닿거나
    /// (영영 안 끝나는 목표), 절반만 밀어도 상한에 닿는다(다양하게 만들 이유가 사라진다).
    func testFullDiversityExactlyReachesThePopulationLimit() {
        XCTAssertEqual(TownTerrain.allCases.count * PokopiaTown.residentsPerHabitat,
                       PokopiaTown.populationLimit)
    }

    /// 개발도 표를 1종부터 8종까지 전부 센다. 자리 수·이름이 종수에서만 나온다.
    func testDevelopmentGrowsWithTerrainDiversity() {
        var seenNames: [String] = []
        for count in 1...TownTerrain.allCases.count {
            let development = PokopiaTown.development(terrain(welcomingHabitats: count))
            XCTAssertEqual(development.habitats, count, "\(count)종 마을을 못 만들었다")
            XCTAssertEqual(development.capacity,
                           min(PokopiaTown.populationLimit,
                               count * PokopiaTown.residentsPerHabitat))
            XCTAssertFalse(development.name.isEmpty)
            seenNames.append(development.name)
        }
        // 이름이 단조로 늘어난다 — 한 이름만 나오면 단계가 화면에서 뜻을 잃는다.
        XCTAssertGreaterThan(Set(seenNames).count, 1)
        XCTAssertEqual(seenNames.first, "빈 터")
        XCTAssertEqual(seenNames.last, "포코피아")
    }

    /// 정원이 자리를 **연다**: 종이 하나 늘면 딱 그만큼 늘고, 상한을 넘지 않는다.
    func testCapacityIsMonotoneAndClamped() {
        var previous = 0
        for count in 1...TownTerrain.allCases.count {
            let capacity = PokopiaTown.development(terrain(welcomingHabitats: count)).capacity
            XCTAssertGreaterThan(capacity, previous, "\(count)종에서 자리가 안 늘었다")
            XCTAssertLessThanOrEqual(capacity, PokopiaTown.populationLimit)
            previous = capacity
        }
        XCTAssertEqual(previous, PokopiaTown.populationLimit)
    }

    /// 개발도는 **현황표와 같은 판정**을 쓴다. 갈리면 "부르는 중" 이라 적힌 줄 수와 개발도가
    /// 어긋나, 화면 안에서 두 숫자가 서로를 부정한다.
    func testDevelopmentAgreesWithTheHabitatBoard() {
        for count in 1...TownTerrain.allCases.count {
            let field = terrain(welcomingHabitats: count)
            XCTAssertEqual(PokopiaTown.development(field).habitats,
                           PokopiaTown.habitats(field).filter(\.isWelcoming).count)
        }
    }
}
