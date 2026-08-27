import Foundation
import Network
import UserNotifications

// MARK: - 프로토콜

/// 피어 간 대전 메시지. 와이어 포맷 = 4바이트 길이(big-endian) + JSON.
/// 턴 결과는 보내지 않는다 — 양쪽이 (스냅샷, seed, 기술 선택)만 교환하고 각자 같은 결정적
/// 엔진으로 해상한다. 결과 필드가 없으니 결과 변조도 없다.
/// 1:1 LAN 대전은 맞짱(턴제 기술 대전) 하나다. 여러 명이 달리는 레이스는 포켓애슬론
/// (`MultiplayerRoomCenter` + `PokeathlonRace`)이 담당한다 — 호스트가 판정하는 방식.
enum NetBattleAction: Codable, Sendable, Equatable {
    case move(index: Int)              // -1 = 발버둥(PP 소진)
    case metronome(move: MoveSpec)     // 손가락흔들기로 실제 발동할 기술 전체를 피어와 공유
    case switchTo(index: Int)
}

enum NetBattleKind: String, Codable, Sendable {
    case regular
    case metronome
}

/// 신청 취소 사유는 연결 단절과 구분한다. 특히 시간 초과는 양쪽에 같은 설명을 보여야 한다.
enum BattleChallengeCancellationReason: String, Codable, Sendable, Equatable {
    case cancelled
    case timedOut
}

enum NetMessage: Codable, Sendable {
    /// 2단계 신청: 이 메시지에는 포켓몬 스냅샷이 없다. 수락 뒤 양쪽이 `teamReady`를 보내야 시작한다.
    case request(trainer: String, teamSize: Int, seed: UInt64, profile: BattleRankProfile,
                 rulesVersion: Int?, chatSupported: Bool?, kind: NetBattleKind?)
    case approve
    case teamReady(snapshot: BattleSnapshot, lineup: [BattleSnapshot], teamSize: Int,
                   profile: BattleRankProfile, rulesVersion: Int?, chatSupported: Bool?)
    /// `rulesVersion` 은 대전 규칙(턴 순서·데미지 계산)의 버전이다. 이 대전은 결과를 주고받지 않고
    /// **두 피어가 각자 계산**하므로, 규칙이 다르면 같은 배틀을 서로 다르게 본다(HP·승패가 어긋난다).
    /// 옵셔널인 이유는 이 필드가 없던 버전이 보낸 메시지도 읽어서 "구버전이라 못 붙는다"고
    /// 알려주기 위해서다 — 필수 필드로 두면 디코딩이 실패해 아무 설명 없이 조용히 무시된다.
    case challenge(snapshot: BattleSnapshot, lineup: [BattleSnapshot], teamSize: Int,
                   seed: UInt64, profile: BattleRankProfile, rulesVersion: Int?, chatSupported: Bool?)
    case accept(snapshot: BattleSnapshot, lineup: [BattleSnapshot], teamSize: Int,
                profile: BattleRankProfile, rulesVersion: Int?, chatSupported: Bool?)
    case decline
    case challengeCancelled(reason: BattleChallengeCancellationReason)
    case action(turn: Int, action: NetBattleAction)
    /// 구버전 와이어 메시지를 디코딩해 규칙 불일치 경로까지 보낼 때만 남긴다. 새 클라이언트는 전송하지 않는다.
    case move(turn: Int, moveIndex: Int)
    case forfeit
    case chat(BattleChatMessage)

    private enum CodingKeys: String, CodingKey { case request, approve, teamReady, challenge, accept, decline, challengeCancelled, action, move, forfeit, chat }
    private struct EmptyPayload: Codable {}
    private struct RequestPayload: Codable {
        var trainer: String; var teamSize: Int; var seed: UInt64; var profile: BattleRankProfile
        var rulesVersion: Int?; var chatSupported: Bool?; var kind: NetBattleKind?
    }
    private struct ChallengePayload: Codable {
        var snapshot: BattleSnapshot
        var lineup: [BattleSnapshot]?
        var teamSize: Int?
        var seed: UInt64
        var profile: BattleRankProfile
        var rulesVersion: Int?
        var chatSupported: Bool?
    }
    private struct AcceptPayload: Codable {
        var snapshot: BattleSnapshot
        var lineup: [BattleSnapshot]?
        var teamSize: Int?
        var profile: BattleRankProfile
        var rulesVersion: Int?
        var chatSupported: Bool?
    }
    private struct ActionPayload: Codable { var turn: Int; var action: NetBattleAction }
    private struct MovePayload: Codable { var turn: Int; var moveIndex: Int }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.request) {
            let p = try container.decode(RequestPayload.self, forKey: .request)
            self = .request(trainer: p.trainer, teamSize: p.teamSize, seed: p.seed, profile: p.profile,
                            rulesVersion: p.rulesVersion, chatSupported: p.chatSupported, kind: p.kind)
        } else if container.contains(.approve) {
            self = .approve
        } else if container.contains(.teamReady) {
            let p = try container.decode(AcceptPayload.self, forKey: .teamReady)
            self = .teamReady(snapshot: p.snapshot, lineup: p.lineup ?? [p.snapshot], teamSize: p.teamSize ?? 1,
                              profile: p.profile, rulesVersion: p.rulesVersion, chatSupported: p.chatSupported)
        } else if container.contains(.challenge) {
            let payload = try container.decode(ChallengePayload.self, forKey: .challenge)
            self = .challenge(snapshot: payload.snapshot,
                              lineup: payload.lineup ?? [payload.snapshot],
                              teamSize: payload.teamSize ?? 1,
                              seed: payload.seed, profile: payload.profile,
                              rulesVersion: payload.rulesVersion, chatSupported: payload.chatSupported)
        } else if container.contains(.accept) {
            let payload = try container.decode(AcceptPayload.self, forKey: .accept)
            self = .accept(snapshot: payload.snapshot,
                           lineup: payload.lineup ?? [payload.snapshot],
                           teamSize: payload.teamSize ?? 1,
                           profile: payload.profile, rulesVersion: payload.rulesVersion,
                           chatSupported: payload.chatSupported)
        } else if container.contains(.decline) {
            self = .decline
        } else if container.contains(.challengeCancelled) {
            self = .challengeCancelled(reason: try container.decode(BattleChallengeCancellationReason.self,
                                                                    forKey: .challengeCancelled))
        } else if container.contains(.action) {
            let payload = try container.decode(ActionPayload.self, forKey: .action)
            self = .action(turn: payload.turn, action: payload.action)
        } else if container.contains(.move) {
            let payload = try container.decode(MovePayload.self, forKey: .move)
            self = .move(turn: payload.turn, moveIndex: payload.moveIndex)
        } else if container.contains(.forfeit) {
            self = .forfeit
        } else if container.contains(.chat) {
            self = .chat(try container.decode(BattleChatMessage.self, forKey: .chat))
        } else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                    debugDescription: "Unknown battle message"))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .request(let trainer, let teamSize, let seed, let profile, let rulesVersion, let chatSupported, let kind):
            try container.encode(RequestPayload(trainer: trainer, teamSize: teamSize, seed: seed, profile: profile,
                                                rulesVersion: rulesVersion, chatSupported: chatSupported, kind: kind), forKey: .request)
        case .approve:
            try container.encode(EmptyPayload(), forKey: .approve)
        case .teamReady(let snapshot, let lineup, let teamSize, let profile, let rulesVersion, let chatSupported):
            try container.encode(AcceptPayload(snapshot: snapshot, lineup: lineup, teamSize: teamSize,
                                               profile: profile, rulesVersion: rulesVersion, chatSupported: chatSupported),
                                 forKey: .teamReady)
        case .challenge(let snapshot, let lineup, let teamSize, let seed, let profile, let rulesVersion, let chatSupported):
            try container.encode(ChallengePayload(snapshot: snapshot, lineup: lineup, teamSize: teamSize,
                                                  seed: seed, profile: profile, rulesVersion: rulesVersion, chatSupported: chatSupported),
                                 forKey: .challenge)
        case .accept(let snapshot, let lineup, let teamSize, let profile, let rulesVersion, let chatSupported):
            try container.encode(AcceptPayload(snapshot: snapshot, lineup: lineup, teamSize: teamSize,
                                               profile: profile, rulesVersion: rulesVersion, chatSupported: chatSupported),
                                 forKey: .accept)
        case .decline:
            try container.encode(EmptyPayload(), forKey: .decline)
        case .challengeCancelled(let reason):
            try container.encode(reason, forKey: .challengeCancelled)
        case .action(let turn, let action):
            try container.encode(ActionPayload(turn: turn, action: action), forKey: .action)
        case .move(let turn, let moveIndex):
            try container.encode(MovePayload(turn: turn, moveIndex: moveIndex), forKey: .move)
        case .forfeit:
            try container.encode(EmptyPayload(), forKey: .forfeit)
        case .chat(let message):
            try container.encode(message, forKey: .chat)
        }
    }
}

/// 신청 마감 작업의 작은 취소 핸들. 실제 시간 대신 테스트 스케줄러를 주입할 수 있다.
@MainActor
final class BattleChallengeTimeout {
    private let cancellation: () -> Void
    init(cancellation: @escaping () -> Void) { self.cancellation = cancellation }
    func cancel() { cancellation() }
}

@MainActor
protocol BattleChallengeTimeoutScheduling: AnyObject {
    func schedule(_ action: @escaping @MainActor () -> Void) -> BattleChallengeTimeout
}

@MainActor
private final class SystemBattleChallengeTimeoutScheduler: BattleChallengeTimeoutScheduling {
    func schedule(_ action: @escaping @MainActor () -> Void) -> BattleChallengeTimeout {
        let task = Task { @MainActor in
            try? await Task.sleep(for: .seconds(BattleCenter.challengeDuration))
            guard !Task.isCancelled else { return }
            action()
        }
        return BattleChallengeTimeout { task.cancel() }
    }
}

/// 발견된 대전 상대.
struct BattlePeer: Identifiable, Equatable {
    let name: String            // 표시 이름(고유 접미 제거)
    let serviceName: String     // Bonjour 광고 원본(고유) — id·self 판정용
    let endpoint: NWEndpoint
    /// 상대가 광고한 표시용 진행도. 쓰임과 한계는 `PeerAdvertisement` 에 적어 뒀다.
    let advertisement: PeerAdvertisement
    /// 광고 안의 랭크. 기존 호출부를 살려 두는 어댑터.
    var rank: BattleRank? { advertisement.rank }
    var id: String { serviceName }
    /// 광고까지 비교한다. 신원은 `id`(=`serviceName`)가 맡는다. 이름만 비교하면 상대가 레벨을
    /// 올려도 같은 값이 되어, 동등성으로 갱신을 판단하는 쪽(SwiftUI 뷰 비교·`onChange`)이 실시간
    /// 갱신을 삼킨다.
    static func == (l: Self, r: Self) -> Bool {
        l.serviceName == r.serviceName && l.advertisement == r.advertisement
    }
}

/// 한 턴의 이벤트가 가리키는 실제 전투원 문맥. `.a`/`.b` 만으로는 교체 뒤 과거 이름·기술을
/// 복원할 수 없으므로, 이벤트가 생긴 시점의 활성 포켓몬 정보를 함께 보존한다.
struct NetBattleLogCombatant: Sendable, Equatable {
    let name: String
    let moves: [MoveSpec]

    init(_ side: BattleSide, calledMoves: [MoveSpec] = []) {
        name = side.snapshot.name
        // 손가락흔들기로 호출된 기술은 대여 토게키스의 정규 기술 목록에는 없다. 이벤트에는 실제
        // 기술 ID가 남으므로, 재생/로그가 이를 발버둥으로 오인하지 않도록 턴 문맥에도 함께 보존한다.
        moves = side.moves + calledMoves.filter { called in
            !side.moves.contains(where: { $0.id == called.id })
        }
    }
}

struct NetBattleEventBatch: Sendable, Equatable {
    let events: [BattleEvent]
    let a: NetBattleLogCombatant
    let b: NetBattleLogCombatant

