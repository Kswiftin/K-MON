import XCTest
import SwiftUI
@testable import PokeTokenBar

/// 배틀 필드 + 선택 패널 (계획 §6 Phase 6·8, §9 PR 4). 기전은 건드리지 않는다 — 화면만이다.
///
/// UI 는 컴파일과 단위 테스트를 통과하면서 화면에서 깨진다(defect-log). 그래서 여기 있는 테스트는
/// 뷰의 모양을 흉내내지 않고, **뷰가 읽는 순수 결정**을 겨냥한다 — 색 임계, 표기 규칙, PP 단계,
/// 스프라이트 URL, 그리고 창 예산. 뷰 자체는 `NSHostingController.sizeThatFits` 로 실제 폭·높이를 잰다.
@MainActor
final class BattleFieldTests: XCTestCase {

    // MARK: 고정 재료

    private func mon(_ types: [PokemonType] = [.normal], hp: Int = 100, name: String = "탱커",
                     shiny: Bool = false) -> BattleSnapshot {
        BattleSnapshot(speciesID: 143, name: name, trainer: nil, level: 50, nature: nil,
                       isShiny: shiny, types: types,
                       base: BattleStats(hp: hp, atk: 100, def: 100, spa: 100, spd: 100, spe: 100),
                       moves: fourMoves)
    }

    private var fourMoves: [MoveSpec] {
        [MoveSpec(id: 1, names: ["ko": "몸통박치기", "en": "Tackle", "ja": "たいあたり"],
                  type: .normal, power: 40, damageClass: .physical, accuracy: 100, pp: 35),
         MoveSpec(id: 2, names: ["ko": "불대문자", "en": "Fire Blast", "ja": "だいもんじ"],
                  type: .fire, power: 110, damageClass: .special, accuracy: 85, pp: 5),
         MoveSpec(id: 3, names: ["ko": "울부짖기", "en": "Roar", "ja": "ほえる"],
                  type: .normal, power: 0, damageClass: .status, accuracy: nil, pp: 20),
         MoveSpec(id: 4, names: ["ko": "지진", "en": "Earthquake", "ja": "じしん"],
                  type: .ground, power: 100, damageClass: .physical, accuracy: 100, pp: 10)]
    }

    private func renderedHeight(_ view: some View, proposingWidth: CGFloat) -> CGFloat {
        NSHostingController(rootView: view)
            .sizeThatFits(in: CGSize(width: proposingWidth, height: .greatestFiniteMagnitude)).height
    }

    private func renderedWidth(_ view: some View, proposing: CGFloat) -> CGFloat {
        NSHostingController(rootView: view)
            .sizeThatFits(in: CGSize(width: proposing, height: BattleFieldMetrics.windowHeight)).width
    }

    // MARK: HP바 — 3단계 (트리거 브랜치: 예전엔 살았나 죽었나로 2색)

    /// 예전 `teamSlotCard`·멀티 격자는 `hp > 0 ? .green : .red` 였다 — HP 5% 와 100% 가 같은 색이다.
    /// 임계 양쪽을 다 밟는다. 경계값(정확히 50%·20%)이 아래 단계로 떨어지는지가 핵심이다.
    func testHPBarHasThreeTiersAndBothThresholdsFallDownward() {
        XCTAssertEqual(HPTier.of(hp: 100, max: 100), .healthy)
        XCTAssertEqual(HPTier.of(hp: 51, max: 100), .healthy)
        XCTAssertEqual(HPTier.of(hp: 50, max: 100), .warning, "정확히 50% 는 이미 초록이 아니다")
        XCTAssertEqual(HPTier.of(hp: 21, max: 100), .warning)
        XCTAssertEqual(HPTier.of(hp: 20, max: 100), .critical, "정확히 20% 는 이미 노랑이 아니다")
        XCTAssertEqual(HPTier.of(hp: 1, max: 100), .critical)
        XCTAssertEqual(HPTier.of(hp: 0, max: 100), .critical)
    }

