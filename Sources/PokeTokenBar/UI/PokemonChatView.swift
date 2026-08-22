import SwiftUI

struct PokemonChatView: View {
    let companionID: UUID
    @State private var profile: PokemonChatProfile
    @State private var chat = PokemonChatStore()
    @State private var draft = ""
    @AppStorage("pokemonChatProvider") private var providerRaw = ""
    @AppStorage("pokemonChatCustomExecutable") private var customExecutable = ""
    @AppStorage("pokemonChatCustomArguments") private var customArguments = ""

    init(companionID: UUID, profile: PokemonChatProfile) {
        self.companionID = companionID
        _profile = State(initialValue: profile)
    }
    private var l: L { L(profile.language) }

    private var provider: (any PokemonChatProviding)? {
        switch PokemonChatProviderKind(rawValue: providerRaw) {
        case .codex: return PokemonChatCLIProvider(executableURL: URL(fileURLWithPath: "/usr/bin/env"), arguments: ["codex", "exec", "--skip-git-repo-check"])
        case .claude: return PokemonChatCLIProvider(executableURL: URL(fileURLWithPath: "/usr/bin/env"), arguments: ["claude", "-p", "--output-format", "text"])
        case .opencode: return PokemonChatCLIProvider(executableURL: URL(fileURLWithPath: "/usr/bin/env"), arguments: ["opencode", "run"])
        case .custom:
            guard !customExecutable.isEmpty else { return nil }
            return PokemonChatCLIProvider(executableURL: URL(fileURLWithPath: customExecutable), arguments: customArguments.split(separator: " ").map(String.init))
        case nil: return nil
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if providerRaw == PokemonChatProviderKind.custom.rawValue {
                VStack(alignment: .leading, spacing: 4) {
                    Text(l.t("사용자 CLI (셸 명령이 아닌 실행 파일 경로)", "Custom CLI (executable path, not a shell command)", "カスタム CLI（シェルではなく実行ファイルのパス）"))
                        .font(.caption2).foregroundStyle(.secondary)
                    TextField("/path/to/executable", text: $customExecutable).textFieldStyle(.roundedBorder)
                    TextField(l.t("공백으로 구분한 인수", "Space-separated arguments", "空白区切りの引数"), text: $customArguments)
                        .textFieldStyle(.roundedBorder)
                }.padding(.horizontal, 12).padding(.bottom, 8)
            }
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(chat.messages(for: companionID)) { message in
                            MessageBubble(message: message, language: profile.language)
                                .id(message.id)
                        }
                        if chat.isSending { ProgressView().controlSize(.small).id("sending") }
                    }.padding(12)
                }
                .onChange(of: chat.messages(for: companionID).count) { _, _ in
                    if let id = chat.messages(for: companionID).last?.id { proxy.scrollTo(id, anchor: .bottom) }
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
        .task(id: profile.speciesID) {
            profile.flavorText = try? await PokeAPIClient.shared.chatFlavorText(speciesID: profile.speciesID, language: profile.language)
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
                Text("OpenCode").tag(PokemonChatProviderKind.opencode.rawValue)
                Text(l.t("사용자 CLI", "Custom CLI", "カスタム CLI")).tag(PokemonChatProviderKind.custom.rawValue)
            }.labelsHidden().frame(width: 120)
            Menu { Button(l.t("새 대화", "New chat", "新しい会話")) { chat.startNewSession(for: companionID, profile: profile) }
                Button(l.t("기록 삭제", "Delete history", "履歴を削除"), role: .destructive) { chat.deleteSession(for: companionID) }
            } label: { Image(systemName: "ellipsis.circle") }.menuStyle(.borderlessButton)
        }.padding(12)
    }

    private func send() {
        guard let provider else { return }
        let message = draft; draft = ""
        Task { await chat.send(message, for: companionID, profile: profile, provider: provider) }
    }
}

private struct MessageBubble: View {
    let message: PokemonChatMessage
    let language: AppLanguage
    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 36) }
            Text(message.body).font(.callout).textSelection(.enabled).padding(8)
                .background(message.role == .user ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            if message.role != .user { Spacer(minLength: 36) }
        }
    }
}
