import Darwin
import Foundation

/// `pokedoro watch` — 전체 화면 실시간 보기. 한 프로세스가 오래 사는 유일한 터미널 경로다.
///
/// **오래 사는 만큼 메모리의 상태가 낡는다.** 그동안 메뉴바 앱이 세이브를 바꾸므로 주기적으로
/// 디스크를 다시 읽는다. 다시 읽는 저장소도 읽기 전용이라, 이 화면이 도는 동안 세이브에 나가는
/// 쓰기는 없다 — 앱이 올린 진행을 덮을 방법 자체가 없다.
@MainActor
final class TUIWatch {
    private var store: CompanionStore
    private let terminal = TUITerminal()
    private var screen: TUIScreen = .home
    private var selection = 0
    private var status: String?
    /// 디스크 재읽기 주기(프레임 수). 0.5초 프레임 기준 5초마다.
    private static let reloadEveryFrames = 10
    private var frame = 0
    /// 앱에 부탁하는 통로. 이 화면도 세이브에는 쓰지 않는다.
    private let mailbox = PokedoroMailbox()
    /// 답을 기다리는 요청. 하나만 든다 — 화면에서 키를 연타해도 마지막 것만 유효하다.
    private var pending: PokedoroRequest?
    /// 확인을 기다리는 **되돌릴 수 없는** 동작. 물어본 문장과 실행할 동작을 **함께** 든다 —
    /// 확인 사이에 목록이 다시 읽혀 커서 아래 행이 바뀔 수 있으므로, 그때 대상을 다시 찾으면
    /// 사용자가 승낙한 것과 다른 개체가 사라진다.
    private var confirmation: (question: String, action: PokedoroRequest.Action)?
    /// 이 화면의 신원. 앱이 여러 터미널을 구분할 필요는 아직 없지만, 신호가 누구 것인지 적어 두면
    /// 나중에 붙은 쪽을 셀 수 있다.
    private let attachmentID = UUID()
    /// 앱이 내놓은 지금 화면. **세이브에 없는 값**(집중 타이머·LAN 대전)은 이 경로로만 온다.
    private var appView: PokedoroViewSnapshot?

    init(store: CompanionStore) {
        self.store = store
    }