    /// 세 단계가 서로 다른 색이어야 단계가 화면에 드러난다 — 같은 색 두 개면 단계가 없는 것과 같다.
    func testEachHPTierHasItsOwnColor() {
        let colors = [HPTier.healthy.color, HPTier.warning.color, HPTier.critical.color]
        XCTAssertEqual(Set(colors.map { String(describing: $0) }).count, 3)
    }

    /// 최대 HP 가 0 인 값이 와도(구버전 피어·손상 세이브) 0 나눗셈으로 죽지 않는다.
    func testHPTierSurvivesAZeroMaximum() {
        XCTAssertEqual(HPTier.of(hp: 0, max: 0), .critical)
    }

    // MARK: HP 표기 — 내 쪽 실수치 / 상대 % (계획 §6.1)

    /// 상대 실수치는 원래 모르는 정보다. 정보 은닉이 곧 게임성이라 Showdown 도 이렇게 가른다.
    func testMyHPShowsExactNumbersWhileTheirsShowsPercentOnly() {
        XCTAssertEqual(HPReadout.mine(hp: 84, max: 121), "84/121")
        let theirs = HPReadout.theirs(hp: 84, max: 121)
        XCTAssertEqual(theirs, "69%")
        XCTAssertFalse(theirs.contains("121"), "상대 최대 HP 가 새면 정보 은닉이 무의미해진다")
        XCTAssertFalse(theirs.contains("84"), "상대 실수치가 새면 정보 은닉이 무의미해진다")
    }

    /// 살아 있으면 절대 `0%` 로 보이지 않고, 쓰러졌으면 반드시 `0%` 다.
    /// 내림만 하면 1/121 이 0% 로 보여 살아 있는 상대가 죽은 것처럼 읽힌다.
    func testALivingOpponentNeverReadsZeroPercent() {
        XCTAssertEqual(HPReadout.theirs(hp: 1, max: 121), "1%")
        XCTAssertEqual(HPReadout.theirs(hp: 0, max: 121), "0%")
        XCTAssertEqual(HPReadout.theirs(hp: 121, max: 121), "100%")
    }

    // MARK: 기술 버튼 — 타입색 + 분류 아이콘 + PP 단계

    /// 예전엔 기술 4개가 전부 회색 `.bordered` 였다 — 타입이 버튼에 안 드러났다.
    func testEveryTypeGetsItsOwnButtonColor() {
        let colors = PokemonType.allCases.map { String(describing: $0.battleColor) }
        XCTAssertEqual(Set(colors).count, PokemonType.allCases.count,
                       "타입 두 개가 같은 색이면 버튼에서 구별되지 않는다")
    }

    /// 밝은 타입색 위엔 검은 글자, 어두운 타입색 위엔 흰 글자. 한쪽으로 고정하면 18색 중 절반이
    /// 읽히지 않는다 — 두 분기를 다 밟고, 실제 대비도 WCAG AA(4.5:1) 이상인지 본다.
    func testTypeLabelPicksTheReadableSideOnBothLightAndDarkTypes() {
        XCTAssertTrue(PokemonType.electric.prefersDarkLabel, "노란 배경엔 검은 글자")
        XCTAssertFalse(PokemonType.dragon.prefersDarkLabel, "남색 배경엔 흰 글자")
        for type in PokemonType.allCases {
            XCTAssertGreaterThanOrEqual(
                ColorContrast.ratio(type.battleRGB, type.prefersDarkLabel ? (0, 0, 0) : (1, 1, 1)),
                4.5, "\(type.rawValue) 배경 위 글자 대비가 AA 미달")
        }
    }

    /// 글자색 접근자가 대비 판정과 어긋나면 안 된다 — 뷰가 읽는 건 이쪽이다.
    func testTheLabelColourFollowsTheContrastDecision() {
        for type in PokemonType.allCases {
            XCTAssertEqual(type.battleLabelColor, type.prefersDarkLabel ? Color.black : Color.white,
                           "\(type.rawValue) 의 글자색이 대비 판정과 다르다")
        }
    }

