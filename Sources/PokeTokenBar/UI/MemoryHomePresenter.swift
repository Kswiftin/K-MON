import AppKit
import Observation
import SwiftUI

/// Memory Home is intentionally an AppKit-owned window.  Its frame belongs to macOS's
/// normal window restoration, never to the companion save file.
@MainActor
@Observable
final class MemoryHomePresenter: NSObject, NSWindowDelegate {
    private let settings: AppSettings
    private let store: CompanionStore
    private let visits: MemoryHomeVisitCenter
    private var window: NSWindow?
    private static let defaultContentSize = NSSize(width: 1_040, height: 720)

    init(settings: AppSettings, store: CompanionStore, visits: MemoryHomeVisitCenter) {
        self.settings = settings
        self.store = store
        self.visits = visits
        super.init()
        observeAvailability()
    }

    private func observeAvailability() {
        withObservationTracking { _ = settings.memoryHomeEnabled } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                if !self.settings.memoryHomeEnabled {
                    self.visits.shutdown()
                    self.window?.orderOut(nil)
                } else {
                    self.visits.startHostingIfEligible()
                }
                self.observeAvailability()
            }
        }
    }

    func open() {
        guard settings.memoryHomeEnabled else { return }
        let window = window ?? makeWindow()
        self.window = window
        if window.contentView == nil { installContent(in: window) }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        settings.recordMemoryHomeEntry()
    }

    func windowWillClose(_ notification: Notification) {
        // Closing the window only ends its UI. LAN-public hosting stays alive for the app.
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: Self.defaultContentSize),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "Poké Home"
        window.minSize = NSSize(width: 900, height: 640)
        window.setFrameAutosaveName("MemoryHomeWindow")
        window.isReleasedWhenClosed = false
        window.delegate = self
        installContent(in: window)
        // contentViewController 를 붙이면 AppKit 이 SwiftUI 의 fitting size 로 창을 다시 잰다.
        // 그대로 두면 위 contentRect 가 무효가 되고 minSize(900×640)까지 쪼그라든다 —
        // 이 Mac 의 저장된 프레임이 실제로 900×640 이었다. 크기는 붙인 **뒤에** 잡는다.
        window.setContentSize(Self.defaultContentSize)
        window.center()
        return window
    }

    private func installContent(in window: NSWindow) {
        window.contentViewController = NSHostingController(rootView:
            MemoryHomeWindowView(store: store, visits: visits)
                .environment(settings)
                .environment(store)
                .environment(visits)
                .environment(\.locale, PokemonNaming.locale))
    }
}

struct MemoryHomeQuickCard: View {
    let store: CompanionStore
    let openHome: () -> Void
    @Environment(AppSettings.self) private var settings

    private var l: L { store.l }

    var body: some View {
        if let mon = store.state.active {
            let album = store.memoryAlbum
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text("TODAY \(album.memoryHomeAccess.visitToday) · TOTAL \(album.memoryHomeAccess.visitTotal)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(PokedoroTheme.blue)
                    Spacer()
                    Text(store.chatProfile(for: mon).displayName).font(.caption.weight(.semibold)).lineLimit(1)
                }
                Text(album.memoryHomeAccess.profileMessage ?? "우리의 작은 포케 홈")
                    .font(.caption).lineLimit(1)
                if let pinned = album.pinned(for: mon.id) {
                    Label(pinned.body, systemImage: "pin.fill")
                        .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                Button(action: openHome) {
                    Label("미니홈피 열기", systemImage: "arrow.up.forward.app")
                }
                .buttonStyle(.borderedProminent).controlSize(.small)
                .accessibilityHint("전용 Memory Home 창을 엽니다.")
            }
            .padding(10)
            .pokedoroCard()
            .onAppear { settings.recordMemoryHomeExposure() }
        }
    }
}

private enum MemoryHomeTab: String, CaseIterable, Identifiable {
    case home = "HOME", profile = "PROFILE", records = "RECORDS", photo = "PHOTO", guestbook = "GUESTBOOK", visit = "VISIT"
    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .home: "house.fill"
        case .profile: "person.text.rectangle"
        case .records: "book.closed.fill"
        case .photo: "photo.fill"
        case .guestbook: "text.bubble.fill"
        case .visit: "figure.walk.arrival"
        }
    }
}

private struct MemoryHomeWindowView: View {
    let store: CompanionStore
    let visits: MemoryHomeVisitCenter
    @Environment(AppSettings.self) private var settings
    @State private var tab: MemoryHomeTab = .home
    @State private var note = ""
    @State private var photo = false
    @State private var guestbookDraft = ""
    @State private var profileMessageDraft = ""
    @State private var profileMessageError: String?
    @State private var nicknameDraft = ""
    @State private var nicknameError: String?
    /// 방문자 일촌명 초안. 확정(`onSubmit`)할 때만 앨범에 쓴다.
    @State private var aliasDrafts: [UUID: String] = [:]
    @State private var editingRoom = false
    @State private var selectedDecorID: UUID?
    @State private var selectedFurniture: ItemKind?
    @State private var selectedCompanionID: UUID?
    @State private var showResetDecorConfirmation = false
    @State private var roomEditFeedback: String?
    /// §25 계절 결산. `eee5c86` 이후 이 시트는 창에서 열 수 없는 상태였다.
    @State private var recap = false
    /// §25 연말 결산. 자동으로 띄우지 않는다 — "올해 한 번만" 을 판정하려면 새 저장 필드가
    /// 필요하고, 그건 이 홈의 "새 필드 0개" 원칙을 깬다(PRD 의 Open Question 으로 남겼다).
    @State private var yearRecap = false

