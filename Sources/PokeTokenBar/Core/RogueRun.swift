import Foundation

/// 런 전용 강화. **세이브에 남지 않는다** — 런이 끝나면 파티와 함께 사라진다.
/// 그래서 무결성 서명·경제(별의조각)에 전혀 닿지 않고, 밸런스를 고쳐도 세이브 이전이 없다.
///
/// 프로토타입은 **파티 값만 건드리는 효과**로 한정한다. 데미지 배수·급소 단계처럼
/// `BattleEngine` 내부를 지나야 하는 강화는 엔진에 훅을 내야 해서 여기 없다.
enum RunModifier: String, CaseIterable, Sendable {
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
}

/// 포켓로그식 한 판. 웨이브를 하나씩 넘으며 **파티 HP·PP 가 이월**되는 것이 유일한 자원이다
/// (기존 던전의 체력 예산 100 을 대체한다).
///
/// 순수 구조체다 — 시각도 네트워크도 쓰지 않는다. 상대 스냅샷은 호출자가 만들어 넣는다
/// (`beginWave(opponents:)`). 그래야 웨이브 진행 규칙을 네트워크 없이 테스트할 수 있다.
struct RogueRun: Sendable {
    enum Stage: Sendable, Equatable {
        case battling
        /// 승리 직후 — 보상 3장 중 하나를 고를 때까지 멈춘다.
        case picking
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
    static func opponentLevel(wave: Int, tuning: RogueTuning = .standard) -> Int {
        let baseline = partyLevelBaseline(wave: wave, tuning: tuning)
        guard isBoss(wave: wave, tuning: tuning) else { return baseline - tuning.wildHandicap(wave: wave) }
        return baseline + (wave == tuning.finalWave ? tuning.finalLevelBonus : tuning.bossLevelBonus)
    }

    /// 웨이브당 상대 마릿수. 후반은 둘이 나온다 — 포획으로 파티가 커지는데 상대가 끝까지 하나면
    /// 판이 뒤로 갈수록 헐거워진다. 보스는 종족값 상한을 올린 한 마리로 남긴다(벽 역할).
    static func opponentCount(wave: Int, tuning: RogueTuning = .standard) -> Int {
        wave >= tuning.doubleOpponentWave ? 2 : 1
    }

    /// 웨이브별 상대 **종족값 합(BST) 상한**. 포켓로그가 웨이브에 따라 종 티어를 올리는 것과 같은
    /// 규칙이다. 이 상한이 없으면 종을 전 범위(1...649)에서 균등 추첨하는 호출자가 웨이브 1 에
    /// 슬라킹(670)·전설을 뽑아, 레벨 곡선을 아무리 맞춰도 판이 첫 턴에 끝난다.
    /// 최종 상한이 560 이라 전설 대부분(660~720)은 자연히 막히고, 따로 전설 목록을 두지 않는다.
    ///
    /// 구간은 **보스 웨이브를 포함**한다. 보스를 다음 구간으로 밀면 보스 4 가 뒤따르는 웨이브보다
    /// 세지는 톱니가 생긴다. 구간 사이는 선형으로 이어 웨이브 수를 늘리면 상승이 저절로 완만해진다.
    static func baseStatTotalCap(wave: Int, tuning: RogueTuning = .standard) -> Int {
        let (index, count) = tuning.tierIndex(wave: wave)
        let span = Double(tuning.lastTierCap - tuning.firstTierCap)
        let progress = count > 1 ? Double(index - 1) / Double(count - 1) : 1
        let tier = tuning.firstTierCap + Int((span * progress).rounded())
        return isBoss(wave: wave, tuning: tuning) ? tier + tuning.bossStatBonus : tier
    }

    static func baseStatTotal(_ stats: BattleStats) -> Int {
        stats.hp + stats.atk + stats.def + stats.spa + stats.spd + stats.spe
    }

