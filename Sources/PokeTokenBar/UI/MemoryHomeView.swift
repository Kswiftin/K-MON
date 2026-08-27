import SwiftUI

enum MemoryHomeRoomTheme {
    static func tint(for theme: PokemonMemoryRoomTheme) -> Color {
        switch theme {
        case .blue: PokedoroTheme.blue
        case .mint: PokedoroTheme.mint
        case .yellow: PokedoroTheme.yellow
        case .red: PokedoroTheme.red
        }
    }
}

/// 카드 아이콘·제목. `Kind` 에 케이스를 더하면 여기 `switch` 가 컴파일 에러로 알려 주고,
/// 테스트가 세 언어 문구까지 확인한다 — 뷰 안 `private` 함수였을 때는 둘 다 없었다.
enum MemoryHomeCardStyle {
    static func icon(_ milestone: PokemonMemoryMilestone) -> String {
        switch milestone.kind {
        case .firstMeeting: "person.2.fill"
        case .focusSessions: "timer"
        case .evolution: "arrow.triangle.2.circlepath"
        case .anniversary: "sparkles"
        case .togetherDays: "heart.circle.fill"
        case .homeVisits: "figure.wave"
        }
    }

    static func title(_ milestone: PokemonMemoryMilestone, _ l: L) -> String {
        switch milestone.kind {
        case .firstMeeting: l.t("첫 만남", "First meeting", "最初の出会い")
        case .focusSessions(let count): l.t("집중 모험 \(count)회", "\(count) focus adventures", "集中冒険 \(count) 回")
        case .evolution: l.t("진화의 순간", "Evolution moment", "進化の瞬間")
        case .anniversary: l.t("첫 만남 1주년", "First-meeting anniversary", "最初の出会い 1周年")
        case .togetherDays(let days): l.t("함께한 \(days)일", "\(days) days together", "いっしょに \(days) 日")
        case .homeVisits(let count): l.t("방문 \(count)명 달성", "\(count) home visits", "訪問 \(count) 件達成")
        }
    }
}

/// 뷰 안의 `private` 함수로 두면 세 언어 문구가 무테스트로 남는다 — `MemoryHomeRoomTheme` 와 같은
/// 이유로 파일 스코프의 순수 헬퍼로 뺀다. 종별 반응은 없다: 1000종 × 5기분은 헤더의 범위가 아니다.
enum MemoryHomeMoodStyle {
    static func emoji(_ mood: MemoryHomeMood) -> String {
        switch mood {
        case .excited: "😊"
        case .calm: "😌"
        case .down: "😢"
        case .annoyed: "😡"
        case .fluttering: "💗"
        }
    }

    static func name(_ mood: MemoryHomeMood, _ l: L) -> String {
        switch mood {
        case .excited: l.t("신남", "Excited", "うきうき")
        case .calm: l.t("평범", "Calm", "ふつう")
        case .down: l.t("우울", "Down", "しずんだ")
        case .annoyed: l.t("짜증", "Annoyed", "いらいら")
        case .fluttering: l.t("설렘", "Fluttering", "どきどき")
        }
    }

    static func reaction(_ mood: MemoryHomeMood, companion: String, _ l: L) -> String {
        switch mood {
        case .excited: l.t("\(companion)도 꼬리를 흔들며 같이 신났어요.",
                           "\(companion) is bouncing around with you.",
                           "\(companion)も一緒にうきうきしています。")
        case .calm: l.t("\(companion)이 옆에서 조용히 낮잠을 자요.",
                        "\(companion) is dozing quietly beside you.",
                        "\(companion)がそばで静かに眠っています。")
        case .down: l.t("\(companion)이 말없이 옆에 앉았어요.",
                        "\(companion) sat down next to you without a word.",
                        "\(companion)が何も言わずに隣に座りました。")
        case .annoyed: l.t("\(companion)도 같이 머리를 감싸 쥐었어요.",
                           "\(companion) is holding its head right along with you.",
                           "\(companion)も一緒に頭を抱えています。")
        case .fluttering: l.t("\(companion)이 하트를 띄웠어요.",
                              "\(companion) let out a little heart.",
                              "\(companion)がハートを浮かべました。")
        }
    }
}

