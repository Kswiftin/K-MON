import XCTest
@testable import PokeTokenBar

/// 집중 프리셋(마일스톤 1) — 길이 목록·휴식 연동·보상 단조성을 고정한다.
///
/// 이 셋이 한 파일에 있는 이유: 길이를 넓히는 변경은 셋을 **동시에** 어긋나게 한다. 25분 미만
/// 구간이 생기면 (a) 대화 도구가 화면에 없는 길이를 켤 수 있고 (b) 휴식이 5분에 묶여 있고
/// (c) 짧은 세션을 반복하는 게 시간당 보상에서 유리해진다.
@MainActor
final class FocusPresetTests: XCTestCase {

    // MARK: 목록

    /// 프리셋 자기 길이는 반드시 자기 자신으로 접힌다. 이게 깨지면 화면에서 고른 값과 실제
    /// 시작되는 세션이 다른 프리셋이 된다.
    func testEveryPresetFoldsBackToItselfFromItsOwnLength() {
        for preset in FocusPreset.allCases {
            XCTAssertEqual(FocusPreset.nearest(toMinutes: preset.minutes), preset, "\(preset.minutes)분")
        }
    }

    /// 화면 피커와 `pokedoro.start` 는 **같은 목록 한 벌**을 본다. 갈라지면 화면이 제시하지 않는
    /// 길이를 대화만 켤 수 있다 — `PokemonChatTools` 의 목록 계약이 그래서 있다.
    func testThePickerAndTheChatToolOfferTheSameLengths() {
        XCTAssertEqual(PokemonChatTool.focusMinutes, FocusPreset.allCases.map(\.minutes))
        XCTAssertEqual(PokemonChatTool.focusMinutes, [15, 20, 25, 50, 90])
    }

    /// 프롬프트 한 줄이 실제 목록을 광고해야 한다. 목록만 넓히고 프롬프트가 옛 셋을 말하면
    /// 모델은 새 길이를 영영 모른다.
    func testThePromptAdvertisesEveryOfferedLength() {
        let line = PokemonChatTool.pokedoroStart.promptLine
        XCTAssertTrue(line.contains("15|20|25|50|90"), line)
    }

    // MARK: 휴식 연동

    /// 집중이 끝나면 휴식은 **그 프리셋의** 길이로 시작한다. 5분 고정이던 동안 90분 세션 뒤에도
    /// 5분만 쉬었다.
    func testTheRestPeriodFollowsThePresetOfTheSessionThatJustEnded() {
        let start = Date(timeIntervalSince1970: 1_000)
        for preset in FocusPreset.allCases {
            let timer = FocusTimer()
            timer.startFocus(minutes: preset.minutes, now: start)
            let focusEnd = start.addingTimeInterval(TimeInterval(preset.minutes * 60))
            timer.tick(now: focusEnd)

            XCTAssertEqual(timer.phase, .rest, "\(preset.minutes)분")
            XCTAssertEqual(timer.remaining(at: focusEnd), TimeInterval(preset.restMinutes * 60),
                           "\(preset.minutes)분 세션의 휴식")
        }
    }

    /// 대화로 시작한 세션도 같은 휴식을 받는다. 버튼 경로에만 연동을 붙이면 대화로 시작한
    /// 90분 세션만 5분 휴식으로 남는다.
    func testASessionStartedFromChatGetsTheSameRest() async {
        let store = makeStore()
        await store.hatch(baseID: 25)
        let timer = FocusTimer()

        // 대화 경로는 시작 시각을 인자로 받지 않는다(실제 `Date()`). 그래서 tick 도 실제 시각
        // 기준으로 미래를 준다 — 고정 시각을 주면 이미 지난 시각이라 tick 이 아무 일도 안 한다.
        XCTAssertTrue(timer.startFocusSession(minutes: 90, companion: store))
        timer.tick(now: Date().addingTimeInterval(91 * 60))

        XCTAssertEqual(timer.phase, .rest)
        XCTAssertEqual(timer.restMinutes, 15)
    }

    // MARK: 보상 — 짧게 쪼개는 게 유리하면 안 된다

