import Foundation

enum BattleTeam: String, Codable, Sendable { case solo, red, blue }
struct LobbyParticipant: Codable, Sendable, Equatable, Identifiable {
    let id: UUID
    var trainerName: String
    var speciesID: Int
    var team: BattleTeam
    var isReady: Bool
    var isHost: Bool
}
enum LobbyError: Error, Equatable { case full, duplicate, invalidCapacity, hostCannotLeave }

/// 네트워크와 분리된 2~4인 로비 규칙. 호스트가 단일 진실 공급원으로 이 상태를 갱신한다.
struct MultiplayerLobby: Codable, Sendable, Equatable {
    private(set) var participants: [LobbyParticipant]
    let capacity: Int
    init(host: LobbyParticipant, capacity: Int = 4) throws {
        guard (2...4).contains(capacity) else { throw LobbyError.invalidCapacity }
        var host = host; host.isHost = true
        participants = [host]; self.capacity = capacity
    }
    var mode: MultiplayerBattleMode {
        participants.allSatisfy { $0.team == .solo } ? .freeForAll : .teams
    }
    var canStart: Bool {
        guard participants.count >= 2, participants.allSatisfy(\.isReady) else { return false }
        if mode == .freeForAll { return true }
        return participants.count == 4 && participants.filter { $0.team == .red }.count == 2
            && participants.filter { $0.team == .blue }.count == 2
    }
    mutating func join(_ participant: LobbyParticipant) throws {
        guard participants.count < capacity else { throw LobbyError.full }
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
