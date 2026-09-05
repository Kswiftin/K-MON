import XCTest
@testable import PokeTokenBar

// 팝오버 내비게이션 리셋 계약 — 닫혔다 열릴 때 AppDelegate.togglePopover 가 reset()을 불러
// 항상 Home 으로 돌아가게 한다(설정 화면 잔류 방지).
@MainActor
final class PopoverNavigationTests: XCTestCase {
    // MARK: 알림 탭 → 어디로 가는가

    /// 집중 체인 알림을 누르면 **집중 타이머가 있는 화면**으로 가야 한다.
    ///
    /// 알림마다 목적지가 다르다는 것을 지금까지 아무도 안 봤다 — `didReceive` 는 종류를 안 보고
    /// 전부 `goToBattle()` 로 보냈고(주석도 "배틀 신청이면" 이라고 전제한다), 그때는 알림이 죄다
    /// 배틀·레이드 계열이라 우연히 맞았다. 체인 알림은 **누르면 시작하라는 뜻**이라 그 전제가
    /// 처음으로 깨진다: 대전 탭엔 시작 버튼이 없어서, 알림을 눌러 앱을 연 사용자가 정작 다음
    /// 세션을 시작할 수 없다.
    func testTheFocusChainNotificationOpensTheFocusTimerNotTheBattleTab() {
        XCTAssertEqual(PopoverNavigation.destination(forNotificationID: "\(FocusChainRules.notificationIDPrefix)-1"),
                       .focusTimer)
    }

    /// 나머지는 지금까지 하던 대로 대전 화면이다 — 이 변경으로 배틀 신청 흐름이 바뀌면 안 된다.
    func testOtherNotificationsStillOpenTheBattleTab() {
        for id in ["raid-room-abc", "raid-hatch-2", "gym-battle-\(UUID().uuidString)",
                   "private-message-trade-1", "companion-event-7"] {
            XCTAssertEqual(PopoverNavigation.destination(forNotificationID: id), .battle, id)
        }
    }

    /// 목적지가 정해지면 그 화면이 실제로 열려야 한다 — 오버레이가 덮고 있으면 접는다.
    /// 체육관을 열어 둔 채 알림을 누르면 시작 버튼이 오버레이 뒤에 가려진다.
    func testGoingToTheFocusTimerFoldsWhateverOverlayWasCovering() {
        let nav = PopoverNavigation()
        nav.showGymLeague = true
        nav.tab = .battle
        nav.goToFocusTimer()
        XCTAssertFalse(nav.showGymLeague)
        XCTAssertEqual(nav.tab, .home, "집중 타이머는 홈 탭에 있다")
    }

    func testDefaultsToHome() {
        let nav = PopoverNavigation()
        XCTAssertFalse(nav.showSettings)
        XCTAssertEqual(nav.tab, .home)
    }

    func testResetReturnsToHomeFromSettings() {
        let nav = PopoverNavigation()
        nav.showSettings = true
        nav.tab = .collection
        nav.reset()
        XCTAssertFalse(nav.showSettings)   // 설정 화면 닫힘
        XCTAssertEqual(nav.tab, .home)     // 탭도 Home 으로
    }

    /// 던전(#79)은 설정·체육관과 같은 층이다 — 배틀 신청이 오면 접혀야 하고 `reset()` 이 닫아야 한다.
    /// 접히지 않으면 신청이 온 줄 모른 채 던전만 보게 된다(체육관에서 겪은 그 함정).
    func testDungeonOverlayFoldsWithTheOthers() {
        let nav = PopoverNavigation()
        nav.showDungeon = true
        nav.goToBattle()
        XCTAssertFalse(nav.showDungeon)
        XCTAssertEqual(nav.tab, .battle)

        nav.showDungeon = true
        nav.reset()
        XCTAssertFalse(nav.showDungeon)
        XCTAssertEqual(nav.tab, .home)
    }

    func testGymBattleKeepsTheChallengeOverlay() {
        let nav = PopoverNavigation()
        nav.showDungeon = true

        nav.goToGymBattle()

        XCTAssertTrue(nav.showGymLeague)
        XCTAssertFalse(nav.showDungeon)
        XCTAssertEqual(nav.tab, .challenge)
    }

    /// 대화도 같은 오버레이 층이다(별도 창 → 팝오버 이관). 접히는 자리를 한 곳만 고치면 나머지
    /// 경로에서 대화가 덮인 채 남아, 배틀 신청이 와도 신청 화면 대신 대화만 보게 된다 —
    /// 던전이 겪은 그 함정이다. 세 경로를 **각각** 밟는다.
    func testChatOverlayFoldsWithTheOthers() {
        let nav = PopoverNavigation()
        let companion = UUID()

        nav.chatCompanionID = companion
        nav.goToBattle()
        XCTAssertNil(nav.chatCompanionID)
        XCTAssertEqual(nav.tab, .battle)

        nav.chatCompanionID = companion
        nav.goToGymBattle()
        XCTAssertNil(nav.chatCompanionID)

        nav.chatCompanionID = companion
        nav.reset()
        XCTAssertNil(nav.chatCompanionID)
        XCTAssertEqual(nav.tab, .home)
    }

