import Foundation

/// 웨이브 런의 실적 — **판이 끝난 뒤 남는 것은 이것 하나다.** 강화·파티·잡은 포켓몬은 런과 함께
/// 사라지고(그게 밸런스를 언제든 고칠 수 있는 근거다), 남기는 것은 "어디까지 갔나"뿐이다.
///
/// 재화를 주지 않는다. 별의조각·도감을 붙이면 반복 플레이가 경제와 도감 집계를 흔들어, 지금 무제한인
/// 하루 판 수를 다시 제한해야 한다 — 실적만 남기면 그 결정을 건드리지 않는다.
struct RunProgress: Codable, Sendable, Equatable {
    /// 가장 멀리 간 웨이브. 클리어했으면 최종 웨이브다.
    var bestWave = 0
    /// 최종 웨이브까지 넘긴 판 수.
    var clears = 0
    /// 끝까지 간 판 수 — **시작한 판이 아니라 끝난 판**이다. 시작으로 세면 화면만 열고 닫은 판이
    /// 실패로 쌓여 클리어율이 실제보다 낮게 보인다.
    var finished = 0

    init() {}

    /// 필드가 늘어난 뒤의 옛 세이브를 기본값으로 읽는다 — 디코드 실패로 실적 전체를 버리면
    /// 업데이트 당일에 기록이 사라진다(`DungeonProgress` 와 같은 이유).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        bestWave = try c.decodeIfPresent(Int.self, forKey: .bestWave) ?? 0
        clears = try c.decodeIfPresent(Int.self, forKey: .clears) ?? 0
        finished = try c.decodeIfPresent(Int.self, forKey: .finished) ?? 0
    }

    /// 끝난 판 하나를 적는다. **최고 기록은 내려가지 않는다** — 실패한 판이 앞선 기록을 지우면
    /// 기록이 "마지막 판"이 되고, 그건 최고 기록이 아니다.
    mutating func record(reachedWave: Int, cleared: Bool) {
        finished += 1
        bestWave = max(bestWave, reachedWave)
        if cleared { clears += 1 }
    }

    /// 신뢰경계 정규화 — 손편집·다른 기기에서 온 값을 여기서 자른다. 상한이 최종 웨이브인 이유는
    /// 그보다 큰 값이 화면에 "13/12" 로 나오기 때문이다.
    mutating func normalize() {
        bestWave = min(max(0, bestWave), RogueRun.finalWave)
        clears = max(0, clears)
        finished = max(0, finished)
        // 클리어한 판은 끝난 판의 부분집합이고, 클리어했으면 최고 기록은 최종 웨이브다.
        clears = min(clears, finished)
        if clears > 0 { bestWave = RogueRun.finalWave }
    }

    /// 무결성 서명에 들어가는 문자열. 재화가 나가지 않아도 서명에 넣는다 — 자랑 기록은 고쳐 적을
    /// 이유가 있는 값이고, 조건부로 붙이므로 기본값 세이브의 구서명은 그대로 유효하다.
    var canonical: String { "\(bestWave)|\(clears)|\(finished)" }

    /// 두 기기의 실적을 합친다 — 각 축의 **큰 값**을 쓴다. 실적은 소모되지 않는 누적이라
    /// 한쪽을 고르면 다른 기기에서 세운 기록이 사라진다.
    static func merged(_ a: RunProgress, _ b: RunProgress) -> RunProgress {
        var merged = RunProgress()
        merged.bestWave = max(a.bestWave, b.bestWave)
        merged.clears = max(a.clears, b.clears)
        merged.finished = max(a.finished, b.finished)
        merged.normalize()
        return merged
    }
}
