import Foundation

/// 터미널이 보낸 요청을 **앱이** 실행한다. 세이브를 바꾸는 쪽은 끝까지 앱 하나다.
///
/// 세 층이 갈라져 있다:
/// - **판정**은 `PokedoroSessionGate` — 화면·대화·터미널이 같은 표를 읽는다.
/// - **실행**은 세 단일 진입점(`startFocusSession`·`claimAdventure`·`stopFocusSession`).
///   여기서 `state.adventure` 를 직접 만지지 않는다 — 네 번째 경로가 생기면 정산·미션·업적
///   훅이 한 곳에서만 돌던 계약이 깨진다.
/// - **문구**만 이 파일이 만든다. 사람이 읽는 한국어라 대화의 영문 기계 문자열과 다른 물건이다.
///
/// `PokeTokenBarApp` 이 아니라 여기 있는 이유는 앱 루트에 테스트가 닿지 않기 때문이다 —
/// `TUITerminal`·`TUIWatch` 에 판단을 두지 않는 것과 같은 규칙이다. 앱은 이 타입을 부르기만 한다.
@MainActor
struct PokedoroRequestExecutor {
    let timer: FocusTimer
    let companion: CompanionStore

    func execute(_ request: PokedoroRequest) -> PokedoroReply {
        switch request.action {
        case .start(let minutes): start(request, minutes: minutes)
        case .claim: claim(request)
        case .stop: stop(request)
        }
    }

    // MARK: 동작

    private func start(_ request: PokedoroRequest, minutes requested: Int?) -> PokedoroReply {
        // 요청 파일은 손으로 고칠 수 있는 **신뢰경계**다. 적힌 분을 그대로 믿으면 화면이 제시하지
        // 않는 길이를 터미널만 켤 수 있다 — 접는 표는 대화와 공유한다.
        let minutes = PokemonChatTool.nearestFocusLength(to: requested ?? PokemonChatTool.focusMinutes[0])
        if let refusal = PokedoroSessionGate.startRefusal(sessionState) {
            return reply(request, refused: refusal)
        }
        // 게이트를 지났는데도 실패하면 조건이 하나 더 있는 것이다. 성공으로 뭉개면 사용자는
        // 시작됐다고 들은 채 아무 일도 안 일어난 화면을 본다.
        guard timer.startFocusSession(minutes: minutes, companion: companion) else {
            return PokedoroReply(id: request.id, succeeded: false, message: "집중을 시작하지 못했다.")
        }
        return PokedoroReply(id: request.id, succeeded: true,
                             message: "\(minutes)분 집중을 시작했다. 파트너는 \(zoneName(minutes))으로 떠났다.")
    }

    private func claim(_ request: PokedoroRequest) -> PokedoroReply {
        if let refusal = PokedoroSessionGate.claimRefusal(sessionState) {
            return reply(request, refused: refusal)
        }
        // 완료 판정의 권위는 여전히 여기 하나다 — 게이트는 **부르기 전에 사유를 말하려고** 있다.
        guard let reward = companion.claimAdventure() else {
            return PokedoroReply(id: request.id, succeeded: false, message: "받을 보상이 없다.")
        }
        return PokedoroReply(id: request.id, succeeded: true,
                             message: "보상을 받았다. " + Self.summary(reward))
    }

    private func stop(_ request: PokedoroRequest) -> PokedoroReply {
        if let refusal = PokedoroSessionGate.stopRefusal(sessionState) {
            return reply(request, refused: refusal)
        }
        // 끝난 모험은 버리지 않는다 — `stopFocusSession` 이 정산을 먼저 한다.
        timer.stopFocusSession(companion: companion)
        return PokedoroReply(id: request.id, succeeded: true, message: "집중을 끝냈다.")
    }

    // MARK: 값

    /// 판정에 쓸 값 한 벌. `isRunning` 의 두 조건을 경계에서 한 값으로 접는다(대화 실행기와 같다).
    private var sessionState: PokedoroSessionState {
        PokedoroSessionState(phase: timer.isRunning ? timer.phase : .idle,
                             hasCompanion: companion.hasActive,
                             hasAdventure: companion.activeAdventure != nil,
                             adventureIsInProgress: companion.isAdventureInProgress)
    }

    /// 시작 길이 → 지역. 규칙은 `startFocusAdventure` 가 들고 있고 여기선 **이름만** 붙인다.
    private func zoneName(_ minutes: Int) -> String {
        PokedoroCLI.zoneLabel(minutes >= 90 ? .coast : (minutes >= 50 ? .cave : .forest))
    }

    // MARK: 문구

    private func reply(_ request: PokedoroRequest, refused: PokedoroSessionGate.Refusal) -> PokedoroReply {
        PokedoroReply(id: request.id, succeeded: false, message: Self.humanLine(refused))
    }

    /// 거절 사유 → 사람이 읽는 한 줄. **다음에 할 일을 같이 말한다** — 사유만 주면 사용자는
    /// 같은 명령을 다시 친다.
    ///
    /// ponytail: 터미널 전체가 그렇듯 한국어 고정이다. 다국어는 `TUIRender` 까지 함께 옮길 때 한다.
    static func humanLine(_ refusal: PokedoroSessionGate.Refusal) -> String {
        switch refusal {
        case .timerAlreadyRunning(.rest): "지금은 휴식 중이다. 휴식이 끝나면 다시 시작할 수 있다."
        case .timerAlreadyRunning: "이미 집중 중이다. 끝내려면 stop 을 쓴다."
        case .adventureInProgress: "파트너가 아직 모험 중이다. 남은 시간을 채워야 한다."
        case .adventureUnclaimed: "끝난 모험의 보상이 남아 있다. claim 으로 먼저 받는다."
        case .noCompanion: "함께 다니는 포켓몬이 없다. 앱에서 알을 부화시킨다."
        case .nothingRunning: "끝낼 집중이 없다."
        case .nothingToClaim: "받을 보상이 없다."
        }
    }

    /// 정산 요약. 줄 조립은 `AdventureReward.bannerLines` 가 한다 — 여기서 `if` 로 다시 세면
    /// 지급 경로가 늘 때 터미널만 뒤처지고, 그걸 걸러 줄 테스트가 생길 자리가 없다.
    private static func summary(_ reward: AdventureReward) -> String {
        reward.bannerLines.map { line in
            switch line {
            case .eggs(let count): "신비한 알 +\(count)"
            case .settled(let stardust): "별의조각 +\(TUIRender.number(stardust))"
            case .overflowConverted(let stardust): "(만렙 초과분 \(TUIRender.number(stardust)) 환산 포함)"
            case .rareCandy: "이상한사탕 +1"
            }
        }.joined(separator: " · ")
    }
}
