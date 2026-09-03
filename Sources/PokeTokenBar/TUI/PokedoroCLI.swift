import Foundation

/// 터미널 프런트엔드의 실행부. 메뉴바 앱과 **같은 세이브 파일을 읽기 전용으로** 연다 —
/// 진행이 갈라지지 않는 유일한 방법이다.
///
/// 왜 읽기만 하나: 두 프로세스 사이에 잠금이 없어 나중 쓰기가 앞 쓰기를 통째로 덮고, 세이브를
/// 여는 것 자체가 "앱이 죽은 사이 밀린 일"(랭크전 패배 정산·끝난 모험 정산)을 실행한다.
/// `CompanionStore(isReadOnly: true)` 가 그 두 가지를 모두 막는다.
@MainActor
enum PokedoroCLI {
    /// 프로세스 종료 코드. **거절과 앱 부재를 입력 오류와 가른다** — 스크립트가 세 경우에 서로
    /// 다르게 대응할 수 있어야 한다(오타는 고쳐야 하고, 거절은 상태를 보고 다시 걸어야 하고,
    /// 앱 부재는 앱을 켜야 한다).
    enum Status: Int32 { case ok = 0, badInput = 1, refused = 2, appNotRunning = 3 }

    static func run(arguments: [String]) -> Int32 {
        let command: PokedoroCommand
        do {
            command = try PokedoroCommandParser.parse(arguments)
        } catch let error as PokedoroCommandError {
            FileHandle.standardError.write(Data((error.message + "\n\n" + PokedoroCommandParser.usage + "\n").utf8))
            return Status.badInput.rawValue
        } catch {
            FileHandle.standardError.write(Data("\(error)\n".utf8))
            return Status.badInput.rawValue
        }

        if case .help = command {
            print(PokedoroCommandParser.usage)
            return Status.ok.rawValue
        }

        // 세션을 바꾸는 명령은 세이브를 **아예 열지 않는다** — 여는 것만으로 정산이 돌 수 있어서다
        // (`ReadOnlyStoreTests`). 앱에 부탁하고 답만 받는다.
        if let action = command.request {
            return send(action)
        }

        let store = CompanionStore(isReadOnly: true)
        switch command {
        case .help, .start, .claim, .stop, .use, .evolve, .switchCompanion, .rename:
            // 위에서 이미 끝났다. `default` 로 접지 않는 이유는 명령이 늘 때 이 자리가 조용히
            // 아무것도 안 하는 길이 되지 않게 하기 위해서다.
            return Status.ok.rawValue
        case .status(let oneline):
            if oneline {
                print(onelineStatus(store))
            } else {
                TUIRender.home(homeModel(store), width: terminalWidth()).forEach { print($0) }
            }
        case .party:
            partyRows(store).forEach { print($0) }
        case .dex:
            dexRows(store).forEach { print($0) }
        case .bag:
            bagRows(store, width: terminalWidth()).forEach { print($0) }
        case .challenge:
            challengeRows(store, width: terminalWidth()).forEach { print($0) }
        case .goals:
            goalRows(store, width: terminalWidth()).forEach { print($0) }
        case .mon(let number):
            monRows(store, number: number, width: terminalWidth()).forEach { print($0) }
        case .watch:
            TUIWatch(store: store).run()
        }
        return Status.ok.rawValue
    }

    // MARK: 앱에 부탁하기

    /// 답을 기다리는 시간. 앱은 1초 틱에서 요청을 집으므로 몇 배의 여유다. 무한정 기다리지
    /// 않는 이유는 앱이 꺼져 있을 때 셸이 멈춰 버리기 때문이다 — 그건 침묵보다 나쁘다.
    static let replyTimeout: TimeInterval = 3
    private static let pollInterval: useconds_t = 100_000   // 0.1초

