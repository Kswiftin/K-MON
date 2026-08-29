import XCTest
@testable import PokeTokenBar

/// §5 "미니룸 안에 실제 포켓몬이 생활함". 이 테스트가 지키는 계약은 두 개다 —
/// (1) 좁은 조건이 먼저 이긴다 (2) 어떤 입력에서도 빈 문장이 나오지 않는다.
@MainActor
final class MemoryHomeRoomLifeTests: XCTestCase {
    private let l = L(.ko)

    // MARK: - 우선순위

    /// 종×가구가 있으면 가구 단독 문구를 **덮어야** 한다. 이 순서가 뒤집히면 기획서 §5 의
    /// "누구의 방인지" 가 사라지고 다시 "모두 같은 방" 이 된다.
    func testSpeciesPairBeatsFurnitureOnlyLine() {
        let paired = MemoryHomeRoomLife.line(speciesID: 143, decor: [.roomBed], mood: nil,
                                             season: .spring, companion: "잠만보", l)
        let unpaired = MemoryHomeRoomLife.line(speciesID: 1, decor: [.roomBed], mood: nil,
                                               season: .spring, companion: "이상해씨", l)
        XCTAssertNotEqual(paired, unpaired, "같은 침대인데 종이 달라도 같은 문장이면 종을 안 보는 것이다")
        XCTAssertTrue(paired.contains("침대"), "잠만보+침대 짝 문구여야 한다: \(paired)")
    }

    /// 가구가 있으면 기분보다 가구가 이긴다 — 방을 채운 물건이 먼저 보이는 게 자연스럽다.
    func testFurnitureBeatsMood() {
        let withFurniture = MemoryHomeRoomLife.line(speciesID: 1, decor: [.roomLamp], mood: .down,
                                                    season: .spring, companion: "이상해씨", l)
        let moodOnly = MemoryHomeRoomLife.line(speciesID: 1, decor: [], mood: .down,
                                               season: .spring, companion: "이상해씨", l)
        XCTAssertNotEqual(withFurniture, moodOnly)
        XCTAssertTrue(moodOnly.contains("이상해씨"), "기분 문구는 동행 이름을 부른다: \(moodOnly)")
    }

    /// 가구도 룸메이트도 기분도 없을 때만 계절이 나온다. 이 가지를 밟는 테스트가 없으면 계절
    /// 단독 경로가 무테스트로 남는다 — `A || B` 게이트의 B 단독을 검증하는 것과 같은 이유다.
    ///
    /// `timeOfDay: .day` 를 **명시한다.** 기본값에 기대면 계절 가지는 낮에 돌린 CI 에서만
    /// 밟히고, 밤에 돌리면 네 계절이 전부 같은 밤 문구가 되어 이 테스트가 시각에 따라 빨개진다.
    func testSeasonIsTheLastResortAndDiffersPerSeason() {
        let lines = MemoryHomeSeason.allCases.map {
            MemoryHomeRoomLife.line(speciesID: 1, decor: [], mood: nil, season: $0,
                                    timeOfDay: .day, companion: "이상해씨", l)
        }
        XCTAssertEqual(Set(lines).count, MemoryHomeSeason.allCases.count, "계절 4개가 서로 달라야 한다")
    }

    // MARK: - 하루 축 (아침·낮·밤)

    /// 빈 방의 세 시간대가 서로 달라야 한다. 아침·밤이 계절을 덮으므로, 셋이 같아지면 하루
    /// 축이 이름만 있고 실제로는 아무것도 안 하는 상태가 된다.
    func testIdleRoomDiffersByTimeOfDay() {
        let lines = MemoryHomeTimeOfDay.allCases.map {
            MemoryHomeRoomLife.line(speciesID: 1, decor: [], mood: nil, season: .spring,
                                    timeOfDay: $0, companion: "이상해씨", l)
        }
        XCTAssertEqual(Set(lines).count, MemoryHomeTimeOfDay.allCases.count,
                       "아침·낮·밤이 서로 달라야 한다")
        for line in lines {
            XCTAssertTrue(line.contains("이상해씨"), "빈 방 문구는 동행 이름을 부른다: \(line)")
        }
    }

    /// 아침·밤은 계절을 **덮는다**. 덮지 않으면 하루 축이 빈 방에서 절대 보이지 않는다.
    func testMorningAndNightOverrideTheSeasonLine() {
        func line(_ time: MemoryHomeTimeOfDay, _ season: MemoryHomeSeason) -> String {
            MemoryHomeRoomLife.line(speciesID: 1, decor: [], mood: nil, season: season,
                                    timeOfDay: time, companion: "이상해씨", l)
        }
        for time in [MemoryHomeTimeOfDay.morning, .night] {
            XCTAssertEqual(line(time, .spring), line(time, .winter),
                           "\(time) 은 계절과 무관하게 같은 문장이어야 한다")
            XCTAssertNotEqual(line(time, .spring), line(.day, .spring))
        }
        XCTAssertNotEqual(line(.day, .spring), line(.day, .winter), "낮에는 계절이 갈려야 한다")
    }