    /// 하한은 상한의 60% — 없으면 최종 보스로 잉어킹(200)이 나온다.
    static func isFairOpponent(baseStats: BattleStats, wave: Int,
                               tuning: RogueTuning = .standard) -> Bool {
        let total = baseStatTotal(baseStats)
        let cap = baseStatTotalCap(wave: wave, tuning: tuning)
        return total <= cap && total >= Int(Double(cap) * tuning.minStatRatio)
    }

    /// 야생 추첨 범위 — 5세대까지.
    static let wildSpeciesPool = 1...649
    /// 스타터 후보 — 1·2세대 기본형 고정 풀(진화 루트 조회를 아직 안 탄다).
    static let starterPool = [1, 4, 7, 25, 152, 155, 158]
    /// 한 웨이브에서 종을 다시 뽑아 보는 횟수. 늘릴수록 PokeAPI 왕복이 그만큼 늘어난다.
    static let wildDrawAttempts = 8

    /// 웨이브에 맞는 상대 하나를 고른다. 후보를 하나씩 받아 티어에 들면 즉시 채택하고, 다 어긋나면
    /// 그중 **가장 약한 것**을 쓴다 — 판을 못 여는 것보다 낫다.
    ///
    /// 규칙이 여기 있는 이유는 **앱과 시뮬레이터가 같은 규칙을 봐야** 하기 때문이다. 화면 쪽에
    /// 두면 밸런스를 재는 판과 실제로 도는 판이 서로 다른 상대를 뽑는다.
    static func chooseOpponent(wave: Int, attempts: Int = wildDrawAttempts,
                               tuning: RogueTuning = .standard,
                               next: sending () async -> BattleSnapshot?) async -> BattleSnapshot? {
        var weakest: BattleSnapshot?
        for _ in 0..<attempts {
            guard let candidate = await next() else { continue }
            if isFairOpponent(baseStats: candidate.base, wave: wave, tuning: tuning) { return candidate }
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
    /// 이 판이 쓰는 밸런스 값. 앱은 `.standard`, 시뮬레이터는 흔든 값을 넣는다.
    let tuning: RogueTuning
    private(set) var battle: TeamPracticeBattle
    /// 웨이브 seed·보상 추첨을 잇는 하나의 흐름. **판마다 완전 무작위로 심는다** — 날짜 결정론은
    /// 쓰지 않는다(퍼즐 던전과 다른 점이다). 하루 판 수도 제한하지 않는다: 같은 판을 다시 도는
    /// 콘텐츠가 아니라 매번 새로 뽑는 콘텐츠고, 보상이 세이브에 남지 않아 반복이 경제를 흔들지 않는다.
    private var rng: SplitMix64

    init(party: [BattleSnapshot], opponents: [BattleSnapshot], seed: UInt64,
         tuning: RogueTuning = .standard) {
        self.tuning = tuning
        self.balls = tuning.ballsPerRun
        var rng = SplitMix64(seed: seed)
        let sides = party.map(BattleSide.init)
        self.party = sides
        self.battle = TeamPracticeBattle(mine: sides,
                                         opponents: opponents.map(BattleSide.init),
                                         rng: SplitMix64(seed: rng.next()))
        self.rng = rng
    }

    // MARK: 전투 중

    mutating func useMove(_ index: Int) {
        guard stage == .battling else { return }
        _ = battle.useMove(index)
        settle()
    }

    mutating func switchParty(to index: Int) {
        guard stage == .battling else { return }
        _ = battle.switchMine(to: index)
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
            offers = Self.drawOffers(&rng)
            stage = .picking
        }
    }

    // MARK: 포획

    /// 지금 볼을 던질 수 있는가. 보스는 제외한다 — 4·8·12 웨이브는 판의 관문이고 회복 지점이라
    /// 잡아서 건너뛰면 그 자리가 사라진다.
    var canThrowBall: Bool {
        stage == .battling && battle.result == nil && balls > 0
            && party.count < tuning.partyLimit && !Self.isBoss(wave: wave, tuning: tuning)
    }

    /// 볼을 던진다. **성공하든 실패하든 그 턴은 내 공격이 아니다** — 실패하면 상대만 움직인다.
    /// 성공하면 그 웨이브는 쓰러뜨린 것과 같은 규칙으로 넘어간다(`clearWave`).
    @discardableResult
    mutating func throwBall() -> Bool {
        guard canThrowBall else { return false }
        balls -= 1
        let target = battle.opponentSlot
        let roll = Double(rng.next() % 10_000) / 10_000
        guard roll < Self.catchChance(target: target) else {
            _ = battle.spendTurnWithoutAttacking()
            settle()
            return false
        }
        party = battle.mine
        // 잡힌 상대는 쓰러진 것과 같은 자리를 지난다 — 상대가 더 남았으면 전투는 이어진다.
        battle.retireOpponent()
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
        return true
    }

    // MARK: 보상

    static func drawOffers(_ rng: inout SplitMix64) -> [RunModifier] {
        var pool = RunModifier.allCases
        var picked: [RunModifier] = []
        while picked.count < offerCount, !pool.isEmpty {
            picked.append(pool.remove(at: Int(rng.next() % UInt64(pool.count))))
        }
        return picked
    }

    mutating func pick(_ modifier: RunModifier) {
        guard stage == .picking, offers.contains(modifier) else { return }
        apply(modifier)
        offers = []
        wave += 1
        stage = .loadingWave
    }

    /// 다음 웨이브 개시 — 상대는 호출자가 만들어 넣는다(네트워크는 코어 밖).
    mutating func beginWave(opponents: [BattleSnapshot]) {
        guard stage == .loadingWave, !opponents.isEmpty,
              let lead = party.firstIndex(where: { $0.isAlive }) else { return }
        // 이월하는 것은 **HP·PP·주 상태이상까지**다. 랭크·혼란·풀죽음은 전투 안에서만 사는 값이라
        // 웨이브가 바뀌면 지운다 — 안 지우면 앞 웨이브에서 울음소리로 깎인 랭크를 판이 끝날 때까지
        // 지고 가서 "웨이브를 넘길수록 이유 없이 약해진다"가 된다(교체할 때와 같은 규칙).
        for i in party.indices { BattleEngine.prepareForSwitch(&party[i]) }
        battle = TeamPracticeBattle(mine: party,
                                    opponents: opponents.map(BattleSide.init),
                                    rng: SplitMix64(seed: rng.next()))
        // 앞 웨이브에서 1번이 쓰러졌으면 살아 있는 첫 칸으로 세운다. 기본값 0 그대로 두면
        // 쓰러진 개체가 활성 슬롯이 되어 첫 턴을 통째로 날린다.
        battle.myActive = lead
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
        }
    }

