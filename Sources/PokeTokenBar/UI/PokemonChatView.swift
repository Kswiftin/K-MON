import AppKit
import SwiftUI

struct PokemonChatView: View {
    let store: CompanionStore
    let companionID: UUID
    let chat: PokemonChatStore
    let album: PokemonMemoryAlbum
    let toolbox: any PokemonChatToolRunning
    let settings: AppSettings
    let onClose: () -> Void
    @State private var identity: PokemonSpeciesIdentity?
    @State private var destination: Destination?
    @State private var providerCache = PokemonChatProviderCache()
    /// 첫 전송 확인이 떠 있는 동안 어느 CLI 를 묻고 있는지. 팝오버가 닫히면 뷰째로 사라지므로
    /// 확인 창도 함께 사라진다 — 승인 없이 남는 상태가 없다.
    @State private var pendingFirstSend: PokemonChatProviderKind?
    @AppStorage("pokemonChatProvider") private var providerRaw = ""

    /// 입력 중인 문장은 **스토어**가 든다. 팝오버는 바깥 클릭에 닫히며 콘텐츠 뷰를 통째로
    /// 해제하므로(`popoverDidClose`), `@State` 로 두면 쓰다 만 문장이 클릭 한 번에 사라진다.
    private var draft: Binding<String> {
        Binding(get: { chat.draft(for: companionID) },
                set: { chat.setDraft($0, for: companionID) })
    }

    private enum Destination: String, Identifiable { case album, dailyDex; var id: String { rawValue } }

    init(store: CompanionStore, companionID: UUID, chat: PokemonChatStore? = nil,
         album: PokemonMemoryAlbum? = nil, toolbox: any PokemonChatToolRunning,
         settings: AppSettings, onClose: @escaping () -> Void) {
        self.store = store
        self.companionID = companionID
        self.chat = chat ?? store.chatStore
        self.album = album ?? store.memoryAlbum
        self.toolbox = toolbox
        self.settings = settings
        self.onClose = onClose
    }
    private var baseProfile: PokemonChatProfile {
        store.ownedMons.first(where: { $0.id == companionID }).map(store.chatProfile(for:))
            ?? PokemonChatProfile(speciesID: 0, displayName: "?", nickname: nil, nature: nil, level: 1, stage: "", flavorText: nil, language: store.language)
    }
    private var profile: PokemonChatProfile { var value = baseProfile; if let identity { value.apply(identity) }; return value }
    private var l: L { L(profile.language) }

    /// **고르지 않아도 보낼 수 있다.** 저장된 선택이 없거나 못 쓰게 됐으면 설치된 검증 CLI 중
    /// 우선순위 첫 번째로 폴백한다. 판정은 Core 한 벌(`PokemonChatProviderSelection`)이다.
    ///
    /// `body` 안에서 여러 자리가 읽고 `body` 는 키 입력마다 평가된다 — 캐시를 지나지 않으면
    /// 한 글자마다 디렉터리 13곳에 파일시스템 질의가 검증 CLI 수만큼 간다.
    private var effectiveKind: PokemonChatProviderKind? {
        PokemonChatProviderSelection.effectiveKind(stored: providerRaw) { kind in
            providerCache.executableURL(for: kind, override: settings.chatProviderExecutablePath(for: kind)) != nil
        }
    }

    private var provider: (any PokemonChatProviding)? {
        guard let kind = effectiveKind,
              let arguments = PokemonChatProviderSafety.arguments(for: kind),
              let executableURL = providerCache.executableURL(
                  for: kind, override: settings.chatProviderExecutablePath(for: kind)) else { return nil }
        return PokemonChatCLIProvider(executableURL: executableURL, arguments: arguments, kind: kind)
    }

    private var unavailableReason: String? {
        PokemonChatProviderSelection.unavailableMessage(stored: providerRaw, effective: effectiveKind,
                                                        language: profile.language)
    }

