import Foundation

/// 런 전용 강화. **세이브에 남지 않는다** — 런이 끝나면 파티와 함께 사라진다.
/// 그래서 무결성 서명·경제(별의조각)에 전혀 닿지 않고, 밸런스를 고쳐도 세이브 이전이 없다.
///
/// 두 부류다 — **소모형**은 그 자리에서 파티 값을 되돌리고 사라지고, **지속형**(`isPersistent`)은
/// `RunBoosts` 에 쌓여 판이 끝날 때까지 남는다. 지속형이 없던 프로토타입은 매 웨이브의 선택이
/// "회복 타이밍" 하나였고, 그래서 12 웨이브가 첫 웨이브와 같은 모양으로 끝났다.
enum RunModifier: String, CaseIterable, Codable, Sendable {
    /// 살아 있는 전원 최대 HP 의 40% 회복.
    case potion
    /// 쓰러진 하나를 최대 HP 의 50% 로 되살린다.
    case revive
    /// 파티 전원 레벨 +2.
    case candy
    /// 파티 전원 PP 전부 회복.
    case elixir
    /// 파티 전원 상태이상·혼란 해제.
    case cleanse
    /// 지속 — 선두의 첫 타입 기술 데미지 +20%(중첩).
    case typeBoost
    /// 지속 — 급소 단계 +1(중첩).
    case focusLens
    /// 지속 — 턴 끝에 최대 HP 의 1/16 회복(중첩).
    case leftovers
    /// 몬스터볼 보충.
    case ballPouch
    /// 지속 — 파티 공격/방어/스피드 +10%(중첩).
    case xAttack
    case xDefense
    case xSpeed

    /// 판이 끝날 때까지 쌓이는가. 뽑기가 **매번 최소 한 장**을 이 부류에서 뽑는다.
    var isPersistent: Bool {
        switch self {
        case .potion, .revive, .candy, .elixir, .cleanse, .ballPouch: return false
        case .typeBoost, .focusLens, .leftovers,
             .xAttack, .xDefense, .xSpeed:                            return true
        }
    }

    /// 이 판 상태에서 뽑힐 **가중치**. 0 이면 목록에 오르지 않는다.
    ///
    /// 균등 추첨이던 시절엔 쓰러진 개체가 없는데 기력의조각이, 만피에 상처약이 떴다. 3장 중 한두
    /// 장이 죽은 칸이면 고르는 일이 선택이 아니라 소거법이 된다. PokeRogue 도 같은 자리를 가중치
    /// 함수로 막는다 — 부활은 기절 수, 회복은 다친 수, 볼은 소지 상한에 걸어 필요 없으면 0 이다
    /// (`src/modifier/init-modifier-pools.ts`).
    ///
    /// 상한을 3마리에서 자르는 이유는 파티 크기다. 자르지 않으면 6마리를 채운 후반에 회복류가
    /// 목록을 통째로 덮어 빌드를 고를 자리가 없어진다.
    func weight(party: [BattleSide], balls: Int, ballCap: Int) -> Int {
        func capped(_ count: Int, each: Int) -> Int { min(count, 3) * each }
        switch self {
        case .potion:
            return capped(party.filter { $0.isAlive && $0.hp * 8 <= $0.stats.hp * 7 }.count, each: 3)
        case .revive:
            return capped(party.filter { !$0.isAlive }.count, each: 6)
        case .elixir:
            return capped(party.filter { side in
                guard let moves = side.snapshot.moves else { return false }
                return side.pp.indices.contains { index in
                    guard moves.indices.contains(index) else { return false }
                    let full = moves[index].pp
                    return full > 0 && side.pp[index] * 2 <= full
                }
            }.count, each: 3)
        case .cleanse:
            return capped(party.filter { $0.status != nil || $0.confusionTurns > 0 }.count, each: 3)
        case .candy:
            return 4
        case .ballPouch:
            return balls >= ballCap ? 0 : 4
        // 지속형은 판 상태와 무관하게 늘 후보다 — 빌드를 쌓는 장이라 "지금 필요한가" 로 거를 수 없다.
        case .typeBoost, .focusLens, .leftovers, .xAttack, .xDefense, .xSpeed:
            return 3
        }
    }
}

/// 다음 웨이브로 가는 길. 포켓로그가 웨이브 사이에 바이옴 갈림길을 두는 자리와 같은 역할이다 —
/// **판을 내가 골랐다는 감각**이 여기서 나온다. 길이 하나뿐이면 12 웨이브가 정해진 순서를 소화하는
/// 일이 되고, 강화 뽑기만으로는 그 감각이 생기지 않는다(뽑기는 나온 것 중에서 고르는 것이다).
enum RunRoute: String, CaseIterable, Codable, Sendable {
    /// 규칙 그대로. 상대도 보상도 기본값이다.
    case safe
    /// 상대 종족값 상한과 레벨이 오르고, 그 웨이브를 넘기면 **보상을 두 장** 고른다.
    case risky

    /// 이 길의 상대가 종족값 상한에 더 받는 값 / 레벨에 더 받는 값 / 승리 시 고르는 보상 장수.
    var statBonus: Int { self == .risky ? 40 : 0 }
    var levelBonus: Int { self == .risky ? 2 : 0 }
    var pickCount: Int { self == .risky ? 2 : 1 }
}

