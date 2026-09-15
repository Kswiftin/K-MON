import SwiftUI

struct PokemonTFTView: View {
    let store: CompanionStore
    let onClose: () -> Void
    @State private var game = PokemonTFTGame()
    @State private var selectedUnit: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PokedoroOverlayHeader(title: "포켓몬 TFT", systemImage: "square.grid.3x3.fill",
                                  tint: .cyan, closeLabel: store.l.close, onClose: onClose)
            status
            switch game.phase {
            case .shopping: board; bench; shop; controls
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
            Button("자동 전투") { selectedUnit = nil; game.fight() }
                .buttonStyle(.borderedProminent).tint(.cyan).disabled(game.deployedCount == 0)
        }.controlSize(.small)
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
