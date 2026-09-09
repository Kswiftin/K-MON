import XCTest
@testable import PokeTokenBar

/// `CompanionStore` 의 사파리존 연동 — 방문 시작·포획 커밋·방문/포획 두 원장의 롤오버.
/// `RaidRoomTests` 의 `catchRaidBoss` 검증과 같은 헬퍼(`stubStore`/`TestClock`)를 쓴다.
@MainActor
final class CompanionStoreSafariZoneTests: XCTestCase {

    // MARK: 방문 시작

    func testBeginSafariZoneVisitStartsAVisitAndRecordsTheLedger() {
        let store = stubStore(TestClock(), tag: "safari-begin")
        XCTAssertEqual(store.safariZoneVisitsRemainingToday, SafariZone.dailyVisitCap)
        XCTAssertTrue(store.beginSafariZoneVisit(zone: .grassland))
        XCTAssertNotNil(store.safariVisit)
        XCTAssertEqual(store.safariVisit?.zone, .grassland)
        XCTAssertEqual(store.safariZoneVisitsRemainingToday, SafariZone.dailyVisitCap - 1)
    }

    /// 이미 진행 중인 방문이 있으면 새 방문을 시작할 수 없다 — 진행 중인 볼·걸음을 잃지 않는다.
    func testBeginSafariZoneVisitRejectsWhileAVisitIsInProgress() {
        let store = stubStore(TestClock(), tag: "safari-begin-twice")
        XCTAssertTrue(store.beginSafariZoneVisit(zone: .grassland))
        let visitsAfterFirst = store.safariZoneVisitsRemainingToday
        XCTAssertFalse(store.beginSafariZoneVisit(zone: .wetland), "진행 중인 방문이 있으면 거부돼야 한다")
        XCTAssertEqual(store.safariVisit?.zone, .grassland, "거부된 시도가 존을 바꾸면 안 된다")
        XCTAssertEqual(store.safariZoneVisitsRemainingToday, visitsAfterFirst, "거부된 시도는 원장을 안 찍는다")
    }

    /// 하루 방문 상한을 다 쓰면 더 이상 방문을 시작할 수 없다.
    func testBeginSafariZoneVisitRejectsAfterDailyVisitCapIsReached() {
        let store = stubStore(TestClock(), tag: "safari-begin-cap")
        for _ in 0..<SafariZone.dailyVisitCap {
            XCTAssertTrue(store.beginSafariZoneVisit(zone: .grassland))
            store.safariVisit = nil   // 방문을 끝낸 것으로 치고 다음 방문을 시작할 수 있게 한다.
        }
        XCTAssertEqual(store.safariZoneVisitsRemainingToday, 0)
        XCTAssertFalse(store.beginSafariZoneVisit(zone: .grassland), "하루 상한을 넘기면 안 된다")
    }

    // MARK: 포획 커밋

    func testCatchInSafariZoneAddsToBoxWhenACompanionExists() async {
        let store = stubStore(TestClock(), tag: "safari-catch-box")
        await store.hatch(baseID: 20)
        let partner = store.state.active?.id
        XCTAssertNotNil(partner, "테스트 전제: 동행이 있다")

        let result = await store.catchInSafariZone(speciesID: 20)
        XCTAssertEqual(result, .box)
        XCTAssertEqual(store.state.active?.id, partner, "동행은 그대로다")
        XCTAssertEqual(store.state.boxedMons.count, 1)
    }

    func testCatchInSafariZoneFillsAnEmptyCompanionSlot() async {
        let store = stubStore(TestClock(), tag: "safari-catch-companion")
        XCTAssertNil(store.state.active, "테스트 전제: 동행이 없다")
        let result = await store.catchInSafariZone(speciesID: 20)
        XCTAssertEqual(result, .companion, "빈 동행 자리를 채웠으면 '상자' 라고 말할 수 없다")
        XCTAssertEqual(store.state.active?.currentID, 20)
    }