    /// 배지 색 7분기를 전부 밟는다. 뷰 안의 `private` 로 두면 화면에 뜬 상태만 실행되고 나머지는
    /// 한 번도 돌지 않는데, 라인 커버리지는 그걸 초록으로 보고한다(PR 3 에서 겪은 부류).
    func testEveryStatusHasABadgeTintAndTheyAreNotAllTheSame() {
        let tints = Status.allCases.map { String(describing: $0.badgeTint) }
        XCTAssertEqual(tints.count, 7)
        XCTAssertGreaterThanOrEqual(Set(tints).count, 6, "독·맹독만 같은 색을 공유한다")
        XCTAssertEqual(Status.poison.badgeTint, Status.toxic.badgeTint, "독 계열은 한 색으로 읽힌다")
        XCTAssertNotEqual(Status.burn.badgeTint, Status.freeze.badgeTint)
    }

    /// 물리·특수·변화 세 분류가 각자 아이콘을 가진다 — 변화기(Phase 3)가 무브셋에 들어오면
    /// 위력 0 만으로는 "공격기인데 위력이 0" 과 구별되지 않는다.
    func testEachDamageClassHasItsOwnIcon() {
        let symbols = [MoveDamageClass.physical, .special, .status].map(\.symbolName)
        XCTAssertEqual(Set(symbols).count, 3)
        XCTAssertFalse(symbols.contains(where: \.isEmpty))
    }

    /// PP 경고는 3단계다 — 예전엔 0 만 빨강이라 1 남은 기술과 35 남은 기술이 같아 보였다.
    /// 경계값(정확히 1/4)이 경고로 떨어지는지, 0 이 경고가 아니라 소진인지 둘 다 본다.
    func testPPWarningHasALowTierBetweenAmpleAndEmpty() {
        XCTAssertEqual(PPTier.of(remaining: 35, max: 35), .ample)
        XCTAssertEqual(PPTier.of(remaining: 10, max: 35), .ample)
        XCTAssertEqual(PPTier.of(remaining: 10, max: 40), .low, "정확히 1/4 은 이미 경고다")
        XCTAssertEqual(PPTier.of(remaining: 1, max: 35), .low)
        XCTAssertEqual(PPTier.of(remaining: 0, max: 35), .empty)
        XCTAssertEqual(Set([PPTier.ample, .low, .empty].map { String(describing: $0.color) }).count, 3,
                       "세 단계가 같은 색이면 단계가 없는 것과 같다")
    }

    /// 최대 PP 가 0 인 기술(구버전 피어·손상 세이브)이 와도 0 나눗셈이나 영구 경고가 되지 않는다.
    func testAMoveClaimingZeroMaximumPPIsNotPermanentlyWarned() {
        XCTAssertEqual(PPTier.of(remaining: 5, max: 0), .ample)
        XCTAssertEqual(PPTier.of(remaining: 0, max: 0), .empty, "남은 게 없으면 최대와 무관하게 소진이다")
    }

    /// 소진된 기술은 고를 수 없다 — 색만 바꾸고 활성으로 두면 눌려서 아무 일도 안 일어난다.
    func testASpentMoveIsNotSelectable() {
        XCTAssertFalse(PPTier.of(remaining: 0, max: 35).isSelectable)
        XCTAssertTrue(PPTier.of(remaining: 1, max: 35).isSelectable)
    }

    // MARK: 등 스프라이트 (계획 §6.4 — URL 하나 차이)

    /// 앞·뒤가 같은 캐시 키를 쓰면 먼저 받은 쪽이 양쪽에 나온다(내 포켓몬이 정면으로 보이는 증상).
    func testBackSpritesGetTheirOwnCacheKey() {
        for animated in [true, false] {
            for shiny in [true, false] {
                XCTAssertNotEqual(
                    SpriteStore.cacheKey(speciesID: 25, animated: animated, shiny: shiny, back: true),
                    SpriteStore.cacheKey(speciesID: 25, animated: animated, shiny: shiny, back: false),
                    "animated=\(animated) shiny=\(shiny) 에서 앞·뒤 키가 겹친다")
            }
        }
    }

    /// 앞면 키는 그대로여야 한다 — 바뀌면 기존 설치의 디스크 캐시가 통째로 무효화된다.
    func testFrontSpriteCacheKeysAreUnchanged() {
        XCTAssertEqual(SpriteStore.cacheKey(speciesID: 25, animated: true, shiny: false), "25-showdown-normal")
        XCTAssertEqual(SpriteStore.cacheKey(speciesID: 25, animated: false, shiny: false), "25-s")
    }