    private var l: L { store.l }

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                header
                tabBar
                Group {
                    if let mon = store.state.active { tabContent(mon: mon, width: proxy.size.width) }
                    else { ContentUnavailableView("동행을 기다리고 있어요", systemImage: "house") }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .background(PokedoroTheme.pageBackground)
        .tint(PokedoroTheme.blue)
        .fontDesign(.rounded)
        .sheet(isPresented: $photo) {
            MemoryHomeStickerPhotoSheet(speciesID: store.state.active?.currentID ?? 25,
                                        shiny: store.state.active?.isShiny ?? false, language: l, album: store.memoryAlbum)
        }
        .sheet(isPresented: $recap) {
            MemoryHomeSeasonRecapSheet(recap: store.memoryAlbum.seasonRecap(for: store.ownedMons.map(\.id)),
                                       language: l)
        }
        .sheet(isPresented: $yearRecap) {
            let summary = store.memoryAlbum.yearRecap(for: store.ownedMons.map(\.id))
            MemoryHomeYearRecapSheet(recap: summary,
                                     topCompanionName: summary.topCompanionID
                                         .flatMap { id in store.ownedMons.first { $0.id == id } }
                                         .map { store.chatProfile(for: $0).displayName },
                                     language: l)
        }
        .alert("배치를 초기화할까요?",
               isPresented: $showResetDecorConfirmation) {
            Button("취소", role: .cancel) { }
            Button("가구 치우기", role: .destructive) {
                store.memoryAlbum.resetDecor()
                selectedDecorID = nil
                selectedFurniture = nil
            }
        } message: {
            Text("현재 배치된 가구 \(store.memoryAlbum.memoryHomeAccess.placedDecor.count)개를 치웁니다. 실행 취소로 되돌릴 수 있어요.")
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            let access = store.memoryAlbum.memoryHomeAccess
            Text("TODAY \(access.visitToday)  TOTAL \(access.visitTotal)")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(PokedoroTheme.red)
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(PokedoroTheme.red.opacity(0.11), in: Capsule())
            VStack(alignment: .leading, spacing: 2) {
                Text("\(store.memoryAlbum.memoryHomePublicNickname)'s Poké Home").font(.headline)
                Text(access.profileMessage ?? "기억을 모으는 작은 방")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            // §24 계절. 저장 없이 달력 월에서 파생한다 — 방 색은 사용자가 고른 테마 그대로 둔다.
            Label(MemoryHomeSeasonStyle.name(MemoryHomeSeason.current()),
                  systemImage: MemoryHomeSeasonStyle.symbol(MemoryHomeSeason.current()))
                .font(.caption2.weight(.medium)).foregroundStyle(.secondary)
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(Color.primary.opacity(0.055), in: Capsule())
            Label(access.visibility == .open ? "LAN 공개" : "LAN 차단",
                  systemImage: access.visibility == .open ? "dot.radiowaves.left.and.right" : "lock.fill")
                .font(.caption2.weight(.medium)).foregroundStyle(.secondary)
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(Color.primary.opacity(0.055), in: Capsule())
                .accessibilityLabel("공유 상태")
            Button { tab = .profile } label: { Image(systemName: "gearshape") }
                .buttonStyle(.borderless).controlSize(.small)
                .frame(minWidth: 28, minHeight: 28)
                .accessibilityLabel("홈 설정")
        }
        .padding(.horizontal, 18).padding(.vertical, 14)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.82))
        .overlay(alignment: .bottom) { Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1) }
    }

    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(MemoryHomeTab.allCases) { item in
                    Button { withAnimation(.snappy(duration: 0.22)) { tab = item } } label: {
                        Label(item.rawValue, systemImage: item.symbol)
                            .font(.system(size: 10, weight: .semibold))
                            .lineLimit(1)
                            .frame(minWidth: 84, minHeight: 34)
                            .foregroundStyle(tab == item ? PokedoroTheme.ink : .secondary)
                            .background(tab == item ? PokedoroTheme.blue.opacity(0.18) : .clear,
                                        in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    }
                        .buttonStyle(.plain)
                        .accessibilityLabel(item.rawValue)
                        .accessibilityValue(tab == item ? "현재 탭" : "")
                }
            }
        }
        .padding(4).padding(.horizontal, 12)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.52))
    }

    @ViewBuilder private func tabContent(mon: MonState, width: CGFloat) -> some View {
        switch tab {
        case .home: home(mon: mon, width: width)
        case .profile: profile(mon: mon)
        case .records: records(mon: mon)
        case .photo: photoTab(mon: mon)
        case .guestbook: guestbook(mon: mon)
        case .visit: visit
        }
    }

    private func home(mon: MonState, width: CGFloat) -> some View {
        return ScrollView {
            if width <= 920 {
                VStack(spacing: 12) {
                    profilePanel(mon: mon)
                    roomStage(mon: mon)
                    if editingRoom { roomEditor(mon: mon) }
                    sidePanel(mon: mon)
                }
            } else {
                HStack(alignment: .top, spacing: 12) {
                    profilePanel(mon: mon).frame(width: 164)
                    VStack(spacing: 12) {
                        roomStage(mon: mon)
                        if editingRoom { roomEditor(mon: mon) }
                    }.frame(maxWidth: .infinity)
                    sidePanel(mon: mon).frame(width: 245)
                }
            }
        }.padding(14)
    }

    private func profilePanel(mon: MonState) -> some View {
        let log = store.memoryAlbum.pokeLog(for: mon.id)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                SpriteView(speciesID: mon.currentID, size: 52, shiny: mon.isShiny)
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.chatProfile(for: mon).displayName).font(.subheadline.weight(.bold)).lineLimit(1)
                    Text("\(log.daysTogether) 일 함께").font(.caption2).foregroundStyle(.secondary)
                }
            }
            // 하트 글리프는 화면 판독기가 "하트 하트 하트 흰하트 흰하트" 로 읽는다 — 눈으로는
            // 게이지지만 귀로는 수가 아니다. 읽을 값은 따로 준다.
            MemoryHomeRule(label: "친밀도",
                           value: String(repeating: "♥", count: log.closenessHearts)
                                + String(repeating: "♡", count: 5 - log.closenessHearts))
                .accessibilityLabel("친밀도")
                .accessibilityValue("5점 만점에 \(log.closenessHearts)점")
            let mood = store.memoryAlbum.mood()
            MemoryHomeRule(label: "현재 기분", value: mood.map { MemoryHomeMoodStyle.emoji($0) + " " + MemoryHomeMoodStyle.name($0) } ?? "—")
            Button("프로필 보기") { tab = .profile }
                .buttonStyle(.bordered).controlSize(.small)
        }.memoryHomePanel()
    }

    /// §5 미니룸. R8 격자(12칸)를 그린다 — `9de278f` 가 이 화면을 만들면서 격자·스타일·
    /// 되돌리기를 **삭제 예정이던 옛 화면**에만 붙였고, 창에는 legacy 3슬롯만 남았다.
    private func roomStage(mon: MonState) -> some View {
        let album = store.memoryAlbum
        let tint = MemoryHomeRoomTheme.tint(for: album.theme(for: mon.id))
        let style = MemoryHomeRoomStyle.tint(for: album.roomStyle)
        return ZStack {
            // 벽지는 8×8 패턴을 **반복**해서 깐다. 예전엔 가구 아틀라스 전체를 `scaledToFill` 로
            // 늘려 배경에 붙여서, 침대·서랍장 그림이 뭉개진 채 벽에 박혀 있었다.
            if let wallpaper = MemoryHomePixelArt.wallpaperTile(for: album.roomStyle) {
                Image(nsImage: wallpaper).resizable(resizingMode: .tile).interpolation(.none)
            } else {
                style.opacity(0.34)
            }
            // 테마(사용자가 고른 4색)는 벽지 위에 옅게 얹는다 — 스타일이 테마를 지우면 안 된다.
            tint.opacity(0.18)
            // §24 창밖. 시각은 여기서 **한 번** 읽는다 — `TimelineView` 로 매초 갱신하면 방이
            // 상시 애니메이션이 되어 미니룸이 열려 있는 내내 CPU 를 먹는다(`defect-log.md`).
            // 경계를 넘는 순간이 아니라 방을 다시 열 때 반영되는 것으로 충분하다.
            let timeOfDay = MemoryHomeTimeOfDay.current()
            if let window = MemoryHomePixelArt.windowImage(for: album.roomStyle, timeOfDay: timeOfDay) {
                GeometryReader { geometry in
                    Image(nsImage: window).interpolation(.none)
                        .position(x: geometry.size.width * 0.76, y: geometry.size.height * 0.27)
                }
                .accessibilityElement()
                .accessibilityLabel("창밖")
                .accessibilityValue(MemoryHomeTimeOfDayStyle.name(timeOfDay))
            }
            if let floor = MemoryHomePixelArt.floorTile(for: album.roomStyle) {
                Image(nsImage: floor).resizable(resizingMode: .tile).interpolation(.none)
                    .frame(height: 64).frame(maxHeight: .infinity, alignment: .bottom)
            } else {
                Rectangle().fill(style.opacity(0.34)).frame(height: 34).frame(maxHeight: .infinity, alignment: .bottom)
            }
            GeometryReader { geometry in
                if editingRoom {
                    roomGrid(in: geometry.size, album: album)
                }
                ForEach(album.memoryHomeAccess.placedDecor.sorted { $0.layer < $1.layer }) { decor in
                    decorSprite(decor)
                        .position(x: decor.position.x * geometry.size.width,
                                  y: decor.position.y * geometry.size.height)
                        .onTapGesture {
                            guard editingRoom else { return }
                            selectedDecorID = decor.id; selectedCompanionID = nil; selectedFurniture = nil
                        }
                        .gesture(editingRoom ? DragGesture(minimumDistance: 2).onEnded { value in
                            _ = album.moveDecor(id: decor.id,
                                                to: .init(x: value.location.x / geometry.size.width,
                                                          y: value.location.y / geometry.size.height))
                        } : nil)
                        .accessibilityLabel(l.itemName(decor.item))
                        .accessibilityHint("드래그하여 8×6 격자에서 이동합니다.")
                }
                let companions = [mon] + roommates
                ForEach(Array(companions.enumerated()), id: \.element.id) { index, companion in
                    let point = album.companionPosition(for: companion.id, fallbackIndex: index)
                    SpriteView(speciesID: companion.currentID, size: companion.id == mon.id ? 128 : 78, shiny: companion.isShiny)
                        .position(x: point.x * geometry.size.width, y: point.y * geometry.size.height)
                        .onTapGesture {
                            guard editingRoom else { return }
                            selectedCompanionID = companion.id; selectedDecorID = nil; selectedFurniture = nil
                        }
                        .gesture(editingRoom ? DragGesture().onEnded { value in
                            album.setCompanionPosition(.clamped(x: value.location.x / geometry.size.width, y: value.location.y / geometry.size.height), for: companion.id, validCompanionIDs: Set(store.ownedMons.map(\.id)))
                        } : nil)
                        .background(selectedCompanionID == companion.id && editingRoom ? Color.white.opacity(0.75) : .clear,
                                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .accessibilityLabel(store.chatProfile(for: companion).displayName)
                        .accessibilityHint("선택하거나 드래그하여 위치를 바꿉니다.")
                }
            }
            VStack { HStack { Text("미니룸").font(.caption.weight(.semibold)); Spacer() }; Spacer() }.padding(12)
            VStack { Spacer(); Text(roomLifeLine(mon: mon)).font(.caption.weight(.medium)).padding(.horizontal, 9).padding(.vertical, 5).background(.black.opacity(0.12), in: Capsule()).padding(12) }
            if editingRoom {
                VStack {
                    HStack { Spacer(); Text(roomCanvasInstruction).font(.caption.weight(.semibold)).padding(8).background(.ultraThinMaterial, in: Capsule()) }
                    Spacer()
                    if let roomEditFeedback { Text(roomEditFeedback).font(.caption.weight(.medium)).foregroundStyle(.red).padding(7).background(.ultraThinMaterial, in: Capsule()) }
                }.padding(12)
            }
        }
        .frame(minHeight: 365)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        // Memory Home 창의 집중 카드 — 이 창이 곧 미니룸이라 강조 예산 하나를 여기가 쓴다
        // (팝오버 쪽 예산은 집중 카드의 것이고, 두 화면은 서로 다른 창이다).
        .pokedoroCard(emphasis: tint)
        .accessibilityLabel("가구와 동행이 배치된 미니룸")
    }

    @ViewBuilder private func roomGrid(in size: CGSize, album: PokemonMemoryAlbum) -> some View {
        ForEach(0..<8, id: \.self) { column in
            ForEach(0..<6, id: \.self) { row in
                let point = (column, row)
                let unavailable = selectedFurniture.map { !album.isDecorCellAvailable(point, item: $0, ownedItems: store.state.inventory) } ?? false
                let gridLabel = "격자 \(column + 1), \(row + 1)"
                let gridHint = unavailable ? "배치할 수 없는 칸" : "선택한 가구를 배치합니다."
                let gridFill: Color = selectedFurniture == nil ? .clear : (unavailable ? Color.red.opacity(0.12) : PokedoroTheme.mint.opacity(0.20))
                Rectangle()
                    .fill(gridFill)
                    .overlay(Rectangle().stroke(Color.white.opacity(0.42), lineWidth: 0.7))
                    .frame(width: size.width / 8, height: size.height / 6)
                    .position(x: (Double(column) + 0.5) * size.width / 8,
                              y: (Double(row) + 0.5) * size.height / 6)
                    .contentShape(Rectangle())
                    .onTapGesture { placeSelectedFurniture(at: point) }
                    .allowsHitTesting(selectedFurniture != nil)
                    .accessibilityHidden(selectedFurniture == nil)
                    .accessibilityLabel(gridLabel)
                    .accessibilityHint(gridHint)
            }
        }
    }

    private var roomCanvasInstruction: String {
        if let item = selectedFurniture { return "\(l.itemName(item))을(를) 빈 격자에 클릭해 놓으세요" }
        if selectedDecorID != nil || selectedCompanionID != nil { return "선택됨 · 드래그해 이동하거나 아래에서 편집하세요" }
        return "가구를 고른 뒤 빈 격자를 클릭하세요 · 동행과 가구는 드래그로 이동"
    }

    private func placeSelectedFurniture(at point: (Int, Int)) {
        guard editingRoom, let item = selectedFurniture else { return }
        let album = store.memoryAlbum
        guard album.isDecorCellAvailable(point, item: item, ownedItems: store.state.inventory) else {
            roomEditFeedback = "이 칸에는 더 배치할 수 없어요."; return
        }
        let position = PokemonMemoryAlbum.normalizedGridPoint(point)
        if let decor = album.placeDecor(item, at: position, ownedItems: store.state.inventory) {
            selectedDecorID = decor.id; selectedCompanionID = nil; selectedFurniture = nil; roomEditFeedback = nil
        } else {
            roomEditFeedback = "보유한 가구 수량이 부족해요."
        }
    }

    /// 가구 픽셀 아트 한 칸. **크기는 `MemoryHomePixelArt.displaySize` 가 정한다** — 뷰가 62pt
    /// 같은 값을 직접 쓰면 16px 스프라이트가 3.875 배로 늘어나 픽셀 폭이 3/4px 로 갈린다.
    @ViewBuilder private func furnitureIcon(_ item: ItemKind, style: MemoryHomeRoomStyle,
                                            scale: Int, emojiSize: CGFloat) -> some View {
        if let art = MemoryHomePixelArt.furnitureImage(for: item, style: style, scale: scale),
           let size = MemoryHomePixelArt.displaySize(for: item, scale: scale) {
            Image(nsImage: art).resizable().interpolation(.none)
                .frame(width: size.width, height: size.height)
        } else {
            // 격자가 없는 가구도 방에 보여야 한다 — 안 그리면 놓았는데 사라진 것처럼 보인다.
            Text(item.fallbackEmoji).font(.system(size: emojiSize))
        }
    }

    @ViewBuilder private func decorSprite(_ decor: MemoryHomePlacedDecor) -> some View {
        furnitureIcon(decor.item, style: store.memoryAlbum.roomStyle,
                      scale: MemoryHomePixelArt.roomScale, emojiSize: 34)
        .padding(3)
        .background(selectedDecorID == decor.id && editingRoom ? Color.white.opacity(0.8) : .clear,
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    /// §5 §17 §24 한 줄. 문구 판정은 전부 `MemoryHomeRoomLife` 에 있다 — 뷰에 두면 문구가
    /// 무테스트로 남는다(이 화면의 옛 문구 3줄이 정확히 그 상태였다).
    private func roomLifeLine(mon: MonState) -> String {
        MemoryHomeRoomLife.line(speciesID: mon.currentID,
                                decor: store.memoryAlbum.memoryHomeAccess.placedDecor.map(\.item),
                                roommates: roommates.map { store.chatProfile(for: $0).displayName },
                                mood: store.memoryAlbum.mood(),
                                season: MemoryHomeSeason.current(),
                                timeOfDay: MemoryHomeTimeOfDay.current(),
                                companion: store.chatProfile(for: mon).displayName, l)
    }

    private func roomEditor(mon: MonState) -> some View {
        let album = store.memoryAlbum
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("미니룸 스튜디오", systemImage: "square.grid.3x3.fill")
                    .font(.headline)
                Spacer()
                Text("\(album.memoryHomeAccess.placedDecor.count)/12 배치")
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Button { album.undoRoomEdit() } label: { Image(systemName: "arrow.uturn.backward") }
                    .disabled(!album.canUndoRoomEdit).accessibilityLabel("실행 취소")
                Button { album.redoRoomEdit() } label: { Image(systemName: "arrow.uturn.forward") }
                    .disabled(!album.canRedoRoomEdit).accessibilityLabel("다시 실행")
                Button(editingRoom ? "완료" : "") {
                    editingRoom = false; selectedFurniture = nil; selectedDecorID = nil; selectedCompanionID = nil; roomEditFeedback = nil
                }.buttonStyle(.borderedProminent).controlSize(.small)
            }
            roomStyleCards(album: album)
            Text("가구 카탈로그").font(.caption.weight(.bold))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 105), spacing: 7)], spacing: 7) {
                ForEach(ItemKind.memoryHomeFurniture.sorted { $0.rawValue < $1.rawValue }, id: \.self) { item in
                    furnitureCard(item, album: album)
                }
            }
            if let selectedDecorID, let decor = album.memoryHomeAccess.placedDecor.first(where: { $0.id == selectedDecorID }) {
                HStack {
                    Label("선택: " + l.itemName(decor.item), systemImage: "cursorarrow.click")
                    Spacer()
                    Button(role: .destructive) { _ = album.removeDecor(id: selectedDecorID); self.selectedDecorID = nil } label: {
                        Label("삭제", systemImage: "trash")
                    }.accessibilityLabel("선택한 가구 치우기")
                }.font(.caption)
            } else if let selectedCompanionID, let companion = store.ownedMons.first(where: { $0.id == selectedCompanionID }) {
                Label("선택한 동행: " + store.chatProfile(for: companion).displayName,
                      systemImage: "figure.wave").font(.caption)
            }
            HStack {
                Menu("룸메이트") {
                    ForEach(RosterOrdering.arrange(
                        store.ownedMons.filter { $0.id != mon.id }, sort: .level, ascending: false)) { candidate in
                        let included = album.memoryHomeAccess.roommateIDs.contains(candidate.id)
                        Button {
                            setRoommate(candidate.id, included: !included)
                        } label: { Label(store.chatProfile(for: candidate).displayName, systemImage: included ? "checkmark.circle.fill" : "circle") }
                    }
                }.menuStyle(.borderedButton).controlSize(.small)
                Spacer()
                Button("초기화", role: .destructive) { showResetDecorConfirmation = true }
                    .disabled(album.memoryHomeAccess.placedDecor.isEmpty).controlSize(.small)
            }
        }
        .padding(12)
        .memoryHomePanel()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("미니룸 편집 도구")
    }

    private func furnitureCard(_ item: ItemKind, album: PokemonMemoryAlbum) -> some View {
        let owned = store.itemCount(item)
        let placed = album.memoryHomeAccess.placedDecor.filter { $0.item == item }.count
        let selectable = owned > placed && album.memoryHomeAccess.placedDecor.count < 12
        return Button {
            selectedFurniture = selectedFurniture == item ? nil : item
            selectedDecorID = nil; selectedCompanionID = nil; roomEditFeedback = nil
        } label: {
            VStack(spacing: 3) {
                // 카탈로그도 방과 같은 픽셀 아트를 보여준다 — 이모지만 띄우면 무엇을 사는지,
                // 고른 스타일에서 어떤 색으로 놓이는지 사기 전에 알 수 없다.
                furnitureIcon(item, style: album.roomStyle, scale: MemoryHomePixelArt.thumbnailScale, emojiSize: 20)
                    .frame(height: 34)
                Text(l.itemName(item)).font(.caption.weight(.semibold)).lineLimit(1)
                Text("보유 \(owned) · 배치 \(placed)")
                    .font(.caption2).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, minHeight: 72)
        }
        .buttonStyle(.plain)
        .padding(5)
        .background(selectedFurniture == item ? PokedoroTheme.blue.opacity(0.23) : Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(selectedFurniture == item ? PokedoroTheme.blue : .clear, lineWidth: 1.5))
        .opacity(selectable || selectedFurniture == item ? 1 : 0.48)
        .accessibilityLabel(l.itemName(item))
        .accessibilityValue("보유 \(owned), 배치 \(placed)")
        .accessibilityHint(selectable ? "선택한 뒤 빈 격자를 클릭해 배치합니다." : "더 배치할 수 없어요.")
        .disabled(!selectable && selectedFurniture != item)
    }

    private func roomStyleCards(album: PokemonMemoryAlbum) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("방 스타일").font(.caption.weight(.bold))
            HStack(spacing: 7) {
                ForEach(MemoryHomeRoomStyle.allCases, id: \.self) { style in
                    let unlocked = album.isRoomStyleUnlocked(style)
                    Button { if unlocked { album.selectRoomStyle(style) } } label: {
                        VStack(spacing: 3) {
                            RoundedRectangle(cornerRadius: 5).fill(MemoryHomeRoomStyle.tint(for: style)).frame(height: 18)
                            Text(style.name).font(.caption2.weight(.semibold)).lineLimit(1)
                            Text(roomStyleStatus(style, unlocked: unlocked, active: style == album.roomStyle))
                                .font(.system(size: 10)).lineLimit(1).foregroundStyle(unlocked ? Color.secondary : Color.orange)
                        }.frame(maxWidth: .infinity).padding(5)
                    }.buttonStyle(.plain)
                    .background(style == album.roomStyle ? MemoryHomeRoomStyle.tint(for: style).opacity(0.18) : Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .accessibilityLabel(style.name)
                    .accessibilityValue(unlocked ? (style == album.roomStyle ? "사용 중" : "해금됨") : roomStyleRequirement(style))
                }
            }
        }
    }

    /// **표는 `MemoryHomeNames` 하나다** — 터미널의 거절 문구도 같은 값을 읽어야 하고, 두 벌로
    /// 두면 조건이 바뀔 때 한쪽만 옛말이 된다.
    private func roomStyleRequirement(_ style: MemoryHomeRoomStyle) -> String {
        MemoryHomeNames.requirement(style)
    }

    private func roomStyleStatus(_ style: MemoryHomeRoomStyle, unlocked: Bool, active: Bool) -> String {
        if !unlocked { return roomStyleRequirement(style) }
        return active ? "사용 중" : "선택"
    }

    private func sidePanel(mon: MonState) -> some View {
        let album = store.memoryAlbum
        let timeline = album.timeline(for: mon.id)
        return VStack(alignment: .leading, spacing: 10) {
            Text("기억 보드").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            if let pin = album.pinned(for: mon.id) { Label(pin.body, systemImage: "pin.fill").font(.caption).lineLimit(3) }
            Divider()
            Text("최근 기억").font(.caption.weight(.bold))
            ForEach(timeline.prefix(3)) { Text("· \($0.body)").font(.caption2).lineLimit(2) }
            if !album.milestones(for: mon.id).isEmpty { Label("\(album.milestones(for: mon.id).count) 열린 카드", systemImage: "rectangle.stack.fill").font(.caption) }
            Divider()
            Text("오늘의 기분")
                .font(.caption.weight(.bold))
            Menu {
                ForEach(MemoryHomeMood.allCases, id: \.self) { mood in
                    Button {
                        album.setMood(mood)
                    } label: {
                        Text("\(MemoryHomeMoodStyle.emoji(mood)) \(MemoryHomeMoodStyle.name(mood))")
                    }
                }
            } label: {
                Label(currentMoodLabel(album), systemImage: "face.smiling")
            }
            .menuStyle(.borderedButton)
            .controlSize(.small)
            .accessibilityHint("기분에 따라 동행의 방명록과 반응이 달라집니다.")

            Divider()
            Text("미니룸 꾸미기")
                .font(.caption.weight(.bold))
            Text("가구, 동행, 스타일은 스튜디오에서 함께 편집합니다.")
                .font(.caption2).foregroundStyle(.secondary)
            Button(editingRoom ? "꾸미기 완료" : "스튜디오 열기") {
                editingRoom.toggle()
                selectedFurniture = nil; selectedDecorID = nil; selectedCompanionID = nil; roomEditFeedback = nil
            }
                .buttonStyle(.borderedProminent).controlSize(.small)

            Divider()
            TextField("빠른 기록", text: $note, axis: .vertical).lineLimit(1...3).textFieldStyle(.roundedBorder)
            Button("남기기") { if album.addManual(companionID: mon.id, body: note) { settings.recordManualMemoryCreated(); note = "" } }
                .buttonStyle(.borderedProminent).controlSize(.small).disabled(note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || note.count > 280)
        }.memoryHomePanel()
    }

    /// 닉네임 확정 = 저장 + **재광고**. Return 과 버튼 두 경로가 같은 규칙을 쓰도록 한 곳에 둔다.
    /// 재광고(`refreshAccess`)를 빠뜨리면 광고 중인 이름과 자기 필터가 갈라진다 — 이 화면이
    /// 그걸 기억해야 하는 구조 자체는 `MemoryHomeVisitCenter.advertisedServiceName` 이 막는다.
    private func commitNickname(_ album: PokemonMemoryAlbum) {
        guard album.setMemoryHomePublicNickname(nicknameDraft) else {
            nicknameError = "공백 없이 1~40자로 입력해 주세요."
            return
        }
        nicknameDraft = album.memoryHomePublicNickname
        nicknameError = nil
        visits.refreshAccess()
    }

    private func profile(mon: MonState) -> some View {
        let album = store.memoryAlbum
        return ScrollView { VStack(alignment: .leading, spacing: 14) {
            let log = album.pokeLog(for: mon.id)
            HStack(spacing: 12) {
                SpriteView(speciesID: mon.currentID, size: 72, shiny: mon.isShiny)
                VStack(alignment: .leading, spacing: 4) {
                    Text(store.chatProfile(for: mon).displayName).font(.title3.weight(.bold))
                    Text("함께한 \(log.daysTogether)일 · 기억 \(log.memoryCount)개")
                        .font(.caption).foregroundStyle(.secondary)
                    Text(roommateNames).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }.memoryHomePanel()
            VStack(alignment: .leading, spacing: 10) {
                Text("공개 프로필").font(.headline)
                // 확정할 때만 저장·재광고한다. 키 입력마다 `refreshAccess()` 를 부르면 글자 하나에
                // `NWListener` 를 한 번씩 취소·재등록해 mDNS 가 이름 충돌로 개명을 쌓는다.
                // 거부(공백·길이)도 조용히 삼키지 않고 이유를 적는다 — 안 적으면 필드가 고장 난 것처럼 보인다.
                HStack {
                    TextField("공개 닉네임", text: $nicknameDraft)
                        .onSubmit { commitNickname(album) }
                        // 고친 값 위에 옛 빨간 줄이 남으면 멀쩡한 필드가 고장 난 것처럼 보인다.
                        .onChange(of: nicknameDraft) { nicknameError = nil }
                    // 확정 버튼이 있어야 한다. `onSubmit` 만 두면 Return 을 누르지 않은 입력이
                    // 조용히 사라진다 — 탭을 옮기거나 팝오버를 닫으면 `onAppear` 가 draft 를
                    // 저장값으로 되돌리기 때문이다. 형제 필드(문구·방명록)는 모두 버튼을 갖고 있다.
                    Button("닉네임 저장") { commitNickname(album) }
                        .buttonStyle(.bordered).controlSize(.small)
                        .disabled(nicknameDraft == album.memoryHomePublicNickname)
                }
                if let nicknameError { Text(nicknameError).font(.caption).foregroundStyle(PokedoroTheme.red) }
                TextField("대문 문구", text: $profileMessageDraft)
                HStack {
                    Button("문구 저장") {
                        if album.setProfileMessage(profileMessageDraft) { profileMessageError = nil }
                        else { profileMessageError = "줄바꿈 없이 1~60자로 입력해 주세요." }
                    }.buttonStyle(.bordered).controlSize(.small)
                    // 저장한 문구를 **지우는** 길. `clearProfileMessage` 도 호출부가 없어서,
                    // 한 번 적은 대문 문구는 덮어쓸 수만 있고 내릴 수 없었다.
                    Button("문구 지우기") {
                        album.clearProfileMessage(); profileMessageDraft = ""; profileMessageError = nil
                    }.buttonStyle(.borderless).controlSize(.small)
                        .disabled(album.memoryHomeAccess.profileMessage == nil)
                    if let profileMessageError { Text(profileMessageError).font(.caption).foregroundStyle(PokedoroTheme.red) }
                }
                Toggle("대문 문구 LAN 공유", isOn: Binding(get: { album.memoryHomeAccess.sharesProfileMessage }, set: { album.setSharesProfileMessage($0) }))
                    .disabled(album.memoryHomeAccess.profileMessage == nil)
                if album.memoryHomeAccess.profileMessage == nil {
                    Text("대문 문구를 저장하면 같은 LAN 공유를 켤 수 있어요.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Toggle("홈 LAN 공개", isOn: Binding(get: { album.memoryHomeAccess.visibility == .open }, set: { album.setMemoryHomeVisibility($0 ? .open : .blocked); visits.refreshAccess() }))
            }.memoryHomePanel().onAppear {
                profileMessageDraft = album.memoryHomeAccess.profileMessage ?? ""
                nicknameDraft = album.memoryHomePublicNickname
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("함께한 발자국").font(.headline)
                MemoryHomeRule(label: "첫 만남", value: log.firstMetAt?.formatted(date: .abbreviated, time: .omitted) ?? "—")
                MemoryHomeRule(label: "집중", value: "\(log.completedFocusSessions)")
                MemoryHomeRule(label: "방문", value: "\(album.memoryHomeAccess.visitTotal)")
            }.memoryHomePanel()
            visitors(album)
            VStack(alignment: .leading, spacing: 5) {
                Text("개인정보").font(.headline)
                Text("수동 기억과 일촌명은 LAN에 공유되지 않습니다.").font(.callout).foregroundStyle(.secondary)
            }.memoryHomePanel()
        }.padding(18) }
    }

    /// 내 홈에 다녀간 사람들. `recentRequesters` 도 `blockedPeerIDs` 도 `peerAliases` 도 릴리스
    /// 내내 저장돼 왔지만 이 패널이 생기기 전까지 **어느 화면도 읽지 않았다** — TODAY/TOTAL 숫자만
    /// 오르고 누가 왔는지 알 수도, 차단할 수도 없었다.
    ///
    /// 별명은 이 Mac 에만 남는다(방명록과 같은 취급). 표시 이름은 남이 지은 문자열이지만 저장
    /// 시점에 `clean(_:limit: 40)` 을 통과한 값이라, 여기서는 줄 수만 제한한다.
    @ViewBuilder private func visitors(_ album: PokemonMemoryAlbum) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("다녀간 방문자", systemImage: "person.2.badge.key.fill").font(.headline)
            if album.memoryHomeAccess.recentRequesters.isEmpty {
                Text("아직 방문자가 없어요. 홈을 LAN에 공개하면 이웃이 찾아올 수 있어요.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(album.memoryHomeAccess.recentRequesters) { visitor in
                    let blocked = album.memoryHomeAccess.blockedPeerIDs.contains(visitor.peerID)
                    HStack(spacing: 8) {
                        Text(album.memoryHomeAccess.peerAliases[visitor.peerID] ?? visitor.displayName)
                            .font(.callout.weight(.semibold)).lineLimit(1)
                        // 확정할 때만 저장한다 — 키 입력마다 `setPeerAlias` 를 부르면 글자 하나에
                        // 세이브가 한 번씩 나간다(대문 문구·닉네임이 같은 규칙을 쓴다).
                        TextField("일촌명", text: Binding(
                            get: { aliasDrafts[visitor.peerID] ?? album.memoryHomeAccess.peerAliases[visitor.peerID] ?? "" },
                            set: { aliasDrafts[visitor.peerID] = $0 }))
                            .textFieldStyle(.roundedBorder).frame(width: 120)
                            .onSubmit { commitAlias(album, for: visitor.peerID) }
                        // 확정 버튼이 있어야 한다. `onSubmit` 만 두면 Return 을 누르지 않은 입력이
                        // 조용히 사라진다 — 닉네임·대문 문구가 같은 규칙을 쓴다.
                        Button("저장") { commitAlias(album, for: visitor.peerID) }
                            .buttonStyle(.borderless).controlSize(.small)
                            .disabled(aliasDrafts[visitor.peerID] == nil)
                        // 내리는 길도 있어야 한다 — `setPeerAlias` 는 빈 값을 거부하므로 지우기
                        // 버튼이 없으면 잘못 붙인 별명은 덮어쓸 수만 있다. 초안도 같이 버려야
                        // 필드가 방금 지운 값을 계속 보여 주지 않는다.
                        Button("지우기") {
                            aliasDrafts[visitor.peerID] = nil
                            album.clearPeerAlias(for: visitor.peerID)
                        }
                            .buttonStyle(.borderless).controlSize(.small)
                            .disabled(album.memoryHomeAccess.peerAliases[visitor.peerID] == nil)
                        Spacer()
                        Button(blocked ? "차단 해제" : "차단") {
                            album.setMemoryHomeBlocked(visitor.peerID, blocked: !blocked)
                        }
                        .buttonStyle(.bordered).controlSize(.small)
                        .accessibilityHint("차단하면 이 방문자에게 카드를 보내지 않습니다.")
                    }
                    .foregroundStyle(blocked ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                }
            }
        }.memoryHomePanel()
    }

    /// 초안을 버리는 것이 **성공·실패 양쪽의 마무리**다. 버리면 필드가 저장값으로 되돌아가므로,
    /// 거부된 값(빈 값·21자 이상·제어문자)이 저장된 것처럼 계속 남아 있지 않는다. 남겨 두면
    /// 이 창이 사는 내내 저장값을 가리므로 초안 사전도 함께 샌다.
    private func commitAlias(_ album: PokemonMemoryAlbum, for peerID: UUID) {
        guard let draft = aliasDrafts[peerID] else { return }
        _ = album.setPeerAlias(draft, for: peerID)
        aliasDrafts[peerID] = nil
    }

    // `pinned(for:)` 는 기억 배열(최대 200개)을 훑는다 — 일기 줄마다 부르면 줄 수 × 200 이다.
    private func records(mon: MonState) -> some View { let album = store.memoryAlbum; let log = album.pokeLog(for: mon.id); let pinnedID = album.pinned(for: mon.id)?.id; return ScrollView { LazyVStack(alignment: .leading, spacing: 12) { VStack(alignment: .leading, spacing: 8) { Text("기록").font(.title2.bold()); Text("매일의 기억과 함께한 발자국을 한곳에서 돌아봐요.") .font(.caption).foregroundStyle(.secondary); HStack { Button { recap = true } label: { Label("계절 결산 보기", systemImage: "calendar") }.buttonStyle(.bordered).controlSize(.small); Button { yearRecap = true } label: { Label("연말 결산 보기", systemImage: "sparkles.rectangle.stack") }.buttonStyle(.bordered).controlSize(.small).accessibilityHint("올해 함께한 기록을 한 장으로 봅니다.") }; Text("함께한 \(log.daysTogether)일 · 집중 \(log.completedFocusSessions)회 · 기억 \(log.memoryCount)개") }.memoryHomePanel(); if !log.milestones.isEmpty { VStack(alignment: .leading, spacing: 6) { Text("함께한 발자국").font(.headline); ForEach(log.milestones) { Label(MemoryHomeCardStyle.title($0), systemImage: MemoryHomeCardStyle.icon($0)) } }.memoryHomePanel() }; featuredMemory(mon: mon, album: album); ForEach(album.diary(for: mon.id)) { day in VStack(alignment: .leading, spacing: 5) { HStack { Text(day.date.formatted(date: .abbreviated, time: .omitted)).font(.headline); if let mood = day.mood { Text(MemoryHomeMoodStyle.emoji(mood)) } }; ForEach(day.memories) { memory in HStack(alignment: .top, spacing: 6) { Text("· \(memory.body)").font(.caption); Spacer(); Button { album.pin(memory) } label: { Image(systemName: pinnedID == memory.id ? "pin.fill" : "pin") }.buttonStyle(.borderless).accessibilityLabel(pinnedID == memory.id ? "대표 기억 고정 해제" : "대표 기억으로 고정") } } }.memoryHomePanel() } } }.padding(14) }

    /// 대표 기억과 그 LAN 공유. `pin`·`setSharedPinnedMemory`·`clearSharedPinnedMemory` 셋 다
    /// 호출부가 없어서, 카드의 `sharedMemoryBody` 는 릴리스 내내 **영구 nil** 이었다.
    ///
    /// 공유는 고정과 **별개의 동의**다 — 고정은 내 대문 장식이고, 공유는 남에게 보내는 일이다
    /// (대문 문구가 `sharesProfileMessage` 를 따로 두는 것과 같은 규칙).
    @ViewBuilder private func featuredMemory(mon: MonState, album: PokemonMemoryAlbum) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("대표 기억", systemImage: "pin.fill").font(.headline)
            if let pin = album.pinned(for: mon.id) {
                Text(pin.body).font(.callout).fixedSize(horizontal: false, vertical: true)
                Toggle("방문자에게 보이기", isOn: Binding(
                    get: { album.sharedPinnedMemory(for: mon.id) != nil },
                    set: { $0 ? album.setSharedPinnedMemory(pin, activeCompanionID: mon.id) : album.clearSharedPinnedMemory() }))
                    .accessibilityHint("켜면 같은 LAN의 방문자가 이 기억을 봅니다.")
                // 공유 동의는 **이 기억 하나**에만 붙는다. 대표를 바꾸면 새 기억은 아직 동의를
                // 받지 않았으므로 공유가 꺼진다 — 미리 적어 두지 않으면 사용자는 여전히 공유
                // 중이라고 믿는다.
                Text("대표 기억을 바꾸거나 내리면 이 공유는 꺼집니다.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("아래 기억의 핀을 눌러 대표로 고정해 보세요.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.memoryHomePanel()
    }
    private func photoTab(mon: MonState) -> some View { let album = store.memoryAlbum; return ScrollView { VStack(alignment: .leading, spacing: 16) { HStack { VStack(alignment: .leading, spacing: 4) { Text("포토부스").font(.title2.bold()); Text("트레이너와 동행의 구도·배경·프레임을 골라 전시해 보세요.") .font(.caption).foregroundStyle(.secondary) }; Spacer(); Button("사진 만들기") { photo = true }.buttonStyle(.borderedProminent) }.memoryHomePanel(); if album.memoryHomeAccess.photos.isEmpty { ContentUnavailableView("첫 사진을 전시해 보세요", systemImage: "photo.on.rectangle") } else { LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) { ForEach(album.memoryHomeAccess.photos) { shot in VStack(alignment: .leading, spacing: 6) { SpriteView(speciesID: shot.speciesID, size: 76, shiny: shot.isShiny).frame(maxWidth: .infinity); Label(shot.caption.isEmpty ? "POKÉDORO" : shot.caption, systemImage: "person.2.fill").font(.caption).lineLimit(2); Text(shot.createdAt.formatted(date: .abbreviated, time: .omitted)).font(.caption2).foregroundStyle(.secondary); HStack { let featured = album.memoryHomeAccess.featuredPhotoID == shot.id; Button { album.setFeaturedPhoto(id: featured ? nil : shot.id) } label: { Label(featured ? "대표 사진" : "대표로", systemImage: featured ? "star.fill" : "star") }.buttonStyle(.borderless).controlSize(.small).accessibilityHint("대표 사진은 방문자의 쇼룸에 걸립니다."); Spacer(); Button(role: .destructive) { album.deletePhoto(id: shot.id) } label: { Image(systemName: "trash") }.buttonStyle(.borderless).accessibilityLabel("사진 삭제") } }.memoryHomePanel() } } } }.padding(18) } }
    /// §13 방명록. 탭을 열 때 동행이 하루 한 번, 약 4일에 1번 흔적을 남긴다 — 판정은
    /// `MemoryHomeCompanionTrace` 의 dayKey 결정론이라 여닫아도 글이 늘지 않는다.
    private func guestbook(mon: MonState) -> some View { let album = store.memoryAlbum; return ScrollView { VStack(alignment: .leading, spacing: 14) { VStack(alignment: .leading, spacing: 8) { Label("방명록", systemImage: "text.bubble.fill").font(.title3.weight(.bold)); Text("내가 남긴 한마디를 모아 둬요. 이 글은 LAN에 공유되지 않습니다.") .font(.caption).foregroundStyle(.secondary); TextField("오늘의 한마디", text: $guestbookDraft, axis: .vertical).lineLimit(1...3).textFieldStyle(.roundedBorder); Button("내 이름으로 남기기") { if album.addGuestbookEntry(author: album.memoryHomePublicNickname, body: guestbookDraft, authorKind: .trainer) { guestbookDraft = "" } }.buttonStyle(.borderedProminent).controlSize(.small).disabled(guestbookDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || guestbookDraft.count > MemoryHomeAccessSettings.guestbookBodyLimit) }.memoryHomePanel(); if album.memoryHomeAccess.guestbookEntries.isEmpty { ContentUnavailableView("첫 방명록을 남겨 보세요", systemImage: "text.bubble") } else { ForEach(album.memoryHomeAccess.guestbookEntries) { entry in VStack(alignment: .leading, spacing: 5) { HStack { Label(entry.author, systemImage: entry.authorKind == .companion ? "pawprint.fill" : "person.fill").font(.subheadline.weight(.semibold)); Spacer(); Text(entry.createdAt.formatted(date: .abbreviated, time: .shortened)).font(.caption2).foregroundStyle(.secondary); Button { album.deleteGuestbookEntry(id: entry.id) } label: { Image(systemName: "xmark.circle") }.buttonStyle(.borderless).accessibilityLabel("방명록 삭제") }; Text(entry.body).font(.callout).fixedSize(horizontal: false, vertical: true) }.memoryHomePanel() } } }.padding(18) }.onAppear { _ = store.memoryAlbum.recordCompanionTraceIfNeeded(companionName: store.chatProfile(for: mon).displayName, l: l) } }
    private var visit: some View { ScrollView { VStack(alignment: .leading, spacing: 12) {
        VStack(alignment: .leading, spacing: 4) { Text("같은 LAN의 Memory Home").font(.headline); Text("홈을 고르고 공개된 쇼룸을 둘러보세요.").font(.caption).foregroundStyle(.secondary); surfRow }.memoryHomePanel()
        // 실패를 화면에 올린다. 이게 없으면 권한 거부(`NoAuth`)·거절·잘못된 페이로드가 전부
        // "주변 홈을 찾는 중이에요…" 한 줄로 뭉개져, 사용자에게는 원인 없는 무동작으로만 보인다.
        // `PlayerGymView`·`BattleView`·`GymLeagueView` 는 모두 이 줄을 갖고 있다.
        if let error = visits.lastError {
            Label(error, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange)
        }
        if let selected = visits.selectedProfile { remoteProfile(selected) }
        if visits.homes.isEmpty { ContentUnavailableView("주변 홈을 찾는 중이에요…", systemImage: "dot.radiowaves.left.and.right") } else { ForEach(visits.homes) { home in Button { visits.visit(home) } label: { Label(home.displayName, systemImage: "house.fill").frame(maxWidth: .infinity, alignment: .leading) }.buttonStyle(.bordered) } }
        footprints
    }.padding(18) }.onAppear { visits.start() }.onDisappear { visits.stop() } }

    /// §14 파도타기. 목록에서 한 채를 골라 누르는 것과 나란히 두는 이유는 둘이 다른 동작이기
    /// 때문이다 — 이쪽은 "누구든 다음 집" 이고, 오늘 아직 안 간 집을 먼저 고른다.
    private var surfRow: some View {
        HStack {
            Button { visits.surf() } label: { Label("파도타기", systemImage: "water.waves") }
                .buttonStyle(.borderedProminent).controlSize(.small)
                .accessibilityHint("오늘 아직 방문하지 않은 다음 홈으로 건너뜁니다.")
            Text("주변 \(visits.homes.count)채")
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
        }
    }

    /// 다녀온 집. 방문 도장(`visitedHomeStamps`)은 릴리스 내내 저장돼 왔지만 이 패널이 생기기
    /// 전까지 **어느 화면도 읽지 않았다** — 파도타기에 발자국이 없던 실제 이유다.
    @ViewBuilder private var footprints: some View {
        let prints = MemoryHomeSurf.footprints(from: store.memoryAlbum.memoryHomeAccess.visitedHomeStamps)
        if !prints.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Label("다녀온 홈", systemImage: "shoeprints.fill").font(.caption.weight(.bold))
                Text("이 발자국은 이 Mac에만 남고 LAN에 공유되지 않습니다.")
                    .font(.caption2).foregroundStyle(.secondary)
                ForEach(prints) { footprint in
                    HStack { Text(footprint.label).font(.caption).lineLimit(1); Spacer(); Text(footprint.at.formatted(date: .abbreviated, time: .shortened)).font(.caption2).foregroundStyle(.secondary) }
                }
            }.memoryHomePanel()
        }
    }

    private func remoteProfile(_ card: MemoryHomeProfileCard) -> some View { VStack(alignment: .leading, spacing: 8) {
        HStack { SpriteView(speciesID: card.speciesID, size: 72, shiny: card.isShiny); VStack(alignment: .leading) { Text(card.displayName).font(.title3.bold()); Text(card.profileMessage ?? "환영합니다!").foregroundStyle(.secondary) } }
        if card.roomStyle != nil || !card.placedDecor.isEmpty || card.featuredPhoto != nil { remoteShowroom(card) }
        else if !card.showcaseFurniture.isEmpty { HStack { ForEach(card.showcaseFurniture, id: \.self) { furnitureIcon($0, style: .campus, scale: MemoryHomePixelArt.thumbnailScale, emojiSize: 22).frame(width: 42, height: 42) } } }
        if let memory = card.sharedMemoryBody { Text(memory).font(.caption) }
    }.memoryHomePanel() }

    private func remoteShowroom(_ card: MemoryHomeProfileCard) -> some View { VStack(alignment: .leading, spacing: 8) {
        Label("공개 미니룸 쇼케이스", systemImage: "house.fill").font(.caption.weight(.bold))
        GeometryReader { proxy in ZStack { RoundedRectangle(cornerRadius: 10).fill(MemoryHomeRoomTheme.tint(for: card.roomTheme ?? .blue).opacity(0.18)); ForEach(card.placedDecor.sorted { $0.layer < $1.layer }) { decor in furnitureIcon(decor.item, style: card.roomStyle ?? .campus, scale: MemoryHomePixelArt.thumbnailScale, emojiSize: 22).frame(width: 42, height: 42).position(x: decor.position.x * proxy.size.width, y: decor.position.y * proxy.size.height) } } }.frame(height: 130)
        if let photo = card.featuredPhoto { MemoryHomeRemotePhoto(photo: photo).frame(height: 160) }
    } }
    private var roommates: [MonState] {
        let ids = store.memoryAlbum.memoryHomeAccess.roommateIDs
        return store.ownedMons.filter { ids.contains($0.id) && $0.id != store.state.active?.id }
    }
    private var roommateNames: String { let names = roommates.map { store.chatProfile(for: $0).displayName }; return names.isEmpty ? "아직 없어요" : names.joined(separator: ", ") }
    private func currentMoodLabel(_ album: PokemonMemoryAlbum) -> String {
        guard let mood = album.mood() else { return "기분을 골라 주세요" }
        return "\(MemoryHomeMoodStyle.emoji(mood)) \(MemoryHomeMoodStyle.name(mood))"
    }
    private func setRoommate(_ id: UUID, included: Bool) {
        let album = store.memoryAlbum
        var ids = album.memoryHomeAccess.roommateIDs.filter { $0 != store.state.active?.id }
        if included { ids.append(id) } else { ids.removeAll { $0 == id } }
        album.setRoommates(ids, validCompanionIDs: Set(store.ownedMons.map(\.id)))
    }
}

private struct MemoryHomeRule: View { let label: String; let value: String; var body: some View { HStack { Text(label).font(.caption).foregroundStyle(.secondary); Spacer(); Text(value).font(.caption.weight(.medium)).lineLimit(1) } } }

/// Remote cards carry composition metadata, never image bytes. Reusing the local photo canvas
/// keeps a LAN featured shot faithful to its owner-selected frame, background and caption.
private struct MemoryHomeRemotePhoto: View {
    let photo: MemoryHomePhoto
    @State private var sprite: NSImage?

    var body: some View {
        StickerPhotoCanvas(sprite: sprite, caption: photo.caption,
                           frame: StickerPhotoFrame(rawValue: photo.frame) ?? .heart,
                           background: photo.background, composition: photo.composition,
                           trainerStyle: photo.trainerStyle)
            .task { sprite = await SpriteLoader.image(speciesID: photo.speciesID, shiny: photo.isShiny) }
    }
}
private extension View {
    func memoryHomePanel() -> some View {
        padding(12).pokedoroCard()
    }
}
