import SwiftUI

struct PokemonChatView: View {
    let companionID: UUID
    @State private var profile: PokemonChatProfile
    @State private var chat = PokemonChatStore()
    @State private var draft = ""
    @State private var showingAlbum = false
    @State private var showingDailyDex = false
    @AppStorage("pokemonChatProvider") private var providerRaw = ""

    init(companionID: UUID, profile: PokemonChatProfile) {
        self.companionID = companionID
        _profile = State(initialValue: profile)
    }
    private var l: L { L(profile.language) }

    private var provider: (any PokemonChatProviding)? {
        guard let kind = PokemonChatProviderKind(rawValue: providerRaw),
              let arguments = PokemonChatProviderSafety.arguments(for: kind) else { return nil }
        return PokemonChatCLIProvider(executableURL: URL(fileURLWithPath: "/usr/bin/env"), arguments: arguments, kind: kind)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if provider == nil, !providerRaw.isEmpty {
                Text(l.t("이 제공자는 MCP·도구를 완전히 격리할 수 없어 포켓몬 대화에서 사용할 수 없습니다.",
                         "This provider is unavailable because its MCP and tool access cannot be fully isolated for Pokémon chat.",
                         "このプロバイダーは、MCP とツールへのアクセスを完全に隔離できないため使用できません。"))
                    .font(.caption2).foregroundStyle(.orange).padding(.horizontal, 12).padding(.bottom, 8)
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
            if let error = chat.errorMessage { Text(error).font(.caption2).foregroundStyle(.red).padding(.horizontal, 12) }
            Divider()
            HStack(alignment: .bottom, spacing: 8) {
                TextField(l.t("메시지를 입력하세요", "Type a message", "メッセージを入力"), text: $draft, axis: .vertical)
                    .textFieldStyle(.roundedBorder).lineLimit(1...4)
                    .onSubmit(send)
                Button(action: send) { Image(systemName: "paperplane.fill") }
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || provider == nil || chat.isSending)
            }.padding(12)
        }
        .frame(width: 420, height: 520)
        .sheet(isPresented: $showingAlbum) { PokemonMemoryAlbumView(companionID: companionID, language: profile.language) }
        .sheet(isPresented: $showingDailyDex) { TodayPokedexView(profile: profile) }
        .task(id: profile.speciesID) {
            profile.flavorText = try? await PokeAPIClient.shared.chatFlavorText(speciesID: profile.speciesID, language: profile.language)
            if profile.types.isEmpty,
               let battleProfile = try? await PokeAPIClient.shared.battleProfile(speciesID: profile.speciesID) {
                profile.types = battleProfile.types.map { $0.name(profile.language) }
            }
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
                Text("Codex").tag(PokemonChatProviderKind.codex.rawValue)
                Text("Claude Code").tag(PokemonChatProviderKind.claude.rawValue)
                Text("OpenCode (disabled)").tag(PokemonChatProviderKind.opencode.rawValue)
                Text(l.t("사용자 CLI (사용 안 함)", "Custom CLI (disabled)", "カスタム CLI（無効）")).tag(PokemonChatProviderKind.custom.rawValue)
            }.labelsHidden().frame(width: 120)
            Menu { Button(l.t("기억 앨범", "Memory album", "思い出アルバム")) { showingAlbum = true }
                Button(l.t("새 대화", "New chat", "新しい会話")) { chat.startNewSession(for: companionID, profile: profile) }
                Button(l.t("기록 삭제", "Delete history", "履歴を削除"), role: .destructive) { chat.deleteSession(for: companionID) }
            } label: { Image(systemName: "ellipsis.circle") }.menuStyle(.borderlessButton)
        }.padding(12)
    }

    private var statusBar: some View {
        HStack(spacing: 6) {
            let name = PokemonChatProviderKind(rawValue: providerRaw)?.rawValue.capitalized ?? l.t("AI 미선택", "No AI", "AI 未選択")
            Label(name, systemImage: "sparkles").font(.caption2)
            Text(l.t("외부 전송", "Sent externally", "外部送信")).font(.caption2).foregroundStyle(.secondary)
            Label(l.t("도구·MCP 격리", "Tools & MCP isolated", "ツール・MCP 隔離"), systemImage: "lock.fill").font(.caption2).foregroundStyle(.green)
        }.padding(.horizontal, 12).padding(.vertical, 6)
    }

    private var questionChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(chips, id: \.self) { chip in
                    Button(chip) { if chip == dailyDexQuestion { showingDailyDex = true } else { draft = chip } }.buttonStyle(.bordered).controlSize(.small)
                }
            }.padding(.horizontal, 12).padding(.bottom, 8)
        }
    }

    private var chips: [String] {
        var values = [l.t("너의 타입이 뭐야?", "What type are you?", "きみのタイプは？"),
                      l.t("지금 기분은 어때?", "How are you feeling?", "いまの気分は？"),
                      dailyDexQuestion]
        if !profile.moves.isEmpty { values.insert(l.t("배운 기술을 알려 줘", "Tell me your moves", "覚えた技を教えて"), at: 1) }
        if profile.nextEvolution != nil { values.insert(l.t("다음 진화는 언제야?", "When is your next evolution?", "次の進化はいつ？"), at: 2) }
        return values
    }
    private var dailyDexQuestion: String { l.t("오늘의 도감을 보여 줘", "Show today’s Pokédex", "今日の図鑑を見せて") }

    private func send() {
        guard let provider else { return }
        let message = draft; draft = ""
        Task { await chat.send(message, for: companionID, profile: profile, provider: provider) }
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
    @State private var album = PokemonMemoryAlbum.shared
    private var l: L { L(language) }
    var body: some View {
        VStack(alignment: .leading) {
            HStack { Text(l.t("기억 앨범", "Memory album", "思い出アルバム")).font(.headline); Spacer()
                Button(l.t("전체 삭제", "Delete all", "すべて削除"), role: .destructive) { album.deleteAll(for: companionID) }
            }
            List {
                ForEach(album.entries(for: companionID).reversed()) { memory in
                    HStack { VStack(alignment: .leading) { Text(memory.body); Text(memory.createdAt, style: .date).font(.caption2).foregroundStyle(.secondary) }; Spacer()
                        Button(role: .destructive) { album.delete(memory) } label: { Image(systemName: "trash") }.buttonStyle(.borderless)
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
            Text("생각 중").font(.caption).foregroundStyle(.secondary)
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
