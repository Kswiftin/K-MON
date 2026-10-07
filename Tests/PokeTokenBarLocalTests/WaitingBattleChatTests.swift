import AppKit
import Foundation
import SwiftUI
import Testing
@testable import PokeTokenBar

@MainActor
@Suite(.serialized)
struct WaitingBattleChatTests {
    private func makeCenter() -> BattleCenter {
        BattleCenter(companion: CompanionStore(
            clock: { Date(timeIntervalSince1970: 1_700_000_000) },
            fileURL: storeFixtureStateURL("waiting-chat")))
    }

    private func request(waitingSupported: Bool?) throws -> NetMessage {
        let request = NetMessage.request(trainer: "상대", teamSize: 1, seed: 42,
                                         profile: BattleRankProfile(rank: BattleRank(points: 0), stardust: 0),
                                         rulesVersion: BattleEngine.rulesVersion,
                                         chatSupported: true, kind: .regular)
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
        var payload = try #require(object["request"] as? [String: Any])
        if let waitingSupported { payload["waitingChatSupported"] = waitingSupported }
        object["request"] = payload
        return try JSONDecoder().decode(NetMessage.self, from: JSONSerialization.data(withJSONObject: object))
    }

    private func incoming(waitingSupported: Bool?) throws -> BattleCenter {
        let previous = UserDefaults.standard.object(forKey: "doNotDisturb")
        UserDefaults.standard.set(false, forKey: "doNotDisturb")
        defer {
            if let previous { UserDefaults.standard.set(previous, forKey: "doNotDisturb") }
            else { UserDefaults.standard.removeObject(forKey: "doNotDisturb") }
        }
        let center = makeCenter()
        center.handle(try request(waitingSupported: waitingSupported))
        return center
    }

    private func snapshot() -> BattleSnapshot {
        BattleSnapshot(speciesID: 1, name: "이상해씨", trainer: "트레이너", level: 50,
                       nature: nil, isShiny: false, types: [.normal],
                       base: BattleStats(hp: 100, atk: 100, def: 100, spa: 100, spd: 100, spe: 80),
                       moves: [MoveSpec(id: 1, names: ["ko": "몸통박치기"], type: .normal, power: 20,
                                        damageClass: .physical, accuracy: nil, pp: 20)])
    }

    private func room(role: LobbyRole = .runner, activity: RoomActivity = .battle,
                      center suppliedCenter: MultiplayerRoomCenter? = nil) throws -> (MultiplayerRoomCenter, MultiplayerLobby) {
        let center = suppliedCenter ?? MultiplayerRoomCenter(companion: CompanionStore(
            clock: { Date(timeIntervalSince1970: 1_700_000_000) },
            fileURL: storeFixtureStateURL("waiting-room-chat")))
        let host = LobbyParticipant(id: UUID(), trainerName: "방장", speciesID: 1,
                                    team: .solo, isReady: true, isHost: true)
        let capacity = activity == .raid ? MultiplayerLobby.raidCapacity : (activity == .gym ? 2 : 4)
        var lobby = try MultiplayerLobby(host: host, capacity: capacity, activity: activity)
        try lobby.join(LobbyParticipant(id: center.myID, trainerName: "내 이름", speciesID: 1,
                                         team: .solo, isReady: true, isHost: false, role: role))
        center.applyGuestLobby(lobby)
        return (center, lobby)
    }

    // 배틀 중으로만 한정된 가드가 되살아나면 수락·편성 중 대화가 사라진다.
    @Test func supportedPeersCanTalkThroughoutTheWaitingFlow() throws {
        let phases: [BattleCenter.Phase] = [
            .incoming(peer: "상대"), .poolSelecting(peer: "상대"), .poolBuilding(peer: "상대"),
            .teamBuilding(peer: "상대"), .waitingTeam(peer: "상대"), .preparing,
        ]
        for phase in phases {
            let center = try incoming(waitingSupported: true)
            defer { center.phase = .ready }
            center.phase = phase
            center.sendChat("  잘 부탁해요  ")
            center.handle(.chat(BattleChatMessage(senderID: UUID(), senderName: "상대", body: "반가워요")))
            #expect(center.chatMessages.map(\.body) == ["잘 부탁해요", "반가워요"], "\(phase)")
        }
    }

