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

    // MARK: 타입 ↔ 특기 (표는 하나다 · 문구 전용)

    /// **양방향**을 본다. 정방향은 전수 `switch` 가 지키지만, 어느 타입도 주지 않는 특기는 화면에 영영 안 나오고 그
    /// 문장 분기는 호출부가 없어 커버리지에 안 잡힌다. 지형 표(8 ← 18)와 달리 18 ← 18 이라 **정확히 하나**다 — 두 타입이
    /// 같은 특기를 주면 다른 특기 하나가 빈다.
    func testEverySpecialtyComesFromExactlyOneType() {
        let given = PokemonType.allCases.map(PokopiaTown.specialty(for:))
        XCTAssertEqual(Set(given), Set(TownSpecialty.allCases), "어떤 타입도 주지 않는 특기가 있다")
        XCTAssertEqual(Set(given).count, given.count, "두 타입이 같은 특기를 준다")
        XCTAssertEqual(TownSpecialty.allCases.count, PokemonType.allCases.count, "특기는 타입마다 하나다")
    }

    /// 이름 18개가 비지 않고 서로 다르다 — 겹치면 주민 줄에 다른 특기가 같은 글자로 보인다.
    func testSpecialtyNamesAreDistinct() {
        let names = TownSpecialty.allCases.map(\.name)
        XCTAssertFalse(names.contains { $0.isEmpty })
        XCTAssertEqual(Set(names).count, names.count)
    }

    /// 주민의 특기는 **첫 타입**의 것이다 — 두 번째 타입으로 정착한 주민도 특기는 바뀌지 않는다(특기는 마을 상태가 아니라
    /// 종의 정체다). 타입 순서를 뒤집으면 특기가 바뀐다는 것이 "첫 타입" 의 증거다. 타입 없는 주민은 nil.
    func testResidentSpecialtyFollowsTheFirstTypeOnly() {
        XCTAssertEqual(PokopiaTown.specialty(of: resident(278, [.water, .flying])), PokopiaTown.specialty(for: .water))
        XCTAssertEqual(PokopiaTown.specialty(of: resident(278, [.flying, .water])), PokopiaTown.specialty(for: .flying))
        XCTAssertNil(PokopiaTown.specialty(of: resident(1, [])))
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

    // MARK: 복합 서식지 (두 서식이 맞닿으면 2타입 종을 먼저 부른다)

    /// 표의 성질 넷 — 이름 유일(id 가 이름이다) · 같은 지형 둘이 아님 · 같은 쌍이 두 번 없음 · **여덟 지형이 전부 든다**.
    /// 빠진 지형은 어떤 조합에도 못 끼는 채 남고, 그 사실은 표를 눈으로 봐도 잘 안 보인다(`testEveryTerrainIsReachableFromSomeType`
    /// 이 타입→지형 표에 같은 일을 한다).
    func testCompositeRecipesAreWellFormed() {
        let recipes = PokopiaTown.compositeRecipes
        XCTAssertEqual(Set(recipes.map(\.name)).count, recipes.count, "조합 이름이 겹친다 — 현황표 두 줄이 하나로 접힌다")
        XCTAssertFalse(recipes.contains { $0.name.isEmpty })
        XCTAssertFalse(recipes.contains { $0.first == $0.second }, "같은 지형 둘은 조합이 아니다")
        let pairs = recipes.map { Set([$0.first, $0.second]) }
        XCTAssertEqual(Set(pairs).count, pairs.count, "같은 쌍이 두 번 들었다")
        XCTAssertEqual(Set(recipes.flatMap { [$0.first, $0.second] }), Set(TownTerrain.allCases),
                       "어떤 조합에도 끼지 못하는 지형이 있다")
    }

    /// **가장자리를 감싸지 않는다.** 평탄 배열에서 15번과 16번은 이웃 첨자지만 화면에서는 반대편 끝이다 — 첨자 산술로 이웃을
    /// 세면 오른쪽 끝의 물과 다음 줄 왼쪽 끝의 나무가 "맞닿은" 것으로 읽힌다. 이웃은 상하좌우 넷뿐이다(대각선 아님).
    /// 인자 순서는 답을 바꾸지 않는다 — `(b, a)` 분기는 이 호출이 없으면 `^0` 으로 남는다.
    func testTouchesNeedsAnOrthogonalNeighborAndNeverWrapsTheEdge() throws {
        let last = PokopiaTown.columns - 1
        var wrap = [TownTerrain](repeating: .grass, count: PokopiaTown.tileCount)
        wrap[try XCTUnwrap(PokopiaTown.index(col: last, row: 2))] = .water
        wrap[try XCTUnwrap(PokopiaTown.index(col: 0, row: 3))] = .tree            // 첨자로는 바로 다음 칸
        XCTAssertFalse(PokopiaTown.touches(.water, .tree, in: wrap), "가장자리가 감쌌다")

        var diagonal = wrap
        diagonal[try XCTUnwrap(PokopiaTown.index(col: 0, row: 3))] = .grass
        diagonal[try XCTUnwrap(PokopiaTown.index(col: last - 1, row: 3))] = .tree   // 대각선 아래
        XCTAssertFalse(PokopiaTown.touches(.water, .tree, in: diagonal), "대각선을 맞닿음으로 읽었다")

        var vertical = wrap
        vertical[try XCTUnwrap(PokopiaTown.index(col: 0, row: 3))] = .grass
        vertical[try XCTUnwrap(PokopiaTown.index(col: last, row: 3))] = .tree     // 가장자리 열에서 위아래
        XCTAssertTrue(PokopiaTown.touches(.water, .tree, in: vertical))
        XCTAssertTrue(PokopiaTown.touches(.tree, .water, in: vertical), "인자 순서가 답을 바꿨다")

        var horizontal = wrap
        horizontal[try XCTUnwrap(PokopiaTown.index(col: 0, row: 3))] = .grass
        horizontal[try XCTUnwrap(PokopiaTown.index(col: last - 1, row: 2))] = .tree   // 같은 줄 왼쪽
        XCTAssertTrue(PokopiaTown.touches(.water, .tree, in: horizontal))

        XCTAssertFalse(PokopiaTown.touches(.water, .tree, in: [.water, .tree]), "잘린 지형은 격자가 아니다 — 맞닿음도 없다")
    }

    /// 성립은 **두 조건**이다. 셋을 가른다: 맞닿았지만 한쪽 문턱 미달 · 둘 다 문턱이지만 떨어져 있음 · 둘 다 + 맞닿음.
    /// 앞 둘 없이 셋째만 세면 "문턱 하나만 보는" 구현도, "맞닿음만 보는" 구현도 통과한다.
    func testACompositeNeedsBothThresholdsAndContact() throws {
        let water = town(.water, count: PokopiaTown.habitatThreshold)              // 0행 0~5 물, 나머지 길
        func status(_ terrain: [TownTerrain]) throws -> PokopiaTown.CompositeStatus {
            try XCTUnwrap(PokopiaTown.compositeHabitats(terrain).first { $0.recipe.first == .water && $0.recipe.second == .tree })
        }
        var oneShort = water
        for col in 0..<(PokopiaTown.habitatThreshold - 1) {                         // 나무 5칸, 물과 맞닿음
            oneShort[try XCTUnwrap(PokopiaTown.index(col: col, row: 1))] = .tree
        }
        let short = try status(oneShort)
        XCTAssertTrue(short.touching)
        XCTAssertFalse(short.bothWelcoming)
        XCTAssertFalse(short.isFormed, "문턱 미달인데 성립했다")

        var apart = water
        for col in 0..<PokopiaTown.habitatThreshold {                               // 나무 6칸, 4행 — 떨어져 있음
            apart[try XCTUnwrap(PokopiaTown.index(col: col, row: 4))] = .tree
        }
        let far = try status(apart)
        XCTAssertTrue(far.bothWelcoming)
        XCTAssertFalse(far.touching)
        XCTAssertFalse(far.isFormed, "떨어져 있는데 성립했다")

        var formed = water
        for col in 0..<PokopiaTown.habitatThreshold {                               // 나무 6칸, 1행 — 맞닿음
            formed[try XCTUnwrap(PokopiaTown.index(col: col, row: 1))] = .tree
        }
        XCTAssertTrue(try status(formed).isFormed)
    }

    /// 조합 여덟이 한 줄씩, 성립한 것이 위로, 나머지는 표 순서. 기본 마을은 아무 조합도 성립시키지 않는다(길가 바위는 바위 0칸) —
    /// 1일차 이사가 전과 같다는 근거다.
    func testCompositeHabitatsListEveryRecipeFormedFirst() throws {
        let none = PokopiaTown.compositeHabitats(PokopiaTown.defaultTerrain)
        XCTAssertEqual(none.count, PokopiaTown.compositeRecipes.count)
        XCTAssertEqual(Set(none.map(\.id)).count, none.count, "현황 줄 id 가 겹친다")
        XCTAssertFalse(none.contains(where: \.isFormed), "기본 마을에서 조합이 성립했다 — 1일차 이사 순서가 바뀐다")
        XCTAssertEqual(none.map(\.recipe), PokopiaTown.compositeRecipes, "성립이 없으면 표 순서 그대로다")

        var terrain = town(.water, count: PokopiaTown.habitatThreshold)
        for col in 0..<PokopiaTown.habitatThreshold {
            terrain[try XCTUnwrap(PokopiaTown.index(col: col, row: 1))] = .tree
        }
        let some = PokopiaTown.compositeHabitats(terrain)
        let formedPrefix = some.prefix { $0.isFormed }
        XCTAssertEqual(formedPrefix.count, some.filter(\.isFormed).count, "성립한 줄이 안 한 줄 아래로 섞였다")
        XCTAssertTrue(formedPrefix.contains { $0.recipe.name == "물가 나무" })
    }

    /// **복합이 성립하면 두 지형을 다 만드는 종을 먼저 뽑는다.** 굴림 0..<30 을 전부 훑어 답이 하나인지 본다 — 한 굴림만
    /// 보면 후보 셋 중 우연히 그 종일 확률이 1/3 이다. 그 종이 이미 살면 **단일 후보로 떨어진다**(복합 성립 시에도 단일
    /// 후보가 남는다 — 로드맵의 필수 회귀). 같은 지형을 떨어뜨리면 우선이 사라진다 — 맞닿음이 판정을 가르는 것을 대조군으로
    /// 확인한다(`defect-log.md` "판정 하나가 두 축을 보게 되면" 부류의 처방).
    func testImmigrantDrawsCompositeMatchesFirstThenFallsBackToSingles() throws {
        let typeIndex: [Int: [PokemonType]] = [7: [.water], 149: [.dragon], 278: [.water, .flying]]   // 278 = 물·비행
        let pool = [7, 149, 278]
        func draws(_ terrain: [TownTerrain], residents: [TownResident]) -> Set<Int?> {
            Set((0..<30).map { PokopiaTown.immigrant(terrain: terrain, pool: pool, typeIndex: typeIndex,
                                                      residents: residents, roll: UInt64($0)) })
        }
        var touching = town(.water, count: PokopiaTown.habitatThreshold)
        for col in 0..<PokopiaTown.habitatThreshold {
            touching[try XCTUnwrap(PokopiaTown.index(col: col, row: 1))] = .tree
        }
        XCTAssertEqual(draws(touching, residents: []), [278], "맞닿았는데 물·비행 종이 먼저 오지 않았다")
        XCTAssertEqual(draws(touching, residents: [resident(278, [.water, .flying])]), [7, 149],
                       "복합 손님이 다 왔는데 단일 후보로 떨어지지 않았다")

        var apart = town(.water, count: PokopiaTown.habitatThreshold)
        for col in 0..<PokopiaTown.habitatThreshold {
            apart[try XCTUnwrap(PokopiaTown.index(col: col, row: 4))] = .tree
        }
        XCTAssertEqual(draws(apart, residents: []), [7, 149, 278], "떨어진 마을에서 우선이 남아 있다 — 맞닿음이 판정을 안 가른다")
    }

    /// 복합은 **후보를 더하지 않는다.** 두 지형을 다 만드는 종이라도 단일 경로를 통과하지 못하면(살고 있음) 오지 않고,
    /// 부르는 타입이 없는 종은 복합이 성립해도 오지 않는다 — 복합 후보는 단일 후보의 부분집합이다.
    func testCompositePreferenceNeverAddsACandidateOutsideTheSinglePath() throws {
        var touching = town(.water, count: PokopiaTown.habitatThreshold)
        for col in 0..<PokopiaTown.habitatThreshold {
            touching[try XCTUnwrap(PokopiaTown.index(col: col, row: 1))] = .tree
        }
        // 불꽃(모래 0칸)만 있는 풀 — 복합이 성립해도 아무도 안 온다.
        XCTAssertNil(PokopiaTown.immigrant(terrain: touching, pool: [4], typeIndex: [4: [.fire]],
                                           residents: [], roll: 0))
        // 복합 일치 종이 유일한 후보인데 이미 산다 — nil 이다(정원이 남아 있어도).
        XCTAssertNil(PokopiaTown.immigrant(terrain: touching, pool: [278], typeIndex: [278: [.water, .flying]],
                                           residents: [resident(278, [.water, .flying])], roll: 0))
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
            // 축 B 는 0 으로 고정한다 — 이 테스트는 축 A(종수→정원·이름)만 본다. 주민을 넣으면 정착이
            // 레벨을 올려 이름 단정이 다른 축 때문에 통과하거나 실패한다(`defect-log.md` "판정 하나가
            // 두 축을 보게 되면" 부류).
            let development = PokopiaTown.development(terrain(welcomingHabitats: count), residents: [])
            XCTAssertEqual(development.habitats, count, "\(count)종 마을을 못 만들었다")
            XCTAssertEqual(development.capacity,
                           min(PokopiaTown.populationLimit,
                               count * PokopiaTown.residentsPerHabitat))
            XCTAssertFalse(development.name.isEmpty)
            seenNames.append(development.name)
        }
        // 주민이 없을 때의 이름표는 축 A 만 봤던 시절과 글자 하나 같아야 한다 — 레벨을 넣으며 구간이
        // 밀리면 지형 3종 마을이 하루아침에 "마을" 로 승격된다.
        XCTAssertEqual(seenNames, ["빈 터", "작은 마을", "작은 마을", "마을", "마을", "큰 마을", "큰 마을", "포코피아"])
    }

    /// 정원이 자리를 **연다**: 종이 하나 늘면 딱 그만큼 늘고, 상한을 넘지 않는다.
    func testCapacityIsMonotoneAndClamped() {
        var previous = 0
        for count in 1...TownTerrain.allCases.count {
            let capacity = PokopiaTown.development(terrain(welcomingHabitats: count), residents: []).capacity
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
            XCTAssertEqual(PokopiaTown.development(field, residents: []).habitats,
                           PokopiaTown.habitats(field).filter(\.isWelcoming).count)
        }
    }

    // MARK: 환경 레벨 (두 축)

    /// 주민이 없으면 레벨은 곧 지형 종수다 — 축 B 가 0 이라는 것을 눈으로 확인하는 자리.
    /// 종수 0(잘린 배열)은 Lv.1 로 올려 세운다 — Lv.0 은 화면에 없는 값이다.
    func testWithoutResidentsTheLevelIsTheHabitatCount() {
        for count in 1...TownTerrain.allCases.count {
            XCTAssertEqual(PokopiaTown.development(terrain(welcomingHabitats: count), residents: []).level, count)
        }
        let truncated = PokopiaTown.development([.water], residents: [])
        XCTAssertEqual(truncated.habitats, 0, "전제: 1칸은 아무 지형도 못 넘긴다")
        XCTAssertEqual(truncated.level, 1)
        XCTAssertEqual(truncated.settled, 0)
    }

    /// 정착 비율 절반이 첫 계단이다. 축 A 는 4종에 **고정**한다 — 바꾸면 어느 축이 레벨을 움직였는지 못 가른다.
    /// 3명 중 1명(33%)은 안 오르고, 2명 중 1명(50%)은 오른다 — 경계는 `>=` 다.
    func testHalfOfTheResidentsSettledLiftsOneLevel() {
        let field = terrain(welcomingHabitats: 4)                  // 풀·흙·물·모래 넘김, 나무 0칸
        let home = resident(7, [.water])                           // 정착
        let lost = resident(149, [.dragon])                        // 드래곤→나무, 0칸 → 미정착
        XCTAssertTrue(PokopiaTown.isSettled(home, terrain: field))
        XCTAssertFalse(PokopiaTown.isSettled(lost, terrain: field), "전제: 나무가 있으면 이 테스트는 아무것도 못 가른다")

        let base = PokopiaTown.development(field, residents: []).level
        let third = PokopiaTown.development(field, residents: [home, lost, resident(148, [.dragon])])
        XCTAssertEqual(third.settled, 1)
        XCTAssertEqual(third.level, base, "1/3 정착인데 레벨이 올랐다")
        let half = PokopiaTown.development(field, residents: [home, lost])
        XCTAssertEqual(half.level, base + 1, "절반 정착이 한 계단을 안 올렸다")
        XCTAssertEqual(half.capacity, third.capacity, "축 B 가 정원을 건드렸다 — 금지한 되먹임이다")
    }

    /// 정원을 채우고 전원 정착하면 두 계단이다. 셋을 가른다: 전원 정착이지만 정원 미달(+1) ·
    /// 정원은 찼지만 한 명 미정착(+1) · 정원 가득 전원 정착(+2). 앞 둘 없이 셋째만 세면
    /// "전원 정착이면 +2" 인 구현과 구별되지 않는다.
    func testAFullAndFullySettledTownLiftsTwoLevels() {
        let field = terrain(welcomingHabitats: 3)                  // 풀·흙·물 → 정원 6
        let base = PokopiaTown.development(field, residents: []).level
        let settled = (1...6).map { resident($0, [.water]) }
        XCTAssertEqual(PokopiaTown.development(field, residents: Array(settled.prefix(5))).level, base + 1,
                       "정원 미달인데 두 계단 올랐다")
        XCTAssertEqual(PokopiaTown.development(field, residents: Array(settled.prefix(5)) + [resident(149, [.dragon])]).level,
                       base + 1, "한 명이 자리를 잃었는데 두 계단 올랐다")
        XCTAssertEqual(PokopiaTown.development(field, residents: settled).level, base + 2)
        // 종수 3 + 두 계단 = Lv.5 는 "마을" 이다. 이름이 종수(3 → "작은 마을")를 읽으면 여기서 갈린다.
        XCTAssertEqual(PokopiaTown.development(field, residents: settled).name, "마을",
                       "이름이 레벨이 아니라 종수를 읽는다")
    }

    /// **8종 + 16마리 전원 정착 = `maxLevel`** 이라는 등식. 어긋나면 Lv.10 이 영영 도달 불가거나
    /// (안 끝나는 목표), 지형만으로 닿아 주민을 지킬 이유가 사라진다. `maxLevel` 의 현재 값 동결은
    /// 이 자리 하나다(`defect-log.md` 의 리터럴 동결 부류) — 다른 테스트는 `PokopiaTown.maxLevel` 로 읽는다.
    func testFullDiversityAndFullSettlementReachTheMaxLevel() {
        XCTAssertEqual(PokopiaTown.maxLevel, 10)
        // 여덟 지형을 돌려 깐 마을(`testAFullGridAlwaysWelcomesSomebody` 와 같은 격자) — 어떤 타입도 정착한다.
        let field = (0..<PokopiaTown.tileCount).map { TownTerrain.allCases[$0 % TownTerrain.allCases.count] }
        let everyone = (1...PokopiaTown.populationLimit).map { resident($0, [.water]) }
        let top = PokopiaTown.development(field, residents: everyone)
        XCTAssertEqual(top.habitats, TownTerrain.allCases.count)
        XCTAssertEqual(top.settled, PokopiaTown.populationLimit)
        XCTAssertEqual(top.level, PokopiaTown.maxLevel)
        XCTAssertEqual(top.name, "포코피아")
        // 한 명 빠지면 정원 미달이라 Lv.9 — 최고 레벨은 정원까지 채워야 한다.
        XCTAssertEqual(PokopiaTown.development(field, residents: Array(everyone.dropLast())).level,
                       PokopiaTown.maxLevel - 1)
    }

    /// 지형을 지우면 레벨은 내려가고 주민은 남는다. 레벨이 `normalized` 나 정원 판정에 새면 여기서
    /// 주민 수가 줄거나 정원이 0 이 된다 — 그것은 이 기능이 금지한 자동 퇴거다.
    func testRemovingTerrainLowersTheLevelButKeepsEveryResident() {
        var state = PokopiaTownState()
        state.terrain = terrain(welcomingHabitats: 3)              // 풀·흙·물
        state.residents = [resident(7, [.water]), resident(9, [.water])]
        let before = PokopiaTown.development(state.terrain, residents: state.residents)
        XCTAssertEqual(before.settled, 2)

        // 물을 전부 풀로 되돌린다 — 두 주민이 자리를 잃는다.
        state.terrain = state.terrain.map { $0 == .water ? .grass : $0 }
        let after = PokopiaTown.development(state.terrain, residents: state.residents)
        XCTAssertEqual(after.settled, 0)
        XCTAssertLessThan(after.level, before.level, "자리를 잃었는데 레벨이 안 내려갔다")
        // 하강의 절반은 축 A(물 종이 빠져 종수 3→2)다. 축 B 도 0 으로 돌아갔는지는 주민 없는 같은 마을과
        // 맞대야 보인다 — 이 줄이 없으면 정착을 무시하는 lift 도 위의 `<` 를 통과한다(주입으로 확인, 2026-09-09).
        XCTAssertEqual(after.level, PokopiaTown.development(state.terrain, residents: []).level,
                       "정착 0 인데 축 B 가 레벨을 얹고 있다")
        XCTAssertEqual(PokopiaTown.normalized(state).residents, state.residents, "정규화가 자리 잃은 주민을 잘랐다")
    }
}