    /// 조우 화면이 미리 굴려 보여준 성별과, 실제로 잡힌 개체의 성별이 달라지면 안 된다 —
    /// 라이츄(#26)는 수컷 쪽이 훨씬 흔한 성비(75%/25%)라, 강제로 넘긴 암컷이 그대로 나오는지가
    /// `presetGender` 가 실제로 존중된다는 강한 증거다.
    func testCatchInSafariZoneUsesThePresetGenderWhenGiven() async {
        let store = stubStore(TestClock(), tag: "safari-catch-preset-gender")
        let result = await store.catchInSafariZone(speciesID: 20, gender: .female)
        XCTAssertEqual(result, .companion)
        XCTAssertEqual(store.state.active?.gender, .female, "미리 굴려 보여준 성별을 그대로 써야 한다")
    }

    /// 조우 화면이 몬스터볼 배지로 보여주는 판정 — 아직 안 잡았으면 거짓, 잡은 뒤(동행이든
    /// 박스든)에는 참이어야 한다.
    func testIsSpeciesAlreadyOwnedReflectsWhatIsActuallyCaught() async {
        let store = stubStore(TestClock(), tag: "safari-owned-badge")
        XCTAssertFalse(store.isSpeciesAlreadyOwned(20), "아직 잡은 적 없으면 거짓이어야 한다")
        await store.hatch(baseID: 20)
        XCTAssertTrue(store.isSpeciesAlreadyOwned(20), "동행으로 있으면 참이어야 한다")
    }

    /// 하루 포획 상한을 다 쓰면 더 이상 잡을 수 없다 — 볼·걸음이 남아 있어도 `MonState` 를
    /// 안 만든다. §입장·일일 제한이 지키려는 바로 그 상한이다.
    func testCatchInSafariZoneRejectsAfterDailyCatchCapIsReached() async {
        let store = stubStore(TestClock(), tag: "safari-catch-cap")
        await store.hatch(baseID: 20)   // 동행을 채워 이후 포획은 전부 박스로 간다.
        for _ in 0..<SafariZone.dailyCatchCap {
            let result = await store.catchInSafariZone(speciesID: 20)
            XCTAssertEqual(result, .box)
        }
        XCTAssertEqual(store.state.boxedMons.count, SafariZone.dailyCatchCap)
        let extra = await store.catchInSafariZone(speciesID: 20)
        XCTAssertEqual(extra, .claimedToday, "하루 상한을 넘기면 안 된다")
        XCTAssertEqual(store.state.boxedMons.count, SafariZone.dailyCatchCap,
                       "거부된 시도가 박스를 늘리면 안 된다")
    }

    /// 스프라이트가 없는 번호는 잡히지 않고, 못 잡은 판은 오늘의 기회를 안 태운다 —
    /// `catchRaidBoss` 와 같은 계약.
    func testCatchInSafariZoneRejectsSpeciesWithoutASprite() async {
        let store = stubStore(TestClock(), tag: "safari-catch-gap")
        await store.hatch(baseID: 20)
        let gap = PokemonAssets.spriteGaps.first ?? 990
        let result = await store.catchInSafariZone(speciesID: gap)
        XCTAssertEqual(result, .unavailable)
        XCTAssertTrue(store.state.boxedMons.isEmpty)
        XCTAssertEqual(store.safariZoneCatchesRemainingToday, SafariZone.dailyCatchCap,
                       "못 잡은 판이 오늘의 기회를 태우면 안 된다")
    }

    // MARK: 레이드·사파리존 원장 독립성

    /// 레이드에서 오늘의 포획 기회를 다 써도 사파리존 포획엔 영향이 없다 — 원장이 완전히
    /// 분리돼 있다(하나로 합치면 레이드로 하루를 태운 사용자가 사파리존도 못 하게 된다).
    func testRaidCatchLedgerDoesNotAffectSafariZoneLedger() async {
        let store = stubStore(TestClock(), tag: "safari-raid-independent")
        await store.hatch(baseID: 20)
        _ = await store.catchRaidBoss(speciesID: 20)
        XCTAssertTrue(store.raidCatchClaimedToday)
        XCTAssertEqual(store.safariZoneCatchesRemainingToday, SafariZone.dailyCatchCap,
                       "레이드 포획이 사파리존 원장을 건드리면 안 된다")
    }

    // MARK: 날짜 롤오버