    @Test func battleChatSupportAloneDoesNotEnableWaitingChat() throws {
        for supported in [nil, false] as [Bool?] {
            let center = try incoming(waitingSupported: supported)
            defer { center.phase = .ready }
            center.sendChat("전송하면 안 됨")
            center.handle(.chat(BattleChatMessage(senderID: UUID(), senderName: "상대", body: "수신하면 안 됨")))
            #expect(!center.chatIsAvailable)
            #expect(center.chatMessages.isEmpty)
        }
    }

    @Test func challengerWaitsForTheWaitingChatAcknowledgement() throws {
        let center = makeCenter()
        defer { center.phase = .ready }
        center.phase = .challenging(peer: "상대")
        center.sendChat("아직 확인 중")
        #expect(center.chatMessages.isEmpty)
        // 상대가 수락하기 전에 지원 여부를 답한다. 구버전에는 이 프레임을 보내지 않는다.
        let acknowledgement = try #require(try? JSONDecoder().decode(
            NetMessage.self, from: Data(#"{"waitingChatReady":{}}"#.utf8)))
        center.handle(try JSONDecoder().decode(NetMessage.self, from: JSONEncoder().encode(acknowledgement)))
        center.sendChat("대기 중 인사")
        #expect(center.chatMessages.map(\.body) == ["대기 중 인사"])
        center.cancelChallenge()
        #expect(center.chatMessages.isEmpty)
        #expect(!center.chatIsAvailable)
    }

    @Test func waitingChatKeepsInputValidationAndSeparateSenderLimits() throws {
        let center = try incoming(waitingSupported: true)
        defer { center.phase = .ready }
        center.sendChat("   ")
        center.sendChat(String(repeating: "가", count: 201))
        for number in 1...4 {
            center.sendChat("내 말 \(number)")
            center.handle(.chat(BattleChatMessage(senderID: center.chatSenderID, senderName: "상대",
                                                  body: "상대 말 \(number)")))
        }
        #expect(center.chatMessages.map(\.body) == ["내 말 1", "상대 말 1", "내 말 2", "상대 말 2", "내 말 3", "상대 말 3"])
        let remote = try #require(center.chatMessages.first { $0.body == "상대 말 1" })
        #expect(remote.senderID != center.chatSenderID)
        center.cancelChallenge()
        #expect(center.chatMessages.isEmpty)
    }

    @Test func waitingCapabilitySurvivesTheWireRoundTrip() throws {
        let decoded = try request(waitingSupported: true)
        let object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(decoded)) as? [String: Any])
        let payload = try #require(object["request"] as? [String: Any])
        #expect(payload["waitingChatSupported"] as? Bool == true)
    }

    @Test func roomWaitingCapabilitySurvivesTheLobbyRoundTrip() throws {
        let host = LobbyParticipant(id: UUID(), trainerName: "방장", speciesID: 1,
                                    team: .solo, isReady: false, isHost: true)
        let lobby = try MultiplayerLobby(host: host)
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(lobby)) as? [String: Any])
        object["waitingChatSupported"] = true
        let decoded = try JSONDecoder().decode(MultiplayerLobby.self, from: JSONSerialization.data(withJSONObject: object))
        let encoded = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(decoded)) as? [String: Any])
        #expect(encoded["waitingChatSupported"] as? Bool == true)
    }

    @Test func battleStartKeepsTheWaitingConversationAndRateLimit() throws {
        let center = try incoming(waitingSupported: true)
        defer { center.phase = .ready }
        for body in ["대기 1", "대기 2", "대기 3"] { center.sendChat(body) }
        center.beginBattle(my: [snapshot()], opp: [snapshot()], iAmA: false, seed: 42)
        #expect(center.phase == .battling)
        #expect(center.chatMessages.map(\.body) == ["대기 1", "대기 2", "대기 3"])
        center.sendChat("배틀 전환으로 도배 제한을 우회하면 안 됨")
        #expect(center.chatMessages.count == 3)
        center.forfeit()
        center.dismissResult()
        #expect(center.chatMessages.isEmpty)
    }

    @Test func roomRunnersAndSpectatorsCanTalkWhileWaiting() throws {
        for role in [LobbyRole.runner, .spectator] {
            let (center, _) = try room(role: role)
            defer { center.leaveRoom() }
            let original = BattleChatMessage(senderID: center.myID, senderName: "위조 이름", body: "안녕하세요")
            center.acceptChat(original, from: center.myID)
            #expect(center.chatMessages.map(\.body) == ["안녕하세요"])
            #expect(center.chatMessages.first?.senderName == "내 이름")
            #expect(center.chatMessages.first?.id != original.id)
            center.leaveRoom()
            #expect(center.chatMessages.isEmpty)
            #expect(!center.chatIsAvailable)
        }
    }

    @Test(arguments: RoomActivity.allCases)
    func roomWaitingChatRejectsUnknownSendersAndFloods(activity: RoomActivity) throws {
        let (center, _) = try room(activity: activity)
        defer { center.leaveRoom() }
        let stranger = UUID()
        center.acceptChat(BattleChatMessage(senderID: stranger, senderName: "외부인", body: "안 됨"), from: stranger)
        center.acceptChat(BattleChatMessage(senderID: stranger, senderName: "위조", body: "안 됨"), from: center.myID)
        center.acceptChat(BattleChatMessage(senderID: center.myID, senderName: "나", body: "   "), from: center.myID)
        center.acceptChat(BattleChatMessage(senderID: center.myID, senderName: "나", body: String(repeating: "가", count: 201)), from: center.myID)
        for number in 1...4 {
            center.acceptChat(BattleChatMessage(senderID: center.myID, senderName: "나", body: "말 \(number)"), from: center.myID)
        }
        #expect(center.chatMessages.map(\.body) == ["말 1", "말 2", "말 3"])
    }

    @Test func anOldRoomDoesNotAcceptWaitingChat() throws {
        let (center, lobby) = try room()
        defer { center.leaveRoom() }
        var payload = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(lobby)) as? [String: Any])
        payload.removeValue(forKey: "waitingChatSupported")
        center.applyGuestLobby(try JSONDecoder().decode(MultiplayerLobby.self, from: JSONSerialization.data(withJSONObject: payload)))
        center.acceptChat(BattleChatMessage(senderID: center.myID, senderName: "나", body: "안 됨"), from: center.myID)
        #expect(center.chatMessages.isEmpty)
    }

    @Test func guestBattleStartKeepsTheLobbyConversation() throws {
        let (center, lobby) = try room()
        defer { center.leaveRoom() }
        let host = try #require(lobby.participants.first { $0.isHost })
        center.acceptRelayedChat(BattleChatMessage(senderID: host.id, senderName: "방장", body: "준비되면 시작해요"))
        let fighters = lobby.runners.map { MultiplayerFighter(participant: $0, snapshot: snapshot()) }
        #expect(center.applyGuestBattleStart(seed: 42, fighters: fighters, mode: .freeForAll))
        #expect(center.phase == .battling)
        #expect(center.chatIsAvailable)
        #expect(center.combatRound == 1)
        #expect(center.chatMessages.map(\.body) == ["준비되면 시작해요"])
        center.acceptRelayedChat(BattleChatMessage(senderID: host.id, senderName: "방장", body: "시작!"))
        #expect(center.chatMessages.map(\.body) == ["준비되면 시작해요", "시작!"])
    }

    @Test func invalidGuestBattleStartStillClosesTheRoom() throws {
        let (center, _) = try room()
        #expect(!center.applyGuestBattleStart(seed: 42, fighters: [], mode: .freeForAll))
        #expect(center.phase == .idle)
        #expect(!center.chatIsAvailable)
        center.sendChat("닫힌 방에는 전송하지 않는다")
        #expect(center.chatMessages.isEmpty)
        #expect(center.lastError != nil)
    }

    @Test func raidStartKeepsTheWaitingConversationAndRateLimit() throws {
        let (center, lobby) = try room(activity: .raid)
        defer { center.leaveRoom() }
        for body in ["대기 1", "대기 2", "대기 3"] {
            center.acceptChat(BattleChatMessage(senderID: center.myID, senderName: "나", body: body), from: center.myID)
        }
        let runners = lobby.runners.map { participant in
            var participant = participant
            participant.team = .red
            return MultiplayerFighter(participant: participant, snapshot: snapshot())
        }
        // 픽스처 스토어의 날짜에 맞는 보스를 보내 실제 레이드 개시 경로를 밟는다.
        let key = RaidBoss.bossKey(at: Date(timeIntervalSince1970: 1_700_000_000), tier: .one)
        var bossSnapshot = snapshot()
        bossSnapshot.speciesID = RaidBoss.speciesID(dayKey: key, tier: .one)
        bossSnapshot.level = RaidTier.one.bossLevel
        bossSnapshot.isShiny = RaidBoss.isShinyBoss(tier: .one)
        let boss = RaidBoss.bossFighter(tier: .one, snapshot: bossSnapshot)
        #expect(center.applyGuestRaidStart(seed: 42, fighters: runners + [boss], tier: .one, periodKey: key))
        #expect(center.phase == .battling)
        #expect(center.chatMessages.map(\.body) == ["대기 1", "대기 2", "대기 3"])
        center.acceptChat(BattleChatMessage(senderID: center.myID, senderName: "나", body: "시작 후 도배"), from: center.myID)
        #expect(center.chatMessages.count == 3)
    }

    @Test func oldPeersStillCanChatOnceTheBattleStarts() throws {
        let center = try incoming(waitingSupported: nil)
        defer { center.phase = .ready }
        #expect(!center.chatIsAvailable)
        center.beginBattle(my: [snapshot()], opp: [snapshot()], iAmA: false, seed: 42)
        center.sendChat("배틀 중 채팅")
        #expect(center.chatMessages.map(\.body) == ["배틀 중 채팅"])
        center.forfeit()
        center.dismissResult()
    }

    @Test func aLateAcknowledgementCannotReopenAnEndedSession() throws {
        let center = try incoming(waitingSupported: true)
        center.sendChat("취소할 대화")
        center.cancelChallenge()
        center.handle(try JSONDecoder().decode(NetMessage.self, from: Data(#"{"waitingChatReady":{}}"#.utf8)))
        center.sendChat("종료 후 전송")
        #expect(center.phase == .ready)
        #expect(!center.showsWaitingChat)
        #expect(!center.chatIsAvailable)
        #expect(center.chatMessages.isEmpty)
        center.phase = .challenging(peer: "다음 상대")
        #expect(center.showsWaitingChat)
        #expect(!center.chatIsAvailable)
        #expect(center.chatLockMessage == nil, "지원 여부를 아직 모르면 미지원이라고 단정하지 않는다")
        center.phase = .ready
    }

    @Test func approvalKeepsTheConfirmedWaitingCapabilityAndRejectsOldPeers() throws {
        for supportsWaiting in [false, true] {
            let center = makeCenter()
            defer { center.phase = .ready }
            center.phase = .challenging(peer: "상대")
            if supportsWaiting {
                center.handle(try JSONDecoder().decode(NetMessage.self, from: Data(#"{"waitingChatReady":{}}"#.utf8)))
            }
            center.handle(.approve)
            #expect(center.chatIsAvailable == supportsWaiting)
            #expect((center.chatLockMessage == nil) == supportsWaiting)
            center.sendChat("수락 후 인사")
            #expect(center.chatMessages.map(\.body) == (supportsWaiting ? ["수락 후 인사"] : []))
        }
    }

    // 활동을 배틀로 한정하거나 지원 광고를 빠뜨리면 다른 공동 대기실에서 대화가 막힌다.
    @Test(arguments: RoomActivity.allCases)
    func everyActivityAllowsWaitingParticipantsToChat(activity: RoomActivity) throws {
        let roles: [LobbyRole] = activity == .pokemonQuiz ? [.runner] : [.runner, .spectator]
        for role in roles {
            let (center, lobby) = try room(role: role, activity: activity)
            defer { center.leaveRoom() }
            let decoded = try JSONDecoder().decode(MultiplayerLobby.self, from: JSONEncoder().encode(lobby))
            center.applyGuestLobby(decoded)
            #expect(center.chatIsAvailable)
            center.acceptChat(BattleChatMessage(senderID: center.myID, senderName: "위조 이름", body: "함께 준비해요"),
                              from: center.myID)
            #expect(center.chatMessages.map(\.body) == ["함께 준비해요"])
            #expect(center.chatMessages.first?.senderName == "내 이름")
            center.leaveRoom()
            #expect(center.chatMessages.isEmpty)
            #expect(!center.chatIsAvailable)
        }
    }

    @Test(arguments: RoomActivity.allCases)
    func unsupportedActivityLobbiesKeepWaitingChatDisabled(activity: RoomActivity) throws {
        for supported in [nil, false] as [Bool?] {
            let (center, lobby) = try room(activity: activity)
            defer { center.leaveRoom() }
            var payload = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(lobby)) as? [String: Any])
            payload["waitingChatSupported"] = supported
            center.applyGuestLobby(try JSONDecoder().decode(MultiplayerLobby.self, from: JSONSerialization.data(withJSONObject: payload)))
            #expect(!center.chatIsAvailable)
            center.acceptChat(BattleChatMessage(senderID: center.myID, senderName: "나", body: "안 됨"), from: center.myID)
            #expect(center.chatMessages.isEmpty)
        }
    }

    private func inputField(in view: NSView) -> NSTextField? {
        if let field = view as? NSTextField, field.isEditable { return field }
        return view.subviews.lazy.compactMap { inputField(in: $0) }.first
    }

    // 센터만 열고 실제 대기 화면에 패널을 연결하지 않는 누락을 잡는다.
    @Test(arguments: [RoomActivity.raid, .tournament, .gym])
    func waitingScreensShowChatAndDisableInputForOldRooms(activity: RoomActivity) async throws {
        _ = NSApplication.shared
        let store = CompanionStore(fileURL: storeFixtureStateURL("waiting-chat-view"))
        let battleCenter = BattleCenter(companion: store)
        let (center, lobby) = try room(activity: activity, center: battleCenter.multiplayer)
        defer { center.leaveRoom() }
        let content: AnyView
        if activity == .raid {
            content = AnyView(RaidView(store: store, onClose: {}).environment(battleCenter))
        } else if activity == .tournament {
            content = AnyView(PokemonTournamentView(store: store, center: center, onClose: {}))
        } else {
            content = AnyView(PlayerGymView(store: store, center: center, onClose: {})
                .environment(PlayerGymCoordinator(companion: store, rooms: center)))
        }
        let hosting = NSHostingView(rootView: content.environment(AppSettings()))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 360, height: 600),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        defer { window.close() }
        hosting.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        #expect(center.phase == .joined)
        #expect(try #require(inputField(in: hosting)).isEnabled)

        var payload = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(lobby)) as? [String: Any])
        payload.removeValue(forKey: "waitingChatSupported")
        center.applyGuestLobby(try JSONDecoder().decode(MultiplayerLobby.self, from: JSONSerialization.data(withJSONObject: payload)))
        try await Task.sleep(for: .milliseconds(100))
        #expect(try #require(inputField(in: hosting)).isEnabled == false)
        center.leaveRoom()
        try await Task.sleep(for: .milliseconds(100))
        hosting.layoutSubtreeIfNeeded()
        #expect(inputField(in: hosting) == nil, "방을 나가면 대기 채팅 입력도 사라진다")
    }

    @Test func terminalChatCommandAndWireValidateTheMessage() throws {
        let command = try PokedoroCommandParser.parse(["room", "chat", "잘", "부탁해요"])
        let action = try #require(command.request)
        #expect(action.name == "room.chat")
        #expect(action.argument == "잘 부탁해요")
        let request = PokedoroRequest(id: UUID(), action: action, requestedAt: Date())
        #expect(try JSONDecoder().decode(PokedoroRequest.self, from: JSONEncoder().encode(request)).action == action)
        #expect(PokedoroRequest.Action(name: "room.chat", argument: "   ") == nil)
        #expect(PokedoroRequest.Action(name: "room.chat", argument: String(repeating: "가", count: 201)) == nil)
        #expect(throws: PokedoroCommandError.self) {
            try PokedoroCommandParser.parse(["room", "chat", String(repeating: "가", count: 201)])
        }
        #expect(throws: PokedoroCommandError.self) {
            try PokedoroCommandParser.parse(["room", "chat", "   "])
        }
    }

    @Test(arguments: RoomActivity.allCases)
    func terminalWaitingScreenIncludesTheConversation(activity: RoomActivity) throws {
        let (center, _) = try room(activity: activity)
        defer { center.leaveRoom() }
        center.acceptChat(BattleChatMessage(senderID: center.myID, senderName: "나", body: "준비됐어요"), from: center.myID)
        let lines = RoomScreen.lines(center.terminalState, width: 80).joined(separator: "\n")
        #expect(lines.contains("내 이름: 준비됐어요"))
        #expect(lines.contains("room chat"))
    }
}
