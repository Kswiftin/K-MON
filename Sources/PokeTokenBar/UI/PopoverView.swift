import AppKit
import SwiftUI

enum PopoverTab {
    case home, pokemon, collection, battle, challenge, shop, bag

    /// 팝오버가 유지하는 높이. 탭 안에서 콘텐츠가 늘고 줄어도(기술 목록 펼침, 로딩 자리표시자,
    /// 진화 프롬프트) 이 값은 그대로라 창이 다시 그려지지 않는다 — 펼칠 때마다 커졌다 작아지며
    /// 떨리던 원인을 없앤다.
    ///
    /// 모든 탭이 같은 값을 쓴다. 예전엔 홈만 560 이라 탭을 옮길 때마다 창이 220pt 씩 뛰었다.
    /// 홈은 콘텐츠가 짧아 아래가 비지만, 창이 제자리에 있는 편이 낫다.
    var contentHeight: CGFloat { PopoverMetrics.tabHeight }
}

enum PopoverMetrics {
    static let width: CGFloat = 360
    static let padding: CGFloat = 14
    static let contentWidth: CGFloat = width - padding * 2

    /// 모든 탭이 함께 쓰는 팝오버 높이. 도감·상점·가방이 안에 520pt 격자를 들고 있어
    /// 타이머·탭바·푸터까지 더하면 이만큼 든다 — 가장 큰 탭에 맞춰야 어느 탭에서도 잘리지 않는다.
    static let tabHeight: CGFloat = 780

    /// 메뉴바·팝오버 화살표·화면 아래 여백이 먹는 세로 공간.
    static let verticalChrome: CGFloat = 80
    /// 좁은 화면에서도 최소한 이만큼은 준다 — 아래 스크롤로 나머지를 본다.
    static let minHeight: CGFloat = 320
    /// 화면 크기를 모를 때(NSScreen 부재) 쓰는 보수적 기본값.
    static let fallbackScreenHeight: CGFloat = 900

    /// 팝오버 콘텐츠 높이 상한. 넘으면 NSPopover 가 스크롤 없이 잘라내므로(#9) 스크롤 컨테이너와 짝으로 쓴다.
    ///
    /// 상한은 오직 화면 가용 높이에서만 나온다. 예전엔 720pt 짜리 고정 천장을 같이 걸었는데,
    /// 1440pt 화면에서도 상한이 720 이라 "기술 보기" 를 펼친 홈 탭(약 760pt)이 화면에 다 들어가는데도
    /// 스크롤로 넘어가 헤더와 그 아래 카드가 잘려 보였다. 화면보다 작은 고정 천장은 두지 않는다.
    static func maxHeight(screenHeight: CGFloat) -> CGFloat {
        max(minHeight, screenHeight - verticalChrome)
    }

    @MainActor
    static var currentMaxHeight: CGFloat {
        maxHeight(screenHeight: NSScreen.main?.visibleFrame.height ?? fallbackScreenHeight)
    }

    /// 탭이 원하는 높이를 화면에 맞춘다 — 고정 높이가 화면 밖으로 나가면 다시 클리핑이 된다.
    static func height(for tab: PopoverTab, screenHeight: CGFloat) -> CGFloat {
        min(tab.contentHeight, maxHeight(screenHeight: screenHeight))
    }

    @MainActor
    static func currentHeight(for tab: PopoverTab) -> CGFloat {
        height(for: tab, screenHeight: NSScreen.main?.visibleFrame.height ?? fallbackScreenHeight)
    }
}

@MainActor
@Observable
final class PopoverNavigation {
    var showSettings = false
    /// 체육관 오버레이. 설정과 같은 층이라 **둘이 동시에 뜨지 않게** 한쪽을 열면 다른 쪽을 닫는다.
    var showGymLeague = false
    /// 던전 오버레이(#79). 설정·체육관과 같은 층이다.
    var showDungeon = false
    /// 꾸미기(트레이너 의상) 오버레이. 위 오버레이들과 같은 층이다.
    var showOutfit = false
    /// 대화 오버레이. 다른 오버레이와 달리 **어느 개체의** 대화인지까지 들어야 한다 —
    /// 대화는 활성 개체뿐 아니라 박스 개체로도 열린다(`PokemonRosterView`).
    /// `nil` 이 곧 닫힘이라 플래그를 따로 두지 않는다.
    var chatCompanionID: UUID?
    var tab: PopoverTab = .home

