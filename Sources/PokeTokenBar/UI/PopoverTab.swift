import SwiftUI

/// 팝오버가 가진 화면 목록.
///
/// 뷰가 아니라 **자기 파일**에 산다. `PopoverView` 안에 두었을 때는 탭 목록을 그리는
/// `PokedoroTabBar`(`PokedoroTheme.swift`)가 `PopoverView` 를 향해 의존하고 `PopoverView` 는
/// 다시 테마를 읽어, 두 파일이 서로를 가리켰다. 목록은 누구의 것도 아니므로 어느 쪽도 아닌 곳에 둔다.
enum PopoverTab: CaseIterable {
    case home, pokemon, collection, battle, challenge, shop, bag

    /// 탭바가 그리는 탭.
    static let tabBarTabs: [PopoverTab] = [.home, .pokemon, .collection, .battle, .challenge]

    /// footer 가 그리는 탭. 상점 · 가방은 **어느 탭에서 쓰든 상관없는** 소지품이라 탭바가 아니라
    /// 아래 줄에 산다. 자리는 다르지만 같은 `tab` 값이므로 선택 표시도 똑같이 필요하다 —
    /// 예전엔 footer 버튼에 활성 표시가 없어, 상점에 들어가면 탭바 다섯 개가 전부 비선택이 되어
    /// 화면 어디에도 "지금 여기" 가 없었다.
    static let footerTabs: [PopoverTab] = [.shop, .bag]

    /// 지금 위치를 footer 가 표시하는가. 판정을 뷰 안에 인라인으로 두면 탭을 더할 때 목록과
    /// 표시 중 한쪽만 고치게 된다(`OverlayChromeTests` 가 둘을 함께 본다).
    var isFooterDestination: Bool { Self.footerTabs.contains(self) }

    /// 팝오버가 유지하는 높이. 탭 안에서 콘텐츠가 늘고 줄어도(기술 목록 펼침, 로딩 자리표시자,
    /// 진화 프롬프트) 이 값은 그대로라 창이 다시 그려지지 않는다 — 펼칠 때마다 커졌다 작아지며
    /// 떨리던 원인을 없앤다.
    ///
    /// 모든 탭이 같은 값을 쓴다. 예전엔 홈만 560 이라 탭을 옮길 때마다 창이 220pt 씩 뛰었다.
    /// 홈은 콘텐츠가 짧아 아래가 비지만, 창이 제자리에 있는 편이 낫다.
    var contentHeight: CGFloat { PopoverMetrics.tabHeight }
}