    /// 실제로 200 이 오는 경로다(계획 §6.4 에서 확인). 폴더 위치를 틀리면 조용히 404 →
    /// 앞면 폴백으로 떨어져 "등 스프라이트가 안 붙는다" 가 아니라 "정면이 나온다" 로 보인다.
    func testBackSpriteURLsPointAtTheBackFolders() {
        XCTAssertTrue(SpriteStore.spriteURL(speciesID: 25, animated: true, shiny: false, back: true)
                        .hasSuffix("/other/showdown/back/25.gif"))
        XCTAssertTrue(SpriteStore.spriteURL(speciesID: 25, animated: true, shiny: true, back: true)
                        .hasSuffix("/other/showdown/back/shiny/25.gif"))
        XCTAssertTrue(SpriteStore.spriteURL(speciesID: 25, animated: false, shiny: false, back: true)
                        .hasSuffix("/pokemon/back/25.png"))
        XCTAssertTrue(SpriteStore.spriteURL(speciesID: 25, animated: false, shiny: true, back: true)
                        .hasSuffix("/pokemon/back/shiny/25.png"))
    }

    /// 앞면 URL 대조군 — 뒤를 붙이면서 앞을 옮기지 않았는지 확인한다.
    func testFrontSpriteURLsStayWhereTheyWere() {
        XCTAssertTrue(SpriteStore.spriteURL(speciesID: 25, animated: true, shiny: false, back: false)
                        .hasSuffix("/other/showdown/25.gif"))
        XCTAssertTrue(SpriteStore.spriteURL(speciesID: 25, animated: false, shiny: true, back: false)
                        .hasSuffix("/pokemon/shiny/25.png"))
    }

    // MARK: 교체 슬롯 (팀 연습의 스트립 일반화)

    /// 활성 슬롯과 쓰러진 슬롯은 고를 수 없고, 그 외는 고를 수 있다. 셋을 한 번에 본다 —
    /// "쓰러진 슬롯만 막기" 오구현은 활성 슬롯 대조군이 없으면 통과한다.
    func testSwitchSlotsBlockTheActiveOneAndTheFaintedOnes() {
        var team = [BattleSide(mon(name: "1번")), BattleSide(mon(name: "2번")), BattleSide(mon(name: "3번"))]
        team[2].hp = 0
        let slots = SwitchStripModel.slots(team, active: 0)

        XCTAssertEqual(slots.count, 3, "쓰러진 슬롯도 자리는 보인다 — 파티가 몇 마리인지가 정보다")
        XCTAssertTrue(slots[0].isActive)
        XCTAssertFalse(slots[0].isSelectable, "지금 나와 있는 포켓몬으로 교체할 수는 없다")
        XCTAssertTrue(slots[1].isSelectable)
        XCTAssertFalse(slots[2].isSelectable, "쓰러진 포켓몬으로 교체할 수는 없다")
        XCTAssertEqual(slots.map(\.index), [0, 1, 2], "인덱스가 곧 교체 대상이다 — 어긋나면 다른 놈이 나온다")
    }

    // MARK: 1v1 턴 타이머 (계획 Phase 8 — 멀티엔 이미 있고 1v1 만 없었다)

    /// 상대가 자리를 비우면 1v1 은 영원히 멈춘다 — 기권 말고는 나갈 길이 없었다.
    /// 시간이 다 되면 PP 가 남은 첫 기술을 자동으로 고른다(결정적 — rng 를 쓰지 않는다).
    func testTimingOutPicksTheFirstUsableMoveInsteadOfStalling() {
        var side = BattleSide(mon())
        XCTAssertEqual(BattleCenter.automaticMoveIndex(for: side), 0)
        side.pp[0] = 0
        XCTAssertEqual(BattleCenter.automaticMoveIndex(for: side), 1)
        side.pp = side.pp.map { _ in 0 }
        XCTAssertEqual(BattleCenter.automaticMoveIndex(for: side), -1, "전부 소진이면 발버둥이다")
    }

