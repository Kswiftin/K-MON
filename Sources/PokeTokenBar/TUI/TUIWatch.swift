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
        switch TUIKeymap.action(for: key, screen: screen, canWrite: true) {
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
            request(.start, minutes: minutes)
        case .claimAdventure:
            request(.claim, minutes: nil)
        case .cancelAdventure:
            request(.stop, minutes: nil)
        case .rejected(.readOnly):
            status = "이 실행에는 쓰기 권한이 없다 — 집중 세션은 앱이 실행한다."
        case .ignored:
            return
        }
        render()
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
    private func request(_ verb: PokedoroRequest.Verb, minutes: Int?) {
        let request = PokedoroRequest(id: UUID(), verb: verb, minutes: minutes, requestedAt: Date())
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
        case .home: return []
        case .party: return PokedoroCLI.partyRows(store)
        case .dex: return PokedoroCLI.dexRows(store)
        case .bag: return PokedoroCLI.bagRows(store, width: width)
        case .challenge: return PokedoroCLI.challengeRows(store, width: width)
        case .goals: return PokedoroCLI.goalRows(store, width: width)
        }
    }

    private func render() {
        let size = terminal.size
        var model = PokedoroCLI.homeModel(store)
        model.status = status
        var lines: [String]
        switch screen {
        case .home:
            lines = TUIRender.home(model, width: size.width, keyHints: true)
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
            lines.append(TUIText.truncate("↑↓/jk 이동   " + TUIRender.screenHints(current: screen),
                                          to: size.width))
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
