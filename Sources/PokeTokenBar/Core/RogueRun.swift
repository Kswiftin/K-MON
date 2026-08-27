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

    static let finalWave = 12
    static let offerCount = 3
    /// 4·8·12 웨이브가 보스다.
    static func isBoss(wave: Int) -> Bool { wave % 4 == 0 }
    /// 상대 레벨 — 야생은 `3 + 2×웨이브`로 **파티 기준선과 같다**(스타터 5 에서 승리마다 +2 이므로
    /// 웨이브 w 의 파티가 `3 + 2w`). 보스만 `+3`(최종 `+5`) 위에 둔다.
    ///
    /// 예전 식(야생 `4 + 2×웨이브`)은 야생조차 늘 파티보다 높았다. 파티가 한 마리이고 HP·PP 가
    /// 웨이브를 넘어 이월되는 구조라, 매 웨이브 레벨이 밀리면 손해가 누적돼 되돌릴 수단이 없다.
    static func opponentLevel(wave: Int) -> Int {
        let wild = 3 + 2 * wave
        guard isBoss(wave: wave) else { return wild }
        return wild + (wave == finalWave ? 5 : 3)
    }

    /// 웨이브별 상대 **종족값 합(BST) 상한**. 포켓로그가 웨이브에 따라 종 티어를 올리는 것과 같은
    /// 규칙이다. 이 상한이 없으면 종을 전 범위(1...649)에서 균등 추첨하는 호출자가 웨이브 1 에
    /// 슬라킹(670)·전설을 뽑아, 레벨 곡선을 아무리 맞춰도 판이 첫 턴에 끝난다.
    /// 상한 640 이 전설 대부분(660~720)을 자연히 막으므로 따로 전설 목록을 두지 않는다.
    static func baseStatTotalCap(wave: Int) -> Int {
        let tier: Int
        switch wave {
        case ..<4:  tier = 320      // 미진화 1단계 대
        case ..<8:  tier = 420      // 2단계 대
        case ..<12: tier = 500      // 최종 진화 대
        default:    tier = 580
        }
        return isBoss(wave: wave) ? tier + 60 : tier
    }

    /// 하한은 상한의 60% — 없으면 최종 보스로 잉어킹(200)이 나온다.
    static func isFairOpponent(baseStats: BattleStats, wave: Int) -> Bool {
        let total = baseStats.hp + baseStats.atk + baseStats.def
            + baseStats.spa + baseStats.spd + baseStats.spe
        let cap = baseStatTotalCap(wave: wave)
        return total <= cap && total >= cap * 3 / 5
    }

    /// 승리 시 파티 전원이 오르는 레벨. 전원 같은 폭이라 교체해도 손해가 없다 — 자원은 HP 지 레벨이 아니다.
    static func levelGain(wave: Int) -> Int { isBoss(wave: wave) ? 3 : 2 }

    private(set) var wave = 1
    /// 파티 — HP·PP 가 웨이브를 넘어 유지된다.
    private(set) var party: [BattleSide]
    private(set) var stage: Stage = .battling
    private(set) var offers: [RunModifier] = []
    private(set) var battle: TeamPracticeBattle
    /// 웨이브 seed·보상 추첨을 잇는 하나의 흐름. 판마다 `dayKey + 판 번호` 로 심는다.
    private var rng: SplitMix64

    init(party: [BattleSnapshot], opponents: [BattleSnapshot], seed: UInt64) {
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
            levelUpParty(by: Self.levelGain(wave: wave))
            // 보스를 넘으면 파티를 완전 회복한다 — 포켓로그가 10 웨이브마다 무료 회복을 주는 자리와
            // 같은 역할이다. 이월 자원이 HP·PP 뿐이라 회복 지점이 없으면 보상 3장으로는 못 메우고
            // 후반 웨이브가 "이미 진 판을 마저 두는" 소화가 된다.
            if Self.isBoss(wave: wave) { restoreParty() }
            if wave == Self.finalWave {
                stage = .cleared
            } else {
                offers = Self.drawOffers(&rng)
                stage = .picking
            }
        case .loss, .draw:
            // 동시 전멸도 실패다 — 파티가 남지 않았으면 다음 웨이브를 설 수 없다.
            stage = .failed
        }
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
    mutating func debugApply(_ modifier: RunModifier) { apply(modifier) }
    /// 최종 웨이브 판정처럼 앞 웨이브를 다 밟지 않고 도달해야 하는 자리에 쓴다.
    mutating func debugJump(toWave value: Int) { wave = value }
}
#endif