    /// 1v1 제한이 멀티와 같아야 두 모드의 체감이 갈리지 않는다.
    func testTheOneOnOneTurnLimitMatchesTheMultiplayerOne() {
        XCTAssertEqual(BattleCenter.turnDuration, MultiplayerRoomCenter.turnDuration)
    }

    // MARK: 창 예산 (계획 §6.3 안 A — 전용 배틀 창)

    /// 창 예산을 재는 표본. **최악 케이스로 채운다** — 상태 배지 두 개, 이로치 별표, 기절한 교체 슬롯,
    /// 양쪽 actor 의 로그 줄. 평온한 표본으로 재면 화면에서만 나타나는 분기를 한 번도 밟지 못한다.
    private func arena(logLines: Int = BattleFieldMetrics.logLines,
                       allPPSpent: Bool = false,
                       turnEndsAt: Date? = nil,
                       theirHP: Int? = nil) -> BattleArenaView {
        var theirs = BattleSide(mon([.fire, .flying], name: "상대"))
        theirs.hp = theirHP ?? theirs.stats.hp / 3
        theirs.status = .burn
        theirs.confusionTurns = 3
        var mine = BattleSide(mon([.water], name: "내 포켓몬", shiny: true))
        mine.pp = allPPSpent ? mine.pp.map { _ in 0 } : [1, mine.pp[1], mine.pp[2], 0]
        var fainted = BattleSide(mon([.grass], name: "기절"))
        fainted.hp = 0
        return BattleArenaView(
            mine: mine, theirs: theirs,
            myTitle: "내 포켓몬", theirTitle: "상대 트레이너",
            l: L(.ko), turn: 7,
            logLines: (0..<logLines).map {
                BattleLog.Line(actor: $0.isMultiple(of: 2) ? .a : .b,
                               text: "탱커의 몸통박치기! 상대는 12 데미지를 받았다 (\($0))")
            },
            myActor: .a,
            switchSlots: SwitchStripModel.slots([mine, theirs, fainted], active: 0),
            turnEndsAt: turnEndsAt,
            isWaitingForOpponent: false,
            onChoose: { _ in }, onSwitch: { _ in }, onForfeit: {})
    }

    /// 창 하나에 필드 + 선택 패널 + 옆 로그가 다 들어가야 한다. 넘치면 팝오버에서 겪은 클리핑(#9)을
    /// 창에서 다시 겪는다 — 이번엔 스크롤도 없어(defect-log 의 중첩 ScrollView 금지) 그냥 잘린다.
    func testTheArenaFitsTheBattleWindowBudget() {
        let width = renderedWidth(arena(), proposing: BattleFieldMetrics.windowWidth)
        XCTAssertLessThanOrEqual(width, BattleFieldMetrics.windowWidth)
        XCTAssertLessThanOrEqual(renderedHeight(arena(), proposingWidth: BattleFieldMetrics.windowWidth),
                                 BattleFieldMetrics.windowHeight)
    }

    /// PP 를 전부 쓴 배틀은 기술 4칸이 발버둥 한 칸으로 바뀐다. 그 분기가 창을 넘기면 마지막 턴에만
    /// 화면이 깨지는데, 평온한 표본만 재면 그 경로를 한 번도 밟지 않는다.
    func testTheStruggleOnlyArenaStillFitsAndStaysNoTallerThanTheNormalOne() {
        let struggling = renderedHeight(arena(allPPSpent: true),
                                        proposingWidth: BattleFieldMetrics.windowWidth)
        XCTAssertLessThanOrEqual(struggling, BattleFieldMetrics.windowHeight)
        XCTAssertLessThanOrEqual(struggling,
                                 renderedHeight(arena(), proposingWidth: BattleFieldMetrics.windowWidth) + 1,
                                 "발버둥 한 칸이 기술 4칸보다 커질 수는 없다")
    }

