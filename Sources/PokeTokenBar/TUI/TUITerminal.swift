import Darwin
import Foundation

/// 터미널 자체를 다루는 얇은 층 — raw mode, 대체 화면, 커서, 크기. 여기만 부수효과를 가진다.
///
/// **복원이 핵심이다.** raw mode 로 바꾼 termios 를 되돌리지 못한 채 프로세스가 끝나면 사용자의
/// 셸이 에코 없는 상태로 남아 입력이 보이지 않는다. 그래서 정상 종료뿐 아니라 시그널
/// (Ctrl+C·터미널 닫힘)에서도 복원을 건다.
/// 시그널 핸들러가 되돌릴 원래 termios. 핸들러는 async-signal-safe 한 일만 해야 하므로 객체를
/// 참조하지 않고 이 전역만 읽는다 — 프로세스에 터미널은 하나뿐이라 인스턴스가 여럿일 수 없다.
nonisolated(unsafe) private var tuiSavedTermios = termios()
nonisolated(unsafe) private var tuiRawModeActive = false

/// 시그널 핸들러 본체. 화면을 되돌리고 termios 를 복원한 뒤 기본 동작으로 다시 죽는다.
/// `write(2)` 와 `tcsetattr(3)` 만 부른다 — 둘 다 핸들러에서 안전하다.
private func tuiRestoreOnSignal(_ received: Int32) {
    if tuiRawModeActive {
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &tuiSavedTermios)
        tuiRawModeActive = false
    }
    let reset = "\u{1B}[?25h\u{1B}[?1049l"
    _ = reset.withCString { write(STDOUT_FILENO, $0, strlen($0)) }
    signal(received, SIG_DFL)
    raise(received)
}

final class TUITerminal {
    // MARK: 모드 전환

    func start() {
        enableRawMode()
        installRestoreOnSignals()
        write("\u{1B}[?1049h")   // 대체 화면 — 종료하면 셸 스크롤백이 그대로 돌아온다
        write("\u{1B}[?25l")     // 커서 숨김
        clear()
    }

    func stop() {
        write("\u{1B}[?25h")
        write("\u{1B}[?1049l")
        disableRawMode()
    }

    private func enableRawMode() {
        guard isatty(STDIN_FILENO) == 1, tcgetattr(STDIN_FILENO, &tuiSavedTermios) == 0 else { return }
        var raw = tuiSavedTermios
        // 정규 모드(줄 단위 입력)와 에코를 끈다. 신호 키(Ctrl+C)는 살려 둔다 — 강제로 빠져나올
        // 마지막 수단을 없애면 복원 실패 시 셸이 잠긴다.
        raw.c_lflag &= ~tcflag_t(ECHO | ICANON)
        raw.c_iflag &= ~tcflag_t(IXON)
        withUnsafeMutableBytes(of: &raw.c_cc) { bytes in
            bytes[Int(VMIN)] = 1     // 최소 1바이트 모일 때까지 read 가 블록
            bytes[Int(VTIME)] = 0
        }
        if tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw) == 0 { tuiRawModeActive = true }
    }

    private func disableRawMode() {
        guard tuiRawModeActive else { return }
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &tuiSavedTermios)
        tuiRawModeActive = false
    }

    /// 시그널로 죽어도 터미널을 되돌린다. 복원 없이 끝나면 사용자의 셸이 에코 없는 상태로 남아
    /// 입력이 보이지 않는다 — 무엇을 쳤는지 안 보이는 셸은 사실상 고장난 터미널이다.
    private func installRestoreOnSignals() {
        for number in [SIGINT, SIGTERM, SIGHUP, SIGQUIT] {
            signal(number, tuiRestoreOnSignal)
        }
    }

    // MARK: 출력

    func write(_ text: String) {
        FileHandle.standardOutput.write(Data(text.utf8))
    }

    func clear() { write("\u{1B}[2J\u{1B}[H") }

    /// 한 프레임을 그린다. 전체 clear 를 매번 하면 깜빡이므로, 커서를 홈으로 옮기고 줄마다
    /// "쓰고 → 줄 끝까지 지우기" 를 한다. 남은 아랫줄은 화면 끝까지 지운다 — 이전 프레임이 더
    /// 길었을 때 그 잔상이 남지 않게.
    func draw(_ lines: [String], height: Int) {
        var frame = "\u{1B}[H"
        for line in lines.prefix(height) {
            frame += line + "\u{1B}[K\r\n"
        }
        frame += "\u{1B}[J"
        write(frame)
    }

    // MARK: 크기

    /// 터미널 칸 수. 파이프로 붙었거나 조회에 실패하면 보수적인 기본값을 쓴다 — 0 을 그대로
    /// 흘리면 레이아웃 계산이 전부 음수가 된다.
    var size: (width: Int, height: Int) {
        var window = winsize()
        guard ioctl(STDOUT_FILENO, UInt(TIOCGWINSZ), &window) == 0,
              window.ws_col > 0, window.ws_row > 0 else { return (80, 24) }
        return (Int(window.ws_col), Int(window.ws_row))
    }
}

