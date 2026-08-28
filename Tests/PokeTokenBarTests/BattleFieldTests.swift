import XCTest
import SwiftUI
@testable import PokeTokenBar

/// 배틀 필드 + 선택 패널 (계획 §6 Phase 6·8, §9 PR 4). 기전은 건드리지 않는다 — 화면만이다.
///
/// UI 는 컴파일과 단위 테스트를 통과하면서 화면에서 깨진다(defect-log). 그래서 여기 있는 테스트는
/// 뷰의 모양을 베끼지 않고 **뷰가 읽는 순수 결정**을 겨냥한다 — 색 임계, 표기 규칙, PP 단계,
/// 스프라이트 URL, 그리고 레이아웃 예산. 뷰 자체는 `NSHostingController.sizeThatFits` 로 폭·높이를 잰다.
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
            .sizeThatFits(in: CGSize(width: proposing, height: .greatestFiniteMagnitude)).width
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
        XCTAssertEqual(tints.count, 8)
        XCTAssertEqual(Set(tints).count, 7, "독·맹독만 같은 색을 공유한다")
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
        XCTAssertEqual(slots.map(\.index), [0, 1, 2], "인덱스가 곧 교체 대상이다 — 어긋나면 다른 포켓몬이 나온다")
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

    // MARK: 팝오버 예산 (계획 §6.3 안 B — 기존 팝오버 안에 압축)

    /// 배틀 탭이 쓸 수 있는 세로 자리. 팝오버는 `tabHeight` 780pt 한 장을 모든 탭이 나눠 쓰고, 그중
    /// 패딩·업데이트 배너·트레이너 바·집중 타이머·탭 피커·푸터가 먼저 가져간다(`PopoverView.mainContent`).
    /// 홈 탭 예산 주석의 실측(560pt 창에서 뷰포트 약 250pt → 크롬 약 310pt)을 그대로 780 에 옮기면
    /// 약 470pt 가 남는다. 폰트·OS 차이를 감당할 30pt 를 떼고 **440pt** 를 예산으로 쓴다.
    ///
    /// 이 값을 넘기면 팝오버가 스크롤이 아니라 **클리핑**으로 처리한다(#9) — 배틀 화면은 defect-log
    /// 규칙상 자기 `ScrollView` 를 둘 수 없으니, 넘친 만큼은 볼 방법이 없어진다.
    private static let battleViewportBudget: CGFloat = 440

    /// 예산을 재는 표본. **최악 케이스로 채운다** — 상태 배지 두 개, 이로치 별표, 기절한 교체 슬롯,
    /// 양쪽 actor 의 로그 줄. 평온한 표본으로 재면 화면에서만 나타나는 분기를 한 번도 밟지 못한다.
    private func arena(logLines: Int = BattleFieldMetrics.logLines,
                       allPPSpent: Bool = false,
                       turnEndsAt: Date? = nil,
                       theirHP: Int? = nil,
                       language: AppLanguage = .ko,
                       overlay: ReplayOverlay = .idle,
                       stagesOnEverySide: Bool = false) -> BattleArenaView {
        var theirs = BattleSide(mon([.fire, .flying], name: "상대이름이제법긴트레이너"))
        theirs.hp = theirHP ?? theirs.stats.hp / 3
        theirs.status = .burn
        theirs.confusionTurns = 3
        theirs.changeStage(.def, by: -2)          // 랭크 화살표도 최악 케이스에 든다
        theirs.changeStage(.accuracy, by: -1)
        var mine = BattleSide(mon([.water], name: "내 포켓몬", shiny: true))
        mine.changeStage(.atk, by: 2)
        mine.changeStage(.spe, by: 1)
        mine.pp = allPPSpent ? mine.pp.map { _ in 0 } : [1, mine.pp[1], mine.pp[2], 0]
        var fainted = BattleSide(mon([.grass], name: "기절"))
        fainted.hp = 0
        if stagesOnEverySide {
            // 일곱 축이 전부 붙은 상태 — 고대의힘 부류가 한 기술로 다섯 축을 올리므로 실제로 가능하다.
            for stat in BattleStat.allCases {
                mine.changeStage(stat, by: 6)
                theirs.changeStage(stat, by: -6)
            }
        }
        return BattleArenaView(
            mine: mine, theirs: theirs,
            myTitle: "내 포켓몬", theirTitle: "상대 트레이너",
            l: L(language), turn: 7,
            logLines: (0..<logLines).map {
                BattleLog.Line(actor: $0.isMultiple(of: 2) ? .a : .b,
                               text: "탱커의 몸통박치기! 상대는 12 데미지를 받았다 (\($0))")
            },
            myActor: .a,
            switchSlots: SwitchStripModel.slots([mine, theirs, fainted], active: 0),
            turnEndsAt: turnEndsAt,
            isWaitingForOpponent: false,
            overlay: overlay,
            onChoose: { _ in }, onSwitch: { _ in }, onForfeit: {})
    }

    /// 재생 중 화면도 같은 예산이다 — 급소 문구가 뜨고 한쪽이 흔들리는 그 프레임이다.
    /// 팝 문구가 자리를 **차지하면** 재생될 때마다 아래 기술 버튼이 밀려 내려가 잘린다.
    /// 세 언어를 다 재는 이유는 문구 길이가 언어마다 다르기 때문이다(영어 CI 에서만 넘친 전례가 있다).
    func testTheArenaKeepsItsBudgetWhileAPhraseIsPoppedOnTheField() {
        for language in [AppLanguage.ko, .en, .ja] {
            let playing = ReplayOverlay(isPlaying: true, hit: .b, popped: .crit(.b))
            let height = renderedHeight(arena(language: language, overlay: playing),
                                        proposingWidth: PopoverMetrics.contentWidth)
            XCTAssertLessThanOrEqual(height, Self.battleViewportBudget,
                                     "\(language.rawValue) 재생 프레임이 예산을 넘긴다")
            XCTAssertEqual(height,
                           renderedHeight(arena(language: language), proposingWidth: PopoverMetrics.contentWidth),
                           accuracy: 1,
                           "\(language.rawValue): 팝 문구가 레이아웃을 밀면 재생 중에만 버튼이 내려간다")
        }
    }

    /// 배틀 탭 전체가 팝오버 콘텐츠 폭과 세로 예산 안에 들어간다. 넘치면 NSPopover 가 스크롤이 아니라
    /// 잘라 낸다(#9) — 기술 버튼이나 푸터가 화면 밖으로 사라지는 그 증상이다.
    func testTheArenaFitsThePopoverBudget() {
        XCTAssertLessThanOrEqual(renderedWidth(arena(), proposing: PopoverMetrics.contentWidth),
                                 PopoverMetrics.contentWidth, "가로가 넘치면 오른쪽이 잘린다")
        XCTAssertLessThanOrEqual(renderedHeight(arena(), proposingWidth: PopoverMetrics.contentWidth),
                                 Self.battleViewportBudget, "세로가 넘치면 아래가 잘린다")
    }

    /// 넉넉한 폭을 줘도 팝오버 폭 이상은 **요구하지 않는다.** 좁은 폭에서만 재면 유연한 칸이 제안을
    /// 그대로 받아들여 통과하므로, 실제로 그 폭에 맞춰 설계됐는지는 이쪽에서만 드러난다.
    func testTheArenaNeverAsksForMoreWidthThanThePopoverGives() {
        XCTAssertLessThanOrEqual(renderedWidth(arena(), proposing: 4_000), PopoverMetrics.contentWidth,
                                 "이상 폭에서 더 요구하면 팝오버에선 매번 압축돼 그려진다")
    }

    /// 랭크가 일곱 축 전부 붙어도 HP바 칸은 자기 폭을 넘겨 요구하지 않는다. 고대의힘 부류가 한
    /// 기술로 다섯 축을 올리므로 실제로 가능한 상태다. 넘겨 요구하면 팝오버가 배틀 화면 전체를
    /// 압축해 그려서, 잘리는 건 화살표가 아니라 옆 칸이 된다.
    func testAFullyBoostedFieldStillFitsThePopover() {
        var side = BattleSide(mon([.water], name: "랭크덩어리"))
        for stat in BattleStat.allCases { side.changeStage(stat, by: stat == .evasion ? -6 : 6) }
        XCTAssertEqual(StageReadout.text(side.stages)?.split(separator: " ").count, 7,
                       "일곱 축이 모두 표기되는 표본이어야 이 검증이 최악 케이스다")

        // HP바 칸도 필드도 **자기 폭·높이를 스스로 정하지 않는다**(`Spacer`·그라데이션이 제안을
        // 그대로 받는다). 예산은 `BattleArenaView` 의 `frame(maxWidth:)` 와 필드의 `frame(height:)`
        // 가 정하므로, 재는 대상은 화면 전체여야 한다.
        let boosted = arena(stagesOnEverySide: true)
        XCTAssertLessThanOrEqual(renderedWidth(boosted, proposing: 4_000), PopoverMetrics.contentWidth,
                                 "화살표가 칸을 밀어내면 팝오버가 배틀 화면 전체를 압축해 그린다")
        XCTAssertLessThanOrEqual(renderedHeight(boosted, proposingWidth: PopoverMetrics.contentWidth),
                                 Self.battleViewportBudget,
                                 "화살표가 줄을 늘리면 아래 기술 버튼이 잘린다")
    }

    /// 안 B 가 로그를 필드 **아래**로 내린 근거 — Showdown 처럼 옆에 두면 332pt 에 들어가지 않는다.
    /// 이 대조군이 없으면 위의 fit 검증이 "애초에 통과할 조건" 이었는지 알 수 없다.
    func testALogBesideTheFieldWouldNotFitThePopoverWidth() {
        let sideBySide = HStack(spacing: 8) {
            arena()
            VStack(alignment: .leading) {
                ForEach(0..<4, id: \.self) { _ in Text("탱커의 몸통박치기! 12 데미지").font(.system(size: 9)) }
            }
            .frame(width: 202)
        }
        XCTAssertGreaterThan(renderedWidth(sideBySide, proposing: 4_000), PopoverMetrics.contentWidth,
                             "옆 로그가 332pt 에 들어간다면 아래로 내릴 이유가 없다")
    }

    /// PP 를 전부 쓴 배틀은 기술 4칸이 발버둥 한 칸으로 바뀐다. 그 분기가 예산을 넘기면 마지막 턴에만
    /// 화면이 깨지는데, 평온한 표본만 재면 그 경로를 한 번도 밟지 않는다.
    func testTheStruggleOnlyArenaStillFitsAndStaysNoTallerThanTheNormalOne() {
        let struggling = renderedHeight(arena(allPPSpent: true),
                                        proposingWidth: PopoverMetrics.contentWidth)
        XCTAssertLessThanOrEqual(struggling, Self.battleViewportBudget)
        XCTAssertLessThanOrEqual(struggling,
                                 renderedHeight(arena(), proposingWidth: PopoverMetrics.contentWidth) + 1,
                                 "발버둥 한 칸이 기술 4칸보다 커질 수는 없다")
    }

    /// 턴 타이머가 붙은 화면도 같은 예산 안에 있다 — 헤더에 한 줄이 더 붙는 분기다.
    /// 남은 시간이 넉넉할 때와 **다 됐을 때**를 모두 그린다: 5초 이하에서 색이 갈리는 분기가 있고,
    /// 넉넉한 마감만 재면 그 경로를 한 번도 밟지 않는다.
    func testTheArenaWithATurnDeadlineFitsWhetherTimeIsLeftOrNot() {
        for deadline in [Date(timeIntervalSinceNow: 3_600), Date(timeIntervalSince1970: 0)] {
            XCTAssertLessThanOrEqual(
                renderedHeight(arena(turnEndsAt: deadline), proposingWidth: PopoverMetrics.contentWidth),
                Self.battleViewportBudget, "마감 \(deadline) 에서 예산을 넘긴다")
        }
    }

    /// 최대 HP 가 0 이하로 계산되는 스냅샷(손상 세이브·적대적 피어의 종족값)이 와도 HP바가 0 으로
    /// 나누지 않는다. `HPTier` 쪽 가드는 이미 검증했지만 바 자체의 비율 계산은 다른 코드라,
    /// 이 케이스를 그리지 않으면 그 분기가 `--show-regions` 에서 `^0` 으로 남는다.
    func testTheHPBarSurvivesASnapshotWhoseMaximumComputesToZero() {
        let broken = BattleSnapshot(speciesID: 1, name: "손상", trainer: nil, level: 1, nature: nil,
                                    isShiny: false, types: [.normal],
                                    base: BattleStats(hp: -9_999, atk: 1, def: 1, spa: 1, spd: 1, spe: 1),
                                    moves: fourMoves)
        let side = BattleSide(broken)
        XCTAssertLessThanOrEqual(side.stats.hp, 0, "이 케이스를 만들지 못하면 아래 검증이 분기를 안 밟는다")
        XCTAssertEqual(HPReadout.ratio(hp: side.hp, max: side.stats.hp), 0,
                       "0 나눗셈은 NaN 폭이 되고, NaN 프레임은 레이아웃을 무너뜨린다")
        let bar = CombatantBar(side: side, title: "손상", l: L(.ko), revealsExactHP: true)
        XCTAssertGreaterThan(renderedHeight(bar, proposingWidth: BattleFieldMetrics.barWidth), 0)
    }

    /// HP바 비율은 0…1 로 잘린다 — 와이어로 최대치보다 큰 HP 가 와도 바가 칸을 넘지 않는다.
    func testTheHPBarRatioIsClampedToItsTrack() {
        XCTAssertEqual(HPReadout.ratio(hp: 84, max: 121), 84.0 / 121.0, accuracy: 0.0001)
        XCTAssertEqual(HPReadout.ratio(hp: 200, max: 100), 1, "최대를 넘겨 오면 꽉 찬 바로 잘린다")
        XCTAssertEqual(HPReadout.ratio(hp: -5, max: 100), 0, "음수 HP 는 빈 바다")
        XCTAssertEqual(HPReadout.ratio(hp: 50, max: 0), 0)
    }

    /// 한쪽이 쓰러진 마지막 프레임도 같은 예산이다 — 스프라이트가 흐려지는 분기를 밟는다.
    func testTheArenaFitsWithAFaintedCombatantOnTheField() {
        XCTAssertLessThanOrEqual(
            renderedHeight(arena(theirHP: 0), proposingWidth: PopoverMetrics.contentWidth),
            Self.battleViewportBudget)
    }

    /// 로그가 길어져도(배틀 후반) 탭 높이는 그대로다. 팝오버는 고정 높이라 늘어난 만큼이 잘리고,
    /// 잘리는 쪽은 아래에 있는 기술 버튼이다 — 로그가 길어질수록 조작이 사라지는 셈이 된다.
    func testALongLogDoesNotGrowTheTab() {
        XCTAssertEqual(renderedHeight(arena(logLines: 4), proposingWidth: PopoverMetrics.contentWidth),
                       renderedHeight(arena(logLines: 200), proposingWidth: PopoverMetrics.contentWidth),
                       accuracy: 1, "로그 줄 수가 높이를 흔들면 후반 턴에 버튼이 잘린다")
    }

    /// 로그 칸이 자기가 그리는 줄 수를 담을 만큼 높은가. 고정 높이 칸은 내용이 넘쳐도 **보고하는
    /// 높이가 그대로**라, 위의 예산 검증은 줄 수를 늘려도 전부 통과한다(실제로 40줄을 주입했을 때
    /// 아무 테스트도 실패하지 않았다). 넘친 줄은 칸 밖에 그려져 아래 기술 버튼 위에 겹친다.
    func testTheLogBoxIsTallEnoughForTheLinesItDraws() {
        // 기술 줄은 타입색 칩(아이콘 + 이름 + 기술명 + 데미지 + 배지)이라 일반 텍스트 한 줄보다
        // 위아래 패딩이 붙는다 — 이 칩이 실제로 그리는 가장 높은 줄이므로 예산도 이걸로 잰다.
        let richLine = BattleLog.Line(actor: .a, text: "", actorName: "탱커", moveType: .fighting,
                                      moveDamageClass: .physical, moveDisplayName: "몸통박치기",
                                      damage: 12, badges: ["효과가 굉장했다!"])
        let oneLine = renderedHeight(BattleLogRow(line: richLine, isMine: true),
                                     proposingWidth: PopoverMetrics.contentWidth)
        func needed(lines: Int) -> CGFloat {
            oneLine * CGFloat(lines) + 2 * CGFloat(lines - 1) + 10   // 줄 + 줄간격 + 위아래 패딩
        }
        XCTAssertLessThanOrEqual(needed(lines: BattleFieldMetrics.logLines), BattleFieldMetrics.logHeight,
                                 "\(BattleFieldMetrics.logLines)줄이 \(BattleFieldMetrics.logHeight)pt 칸에 안 들어간다 — 넘친 줄이 버튼 위에 그려진다")
        // 대조군: 줄 수를 늘리면 이 가드가 실제로 깨진다. 이게 없으면 "지금 값이 우연히 맞았을 뿐"
        // 인지 알 수 없다 — 실제로 40줄을 주입했을 때 다른 어떤 테스트도 실패하지 않았다.
        XCTAssertGreaterThan(needed(lines: 40), BattleFieldMetrics.logHeight,
                             "대조군이 안 넘치면 위 검증이 무의미해진다")
    }

    /// 세 언어 어디서도 예산을 넘기지 않는다. 한국어 이름이 짧아 로컬에선 통과하고 영어로 도는 CI 에서만
    /// 넘치는 회귀를 기술 목록에서 이미 겪었다(CI 118pt vs 로컬 78pt).
    func testTheArenaFitsInEveryLanguage() {
        for language in [AppLanguage.ko, .en, .ja] {
            XCTAssertLessThanOrEqual(
                renderedHeight(arena(language: language), proposingWidth: PopoverMetrics.contentWidth),
                Self.battleViewportBudget, "\(language.rawValue) 에서 예산을 넘긴다")
            XCTAssertLessThanOrEqual(
                renderedWidth(arena(language: language), proposing: 4_000), PopoverMetrics.contentWidth,
                "\(language.rawValue) 에서 폭을 더 요구한다")
        }
    }

    /// 예산 검증은 **자리를 얼마나 차지하는가**만 본다 — 아무것도 그리지 않는 뷰도 전부 통과한다.
    /// 그래서 한 번은 실제로 래스터화해 색이 여러 개 나오는지 본다(defect-log: UI 결함은 컴파일과
    /// 단위 테스트를 통과한다).
    ///
    /// `KMON_SNAPSHOT_DIR` 이 있으면 그 폴더에 PNG 로도 떨어뜨린다 — 사람이 눈으로 확인할 때 쓴다.
    /// CI 는 그 변수를 두지 않으므로 파일을 만들지 않는다.
    func testTheArenaActuallyRastersSomethingRatherThanABlankBox() throws {
        let bounds = CGRect(x: 0, y: 0,
                            width: PopoverMetrics.contentWidth, height: Self.battleViewportBudget)
        let rep = try XCTUnwrap(raster(arena(), in: bounds))

        var seen = Set<String>()
        for x in stride(from: 4, to: Int(bounds.width) - 4, by: 12) {
            for y in stride(from: 4, to: Int(bounds.height) - 4, by: 8) {
                guard let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                seen.insert(String(format: "%.2f-%.2f-%.2f",
                                   color.redComponent, color.greenComponent, color.blueComponent))
            }
        }
        XCTAssertGreaterThan(seen.count, 8, "배틀 화면이 사실상 단색이다 — 자리는 잡았는데 그린 게 없다")

        if let dir = ProcessInfo.processInfo.environment["KMON_SNAPSHOT_DIR"],
           let png = rep.representation(using: .png, properties: [:]) {
            try png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("battle-arena.png"))
            // 재생 프레임도 같이 떨군다 — 팝 문구와 피격 스프라이트는 정지 화면에서만 눈으로
            // 확인할 수 있고, 예산 테스트는 자리만 볼 뿐 무엇이 그려졌는지는 보지 않는다.
            let playing = ReplayOverlay(isPlaying: true, hit: .b, popped: .crit(.b))
            try raster(arena(overlay: playing), in: bounds)?
                .representation(using: .png, properties: [:])?
                .write(to: URL(fileURLWithPath: dir).appendingPathComponent("battle-arena-replay.png"))
        }
    }

    /// 창을 띄우지 않는 오프스크린 래스터. 색 검증과 PNG 떨구기가 같은 경로를 쓴다 —
    /// 두 벌로 두면 한쪽만 손봐서 "눈으로 본 그림" 과 "테스트가 본 그림" 이 갈라진다.
    private func raster(_ view: some View, in bounds: CGRect) -> NSBitmapImageRep? {
        let controller = NSHostingController(rootView: view)
        controller.view.frame = bounds
        controller.view.layoutSubtreeIfNeeded()
        guard let rep = controller.view.bitmapImageRepForCachingDisplay(in: bounds) else { return nil }
        controller.view.cacheDisplay(in: bounds, to: rep)
        return rep
    }

    /// 전투 본문에는 중첩 스크롤을 두지 않되, 채팅의 고정 높이 이력에는 내부 스크롤을 허용한다.
    ///
    /// **주석은 세지 않는다.** 규칙을 설명하는 문장에 그 타입 이름이 들어가는 건 당연하고, 그것까지
    /// 세면 가드가 "이 규칙을 문서화하지 말라"는 뜻이 돼 버린다. 실제 구성(`ScrollView {` / `(`)만 본다.
    func testOnlyTheFixedHeightChatHistoryUsesScrollView() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("Sources/PokeTokenBar/UI/BattleField.swift"), encoding: .utf8)
        XCTAssertTrue(source.contains("struct BattleChatPanel"))
        XCTAssertTrue(source.contains("ScrollView {"))
        XCTAssertTrue(source.contains(".frame(height: 82)"), "채팅 이력은 고정 높이 내부에서만 스크롤한다")
    }

    /// 문서용 캡처도 실제 SwiftUI 렌더러로 만든다. `KMON_SNAPSHOT_DIR` 을 주면 사람이 검토할 PNG를
    /// 남기고, 평소 CI에서는 파일 시스템에 흔적을 남기지 않는다.
    func testBattleChatPanelKeepsHistoryInsideItsFixedViewportAndRasters() throws {
        let me = UUID(), other = UUID()
        let messages = (0..<BattleChatPolicy.historyLimit).map { index in
            BattleChatMessage(senderID: index.isMultiple(of: 2) ? me : other,
                              senderName: index.isMultiple(of: 2) ? "나" : "Misty",
                              body: "채팅 메시지 \(index + 1)", sentAt: .distantPast)
        }
        let panel = BattleChatPanel(configuration: BattleChatConfiguration(
            messages: messages, mySenderID: me, isEnabled: true, unavailableMessage: nil,
            l: L(.ko), onSend: { _ in }))
        let bounds = CGRect(x: 0, y: 0, width: PopoverMetrics.contentWidth, height: 158)
        // 문서 이미지도 앱의 밝은 팝오버 바탕에서 읽히게 만든다.
        let screenshot = ZStack { Color.white; panel.padding(8) }.preferredColorScheme(.light)
        let rep = try XCTUnwrap(raster(screenshot, in: bounds))
        XCTAssertLessThanOrEqual(renderedHeight(panel, proposingWidth: PopoverMetrics.contentWidth), bounds.height,
                                 "50개 이력도 내부 스크롤 밖으로 패널을 키우면 안 된다")
        if let dir = ProcessInfo.processInfo.environment["KMON_SNAPSHOT_DIR"],
           let png = rep.representation(using: .png, properties: [:]) {
            try png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("screenshot-battle-chat.png"))
        }
    }
}
