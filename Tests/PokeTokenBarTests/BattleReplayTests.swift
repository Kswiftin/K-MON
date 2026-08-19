import XCTest
@testable import PokeTokenBar

/// 재생 애니메이션의 **큐 로직** (계획 §6 Phase 7, §9 PR 5). 애니메이션 자체는 UI라 단위 테스트가
/// 얕으므로, 계획대로 큐를 순수 함수로 분리해 그쪽만 겨냥한다 — 스텝 수·재생 시간 상한·끄기 모드·
/// 입력 잠김, 그리고 **재생 중 HP 가 엔진과 같은 값으로 수렴하는가**.
///
/// 마지막 항목이 이 파일의 핵심이다. 지금 화면은 턴이 해상되면 HP 가 즉시 최종값으로 튀는데,
/// 중간 프레임을 만들려면 "각 스텝 시점의 HP" 를 따로 계산해야 한다. 그 계산이 엔진과 어긋나면
/// 바가 엉뚱한 데서 멈춘다 — 그래서 기대값을 손으로 적지 않고 **실제 엔진을 돌려서** 대조한다.
final class BattleReplayTests: XCTestCase {

    // MARK: 고정 재료

    private func mon(_ types: [PokemonType] = [.normal], hp: Int = 100, spe: Int = 100,
                     name: String = "탱커") -> BattleSnapshot {
        BattleSnapshot(speciesID: 143, name: name, trainer: nil, level: 50, nature: nil,
                       isShiny: false, types: types,
                       base: BattleStats(hp: hp, atk: 100, def: 100, spa: 100, spd: 100, spe: spe),
                       moves: [MoveSpec(id: 1, names: ["ko": "몸통박치기"], type: .normal, power: 40,
                                        damageClass: .physical, accuracy: 100, pp: 35)])
    }

    /// 한 턴을 실제로 해상해 (이벤트, 엔진이 끝낸 HP) 를 얻는다. 재생 결과를 대조할 정답이다.
    private func resolvedTurn(seed: UInt64 = 7) -> (events: [BattleEvent], a: BattleSide, b: BattleSide) {
        var a = BattleSide(mon(name: "선공"))
        var b = BattleSide(mon(name: "후공"))
        var rng = SplitMix64(seed: seed)
        let move = a.move(at: 0)
        let events = BattleEngine.resolveTurn(a: &a, b: &b, moveA: move, moveB: move,
                                              turn: 1, rng: &rng)
        return (events, a, b)
    }

    // MARK: 스텝 — 이벤트 N개 → 스텝 N개

    /// 이벤트 하나가 스텝 하나다. 접거나 건너뛰면 로그(이벤트마다 한 줄로 접히는 `BattleLog`)와
    /// 재생이 서로 다른 개수를 세게 되고, 로그를 재생 진행도만큼 잘라 보여 줄 수 없다.
    func testEveryEventBecomesExactlyOneStepInOrder() {
        let turn = resolvedTurn()
        let steps = BattleReplay.steps(turn.events, from: [.a: 200, .b: 200], speed: .normal)

        XCTAssertEqual(steps.count, turn.events.count, "이벤트와 스텝 수가 어긋나면 로그를 진행도로 자를 수 없다")
        XCTAssertEqual(steps.map(\.event), turn.events, "순서가 바뀌면 급소 문구가 데미지 뒤로 간다")
    }

    /// 빈 스트림은 빈 큐다 — 재생할 게 없는데 재생 상태로 들어가면 입력이 영영 잠긴다.
    func testAnEmptyStreamProducesNoSteps() {
        XCTAssertTrue(BattleReplay.steps([], from: [.a: 100], speed: .normal).isEmpty)
    }

    // MARK: 재생 시간 — 상한이 있다

    /// 한 턴이 길어져도(혼란 자멸 + 양쪽 잔뎀 + 기절) 재생이 턴 타이머를 잡아먹으면 안 된다.
    /// 상한이 없으면 이벤트가 늘어난 만큼 재생이 길어져 상대는 그동안 기다린다.
    func testALongStreamIsCompressedIntoTheBudget() {
        let long: [BattleEvent] = (0..<40).map { _ in .damage(.b, amount: 3, cause: .move) }
        let steps = BattleReplay.steps(long, from: [.b: 500], speed: .normal)

        XCTAssertEqual(steps.count, 40, "압축이 스텝을 버리면 로그 진행도가 어긋난다")
        XCTAssertLessThanOrEqual(BattleReplay.totalDuration(steps), BattleReplay.budget + 0.001)
    }

