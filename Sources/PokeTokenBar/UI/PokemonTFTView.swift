import SwiftUI

struct PokemonTFTView: View {
    private enum PlayMode { case solo, multiplayer }
    private let arenaInk = Color(red: 0.055, green: 0.075, blue: 0.13)
    private let arenaPanel = Color(red: 0.09, green: 0.12, blue: 0.20)
    private let arenaBlue = Color(red: 0.20, green: 0.66, blue: 0.96)
    private let arenaGold = Color(red: 1.00, green: 0.76, blue: 0.22)
    let store: CompanionStore
    let onClose: () -> Void
    @Environment(BattleCenter.self) private var battleCenter
    @State private var selectedUnit: UUID?
    @State private var battleReplay: PokemonTFTBattleReplay?
    @State private var battleFrameIndex = 0
    @State private var battleEffectProgress: CGFloat = 0
    @State private var showSynergyGuide = false
    @State private var showBeginnerGuide = false
    @State private var playMode: PlayMode?

    private var center: MultiplayerRoomCenter { battleCenter.multiplayer }
    private var game: PokemonTFTGame {
        get { battleCenter.pokemonTFTGame }
        nonmutating set { battleCenter.pokemonTFTGame = newValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PokedoroOverlayHeader(title: "포켓몬 TFT", systemImage: "square.grid.3x3.fill",
                                  tint: .cyan, closeLabel: store.l.close, onClose: close)
            if playMode == nil && !center.tftStarted { modeSelection }
            else if playMode == .multiplayer && !center.tftStarted { multiplayerEntry }
            else {
                status
                if center.tftStarted { multiplayerStandings }
                if showBeginnerGuide {
                    beginnerGuide
                } else {
                    switch game.phase {
                    case .shopping:
                        if battleReplay != nil { battleArena }
                        else if showSynergyGuide { synergyGuide }
                        else { board; bench; shop; controls; fieldSynergyBar }
                    case .finished(let won): ending(won: won)
                    }
                }
            }
        }
        .padding(PopoverMetrics.padding)
        .frame(height: PopoverMetrics.currentHeight(for: .battle))
        .background(
            LinearGradient(colors: [Color(red: 0.93, green: 0.96, blue: 1),
                                    Color(red: 0.86, green: 0.91, blue: 0.98)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        )
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
        .onAppear {
            if center.tftStarted {
                playMode = .multiplayer
                resumeCurrentMatchupIfNeeded()
            }
        }
    }

    private var modeSelection: some View {
        VStack(spacing: 18) {
            Spacer()
            ZStack {
                Circle().fill(arenaBlue.opacity(0.16)).frame(width: 82, height: 82)
                Image(systemName: "square.grid.3x3.fill")
                    .font(.system(size: 38, weight: .black)).foregroundStyle(arenaBlue)
            }
            VStack(spacing: 4) {
                Text("포켓몬 TFT").font(.title2.bold()).foregroundStyle(.white)
                Text("포켓몬을 모으고 배치해 최후의 트레이너가 되세요")
                    .font(.caption).foregroundStyle(.white.opacity(0.68))
            }
            HStack(spacing: 10) {
                modeCard(title: "혼자 하기", subtitle: "바로 이어서 플레이", icon: "person.fill",
                         tint: arenaBlue) { playMode = .solo }
                modeCard(title: "친구랑 하기", subtitle: "LAN 2~8인 대전", icon: "person.3.fill",
                         tint: .purple) { playMode = .multiplayer }
            }
            Spacer()
        }
        .padding(18)
        .background(LinearGradient(colors: [arenaPanel, arenaInk], startPoint: .top, endPoint: .bottom),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(arenaBlue.opacity(0.25)))
    }

    private func modeCard(title: String, subtitle: String, icon: String, tint: Color,
                          action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Image(systemName: icon).font(.system(size: 25, weight: .bold))
                Text(title).font(.headline)
                Text(subtitle).font(.caption2).foregroundStyle(.white.opacity(0.64))
            }
            .foregroundStyle(.white).frame(maxWidth: .infinity).padding(.vertical, 15)
            .background(tint.opacity(0.22), in: RoundedRectangle(cornerRadius: 13))
            .overlay(RoundedRectangle(cornerRadius: 13).stroke(tint.opacity(0.72), lineWidth: 1.5))
        }.buttonStyle(.plain)
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
            HStack {
                Text("같은 네트워크의 친구 2~8명과 플레이합니다.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("방식 다시 선택") { playMode = nil }.controlSize(.mini)
            }
            Button("8인 TFT 방 만들기") { center.createPokemonTFTRoom() }
                .buttonStyle(.borderedProminent).tint(PokedoroTheme.blue)
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
                    .buttonStyle(.borderedProminent).tint(PokedoroTheme.blue)
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
                        .font(.caption2.bold())
                        .foregroundStyle(player.isEliminated ? .secondary : .primary)
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(Color.primary.opacity(0.06), in: Capsule())
                }
            }
        }
    }

    private var status: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                hudChip("ROUND \(game.round)", icon: "flag.checkered", tint: arenaBlue)
                Spacer()
                hudChip("\(game.health)", icon: "heart.fill", tint: .red)
                hudChip("\(game.gold)G", icon: "dollarsign.circle.fill", tint: arenaGold)
            }
            HStack {
                Text("Lv.\(game.level)").font(.caption.bold()).foregroundStyle(.white)
                ProgressView(value: Double(game.experience), total: Double(max(1, game.experienceNeeded)))
                    .tint(arenaBlue).frame(width: 76)
                Text("배치 \(game.deployedCount)/\(game.unitLimit)")
                Spacer()
                Button {
                    withAnimation { showBeginnerGuide = true; showSynergyGuide = false }
                } label: {
                    Label("가이드", systemImage: "questionmark.circle.fill")
                }.buttonStyle(.plain).foregroundStyle(.mint).disabled(battleReplay != nil)
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { showSynergyGuide.toggle() }
                } label: {
                    Label(showSynergyGuide ? "배치판" : "시너지 도감", systemImage: "books.vertical.fill")
                }.buttonStyle(.plain).foregroundStyle(arenaBlue)
            }.font(.caption2).foregroundStyle(.white.opacity(0.7))
            Text(game.lastBattleText).font(.caption2).lineLimit(1).foregroundStyle(.white.opacity(0.8))
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(LinearGradient(colors: [arenaPanel, arenaInk], startPoint: .leading, endPoint: .trailing),
                    in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.09)))
    }

    private func hudChip(_ text: String, icon: String, tint: Color) -> some View {
        Label(text, systemImage: icon)
            .font(.caption.bold()).foregroundStyle(.white)
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(tint.opacity(0.22), in: Capsule())
            .overlay(Capsule().stroke(tint.opacity(0.7)))
    }

    private func fieldSynergyChip(_ synergy: PokemonTFTGame.SynergyInfo) -> some View {
        let active = synergy.deployed >= 2
        let target = synergy.deployed >= 4 ? 6 : synergy.deployed >= 2 ? 4 : 2
        let tier = synergy.deployed >= 6 ? 45 : synergy.deployed >= 4 ? 25 : active ? 10 : 0
        return HStack(spacing: 4) {
            Circle().fill(synergy.type.battleColor).frame(width: 7, height: 7)
            Text("\(synergy.type.rawValue) \(min(synergy.deployed, 6))/\(target)")
            if active { Text("+\(tier)%") }
        }
        .font(.caption2.bold()).foregroundStyle(active ? .white : .white.opacity(0.58))
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(synergy.type.battleColor.opacity(active ? 0.28 : 0.10), in: Capsule())
        .overlay(Capsule().stroke(synergy.type.battleColor.opacity(active ? 0.72 : 0.30)))
    }

    private var fieldSynergyBar: some View {
        HStack(spacing: 6) {
            Label("필드 시너지", systemImage: "sparkles")
                .font(.caption2.bold()).foregroundStyle(.white.opacity(0.7))
            if game.fieldSynergies.isEmpty {
                Text("포켓몬을 배치하면 조합이 표시됩니다")
                    .font(.caption2).foregroundStyle(.white.opacity(0.4))
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 5) {
                        ForEach(game.fieldSynergies) { synergy in fieldSynergyChip(synergy) }
                    }
                }
            }
        }
        .padding(.horizontal, 8).frame(height: 30)
        .background(arenaInk.opacity(0.94), in: RoundedRectangle(cornerRadius: 9))
    }

    private var synergyGuide: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("시너지 도감").font(.headline)
                Spacer(); Text("같은 타입 2/4/6마리로 강화").font(.caption2).foregroundStyle(.secondary)
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
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }.padding(8).pokedoroCard()
                    }
                }
            }
            Button("배치판으로 돌아가기") { withAnimation { showSynergyGuide = false } }
                .buttonStyle(.borderedProminent).tint(PokedoroTheme.blue).frame(maxWidth: .infinity)
        }.transition(.opacity)
    }

    private var beginnerGuide: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("처음 하는 트레이너 가이드", systemImage: "graduationcap.fill").font(.headline)
                Spacer()
                Button("닫기") { withAnimation { showBeginnerGuide = false } }
            }
            guideRow("1", "상점에서 포켓몬을 사고 대기석에 모으세요. 새로고침은 2G입니다.")
            guideRow("2", "같은 포켓몬 3마리를 모으면 2성이 되며 다음 진화체로 진화합니다.")
            guideRow("3", "필드에는 레벨만큼 배치할 수 있습니다. 같은 타입 2·4·6마리로 시너지가 강화됩니다.")
            guideRow("4", "매 라운드 자동으로 2 XP를 받고, 4G를 쓰면 XP 4를 추가로 살 수 있습니다.")
            guideRow("5", "승패와 무관하게 기본 수입과 이자를 받으며 연승·연패 보너스도 쌓입니다.")
            guideRow("6", "멀티에서는 배치를 확정하면 상대가 정해집니다. 체력이 0이 되면 탈락합니다.")
            Spacer()
        }
        .padding(12).pokedoroCard()
    }

    private func guideRow(_ number: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(number).font(.caption.bold()).foregroundStyle(.white)
                .frame(width: 22, height: 22).background(arenaBlue, in: Circle())
            Text(text).font(.caption).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var board: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Label("배치판", systemImage: "scope").font(.caption.bold()).foregroundStyle(.white)
                Spacer()
                Text("선택 후 이동 · 다시 누르면 대기석").font(.caption2).foregroundStyle(.white.opacity(0.55))
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4),
                                     count: PokemonTFTGame.boardColumns), spacing: 4) {
                ForEach(0..<PokemonTFTGame.boardSlots, id: \.self) { slot in
                    let unit = game.units.first { $0.boardSlot == slot }
                    Button { boardTap(slot: slot, unit: unit) } label: {
                        ZStack {
                            TFTArenaCell()
                                .fill(slot < 4 ? arenaBlue.opacity(0.15) : Color.teal.opacity(0.12))
                            TFTArenaCell().stroke(.white.opacity(0.12), lineWidth: 1)
                            if let unit { unitTile(unit, compact: true) }
                            else { Circle().fill(.white.opacity(0.07)).frame(width: 6, height: 6) }
                        }.frame(height: 52)
                    }.buttonStyle(.plain)
                        .accessibilityLabel(unit.map { "\(game.definition(for: $0.definitionID).name) 배치 칸" }
                            ?? "빈 배치 칸 \(slot + 1)")
                }
            }
        }
        .padding(8)
        .background {
            ZStack {
                LinearGradient(colors: [arenaPanel, arenaInk], startPoint: .top, endPoint: .bottom)
                RadialGradient(colors: [arenaBlue.opacity(0.18), .clear], center: .center,
                               startRadius: 5, endRadius: 190)
            }.clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(arenaBlue.opacity(0.22)))
    }

    private var bench: some View {
        let waiting = game.units.filter { $0.boardSlot == nil }
        return VStack(alignment: .leading, spacing: 3) {
            HStack {
                Label("대기석", systemImage: "rectangle.stack.fill")
                Spacer()
                if let selectedUnit,
                   game.units.first(where: { $0.id == selectedUnit })?.boardSlot != nil {
                    Button("선택 포켓몬 내리기") {
                        game.moveToBench(selectedUnit)
                        self.selectedUnit = nil
                    }.buttonStyle(.plain).foregroundStyle(arenaBlue)
                }
                Text("\(game.benchCount)/\(PokemonTFTGame.benchLimit)")
            }.font(.caption2.bold()).foregroundStyle(.white.opacity(0.7))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    ForEach(0..<PokemonTFTGame.benchLimit, id: \.self) { index in
                        if waiting.indices.contains(index) {
                            let unit = waiting[index]
                            Button { selectedUnit = selectedUnit == unit.id ? nil : unit.id } label: {
                                unitTile(unit, compact: false)
                                    .frame(width: 48, height: 48)
                            }.buttonStyle(.plain).contextMenu { Button("판매") { game.sell(unit.id) } }
                        } else {
                            RoundedRectangle(cornerRadius: 7)
                                .fill(.white.opacity(0.035))
                                .overlay(RoundedRectangle(cornerRadius: 7).stroke(.white.opacity(0.07)))
                                .frame(width: 48, height: 48)
                        }
                    }
                }
            }.frame(height: 50)
        }
        .padding(7).frame(height: 76)
        .background(arenaInk.opacity(0.94), in: RoundedRectangle(cornerRadius: 11))
    }

    private var shop: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Label("상점", systemImage: "cart.fill").font(.caption.bold())
                Text("보유 \(game.gold)G").font(.caption2.bold()).foregroundStyle(arenaGold)
                Spacer()
                Button { game.refreshShop() } label: { Label("2G", systemImage: "arrow.clockwise") }
                    .controlSize(.mini).buttonStyle(.bordered).tint(arenaBlue)
            }.foregroundStyle(.white)
            HStack(spacing: 5) {
                ForEach(game.shop.indices, id: \.self) { index in
                    if let id = game.shop[index] {
                        let definition = game.definition(for: id)
                        Button { _ = game.buy(shopIndex: index) } label: {
                            shopCard(definition)
                        }.buttonStyle(.plain).disabled(game.gold < definition.cost || game.benchCount >= PokemonTFTGame.benchLimit)
                    } else {
                        RoundedRectangle(cornerRadius: 9).fill(.white.opacity(0.035))
                            .frame(maxWidth: .infinity, minHeight: 61)
                    }
                }
            }.frame(height: 63)
        }.padding(8).background(arenaPanel, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.09)))
    }

    private func shopCard(_ definition: PokemonTFTUnitDefinition) -> some View {
        let rarity = rarityColor(cost: definition.cost)
        return VStack(spacing: 1) {
            ZStack(alignment: .topTrailing) {
                SpriteView(speciesID: definition.id, size: 35, animated: false, shiny: false, back: false)
                    .frame(maxWidth: .infinity)
                Circle().fill(definition.type.battleColor).frame(width: 8, height: 8)
            }
            Text(definition.name).font(.caption2.bold()).lineLimit(1).foregroundStyle(.white)
            Text("\(definition.cost)G").font(.caption2.bold()).foregroundStyle(arenaGold)
        }
        .frame(maxWidth: .infinity).padding(4)
        .background(LinearGradient(colors: [rarity.opacity(0.35), arenaInk],
                                   startPoint: .top, endPoint: .bottom),
                    in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(rarity.opacity(0.85), lineWidth: 1))
    }

    private func rarityColor(cost: Int) -> Color {
        switch cost {
        case 1: .gray
        case 2: .green
        case 3: arenaBlue
        case 4: .purple
        default: arenaGold
        }
    }

    private var controls: some View {
        HStack {
            Button { game.buyExperience() } label: {
                Label("XP +4", systemImage: "bolt.fill")
            }.disabled(game.gold < 4 || game.level >= 6)
            Text("4G").font(.caption2.bold()).foregroundStyle(arenaGold)
            if let selectedUnit { Button("판매") { game.sell(selectedUnit); self.selectedUnit = nil } }
            Button("기권", role: .destructive) { forfeitTFT() }
            Spacer()
            if center.tftStarted {
                if let winner = center.tftWinner {
                    Label("\(winner.trainerName) 우승!", systemImage: "trophy.fill").foregroundStyle(.yellow)
                } else {
                    Button(center.hasSubmittedTFTArmy ? "다른 참가자 대기 중…" : "배치 확정") {
                        center.submitPokemonTFTArmy(game.armySnapshot)
                    }
                    .buttonStyle(.borderedProminent).tint(PokedoroTheme.blue)
                    .disabled(game.deployedCount == 0 || center.hasSubmittedTFTArmy ||
                              center.tftPlayers.first(where: { $0.id == center.myID })?.isEliminated == true)
                }
            } else {
                Button("자동 전투") { startAnimatedBattle() }
                    .buttonStyle(.borderedProminent).tint(PokedoroTheme.blue).disabled(game.deployedCount == 0)
            }
        }.controlSize(.small).padding(.horizontal, 4)
    }

    private var battleArena: some View {
        let frames = battleReplay?.frames ?? []
        let frame = frames.indices.contains(battleFrameIndex) ? frames[battleFrameIndex] : frames.first
        return VStack(spacing: 6) {
            HStack {
                Spacer()
                Text(center.tftMatchup.map { "VS \($0.opponentName)" } ?? "VS CPU 트레이너")
                    .font(.headline.bold()).foregroundStyle(arenaGold)
                Spacer()
                Button("기권", role: .destructive) { forfeitTFT() }.controlSize(.mini)
            }
            Text(frame?.message ?? "전투 준비").font(.caption.bold()).foregroundStyle(.white)
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
            Text("LIVE BATTLE · 가장 가까운 상대를 추적합니다")
                .font(.caption2.bold()).foregroundStyle(arenaBlue)
        }
        .padding(10)
        .background(arenaInk, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(arenaBlue.opacity(0.35)))
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
                            .fill(row < 3 ? Color.red.opacity(0.13) : arenaBlue.opacity(0.13))
                            .overlay(RoundedRectangle(cornerRadius: 3).stroke(.white.opacity(0.06)))
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
        if let matchup = center.tftMatchup {
            guard battleCenter.pokemonTFTResolvingRound != matchup.round else { return }
            battleCenter.pokemonTFTResolvingRound = matchup.round
        } else {
            guard !battleCenter.isPokemonTFTSoloBattleRunning else { return }
            battleCenter.isPokemonTFTSoloBattleRunning = true
        }
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
                battleCenter.pokemonTFTResolvingRound = nil
            } else {
                game.settleBattle(playerWon: replay.playerWon)
                battleCenter.isPokemonTFTSoloBattleRunning = false
            }
            withAnimation { battleReplay = nil; battleFrameIndex = 0; battleEffectProgress = 0 }
        }
    }

    private func forfeitTFT() {
        battleReplay = nil
        battleFrameIndex = 0
        battleEffectProgress = 0
        battleCenter.isPokemonTFTSoloBattleRunning = false
        battleCenter.pokemonTFTResolvingRound = nil
        if center.tftStarted { center.forfeitPokemonTFT() }
        else { game.phase = .finished(won: false) }
    }

    private func close() {
        onClose()
    }

    private func resumeCurrentMatchupIfNeeded() {
        guard let matchup = center.tftMatchup, battleReplay == nil else { return }
        startAnimatedBattle(opponent: matchup.army)
    }

    private func unitTile(_ unit: PokemonTFTUnit, compact: Bool) -> some View {
        let definition = game.definition(for: unit.definitionID)
        return VStack(spacing: 0) {
            SpriteView(speciesID: definition.id, size: compact ? 31 : 34, animated: false, shiny: false, back: false)
            Text(String(repeating: "★", count: unit.star)).font(PokedoroTheme.glyphFont(size: 8)).foregroundStyle(.yellow)
            if !compact { Text(definition.name).font(.caption2).foregroundStyle(.white).lineLimit(1) }
        }
        .padding(2)
        .background(selectedUnit == unit.id ? arenaBlue.opacity(0.25) : Color.white.opacity(compact ? 0 : 0.06))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(selectedUnit == unit.id ? arenaBlue : .clear,
                                                                lineWidth: 1.5))
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }

    private func boardTap(slot: Int, unit: PokemonTFTUnit?) {
        if let selectedUnit, unit?.id == selectedUnit {
            game.moveToBench(selectedUnit); self.selectedUnit = nil
        } else if let selectedUnit { game.move(selectedUnit, to: slot); self.selectedUnit = nil }
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

private struct TFTArenaCell: Shape {
    func path(in rect: CGRect) -> Path {
        let cut = min(rect.width, rect.height) * 0.14
        var path = Path()
        path.move(to: CGPoint(x: cut, y: 0))
        path.addLine(to: CGPoint(x: rect.maxX - cut, y: 0))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX - cut, y: rect.maxY))
        path.addLine(to: CGPoint(x: cut, y: rect.maxY))
        path.addLine(to: CGPoint(x: 0, y: rect.midY))
        path.closeSubpath()
        return path
    }
}
