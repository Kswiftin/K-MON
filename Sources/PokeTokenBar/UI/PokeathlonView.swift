import SwiftUI

struct PokeathlonView: View {
    private enum Event: String, CaseIterable { case relay, quiz }
    let store: CompanionStore
    @Environment(BattleCenter.self) private var battleCenter
    private var center: MultiplayerRoomCenter { battleCenter.multiplayer }
    @State private var joinRole: LobbyRole = .runner
    @State private var roomPage = 0
    @State private var selectedEvent: Event = .quiz

    /// 한 페이지에 그리는 릴레이 방 수. 상대 목록과 같은 부류다 — 목록 길이를 LAN 이 정하므로
    /// 상한 없이 그리면 팝오버가 잘리고, 상한만 걸면 뒤쪽 방에 참가할 방법이 없어진다.
    static let roomPageSize = 5

    static func roomPageCount(_ roomCount: Int) -> Int {
        max(1, (roomCount + roomPageSize - 1) / roomPageSize)
    }
    @State private var betRunnerID: UUID?
    @State private var betAmount = 10

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(selectedEvent == .quiz
                      ? store.l.t("포켓슬론 · 포켓몬 OX", "Pokéathlon · Pokémon OX", "ポケスロン · ポケモンOX")
                      : store.l.t("포켓슬론 · 체인지릴레이", "Pokéathlon · Relay Run", "ポケスロン · チェンジリレー"),
                      systemImage: selectedEvent == .quiz ? "questionmark.circle.fill" : "figure.run")
                    .font(.headline)
                Spacer()
                if center.phase != .idle {
                    Button(store.l.t("나가기", "Leave", "退出")) { center.leaveRoom() }.controlSize(.small)
                }
            }
            switch center.phase {
            case .pokeathlon: raceView
            case .pokemonQuiz: pokemonQuizView
            case .hosting, .joined, .joining, .creating: lobbyView
            case .battling:
                Text(store.l.t("배틀 방이 진행 중입니다.", "A battle room is active.", "バトルの部屋が進行中です。"))
            case .idle: roomBrowser
            }
        }
    }

    private var roomBrowser: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("", selection: $selectedEvent) {
                Text(store.l.t("포켓몬 OX", "Pokémon OX", "ポケモンOX")).tag(Event.quiz)
                Text(store.l.t("체인지릴레이", "Relay Run", "チェンジリレー")).tag(Event.relay)
            }
            .pickerStyle(.segmented)
            Text(selectedEvent == .quiz
                 ? store.l.t("포켓몬 퀴즈를 읽고 O 또는 X 발판으로 이동하세요. 정답마다 10점, 총 10문제로 순위를 정합니다.",
                             "Move onto the O or X platform. Each correct answer is worth 10 points across 10 questions.",
                             "問題を読んでOかXの足場へ移動。正解は10点、全10問で順位を決めます。")
                 : store.l.t("포켓몬 3마리가 이어 달립니다. 지치기 전에 교대하고 장애물을 넘으세요.",
                             "Three Pokémon run as a team. Switch before they tire and clear obstacles.",
                             "ポケモン3匹がリレーで走ります。疲れる前に交代して障害物を越えましょう。"))
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button(store.l.t("혼자 연습하기", "Solo practice", "ひとりで練習")) {
                    if selectedEvent == .quiz { center.startSoloPokemonQuiz() }
                    else { center.startSoloPokeathlon() }
                }.buttonStyle(.borderedProminent).controlSize(.small)
                Button(selectedEvent == .quiz
                       ? store.l.t("OX 방 만들기", "Create OX room", "OXの部屋を作る")
                       : store.l.t("릴레이 방 만들기", "Create relay room", "リレーの部屋を作る")) {
                    if selectedEvent == .quiz { center.createPokemonQuizRoom() }
                    else { center.createPokeathlonRoom() }
                }.controlSize(.small)
            }
            if selectedEvent == .relay {
                Picker("", selection: $joinRole) {
                    Text(store.l.t("선수로 참가", "Join as runner", "選手として参加")).tag(LobbyRole.runner)
                    Text(store.l.t("관전·베팅", "Spectate & bet", "観戦・ベット")).tag(LobbyRole.spectator)
                }
                .pickerStyle(.segmented).controlSize(.small)
            }
            let prefix = selectedEvent == .quiz ? "QUIZ" : "RUN"
            let eventRooms = center.rooms.filter { $0.name.hasPrefix(prefix) }
            let roomPageCount = Self.roomPageCount(eventRooms.count)
            // 방은 수시로 열리고 닫힌다 — 보던 페이지가 사라지면 마지막 페이지로 당긴다.
            let currentRoomPage = min(roomPage, roomPageCount - 1)
            ForEach(eventRooms.dropFirst(currentRoomPage * Self.roomPageSize).prefix(Self.roomPageSize)) { room in
                HStack {
                    Label(room.name, systemImage: "door.left.hand.open").font(.caption).lineLimit(1)
                    Spacer()
                    Button(store.l.t("참가", "Join", "参加")) {
                        center.join(room, as: selectedEvent == .quiz ? .runner : joinRole)
                    }
                        .controlSize(.small)
                }
            }
            if roomPageCount > 1 {
                HStack(spacing: 8) {
                    Spacer(minLength: 4)
                    Button { roomPage = max(0, currentRoomPage - 1) } label: { Image(systemName: "chevron.left") }
                        .buttonStyle(.plain).disabled(currentRoomPage == 0)
                        .accessibilityLabel(store.l.dexPagePrev)
                    Text("\(currentRoomPage + 1) / \(roomPageCount)")
                        .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                        .accessibilityLabel(store.l.dexPageLabel(currentRoomPage + 1, roomPageCount))
                    Button { roomPage = min(roomPageCount - 1, currentRoomPage + 1) } label: { Image(systemName: "chevron.right") }
                        .buttonStyle(.plain).disabled(currentRoomPage == roomPageCount - 1)
                        .accessibilityLabel(store.l.dexPageNext)
                }
            }
            if eventRooms.isEmpty {
                Text(selectedEvent == .quiz
                     ? store.l.t("발견된 OX 방이 없습니다.", "No OX rooms found.", "OXの部屋が見つかりません。")
                     : store.l.t("발견된 릴레이 방이 없습니다.", "No relay rooms found.", "リレーの部屋が見つかりません。"))
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(10).background(Color.green.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
    }

    private var lobbyView: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let lobby = center.lobby {
                sectionHeader(store.l.t("선수", "Racers", "選手"),
                              count: lobby.runners.count, limit: lobby.capacity)
                ForEach(lobby.runners) { player in participantRow(player, showsReady: true) }
                sectionHeader(store.l.t("관전", "Spectators", "観戦"),
                              count: lobby.spectators.count, limit: MultiplayerLobby.spectatorCapacity)
                if lobby.spectators.isEmpty {
                    Text(store.l.t("관전자가 없습니다.", "No spectators yet.", "観戦者はまだいません。"))
                        .font(.caption2).foregroundStyle(.tertiary)
                } else {
                    ForEach(lobby.spectators) { player in participantRow(player, showsReady: false) }
                }
                if !center.amSpectator {
                    Button(center.myParticipant?.isReady == true
                           ? store.l.t("준비 취소", "Cancel ready", "準備をやめる")
                           : store.l.t("준비", "Ready", "準備完了")) { center.toggleReady() }
                        .controlSize(.small)
                } else {
                    Text(store.l.t("경기가 시작되면 베팅이 마감됩니다.",
                             "Betting closes when the race starts.",
                             "レースが始まるとベットは締め切られます。"))
                        .font(.caption2).foregroundStyle(.secondary)
                }
                if center.isHost {
                    let quiz = lobby.activity == .pokemonQuiz
                    Button(quiz
                           ? (center.isPreparingPokemonQuiz
                              ? store.l.t("문제 생성 중…", "Generating…", "問題を生成中…")
                              : store.l.t("OX 퀴즈 시작", "Start OX quiz", "OXクイズ開始"))
                           : store.l.t("경기 시작", "Start race", "レース開始")) {
                        if quiz { center.startPokemonQuiz() } else { center.startPokeathlon() }
                    }
                        .buttonStyle(.borderedProminent).controlSize(.small)
                        .disabled(!lobby.canStart || center.isPreparingPokemonQuiz)
                }
            } else { ProgressView().controlSize(.small) }
        }
    }

    private func sectionHeader(_ title: String, count: Int, limit: Int) -> some View {
        HStack {
            Text(title).font(.callout.bold())
            Spacer()
            Text("\(count)/\(limit)").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
        }
    }

    private func participantRow(_ player: LobbyParticipant, showsReady: Bool) -> some View {
        HStack {
            SpriteView(speciesID: player.speciesID, size: 28)
            Text(player.trainerName).font(.caption.bold())
            Spacer()
            if player.isHost { Text("HOST").font(.system(size: 8, weight: .bold)).foregroundStyle(.orange) }
            if showsReady {
                Image(systemName: player.isReady ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(player.isReady ? .green : .secondary)
            } else {
                Image(systemName: "eye").foregroundStyle(.secondary)
            }
        }
    }

    private var pokemonQuizView: some View {
        Group {
            if let game = center.pokemonQuizGame {
                TimelineView(.periodic(from: .now, by: 0.1)) { timeline in
                    VStack(spacing: 9) {
                        pokemonQuizHeader(game, now: timeline.date)
                        pokemonQuizArena(game)
                        if game.isFinished { pokemonQuizResults(game) }
                        else { pokemonQuizControls(game, now: timeline.date) }
                    }
                }
            }
        }
    }

    private func pokemonQuizHeader(_ game: PokemonOXGame, now: Date) -> some View {
        VStack(spacing: 6) {
            HStack {
                Text(game.isFinished ? store.l.t("최종 결과", "Final results", "最終結果")
                     : "Q\(game.questionIndex + 1) / \(game.questions.count)")
                    .font(.caption.bold()).foregroundStyle(.white)
                Spacer()
                if !game.isFinished {
                    Text(String(format: "%.1f초", max(0, game.deadline.timeIntervalSince(now))))
                        .font(.caption.monospacedDigit().bold()).foregroundStyle(.yellow)
                }
            }
            if let question = game.currentQuestion {
                HStack(spacing: 8) {
                    SpriteView(speciesID: question.speciesID, size: 44)
                    Text(store.l.t(question.ko, question.en, question.ja))
                        .font(.callout.bold()).foregroundStyle(.white).multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
                if game.isRevealing {
                    Text(question.answer ? "⭕ O" : "❌ X")
                        .font(.title2.weight(.black)).foregroundStyle(.yellow)
                }
            }
        }
        .padding(10)
        .background(LinearGradient(colors: [.indigo, .purple], startPoint: .leading, endPoint: .trailing),
                    in: RoundedRectangle(cornerRadius: 10))
    }

    private func pokemonQuizArena(_ game: PokemonOXGame) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                LinearGradient(colors: [.cyan.opacity(0.2), .blue.opacity(0.08)],
                               startPoint: .top, endPoint: .bottom)
                HStack(spacing: 8) {
                    quizPlatform(label: "X", color: .red)
                    quizPlatform(label: "O", color: .blue)
                }.padding(8)
                Rectangle().fill(.white.opacity(0.8)).frame(width: 2)
                    .offset(x: geo.size.width / 2 - 1)
                ForEach(Array(game.players.enumerated()), id: \.element.id) { index, player in
                    let usable = max(1, geo.size.width - 42)
                    let x = usable * CGFloat((player.position + 1) / 2)
                    VStack(spacing: -3) {
                        SpriteView(speciesID: player.speciesID, size: 28)
                        Text(player.trainerName).font(.system(size: 8, weight: .bold)).lineLimit(1)
                            .padding(.horizontal, 3).background(.white.opacity(0.86), in: Capsule())
                        Text("\(player.score)점").font(.system(size: 8, weight: .black).monospacedDigit())
                    }
                    .frame(width: 42)
                    .offset(x: x, y: 20 + CGFloat(index % 5) * 32 + (game.isRevealing && player.lastCorrect == false ? 24 : 0))
                    .opacity(game.isRevealing && player.lastCorrect == false ? 0.32 : 1)
                    .animation(.snappy(duration: 0.18), value: player.position)
                    .animation(.easeIn(duration: 0.35), value: player.lastCorrect)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.8), lineWidth: 2))
        }.frame(height: 190)
    }

    private func quizPlatform(label: String, color: Color) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10).fill(color.opacity(0.36))
            Text(label).font(.system(size: 44, weight: .black, design: .rounded)).foregroundStyle(.white.opacity(0.72))
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func pokemonQuizControls(_ game: PokemonOXGame, now: Date) -> some View {
        if game.isRevealing {
            let mine = game.players.first(where: { $0.id == center.myID })
            Text(mine?.lastCorrect == true
                 ? store.l.t("정답! +10점", "Correct! +10", "正解！+10点")
                 : store.l.t("아쉽지만 오답!", "Not quite!", "残念、不正解！"))
                .font(.headline).foregroundStyle(mine?.lastCorrect == true ? .green : .red)
                .frame(maxWidth: .infinity).padding(8)
        } else {
            HStack(spacing: 10) {
                Button { center.pokemonQuizInput(.left) } label: {
                    Label("X", systemImage: "arrow.left").frame(maxWidth: .infinity).padding(.vertical, 7)
                }
                .buttonStyle(.borderedProminent).tint(.red).keyboardShortcut(.leftArrow, modifiers: [])
                Button { center.pokemonQuizInput(.right) } label: {
                    Label("O", systemImage: "arrow.right").frame(maxWidth: .infinity).padding(.vertical, 7)
                }
                .buttonStyle(.borderedProminent).tint(.blue).keyboardShortcut(.rightArrow, modifiers: [])
            }
            .controlSize(.large).disabled(now >= game.deadline)
        }
    }

    private func pokemonQuizResults(_ game: PokemonOXGame) -> some View {
        VStack(spacing: 5) {
            ForEach(Array(game.standings.enumerated()), id: \.element.id) { index, player in
                HStack {
                    Text(index == 0 ? "🏆" : "\(index + 1).")
                        .font(.caption.bold()).frame(width: 28)
                    SpriteView(speciesID: player.speciesID, size: 25)
                    Text(player.trainerName).font(.caption.bold()).lineLimit(1)
                    Spacer()
                    Text("\(player.score)점").font(.caption.monospacedDigit().bold())
                }.padding(.horizontal, 8).padding(.vertical, 3)
                    .background(player.id == center.myID ? Color.yellow.opacity(0.18) : .clear,
                                in: RoundedRectangle(cornerRadius: 7))
            }
            Button(store.l.t("퀴즈 종료", "Finish quiz", "クイズ終了")) { center.leaveRoom() }
                .controlSize(.small)
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
                Label(store.l.t("체인지릴레이", "Relay Run", "チェンジリレー"), systemImage: "flag.checkered")
                    .font(.caption.bold()).foregroundStyle(.white)
                Spacer()
                Text(store.l.t("실시간 순위", "LIVE STANDINGS", "リアルタイム順位"))
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
                Text("🏆 \(winner.trainerName) " + store.l.t("우승!", "wins!", "優勝！"))
                    .font(.title3.bold())
                if let payout = center.settlementPayout, let mine = center.myBet {
                    Text(settlementText(payout: payout, stake: mine.amount,
                                        backedWinner: mine.runnerID == winner.id))
                        .font(.caption).foregroundStyle(payout > mine.amount ? .green : .secondary)
                }
                Button(store.l.t("연습 종료", "Finish practice", "練習を終える")) { center.leaveRoom() }
            }.frame(maxWidth: .infinity).padding(10).background(.yellow.opacity(0.16), in: RoundedRectangle(cornerRadius: 10))
        } else if center.amSpectator {
            bettingPanel(race, now: now)
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
                    Text(store.l.t("스태미나", "Stamina", "スタミナ"))
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 7) {
                Button { center.pokeathlonInput(.run) } label: {
                    Label(store.l.t("달리기  →", "RUN  →", "はしる  →"), systemImage: "figure.run")
                        .frame(maxWidth: .infinity).padding(.vertical, 5)
                }
                .buttonStyle(.borderedProminent).tint(.green).keyboardShortcut(.rightArrow, modifiers: [])
                Button { center.pokeathlonInput(.dodgeLeft) } label: { Image(systemName: "arrow.up") }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.upArrow, modifiers: [])
                Button { center.pokeathlonInput(.dodgeRight) } label: { Image(systemName: "arrow.down") }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.downArrow, modifiers: [])
                Button { center.pokeathlonInput(.switchPokemon) } label: {
                    Label(store.l.t("교대  C", "SWITCH  C", "交代  C"), systemImage: "arrow.triangle.2.circlepath")
                        .frame(maxWidth: .infinity).padding(.vertical, 5)
                }
                .buttonStyle(.borderedProminent).tint(.blue).keyboardShortcut("c", modifiers: [])
            }
            .controlSize(.large)
            .disabled(now < race.startsAt)
        }
    }

    /// 관전자 패널 — 출발 전에는 베팅 입력, 출발 후에는 배당 보드.
    @ViewBuilder
    private func bettingPanel(_ race: PokeathlonRace, now: Date) -> some View {
        let pool = center.pokeathlonPool
        let open = now < race.startsAt && !pool.isClosed
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Label(store.l.t("관전 베팅", "Spectator betting", "観戦ベット"), systemImage: "ticket")
                    .font(.caption.bold())
                Spacer()
                Text("\(pool.total) ⭐").font(.caption.monospacedDigit())
            }
            if open {
                Picker("", selection: Binding(get: { betRunnerID ?? race.racers.first?.id },
                                              set: { betRunnerID = $0 })) {
                    ForEach(race.racers) { racer in Text(racer.trainerName).tag(Optional(racer.id)) }
                }
                .pickerStyle(.segmented).controlSize(.small)
                HStack(spacing: 7) {
                    Stepper(value: $betAmount, in: 1...max(1, store.availableTokens), step: 5) {
                        Text("\(betAmount) ⭐").font(.caption.monospacedDigit())
                    }
                    .controlSize(.small)
                    Button(center.myBet == nil
                           ? store.l.t("베팅", "Bet", "ベット")
                           : store.l.t("변경", "Change", "変更")) {
                        if let runnerID = betRunnerID ?? race.racers.first?.id {
                            center.placeBet(runnerID: runnerID, amount: betAmount)
                        }
                    }
                    .buttonStyle(.borderedProminent).controlSize(.small)
                    .disabled(store.availableTokens < betAmount)
                }
            } else {
                Text(store.l.t("베팅 마감", "Betting closed", "ベット締め切り"))
                    .font(.caption2).foregroundStyle(.secondary)
            }
            oddsBoard(race, pool: pool)
            if let mine = center.myBet,
               let backed = race.racers.first(where: { $0.id == mine.runnerID }) {
                Text(store.l.t("내 베팅: ", "My bet: ", "自分のベット: ")
                     + "\(backed.trainerName) · \(mine.amount) ⭐ → \(pool.payouts(winnerID: mine.runnerID)[center.myID] ?? 0) ⭐")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(9).background(Color.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
    }

    /// 선수별 받은 판돈과, 그 선수가 우승했을 때 내가 받게 될 금액.
    private func oddsBoard(_ race: PokeathlonRace, pool: PokeathlonPool) -> some View {
        VStack(spacing: 3) {
            ForEach(race.racers) { racer in
                let backed = pool.bets.values.filter { $0.runnerID == racer.id }.reduce(0) { $0 + $1.amount }
                HStack {
                    SpriteView(speciesID: racer.activeSpeciesID, size: 18)
                    Text(racer.trainerName).font(.system(size: 10, weight: .bold)).lineLimit(1)
                    Spacer()
                    Text("\(backed) ⭐").font(.system(size: 10).monospacedDigit())
                    if center.myBet?.runnerID == racer.id {
                        Text("→ \(pool.payouts(winnerID: racer.id)[center.myID] ?? 0) ⭐")
                            .font(.system(size: 10, weight: .bold).monospacedDigit())
                            .foregroundStyle(.green)
                    }
                }
            }
        }
    }

    /// 정산 문구 — 딴 금액, 또는 환불과 그 이유.
    private func settlementText(payout: Int, stake: Int, backedWinner: Bool) -> String {
        if backedWinner && payout > stake {
            return store.l.t("+\(payout - stake) ⭐ 획득 (총 \(payout) ⭐ 수령)",
                          "Won +\(payout - stake) ⭐ (received \(payout) ⭐)",
                          "+\(payout - stake) ⭐ 獲得（合計 \(payout) ⭐ 受け取り）")
        }
        if payout == stake {
            return store.l.t("환불 \(stake) ⭐ — 우승자에 건 관전자가 없습니다.",
                          "Refunded \(stake) ⭐ — nobody backed the winner.",
                          "\(stake) ⭐ を返金 — 優勝者に賭けた観戦者がいません。")
        }
        if payout == 0 {
            return store.l.t("판돈 \(stake) ⭐ 를 잃었습니다.",
                          "Lost the \(stake) ⭐ stake.",
                          "\(stake) ⭐ の賭け金を失いました。")
        }
        return store.l.t("정산 \(payout) ⭐", "Settled \(payout) ⭐", "精算 \(payout) ⭐")
    }

    private func countdownLabel(_ race: PokeathlonRace, now: Date) -> String? {
        let remaining = race.startsAt.timeIntervalSince(now)
        if remaining > 0 { return String(max(1, Int(ceil(remaining)))) }
        if remaining > -0.7 { return store.l.t("시작!", "GO!", "スタート！") }
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
