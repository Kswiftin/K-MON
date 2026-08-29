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

    /// 가구도 기분도 없을 때만 계절이 나온다. 이 가지를 밟는 테스트가 없으면 계절 단독 경로가
    /// 무테스트로 남는다 — `A || B` 게이트의 B 단독을 검증하는 것과 같은 이유다.
    func testSeasonIsTheLastResortAndDiffersPerSeason() {
        let lines = MemoryHomeSeason.allCases.map {
            MemoryHomeRoomLife.line(speciesID: 1, decor: [], mood: nil, season: $0,
                                    companion: "이상해씨", l)
        }
        XCTAssertEqual(Set(lines).count, MemoryHomeSeason.allCases.count, "계절 4개가 서로 달라야 한다")
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
