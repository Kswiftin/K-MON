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
        if let verb = command.request {
            var minutes: Int?
            if case .start(let value) = command { minutes = value }
            return send(verb, minutes: minutes)
        }

        let store = CompanionStore(isReadOnly: true)
        switch command {
        case .help, .start, .claim, .stop:
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
    static func send(_ verb: PokedoroRequest.Verb, minutes: Int?) -> Int32 {
        let request = PokedoroRequest(id: UUID(), verb: verb, minutes: minutes, requestedAt: Date())
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
            let marks = (entry.isActive ? TUIRender.activeMark + " " : "  ")
                + (entry.isShiny ? "✨ " : "   ")
            return marks + TUIText.pad(entry.name, to: 18) + "Lv.\(entry.level)"
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
