import AppKit
import SwiftUI

struct PokemonChatView: View {
    let store: CompanionStore
    let companionID: UUID
    let chat: PokemonChatStore
    let album: PokemonMemoryAlbum
    let toolbox: any PokemonChatToolRunning
    let settings: AppSettings
    @State private var identity: PokemonSpeciesIdentity?
    @State private var draft = ""
    @State private var destination: Destination?
    @AppStorage("pokemonChatProvider") private var providerRaw = ""

    private enum Destination: String, Identifiable { case album, dailyDex; var id: String { rawValue } }

    init(store: CompanionStore, companionID: UUID, chat: PokemonChatStore? = nil,
         album: PokemonMemoryAlbum? = nil, toolbox: any PokemonChatToolRunning, settings: AppSettings) {
        self.store = store
        self.companionID = companionID
        self.chat = chat ?? store.chatStore
        self.album = album ?? store.memoryAlbum
        self.toolbox = toolbox
        self.settings = settings
    }
    private var baseProfile: PokemonChatProfile {
        store.ownedMons.first(where: { $0.id == companionID }).map(store.chatProfile(for:))
            ?? PokemonChatProfile(speciesID: 0, displayName: "?", nickname: nil, nature: nil, level: 1, stage: "", flavorText: nil, language: store.language)
    }
    private var profile: PokemonChatProfile { var value = baseProfile; if let identity { value.apply(identity) }; return value }
    private var l: L { L(profile.language) }

    private var selectedKind: PokemonChatProviderKind? { PokemonChatProviderKind(rawValue: providerRaw) }

    private var provider: (any PokemonChatProviding)? {
        guard let kind = selectedKind,
              let arguments = PokemonChatProviderSafety.arguments(for: kind),
              let executableURL = PokemonChatProviderExecutableResolver.executableURL(for: kind) else { return nil }
        return PokemonChatCLIProvider(executableURL: executableURL, arguments: arguments, kind: kind)
    }

    /// 차단(사용자가 할 수 있는 일이 없다)과 실행 파일 미발견(설정에서 경로를 지정하면 된다)은
    /// 다른 사유다. 한 문장으로 뭉개면 어느 쪽도 안내가 되지 않는다.
    private var unavailableReason: String? {
        guard let kind = selectedKind, provider == nil else { return nil }
        if let reason = PokemonChatProviderSafety.availability(for: kind).blockReason {
            return reason.message(profile.language)
        }
        let name = kind.label(profile.language)
        return l.t("\(name) 실행 파일을 흔한 설치 위치에서 찾지 못했습니다. 아래에서 직접 고르거나 설정에서 경로를 넣으세요.",
                   "Could not find the \(name) executable in the usual install locations. Choose it below, or type its path in Settings.",
                   "\(name) の実行ファイルが標準の場所で見つかりません。下で選ぶか、設定でパスを入力してください。")
    }

