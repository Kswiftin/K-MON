import SwiftUI

struct PokeathlonView: View {
    let store: CompanionStore
    @Environment(BattleCenter.self) private var battleCenter
    private var center: MultiplayerRoomCenter { battleCenter.multiplayer }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(store.language == .ko ? "포켓슬론 · 체인지릴레이" : "Pokéathlon · Relay Run",
                      systemImage: "figure.run")
                    .font(.headline)
                Spacer()
                if center.phase != .idle {
                    Button(store.language == .ko ? "나가기" : "Leave") { center.leaveRoom() }.controlSize(.small)
                }
            }
            switch center.phase {
            case .pokeathlon: raceView
            case .hosting, .joined, .joining, .creating: lobbyView
            case .battling:
                Text(store.language == .ko ? "배틀 방이 진행 중입니다." : "A battle room is active.")
            case .idle: roomBrowser
            }
        }
    }

    private var roomBrowser: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(store.language == .ko
                 ? "포켓몬 3마리가 이어 달립니다. 지치기 전에 교대하고 장애물을 넘으세요."
                 : "Three Pokémon run as a team. Switch before they tire and clear obstacles.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button(store.language == .ko ? "혼자 연습하기" : "Solo practice") {
                    center.startSoloPokeathlon()
                }.buttonStyle(.borderedProminent).controlSize(.small)
                Button(store.language == .ko ? "릴레이 방 만들기" : "Create relay room") {
                    center.createPokeathlonRoom()
                }.controlSize(.small)
            }
            ForEach(center.rooms.filter { $0.name.hasPrefix("RUN") }) { room in
                HStack {
                    Label(room.name, systemImage: "door.left.hand.open").font(.caption).lineLimit(1)
                    Spacer()
                    Button(store.language == .ko ? "참가" : "Join") { center.join(room) }.controlSize(.small)
                }
            }
            if center.rooms.allSatisfy({ !$0.name.hasPrefix("RUN") }) {
                Text(store.language == .ko ? "발견된 릴레이 방이 없습니다." : "No relay rooms found.")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(10).background(Color.green.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
    }

    private var lobbyView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(store.language == .ko ? "대기실 · 최대 4명" : "Lobby · up to 4 players").font(.callout.bold())
            if let lobby = center.lobby {
                ForEach(lobby.participants) { player in
                    HStack {
                        SpriteView(speciesID: player.speciesID, size: 28)
                        Text(player.trainerName).font(.caption.bold())
                        Spacer()
                        if player.isHost { Text("HOST").font(.system(size: 8, weight: .bold)).foregroundStyle(.orange) }
                        Image(systemName: player.isReady ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(player.isReady ? .green : .secondary)
                    }
                }
                Button(center.myParticipant?.isReady == true
                       ? (store.language == .ko ? "준비 취소" : "Cancel ready")
                       : (store.language == .ko ? "준비" : "Ready")) { center.toggleReady() }
                    .controlSize(.small)
                if center.isHost {
                    Button(store.language == .ko ? "경기 시작" : "Start race") { center.startPokeathlon() }
                        .buttonStyle(.borderedProminent).controlSize(.small).disabled(!lobby.canStart)
                }
            } else { ProgressView().controlSize(.small) }
        }
    }

    private var raceView: some View {
        Group {
            if let race = center.pokeathlonRace {
                TimelineView(.periodic(from: .now, by: 0.1)) { timeline in
                    ZStack {
                        VStack(spacing: 10) {
                            raceScoreboard(race)
                            raceTrack(race)
                            raceControls(race, now: timeline.date)
                        }
                        if let label = countdownLabel(race, now: timeline.date) {
                            Text(label)
                                .font(.system(size: label.count == 1 ? 52 : 30, weight: .black, design: .rounded))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 24).padding(.vertical, 12)
                                .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 16))
                                .shadow(radius: 8)
                        }
                    }
                }
            }
        }
    }

    private func raceScoreboard(_ race: PokeathlonRace) -> some View {
        let standings = race.racers.sorted {
            $0.distance == $1.distance ? $0.crashes < $1.crashes : $0.distance > $1.distance
        }
        return VStack(spacing: 7) {
            HStack {
                Label(store.language == .ko ? "체인지릴레이" : "Relay Run", systemImage: "flag.checkered")
                    .font(.caption.bold()).foregroundStyle(.white)
                Spacer()
                Text(store.language == .ko ? "실시간 순위" : "LIVE STANDINGS")
                    .font(.system(size: 9, weight: .black)).foregroundStyle(.white.opacity(0.75))
            }
            HStack(spacing: 5) {
                ForEach(Array(standings.enumerated()), id: \.element.id) { index, racer in
                    standingCard(racer, position: index + 1)
                }
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(LinearGradient(colors: [.blue.opacity(0.95), .indigo], startPoint: .leading, endPoint: .trailing),
                    in: RoundedRectangle(cornerRadius: 8))
    }

    private func standingCard(_ racer: PokeathlonRacer, position: Int) -> some View {
        HStack(spacing: 3) {
            Text("\(position)")
                .font(.caption2.weight(.black)).foregroundStyle(position == 1 ? .black : .white)
                .frame(width: 17, height: 17)
                .background(position == 1 ? Color.yellow : Color.white.opacity(0.18), in: Circle())
            SpriteView(speciesID: racer.activeSpeciesID, size: 20)
            VStack(alignment: .leading, spacing: 0) {
                Text(racer.trainerName).font(.system(size: 9, weight: .bold)).lineLimit(1)
                Text("\(racer.distance)m").font(.system(size: 8).monospacedDigit()).opacity(0.8)
            }
        }
        .foregroundStyle(.white).padding(.horizontal, 4).padding(.vertical, 3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(racer.id == center.myID ? Color.green.opacity(0.45) : Color.black.opacity(0.18),
                    in: RoundedRectangle(cornerRadius: 6))
    }

    private func raceTrack(_ race: PokeathlonRace) -> some View {
        GeometryReader { geo in
            let laneHeight = geo.size.height / 3
            ZStack(alignment: .topLeading) {
                LinearGradient(colors: [Color(red: 0.82, green: 0.64, blue: 0.38),
                                        Color(red: 0.65, green: 0.43, blue: 0.22)],
                               startPoint: .top, endPoint: .bottom)
                ForEach(0...3, id: \.self) { lane in
                    Rectangle().fill(.white.opacity(0.52)).frame(height: 1)
                        .offset(y: CGFloat(lane) * laneHeight)
                }
                ForEach(PokeathlonRace.obstacles.filter { $0 / 100 == currentLap(race) }, id: \.self) { meter in
                    obstacle(at: meter, width: geo.size.width, laneHeight: laneHeight)
                }
                if currentLap(race) == 2 {
                    finishLine(width: geo.size.width, height: geo.size.height)
                }
                ForEach(race.racers) { racer in
                    racerMarker(racer, laneHeight: laneHeight, trackWidth: geo.size.width)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.8), lineWidth: 2))
        }
        .frame(height: 150)
        .shadow(color: .black.opacity(0.18), radius: 3, y: 2)
    }

    private func obstacle(at meter: Int, width: CGFloat, laneHeight: CGFloat) -> some View {
        let x = width * CGFloat(meter % 100) / 100
        let subLane = CGFloat(PokeathlonRace.obstacleLane(at: meter))
        return Text("🪨")
            .font(.system(size: 16))
            .offset(x: x - 8, y: subLane * laneHeight + (laneHeight - 18) / 2)
    }

    private func finishLine(width: CGFloat, height: CGFloat) -> some View {
        VStack(spacing: 0) {
            ForEach(0..<24, id: \.self) { row in
                HStack(spacing: 0) {
                    Rectangle().fill(row.isMultiple(of: 2) ? .white : .black)
                    Rectangle().fill(row.isMultiple(of: 2) ? .black : .white)
                }
                .frame(width: 12, height: height / 24)
            }
        }
        .frame(width: 12, height: height)
        .offset(x: width - 12)
    }

    private func racerMarker(_ racer: PokeathlonRacer, laneHeight: CGFloat, trackWidth: CGFloat) -> some View {
        let usableWidth = max(1, trackWidth - 38)
        let x = min(usableWidth, usableWidth * CGFloat(racer.distance % 100) / 100)
        return VStack(spacing: -4) {
            Text(racer.id == center.myID ? "▼" : "")
                .font(.system(size: 8, weight: .black)).foregroundStyle(.yellow)
            SpriteView(speciesID: racer.activeSpeciesID, size: 34)
                .shadow(color: .black.opacity(0.3), radius: 1, y: 1)
            Text(racer.trainerName).font(.system(size: 8, weight: .bold)).lineLimit(1)
                .padding(.horizontal, 3).background(.white.opacity(0.78), in: Capsule())
        }
        .frame(width: 42)
        .offset(x: x, y: CGFloat(racer.lane) * laneHeight + 1)
        .animation(.snappy(duration: 0.16), value: racer.distance)
    }

    @ViewBuilder
    private func raceControls(_ race: PokeathlonRace, now: Date) -> some View {
        if let winner = race.racers.first(where: { $0.id == race.winnerID }) {
            VStack(spacing: 7) {
                Text("🏆 \(winner.trainerName) " + (store.language == .ko ? "우승!" : "wins!"))
                    .font(.title3.bold())
                Button(store.language == .ko ? "연습 종료" : "Finish practice") { center.leaveRoom() }
            }.frame(maxWidth: .infinity).padding(10).background(.yellow.opacity(0.16), in: RoundedRectangle(cornerRadius: 10))
        } else {
            if let me = race.racers.first(where: { $0.id == center.myID }) {
                HStack(spacing: 8) {
                    ForEach(Array(me.teamSpeciesIDs.enumerated()), id: \.offset) { index, speciesID in
                        VStack(spacing: 2) {
                            SpriteView(speciesID: speciesID, size: 28)
                                .opacity(index == me.activeTeamIndex ? 1 : 0.55)
                            ProgressView(value: Double(me.stamina[index]), total: 100)
                                .tint(me.stamina[index] > 25 ? .green : .red).frame(width: 48)
                        }
                        .padding(4)
                        .background(index == me.activeTeamIndex ? Color.yellow.opacity(0.2) : .clear,
                                    in: RoundedRectangle(cornerRadius: 7))
                    }
                    Spacer()
                    Text(store.language == .ko ? "스태미나" : "Stamina")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 7) {
                Button { center.pokeathlonInput(.run) } label: {
                    Label(store.language == .ko ? "달리기  →" : "RUN  →", systemImage: "figure.run")
                        .frame(maxWidth: .infinity).padding(.vertical, 5)
                }
                .buttonStyle(.borderedProminent).tint(.green).keyboardShortcut(.rightArrow, modifiers: [])
                Button { center.pokeathlonInput(.dodgeLeft) } label: { Image(systemName: "arrow.up") }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.upArrow, modifiers: [])
                Button { center.pokeathlonInput(.dodgeRight) } label: { Image(systemName: "arrow.down") }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.downArrow, modifiers: [])
                Button { center.pokeathlonInput(.switchPokemon) } label: {
                    Label(store.language == .ko ? "교대  C" : "SWITCH  C", systemImage: "arrow.triangle.2.circlepath")
                        .frame(maxWidth: .infinity).padding(.vertical, 5)
                }
                .buttonStyle(.borderedProminent).tint(.blue).keyboardShortcut("c", modifiers: [])
            }
            .controlSize(.large)
            .disabled(now < race.startsAt)
        }
    }

    private func countdownLabel(_ race: PokeathlonRace, now: Date) -> String? {
        let remaining = race.startsAt.timeIntervalSince(now)
        if remaining > 0 { return String(max(1, Int(ceil(remaining)))) }
        if remaining > -0.7 { return store.language == .ko ? "시작!" : "GO!" }
        return nil
    }

    private func currentLap(_ race: PokeathlonRace) -> Int {
        min(2, (race.racers.first(where: { $0.id == center.myID })?.distance ?? 0) / 100)
    }

    private func rank(of racer: PokeathlonRacer, in race: PokeathlonRace) -> Int {
        race.racers.sorted {
            $0.distance == $1.distance ? $0.crashes < $1.crashes : $0.distance > $1.distance
        }.firstIndex(where: { $0.id == racer.id }).map { $0 + 1 } ?? 1
    }
}