    /// 요청을 남기고 **내 요청의 답**만 기다린다.
    ///
    /// 판단이 없는 자리다(`TUIWatch` 와 같은 규칙): 실행 여부·거절 사유·문구는 전부 앱 쪽
    /// (`PokedoroRequestBus`·`PokedoroSessionGate`·`PokedoroRequestExecutor`)에 있다.
    static func send(_ action: PokedoroRequest.Action) -> Int32 {
        let request = PokedoroRequest(id: UUID(), action: action, requestedAt: Date())
        let mailbox = PokedoroMailbox()
        do {
            try mailbox.send(request)
        } catch {
            // 요청을 남기지도 못한 것과 앱이 안 받은 것은 고칠 방법이 다르다. 뭉개면 사용자는
            // 앱을 껐다 켜며 시간을 버린다.
            FileHandle.standardError.write(Data("요청을 남기지 못했다: \(error.localizedDescription)\n".utf8))
            return Status.badInput.rawValue
        }

        let deadline = Date().addingTimeInterval(replyTimeout)
        while Date() < deadline {
            if let reply = mailbox.reply(to: request.id) {
                let out = reply.succeeded ? FileHandle.standardOutput : FileHandle.standardError
                out.write(Data((reply.message + "\n").utf8))
                return reply.succeeded ? Status.ok.rawValue : Status.refused.rawValue
            }
            usleep(pollInterval)
        }
        FileHandle.standardError.write(Data("""
        메뉴바 앱이 응답하지 않는다. 집중 세션은 앱이 실행하므로 앱이 떠 있어야 한다.
        조회 명령(status·party·dex)은 앱 없이도 된다.

        """.utf8))
        return Status.appNotRunning.rawValue
    }

    // MARK: 화면 값 조립

    /// 파트너 표시 이름.
    ///
    /// `CompanionStore.displayName` 을 쓰지 않는 이유: 그쪽은 PokéAPI 에서 **비동기로 받아 온**
    /// 진화 라인이 있어야 이름을 내고, 없으면 `"Token Egg"` 로 떨어진다. 메뉴바 앱은 오래 살아
    /// 라인이 곧 채워지지만 CLI 는 그 전에 끝나므로 언제나 자리표시자만 보인다(오프라인 앱도 같다).
    /// 로스터는 부화 때 세이브에 넣어 둔 이름을 읽으므로 네트워크 없이 맞는 값이 나온다.
    static func partnerName(_ store: CompanionStore) -> String? {
        guard store.hasActive else { return nil }
        return store.chatRosterEntries.first { $0.isActive }?.name ?? store.displayName
    }

    static func homeModel(_ store: CompanionStore) -> TUIHomeModel {
        let run = store.activeAdventure
        let adventure = run.map { active in
            TUIHomeModel.Adventure(
                zone: zoneLabel(active.zone),
                minutes: Int((active.endsAt.timeIntervalSince(active.startedAt) / 60).rounded()),
                remainingSeconds: Int(active.endsAt.timeIntervalSinceNow.rounded()),
                progress: store.adventureProgress())
        }
        return TUIHomeModel(
            trainerName: store.hasTrainerName ? store.trainerName : "이름 없음",
            partnerName: partnerName(store),
            partnerLevel: store.currentLevel,
            isShiny: store.currentIsShiny,
            levelProgress: store.levelProgress,
            experienceToNextLevel: store.experienceToNextLevel,
            starPieces: store.availableTokens,
            adventure: adventure,
            isReadOnly: true,
            status: nil)
    }

    /// tmux 상태줄·셸 프롬프트에 꽂는 한 줄. 폭이 귀한 자리라 라벨을 빼고 기호만 쓴다.
    static func onelineStatus(_ store: CompanionStore) -> String {
        let partner = partnerName(store).map { "\($0) Lv.\(store.currentLevel)" } ?? "알"
        guard let run = store.activeAdventure else { return "\(partner) · 쉬는 중" }
        let remaining = Int(run.endsAt.timeIntervalSinceNow.rounded())
        return remaining <= 0
            ? "\(partner) · 보상 대기"
            : "\(partner) · \(zoneLabel(run.zone)) \(TUIRender.duration(remaining))"
    }