    init(events: [BattleEvent], a: BattleSide, b: BattleSide,
         calledMovesA: [MoveSpec] = [], calledMovesB: [MoveSpec] = []) {
        self.events = events
        self.a = NetBattleLogCombatant(a, calledMoves: calledMovesA)
        self.b = NetBattleLogCombatant(b, calledMoves: calledMovesB)
    }
}

/// 진행 중 대전 상태(뷰 렌더 소스).
struct NetBattleState {
    var iAmA: Bool                      // challenger = A (엔진 좌변)
    var myTeam: [BattleSide]
    var oppTeam: [BattleSide]
    var myActive = 0
    var oppActive = 0
    var rng: SplitMix64
    var turn = 1
    var myAction: NetBattleAction?
    var oppAction: NetBattleAction?
    var events: [BattleEvent] = []
    var eventBatches: [NetBattleEventBatch] = []
    var isMetronome = false

    var me: BattleSide {
        get { myTeam[myActive] }
        set { myTeam[myActive] = newValue }
    }
    var opp: BattleSide {
        get { oppTeam[oppActive] }
        set { oppTeam[oppActive] = newValue }
    }

    /// 내가 고를 수 있는 기술이 하나도 없으면 발버둥.
    var mustStruggle: Bool { me.mustStruggle }

    func canChoose(_ action: NetBattleAction, mine: Bool) -> Bool {
        let team = mine ? myTeam : oppTeam
        let active = mine ? myActive : oppActive
        guard team.indices.contains(active), team[active].isAlive else { return false }
        switch action {
        case .move(let index):
            return index == -1 ? team[active].mustStruggle : team[active].canUse(moveAt: index)
        case .metronome(let move):
            return isMetronome && team[active].canUse(moveAt: 0)
                && move.id != 118 && move.id != 165 && MultiplayerValidation.validMoves([move])
        case .switchTo(let index):
            return team.indices.contains(index) && index != active && team[index].isAlive
        }
    }

    /// 양쪽 행동을 challenger=A 기준으로 해상한다. 반환값은 내 관점의 승/패/무다.
    @discardableResult
    mutating func resolveChosenActions() -> BattleOutcome? {
        guard let myAction, let oppAction else { return nil }
        var teamA = iAmA ? myTeam : oppTeam
        var teamB = iAmA ? oppTeam : myTeam
        var activeA = iAmA ? myActive : oppActive
        var activeB = iAmA ? oppActive : myActive
        let rawActionA = iAmA ? myAction : oppAction
        let rawActionB = iAmA ? oppAction : myAction
        let overrideA: MoveSpec? = { if case .metronome(let move) = rawActionA { return move }; return nil }()
        let overrideB: MoveSpec? = { if case .metronome(let move) = rawActionB { return move }; return nil }()
        let actionA: NetBattleAction = overrideA == nil ? rawActionA : .move(index: 0)
        let actionB: NetBattleAction = overrideB == nil ? rawActionB : .move(index: 0)
        var turnEvents: [BattleEvent] = []

        func switchSlot(_ index: Int, team: inout [BattleSide], active: inout Int) {
            BattleEngine.prepareForSwitch(&team[active])
            active = index
        }
        func spendPP(_ index: Int, override: MoveSpec?, team: inout [BattleSide], active: Int) -> MoveSpec {
            let move = override ?? team[active].move(at: index)
            if team[active].pp.indices.contains(index) {
                team[active].pp[index] = max(0, team[active].pp[index] - 1)
            }
            return move
        }
        func finishTurn(_ a: inout BattleSide, _ b: inout BattleSide,
                        events: inout [BattleEvent]) {
            events += BattleEngine.endOfTurnResidual(&a, actor: .a)
            events += BattleEngine.endOfTurnResidual(&b, actor: .b)
        }

        switch (actionA, actionB) {
        case (.move(let indexA), .move(let indexB)):
            let moveA = spendPP(indexA, override: overrideA, team: &teamA, active: activeA)
            let moveB = spendPP(indexB, override: overrideB, team: &teamB, active: activeB)
            var a = teamA[activeA], b = teamB[activeB]
            turnEvents = BattleEngine.resolveTurn(a: &a, b: &b, moveA: moveA, moveB: moveB,
                                                  turn: turn, rng: &rng)
            teamA[activeA] = a; teamB[activeB] = b
        case (.switchTo(let indexA), .move(let indexB)):
            switchSlot(indexA, team: &teamA, active: &activeA)
            let moveB = spendPP(indexB, override: overrideB, team: &teamB, active: activeB)
            var a = teamA[activeA], b = teamB[activeB]
            BattleEngine.beginTurn(&a); BattleEngine.beginTurn(&b)
            // 출전은 상대 공격보다 **앞**이다 — 재생기가 이 순서대로 개체를 갈아타야 새로 나온
            // 개체가 맞는 그림이 된다(뒤에 두면 이전 개체가 남의 데미지를 맞는다).
            turnEvents = [.turn(turn), .sendOut(.a, teamIndex: indexA)]
            if a.isAlive && b.isAlive {
                turnEvents += BattleEngine.applyAttack(attacker: &b, defender: &a,
                                                       attackerActor: .b, defenderActor: .a,
                                                       move: moveB, rng: &rng)
            }
            finishTurn(&a, &b, events: &turnEvents)
            teamA[activeA] = a; teamB[activeB] = b
        case (.move(let indexA), .switchTo(let indexB)):
            switchSlot(indexB, team: &teamB, active: &activeB)
            let moveA = spendPP(indexA, override: overrideA, team: &teamA, active: activeA)
            var a = teamA[activeA], b = teamB[activeB]
            BattleEngine.beginTurn(&a); BattleEngine.beginTurn(&b)
            turnEvents = [.turn(turn), .sendOut(.b, teamIndex: indexB)]
            if a.isAlive && b.isAlive {
                turnEvents += BattleEngine.applyAttack(attacker: &a, defender: &b,
                                                       attackerActor: .a, defenderActor: .b,
                                                       move: moveA, rng: &rng)
            }
            finishTurn(&a, &b, events: &turnEvents)
            teamA[activeA] = a; teamB[activeB] = b
        case (.switchTo(let indexA), .switchTo(let indexB)):
            switchSlot(indexA, team: &teamA, active: &activeA)
            switchSlot(indexB, team: &teamB, active: &activeB)
            var a = teamA[activeA], b = teamB[activeB]
            // 공격이 없는 턴도 턴이다. 여기만 `beginTurn` 을 빼면 volatile(맞은 기록·풀죽음)이
            // 한 턴을 건너뛰고 살아남는다 — 네 갈래가 같은 규칙을 써야 한다.
            BattleEngine.beginTurn(&a); BattleEngine.beginTurn(&b)
            turnEvents = [.turn(turn),
                          .sendOut(.a, teamIndex: indexA), .sendOut(.b, teamIndex: indexB)]
            finishTurn(&a, &b, events: &turnEvents)
            teamA[activeA] = a; teamB[activeB] = b
        case (.metronome, _), (_, .metronome):
            // 위에서 실제 기술을 보존한 `.move(0)`으로 정규화하므로 도달하지 않는다.
            return nil
        }

        // 자동 출전으로 active index를 바꾸기 전에 이번 이벤트의 실제 이름·기술 문맥을 고정한다.
        let contextA = teamA[activeA], contextB = teamB[activeB]
        let aWiped = !teamA.contains(where: \.isAlive)
        let bWiped = !teamB.contains(where: \.isAlive)
        // 자동 출전도 스트림에 남는다 — 재생기가 이 이벤트를 보고서야 표시 상태를 새 개체로
        // 갈아탄다. 없으면 기절 턴에 새로 나온 만피 개체를 이전 개체의 HP 로 깎아 그린다.
        if !aWiped, !teamA[activeA].isAlive,
           let next = teamA.indices.first(where: { teamA[$0].isAlive }) {
            activeA = next
            turnEvents.append(.sendOut(.a, teamIndex: next))
        }
        if !bWiped, !teamB[activeB].isAlive,
           let next = teamB.indices.first(where: { teamB[$0].isAlive }) {
            activeB = next
            turnEvents.append(.sendOut(.b, teamIndex: next))
        }
        // 배치는 **자동 출전 이벤트까지 담은 뒤** 만든다 — 배치 이벤트 수가 평평한 `events` 와
        // 어긋나면 `BattleLogSource.netBattle` 의 진행도 자르기가 그만큼 밀린다.
        let eventBatch = NetBattleEventBatch(events: turnEvents, a: contextA, b: contextB,
                                              calledMovesA: overrideA.map { [$0] } ?? [],
                                              calledMovesB: overrideB.map { [$0] } ?? [])

        self.myTeam = iAmA ? teamA : teamB
        self.oppTeam = iAmA ? teamB : teamA
        self.myActive = iAmA ? activeA : activeB
        self.oppActive = iAmA ? activeB : activeA
        events.append(contentsOf: turnEvents)
        eventBatches.append(eventBatch)
        turn += 1
        self.myAction = nil
        self.oppAction = nil

        guard aWiped || bWiped else { return nil }
        if aWiped && bWiped { return .draw }
        let aWon = !aWiped
        return (iAmA == aWon) ? .win : .loss
    }
}

// MARK: - BattleCenter

/// LAN 대전 허브 — Bonjour 광고/탐색, 신청/수락, 턴 교환까지 전 상태를 들고 있는 단일 소스.
/// 앱 기동 시 start() — 팝오버가 닫혀 있어도 신청을 받아 알림을 쏠 수 있어야 한다.
@MainActor
@Observable
final class BattleCenter {
    typealias MonSnapshotBuilder = @MainActor (MonState, Int) async -> BattleSnapshot?
    typealias BattleProfileLoader = @MainActor (Int) async -> PokemonBattleProfile?
    typealias MoveSetLoader = @MainActor (Int, Int, [PokemonType]) async -> [MoveSpec]
    typealias MoveDetailLoader = @MainActor (String) async -> MoveSpec?
    typealias InheritedMovesPreparer = @MainActor () async -> Void

    nonisolated static let serviceType = "_ptbbattle._tcp"
    private nonisolated static let maxMessageBytes: UInt32 = 1_000_000

    enum Phase: Equatable {
        case ready                          // 대기(광고/탐색 중)
        case preparing                      // 내 스냅샷·무브셋 로딩
        case challenging(peer: String)      // 신청 보냄
        case incoming(peer: String)         // 신청 받음
        case teamBuilding(peer: String)     // 수락 후 양쪽 파티 편성
        case waitingTeam(peer: String)      // 내 확인 완료, 상대 확인 대기
        case battling
        case finished(iWon: Bool?, byForfeit: Bool)
    }