/// 포켓로그식 한 판. 웨이브를 하나씩 넘으며 **파티 HP·PP 가 이월**되는 것이 유일한 자원이다
/// (기존 던전의 체력 예산 100 을 대체한다).
///
/// 순수 구조체다 — 시각도 네트워크도 쓰지 않는다. 상대 스냅샷은 호출자가 만들어 넣는다
/// (`beginWave(opponents:)`). 그래야 웨이브 진행 규칙을 네트워크 없이 테스트할 수 있다.
struct RogueRun: Sendable {
    /// 문자열 raw 를 두는 이유는 저장이다(`RogueRunSave`) — 정수 순서로 적으면 case 를
    /// 하나 끼워 넣는 순간 옛 파일의 국면이 다른 국면으로 바뀐다.
    enum Stage: String, Codable, Sendable, Equatable {
        case battling
        /// 승리 직후 — 보상 3장 중 하나를 고를 때까지 멈춘다(위험한 길이었으면 두 장).
        case picking
        /// 보상을 다 고른 뒤 — 다음 웨이브로 갈 길을 고를 때까지 멈춘다.
        case routing
        /// 다음 웨이브 상대를 받는 중. 호출자가 `beginWave` 로 푼다.
        case loadingWave
        case cleared
        case failed
    }

    static let offerCount = 3
    /// 앱이 쓰는 값. 시뮬레이터는 `tuning` 을 갈아 끼워 같은 코어로 다른 밸런스를 잰다.
    static let finalWave = RogueTuning.standard.finalWave
    static let partyLimit = RogueTuning.standard.partyLimit
    static let ballsPerRun = RogueTuning.standard.ballsPerRun
    static let ballCap = RogueTuning.standard.ballCap

    /// 보스 웨이브. **마지막 웨이브는 주기와 무관하게 항상 보스다** — 주기를 늦추면(첫 보스를
    /// 파티가 커진 뒤로 미루면) 최종 웨이브가 주기에서 빗나가 판이 야생으로 끝난다.
    static func isBoss(wave: Int, tuning: RogueTuning = .standard) -> Bool {
        wave % tuning.bossEvery == 0 || wave == tuning.finalWave
    }

    /// 파티 레벨 기준선 — 스타터 5 에서 승리마다 +2. 보스의 +3 은 **세지 않는다**, 상대 레벨을
    /// 여기에 맞추므로 기준선이 실제보다 낮아야 안전하다(실제 파티는 보스를 넘을 때마다 1 더 위).
    static func partyLevelBaseline(wave: Int, tuning: RogueTuning = .standard) -> Int {
        3 + tuning.levelGain * wave
    }

    /// 야생이 파티 기준선보다 얼마나 아래에 서는가. PokeRogue 는 웨이브 1 에 레벨 2 야생을
    /// 레벨 5 스타터에게 붙인다(`baseLevel = 1 + wave/2 + (wave/25)^2`, `src/battle.ts`) —
    /// 플레이어가 처음부터 위에 서고 적은 웨이브당 0.5 씩만 오른다.
    static let wildLevelHandicap = RogueTuning.standard.wildLevelHandicapStart

    /// 상대 레벨 — 야생은 파티 기준선 아래, 보스는 기준선, 최종만 그 위다.
    ///
    /// 예전 식은 야생을 기준선과 같은 레벨에 두었다. PokeRogue 는 파티가 최대 6마리인데도 적을
    /// 늘 아래에 두는데, 우리는 파티가 **한 마리로 시작**해 그 여유가 더 필요하다.
    static func opponentLevel(wave: Int, route: RunRoute = .safe,
                              tuning: RogueTuning = .standard) -> Int {
        let baseline = partyLevelBaseline(wave: wave, tuning: tuning)
        guard isBoss(wave: wave, tuning: tuning) else {
            return baseline - tuning.wildHandicap(wave: wave) + route.levelBonus
        }
        return baseline + route.levelBonus
            + (wave == tuning.finalWave ? tuning.finalLevelBonus : tuning.bossLevelBonus)
    }

    /// 웨이브당 상대 마릿수. **진행률 임계값이 아니라 확률**이다 — 임계값은 "23 웨이브부터 늘 둘"
    /// 이라 그 지점 앞뒤가 통째로 같은 모양이 되고, 어느 웨이브가 험할지 미리 알아 판단할 것이 없다.
    /// PokeRogue 는 야생 조우마다 1/8, 보스 웨이브는 1/32 로 굴린다
    /// (`getDoubleBattleChance`, `src/battle-scene.ts:1232`) — 보스 쪽 확률이 **더 낮은** 이유는
    /// 보스가 벽 역할을 하는 한 마리여야 하기 때문이다. 최종 웨이브는 그쪽도 항상 한 마리다.
    ///
    /// 런 rng 를 쓰지 않고 seed 와 웨이브로 따로 뽑는다. 런 rng 는 보상 추첨과 한 흐름이라,
    /// 여기서 한 번 더 당기면 상대를 못 받아 다시 부르는 경로(`loadNextWave` 재시도)마다
    /// 보상 목록이 달라진다.
    static func opponentCount(wave: Int, seed: UInt64, tuning: RogueTuning = .standard) -> Int {
        guard wave != tuning.finalWave else { return 1 }
        let denominator = isBoss(wave: wave, tuning: tuning)
            ? tuning.bossDoubleDenominator : tuning.doubleDenominator
        guard denominator > 0 else { return 2 }
        var rng = SplitMix64(seed: seed &+ 0x9E37_79B9_7F4A_7C15 &* UInt64(wave))
        return rng.next() % UInt64(denominator) == 0 ? 2 : 1
    }

