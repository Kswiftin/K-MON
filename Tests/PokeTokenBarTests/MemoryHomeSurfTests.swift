import XCTest
import Network
@testable import PokeTokenBar

/// 기획서 §14 파도타기 — 다음 홈 선택과 발자국 파생. 순수 함수라 여기서 전수 검증한다.
/// 화면에 두면 무테스트로 남고, 센터의 MainActor 상태에 두면 "목록이 이럴 때 어디로 가는가" 를
/// 물을 방법이 없다(`homes(fromServices:)` 를 순수 함수로 뺀 것과 같은 이유).
final class MemoryHomeSurfTests: XCTestCase {
    private func endpoint(_ port: UInt16) -> NWEndpoint { .hostPort(host: "127.0.0.1", port: .init(rawValue: port)!) }

    private func peers(_ ids: [String]) -> [MemoryHomePeer] {
        ids.enumerated().map { MemoryHomePeer(id: $1, displayName: $1, endpoint: endpoint(UInt16(5_000 + $0))) }
    }

    // MARK: - 다음 홈 선택

    func testEmptyListHasNoTarget() {
        XCTAssertNil(MemoryHomeSurf.target(in: [], visited: [], after: nil))
    }

    func testFirstSurfPicksTheFirstUnvisitedHome() {
        let target = MemoryHomeSurf.target(in: peers(["가#A", "나#B", "다#C"]), visited: [], after: nil)
        XCTAssertEqual(target?.id, "가#A")
    }

    func testSurfSkipsHomesAlreadyVisitedToday() {
        let target = MemoryHomeSurf.target(in: peers(["가#A", "나#B", "다#C"]), visited: ["가#A", "나#B"], after: nil)
        XCTAssertEqual(target?.id, "다#C", "오늘 이미 다녀온 집으로 다시 보내면 파도타기가 제자리에서 돈다")
    }

    /// `안 간 집이 있다 || 커서 다음으로 넘긴다` 게이트의 **B 단독** 분기다(A=false, B=true).
    /// 안 간 집이 있는 목록으로만 테스트하면 이 경로를 한 번도 밟지 않고 통과한다 — 그리고
    /// 여기서 `nil` 을 돌려주면 하루에 한 바퀴 돈 사용자에게 파도타기가 죽은 버튼이 된다.
    func testWhenEveryHomeIsVisitedSurfStillMovesToTheNextOne() {
        let all = peers(["가#A", "나#B", "다#C"])
        let visited: Set<String> = ["가#A", "나#B", "다#C"]
        XCTAssertEqual(MemoryHomeSurf.target(in: all, visited: visited, after: "가#A")?.id, "나#B")
        XCTAssertEqual(MemoryHomeSurf.target(in: all, visited: visited, after: "나#B")?.id, "다#C")
    }

    func testSurfWrapsAroundFromTheLastHome() {
        let all = peers(["가#A", "나#B", "다#C"])
        let visited: Set<String> = ["가#A", "나#B", "다#C"]
        XCTAssertEqual(MemoryHomeSurf.target(in: all, visited: visited, after: "다#C")?.id, "가#A")
    }

    /// 커서가 가리키던 집이 목록에서 사라지는 것은 흔한 일이다(mDNS 만료·상대 종료).
    /// 그때 `firstIndex` 가 `nil` 이라고 파도타기를 멈추면 버튼이 조용히 죽는다.
    func testUnknownCursorFallsBackToTheStartOfTheList() {
        let all = peers(["가#A", "나#B"])
        XCTAssertEqual(MemoryHomeSurf.target(in: all, visited: ["가#A", "나#B"], after: "사라진#Z")?.id, "가#A")
    }

    func testSingleHomeIsStillATargetEvenAfterVisiting() {
        let one = peers(["가#A"])
        XCTAssertEqual(MemoryHomeSurf.target(in: one, visited: ["가#A"], after: "가#A")?.id, "가#A")
    }

    // MARK: - 오늘 방문 판정

    /// 도장은 통산 기록이라 어제 것도 남아 있다. 날짜를 안 보면 어제 다녀온 집이 오늘 영구히
    /// 제외돼, 이웃이 한 채인 사용자는 다음 날부터 파도타기를 쓸 수 없다.
    func testVisitedTodayIgnoresYesterdaysStamps() {
        let now = Date()
        let yesterday = now.addingTimeInterval(-60 * 60 * 24)
        let visited = MemoryHomeSurf.visitedIDs(in: ["가#A": now, "나#B": yesterday],
                                                on: CompanionStore.dayKey(now))
        XCTAssertEqual(visited, ["가#A"])
    }

    // MARK: - 발자국

    func testFootprintsAreNewestFirstAndStripTheAdvertisedSuffix() {
        let now = Date()
        let prints = MemoryHomeSurf.footprints(from: ["피카홈#AAAAAA": now.addingTimeInterval(-10),
                                                      "라이홈#BBBBBB": now])
        XCTAssertEqual(prints.map(\.label), ["라이홈", "피카홈"])
        XCTAssertEqual(prints.map(\.id), ["라이홈#BBBBBB", "피카홈#AAAAAA"], "id 는 광고 원문이어야 기기별로 구분된다")
    }

    /// 도장의 키는 **남이 지은 문자열**이다. 라벨을 만들 수 없는 값은 화면에 올리지 않는다 —
    /// 목록 검증(`displayName(fromService:)`)과 같은 경계를 쓴다.
    func testFootprintsDropUnreadableAdvertisedNames() {
        let prints = MemoryHomeSurf.footprints(from: ["": Date(), "줄\n바꿈#AAAAAA": Date(), "정상#BBBBBB": Date()])
        XCTAssertEqual(prints.map(\.label), ["정상"])
    }

    /// 같은 시각 두 발자국. 정렬이 딕셔너리 순회를 따라가면 목록이 열 때마다 자리를 바꾼다.
    /// **순서를 못 박는다** — "흔들리지만 않으면 된다" 로 두면 비교 두 항이 짝이 어긋난
    /// (`($0.at, $1.id) > ($1.at, $0.id)`) 형태도 통과한다. 그 형태는 지금은 우연히 결정적이고,
    /// 정렬 키를 하나 더하는 순간 조용히 무너진다.
    func testFootprintsWithTheSameTimestampFallBackToADescendingID() {
        let now = Date()
        XCTAssertEqual(MemoryHomeSurf.footprints(from: ["가#AAAAAA": now, "다#CCCCCC": now, "나#BBBBBB": now]).map(\.id),
                       ["다#CCCCCC", "나#BBBBBB", "가#AAAAAA"])
    }

    /// 도장은 200개까지 쌓인다(`recordMemoryHomeVisitStamp`). 화면은 최근 것만 본다.
    func testFootprintsAreCappedAtTheRequestedLimit() {
        let now = Date()
        let stamps = Dictionary(uniqueKeysWithValues: (0..<30).map {
            ("홈\($0)#\(String(format: "%06d", $0))", now.addingTimeInterval(Double($0)))
        })
        let prints = MemoryHomeSurf.footprints(from: stamps, limit: 10)
        XCTAssertEqual(prints.count, 10)
        XCTAssertEqual(prints.first?.label, "홈29", "상한을 앞에서 자르면 가장 최근 발자국이 사라진다")
    }
}
