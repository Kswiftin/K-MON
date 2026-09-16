import Foundation
import Testing
@testable import PokeTokenBar

// MARK: 포코피아 6단계 — 오늘의 날씨 (파생, 저장 0, **판정에 쓰지 않는다**)
//
// 문장을 리터럴로 기대하지 않는다(`PokopiaTownLifeTests` 머리의 규칙) — 게이트가 테스트를 영어
// 로케일로 재실행하고 문구는 다듬어질 값이다. 대신 서로 다른지, 비지 않는지, 어느 풀에서
// 나왔는지를 본다.

@Suite struct PokopiaTownWeatherTests {

    /// 한 해치 dayKey. `CompanionStore.dayKey` 와 같은 형태를 직접 만든다 — 날짜 산술을 테스트가
    /// 다시 구현하지 않으려면 문자열이 입력인 편이 낫고, 실제로 `today` 의 인자가 문자열이다.
    private func keys(month: Int, days: Int) -> [String] {
        (1...days).map { String(format: "2026-%02d-%02d", month, $0) }
    }

    /// **눈은 겨울만이다.** 세 계절을 다 돈다 — 한 계절만 돌리면 필터를 `season == .summer` 로
    /// 잘못 써도 통과한다.
    @Test func snowOnlyFallsInWinter() {
        for season in [MemoryHomeSeason.spring, .summer, .autumn] {
            let drawn = keys(month: 6, days: 28).map { TownWeather.today(dayKey: $0, season: season) }
            #expect(!drawn.contains(.snow), "\(season) 에 눈이 왔다")
        }
        let winter = keys(month: 1, days: 31).map { TownWeather.today(dayKey: $0, season: .winter) }
        #expect(winter.contains(.snow), "겨울 한 달에 눈이 한 번도 안 왔다")
    }

    /// 풀 크기: 겨울만 다섯이다.
    @Test func thePoolIsFourOutsideWinterAndFiveInWinter() {
        #expect(TownWeather.allowed(in: .winter).count == TownWeather.allCases.count)
        for season in [MemoryHomeSeason.spring, .summer, .autumn] {
            #expect(TownWeather.allowed(in: season).count == TownWeather.allCases.count - 1)
            #expect(!TownWeather.allowed(in: season).contains(.snow))
        }
    }

    /// 다섯 전부가 서로 다른 접두를 낸다 — 빠진 날씨는 다른 날씨의 문장을 물려받는다
    /// (`testEveryTerrainHasItsOwnSettledSentence` 와 같은 가드). **다섯 case 를 전부 밟는다** —
    /// 하나만 읽으면 나머지 넷이 커버리지에 `^0` 으로 남는다.
    @Test func everyWeatherHasItsOwnPrefix() {
        var seen: [String: TownWeather] = [:]
        for weather in TownWeather.allCases {
            let text = weather.prefix
            #expect(!text.trimmingCharacters(in: .whitespaces).isEmpty, "\(weather): 접두가 비었다")
            #expect(text.hasSuffix("."), "\(weather): 마침표로 끝나지 않는다 — 뒤 문장과 붙는다: \(text)")
            if let twin = seen[text] { Issue.record("\(weather) 와 \(twin) 이 같은 접두를 쓴다: \(text)") }
            seen[text] = weather
        }
        #expect(seen.count == TownWeather.allCases.count)
    }

    /// 같은 날은 같은 날씨다 — 창을 여닫을 때마다 날씨가 바뀌면 마을이 불안해 보인다.
    @Test func theSameDayKeyAlwaysYieldsTheSameWeather() {
        let answers = Set((0..<20).map { _ in TownWeather.today(dayKey: "2026-09-16", season: .autumn) })
        #expect(answers.count == 1, "같은 dayKey 가 다른 날씨를 냈다")
        // 빈 키(있을 수 없는 입력)도 크래시하지 않는다 — 합이 0이면 시드가 상수일 뿐이고 풀은
        // 비지 않는다. 첨자 계산이 풀 밖으로 나가지 않는 것을 여기서 한 번 밟는다.
        #expect(TownWeather.allowed(in: .spring).contains(TownWeather.today(dayKey: "", season: .spring)))
    }

    /// 한 계절 안에서 풀의 모든 날씨가 실제로 나온다 — 한 종만 나오는 추첨은 표가 죽은 것이다.
    @Test func everyWeatherAppearsWithinItsSeason() {
        let winter = Set(keys(month: 1, days: 31).map { TownWeather.today(dayKey: $0, season: .winter) })
        #expect(winter.count == TownWeather.allowed(in: .winter).count, "겨울 한 달에 안 나온 날씨가 있다: \(winter)")
        let summer = Set(keys(month: 6, days: 30).map { TownWeather.today(dayKey: $0, season: .summer) })
        #expect(summer.count == TownWeather.allowed(in: .summer).count, "여름 한 달에 안 나온 날씨가 있다: \(summer)")
    }

    /// **회전하지 않는다.** 인접한 dayKey 는 스칼라 합이 1 만큼 다르므로, 섞지 않고 `% 4` 하면
    /// 날씨가 매일 한 칸씩 도는 순환이 되고 사용자는 사흘이면 그것을 읽는다. 임계값은 절반이다 —
    /// 실측은 섞으면 4/29, 안 섞으면 26/29 라 그 사이가 넓다.
    @Test func theWeatherDoesNotRotateInLockstep() {
        let pool = TownWeather.allowed(in: .summer)          // 여름 = 네 종 고정
        let drawn = keys(month: 6, days: 30).map { TownWeather.today(dayKey: $0, season: .summer) }
        var steps = 0
        for (previous, next) in zip(drawn, drawn.dropFirst()) {
            guard let before = pool.firstIndex(of: previous), let after = pool.firstIndex(of: next) else {
                Issue.record("풀 밖의 날씨가 뽑혔다: \(previous) → \(next)"); continue
            }
            if (after - before + pool.count) % pool.count == 1 { steps += 1 }
        }
        #expect(steps <= 14, "날씨가 매일 한 칸씩 도는 회전이다(\(steps)/\(drawn.count - 1)) — 섞지 않고 나눈 값이다")
    }
}