    /// 웨이브별 상대 **종족값 합(BST) 상한**. 포켓로그가 웨이브에 따라 종 티어를 올리는 것과 같은
    /// 규칙이다. 이 상한이 없으면 종을 전 범위에서 균등 추첨하는 호출자가 웨이브 1 에
    /// 슬라킹(670)·전설을 뽑아, 레벨 곡선을 아무리 맞춰도 판이 첫 턴에 끝난다.
    /// 최종 상한이 560 이라 전설 대부분(660~720)은 자연히 막히고, 따로 전설 목록을 두지 않는다.
    ///
    /// 구간은 **보스 웨이브를 포함**한다. 보스를 다음 구간으로 밀면 보스 4 가 뒤따르는 웨이브보다
    /// 세지는 톱니가 생긴다. 구간 사이는 선형으로 이어 웨이브 수를 늘리면 상승이 저절로 완만해진다.
    static func baseStatTotalCap(wave: Int, route: RunRoute = .safe,
                                 tuning: RogueTuning = .standard) -> Int {
        let (index, count) = tuning.tierIndex(wave: wave)
        let span = Double(tuning.lastTierCap - tuning.firstTierCap)
        let progress = count > 1 ? Double(index - 1) / Double(count - 1) : 1
        let tier = tuning.firstTierCap + Int((span * progress).rounded())
        let boss = isBoss(wave: wave, tuning: tuning) ? tuning.bossStatBonus : 0
        return tier + boss + route.statBonus
    }

    static func baseStatTotal(_ stats: BattleStats) -> Int {
        stats.hp + stats.atk + stats.def + stats.spa + stats.spd + stats.spe
    }

    /// 하한은 상한의 60% — 없으면 최종 보스로 잉어킹(200)이 나온다.
    static func isFairOpponent(baseStats: BattleStats, wave: Int, route: RunRoute = .safe,
                               tuning: RogueTuning = .standard) -> Bool {
        let total = baseStatTotal(baseStats)
        let cap = baseStatTotalCap(wave: wave, route: route, tuning: tuning)
        return total <= cap && total >= Int(Double(cap) * tuning.minStatRatio)
    }

    /// 야생 추첨 풀 — 획득 가능한 종 전체(1~9세대). 스프라이트 구멍은 이 목록에 없다.
    static let wildSpeciesPool = PokemonAssets.obtainableSpeciesIDs
    /// 스타터 후보 — 1·2세대 기본형 고정 풀(진화 루트 조회를 아직 안 탄다).
    static let starterPool = [1, 4, 7, 25, 152, 155, 158]
    /// 한 웨이브에서 종을 다시 뽑아 보는 횟수. 늘릴수록 PokeAPI 왕복이 그만큼 늘어난다.
    static let wildDrawAttempts = 8

    /// 웨이브에 맞는 상대 하나를 고른다. 후보를 하나씩 받아 티어에 들면 즉시 채택하고, 다 어긋나면
    /// 그중 **가장 약한 것**을 쓴다 — 판을 못 여는 것보다 낫다.
    ///
    /// 규칙이 여기 있는 이유는 **앱과 시뮬레이터가 같은 규칙을 봐야** 하기 때문이다. 화면 쪽에
    /// 두면 밸런스를 재는 판과 실제로 도는 판이 서로 다른 상대를 뽑는다.
    static func chooseOpponent(wave: Int, route: RunRoute = .safe,
                               attempts: Int = wildDrawAttempts,
                               tuning: RogueTuning = .standard,
                               next: sending () async -> BattleSnapshot?) async -> BattleSnapshot? {
        var weakest: BattleSnapshot?
        for _ in 0..<attempts {
            guard let candidate = await next() else { continue }
            if isFairOpponent(baseStats: candidate.base, wave: wave, route: route,
                              tuning: tuning) { return candidate }
            if weakest.map({ baseStatTotal($0.base) > baseStatTotal(candidate.base) }) ?? true {
                weakest = candidate
            }
        }
        return weakest
    }

    /// 포획 확률 — 본가 1세대의 HP 계수 `(3·최대 − 2·현재) / 3·최대` 에 상태이상 보정을 곱한다.
    /// 종별 `capture_rate` 는 쓰지 않는다: 웨이브별 종족값 상한이 이미 어떤 종이 나올지를 정하므로
    /// 희귀도 축을 하나 더 두면 같은 일을 두 번 하고, 종마다 `/pokemon-species` 왕복이 붙는다.
    ///
    /// 만피에서 33%, 빈사 직전에 상한 95% 다. 하한 5% 는 "절대 안 잡히는 턴"을 없애려는 값이다.
    static func catchChance(target: BattleSide) -> Double {
        let maxHP = max(1, target.stats.hp)
        let hpFactor = Double(3 * maxHP - 2 * max(0, target.hp)) / Double(3 * maxHP)
        let statusBonus: Double
        switch target.status {
        case .sleep, .freeze:                      statusBonus = 2.0
        case .paralysis, .poison, .toxic, .burn:   statusBonus = 1.5
        default:                                   statusBonus = 1.0
        }
        return min(0.95, max(0.05, hpFactor * statusBonus))
    }

    /// 승리 시 파티 전원이 오르는 레벨. 전원 같은 폭이라 교체해도 손해가 없다 — 자원은 HP 지 레벨이 아니다.
    static func levelGain(wave: Int, tuning: RogueTuning = .standard) -> Int {
        isBoss(wave: wave, tuning: tuning) ? tuning.bossLevelGain : tuning.levelGain
    }