    /// 대화를 여는 자리도 **형제 오버레이를 접어야** 한다. 화면 체인이 설정·체육관·던전·꾸미기를
    /// 먼저 보므로, 접지 않고 `chatCompanionID` 만 세우면 아무 일도 안 일어난 것처럼 보이고
    /// (플로팅 펫에서 부르면 죽은 클릭) 나중에 그 오버레이를 닫는 순간 대화가 불쑥 되살아난다.
    func testGoToChatFoldsTheSiblingOverlays() {
        let nav = PopoverNavigation()
        let companion = UUID()
        nav.showSettings = true
        nav.showGymLeague = true
        nav.showDungeon = true
        nav.showOutfit = true

        nav.goToChat(companionID: companion)

        XCTAssertEqual(nav.chatCompanionID, companion)
        XCTAssertFalse(nav.showSettings)
        XCTAssertFalse(nav.showGymLeague)
        XCTAssertFalse(nav.showDungeon)
        XCTAssertFalse(nav.showOutfit)
    }

    /// 주간 회고(마일스톤 4)도 같은 오버레이 층이다 — 설정·체육관·던전·꾸미기·대화와 나란히 뜬다.
    ///
    /// **네 경로를 각각 밟는다.** 접는 자리를 한 곳만 고치면 나머지에서 회고가 덮인 채 남고,
    /// 그러면 배틀 신청이 와도 신청 화면 대신 지난주 막대그래프만 보게 된다 — 던전과 대화가
    /// 이미 겪은 그 함정이다(`goToChat` 주석).
    ///
    /// `goToFocusTimer()` 를 함께 보는 이유: 체인 알림을 누른 사용자가 원하는 것은 **시작 버튼**인데,
    /// 회고가 그 버튼을 정확히 덮는 자리에 뜬다.
    func testFocusRecapOverlayFoldsWithTheOthers() {
        let nav = PopoverNavigation()

        nav.showFocusRecap = true
        nav.goToBattle()
        XCTAssertFalse(nav.showFocusRecap, "배틀 신청이 왔는데 회고가 덮고 있다")
        XCTAssertEqual(nav.tab, .battle)

        nav.showFocusRecap = true
        nav.goToChat(companionID: UUID())
        XCTAssertFalse(nav.showFocusRecap, "대화를 열었는데 회고가 위에 남았다")

        nav.showFocusRecap = true
        nav.goToFocusTimer()
        XCTAssertFalse(nav.showFocusRecap, "체인 알림을 눌렀는데 회고가 시작 버튼을 덮고 있다")
        XCTAssertEqual(nav.tab, .home)

        nav.showFocusRecap = true
        nav.reset()
        XCTAssertFalse(nav.showFocusRecap, "팝오버를 닫았다 열었는데 회고가 남아 있다")
        XCTAssertEqual(nav.tab, .home)
    }

    /// 대화 상대가 놓아주기·교환·졸업으로 사라지면 오버레이를 접는다. 안 접으면 이름이 `?` 이고
    /// 스프라이트가 빈 화면에 전송 버튼만 살아 있고, 보내면 죽은 UUID 로 세션이 새로 생겨
    /// 다음 `prune` 까지 디스크에 남는다. 여는 시점의 검사만으로는 이 구간을 못 덮는다.
    func testChatOverlayDropsWhenItsCompanionIsGone() {
        let nav = PopoverNavigation()
        let gone = UUID(), stillHere = UUID()

        nav.goToChat(companionID: gone)
        nav.dropChatIfCompanionIsGone(ownedIDs: [stillHere])
        XCTAssertNil(nav.chatCompanionID)

        nav.goToChat(companionID: stillHere)
        nav.dropChatIfCompanionIsGone(ownedIDs: [stillHere])
        XCTAssertEqual(nav.chatCompanionID, stillHere)
    }
}

/// 팝오버 고정은 이제 **둘**이 원한다 — 배틀(일하면서 대전)과 대화(전송 중 왕복).
/// 각자 `.transient` 로 되돌리면 나중에 끝난 쪽이 아직 진행 중인 쪽의 고정을 풀어 버린다.
/// 그래서 되돌림 판정을 여기 한 곳에만 두고, 부르는 자리는 플래그를 넘기기만 한다.
@MainActor
final class PopoverPinPolicyTests: XCTestCase {
    /// 붙드는 이유는 **대화 전송 하나뿐**이다. 배틀은 붙들지 않는다 — 급히 화면을 치워야 할 때
    /// 닫히지 않으면 곤란하고, 배틀은 창을 닫아도 살아 있어 다시 열면 이어진다.
    func testOnlyChatSendingPinsThePopover() {
        XCTAssertEqual(PopoverPinPolicy.behavior(chatSending: true, chatVisible: true),
                       .applicationDefined)
    }

    /// 고정하는 이유는 "답이 오는 걸 보게 하려고" 다. 사용자가 대화를 닫았으면 볼 것이 없으므로
    /// 붙들 이유도 없다 — 안 풀면 화면에 아무 설명 없이 바깥 클릭이 먹통이 된다.
    func testClosingTheChatWhileStillSendingReleasesThePin() {
        XCTAssertEqual(PopoverPinPolicy.behavior(chatSending: true, chatVisible: false),
                       .transient)
    }

    func testNoReasonReturnsToTransient() {
        XCTAssertEqual(PopoverPinPolicy.behavior(chatSending: false, chatVisible: false),
                       .transient)
    }
}