    var body: some View {
        // 시트가 아니라 **자리 바꿈**이다. 팝오버 안에서 `.sheet` 을 띄우면 발표자가 borderless
        // `_NSPopoverWindow` 라 붙지 않거나, 붙더라도 키 윈도우가 되며 `.transient` 팝오버를
        // 닫아 발표자째로 사라진다. 레포의 다른 `.sheet` 은 전부 진짜 창 안에 있다.
        Group {
            if let destination { detail(destination) } else { conversation }
        }
        // 팝오버 폭은 바깥(`PopoverView`)이 정한다. 높이만 다른 오버레이와 같은 예산을 쓴다 —
        // 전용 창의 520 보다 커져 메시지 영역이 그만큼 늘어난다.
        .frame(height: PopoverMetrics.currentHeight(for: .battle))
        .task(id: profile.speciesID) {
            identity = await PokeAPIClient.shared.chatSpeciesIdentity(speciesID: profile.speciesID, language: profile.language)
        }
    }

    /// 하위 화면은 대화 자리를 덮되 **돌아갈 길**을 항상 준다 — 팝오버엔 창 닫기 버튼이 없다.
    @ViewBuilder private func detail(_ destination: Destination) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button { self.destination = nil } label: {
                    Label(l.t("대화로", "Back to chat", "会話へ"), systemImage: "chevron.left")
                }.buttonStyle(.borderless)
                Spacer()
            }.padding(12)
            Divider()
            switch destination {
            case .album: PokemonMemoryAlbumView(companionID: companionID, language: profile.language, album: album)
            case .dailyDex: TodayPokedexView(profile: profile)
            }
            Spacer(minLength: 0)
        }
    }

    private var conversation: some View {
        VStack(spacing: 0) {
            header
            if let unavailableReason {
                // 여기 파일 선택 버튼을 두면 안 된다. 팝오버가 `.transient` 라 `NSOpenPanel` 이
                // 키 윈도우가 되는 순간 팝오버가 닫히고, `popoverDidClose` 가 호스팅 컨트롤러를
                // 해제해 이 뷰가 통째로 사라진다 — 경로는 저장되는데 사용자는 닫힌 팝오버 앞에
                // 남는다(같은 함정을 `SettingsView` 가 이미 문서화해 뒀다). 경로 입력은 설정에 있다.
                // 주황은 **막혔다**는 뜻으로만 쓴다. 폴백이 보내 주는 중에도 주황이면, 같은 화면이
                // "못 씁니다" 와 "Codex 로 나갑니다" 를 동시에 말하게 된다.
                Text(unavailableReason).font(.caption2)
                    .foregroundStyle(provider == nil ? Color.orange : Color.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).padding(.bottom, 8)
            }
            Divider()
            questionChips
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        let messages = chat.messages(for: companionID)
                        let emphasizedID = PokemonChatMessagePresentation.emphasizedPokemonMessageID(in: messages)
                        ForEach(messages) { message in
                            PokemonSpeechBubble(message: message, profile: profile,
                                                isEmphasized: message.id == emphasizedID)
                                .id(message.id)
                        }
                        // 이 대화의 상태만 본다 — 전역이면 답이 오지 않을 기록에도 점 세 개가 뜬다.
                        if chat.isSending(for: companionID) {
                            PokemonThinkingBubble(profile: profile).id("sending")
                        }
                    }.padding(12)
                }
                .onChange(of: chat.messages(for: companionID).count) { _, _ in
                    if let id = chat.messages(for: companionID).last?.id { proxy.scrollTo(id, anchor: .bottom) }
                }
                .onChange(of: chat.isSending(for: companionID)) { _, sending in
                    if sending { proxy.scrollTo("sending", anchor: .bottom) }
                    else if let id = chat.messages(for: companionID).last?.id { proxy.scrollTo(id, anchor: .bottom) }
                }
            }
            proposalCard
            if let error = chat.errorMessage { Text(error).font(.caption2).foregroundStyle(.red).padding(.horizontal, 12) }
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                firstSendConsentCard
                // 동의는 이 줄과 아래 버튼이 함께 이룬다 — 어디로 나가는지 읽고 누르는 것.
                if let effectiveKind {
                    PokemonChatConsentLabel(kind: effectiveKind, language: profile.language)
                }
                HStack(alignment: .bottom, spacing: 8) {
                    TextField(l.t("메시지를 입력하세요", "Type a message", "メッセージを入力"), text: draft, axis: .vertical)
                        .textFieldStyle(.roundedBorder).lineLimit(1...4)
                        .onSubmit(send)
                    Button(action: send) { Image(systemName: "paperplane.fill") }
                        .disabled(draft.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || provider == nil)
                }
            }.padding(PokemonChatConsentLabel.horizontalPadding)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.displayName).font(.headline)
                Text(profile.flavorText ?? "PokéAPI 설명을 불러오는 중…").font(.caption2).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 4)
            Menu {
                providerPicker
                Divider()
                Button(l.t("기억 앨범", "Memory album", "思い出アルバム")) { destination = .album }
                Button(l.t("새 대화", "New chat", "新しい会話")) { chat.startNewSession(for: companionID, profile: profile) }
                Button(l.t("기록 삭제", "Delete history", "履歴を削除"), role: .destructive) { chat.deleteSession(for: companionID) }
            } label: { Image(systemName: "ellipsis.circle") }.menuStyle(.borderlessButton).fixedSize()
            Button(action: onClose) { Image(systemName: "xmark") }.buttonStyle(.borderless)
        }.padding(12)
    }

    /// 제공자 선택은 `⋯` 메뉴 안에 산다. 전용 줄(`statusBar`)이었을 때 **띄워 보니** 우측 230pt 가
    /// 상시로 비어 있었고, 헤더에 나란히 두는 대안은 이미 2줄로 잘려 있는 설명 텍스트를 더 깎았다.
    /// 자주 바꾸는 값이 아니고, "지금 어디로 나가는가" 는 전송 자리의 동의 줄이 상시 답한다.
    ///
    /// 피커는 **사용자의 선택**만 보여 준다. 읽기를 자동 선택 결과로 바꿔 끼우면 쓴 값과 읽는 값이
    /// 달라져, "자동 선택" 은 영영 선택된 적이 없고 차단된 저장값은 목록 어디에도 안 뜨면서 배너만
    /// 그 이름을 말한다.
    private var providerPicker: some View {
        Picker(l.t("대화 상대 AI", "Chat AI", "会話 AI"), selection: $providerRaw) {
            // 빈 값은 "안 골랐다" 가 아니라 **자동에 맡긴다** 는 뜻이 됐다. 고른 걸 되돌리는 길.
            Text(l.t("자동 선택", "Automatic", "自動選択")).tag("")
            // 차단된 제공자도 보여 준다 — 목록에서 지우면 왜 못 쓰는지 알 길이 없다. 대신
            // 자물쇠를 달고 고를 수 없게 한다(`(disabled)` 라고 *쓰기만* 하면 골라진다).
            ForEach(PokemonChatProviderKind.allCases, id: \.self) { kind in
                if PokemonChatProviderSafety.availability(for: kind).isVerified {
                    Text(kind.label(profile.language)).tag(kind.rawValue)
                } else {
                    Label(kind.label(profile.language), systemImage: "lock.fill")
                        .disabled(true).tag(kind.rawValue)
                }
            }
        }
    }

    /// 무엇을 시킬 수 있는지는 **여기서** 답한다. 액션 칩은 실행기가 지금 성공시킬 수 있는 것만
    /// 오므로 목록이 아니라 상태다 — `FocusTimer`·`CompanionStore` 가 `@Observable` 이라 집중을
    /// 시작하면 이 줄이 그 자리에서 바뀐다.
    private var questionChips: some View {
        PokemonChatChipRow(actions: toolbox.availableActions(owner: companionID),
                           questions: chips, language: profile.language) { phrase in
            if phrase == dailyDexQuestion { destination = .dailyDex } else { draft.wrappedValue = phrase }
        }
    }

    private var chips: [String] {
        var values = [l.t("너의 타입이 뭐야?", "What type are you?", "きみのタイプは？"),
                      l.t("지금 기분은 어때?", "How are you feeling?", "いまの気分は？"),
                      dailyDexQuestion]
        if !profile.moves.isEmpty { values.insert(l.t("배운 기술을 알려 줘", "Tell me your moves", "覚えた技を教えて"), at: 1) }
        if profile.genus != nil { values.insert(l.t("너는 어떤 포켓몬이야?", "What kind of Pokémon are you?", "どんなポケモンなの？"), at: 1) }
        if profile.nextEvolution != nil { values.insert(l.t("다음 진화는 언제야?", "When is your next evolution?", "次の進化はいつ？"), at: 2) }
        return values
    }
    private var dailyDexQuestion: String { l.t("오늘의 도감을 보여 줘", "Show today’s Pokédex", "今日の図鑑を見せて") }

    /// 상태를 바꾸는 도구는 여기를 지나야만 실행된다. 카드가 실제 인자(분 수)를 그대로 보여 주므로
    /// 사용자는 무엇을 켜는지 정확히 알고 누른다.
    @ViewBuilder private var proposalCard: some View {
        if let proposal = chat.pendingProposal, proposal.companionID == companionID, proposal.state == .pending {
            VStack(alignment: .leading, spacing: 6) {
                Text(proposal.call.approvalQuestion(profile.language)).font(.callout)
                HStack {
                    Button(l.t("승인", "Approve", "承認")) { resolve(approved: true) }.buttonStyle(.borderedProminent)
                    Button(l.t("거절", "Reject", "断る")) { resolve(approved: false) }.buttonStyle(.bordered)
                }
            }
            .padding(10)
            .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 12)
        }
    }

    /// 승인된 호출도 루프와 **같은 실행기**로 간다. 뷰에 스위치를 한 벌 더 두면 두 경로가 갈라진다.
    private func resolve(approved: Bool) {
        Task {
            await chat.resolvePending(approved: approved, profileForCompanion: profileForOwner) { call, owner in
                await toolbox.run(call, owner: owner).succeeded
            }
        }
    }

    /// **문턱은 여기 하나다.** 전송 버튼과 Return 키가 둘 다 이 함수를 지나므로, 확인을 버튼
    /// 쪽에만 달면 Return 으로 그냥 나간다 — 같은 부류의 결함을 이미 겪었다.
    private func send() {
        guard let provider, let kind = effectiveKind else { return }
        switch PokemonChatProviderSelection.sendAction(
            kind: kind, acknowledged: settings.hasAcknowledgedExternalChatSend) {
        case .ask(let kind):
            // 입력칸은 **비우지 않는다.** 물어만 보고 아직 아무것도 안 보냈으므로, 여기서 비우면
            // 취소한 사용자가 쓰던 문장을 잃는다.
            pendingFirstSend = kind
        case .send:
            deliverDraft(through: provider)
        }
    }

    private func deliverDraft(through provider: any PokemonChatProviding) {
        // 꺼내기와 비우기가 한 동작이라 동기다 — `Task` 가 도는 사이 한 번 더 눌려 같은 문장이
        // 두 번 가는 창이 없고, 공백만 친 뒤 Return 을 눌러도 입력칸이 비워진다.
        let message = chat.takeDraft(for: companionID)
        Task { await chat.send(message, for: companionID, profile: profile, provider: provider, toolbox: toolbox) }
    }

    /// 처음 한 번만 뜬다. `proposalCard` 와 같은 모양을 쓰는 이유는, 이 화면에서 "승인해야 일어나는
    /// 일" 의 생김새가 이미 그것이기 때문이다 — 새 모양을 만들면 사용자가 새로 배워야 한다.
    @ViewBuilder private var firstSendConsentCard: some View {
        if let pendingFirstSend {
            VStack(alignment: .leading, spacing: 6) {
                Text(PokemonChatProviderSelection.firstSendConsentQuestion(
                    kind: pendingFirstSend, language: profile.language)).font(.callout)
                HStack {
                    Button(l.t("보내기", "Send", "送信")) {
                        settings.hasAcknowledgedExternalChatSend = true
                        self.pendingFirstSend = nil
                        if let provider { deliverDraft(through: provider) }
                    }.buttonStyle(.borderedProminent)
                    Button(l.t("취소", "Cancel", "キャンセル")) { self.pendingFirstSend = nil }
                        .buttonStyle(.bordered)
                }
            }
            .padding(10)
            .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private func profileForOwner(_ id: UUID) -> PokemonChatProfile {
        guard let mon = store.ownedMons.first(where: { $0.id == id }) else { return profile }
        var owner = store.chatProfile(for: mon)
        if id == companionID, let identity { owner.apply(identity) }
        return owner
    }
}

/// 칩 한 줄. **가로 스크롤이고 절대 감기지 않는다** — 세로로 감기면 그만큼 메시지 영역과 승인
/// 카드가 밀리고, 승인 카드는 안전 경계라 축소 대상이 아니다.
///
/// 뷰로 떼어낸 이유는 레이아웃 테스트가 이 줄만 그려 볼 수 있어야 해서다(`PokemonChatConsentLabel`
/// 과 같은 이유). 액션 칩은 **누르면 문장이 채워질 뿐** 아무것도 실행하지 않는다.
struct PokemonChatChipRow: View {
    let actions: [PokemonChatAction]
    let questions: [String]
    let language: AppLanguage
    let onTap: (String) -> Void

    /// 칩을 눌렀을 때 입력칸에 남을 값. **쓰던 문장을 덮지 않는다** — 초안은 팝오버가 닫혀도
    /// 남으라고 `PokemonChatStore` 에 두었고, 그래서 되돌릴 `@State` 스냅샷이 없다. 액션 칩은
    /// 채워진 배경으로 줄 맨 앞에 앉아 눈이 먼저 닿는 자리라, 덮어쓰기면 오타 한 번에 세 문장이 진다.
    static func composed(draft: String, chip: String) -> String {
        let kept = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        // 공백뿐인 초안은 비어 있는 것으로 친다 — 전송 버튼이 이미 같은 기준으로 센다.
        return kept.isEmpty ? chip : kept + " " + chip
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                // 상태를 바꾸는 쪽이 앞에 온다. 칠할 때 채워진 배경을 쓰는 건 "이건 무언가를
                // 일으킨다" 를 질문 칩과 구분하기 위해서다 — 뜻이 다르면 생김새도 달라야 한다.
                ForEach(actions, id: \.self) { action in
                    Button(action.phrase(language)) { onTap(action.phrase(language)) }
                        .buttonStyle(.borderedProminent).controlSize(.small)
                }
                ForEach(questions, id: \.self) { question in
                    Button(question) { onTap(question) }
                        .buttonStyle(.bordered).controlSize(.small)
                }
            }.padding(.horizontal, 12).padding(.bottom, 8)
        }
    }
}

