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

    init(settings: AppSettings, store: CompanionStore, visits: MemoryHomeVisitCenter) {
        self.settings = settings
        self.store = store
        self.visits = visits
    }

    func open() {
        let window = window ?? makeWindow()
        self.window = window
        if window.contentView == nil { installContent(in: window) }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        settings.recordMemoryHomeEntry()
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1_040, height: 720),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "Poké Home"
        window.minSize = NSSize(width: 900, height: 640)
        window.setFrameAutosaveName("MemoryHomeWindow")
        window.isReleasedWhenClosed = false
        window.delegate = self
        installContent(in: window)
        window.center()
        return window
    }

    private func installContent(in window: NSWindow) {
        window.contentViewController = NSHostingController(rootView:
            MemoryHomeWindowView(store: store, visits: visits)
                .environment(settings)
                .environment(store)
                .environment(visits)
                .environment(\.locale, store.language.displayLocale))
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
                Text(album.memoryHomeAccess.profileMessage ?? l.t("우리의 작은 포케 홈", "Our little Poké Home", "ふたりの小さなポケホーム"))
                    .font(.caption).lineLimit(1)
                if let pinned = album.pinned(for: mon.id) {
                    Label(pinned.body, systemImage: "pin.fill")
                        .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                Button(action: openHome) {
                    Label(l.t("미니홈피 열기", "Open Poké Home", "ポケホームを開く"), systemImage: "arrow.up.forward.app")
                }
                .buttonStyle(.borderedProminent).controlSize(.small)
                .accessibilityHint(l.t("전용 Memory Home 창을 엽니다.", "Opens the dedicated Memory Home window.", "専用Memory Homeウインドウを開きます。"))
            }
            .padding(10)
            .pokedoroCard(tint: PokedoroTheme.mint)
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
    @State private var editingRoom = false

    private var l: L { store.l }

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                header
                tabBar
                Group {
                    if let mon = store.state.active { tabContent(mon: mon, width: proxy.size.width) }
                    else { ContentUnavailableView(l.t("동행을 기다리고 있어요", "Waiting for a companion", "相棒を待っています"), systemImage: "house") }
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
                Text(access.profileMessage ?? l.t("기억을 모으는 작은 방", "A little room for memories", "思い出を集める小さな部屋"))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Label(access.visibility == .open ? l.t("LAN 공개", "LAN open", "LAN公開") : l.t("LAN 차단", "LAN blocked", "LANブロック"),
                  systemImage: access.visibility == .open ? "dot.radiowaves.left.and.right" : "lock.fill")
                .font(.caption2.weight(.medium)).foregroundStyle(.secondary)
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(Color.primary.opacity(0.055), in: Capsule())
                .accessibilityLabel(l.t("공유 상태", "Sharing status", "共有状態"))
            Button { tab = .profile } label: { Image(systemName: "gearshape") }
                .buttonStyle(.borderless).controlSize(.small)
                .frame(minWidth: 28, minHeight: 28)
                .accessibilityLabel(l.t("홈 설정", "Home settings", "ホーム設定"))
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
                        .accessibilityValue(tab == item ? l.t("현재 탭", "Current tab", "現在のタブ") : "")
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
                VStack(spacing: 12) { profilePanel(mon: mon); roomStage(mon: mon); sidePanel(mon: mon) }
            } else {
                HStack(alignment: .top, spacing: 12) {
                    profilePanel(mon: mon).frame(width: 164)
                    roomStage(mon: mon).frame(maxWidth: .infinity)
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
                    Text("\(log.daysTogether) \(l.t("일 함께", "days together", "日いっしょ"))").font(.caption2).foregroundStyle(.secondary)
                }
            }
            MemoryHomeRule(label: l.t("친밀도", "Closeness", "なかよし度"), value: String(repeating: "♥", count: log.closenessHearts) + String(repeating: "♡", count: 5 - log.closenessHearts))
            let mood = store.memoryAlbum.mood()
            MemoryHomeRule(label: l.t("현재 기분", "Mood", "今の気分"), value: mood.map { MemoryHomeMoodStyle.emoji($0) + " " + MemoryHomeMoodStyle.name($0, l) } ?? "—")
            Button(l.t("프로필 보기", "View profile", "プロフィールを見る")) { tab = .profile }
                .buttonStyle(.bordered).controlSize(.small)
        }.memoryHomePanel()
    }

    private func roomStage(mon: MonState) -> some View {
        let album = store.memoryAlbum
        let tint = MemoryHomeRoomTheme.tint(for: album.theme(for: mon.id))
        return ZStack {
            tint.opacity(0.18)
            if let art = MemoryHomeBundledArt.interiorTileset() { Image(nsImage: art).resizable().interpolation(.none).scaledToFill().opacity(0.32) }
            Rectangle().fill(tint.opacity(0.34)).frame(height: 34).frame(maxHeight: .infinity, alignment: .bottom)
            GeometryReader { geometry in
                ForEach(["left", "center", "right"], id: \.self) { slot in
                    if let item = album.memoryHomeAccess.roomLayout[slot], let art = MemoryHomeBundledArt.furnitureImage(for: item) {
                        let point = album.furniturePosition(for: slot)
                        Image(nsImage: art).resizable().interpolation(.none).scaledToFit().frame(width: 74, height: 74)
                            .position(x: point.x * geometry.size.width, y: point.y * geometry.size.height)
                            .gesture(editingRoom ? DragGesture().onEnded { value in
                                album.setFurniturePosition(.clamped(x: value.location.x / geometry.size.width, y: value.location.y / geometry.size.height), in: slot)
                            } : nil)
                    }
                }
                let companions = [mon] + Array(roommates.prefix(2))
                ForEach(Array(companions.enumerated()), id: \.element.id) { index, companion in
                    let point = album.companionPosition(for: companion.id, fallbackIndex: index)
                    SpriteView(speciesID: companion.currentID, size: companion.id == mon.id ? 128 : 78, shiny: companion.isShiny)
                        .position(x: point.x * geometry.size.width, y: point.y * geometry.size.height)
                        .gesture(editingRoom ? DragGesture().onEnded { value in
                            album.setCompanionPosition(.clamped(x: value.location.x / geometry.size.width, y: value.location.y / geometry.size.height), for: companion.id, validCompanionIDs: Set(store.ownedMons.map(\.id)))
                        } : nil)
                }
            }
            VStack { HStack { Text(l.t("미니룸", "Mini room", "ミニルーム")).font(.caption.weight(.semibold)); Spacer() }; Spacer() }.padding(12)
            VStack { Spacer(); Text(roomInteraction(mon: mon)).font(.caption.weight(.medium)).padding(.horizontal, 9).padding(.vertical, 5).background(.black.opacity(0.12), in: Capsule()).padding(12) }
            if editingRoom { VStack { HStack { Spacer(); Text(l.t("가구와 동행을 드래그해 배치하세요", "Drag furniture and companions to arrange", "家具と相棒をドラッグして配置")) .font(.caption.weight(.semibold)).padding(8).background(.ultraThinMaterial, in: Capsule()) }; Spacer() }.padding(12) }
        }
        .frame(minHeight: 365)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .pokedoroCard(tint: tint, emphasized: true)
        .accessibilityLabel(l.t("가구와 동행이 배치된 미니룸", "Mini room with furniture and companions", "家具と相棒を配置したミニルーム"))
    }

    @ViewBuilder private func roomObject(_ slot: String) -> some View {
        if let item = store.memoryAlbum.memoryHomeAccess.roomLayout[slot], let art = MemoryHomeBundledArt.furnitureImage(for: item) {
            Image(nsImage: art).resizable().interpolation(.none).scaledToFit().frame(width: 74, height: 74)
        }
    }

    private func sidePanel(mon: MonState) -> some View {
        let album = store.memoryAlbum
        let timeline = album.timeline(for: mon.id)
        return VStack(alignment: .leading, spacing: 10) {
            Text(l.t("기억 보드", "Memory board", "思い出ボード")).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            if let pin = album.pinned(for: mon.id) { Label(pin.body, systemImage: "pin.fill").font(.caption).lineLimit(3) }
            Divider()
            Text(l.t("최근 기억", "Recent", "最近の記憶")).font(.caption.weight(.bold))
            ForEach(timeline.prefix(3)) { Text("· \($0.body)").font(.caption2).lineLimit(2) }
            if !album.milestones(for: mon.id).isEmpty { Label("\(album.milestones(for: mon.id).count) \(l.t("열린 카드", "cards unlocked", "枚のカード"))", systemImage: "rectangle.stack.fill").font(.caption) }
            Divider()
            Text(l.t("오늘의 기분", "Today's mood", "今日の気分"))
                .font(.caption.weight(.bold))
            Menu {
                ForEach(MemoryHomeMood.allCases, id: \.self) { mood in
                    Button {
                        album.setMood(mood)
                    } label: {
                        Text("\(MemoryHomeMoodStyle.emoji(mood)) \(MemoryHomeMoodStyle.name(mood, l))")
                    }
                }
            } label: {
                Label(currentMoodLabel(album), systemImage: "face.smiling")
            }
            .menuStyle(.borderedButton)
            .controlSize(.small)
            .accessibilityHint(l.t("기분에 따라 동행의 방명록과 반응이 달라집니다.", "Your companion reacts differently in the guestbook and room.", "気分で相棒の反応とゲストブックが変わります。"))

            Divider()
            Text(l.t("미니룸 꾸미기", "Mini room", "ミニルームを飾る"))
                .font(.caption.weight(.bold))
            Button(editingRoom ? l.t("꾸미기 완료", "Done decorating", "模様替えを完了") : l.t("배치 편집", "Edit layout", "配置を編集")) { editingRoom.toggle() }
                .buttonStyle(.borderedProminent).controlSize(.small)
            Menu(l.t("룸메이트", "Roommates", "ルームメイト")) {
                ForEach(store.ownedMons.filter { $0.id != mon.id }) { candidate in
                    let included = album.memoryHomeAccess.roommateIDs.contains(candidate.id)
                    Button {
                        setRoommate(candidate.id, included: !included)
                    } label: {
                        Label(store.chatProfile(for: candidate).displayName,
                              systemImage: included ? "checkmark.circle.fill" : "circle")
                    }
                }
            }
            .menuStyle(.borderedButton)
            .controlSize(.small)

            ForEach(["left", "center", "right"], id: \.self) { slot in
                Menu(roomSlotName(slot)) {
                    Button(l.t("비우기", "Clear", "空にする")) {
                        album.setFurniture(nil, in: slot, ownedItems: store.state.inventory)
                    }
                    ForEach([ItemKind.roomBed, .roomTable, .roomLamp], id: \.self) { item in
                        Button(l.itemName(item)) {
                            album.setFurniture(item, in: slot, ownedItems: store.state.inventory)
                        }
                        .disabled(store.state.inventory[item.rawValue, default: 0] <= 0)
                    }
                }
                .menuStyle(.borderedButton)
                .controlSize(.small)
                .accessibilityLabel(roomSlotName(slot))
            }

            Divider()
            TextField(l.t("빠른 기록", "Quick note", "クイックメモ"), text: $note, axis: .vertical).lineLimit(1...3).textFieldStyle(.roundedBorder)
            Button(l.t("남기기", "Save", "保存")) { if album.addManual(companionID: mon.id, body: note) { settings.recordManualMemoryCreated(); note = "" } }
                .buttonStyle(.borderedProminent).controlSize(.small).disabled(note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || note.count > 280)
        }.memoryHomePanel()
    }

    private func profile(mon: MonState) -> some View {
        let album = store.memoryAlbum
        return ScrollView { VStack(alignment: .leading, spacing: 14) {
            let log = album.pokeLog(for: mon.id)
            HStack(spacing: 12) {
                SpriteView(speciesID: mon.currentID, size: 72, shiny: mon.isShiny)
                VStack(alignment: .leading, spacing: 4) {
                    Text(store.chatProfile(for: mon).displayName).font(.title3.weight(.bold))
                    Text(l.t("함께한 \(log.daysTogether)일 · 기억 \(log.memoryCount)개", "\(log.daysTogether) days · \(log.memoryCount) memories", "いっしょに\(log.daysTogether)日・記憶\(log.memoryCount)件"))
                        .font(.caption).foregroundStyle(.secondary)
                    Text(roommateNames).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }.memoryHomePanel(tint: PokedoroTheme.yellow)
            VStack(alignment: .leading, spacing: 10) {
                Text(l.t("공개 프로필", "Public profile", "公開プロフィール")).font(.headline)
                TextField(l.t("공개 닉네임", "Public nickname", "公開ニックネーム"), text: Binding(get: { album.memoryHomePublicNickname }, set: { _ = album.setMemoryHomePublicNickname($0); visits.refreshAccess() }))
                TextField(l.t("대문 문구", "Home message", "ホームの一言"), text: $profileMessageDraft)
                HStack {
                    Button(l.t("문구 저장", "Save message", "一言を保存")) {
                        if album.setProfileMessage(profileMessageDraft) { profileMessageError = nil }
                        else { profileMessageError = l.t("줄바꿈 없이 1~60자로 입력해 주세요.", "Use 1–60 characters without line breaks.", "改行なしで1〜60文字にしてください。") }
                    }.buttonStyle(.bordered).controlSize(.small)
                    if let profileMessageError { Text(profileMessageError).font(.caption).foregroundStyle(PokedoroTheme.red) }
                }
                Toggle(l.t("대문 문구 LAN 공유", "Share home message on LAN", "一言をLAN共有"), isOn: Binding(get: { album.memoryHomeAccess.sharesProfileMessage }, set: { album.setSharesProfileMessage($0) }))
                    .disabled(album.memoryHomeAccess.profileMessage == nil)
                if album.memoryHomeAccess.profileMessage == nil {
                    Text(l.t("대문 문구를 저장하면 같은 LAN 공유를 켤 수 있어요.", "Save a home message before enabling LAN sharing.", "一言を保存するとLAN共有を有効にできます。"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Toggle(l.t("홈 LAN 공개", "Open home on LAN", "ホームをLAN公開"), isOn: Binding(get: { album.memoryHomeAccess.visibility == .open }, set: { album.setMemoryHomeVisibility($0 ? .open : .blocked); visits.refreshAccess() }))
            }.memoryHomePanel(tint: PokedoroTheme.mint).onAppear { profileMessageDraft = album.memoryHomeAccess.profileMessage ?? "" }
            VStack(alignment: .leading, spacing: 8) {
                Text(l.t("함께한 발자국", "Our journey", "ふたりのあしあと")).font(.headline)
                MemoryHomeRule(label: l.t("첫 만남", "First met", "出会い"), value: log.firstMetAt?.formatted(date: .abbreviated, time: .omitted) ?? "—")
                MemoryHomeRule(label: l.t("집중", "Focus", "集中"), value: "\(log.completedFocusSessions)")
                MemoryHomeRule(label: l.t("방문", "Visits", "訪問"), value: "\(album.memoryHomeAccess.visitTotal)")
            }.memoryHomePanel(tint: PokedoroTheme.yellow)
            VStack(alignment: .leading, spacing: 5) {
                Text(l.t("개인정보", "Privacy", "プライバシー")).font(.headline)
                Text(l.t("수동 기억과 일촌명은 LAN에 공유되지 않습니다.", "Manual memories and peer aliases are never shared on LAN.", "手動の思い出と一村名はLAN共有されません。")).font(.callout).foregroundStyle(.secondary)
            }.memoryHomePanel(tint: PokedoroTheme.blue)
        }.padding(18) }
    }

    private func records(mon: MonState) -> some View { let album = store.memoryAlbum; let log = album.pokeLog(for: mon.id); return ScrollView { LazyVStack(alignment: .leading, spacing: 12) { VStack(alignment: .leading, spacing: 8) { Text(l.t("기록", "Records", "記録")).font(.title2.bold()); Text(l.t("매일의 기억과 함께한 발자국을 한곳에서 돌아봐요.", "Revisit daily memories and milestones in one place.", "毎日の思い出とふたりのあしあとを一緒に振り返ります。")) .font(.caption).foregroundStyle(.secondary); Text(l.t("함께한 \(log.daysTogether)일 · 집중 \(log.completedFocusSessions)회 · 기억 \(log.memoryCount)개", "\(log.daysTogether) days · \(log.completedFocusSessions) focus sessions · \(log.memoryCount) memories", "いっしょに\(log.daysTogether)日・集中\(log.completedFocusSessions)回・記憶\(log.memoryCount)件")) }.memoryHomePanel(tint: PokedoroTheme.red); if !log.milestones.isEmpty { VStack(alignment: .leading, spacing: 6) { Text(l.t("함께한 발자국", "Milestones", "あしあと")).font(.headline); ForEach(log.milestones) { Label(MemoryHomeCardStyle.title($0, l), systemImage: MemoryHomeCardStyle.icon($0)) } }.memoryHomePanel(tint: PokedoroTheme.yellow) }; ForEach(album.diary(for: mon.id)) { day in VStack(alignment: .leading, spacing: 5) { HStack { Text(day.date.formatted(date: .abbreviated, time: .omitted)).font(.headline); if let mood = day.mood { Text(MemoryHomeMoodStyle.emoji(mood)) } }; ForEach(day.memories) { Text("· \($0.body)").font(.caption) } }.memoryHomePanel() } } }.padding(14) }
    private func photoTab(mon: MonState) -> some View { let album = store.memoryAlbum; return ScrollView { VStack(alignment: .leading, spacing: 16) { HStack { VStack(alignment: .leading, spacing: 4) { Text(l.t("포토부스", "Photo booth", "フォトブース")).font(.title2.bold()); Text(l.t("트레이너와 동행의 구도·배경·프레임을 골라 전시해 보세요.", "Choose a trainer, companion, composition and background, then exhibit the shot.", "トレーナーと相棒の構図・背景・フレームを選んで展示しましょう。")) .font(.caption).foregroundStyle(.secondary) }; Spacer(); Button(l.t("사진 만들기", "Make photo", "写真を作る")) { photo = true }.buttonStyle(.borderedProminent) }.memoryHomePanel(tint: PokedoroTheme.yellow); if album.memoryHomeAccess.photos.isEmpty { ContentUnavailableView(l.t("첫 사진을 전시해 보세요", "Exhibit your first photo", "最初の写真を展示しましょう"), systemImage: "photo.on.rectangle") } else { LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) { ForEach(album.memoryHomeAccess.photos) { shot in VStack(alignment: .leading, spacing: 6) { SpriteView(speciesID: shot.speciesID, size: 76, shiny: shot.isShiny).frame(maxWidth: .infinity); Label(shot.caption.isEmpty ? "POKÉDORO" : shot.caption, systemImage: "person.2.fill").font(.caption).lineLimit(2); Text(shot.createdAt.formatted(date: .abbreviated, time: .omitted)).font(.caption2).foregroundStyle(.secondary); Button(role: .destructive) { album.deletePhoto(id: shot.id) } label: { Image(systemName: "trash") }.buttonStyle(.borderless).accessibilityLabel(l.t("사진 삭제", "Delete photo", "写真を削除")) }.memoryHomePanel(tint: PokedoroTheme.mint) } } } }.padding(18) } }
    private func guestbook(mon: MonState) -> some View { let album = store.memoryAlbum; return ScrollView { VStack(alignment: .leading, spacing: 14) { VStack(alignment: .leading, spacing: 8) { Label(l.t("방명록", "Guestbook", "ゲストブック"), systemImage: "text.bubble.fill").font(.title3.weight(.bold)); Text(l.t("내가 남긴 한마디를 모아 둬요. 이 글은 LAN에 공유되지 않습니다.", "Keep your notes here. They stay on this device.", "自分のひとことを残します。LANには共有されません。")) .font(.caption).foregroundStyle(.secondary); TextField(l.t("오늘의 한마디", "Leave a note", "今日のひとこと"), text: $guestbookDraft, axis: .vertical).lineLimit(1...3).textFieldStyle(.roundedBorder); Button(l.t("내 이름으로 남기기", "Sign as me", "自分の名前で残す")) { if album.addGuestbookEntry(author: album.memoryHomePublicNickname, body: guestbookDraft, authorKind: .trainer) { guestbookDraft = "" } }.buttonStyle(.borderedProminent).controlSize(.small).disabled(guestbookDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || guestbookDraft.count > MemoryHomeAccessSettings.guestbookBodyLimit) }.memoryHomePanel(tint: PokedoroTheme.yellow); if album.memoryHomeAccess.guestbookEntries.isEmpty { ContentUnavailableView(l.t("첫 방명록을 남겨 보세요", "Leave the first note", "最初のひとことを残しましょう"), systemImage: "text.bubble") } else { ForEach(album.memoryHomeAccess.guestbookEntries) { entry in VStack(alignment: .leading, spacing: 5) { HStack { Label(entry.author, systemImage: entry.authorKind == .companion ? "pawprint.fill" : "person.fill").font(.subheadline.weight(.semibold)); Spacer(); Text(entry.createdAt.formatted(date: .abbreviated, time: .shortened)).font(.caption2).foregroundStyle(.secondary); Button { album.deleteGuestbookEntry(id: entry.id) } label: { Image(systemName: "xmark.circle") }.buttonStyle(.borderless).accessibilityLabel(l.t("방명록 삭제", "Delete guestbook note", "メモを削除")) }; Text(entry.body).font(.callout).fixedSize(horizontal: false, vertical: true) }.memoryHomePanel(tint: entry.authorKind == .companion ? PokedoroTheme.mint : PokedoroTheme.blue) } } }.padding(18) } }
    private var visit: some View { ScrollView { VStack(alignment: .leading, spacing: 12) { VStack(alignment: .leading, spacing: 4) { Text(l.t("같은 LAN의 Memory Home", "Memory Homes on this LAN", "同じLANのMemory Home")).font(.headline); Text(l.t("홈을 고르고, 공개된 대표 동행과 미니룸 쇼케이스를 둘러보세요. 수집한 방문 도장 \(store.memoryAlbum.memoryHomeAccess.visitedHomeStamps.count)개", "Choose a home and explore its public companion and mini-room showcase. \(store.memoryAlbum.memoryHomeAccess.visitedHomeStamps.count) visit stamps collected.", "ホームを選び、公開された相棒とミニルームを見て回りましょう。訪問スタンプ\(store.memoryAlbum.memoryHomeAccess.visitedHomeStamps.count)個を集めました。")) .font(.caption).foregroundStyle(.secondary) }.memoryHomePanel(tint: PokedoroTheme.blue); if let selected = visits.selectedProfile { VStack(alignment: .leading, spacing: 8) { HStack { SpriteView(speciesID: selected.speciesID, size: 72, shiny: selected.isShiny); VStack(alignment: .leading) { Text(selected.displayName).font(.title3.bold()); Text(selected.profileMessage ?? l.t("환영합니다!", "Welcome!", "ようこそ！")).foregroundStyle(.secondary) } }; if let theme = selected.roomTheme { Label(l.t("공개 미니룸 쇼케이스", "Public mini-room showcase", "公開ミニルームショーケース"), systemImage: "house.fill").font(.caption.weight(.bold)); HStack { ForEach(selected.showcaseFurniture, id: \.self) { item in if let art = MemoryHomeBundledArt.furnitureImage(for: item) { Image(nsImage: art).resizable().interpolation(.none).scaledToFit().frame(width: 42, height: 42) } } }.padding(8).frame(maxWidth: .infinity, alignment: .leading).background(MemoryHomeRoomTheme.tint(for: theme).opacity(0.18), in: RoundedRectangle(cornerRadius: 10)) }; if let memory = selected.sharedMemoryBody { Text(memory).font(.caption) } }.memoryHomePanel(tint: PokedoroTheme.mint) }; if visits.homes.isEmpty { ContentUnavailableView(l.t("주변 홈을 찾는 중이에요…", "Looking for homes…", "近くのホームを探しています…"), systemImage: "dot.radiowaves.left.and.right") } else { ForEach(visits.homes) { home in Button { visits.visit(home) } label: { Label(home.displayName, systemImage: "house.fill").frame(maxWidth: .infinity, alignment: .leading) }.buttonStyle(.bordered).controlSize(.regular) } } }.padding(18) }.onAppear { visits.start() }.onDisappear { visits.stop() } }
    private var roommates: [MonState] {
        let ids = store.memoryAlbum.memoryHomeAccess.roommateIDs
        return store.ownedMons.filter { ids.contains($0.id) && $0.id != store.state.active?.id }
    }
    private var roommateNames: String { let names = roommates.map { store.chatProfile(for: $0).displayName }; return names.isEmpty ? l.t("아직 없어요", "None yet", "まだいません") : names.joined(separator: ", ") }
    private func currentMoodLabel(_ album: PokemonMemoryAlbum) -> String {
        guard let mood = album.mood() else { return l.t("기분을 골라 주세요", "Choose a mood", "気分を選ぶ") }
        return "\(MemoryHomeMoodStyle.emoji(mood)) \(MemoryHomeMoodStyle.name(mood, l))"
    }
    private func setRoommate(_ id: UUID, included: Bool) {
        let album = store.memoryAlbum
        var ids = album.memoryHomeAccess.roommateIDs.filter { $0 != store.state.active?.id }
        if included { ids.append(id) } else { ids.removeAll { $0 == id } }
        album.setRoommates(ids, validCompanionIDs: Set(store.ownedMons.map(\.id)))
    }
    private func roomSlotName(_ slot: String) -> String {
        switch slot {
        case "left": l.t("왼쪽 자리", "Left spot", "左の場所")
        case "center": l.t("가운데 자리", "Center spot", "中央の場所")
        default: l.t("오른쪽 자리", "Right spot", "右の場所")
        }
    }
    private func companionGuestbookLine(_ mon: MonState) -> String {
        switch store.memoryAlbum.mood() {
        case .excited: return l.t("오늘 진짜 신났어!", "Today was so fun!", "今日はすごく楽しかった！")
        case .down: return l.t("옆에 있을게.", "I'll stay by your side.", "そばにいるよ。")
        case .fluttering: return l.t("두근두근, 또 놀자!", "My heart's racing—let's play again!", "どきどき、また遊ぼう！")
        case .annoyed: return l.t("잠깐 쉬고 다시 놀자.", "Let's take a break, then play again.", "少し休んで、また遊ぼう。")
        case .calm, .none: return l.t("오늘도 같이 있어서 좋았어.", "I'm glad we were together today.", "今日も一緒でよかった。")
        }
    }
    private func roomInteraction(mon _: MonState) -> String {
        let layout = store.memoryAlbum.memoryHomeAccess.roomLayout
        if layout.values.contains(.roomBed) { return l.t("침대 옆에서 꾸벅꾸벅 졸고 있어요.", "Dozing off by the bed.", "ベッドのそばでうとうとしています。") }
        if layout.values.contains(.roomLamp) { return l.t("램프 불빛 아래서 쉬고 있어요.", "Resting under the lamp.", "ランプの灯りで休んでいます。") }
        if layout.values.contains(.roomTable) { return l.t("테이블 주변을 기웃거리고 있어요.", "Poking around the table.", "テーブルのまわりをうろうろしています。") }
        return l.t("방을 천천히 둘러보고 있어요.", "Looking around the room.", "部屋をゆっくり見回しています。")
    }
}

private struct MemoryHomeRule: View { let label: String; let value: String; var body: some View { HStack { Text(label).font(.caption).foregroundStyle(.secondary); Spacer(); Text(value).font(.caption.weight(.medium)).lineLimit(1) } } }
private extension View {
    func memoryHomePanel(tint: Color = PokedoroTheme.blue) -> some View {
        padding(12).pokedoroCard(tint: tint)
    }
}