    /// 오버레이는 서로 같은 층이라 **한 번에 하나만** 떠야 한다. 접는 목록을 부르는 자리마다
    /// 손으로 베껴 두면 다음에 오버레이를 더할 때 한 곳을 빠뜨리고, 그건 테스트로만 잡힌다.
    /// 목록이 한 벌이면 빠뜨릴 자리가 없다.
    private func closeOverlays() {
        showSettings = false
        showGymLeague = false
        showDungeon = false
        showOutfit = false
        chatCompanionID = nil
    }

    func reset() {
        closeOverlays()
        tab = .home
    }

    /// 배틀 신청이 오면 그 화면으로 데려간다 — 덮여 있던 오버레이는 접는다.
    /// 체육관을 여기서 안 닫으면 신청이 온 줄 모른 채 목록만 보게 된다.
    func goToBattle() {
        closeOverlays()
        tab = .battle
    }

    /// 체육관은 혼자 도전하는 콘텐츠다. 전투 엔진은 친구 대전과 같아도, 시작한 문맥까지 친구 탭으로
    /// 보내면 체육관에서 도전했다는 흐름이 끊긴다.
    func goToGymBattle() {
        closeOverlays()
        showGymLeague = true
        tab = .challenge
    }

    /// 대화를 여는 **유일한** 자리. 형제 오버레이를 접지 않고 `chatCompanionID` 만 세우면
    /// 화면 체인이 설정·체육관·던전·꾸미기를 먼저 보므로 아무 일도 안 일어난 것처럼 보이고,
    /// 나중에 그 오버레이를 닫는 순간 대화가 불쑥 되살아난다.
    func goToChat(companionID: UUID) {
        closeOverlays()
        chatCompanionID = companionID
    }

    /// 여는 시점의 소유 검사는 **여는 순간**만 덮는다. 대화가 떠 있는 동안 상대가 놓아주기·교환·
    /// 졸업으로 사라지면 이름이 `?` 이고 스프라이트가 빈 화면에 전송 버튼만 살아 있고, 보내면
    /// 죽은 UUID 로 세션이 새로 생겨 다음 `prune` 까지 디스크에 남는다.
    func dropChatIfCompanionIsGone(ownedIDs: Set<UUID>) {
        guard let id = chatCompanionID, !ownedIDs.contains(id) else { return }
        chatCompanionID = nil
    }
}

/// 팝오버를 바깥 클릭에 안 닫히게 붙드는 이유가 **둘** 이상이라, 되돌림 판정을 한 곳에 둔다.
///
/// 각 이유가 스스로 `.transient` 로 되돌리면 나중에 끝난 쪽이 아직 진행 중인 쪽의 고정을
/// 풀어 버린다 — 배틀 중에 대화 전송이 먼저 끝나면 일하면서 하던 배틀이 클릭 한 번에 닫힌다.
/// 부르는 자리는 플래그만 넘기고 판정하지 않는다.
enum PopoverPinPolicy {
    /// `chatVisible` 이 따로 있는 이유: 붙드는 목적이 "답이 오는 걸 **보게** 하려고" 다.
    /// 사용자가 대화를 닫았으면 볼 것이 없는데, 전송만 보고 붙들면 화면에 아무 설명도 없이
    /// 바깥 클릭이 먹통이 된다.
    /// **배틀은 창을 붙들지 않는다.** 예전엔 배틀 중 `.applicationDefined` 로 고정해 바깥 클릭으로
    /// 닫히지 않게 했는데, 급히 화면을 치워야 할 때 닫히지 않아 불편했다. 배틀은 창을 닫아도
    /// 살아 있고 다시 열면 이어지므로 붙들 이유가 없다(다만 30초 턴 마감은 계속 돌아 자리를
    /// 비우면 그 턴은 자동으로 채워진다 — 상대를 무한정 기다리게 하지 않으려는 장치라 그대로 둔다).
    ///
    /// 대화 전송 중 고정은 남긴다. 그건 몇 초짜리이고, 붙드는 목적이 "답이 오는 걸 **보게**"
    /// 하려는 것이라 닫히면 응답을 놓친다.
    static func behavior(chatSending: Bool, chatVisible: Bool) -> NSPopover.Behavior {
        chatSending && chatVisible ? .applicationDefined : .transient
    }
}

