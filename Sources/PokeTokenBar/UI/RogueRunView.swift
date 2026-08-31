import SwiftUI

/// 화면이 지금 그릴 국면. **코어의 `RogueRun.Stage` 와 다를 수 있다는 것이 이 타입의 존재
/// 이유다.** 승리 정산(`settle`)은 마지막 턴의 이벤트가 재생되기 전에 국면을 `.picking` 으로
/// 넘기므로, 국면만 보고 그리면 결정타·기절·로그가 화면에 뜨기 전에 보상 목록이 전투를 덮는다
/// (실제 결함: 던전이 "턴 종료 연출 없이 선택지로 점프" 했다).
///
/// 볼을 던진 결과도 같은 부류다 — 성공하면 이벤트가 하나도 안 붙은 채 웨이브가 넘어가서,
/// 잡았다는 사실이 어디에도 뜨지 않는다. 그래서 알림(`hasNotice`)이 남아 있는 동안도 전투를 든다.
enum RogueRunPhase: Equatable {
    case battle
    case picking
    case routing
    case loading
    case ending

    /// `hasUnplayedEvents` 는 **재생이 스트림 끝에 닿지 않았다**는 뜻이다(재생 중도 포함).
    /// 재생 중 여부만 보면 안 되는 이유는 순서다 — 코어가 국면을 넘긴 프레임에는 재생기가 아직
    /// 새 이벤트를 받지 못해 `isPlaying` 이 false 이고, 그 한 프레임에 전투가 화면에서 사라지면
    /// 재생기는 영영 스트림을 받지 못한다.
    static func of(stage: RogueRun.Stage, hasUnplayedEvents: Bool,
                   hasNotice: Bool) -> RogueRunPhase {
        let holdsBattle = hasUnplayedEvents || hasNotice
        switch stage {
        case .battling:    return .battle
        // 로딩은 전투가 이미 교체된 뒤다 — 여기서 전투를 들면 다음 웨이브 상대를 기다리는 동안
        // 지나간 판이 화면에 남는다.
        case .loadingWave: return .loading
        case .picking:     return holdsBattle ? .battle : .picking
        case .routing:     return holdsBattle ? .battle : .routing
        case .cleared, .failed: return holdsBattle ? .battle : .ending
        }
    }
}

/// 볼을 던진 결과 — 화면에 한 줄로 남는다. 성공은 이벤트를 만들지 않으므로(잡힌 상대는
/// `retireOpponent` 로 조용히 빠진다) 이 값이 없으면 포획이 화면에 존재하지 않는다.
struct BallThrowNotice: Equatable {
    let target: String
    let caught: Bool
}

/// 포켓로그식 런 화면 — **프로토타입**이다. 기록 저장(`RunProgress`)이 아직 없다.
/// 입장권·하루 판 수 제한은 두지 않기로 했다(설계: `docs/reference/wave-run-design.md`).
struct RogueRunView: View {
    @Bindable var store: CompanionStore
    @Environment(AppSettings.self) private var settings
    /// 턴 결과를 시간축에 푸는 재생기 — 기존 배틀 화면과 같은 객체를 쓴다. 없으면 기절·피격이
    /// 화면에 뜨기 전에 필드가 다음 포켓몬으로 갈아타 "맞고 쓰러진" 순간이 통째로 사라진다.
    @State private var animator = BattleAnimator()
    let onClose: () -> Void

    private var l: L { store.l }

    /// 런이 **시작되기 전**의 국면만 뷰가 든다. 진행 중인 런은 `store.rogueRun` 에 있어야
    /// 팝오버를 닫아도 이어진다 — 뷰 상태로 들면 창을 닫는 순간 판이 사라진다.
    private enum Setup {
        case loading
        case choosingStarter([BattleSnapshot])
        case failedToLoad
    }

