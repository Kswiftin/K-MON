import SwiftUI

/// 포켓로그식 런 화면 — **프로토타입**이다. 문구는 아직 `Localization` 을 지나지 않고,
/// 입장권·기록 저장(`RunProgress`)·포획도 없다. 규칙 검증이 끝나면 그때 붙인다.
struct RogueRunView: View {
    @Bindable var store: CompanionStore
    let onClose: () -> Void

    private enum Phase {
        case loading
        case choosingStarter([BattleSnapshot])
        case running(RogueRun)
        case failedToLoad
    }

    @State private var phase: Phase = .loading

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
        .task { await loadStarters() }
    }

    private var header: some View {
        HStack {
            Label(headerTitle, systemImage: "flame.fill").font(.headline)
            Spacer()
            Button(action: onClose) { Image(systemName: "xmark") }.buttonStyle(.plain)
        }
    }

    private var headerTitle: String {
        guard case .running(let run) = phase else { return "Rogue Run" }
        let boss = RogueRun.isBoss(wave: run.wave) ? " · BOSS" : ""
        return "Wave \(run.wave)/\(RogueRun.finalWave)\(boss)"
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .loading:
            ProgressView().frame(maxWidth: .infinity)
        case .failedToLoad:
            VStack(alignment: .leading, spacing: 8) {
                Text("Could not reach PokéAPI. A run needs it to build wild Pokémon.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Retry") { phase = .loading; Task { await loadStarters() } }
            }
        case .choosingStarter(let candidates):
            starterPicker(candidates)
        case .running(let run):
            switch run.stage {
            case .battling:   battlePanel(run)
            case .picking:    rewardPicker(run)
            case .loadingWave: ProgressView().frame(maxWidth: .infinity)
            case .cleared:    ending("Cleared all 12 waves.")
            case .failed:     ending("Party wiped on wave \(run.wave).")
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
        VStack(spacing: 8) {
            BattleFieldView(mine: run.battle.mySlot, theirs: run.battle.opponentSlot,
                            myTitle: run.battle.mySlot.snapshot.name,
                            theirTitle: run.battle.opponentSlot.snapshot.name,
                            l: store.l)
                .frame(height: 150)
            let moves = run.battle.mySlot.moves
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                ForEach(moves.indices, id: \.self) { index in
                    Button {
                        mutate { $0.useMove(index) }
                    } label: {
                        VStack(spacing: 1) {
                            Text(moves[index].name(store.language)).font(.caption)
                            Text("PP \(run.battle.mySlot.pp[index])/\(moves[index].pp)")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(!run.battle.mySlot.canUse(moveAt: index))
                }
            }
            if !run.battle.availableSwitches.isEmpty {
                HStack(spacing: 6) {
                    ForEach(run.battle.availableSwitches, id: \.self) { index in
                        Button(run.party[index].snapshot.name) {
                            mutate { $0.switchParty(to: index) }
                        }
                        .font(.caption2)
                    }
                }
            }
        }
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
            Button("Close", action: onClose)
        }
    }

    // MARK: 진행

    /// `phase` 안의 런을 꺼내 바꾸고 되넣는다 — 뷰가 값 타입 코어를 다루는 유일한 자리다.
    private func mutate(_ body: (inout RogueRun) -> Void) {
        guard case .running(var run) = phase else { return }
        body(&run)
        phase = .running(run)
    }

    private func loadStarters() async {
        var built: [BattleSnapshot] = []
        for speciesID in Self.starterPool.shuffled().prefix(3) {
            if let snapshot = await Self.snapshot(speciesID: speciesID, level: 5, store: store) {
                built.append(snapshot)
            }
        }
        phase = built.isEmpty ? .failedToLoad : .choosingStarter(built)
    }

    private func start(with starter: BattleSnapshot) async {
        phase = .loading
        guard let opponent = await Self.wild(wave: 1, store: store) else {
            phase = .failedToLoad
            return
        }
        phase = .running(RogueRun(party: [starter], opponents: [opponent],
                                  seed: UInt64.random(in: UInt64.min...UInt64.max)))
    }

    private func loadNextWave() async {
        guard case .running(let run) = phase else { return }
        guard let opponent = await Self.wild(wave: run.wave, store: store) else {
            phase = .failedToLoad
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