    func testCatchLedgerResetsOnANewDay() async {
        let clock = TestClock()
        let store = stubStore(clock, tag: "safari-catch-rollover")
        await store.hatch(baseID: 20)
        for _ in 0..<SafariZone.dailyCatchCap {
            _ = await store.catchInSafariZone(speciesID: 20)
        }
        XCTAssertEqual(store.safariZoneCatchesRemainingToday, 0)
        clock.advance(24 * 60 * 60)
        XCTAssertEqual(store.safariZoneCatchesRemainingToday, SafariZone.dailyCatchCap,
                       "날짜가 바뀌면 원장이 갈아 끼워져야 한다")
        let result = await store.catchInSafariZone(speciesID: 20)
        XCTAssertEqual(result, .box)
    }

    func testVisitLedgerResetsOnANewDay() {
        let clock = TestClock()
        let store = stubStore(clock, tag: "safari-visit-rollover")
        for _ in 0..<SafariZone.dailyVisitCap {
            XCTAssertTrue(store.beginSafariZoneVisit(zone: .grassland))
            store.safariVisit = nil
        }
        XCTAssertEqual(store.safariZoneVisitsRemainingToday, 0)
        clock.advance(24 * 60 * 60)
        XCTAssertEqual(store.safariZoneVisitsRemainingToday, SafariZone.dailyVisitCap,
                       "날짜가 바뀌면 원장이 갈아 끼워져야 한다")
    }

    // MARK: 세이브 이전 — 무결성 서명·기기 병합

    /// 값이 든 기존 세이브가 없는 새 필드라 조건부 append다 — 기본 상태는 서명에 아무 흔적도
    /// 안 남긴다(`testDefaultStateGainsNoRaidCanonicalSegment` 와 같은 패턴).
    func testDefaultStateGainsNoSafariZoneCanonicalSegment() {
        let canonical = SaveTransfer.canonicalString(CompanionState())
        XCTAssertFalse(canonical.contains("|szv"))
        XCTAssertFalse(canonical.contains("|szc"))
    }

    /// 기기 병합 시 같은 날이면 **많이 쓴/받은 쪽**을 남긴다 — 적은 쪽을 쓰면 세이브를 주고받는
    /// 것만으로 하루 상한이 되살아난다(`mergedGymDefenseLedger` 와 같은 계약).
    func testRebaseKeepsTheLargerSafariZoneLedgerOnTheSameDay() {
        var imported = CompanionState()
        imported.safariZoneCatchDate = "2026-09-02"
        imported.safariZoneCatchesToday = 2
        var current = CompanionState()
        current.safariZoneCatchDate = "2026-09-02"
        current.safariZoneCatchesToday = 5
        let rebased = SaveTransfer.rebasedForThisDevice(imported, current: current)
        XCTAssertEqual(rebased.safariZoneCatchDate, "2026-09-02")
        XCTAssertEqual(rebased.safariZoneCatchesToday, 5, "적게 쓴 쪽을 남기면 상한이 되살아난다")
    }

    /// 날짜가 다르면 더 최근 쪽을 그대로 남긴다 — 지난 날 기록은 어차피 다음 방문에서 갈아 끼워진다.
    func testRebaseKeepsTheNewerSafariZoneLedgerOnDifferentDays() {
        var imported = CompanionState()
        imported.safariZoneVisitDate = "2026-08-01"
        imported.safariZoneVisitsToday = 3
        var current = CompanionState()
        current.safariZoneVisitDate = "2026-09-02"
        current.safariZoneVisitsToday = 1
        let rebased = SaveTransfer.rebasedForThisDevice(imported, current: current)
        XCTAssertEqual(rebased.safariZoneVisitDate, "2026-09-02")
        XCTAssertEqual(rebased.safariZoneVisitsToday, 1, "이 기기가 오늘 이미 쓴 참여 횟수여야 한다")
    }

    /// 정규화(`sanitized`)가 원장 카운트를 0~하루 상한으로 자른다 — 손편집으로 상한을 넘긴
    /// 값이 들어오면 그다음부터 하루 상한이 사실상 사라진다.
    func testSanitizedClampsSafariZoneCountsToTheDailyCaps() {
        var state = CompanionState()
        state.safariZoneVisitsToday = SafariZone.dailyVisitCap + 50
        state.safariZoneCatchesToday = -5
        let sanitized = SaveTransfer.sanitized(state)
        XCTAssertEqual(sanitized.safariZoneVisitsToday, SafariZone.dailyVisitCap)
        XCTAssertEqual(sanitized.safariZoneCatchesToday, 0)
    }
}