    static func partyRows(_ store: CompanionStore) -> [String] {
        let entries = store.chatRosterEntries
        guard !entries.isEmpty else { return ["보유한 포켓몬이 없다."] }
        return entries.map { entry in
            // 번호를 찍는 이유는 `mon <번호>` 가 이 값을 받기 때문이다 — 안내만 하고 안 찍으면
            // 사용자는 어디서 번호를 얻는지 모른다. 세는 표는 `TUIRender` 한 곳이다.
            let number = TUIText.pad("\(TUIRender.printedRosterNumber(index: entry.index)).", to: 4)
            let marks = (entry.isActive ? TUIRender.activeMark + " " : "  ")
                + (entry.isShiny ? "✨ " : "   ")
            return number + marks + TUIText.pad(entry.name, to: 18) + "Lv.\(entry.level)"
        }
    }

    static func dexRows(_ store: CompanionStore) -> [String] {
        let species = store.dexSpecies
        guard !species.isEmpty else { return ["도감이 비어 있다."] }
        return species.map { entry in
            let shiny = entry.isShiny ? " ✨" : ""
            return String(format: "  #%04d ", entry.id) + TUIText.pad(entry.name + shiny, to: 20)
                + entry.rarity.rawValue
        }
    }

    /// 가방. 아이템 이름은 표에서 오므로 네트워크가 필요 없다 — 진화 라인이 있어야 채워지는
    /// 값(`displayName` 부류)을 쓰지 않는다는 규칙을 그대로 지킨다.
    static func bagRows(_ store: CompanionStore, width: Int) -> [String] {
        let items = store.ownedItems
        guard !items.isEmpty else { return ["가방이 비어 있다."] }
        let l = L(store.language)
        return TUIRender.rows(items.map { (l.itemName($0.kind), "×\(TUIRender.number($0.count))") },
                              width: width)
    }

    /// 도전 — 던전 실적·배지·미션·시즌. 앱의 도전 탭과 같은 묶음이다.
    ///
    /// 총량은 **카탈로그에서 읽는다**(`RogueRun.finalWave`·`GymLeague.catalog`). 숫자를 여기
    /// 적으면 콘텐츠가 늘 때 이 줄만 옛말이 된다 — 대화의 `challenge.status` 와 같은 규칙이다.
    static func challengeRows(_ store: CompanionStore, width: Int) -> [String] {
        let l = L(store.language)
        let run = store.runProgress
        var lines = TUIRender.rows([
            ("던전 최고 웨이브", "\(run.bestWave)/\(RogueRun.finalWave)"),
            ("던전 클리어", "\(TUIRender.number(run.clears))회"),
            ("\(l.gymLeagueTitle) 배지", "\(store.state.gymBadges.count)/\(GymLeague.catalog.count)")
        ], width: width)

        lines += section(l.missionsTitle, width: width)
        lines += TUIRender.progress(store.missionRows.map { row in
            TUIProgressRow(label: "\(row.mission.period == .daily ? l.missionDaily : l.weekly) "
                            + l.missionName(row.mission),
                           value: row.progress, target: row.mission.target)
        }, width: width)

        lines += section("\(l.seasonTitle) · \(l.seasonDaysLeft(store.seasonDaysRemaining))", width: width)
        lines += TUIRender.progress(store.seasonRows.map { row in
            TUIProgressRow(label: l.goalName(row.challenge.event, row.challenge.target),
                           value: row.progress, target: row.challenge.target)
        }, width: width)
        return lines
    }

    /// 도감 목표·업적. 둘 다 "다음에 무엇을 노릴까" 를 답하는 값이라 한 화면이다.
    static func goalRows(_ store: CompanionStore, width: Int) -> [String] {
        let l = L(store.language)
        var lines = [TUIText.truncate(l.dexTitle, to: width)]
        lines += TUIRender.progress(store.dexGoalRows.map { row in
            TUIProgressRow(label: l.dexGoalName(row.goal), value: row.progress, target: row.goal.target)
        }, width: width)

        lines += section(l.achievementsTitle, width: width)
        lines += TUIRender.progress(store.achievementRows.map { row in
            // 다음 문턱이 없으면 최고 단계다 — 자기 카운터를 목표로 삼아 완료로 그린다. 마지막
            // 문턱을 목표로 쓰면 상한을 넘긴 카운터가 "8/5" 처럼 보인다.
            let next = store.nextAchievementTier(row.achievement.track)
            return TUIProgressRow(label: l.achievementName(row.achievement.track),
                                  value: row.count, target: next?.goal ?? row.count)
        }, width: width)
        return lines
    }