    private(set) var wave = 1
    /// 파티 — HP·PP 가 웨이브를 넘어 유지된다.
    private(set) var party: [BattleSide]
    private(set) var stage: Stage = .battling
    private(set) var offers: [RunModifier] = []
    /// 남은 몬스터볼. 판이 끝나면 파티와 함께 사라진다.
    private(set) var balls: Int
    /// 지금까지 쌓인 지속 강화. **개체가 아니라 런이 든다** — 파티가 바뀌는 모든 경로(포획·다음
    /// 웨이브)가 `stampBoosts()` 한 곳에서 다시 도장을 받으므로, 잡은 개체만 강화 없이 싸울 일이 없다.
    private(set) var boosts = RunBoosts()
    /// 이번 웨이브를 지나온 길. 상대 생성(레벨·종족값 상한)과 승리 보상 장수를 이 값이 정한다.
    /// 첫 웨이브는 고를 기회가 없었으므로 안전한 길이다.
    private(set) var route: RunRoute = .safe
    /// 이 승리로 아직 고를 수 있는 보상 장수. 0 이 되면 길 고르기로 넘어간다.
    private(set) var remainingPicks = 0
    /// 끝난 판의 결과를 실적(`RunProgress`)에 적었나. 결과 화면은 다시 그려질 때마다 이 값을 보는데,
    /// 플래그가 없으면 팝오버를 여닫는 횟수만큼 같은 판이 실적에 쌓인다.
    private(set) var resultRecorded = false
    /// 갈림길에서 **한 번도 안전한 길을 고르지 않았나**. 업적(`dungeonSweep`)의 난이도 축이다.
    /// 첫 웨이브는 고를 기회가 없으므로 세지 않는다 — `take` 가 부른 선택만 본다.
    private(set) var tookOnlyRiskyRoutes = true
    /// 이 판이 쓰는 밸런스 값. 앱은 `.standard`, 시뮬레이터는 흔든 값을 넣는다.
    let tuning: RogueTuning
    private(set) var battle: WaveBattle
    /// 웨이브 seed·보상 추첨을 잇는 하나의 흐름. **판마다 완전 무작위로 심는다** — 날짜 결정론은
    /// 쓰지 않는다(퍼즐 던전과 다른 점이다). 하루 판 수도 제한하지 않는다: 같은 판을 다시 도는
    /// 콘텐츠가 아니라 매번 새로 뽑는 콘텐츠고, 보상이 세이브에 남지 않아 반복이 경제를 흔들지 않는다.
    private var rng: SplitMix64
    /// 판을 심은 값. rng 상태와 따로 두는 이유는 `opponentCount` 다 — 그 판정은 판이 어디까지
    /// 왔든 같은 답을 내야 하므로 소비되는 rng 상태를 볼 수 없다.
    let seed: UInt64

    init(party: [BattleSnapshot], opponents: [BattleSnapshot], seed: UInt64,
         tuning: RogueTuning = .standard) {
        self.tuning = tuning
        self.seed = seed
        self.balls = tuning.ballsPerRun
        var rng = SplitMix64(seed: seed)
        let sides = party.map(BattleSide.init)
        self.party = sides
        self.battle = WaveBattle(mine: sides,
                                 opponents: opponents.map(BattleSide.init),
                                 rng: SplitMix64(seed: rng.next()))
        self.rng = rng
    }

    // MARK: 전투 중

    /// 기술을 쓴다. `slot` 은 내 필드 칸, `target` 은 상대 필드 칸이다 — 단일전은 둘 다 0 이라
    /// 호출부가 2대2 를 몰라도 된다. 살아 있는 칸이 모두 정해지는 순간 턴이 돈다(`WaveBattle`).
    mutating func useMove(_ index: Int, fromSlot slot: Int = 0, target: Int = 0) {
        guard stage == .battling else { return }
        _ = battle.choose(.move(index: index, target: target), forSlot: slot)
        settle()
    }

    /// 살아 있는 개체를 바꾼다 — **그 칸의 행동이다**(때리지 못한다).
    mutating func switchParty(to index: Int, fromSlot slot: Int = 0) {
        guard stage == .battling else { return }
        _ = battle.choose(.switchTo(teamIndex: index), forSlot: slot)
        settle()
    }

    /// 쓰러진 칸을 벤치에서 채운다 — 턴을 쓰지 않는다(근거는 `WaveBattle.sendOut`).
    mutating func sendOut(_ index: Int, toSlot slot: Int) {
        guard stage == .battling else { return }
        _ = battle.sendOut(teamIndex: index, toSlot: slot)
        settle()
    }

    /// 전투 결과를 런으로 옮기는 **유일한 자리**. 파티 이월이 여기 한 곳이라야
    /// 어느 행동으로 이겼든 HP·PP 가 같은 규칙으로 넘어간다.
    private mutating func settle() {
        party = battle.mine
        guard let result = battle.result else { return }
        switch result {
        case .win:
            clearWave()
        case .loss, .draw:
            // 동시 전멸도 실패다 — 파티가 남지 않았으면 다음 웨이브를 설 수 없다.
            stage = .failed
        }
    }

    /// 웨이브를 넘긴 정산. **쓰러뜨려서 넘기든 잡아서 넘기든 같은 자리를 지난다** — 두 경로가
    /// 갈리면 레벨업·회복·보상 규칙이 조용히 어긋난다.
    private mutating func clearWave() {
        levelUpParty(by: Self.levelGain(wave: wave, tuning: tuning))
        // 주 상태이상(독·화상…)은 웨이브를 넘기지 않는다. 파티가 한 마리라 독 하나가 매 턴
        // 최대 HP 1/8 을 가져가고, 판이 끝날 때까지 되돌릴 수단이 사실상 없다.
        // 이월하는 자원은 HP·PP 다 — 만병통치제 보상은 전투 **중** 해제로 값이 남는다.
        clearStatus()
        // 보스를 넘으면 파티를 완전 회복한다 — 포켓로그가 10 웨이브마다 무료 회복을 주는 자리와
        // 같은 역할이다. 이월 자원이 HP·PP 뿐이라 회복 지점이 없으면 보상 3장으로는 못 메우고
        // 후반 웨이브가 "이미 진 판을 마저 두는" 소화가 된다.
        if Self.isBoss(wave: wave, tuning: tuning) { restoreParty() }
        if wave == tuning.finalWave {
            stage = .cleared
        } else {
            // 위험한 길로 왔으면 이 승리의 보상이 두 장이다 — 늘린 난이도의 값이 여기서 돌아온다.
            remainingPicks = route.pickCount
            offers = Self.drawOffers(&rng, party: party, balls: balls, tuning: tuning)
            stage = .picking
        }
    }

