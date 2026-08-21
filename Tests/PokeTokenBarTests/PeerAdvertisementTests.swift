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

    // MARK: 랭크 어댑터

    /// 기존 `peer.rank` 호출부가 그대로 살아 있게 하는 자리. 랭크가 없으면 nil 이어야 한다 —
    /// 빈 `BattleRank()` 를 돌려주면 카드가 "정보 없음" 대신 Iron 4 를 그린다.
    func testRankAdapterMirrorsBattleRankAndStaysNilWhenAbsent() {
        XCTAssertEqual(PeerAdvertisement(rankPoints: 1_234).rank, BattleRank(points: 1_234))
        XCTAssertNil(PeerAdvertisement().rank)
    }
}
