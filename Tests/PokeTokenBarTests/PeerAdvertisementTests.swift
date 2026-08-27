import Network
import XCTest
@testable import PokeTokenBar

// 표시용 진행도의 와이어 계약(`PeerAdvertisement`)을 동결한다.
//
// 키 이름은 #85 와 함께 배포됐다. 고치면 구버전 목록에서 랭크가 사라지는데 컴파일은 통과한다.
// 클램프는 상대가 채우는 값을 막는 신뢰경계라, 지점마다 흩어지면 한 곳이 빠진다.
final class PeerAdvertisementTests: XCTestCase {

    /// 피어 변환 테스트용 엔드포인트. 연결에 쓰지 않으므로 값 자체는 의미가 없다.
    private let anyEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: 4_242)

    /// `.bonjour` 는 서비스만 찾아 실제 광고에 TXT가 있어도 `metadata == .none` 을 돌려준다.
    /// 랭크·레벨 카드가 다시 전부 빈 칸이 되지 않도록 TXT 요청 descriptor를 고정한다.
    func testBattleDiscoveryExplicitlyRequestsTXTRecords() {
        switch BattleCenter.discoveryDescriptor() {
        case .bonjourWithTXTRecord(let type, let domain):
            XCTAssertEqual(type, BattleCenter.serviceType)
            XCTAssertNil(domain)
        default:
            XCTFail("Battle discovery must use bonjourWithTXTRecord")
        }
    }

    // MARK: 와이어 계약 (구버전과의 호환)

    /// 키 이름을 리터럴로 동결한다. 상수끼리 비교하면 이름을 바꿔도 테스트가 따라가서, 구버전과
    /// 단절된 사실이 드러나지 않는다.
    func testKeyNamesAreFrozenAsLiterals() {
        XCTAssertEqual(PeerAdvertisement.Key.rank, "rankPoints")
        XCTAssertEqual(PeerAdvertisement.Key.level, "trainerLevel")
        XCTAssertEqual(PeerAdvertisement.Key.tiers, "achievementTiers")
    }

    /// 구운 레코드에 그 키가 실제로 실려 있는지 본다. 상수만 맞고 굽는 쪽이 다른 키를 쓰면 위
    /// 테스트는 통과하고 상대 화면은 빈다.
    func testTheBakedRecordCarriesTheFrozenKeys() {
        let record = PeerAdvertisement(rankPoints: 1_234, trainerLevel: 12, achievementTiers: 8).txtRecord
        XCTAssertEqual(record["rankPoints"], "1234")
        XCTAssertEqual(record["trainerLevel"], "12")
        XCTAssertEqual(record["achievementTiers"], "8")
    }

    // MARK: 왕복

    func testRoundTripPreservesEveryField() {
        let mine = PeerAdvertisement(rankPoints: 2_150, trainerLevel: 37, achievementTiers: 11,
                                     outfit: TrainerOutfit(worn: [.hat: .capRed]))
        XCTAssertEqual(PeerAdvertisement(mine.txtRecord), mine)
    }

    // MARK: 착장 (#room-walk-dungeon-design 트레이너 아바타)

    func testOutfitKeyIsFrozen() { XCTAssertEqual(PeerAdvertisement.Key.outfit, "outfit") }

    /// 착장도 다른 필드처럼 왕복해야 상대 카드가 옳게 그려진다.
    func testOutfitRoundTripsThroughTheRecord() {
        let outfit = TrainerOutfit(worn: [.hat: .capRed, .top: .jacketBlue])
        let mine = PeerAdvertisement(trainerLevel: 3, outfit: outfit)
        XCTAssertEqual(mine.txtRecord["outfit"], "hat:cap_red,top:jacket_blue")
        XCTAssertEqual(PeerAdvertisement(mine.txtRecord).outfit, outfit)
    }

    /// 빈 착장은 키를 안 싣는다 — 다른 필드와 같은 "없음 vs 0" 구분이다.
    func testEmptyOutfitIsNotAdvertised() {
        XCTAssertNil(PeerAdvertisement(outfit: TrainerOutfit()).txtRecord["outfit"])
        XCTAssertNil(PeerAdvertisement(outfit: TrainerOutfit()).outfit)
    }

    /// 모르는 슬롯·아이템이 섞여도 아는 것만 살고, 완전히 못 읽으면 착장만 nil — 피어 자체는
    /// 목록에 남는다(관대 파싱).
    func testUnknownOutfitEntriesAreIgnoredWithoutDroppingThePeer() {
        var record = NWTXTRecord()
        record["outfit"] = "hat:cap_red,wings:future_item"
        let parsed = PeerAdvertisement(record)
        XCTAssertEqual(parsed.outfit?.worn, [.hat: .capRed])
        record["outfit"] = "garbage"
        XCTAssertNil(PeerAdvertisement(record).outfit)
    }

    /// 전체 슬롯을 다 입어도 TXT 제한(255 바이트)에 한참 못 미쳐야 한다.
    func testFullOutfitStaysWellUnderTheTxtLimit() {
        let worn = Dictionary(uniqueKeysWithValues: OutfitSlot.allCases.map { slot in
            (slot, OutfitItem.allCases.first { $0.slot == slot }!) })
        XCTAssertLessThan(TrainerOutfit(worn: worn).wireString!.utf8.count, 200)
    }

    /// 빈 칸은 키를 싣지 않는다. 읽는 쪽이 "없음"과 "0"을 구별해야 하고, 0 을 실으면 상대
    /// 카드에 Lv.0 이 그려진다.
    func testNilFieldsAreOmittedFromTheRecord() {
        let record = PeerAdvertisement(rankPoints: 100).txtRecord
        XCTAssertEqual(record["rankPoints"], "100")
        XCTAssertNil(record["trainerLevel"])
        XCTAssertNil(record["achievementTiers"])
    }

    // MARK: 관대 파싱 (피어를 버리지 않는다)

    /// 구버전은 `rankPoints` 하나만 광고한다. 랭크는 살고 나머지는 비어야 한다. 파싱이 실패하면
    /// 그 피어가 목록에서 사라져 신청조차 못 한다.
    func testAnOlderPeerAdvertisingOnlyRankStillParses() {
        let parsed = PeerAdvertisement(NWTXTRecord(["rankPoints": "1200"]))
        XCTAssertEqual(parsed.rankPoints, 1_200)
        XCTAssertNil(parsed.trainerLevel)
        XCTAssertNil(parsed.achievementTiers)
    }

    func testAnEmptyRecordParsesToAllNils() {
        XCTAssertEqual(PeerAdvertisement(NWTXTRecord()), PeerAdvertisement())
    }

    /// 숫자가 아닌 값은 nil 이다. 0 으로 떨어지면 랭크 없는 상대가 "Poké Ball R4"로 보인다.
    func testGarbageValuesBecomeNilRatherThanZero() {
        let parsed = PeerAdvertisement(NWTXTRecord(["rankPoints": "abc",
                                                    "trainerLevel": "",
                                                    "achievementTiers": " "]))
        XCTAssertNil(parsed.rankPoints)
        XCTAssertNil(parsed.trainerLevel)
        XCTAssertNil(parsed.achievementTiers)
    }

    // MARK: 클램프 (신뢰경계 한 곳)

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

    /// 와이어로 들어오는 경로도 같은 클램프를 지나야 한다. 이니셜라이저만 자르고 파싱이 그냥
    /// 대입하면 조작된 광고가 Lv.99999 로 카드를 밀어내 목록 폭이 깨진다. `BattleRank.clamped`
    /// 가 세이브 경로만 막고 와이어 경로엔 가드가 없던 것과 같은 부류다.
    func testValuesArrivingOverTheWireAreClampedToo() {
        let hostile = PeerAdvertisement(NWTXTRecord(["rankPoints": "999999",
                                                     "trainerLevel": "99999",
                                                     "achievementTiers": "-42"]))
        XCTAssertEqual(hostile.rankPoints, BattleRank.maximumPoints)
        XCTAssertEqual(hostile.trainerLevel, TrainerLevel.maximumLevel)
        XCTAssertEqual(hostile.achievementTiers, 0)
    }

    // MARK: 버전 스큐 (상대의 카탈로그가 내 것과 다를 때)

    /// 카탈로그는 조절 손잡이라 언젠가 트랙·문턱이 늘어난다. 그때 상대의 단계 수를 내 분모로
    /// 그리면 18/20 인 상대가 `16/16`(완료)으로 보이고, 진행도를 보는 기능이 거짓을 말한다.
    /// 분모를 함께 광고하는 이 빌드가 먼저 배포돼 있어야 미래 상대를 옳게 그린다.
    func testAPeerOnANewerCatalogKeepsItsOwnDenominator() {
        let newer = PeerAdvertisement(NWTXTRecord(["achievementTiers": "18",
                                                   "achievementCeiling": "20"]))
        XCTAssertEqual(newer.achievementProgress?.tiers, 18, "내 상한(16)으로 깎으면 안 된다")
        XCTAssertEqual(newer.achievementProgress?.ceiling, 20)
    }

    /// 분모를 안 싣는 구버전 상대는 내 카탈로그를 쓴다. 그게 가진 정보의 전부다.
    func testAPeerWithoutACeilingFallsBackToMyCatalog() {
        let older = PeerAdvertisement(NWTXTRecord(["achievementTiers": "8"]))
        XCTAssertEqual(older.achievementProgress?.tiers, 8)
        XCTAssertEqual(older.achievementProgress?.ceiling, AchievementLadder.tierCeiling)
    }

    /// 분모도 상대가 신고하니 신뢰경계다. 자릿수가 늘면 카드가 밀리므로 표시 상한으로 자른다.
    func testAnAdvertisedCeilingIsClampedForDisplay() {
        let hostile = PeerAdvertisement(NWTXTRecord(["achievementTiers": "999999",
                                                     "achievementCeiling": "999999"]))
        XCTAssertEqual(hostile.achievementProgress?.ceiling, PeerAdvertisement.maximumTierCeiling)
        XCTAssertEqual(hostile.achievementProgress?.tiers, PeerAdvertisement.maximumTierCeiling,
                       "단계는 분모를 넘을 수 없다")
        XCTAssertEqual(PeerAdvertisement(achievementTiers: 5, achievementCeiling: 0)
                        .achievementProgress?.ceiling, 1, "분모 0 은 나눗셈이 아니다")
    }

    /// 단계가 없으면 분수도 없다. 분모만 온 광고로 `0/20` 을 그리면 없는 정보를 만든다.
    func testNoTiersMeansNoFraction() {
        XCTAssertNil(PeerAdvertisement(NWTXTRecord(["achievementCeiling": "20"])).achievementProgress)
    }

    /// 내 광고에도 분모가 실려야 한다. 안 실으면 미래 빌드가 나를 잘못 그린다.
    func testMyOwnAdvertisementCarriesMyCeiling() {
        let mine = PeerAdvertisement(rankPoints: 0, trainerLevel: 1,
                                     achievementTiers: 3,
                                     achievementCeiling: AchievementLadder.tierCeiling)
        XCTAssertEqual(mine.txtRecord["achievementCeiling"], String(AchievementLadder.tierCeiling))
        XCTAssertEqual(PeerAdvertisement.Key.ceiling, "achievementCeiling")
    }

    // MARK: 수신 측 (광고 하나를 카드 한 장으로)
    //
    // private 클로저 안이라 지금까지 무검증이던 구간이다. 아래 서비스 이름과 TXT 는 실제로 관찰한
    // 값이다. 릴리스판이 광고 중인 `유썽#44D580` / `rankPoints=0` 을 `dns-sd` 로 읽어 옮겼다.

    private func peer(_ name: String, _ record: NWTXTRecord? = nil,
                      mine: String = "me#000000") -> BattlePeer? {
        BattleCenter.peer(fromService: name, txtRecord: record,
                          excluding: mine, endpoint: anyEndpoint)
    }

    /// 내 광고는 목록에서 빠져야 한다. 자기 자신에게 대전을 신청할 수는 없다.
    func testMyOwnServiceIsFilteredOut() {
        XCTAssertNil(peer("유썽#44D580", mine: "유썽#44D580"))
    }

    /// 같은 트레이너 이름의 다른 기기는 남이고, 고유 접미가 그걸 가른다. 이름으로 걸렀다면 같은
    /// 이름을 쓰는 두 Mac 이 서로를 자기로 오인해 목록에서 사라진다.
    func testTheSameTrainerNameOnAnotherMachineIsStillAPeer() {
        let other = peer("유썽#FFFFFF", mine: "유썽#44D580")
        XCTAssertEqual(other?.name, "유썽")
        XCTAssertEqual(other?.serviceName, "유썽#FFFFFF")
    }

    /// 표시 이름은 마지막 `#` 에서 자른다. 첫 `#` 에서 자르면 이름에 `#` 을 쓴 사람이 잘린다.
    func testDisplayNameStripsOnlyTheUniqueSuffix() {
        XCTAssertEqual(peer("유썽#44D580")?.name, "유썽")
        XCTAssertEqual(peer("A#B#c1d2e3")?.name, "A#B")
        // 접미가 없는 광고(다른 구현·손으로 띄운 서비스)도 이름 그대로 살린다.
        XCTAssertEqual(peer("NoSuffix")?.name, "NoSuffix")
    }

    /// 실제로 관찰한 구버전 광고. 랭크만 있고, 목록에 남아야 하며 랭크는 보여야 한다.
    func testTheReleasedBuildsRealRecordParsesAsRankOnly() {
        let live = peer("유썽#44D580", NWTXTRecord(["rankPoints": "0"]))
        XCTAssertEqual(live?.rank, BattleRank(points: 0))
        XCTAssertNil(live?.advertisement.trainerLevel)
        XCTAssertNil(live?.advertisement.achievementTiers)
    }

    /// TXT 가 없는 결과(비-Bonjour 메타데이터)도 피어로 남는다. 숨기면 신청할 방법이 없다.
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

    /// 같은 상대가 레벨을 올리면 다른 값이어야 한다. 신원(`serviceName`)만 비교하면 동등성으로
    /// 갱신을 판단하는 쪽이 실시간 갱신을 삼켜, 이 기능의 존재 이유가 사라진다.
    func testAdvertisementChangeMakesThePeerUnequal() {
        let before = peer("Ash#abc123", NWTXTRecord(["trainerLevel": "12"]))
        let after = peer("Ash#abc123", NWTXTRecord(["trainerLevel": "13"]))
        XCTAssertEqual(before?.id, after?.id, "신원은 그대로여야 한다(행이 새로 그려지면 안 된다)")
        XCTAssertNotEqual(before, after)
    }

    // MARK: 랭크 어댑터

    /// 기존 `peer.rank` 호출부를 살려 두는 자리. 랭크가 없으면 nil 이어야 한다. 빈
    /// `BattleRank()` 는 정보 없음 대신 Poké Ball R4 로 그려진다.
    func testRankAdapterMirrorsBattleRankAndStaysNilWhenAbsent() {
        XCTAssertEqual(PeerAdvertisement(rankPoints: 1_234).rank, BattleRank(points: 1_234))
        XCTAssertNil(PeerAdvertisement().rank)
    }
}