    // MARK: 포획

    /// 지금 볼을 던질 수 있는가. 보스는 제외한다 — 4·8·12 웨이브는 판의 관문이고 회복 지점이라
    /// 잡아서 건너뛰면 그 자리가 사라진다.
    var canThrowBall: Bool {
        // 채워야 할 빈 칸이 있으면 던질 수 없다. 이 조건이 빠져 있던 동안은 실패한 던지기가
        // **볼만 먹고 턴을 쓰지 않았다** — 그 상태에서는 `spendTurnWithoutAttacking` 이 거부되므로
        // (기절 보충 전에는 턴이 돌지 않는다) 대가 없이 던질 수 있었다.
        stage == .battling && battle.result == nil && balls > 0
            && party.count < tuning.partyLimit && !Self.isBoss(wave: wave, tuning: tuning)
            && battle.slotsNeedingSendOut.isEmpty
    }

    /// 볼을 던진다. **성공하든 실패하든 그 턴은 내 공격이 아니다** — 실패하면 상대만 움직인다.
    /// 성공하면 그 웨이브는 쓰러뜨린 것과 같은 규칙으로 넘어간다(`clearWave`).
    @discardableResult
    mutating func throwBall(atSlot slot: Int = 0) -> Bool {
        guard canThrowBall, let target = battle.opponentSide(at: slot), target.isAlive
        else { return false }
        balls -= 1
        let roll = Double(rng.next() % 10_000) / 10_000
        guard roll < Self.catchChance(target: target) else {
            _ = battle.spendTurnWithoutAttacking()
            settle()
            return false
        }
        party = battle.mine
        // 잡힌 상대는 쓰러진 것과 같은 자리를 지난다 — 상대가 더 남았으면 전투는 이어진다.
        battle.retireOpponent(atSlot: slot)
        // 정산을 먼저 지난다 — 잡힌 개체는 그 전투의 경험치를 받지 않으므로 레벨업 대상이 아니다.
        if battle.result == .win { clearWave() }
        var caught = target
        BattleEngine.prepareForSwitch(&caught)
        caught.status = nil
        caught.statusCounter = 0
        party.append(caught)
        // 전투가 이어지는 중이면 잡은 개체도 **그 자리에서 파티에 합류한다.** 런의 파티는
        // `battle.mine` 에서 다시 읽히므로(`settle`), 여기 안 넣으면 다음 행동에 조용히 사라진다.
        if battle.result == nil { battle.mine.append(caught) }
        // 잡힌 개체는 상대였으므로 강화가 없다 — 여기서 파티와 같은 도장을 받는다.
        stampBoosts()
        return true
    }

    // MARK: 보상

    /// 뽑기 3장. **적어도 한 장은 지속형이다** — 소모형만 뜨면 그 웨이브의 선택이 다시 "회복
    /// 타이밍" 하나로 접히고, 판이 12 웨이브를 지나도 첫 웨이브와 같은 모양으로 남는다.
    /// 뽑은 뒤 섞는 이유는 순서다 — 안 섞으면 첫 칸이 늘 지속형이라 목록을 읽지 않고 누르게 된다.
    static func drawOffers(_ rng: inout SplitMix64, party: [BattleSide], balls: Int,
                           tuning: RogueTuning = .standard) -> [RunModifier] {
        var pool = RunModifier.allCases.compactMap { modifier -> (RunModifier, Int)? in
            let weight = modifier.weight(party: party, balls: balls, ballCap: tuning.ballCap)
            return weight > 0 ? (modifier, weight) : nil
        }
        var persistent = pool.filter { $0.0.isPersistent }
        pool.removeAll { $0.0.isPersistent }
        var picked: [RunModifier] = []
        if let first = takeWeighted(&persistent, &rng) { picked.append(first) }
        pool += persistent
        while picked.count < offerCount, let next = takeWeighted(&pool, &rng) {
            picked.append(next)
        }
        picked.shuffle(using: &rng)
        return picked
    }

    /// 가중치에 비례해 하나를 뽑아 **풀에서 뺀다**(같은 장이 두 칸을 먹지 않게). 풀이 비면 nil 이다.
    private static func takeWeighted(_ pool: inout [(RunModifier, Int)],
                                     _ rng: inout SplitMix64) -> RunModifier? {
        let total = pool.reduce(0) { $0 + $1.1 }
        guard total > 0 else { return nil }
        var roll = Int(rng.next() % UInt64(total))
        for (index, entry) in pool.enumerated() {
            roll -= entry.1
            if roll < 0 { return pool.remove(at: index).0 }
        }
        return pool.removeLast().0
    }

    /// 보상 한 장을 고른다. 두 장을 받는 웨이브면 다음 3장을 다시 뽑아 한 번 더 멈춘다 —
    /// 같은 목록에서 두 장을 고르게 하면 두 번째 선택이 남은 것 중 최선 하나로 정해진다.
    mutating func pick(_ modifier: RunModifier) {
        guard stage == .picking, offers.contains(modifier) else { return }
        apply(modifier)
        stampBoosts()
        remainingPicks -= 1
        guard remainingPicks <= 0 else {
            offers = Self.drawOffers(&rng, party: party, balls: balls, tuning: tuning)
            return
        }
        offers = []
        stage = .routing
    }

