import Foundation

/// 배틀·체육관·레이드 상태가 바뀌었을 때 메뉴바 팝오버를 앱이 스스로 열어도 되는지 정한다.
///
/// 사용자가 직접 메뉴바 아이콘·전역 단축키·알림을 누르는 동작은 여기서 막지 않는다. 이 정책은
/// 오직 이벤트가 앱을 앞에 내세우는 자동 열기 경로에만 적용한다.
enum BattleWindowPresentationPolicy {
    static func shouldOpenAutomatically(automaticOpeningEnabled: Bool,
                                        terminalControlling: Bool,
                                        wantsForegroundWindow: Bool) -> Bool {
        automaticOpeningEnabled && !terminalControlling && wantsForegroundWindow
    }
}