    /// 턴 타이머가 붙은 화면도 같은 예산 안에 있다 — 헤더에 한 줄이 더 붙는 분기다.
    /// 남은 시간이 넉넉할 때와 **다 됐을 때**를 모두 그린다: 5초 이하에서 색이 갈리는 분기가 있고,
    /// 넉넉한 마감만 재면 그 경로를 한 번도 밟지 않는다.
    func testTheArenaWithATurnDeadlineFitsWhetherTimeIsLeftOrNot() {
        for deadline in [Date(timeIntervalSinceNow: 3_600), Date(timeIntervalSince1970: 0)] {
            XCTAssertLessThanOrEqual(
                renderedHeight(arena(turnEndsAt: deadline), proposingWidth: BattleFieldMetrics.windowWidth),
                BattleFieldMetrics.windowHeight, "마감 \(deadline) 에서 창을 넘긴다")
        }
    }

    /// 한쪽이 쓰러진 마지막 프레임도 같은 예산이다 — 스프라이트가 흐려지는 분기를 밟는다.
    func testTheArenaFitsWithAFaintedCombatantOnTheField() {
        XCTAssertLessThanOrEqual(
            renderedHeight(arena(theirHP: 0), proposingWidth: BattleFieldMetrics.windowWidth),
            BattleFieldMetrics.windowHeight)
    }

    /// 로그가 길어져도(배틀 후반) 창 높이는 그대로다 — 고정 높이 칸이라야 창이 안 흔들린다.
    func testALongLogDoesNotGrowTheWindow() {
        XCTAssertEqual(renderedHeight(arena(logLines: 4), proposingWidth: BattleFieldMetrics.windowWidth),
                       renderedHeight(arena(logLines: 200), proposingWidth: BattleFieldMetrics.windowWidth),
                       accuracy: 1, "로그 줄 수가 창 높이를 흔들면 매 턴 창이 뛴다")
    }

    /// 안 A 를 고른 근거를 테스트로 남긴다 — 이 배치는 팝오버 332pt 에 애초에 들어가지 않는다.
    /// 이 대조군이 없으면 위의 fit 검증은 "애초에 통과할 조건" 이었는지 알 수 없다.
    ///
    /// **팝오버 폭을 제안하고 잰다.** 넉넉한 폭(4,000)을 제안하면 유연한 칸이 그 값을 그대로
    /// 되돌려 주므로 어떤 구현이든 통과한다 — 좁은 폭을 제안했을 때도 더 요구하는지가 실제 질문이다.
    func testTheSameArenaDoesNotFitThePopoverContentWidth() {
        XCTAssertGreaterThan(renderedWidth(arena(), proposing: PopoverMetrics.contentWidth),
                             PopoverMetrics.contentWidth,
                             "팝오버 폭에 들어간다면 전용 창을 만든 이유가 없다")
    }

    /// defect-log 규칙: 배틀 화면에 세로 스크롤 컨테이너를 두면 안쪽이 스크롤되지 않고 잘린다.
    /// 기억이 아니라 기계로 막는다 — 배틀 뷰 파일에 그 컨테이너가 다시 들어오면 여기서 실패한다.
    ///
    /// **주석은 세지 않는다.** 규칙을 설명하는 문장에 그 타입 이름이 들어가는 건 당연하고, 그것까지
    /// 세면 가드가 "이 규칙을 문서화하지 말라"는 뜻이 돼 버린다. 실제 구성(`ScrollView {` / `(`)만 본다.
    func testTheBattleFieldSourceHasNoScrollView() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        for file in ["Sources/PokeTokenBar/UI/BattleField.swift",
                     "Sources/PokeTokenBar/UI/BattleWindow.swift"] {
            let source = try String(contentsOf: root.appendingPathComponent(file), encoding: .utf8)
            let code = source.split(separator: "\n", omittingEmptySubsequences: false)
                .map { line -> String in
                    guard let comment = line.range(of: "///") ?? line.range(of: "//") else { return String(line) }
                    return String(line[line.startIndex..<comment.lowerBound])
                }
                .joined(separator: "\n")
            XCTAssertFalse(code.contains("ScrollView {") || code.contains("ScrollView("),
                           "\(file): 배틀 화면은 고정 높이 칸으로 그린다 — 중첩 스크롤은 잘린다(defect-log)")
        }
    }
}