/// 전송 버튼이 곧 동의다 — 그래서 이 줄은 **누르는 자리 바로 위**에 산다. 자동 선택이 "어느
/// CLI 인가" 를 사용자 손에서 가져갔으므로, 그 답을 여기서 돌려주지 않으면 동의가 사라진다.
///
/// 자물쇠는 실제로 격리된 provider 가 해석됐을 때만 그려진다(`kind` 는 검증된 종류만 온다) —
/// 상시로 그리면 없는 보증을 광고한다.
struct PokemonChatConsentLabel: View {
    /// 대화 화면의 좌우 여백. **테스트 앵커가 여기서 나온다** — 폭 검증이 다른 상수
    /// (`PopoverMetrics.contentWidth`)를 쓰던 동안은 4pt 차이로 우연히 안전했을 뿐이라,
    /// 그 상수가 느슨해지는 순간 실제로 잘리는 라벨을 통과시켰다.
    ///
    /// 팝오버는 `PopoverMetrics.width` 를 통째로 준다. `PopoverMetrics.padding` 은 `mainContent`
    /// 안에서만 걸리고 대화는 그 **형제 가지**라 해당되지 않는다.
    static let horizontalPadding: CGFloat = 12
    static let contentWidth: CGFloat = PopoverMetrics.width - horizontalPadding * 2

