import SwiftUI

/// 포켓로그식 런 화면 — **프로토타입**이다. 문구는 아직 `Localization` 을 지나지 않고,
/// 입장권·기록 저장(`RunProgress`)·포획도 없다. 규칙 검증이 끝나면 그때 붙인다.
struct RogueRunView: View {
    @Bindable var store: CompanionStore
    let onClose: () -> Void

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
        guard let run = store.rogueRun else { return "Rogue Run" }
        let boss = RogueRun.isBoss(wave: run.wave) ? " · BOSS" : ""
        return "Wave \(run.wave)/\(RogueRun.finalWave)\(boss)"
    }

    @ViewBuilder
    private var content: some View {
        if let run = store.rogueRun {
            switch run.stage {
            case .battling:   battlePanel(run)
            case .picking:    rewardPicker(run)
            case .loadingWave: ProgressView().frame(maxWidth: .infinity)
            case .cleared:    ending("Cleared all 12 waves.")
            case .failed:     ending("Party wiped on wave \(run.wave).")
            }
        } else {
            switch setup {
            case .loading:
                ProgressView().frame(maxWidth: .infinity)
            case .failedToLoad:
                VStack(alignment: .leading, spacing: 8) {
                    Text("Could not reach PokéAPI. A run needs it to build wild Pokémon.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Retry") { setup = .loading; Task { await loadStarters() } }
                }
            case .choosingStarter(let candidates):
                starterPicker(candidates)
            }
        }
    }

    // MARK: 스타터

    private func starterPicker(_ candidates: [BattleSnapshot]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Pick your starter").font(.caption).foregroundStyle(.secondary)
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
        // 기존 배틀·팀 연습과 **같은 렌더러**를 쓴다. 직접 그리면 기술 버튼의 타입 색·PP 배지·로그가
        // 이 화면만 달라져, 같은 기술이 화면마다 다른 색으로 보인다(실제로 그렇게 어긋났다).
        let me = run.battle.mySlot
        let opponent = run.battle.opponentSlot
        return BattleArenaView(
            mine: me, theirs: opponent,
            myTitle: store.l.battleMyPokemon,
            theirTitle: RogueRun.isBoss(wave: run.wave) ? "BOSS" : "Wild",
            l: store.l, turn: run.battle.turn,
            logLines: BattleLogSource.twoSided(run.battle.events, mine: .a, l: store.l,
                                               myName: me.snapshot.name,
                                               theirName: opponent.snapshot.name,
                                               myMoves: me.moves, theirMoves: opponent.moves),
            myActor: .a,
            switchSlots: SwitchStripModel.slots(run.battle.mine, active: run.battle.myActive),
            turnEndsAt: nil,
            isWaitingForOpponent: false,
            onChoose: { index in mutate { $0.useMove(index) } },
            onSwitch: { index in mutate { $0.switchParty(to: index) } },
            // 항복은 런 포기다 — 판을 버리고 나간다(프로토라 기록도 남지 않는다).
            onForfeit: { store.rogueRun = nil; onClose() })
    }

    // MARK: 보상

    private func rewardPicker(_ run: RogueRun) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Wave \(run.wave) cleared — pick one").font(.caption).foregroundStyle(.secondary)
            ForEach(run.offers, id: \.self) { offer in
                Button {
                    mutate { $0.pick(offer) }
                    Task { await loadNextWave() }
                } label: {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(Self.title(offer)).font(.callout.bold())
                        Text(Self.detail(offer)).font(.caption2).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private static func title(_ modifier: RunModifier) -> String {
        switch modifier {
        case .potion:  return "Potion"
        case .revive:  return "Revive"
        case .candy:   return "Rare Candy"
        case .elixir:  return "Elixir"
        case .cleanse: return "Full Heal"
        }
    }

    private static func detail(_ modifier: RunModifier) -> String {
        switch modifier {
        case .potion:  return "Heal 40% of max HP on every conscious member."
        case .revive:  return "Bring one fainted member back at half HP."
        case .candy:   return "The whole party gains 2 levels."
        case .elixir:  return "Restore every move's PP."
        case .cleanse: return "Clear status and confusion from the party."
        }
    }

    private func ending(_ line: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(line).font(.callout)
            // 끝난 판은 여기서 비운다 — 남겨 두면 다음에 던전 탭을 열 때 결과 화면이 다시 뜬다.
            Button("Close") { store.rogueRun = nil; onClose() }
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

    private static func wild(wave: Int, store: CompanionStore) async -> BattleSnapshot? {
        await snapshot(speciesID: Int.random(in: wildPool),
                       level: RogueRun.opponentLevel(wave: wave), store: store)
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