    /// 실행 파일을 못 찾은 자리에서 **바로** 고를 수 있게 한다. 설정 화면은 팝오버 안에 있고 대화는
    /// 별도 창이라, "설정으로 가세요" 한 줄은 사용자에게 창을 두 번 옮기라는 뜻이 된다.
    private func chooseExecutable(_ kind: PokemonChatProviderKind) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false; panel.canChooseFiles = true; panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.directoryURL = URL(fileURLWithPath: NSHomeDirectory() + "/.local/bin")
        panel.message = l.t("CLI 실행 파일을 선택하세요.", "Choose the CLI executable.", "CLI 実行ファイルを選んでください。")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        settings.setChatProviderExecutablePath(url.path, for: kind)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if let unavailableReason {
                VStack(alignment: .leading, spacing: 4) {
                    Text(unavailableReason).font(.caption2).foregroundStyle(.orange)
                    // 차단된 제공자에는 고를 실행 파일이 없다 — 버튼을 그리면 사용자가 할 수 있는
                    // 일이 있는 것처럼 보인다.
                    if let kind = selectedKind,
                       PokemonChatProviderSafety.availability(for: kind).isVerified {
                        Button(l.t("실행 파일 선택…", "Choose executable…", "実行ファイルを選択…")) {
                            chooseExecutable(kind)
                        }.buttonStyle(.link).font(.caption2)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).padding(.bottom, 8)
            }
            Divider()
            statusBar
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
                        if chat.isSending {
                            PokemonThinkingBubble(profile: profile).id("sending")
                        }
                    }.padding(12)
                }
                .onChange(of: chat.messages(for: companionID).count) { _, _ in
                    if let id = chat.messages(for: companionID).last?.id { proxy.scrollTo(id, anchor: .bottom) }
                }
                .onChange(of: chat.isSending) { _, sending in
                    if sending { proxy.scrollTo("sending", anchor: .bottom) }
                    else if let id = chat.messages(for: companionID).last?.id { proxy.scrollTo(id, anchor: .bottom) }
                }
            }
            proposalCard
            if let error = chat.errorMessage { Text(error).font(.caption2).foregroundStyle(.red).padding(.horizontal, 12) }
            Divider()
            HStack(alignment: .bottom, spacing: 8) {
                TextField(l.t("메시지를 입력하세요", "Type a message", "メッセージを入力"), text: $draft, axis: .vertical)
                    .textFieldStyle(.roundedBorder).lineLimit(1...4)
                    .onSubmit(send)
                Button(action: send) { Image(systemName: "paperplane.fill") }
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || provider == nil)
            }.padding(12)
        }
        .frame(width: 420, height: 520)
        .sheet(item: $destination) { destination in
            switch destination {
            case .album: PokemonMemoryAlbumView(companionID: companionID, language: profile.language, album: album)
            case .dailyDex: TodayPokedexView(profile: profile)
            }
        }
        .task(id: profile.speciesID) {
            identity = await PokeAPIClient.shared.chatSpeciesIdentity(speciesID: profile.speciesID, language: profile.language)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.displayName).font(.headline)
                Text(profile.flavorText ?? "PokéAPI 설명을 불러오는 중…").font(.caption2).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer()
            Picker("AI", selection: $providerRaw) {
                Text(l.t("AI 선택", "Choose AI", "AI を選択")).tag("")
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
            }.labelsHidden().frame(width: 140)
            Menu { Button(l.t("기억 앨범", "Memory album", "思い出アルバム")) { destination = .album }
                Button(l.t("새 대화", "New chat", "新しい会話")) { chat.startNewSession(for: companionID, profile: profile) }
                Button(l.t("기록 삭제", "Delete history", "履歴を削除"), role: .destructive) { chat.deleteSession(for: companionID) }
            } label: { Image(systemName: "ellipsis.circle") }.menuStyle(.borderlessButton)
        }.padding(12)
    }

    private var statusBar: some View {
        HStack(spacing: 6) {
            let name = selectedKind?.label(profile.language) ?? l.t("AI 미선택", "No AI", "AI 未選択")
            Label(name, systemImage: "sparkles").font(.caption2)
            Text(l.t("외부 전송", "Sent externally", "外部送信")).font(.caption2).foregroundStyle(.secondary)
            // 자물쇠는 실제로 격리된 provider 가 해석됐을 때만 — 상시로 그리면 차단·미선택
            // 상태에서 없는 보증을 광고한다.
            if provider != nil {
                Label(l.t("도구·MCP 격리", "Tools & MCP isolated", "ツール・MCP 隔離"), systemImage: "lock.fill")
                    .font(.caption2).foregroundStyle(.green)
            }
        }.padding(.horizontal, 12).padding(.vertical, 6)
    }

    private var questionChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(chips, id: \.self) { chip in
                    Button(chip) { if chip == dailyDexQuestion { destination = .dailyDex } else { draft = chip } }.buttonStyle(.bordered).controlSize(.small)
                }
            }.padding(.horizontal, 12).padding(.bottom, 8)
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

    private func send() {
        guard let provider else { return }
        let message = draft; draft = ""
        Task { await chat.send(message, for: companionID, profile: profile, provider: provider, toolbox: toolbox) }
    }

    private func profileForOwner(_ id: UUID) -> PokemonChatProfile {
        guard let mon = store.ownedMons.first(where: { $0.id == id }) else { return profile }
        var owner = store.chatProfile(for: mon)
        if id == companionID, let identity { owner.apply(identity) }
        return owner
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