    var phase: Phase = .ready {
        // 국면이 바뀌면 미뤄 둔 결과는 무효다 — 항복·끊김·새 배틀이 국면을 먼저 옮긴 뒤에 옛 배틀의
        // 마감이 뒤늦게 깨어나 엉뚱한 결과 화면을 올리는 것을 막는다.
        didSet {
            dropPendingFinish()
            // `.ready` 는 어떤 경로로 돌아왔든 세션 경계다. 신청 취소·거절·연결 실패처럼 배틀을
            // 시작하지 못한 경우까지 한 곳에서 비워야, 다음 상대에게 이전 대화나 지원 여부가 남지 않는다.
            if case .ready = phase { endChatSession() }
        }
    }
    /// 승부는 났지만 재생이 아직 안 끝나 미뤄 둔 결과. **`phase` 를 바로 넘기지 않는 이유**는
    /// 이벤트 append 와 `phase = .finished` 가 같은 동기 블록이면 SwiftUI 가 한 번만 다시 그려
    /// 결정타·기절이 재생을 한 프레임도 못 본 채 결과 화면으로 스냅하기 때문이다 — 재생기가 생긴
    /// 이유가 바로 그 턴이다.
    private(set) var pendingFinish: (iWon: Bool?, byForfeit: Bool)?
    /// 재생기가 아무 말도 없을 때의 안전망. 팝오버가 닫혀 있으면 `onCaughtUp` 을 부를 뷰가 없어
    /// 배틀이 `.battling` 에 갇힌다. 한 배치의 재생은 `BattleReplay.budget` 을 넘길 수 없으므로
    /// 그보다 넉넉한 한 번의 마감으로 충분하다.
    private var finishDeadline: Task<Void, Never>?
    private(set) var peers: [BattlePeer] = []
    /// 수동(IP) 연결용 — 사내망 등 mDNS 멀티캐스트가 막힌 네트워크에선 자동 탐색이 안 되므로
    /// 이 주소를 상대에게 알려주고 직접 연결받는다.
    private(set) var listeningPort: UInt16?
    private(set) var battle: NetBattleState?
    private(set) var incomingSnapshot: BattleSnapshot?   // 수락 화면에서 상대 미리보기
    private(set) var incomingLineup: [BattleSnapshot] = []
    private(set) var incomingTeamSize = 1
    /// 수락 화면 전용 초안. 수락 전에는 공용 `pickedTeam` 을 건드리지 않는다.
    var incomingPickedTeam: [UUID] = []
    private(set) var opponentRankProfile: BattleRankProfile?
    private(set) var rankedStake = 0
    private(set) var lastRankDelta = 0
    private(set) var lastError: String?
    private(set) var chatMessages: [BattleChatMessage] = []
    /// 채팅 입력이 열려 있나. 연결이 닫히면 닫힌다.
    private(set) var chatIsAvailable = false
    /// 상대 빌드가 채팅을 지원하나 — **핸드셰이크가 정하는 사실**이라 연결 정리가 지우지 않는다.
    /// 이 사실을 `chatIsAvailable` 하나에 겹쳐 담았던 탓에, 배틀이 끝나며 소켓이 닫힌 것을
    /// "상대 앱 버전이 채팅을 지원하지 않는다"고 말했다. 두 사실은 문구가 다르므로 따로 든다.
    private(set) var peerSupportsChat = false
    private var chatHistory = BattleChatHistory()
    private var chatRateLimiter = BattleChatRateLimiter()
    let chatSenderID = UUID()
    /// 팝오버를 열 때 친구 탭으로 데려가라는 신호. **한 번 쓰면 꺼진다**(`consumePendingAttention`).
    ///
    /// 직접 끄지 말 것. 예전엔 `BattleView.onAppear` 가 껐는데, 친구 탭에 관문(`FriendView`)이
    /// 생기면서 그 화면은 **배틀이 진행 중일 때만** 그려지게 됐다. 배틀이 끝나 `phase == .ready` 가
    /// 되면 관문이 선택 화면을 그리므로 신호를 끌 화면이 영영 안 뜨고, 팝오버를 열 때마다 친구
    /// 탭으로 튀었다(체육관 한 판만 해도 그 뒤로 계속).
    private(set) var pendingAttention = false

    /// 신호를 **소비한다** — 켜져 있었으면 끄고 true. 끄는 일과 읽는 일을 한 호출로 묶어,
    /// 신호를 읽고 끄지 않는 경로가 생기지 않게 한다.
    @discardableResult
    func consumePendingAttention() -> Bool {
        guard pendingAttention else { return false }
        pendingAttention = false
        return true
    }

    #if DEBUG
    /// 테스트 전용 — 신호를 세운다. 실제로는 배틀 시작·신청 수신이 세우는데, 그 경로는 네트워크와
    /// 파티 편성을 지나므로 이 한 축만 보려면 여기로 들어온다.
    func debugRaisePendingAttention() { pendingAttention = true }
    #endif
    /// 배틀이 잡히거나 걸릴 때 창을 자동으로 열고 고정하게 하는 신호(AppDelegate 가 관찰).
    /// 배틀 관련 phase 면 true — 창을 띄우고 닫히지 않게 유지한다.
    var wantsPinnedWindow: Bool {
        // 받은 신청은 화면을 자동으로 열지 않는다. 옆 사람이 모니터를 보고 있어도 신청자와
        // 게임 내용이 노출되지 않고, 사용자가 일반 알림을 눌렀을 때만 상세 화면을 연다.
        if case .incoming = trading.phase { return false }
        if trading.phase != .ready { return true }
        switch phase {
        case .ready, .incoming: return false
        default: return true
        }
    }

    /// 한 턴에 주는 시간 — 멀티와 같은 값이다.
    static let turnDuration: TimeInterval = MultiplayerRoomCenter.turnDuration

    /// 대결 신청은 양쪽 모두 받은 시점부터 60초 안에 수락해야 한다.
    static let challengeDuration: TimeInterval = 60
    private(set) var challengeEndsAt: Date?
    private var challengeTimeout: BattleChallengeTimeout?
    private let challengeTimeoutScheduler: BattleChallengeTimeoutScheduling

    /// 이번 턴이 끝나는 시각. 멀티엔 이미 있던 값이고 1v1 만 없었다 — 상대가 자리를 비우면 1v1 은
    /// 기권 말고는 나갈 길이 없었다.
    private(set) var turnEndsAt: Date?
    private var turnTimeoutTask: Task<Void, Never>?

    /// 시간이 다 됐을 때 자동으로 고를 기술 — PP 가 남은 **첫** 칸, 전부 소진이면 발버둥(−1).
    /// 무작위로 고르지 않는 건 시스템 RNG 를 쓰면 같은 상황이 재현되지 않아 회귀 테스트를 못 쓰기 때문.
    static func automaticMoveIndex(for side: BattleSide) -> Int {
        side.pp.indices.first { side.canUse(moveAt: $0) } ?? -1
    }
    private let companion: CompanionStore
    private let monSnapshotBuilder: MonSnapshotBuilder
    private let battleProfileLoader: BattleProfileLoader
    private let moveSetLoader: MoveSetLoader
    private let moveDetailLoader: MoveDetailLoader
    private let inheritedMovesPreparer: InheritedMovesPreparer
    /// TXT 레코드 재발행 지점 — nil 이면 실제 리스너의 `service` 를 갈아 끼운다(테스트 주입 seam).
    private let advertisementPublisher: ((NWTXTRecord) -> Void)?
    let multiplayer: MultiplayerRoomCenter
    let trading: PokemonTradeCenter
    private var listener: NWListener?
    private var browser: NWBrowser?
    private var connection: NWConnection?
    private var incomingSeed: UInt64 = 0
    private var pendingPeerName = ""
    private var iAmPendingChallenger = false
    private var pendingBattleKind: NetBattleKind = .regular
    private var myName: String          // 표시 이름(상대 카드·스냅샷 trainer)
    private var didSettleRankedBrawl = false
    private(set) var isPracticeBattle = false
    private(set) var isMetronomeBattle = false
    private(set) var isResolvingMetronome = false
    private(set) var teamPractice: TeamPracticeBattle?
    /// 지금 도전 중인 체육관. 모의전과 같은 배틀을 쓰므로 이 값이 둘을 가른다.
    private(set) var activeGym: Gym?
    /// 방금 승리로 받은 보상 — 결과 화면이 보여준다. 재도전이면 nil 이다.
    private(set) var lastGymReward: GymReward?
    var rankedTeamSize = 1
    nonisolated static let supportedTeamSizes: Set<Int> = [1, 3, 6]

    /// 모의전에 데려갈 개체 — **고른 순서가 곧 출전 순서**다(첫 번째가 선봉).
    /// 비워 두면 예전처럼 소유 목록 앞에서 자동으로 채운다.
    var pickedTeam: [UUID] = []

    /// 칩을 눌렀을 때 — 이미 고른 것이면 빼고, 아니면 뒤에 붙인다. 정원이 차면 더 받지 않는다
    /// (앞을 밀어내면 애써 정한 순서가 조용히 바뀐다).
    ///
    /// `limit` 은 그 화면의 정원이다 — 체육관은 관장 팀에 맞춰 3, 모의전은 화면에서 고른 크기.
    /// 고른 목록 자체는 하나라 두 화면이 같은 팀을 본다.
    func toggleTeamPick(_ monID: UUID, limit: Int? = nil) {
        let cap = limit ?? rankedTeamSize
        if let index = pickedTeam.firstIndex(of: monID) {
            pickedTeam.remove(at: index)
        } else if pickedTeam.count < cap {
            pickedTeam.append(monID)
        }
    }

    /// 실제 출전 팀. 고른 것을 그 순서대로 앞에 두고, 정원이 남으면 소유 순서로 채운다 —
    /// 하나도 안 골라도 배틀은 시작돼야 하고, 3마리만 고른 6vs6 도 그대로 성립해야 한다.
    var battleTeamMons: [MonState] { battleTeamMons(size: rankedTeamSize) }

    /// 정해진 머릿수의 출전 팀. 체육관은 관장 팀에 맞춰 3 을 넘기고, 모의전은 화면에서 고른 크기를 쓴다.
    func battleTeamMons(size: Int) -> [MonState] {
        battleTeamMons(size: size, selection: pickedTeam)
    }

