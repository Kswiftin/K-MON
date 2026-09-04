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

    /// `async` 인 이유는 **부화 하나** 때문이다 — `hatchIfNeeded` 는 PokéAPI 에서 종 라인을 받아
    /// 온다. 앱은 이미 요청 id 를 실행 **전에** 기억하므로(`PokeTokenBarApp`), 이 await 를 넘는
    /// 1초 틱이 같은 요청을 두 번 실행하지 못한다.
    func execute(_ request: PokedoroRequest) async -> PokedoroReply {
        switch request.action {
        case .start(let minutes): return start(request, minutes: minutes)
        case .claim: return claim(request)
        case .stop: return stop(request)
        case .use(let item): return use(request, item: item)
        case .evolve: return evolve(request)
        case .switchCompanion(let number): return switchCompanion(request, number: number)
        case .rename(let nickname): return rename(request, nickname: nickname)
        case .buy(let good, let quantity): return buy(request, good: good, quantity: quantity)
        case .hatch: return await hatch(request)
        case .release(let number): return release(request, number: number)
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

    /// 아이템 하나 사용. **갈래를 고르는 표는 `CompanionAction` 하나이고 여기 남는 것은 문구뿐이다** —
    /// 대화가 같은 표를 읽으므로, 여기서 갈래를 다시 쓰면 한쪽만 고쳐진다.
    private func use(_ request: PokedoroRequest, item: ItemKind) -> PokedoroReply {
        let name = L(companion.language).itemName(item)
        switch CompanionAction.useItem(item, companion: companion) {
        case .candy(let result):
            return ok(request, "\(name)을 썼다 — \(Self.candyLine(result))")
        case .mint(let nature):
            return ok(request, "\(name)을 썼다. 성격이 \(nature.name(companion.language))가 됐다.")
        // 후보 카드가 떴을 뿐 아직 아무것도 안 바뀌었다 — 고르는 화면은 앱에만 있다. "바꿨다" 로
        // 답하면 사용자는 끝난 줄 알고 앱을 안 열어 본다.
        case .relearnOpened:
            return ok(request, "\(name)을 썼다. 배울 기술은 앱의 포켓몬 화면에서 고른다.")
        case .evolutionItemUsed:
            return ok(request, "\(name)을 썼다.")
        // 재고 부족과 **갈라 말한다**: 사러 가야 하는지, 애초에 쓰는 물건이 아닌지 다르다.
        case .notUsedThisWay:
            return no(request, "\(name)은 지니고만 있는 물건이라 쓰는 것이 아니다.")
        case .unavailable:
            return no(request, "가방에 쓸 수 있는 \(name)이 없다.")
        case .refused:
            return no(request, "지금은 \(name)을 쓸 수 없다.")
        }
    }

    private func evolve(_ request: PokedoroRequest) -> PokedoroReply {
        switch CompanionAction.acceptEvolution(companion: companion) {
        case .nonePending:
            return no(request, "진화를 기다리는 포켓몬이 없다.")
        // 카드가 뜬 뒤에 조건이 무너지는 건 실제로 밟힌다(밤 한정 진화를 새벽에 승인).
        case .conditionsNoLongerMet:
            return no(request, "지금은 진화 조건이 맞지 않는다.")
        case .evolved(let stage):
            let name = PokedoroCLI.partnerName(companion) ?? "파트너"
            return ok(request, "진화했다 — \(name) (\(stage + 1)번째 형태)")
        }
    }

    /// 파트너 교체. 번호는 `party` 가 찍는 값이고, **인덱스로 접는 것은 로스터를 아는 여기서** 한다.
    private func switchCompanion(_ request: PokedoroRequest, number: Int) -> PokedoroReply {
        let index = TUIRender.rosterIndex(printed: number)
        guard let target = companion.chatRosterEntries.first(where: { $0.index == index }) else {
            return no(request, "\(number)번 포켓몬이 없다 — party 로 번호를 확인한다.")
        }
        // 이미 나와 있는 개체로 바꾸는 것은 아무 일도 아니다. 성공으로 답하면 사용자는 교체가
        // 일어났다고 믿는다.
        guard !target.isActive else {
            return no(request, "\(target.name)은 이미 함께 다니고 있다.")
        }
        companion.switchCompanion(to: target.id)
        return ok(request, "\(target.name)와 함께 나섰다.")
    }

    /// 별명 바꾸기. 인자가 자유 문자열인 유일한 동작이라 **클램프가 여기 있다** — 요청 파일은
    /// 손으로 고칠 수 있으므로 명령 파서만 검사하면 그 경로가 통째로 빈다.
    private func rename(_ request: PokedoroRequest, nickname: String) -> PokedoroReply {
        guard companion.hasActive else {
            return no(request, "이름을 붙일 포켓몬이 없다.")
        }
        companion.setNickname(Self.oneLine(nickname))
        // 붙은 이름을 **되읽어서** 말한다. 내 클램프 결과를 그대로 echo 하면 세이브 경계가
        // 달라진 날 답과 실제가 갈라진다 — 사용자는 자기가 지은 이름이 왜 다른지 모른다.
        let applied = companion.chatRosterEntries.first { $0.isActive }?.name ?? Self.oneLine(nickname)
        return ok(request, "별명을 '\(applied)'로 바꿨다.")
    }

    /// 상점 구매. 값과 이름은 `ShopCatalog` 이 들고, 실행은 스토어의 구매 경로 그대로다 —
    /// 여기서 지갑을 직접 깎으면 화면 버튼과 다른 경로가 된다.
    private func buy(_ request: PokedoroRequest, good: ShopGood, quantity: Int) -> PokedoroReply {
        let name = good.displayName(companion.language)
        let total = good.price * quantity
        // 잔액을 먼저 본다 — 실패 사유 중 사용자가 **가장 자주 만나고 가장 고치기 쉬운** 것이라
        // 뭉뚱그린 거절보다 액수를 말해 주는 편이 낫다.
        guard companion.availableTokens >= total else {
            return no(request, "별의조각이 모자란다 — \(name) \(quantity)개에 "
                      + "\(TUIRender.number(total)), 지금 \(TUIRender.number(companion.availableTokens)).")
        }
        guard Self.purchase(good, quantity: quantity, companion: companion) else {
            return no(request, "지금은 \(name)을 살 수 없다.")
        }
        return ok(request, "\(name) \(quantity)개를 샀다. 남은 별의조각 "
                  + "\(TUIRender.number(companion.availableTokens)).")
    }

    /// 종류별 구매 경로. 스토어의 네 진입점을 그대로 부른다.
    private static func purchase(_ good: ShopGood, quantity: Int, companion: CompanionStore) -> Bool {
        switch good {
        case .item(let kind): companion.buy(kind, quantity: quantity)
        case .egg: (0..<quantity).allSatisfy { _ in companion.buyEgg(nil) }
        case .outfit(let item): companion.buyOutfit(item)
        case .machine(let machine): companion.buyTechnicalMachine(machine, quantity: quantity)
        }
    }

    /// 부화. **오래 걸릴 수 있다** — 종 라인을 네트워크에서 받아 온다. 터미널은 그동안 답을
    /// 기다리므로 한 번 찍고 끝나는 명령의 대기 시간이 이 동작에서만 길다.
    private func hatch(_ request: PokedoroRequest) async -> PokedoroReply {
        // 부화했는지는 **활성 개체가 생겼는가**로 판정한다. `hatchIfNeeded` 는 조건이 안 맞으면
        // 조용히 돌아가므로, 부르고 성공으로 답하면 사용자는 파트너가 생긴 줄 안다.
        guard !companion.hasActive else {
            return no(request, "이미 함께 다니는 포켓몬이 있다.")
        }
        await companion.hatchIfNeeded()
        guard companion.hasActive else {
            return no(request, "아직 부화할 알이 없다. 집중을 더 쌓으면 부화한다.")
        }
        return ok(request, "알이 부화했다 — \(PokedoroCLI.partnerName(companion) ?? "새 친구")!")
    }

    /// 방생. **되돌릴 수 없다** — 확인은 명령 쪽(`--yes`)에서 이미 받았고, 여기서는 대상만 찾는다.
    private func release(_ request: PokedoroRequest, number: Int) -> PokedoroReply {
        let index = TUIRender.rosterIndex(printed: number)
        guard let target = companion.chatRosterEntries.first(where: { $0.index == index }) else {
            return no(request, "\(number)번 포켓몬이 없다 — party 로 번호를 확인한다.")
        }
        // `releaseMon` 은 박스 개체만 놓아주고 즐겨찾기·체육관 방어를 거절한다. 사유를 갈라
        // 말하지 않으면 사용자는 왜 안 되는지 모른 채 같은 명령을 반복한다.
        guard !target.isActive else {
            return no(request, "\(target.name)은 함께 다니는 중이라 놓아줄 수 없다. 먼저 switch 로 바꾼다.")
        }
        guard companion.releaseMon(target.id) else {
            return no(request, "\(target.name)은 놓아줄 수 없다 — 즐겨찾기이거나 체육관을 지키는 중이다.")
        }
        return ok(request, "\(target.name)을 놓아줬다.")
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

    private func ok(_ request: PokedoroRequest, _ message: String) -> PokedoroReply {
        PokedoroReply(id: request.id, succeeded: true, message: message)
    }

    private func no(_ request: PokedoroRequest, _ message: String) -> PokedoroReply {
        PokedoroReply(id: request.id, succeeded: false, message: message)
    }

    /// 사탕 결과 → 사람 문장. `.unavailable` 은 여기 없다 — 그건 결과가 아니라 재고 없음이고,
    /// `CompanionAction` 이 경계에서 이미 갈라 놨다.
    private static func candyLine(_ result: CompanionStore.CandyUseResult) -> String {
        switch result {
        case .evolved: "진화했다!"
        case .graduated: "졸업했다!"
        case .progressed: "경험이 쌓였다."
        case .unavailable: "아무 일도 없었다."
        }
    }

    /// 한 줄로 접는다. 별명이 줄바꿈·탭을 물고 들어오면 상태줄·목록이 그 줄부터 어긋난다 —
    /// `setNickname` 은 **양끝만** 다듬으므로 가운데 개행은 그대로 통과한다.
    private static func oneLine(_ text: String) -> String {
        text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
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