    let kind: PokemonChatProviderKind
    let language: AppLanguage

    var body: some View {
        HStack(spacing: 6) {
            Text(PokemonChatProviderSelection.externalSendLabel(kind: kind, language: language))
            Label(L(language).t("도구·MCP 격리", "Tools & MCP isolated", "ツール・MCP 隔離"),
                  systemImage: "lock.fill")
                .foregroundStyle(.green)
            Spacer(minLength: 0)
        }
        .font(.caption2).foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
    }
}

private struct TodayPokedexView: View {
    let profile: PokemonChatProfile
    private var l: L { L(profile.language) }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(l.t("오늘의 도감", "Today’s Pokédex", "今日の図鑑")).font(.headline)
            Text(profile.displayName).font(.title2)
            if let flavor = profile.flavorText { Text(flavor) }
            if let genus = profile.genus { Text(l.t("분류: \(genus)", "Genus: \(genus)", "分類: \(genus)")) }
            if let habitat = profile.habitat { Text(l.t("서식지: \(habitat)", "Habitat: \(habitat)", "生息地: \(habitat)")) }
            if let ability = profile.ability { Text(l.t("특성: \(ability)", "Ability: \(ability)", "特性: \(ability)")) }
            if !profile.types.isEmpty { Label(profile.types.joined(separator: " · "), systemImage: "circle.hexagongrid") }
            Text(l.t("현재 형태: \(profile.stage)", "Current form: \(profile.stage)", "現在の姿: \(profile.stage)"))
            if let next = profile.nextEvolution { Text(l.t("다음 진화: \(next)", "Next evolution: \(next)", "次の進化: \(next)")) }
            Text(l.t("앱이 알고 있는 사실만 표시합니다.", "Only facts known by the app are shown.", "アプリが知っている事実だけを表示します。"))
                .font(.caption).foregroundStyle(.secondary)
        }.padding().frame(width: 360)
    }
}

