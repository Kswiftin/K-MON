import SwiftUI

struct PokemonTFTView: View {
    private enum PlayMode: String, CaseIterable { case solo = "혼자", multiplayer = "친구와" }
    let store: CompanionStore
    let onClose: () -> Void
    @Environment(BattleCenter.self) private var battleCenter
    @State private var game = PokemonTFTGame()
    @State private var selectedUnit: UUID?
    @State private var battleReplay: PokemonTFTBattleReplay?
    @State private var battleFrameIndex = 0
    @State private var battleEffectProgress: CGFloat = 0
    @State private var showSynergyGuide = false
    @State private var playMode: PlayMode = .solo

    private var center: MultiplayerRoomCenter { battleCenter.multiplayer }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PokedoroOverlayHeader(title: "포켓몬 TFT", systemImage: "square.grid.3x3.fill",
                                  tint: .cyan, closeLabel: store.l.close, onClose: close)
            if !center.tftStarted && center.phase == .idle {
                Picker("모드", selection: $playMode) {
                    ForEach(PlayMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented)
            }
            if playMode == .multiplayer && !center.tftStarted { multiplayerEntry }
            else {
                status
                if center.tftStarted { multiplayerStandings }
                switch game.phase {
                case .shopping:
                    if battleReplay != nil { battleArena }
                    else if showSynergyGuide { synergyGuide }
                    else { board; selectedSynergy; bench; shop; controls }
                case .finished(let won): ending(won: won)
                }
            }
        }
        .padding(PopoverMetrics.padding)
        .frame(height: PopoverMetrics.currentHeight(for: .battle))
        .onChange(of: center.tftStarted) { _, started in
            guard started else { return }
            playMode = .multiplayer; game = PokemonTFTGame(); selectedUnit = nil
        }
        .onChange(of: center.tftMatchup) { _, matchup in
            guard let matchup, battleReplay == nil else { return }
            startAnimatedBattle(opponent: matchup.army)
        }
        .onChange(of: center.tftPlayers) { _, players in
            if let me = players.first(where: { $0.id == center.myID }) { game.health = me.health }
        }
    }

    @ViewBuilder private var multiplayerEntry: some View {
        switch center.phase {
        case .idle: multiplayerBrowser
        case .creating, .joining: ProgressView("TFT 방에 연결 중…").frame(maxWidth: .infinity, maxHeight: .infinity)
        case .hosting, .joined: multiplayerLobby
        default:
            Text("다른 LAN 콘텐츠가 진행 중입니다.").foregroundStyle(.secondary)
        }
    }

    private var multiplayerBrowser: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("같은 네트워크의 친구 2~8명과 플레이합니다.")
                .font(.caption).foregroundStyle(.secondary)
            Button("8인 TFT 방 만들기") { center.createPokemonTFTRoom() }
                .buttonStyle(.borderedProminent).tint(.cyan)
            Divider(); Text("참가 가능한 방").font(.caption.bold())
            let rooms = center.rooms.filter {
                LANRoomList.isVisible($0.serviceName, activity: .pokemonTFT, myTag: center.myRoomTag)
            }
            if rooms.isEmpty {
                Text("TFT 방을 찾는 중…").font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(rooms) { room in
                    HStack { Text(room.name).font(.caption); Spacer(); Button("참가") { center.join(room) } }
                }
            }
            if let error = center.lastError { Text(error).font(.caption).foregroundStyle(.orange) }
            Spacer()
        }.padding(10).pokedoroCard()
    }

    private var multiplayerLobby: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack { Text("TFT 로비").font(.headline); Spacer(); Text("\(center.lobby?.runners.count ?? 0)/8") }
            ForEach(center.lobby?.runners ?? []) { player in
                HStack {
                    Image(systemName: player.isHost ? "crown.fill" : "person.fill")
                        .foregroundStyle(player.isHost ? .yellow : .secondary)
                    Text(player.trainerName).font(.caption.bold())
                    Spacer()
                    Text(player.isReady ? "준비" : "대기").font(.caption2)
                        .foregroundStyle(player.isReady ? .green : .secondary)
                }.padding(7).pokedoroCard()
            }
            HStack {
                Button("방 나가기") { center.leaveRoom() }
                Spacer()
                Button(center.myParticipant?.isReady == true ? "준비 취소" : "준비") { center.toggleReady() }
                    .buttonStyle(.borderedProminent).tint(.cyan)
                if center.isHost {
                    Button("시작") { center.startPokemonTFT() }
                        .buttonStyle(.borderedProminent)
                        .disabled(center.lobby?.canStart != true)
                }
            }.controlSize(.small)
            Text("전원이 준비하면 호스트가 시작할 수 있습니다.")
                .font(.caption2).foregroundStyle(.secondary)
        }.padding(10).pokedoroCard()
    }

    private var multiplayerStandings: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 5) {
                Text("R\(center.tftRound)").font(.caption.bold()).foregroundStyle(.cyan)
                ForEach(center.tftPlayers.sorted { $0.health > $1.health }) { player in
                    Text("\(player.trainerName) \(player.health)")
                        .font(.system(size: 9).bold())
                        .foregroundStyle(player.isEliminated ? .secondary : .primary)
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(Color.primary.opacity(0.06), in: Capsule())
                }
            }
        }
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
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { showSynergyGuide.toggle() }
                } label: {
                    Label(showSynergyGuide ? "배치판" : "시너지 도감", systemImage: "books.vertical.fill")
                }.buttonStyle(.plain).foregroundStyle(.cyan)
            }.font(.caption2).foregroundStyle(.secondary)
            Text(game.synergyText()).font(.caption2).foregroundStyle(.secondary)
            Text(game.lastBattleText).font(.caption2).lineLimit(1)
        }.padding(8).pokedoroCard()
    }

    @ViewBuilder private var selectedSynergy: some View {
        if let selectedUnit,
           let unit = game.units.first(where: { $0.id == selectedUnit }) {
            let definition = game.definition(for: unit.definitionID)
            let synergy = game.synergyInfo(for: definition.type)
            HStack(spacing: 6) {
                Circle().fill(definition.type.battleColor).frame(width: 8, height: 8)
                Text("\(definition.name) · \(definition.type.rawValue) 시너지")
                    .font(.caption2.bold())
                Spacer()
                Text("\(synergy.deployed)/\(synergy.nextThreshold ?? 4) · \(synergy.effectText)")
                    .font(.system(size: 9)).foregroundStyle(synergy.deployed >= 2 ? .cyan : .secondary)
            }.padding(.horizontal, 7).padding(.vertical, 5).pokedoroCard()
        }
    }

    private var synergyGuide: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("시너지 도감").font(.headline)
                Spacer(); Text("배치한 같은 타입 2/4마리로 활성화").font(.caption2).foregroundStyle(.secondary)
            }
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(game.synergyGuide) { synergy in
                        HStack(alignment: .top, spacing: 8) {
                            Circle().fill(synergy.type.battleColor).frame(width: 11, height: 11).padding(.top, 3)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(synergy.type.rawValue).font(.caption.bold())
                                    Text("\(synergy.deployed)/\(synergy.nextThreshold ?? 4)")
                                        .font(.caption2.bold()).foregroundStyle(synergy.deployed >= 2 ? .cyan : .secondary)
                                }
                                Text(synergy.effectText).font(.caption2)
                                Text("포함: \(synergy.members.joined(separator: ", "))")
                                    .font(.system(size: 9)).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }.padding(8).pokedoroCard()
                    }
                }
            }
            Button("배치판으로 돌아가기") { withAnimation { showSynergyGuide = false } }
                .buttonStyle(.borderedProminent).tint(.cyan).frame(maxWidth: .infinity)
        }.transition(.opacity)
    }

    private var board: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("배치판 · 포켓몬 선택 후 칸을 누르면 이동").font(.caption2).foregroundStyle(.secondary)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4),
                                     count: PokemonTFTGame.boardColumns), spacing: 4) {
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
            if center.tftStarted {
                if let winner = center.tftWinner {
                    Label("\(winner.trainerName) 우승!", systemImage: "trophy.fill").foregroundStyle(.yellow)
                } else {
                    Button(center.hasSubmittedTFTArmy ? "다른 참가자 대기 중…" : "배치 확정") {
                        center.submitPokemonTFTArmy(game.armySnapshot)
                    }
                    .buttonStyle(.borderedProminent).tint(.cyan)
                    .disabled(game.deployedCount == 0 || center.hasSubmittedTFTArmy ||
                              center.tftPlayers.first(where: { $0.id == center.myID })?.isEliminated == true)
                }
            } else {
                Button("자동 전투") { startAnimatedBattle() }
                    .buttonStyle(.borderedProminent).tint(.cyan).disabled(game.deployedCount == 0)
            }
        }.controlSize(.small)
    }

    private var battleArena: some View {
        let frames = battleReplay?.frames ?? []
        let frame = frames.indices.contains(battleFrameIndex) ? frames[battleFrameIndex] : frames.first
        return VStack(spacing: 6) {
            Text(frame?.message ?? "전투 준비").font(.caption.bold())
                .contentTransition(.numericText())
            GeometryReader { proxy in
                let cellWidth = proxy.size.width / CGFloat(PokemonTFTGame.combatColumns)
                let cellHeight = proxy.size.height / CGFloat(PokemonTFTGame.combatRows)
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
                    if let action = frame?.action, action.kind != .move {
                        battleEffect(action, cellWidth: cellWidth, cellHeight: cellHeight)
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

    private func battleEffect(_ action: PokemonTFTBattleAction,
                              cellWidth: CGFloat, cellHeight: CGFloat) -> some View {
        let startX = (CGFloat(action.sourceX) + 0.5) * cellWidth
        let startY = (CGFloat(action.sourceY) + 0.5) * cellHeight
        let endX = (CGFloat(action.targetX) + 0.5) * cellWidth
        let endY = (CGFloat(action.targetY) + 0.5) * cellHeight
        let x = startX + (endX - startX) * battleEffectProgress
        let y = startY + (endY - startY) * battleEffectProgress
        let isSkill = action.kind == .skill
        return ZStack {
            Circle().fill(action.type.battleColor.opacity(0.25))
                .frame(width: isSkill ? 34 : 20, height: isSkill ? 34 : 20)
                .blur(radius: isSkill ? 5 : 2)
            Image(systemName: isSkill ? "sparkles" : action.kind == .critical ? "burst.fill" : "circle.fill")
                .font(.system(size: isSkill ? 19 : 11, weight: .bold))
                .foregroundStyle(action.type.battleColor)
                .shadow(color: action.type.battleColor, radius: isSkill ? 8 : 3)
        }
        .position(x: x, y: y)
        .scaleEffect(isSkill ? 0.75 + battleEffectProgress * 0.45 : 1)
        .opacity(battleEffectProgress < 0.94 ? 1 : 0.15)
        .allowsHitTesting(false)
    }

    private var battleGrid: some View {
        VStack(spacing: 1) {
            ForEach(0..<PokemonTFTGame.combatRows, id: \.self) { row in
                HStack(spacing: 1) {
                    ForEach(0..<PokemonTFTGame.combatColumns, id: \.self) { _ in
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

    private func startAnimatedBattle(opponent: PokemonTFTArmy? = nil) {
        guard battleReplay == nil, game.deployedCount > 0 else { return }
        selectedUnit = nil
        let replay = game.makeBattleReplay(opponent: opponent)
        battleReplay = replay
        battleFrameIndex = 0
        battleEffectProgress = 0
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(650))
            for index in replay.frames.indices.dropFirst() {
                guard battleReplay != nil else { return }
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    battleFrameIndex = index
                    battleEffectProgress = 0
                }
                await Task.yield()
                withAnimation(.easeIn(duration: 0.18)) { battleEffectProgress = 1 }
                try? await Task.sleep(for: .milliseconds(210))
            }
            try? await Task.sleep(for: .milliseconds(650))
            if center.tftStarted {
                game.settleMultiplayerBattle(playerWon: replay.playerWon)
                center.reportPokemonTFTResult(won: replay.playerWon)
            } else {
                game.settleBattle(playerWon: replay.playerWon)
            }
            withAnimation { battleReplay = nil; battleFrameIndex = 0; battleEffectProgress = 0 }
        }
    }

    private func close() {
        if center.roomActivity == .pokemonTFT { center.leaveRoom() }
        onClose()
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