    /// 대조군 — 짧은 턴은 압축되지 않는다. 위 검증만 있으면 "전부 0 으로 만들기" 오구현이 통과한다.
    func testAShortStreamKeepsItsFullTiming() {
        let short: [BattleEvent] = [.move(.a, moveID: 1), .damage(.b, amount: 12, cause: .move)]
        let steps = BattleReplay.steps(short, from: [.b: 100], speed: .normal)

        XCTAssertEqual(BattleReplay.totalDuration(steps),
                       short.reduce(0) { $0 + BattleReplay.duration(of: $1) }, accuracy: 0.001,
                       "예산 안에 드는 턴까지 압축하면 두 데미지가 같은 프레임에 겹쳐 보인다")
        XCTAssertGreaterThan(BattleReplay.totalDuration(steps), 0)
    }

    // MARK: 속도 — 보통 / 빠름 / 끄기

    /// **끄기는 필수다**(저전력·접근성, 계획 Phase 7). 끄면 기다림이 0 이라 결과가 즉시 보인다.
    func testTurningPlaybackOffFinishesImmediately() {
        let turn = resolvedTurn()
        let steps = BattleReplay.steps(turn.events, from: [.a: 200, .b: 200], speed: .off)

        XCTAssertEqual(steps.count, turn.events.count, "끄기여도 스텝은 남는다 — 로그·HP 는 그대로 갱신된다")
        XCTAssertEqual(BattleReplay.totalDuration(steps), 0)
    }

    /// 빠름은 보통보다 짧되 0 은 아니다 — 0 이면 "빠름" 과 "끄기" 가 같은 설정이 된다.
    func testFastIsQuickerThanNormalButStillPlays() {
        let turn = resolvedTurn()
        let normal = BattleReplay.totalDuration(BattleReplay.steps(turn.events, from: [:], speed: .normal))
        let fast = BattleReplay.totalDuration(BattleReplay.steps(turn.events, from: [:], speed: .fast))

        XCTAssertGreaterThan(fast, 0, "빠름이 0 이면 끄기와 구별되지 않는다")
        XCTAssertLessThan(fast, normal)
    }

    /// 저전력 모드에선 재생하지 않는다 — `FloatingPetController.shouldAnimate(lowPower:)` 와 같은 가드다.
    /// 설정값 자체는 건드리지 않는다(저전력이 풀리면 사용자가 고른 속도로 돌아와야 한다).
    func testLowPowerModeForcesPlaybackOff() {
        XCTAssertEqual(BattleReplay.effectiveSpeed(.normal, lowPower: true), .off)
        XCTAssertEqual(BattleReplay.effectiveSpeed(.fast, lowPower: true), .off)
        XCTAssertEqual(BattleReplay.effectiveSpeed(.normal, lowPower: false), .normal,
                       "저전력이 아니면 사용자가 고른 속도 그대로다")
    }

    // MARK: HP 투영 — 재생이 엔진과 같은 값으로 끝난다

    /// 재생이 끝난 시점의 HP 는 엔진이 계산한 HP 와 **정확히** 같아야 한다. 어긋나면 바가 엉뚱한
    /// 데서 멈추고, 다음 턴에 값이 튀면서 보정된다. 기대값을 손으로 적지 않고 엔진을 돌려서 맞춘다 —
    /// 손으로 적으면 데미지 식이 바뀔 때 이 테스트가 같이 틀린 채로 통과한다.
    func testPlaybackEndsOnExactlyTheEngineHP() {
        let turn = resolvedTurn()
        let steps = BattleReplay.steps(turn.events,
                                       from: [.a: turn.a.stats.hp, .b: turn.b.stats.hp], speed: .normal)

        XCTAssertEqual(steps.last?.hp[.a], turn.a.hp)
        XCTAssertEqual(steps.last?.hp[.b], turn.b.hp)
        XCTAssertLessThan(turn.b.hp, turn.b.stats.hp, "데미지가 0 이면 이 검증이 아무것도 안 본다")
    }

