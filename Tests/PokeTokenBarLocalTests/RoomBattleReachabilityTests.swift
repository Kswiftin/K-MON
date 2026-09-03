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
        #expect(RoomBattleView.showsLobby(phase: .hosting, activity: .battle))
        #expect(RoomBattleView.showsLobby(phase: .battling, activity: .battle))
        #expect(!RoomBattleView.showsLobby(phase: .hosting, activity: .raid))
        #expect(!RoomBattleView.showsLobby(phase: .battling, activity: .raid))
        #expect(!RoomBattleView.showsLobby(phase: .hosting, activity: .gym))
        #expect(!RoomBattleView.showsLobby(phase: .tournament, activity: .tournament))
    }

    /// 방이 없으면 모집 화면이다.
    @Test func idleShowsTheRecruitingScreen() {
        #expect(!RoomBattleView.showsLobby(phase: .idle, activity: nil))
        // 활동이 남아 있어도 국면이 idle 이면 방이 없는 것이다(`leaveRoom` 직후).
        #expect(!RoomBattleView.showsLobby(phase: .idle, activity: .battle))
    }

    /// **개설·참가 중에는 활동을 아직 모른다** — 로비가 `await` 뒤에 온다. 그 사이 모집
    /// 화면으로 되돌리면 방금 누른 "방 만들기" 가 아무 일도 안 한 것처럼 보인다.
    @Test func creatingAndJoiningHoldTheLobbyBeforeTheActivityArrives() {
        #expect(RoomBattleView.showsLobby(phase: .creating, activity: nil))
        #expect(RoomBattleView.showsLobby(phase: .joining("현우"), activity: nil))
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
}