    /// 결과를 실적에 적었다고 표시한다. 무엇을 적을지는 호출자(화면)가 정한다 — 코어는 세이브를
    /// 모르고, 알면 순수 구조체가 저장 경로를 들게 된다.
    mutating func markResultRecorded() {
        guard stage == .cleared || stage == .failed else { return }
        resultRecorded = true
    }

    /// 다음 웨이브로 갈 길을 고른다. **웨이브 번호가 오르는 자리는 여기 하나뿐이다** — 보상을
    /// 고르는 자리에서 올리면 길을 고르기 전에 상대가 만들어져, 고른 길이 다음 웨이브에 안 걸린다.
    mutating func take(_ next: RunRoute) {
        guard stage == .routing else { return }
        if next != .risky { tookOnlyRiskyRoutes = false }
        route = next
        wave += 1
        stage = .loadingWave
    }

    /// 다음 웨이브 개시 — 상대는 호출자가 만들어 넣는다(네트워크는 코어 밖).
    mutating func beginWave(opponents: [BattleSnapshot]) {
        // 살아 있는 개체가 하나도 없는 파티로는 웨이브를 열지 않는다 — 그 판은 이미 실패다.
        guard stage == .loadingWave, !opponents.isEmpty,
              party.contains(where: \.isAlive) else { return }
        // 이월하는 것은 **HP·PP·주 상태이상까지**다. 랭크·혼란·풀죽음은 전투 안에서만 사는 값이라
        // 웨이브가 바뀌면 지운다 — 안 지우면 앞 웨이브에서 울음소리로 깎인 랭크를 판이 끝날 때까지
        // 지고 가서 "웨이브를 넘길수록 이유 없이 약해진다"가 된다(교체할 때와 같은 규칙).
        for i in party.indices { BattleEngine.prepareForSwitch(&party[i]) }
        // 주 상태이상도 여기서 지운다. 승리 정산(`clearWave`)이 이미 지우지만, 웨이브 경계를
        // 지나는 자리는 여기 하나뿐이라 불변식("주 상태이상은 웨이브를 넘지 않는다")을 여기서
        // 잠근다 — 정산 뒤 파티가 바뀌는 경로(포획으로 합류한 개체)가 생겨도 규칙이 유지된다.
        clearStatus()
        // 살아 있는 개체로 필드를 세우는 것은 `WaveBattle` 의 초기화가 맡는다 — 앞 웨이브에서
        // 1번이 쓰러졌어도 쓰러진 개체가 필드에 서지 않는다.
        battle = WaveBattle(mine: party,
                            opponents: opponents.map(BattleSide.init),
                            rng: SplitMix64(seed: rng.next()))
        stampBoosts()
        stage = .battling
    }

    fileprivate mutating func apply(_ modifier: RunModifier) {
        switch modifier {
        case .potion:
            for i in party.indices where party[i].isAlive {
                party[i].hp = min(party[i].stats.hp, party[i].hp + party[i].stats.hp * 40 / 100)
            }
        case .revive:
            guard let i = party.firstIndex(where: { !$0.isAlive }) else { return }
            party[i].hp = max(1, party[i].stats.hp / 2)
        case .candy:
            levelUpParty(by: 2)
        case .elixir:
            for i in party.indices { party[i].pp = party[i].moves.map(\.pp) }
        case .cleanse:
            for i in party.indices {
                party[i].status = nil
                party[i].statusCounter = 0
                party[i].confusionTurns = 0
            }
        // 지속형은 파티 값을 건드리지 않고 `boosts` 에 쌓인다. 개체에 옮기는 것은 `stampBoosts()` 다.
        case .typeBoost:
            guard let type = boostableType else { return }
            boosts.typeDamage[type, default: 0] += 1
        case .focusLens:
            boosts.critStages += 1
        case .leftovers:
            boosts.leftovers += 1
        case .xAttack:
            boosts.attack += 1
        case .xDefense:
            boosts.defense += 1
        case .xSpeed:
            boosts.speed += 1
        case .ballPouch:
            balls = min(tuning.ballCap, balls + tuning.ballsPerPouch)
        }
    }

    /// `typeBoost` 가 올릴 타입 — **선두의 첫 타입**이다. 규칙이 코어에 있는 이유는 뽑기 화면이
    /// 고르기 전에 같은 값을 보여줘야 하기 때문이다(무엇이 올라가는지 모르고 고르면 빌드가 아니라
    /// 복권이 된다).
    var boostableType: PokemonType? {
        let lead = party.first(where: { $0.isAlive }) ?? party.first
        return lead?.snapshot.types.first
    }

    // MARK: 진화

    /// 이번 레벨에서 진화하는 자식 노드. **레벨 조건이 붙은 level-up 진화만** 본다 — 런에는 아이템·
    /// 교환·친밀도·시간대 축이 없어 그 밖의 조건은 판 안에서 만족시킬 방법이 없고, 무시하고 진화시키면
    /// 돌 없이 피카츄가 라이츄가 된다.
    ///
    /// 후보가 여럿이면 **요구 레벨이 가장 높은 것**을 쓴다. 레벨이 두 단계를 한 번에 넘겼을 때
    /// (보스 +3) 낮은 쪽을 고르면 한 웨이브에 한 단계씩만 올라 최종 형태에 영영 닿지 않는다.
    static func levelUpEvolution(from node: EvoNode, level: Int) -> EvoNode? {
        node.children
            .filter { ($0.evolutionTrigger ?? "level-up") == "level-up" }
            .filter { $0.evolutionItem == nil && $0.evolutionHeldItem == nil }
            .filter { $0.evolutionKnownMoveID == nil && $0.evolutionTimeOfDay == nil }
            .filter { $0.evolutionTradeSpeciesID == nil && $0.evolutionPartySpeciesID == nil }
            .filter { level >= ($0.evolutionLevel ?? Int.max) }
            .max { ($0.evolutionLevel ?? 0) < ($1.evolutionLevel ?? 0) }
    }

