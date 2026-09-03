import Foundation
import Testing
@testable import PokeTokenBar

/// 2~4인 방 배틀이 **화면에서 도달 불가**였던 #209 의 회귀 가드.
///
/// 결함은 두 겹이었다. ⓐ 방을 만드는 버튼과 방 목록이 아무 데도 안 붙어 있었고(고아 뷰),
/// ⓑ 되살릴 목록 자체가 활동을 안 가려 GYM·TOUR·RAID 방까지 "배틀 방" 으로 뜬다.
/// 여기서는 ⓑ 와 라우팅을 순수 함수로 고정한다 — ⓐ 는 `AdventureClaimTests` 의 도달성 가드가 본다.
@Suite struct RoomBattleReachabilityTests {

    // MARK: 목록 필터

    /// 접두는 **개설과 목록이 같은 값을 읽어야 한다.** 한쪽만 바꾸면 만든 방이 어느 목록에도
    /// 안 뜬다 — 방 배틀이 정확히 그 상태로 세 주를 보냈다.
    @Test func everyActivityHasTheSamePrefixItAdvertises() {
        #expect(LANRoomList.prefix(for: .battle) == "BATTLE")
        #expect(LANRoomList.prefix(for: .pokeathlon) == "RUN")
        #expect(LANRoomList.prefix(for: .pokemonQuiz) == "QUIZ")
        #expect(LANRoomList.prefix(for: .tournament) == "TOUR")
        // 체육관·레이드는 이름 생성기가 따로 있다 — 접두 상수를 두 곳에 적지 않는다.
        #expect(LANRoomList.prefix(for: .gym) == PlayerGym.roomNamePrefix)
        #expect(LANRoomList.prefix(for: .raid) == RaidRoomName.prefix)
    }

