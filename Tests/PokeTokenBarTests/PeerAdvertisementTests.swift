import Network
import XCTest
@testable import PokeTokenBar

// 근처 트레이너 카드가 보여줄 표시용 진행도 — Bonjour TXT 레코드로 오간다.
//
// 굽는 쪽과 읽는 쪽이 **같은 구조체**를 지나야 하는 이유가 두 가지다.
//  ① 키 이름이 와이어 계약이다 — `rankPoints` 는 #85 수정과 함께 이미 배포됐다. 이름을 고치면
//     구버전 클라이언트 목록에서 랭크가 사라지는데 컴파일은 통과한다.
//  ② 클램프가 한 곳이어야 한다 — 상한 클램프가 누적 지점마다 흩어지면 한 곳은 반드시 빠진다
//     (defect-log). 들어오는 값은 상대가 채우므로 신뢰경계다.
final class PeerAdvertisementTests: XCTestCase {

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
    // 이 구간은 지금까지 무검증이었다(private 클로저 안). 아래 입력들은 **실제로 관찰한 값**이다 —
    // 이 저장소의 릴리스판이 광고 중인 서비스 이름 `유썽#44D580` 과 TXT `rankPoints=0` 을
    // `dns-sd -B` / `dns-sd -L` 로 읽어 그대로 옮겼다.

    /// 내 광고는 목록에서 빠져야 한다 — 자기 자신에게 대전을 신청할 수는 없다.
    func testMyOwnServiceIsFilteredOut() {
        XCTAssertNil(BattleCenter.peer(fromService: "유썽#44D580", txtRecord: nil,
                                       excluding: "유썽#44D580"))
    }

    /// **같은 트레이너 이름의 다른 기기는 남이다.** 고유 접미가 그걸 가른다 — 이름으로 걸렀다면
    /// 같은 이름을 쓰는 두 Mac 이 서로를 "자기" 로 오인해 목록에서 사라진다.
    func testTheSameTrainerNameOnAnotherMachineIsStillAPeer() {
        let other = BattleCenter.peer(fromService: "유썽#FFFFFF", txtRecord: nil,
                                      excluding: "유썽#44D580")
        XCTAssertEqual(other?.name, "유썽")
        XCTAssertEqual(other?.serviceName, "유썽#FFFFFF")
    }

    /// 표시 이름은 **마지막** `#` 에서 자른다. 첫 `#` 에서 자르면 이름에 `#` 을 쓴 사람의 이름이
    /// 잘려 보인다.
    func testDisplayNameStripsOnlyTheUniqueSuffix() {
        XCTAssertEqual(BattleCenter.peer(fromService: "유썽#44D580", txtRecord: nil,
                                        excluding: "me#000000")?.name, "유썽")
        XCTAssertEqual(BattleCenter.peer(fromService: "A#B#c1d2e3", txtRecord: nil,
                                        excluding: "me#000000")?.name, "A#B")
        // 접미가 없는 광고(다른 구현·손으로 띄운 서비스)도 이름 그대로 살린다.
        XCTAssertEqual(BattleCenter.peer(fromService: "NoSuffix", txtRecord: nil,
                                        excluding: "me#000000")?.name, "NoSuffix")
    }

    /// 실제로 관찰한 구버전 광고 — 랭크만 있고 레벨·배지는 없다. 목록에 남아야 하고 랭크는 보여야 한다.
    func testTheReleasedBuildsRealRecordParsesAsRankOnly() {
        let live = BattleCenter.peer(fromService: "유썽#44D580",
                                     txtRecord: NWTXTRecord(["rankPoints": "0"]),
                                     excluding: "me#000000")
        XCTAssertEqual(live?.rank, BattleRank(points: 0))
        XCTAssertNil(live?.advertisement.trainerLevel)
        XCTAssertNil(live?.advertisement.achievementTiers)
    }

    /// TXT 가 아예 없는 결과(비-Bonjour 메타데이터)도 피어로 남는다 — 숨기면 신청할 방법이 없다.
    func testAPeerWithoutAnyRecordIsStillListed() {
        let peer = BattleCenter.peer(fromService: "Ash#abc123", txtRecord: nil,
                                     excluding: "me#000000")
        XCTAssertNotNil(peer)
        XCTAssertNil(peer?.rank)
        XCTAssertEqual(peer?.advertisement, PeerAdvertisement())
    }

    func testANewBuildsRecordCarriesAllThreeValues() {
        let peer = BattleCenter.peer(fromService: "Ash#abc123",
                                     txtRecord: NWTXTRecord(["rankPoints": "1200",
                                                             "trainerLevel": "12",
                                                             "achievementTiers": "8"]),
                                     excluding: "me#000000")
        XCTAssertEqual(peer?.rank, BattleRank(points: 1_200))
        XCTAssertEqual(peer?.advertisement.trainerLevel, 12)
        XCTAssertEqual(peer?.advertisement.achievementTiers, 8)
    }

    // MARK: 랭크 어댑터

    /// 기존 `peer.rank` 호출부가 그대로 살아 있게 하는 자리. 랭크가 없으면 nil 이어야 한다 —
    /// 빈 `BattleRank()` 를 돌려주면 카드가 "정보 없음" 대신 Iron 4 를 그린다.
    func testRankAdapterMirrorsBattleRankAndStaysNilWhenAbsent() {
        XCTAssertEqual(PeerAdvertisement(rankPoints: 1_234).rank, BattleRank(points: 1_234))
        XCTAssertNil(PeerAdvertisement().rank)
    }
}