private struct PokemonMemoryAlbumView: View {
    let companionID: UUID
    let language: AppLanguage
    let album: PokemonMemoryAlbum
    private var l: L { L(language) }
    var body: some View {
        VStack(alignment: .leading) {
            Text(l.t("기억 앨범", "Memory album", "思い出アルバム")).font(.headline)
            List {
                ForEach(album.entries(for: companionID).reversed()) { memory in
                    HStack { VStack(alignment: .leading) { Text(memory.body); Text(memory.createdAt, style: .date).font(.caption2).foregroundStyle(.secondary) }; Spacer()
                        if memory.source == .manual {
                            Button(role: .destructive) { _ = album.delete(memory) } label: { Image(systemName: "trash") }.buttonStyle(.borderless)
                        }
                    }
                }
            }
        }.padding().frame(width: 400, height: 440)
    }
}

enum PokemonChatMessagePresentation {
    static func emphasizedPokemonMessageID(in messages: [PokemonChatMessage]) -> UUID? {
        messages.last(where: { $0.role == .pokemon })?.id
    }

    static func avatarSize(isEmphasized: Bool) -> CGFloat { isEmphasized ? 72 : 28 }
}

private struct PokemonSpeechBubble: View {
    let message: PokemonChatMessage
    let profile: PokemonChatProfile
    let isEmphasized: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        switch message.role {
        case .pokemon:
            HStack(alignment: .bottom, spacing: isEmphasized ? 10 : 6) {
                PokemonChatAvatar(profile: profile, size: PokemonChatMessagePresentation.avatarSize(isEmphasized: isEmphasized))
                VStack(alignment: .leading, spacing: 3) {
                    Text(profile.nickname?.isEmpty == false ? "\(profile.nickname!) · \(profile.displayName)" : profile.displayName)
                        .font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    Text(message.body).font(isEmphasized ? .body : .callout).textSelection(.enabled)
                        .padding(.leading, 14).padding(.trailing, 11).padding(.vertical, 8)
                        .frame(minHeight: isEmphasized ? 54 : 36)
                        .background(pokemonTone, in: SpeechBubbleShape(tailOnLeadingEdge: true))
                }
                Spacer(minLength: 28)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(profile.displayName): \(message.body)")
            .scaleEffect(isEmphasized && !reduceMotion && !appeared ? 0.94 : 1)
            .opacity(isEmphasized && !reduceMotion && !appeared ? 0 : 1)
            .onAppear {
                guard isEmphasized, !reduceMotion else { return }
                withAnimation(.spring(duration: 0.28, bounce: 0.28)) { appeared = true }
            }
        case .user:
            HStack {
                Spacer(minLength: 36)
                Text(message.body).font(.callout).textSelection(.enabled).padding(9)
                    .background(Color.accentColor.opacity(0.20), in: SpeechBubbleShape(tailOnLeadingEdge: false))
                    .accessibilityLabel("Trainer: \(message.body)")
            }
        case .system:
            HStack(spacing: 6) {
                Spacer()
                Image(systemName: "info.circle").foregroundStyle(.secondary)
                Text(message.body).font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("System message: \(message.body)")
        }
    }

    private var pokemonTone: Color {
        let source = (profile.types.first ?? profile.nature ?? profile.displayName).lowercased()
        if source.contains("fire") || source.contains("불") || source.contains("ほのお") { return .orange.opacity(0.22) }
        if source.contains("water") || source.contains("물") || source.contains("みず") { return .blue.opacity(0.16) }
        if source.contains("grass") || source.contains("풀") || source.contains("くさ") { return .green.opacity(0.16) }
        if source.contains("electric") || source.contains("전기") || source.contains("でんき") { return .yellow.opacity(0.19) }
        if source.contains("psychic") || source.contains("에스퍼") || source.contains("エスパー") { return .purple.opacity(0.16) }
        if source.contains("fairy") || source.contains("페어리") || source.contains("フェアリー") { return .pink.opacity(0.18) }
        return .secondary.opacity(0.13)
    }
}

private struct PokemonChatAvatar: View {
    let profile: PokemonChatProfile
    let size: CGFloat
    var body: some View {
        SpriteView(speciesID: profile.speciesID, size: size, shiny: profile.isShiny,
                   fallbackLabel: String(profile.displayName.prefix(1)))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

private struct PokemonThinkingBubble: View {
    let profile: PokemonChatProfile
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false
    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            PokemonChatAvatar(profile: profile, size: 28)
            HStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { index in
                    Circle().frame(width: 4, height: 4)
                        .opacity(reduceMotion ? 0.65 : (pulse ? (index == 1 ? 1 : 0.45) : (index == 1 ? 0.45 : 1)))
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 9)
            .background(.secondary.opacity(0.12), in: Capsule())
            Text(L(profile.language).t("생각 중", "Thinking", "考え中")).font(.caption).foregroundStyle(.secondary)
            Spacer()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(profile.displayName) is thinking")
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true)) { pulse = true }
        }
    }
}

private struct SpeechBubbleShape: Shape {
    let tailOnLeadingEdge: Bool
    func path(in rect: CGRect) -> Path {
        let radius: CGFloat = 11
        let tail: CGFloat = 7
        let bubble = tailOnLeadingEdge
            ? CGRect(x: tail, y: 0, width: rect.width - tail, height: rect.height)
            : CGRect(x: 0, y: 0, width: rect.width - tail, height: rect.height)
        var path = Path(roundedRect: bubble, cornerRadius: radius)
        let tailY = min(max(radius + 4, rect.height * 0.66), rect.height - radius)
        if tailOnLeadingEdge {
            path.move(to: CGPoint(x: tail, y: tailY - 5))
            path.addLine(to: CGPoint(x: 0, y: tailY + 2))
            path.addLine(to: CGPoint(x: tail, y: tailY + 6))
        } else {
            path.move(to: CGPoint(x: rect.width - tail, y: tailY - 5))
            path.addLine(to: CGPoint(x: rect.width, y: tailY + 2))
            path.addLine(to: CGPoint(x: rect.width - tail, y: tailY + 6))
        }
        return path
    }
}