    /// 밤은 자정을 가로지른다. 21시와 3시가 같은 밤으로 묶이지 않으면 새벽의 방이 대낮 문구를
    /// 낸다 — `MemoryHomeSeason` 의 겨울(12·1·2)과 같은 부류의 경계다.
    func testNightWrapsAroundMidnight() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        func at(_ hour: Int) -> MemoryHomeTimeOfDay {
            let date = calendar.date(from: DateComponents(year: 2026, month: 8, day: 30, hour: hour))!
            return MemoryHomeTimeOfDay.current(date, calendar: calendar)
        }
        XCTAssertEqual(at(21), .night)
        XCTAssertEqual(at(3), .night)
        XCTAssertEqual(at(23), .night)
        XCTAssertEqual(at(5), .morning)
        XCTAssertEqual(at(10), .morning)
        XCTAssertEqual(at(11), .day)
        XCTAssertEqual(at(20), .day)
    }

    // MARK: - 룸메이트

    /// 같이 사는 동행이 있으면 가구 단독 문구를 **덮는다**. 이 순서가 뒤집히면 "둘이 사는 방" 이
    /// 화면에서 사라져, 룸메이트를 넣은 사용자만 아무 변화도 못 본다.
    func testRoommateBeatsFurnitureAndNamesBoth() {
        let shared = MemoryHomeRoomLife.line(speciesID: 1, decor: [.roomLamp], roommates: ["피카츄"],
                                             mood: nil, season: .spring, timeOfDay: .day,
                                             companion: "이상해씨", l)
        let alone = MemoryHomeRoomLife.line(speciesID: 1, decor: [.roomLamp], mood: nil,
                                            season: .spring, timeOfDay: .day, companion: "이상해씨", l)
        XCTAssertNotEqual(shared, alone, "룸메이트가 있어도 가구 문구가 그대로면 축이 죽은 것이다")
        XCTAssertTrue(shared.contains("피카츄") && shared.contains("이상해씨"),
                      "둘의 이름이 모두 나와야 한다: \(shared)")
    }

    /// 종×가구 짝은 룸메이트보다도 앞이다 — 기획서 §5 의 "누구의 방인지" 가 가장 좁은 조건이다.
    func testSpeciesPairStillBeatsRoommate() {
        let line = MemoryHomeRoomLife.line(speciesID: 143, decor: [.roomBed], roommates: ["피카츄"],
                                           mood: nil, season: .spring, timeOfDay: .day,
                                           companion: "잠만보", l)
        XCTAssertTrue(line.contains("침대"), "짝 문구가 룸메이트에 밀렸다: \(line)")
    }

    /// 세 마리 이상이면 나머지 수를 센다. 첫 이름만 부르면 나머지 동행이 방에서 사라진다.
    func testExtraRoommatesAreCounted() {
        let line = MemoryHomeRoomLife.line(speciesID: 1, decor: [], roommates: ["피카츄", "이브이"],
                                           mood: nil, season: .spring, timeOfDay: .day,
                                           companion: "이상해씨", l)
        XCTAssertTrue(line.contains("1"), "나머지 1마리가 문장에 없다: \(line)")
    }

    /// 룸메이트 문구도 세 시간대·세 언어가 모두 채워져 있어야 한다.
    func testRoommateLineIsFilledInEveryTimeAndLanguage() {
        for language in [AppLanguage.ko, .en, .ja] {
            let l = L(language)
            let lines = MemoryHomeTimeOfDay.allCases.map {
                MemoryHomeRoomLife.line(speciesID: 1, decor: [], roommates: ["피카츄"], mood: nil,
                                        season: .spring, timeOfDay: $0, companion: "이상해씨", l)
            }
            XCTAssertEqual(Set(lines).count, MemoryHomeTimeOfDay.allCases.count,
                           "\(language) 에서 시간대별 룸메이트 문구가 겹쳤다")
            for line in lines {
                XCTAssertFalse(line.trimmingCharacters(in: .whitespaces).isEmpty,
                               "\(language) 룸메이트 문구가 비었다")
            }
        }
    }

    // MARK: - 전수 검증

    /// 짝 표의 **모든** 항목이 실제로 짝 문구를 낸다. 표에 줄을 더하고 여기 배열에 안 더하면
    /// 새 짝이 무테스트로 남으므로, 표 자체를 테스트가 읽는다.
    func testEveryPairInTheTableProducesItsOwnLine() {
        XCTAssertFalse(MemoryHomeRoomLife.pairedSpecies.isEmpty)
        for key in MemoryHomeRoomLife.pairedSpecies {
            let paired = MemoryHomeRoomLife.line(speciesID: key.speciesID, decor: [key.item],
                                                 mood: nil, season: .spring, companion: "동행", l)
            let generic = MemoryHomeRoomLife.line(speciesID: 999_999, decor: [key.item],
                                                  mood: nil, season: .spring, companion: "동행", l)
            XCTAssertNotEqual(paired, generic,
                              "짝 (\(key.speciesID), \(key.item.rawValue)) 이 가구 단독 문구와 같다")
        }
    }

    /// 가구 12종이 **전부** 최소 한 짝을 갖는다. 한 종류라도 비면 그 가구를 산 사용자만 계속
    /// 일반 문구를 보는데, 화면에서는 "내 가구만 반응이 없다" 로 읽힌다. 표를 늘릴 때 이 게이트가
    /// 없으면 빈 가구가 조용히 남는다 — 숫자를 세지 않고 어느 가구가 비었는지 이름을 찍는다.
    func testEveryFurnitureItemHasAtLeastOneSpeciesPair() {
        let paired = Set(MemoryHomeRoomLife.pairedSpecies.map(\.item))
        let missing = ItemKind.memoryHomeFurniture.filter { !paired.contains($0) }
        XCTAssertTrue(missing.isEmpty,
                      "짝이 하나도 없는 가구: \(missing.map(\.rawValue).sorted().joined(separator: ", "))")
    }

    /// 세 언어 모두 채워져 있어야 한다. `l.t` 는 빈 문자열도 그대로 통과시키므로 컴파일러가
    /// 못 잡는 부류다.
    func testEveryPairIsTranslatedInThreeLanguages() {
        for language in [AppLanguage.ko, .en, .ja] {
            let l = L(language)
            for key in MemoryHomeRoomLife.pairedSpecies {
                let line = MemoryHomeRoomLife.line(speciesID: key.speciesID, decor: [key.item],
                                                   mood: nil, season: .spring, companion: "동행", l)
                XCTAssertFalse(line.trimmingCharacters(in: .whitespaces).isEmpty,
                               "\(language) 에서 (\(key.speciesID), \(key.item.rawValue)) 문구가 비었다")
            }
        }
    }

    /// 가구 12종 전부가 문구를 낸다 — `roomReaction` 이 `nil` 인 아이템이 방에 들어오면
    /// 빈 줄이 되는데, 그건 화면에 아무 설명 없는 회색 캡슐로 나간다.
    func testEveryFurnitureItemProducesANonEmptyLine() {
        for item in ItemKind.memoryHomeFurniture {
            let line = MemoryHomeRoomLife.line(speciesID: 999_999, decor: [item], mood: nil,
                                               season: .spring, companion: "동행", l)
            XCTAssertFalse(line.trimmingCharacters(in: .whitespaces).isEmpty,
                           "\(item.rawValue) 가구에서 빈 문장이 나왔다")
        }
    }

    /// 여러 가구가 놓였을 때 결과가 흔들리면 방을 열 때마다 문장이 바뀐다. 배열 순서가 같으면
    /// 결과도 같아야 한다.
    func testMultipleDecorPicksTheSpeciesPairDeterministically() {
        let decor: [ItemKind] = [.roomTable, .roomBed, .retroTV]
        let first = MemoryHomeRoomLife.line(speciesID: 143, decor: decor, mood: nil,
                                            season: .summer, companion: "잠만보", l)
        let again = MemoryHomeRoomLife.line(speciesID: 143, decor: decor, mood: nil,
                                            season: .summer, companion: "잠만보", l)
        XCTAssertEqual(first, again)
        XCTAssertTrue(first.contains("침대"),
                      "테이블이 배열 앞에 있어도 짝이 있는 침대가 이겨야 한다: \(first)")
    }

    /// 소비 아이템이 방 목록에 섞여 들어와도(가져온 세이브·미래의 버그) 빈 문장을 내지 않는다.
    func testNonFurnitureItemFallsThroughToMood() {
        let line = MemoryHomeRoomLife.line(speciesID: 1, decor: [.rareCandy], mood: .excited,
                                           season: .spring, companion: "이상해씨", l)
        XCTAssertTrue(line.contains("이상해씨"), "가구가 아니면 기분 문구로 내려가야 한다: \(line)")
    }
}