    /// 배틀 목록은 **배틀 방만** 보여준다. 안 거르면 레이드 방에 "참가" 가 눌리고,
    /// 붙은 게스트는 자기가 누른 적 없는 협동전 화면으로 끌려간다.
    @Test func battleListShowsOnlyBattleRooms() {
        let mine = "abc123"
        #expect(LANRoomList.isVisible("BATTLE · 현우 #def456", activity: .battle, myTag: mine))
        #expect(!LANRoomList.isVisible("RAID · 5★ · 현우 #def456", activity: .battle, myTag: mine))
        #expect(!LANRoomList.isVisible("TOUR · 현우 #def456", activity: .battle, myTag: mine))
        #expect(!LANRoomList.isVisible("GYM · 1730000000 · v15 · 현우 #def456",
                                       activity: .battle, myTag: mine))
        #expect(!LANRoomList.isVisible("RUN · 현우 #def456", activity: .battle, myTag: mine))
        #expect(!LANRoomList.isVisible("QUIZ · 현우 #def456", activity: .battle, myTag: mine))
    }

    /// 접두가 **다른 접두의 앞부분**이어도 새면 안 된다. `RUN` 과 `RUNNER`, `QUIZ` 와 `QUIZZES`
    /// 처럼 구분자 없이 비교하면 옆 활동이 섞인다.
    @Test func prefixMatchRequiresTheSeparator() {
        #expect(!LANRoomList.isVisible("BATTLEROYALE · 현우 #def456", activity: .battle, myTag: "abc123"))
        #expect(!LANRoomList.isVisible("BATTLE현우 #def456", activity: .battle, myTag: "abc123"))
    }

    /// **내 방은 내 목록에 안 뜬다.** 자기 방에 "참가" 를 누르면 개설 국면이라 조용히 거절되고,
    /// 사용자에게는 눌러도 아무 일이 없는 버튼으로 보인다. 체육관·레이드만 이걸 걸렀다.
    @Test func myOwnRoomNeverAppearsInMyList() {
        let mine = "abc123"
        #expect(!LANRoomList.isVisible("BATTLE · 나 #abc123", activity: .battle, myTag: mine))
        #expect(!LANRoomList.isVisible("TOUR · 나 #abc123", activity: .tournament, myTag: mine))
        #expect(!LANRoomList.isVisible("RUN · 나 #abc123", activity: .pokeathlon, myTag: mine))
        #expect(!LANRoomList.isVisible("QUIZ · 나 #abc123", activity: .pokemonQuiz, myTag: mine))
        // 꼬리표가 다르면 남의 방이다.
        #expect(LANRoomList.isVisible("BATTLE · 현우 #abc124", activity: .battle, myTag: mine))
    }

    // MARK: 로비 전환

    /// 방 배틀 화면은 **자기 활동의 방만** 로비로 그린다. 레이드·체육관 방이 켜져 있는데
    /// 여기가 로비를 그리면 화면은 방 배틀인데 뒤에서는 다른 판이 돈다.
    @Test func lobbyIsDrawnOnlyForBattleRooms() {
        #expect(RoomBattleView.showsLobby(phase: .hosting, activity: .battle, initiatedHere: true))
        #expect(RoomBattleView.showsLobby(phase: .battling, activity: .battle, initiatedHere: true))
        #expect(!RoomBattleView.showsLobby(phase: .hosting, activity: .raid, initiatedHere: true))
        #expect(!RoomBattleView.showsLobby(phase: .battling, activity: .raid, initiatedHere: true))
        #expect(!RoomBattleView.showsLobby(phase: .hosting, activity: .gym, initiatedHere: true))
        #expect(!RoomBattleView.showsLobby(phase: .tournament, activity: .tournament, initiatedHere: true))
        // 활동이 온 뒤에는 누가 열었는지와 무관하다 — 활동만 본다.
        #expect(RoomBattleView.showsLobby(phase: .hosting, activity: .battle, initiatedHere: false))
    }

    /// 방이 없으면 모집 화면이다.
    @Test func idleShowsTheRecruitingScreen() {
        #expect(!RoomBattleView.showsLobby(phase: .idle, activity: nil, initiatedHere: true))
        // 활동이 남아 있어도 국면이 idle 이면 방이 없는 것이다(`leaveRoom` 직후).
        #expect(!RoomBattleView.showsLobby(phase: .idle, activity: .battle, initiatedHere: true))
    }

    /// **개설·참가 중에는 활동을 아직 모른다** — 로비가 `await` 뒤에 온다. 그 사이 모집
    /// 화면으로 되돌리면 방금 누른 "방 만들기" 가 아무 일도 안 한 것처럼 보인다.
    @Test func creatingAndJoiningHoldTheLobbyBeforeTheActivityArrives() {
        #expect(RoomBattleView.showsLobby(phase: .creating, activity: nil, initiatedHere: true))
        #expect(RoomBattleView.showsLobby(phase: .joining("현우"), activity: nil, initiatedHere: true))
    }

    /// **내가 연 방이 아니면 로비를 그리지 않는다.** 모집 화면을 보는 동안 체육관 코디네이터가
    /// `createGymRoom()` 을 부르면 국면만 `.creating` 이 된다 — 국면만 보면 사용자가 연 적 없는
    /// 체육관 방에 대고 "방을 만드는 중…" 을 그린다.
    @Test func aRoomOpenedElsewhereDoesNotDrawThisLobby() {
        #expect(!RoomBattleView.showsLobby(phase: .creating, activity: nil, initiatedHere: false))
        #expect(!RoomBattleView.showsLobby(phase: .joining("현우"), activity: nil, initiatedHere: false))
    }

    // MARK: 친구 탭 라우팅

    /// 국면만 보면 **토너먼트가 아닌 방까지 토너먼트 화면이 삼킨다.** 활동 종류로 가른다.
    @Test func friendTabRoutesEachRoomActivityToItsOwnScreen() {
        #expect(FriendView.destination(forRoom: .battle) == .roomBattle)
        #expect(FriendView.destination(forRoom: .tournament) == .tournament)
        #expect(FriendView.destination(forRoom: .gym) == .gym)
    }

    /// 친구 탭이 **관여하지 않는** 활동은 nil 이다. 레이드는 팝오버 오버레이(`nav.showRaid`),
    /// 포켓애슬론·퀴즈는 챌린지 탭이 그린다 — 여기서 잡으면 그 화면들이 친구 탭에 갇힌다.
    @Test func friendTabDoesNotClaimRoomsThatLiveElsewhere() {
        #expect(FriendView.destination(forRoom: .raid) == nil)
        #expect(FriendView.destination(forRoom: .pokeathlon) == nil)
        #expect(FriendView.destination(forRoom: .pokemonQuiz) == nil)
        #expect(FriendView.destination(forRoom: nil) == nil)
    }

    /// **체육관 방은 친구 탭을 붙잡지 않는다.** 관장은 도전을 기다리는 배경 상태지 배틀 중이
    /// 아니다 — 방이 떠 있다는 이유로 화면을 잡으면 교환도 1:1 배틀도 방 배틀도 못 하고,
    /// 닫기를 눌러도 조건이 계속 참이라 안 나가진다.
    ///
    /// `body` 와 `onAppear` 가 **이 함수 하나만** 읽는다. 두 곳에 따로 적어서 한쪽만 체육관을
    /// 빼먹은 것이 결함이었다.
    @Test func aGymRoomNeverHoldsTheFriendTab() {
        #expect(FriendView.screenHeldByRoom(.gym) == nil)
        #expect(FriendView.screenHeldByRoom(.battle) == .roomBattle)
        #expect(FriendView.screenHeldByRoom(.tournament) == .tournament)
        #expect(FriendView.screenHeldByRoom(.raid) == nil)
        #expect(FriendView.screenHeldByRoom(nil) == nil)
    }

    // MARK: 실제 광고 이름 왕복

    /// **손으로 쓴 문자열이 아니라 광고에 실리는 이름 그대로**를 거른다. 구분자·대소문자·`#`
    /// 위치가 생성기와 어긋나면 목록이 통째로 비는데, 픽스처만 검사하면 그 어긋남이 안 보인다.
    @Test func namesFromTheRealGeneratorsRoundTripThroughTheFilter() {
        let mine = "ABC123"
        let theirs = "DEF456"

        // 배틀·토너먼트·포켓애슬론·퀴즈는 `startHosting` 의 일반 경로를 탄다.
        for activity in [RoomActivity.battle, .tournament, .pokeathlon, .pokemonQuiz] {
            let prefix = LANRoomList.prefix(for: activity)
            let theirRoom = LANServiceName.make(base: "\(prefix) · 현우", suffix: "#\(theirs)")
            let myRoom = LANServiceName.make(base: "\(prefix) · 나", suffix: "#\(mine)")
            #expect(LANRoomList.isVisible(theirRoom, activity: activity, myTag: mine))
            #expect(!LANRoomList.isVisible(myRoom, activity: activity, myTag: mine))
            // 다른 활동의 목록에는 안 뜬다.
            let other: RoomActivity = activity == .battle ? .tournament : .battle
            #expect(!LANRoomList.isVisible(theirRoom, activity: other, myTag: mine))
        }

        // 체육관·레이드는 자기 이름 생성기를 탄다 — 그쪽이 붙이는 접두도 같은 표를 읽어야 한다.
        let gym = PlayerGymRoomName.make(leaderName: "현우", idTag: theirs, heldSince: Date())
        #expect(LANRoomList.isVisible(gym, activity: .gym, myTag: mine))
        #expect(!LANRoomList.isVisible(gym, activity: .battle, myTag: mine))
        #expect(!LANRoomList.isVisible(PlayerGymRoomName.make(leaderName: "나", idTag: mine,
                                                              heldSince: Date()),
                                       activity: .gym, myTag: mine))

        let raid = RaidRoomName.make(trainerName: "현우", idTag: theirs, tier: .five)
        #expect(LANRoomList.isVisible(raid, activity: .raid, myTag: mine))
        #expect(!LANRoomList.isVisible(raid, activity: .battle, myTag: mine))
        #expect(!LANRoomList.isVisible(RaidRoomName.make(trainerName: "나", idTag: mine, tier: .five),
                                       activity: .raid, myTag: mine))
    }

    // MARK: 활동 판정은 한 표에서만

    /// 방 종류를 묻는 곳이 **저마다 접두를 다시 적으면** 한쪽만 바뀐 순간 갈라진다. 체육관·
    /// 레이드의 기존 술어도 같은 표를 읽는지 고정한다.
    @Test func everyRoomKindPredicateReadsTheSingleTable() {
        let gym = PlayerGymRoomName.make(leaderName: "현우", idTag: "DEF456", heldSince: Date())
        let raid = RaidRoomName.make(trainerName: "현우", idTag: "DEF456", tier: .three)
        let battle = LANServiceName.make(base: "BATTLE · 현우", suffix: "#DEF456")

        #expect(PlayerGym.isGymRoomName(gym) == LANRoomList.matches(gym, activity: .gym))
        #expect(PlayerGym.isGymRoomName(raid) == LANRoomList.matches(raid, activity: .gym))
        #expect(RaidRoomName.isRaidRoomName(raid) == LANRoomList.matches(raid, activity: .raid))
        #expect(RaidRoomName.isRaidRoomName(gym) == LANRoomList.matches(gym, activity: .raid))
        #expect(LANRoomList.matches(battle, activity: .battle))
        #expect(!LANRoomList.matches(battle, activity: .tournament))
    }

    /// `matches` 는 **내 방인지 안 본다** — 참가 직전에 "이 방이 무슨 방인가" 를 묻는 자리
    /// (`MultiplayerRoomCenter.join`)에서는 내 방 여부가 답을 바꾸면 안 된다.
    @Test func matchesIgnoresOwnership() {
        let mine = LANServiceName.make(base: "TOUR · 나", suffix: "#ABC123")
        #expect(LANRoomList.matches(mine, activity: .tournament))
        #expect(!LANRoomList.isVisible(mine, activity: .tournament, myTag: "ABC123"))
    }
}