    /// 트리거 브랜치 — **오버킬**. 남은 HP 보다 큰 데미지가 오면 화면 HP 는 0 에서 멈춘다.
    /// 엔진도 `max(0, …)` 로 자른다. 자르지 않으면 바가 음수 비율이 되고 "-3/121" 같은 표기가 나온다.
    func testOverkillDamageStopsAtZeroInsteadOfGoingNegative() {
        let steps = BattleReplay.steps([.damage(.b, amount: 999, cause: .move), .faint(.b)],
                                       from: [.b: 12], speed: .normal)

        XCTAssertEqual(steps.first?.hp[.b], 0, "음수 HP 는 바 비율을 음수로 만든다")
        XCTAssertEqual(steps.last?.hp[.b], 0)
    }

    /// 잔뎀·자멸도 HP 를 깎는다 — 원인이 무엇이든 `.damage` 면 바가 움직여야 한다.
    /// 원인별로 갈라 `cause == .move` 만 반영하면 화상 데미지가 화면에서 사라진다.
    func testResidualAndSelfInflictedDamageMoveTheBarToo() {
        let steps = BattleReplay.steps([.damage(.a, amount: 15, cause: .burn),
                                        .damage(.a, amount: 10, cause: .confusion)],
                                       from: [.a: 100], speed: .normal)

        XCTAssertEqual(steps.first?.hp[.a], 85)
        XCTAssertEqual(steps.last?.hp[.a], 75)
    }

    /// 데미지가 아닌 이벤트는 HP 를 건드리지 않는다 — 상태가 걸렸다고 바가 움직이면 안 된다.
    func testNonDamageEventsLeaveTheBarWhereItWas() {
        let steps = BattleReplay.steps([.status(.b, .burn), .cant(.b, .paralysis), .turn(2)],
                                       from: [.a: 90, .b: 80], speed: .normal)

        XCTAssertEqual(steps.map { $0.hp[.b] }, [80, 80, 80])
        XCTAssertEqual(steps.map { $0.hp[.a] }, [90, 90, 90], "다른 쪽 HP 도 그대로다")
    }

    /// 여러 턴이 한꺼번에 들어와도(팝오버를 닫아 둔 사이 쌓인 스트림) 순서대로 누적된다.
    func testDamageAccumulatesAcrossSeveralTurns() {
        let steps = BattleReplay.steps([.turn(1), .damage(.b, amount: 20, cause: .move),
                                        .turn(2), .damage(.b, amount: 30, cause: .move)],
                                       from: [.b: 100], speed: .normal)

        XCTAssertEqual(steps.map { $0.hp[.b] }, [100, 80, 80, 50])
    }

    // MARK: 입력 잠김

    /// 재생 중엔 기술 버튼을 잠근다. 지금은 해상 직후 바로 다음 턴 입력이 열려서, 무엇이 일어났는지
    /// 보기 전에 다음 턴이 시작된다 — 계획 Phase 7 이 지목한 "체감되는 조잡함" 이 이것이다.
    func testInputIsLockedWhilePlayingBack() {
        XCTAssertFalse(BattleReplay.acceptsInput(isWaitingForOpponent: false, isReplaying: true))
        XCTAssertTrue(BattleReplay.acceptsInput(isWaitingForOpponent: false, isReplaying: false))
    }

    /// 기존 규칙(상대를 기다리는 동안 잠김)은 그대로다 — 재생 잠김을 넣으면서 이쪽이 풀리면
    /// 같은 턴에 두 번 보내게 된다.
    func testWaitingForTheOpponentStillLocksInput() {
        XCTAssertFalse(BattleReplay.acceptsInput(isWaitingForOpponent: true, isReplaying: false))
        XCTAssertFalse(BattleReplay.acceptsInput(isWaitingForOpponent: true, isReplaying: true))
    }

    // MARK: 문구 팝

    /// 급소·상성·빗나감은 재생 중 화면에 한 번 뜬다. 로그는 재생이 그 줄에 닿아야 나오므로,
    /// 이 팝이 없으면 급소가 화면 어디에도 안 보인 채 HP 만 크게 깎인다.
    func testOnlyTheAnnounceableEventsPopAPhrase() {
        let l = L(.ko)
        XCTAssertEqual(BattleReplay.popup(for: .crit(.b), l: l), l.battleCritical)
        XCTAssertEqual(BattleReplay.popup(for: .superEffective(.b), l: l), l.battleSuperEffective)
        XCTAssertEqual(BattleReplay.popup(for: .resisted(.b), l: l), l.battleNotVeryEffective)
        XCTAssertEqual(BattleReplay.popup(for: .miss(.a), l: l), l.battleMissed)
        XCTAssertEqual(BattleReplay.popup(for: .immune(.b), l: l), l.battleNoEffect)
    }

