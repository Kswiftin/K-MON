import Foundation

/// 마을의 오늘 날씨 — **문구 전용**이다.
///
/// 저장 필드가 없다(`PokopiaTownLife` 와 같은 원칙). `dayKey` 에서 파생하므로 같은 날은 창을 몇 번
/// 열어도 같은 날씨이고, 자정을 넘기면 바뀐다.
///
/// **판정에 쓰지 않는다.** 비 오는 날 물 문턱을 낮추면 서식 판정이 날짜마다 흔들려 "내가 만들어서
/// 왔다" 가 깨진다 — 지형을 민 사람이 원인이라는 것이 이 기능의 전부인데, 그 인과가 날씨라는
/// 우연에 덮인다. 그래서 이사·문턱·정원·레벨·복합·전설은 이 타입을 읽지 않는다.
///
/// `Hasher`·`hashValue` 를 **쓸 수 없다** — Swift 의 해시는 프로세스마다 시드가 달라 앱을
/// 재시작하면 같은 날의 답이 바뀐다(`MemoryHomeCompanionTrace` 가 스칼라 합을 쓰는 이유와 같다).
///
/// 파일 이름이 `Pokopia` 로 시작하는 것은 취향이 아니다 — 조사 가드(`PokopiaParticleGuardTests`)가
/// 그 접두를 가진 파일만 훑는다.
enum TownWeather: Sendable, Hashable, CaseIterable {
    case clear, cloudy, rain, wind, snow

    /// 그 계절에 올 수 있는 날씨. **눈은 겨울만이다** — 한여름에 눈이 오면 파생 날씨가 거짓으로
    /// 읽힌다. 계절은 이미 `PokopiaTownLife.line` 의 인자라 새 입력이 없다.
    nonisolated static func allowed(in season: MemoryHomeSeason) -> [TownWeather] {
        season == .winter ? allCases : allCases.filter { $0 != .snow }
    }

    /// 오늘의 날씨. 스칼라 합을 **그대로 나누지 않고** `SplitMix64` 를 한 번 돌린다 — 인접한
    /// dayKey 는 합이 1 만큼 다르므로 `% 4` 가 곧 맑음→구름→비→바람이 매일 한 칸씩 도는 회전이
    /// 되고, 사용자는 사흘이면 그 순환을 읽는다(2026-06 30일 모사에서 회전 26/29, 섞은 뒤 4/29).
    /// `MemoryHomeCompanionTrace` 가 합을 그대로 쓰는 것은 "약 4일에 1번" 이 곧 의도였기 때문이다.
    ///
    /// `RaidBoss.seed(dayKey:)` 를 부르지 않는다. 같은 시드 계열을 공유하면 오늘의 보스와 오늘의
    /// 날씨가 상관을 갖는다 — RaidBoss 가 키에 접미를 붙여 피하는 부류다(`RaidBoss.swift:258-259`).
    nonisolated static func today(dayKey: String, season: MemoryHomeSeason) -> TownWeather {
        let pool = allowed(in: season)
        var rng = SplitMix64(seed: dayKey.unicodeScalars
            .reduce(UInt64(0x9E37_79B9_7F4A_7C15)) { $0 &* 31 &+ UInt64($1.value) })
        return pool[Int(rng.next() % UInt64(pool.count))]
    }

    /// 마을 한 줄 **앞**에 붙는 조각. 다섯 전부에 답이 있어야 한다(전수 `switch`).
    ///
    /// **지형·주민을 말하지 않는다.** 뒤에 오는 문장이 그 자리의 주인이고, 여기서 "물가에 비가" 를
    /// 말하면 물 0칸 마을이 없는 물가를 가리킨다(1단계가 고친 부류). 마침표로 끝난다 — 뒤 문장과
    /// 공백 하나로 이어진다.
    var prefix: String {
        switch self {
        case .clear:  "하늘이 맑아요."
        case .cloudy: "구름이 낮게 깔렸어요."
        case .rain:   "비가 내려요."
        case .wind:   "바람이 불어요."
        case .snow:   "눈이 내려요."
        }
    }
}
