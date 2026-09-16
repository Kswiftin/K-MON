import SwiftUI

struct PokemonTFTView: View {
    let store: CompanionStore
    let onClose: () -> Void
    @State private var game = PokemonTFTGame()
    @State private var selectedUnit: UUID?
    @State private var battleReplay: PokemonTFTBattleReplay?
    @State private var battleFrameIndex = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PokedoroOverlayHeader(title: "포켓몬 TFT", systemImage: "square.grid.3x3.fill",
                                  tint: .cyan, closeLabel: store.l.close, onClose: onClose)
            status
            switch game.phase {
            case .shopping:
                if battleReplay != nil { battleArena }
                else { board; bench; shop; controls }
            case .finished(let won): ending(won: won)
            }
        }
        .padding(PopoverMetrics.padding)
        .frame(height: PopoverMetrics.currentHeight(for: .battle))
    }

    private var status: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Label("라운드 \(game.round)/\(PokemonTFTGame.finalRound)", systemImage: "flag.fill")
                Spacer(); Label("\(game.health)", systemImage: "heart.fill").foregroundStyle(.red)
                Label("\(game.gold)", systemImage: "circle.fill").foregroundStyle(.yellow)
            }.font(.caption.bold())
            HStack {
                Text("Lv.\(game.level) · 배치 \(game.deployedCount)/\(game.unitLimit)")
                Spacer(); Text(game.synergyText())
            }.font(.caption2).foregroundStyle(.secondary)
            Text(game.lastBattleText).font(.caption2).lineLimit(1)
        }.padding(8).pokedoroCard()
    }

    private var board: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("배치판 · 포켓몬 선택 후 칸을 누르면 이동").font(.caption2).foregroundStyle(.secondary)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 3), spacing: 4) {
                ForEach(0..<PokemonTFTGame.boardSlots, id: \.self) { slot in
                    let unit = game.units.first { $0.boardSlot == slot }
                    Button { boardTap(slot: slot, unit: unit) } label: {
                        ZStack {
                            RoundedRectangle(cornerRadius: 7).fill(slot < 3 ? Color.blue.opacity(0.12) : Color.green.opacity(0.10))
                            if let unit { unitTile(unit, compact: true) }
                            else { Image(systemName: "plus").foregroundStyle(.tertiary) }
                        }.frame(height: 52)
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    private var bench: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("대기석 \(game.benchCount)/\(PokemonTFTGame.benchLimit)").font(.caption2).foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    ForEach(game.units.filter { $0.boardSlot == nil }) { unit in
                        Button { selectedUnit = selectedUnit == unit.id ? nil : unit.id } label: {
                            unitTile(unit, compact: false)
                                .overlay(RoundedRectangle(cornerRadius: 7).stroke(selectedUnit == unit.id ? .cyan : .clear, lineWidth: 2))
                        }.buttonStyle(.plain).contextMenu { Button("판매") { game.sell(unit.id) } }
                    }
                }
            }.frame(height: 62)
        }
    }

    private var shop: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack { Text("상점").font(.caption.bold()); Spacer(); Button("새로고침 2G") { game.refreshShop() }.controlSize(.mini) }
            HStack(spacing: 5) {
                ForEach(game.shop.indices, id: \.self) { index in
                    if let id = game.shop[index] {
                        let definition = game.definition(for: id)
                        Button { _ = game.buy(shopIndex: index) } label: {
                            VStack(spacing: 0) {
                                SpriteView(speciesID: id, size: 34, animated: false, shiny: false, back: false)
                                Text(definition.name).font(.system(size: 9)).lineLimit(1)
                                Text("\(definition.cost)G").font(.system(size: 9).bold()).foregroundStyle(.yellow)
                            }.frame(maxWidth: .infinity).padding(3).pokedoroCard()
                        }.buttonStyle(.plain).disabled(game.gold < definition.cost || game.benchCount >= PokemonTFTGame.benchLimit)
                    } else { Color.clear.frame(maxWidth: .infinity, minHeight: 52) }
                }
            }
        }
    }

    private var controls: some View {
        HStack {
            Button("XP +4 · 4G") { game.buyExperience() }.disabled(game.gold < 4 || game.level >= 6)
            if let selectedUnit { Button("판매") { game.sell(selectedUnit); self.selectedUnit = nil } }
            Spacer()
            Button("자동 전투") { startAnimatedBattle() }
                .buttonStyle(.borderedProminent).tint(.cyan).disabled(game.deployedCount == 0)
        }.controlSize(.small)
    }

    private var battleArena: some View {
        let frames = battleReplay?.frames ?? []
        let frame = frames.indices.contains(battleFrameIndex) ? frames[battleFrameIndex] : frames.first
        return VStack(spacing: 6) {
            Text(frame?.message ?? "전투 준비").font(.caption.bold())
                .contentTransition(.numericText())
            GeometryReader { proxy in
                let cellWidth = proxy.size.width / 6
                let cellHeight = proxy.size.height / 6
                ZStack(alignment: .topLeading) {
                    battleGrid
                    ForEach(frame?.fighters ?? []) { fighter in
                        fighterView(fighter, width: cellWidth, height: cellHeight)
                            .offset(x: CGFloat(fighter.x) * cellWidth,
                                    y: CGFloat(fighter.y) * cellHeight)
                            .animation(.easeInOut(duration: 0.16), value: fighter.x)
                            .animation(.easeInOut(duration: 0.16), value: fighter.y)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
            }
            .frame(height: 330)
            Text("가장 가까운 상대를 추적해 이동하고, 사거리 안에서 공격합니다.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(10)
        .pokedoroCard()
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
    }

    private var battleGrid: some View {
        VStack(spacing: 1) {
            ForEach(0..<6, id: \.self) { row in
                HStack(spacing: 1) {
                    ForEach(0..<6, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(row < 3 ? Color.red.opacity(0.07) : Color.blue.opacity(0.08))
                    }
                }
            }
        }
    }

    private func fighterView(_ fighter: PokemonTFTFighter, width: CGFloat, height: CGFloat) -> some View {
        VStack(spacing: 0) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.black.opacity(0.15))
                    Capsule().fill(fighter.team == .player ? Color.green : Color.red)
                        .frame(width: proxy.size.width * CGFloat(fighter.hp) / CGFloat(max(1, fighter.maxHP)))
                }
            }
            .frame(width: max(24, width - 8), height: 4)
            SpriteView(speciesID: fighter.speciesID, size: min(42, height - 9), animated: true,
                       shiny: false, back: fighter.team == .player)
        }
        .frame(width: width, height: height)
        .opacity(fighter.hp > 0 ? 1 : 0)
        .scaleEffect(fighter.hp > 0 ? 1 : 0.3)
        .animation(.easeOut(duration: 0.2), value: fighter.hp)
    }

    private func startAnimatedBattle() {
        guard battleReplay == nil, game.deployedCount > 0 else { return }
        selectedUnit = nil
        let replay = game.makeBattleReplay()
        battleReplay = replay
        battleFrameIndex = 0
        Task { @MainActor in
            for index in replay.frames.indices.dropFirst() {
                guard battleReplay != nil else { return }
                withAnimation { battleFrameIndex = index }
                try? await Task.sleep(for: .milliseconds(220))
            }
            try? await Task.sleep(for: .milliseconds(500))
            game.settleBattle(playerWon: replay.playerWon)
            withAnimation { battleReplay = nil; battleFrameIndex = 0 }
        }
    }

    private func unitTile(_ unit: PokemonTFTUnit, compact: Bool) -> some View {
        let definition = game.definition(for: unit.definitionID)
        return VStack(spacing: 0) {
            SpriteView(speciesID: definition.id, size: compact ? 31 : 34, animated: false, shiny: false, back: false)
            Text(String(repeating: "★", count: unit.star)).font(.system(size: 8)).foregroundStyle(.yellow)
            if !compact { Text(definition.name).font(.system(size: 9)).lineLimit(1) }
        }.padding(2).background(selectedUnit == unit.id ? Color.cyan.opacity(0.12) : .clear).clipShape(RoundedRectangle(cornerRadius: 7))
    }

    private func boardTap(slot: Int, unit: PokemonTFTUnit?) {
        if let selectedUnit { game.move(selectedUnit, to: slot); self.selectedUnit = nil }
        else if let unit { selectedUnit = unit.id }
    }

    private func ending(won: Bool) -> some View {
        VStack(spacing: 14) {
            Spacer(); Image(systemName: won ? "trophy.fill" : "heart.slash.fill").font(.system(size: 44)).foregroundStyle(won ? .yellow : .red)
            Text(won ? "챔피언! 12라운드를 모두 돌파했습니다." : "도전 종료 · \(game.round)라운드")
                .font(.headline)
            Button("새 게임") { game = PokemonTFTGame(); selectedUnit = nil }.buttonStyle(.borderedProminent)
            Spacer()
        }.frame(maxWidth: .infinity)
    }
}