    /// **시간당** 기대 보상은 세션이 길수록 크거나 같아야 한다. 알 확률이 25분 미만에서 평평하면
    /// 15분을 네 번 도는 게 25분을 2.4번 도는 것보다 유리해져, 프리셋이 집중 도구가 아니라
    /// 파밍 경로가 된다.
    func testShorterPresetsAreNeverAMoreEfficientWayToFarm() {
        func perHour(_ perSession: Double, minutes: Int) -> Double {
            perSession * (60.0 / Double(minutes))
        }
        let ordered = FocusPreset.allCases.sorted { $0.minutes < $1.minutes }
        for (shorter, longer) in zip(ordered, ordered.dropFirst()) {
            let eggShort = perHour(Double(FocusRewardRules.eggChanceBasisPoints(minutes: shorter.minutes)),
                                   minutes: shorter.minutes)
            let eggLong = perHour(Double(FocusRewardRules.eggChanceBasisPoints(minutes: longer.minutes)),
                                  minutes: longer.minutes)
            XCTAssertLessThanOrEqual(eggShort, eggLong, "알 확률 \(shorter.minutes)분 → \(longer.minutes)분")

            let fragShort = perHour(Double(FocusRewardRules.eggFragments(minutes: shorter.minutes)),
                                    minutes: shorter.minutes)
            let fragLong = perHour(Double(FocusRewardRules.eggFragments(minutes: longer.minutes)),
                                   minutes: longer.minutes)
            XCTAssertLessThanOrEqual(fragShort, fragLong, "조각 \(shorter.minutes)분 → \(longer.minutes)분")

            let dustShort = perHour(Double(AdventureRules.amounts(minutes: shorter.minutes).starPieces),
                                    minutes: shorter.minutes)
            let dustLong = perHour(Double(AdventureRules.amounts(minutes: longer.minutes).starPieces),
                                   minutes: longer.minutes)
            XCTAssertLessThanOrEqual(dustShort, dustLong, "별의조각 \(shorter.minutes)분 → \(longer.minutes)분")
        }
    }

    /// 기존 세 길이의 보상은 **한 톨도** 바뀌지 않는다. 새 구간을 넣으면서 옛 구간을 같이
    /// 건드리면 쓰던 사람의 경제가 조용히 달라진다.
    func testTheThreeOriginalLengthsKeepTheirExactRewards() {
        XCTAssertEqual(FocusRewardRules.eggChanceBasisPoints(minutes: 25), 100)
        XCTAssertEqual(FocusRewardRules.eggChanceBasisPoints(minutes: 50), 300)
        XCTAssertEqual(FocusRewardRules.eggChanceBasisPoints(minutes: 90), 700)
        XCTAssertEqual(FocusRewardRules.eggFragments(minutes: 25), 1)
        XCTAssertEqual(FocusRewardRules.eggFragments(minutes: 50), 3)
        XCTAssertEqual(FocusRewardRules.eggFragments(minutes: 90), 6)
    }

    /// 25분 미만은 조각을 주지 않는다. 계단을 그대로 두면 15분에도 1개가 나가 시간당 4개가 된다
    /// (25분은 2.4개).
    func testSessionsShorterThanTheClassicLengthEarnNoFragments() {
        XCTAssertEqual(FocusRewardRules.eggFragments(minutes: 15), 0)
        XCTAssertEqual(FocusRewardRules.eggFragments(minutes: 20), 0)
        XCTAssertEqual(FocusRewardRules.eggFragments(minutes: 24), 0)
    }

    /// 모험 정산이 실제로 그 규칙을 쓴다. 순수 함수만 고치고 정산이 옛 계단을 그대로 쓰면
    /// 테스트는 통과하는데 지갑은 안 바뀐다.
    func testTheAdventureClaimUsesTheFragmentRule() async {
        let clock = TestClock()
        let store = makeStore(clock: clock.closure)
        await store.hatch(baseID: 25)
        XCTAssertTrue(store.startFocusAdventure(minutes: 15))
        clock.advance(15 * 60)

        let reward = store.claimAdventure()

        XCTAssertNotNil(reward)
        // 하루 첫 모험 보너스 +1 은 길이와 무관하게 붙는다 — 15분 몫이 0이어야 총 1개다.
        XCTAssertEqual(reward?.eggFragments, 1)
    }

    // MARK: fixture

    private func makeStore(clock: @escaping () -> Date = { Date(timeIntervalSince1970: 1_000) }) -> CompanionStore {
        let line = EvoLine(baseID: 25, tree: EvoNode(speciesID: 25, children: []), rarity: .common,
                           names: [25: ["ko": "피카츄", "en": "Pikachu"]])
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("focus-preset-\(UUID().uuidString).json")
        let store = CompanionStore(provider: FocusPresetLineProvider(evoLine: line), clock: clock,
                                   fileURL: url, rng: SeededRNG(seed: 1))
        store.setLanguage(.ko)
        return store
    }
}

private struct FocusPresetLineProvider: PokeProviding {
    let evoLine: EvoLine
    func line(baseSpeciesID: Int) async throws -> EvoLine { evoLine }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [BaseSpecies(id: evoLine.baseID, captureRate: 255)] }
}
