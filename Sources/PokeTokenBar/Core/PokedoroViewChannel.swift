import Foundation

/// 터미널이 "지금 보고 있다" 고 남기는 신호. **터미널만 쓴다**(`pokedoro-attach.json`).
///
/// 앱이 이 신호를 보는 이유는 둘이다. ⓐ 아무도 안 보는데 스냅샷을 쓰면 디스크만 갈린다.
/// ⓑ 터미널에서 대전을 보고 있는 사용자에게 앱 창이 튀어나오면 화면이 통째로 가려진다.
struct PokedoroAttachment: Codable, Equatable, Sendable {
    var id: UUID
    /// **터미널의 칸 수.** 줄을 만드는 쪽이 앱이므로 폭을 앱이 알아야 한다 — 모르면 80칸을
    /// 가정하게 되고, 좁은 창에서는 매 줄이 접혀 화면이 흘러간다.
    var width: Int
    var height: Int
    /// 마지막 인사 시각. 터미널은 살아 있는 동안 주기적으로 갱신한다.
    var at: Date
}

/// 앱이 내놓는 **지금 화면 한 장**. 앱만 쓴다(`pokedoro-view.json`).
///
/// 줄을 이미 사람이 읽는 문자열로 담는 이유는, 무엇이 벌어지고 있는지 아는 곳이 앱뿐이기
/// 때문이다(대전 판·레이드 방·교환 상은 전부 앱 프로세스에 산다). 터미널은 **그리기만** 한다 —
/// 기능마다 구조체를 새로 만들면 라이브 기능 수만큼 모델이 늘고, 그 모델은 전부 한쪽에서만 쓰인다.
///
/// 폭은 `PokedoroAttachment.width` 를 쓴다. 그래서 줄 조립도 결국 같은 `TUIRender` 규칙을 탄다.
struct PokedoroViewSnapshot: Codable, Equatable, Sendable {
    /// 무엇을 보고 있는지. 터미널은 이 값으로 머리글·복귀 경로를 고른다.
    var screen: String
    var title: String
    var lines: [String]
    /// 지금 누를 수 있는 키. **앱이 보낸다** — 무엇을 할 수 있는지 아는 곳이 앱이고, 터미널이
    /// 따로 판정하면 두 표가 갈라져 먹지도 않는 키를 권하게 된다.
    var keys: [String]
    var writtenAt: Date
}

/// 화면 채널의 판정. 순수 함수로 두는 이유는 **프로세스 둘을 띄우지 않고 전수 검증**하기
/// 위해서다 — 요청 우편함(`PokedoroRequestBus`)과 같은 규칙이다.
enum PokedoroViewChannel {
    /// 신호가 살아 있는 시간. 터미널의 갱신 주기(0.5초 프레임)보다 넉넉히 크되, 터미널이 죽은 뒤
    /// 앱이 스냅샷을 계속 쓰는 시간이기도 하므로 짧게 잡는다.
    static let attachmentTimeout: TimeInterval = 5
    /// 스냅샷을 믿는 시간. 앱이 죽으면 파일은 마지막 상태로 얼어붙으므로, 이 시간을 넘기면
    /// 화면은 "낡았다" 고 말해야 한다 — 멈춘 대전을 진행 중으로 읽으면 사용자는 계속 기다린다.
    static let snapshotTimeout: TimeInterval = 5

    /// 지금 터미널이 보고 있는가.
    ///
    /// **어긋남은 양쪽 대칭으로 본다.** 앞으로 어긋난 시각을 통과시키면 미래로 적은 신호 하나로
    /// 나이 제한이 통째로 우회되고, 그 파일이 남아 있는 한 앱은 영원히 붙어 있다고 믿는다
    /// (요청 나이 제한과 같은 이유이며, 이 파일도 손으로 고칠 수 있다).
    static func isAttached(_ attachment: PokedoroAttachment?, now: Date) -> Bool {
        guard let attachment else { return false }
        return abs(now.timeIntervalSince(attachment.at)) <= attachmentTimeout
    }

    /// 이 화면을 파일에 써야 하는가. **바뀐 것이 없으면 안 쓴다** — 연출 프레임마다 쓰면 디스크가
    /// 갈리고, 터미널은 바뀐 게 없는데도 매번 다시 그린다.
    ///
    /// 시각은 비교에서 뺀다. 넣으면 매번 달라져 이 판정이 아무것도 거르지 못한다.
    static func shouldWrite(_ snapshot: PokedoroViewSnapshot,
                            lastWritten: PokedoroViewSnapshot?) -> Bool {
        guard let lastWritten else { return true }
        return (snapshot.screen, snapshot.title, snapshot.lines, snapshot.keys)
            != (lastWritten.screen, lastWritten.title, lastWritten.lines, lastWritten.keys)
    }

    /// 이 화면이 낡았는가(앱이 조용해졌는가).
    static func isStale(_ snapshot: PokedoroViewSnapshot, now: Date) -> Bool {
        now.timeIntervalSince(snapshot.writtenAt) > snapshotTimeout
    }

    /// 줄을 만들 수 있는 폭. 파이프로 붙었거나 손으로 고친 파일에서 0·음수가 올 수 있는데,
    /// 그 값으로는 `TUIRender` 가 빈 줄만 내놓는다 — 화면이 죽는 대신 읽을 수 있는 폭으로 접는다.
    static let fallbackWidth = 80

    static func drawableWidth(_ width: Int) -> Int { width > 0 ? width : fallbackWidth }

    /// 집중 타이머 화면. **이 채널의 첫 생산자**다.
    ///
    /// `FocusTimer` 는 세이브에 저장되지 않으므로 터미널이 스스로 만들 수 없다 — 지금까지 `watch`
    /// 는 모험 진행만 보여 주고 "집중 12:34 남음" 은 못 보여 줬다. 앱만 아는 값을 앱이 내놓는
    /// 것이 이 채널의 존재 이유이고, 라이브 기능(대전·레이드…)은 같은 자리에 생산자를 더한다.
    ///
    /// 아무것도 안 돌면 `nil` 이다 — 빈 화면을 내놓으면 터미널이 빈 줄을 그리고 파일도 이유 없이
    /// 갱신된다.
    static func focusSnapshot(phase: FocusPhase, clockText: String, completed: Int,
                              now: Date) -> PokedoroViewSnapshot? {
        let title: String
        switch phase {
        case .idle: return nil
        case .focus: title = "집중 중"
        case .rest: title = "휴식 중"
        }
        return PokedoroViewSnapshot(
            screen: "focus",
            title: title,
            lines: ["\(title)   남은 시간 \(clockText)", "오늘 마친 집중  \(completed)회"],
            // 키는 앱이 정한다 — 무엇을 할 수 있는지 아는 곳이 앱이다. 지금 단계에서 할 수 있는
            // 것은 끝내기뿐이고, 시작 키는 홈이 이미 상태를 보고 고른다.
            keys: ["x 끝내기"],
            writtenAt: now)
    }
}