    @State private var setup: Setup = .loading
    /// 방금 보상 화면에서 진화한 개체의 이름 — 화면에 한 줄로 알린다. 진화를 조용히 처리하면
    /// 판의 가장 큰 사건이 스프라이트가 바뀐 것으로만 남는다.
    @State private var evolved: [String] = []
    /// 진화 조회를 이미 지난 웨이브. `.task` 는 화면이 다시 그려질 때마다 도는데, 조회는 왕복이
    /// 여러 번이라 같은 웨이브에서 두 번 돌면 보상 화면이 그만큼 늦게 열린다.
    @State private var evolutionCheckedWave = 0
    /// 방금 던진 볼의 결과. 사용자가 확인할 때까지 전투 화면을 붙잡는다.
    @State private var throwNotice: BallThrowNotice?


    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            content
            Spacer(minLength: 0)
        }
        .padding(PopoverMetrics.padding)
        .frame(height: PopoverMetrics.currentHeight(for: .battle))
        .task { await resume() }
        // 웨이브가 넘어가면 앞 웨이브의 볼 결과는 끝난 이야기다 — 남겨 두면 다음 전투 화면이
        // 지나간 포켓몬 이름을 들고 열린다.
        .onChange(of: store.rogueRun?.wave) { throwNotice = nil }
    }

    private var header: some View {
        HStack {
            Label(headerTitle, systemImage: "flame.fill").font(.headline)
            Spacer()
            Button(action: onClose) { Image(systemName: "xmark") }.buttonStyle(.plain)
        }
    }

    private var headerTitle: String {
        guard let run = store.rogueRun else { return l.t("웨이브 런", "Wave Run", "ウェーブラン") }
        let boss = RogueRun.isBoss(wave: run.wave) ? l.t(" · 보스", " · BOSS", " · ボス") : ""
        return l.t("웨이브 \(run.wave)/\(RogueRun.finalWave)\(boss)",
                   "Wave \(run.wave)/\(RogueRun.finalWave)\(boss)",
                   "ウェーブ \(run.wave)/\(RogueRun.finalWave)\(boss)")
    }

    @ViewBuilder
    private var content: some View {
        if let run = store.rogueRun {
            switch phase(of: run) {
            case .battle:     battlePanel(run)
            case .picking:    rewardPicker(run)
            case .routing:    routePicker(run)
            case .loading:    ProgressView().frame(maxWidth: .infinity)
            case .ending where run.stage == .cleared:
                ending(l.t("\(RogueRun.finalWave) 웨이브를 모두 돌파했다.",
                           "Cleared all \(RogueRun.finalWave) waves.",
                           "\(RogueRun.finalWave) ウェーブすべてを突破した。"))
            case .ending:     ending(l.t("웨이브 \(run.wave) 에서 파티가 전멸했다.",
                                          "Party wiped on wave \(run.wave).",
                                          "ウェーブ \(run.wave) でパーティが全滅した。"))
            }
        } else {
            switch setup {
            case .loading:
                ProgressView().frame(maxWidth: .infinity)
            case .failedToLoad:
                VStack(alignment: .leading, spacing: 8) {
                    Text(l.t("PokéAPI 에 연결하지 못했다. 야생 포켓몬을 만들 수 없어 판을 시작할 수 없다.",
                             "Could not reach PokéAPI. A run needs it to build wild Pokémon.",
                             "PokéAPI に接続できなかった。野生ポケモンを作れないため開始できない。"))
                        .font(.caption).foregroundStyle(.secondary)
                    Button(l.t("다시 시도", "Retry", "再試行")) {
                        setup = .loading
                        Task { await loadStarters() }
                    }
                }
            case .choosingStarter(let candidates):
                starterPicker(candidates)
            }
        }
    }

    // MARK: 스타터

    private func starterPicker(_ candidates: [BattleSnapshot]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(l.t("첫 포켓몬을 고른다", "Pick your starter", "最初のポケモンを選ぶ"))
                .font(.caption).foregroundStyle(.secondary)
            recordLine
            HStack(spacing: 10) {
                ForEach(candidates, id: \.speciesID) { candidate in
                    Button { Task { await start(with: candidate) } } label: {
                        VStack(spacing: 2) {
                            SpriteView(speciesID: candidate.speciesID, size: 56, animated: true,
                                       shiny: false, back: false)
                            Text(candidate.name).font(.caption2)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: 전투

    /// 코어의 국면을 화면 국면으로 옮긴다. 재생이 스트림 끝에 닿았는지를 `playedCount` 로 보는
    /// 이유는 `RogueRunPhase.of` 에 적어 뒀다.
    private func phase(of run: RogueRun) -> RogueRunPhase {
        RogueRunPhase.of(stage: run.stage,
                         hasUnplayedEvents: animator.playedCount < run.battle.events.count
                            || animator.overlay.isPlaying,
                         hasNotice: throwNotice != nil)
    }

    private func battlePanel(_ run: RogueRun) -> some View {
        // 기존 배틀·팀 연습과 **같은 렌더러와 같은 재생기**를 쓴다. 직접 그리면 기술 버튼의 타입 색·
        // PP 배지·로그가 이 화면만 달라지고, 재생기를 빼면 기절이 화면에 뜨기 전에 필드가 다음
        // 포켓몬으로 갈아타 "맞고 쓰러졌다" 가 사라진다(둘 다 실제로 그렇게 어긋났다).
        let engineMine = ReplaySide(team: run.battle.mine, active: run.battle.myActive)
        let engineTheirs = ReplaySide(team: run.battle.opponents, active: run.battle.opponentActive)
        let shownMine = animator.side(for: .a) ?? engineMine
        let shownTheirs = animator.side(for: .b) ?? engineTheirs
        let me = shownMine.side ?? run.battle.mySlot
        let opponent = shownTheirs.side ?? run.battle.opponentSlot
        return VStack(spacing: 6) {
            catchBar(run)
            if let throwNotice { noticeBar(throwNotice) }
            boostBar(run)
            arena(run, me: me, opponent: opponent, shownMine: shownMine,
                  engineMine: engineMine, engineTheirs: engineTheirs)
        }
    }

    /// 볼·파티 칸·성공률을 한 줄로 보여주고 던진다. 성공률을 감추면 언제 던질지가 순전히 감이 되고,
    /// 볼이 5개뿐이라 그 감이 곧 판을 버리는 선택이 된다.
    private func catchBar(_ run: RogueRun) -> some View {
        HStack(spacing: 8) {
            Label("\(run.balls)", systemImage: "circle.circle")
            Text(l.t("파티 \(run.party.count)/\(RogueRun.partyLimit)",
                     "Party \(run.party.count)/\(RogueRun.partyLimit)",
                     "手持ち \(run.party.count)/\(RogueRun.partyLimit)"))
                .foregroundStyle(.secondary)
            Spacer()
            if run.canThrowBall {
                Text("\(Int(RogueRun.catchChance(target: run.battle.opponentSlot) * 100))%")
                    .foregroundStyle(.secondary)
            }
            Button(l.t("잡기", "Catch", "捕まえる")) {
                let target = run.battle.opponentSlot.snapshot.name
                var caught = false
                mutate { caught = $0.throwBall() }
                throwNotice = BallThrowNotice(target: target, caught: caught)
            }
            .disabled(!run.canThrowBall)
        }
        .font(.caption)
    }

    /// 볼을 던진 결과 한 줄. **성공은 이벤트를 만들지 않는다** — 잡힌 상대는 `retireOpponent` 로
    /// 조용히 빠지고 웨이브가 그 자리에서 넘어가므로, 이 줄이 없으면 포획이 화면에 존재하지 않고
    /// 보상 목록만 갑자기 뜬다. 사용자가 "계속"을 누를 때까지 전투 화면을 붙잡는다.
    private func noticeBar(_ notice: BallThrowNotice) -> some View {
        HStack(spacing: 8) {
            Label(notice.caught
                  ? l.t("\(notice.target) 을(를) 잡았다!", "Caught \(notice.target)!",
                        "\(notice.target) を捕まえた！")
                  : l.t("\(notice.target) 이(가) 볼에서 튀어나왔다!",
                        "\(notice.target) broke free!",
                        "\(notice.target) がボールから出てきた！"),
                  systemImage: notice.caught ? "checkmark.circle.fill" : "xmark.circle")
                .font(.caption.bold())
            Spacer()
            Button(l.t("계속", "Continue", "つづける")) { throwNotice = nil }
                .controlSize(.small)
        }
    }

    /// 쌓인 지속 강화 한 줄. 안 보여주면 무엇을 골라 왔는지 판 도중에 확인할 길이 없어, 다음 뽑기의
    /// 선택(같은 타입에 더 쌓을지 갈아탈지)이 기억에 의존한다.
    @ViewBuilder
    private func boostBar(_ run: RogueRun) -> some View {
        if !run.boosts.isEmpty {
            HStack(spacing: 8) {
                ForEach(run.boosts.typeDamage.sorted { $0.key.rawValue < $1.key.rawValue },
                        id: \.key) { entry in
                    Label("\(entry.key.name(store.language)) ×\(entry.value)",
                          systemImage: "bolt.fill")
                }
                if run.boosts.critStages > 0 {
                    Label("+\(run.boosts.critStages)", systemImage: "scope")
                }
                if run.boosts.leftovers > 0 {
                    Label("×\(run.boosts.leftovers)", systemImage: "leaf.fill")
                }
                Spacer()
            }
            .font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func arena(_ run: RogueRun, me: BattleSide, opponent: BattleSide,
                       shownMine: ReplaySide,
                       engineMine: ReplaySide, engineTheirs: ReplaySide) -> some View {
        BattleArenaView(
            mine: me, theirs: opponent,
            myTitle: l.battleMyPokemon,
            theirTitle: RogueRun.isBoss(wave: run.wave) ? l.t("보스", "BOSS", "ボス")
                                                        : l.t("야생", "Wild", "野生"),
            l: l, turn: run.battle.turn,
            logLines: BattleLogSource.twoSided(Array(run.battle.events.prefix(animator.playedCount)),
                                               mine: .a, l: l,
                                               myName: me.snapshot.name,
                                               theirName: opponent.snapshot.name,
                                               myMoves: me.moves, theirMoves: opponent.moves),
            myActor: .a,
            switchSlots: SwitchStripModel.slots(shownMine.team, active: shownMine.active),
            turnEndsAt: nil,
            isWaitingForOpponent: false,
            overlay: animator.overlay,
            onChoose: { index in mutate { $0.useMove(index) } },
            onSwitch: { index in mutate { $0.switchParty(to: index) } },
            // 항복은 런 포기다 — 판을 버리고 나간다(프로토라 기록도 남지 않는다).
            onForfeit: { store.rogueRun = nil; onClose() })
        .onAppear { replay(run.battle.events, sides: [.a: engineMine, .b: engineTheirs]) }
        .onChange(of: run.battle.events.count) {
            replay(run.battle.events, sides: [.a: engineMine, .b: engineTheirs])
        }
    }

    /// 재생기에 스트림을 넘긴다. 속도 규칙은 기존 배틀과 같다(저전력이면 설정과 무관하게 끈다).
    private func replay(_ events: [BattleEvent], sides: [BattleActor: ReplaySide]) {
        animator.sync(events: events, sides: sides,
                      speed: BattleReplay.effectiveSpeed(
                        settings.battleReplaySpeed,
                        lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled))
    }

    // MARK: 보상

    private func rewardPicker(_ run: RogueRun) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(evolved, id: \.self) { name in
                Text(l.t("\(name) 이(가) 진화했다!", "\(name) evolved!", "\(name) がしんかした！"))
                    .font(.callout.bold())
            }
            Text(run.remainingPicks > 1
                 ? l.t("웨이브 \(run.wave) 돌파 — \(run.remainingPicks) 장 중 첫 장을 고른다",
                       "Wave \(run.wave) cleared — pick the first of \(run.remainingPicks)",
                       "ウェーブ \(run.wave) 突破 — \(run.remainingPicks) 枚のうち一枚目を選ぶ")
                 : l.t("웨이브 \(run.wave) 돌파 — 하나를 고른다",
                       "Wave \(run.wave) cleared — pick one",
                       "ウェーブ \(run.wave) 突破 — 一つ選ぶ"))
                .font(.caption).foregroundStyle(.secondary)
            ForEach(run.offers, id: \.self) { offer in
                Button {
                    mutate { $0.pick(offer) }
                    Task { await loadNextWave() }
                } label: {
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 4) {
                            Text(Self.title(offer, l)).font(.callout.bold())
                            // 지속형은 배지로 갈라 보여준다 — 이 판에 남는 장과 그 자리에서 사라지는
                            // 장을 구별하지 못하면 빌드를 고를 수 없다.
                            if offer.isPersistent {
                                Text(l.t("지속", "Keeps", "永続"))
                                    .font(.caption2).padding(.horizontal, 4)
                                    .background(.tint.opacity(0.2), in: Capsule())
                            }
                        }
                        Text(Self.detail(offer, type: run.boostableType, language: store.language, l))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .task(id: run.wave) { await evolveParty() }
    }

    /// 웨이브를 넘긴 파티에서 **레벨 조건을 채운 개체를 진화시킨다.** 보상 화면에서 도는 이유는
    /// 두 가지다 — 전투 중에 개체를 갈면 진행 중인 턴의 활성 슬롯이 다른 종으로 바뀌고, 다음 웨이브
    /// 로딩에 붙이면 판의 가장 큰 사건이 로딩 스피너 뒤로 숨는다.
    ///
    /// 조회가 실패하면 **진화하지 않고 그대로 간다** — 판을 세우는 대신 이번 웨이브의 진화를 건너뛴다.
    private func evolveParty() async {
        guard let run = store.rogueRun, run.stage == .picking,
              evolutionCheckedWave != run.wave else { return }
        evolutionCheckedWave = run.wave
        evolved = []
        for (index, member) in run.party.enumerated() {
            guard let line = try? await PokeAPIClient.shared.line(baseSpeciesID: member.snapshot.speciesID),
                  let node = line.tree.node(withID: member.snapshot.speciesID),
                  let target = RogueRun.levelUpEvolution(from: node, level: member.snapshot.level),
                  // 애니메이션 스프라이트가 없는 종으로 진화시키면 화면에서 개체가 사라진다.
                  PokemonAssets.hasAnimatedSprite(speciesID: target.speciesID),
                  let snapshot = await Self.snapshot(speciesID: target.speciesID,
                                                    level: member.snapshot.level, store: store)
            else { continue }
            let before = member.snapshot.name
            mutate { $0.evolve(memberAt: index, into: snapshot) }
            evolved.append(before)
        }
    }

    /// 다음 웨이브로 갈 길. 두 장이 무엇을 주고 무엇을 요구하는지 **숫자로** 보여준다 —
    /// "위험한 길"이라고만 쓰면 얼마나 위험한지 모르고 고르게 되고, 그러면 선택이 아니라 도박이 된다.
    private func routePicker(_ run: RogueRun) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(l.t("웨이브 \(run.wave + 1) 로 가는 길을 고른다",
                     "Choose the path to wave \(run.wave + 1)",
                     "ウェーブ \(run.wave + 1) への道を選ぶ"))
                .font(.caption).foregroundStyle(.secondary)
            ForEach(RunRoute.allCases, id: \.self) { route in
                Button {
                    mutate { $0.take(route) }
                    Task { await loadNextWave() }
                } label: {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(Self.routeTitle(route, l)).font(.callout.bold())
                        Text(Self.routeDetail(route, l)).font(.caption2).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private static func routeTitle(_ route: RunRoute, _ l: L) -> String {
        switch route {
        case .safe:  return l.t("평탄한 길", "Even path", "平らな道")
        case .risky: return l.t("험한 길", "Rough path", "険しい道")
        }
    }

    private static func routeDetail(_ route: RunRoute, _ l: L) -> String {
        switch route {
        case .safe:
            return l.t("상대도 보상도 규칙 그대로다.",
                       "Opponents and rewards stay as they are.",
                       "相手も報酬も規則どおりだ。")
        case .risky:
            return l.t("상대 레벨 +\(RunRoute.risky.levelBonus), 종족값 상한 +\(RunRoute.risky.statBonus). 넘기면 보상을 \(RunRoute.risky.pickCount) 장 고른다.",
                       "Opponents get +\(RunRoute.risky.levelBonus) levels and +\(RunRoute.risky.statBonus) base-stat headroom. Clear it and pick \(RunRoute.risky.pickCount) rewards.",
                       "相手のレベル +\(RunRoute.risky.levelBonus)、種族値上限 +\(RunRoute.risky.statBonus)。突破すると報酬を \(RunRoute.risky.pickCount) 枚選べる。")
        }
    }

    private static func title(_ modifier: RunModifier, _ l: L) -> String {
        switch modifier {
        case .potion:  return l.t("상처약", "Potion", "きずぐすり")
        case .revive:  return l.t("기력의조각", "Revive", "げんきのかけら")
        case .candy:   return l.t("이상한사탕", "Rare Candy", "ふしぎなアメ")
        case .elixir:  return l.t("엘릭서", "Elixir", "エリキシル")
        case .cleanse: return l.t("만병통치제", "Full Heal", "なんでもなおし")
        case .typeBoost: return l.t("타입 강화판", "Type Booster", "タイプ強化板")
        case .focusLens: return l.t("초점렌즈", "Scope Lens", "ピントレンズ")
        case .leftovers: return l.t("먹다남은음식", "Leftovers", "たべのこし")
        case .ballPouch: return l.t("몬스터볼 보충", "Ball Pouch", "モンスターボール補充")
        case .xAttack:   return l.t("플러스파워", "X Attack", "プラスパワー")
        case .xDefense:  return l.t("디펜드업", "X Defense", "ディフェンダー")
        case .xSpeed:    return l.t("스피드업", "X Speed", "スピーダー")
        }
    }

    private static func detail(_ modifier: RunModifier, type: PokemonType?,
                               language: AppLanguage, _ l: L) -> String {
        switch modifier {
        case .potion:  return l.t("살아 있는 전원의 최대 HP 40% 를 회복한다.",
                                  "Heal 40% of max HP on every conscious member.",
                                  "戦えるポケモン全員の最大HPの40%を回復する。")
        case .revive:  return l.t("쓰러진 한 마리를 최대 HP 의 절반으로 되살린다.",
                                  "Bring one fainted member back at half HP.",
                                  "ひんしのポケモン1匹を最大HPの半分で復活させる。")
        case .candy:   return l.t("파티 전원의 레벨이 2 오른다.",
                                  "The whole party gains 2 levels.",
                                  "パーティ全員のレベルが2上がる。")
        case .elixir:  return l.t("파티 전원의 기술 PP 를 모두 회복한다.",
                                  "Restore every move's PP.",
                                  "パーティ全員の技のPPをすべて回復する。")
        case .cleanse: return l.t("파티의 상태이상과 혼란을 해제한다.",
                                  "Clear status and confusion from the party.",
                                  "パーティの状態異常と混乱を回復する。")
        // 어떤 타입이 올라가는지 **고르기 전에** 보여준다 — 모르고 고르면 빌드가 아니라 복권이다.
        case .typeBoost:
            let name = type?.name(language) ?? l.t("선두", "lead", "先頭")
            return l.t("\(name) 타입 기술 데미지가 20% 오른다. 판이 끝날 때까지 남고 중첩된다.",
                       "\(name)-type moves deal 20% more damage. Keeps stacking for the run.",
                       "\(name)タイプの技のダメージが20%上がる。ラン中ずっと残り、重ねられる。")
        case .focusLens:
            return l.t("급소 단계가 1 오른다. 판이 끝날 때까지 남고 중첩된다.",
                       "Raises the critical-hit stage by 1. Keeps stacking for the run.",
                       "急所ランクが1上がる。ラン中ずっと残り、重ねられる。")
        case .leftovers:
            return l.t("턴이 끝날 때마다 최대 HP 의 1/16 을 회복한다. 판이 끝날 때까지 남고 중첩된다.",
                       "Restores 1/16 of max HP at the end of every turn. Keeps stacking for the run.",
                       "ターン終了ごとに最大HPの1/16を回復する。ラン中ずっと残り、重ねられる。")
        case .ballPouch:
            return l.t("몬스터볼 \(RogueTuning.standard.ballsPerPouch) 개를 채운다(최대 \(RogueTuning.standard.ballCap) 개).",
                       "Adds \(RogueTuning.standard.ballsPerPouch) Poké Balls (up to \(RogueTuning.standard.ballCap)).",
                       "モンスターボールを \(RogueTuning.standard.ballsPerPouch) 個補充する(最大 \(RogueTuning.standard.ballCap) 個)。")
        case .xAttack:
            return l.t("파티의 공격이 \(RunBoosts.statPercentPerStack)% 오른다. 판이 끝날 때까지 남고 중첩된다.",
                       "The party's Attack rises \(RunBoosts.statPercentPerStack)%. Keeps stacking for the run.",
                       "パーティの攻撃が \(RunBoosts.statPercentPerStack)% 上がる。ラン中ずっと残り、重ねられる。")
        case .xDefense:
            return l.t("파티의 방어가 \(RunBoosts.statPercentPerStack)% 오른다. 판이 끝날 때까지 남고 중첩된다.",
                       "The party's Defense rises \(RunBoosts.statPercentPerStack)%. Keeps stacking for the run.",
                       "パーティの防御が \(RunBoosts.statPercentPerStack)% 上がる。ラン中ずっと残り、重ねられる。")
        case .xSpeed:
            return l.t("파티의 스피드가 \(RunBoosts.statPercentPerStack)% 오른다. 판이 끝날 때까지 남고 중첩된다.",
                       "The party's Speed rises \(RunBoosts.statPercentPerStack)%. Keeps stacking for the run.",
                       "パーティのすばやさが \(RunBoosts.statPercentPerStack)% 上がる。ラン中ずっと残り、重ねられる。")
        }
    }

    private func ending(_ line: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(line).font(.callout)
            recordLine
            // 끝난 판은 여기서 비운다 — 남겨 두면 다음에 던전 탭을 열 때 결과 화면이 다시 뜬다.
            Button(l.battleClose) { store.rogueRun = nil; onClose() }
        }
        .task { recordResult() }
    }

    /// 판 밖으로 남는 것 — 최고 도달 웨이브와 클리어 횟수. 판마다 사라지는 게임이라 이 줄이 없으면
    /// 여러 판을 돌린 것이 화면 어디에도 남지 않는다.
    @ViewBuilder
    private var recordLine: some View {
        let progress = store.runProgress
        if progress.finished > 0 {
            Text(l.t("최고 웨이브 \(progress.bestWave)/\(RogueRun.finalWave) · 클리어 \(progress.clears)회 · 판 \(progress.finished)회",
                     "Best wave \(progress.bestWave)/\(RogueRun.finalWave) · \(progress.clears) cleared · \(progress.finished) runs",
                     "最高ウェーブ \(progress.bestWave)/\(RogueRun.finalWave) · クリア \(progress.clears)回 · \(progress.finished)回"))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    /// 끝난 판을 실적에 적는다. **판 하나는 한 번만 센다** — 결과 화면은 팝오버를 여닫을 때마다
    /// 다시 그려지므로, 플래그(`resultRecorded`)를 코어에 두고 그 값을 보고 판단한다.
    private func recordResult() {
        guard let run = store.rogueRun, !run.resultRecorded,
              run.stage == .cleared || run.stage == .failed else { return }
        store.recordRunResult(reachedWave: run.wave, cleared: run.stage == .cleared,
                              tookOnlyRiskyRoutes: run.tookOnlyRiskyRoutes)
        mutate { $0.markResultRecorded() }
    }

    // MARK: 진행

    /// store 의 런을 꺼내 바꾸고 되넣는다 — 뷰가 값 타입 코어를 다루는 유일한 자리다.
    private func mutate(_ body: (inout RogueRun) -> Void) {
        guard var run = store.rogueRun else { return }
        body(&run)
        store.rogueRun = run
    }

    /// 화면을 열 때마다 불린다. 진행 중인 판이 있으면 이어 붙이고, 상대를 받는 중이던 판은
    /// 그 상대를 다시 불러온다 — 안 그러면 웨이브 로딩 중 창을 닫은 판이 영원히 로딩에 멈춘다.
    private func resume() async {
        guard let run = store.rogueRun else { return await loadStarters() }
        if run.stage == .loadingWave { await loadNextWave() }
    }

    private func loadStarters() async {
        var built: [BattleSnapshot] = []
        for speciesID in RogueRun.starterPool.shuffled().prefix(3) {
            if let snapshot = await Self.snapshot(speciesID: speciesID, level: 5, store: store) {
                built.append(snapshot)
            }
        }
        setup = built.isEmpty ? .failedToLoad : .choosingStarter(built)
    }

    private func start(with starter: BattleSnapshot) async {
        setup = .loading
        // 판 seed 를 먼저 정한다 — 첫 웨이브의 마릿수 판정이 이 값을 본다.
        let seed = UInt64.random(in: UInt64.min...UInt64.max)
        let opponents = await Self.wilds(wave: 1, route: .safe, seed: seed, store: store)
        guard !opponents.isEmpty else {
            setup = .failedToLoad
            return
        }
        store.rogueRun = RogueRun(party: [starter], opponents: opponents, seed: seed)
    }

    private func loadNextWave() async {
        guard let run = store.rogueRun else { return }
        let opponents = await Self.wilds(wave: run.wave, route: run.route, seed: run.seed, store: store)
        guard !opponents.isEmpty else {
            // 판은 그대로 둔다 — 창을 다시 열면 `resume()` 이 이 웨이브를 다시 불러온다.
            setup = .failedToLoad
            return
        }
        mutate { $0.beginWave(opponents: opponents) }
    }

    /// 이 웨이브의 상대 전원. **한 마리라도 만들었으면 그대로 간다** — 둘째를 못 받았다고 판을
    /// 세우면 네트워크가 흔들릴 때마다 진행 중인 런이 멈춘다.
    private static func wilds(wave: Int, route: RunRoute, seed: UInt64,
                              store: CompanionStore) async -> [BattleSnapshot] {
        var built: [BattleSnapshot] = []
        for _ in 0..<RogueRun.opponentCount(wave: wave, seed: seed) {
            if let one = await wild(wave: wave, route: route, store: store) { built.append(one) }
        }
        return built
    }

    // MARK: 상대 만들기

    /// 웨이브에 맞는 야생 하나. 종을 전 범위에서 균등 추첨하면 웨이브 1 에 슬라킹이 나오므로
    /// 채택 규칙은 코어(`RogueRun.chooseOpponent`)가 든다 — 시뮬레이터와 같은 규칙을 써야 한다.
    private static func wild(wave: Int, route: RunRoute,
                             store: CompanionStore) async -> BattleSnapshot? {
        let level = RogueRun.opponentLevel(wave: wave, route: route)
        return await RogueRun.chooseOpponent(wave: wave, route: route) {
            await snapshot(speciesID: Int.random(in: RogueRun.wildSpeciesPool),
                           level: level, store: store)
        }
    }

    private static func snapshot(speciesID: Int, level: Int,
                                 store: CompanionStore) async -> BattleSnapshot? {
        guard let profile = try? await PokeAPIClient.shared.battleProfile(speciesID: speciesID)
        else { return nil }
        let moves = await PokeAPIClient.shared.moveSet(speciesID: speciesID, level: level,
                                                       types: profile.types)
        let name = await store.resolveSpeciesName(speciesID)
        return BattleSnapshot(speciesID: speciesID, name: name, trainer: nil, level: level,
                              nature: nil, isShiny: false, types: profile.types,
                              base: profile.stats, moves: moves, ability: profile.abilitySlug,
                              weightHectograms: profile.weightHectograms)
    }
}