    func run() {
        // 터미널이 아니면(파이프·리다이렉트) raw mode 도 화면 제어도 의미가 없다. 조용히 도는 대신
        // 한 번 찍고 끝내 사용자가 무엇을 얻었는지 알게 한다.
        guard isatty(STDIN_FILENO) == 1, isatty(STDOUT_FILENO) == 1 else {
            TUIRender.home(PokedoroCLI.homeModel(store), width: PokedoroCLI.terminalWidth()).forEach { print($0) }
            return
        }
        terminal.start()
        startReadingInput()
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            MainActor.assumeIsolated { self.tick() }
        }
        render()
        RunLoop.main.run()
    }

    // MARK: 입력

    /// stdin 읽기는 블로킹이라 별도 스레드에 둔다. 해석 결과만 메인으로 넘긴다 —
    /// `CompanionStore` 가 `@MainActor` 라 상태는 메인에서만 만진다.
    ///
    /// 입력이 멎으면 남은 바이트를 `flush` 로 확정한다. ESC 한 바이트는 그것만으로는 화살표
    /// 시퀀스의 첫 바이트와 구분되지 않아 `decode` 가 판단을 미루는데, 뒤 바이트가 영영 안 오는
    /// 것이 정상(사용자가 ESC 를 눌렀다)이라 그대로 두면 ESC 키가 죽는다.
    private func startReadingInput() {
        Thread.detachNewThread {
            var pending: [UInt8] = []
            var chunk = [UInt8](repeating: 0, count: 32)
            while true {
                let count = read(STDIN_FILENO, &chunk, chunk.count)
                guard count > 0 else { break }
                pending.append(contentsOf: chunk[0..<count])
                while let key = TUIKeyDecoder.decode(&pending) {
                    DispatchQueue.main.async { MainActor.assumeIsolated { self.handle(key) } }
                }
                // 덜 온 시퀀스는 다음 read 를 조금 기다려 본다. 그 사이에 아무것도 안 오면 확정한다.
                if !pending.isEmpty, !Self.inputIsWaiting(timeoutSeconds: 0.05),
                   let key = TUIKeyDecoder.flush(&pending) {
                    DispatchQueue.main.async { MainActor.assumeIsolated { self.handle(key) } }
                }
            }
        }
    }

    /// stdin 에 읽을 것이 있나. `select(2)` 는 시그널 핸들러에서 쓰는 함수가 아니라 여기서 그대로 쓴다.
    private nonisolated static func inputIsWaiting(timeoutSeconds: Double) -> Bool {
        var readSet = fd_set()
        fdZero(&readSet)
        fdSet(STDIN_FILENO, &readSet)
        var timeout = timeval(tv_sec: 0, tv_usec: __darwin_suseconds_t(timeoutSeconds * 1_000_000))
        return select(STDIN_FILENO + 1, &readSet, nil, nil, &timeout) > 0
    }

    private func handle(_ key: TUIKey) {
        // 쓰기 키(1·2·3·c·x)는 **앱에 요청을 보낸다** — 이 프로세스는 여전히 세이브에 쓰지 않는다.
        switch TUIKeymap.action(for: key, screen: screen, canWrite: true,
                                awaitingConfirmation: confirmation != nil) {
        case .quit:
            terminal.stop()
            exit(0)
        case .reload:
            reload()
            status = "다시 읽었다."
        case .show(let next):
            screen = next
            selection = 0
            status = nil
        case .scroll(let delta):
            selection = TUIKeymap.clamp(selection: selection, delta: delta, count: rows().count)
        case .startAdventure(let minutes):
            request(.start(minutes: minutes))
        case .claimAdventure:
            request(.claim)
        case .cancelAdventure:
            request(.stop)
        case .useSelected:
            if let item = selectedItem() { request(.use(item: item.kind)) }
        case .switchToSelected:
            if let mon = selectedMon() {
                request(.switchCompanion(number: TUIRender.printedRosterNumber(index: mon.index)))
            }
        case .releaseSelected:
            // 여기서 바로 보내지 않는다 — 개체가 영영 사라지므로 한 번 더 묻는다.
            if let mon = selectedMon() {
                confirmation = ("\(mon.name)을 놓아준다 — 되돌릴 수 없다",
                                .release(number: TUIRender.printedRosterNumber(index: mon.index)))
            }
        case .waveChoice(let number):
            // 숫자가 무엇이 되는지는 판의 국면이 정한다 — 표는 `WaveRunScreen` 하나다.
            if let action = WaveRunScreen.action(number: number, in: store.rogueRun) {
                request(action)
            }
        case .throwWaveBall:
            request(.waveBall(target: nil))
        case .forfeitWaveRun:
            // 여기서 바로 보내지 않는다 — 판이 통째로 사라지므로 한 번 더 묻는다(방생과 같다).
            if let run = store.rogueRun {
                confirmation = ("웨이브 \(run.wave) 까지 온 판을 버린다 — 되돌릴 수 없다",
                                .waveForfeit)
            }
        case .battleChoice(let number):
            // 대전 판은 세이브에 없다 — **앱이 보낸 화면의 키 안내**가 무엇을 누를 수 있는지
            // 말해 주므로, 여기서는 그 번호를 그대로 요청으로 보낸다. 목록 밖 번호는 앱이
            // 거절하고 사유를 답한다(제안 ⊆ 실행 가능은 앱 쪽에서 지킨다).
            request(.battleMove(move: number))
        case .forfeitBattle:
            confirmation = ("이 대전을 항복한다 — 되돌릴 수 없다", .battleForfeit)
        case .declineBattle:
            request(.battleDecline)
        case .roomChoice(let number):
            // 대전과 같다 — 무엇을 누를 수 있는지는 앱이 보낸 키 안내가 말해 주고, 목록 밖
            // 번호는 앱이 사유를 붙여 거절한다.
            request(.roomMove(move: number, target: nil))
        case .startRoom:
            request(.roomStart)
        case .leaveRoom:
            confirmation = ("이 방에서 나간다 — 이 판의 정산을 못 받는다", .roomLeave)
        case .confirm:
            if let action = confirmation?.action { request(action) }
            confirmation = nil
        case .cancelConfirmation:
            confirmation = nil
            status = "취소했다."
        case .rejected(.readOnly):
            status = "이 실행에는 쓰기 권한이 없다 — 집중 세션은 앱이 실행한다."
        case .ignored:
            return
        }
        render()
    }

    /// 커서가 가리키는 개체·아이템. 목록이 비었거나 커서가 범위를 벗어나면 `nil` 이다 —
    /// 그 값을 그대로 첨자로 쓰면 배열 밖을 읽는다.
    private func selectedMon() -> CompanionStore.ChatRosterEntry? {
        guard screen == .party else { return nil }
        let entries = PokedoroCLI.partyEntries(store)
        return entries.indices.contains(selection) ? entries[selection] : nil
    }

    private func selectedItem() -> (kind: ItemKind, count: Int)? {
        guard screen == .bag else { return nil }
        let items = PokedoroCLI.bagEntries(store)
        return items.indices.contains(selection) ? items[selection] : nil
    }

    /// 커서 행이 **대상이 될 수 있는가.** 안내가 이 값을 읽는다 — 이미 나와 있는 개체를 가리킬 때
    /// "s 교체" 를 권하면 눌러도 거절만 돌아온다. 실행을 막지는 않는다(거절 사유는 앱이 말한다).
    private func canActOnSelection() -> Bool {
        switch screen {
        case .party: selectedMon().map { !$0.isActive } ?? false
        case .bag: selectedItem() != nil
        // 판 화면에는 커서가 없다 — 웨이브의 선택은 숫자 키이고 유효성은 `WaveRunScreen` 이 본다.
        case .home, .dex, .challenge, .goals, .wave, .battle, .room: false
        }
    }

    private func reload() {
        store = CompanionStore(isReadOnly: true)
        selection = min(selection, max(0, rows().count - 1))
    }

    /// 앱에 요청을 남기고 **기다리지 않는다.** 여기서 막으면 화면이 3초 얼어붙는데, 이 화면은
    /// 이미 0.5초마다 다시 그리므로 답은 다음 프레임들이 알아서 집어 온다.
    ///
    /// 답을 못 받은 채 시간이 지나면 "앱이 응답하지 않는다" 로 바뀐다 — 침묵으로 두면 사용자는
    /// 키가 안 먹은 것과 앱이 꺼진 것을 구분할 수 없다.
    private func request(_ action: PokedoroRequest.Action) {
        let request = PokedoroRequest(id: UUID(), action: action, requestedAt: Date())
        do {
            try mailbox.send(request)
        } catch {
            status = "요청을 남기지 못했다: \(error.localizedDescription)"
            return
        }
        pending = request
        status = "앱에 요청했다…"
    }

    /// 기다리던 답이 왔는지 본다. 매 프레임 부른다 — 요청이 없으면 아무것도 안 한다.
    private func collectReplyIfNeeded() {
        guard let request = pending else { return }
        if let reply = mailbox.reply(to: request.id) {
            pending = nil
            status = reply.message
            reload()   // 앱이 바꾼 진행을 곧바로 끌어온다 — 5초 주기를 기다리면 답과 화면이 어긋난다.
            return
        }
        guard Date().timeIntervalSince(request.requestedAt) > PokedoroCLI.replyTimeout else { return }
        pending = nil
        status = "메뉴바 앱이 응답하지 않는다 — 집중 세션은 앱이 실행한다."
    }

    // MARK: 그리기

    private func tick() {
        frame += 1
        // 보고 있다고 계속 인사한다 — 앱은 나이로 판정하므로 멈추면 곧 "아무도 안 본다" 가 된다.
        let size = terminal.size
        try? mailbox.attach(PokedoroAttachment(id: attachmentID, width: size.width,
                                               height: size.height, at: Date()))
        // 낡은 화면은 버린다. 앱이 죽으면 파일은 마지막 상태로 얼어붙는데, 그대로 그리면 사용자는
        // 멈춘 타이머를 도는 것으로 읽는다.
        appView = mailbox.view().flatMap { PokedoroViewChannel.isStale($0, now: Date()) ? nil : $0 }
        collectReplyIfNeeded()
        // 주기적 재읽기 — 메뉴바 앱이 바꾼 진행을 끌어온다. 사용자가 r 을 누르지 않아도 낡지 않게.
        if frame % Self.reloadEveryFrames == 0 { reload() }
        render()
    }

    /// 목록 행. 폭은 **표식 칸을 뺀 값**으로 넘긴다 — 전체 폭으로 만들면 `TUIRender.list` 가
    /// 커서 표식을 붙인 뒤 오른쪽(개수·진행도)을 잘라 낸다.
    private func rows() -> [String] {
        let width = TUIRender.listRowWidth(terminal.size.width)
        switch screen {
        case .home, .wave, .battle, .room: return []
        case .party: return PokedoroCLI.partyRows(store)
        case .dex: return PokedoroCLI.dexRows(store)
        case .bag: return PokedoroCLI.bagRows(store, width: width)
        case .challenge: return PokedoroCLI.challengeRows(store, width: width)
        case .goals: return PokedoroCLI.goalRows(store, width: width)
        }
    }

    /// **앱이 만든 줄을 그대로 그린다.** 라이브 기능의 판은 앱 프로세스에만 살아 터미널이 스스로
    /// 조립할 수 없다 — 웨이브 런과 갈리는 지점이다(그쪽은 세이브에서 읽는다).
    ///
    /// 화면 이름을 받는 이유는 기능이 늘기 때문이다. 대전 전용으로 두면 방·다음 기능마다 같은
    /// 절차가 한 벌씩 복제되고, 그중 하나만 고쳐지는 날이 온다.
    private func liveLines(screen name: String, on screen: TUIScreen,
                           absent: String, width: Int) -> [String] {
        var lines = [TUIRender.row(left: appView?.screen == name ? (appView?.title ?? screen.title)
                                        : screen.title,
                                   right: "", width: width),
                     TUIRender.rule(width: width)]
        if let view = appView, view.screen == name {
            lines += view.lines.map { TUIText.truncate($0, to: width) }
            lines.append(TUIRender.rule(width: width))
            if let status { lines.append(TUIText.truncate(status, to: width)) }
            let hint = confirmation.map { TUIRender.confirmationHint(question: $0.question) }
                ?? view.keys.joined(separator: "   ")
            lines.append(TUIText.truncate(hint, to: width))
        } else {
            // 붙었는데도 이 화면이 안 오면 **앱이 그 기능을 들고 있지 않다는 뜻**이다.
            // 빈 화면을 그리면 사용자는 터미널이 고장난 줄 안다.
            lines.append(TUIText.truncate(absent, to: width))
            if let status { lines.append(TUIText.truncate(status, to: width)) }
        }
        return lines + TUIRender.screenHintLines(current: screen, width: width)
    }

    private func render() {
        let size = terminal.size
        var model = PokedoroCLI.homeModel(store)
        model.status = status
        var lines: [String]
        switch screen {
        case .home:
            lines = TUIRender.home(model, width: size.width, keyHints: true)
            // 앱만 아는 값(집중 타이머)은 세이브에 없으므로 스냅샷으로만 온다. 붙어 있지 않거나
            // 앱이 조용하면 그냥 없는 것이다 — 없는 줄을 만들어 채우지 않는다.
            if let view = appView {
                lines.append(TUIRender.rule(width: size.width))
                lines += view.lines.map { TUIText.truncate($0, to: size.width) }
            }
        case .wave:
            // 판이 세이브에 남으므로 화면 채널을 타지 않는다 — 조회 명령(`pokedoro wave`)과
            // **같은 함수**를 읽으므로 두 화면이 갈라질 자리가 없다.
            lines = WaveRunScreen.lines(store.rogueRun, language: store.language, width: size.width)
            lines.append(TUIRender.rule(width: size.width))
            if let status { lines.append(TUIText.truncate(status, to: size.width)) }
            let hint = confirmation.map { TUIRender.confirmationHint(question: $0.question) }
                ?? WaveRunScreen.hints(store.rogueRun)
            lines.append(TUIText.truncate(hint, to: size.width))
            lines += TUIRender.screenHintLines(current: .wave, width: size.width)
        case .battle:
            lines = liveLines(screen: "battle", on: .battle,
                              absent: "진행 중인 대전이 없다 — 신청은 앱의 친구 탭에서 한다.",
                              width: size.width)
        case .room:
            lines = liveLines(screen: "room", on: .room,
                              absent: "방에 없다 — 방을 만들거나 찾는 일은 앱에서 한다.",
                              width: size.width)
        case .party, .dex, .bag, .challenge, .goals:
            // 머리글 2줄 + 바닥글 2줄을 빼고 남는 만큼이 목록 창이다.
            let listHeight = max(1, size.height - 5)
            lines = [TUIRender.row(left: screen.title,
                                   right: "★ \(TUIRender.number(store.availableTokens))",
                                   width: size.width),
                     TUIRender.rule(width: size.width)]
            lines += TUIRender.list(rows: rows(), selection: selection,
                                    height: listHeight, width: size.width)
            lines.append(TUIRender.rule(width: size.width))
            if let confirmation {
                lines.append(TUIText.truncate(
                    TUIRender.confirmationHint(question: confirmation.question), to: size.width))
            } else {
                lines += TUIRender.listHintLines(screen: screen,
                                                 canActOnSelection: canActOnSelection(),
                                                 width: size.width)
            }
        }
        terminal.draw(lines, height: size.height)
    }
}

/// `FD_ZERO`·`FD_SET` 은 C 매크로라 Swift 로 넘어오지 않는다. `fd_set` 의 비트 배열을 직접 만진다.
private func fdZero(_ set: inout fd_set) {
    withUnsafeMutableBytes(of: &set.fds_bits) { bytes in
        _ = bytes.initializeMemory(as: UInt8.self, repeating: 0)
    }
}

private func fdSet(_ descriptor: Int32, _ set: inout fd_set) {
    let index = Int(descriptor) / 32
    let bit = Int32(1) << (Int32(descriptor) % 32)
    withUnsafeMutableBytes(of: &set.fds_bits) { bytes in
        let words = bytes.bindMemory(to: Int32.self)
        guard index < words.count else { return }
        words[index] |= bit
    }
}