    /// 데미지·기술·턴에는 팝이 없다 — 전부 팝으로 만들면 화면이 문구로 덮이고, 정작 급소가 묻힌다.
    func testOrdinaryEventsDoNotPopAnything() {
        let l = L(.ko)
        XCTAssertNil(BattleReplay.popup(for: .damage(.b, amount: 12, cause: .move), l: l))
        XCTAssertNil(BattleReplay.popup(for: .move(.a, moveID: 1), l: l))
        XCTAssertNil(BattleReplay.popup(for: .turn(3), l: l))
        XCTAssertNil(BattleReplay.popup(for: .faint(.b), l: l))
    }

    /// 세 언어 모두 팝 문구가 있다 — 한 언어만 채우면 나머지 언어에서 빈 팝이 뜬다.
    func testThePopPhraseExistsInEveryLanguage() {
        for language in [AppLanguage.ko, .en, .ja] {
            let phrase = BattleReplay.popup(for: .crit(.b), l: L(language))
            XCTAssertFalse(phrase?.isEmpty ?? true, "\(language.rawValue) 에서 급소 팝이 비었다")
        }
    }

    // MARK: 맞은 쪽 (shake·flash 대상)

    /// 피격 연출은 **맞은 쪽** 스프라이트에 건다. 때린 쪽이 흔들리면 누가 맞았는지 반대로 읽힌다.
    func testTheStruckSideIsTheOneThatTakesTheDamage() {
        XCTAssertEqual(BattleReplay.struck(by: .damage(.b, amount: 12, cause: .move)), .b)
        XCTAssertEqual(BattleReplay.struck(by: .damage(.a, amount: 9, cause: .burn)), .a)
        XCTAssertNil(BattleReplay.struck(by: .move(.a, moveID: 1)), "기술을 쓴 것만으로는 아무도 안 맞는다")
        XCTAssertNil(BattleReplay.struck(by: .status(.b, .burn)))
    }
}

/// 큐를 실제로 돌리는 쪽 — 뷰가 읽는 상태(표시 HP · 재생 진행도 · 오버레이)를 시간축에 푼다.
/// 순수 큐(`BattleReplay`)가 맞아도 여기서 어긋나면 화면은 그대로 튄다.
@MainActor
final class BattleAnimatorTests: XCTestCase {

