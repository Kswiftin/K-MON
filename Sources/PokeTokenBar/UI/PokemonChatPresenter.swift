import AppKit
import SwiftUI

/// 대화 진입점. 화면은 팝오버가 그리므로 여기서 정하는 건 **어느 개체의 대화를 열지**뿐이다.
///
/// 예전엔 전용 `NSWindow` 를 띄웠다. 근거는 "팝오버가 닫히면 대화를 잃는다" 였는데 그건 절반만
/// 참이었다 — 메시지·진행 중인 왕복·승인 카드는 전부 `PokemonChatStore`(앱 소유)에 있어 뷰가
/// 해제돼도 살아남는다. 실제로 잃던 건 입력 중이던 draft 뿐이라 그건 스토어로 올렸고,
/// 응답을 못 보고 놓치는 문제는 전송 중 팝오버 고정(`PopoverPinPolicy`)이 막는다.
/// 그 대가로 설정·게임과 창이 갈라져 사용자가 창을 두 번 옮겨야 했다.
///
/// 실행기(`toolbox`)는 여기서 **한 번만** 조립한다. 도구가 붙는 자리가 화면마다 생기면
/// 승인 게이트도 화면마다 갈라진다.
@MainActor
@Observable
final class PokemonChatPresenter {
    private let store: CompanionStore
    private let navigation: PopoverNavigation
    /// 팝오버가 닫혀 있을 수 있다 — 플로팅 펫은 팝오버 밖에서 대화를 부른다.
    private let showPopover: () -> Void
    /// 대화가 실행할 수 있는 것 전부. 화면이 조립하지 않고 받아 쓴다.
    let toolbox: PokemonChatToolbox

    init(store: CompanionStore, album: PokemonMemoryAlbum, timer: FocusTimer,
         navigation: PopoverNavigation, showPopover: @escaping () -> Void) {
        self.store = store
        self.navigation = navigation
        self.showPopover = showPopover
        self.toolbox = PokemonChatToolbox(timer: timer, companion: store, album: album,
                                          lookup: PokemonChatToolbox.apiLookup)
    }

    func open(companionID: UUID) {
        guard store.ownedMons.contains(where: { $0.id == companionID }) else { return }
        // 순서가 중요하다 — 팝오버를 여는 경로가 `navigation.reset()` 을 부르므로(닫혔다 열리면
        // 항상 Home), 대화를 먼저 세우면 그 reset 이 방금 연 대화를 접는다.
        showPopover()
        navigation.chatCompanionID = companionID
        NSApp.activate(ignoringOtherApps: true)
    }
}
