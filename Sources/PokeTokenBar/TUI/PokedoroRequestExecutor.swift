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
    /// LAN 대전에 닿는 좁은 창구. **`nil` 은 "대전이 없다" 와 같은 뜻**이다 — 창구가 없으면
    /// 볼 판도 낼 턴도 없으므로 사유를 따로 만들지 않는다(앱은 늘 연결해 넘긴다).
    var battle: (any TerminalBattleControl)?
    /// LAN 방(레이드·방 대전)에 닿는 창구. `battle` 과 같은 이유로 좁게 두고, `nil` 은
    /// "방에 없다" 와 같은 뜻이다.
    var room: (any TerminalRoomControl)?
    /// 교환에 닿는 창구. 같은 이유로 좁게 두고, `nil` 은 "교환이 없다" 와 같은 뜻이다.
    var trade: (any TerminalTradeControl)?

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
        case .waveStart(let starter): return await waveStart(request, starter: starter)
        case .waveMove(let move, let target):
            return await waveMove(request, move: move, target: target)
        case .waveSwitch(let number): return await waveSwitch(request, number: number)
        case .waveBall(let target): return await waveBall(request, target: target)
        case .wavePick(let number): return await wavePick(request, number: number)
        case .waveRoute(let route): return await waveRoute(request, route: route)
        case .waveForfeit: return waveForfeit(request)
        case .battleMove(let move): return battleMove(request, move: move)
        case .battleSwitch(let number): return battleSwitch(request, number: number)
        case .battleForfeit: return battleForfeit(request)
        case .battleDecline: return battleDecline(request)
        case .roomMove(let move, let target): return roomMove(request, move: move, target: target)
        case .roomStart: return roomStart(request)
        case .roomLeave: return roomLeave(request)
        case .tradeAccept: return tradeAnswer(request, accept: true)
        case .tradeDecline: return tradeAnswer(request, accept: false)
        case .tradeOffer(let number): return tradeOffer(request, number: number)
        case .tradeWant(let number): return tradeWant(request, number: number)
        case .tradeConfirm: return tradeConfirm(request)
        case .tradeCancel: return tradeCancel(request)
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

    // MARK: 웨이브 런
    //
    // 규칙은 `RogueRun` 이, 무엇을 고를 수 있는지는 `WaveRunScreen` 이, 네트워크는
    // `WaveRunLoader` 가 든다. 여기 남는 것은 **거절 사유를 갈라 말하는 일**뿐이다 — 뭉뚱그리면
    // 사용자는 무엇을 고쳐야 할지 모른 채 같은 명령을 반복한다.

    /// 지금 판. **상대를 받다 만 판은 여기서 이어 받는다** — `.loadingWave` 에는 사용자가 보낼
    /// 동작이 없으므로, 네트워크가 한 번 흔들린 판은 여기서 다시 열지 않으면 영영 멈춘다.
    private func currentRun() async -> RogueRun? {
        if companion.rogueRun?.stage == .loadingWave {
            await WaveRunLoader.openNextWaveIfNeeded(store: companion)
        }
        return companion.rogueRun
    }

    private func waveStart(_ request: PokedoroRequest, starter: Int?) async -> PokedoroReply {
        // 진행 중인 판을 덮어쓰지 않는다 — 되돌릴 수 없는 손실이고, 버리는 길은 따로 있다.
        if let run = companion.rogueRun {
            return no(request, "이미 웨이브 \(run.wave) 를 도는 중이다. 버리려면 wave forfeit --yes.")
        }
        let pool = RogueRun.starterPool
        let speciesID: Int
        if let starter {
            guard let picked = WaveRunLoader.starter(number: starter) else {
                return no(request, "스타터 번호는 1~\(pool.count) 다 — wave 가 찍는 목록을 본다.")
            }
            speciesID = picked
        } else {
            speciesID = pool.randomElement() ?? pool[0]
        }
        guard await WaveRunLoader.startRun(starter: speciesID, store: companion),
              let run = companion.rogueRun else {
            return no(request, "PokéAPI 에 연결하지 못해 판을 열 수 없다. 잠시 뒤 다시 시도한다.")
        }
        let name = run.party.first?.snapshot.name ?? "#\(speciesID)"
        return ok(request, "웨이브 1 시작 — \(name) 와(과) 나섰다. " + Self.next(run))
    }

    private func waveMove(_ request: PokedoroRequest, move: Int,
                          target: Int?) async -> PokedoroReply {
        guard var run = await currentRun() else { return noRun(request) }
        guard run.stage == .battling else { return no(request, Self.wrongStage(run)) }
        guard run.battle.slotsNeedingSendOut.isEmpty else {
            return no(request, "쓰러진 칸을 먼저 채운다 — wave switch <파티 번호>.")
        }
        guard let slot = run.battle.slotsAwaitingAction.first,
              let side = run.battle.mySide(at: slot) else {
            return no(request, "이번 턴에 행동할 칸이 없다.")
        }
        let index = move - 1
        // 발버둥이면 인덱스와 무관하게 통과한다 — `WaveBattle.choose` 가 그 자리에서 −1 로 접는다.
        guard side.mustStruggle || side.canUse(moveAt: index) else {
            return no(request, "\(move)번 기술을 쓸 수 없다 — wave 가 찍는 번호와 남은 PP 를 본다.")
        }
        let ordinal = (target ?? 1) - 1
        guard run.battle.opponentField.indices.contains(ordinal) else {
            return no(request, "상대 \(target ?? 1)번 칸이 없다 — 지금 서 있는 칸은 "
                      + "\(run.battle.opponentField.count) 개다.")
        }
        let played = run.battle.events.count
        // PP 가 다 떨어졌으면 무엇을 골랐든 발버둥이다(`WaveBattle.choose`) — 고른 기술 이름을
        // 그대로 되뇌면 답과 로그가 서로 다른 기술을 말한다.
        let chosen = side.mustStruggle || !side.moves.indices.contains(index)
            ? MoveSpec.struggle() : side.moves[index]
        run.useMove(index, fromSlot: slot, target: ordinal)
        companion.rogueRun = run
        return await settled(request, since: played,
                             head: "\(chosen.name(companion.language)) 을(를) 골랐다.")
    }

    /// 교체와 기절 보충이 **한 동작**인 이유는 화면의 같은 줄이 두 일을 하기 때문이다
    /// (`RogueRunView.arena` 의 `onSwitch`). 나누면 사용자가 지금 어느 쪽인지 알아야 한다.
    private func waveSwitch(_ request: PokedoroRequest, number: Int) async -> PokedoroReply {
        guard var run = await currentRun() else { return noRun(request) }
        guard run.stage == .battling else { return no(request, Self.wrongStage(run)) }
        let index = number - 1
        guard run.party.indices.contains(index) else {
            return no(request, "\(number)번 포켓몬이 이 판의 파티에 없다 — wave 로 번호를 확인한다.")
        }
        let member = run.party[index]
        // 사유를 갈라 말한다 — "이미 나와 있다" 와 "쓰러졌다" 는 다음에 할 일이 다르다.
        guard member.isAlive else {
            return no(request, "\(member.snapshot.name) 은(는) 쓰러져 있다.")
        }
        guard run.battle.benchCandidates.contains(index) else {
            return no(request, "\(member.snapshot.name) 은(는) 이미 필드에 서 있다.")
        }
        let played = run.battle.events.count
        if let slot = run.battle.slotsNeedingSendOut.first {
            // 기절 보충은 **턴을 쓰지 않는다**(근거는 `WaveBattle.sendOut`).
            run.sendOut(index, toSlot: slot)
            companion.rogueRun = run
            return await settled(request, since: played,
                                 head: "\(member.snapshot.name) 이(가) 빈 칸에 나섰다.")
        }
        guard let slot = run.battle.slotsAwaitingAction.first else {
            return no(request, "이번 턴에 행동할 칸이 없다.")
        }
        run.switchParty(to: index, fromSlot: slot)
        companion.rogueRun = run
        return await settled(request, since: played,
                             head: "\(member.snapshot.name) 으로 교체했다 — 그 칸은 이번 턴에 때리지 못한다.")
    }

    private func waveBall(_ request: PokedoroRequest, target: Int?) async -> PokedoroReply {
        guard var run = await currentRun() else { return noRun(request) }
        guard run.stage == .battling else { return no(request, Self.wrongStage(run)) }
        if let refusal = Self.ballRefusal(run) { return no(request, refusal) }
        let ordinal = (target ?? 1) - 1
        guard let side = run.battle.opponentSide(at: ordinal), side.isAlive else {
            return no(request, "상대 \(target ?? 1)번 칸에 잡을 포켓몬이 없다.")
        }
        let name = side.snapshot.name
        let played = run.battle.events.count
        let caught = run.throwBall(atSlot: ordinal)
        companion.rogueRun = run
        return await settled(request, since: played,
                             head: caught ? "\(name) 을(를) 잡았다!"
                                          : "\(name) 이(가) 볼에서 튀어나왔다 — 그 턴은 때리지 못했다.")
    }

    /// 볼을 못 던지는 사유. `canThrowBall` 은 불리언 하나라 이유를 말할 수 없다 — 뭉뚱그리면
    /// 사용자는 볼이 없는 것과 보스라 안 되는 것을 구분하지 못한다.
    private static func ballRefusal(_ run: RogueRun) -> String? {
        guard run.canThrowBall else {
            if run.balls <= 0 { return "몬스터볼이 없다 — 보상에서 보충한다." }
            if run.party.count >= RogueRun.partyLimit { return "파티가 가득 찼다." }
            if RogueRun.isBoss(wave: run.wave) { return "보스에게는 볼을 던질 수 없다." }
            if !run.battle.slotsNeedingSendOut.isEmpty {
                return "쓰러진 칸을 먼저 채운다 — wave switch <파티 번호>."
            }
            return "지금은 볼을 던질 수 없다."
        }
        return nil
    }

    private func wavePick(_ request: PokedoroRequest, number: Int) async -> PokedoroReply {
        guard var run = await currentRun() else { return noRun(request) }
        guard run.stage == .picking else { return no(request, Self.wrongStage(run)) }
        let index = number - 1
        guard run.offers.indices.contains(index) else {
            return no(request, "\(number)번 보상이 없다 — 지금 \(run.offers.count) 장이 떠 있다.")
        }
        let name = run.offers[index].name(L(companion.language))
        run.pick(run.offers[index])
        companion.rogueRun = run
        return await settled(request, since: .max, head: "\(name) 을(를) 골랐다.")
    }

    private func waveRoute(_ request: PokedoroRequest, route: RunRoute) async -> PokedoroReply {
        guard var run = await currentRun() else { return noRun(request) }
        guard run.stage == .routing else { return no(request, Self.wrongStage(run)) }
        run.take(route)
        companion.rogueRun = run
        // 길을 고르면 그 자리에서 다음 웨이브를 연다. 안 열면 판이 `.loadingWave` 에 서고,
        // 그 국면에는 사용자가 보낼 동작이 없다.
        await WaveRunLoader.openNextWaveIfNeeded(store: companion)
        guard let opened = companion.rogueRun else { return noRun(request) }
        guard opened.stage != .loadingWave else {
            return no(request, "\(route.name(L(companion.language))) 로 정했지만 상대를 받지 못했다 "
                      + "— PokéAPI 에 연결되면 다음 명령에서 이어 연다.")
        }
        return ok(request, "\(route.name(L(companion.language))) 로 웨이브 \(opened.wave) 에 들어섰다. "
                  + Self.next(opened))
    }

    private func waveForfeit(_ request: PokedoroRequest) -> PokedoroReply {
        guard let run = companion.rogueRun else { return noRun(request) }
        // 화면의 항복과 같다 — 판을 버리고 실적에도 적지 않는다(`RogueRunView.onForfeit`).
        companion.rogueRun = nil
        return ok(request, "웨이브 \(run.wave) 에서 판을 버렸다.")
    }

    /// 동작 하나가 끝난 뒤의 답. **무슨 일이 일어났는지와 다음에 할 일을 함께 말한다** —
    /// 한 번 찍고 끝나는 명령은 이 한 줄이 화면의 전부다.
    ///
    /// 보상 화면으로 넘어갔으면 여기서 진화를 돌린다. 화면이 같은 자리에서 도는 것과 맞춘
    /// 것이고(`RogueRunView.evolveParty`), 안 돌리면 터미널로만 돈 판은 영영 진화하지 않는다.
    private func settled(_ request: PokedoroRequest, since played: Int,
                         head: String) async -> PokedoroReply {
        var evolved: [String] = []
        if companion.rogueRun?.stage == .picking {
            evolved = await WaveRunLoader.evolveParty(store: companion)
        }
        var parts = [head]
        if let run = companion.rogueRun {
            parts += WaveRunScreen.log(run, language: companion.language, since: played)
        }
        parts += evolved.map { "\($0) 이(가) 진화했다!" }
        parts.append(Self.next(companion.rogueRun))
        return ok(request, parts.filter { !$0.isEmpty }.joined(separator: " "))
    }

    /// 다음에 할 일 한 조각. 안내 표는 `WaveRunScreen` 하나다 — 여기서 다시 쓰면 화면과 답이
    /// 서로 다른 키를 권한다.
    private static func next(_ run: RogueRun?) -> String { WaveRunScreen.hints(run) }

    private func noRun(_ request: PokedoroRequest) -> PokedoroReply {
        no(request, "진행 중인 웨이브 런이 없다 — wave start 로 연다.")
    }

    /// 지금 국면에서는 할 수 없는 일. **무엇을 기다리는지 말한다** — "할 수 없다" 만 주면
    /// 사용자는 같은 명령을 다시 친다.
    private static func wrongStage(_ run: RogueRun) -> String {
        switch run.stage {
        case .battling:    "지금은 전투 중이다. " + WaveRunScreen.hints(run)
        case .picking:     "먼저 보상을 고른다. " + WaveRunScreen.hints(run)
        case .routing:     "먼저 길을 고른다. " + WaveRunScreen.hints(run)
        case .loadingWave: "다음 상대를 받는 중이다 — 잠시 뒤 다시 시도한다."
        case .cleared:     "이 판은 이미 끝났다(전 웨이브 돌파). wave start 로 새 판을 연다."
        case .failed:      "이 판은 이미 끝났다(전멸). wave start 로 새 판을 연다."
        }
    }

    // MARK: LAN 1대1 대전
    //
    // 무엇을 고를 수 있는지는 `NetBattleScreen` 이, 실제 변경은 `BattleCenter` 의 기존 진입점
    // (`chooseMove`·`switchLAN`·`forfeit`·`declineIncoming`)이 든다. 여기 남는 것은 **번호를
    // 인덱스로 접는 일과 거절 사유를 갈라 말하는 일**뿐이다.

    /// 지금 대전. 창구가 없으면 대전도 없다.
    private var battleState: BattleTerminalState? { battle?.terminalState }

    private func battleMove(_ request: PokedoroRequest, move: Int) -> PokedoroReply {
        guard let control = battle, let state = battleState else { return noBattle(request) }
        // **번호가 목록에 있는지는 화면 표가 판정한다** — 실행기가 따로 세면 안내와 실행이 갈린다.
        guard NetBattleScreen.action(number: move, in: state) == .battleMove(move: move) else {
            return no(request, Self.battleRefusal(state, wanted: .move, number: move))
        }
        control.chooseMove(move - 1)
        return battleDone(request, head: "\(move)번 기술을 냈다.")
    }

    private func battleSwitch(_ request: PokedoroRequest, number: Int) -> PokedoroReply {
        guard let control = battle, let state = battleState else { return noBattle(request) }
        guard NetBattleScreen.action(number: number, in: state) == .battleSwitch(number: number)
        else {
            return no(request, Self.battleRefusal(state, wanted: .sendOut, number: number))
        }
        control.switchLAN(to: number - 1)
        return battleDone(request, head: "\(number)번으로 교체했다.")
    }

    /// 항복. **되돌릴 수 없다** — 확인은 명령 쪽(`--yes`)에서 이미 받았다.
    private func battleForfeit(_ request: PokedoroRequest) -> PokedoroReply {
        guard let control = battle, let state = battleState,
              NetBattleScreen.kind(state) != .none else { return noBattle(request) }
        control.forfeit()
        return ok(request, "항복했다 — 이 판은 졌다.")
    }

    private func battleDecline(_ request: PokedoroRequest) -> PokedoroReply {
        guard let control = battle, let state = battleState else { return noBattle(request) }
        // 거절할 신청이 없는데 성공으로 답하면 사용자는 치웠다고 믿고 앱을 안 열어 본다.
        guard NetBattleScreen.kind(state) == .incoming else {
            return no(request, "거절할 대전 신청이 없다.")
        }
        control.declineIncoming()
        return ok(request, "대전 신청을 거절했다.")
    }

    /// 낸 뒤의 답. **바뀐 판을 되읽어서** 다음에 할 일을 말한다 — 내 클램프 결과를 echo 하면
    /// 앱이 그 입력을 거절한 날에도 성공으로 보고한다(별명 되읽기와 같은 규칙).
    private func battleDone(_ request: PokedoroRequest, head: String) -> PokedoroReply {
        let after = battleState
        return ok(request, head + " " + (after.map(NetBattleScreen.hints) ?? ""))
    }

    /// 지금 고를 수 없는 번호의 사유. **무엇을 기다리는지 말한다** — 뭉뚱그리면 사용자는 같은
    /// 번호를 다시 낸다.
    private static func battleRefusal(_ state: BattleTerminalState,
                                      wanted: NetBattleScreen.Kind, number: Int) -> String {
        let kind = NetBattleScreen.kind(state)
        guard kind == wanted else {
            switch kind {
            case .none:     return "진행 중인 대전이 없다."
            case .waiting:  return "이번 턴은 이미 냈다 — 상대의 행동을 기다린다."
            case .sendOut:  return "쓰러진 자리를 먼저 메운다 — battle switch <번호>."
            case .move:     return "지금은 기술을 고를 차례다 — battle move <n>."
            case .incoming: return "받은 신청을 먼저 처리한다 — battle decline 또는 앱에서 수락."
            case .appOnly:  return "앱에서 이어 한다 — 파티 편성은 터미널에 입력 줄이 없다."
            case .finished: return "대전이 끝났다."
            }
        }
        return "\(number)번은 지금 고를 수 없다 — \(NetBattleScreen.hints(state))"
    }

    private func noBattle(_ request: PokedoroRequest) -> PokedoroReply {
        no(request, "진행 중인 대전이 없다 — 신청은 앱의 친구 탭에서 한다.")
    }

    // MARK: LAN 방
    //
    // 대전과 같은 모양이다. 다른 점 하나는 **대상**이다: 센터는 UUID 로 받고 사용자는 번호를
    // 치므로, 그 변환을 여기서 `RoomScreen.targetID` 한 곳으로 지난다.

    private var roomState: RoomTerminalState? { room?.terminalState }

    private func roomMove(_ request: PokedoroRequest, move: Int, target: Int?) -> PokedoroReply {
        guard let control = room, let state = roomState else { return noRoom(request) }
        guard RoomScreen.kind(state) == .move else {
            return no(request, Self.roomRefusal(state))
        }
        guard RoomScreen.numbers(state).contains(move) else {
            return no(request, "\(move)번 기술을 쓸 수 없다 — room 이 찍는 번호와 남은 PP 를 본다.")
        }
        // 대상을 안 적으면 첫 상대다. 협동 레이드는 보스 하나라 대개 그것으로 끝난다.
        let wanted = target ?? 1
        guard let targetID = RoomScreen.targetID(number: wanted, in: state) else {
            return no(request, "\(wanted)번 상대가 없다 — 지금 "
                      + "\(RoomScreen.targets(state).count) 명이 서 있다.")
        }
        control.submitAction(targetID: targetID, moveIndex: move - 1)
        return ok(request, "\(move)번 기술을 냈다. " + RoomScreen.hints(roomState ?? state))
    }

    private func roomStart(_ request: PokedoroRequest) -> PokedoroReply {
        guard let control = room, let state = roomState else { return noRoom(request) }
        // 사유를 갈라 말한다 — 호스트가 아닌 것과 사람이 덜 모인 것은 다음에 할 일이 다르다.
        guard state.isHost else { return no(request, "호스트만 시작할 수 있다.") }
        guard RoomScreen.kind(state) == .lobby else {
            return no(request, "지금은 시작할 수 있는 상태가 아니다 — " + RoomScreen.hints(state))
        }
        guard state.canStart else { return no(request, "사람이 더 모여야 시작할 수 있다.") }
        control.startRaid()
        return ok(request, "판을 시작했다.")
    }

    /// 방 나가기. **되돌릴 수 없다** — 확인은 명령 쪽(`--yes`)에서 이미 받았다.
    private func roomLeave(_ request: PokedoroRequest) -> PokedoroReply {
        guard let control = room, let state = roomState,
              RoomScreen.kind(state) != .none else { return noRoom(request) }
        control.leaveRoom()
        return ok(request, "방에서 나왔다.")
    }

    private static func roomRefusal(_ state: RoomTerminalState) -> String {
        switch RoomScreen.kind(state) {
        case .none:     "방에 없다."
        case .lobby:    "판이 아직 시작되지 않았다 — " + RoomScreen.hints(state)
        case .waiting:  "이번 라운드는 이미 냈거나 행동할 수 없다 — " + RoomScreen.hints(state)
        case .finished: "판이 끝났다."
        case .move:     RoomScreen.hints(state)
        }
    }

    private func noRoom(_ request: PokedoroRequest) -> PokedoroReply {
        no(request, "방에 없다 — 방을 만들거나 찾는 일은 앱에서 한다.")
    }

    // MARK: 교환
    //
    // 번호가 두 종류라 **접는 자리도 둘**이다: 내 개체는 창구가 `party` 번호로 받고(사유까지
    // 돌려준다), 상대 목록은 `TradeScreen.remoteID` 가 id 로 접는다.

    private var tradeState: TradeTerminalState? { trade?.terminalState }

    private func tradeAnswer(_ request: PokedoroRequest, accept: Bool) -> PokedoroReply {
        guard let control = trade, let state = tradeState else { return noTrade(request) }
        guard TradeScreen.kind(state) == .incoming else {
            return no(request, "답할 교환 신청이 없다 — " + TradeScreen.hints(state))
        }
        if accept {
            control.accept()
            return ok(request, "교환 신청을 수락했다. " + TradeScreen.hints(tradeState ?? state))
        }
        control.decline()
        return ok(request, "교환 신청을 거절했다.")
    }

    private func tradeOffer(_ request: PokedoroRequest, number: Int) -> PokedoroReply {
        guard let control = trade, let state = tradeState else { return noTrade(request) }
        guard TradeScreen.kind(state) == .negotiating else {
            return no(request, "지금은 개체를 낼 수 없다 — " + TradeScreen.hints(state))
        }
        // 사유는 **창구가** 만든다(체육관 방어·즐겨찾기·없는 번호) — 로스터를 아는 쪽이다.
        if let refusal = control.offerMon(number: number) { return no(request, refusal) }
        // 낸 것을 **되읽어서** 말한다. 내가 접은 값을 echo 하면 세이브 경계가 달라진 날 답과
        // 실제가 갈라진다(별명 되읽기와 같은 규칙).
        let applied = tradeState?.localOffer ?? "\(number)번"
        return ok(request, "\(applied)을 냈다. " + TradeScreen.hints(tradeState ?? state))
    }

    private func tradeWant(_ request: PokedoroRequest, number: Int) -> PokedoroReply {
        guard let control = trade, let state = tradeState else { return noTrade(request) }
        guard TradeScreen.kind(state) == .negotiating else {
            return no(request, "지금은 지목할 수 없다 — " + TradeScreen.hints(state))
        }
        guard let id = TradeScreen.remoteID(number: number, in: state) else {
            return no(request, "\(number)번은 상대 목록에 없다 — 지금 "
                      + "\(state.theirRoster.count) 마리가 올라 있다.")
        }
        control.wantRemote(id: id)
        let label = state.theirRoster.first { $0.number == number }?.label ?? "\(number)번"
        return ok(request, "\(label)을 원한다고 알렸다.")
    }

    /// 성사. **되돌릴 수 없다** — 확인은 명령 쪽(`--yes`)에서 이미 받았다.
    private func tradeConfirm(_ request: PokedoroRequest) -> PokedoroReply {
        guard let control = trade, let state = tradeState else { return noTrade(request) }
        guard TradeScreen.kind(state) == .negotiating else {
            return no(request, "지금은 성사시킬 수 없다 — " + TradeScreen.hints(state))
        }
        // 양쪽이 다 내지 않았으면 확인해도 아무 일이 없다 — 성공으로 답하면 사용자는 끝난 줄 안다.
        guard state.localOffer != nil, state.remoteOffer != nil else {
            return no(request, "양쪽이 다 내야 성사시킬 수 있다 — " + TradeScreen.hints(state))
        }
        control.confirm()
        return ok(request, "확인했다. " + TradeScreen.hints(tradeState ?? state))
    }

    private func tradeCancel(_ request: PokedoroRequest) -> PokedoroReply {
        guard let control = trade, let state = tradeState,
              TradeScreen.kind(state) != .none else { return noTrade(request) }
        control.cancel()
        return ok(request, "교환을 취소했다.")
    }

    private func noTrade(_ request: PokedoroRequest) -> PokedoroReply {
        no(request, "진행 중인 교환이 없다 — 상대를 찾는 일은 앱에서 한다.")
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