    /// 재생이 끝날 때까지 기다린다 — 고정 대기(`sleep(0.5)`)는 부하가 걸린 CI 에서 흔들린다.
    private func waitUntilIdle(_ animator: BattleAnimator, timeout: TimeInterval = 5) async {
        let deadline = Date().addingTimeInterval(timeout)
        while animator.overlay.isPlaying, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    private let oneTurn: [BattleEvent] = [
        .turn(2), .move(.a, moveID: 1), .crit(.b), .damage(.b, amount: 30, cause: .move),
    ]

    /// 팝오버를 닫아 뒀다 다시 열면 그동안 쌓인 스트림이 통째로 들어온다. 그걸 처음부터 재생하면
    /// 이미 지나간 턴을 다시 보게 되고, 그동안 입력이 잠긴다 — 첫 동기화는 **끝으로 건너뛴다**.
    func testOpeningAnInProgressBattleDoesNotReplayItsHistory() {
        let animator = BattleAnimator()
        animator.sync(events: oneTurn, hp: [.a: 100, .b: 70], speed: .normal)

        XCTAssertEqual(animator.playedCount, oneTurn.count, "이미 지나간 턴을 다시 재생하면 안 된다")
        XCTAssertFalse(animator.overlay.isPlaying, "재생 중이면 입력이 잠긴 채 화면이 열린다")
        XCTAssertEqual(animator.hp(for: .b), 70, "건너뛴 뒤의 HP 는 엔진 값 그대로다")
    }

    /// 끄기는 기다리지 않는다 — `sync` 가 돌아온 시점에 이미 끝나 있어야 한다.
    /// 비동기로 한 프레임이라도 미루면 "끄기" 인데도 입력이 한 순간 잠긴다.
    func testTurningPlaybackOffRevealsTheOutcomeWithoutWaiting() {
        let animator = BattleAnimator()
        animator.sync(events: [], hp: [.a: 100, .b: 100], speed: .off)
        animator.sync(events: oneTurn, hp: [.a: 100, .b: 70], speed: .off)

        XCTAssertEqual(animator.playedCount, oneTurn.count)
        XCTAssertFalse(animator.overlay.isPlaying)
        XCTAssertEqual(animator.hp(for: .b), 70)
    }

    /// 이 PR 의 본론 — 새 턴이 들어와도 바가 최종값으로 **튀지 않는다.** `sync` 직후엔 아직 이전
    /// HP 고, 재생이 끝나야 엔진 값에 도달한다. 로그도 같은 진행도로 잘리므로 결과가 미리 새지 않는다.
    func testANewTurnIsPlayedBackInsteadOfSnappingToTheFinalHP() async {
        let animator = BattleAnimator()
        animator.sync(events: [], hp: [.a: 100, .b: 100], speed: .normal)
        animator.sync(events: oneTurn, hp: [.a: 100, .b: 70], speed: .normal)

        XCTAssertTrue(animator.overlay.isPlaying, "재생이 시작되지 않으면 입력이 잠기지 않는다")
        XCTAssertEqual(animator.hp(for: .b), 100, "동기화 직후 최종 HP 로 튀면 재생할 게 남지 않는다")
        XCTAssertLessThan(animator.playedCount, oneTurn.count, "로그가 결과를 미리 보여 주면 안 된다")

        await waitUntilIdle(animator)

        XCTAssertEqual(animator.hp(for: .b), 70, "재생이 끝나면 엔진 값에 정확히 도달한다")
        XCTAssertEqual(animator.playedCount, oneTurn.count)
        XCTAssertFalse(animator.overlay.isPlaying, "재생이 끝났는데 잠겨 있으면 다음 턴을 고를 수 없다")
        XCTAssertNil(animator.overlay.popped, "마지막 팝 문구가 남으면 다음 턴 내내 떠 있는다")
    }

    /// 다음 배틀은 처음부터다 — 스트림이 짧아지면(새 배틀은 빈 스트림으로 시작한다) 진행도를 되돌린다.
    /// 안 되돌리면 새 배틀의 첫 턴들이 "이미 재생한 것" 으로 취급돼 화면이 멈춘 채로 있는다.
    func testStartingANewBattleForgetsTheOldOne() {
        let animator = BattleAnimator()
        animator.sync(events: oneTurn, hp: [.a: 100, .b: 70], speed: .off)
        animator.sync(events: [], hp: [.a: 120, .b: 120], speed: .off)

        XCTAssertEqual(animator.playedCount, 0)
        XCTAssertEqual(animator.hp(for: .b), 120, "새 배틀의 만피로 갈아탄다")
    }

    /// 모르는 쪽(멀티의 다른 참가자 등)을 물으면 nil 이다 — 0 을 돌려주면 뷰가 쓰러진 것처럼 그린다.
    func testAnUnknownSideHasNoDisplayHP() {
        let animator = BattleAnimator()
        animator.sync(events: [], hp: [.a: 100], speed: .off)

        XCTAssertNil(animator.hp(for: .b))
    }
}

/// 재생 속도 설정 — 저장과 문구. 끄기가 필수라(저전력·접근성) 설정 표면에 실제로 노출돼야 한다.
final class ReplaySpeedSettingTests: XCTestCase {

    /// 기본값은 보통이고, 고른 값은 앱을 다시 켜도 남는다.
    func testTheReplaySpeedDefaultsToNormalAndSurvivesARelaunch() throws {
        let suite = "kmon.replay.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let initial = AppSettings(defaults: defaults)
        XCTAssertEqual(initial.battleReplaySpeed, .normal)

        initial.battleReplaySpeed = .off
        XCTAssertEqual(AppSettings(defaults: defaults).battleReplaySpeed, .off,
                       "끄기를 고른 사용자에게 다시 켜서 애니메이션을 보여 주면 안 된다")
    }

    /// 세 속도가 세 언어에서 각각 다른 이름을 가진다 — 같은 이름 두 개면 고를 수 없다.
    func testEverySpeedIsLabelledInEveryLanguage() {
        for language in [AppLanguage.ko, .en, .ja] {
            let l = L(language)
            let names = ReplaySpeed.allCases.map { l.battleReplaySpeedName($0) }
            XCTAssertFalse(names.contains { $0.isEmpty }, "\(language.rawValue) 에 빈 이름이 있다")
            XCTAssertEqual(Set(names).count, ReplaySpeed.allCases.count,
                           "\(language.rawValue) 에서 두 속도의 이름이 같다")
            XCTAssertFalse(l.battleReplaySpeedLabel.isEmpty)
        }
    }
}
