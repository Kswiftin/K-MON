import XCTest
@testable import PokeTokenBar

// MARK: 포코피아 10단계 — 네임드 NPC (파생 게이트 · 저장 필드 0개)
//
// 문구를 **리터럴로 기대하지 않는다**(`PokopiaTownLifeTests` 와 같은 규칙) — 게이트가 테스트를
// 영어 로케일로 재실행하고 문구는 다듬어질 값이다. 여기서 보는 것은 "어느 게이트가 열렸는가" 다.
//
// 게이트 여섯을 **각각 단독**으로 켠다. 지형 여덟 종 마을 하나로 전부 검증하면 루브도(5종)와
// 창백카츄(8종)가 같은 입력으로 통과해 5 와 8 이 뒤바뀌어도 초록이다.

final class PokopiaTownNPCTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func resident(_ speciesID: Int, _ types: [PokemonType]) -> TownResident {
        TownResident(speciesID: speciesID, name: "이웃", types: types, arrivedAt: now)
    }

    /// 부유섬 기본 마을은 **풀 176 + 길 16** 이라 이미 지형 두 종이다(둘 다 문턱 6을 넘는다).
    /// 거기에 여섯 지형을 문턱만큼씩 덮어 원하는 종수를 만든다. 덮어도 풀은 176 - 6k >= 140 이라
    /// 문턱 아래로 안 떨어진다.
    private func terrain(habitats: Int) -> [TownTerrain] {
        var terrain = PokopiaTown.defaultTerrain(for: .isle)
        let extras: [TownTerrain] = [.water, .soil, .sand, .rock, .flower, .tree]
        for (order, tile) in extras.prefix(max(0, habitats - 2)).enumerated() {
            for offset in 0..<PokopiaTown.habitatThreshold {
                terrain[order * PokopiaTown.habitatThreshold + offset] = tile
            }
        }
        return terrain
    }

    private func unlocked(_ terrain: [TownTerrain], residents: [TownResident] = [],
                          kitchen: Bool = false, furnace: Bool = false) -> Set<TownNPC> {
        PokopiaTownNPC.unlocked(terrain: terrain, residents: residents,
                                hasKitchen: kitchen, hasFurnace: furnace)
    }

    // MARK: 게이트 여섯 — 각각 단독으로

    /// 기본 마을(주민 0 · 설비 0)은 **아무도 없다.** 기본값이 해금이면 나머지 테스트가 전부 거짓 초록이다.
    func testNobodyIsUnlockedInAFreshTown() {
        XCTAssertTrue(unlocked(terrain(habitats: 2)).isEmpty)
    }

    /// 덩쿠림보 박사 — 주민 한 명이면 온다.
    func testTheProfessorArrivesWithTheFirstResident() {
        XCTAssertFalse(unlocked(terrain(habitats: 2)).contains(.professor))
        XCTAssertTrue(unlocked(terrain(habitats: 2), residents: [resident(1, [.grass])])
                        .contains(.professor))
    }

    /// 루브도 선생 — 지형 **5종**이다. 4종에서 열리면 문턱이 뜻을 잃는다.
    func testThePainterNeedsFiveHabitatsNotFour() {
        XCTAssertFalse(unlocked(terrain(habitats: 4)).contains(.painter))
        XCTAssertTrue(unlocked(terrain(habitats: 5)).contains(.painter))
    }

    /// DJ 로토무 — 복합 서식지가 한 곳이라도 성립해야 한다. 기본 마을(풀·길)은 조합표에 없는 짝이라
    /// 성립하지 않고, 물을 문턱만큼 깔면 풀과 맞닿아 "연못 풀숲" 이 선다.
    func testTheDJNeedsAFormedCompositeHabitat() {
        XCTAssertFalse(PokopiaTown.compositeHabitats(terrain(habitats: 2)).contains(where: \.isFormed),
                       "기본 마을에 이미 복합이 있으면 이 테스트는 아무것도 안 센다")
        XCTAssertFalse(unlocked(terrain(habitats: 2)).contains(.dj))
        XCTAssertTrue(unlocked(terrain(habitats: 3)).contains(.dj))
    }

    /// 요씽셰프 — 조리대다. **지형·주민과 무관하다**(설비는 전역이고 마을의 것이 아니다).
    func testTheChefComesWithTheKitchenAloneEvenInAnEmptyTown() {
        XCTAssertFalse(unlocked(terrain(habitats: 2)).contains(.chef))
        XCTAssertEqual(unlocked(terrain(habitats: 2), kitchen: true), [.chef])
    }

    /// 두드리짱 거장 — 용광로다. 조리대와 갈려 있다.
    func testTheArtisanComesWithTheFurnaceAlone() {
        XCTAssertFalse(unlocked(terrain(habitats: 2), kitchen: true).contains(.artisan))
        XCTAssertEqual(unlocked(terrain(habitats: 2), furnace: true), [.artisan])
    }

    /// 창백카츄 — 지형 **여덟 종 전부**다. 일곱에서 열리면 꿈섬 전설과 게이트가 갈린다.
    func testTheGlowNeedsAllEightHabitats() {
        XCTAssertFalse(unlocked(terrain(habitats: 7)).contains(.glow))
        XCTAssertTrue(unlocked(terrain(habitats: 8)).contains(.glow))
    }

    /// 해금은 **상태라서 되돌아간다.** 지형을 지우면 루브도가 다시 잠긴다 — 저장이 없으니 다른 답을
    /// 낼 수도 없다. 주민의 자동 퇴거 금지와 다른 규칙이라는 것을 여기서 못 박는다.
    func testAnUnlockClosesAgainWhenItsConditionBreaks() {
        XCTAssertTrue(unlocked(terrain(habitats: 5)).contains(.painter))
        XCTAssertFalse(unlocked(terrain(habitats: 4)).contains(.painter))
    }

    // MARK: 표 — 전수와 유일

    /// 여섯 전부 그릴 수 있어야 한다. 통과 못 하는 종은 절과 캔버스에서 **조용히 빈다**
    /// (5단계 `testDreamIslandGuestsSurviveNormalization` 과 같은 부류).
    func testEverySpeciesIDSurvivesTheSpriteCheck() {
        for npc in TownNPC.allCases {
            XCTAssertTrue(PokemonAssets.hasAnimatedSprite(speciesID: npc.speciesID),
                          "\(npc.name)(\(npc.speciesID)) 는 그릴 수 없다")
        }
    }

    /// 종·이름·특기가 각각 유일하다. 겹치면 둘 중 하나가 화면에서 영영 사라진다
    /// (`testEverySpecialtyComesFromExactlyOneType` 과 같은 이유).
    func testEveryNPCIsDistinctInSpeciesNameAndSpecialty() {
        let all = TownNPC.allCases
        XCTAssertEqual(Set(all.map(\.speciesID)).count, all.count)
        XCTAssertEqual(Set(all.map(\.name)).count, all.count)
        XCTAssertEqual(Set(all.map(\.specialtyName)).count, all.count)
    }

    /// 여섯의 특기는 4단계가 옮긴 18종과 **겹치지 않는다.** 겹치면 같은 이름이 타입 파생과 NPC
    /// 양쪽에 살아, 화면에서 "특기 발광" 이 주민에게도 붙는 것처럼 읽힌다.
    func testTheNPCSpecialtiesAreNoneOfTheEighteenTypeDerivedOnes() {
        let typeDerived = Set(TownSpecialty.allCases.map(\.name))
        for npc in TownNPC.allCases {
            XCTAssertFalse(typeDerived.contains(npc.specialtyName),
                           "\(npc.specialtyName) 가 타입 파생 특기와 겹친다")
        }
    }

    /// 문구 두 표가 **여섯 다 다르다.** 뷰만 읽는 값이라 테스트가 없으면 여섯이 같은 문장을 내도
    /// 아무것도 안 깨진다 — 미니룸 문구가 실제로 그 상태였고, 그래서 누구의 방이든 같은 문장이
    /// 나왔다(`PokopiaTownLife` 머리 주석).
    func testTheUnlockLinesAreDistinctAndNeverEmpty() {
        let hints = TownNPC.allCases.map(\.unlockHint)
        let lines = TownNPC.allCases.map(\.unlockedLine)
        XCTAssertEqual(Set(hints).count, TownNPC.allCases.count, "잠김 문구가 겹친다")
        XCTAssertEqual(Set(lines).count, TownNPC.allCases.count, "해금 문구가 겹친다")
        for text in hints + lines { XCTAssertFalse(text.isEmpty) }
    }

    /// 잠김 문구와 해금 문구가 **서로 다르다.** 같으면 잠긴 줄과 해금된 줄이 화면에서 구별되지 않는다.
    func testALockedLineNeverReadsLikeItsUnlockedOne() {
        for npc in TownNPC.allCases {
            XCTAssertNotEqual(npc.unlockHint, npc.unlockedLine, "\(npc.name) 의 두 문구가 같다")
        }
    }

    /// 루브도의 잠김 문구가 **문턱을 보간한다.** 리터럴로 적으면 `painterHabitats` 를 고쳐도 화면이
    /// 옛 숫자를 말한다(`specialtyLine` 이 `TownSpecialty.name` 을 보간하는 것과 같은 이유).
    func testThePainterHintQuotesTheThresholdItActuallyUses() {
        XCTAssertTrue(TownNPC.painter.unlockHint.contains("\(PokopiaTownNPC.painterHabitats)"))
        XCTAssertTrue(TownNPC.glow.unlockHint.contains("\(TownTerrain.allCases.count)"))
    }

    /// `id` 는 자기 자신이다 — `ForEach(TownNPC.allCases)` 가 이 값으로 줄을 센다.
    func testEachNPCIdentifiesItself() {
        XCTAssertEqual(Set(TownNPC.allCases.map(\.id)).count, TownNPC.allCases.count)
    }

    // MARK: 자리 (파생 · 결정적)

    /// 같은 날은 같은 자리, 다른 날은 (대체로) 다른 자리. 늘 주민이 설 수 있는 칸 안이다.
    func testTheSpotIsStableWithinADayAndAlwaysOnTheGrid() {
        for npc in TownNPC.allCases {
            let first = PokopiaTownNPC.spot(npc, dayKey: "2026-09-16")
            let again = PokopiaTownNPC.spot(npc, dayKey: "2026-09-16")
            XCTAssertEqual(first.col, again.col)
            XCTAssertEqual(first.row, again.row)
            let index = PokopiaTown.index(col: first.col, row: first.row)
            XCTAssertNotNil(index)
            XCTAssertTrue(PokopiaTown.residentSpotIndices.contains(index!),
                          "\(npc.name) 이 아바타 줄에 섰다")
        }
    }

    /// 날이 바뀌면 자리가 움직인다. 여섯이 **하나도** 안 움직이면 dayKey 가 시드에 안 들어간 것이다.
    func testTheSpotMovesAcrossDays() {
        let moved = TownNPC.allCases.filter {
            let a = PokopiaTownNPC.spot($0, dayKey: "2026-09-16")
            let b = PokopiaTownNPC.spot($0, dayKey: "2026-09-17")
            return a.col != b.col || a.row != b.row
        }
        XCTAssertFalse(moved.isEmpty, "dayKey 가 자리에 영향을 주지 않는다")
    }

    // MARK: 캔버스 id (주민과 NPC 가 같은 종일 수 있다)

    /// 로토무(479)·루브도(235)는 base 종이라 **주민으로도 산다.** id 가 speciesID 면 그 순간
    /// `ForEach` 가 겹쳐 화면이 깨진다 — 컴파일도 다른 테스트도 안 잡는 부류다.
    func testCanvasIDsDoNotCollideWhenAnNPCSpeciesAlsoLivesInTown() {
        let spot = (col: 0, row: 0)
        let living = [resident(479, [.electric, .ghost]), resident(235, [.normal])]
        let ids = living.map { PokopiaTownCanvas.Resident.resident($0, at: spot).id }
            + TownNPC.allCases.map { PokopiaTownCanvas.Resident.npc($0, at: spot).id }
        XCTAssertEqual(Set(ids).count, ids.count, "캔버스 id 가 겹친다: \(ids)")
    }

    // MARK: 배율 (양방향 — 꺼진 쪽을 함께 센다)

    /// 장인이 없으면 그대로, 있으면 짧다. **0 분이 되지 않는다** — 걸자마자 끝나면 기다림이 사라진다.
    func testTheArtisanShortensCraftTimeAndItsAbsenceDoesNot() {
        XCTAssertEqual(PokopiaTownNPC.craftMinutes(60, artisan: false), 60)
        XCTAssertLessThan(PokopiaTownNPC.craftMinutes(60, artisan: true), 60)
        XCTAssertGreaterThanOrEqual(PokopiaTownNPC.craftMinutes(1, artisan: true), 1)
    }

    /// 셰프가 없으면 그대로, 있으면 길다. **짧아지지 않는다** — 정수 나눗셈이 1시간짜리를 줄이면
    /// 요리가 셰프 때문에 나빠진다.
    func testTheChefLengthensSatietyAndNeverShortensIt() {
        XCTAssertEqual(PokopiaTownNPC.satietyHours(6, chef: false), 6)
        XCTAssertGreaterThan(PokopiaTownNPC.satietyHours(6, chef: true), 6)
        for hours in 1...12 {
            XCTAssertGreaterThanOrEqual(PokopiaTownNPC.satietyHours(hours, chef: true), hours)
        }
    }
}
