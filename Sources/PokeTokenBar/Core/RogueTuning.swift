import Foundation

/// 웨이브 런의 밸런스 손잡이를 한자리에 모은 값. 앱은 `.standard` 하나만 쓰고, 시뮬레이터
/// (`scripts/rogue-sim.sh`)가 이 값을 흔들어 판을 수백 번 돌려 최적값을 찾는다.
///
/// 손잡이를 상수로 흩어 두면 실험할 때마다 코어를 고쳐 다시 컴파일해야 하고, 그러면 **잰 판과
/// 나가는 판이 같은 규칙이라는 보장이 사라진다.** 값만 바꿔 끼우는 구조라야 실험 결과를 그대로
/// `.standard` 에 옮길 수 있다.
struct RogueTuning: Sendable, Equatable {
    /// 판의 마지막 웨이브.
    var finalWave = 12
    /// 보스 주기 — 이 배수 웨이브가 보스다.
    var bossEvery = 4
    /// 야생이 파티 레벨 기준선보다 몇 아래에 서는가.
    var wildLevelHandicap = 3
    /// 보스가 기준선보다 몇 위에 서는가(최종 웨이브 제외).
    var bossLevelBonus = 0
    /// 최종 보스가 기준선보다 몇 위에 서는가.
    var finalLevelBonus = 2
    /// 첫 구간·마지막 구간의 종족값 합 상한. 사이 구간은 선형으로 잇는다 — 웨이브 수가 바뀌어도
    /// 구간 수만 늘고 오르는 폭이 저절로 완만해진다.
    var firstTierCap = 320
    var lastTierCap = 500
    /// 보스 웨이브가 자기 구간 상한에 더 받는 값.
    var bossStatBonus = 60
    /// 상대 종족값 하한 = 상한 × 이 비율. 없으면 최종 보스로 잉어킹(200)이 나온다.
    var minStatRatio = 0.6
    /// 상대가 둘이 되는 지점 — 판 진행률. 1.0 을 넘기면 끝까지 한 마리다.
    var doubleOpponentFrom = 0.75
    /// 한 판에 주는 몬스터볼.
    var ballsPerRun = 5
    /// 파티 상한.
    var partyLimit = 6
    /// 일반 승리·보스 승리로 오르는 레벨.
    var levelGain = 2
    var bossLevelGain = 3

    static let standard = RogueTuning()

    /// 이 웨이브가 속한 구간(1부터)과 전체 구간 수.
    func tierIndex(wave: Int) -> (index: Int, count: Int) {
        let count = max(1, Int(ceil(Double(finalWave) / Double(bossEvery))))
        let index = min(count, max(1, Int(ceil(Double(wave) / Double(bossEvery)))))
        return (index, count)
    }

    /// 상대가 둘이 되는 첫 웨이브. 진행률로 두는 이유는 웨이브 수를 늘려도 "후반부터 둘"이라는
    /// 뜻이 유지되게 하기 위해서다.
    var doubleOpponentWave: Int {
        max(1, Int(ceil(Double(finalWave) * doubleOpponentFrom)))
    }
}