    /// 진화한다. 종 데이터는 네트워크를 지나야 하므로 **새 스냅샷은 호출자가 만들어 넣는다**
    /// (상대 생성과 같은 규칙이다). 보상 화면(`picking`)에서만 부른다 — 전투 중에 개체를 갈면
    /// 진행 중인 턴의 활성 슬롯이 다른 종으로 바뀐다.
    ///
    /// **HP 는 비율로, PP 는 만피로** 넘어간다. 레벨업과 달리 최대 HP 가 크게 뛰므로 절대값을 그대로
    /// 두면 진화가 손해처럼 보이고, 진화는 이 판의 보상이라 그렇게 남아선 안 된다. 레벨은 파티의
    /// 값으로 덮는다 — 호출자가 만든 스냅샷의 레벨이 어긋나면 유효 스탯이 통째로 달라진다.
    mutating func evolve(memberAt index: Int, into snapshot: BattleSnapshot) {
        guard stage == .picking, party.indices.contains(index) else { return }
        let old = party[index]
        var normalized = snapshot
        normalized.level = old.snapshot.level
        var next = BattleSide(normalized)
        let ratio = Double(old.hp) / Double(max(1, old.stats.hp))
        next.hp = old.isAlive ? max(1, Int((Double(next.stats.hp) * ratio).rounded())) : 0
        next.status = old.status
        next.statusCounter = old.statusCounter
        party[index] = next
        stampBoosts()
    }

    /// 파티와 진행 중인 전투 양쪽에 현재 강화를 도장 찍는다. **강화가 개체로 들어가는 자리는 여기
    /// 하나뿐이다.** 전투 쪽에 안 찍으면 이번 웨이브에는 안 걸려서 방금 고른 보상이 안 듣는 것처럼
    /// 보이고, 포획 경로가 이 자리를 안 지나면 잡은 개체만 강화 없이 싸운다.
    private mutating func stampBoosts() {
        for i in party.indices { party[i].runBoosts = boosts }
        for i in battle.mine.indices { battle.mine[i].runBoosts = boosts }
    }

    /// 파티의 주 상태이상·혼란을 지운다. **HP·PP 는 건드리지 않는다** — 그게 이월 자원이다.
    private mutating func clearStatus() {
        for i in party.indices {
            party[i].status = nil
            party[i].statusCounter = 0
            party[i].confusionTurns = 0
        }
    }

    /// 살아 있는 개체를 회복한다. **쓰러진 개체는 일으키지 않는다** — 부활은 `revive` 보상의
    /// 몫이고, 여기서 같이 살리면 그 보상이 보스 직후에 늘 꽝이 된다.
    ///
    /// HP 는 **최대치의 `bossHealRatio` 까지만** 채운다(그보다 높으면 그대로 둔다). 완전 회복이면
    /// 보스 직후마다 판이 만피에서 다시 서서, 이월 자원을 아낀 판과 다 쓴 판이 구별되지 않는다.
    /// PP·상태이상은 전부 되돌린다 — 조여야 하는 자원은 HP 하나다.
    private mutating func restoreParty() {
        for i in party.indices where party[i].isAlive {
            let floor = Int((Double(party[i].stats.hp) * tuning.bossHealRatio).rounded())
            party[i].hp = max(party[i].hp, min(party[i].stats.hp, floor))
            party[i].pp = party[i].moves.map(\.pp)
            party[i].status = nil
            party[i].statusCounter = 0
            party[i].confusionTurns = 0
        }
    }

    private mutating func levelUpParty(by amount: Int) {
        party = party.map { Self.leveledUp($0, by: amount) }
    }

    /// 레벨을 올린 개체. 유효 스탯이 다시 계산되므로 **HP 비율**로 옮긴다 — 절대값을 그대로 두면
    /// 최대치가 오른 만큼 조용히 손해가 된다. PP·상태이상은 그대로 이월한다(레벨업은 회복이 아니다).
    static func leveledUp(_ side: BattleSide, by amount: Int) -> BattleSide {
        var snapshot = side.snapshot
        snapshot.level = min(100, snapshot.level + amount)
        guard snapshot.level != side.snapshot.level else { return side }
        var next = BattleSide(snapshot)
        let ratio = Double(side.hp) / Double(max(1, side.stats.hp))
        next.hp = side.isAlive
            ? max(1, Int((Double(next.stats.hp) * ratio).rounded()))
            : 0
        next.pp = side.pp
        next.status = side.status
        next.statusCounter = side.statusCounter
        next.confusionTurns = side.confusionTurns
        // 레벨업은 스냅샷으로 개체를 다시 만든다 — 런 강화를 옮기지 않으면 사탕 한 장이 그때까지
        // 쌓은 지속 강화를 통째로 지운다(화면에는 그대로 남아 있는 것으로 보인다).
        next.runBoosts = side.runBoosts
        return next
    }
}

