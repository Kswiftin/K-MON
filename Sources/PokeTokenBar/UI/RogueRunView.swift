import SwiftUI

/// 포켓로그식 런 화면 — **프로토타입**이다. 입장권·기록 저장(`RunProgress`)이 아직 없다.
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

    /// 스타터 후보 — 프로토타입은 1세대 기본형에서 고정 풀로 뽑는다(진화 루트 조회를 아직 안 탄다).
    private static let starterPool = [1, 4, 7, 25, 152, 155, 158]
    private static let wildPool = 1...649

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            content
            Spacer(minLength: 0)
        }
        .padding(PopoverMetrics.padding)
        .frame(height: PopoverMetrics.currentHeight(for: .battle))
        .task { await resume() }
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
            switch run.stage {
            case .battling:   battlePanel(run)
            case .picking:    rewardPicker(run)
            case .loadingWave: ProgressView().frame(maxWidth: .infinity)
            case .cleared:    ending(l.t("12 웨이브를 모두 돌파했다.", "Cleared all 12 waves.",
                                          "12ウェーブすべてを突破した。"))
            case .failed:     ending(l.t("웨이브 \(run.wave) 에서 파티가 전멸했다.",
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
            Button(l.t("잡기", "Catch", "捕まえる")) { mutate { _ = $0.throwBall() } }
                .disabled(!run.canThrowBall)
        }
        .font(.caption)
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
            Text(l.t("웨이브 \(run.wave) 돌파 — 하나를 고른다",
                     "Wave \(run.wave) cleared — pick one",
                     "ウェーブ \(run.wave) 突破 — 一つ選ぶ"))
                .font(.caption).foregroundStyle(.secondary)
            ForEach(run.offers, id: \.self) { offer in
                Button {
                    mutate { $0.pick(offer) }
                    Task { await loadNextWave() }
                } label: {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(Self.title(offer, l)).font(.callout.bold())
                        Text(Self.detail(offer, l)).font(.caption2).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private static func title(_ modifier: RunModifier, _ l: L) -> String {
        switch modifier {
        case .potion:  return l.t("상처약", "Potion", "きずぐすり")
        case .revive:  return l.t("기력의조각", "Revive", "げんきのかけら")
        case .candy:   return l.t("이상한사탕", "Rare Candy", "ふしぎなアメ")
        case .elixir:  return l.t("엘릭서", "Elixir", "エリキシル")
        case .cleanse: return l.t("만병통치제", "Full Heal", "なんでもなおし")
        }
    }

    private static func detail(_ modifier: RunModifier, _ l: L) -> String {
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
        }
    }

    private func ending(_ line: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(line).font(.callout)
            // 끝난 판은 여기서 비운다 — 남겨 두면 다음에 던전 탭을 열 때 결과 화면이 다시 뜬다.
            Button(l.battleClose) { store.rogueRun = nil; onClose() }
        }
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
        for speciesID in Self.starterPool.shuffled().prefix(3) {
            if let snapshot = await Self.snapshot(speciesID: speciesID, level: 5, store: store) {
                built.append(snapshot)
            }
        }
        setup = built.isEmpty ? .failedToLoad : .choosingStarter(built)
    }

    private func start(with starter: BattleSnapshot) async {
        setup = .loading
        guard let opponent = await Self.wild(wave: 1, store: store) else {
            setup = .failedToLoad
            return
        }
        store.rogueRun = RogueRun(party: [starter], opponents: [opponent],
                                  seed: UInt64.random(in: UInt64.min...UInt64.max))
    }

    private func loadNextWave() async {
        guard let run = store.rogueRun else { return }
        guard let opponent = await Self.wild(wave: run.wave, store: store) else {
            // 판은 그대로 둔다 — 창을 다시 열면 `resume()` 이 이 웨이브를 다시 불러온다.
            setup = .failedToLoad
            return
        }
        mutate { $0.beginWave(opponents: [opponent]) }
    }

    // MARK: 상대 만들기

    /// 웨이브에 맞는 야생 하나. 종을 전 범위에서 균등 추첨하면 웨이브 1 에 슬라킹이 나오므로
    /// **종족값 합이 웨이브 티어에 드는 종만** 받는다(`RogueRun.isFairOpponent`). 뽑기는 몇 번만
    /// 돌리고, 다 어긋나면 그중 가장 약한 종으로 간다 — 판을 못 여는 것보다 낫다.
    private static let wildDrawAttempts = 8

    private static func wild(wave: Int, store: CompanionStore) async -> BattleSnapshot? {
        let level = RogueRun.opponentLevel(wave: wave)
        var weakest: BattleSnapshot?
        for _ in 0..<wildDrawAttempts {
            guard let candidate = await snapshot(speciesID: Int.random(in: wildPool),
                                                 level: level, store: store) else { continue }
            if RogueRun.isFairOpponent(baseStats: candidate.base, wave: wave) { return candidate }
            if weakest.map({ total($0.base) > total(candidate.base) }) ?? true { weakest = candidate }
        }
        return weakest
    }

    private static func total(_ stats: BattleStats) -> Int {
        stats.hp + stats.atk + stats.def + stats.spa + stats.spd + stats.spe
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