    func battleTeamMons(size: Int, selection: [UUID]) -> [MonState] {
        guard size > 0 else { return [] }
        let owned = companion.ownedMons
        let byID = Dictionary(owned.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var included = Set<UUID>()
        var team: [MonState] = []
        for id in selection where included.insert(id).inserted {
            if let mon = byID[id] { team.append(mon) }
        }
        for mon in owned where included.insert(mon.id).inserted { team.append(mon) }
        return Array(team.prefix(size))
    }

    /// 선택이 덜 찼을 때 소유 목록 순으로 자동 보충한 실제 UUID 순서.
    func resolvedTeamIDs(size: Int, selection: [UUID]) -> [UUID] {
        battleTeamMons(size: size, selection: selection).map(\.id)
    }

    func prepareIncomingSelection(teamSize: Int) {
        let owned = Set(companion.ownedMons.map(\.id))
        var seen = Set<UUID>()
        incomingPickedTeam = Array(pickedTeam.filter { owned.contains($0) && seen.insert($0).inserted }
            .prefix(teamSize))
    }

    func discardIncomingSelection() {
        incomingPickedTeam = []
    }

    func commitIncomingSelection(_ confirmedIDs: [UUID]) {
        let confirmed = Set(confirmedIDs)
        pickedTeam = Array((confirmedIDs + pickedTeam.filter { !confirmed.contains($0) }).prefix(6))
    }

    /// 파티 편성 화면에서 확정할 실제 출전 순서. 신청자와 수락자 모두 화면이 편집하는
    /// `incomingPickedTeam`을 써야 한다. 신청자만 이전 `pickedTeam`을 읽으면 화면에서 고른 포켓몬과
    /// 실제 선봉이 달라진다.
    func confirmedBattleTeamIDs(size: Int) -> [UUID] {
        resolvedTeamIDs(size: size, selection: incomingPickedTeam)
    }

    /// 출전 순서를 먼저 값으로 확정한 뒤 그 배열만 순차 변환한다. 스탯/기술 조회 중 사용자가
    /// 선택을 바꾸거나 파트너가 교체돼도 이미 시작한 배틀의 슬롯 순서는 흔들리지 않는다.
    func battleTeamSnapshots(size: Int, selection: [UUID]? = nil,
                             levelOverride: Int? = nil) async -> [BattleSnapshot]? {
        var preparedMons = battleTeamMons(size: size, selection: selection ?? pickedTeam)
        guard preparedMons.count == size else { return nil }
        // 기존 근거리전은 현재 파트너의 진화 전 기술까지 먼저 복원했다. 공용 경로로 옮긴 뒤에도
        // 활성 개체가 팀에 있으면 그 동작을 보존하되, UUID/슬롯 순서는 위에서 고정한 배열을 쓴다.
        if let activeID = companion.activeMonID,
           let activeIndex = preparedMons.firstIndex(where: { $0.id == activeID && $0.learnedMoves.isEmpty }) {
            await inheritedMovesPreparer()
            // 다음 슬롯의 스냅샷을 기다리는 동안 동행이 바뀔 수 있다. 복원 직후 UUID 로 다시 찾은
            // 값을 배열에 고정해야, 원래 활성 개체가 박스로 이동해도 복원된 기술이 유실되지 않는다.
            if let refreshed = companion.ownedMons.first(where: { $0.id == activeID }) {
                preparedMons[activeIndex] = refreshed
            }
        }
        var snapshots: [BattleSnapshot] = []
        snapshots.reserveCapacity(preparedMons.count)
        for mon in preparedMons {
            guard let snapshot = await monSnapshotBuilder(mon, levelOverride ?? mon.level) else { return nil }
            snapshots.append(snapshot)
        }
        return snapshots
    }

    nonisolated static func validLineup(snapshot: BattleSnapshot, lineup: [BattleSnapshot],
                                        teamSize: Int) -> Bool {
        guard supportedTeamSizes.contains(teamSize), lineup.count == teamSize,
              lineup.first == snapshot else { return false }
        // 무브셋 범위도 **여기서** 본다. 호출부에 두면 도전/수락 중 한쪽이 무검사가 되고
        // (`statChance: 5000` → 2차효과 확정), 리드 스냅샷만 보면 팀전 2번째 이후 슬롯이 무검사다.
        // 특성 슬러그도 같은 이유로 여기다 — 방 입장에만 두면 1v1 LAN 이 문자열 무검사가 된다.
        return lineup.allSatisfy {
            !$0.types.isEmpty && (1...100).contains($0.level)
                && MultiplayerValidation.validMoves($0.moves ?? [])
                && MultiplayerValidation.validAbility($0.ability)
        }
    }
    private let myServiceName: String   // Bonjour 광고 이름 — 고유 접미로 같은 계정명 두 기기 충돌 방지

    init(companion: CompanionStore,
         monSnapshotBuilder: MonSnapshotBuilder? = nil,
         battleProfileLoader: BattleProfileLoader? = nil,
         moveSetLoader: MoveSetLoader? = nil,
         moveDetailLoader: MoveDetailLoader? = nil,
         inheritedMovesPreparer: InheritedMovesPreparer? = nil,
         advertisementPublisher: ((NWTXTRecord) -> Void)? = nil,
         challengeTimeoutScheduler: BattleChallengeTimeoutScheduling? = nil) {
        self.companion = companion
        self.advertisementPublisher = advertisementPublisher
        self.challengeTimeoutScheduler = challengeTimeoutScheduler ?? SystemBattleChallengeTimeoutScheduler()
        self.monSnapshotBuilder = monSnapshotBuilder ?? { mon, level in
            await companion.battleSnapshot(for: mon, level: level)
        }
        self.battleProfileLoader = battleProfileLoader ?? { speciesID in
            try? await PokeAPIClient.shared.battleProfile(speciesID: speciesID)
        }
        self.moveSetLoader = moveSetLoader ?? { speciesID, level, types in
            await PokeAPIClient.shared.moveSet(speciesID: speciesID, level: level, types: types)
        }
        self.moveDetailLoader = moveDetailLoader ?? { name in
            try? await PokeAPIClient.shared.moveDetail(named: name)
        }
        self.inheritedMovesPreparer = inheritedMovesPreparer ?? {
            await companion.ensureInheritedMoves()
        }
        self.multiplayer = MultiplayerRoomCenter(companion: companion)
        self.trading = PokemonTradeCenter(companion: companion)
        // 표시 이름 우선순위: 사용자가 정한 트레이너 이름 → 계정 풀네임 → 호스트명 → "Trainer".
        let trainer = companion.trainerName.trimmingCharacters(in: .whitespaces)
        let name = !trainer.isEmpty ? trainer
            : (NSFullUserName().isEmpty ? (Host.current().localizedName ?? "Trainer") : NSFullUserName())
        self.myName = name
        // 고유 접미(#xxxxxx) — 같은 사람 이름의 두 Mac이 서로를 "자기"로 오인 필터링하지 않게 한다.
        // 표시할 땐 접미를 떼고, self·id 판정은 이 전체 문자열로 한다.
        self.myServiceName = "\(name)#\(String(UUID().uuidString.prefix(6)))"
        trackAdvertisedValues()
    }

    // MARK: 광고 중인 진행도 (Bonjour TXT)

    /// 지금 TXT 레코드에 실려 있는 값들. 셋이 모두 그대로면 재발행하지 않는다.
    private(set) var advertisedProfile: PeerAdvertisement?

    /// 지금 광고해야 할 값. 형식과 클램프는 `PeerAdvertisement` 가 맡는다.
    private var myAdvertisement: PeerAdvertisement {
        let representative = companion.battleRepresentative
        return PeerAdvertisement(rankPoints: companion.battleRank.points,
                          trainerLevel: companion.trainerLevel.level,
                          achievementTiers: companion.achievementTierTotal,
                          // 내 분모도 싣는다. 카탈로그가 늘어난 뒤 상대가 나를 옳게 그릴 근거다.
                          achievementCeiling: AchievementLadder.tierCeiling,
                          outfit: companion.outfit,
                          representativeSpeciesID: representative?.presentationID,
                          representativeIsShiny: representative?.isShiny ?? false)
    }

    /// 광고 값이 바뀌면 다시 굽는다. 리스너를 만들 때 한 번만 구워서 랭크전 뒤에도 옛 점수가
    /// 계속 광고됐다(#85). 레벨·업적도 같은 부류라 재발행 지점은 여기 하나다.
    func refreshAdvertisedProfile() {
        let profile = myAdvertisement
        guard advertisedProfile != profile else { return }
        let record = profile.txtRecord
        if let advertisementPublisher {
            advertisementPublisher(record)
        } else {
            // 리스너가 없으면 광고 자체가 없다 — 나중에 만들 때 그 시점의 현재 값을 굽으므로
            // 여기서 기록해 두면 그 값이 최신인지 판단할 근거를 잃는다.
            guard let listener else { return }
            listener.service = NWListener.Service(name: myServiceName, type: Self.serviceType,
                                                  domain: nil, txtRecord: record)
        }
        advertisedProfile = profile
    }

    /// `companion` 변화를 계속 따라간다. `withObservationTracking` 은 1회성이라 콜백에서 다시
    /// 등록해야 한다. 세 원본을 각각 읽는 이유: 지금은 셋이 모두 `state` 를 지나 하나만 읽어도
    /// 발화하지만, 하나가 `state` 밖으로 나가면 한 줄짜리 추적은 그 값을 조용히 놓친다(#85).
    private func trackAdvertisedValues() {
        withObservationTracking {
            _ = companion.battleRank.points
            _ = companion.trainerLevel.points
            _ = companion.achievementTierTotal
            // 착장도 같은 부류 — 안 읽으면 옷을 입어도(`wear`/`buyOutfit`/`grantOutfit`) 재발행이
            // 안 걸려 상대 카드가 옛 착장으로 굳는다(#85 와 같은 부류).
            _ = companion.outfit
            _ = companion.battleRepresentative?.id
            _ = companion.battleRepresentative?.presentationID
            _ = companion.battleRepresentative?.isShiny
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.refreshAdvertisedProfile()
                self.trackAdvertisedValues()
            }
        }
    }

    /// 현재 트레이너 표시 이름 — 스냅샷 trainer 필드에 넣는다(설정 후 바뀌어도 최신값).
    private var trainerDisplayName: String {
        let trainer = companion.trainerName.trimmingCharacters(in: .whitespaces)
        return !trainer.isEmpty ? trainer : myName
    }

    /// Bonjour 광고 이름에서 표시 이름 복원 — 마지막 "#고유접미"를 뗀다.
    private nonisolated static func displayName(fromService service: String) -> String {
        guard let hash = service.lastIndex(of: "#") else { return service }
        return String(service[service.startIndex..<hash])
    }

    private var l: L { companion.l }

    var incomingRankedStake: Int {
        guard let opponentRankProfile else { return 0 }
        return BattleRank.stake(challenger: opponentRankProfile.rank, defender: companion.battleRank)
    }

    private var isChallengePending: Bool {
        switch phase {
        case .challenging, .incoming, .teamBuilding, .waitingTeam: true
        default: false
        }
    }

    // MARK: 기동/정지

    func start() {
        startListener()
        startBrowser()
        multiplayer.startBrowsing()
        trading.start()
    }

    /// Bonjour 광고/탐색 파라미터 — `includePeerToPeer` 로 AWDL(피어투피어)까지 켠다.
    /// 사내·게스트 Wi-Fi 처럼 AP 가 클라이언트 간 mDNS 멀티캐스트를 막는 망에선 이게 없으면
    /// 자동 탐색이 조용히 빈다(직접 IP 연결은 unicast 라 되는데 탐색만 안 되는 전형 증상).
    private nonisolated static func discoveryParameters() -> NWParameters {
        let params = NWParameters.tcp
        params.includePeerToPeer = true
        return params
    }

    /// 기본 `.bonjour` 탐색은 서비스만 찾고 TXT 레코드를 요청하지 않아 `metadata == .none` 이다.
    /// 근처 트레이너 카드의 랭크·레벨을 받으려면 TXT 포함 descriptor를 명시해야 한다.
    nonisolated static func discoveryDescriptor() -> NWBrowser.Descriptor {
        .bonjourWithTXTRecord(type: Self.serviceType, domain: nil)
    }