    /// 개체 상세. **세이브에 저장된 값만** 쓴다 — 능력치·기술은 진화 라인을 받아야 채워지므로
    /// 짧게 살다 죽는 명령에서는 언제나 비어 있다.
    ///
    /// 번호는 `party` 가 찍는 값(1부터)이다. 없으면 파트너다 — 가장 자주 보는 개체에 인자를
    /// 강제하지 않는다. 범위 밖 번호는 **조용히 파트너로 접지 않는다**: 사용자는 자기가 무엇을
    /// 보고 있는지 모른 채 다른 개체의 값을 읽는다.
    static func monRows(_ store: CompanionStore, number: Int?, width: Int) -> [String] {
        let entries = store.chatRosterEntries
        guard !entries.isEmpty else { return ["보유한 포켓몬이 없다."] }
        let wanted: CompanionStore.ChatRosterEntry?
        if let number {
            // `??` 로 이어 붙이지 않는다 — 못 찾은 번호가 파트너로 접히면 사용자는 자기가 무엇을
            // 보고 있는지 모른 채 다른 개체의 값을 읽는다.
            wanted = entries.first { $0.index == TUIRender.rosterIndex(printed: number) }
        } else {
            wanted = entries.first { $0.isActive } ?? entries.first
        }
        guard let entry = wanted, let mon = store.ownedMons.first(where: { $0.id == entry.id }) else {
            return ["\(number.map(String.init) ?? "")번 포켓몬이 없다 — party 로 번호를 확인한다."]
        }
        var rows: [(label: String, value: String)] = [
            ("이름", entry.name + (entry.isShiny ? " ✨" : "")),
            ("번호", "\(TUIRender.printedRosterNumber(index: entry.index))"),
            ("레벨", "Lv.\(entry.level)"),
            ("등급", mon.rarity.rawValue),
            ("형태", "\(mon.stageIndex + 1)/\(mon.totalForms)")
        ]
        // 구버전 세이브엔 없는 값들이다. 빈 줄로 채우면 무엇이 없는지가 아니라 무엇이 고장났는지로 읽힌다.
        if let nature = mon.nature { rows.append(("성격", nature.name(store.language))) }
        if let gender = mon.gender { rows.append(("성별", gender.symbol)) }
        if let metAt = mon.firstMetAt { rows.append(("처음 만난 날", day.string(from: metAt))) }
        rows.append(("함께 다니는 중", entry.isActive ? "예" : "아니오"))
        return TUIRender.rows(rows, width: width)
    }

    /// 목록 안의 구획 머리글. 빈 줄을 앞에 둬 눈이 묶음을 끊어 읽게 한다.
    private static func section(_ title: String, width: Int) -> [String] {
        ["", TUIText.truncate(title, to: width)]
    }

    /// 처음 만난 날. 시각은 안 싣는다 — 폭이 귀하고 날짜만으로 할 말이 충분하다.
    private static let day: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    /// 표시용 지역 이름. `AdventureZone` 은 심볼(SF Symbols)만 들고 있어 터미널에서 쓸 수 없다.
    static func zoneLabel(_ zone: AdventureZone?) -> String {
        switch zone {
        case .forest: "숲"
        case .cave: "동굴"
        case .coast: "해안"
        case nil: "모험"
        }
    }

    /// 파이프로 연결됐거나 조회 실패면 80 칸으로 본다 — 0 을 흘리면 레이아웃이 전부 음수가 된다.
    static func terminalWidth() -> Int {
        let width = TUITerminal().size.width
        return width > 0 ? min(width, 100) : 80
    }
}
