import XCTest
@testable import PokeTokenBar

// 팝오버 내비게이션 리셋 계약 — 닫혔다 열릴 때 AppDelegate.togglePopover 가 reset()을 불러
// 항상 Home 으로 돌아가게 한다(설정 화면 잔류 방지).
@MainActor
final class PopoverNavigationTests: XCTestCase {
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
    func testEitherReasonAlonePinsThePopover() {
        XCTAssertEqual(PopoverPinPolicy.behavior(battlePinned: true, chatSending: false, chatVisible: false),
                       .applicationDefined)
        XCTAssertEqual(PopoverPinPolicy.behavior(battlePinned: false, chatSending: true, chatVisible: true),
                       .applicationDefined)
    }

    /// 트리거 브랜치: 배틀 중에 대화 전송이 **먼저** 끝나는 순간. 여기가 풀리면 일하면서 하던
    /// 배틀이 바깥 클릭 한 번에 닫힌다.
    func testChatFinishingDoesNotReleaseTheBattlePin() {
        XCTAssertEqual(PopoverPinPolicy.behavior(battlePinned: true, chatSending: true, chatVisible: true),
                       .applicationDefined)
        XCTAssertEqual(PopoverPinPolicy.behavior(battlePinned: true, chatSending: false, chatVisible: false),
                       .applicationDefined)
    }

    /// 반대 방향도 같다 — 배틀이 먼저 끝나도 전송 중인 대화는 고정을 유지한다.
    func testBattleEndingDoesNotReleaseTheChatPin() {
        XCTAssertEqual(PopoverPinPolicy.behavior(battlePinned: false, chatSending: true, chatVisible: true),
                       .applicationDefined)
    }

    /// 고정하는 이유는 "답이 오는 걸 보게 하려고" 다. 사용자가 대화를 닫았으면 볼 것이 없으므로
    /// 붙들 이유도 없다 — 안 풀면 화면에 아무 설명 없이 바깥 클릭이 먹통이 된다.
    func testClosingTheChatWhileStillSendingReleasesThePin() {
        XCTAssertEqual(PopoverPinPolicy.behavior(battlePinned: false, chatSending: true, chatVisible: false),
                       .transient)
    }

    func testNoReasonReturnsToTransient() {
        XCTAssertEqual(PopoverPinPolicy.behavior(battlePinned: false, chatSending: false, chatVisible: false),
                       .transient)
    }
}
