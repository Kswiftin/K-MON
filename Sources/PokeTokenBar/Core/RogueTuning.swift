import Foundation

/// 웨이브 런의 밸런스 손잡이를 한자리에 모은 값. 앱은 `.standard` 하나만 쓰고, 시뮬레이터
/// (`scripts/rogue-sim.sh`)가 이 값을 흔들어 판을 수백 번 돌려 최적값을 찾는다.
///
/// 손잡이를 상수로 흩어 두면 실험할 때마다 코어를 고쳐 다시 컴파일해야 하고, 그러면 **잰 판과
/// 나가는 판이 같은 규칙이라는 보장이 사라진다.** 값만 바꿔 끼우는 구조라야 실험 결과를 그대로
/// `.standard` 에 옮길 수 있다.
struct RogueTuning: Sendable, Equatable {
    /// 판의 마지막 웨이브. 12 는 한 판이 너무 빨리 끝나 강화가 쌓이기 전에 판이 닫혔다 —
    /// 보스가 7번(4·8·…·28) 오고 최종 30 이 여덟 번째 관문이라, 회복 지점과 종족값 구간이
    /// 함께 늘어난다.
    var finalWave = 30
    /// 보스 주기 — 이 배수 웨이브가 보스다.
    var bossEvery = 4
    /// 야생이 파티 레벨 기준선보다 몇 아래에 서는가 — 첫 웨이브와 마지막 웨이브 값. 사이는 선형이다.
    /// 판이 뒤로 갈수록 좁히면 난이도가 우상향한다. 폭이 끝까지 같으면 보스만 사납고 야생 웨이브는
    /// 통째로 공짜가 된다(실측: 웨이브 5–7 의 조건부 사망률이 0.000 이었다).
    var wildLevelHandicapStart = 3
    var wildLevelHandicapEnd = 0
    /// 보스가 기준선보다 몇 위에 서는가(최종 웨이브 제외).
    var bossLevelBonus = 2
    /// 최종 보스가 기준선보다 몇 위에 서는가. 보통 보스보다 **높게** 둔다 — 같은 값이면 30 웨이브
    /// 관문이 8 웨이브 관문과 같은 높이라, 판의 마지막이 그냥 여덟 번째 보스가 된다.
    var finalLevelBonus = 4
    /// 첫 구간·마지막 구간의 종족값 합 상한. 사이 구간은 선형으로 잇는다 — 웨이브 수가 바뀌어도
    /// 구간 수만 늘고 오르는 폭이 저절로 완만해진다.
    var firstTierCap = 320
    var lastTierCap = 500
    /// 보스 웨이브가 자기 구간 상한에 더 받는 값.
    var bossStatBonus = 60
    /// 상대 종족값 하한 = 상한 × 이 비율. 없으면 최종 보스로 잉어킹(200)이 나온다.
    var minStatRatio = 0.6
    /// 상대가 둘이 될 확률의 **분모**. 8 이면 야생 웨이브의 1/8 이 둘이다(PokeRogue 와 같은 값).
    /// 0 이면 항상 둘이다.
    var doubleDenominator = 8
    /// 보스 웨이브의 분모. 야생보다 크게(확률을 낮게) 두는 이유는 보스가 종족값 상한을 올린
    /// 한 마리로 서는 벽이기 때문이다 — 둘이 되면 관문이 아니라 사고가 된다.
    var bossDoubleDenominator = 32
    /// 한 판에 주는 몬스터볼.
    var ballsPerRun = 5
    /// 볼 소지 상한. 보상(`ballPouch`)으로 채워도 이 위로는 안 간다 — 상한이 없으면 후반에 볼이
    /// 남아돌아 포획이 자원 판단이 아니라 클릭이 된다. 상한에 닿으면 보상 목록에서도 빠진다.
    var ballCap = 9
    /// 볼 보상 한 장이 채워 주는 개수.
    var ballsPerPouch = 2
    /// 파티 상한.
    var partyLimit = 6
    /// 보스를 넘을 때 채워 주는 HP — **최대치의 비율**이다. 1.0(완전 회복)이면 보스 직후의 판이
    /// 늘 만피에서 다시 시작해, 이월 자원(HP)을 아낀 판과 다 쓴 판이 같은 자리에 선다.
    /// 이미 이 비율보다 높으면 깎지 않는다(회복이지 정규화가 아니다).
    var bossHealRatio = 0.7
    /// 일반 승리·보스 승리로 오르는 레벨.
    var levelGain = 2
    var bossLevelGain = 3

    static let standard = RogueTuning()

    /// 이 웨이브의 야생 핸디캡.
    func wildHandicap(wave: Int) -> Int {
        guard finalWave > 1 else { return wildLevelHandicapStart }
        let progress = Double(min(wave, finalWave) - 1) / Double(finalWave - 1)
        let span = Double(wildLevelHandicapEnd - wildLevelHandicapStart)
        return Int((Double(wildLevelHandicapStart) + span * progress).rounded())
    }

    /// 이 웨이브가 속한 구간(1부터)과 전체 구간 수.
    func tierIndex(wave: Int) -> (index: Int, count: Int) {
        let count = max(1, Int(ceil(Double(finalWave) / Double(bossEvery))))
        let index = min(count, max(1, Int(ceil(Double(wave) / Double(bossEvery)))))
        return (index, count)
    }

}
