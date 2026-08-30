import Foundation

enum BattleTeam: String, Codable, Sendable { case solo, red, blue }
enum RoomActivity: String, Codable, Sendable { case battle, pokeathlon, pokemonQuiz, tournament, gym }

/// 방에서의 역할. 러너만 경기·전투에 참여하고, 관전자는 베팅만 한다.
enum LobbyRole: String, Codable, Sendable { case runner, spectator }

struct LobbyParticipant: Codable, Sendable, Equatable, Identifiable {
    let id: UUID
    var trainerName: String
    var speciesID: Int
    var team: BattleTeam
    var isReady: Bool
    var isHost: Bool
    var role: LobbyRole
    /// 참가 시점에 본인이 신고한 별조각 잔액. 호스트가 베팅 상한 검사에 쓴다.
    /// 조작된 클라이언트가 부풀릴 수 있는 값이라 "이 이상은 못 건다"는 상한으로만 쓰고,
    /// 실제 차감은 각 클라이언트가 자기 세이브에서 한다.
    var reportedStarPieces: Int

    init(id: UUID, trainerName: String, speciesID: Int, team: BattleTeam,
         isReady: Bool, isHost: Bool, role: LobbyRole = .runner, reportedStarPieces: Int = 0) {
        self.id = id; self.trainerName = trainerName; self.speciesID = speciesID
        self.team = team; self.isReady = isReady; self.isHost = isHost
        self.role = role; self.reportedStarPieces = reportedStarPieces
    }

    /// role/reportedStarPieces 가 없는 옛 payload·세이브도 계속 디코딩되게 기본값을 준다.
    /// (합성 이니셜라이저를 쓰면 필드 추가가 곧 구버전 호환 파괴가 된다.)
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        trainerName = try c.decode(String.self, forKey: .trainerName)
        speciesID = try c.decode(Int.self, forKey: .speciesID)
        team = try c.decode(BattleTeam.self, forKey: .team)
        isReady = try c.decode(Bool.self, forKey: .isReady)
        isHost = try c.decode(Bool.self, forKey: .isHost)
        role = try c.decodeIfPresent(LobbyRole.self, forKey: .role) ?? .runner
        // 신고 잔액은 상대가 채우는 값이다 — 베팅 상한 검사가 이 값을 보므로 여기서 자른다.
        reportedStarPieces = min(SaveTransfer.maxTokenValue,
                                 max(0, try c.decodeIfPresent(Int.self, forKey: .reportedStarPieces) ?? 0))
    }
}

enum LobbyError: Error, Equatable {
    case runnersFull, spectatorsFull, duplicate, invalidCapacity, hostCannotLeave, unsupportedRole
}

/// 네트워크와 분리된 2~4인 로비 규칙. 호스트가 단일 진실 공급원으로 이 상태를 갱신한다.
struct MultiplayerLobby: Codable, Sendable, Equatable {
    static let quizCapacity = 10
    private(set) var participants: [LobbyParticipant]
    let capacity: Int
    let activity: RoomActivity
    init(host: LobbyParticipant, capacity: Int = 4, activity: RoomActivity = .battle) throws {
        let allowed: Bool
        switch activity {
        case .pokemonQuiz: allowed = (2...Self.quizCapacity).contains(capacity)
        case .tournament: allowed = (2...8).contains(capacity)
        // 체육관은 관장 1 + 도전자 1 이 한 판이다. 남는 자리는 전부 관전자 몫이라 러너 정원은 둘이다.
        case .gym: allowed = capacity == 2
        default: allowed = (2...4).contains(capacity)
        }
        guard allowed else { throw LobbyError.invalidCapacity }
        var host = host; host.isHost = true
        participants = [host]; self.capacity = capacity; self.activity = activity
    }
    static let spectatorCapacity = 8

    /// 경기·전투에 참여하는 참가자. 게임플레이 판정은 전부 이 목록만 본다.
    var runners: [LobbyParticipant] { participants.filter { $0.role == .runner } }
    var spectators: [LobbyParticipant] { participants.filter { $0.role == .spectator } }

    var mode: MultiplayerBattleMode {
        runners.allSatisfy { $0.team == .solo } ? .freeForAll : .teams
    }
    var canStart: Bool {
        let runners = self.runners
        guard runners.count >= 2, runners.allSatisfy(\.isReady) else { return false }
        if activity == .pokeathlon || activity == .pokemonQuiz { return true }
        if mode == .freeForAll { return true }
        return runners.count == 4 && runners.filter { $0.team == .red }.count == 2
            && runners.filter { $0.team == .blue }.count == 2
    }
    mutating func join(_ participant: LobbyParticipant) throws {
        guard activity != .pokemonQuiz || participant.role == .runner else { throw LobbyError.unsupportedRole }
        switch participant.role {
        case .runner: guard runners.count < capacity else { throw LobbyError.runnersFull }
        case .spectator: guard spectators.count < Self.spectatorCapacity else { throw LobbyError.spectatorsFull }
        }
        guard !participants.contains(where: { $0.id == participant.id }) else { throw LobbyError.duplicate }
        var participant = participant; participant.isHost = false; participants.append(participant)
    }
    mutating func setReady(_ ready: Bool, participantID: UUID) {
        guard let i = participants.firstIndex(where: { $0.id == participantID }) else { return }
        participants[i].isReady = ready
    }
    mutating func setTeam(_ team: BattleTeam, participantID: UUID) {
        guard let i = participants.firstIndex(where: { $0.id == participantID }) else { return }
        participants[i].team = team
        participants[i].isReady = false
    }
    mutating func leave(participantID: UUID) throws {
        guard let i = participants.firstIndex(where: { $0.id == participantID }) else { return }
        guard !participants[i].isHost else { throw LobbyError.hostCannotLeave }
        participants.remove(at: i)
    }
}