#if DEBUG
extension RogueRun {
    /// 테스트 전용 — 프로덕션 경로는 `useMove`/`switchParty`/`pick`/`beginWave` 뿐이다.
    mutating func debugSetParty(_ sides: [BattleSide]) { party = sides }
    mutating func debugFaint(_ index: Int) { party[index].hp = 0 }
    /// 테스트 전용 — **전투 중** 개체에 상태이상을 건다. `debugSetParty` 는 `party` 만 바꾸는데
    /// 승리 정산은 `battle.mine` 을 덮어쓰므로, 이월 규칙을 재려면 전투 쪽에 걸어야 한다.
    mutating func debugAfflict(_ status: Status) {
        battle.mine[battle.myField[0].teamIndex].status = status
    }
    mutating func debugApply(_ modifier: RunModifier) { apply(modifier) }
    /// 테스트 전용 — **전투 중** 개체를 눕힌다. `debugFaint` 는 `party` 만 바꾸는데, 필드 칸은
    /// `battle.mine` 을 보므로 기절 보충 경로를 재려면 전투 쪽을 눕혀야 한다.
    mutating func debugFaintInBattle(_ index: Int) { battle.mine[index].hp = 0 }
    /// 최종 웨이브 판정처럼 앞 웨이브를 다 밟지 않고 도달해야 하는 자리에 쓴다.
    mutating func debugJump(toWave value: Int) { wave = value }
    /// 테스트 전용 — 포획 확률을 재려면 상대 HP·볼 개수를 직접 세워야 한다.
    mutating func debugSetOpponentHP(_ value: Int, atSlot slot: Int = 0) {
        battle.opponents[battle.opponentField[slot].teamIndex].hp = value
    }
    mutating func debugSetBalls(_ value: Int) { balls = value }
    /// 테스트 전용 — 길 고르기 국면으로 바로 세운다(`take` 의 분기만 재려면 전투를 이길 필요가 없다).
    mutating func debugSetStageRouting() { stage = .routing }
    /// 테스트 전용 — 보상 화면을 원하는 목록으로 세운다. 실제로 이겨서 도달하면 뽑기가 rng 라
    /// 원하는 장이 안 뜨고, 화면 투영을 재는 테스트가 매번 다른 목록을 본다.
    mutating func debugSetStagePicking(offering list: [RunModifier]) {
        offers = list
        remainingPicks = max(1, list.count)
        stage = .picking
    }
    /// 테스트 전용 — 끝난 판의 화면을 잰다. 실제로 지려면 상대의 공격 판정이 rng 라 재현되지
    /// 않는다(전멸 판정 자체는 `WaveBattle.advanceFainted` 쪽 테스트가 든다).
    mutating func debugFail() { stage = .failed }
    /// 테스트 전용 — 강화가 쌓인 상태를 앞 웨이브를 다 밟지 않고 세운다.
    mutating func debugSetBoosts(_ value: RunBoosts) { boosts = value; stampBoosts() }
    /// 테스트 전용 — 특정 보상이 제시된 상태로 만든다(뽑기는 rng 라 원하는 장이 안 뜬다).
    mutating func debugOffer(_ modifier: RunModifier) { offers = [modifier] }
}
#endif

// MARK: - 디스크로 옮기기

extension RogueRun {
    /// 지금 판을 저장 형식으로. 무엇을 남기고 무엇을 버리는지는 `RogueRunSave` 에 적어 뒀다.
    var saveForm: RogueRunSave {
        RogueRunSave(wave: wave, stage: stage, route: route, offers: offers,
                     remainingPicks: remainingPicks, balls: balls,
                     boosts: RogueRunSave.BoostsSave(boosts), resultRecorded: resultRecorded,
                     rngState: rng.state, seed: seed, tookOnlyRiskyRoutes: tookOnlyRiskyRoutes, party: party.map(RogueRunSave.SideSave.init),
                     battle: RogueRunSave.BattleSave(battle))
    }

    /// 저장된 판을 되살린다. **되살릴 수 없으면 `nil` 이다** — 판은 소모품이라 버리는 쪽이
    /// 반쯤 복원된 전투(범위 밖 활성 칸, 웨이브 밖 진행)보다 낫다. 여기서 막는 것:
    ///
    /// - 형식 판이 다르거나 파티·전투가 비었거나 활성 칸이 범위 밖인 파일
    /// - 판 길이(`finalWave`)가 줄어든 뒤의 옛 판 — 밸런스 손잡이라 언제든 바뀐다
    /// - 고를 것이 없는 보상 화면 — 버튼 없는 화면에 갇힌다
    ///
    /// **밸런스 값은 저장하지 않는다**(`tuning` 은 언제나 `.standard`). 판 도중에 앱을 업데이트하면
    /// 남은 웨이브가 새 규칙으로 진행된다 — 옛 값을 파일에 실어 되살리면 그 판만 조용히 옛
    /// 밸런스로 도는데, 런은 기록만 남기므로 새 규칙을 따르는 편이 설명하기 쉽다.
    init?(save: RogueRunSave) {
        guard save.version == RogueRunSave.currentVersion,
              !save.party.isEmpty, save.party.count <= RogueRun.partyLimit,
              (1...RogueRun.finalWave).contains(save.wave),
              let battle = save.battle.restored
        else { return nil }
        let stage = save.stage
        if stage == .picking && save.offers.isEmpty { return nil }
        tuning = .standard
        self.wave = save.wave
        self.stage = stage
        self.route = save.route
        self.offers = save.offers
        self.remainingPicks = max(0, save.remainingPicks)
        self.balls = min(RogueRun.ballCap, max(0, save.balls))
        self.boosts = save.boosts.restored
        self.resultRecorded = save.resultRecorded
        self.party = save.party.map(\.restored)
        self.battle = battle
        self.rng = SplitMix64(seed: 0)
        self.rng.state = save.rngState
        self.seed = save.seed
        self.tookOnlyRiskyRoutes = save.tookOnlyRiskyRoutes
        // 강화는 개체에 도장으로 들어간다 — 되살린 개체는 그 도장이 없다(저장 형식이 개체별
        // 강화를 싣지 않고 런의 값 하나만 싣는다). 여기서 찍지 않으면 판을 이어 여는 순간
        // 화면에는 강화가 그대로인데 데미지에는 안 걸린다.
        stampBoosts()
    }
}