    private func startListener() {
        // 재시작이면 옛 리스너를 먼저 취소한다. 참조만 버리면 실패한 객체가 큐·포트를 붙든 채
        // 남아 슬립 복귀마다 누적된다. 형제인 `MultiplayerRoomCenter.leaveRoom` 은 취소하고
        // 있었다. 호출부가 아니라 입구에 두면 새 재시작 경로가 생겨도 덮인다.
        listener?.cancel()
        do {
            let listener = try NWListener(using: Self.discoveryParameters())
            let profile = myAdvertisement
            listener.service = NWListener.Service(name: myServiceName, type: Self.serviceType,
                                                  domain: nil,
                                                  txtRecord: profile.txtRecord)
            advertisedProfile = profile
            listener.newConnectionHandler = { [weak self] conn in
                Task { @MainActor in self?.acceptConnection(conn) }
            }
            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    let port = listener.port?.rawValue
                    Task { @MainActor in
                        self?.listeningPort = port
                        AppLog.write("battle listener ready port=\(port ?? 0) advertising=\(Self.serviceType)")
                    }
                case .waiting(let e):
                    // 로컬 네트워크 권한 거부·mDNS 차단 → .failed 가 아니라 .waiting 으로 조용히 멈춘다.
                    // 사용자에게 원인(자동 탐색 불가)을 노출해 수동 연결로 유도한다.
                    Task { @MainActor in
                        AppLog.write("battle listener waiting: \(e) — local network blocked?")
                        self?.lastError = self?.l.battleDiscoveryBlocked
                    }
                case .failed(let e):
                    Task { @MainActor in
                        AppLog.write("battle listener failed: \(e) — restarting")
                        self?.listener = nil
                        self?.listeningPort = nil
                        // 슬립 복귀 등 일시 실패 재시도(1회성 지연).
                        try? await Task.sleep(for: .seconds(5))
                        self?.startListener()
                    }
                default:
                    break
                }
            }
            listener.start(queue: .main)
            self.listener = listener
        } catch {
            AppLog.write("battle listener start failed: \(error)")
        }
    }

    private func startBrowser() {
        browser?.cancel()   // 재시작 시 옛 브라우저 취소. `startListener` 와 같은 이유.
        let browser = NWBrowser(for: Self.discoveryDescriptor(),
                                using: Self.discoveryParameters())
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor in self?.updatePeers(results) }
        }
        browser.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                Task { @MainActor in AppLog.write("battle browser ready — scanning \(Self.serviceType)") }
            case .waiting(let e):
                // 권한 거부·차단 → 조용한 무한 대기. 원인을 노출하고 계속 대기(권한을 켜면 자동 복구).
                Task { @MainActor in
                    AppLog.write("battle browser waiting: \(e) — local network blocked?")
                    self?.lastError = self?.l.battleDiscoveryBlocked
                }
            case .failed:
                Task { @MainActor in
                    self?.browser = nil
                    try? await Task.sleep(for: .seconds(5))
                    self?.startBrowser()
                }
            default:
                break
            }
        }
        browser.start(queue: .main)
        self.browser = browser
    }

    /// 발견된 광고 하나를 카드 한 장으로 옮긴다. 자기 필터·표시 이름·광고 파싱이 여기 모인다.
    /// `updatePeers` 의 클로저 안에 두면 `NWBrowser.Result` 를 만들 수 없어 테스트가 닿지 못한다.
    /// `endpoint` 에 기본값을 두지 않는 이유: 브라우저가 해석해 준 엔드포인트 대신 손으로 지은
    /// 것이 쓰이는데, 그 경로는 테스트에서만 밟혀 틀린 채로 남는다.
    nonisolated static func peer(fromService name: String, txtRecord: NWTXTRecord?,
                                 excluding myServiceName: String,
                                 endpoint: NWEndpoint) -> BattlePeer? {
        guard name != myServiceName else { return nil }   // 내 광고만 제외(고유 접미로 정확히 판정)
        // 레코드가 없거나 값이 쓰레기여도 피어를 버리지 않는다. 구버전 상대도 목록에 남아야
        // 신청할 수 있다.
        return BattlePeer(name: displayName(fromService: name), serviceName: name,
                          endpoint: endpoint,
                          advertisement: txtRecord.map(PeerAdvertisement.init) ?? PeerAdvertisement())
    }

    private func updatePeers(_ results: Set<NWBrowser.Result>) {
        peers = results.compactMap { r in
            guard case .service(let name, _, _, _) = r.endpoint else { return nil }
            let record: NWTXTRecord? = if case .bonjour(let txt) = r.metadata { txt } else { nil }
            return Self.peer(fromService: name, txtRecord: record,
                             excluding: myServiceName, endpoint: r.endpoint)
        }.sorted { $0.name < $1.name }
        AppLog.write("battle peers updated: \(results.count) result(s), \(peers.count) after self-filter")
        if !peers.isEmpty { lastError = nil }   // 상대가 보이면 이전 차단 경고 해제
    }

    // MARK: 신청 (challenger = A)

    func startRankedPractice() {
        guard case .ready = phase else { return }
        guard companion.ownedMons.count >= rankedTeamSize else {
            lastError = "출전할 포켓몬이 부족합니다."
            return
        }
        phase = .preparing
        Task {
            // 모의전은 **키운 그대로** 나간다. 랭크도 별의조각도 걸리지 않는 자리라 Lv.50 으로
            // 평준화할 이유가 없고, 평준화하면 갓 부화한 개체와 몇 주 키운 개체가 같은 전력이 되어
            // 정작 키운 보람이 배틀에 드러나지 않는다. 랭크가 걸린 맞짱은 그대로 50 고정이다
            // (`buildMySnapshot(levelOverride: 50)`).
            guard let myTeam = await battleTeamSnapshots(size: rankedTeamSize) else {
                phase = .ready; lastError = l.battleStatsFailed; return
            }
            // CPU 는 마주 서는 슬롯과 같은 레벨로 세운다 — 내 1번이 Lv.12 면 상대 1번도 Lv.12 다.
            // 고정 레벨로 두면 내 팀이 낮을 땐 이길 수 없고, 높을 땐 연습이 되지 않는다.
            var cpuTeam: [BattleSnapshot] = []
            for (slot, opponentID) in Array([25, 59, 94, 130, 143, 149].shuffled().prefix(rankedTeamSize)).enumerated() {
                guard let profile = await battleProfileLoader(opponentID) else { continue }
                let level = myTeam.indices.contains(slot) ? myTeam[slot].level : 50
                let moves = await moveSetLoader(opponentID, level, profile.types)
                cpuTeam.append(BattleSnapshot(speciesID: opponentID, name: "CPU #\(opponentID)", trainer: "CPU",
                                              level: level, nature: nil, isShiny: false, types: profile.types,
                                              base: profile.stats, moves: moves,
                                              ability: profile.abilitySlug,
                                              weightHectograms: profile.weightHectograms))
            }
            guard cpuTeam.count == rankedTeamSize else { phase = .ready; lastError = l.battleStatsFailed; return }
            isPracticeBattle = true
            teamPractice = TeamPracticeBattle(mine: myTeam.map(BattleSide.init),
                                              opponents: cpuTeam.map(BattleSide.init),
                                              rng: SplitMix64(seed: UInt64.random(in: UInt64.min...UInt64.max)))
            opponentRankProfile = BattleRankProfile(rank: companion.battleRank, stardust: 0)
            phase = .battling; rankedStake = 0; pendingAttention = true
        }
    }

    /// 체육관 도전 — 모의전과 같은 배틀이지만 상대는 카탈로그가 정한 관장 팀이다.
    ///
    /// 내 팀은 키운 레벨 그대로, 관장은 카탈로그의 고정 레벨이다(#57 과 같은 규칙, 방향만 반대).
    /// 관장이 도전자를 따라오면 언제 가도 같은 난이도라 이 컨텐츠가 성립하지 않는다.
    func startGymChallenge(_ gym: Gym) {
        guard case .ready = phase else { return }
        guard companion.ownedMons.count >= GymLeague.teamSize else {
            lastError = l.gymNeedsMorePokemon(GymLeague.teamSize)
            return
        }
        phase = .preparing
        Task {
            guard let myTeam = await battleTeamSnapshots(size: GymLeague.teamSize) else {
                phase = .ready; lastError = l.battleStatsFailed; return
            }
            var leaderTeam: [BattleSnapshot] = []
            for (slot, speciesID) in gym.teamSpeciesIDs.enumerated() {
                guard let profile = await battleProfileLoader(speciesID) else { continue }
                // 카탈로그가 정한 기술을 그대로 세운다. 이름이 틀렸거나 못 받아오면 그 종만
                // 자동 선발로 돌아간다 — 관장 하나 때문에 체육관 전체가 막히지는 않는다.
                var moves: [MoveSpec] = []
                for name in gym.teamMoveNames.indices.contains(slot) ? gym.teamMoveNames[slot] : [] {
                    if let spec = await moveDetailLoader(name) { moves.append(spec) }
                }
                if moves.isEmpty {
                    moves = await moveSetLoader(speciesID, gym.level, profile.types)
                }
                let name = await companion.resolveSpeciesName(speciesID)
                leaderTeam.append(BattleSnapshot(speciesID: speciesID, name: name,
                                                 trainer: gym.leaderName(companion.language),
                                                 level: gym.level, nature: nil, isShiny: false,
                                                 types: profile.types, base: profile.stats, moves: moves,
                                                 ability: profile.abilitySlug,
                                                 weightHectograms: profile.weightHectograms))
            }
            guard leaderTeam.count == GymLeague.teamSize else {
                phase = .ready; lastError = l.battleStatsFailed; return
            }
            isPracticeBattle = true
            activeGym = gym
            lastGymReward = nil
            teamPractice = TeamPracticeBattle(mine: myTeam.map(BattleSide.init),
                                              opponents: leaderTeam.map(BattleSide.init),
                                              rng: SplitMix64(seed: UInt64.random(in: .min ... .max)))
            phase = .battling
            pendingAttention = true
        }
    }

    func chooseTeamPracticeMove(_ index: Int) {
        if isMetronomeBattle {
            Task { await chooseMetronomeTurn() }
            return
        }
        guard var practice = teamPractice, practice.useMove(index) else { return }
        teamPractice = practice
        settlePracticeResult(practice)
    }

    private func chooseMetronomeTurn() async {
        guard var practice = teamPractice, isMetronomeBattle, !isResolvingMetronome else { return }
        isResolvingMetronome = true
        defer { isResolvingMetronome = false }
        // 5세대 TM 풀은 공격·회복·랭크·상태기를 고르게 포함하고, 현재 엔진이 모두 해석 가능한
        // 스펙만 들어 있다. 손가락흔들기 자신과 미구현 특수 명령기를 뽑는 일을 피한다.
        let pool = TechnicalMachine.catalog
        guard !pool.isEmpty else { return }
        let mine = pool[Int.random(in: pool.indices)]
        let cpu = pool[Int.random(in: pool.indices)]
        guard let myMove = await moveDetailLoader(mine.slug),
              let cpuMove = await moveDetailLoader(cpu.slug),
              isMetronomeBattle, practice.useResolvedMoves(myMove, cpuMove: cpuMove) else { return }
        teamPractice = practice
        settlePracticeResult(practice)
    }

    /// 승부가 났으면 마무리한다 — 체육관이었고 이겼으면 배지가 여기서 나간다.
    /// 기술 사용과 교체 양쪽이 승부를 낼 수 있어 두 경로가 이 한 곳을 지난다.
    private func settlePracticeResult(_ practice: TeamPracticeBattle) {
        guard let result = practice.result else { return }
        // 배지는 **`.win` 에서만** 나간다 — 무승부는 이긴 판이 아니다.
        // 재도전이면 `recordGymVictory` 가 0 을 돌려준다 — 배지가 이미 있으면 아무것도 지급하지 않는다.
        lastGymReward = (result == .win && activeGym != nil) ? companion.recordGymVictory(activeGym!) : nil
        // 무승부는 `iWon: nil` — 결과 화면이 `l.battleDraw` 를 그린다(`BattleView.finishText`).
        // 결정타가 재생되기 전에 결과 화면으로 스냅하지 않게 재생 뒤로 미룬다.
        deferFinish(iWon: result == .draw ? nil : result == .win, byForfeit: false)
    }

    func switchTeamPractice(to index: Int) {
        guard var practice = teamPractice, practice.switchMine(to: index) else { return }
        teamPractice = practice
        // 교체는 이제 턴을 쓰므로 상대가 그 사이 공격한다 — 마지막 한 마리가 거기서 쓰러질 수 있다.
        settlePracticeResult(practice)
    }

    func challenge(_ peer: BattlePeer) {
        challengeEndpoint(peer.endpoint, displayName: peer.name, kind: .regular)
    }

    /// 친구와 하는 손가락흔들기 전용전. 소유 포켓몬이나 랭크 정산을 사용하지 않는다.
    func challengeMetronome(_ peer: BattlePeer) {
        challengeEndpoint(peer.endpoint, displayName: peer.name, kind: .metronome)
    }

    /// mDNS 가 막힌 네트워크(사내망 등)용 — "IP:포트" 직접 입력 신청.
    func challengeManual(_ address: String) {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: ":")
        guard parts.count == 2, !parts[0].isEmpty,
              let rawPort = UInt16(parts[1]), let port = NWEndpoint.Port(rawValue: rawPort) else {
            lastError = l.battleBadAddress
            return
        }
        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(String(parts[0])), port: port)
        challengeEndpoint(endpoint, displayName: trimmed, kind: .regular)
    }

    /// 내 수동 연결 주소("IP:포트") — 리스너 준비 전/IP 미확인이면 nil.
    var myManualAddress: String? {
        guard let port = listeningPort, let ip = Self.localIPv4() else { return nil }
        return "\(ip):\(port)"
    }

    private func challengeEndpoint(_ endpoint: NWEndpoint, displayName: String, kind: NetBattleKind) {
        guard case .ready = phase else { return }
        let teamSize = kind == .metronome ? 1 : rankedTeamSize
        guard kind == .metronome || (Self.supportedTeamSizes.contains(teamSize)
                                     && companion.ownedMons.count >= teamSize) else {
            lastError = l.battleNeedsPokemon(teamSize)
            return
        }
        lastError = nil
        let seed = UInt64.random(in: .min ... .max)
        incomingSeed = seed
        pendingMyTeamSize = teamSize
        pendingPeerName = displayName
        iAmPendingChallenger = true
        pendingBattleKind = kind
            // includePeerToPeer 파라미터로 연결 — 브라우저가 AWDL(피어투피어)로 찾은 상대는
            // 평범한 .tcp 로는 연결이 안 붙는다(수동 IP 는 직접 hostPort 라 됐던 이유). 리스너/브라우저와
            // 같은 파라미터를 써야 mDNS·AWDL 어느 경로로 발견됐든 연결이 성립한다.
        let conn = NWConnection(to: endpoint, using: Self.discoveryParameters())
        connection = conn
        phase = .challenging(peer: displayName)
        startChallengeTimeout()
        conn.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in self?.connectionState(state, conn: conn) }
        }
        conn.start(queue: .main)
        send(.request(trainer: trainerDisplayName, teamSize: teamSize, seed: seed,
                      profile: companion.battleRankProfile, rulesVersion: BattleEngine.rulesVersion,
                      chatSupported: true, kind: kind), over: conn)
        receiveLoop(conn)
    }

    /// en0 우선 IPv4 — 수동 연결 주소 표기용.
    nonisolated static func localIPv4() -> String? {
        var addrs: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addrs) == 0, let first = addrs else { return nil }
        defer { freeifaddrs(addrs) }
        var fallback: String?
        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let ifa = ptr.pointee
            guard let sa = ifa.ifa_addr, sa.pointee.sa_family == UInt8(AF_INET) else { continue }
            guard (ifa.ifa_flags & UInt32(IFF_UP)) != 0, (ifa.ifa_flags & UInt32(IFF_LOOPBACK)) == 0 else { continue }
            let name = String(cString: ifa.ifa_name)
            guard name.hasPrefix("en") else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(sa, socklen_t(sa.pointee.sa_len), &host, socklen_t(host.count),
                              nil, 0, NI_NUMERICHOST) == 0 else { continue }
            // String(cString:) 의 배열 오버로드만 Swift 6 에서 deprecated 이다 — 포인터 오버로드로 넘긴다.
            let ip = host.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
            if name == "en0" { return ip }
            if fallback == nil { fallback = ip }
        }
        return fallback
    }

    func cancelChallenge() {
        if isChallengePending {
            send(.challengeCancelled(reason: .cancelled), over: connection)
            dropConnection(); phase = .ready
        }
        if case .preparing = phase { clearPendingOutgoing(); phase = .ready }
    }

    // MARK: 수신 (defender = B)

    private func acceptConnection(_ conn: NWConnection) {
        guard case .ready = phase, connection == nil else {
            // 대전 중 새 신청 — 정중히 거절하고 닫는다.
            conn.start(queue: .main)
            send(.decline, over: conn)
            conn.cancel()
            return
        }
        connection = conn
        conn.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in self?.connectionState(state, conn: conn) }
        }
        conn.start(queue: .main)
        receiveLoop(conn)
    }

    func acceptIncoming() {
        guard case .incoming(let peer) = phase, let conn = connection else { return }
        if pendingBattleKind == .metronome {
            cancelChallengeTimeout()
            send(.approve, over: conn)
            prepareMetronomeLineup(peer: peer, connection: conn)
            return
        }
        // 새 신청은 포켓몬을 싣지 않는다. 수락 뒤 양쪽을 같은 파티 편성 단계로 보낸다.
        if incomingLineup.isEmpty {
            cancelChallengeTimeout()
            prepareIncomingSelection(teamSize: incomingTeamSize)
            pendingPeerName = peer
            iAmPendingChallenger = false
            send(.approve, over: conn)
            phase = .teamBuilding(peer: peer)
            return
        }
        guard companion.ownedMons.count >= incomingTeamSize else {
            lastError = l.battleNeedsPokemon(incomingTeamSize)
            return
        }
        let confirmedIDs = resolvedTeamIDs(size: incomingTeamSize, selection: incomingPickedTeam)
        guard confirmedIDs.count == incomingTeamSize else {
            lastError = l.battleNeedsPokemon(incomingTeamSize)
            return
        }
        let opponentTeam = incomingLineup
        let teamSize = incomingTeamSize
        cancelChallengeTimeout()
        phase = .preparing
        Task { @MainActor in
            let prepared = await buildMyLineup(size: teamSize, selection: confirmedIDs,
                                               levelOverride: 50)
            // 스냅샷을 준비하는 동안 상대 연결이 끊겼으면 초안도 이미 폐기됐다. 늦게 수락하지 않는다.
            guard case .preparing = phase, conn === connection else { return }
            guard let mine = prepared, let lead = mine.first else {
                send(.decline, over: conn)
                dropConnection()
                phase = .ready
                lastError = l.battleStatsFailed
                return
            }
            let mineProfile = companion.battleRankProfile
            let stake = BattleRank.stake(challenger: opponentRankProfile?.rank ?? BattleRank(),
                                         defender: mineProfile.rank)
            guard stake == 0 || (mineProfile.stardust >= stake && (opponentRankProfile?.stardust ?? 0) >= stake) else {
                send(.decline, over: conn)
                dropConnection(); phase = .ready; lastError = l.battleStakeShort
                return
            }
            // 수락이 확정된 뒤에만 공용 선택의 앞부분을 실제 출전 순서로 바꾼다.
            commitIncomingSelection(confirmedIDs)
            send(.accept(snapshot: lead, lineup: mine, teamSize: teamSize, profile: mineProfile,
                         rulesVersion: BattleEngine.rulesVersion, chatSupported: true), over: conn)
            beginBattle(my: mine, opp: opponentTeam, iAmA: false, seed: incomingSeed)
        }
    }

    private func prepareMetronomeLineup(peer: String, connection conn: NWConnection) {
        phase = .preparing
        Task { @MainActor in
            guard let profile = await battleProfileLoader(468),
                  var metronome = await moveDetailLoader("metronome"), conn === connection else {
                phase = .ready; lastError = l.battleStatsFailed; return
            }
            // 전용전은 PP 고갈로 발버둥에 떨어지는 모드가 아니다.
            metronome.pp = 99
            let rental = BattleSnapshot(speciesID: 468,
                                        name: l.t("대여 토게키스", "Rental Togekiss", "レンタルトゲキッス"),
                                        trainer: trainerDisplayName, level: 50, nature: nil, isShiny: false,
                                        types: profile.types, base: profile.stats, moves: [metronome],
                                        ability: profile.abilitySlug, weightHectograms: profile.weightHectograms)
            pendingMyLineup = [rental]
            isMetronomeBattle = true
            send(.teamReady(snapshot: rental, lineup: [rental], teamSize: 1,
                            profile: companion.battleRankProfile, rulesVersion: BattleEngine.rulesVersion,
                            chatSupported: true), over: conn)
            if !incomingLineup.isEmpty {
                opponentRankProfile = nil
                beginBattle(my: [rental], opp: incomingLineup, iAmA: iAmPendingChallenger, seed: incomingSeed)
            } else {
                phase = .waitingTeam(peer: peer)
            }
        }
    }

    /// 수락 뒤 편성 확정. 내 스냅샷은 이 시점에 처음 상대에게 전송된다.
    func confirmBattleTeam() {
        guard case .teamBuilding(let peer) = phase, let conn = connection else { return }
        let ids = confirmedBattleTeamIDs(size: incomingTeamSize)
        guard ids.count == incomingTeamSize else { lastError = l.battleNeedsPokemon(incomingTeamSize); return }
        phase = .preparing
        Task { @MainActor in
            guard let mine = await buildMyLineup(size: incomingTeamSize, selection: ids, levelOverride: 50),
                  let lead = mine.first, conn === connection else {
                phase = .ready; lastError = l.battleStatsFailed; return
            }
            pendingMyLineup = mine
            commitIncomingSelection(ids)
            send(.teamReady(snapshot: lead, lineup: mine, teamSize: incomingTeamSize,
                            profile: companion.battleRankProfile, rulesVersion: BattleEngine.rulesVersion,
                            chatSupported: true), over: conn)
            if !incomingLineup.isEmpty {
                beginBattle(my: mine, opp: incomingLineup, iAmA: iAmPendingChallenger, seed: incomingSeed)
            } else {
                phase = .waitingTeam(peer: peer)
            }
        }
    }

    func declineIncoming() {
        guard case .incoming = phase, let conn = connection else { return }
        send(.decline, over: conn)
        dropConnection()
        phase = .ready
    }

    // MARK: 대전 진행

    func chooseMove(_ index: Int) {
        // `pendingFinish` 는 승부가 이미 난 상태다 — 재생이 도는 동안 국면은 아직 `.battling` 이라
        // 이 가드가 없으면 끝난 배틀에 기술을 보낸다.
        guard case .battling = phase, pendingFinish == nil,
              var b = battle, b.myAction == nil else { return }
        if b.isMetronome {
            guard !isResolvingMetronome else { return }
            isResolvingMetronome = true
            Task { @MainActor in
                defer { isResolvingMetronome = false }
                guard let called = await randomMetronomeMove(), case .battling = phase,
                      var current = battle, current.myAction == nil else { return }
                let action = NetBattleAction.metronome(move: called)
                guard current.canChoose(action, mine: true), let conn = connection else { return }
                current.myAction = action
                battle = current
                send(.action(turn: current.turn, action: action), over: conn)
                resolveIfReady()
            }
            return
        }
        let idx = b.mustStruggle ? -1 : index
        let action = NetBattleAction.move(index: idx)
        guard b.canChoose(action, mine: true) else { return }
        b.myAction = action
        guard let conn = connection else { return }
        battle = b
        send(.action(turn: b.turn, action: action), over: conn)
        resolveIfReady()
    }

    /// 5세대까지 존재하는 기술 ID 전체에서 뽑는다. 호출 불가인 손가락흔들기 자신과 발버둥만 제외하고,
    /// 현재 엔진/와이어 검증을 통과하는 실제 MoveSpec을 상대에게 그대로 보내 양쪽 결과를 일치시킨다.
    private func randomMetronomeMove() async -> MoveSpec? {
        for _ in 0..<20 {
            let id = Int.random(in: 1...559)
            guard id != 118, id != 165,
                  let move = await moveDetailLoader(String(id)),
                  MultiplayerValidation.validMoves([move]) else { continue }
            return move
        }
        // 일시적으로 일부 ID 조회가 실패해도 턴을 잠그지 않는다. 같은 전체 범위에서 이미 앱이
        // 지원 목록으로 검증한 5세대 TM 중 하나를 마지막 폴백으로 사용한다.
        guard let fallback = TechnicalMachine.catalog.randomElement() else { return nil }
        return await moveDetailLoader(fallback.slug)
    }

    func switchLAN(to index: Int) {
        guard case .battling = phase, pendingFinish == nil,
              var b = battle, b.myAction == nil else { return }
        let action = NetBattleAction.switchTo(index: index)
        guard b.canChoose(action, mine: true), let conn = connection else { return }
        b.myAction = action
        battle = b
        send(.action(turn: b.turn, action: action), over: conn)
        resolveIfReady()
    }

    func forfeit() {
        cancelTurnTimeout()
        if isPracticeBattle {
            phase = .finished(iWon: false, byForfeit: true)
            return
        }
        if let conn = connection { send(.forfeit, over: conn) }
        dropConnection()
        phase = .finished(iWon: false, byForfeit: true)
        settleRankedBrawlIfNeeded(won: false)
    }

    /// 새 대전이 시작될 때 대화만 비운다. 상대 지원 여부는 핸드셰이크가 이미 정했으므로 건드리지 않는다.
    private func resetChatHistory() {
        chatHistory.reset(); chatMessages = []; chatRateLimiter.reset()
    }

    /// 소켓이 닫혔다 — 입력만 잠근다. 두 정리 경로(`connectionDropped`·`dropConnection`)가
    /// 이 한 곳을 지나므로 "닫는다"의 정의가 하나다.
    ///
    /// **주고받은 대화는 여기서 지우지 않는다.** 배틀이 끝나는 순간 `resolveIfReady` 가 여기를
    /// 지나는데 결과는 재생 뒤로 미뤄져(`deferFinish`) 국면은 아직 `.battling` 이다 — 지우면 화면에
    /// 남아 있는 대전 화면에서 방금 한 말이 사라진다(리포트된 증상). 비우는 자리는 새 배틀 시작과
    /// 세션 경계인 `.ready` 진입뿐이다.
    private func closeChatInput() {
        chatIsAvailable = false
    }

    /// 세션 종료 — 다음 핸드셰이크가 다시 열 때까지 아무것도 남기지 않는다.
    /// `.ready` 진입점에서만 부른다. 결과·결정타 재생은 아직 같은 세션이므로 대화와 상대 지원
    /// 사실을 유지해야 한다.
    private func endChatSession() {
        resetChatHistory()
        chatIsAvailable = false
        peerSupportsChat = false
    }

    /// 채팅이 잠긴 **이유**. 상대 빌드가 채팅을 명시적으로 지원하지 않을 때만 안내한다.
    /// 정상적인 연결 종료·결과·결정타 재생에는 원인을 추측하는 문구를 그리지 않는다.
    var chatLockMessage: String? {
        guard !chatIsAvailable, !peerSupportsChat else { return nil }
        return l.battleChatUnavailable
    }

    /// 채팅은 행동 선택과 별도 프레임으로만 전송한다.
    func sendChat(_ body: String) {
        guard case .battling = phase, chatIsAvailable,
              let text = BattleChatPolicy.normalizedBody(body), chatRateLimiter.allows(chatSenderID) else { return }
        let message = BattleChatMessage(senderID: chatSenderID, senderName: myName, body: text)
        chatHistory.append(message); chatMessages = chatHistory.messages
        send(.chat(message), over: connection)
    }

    func dismissResult() {
        cancelTurnTimeout()
        battle = nil
        teamPractice = nil
        if case .finished = phase { phase = .ready }
        isPracticeBattle = false
        isMetronomeBattle = false
        isResolvingMetronome = false
        activeGym = nil
        lastGymReward = nil
        // 정산 표시값도 여기서 비운다 — 결과 화면(`finishedView`)이 이 둘을 그대로 그리는데, 다음 배틀이
        // 랭크전이 아니면(체육관·모의전) 아무도 다시 채우지 않아 체육관 결과에 직전 랭크전의
        // "−⭐ 5,000 / −25 LP"가 그대로 남는다.
        rankedStake = 0
        lastRankDelta = 0
        // `.ready` 전환이 모든 세션 상태를 정리한다. 연결 정리(`dropConnection`)는 소켓 입력만 닫아
        // 결과 화면과 결정타 재생에서 대화가 유지되게 한다.
    }

    private var pendingMyLineup: [BattleSnapshot] = []
    private var pendingMyTeamSize = 1

    private func clearPendingOutgoing() {
        pendingMyLineup = []
        pendingMyTeamSize = 1
    }

    private func beginBattle(my: [BattleSnapshot], opp: [BattleSnapshot], iAmA: Bool, seed: UInt64) {
        cancelChallengeTimeout()
        resetChatHistory()
        didSettleRankedBrawl = false
        lastRankDelta = 0
        if let opponentRankProfile {
            rankedStake = iAmA
                ? BattleRank.stake(challenger: companion.battleRank, defender: opponentRankProfile.rank)
                : BattleRank.stake(challenger: opponentRankProfile.rank, defender: companion.battleRank)
        } else {
            rankedStake = 0
        }
        // 판돈은 **여기서** 빠져나간다 — 정산을 배틀 끝에 두면 앱을 끄는 것으로 회피할 수 있었다.
        // 판돈 0 이어도 기록은 남는다(이탈의 LP 대가). 못 내면 배틀을 시작하지 않는다 —
        // 앞단(`acceptIncoming`·`handle(.accept)`)이 이미 잔액을 확인하므로 여기 걸리는 건 이상 상황이다.
        if !isPracticeBattle, let opponentRankProfile,
           !companion.escrowRankedBattle(stake: rankedStake, opponent: opponentRankProfile.rank) {
            // 상대는 이미 `.accept` 를 주고받아 `.battling` 으로 들어가 **자기 에스크로를 잡은** 상태다.
            // 연결만 끊는다 — `.forfeit` 은 보내면 안 된다. 상대의 `handle(.forfeit)` 이 몰수승으로
            // `escrowed * 2` 를 지급하는데 나는 판돈을 못 내서 빠지는 것이라, 아무도 내지 않은 판돈
            // 1배가 그대로 생성된다(별의조각 총량 증가). 끊기만 해도 상대는 안다 — `dropConnection` 이
            // 연결을 닫으면 상대의 `connectionDropped` 가 돌고, 아직 한 턴도 안 지나 HP 비율이 같아
            // **무효(환급)** 가 된다.
            dropConnection()
            phase = .ready
            lastError = l.battleStakeShort
            return
        }
        var nextBattle = NetBattleState(iAmA: iAmA, myTeam: my.map(BattleSide.init),
                                        oppTeam: opp.map(BattleSide.init),
                                        rng: SplitMix64(seed: seed))
        nextBattle.isMetronome = isMetronomeBattle
        battle = nextBattle
        clearPendingOutgoing()
        phase = .battling
        pendingAttention = true
        scheduleTurnTimeout()
    }

    #if DEBUG
    /// 단위 테스트가 실제 수신 행동 → 턴 해상 → 재생 지연 마감 경로를 연결 없이 검증하는 진입점.
    /// 이미 고른 내 행동만 받는다. 상대 행동은 반드시 `handle(.action)` 으로 넣어야 한다.
    func stageBattleForTesting(_ state: NetBattleState, peerSupportsChat: Bool = true) {
        precondition(state.myAction != nil, "the local action must already be selected")
        precondition(state.oppAction == nil, "the remote action must arrive through handle(_:)")
        cancelTurnTimeout()
        battle = state
        phase = .battling
        self.peerSupportsChat = peerSupportsChat
        chatIsAvailable = peerSupportsChat
    }
    #endif

    /// 이번 턴의 마감을 건다. 연습 배틀엔 걸지 않는다 — CPU 는 즉시 답하므로 기다림이 없다.
    private func scheduleTurnTimeout() {
        turnTimeoutTask?.cancel()
        guard case .battling = phase, let state = battle, !isPracticeBattle else {
            turnEndsAt = nil
            return
        }
        let turn = state.turn
        turnEndsAt = Date().addingTimeInterval(Self.turnDuration)
        turnTimeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.turnDuration))
            guard !Task.isCancelled else { return }
            self?.fillTimedOutChoice(turn: turn)
        }
    }

    private func cancelTurnTimeout() {
        turnTimeoutTask?.cancel()
        turnTimeoutTask = nil
        turnEndsAt = nil
    }

    /// 시간이 다 됐는데 아직 안 골랐으면 자동으로 고른다. 사람이 고른 것과 **같은 경로로** 나가므로
    /// 두 피어가 갈라지지 않고, 규칙이 아니라 입력이 바뀌는 것이라 `rulesVersion` 도 그대로다.
    private func fillTimedOutChoice(turn: Int) {
        guard case .battling = phase, let state = battle, state.turn == turn, state.myAction == nil else { return }
        AppLog.write("battle turn \(turn) timed out — choosing a move automatically")
        chooseMove(Self.automaticMoveIndex(for: state.me))
    }

    /// 재생이 엔진을 따라잡았다 — 미뤄 둔 결과를 화면에 올린다.
    /// `BattleAnimator.onCaughtUp` 이 부르고, 팝오버가 닫혀 있으면 `finishDeadline` 이 부른다.
    func commitPendingFinish() {
        // 국면이 이미 넘어갔으면(항복·끊김·새 배틀) 미뤄 둔 결과는 버린다.
        guard case .battling = phase, let finish = pendingFinish else { return dropPendingFinish() }
        dropPendingFinish()
        phase = .finished(iWon: finish.iWon, byForfeit: finish.byForfeit)
    }

    /// 결과를 재생 뒤로 미룬다. 정산·연결 정리는 미루지 않는다 — 결과 화면이 뜰 때 LP·판돈 숫자가
    /// 이미 준비돼 있어야 하고, 끊긴 연결을 재생 시간만큼 붙잡아 둘 이유도 없다.
    private func deferFinish(iWon: Bool?, byForfeit: Bool) {
        dropPendingFinish()
        pendingFinish = (iWon, byForfeit)
        finishDeadline = Task { [weak self] in
            try? await Task.sleep(for: .seconds(BattleReplay.budget + 0.6))
            self?.commitPendingFinish()
        }
    }

    private func dropPendingFinish() {
        pendingFinish = nil
        finishDeadline?.cancel()
        finishDeadline = nil
    }

    /// 양쪽 선택이 모이면 턴 해상 — challenger 를 A 로 고정해 양쪽이 같은 좌변으로 계산.
    private func resolveIfReady() {
        guard var b = battle, b.myAction != nil, b.oppAction != nil else { return }
        let outcome = b.resolveChosenActions()
        battle = b

        if let outcome {
            let iWon: Bool?
            switch outcome {
            case .win: iWon = true
            case .loss: iWon = false
            case .draw: iWon = nil
            }
            dropConnection()
            cancelTurnTimeout()
            deferFinish(iWon: iWon, byForfeit: false)
            if !isPracticeBattle {
                if let iWon { settleRankedBrawlIfNeeded(won: iWon) } else { refundRankedBrawlIfNeeded() }
            }
        } else {
            scheduleTurnTimeout()   // 다음 턴의 마감 — 멀티의 `finishRoundIfReady` 와 같은 자리다
        }
    }

    // MARK: 메시지 처리

    /// 와이어 메시지 하나를 상태기계에 넣는다. `internal` 인 이유는 **테스트 진입점**이다 —
    /// 수신 루프는 `NWConnection` 이 필요해 단위 테스트가 실제 핸드셰이크·채팅 경로를 밟을 다른
    /// 수단이 없다(그래서 채팅 상태 수명주기에 테스트가 0건이었고 이 결함이 나갔다).
    func handle(_ message: NetMessage) {
        switch message {
        case .request(let trainer, let teamSize, let seed, let profile, let rulesVersion, let peerChatSupported, let kind):
            guard case .ready = phase, Self.supportedTeamSizes.contains(teamSize),
                  rulesVersion == BattleEngine.rulesVersion else {
                send(.decline, over: connection); dropConnection(); phase = .ready; return
            }
            if UserDefaults.standard.object(forKey: "doNotDisturb") as? Bool ?? false {
                send(.decline, over: connection); dropConnection(); phase = .ready; return
            }
            incomingLineup = []
            incomingSnapshot = nil
            incomingTeamSize = teamSize
            incomingSeed = seed
            opponentRankProfile = profile
            peerSupportsChat = peerChatSupported == true
            pendingPeerName = trainer
            iAmPendingChallenger = false
            pendingBattleKind = kind ?? .regular
            phase = .incoming(peer: trainer)
            startChallengeTimeout()
            pendingAttention = true
            postPrivateMessageNotification(kind: "battle", nonce: seed)
        case .approve:
            guard case .challenging(let peer) = phase else { return }
            cancelChallengeTimeout()
            incomingTeamSize = pendingMyTeamSize
            incomingLineup = []
            if pendingBattleKind == .metronome, let connection {
                prepareMetronomeLineup(peer: peer, connection: connection)
                return
            }
            incomingPickedTeam = resolvedTeamIDs(size: incomingTeamSize, selection: pickedTeam)
            phase = .teamBuilding(peer: peer)
        case .teamReady(let snapshot, let lineup, let teamSize, let profile, let rulesVersion, let peerChatSupported):
            guard rulesVersion == BattleEngine.rulesVersion,
                  teamSize == incomingTeamSize,
                  Self.validLineup(snapshot: snapshot, lineup: lineup, teamSize: teamSize) else {
                send(.decline, over: connection); dropConnection(); phase = .ready; return
            }
            incomingSnapshot = snapshot
            incomingLineup = lineup
            opponentRankProfile = pendingBattleKind == .metronome ? nil : profile
            peerSupportsChat = peerChatSupported == true
            chatIsAvailable = peerSupportsChat
            if !pendingMyLineup.isEmpty {
                if pendingBattleKind == .metronome { isMetronomeBattle = true }
                beginBattle(my: pendingMyLineup, opp: lineup, iAmA: iAmPendingChallenger, seed: incomingSeed)
            }
        case .challenge(let snapshot, let lineup, let teamSize, let seed, let profile, let rulesVersion, let peerChatSupported):
            guard case .ready = phase else { return }   // 자기 연결로 challenge 재수신 등 비정상
            guard rulesVersion == BattleEngine.rulesVersion else {
                send(.decline, over: connection)
                dropConnection()
                phase = .ready
                lastError = l.battleRulesMismatch
                AppLog.write("battle challenge declined: rules version \(rulesVersion.map(String.init) ?? "none")")
                return
            }
            if UserDefaults.standard.object(forKey: "doNotDisturb") as? Bool ?? false {
                send(.decline, over: connection)
                dropConnection()
                phase = .ready
                AppLog.write("battle challenge declined: do not disturb enabled")
                return
            }
            guard Self.validLineup(snapshot: snapshot, lineup: lineup, teamSize: teamSize) else {
                send(.decline, over: connection)
                dropConnection()
                return
            }
            incomingSnapshot = snapshot
            incomingLineup = lineup
            incomingTeamSize = teamSize
            prepareIncomingSelection(teamSize: teamSize)
            incomingSeed = seed
            opponentRankProfile = profile
            peerSupportsChat = peerChatSupported == true
            chatIsAvailable = peerSupportsChat
            AppLog.write("battle chat \(peerSupportsChat ? "enabled" : "disabled — peer build sent no chatSupported")")
            phase = .incoming(peer: snapshot.trainer ?? snapshot.name)
            startChallengeTimeout()
            pendingAttention = true
            postPrivateMessageNotification(kind: "battle", nonce: incomingSeed)
        case .accept(let snapshot, let lineup, let teamSize, let profile, let rulesVersion, let peerChatSupported):
            guard case .challenging = phase, !pendingMyLineup.isEmpty else { return }
            guard rulesVersion == BattleEngine.rulesVersion else {
                dropConnection(); phase = .ready; lastError = l.battleRulesMismatch
                return
            }
            guard teamSize == pendingMyTeamSize,
                  Self.validLineup(snapshot: snapshot, lineup: lineup, teamSize: teamSize) else {
                dropConnection(); phase = .ready; return
            }
            let stake = BattleRank.stake(challenger: companion.battleRank, defender: profile.rank)
            guard stake == 0 || (companion.availableTokens >= stake && profile.stardust >= stake) else {
                dropConnection(); phase = .ready; lastError = l.battleStakeShort
                return
            }
            opponentRankProfile = profile
            peerSupportsChat = peerChatSupported == true
            chatIsAvailable = peerSupportsChat
            AppLog.write("battle chat \(peerSupportsChat ? "enabled" : "disabled — peer build sent no chatSupported")")
            beginBattle(my: pendingMyLineup, opp: lineup, iAmA: true, seed: incomingSeed)
        case .decline:
            if isChallengePending {
                dropConnection()
                phase = .ready
                lastError = l.battleDeclined
            }
        case .challengeCancelled(let reason):
            guard isChallengePending else { return }
            dropConnection()
            phase = .ready
            if reason == .timedOut { lastError = l.battleChallengeTimedOut }
        case .action(let turn, let action):
            guard case .battling = phase, var b = battle, b.oppAction == nil, turn == b.turn,
                  b.canChoose(action, mine: false) else { return }
            b.oppAction = action
            battle = b
            resolveIfReady()
        case .move:
            // 구버전 메시지는 디코딩만 한다. 팀 규칙 버전 핸드셰이크를 통과할 수 없어 적용하지 않는다.
            return
        case .forfeit:
            if case .battling = phase {
                dropConnection()
                phase = .finished(iWon: true, byForfeit: true)
                settleRankedBrawlIfNeeded(won: true)
            }
        case .chat(let message):
            guard case .battling = phase, chatIsAvailable,
                  BattleChatPolicy.normalizedBody(message.body) == message.body,
                  chatRateLimiter.allows(message.senderID) else { return }
            chatHistory.append(message); chatMessages = chatHistory.messages
        }
    }

    private func connectionState(_ state: NWConnection.State, conn: NWConnection) {
        guard conn === connection else { return }
        switch state {
        case .ready:
            AppLog.write("battle connection ready")
        case .waiting(let e):
            AppLog.write("battle connection waiting: \(e)")   // 경로 못 붙음(p2p 파라미터·권한·방화벽)
        case .preparing:
            break
        case .failed(let e):
            AppLog.write("battle connection failed: \(e)")
            connectionDropped()
        case .cancelled:
            connectionDropped()
        default:
            break
        }
    }

    private func connectionDropped() {
        guard connection != nil else { return }
        connection = nil
        cancelChallengeTimeout()
        cancelTurnTimeout()   // 상대가 사라진 뒤에 마감이 돌면 이미 끝난 배틀에 기술을 보낸다
        switch phase {
        case .battling:
            // 끊김은 몰수승이 **아니다** — 내 연결이 죽은 건 두 피어에게 똑같이 보이므로 무조건 승리로
            // 접으면 네트워크가 한 번 끊길 때 양쪽이 동시에 이기고 양쪽이 판돈을 받았다. 남은 HP 비율로
            // 판정하고 동률이면 무효다(정산 없음). 상대가 보낸 `.forfeit` 은 `handle(.forfeit)` 이 처리한다 —
            // 그건 상대가 스스로 진 것이므로 그대로 몰수승이다.
            //
            // `byForfeit: false` 다 — 끊김은 기권이 **아니다.** true 로 두면 결과 화면이 `battleYouForfeited`
            // ("기권했어요")를 그려, 와이파이가 끊겨 HP 비율로 진 사람에게 스스로 기권했다고 말한다.
            // 끊겼다는 사실은 `lastError` 가 따로 알린다(다른 phase 의 끊김과 같은 문구).
            let iWon = battle.flatMap { BattleEngine.disconnectOutcome(me: $0.myTeam, opp: $0.oppTeam) }
            phase = .finished(iWon: iWon, byForfeit: false)
            lastError = l.battleConnectionLost
            if let iWon { settleRankedBrawlIfNeeded(won: iWon) } else { refundRankedBrawlIfNeeded() }
        case .challenging, .incoming, .teamBuilding, .waitingTeam, .preparing:
            phase = .ready
            lastError = l.battleConnectionLost
        default:
            break
        }
        incomingSnapshot = nil
        incomingLineup = []
        discardIncomingSelection()
        incomingTeamSize = 1
        clearPendingOutgoing()
        closeChatInput()
    }

    private func dropConnection() {
        let conn = connection
        connection = nil          // connectionDropped 재진입 차단(cancel 콜백)
        conn?.cancel()
        cancelChallengeTimeout()
        cancelTurnTimeout()
        incomingSnapshot = nil
        incomingLineup = []
        discardIncomingSelection()
        incomingTeamSize = 1
        clearPendingOutgoing()
        closeChatInput()
    }

    /// 신청 상태에서만 실행되는 별도 마감. 배틀 턴 타이머와 독립적이다.
    func startChallengeTimeout() {
        cancelChallengeTimeout()
        guard isChallengePending else { return }
        challengeEndsAt = Date().addingTimeInterval(Self.challengeDuration)
        challengeTimeout = challengeTimeoutScheduler.schedule { [weak self] in
            self?.expireChallenge()
        }
    }

    private func cancelChallengeTimeout() {
        challengeTimeout?.cancel()
        challengeTimeout = nil
        challengeEndsAt = nil
    }

    private func expireChallenge() {
        guard isChallengePending else { return }
        send(.challengeCancelled(reason: .timedOut), over: connection)
        dropConnection()
        phase = .ready
        lastError = l.battleChallengeTimedOut
    }

    private func settleRankedBrawlIfNeeded(won: Bool) {
        // 전제는 환급(`refundRankedBrawlIfNeeded`)과 같아야 한다 — 둘 중 하나만 연습전을 걸러 두면
        // 다음 호출부가 "어느 쪽이 안전한가"를 스스로 판단해야 한다(모의전은 애초에 에스크로가 없다).
        guard battle != nil, !didSettleRankedBrawl, !isPracticeBattle,
              let opponent = opponentRankProfile else { return }
        didSettleRankedBrawl = true
        lastRankDelta = companion.settleRankedBrawl(won: won, opponent: opponent.rank)
    }

    /// 무효로 끝난 랭크전 — 에스크로를 돌려주고 랭크는 그대로 둔다. 승패 정산과 같은 자리에서
    /// 한 번만 돈다(`didSettleRankedBrawl`).
    private func refundRankedBrawlIfNeeded() {
        guard battle != nil, !didSettleRankedBrawl, !isPracticeBattle else { return }
        didSettleRankedBrawl = true
        companion.refundRankedEscrow()
    }

    // MARK: 전송/수신 (길이 프리픽스 프레이밍)

    private func send(_ message: NetMessage, over conn: NWConnection?) {
        guard let conn else { return }
        guard let payload = try? JSONEncoder().encode(message) else { return }
        var frame = withUnsafeBytes(of: UInt32(payload.count).bigEndian) { Data($0) }
        frame.append(payload)
        conn.send(content: frame, completion: .contentProcessed { _ in })
    }

    private func receiveLoop(_ conn: NWConnection) {
        conn.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self] data, _, _, _ in
            guard let data, data.count == 4 else {
                Task { @MainActor in self?.connectionDropped() }
                return
            }
            let length = data.withUnsafeBytes { $0.load(as: UInt32.self) }.bigEndian
            guard length > 0, length <= Self.maxMessageBytes else {
                Task { @MainActor in self?.connectionDropped() }
                return
            }
            conn.receive(minimumIncompleteLength: Int(length), maximumLength: Int(length)) { data, _, _, _ in
                guard let data, data.count == Int(length),
                      let message = try? JSONDecoder().decode(NetMessage.self, from: data) else {
                    Task { @MainActor in self?.connectionDropped() }
                    return
                }
                Task { @MainActor in
                    guard let self, conn === self.currentConnection() else { return }
                    self.handle(message)
                    self.receiveLoop(conn)
                }
            }
        }
    }

    private func currentConnection() -> NWConnection? { connection }

    // MARK: 내 스냅샷 (무브셋 포함)

    func buildMySnapshot(levelOverride: Int? = nil) async -> BattleSnapshot? {
        await buildMyLineup(size: 1, levelOverride: levelOverride)?.first
    }

    func buildMyLineup(size: Int, selection: [UUID]? = nil,
                       levelOverride: Int? = nil) async -> [BattleSnapshot]? {
        guard var lineup = await battleTeamSnapshots(size: size, selection: selection,
                                                     levelOverride: levelOverride) else { return nil }
        // 근거리 랭크전은 기존처럼 비어 있지 않은 표시 이름을 보낸다. 공용 포켓몬 스냅샷은
        // 연습전에서도 써서 저장된 trainerName 그대로 두므로, wire 로 내보내는 이 자리에서만 보정한다.
        for index in lineup.indices { lineup[index].trainer = trainerDisplayName }
        return lineup
    }

    // MARK: 알림

    private func postPrivateMessageNotification(kind: String, nonce: UInt64) {
        guard !(UserDefaults.standard.object(forKey: "doNotDisturb") as? Bool ?? false) else { return }
        AppLog.write("private \(kind) request received — posting generic notification")
        guard AppEnv.isBundledApp else { AppLog.write("battle notif skipped: not bundled app"); return }
        let content = UNMutableNotificationContent()
        content.title = l.t("메시지가 왔습니다", "You have a message", "メッセージが届きました")
        content.body = l.t("눌러서 확인하세요.", "Click to view it.", "クリックして確認してください。")
        content.sound = .default
        let center = UNUserNotificationCenter.current()
        // completion 은 시스템이 **백그라운드 큐**에서 부른다 — @MainActor 문맥에서 만든 클로저가 격리를
        // 상속하면 런타임 executor 검사에 걸려 SIGTRAP(_dispatch_assert_queue_fail). @Sendable 로 격리 차단.
        // 앱이 포그라운드여도 배틀 신청 알림이 보이도록 권한을 요청한다.
        center.getNotificationSettings { @Sendable settings in
            AppLog.write("battle notif auth status=\(settings.authorizationStatus.rawValue) (0=notDetermined 1=denied 2=authorized 3=provisional)")
        }
        center.add(
            UNNotificationRequest(identifier: "private-message-\(kind)-\(nonce)",
                                  content: content, trigger: nil)) { @Sendable error in
            if let error { AppLog.write("battle notif add failed: \(error)") }
            else { AppLog.write("battle notif posted") }
        }
    }
}
