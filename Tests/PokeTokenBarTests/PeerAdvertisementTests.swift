import Network
import XCTest
@testable import PokeTokenBar

// 표시용 진행도의 와이어 계약(`PeerAdvertisement`)을 동결한다.
//  ① 키 이름 — `rankPoints` 는 #85 와 함께 배포됐다. 고치면 구버전 목록에서 랭크가 사라지는데
//     컴파일은 통과한다.
//  ② 클램프 — 들어오는 값은 상대가 채우는 신뢰경계다. 지점마다 흩어지면 한 곳은 반드시 빠진다.
final class PeerAdvertisementTests: XCTestCase {

    /// 피어 변환 테스트용 엔드포인트. 연결에 쓰지 않으므로 값 자체는 의미가 없다.
    private let anyEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: 4_242)

    // MARK: 와이어 계약 (구버전과의 호환)

    /// 키 이름을 리터럴로 동결한다. 상수만 서로 비교하면 이름을 바꿔도 테스트가 같이 따라가서
    /// 구버전과 단절된 사실을 아무도 못 본다.
    func testKeyNamesAreFrozenAsLiterals() {
        XCTAssertEqual(PeerAdvertisement.Key.rank, "rankPoints")
        XCTAssertEqual(PeerAdvertisement.Key.level, "trainerLevel")
        XCTAssertEqual(PeerAdvertisement.Key.tiers, "achievementTiers")
    }

    /// 구운 레코드에 그 키가 실제로 실려 있는지 — 상수만 맞고 굽는 쪽이 다른 키를 쓰면
    /// 위 테스트는 통과하고 상대 화면은 빈다.
    func testTheBakedRecordCarriesTheFrozenKeys() {
        let record = PeerAdvertisement(rankPoints: 1_234, trainerLevel: 12, achievementTiers: 8).txtRecord
        XCTAssertEqual(record["rankPoints"], "1234")
        XCTAssertEqual(record["trainerLevel"], "12")
        XCTAssertEqual(record["achievementTiers"], "8")
    }

    // MARK: 왕복

    func testRoundTripPreservesEveryField() {
        let mine = PeerAdvertisement(rankPoints: 2_150, trainerLevel: 37, achievementTiers: 11)
        XCTAssertEqual(PeerAdvertisement(mine.txtRecord), mine)
    }

    /// 비어 있는 칸은 키를 아예 싣지 않는다 — 읽는 쪽이 "없음"과 "0"을 구별해야 한다.
    /// (0 을 실으면 상대 카드에 Lv.0 이 그려진다.)
    func testNilFieldsAreOmittedFromTheRecord() {
        let record = PeerAdvertisement(rankPoints: 100).txtRecord
        XCTAssertEqual(record["rankPoints"], "100")
        XCTAssertNil(record["trainerLevel"])
        XCTAssertNil(record["achievementTiers"])
    }

    // MARK: 관대 파싱 — 피어를 버리지 않는다

    /// 구버전은 `rankPoints` 하나만 광고한다. 랭크는 살고 나머지는 비어야 한다 —
    /// 파싱이 실패하면 그 피어가 목록에서 사라져 신청조차 못 한다.
    func testAnOlderPeerAdvertisingOnlyRankStillParses() {
        let parsed = PeerAdvertisement(NWTXTRecord(["rankPoints": "1200"]))
        XCTAssertEqual(parsed.rankPoints, 1_200)
        XCTAssertNil(parsed.trainerLevel)
        XCTAssertNil(parsed.achievementTiers)
    }

    func testAnEmptyRecordParsesToAllNils() {
        XCTAssertEqual(PeerAdvertisement(NWTXTRecord()), PeerAdvertisement())
    }

    /// 숫자가 아닌 값은 nil 이다 — 0 으로 떨어지면 랭크 없는 상대가 "Iron 4 · 0 LP" 로 보인다.
    func testGarbageValuesBecomeNilRatherThanZero() {
        let parsed = PeerAdvertisement(NWTXTRecord(["rankPoints": "abc",
                                                    "trainerLevel": "",
                                                    "achievementTiers": " "]))
        XCTAssertNil(parsed.rankPoints)
        XCTAssertNil(parsed.trainerLevel)
        XCTAssertNil(parsed.achievementTiers)
    }

    // MARK: 클램프 — 신뢰경계 한 곳

    func testTrainerLevelIsClampedIntoTheDisplayableRange() {
        XCTAssertEqual(PeerAdvertisement(trainerLevel: 0).trainerLevel, 1)
        XCTAssertEqual(PeerAdvertisement(trainerLevel: -5).trainerLevel, 1)
        XCTAssertEqual(PeerAdvertisement(trainerLevel: 500).trainerLevel, TrainerLevel.maximumLevel)
        XCTAssertEqual(PeerAdvertisement(trainerLevel: 37).trainerLevel, 37)
    }

    func testAchievementTiersAreClampedToTheCatalogCeiling() {
        XCTAssertEqual(PeerAdvertisement(achievementTiers: -1).achievementTiers, 0)
        XCTAssertEqual(PeerAdvertisement(achievementTiers: 999).achievementTiers,
                       AchievementLadder.tierCeiling)
    }

    func testRankPointsAreClampedLikeBattleRank() {
        XCTAssertEqual(PeerAdvertisement(rankPoints: -10).rankPoints, 0)
        XCTAssertEqual(PeerAdvertisement(rankPoints: BattleRank.maximumPoints + 500).rankPoints,
                       BattleRank.maximumPoints)
    }

    /// **와이어로 들어오는 경로도 같은 클램프를 지나야 한다.** 이니셜라이저만 자르고 파싱이
    /// 그냥 대입하면, 조작된 광고가 Lv.99999 로 카드를 밀어내 목록 폭이 깨진다.
    /// (`BattleRank.clamped` 가 세이브 경로만 막고 와이어 경로엔 가드가 없던 것과 같은 부류다.)
    func testValuesArrivingOverTheWireAreClampedToo() {
        let hostile = PeerAdvertisement(NWTXTRecord(["rankPoints": "999999",
                                                     "trainerLevel": "99999",
                                                     "achievementTiers": "-42"]))
        XCTAssertEqual(hostile.rankPoints, BattleRank.maximumPoints)
        XCTAssertEqual(hostile.trainerLevel, TrainerLevel.maximumLevel)
        XCTAssertEqual(hostile.achievementTiers, 0)
    }

    // MARK: 수신 측 — 광고 하나를 카드 한 장으로 옮기는 지점
    //
    // 이 구간은 지금까지 무검증이었다(private 클로저 안). 아래 서비스 이름·TXT 는 **실제로 관찰한
    // 값**이다 — 릴리스판이 광고 중인 `유썽#44D580` / `rankPoints=0` 을 `dns-sd` 로 읽어 옮겼다.

    private func peer(_ name: String, _ record: NWTXTRecord? = nil,
                      mine: String = "me#000000") -> BattlePeer? {
        BattleCenter.peer(fromService: name, txtRecord: record,
                          excluding: mine, endpoint: anyEndpoint)
    }

    /// 내 광고는 목록에서 빠져야 한다 — 자기 자신에게 대전을 신청할 수는 없다.
    func testMyOwnServiceIsFilteredOut() {
        XCTAssertNil(peer("유썽#44D580", mine: "유썽#44D580"))
    }

    /// **같은 트레이너 이름의 다른 기기는 남이다.** 고유 접미가 그걸 가른다 — 이름으로 걸렀다면
    /// 같은 이름을 쓰는 두 Mac 이 서로를 "자기" 로 오인해 목록에서 사라진다.
    func testTheSameTrainerNameOnAnotherMachineIsStillAPeer() {
        let other = peer("유썽#FFFFFF", mine: "유썽#44D580")
        XCTAssertEqual(other?.name, "유썽")
        XCTAssertEqual(other?.serviceName, "유썽#FFFFFF")
    }

    /// 표시 이름은 **마지막** `#` 에서 자른다 — 첫 `#` 에서 자르면 이름에 `#` 을 쓴 사람이 잘린다.
    func testDisplayNameStripsOnlyTheUniqueSuffix() {
        XCTAssertEqual(peer("유썽#44D580")?.name, "유썽")
        XCTAssertEqual(peer("A#B#c1d2e3")?.name, "A#B")
        // 접미가 없는 광고(다른 구현·손으로 띄운 서비스)도 이름 그대로 살린다.
        XCTAssertEqual(peer("NoSuffix")?.name, "NoSuffix")
    }

    /// 실제로 관찰한 구버전 광고 — 랭크만 있다. 목록에 남아야 하고 랭크는 보여야 한다.
    func testTheReleasedBuildsRealRecordParsesAsRankOnly() {
        let live = peer("유썽#44D580", NWTXTRecord(["rankPoints": "0"]))
        XCTAssertEqual(live?.rank, BattleRank(points: 0))
        XCTAssertNil(live?.advertisement.trainerLevel)
        XCTAssertNil(live?.advertisement.achievementTiers)
    }

    /// TXT 가 아예 없는 결과(비-Bonjour 메타데이터)도 피어로 남는다 — 숨기면 신청할 방법이 없다.
    func testAPeerWithoutAnyRecordIsStillListed() {
        let found = peer("Ash#abc123")
        XCTAssertNotNil(found)
        XCTAssertNil(found?.rank)
        XCTAssertEqual(found?.advertisement, PeerAdvertisement())
    }

    func testANewBuildsRecordCarriesAllThreeValues() {
        let found = peer("Ash#abc123", NWTXTRecord(["rankPoints": "1200",
                                                    "trainerLevel": "12",
                                                    "achievementTiers": "8"]))
        XCTAssertEqual(found?.rank, BattleRank(points: 1_200))
        XCTAssertEqual(found?.advertisement.trainerLevel, 12)
        XCTAssertEqual(found?.advertisement.achievementTiers, 8)
    }

    /// 같은 상대가 레벨을 올리면 **다른 값**이어야 한다. 신원(`serviceName`)만 비교하면 동등성으로
    /// 갱신을 판단하는 쪽이 실시간 갱신을 삼킨다 — 이 기능의 존재 이유가 사라진다.
    func testAdvertisementChangeMakesThePeerUnequal() {
        let before = peer("Ash#abc123", NWTXTRecord(["trainerLevel": "12"]))
        let after = peer("Ash#abc123", NWTXTRecord(["trainerLevel": "13"]))
        XCTAssertEqual(before?.id, after?.id, "신원은 그대로여야 한다(행이 새로 그려지면 안 된다)")
        XCTAssertNotEqual(before, after)
    }

    // MARK: 랭크 어댑터

    /// 기존 `peer.rank` 호출부를 살려 두는 자리. 랭크가 없으면 nil 이어야 한다 — 빈 `BattleRank()`
    /// 는 "정보 없음" 대신 Iron 4 로 그려진다.
    func testRankAdapterMirrorsBattleRankAndStaysNilWhenAbsent() {
        XCTAssertEqual(PeerAdvertisement(rankPoints: 1_234).rank, BattleRank(points: 1_234))
        XCTAssertNil(PeerAdvertisement().rank)
    }
}