/// stdin 바이트열을 `TUIKey` 로 바꾼다. 화살표는 한 글자가 아니라 `ESC [ A` 같은 시퀀스로 온다.
enum TUIKeyDecoder {
    /// 버퍼 앞에서 키 하나를 떼어 낸다. 시퀀스가 덜 왔으면 `nil` 을 돌려 다음 바이트를 기다린다.
    ///
    /// `nil` 로 남는 바이트가 있을 수 있다 — ESC 한 바이트만 온 경우다(사용자가 ESC 를 눌렀는지,
    /// 화살표 시퀀스의 첫 바이트인지 이 시점에는 구분할 수 없다). 입력이 잠시 멎으면
    /// `flush(_:)` 가 그것을 ESC 로 확정한다.
    static func decode(_ buffer: inout [UInt8]) -> TUIKey? {
        guard !buffer.isEmpty else { return nil }
        if buffer[0] != 0x1B {
            let byte = buffer.removeFirst()
            // UTF-8 선행 바이트면 이어지는 바이트까지 모아 한 문자로 만든다. 한글 입력이 세 개의
            // 깨진 키로 흩어지지 않게.
            return character(from: byte, buffer: &buffer)
        }
        // ESC 단독인지 시퀀스인지는 뒤 바이트로 갈린다. 아직 안 왔으면 판단을 미룬다.
        if buffer.count == 1 { return nil }
        if buffer[1] != 0x5B {   // '[' 가 아니면 시퀀스가 아니다 — ESC 를 그대로 낸다.
            buffer.removeFirst()
            return .escape
        }
        guard buffer.count >= 3 else { return nil }
        let final = buffer[2]
        buffer.removeFirst(3)
        switch final {
        case 0x41: return .up      // 'A'
        case 0x42: return .down    // 'B'
        default: return .unknown
        }
    }

    /// 입력이 멎었을 때 남은 바이트를 확정한다. **ESC 단독을 살리는 유일한 경로다** — 그것만으로는
    /// 화살표의 첫 바이트와 구분할 수 없어 `decode` 는 판단을 미루고, 뒤 바이트가 영영 안 오면
    /// 그대로 묻힌다(ESC 로 목록에서 빠져나오려던 사용자에겐 키가 죽은 것으로 보인다).
    static func flush(_ buffer: inout [UInt8]) -> TUIKey? {
        guard !buffer.isEmpty else { return nil }
        guard buffer[0] == 0x1B else { return decode(&buffer) }
        // 덜 온 시퀀스(ESC [ 까지만 온 경우)도 여기서 버린다 — 다음 입력에 섞이면 그 키가 깨진다.
        buffer.removeFirst(buffer.count)
        return .escape
    }

    /// UTF-8 멀티바이트를 모아 한 문자로. 바이트가 덜 왔으면 되돌려 놓고 다음 read 를 기다린다.
    private static func character(from first: UInt8, buffer: inout [UInt8]) -> TUIKey? {
        // 이어지는 바이트(0x80...0xBF)가 홀로 왔다는 것은 앞이 잘렸다는 뜻이다. Latin-1 문자로
        // 읽으면 한글 한 글자가 알파벳 세 개로 흩어져 그중 하나가 화면 전환 키로 먹힌다.
        if (0x80...0xBF).contains(first) { return .unknown }
        let extra = first >= 0xF0 ? 3 : (first >= 0xE0 ? 2 : (first >= 0xC0 ? 1 : 0))
        guard extra > 0 else { return .char(Character(UnicodeScalar(first))) }
        guard first < 0xF8 else { return .unknown }   // UTF-8 에 없는 선행 바이트
        guard buffer.count >= extra else {
            buffer.insert(first, at: 0)   // 미완성 시퀀스는 되돌린다
            return nil
        }
        let bytes = [first] + buffer.prefix(extra)
        buffer.removeFirst(extra)
        // 잘못된 시퀀스는 대체 문자(U+FFFD)로 디코딩된다 — 그것을 키로 흘리지 않는다.
        guard let character = String(decoding: bytes, as: UTF8.self).first,
              character != "\u{FFFD}" else { return .unknown }
        return .char(character)
    }
}