/// 계절 이름·심볼. `MemoryHomeMoodStyle` 과 같은 이유로 뷰 밖에 둔다 — 뷰 안 `private` 함수면
/// 세 언어 문구가 무테스트로 남는다.
///
/// 색은 일부러 주지 않는다. 방에는 이미 사용자가 고른 테마 4색이 있고, 계절색으로 덮으면 사용자의
/// 선택을 뭉갠다 — 계절은 대문의 한 줄이지 방의 주인이 아니다.
enum MemoryHomeSeasonStyle {
    static func name(_ season: MemoryHomeSeason, _ l: L) -> String {
        switch season {
        case .spring: l.t("봄", "Spring", "春")
        case .summer: l.t("여름", "Summer", "夏")
        case .autumn: l.t("가을", "Autumn", "秋")
        case .winter: l.t("겨울", "Winter", "冬")
        }
    }

    static func symbol(_ season: MemoryHomeSeason) -> String {
        switch season {
        case .spring: "camera.macro"
        case .summer: "sun.max.fill"
        case .autumn: "leaf.fill"
        case .winter: "snowflake"
        }
    }
}

struct MemoryHomeView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(MemoryHomeVisitCenter.self) private var visits
    let store: CompanionStore
    @State private var note = ""
    @State private var validationMessage: String?
    @State private var showingVisits = false
    @State private var showingDiary = false
    @State private var showingPublicNicknameEditor = false
    @State private var publicNicknameDraft = ""
    @State private var publicNicknameError: String?
    @State private var showingProfileMessageEditor = false
    @State private var profileMessageDraft = ""
    @State private var profileMessageError: String?

    private var l: L { store.l }

    var body: some View {
        guard let mon = store.state.active else { return AnyView(EmptyView()) }
        let album = store.memoryAlbum
        let entries = album.entries(for: mon.id)
        let timeline = album.timeline(for: mon.id)
        let hidden = entries.filter(\.isHidden).sorted { $0.createdAt > $1.createdAt }
        let milestones = album.milestones(for: mon.id)
        let roomTheme = album.theme(for: mon.id)
        let roomTint = MemoryHomeRoomTheme.tint(for: roomTheme)

        return AnyView(VStack(alignment: .leading, spacing: 10) {
            visitCounterRow(album: album)
            roomHeader(mon: mon, entries: entries, milestones: milestones, theme: roomTheme, tint: roomTint)
            moodRow(album: album, mon: mon)

            HStack {
                Button { showingVisits = true } label: {
                    Label(l.t("주변 홈 방문", "Visit nearby homes", "近くのホームを訪問"), systemImage: "house.and.flag")
                }
                .accessibilityLabel(l.t("주변 Memory Home 방문", "Visit nearby Memory Homes", "近くのMemory Homeを訪問"))
                Button { showingDiary = true } label: {
                    Label(l.t("다이어리", "Diary", "ダイアリー"), systemImage: "book.closed")
                }
                .accessibilityLabel(l.t("날짜별 다이어리", "Diary by date", "日付ごとのダイアリー"))
                Spacer()
                Menu {
                    Button(l.t("공개 닉네임 편집", "Edit public nickname", "公開ニックネームを編集")) {
                        publicNicknameDraft = album.memoryHomePublicNickname
                        publicNicknameError = nil
                        showingPublicNicknameEditor = true
                    }
                    Button(l.t("대문 문구 편집", "Edit home message", "ホームの一言を編集")) {
                        profileMessageDraft = album.memoryHomeAccess.profileMessage ?? ""
                        profileMessageError = nil
                        showingProfileMessageEditor = true
                    }
                    if album.memoryHomeAccess.profileMessage != nil {
                        Button(album.memoryHomeAccess.sharesProfileMessage
                               ? l.t("대문 문구 공유 해제", "Stop sharing home message", "一言の共有をやめる")
                               : l.t("대문 문구 공유", "Share home message", "一言を共有")) {
                            album.setSharesProfileMessage(!album.memoryHomeAccess.sharesProfileMessage)
                        }
                        Button(l.t("대문 문구 삭제", "Delete home message", "一言を削除"), role: .destructive) {
                            album.clearProfileMessage()
                        }
                    }
                    Button(store.memoryAlbum.memoryHomeAccess.visibility == .open
                           ? l.t("홈 차단", "Block home", "ホームをブロック")
                           : l.t("홈 공개", "Open home", "ホームを公開")) {
                        store.memoryAlbum.setMemoryHomeVisibility(store.memoryAlbum.memoryHomeAccess.visibility == .open ? .blocked : .open)
                        visits.refreshAccess()
                    }
                    if let pinned = album.pinned(for: mon.id) {
                        Button(album.sharedPinnedMemory(for: mon.id) == nil
                               ? l.t("고정 기억 공유", "Share pinned memory", "固定した思い出を共有")
                               : l.t("기억 공유 해제", "Stop sharing memory", "思い出の共有をやめる")) {
                            if album.sharedPinnedMemory(for: mon.id) == nil { album.setSharedPinnedMemory(pinned, activeCompanionID: mon.id) }
                            else { album.clearSharedPinnedMemory() }
                        }
                    }
                    if !album.memoryHomeAccess.recentRequesters.isEmpty {
                        Divider()
                        ForEach(album.memoryHomeAccess.recentRequesters) { requester in
                            Button(requester.displayName + " · " + (album.memoryHomeAccess.blockedPeerIDs.contains(requester.peerID)
                                   ? l.t("차단 해제", "Unblock", "ブロック解除")
                                   : l.t("차단", "Block", "ブロック"))) {
                                album.setMemoryHomeBlocked(requester.peerID, blocked: !album.memoryHomeAccess.blockedPeerIDs.contains(requester.peerID))
                            }
                        }
                    }
                } label: { Image(systemName: "lock.shield") }
                .accessibilityLabel(l.t("홈 공유 설정", "Home sharing settings", "ホーム共有設定"))
            }

            if let pinned = album.pinned(for: mon.id) {
                VStack(alignment: .leading, spacing: 3) {
                    Label(l.t("고정한 기억", "Pinned memory", "固定した思い出"), systemImage: "pin.fill")
                        .font(.caption.weight(.semibold)).foregroundStyle(PokedoroTheme.red)
                    Text(pinned.body).font(.subheadline)
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(9)
                .pokedoroCard(tint: PokedoroTheme.red, emphasized: true)
            }

            if !milestones.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(l.t("함께 연 카드", "Unlocked cards", "解放したカード")).font(.headline)
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 8) {
                            ForEach(milestones) { milestone in
                                milestoneCard(milestone, tint: roomTint)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                TextEditor(text: $note).frame(minHeight: 54, maxHeight: 74)
                    .accessibilityLabel(l.t("새 개인 기억", "New private memory", "新しい非公開の思い出"))
                HStack {
                    Text(l.t("\(note.count)/280", "\(note.count)/280", "\(note.count)/280"))
                        .font(.caption).foregroundStyle(note.count > 280 ? PokedoroTheme.red : .secondary)
                    Spacer()
                    Button(l.t("기억 남기기", "Save memory", "思い出を残す")) {
                        if album.addManual(companionID: mon.id, body: note) {
                            settings.recordManualMemoryCreated()
                            note = ""; validationMessage = nil
                        } else {
                            validationMessage = l.t("1~280자로 적어 주세요.", "Enter 1–280 characters.", "1〜280文字で入力してください。")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
                if let validationMessage { Text(validationMessage).font(.caption).foregroundStyle(PokedoroTheme.red) }
            }
            .padding(9).pokedoroCard(tint: PokedoroTheme.mint)

            Text(l.t("최근 기억", "Recent memories", "最近の思い出")).font(.headline)
            if timeline.isEmpty {
                Text(l.t("첫 집중을 마치면 여기에 함께한 기록이 쌓여요.",
                         "Finish a focus session to start this shared record.",
                         "集中を終えると、ここにふたりの記録が積み重なります。"))
                    .font(.caption).foregroundStyle(.secondary).padding(.vertical, 8)
            }
            ForEach(timeline) { memory in
                memoryRow(memory, album: album)
            }
            if !hidden.isEmpty {
                DisclosureGroup(l.t("숨긴 기억", "Hidden memories", "非表示の思い出")) {
                    ForEach(hidden) { memory in
                        memoryRow(memory, album: album)
                    }
                }
            }
        }
        .padding(10).pokedoroCard(tint: roomTint)
        .onAppear { settings.recordMemoryHomeExposure() }
        .sheet(isPresented: $showingVisits, onDismiss: { visits.stop() }) {
            MemoryHomeVisitSheet(visits: visits, language: l)
                .onAppear { visits.start() }
        }
        // 인라인 섹션이 아니라 시트다. 팝오버 높이는 `PopoverMetrics.tabHeight` 로 고정이고 홈 탭엔
        // 이미 미션보드·동행 헤더·미니룸이 들어 있어, 인라인이면 스크롤이 아니라 잘림이 된다(#9).
        .sheet(isPresented: $showingDiary) {
            MemoryHomeDiarySheet(days: album.diary(for: mon.id), language: l,
                                 locale: store.language.displayLocale)
        }
        .alert(l.t("공개 닉네임", "Public nickname", "公開ニックネーム"), isPresented: $showingPublicNicknameEditor) {
            TextField(l.t("공개 닉네임", "Public nickname", "公開ニックネーム"), text: $publicNicknameDraft)
            Button(l.t("저장", "Save", "保存")) {
                if album.setMemoryHomePublicNickname(publicNicknameDraft) {
                    publicNicknameError = nil
                    visits.refreshAccess()
                } else {
                    publicNicknameError = l.t("공백이나 제어문자 없이 1~40자로 입력해 주세요.", "Use 1–40 characters with no whitespace or control characters.", "空白・制御文字なしで1〜40文字にしてください。")
                    showingPublicNicknameEditor = true
                }
            }
            Button(l.t("취소", "Cancel", "キャンセル"), role: .cancel) {}
        } message: {
            Text(publicNicknameError ?? l.t("이 이름만 같은 LAN에 공개됩니다.", "Only this name is shared on your local network.", "この名前だけが同じLANに公開されます。"))
        }
        .alert(l.t("대문 문구", "Home message", "ホームの一言"), isPresented: $showingProfileMessageEditor) {
            TextField(l.t("대문 문구", "Home message", "ホームの一言"), text: $profileMessageDraft)
            Button(l.t("저장", "Save", "保存")) {
                if store.memoryAlbum.setProfileMessage(profileMessageDraft) {
                    profileMessageError = nil
                } else {
                    profileMessageError = l.t("줄바꿈 없이 1~60자로 입력해 주세요.",
                                              "Use 1–60 characters with no line breaks.",
                                              "改行なしで1〜60文字にしてください。")
                    showingProfileMessageEditor = true
                }
            }
            Button(l.t("취소", "Cancel", "キャンセル"), role: .cancel) {}
        } message: {
            // 기본값은 비공개다. 공유는 메뉴에서 따로 켜야 한다 — 저장이 곧 공개가 되면
            // 사용자가 동의하지 않은 문구가 LAN 으로 나간다.
            Text(profileMessageError ?? l.t("저장해도 공개되지 않아요. 공유는 따로 켜 주세요.",
                                            "Saving does not share it. Turn sharing on separately.",
                                            "保存しても公開されません。共有は別に有効化してください。"))
        }
        )
    }

    /// 싸이월드 미니홈피의 그 줄. 경쟁 지표가 아니라 기념일 트리거라서 랭킹·비교는 넣지 않는다.
    private func visitCounterRow(album: PokemonMemoryAlbum) -> some View {
        let today = album.memoryHomeAccess.visitToday, total = album.memoryHomeAccess.visitTotal
        return HStack(spacing: 6) {
            Text("TODAY").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            Text("\(today)").font(.caption.weight(.bold).monospacedDigit()).foregroundStyle(PokedoroTheme.red)
            Text("TOTAL").font(.caption2.weight(.semibold)).foregroundStyle(.secondary).padding(.leading, 6)
            Text("\(total)").font(.caption.weight(.bold).monospacedDigit())
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(l.t("오늘 방문 \(today)명, 전체 방문 \(total)명",
                                "\(today) visits today, \(total) total",
                                "本日の訪問 \(today) 件、累計 \(total) 件"))
    }

    /// 순수 자기표현이다 — 스탯·보상·포획률에 아무 영향이 없다. 종별 반응은 넣지 않는다:
    /// 1000종 × 5기분은 헤더 기능의 범위가 아니다.
    private func moodRow(album: PokemonMemoryAlbum, mon: MonState) -> some View {
        let current = album.mood()
        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 4) {
                Text(l.t("오늘 기분", "Today's mood", "今日の気分"))
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                ForEach(MemoryHomeMood.allCases, id: \.self) { mood in
                    Button { album.setMood(mood) } label: {
                        Text(MemoryHomeMoodStyle.emoji(mood)).font(.body)
                            .frame(minWidth: 26, minHeight: 26)
                            .background(current == mood ? PokedoroTheme.yellow.opacity(0.32) : .clear,
                                        in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(MemoryHomeMoodStyle.name(mood, l))
                    .accessibilityAddTraits(current == mood ? [.isSelected] : [])
                }
            }
            if let current {
                Text(MemoryHomeMoodStyle.reaction(current, companion: store.chatProfile(for: mon).displayName, l))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(8).pokedoroCard(tint: PokedoroTheme.yellow)
    }

    private func roomHeader(mon: MonState, entries: [PokemonMemory], milestones: [PokemonMemoryMilestone], theme: PokemonMemoryRoomTheme, tint: Color) -> some View {
        let season = MemoryHomeSeason.current()
        return HStack(alignment: .center, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(tint.opacity(0.18))
                Rectangle().fill(tint.opacity(0.24)).frame(height: 13).frame(maxHeight: .infinity, alignment: .bottom)
                SpriteView(speciesID: mon.currentID, size: 54, shiny: mon.isShiny)
            }
            .frame(width: 76, height: 68)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(l.t("우리의 미니룸", "Our mini room", "ふたりのミニルーム")).font(.headline)
                    // 저장 없이 달력 월에서 파생한다 — 방 색은 사용자가 고른 테마 그대로 둔다.
                    Label(MemoryHomeSeasonStyle.name(season, l),
                          systemImage: MemoryHomeSeasonStyle.symbol(season))
                        .font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                        .labelStyle(.titleAndIcon)
                }
                Text(store.chatProfile(for: mon).displayName).font(.subheadline.weight(.semibold))
                if let message = store.memoryAlbum.memoryHomeAccess.profileMessage {
                    HStack(spacing: 3) {
                        Text(message).font(.caption.italic()).foregroundStyle(PokedoroTheme.blue).lineLimit(2)
                        // 공유 중일 때만 아이콘이 뜬다 — 내 문구가 지금 LAN 에 나가는지 화면에서 바로 보이게.
                        if store.memoryAlbum.memoryHomeAccess.sharesProfileMessage {
                            Image(systemName: "dot.radiowaves.left.and.right")
                                .font(.caption2).foregroundStyle(.secondary)
                                .accessibilityLabel(l.t("LAN에 공유 중", "Shared on your local network", "LANに共有中"))
                        }
                    }
                }
                Text(firstMeetingText(mon.id)).font(.caption).foregroundStyle(.secondary)
                Text(l.t("기억 \(entries.count)개 · 카드 \(milestones.count)개",
                         "\(entries.count) memories · \(milestones.count) cards",
                         "思い出 \(entries.count) 件・カード \(milestones.count) 枚"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Menu {
                ForEach(PokemonMemoryRoomTheme.allCases, id: \.self) { candidate in
                    Button {
                        store.memoryAlbum.setTheme(candidate, for: mon.id)
                    } label: {
                        Label(themeName(candidate), systemImage: candidate == theme ? "checkmark" : "circle.fill")
                    }
                }
            } label: {
                Image(systemName: "paintpalette.fill")
                    .foregroundStyle(tint)
                    .frame(minWidth: 28, minHeight: 28)
            }
            .menuStyle(.borderlessButton)
            .accessibilityLabel(l.t("미니룸 테마", "Mini room theme", "ミニルームのテーマ"))
            .accessibilityValue(themeName(theme))
            .accessibilityHint(l.t("동행별 테마를 선택합니다.", "Choose a theme for this companion.", "この相棒のテーマを選びます。"))
        }
        .padding(8)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(l.t("\(store.chatProfile(for: mon).displayName)의 미니룸. \(firstMeetingText(mon.id)). 기억 \(entries.count)개, 카드 \(milestones.count)개",
                               "\(store.chatProfile(for: mon).displayName)'s mini room. \(firstMeetingText(mon.id)). \(entries.count) memories, \(milestones.count) cards",
                               "\(store.chatProfile(for: mon).displayName)のミニルーム。\(firstMeetingText(mon.id))。思い出 \(entries.count) 件、カード \(milestones.count) 枚"))
    }

    private func firstMeetingText(_ companionID: UUID) -> String {
        guard let first = store.memoryAlbum.firstMetAt(for: companionID) else {
            return l.t("첫 만남을 기다리고 있어요", "Waiting for our first meeting", "最初の出会いを待っています")
        }
        return l.t("첫 만남 ", "First meeting ", "最初の出会い ") + formattedDate(first)
    }

    private func milestoneCard(_ milestone: PokemonMemoryMilestone, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Image(systemName: MemoryHomeCardStyle.icon(milestone))
                .font(.title3.weight(.semibold)).foregroundStyle(tint)
            Text(MemoryHomeCardStyle.title(milestone, l)).font(.subheadline.weight(.semibold)).lineLimit(2)
            Text(formattedDate(milestone.occurredAt)).font(.caption).foregroundStyle(.secondary)
        }
        .frame(width: 132, height: 98, alignment: .leading)
        .padding(10)
        .background(tint.opacity(0.11), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(MemoryHomeCardStyle.title(milestone, l) + ", " + formattedDate(milestone.occurredAt))
    }

    private func themeName(_ theme: PokemonMemoryRoomTheme) -> String {
        switch theme {
        case .blue: l.t("파랑", "Blue", "ブルー")
        case .mint: l.t("민트", "Mint", "ミント")
        case .yellow: l.t("노랑", "Yellow", "イエロー")
        case .red: l.t("빨강", "Red", "レッド")
        }
    }

    private func formattedDate(_ date: Date) -> String {
        date.formatted(.dateTime.locale(store.language.displayLocale).year().month(.abbreviated).day())
    }

    private func memoryRow(_ memory: PokemonMemory, album: PokemonMemoryAlbum) -> some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(memory.body).font(.subheadline)
                Text(sourceName(memory.source) + " · " + memory.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Menu {
                Button(l.t("고정", "Pin", "固定")) { album.pin(memory) }
                Button(memory.isHidden ? l.t("다시 표시", "Show", "再表示") : l.t("숨기기", "Hide", "非表示")) {
                    _ = album.setHidden(memory, isHidden: !memory.isHidden)
                }
                if memory.source == .manual {
                    Button(l.t("삭제", "Delete", "削除"), role: .destructive) { _ = album.delete(memory) }
                }
            } label: {
                Image(systemName: album.pinned(for: memory.companionID)?.id == memory.id ? "pin.fill" : "ellipsis")
            }
            .menuStyle(.borderlessButton).accessibilityLabel(l.t("기억 동작", "Memory actions", "思い出の操作"))
        }
        .padding(.vertical, 4)
    }

    private func sourceName(_ source: PokemonMemorySource) -> String {
        switch source {
        case .event: return l.t("모험", "Event", "イベント")
        case .conversation: return l.t("대화", "Conversation", "会話")
        case .manual: return l.t("내 기록", "Note", "メモ")
        }
    }
}

/// 날짜별 일기. 이미 쌓인 기억을 묶어 보여 줄 뿐이라 여기서 저장하는 것은 아무것도 없다.
private struct MemoryHomeDiarySheet: View {
    let days: [MemoryHomeDiaryDay]
    let language: L
    let locale: Locale
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(language.t("다이어리", "Diary", "ダイアリー")).font(.headline)
                Spacer(); Button(language.t("닫기", "Close", "閉じる")) { dismiss() }
            }
            if days.isEmpty {
                Text(language.t("아직 적힌 날이 없어요. 첫 집중을 마치면 오늘이 여기 남아요.",
                                "No days yet. Finish a focus session and today lands here.",
                                "まだ記録がありません。集中を終えると今日がここに残ります。"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(days) { day in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: 5) {
                                Text(day.date.formatted(.dateTime.locale(locale).year().month(.abbreviated).day()))
                                    .font(.subheadline.weight(.bold))
                                if let mood = day.mood {
                                    Text(MemoryHomeMoodStyle.emoji(mood))
                                        .accessibilityLabel(MemoryHomeMoodStyle.name(mood, language))
                                }
                            }
                            ForEach(day.memories) { memory in
                                Text("· " + memory.body).font(.caption)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(9).pokedoroCard(tint: PokedoroTheme.blue)
                    }
                }
            }
            // 캡을 밝히지 않으면 잘려 나간 옛날이 "사라진 일기" 로 읽힌다.
            Text(language.t("최근 기억 200개 안에서 보여 줘요.",
                            "Shows what fits in the most recent 200 memories.",
                            "最新200件の思い出の範囲で表示します。"))
                .font(.caption2).foregroundStyle(.tertiary)
        }.padding().frame(minWidth: 330, minHeight: 320)
    }
}

private struct MemoryHomeVisitSheet: View {
    let visits: MemoryHomeVisitCenter
    let language: L
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(language.t("주변 Memory Home", "Nearby Memory Homes", "近くのMemory Home")).font(.headline)
                Spacer(); Button(language.t("닫기", "Close", "閉じる")) { dismiss() }
            }
            if let profile = visits.selectedProfile {
                VStack(alignment: .leading, spacing: 5) {
                    Text(profile.displayName).font(.title3.weight(.bold))
                    if let message = profile.profileMessage {
                        Text(message).font(.caption.italic()).foregroundStyle(PokedoroTheme.blue)
                    }
                    Text(profile.speciesLabel)
                    if let memory = profile.sharedMemoryBody { Text(memory).font(.callout) }
                }.padding().pokedoroCard(tint: PokedoroTheme.mint)
            }
            if let error = visits.lastError { Text(error).foregroundStyle(PokedoroTheme.red).font(.caption) }
            if visits.homes.isEmpty { Text(language.t("홈을 찾는 중이에요…", "Looking for homes…", "ホームを探しています…")).foregroundStyle(.secondary) }
            // 그 시절 그 버튼. 범위는 같은 LAN 까지다 — Bonjour 가 닿는 데까지가 전부이고,
            // 그 밖으로 나가려면 앱에 없는 인터넷 경로가 필요하다.
            Button { if let home = visits.homes.randomElement() { visits.visit(home) } } label: {
                Label(language.t("파도타기", "Surf a random home", "波乗り"), systemImage: "shuffle")
            }
            .disabled(visits.homes.isEmpty)
            ForEach(visits.homes) { home in
                Button { visits.visit(home) } label: { Label(home.displayName, systemImage: "house") }
                    .accessibilityLabel(language.t("\(home.displayName) 홈 방문", "Visit \(home.displayName)'s home", "\(home.displayName)のホームを訪問"))
            }
            Spacer()
        }.padding().frame(minWidth: 330, minHeight: 260)
    }
}