    /// 파티의 주 상태이상·혼란을 지운다. **HP·PP 는 건드리지 않는다** — 그게 이월 자원이다.
    private mutating func clearStatus() {
        for i in party.indices {
            party[i].status = nil
            party[i].statusCounter = 0
            party[i].confusionTurns = 0
        }
    }

    /// 살아 있는 개체를 완전 회복한다. **쓰러진 개체는 일으키지 않는다** — 부활은 `revive` 보상의
    /// 몫이고, 여기서 같이 살리면 그 보상이 보스 직후에 늘 꽝이 된다.
    private mutating func restoreParty() {
        for i in party.indices where party[i].isAlive {
            party[i].hp = party[i].stats.hp
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
    mutating func debugAfflict(_ status: Status) { battle.mine[battle.myActive].status = status }
    mutating func debugApply(_ modifier: RunModifier) { apply(modifier) }
    /// 최종 웨이브 판정처럼 앞 웨이브를 다 밟지 않고 도달해야 하는 자리에 쓴다.
    mutating func debugJump(toWave value: Int) { wave = value }
    /// 테스트 전용 — 포획 확률을 재려면 상대 HP·볼 개수를 직접 세워야 한다.
    mutating func debugSetOpponentHP(_ value: Int) { battle.opponents[battle.opponentActive].hp = value }
    mutating func debugSetBalls(_ value: Int) { balls = value }
}
#endif