struct PopoverView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(CompanionStore.self) private var companion
    @Environment(UpdateChecker.self) private var updater
    @Environment(PopoverNavigation.self) private var nav
    @Environment(BattleCenter.self) private var battleCenter
    @Environment(MemoryHomeVisitCenter.self) private var memoryHomeVisits
    @Environment(FocusTimer.self) private var focusTimer
    @Environment(MemoryHomePresenter.self) private var memoryHomePresenter
    @Environment(PokemonChatPresenter.self) private var chatPresenter

    private var l: L { companion.l }

    var body: some View {
        @Bindable var nav = nav
        Group {
            if nav.showSettings {
                SettingsView(onClose: { nav.showSettings = false })
                    .environment(settings)
                    .environment(companion)
                    .environment(updater)
            } else if nav.showGymLeague {
                GymLeagueView(store: companion, onClose: { nav.showGymLeague = false })
            } else if nav.showDungeon {
                RogueRunView(store: companion, onClose: { nav.showDungeon = false })
            } else if nav.showOutfit {
                OutfitView(store: companion, onClose: { nav.showOutfit = false })
            } else if let chatCompanionID = nav.chatCompanionID {
                // 대화는 전용 창에서 여기로 옮겨 왔다 — 근거는 `PokemonChatPresenter` 주석.
                // 실행기는 프레젠터가 조립한 한 벌을 받아 쓴다.
                PokemonChatView(store: companion, companionID: chatCompanionID,
                                toolbox: chatPresenter.toolbox, settings: settings,
                                onClose: { nav.chatCompanionID = nil })
            } else {
                // 고정 높이 + 탭 안 스크롤. 콘텐츠가 늘 때마다 창이 커지면 NSPopover 가 매번 다시
                // 그려 떨리고, 화면을 넘기면 스크롤 대신 잘라낸다(#9). 창 크기는 고정하고 넘치는
                // 부분만 탭 안에서 스크롤한다 — 타이머·탭바·푸터는 스크롤 밖이라 항상 제자리다.
                mainContent
                    .frame(height: PopoverMetrics.currentHeight(for: nav.tab))
            }
        }
        .frame(width: PopoverMetrics.width)
        .background { PokedoroTheme.pageBackground }
        .tint(PokedoroTheme.blue)
        .fontDesign(.rounded)
        .environment(\.spriteAntialiasing, settings.imageAntialiasing)
        .environment(\.locale, companion.language.displayLocale)
        // 신호를 읽는 **바로 그 자리에서** 끈다. 끄는 일을 아래 화면에 맡기면 그 화면이 조건부로
        // 그려지는 순간(친구 탭 관문이 그랬다) 신호가 영영 안 꺼져 열 때마다 여기로 튄다.
        // 탭만 바꾸면 위에 덮인 오버레이가 그대로 남아 신청 화면이 안 보인다 — 탭 전환과 오버레이
        // 접기는 `goToBattle()` 한 곳에 함께 있어야 한다.
        .onAppear { if battleCenter.consumePendingAttention() { nav.goToBattle() } }
        // 로스터가 바뀌는 모든 경로(놓아주기·교환·졸업·부화)를 하나로 본다. 개수만 보면 교환처럼
        // 한 마리가 나가고 한 마리가 들어오는 경우를 놓친다.
        .onChange(of: companion.ownedMons.map(\.id)) { _, ids in
            nav.dropChatIfCompanionIsGone(ownedIDs: Set(ids))
        }
        // 던전은 배틀과 화면이 다르므로 접는다. 체육관은 `GymLeagueView` 안에서 전투 화면으로
        // 갈아 끼워 도전 문맥을 유지한다.
        .onChange(of: battleCenter.phase) { _, phase in
            if nav.showDungeon, phase != .ready { nav.showDungeon = false }
        }
        // 거래 신청(`.incoming`)은 `wantsForegroundWindow` 가 false 라 AppDelegate 의 창 열기 경로를
        // 타지 않는다(`BattleNet.swift:507`). 즉 오버레이를 접는 일이 **여기서만** 일어난다 —
        // 탭만 바꾸면 대화가 덮은 채로 남아 신청이 온 줄 모른다.
        .onChange(of: battleCenter.trading.phase) { _, phase in
            if phase != .ready { nav.goToBattle() }
        }
        .onChange(of: nav.tab) { _, tab in
            if tab == .home { settings.recordMemoryHomeEntry() }
        }
    }

    @ViewBuilder
    private var updateBanner: some View {
        if let update = updater.available, settings.updateNotificationsEnabled {
            HStack(spacing: 8) {
                Text(l.updateAvailable(update.version, current: updater.currentVersion)).font(.caption)
                Spacer()
                if updater.isUpdating {
                    ProgressView().controlSize(.small)
                } else {
                    Button(l.updateButton) { updater.applyUpdate() }
                        .buttonStyle(.borderedProminent).controlSize(.small)
                    Button(l.updateLater) { updater.skipCurrent() }
                        .buttonStyle(.borderless).controlSize(.small)
                }
            }
            .padding(8)
            .pokedoroCard(tint: PokedoroTheme.blue, emphasized: true)
        }
    }

    /// 계정 단위 상태 한 줄 — 트레이너 레벨과 별의조각 잔액. 팝오버 최상단에 고정해 어느 탭에서도 보인다.
    ///
    /// 파트너 카드가 아니라 여기 있어야 한다 — 레벨은 졸업으로 초기화되지 않는 **계정** 값이다.
    /// 라벨의 "트레이너" 도 빼면 안 된다. `Lv.N` 만 쓰면 파트너·로스터·배틀이 이미 쓰는 표기와
    /// 겹쳐 포켓몬 레벨로 잘못 읽힌다. 게이지와 남은 포인트가 있어야 배지가 아니라 좇을 목표가 되고,
    /// 옆의 잔액이 레벨업 보상이 어디로 들어왔는지 연결해 준다(그 전엔 상점 안에서만 보였다).
    private var trainerBar: some View {
        VStack(spacing: 5) {
            HStack(spacing: 7) {
                PokeBallMark(size: 22)
                Text("\(l.trainerLevelLabel) Lv.\(companion.trainerLevel.level)")
                    .font(.caption.weight(.bold)).monospacedDigit()
                if let remaining = companion.trainerLevel.pointsToNextLevel {
                    Text("NEXT \(remaining)p")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .monospacedDigit().foregroundStyle(.secondary)
                }
                Spacer()
                Text("✦ " + GameNumberFormatter.compact(companion.availableTokens))
                    .font(.caption.weight(.bold)).foregroundStyle(.orange).monospacedDigit()
            }
            ProgressView(value: companion.trainerLevel.progress)
                .tint(PokedoroTheme.blue)
                .scaleEffect(x: 1, y: 1.35)
        }
        .padding(.horizontal, 11).padding(.vertical, 8)
        .pokedoroCard(tint: PokedoroTheme.yellow)
    }

    private var mainContent: some View {
        @Bindable var nav = nav
        return VStack(alignment: .leading, spacing: 12) {
            updateBanner
            trainerBar
            FocusTimerView()
            PokedoroTabBar(selection: $nav.tab, l: l)

            // 탭 콘텐츠만 스크롤한다. 짧은 탭은 위로 붙고 남는 자리는 빈 공간으로 둔다 —
            // 창 높이가 고정이라 탭을 바꾸거나 기술 목록을 펼쳐도 팝오버는 그대로다.
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    switch nav.tab {
                    case .challenge: ChallengeView(store: companion)
                    case .battle: FriendView(store: companion, nav: nav)
                    case .collection: CollectionView(store: companion)
                    case .pokemon: PokemonRosterView(store: companion)
                    case .bag: BagView(store: companion, nav: nav)
                    case .shop: ShopView(store: companion, nav: nav)
                    case .home:
                        // 스타터를 아직 안 고른 첫 화면에는 띄우지 않는다 — 첫 한 시간은 대상이 아니다.
                        if !companion.needsStarterSelection { MissionBoardView(store: companion) }
                        CompanionHeader(store: companion)
                        if settings.memoryHomeEnabled {
                            MemoryHomeQuickCard(store: companion) { memoryHomePresenter.open() }
                        }
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxHeight: .infinity, alignment: .top)

            footer
        }
        .padding(PopoverMetrics.padding)
        .animation(.snappy(duration: 0.22), value: nav.tab)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if nav.tab == .home {
                Text("\(l.totalPlaytime) \(l.duration(companion.activeSecondsTotal))")
                    .font(.caption).foregroundStyle(.tertiary).monospacedDigit()
            }
            Button { nav.tab = .shop } label: { Label(l.shop, systemImage: "cart") }
                .buttonStyle(.borderless).help(l.shop)
            // 가방은 포켓몬 탭 안에 있었다 — 어느 탭에서 쓰든 상관없는 소지품이라 상점 옆이 제자리다.
            Button { nav.tab = .bag } label: { Label(l.bag, systemImage: "backpack.fill") }
                .buttonStyle(.borderless).help(l.bag)
            Spacer()
            Button { nav.showSettings = true } label: { Image(systemName: "gearshape") }
                .buttonStyle(.borderless).help(l.settings)
            Button { NSApplication.shared.terminate(nil) } label: { Image(systemName: "power") }
                .buttonStyle(.borderless).help(l.quit)
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.94), in: Capsule())
        .overlay(Capsule().strokeBorder(PokedoroTheme.ink.opacity(0.28), lineWidth: 1.25)
            .allowsHitTesting(false))
    }
}
