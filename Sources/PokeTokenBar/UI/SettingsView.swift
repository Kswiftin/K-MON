import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(CompanionStore.self) private var companion
    @Environment(UpdateChecker.self) private var updater
    /// 팝오버 내부 화면 전환 방식 — sheet/dismiss 를 쓰지 않는다 (PopoverView 의 NOTE 참조)
    var onClose: () -> Void
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var launchAtLoginError: String?
    @State private var reportError: String?
    @State private var isCheckingUpdate = false
    @State private var didCheckUpdate = false
    @State private var trainerNameDraft = ""
    @State private var trainerNameFeedback: String?
    private var l: L { companion.l }

    private var isBundledApp: Bool { AppEnv.isBundledApp }

    /// 이로치는 도감 격자와 같은 표식으로 — 메뉴에서만 표기가 다르면 같은 칸으로 안 보인다.
    private func speciesMenuLabel(_ species: CompanionStore.DexSpecies) -> String {
        species.isShiny ? "✨ \(species.name)" : species.name
    }

    /// 고른 종이 도감에서 사라졌으면 파트너 표기로 — 실제로 그려지는 대상(floatingPetSubject)과 맞춘다.
    private var floatingPetSpeciesSelectionLabel: String {
        guard let pinned = settings.floatingPetSpeciesID,
              let species = companion.dexSpecies.first(where: { $0.id == pinned })
        else { return l.floatingPetSpeciesFollowsPartner }
        return speciesMenuLabel(species)
    }

    /// 세이브 봉투에 남길 출처 표기 — 어느 Mac에서 내보낸 파일인지 나중에 알아보기 위한 것.
    private static var deviceName: String {
        Host.current().localizedName ?? ProcessInfo.processInfo.hostName
    }

    /// 현재 앱 버전 — 업데이트 적용 여부 확인용으로 설정창 하단에 표기.
    private static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    // MARK: 레이아웃 — 헤더 고정 / 본문 스크롤 / 푸터 고정

    var body: some View {
        @Bindable var settings = settings
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    generalGroup
                    memoryHomeGroup(settings)
                    workModeGroup(settings)
                    chatProviderGroup(settings)
                    floatingPetGroup(settings)
                    notificationsGroup(settings)
                    updateGroup(settings)
                    transferGroup
                    aboutSupportGroup
                }
                .padding(16)
            }
            Divider()
            footer
        }
        .frame(height: 460)
        .onAppear {
            if trainerNameDraft.isEmpty { trainerNameDraft = companion.trainerName }
        }
    }

    @ViewBuilder
    private func workModeGroup(_ settings: AppSettings) -> some View {
        @Bindable var settings = settings
        settingsSection(l.t("집중 타이머", "Focus timer", "集中タイマー")) {
            groupRow {
                VStack(alignment: .leading, spacing: 1) {
                    Text(l.t("방해금지 모드", "Do Not Disturb", "おやすみモード"))
                    Text(l.t("알림과 배틀 신청을 받지 않습니다.",
                             "Blocks notifications and incoming battle challenges.",
                             "通知とバトルの申し込みを受け取りません。"))
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                Spacer()
                Toggle("", isOn: $settings.doNotDisturb)
                    .labelsHidden().toggleStyle(.switch).controlSize(.small)
            }
        }
    }

    @ViewBuilder
    private func chatProviderGroup(_ settings: AppSettings) -> some View {
        settingsSection(l.t("포켓몬 대화 CLI", "Pokémon chat CLI", "ポケモン会話 CLI")) {
            Text(l.t("Finder/launchd의 PATH를 사용하지 않습니다. 흔한 설치 위치를 먼저 찾아보고, 없으면 아래에 경로를 직접 넣으세요.",
                     "The app never uses Finder or launchd PATH. Common install locations are searched first; type a path below if none matched.",
                     "Finder/launchd の PATH は使いません。よくあるインストール先を先に探し、見つからなければ下にパスを直接入力してください。"))
                .font(.caption2).foregroundStyle(.secondary)
            ForEach(PokemonChatProviderSafety.verifiedKinds, id: \.self) { kind in
                chatProviderRow(kind, settings: settings)
            }
        }
    }

    /// 한 CLI 의 상태 + 고치는 방법을 한 줄에 둔다. 상태만 보여 주고 고치는 자리가 다른 화면이면,
    /// "찾지 못함" 을 본 사용자가 다음에 무엇을 눌러야 하는지 알 수 없다.
    @ViewBuilder
    private func chatProviderRow(_ kind: PokemonChatProviderKind, settings: AppSettings) -> some View {
        // 지정 경로는 아래 칸(`chatExecutablePathBinding`)이 읽는 것과 **같은 저장소**에서 온다.
        // 해석만 다른 곳을 읽으면 이 줄의 초록 체크가 사용자가 방금 지운 경로를 계속 가리킨다.
        let resolved = PokemonChatProviderExecutableResolver.executableURL(
            for: kind, override: settings.chatProviderExecutablePath(for: kind),
            searchPaths: PokemonChatProviderExecutableResolver.standardPaths(for: kind))
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(kind.label(l.lang))
                Spacer()
                if let resolved {
                    Label(resolved.path, systemImage: "checkmark.circle.fill")
                        .font(.caption2).foregroundStyle(.green).lineLimit(1).truncationMode(.middle)
                } else {
                    Label(l.t("찾지 못함", "Not found", "未検出"), systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2).foregroundStyle(.orange)
                }
                Button(l.t("선택…", "Choose…", "選択…")) { chooseChatExecutable(kind, settings: settings) }
                if settings.chatProviderExecutablePath(for: kind) != nil {
                    Button(l.t("지우기", "Clear", "消去")) { settings.setChatProviderExecutablePath(nil, for: kind) }
                }
            }
            // 직접 입력을 파일 선택창과 함께 둔다 — NSOpenPanel 은 `~/.local` 같은 숨김 폴더로
            // Cmd+Shift+G 없이 갈 수 없어, 정작 CLI 가 가장 많이 사는 자리를 못 고른다.
            TextField(l.t("예: \(NSHomeDirectory())/.local/bin/\(PokemonChatProviderExecutableResolver.binaryName(for: kind) ?? "")",
                          "e.g. \(NSHomeDirectory())/.local/bin/\(PokemonChatProviderExecutableResolver.binaryName(for: kind) ?? "")",
                          "例: \(NSHomeDirectory())/.local/bin/\(PokemonChatProviderExecutableResolver.binaryName(for: kind) ?? "")"),
                      text: chatExecutablePathBinding(kind, settings: settings))
                .textFieldStyle(.roundedBorder).font(.caption2)
            if let typed = settings.chatProviderExecutablePath(for: kind), !typed.isEmpty,
               PokemonChatProviderExecutableResolver.validatedExecutable(typed) == nil {
                // 저장은 막지 않는다(오타를 고치는 중일 수 있다). 다만 이 경로로는 아무것도 실행되지
                // 않는다는 사실을 대화 창까지 끌고 가지 않는다.
                Text(l.t("이 경로에는 실행 가능한 파일이 없습니다.",
                         "No executable file at this path.",
                         "このパスに実行可能なファイルがありません。"))
                    .font(.caption2).foregroundStyle(.red)
            }
            if resolved == nil {
                Text(l.t("찾아본 곳: \(PokemonChatProviderExecutableResolver.searchDirectories.joined(separator: ", "))",
                         "Searched: \(PokemonChatProviderExecutableResolver.searchDirectories.joined(separator: ", "))",
                         "探した場所: \(PokemonChatProviderExecutableResolver.searchDirectories.joined(separator: ", "))"))
                    .font(.caption2).foregroundStyle(.secondary)
                Text(l.t("터미널에서 `which \(PokemonChatProviderExecutableResolver.binaryName(for: kind) ?? "")` 결과를 위에 붙여 넣으면 됩니다.",
                         "Paste the output of `which \(PokemonChatProviderExecutableResolver.binaryName(for: kind) ?? "")` above.",
                         "ターミナルの `which \(PokemonChatProviderExecutableResolver.binaryName(for: kind) ?? "")` の結果を上に貼り付けてください。"))
                    .font(.caption2).foregroundStyle(.secondary).textSelection(.enabled)
            }
        }
    }

    private func chatExecutablePathBinding(_ kind: PokemonChatProviderKind, settings: AppSettings) -> Binding<String> {
        Binding(get: { settings.chatProviderExecutablePath(for: kind) ?? "" },
                set: { settings.setChatProviderExecutablePath($0, for: kind) })
    }

    private func chooseChatExecutable(_ kind: PokemonChatProviderKind, settings: AppSettings) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false; panel.canChooseFiles = true; panel.allowsMultipleSelection = false
        // CLI 가 사는 자리는 대부분 숨김 폴더다. 기본값으로 열어 주지 않으면 사용자가 Cmd+Shift+G 를
        // 알아야만 자기 설치분에 닿는다.
        panel.showsHiddenFiles = true
        panel.directoryURL = URL(fileURLWithPath: NSHomeDirectory() + "/.local/bin")
        panel.message = l.t("CLI 실행 파일을 선택하세요.", "Choose the CLI executable.", "CLI 実行ファイルを選んでください。")
        if panel.runModal() == .OK, let url = panel.url { settings.setChatProviderExecutablePath(url.path, for: kind) }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Button(action: onClose) {
                HStack(spacing: 2) {
                    Image(systemName: "chevron.backward")
                    Text(l.back)
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
            .keyboardShortcut(.cancelAction)
            Spacer()
            Text(l.settings).font(.headline)
            Spacer()
            // 좌측 뒤로 버튼과 시각적 균형 (제목 중앙 정렬 유지)
            Text(l.back).opacity(0).accessibilityHidden(true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var footer: some View {
        HStack(spacing: 5) {
            Text("v\(Self.appVersion)")
            Text("·")
            footerLink("GitHub", "https://github.com/Kswiftin/K-MON")
            Spacer()
        }
        .font(.caption2)
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: 그룹 섹션

    @ViewBuilder
    private var generalGroup: some View {
        @Bindable var settings = settings
        settingsSection(l.generalSectionTitle) {
            VStack(alignment: .leading, spacing: 5) {
                Text(l.trainerNamePrompt)
                HStack(spacing: 7) {
                    TextField(l.trainerNamePlaceholder, text: $trainerNameDraft)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { commitTrainerName() }
                        .onChange(of: trainerNameDraft) { trainerNameFeedback = nil }
                    Button(l.t("저장", "Save", "保存")) { commitTrainerName() }
                        .buttonStyle(.borderedProminent)
                        .disabled(normalizedTrainerName.isEmpty || normalizedTrainerName == companion.trainerName)
                }
                Text(trainerNameFeedback
                     ?? l.t("배틀·교환·멀티플레이에서 다른 트레이너에게 표시됩니다.",
                            "Shown to other trainers in battles, trades, and multiplayer.",
                            "バトル・交換・マルチプレイでほかのトレーナーに表示されます。"))
                    .font(.caption2)
                    .foregroundStyle(trainerNameFeedback == nil ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.green))
            }
            Divider()
            groupRow {
                Text(l.language)
                Spacer()
                Picker("", selection: Binding(
                    get: { companion.language },
                    set: { companion.setLanguage($0) })) {
                    ForEach(AppLanguage.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .labelsHidden().pickerStyle(.menu).fixedSize()
            }
            Divider()
            groupRow {
                VStack(alignment: .leading, spacing: 1) {
                    Text(l.launchAtLogin)
                    if !isBundledApp {
                        Text(l.bundledOnly).font(.caption2).foregroundStyle(.tertiary)
                    }
                    if let launchAtLoginError {
                        Text(launchAtLoginError).font(.caption2).foregroundStyle(.red)
                    }
                }
                Spacer()
                Toggle("", isOn: $launchAtLogin)
                    .labelsHidden().toggleStyle(.switch).controlSize(.small)
                    .disabled(!isBundledApp)
                    .onChange(of: launchAtLogin) { _, newValue in
                        do {
                            try LoginItem.setEnabled(newValue)   // KeepAlive 에이전트(로그인 실행+크래시 재실행)
                            launchAtLoginError = nil
                        } catch {
                            launchAtLoginError = "\(error.localizedDescription)"
                            launchAtLogin = LoginItem.isEnabled
                        }
                    }
            }
            Divider()
            toggleRow(l.imageAntialiasingLabel, $settings.imageAntialiasing)
            Divider()
            groupRow {
                Text(l.battleReplaySpeedLabel)
                Spacer()
                // 끄기가 목록에 있어야 하는 설정이다 — 저전력·접근성. 저전력 모드에선 여기서 무엇을
                // 골랐든 재생하지 않는다(`BattleReplay.effectiveSpeed`).
                Picker("", selection: $settings.battleReplaySpeed) {
                    ForEach(ReplaySpeed.allCases, id: \.self) { Text(l.battleReplaySpeedName($0)).tag($0) }
                }
                .labelsHidden().pickerStyle(.menu).fixedSize()
            }
            Divider()
            groupRow {
                VStack(alignment: .leading, spacing: 1) {
                    Text(l.t("초보자 모드", "Beginner mode", "初心者モード"))
                    Text(l.t("배틀 기술 버튼에 상대 타입 상성을 표시하며, 친구들에게 초보자 배지가 공개됩니다.",
                             "Shows type matchups on move buttons and displays a public beginner badge.",
                             "技ボタンに相性を表示し、公開の初心者バッジが付きます。"))
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                Spacer()
                Toggle("", isOn: $settings.beginnerModeEnabled)
                    .labelsHidden().toggleStyle(.switch).controlSize(.small)
            }
        }
    }

    private var normalizedTrainerName: String {
        String(trainerNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(SaveTransfer.maxNameLength))
    }

    private func commitTrainerName() {
        guard !normalizedTrainerName.isEmpty else { return }
        companion.setTrainerName(normalizedTrainerName)
        trainerNameDraft = companion.trainerName
        trainerNameFeedback = l.t("닉네임을 저장했습니다.", "Nickname saved.", "ニックネームを保存しました。")
    }

    @ViewBuilder
    private func memoryHomeGroup(_ settings: AppSettings) -> some View {
        @Bindable var settings = settings
        settingsSection(l.t("기억 홈", "Memory Home", "メモリーホーム")) {
            groupRow {
                VStack(alignment: .leading, spacing: 1) {
                    Text(l.t("홈에 기억 표시", "Show memories on Home", "ホームに思い出を表示"))
                    Text(l.t("기본으로 켜져 있으며, 개인 메모는 대화 제공자에게 전달되지 않습니다.",
                             "On by default. Private notes are never sent to chat providers.",
                             "初期設定はオンです。個人メモは会話プロバイダに送信されません。"))
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                Spacer()
                Toggle("", isOn: $settings.memoryHomeEnabled).labelsHidden().toggleStyle(.switch).controlSize(.small)
            }
            Divider()
            groupRow {
                VStack(alignment: .leading, spacing: 1) {
                    Text(l.t("로컬 사용 진단", "Local usage diagnostics", "ローカル利用診断"))
                    Text(l.t("동의 시 홈 방문과 메모 생성 횟수만 이 Mac에 집계합니다.",
                             "With consent, only Home visits and note counts are aggregated on this Mac.",
                             "同意すると、ホーム閲覧とメモ作成数だけをこの Mac に集計します。"))
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                Spacer()
                Toggle("", isOn: $settings.memoryHomeDiagnosticsEnabled).labelsHidden().toggleStyle(.switch).controlSize(.small)
            }
            if settings.memoryHomeDiagnosticsEnabled {
                Divider()
                groupRow {
                    Text(l.t("진단 JSON 내보내기", "Export diagnostics JSON", "診断 JSON を書き出す"))
                    Spacer()
                    Button(l.t("내보내기", "Export", "書き出す")) { exportMemoryHomeDiagnostics() }
                }
            }
        }
    }

    @ViewBuilder
    private func floatingPetGroup(_ settings: AppSettings) -> some View {
        @Bindable var settings = settings
        settingsSection(l.floatingPetSectionTitle) {
            groupRow {
                VStack(alignment: .leading, spacing: 1) {
                    Text(l.floatingPetEnableLabel)
                    Text(l.floatingPetHint).font(.caption2).foregroundStyle(.tertiary)
                }
                Spacer()
                Toggle("", isOn: $settings.floatingPetEnabled)
                    .labelsHidden().toggleStyle(.switch).controlSize(.small)
            }
            if settings.floatingPetEnabled {
                Divider()
                groupRow {
                    Text(l.floatingPetSizeLabel).font(.callout)
                    Slider(value: $settings.floatingPetSize, in: 48...192, step: 8)
                    Text("\(Int(settings.floatingPetSize))px")
                        .font(.caption).monospacedDigit().frame(width: 44, alignment: .trailing)
                }
                Divider()
                // 크기 바로 아래에 둔다 — 크게 띄울수록 흐려지므로 두 설정을 같이 만지게 된다.
                VStack(alignment: .leading, spacing: 4) {
                    Picker(selection: $settings.floatingPetArtwork) {
                        ForEach(FloatingPetArtwork.allCases, id: \.self) { artwork in
                            Text(l.floatingPetArtworkLabel(artwork)).tag(artwork)
                        }
                    } label: {
                        Text(l.floatingPetArtworkTitle).font(.callout)
                    }
                    .pickerStyle(.segmented)
                    Text(l.floatingPetArtworkHint(settings.floatingPetArtwork))
                        .font(.caption2).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Divider()
                toggleRow(l.floatingPetRoamingLabel, $settings.floatingPetRoamingEnabled)
                Divider()
                toggleRow(l.floatingPetMouseChaseLabel, $settings.floatingPetMouseChaseEnabled)
                if settings.floatingPetRoamingEnabled || settings.floatingPetMouseChaseEnabled {
                    Divider()
                    groupRow {
                        Text(l.floatingPetSpeedLabel).font(.callout)
                        Slider(value: $settings.floatingPetMovementSpeed, in: 20...200, step: 10)
                        Text("\(Int(settings.floatingPetMovementSpeed))")
                            .font(.caption).monospacedDigit().frame(width: 32, alignment: .trailing)
                    }
                }
                Divider()
                groupRow {
                    Text(l.floatingPetSpeciesLabel).font(.callout)
                    Spacer()
                    // 진화 라인을 하위 메뉴로 접는다 — 도감이 커지면 평평한 목록은 스크롤만 길어진다.
                    Menu {
                        Button(l.floatingPetSpeciesFollowsPartner) { settings.floatingPetSpeciesID = nil }
                        ForEach(companion.dexLines) { line in
                            Menu(line.name) {
                                ForEach(line.species) { species in
                                    Button(speciesMenuLabel(species)) {
                                        settings.floatingPetSpeciesID = species.id
                                    }
                                }
                            }
                        }
                    } label: {
                        Text(floatingPetSpeciesSelectionLabel)
                    }
                    .menuStyle(.borderlessButton).controlSize(.small).frame(maxWidth: 180)
                }
            }
        }
    }

    @ViewBuilder
    private func notificationsGroup(_ settings: AppSettings) -> some View {
        @Bindable var settings = settings
        settingsSection(l.notificationsSection) {
            toggleRow(l.companionNotificationsLabel, $settings.companionNotifications)
            groupRow {
                VStack(alignment: .leading, spacing: 1) {
                    Text(l.raidNotificationsLabel)
                    Text(l.raidNotificationsHint).font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("", isOn: $settings.raidNotifications).labelsHidden()
            }
            groupRow {
                VStack(alignment: .leading, spacing: 1) {
                    Text(l.t("배틀 신청 받기", "Receive battle invites", "バトル招待を受け取る"))
                    Text(l.t("끄면 LAN 탐색을 시작하지 않아 로컬 네트워크 권한을 묻지 않습니다. 적용은 재시작 후.",
                             "Off skips LAN discovery, so macOS never asks for local network access. Takes effect after a restart.",
                             "オフにすると LAN 探索を行わないため、ローカルネットワーク権限を聞かれません。再起動後に反映。"))
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("", isOn: $settings.battleInvitesEnabled).labelsHidden()
            }
        }
    }

    @ViewBuilder
    private func updateGroup(_ settings: AppSettings) -> some View {
        @Bindable var settings = settings
        settingsSection(l.updateSectionTitle) {
            groupRow {
                VStack(alignment: .leading, spacing: 2) {
                    Text(l.githubAccountLabel)
                    if updater.githubAuth.isSignedIn {
                        Text(updater.githubAuth.login.map { "@\($0)" } ?? l.githubConnected)
                            .font(.caption2).foregroundStyle(.secondary)
                    } else if let code = updater.githubAuth.deviceCode {
                        Text(l.githubDeviceCode(code))
                            .font(.caption.monospaced().weight(.semibold))
                            .textSelection(.enabled)
                        Text(l.githubDeviceCodeHint)
                            .font(.caption2).foregroundStyle(.secondary)
                    } else {
                        Text(l.githubLoginHint).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if updater.githubAuth.isSignedIn {
                    Button(l.githubLogout) { updater.signOutFromGitHub() }.controlSize(.small)
                } else {
                    Button {
                        Task { await updater.signInToGitHub() }
                    } label: {
                        if updater.githubAuth.isAuthorizing {
                            ProgressView().controlSize(.small)
                        } else {
                            Text(l.githubLogin)
                        }
                    }
                    .disabled(updater.githubAuth.isAuthorizing)
                    .controlSize(.small)
                }
            }
            if let message = updater.githubAuth.errorMessage {
                Divider()
                groupRow { Text(message).font(.caption).foregroundStyle(.red); Spacer() }
            }
            Divider()
            toggleRow(l.updateNotificationsLabel, $settings.updateNotificationsEnabled)
            Divider()
            toggleRow(l.automaticUpdateDownloadsLabel, $settings.automaticUpdateDownloadsEnabled)
            Divider()
            toggleRow(l.releaseNotesOnUpdateLabel, $settings.releaseNotesOnUpdateEnabled)
            Divider()
            groupRow {
                Text(l.checkForUpdatesLabel)
                Spacer()
                Button {
                    isCheckingUpdate = true
                    Task {
                        await updater.check(minInterval: 0)   // 수동 확인 — 레이트리밋 우회(강제 조회)
                        isCheckingUpdate = false
                        didCheckUpdate = true
                    }
                } label: {
                    if isCheckingUpdate {
                        ProgressView().controlSize(.small)
                    } else {
                        Text(l.checkNowButton)
                    }
                }
                .disabled(isCheckingUpdate || !updater.githubAuth.isSignedIn)
            }
            // 확인 결과 — 알림을 꺼둔 사용자도 여기서 새 버전을 알고 바로 적용할 수 있게 업데이트 버튼을 함께 노출.
            if didCheckUpdate, !isCheckingUpdate {
                Divider()
                groupRow {
                    if let error = updater.checkError {
                        Text(l.updateCheckError(error)).font(.caption).foregroundStyle(.red)
                        Spacer()
                    } else if let version = updater.available?.version {
                        Text(l.updateFound(version)).font(.caption).foregroundStyle(.orange)
                        Spacer()
                        Button(l.updateButton) { updater.applyUpdate() }.controlSize(.small)
                    } else {
                        Text(l.upToDate(Self.appVersion)).font(.caption).foregroundStyle(.secondary)
                        Spacer()
                    }
                }
            }
        }
    }

    /// 백업 & 이전 — 새 Mac으로 옮길 때 쓰는 세이브 파일 내보내기/불러오기.
    /// 사용자가 상태 파일 경로를 직접 찾아다니지 않도록, 저장 위치와 불러올 파일 모두 표준
    /// 파일 선택창으로 고르게 한다.
    @ViewBuilder
    private var transferGroup: some View {
        settingsSection(l.transferSectionTitle) {
            groupRow {
                VStack(alignment: .leading, spacing: 1) {
                    Text(l.exportSaveLabel)
                    Text(l.exportSaveHint).font(.caption2).foregroundStyle(.tertiary)
                }
                Spacer()
                Button(l.exportSaveButton) { exportSave() }
            }
            Divider()
            groupRow {
                VStack(alignment: .leading, spacing: 1) {
                    Text(l.importSaveLabel)
                    Text(l.importSaveHint).font(.caption2).foregroundStyle(.tertiary)
                }
                Spacer()
                Button(l.importSaveButton) { importSave() }
            }
        }
    }

    private var aboutSupportGroup: some View {
        settingsSection(l.aboutSupportSectionTitle) {
            groupRow {
                VStack(alignment: .leading, spacing: 1) {
                    Text(l.reportProblem)
                    Text(l.reportAttachHint).font(.caption2).foregroundStyle(.tertiary)
                }
                Spacer()
                Button(l.reportProblem) { reportProblem() }
            }
            Divider()
            // 로그 파일 보기 — 문제 제보 시 바로 첨부할 수 있게 같은 그룹에 둔다(고급 접기 밖).
            groupRow {
                Text(l.showLogFile)
                Spacer()
                Button("Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([AppLog.logFileURL])
                }
            }
            if let reportError {
                Text(reportError)
                    .font(.caption2).foregroundStyle(.orange).textSelection(.enabled)
                    .padding(.horizontal, 12).padding(.bottom, 6)
            }
        }
    }

    // MARK: 공용 빌더

    /// 섹션 = 소문자 회색 타이틀 + 라운드 카드 (macOS inset grouped 룩).
    @ViewBuilder
    private func settingsSection<Content: View>(
        _ title: String, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption).fontWeight(.semibold).foregroundStyle(.secondary)
                .textCase(.uppercase).padding(.leading, 4)
            VStack(spacing: 0) { content() }
                .background(Color(nsColor: .controlBackgroundColor),
                           in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.6), lineWidth: 1))
        }
    }

    /// 카드 내부 한 줄 — 좌 라벨 / 우 컨트롤.
    private func groupRow<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 10) { content() }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .frame(minHeight: 38)
    }

    private func toggleRow(_ label: String, _ isOn: Binding<Bool>) -> some View {
        groupRow {
            Text(label)
            Spacer()
            Toggle("", isOn: isOn).labelsHidden().toggleStyle(.switch).controlSize(.small)
        }
    }

    /// 푸터 링크 — 버전 표기와 동일한 크기·색을 상속하고 밑줄로만 구분.
    private func footerLink(_ title: String, _ urlString: String) -> some View {
        Button {
            if let url = URL(string: urlString) { NSWorkspace.shared.open(url) }
        } label: {
            Text(title).underline()
        }
        .buttonStyle(.plain)
        .help(urlString)
    }

    // MARK: 동작

    /// 문제점 알리기 — 진단 정보(버전·macOS)가 채워진 리포트 메일을 기본 메일 앱으로 연다.
    /// 메일 앱이 없거나 열기에 실패하면 수신 주소를 안내(복사 가능)한다.
    private func reportProblem() {
        let subject = l.reportMailSubject(Self.appVersion)
        let body = l.reportMailBody(
            version: Self.appVersion,
            os: ProcessInfo.processInfo.operatingSystemVersionString)
        guard let url = SupportMail.mailtoURL(subject: subject, body: body),
              NSWorkspace.shared.open(url) else {
            reportError = l.reportMailFallback(SupportMail.address)
            return
        }
        reportError = nil
    }

    // MARK: 세이브 이전
    //
    // 결과를 인라인 텍스트로 못 보여주는 이유: 팝오버가 `.transient` 라 파일 선택창이 키 윈도우가 되는
    // 순간 닫히고, popoverDidClose 가 호스팅 컨트롤러를 해제해 이 뷰(@State 포함)가 사라진다.
    // → 성공은 Finder 노출(로그 파일 보기와 같은 방식), 그 외는 알림창으로 알린다.
    //
    // 활성화는 `activate(ignoringOtherApps: true)` 여야 한다 — 이 앱은 LSUIElement 라 백그라운드에서
    // `NSApp.activate()`(협조적 활성화)가 무시된다. 실측: activate() 는 isActive=false 로 최전면이 안 바뀌고
    // (패널이 다른 창 뒤에 떠 사용자가 못 찾는다), ignoringOtherApps 만 전면화된다.
    // `NSRunningApplication.current.activate(.activateAllWindows)` 도 같은 이유로 실패한다.
    // 레포의 다른 활성화 지점(PokeTokenBarApp·FloatingPetPanel)도 같은 형태다 — 통일해서 유지할 것.

    private func exportSave() {
        let panel = NSSavePanel()
        panel.title = l.exportSaveLabel
        panel.nameFieldStringValue = companion.suggestedExportFileName
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try companion.exportedSaveData(appVersion: Self.appVersion, deviceName: Self.deviceName)
            try data.write(to: url, options: .atomic)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            presentAlert(title: l.exportSaveLabel, message: error.localizedDescription, style: .warning)
        }
    }

    private func exportMemoryHomeDiagnostics() {
        let panel = NSSavePanel()
        panel.title = l.t("기억 홈 진단 내보내기", "Export Memory Home diagnostics", "メモリーホーム診断を書き出す")
        panel.nameFieldStringValue = "PokeTokenBar-MemoryHome-Diagnostics.json"
        panel.allowedContentTypes = [.json]
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try settings.memoryHomeDiagnosticsData().write(to: url, options: .atomic)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            presentAlert(title: panel.title, message: error.localizedDescription, style: .warning)
        }
    }

    private func importSave() {
        let panel = NSOpenPanel()
        panel.title = l.importSaveLabel
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let envelope: SaveEnvelope
        do {
            envelope = try SaveTransfer.decode(try Data(contentsOf: url))
        } catch {
            presentAlert(title: l.importSaveLabel, message: l.importErrorMessage(error), style: .warning)
            return
        }
        let incoming = SaveSummary(state: envelope.state)

        // 고른 즉시 덮어쓰지 않는다 — 무엇이 대체되는지 수치로 보여주고 한 번 더 확인받는다.
        let current = companion.transferSummary
        let confirm = NSAlert()
        confirm.alertStyle = .warning
        confirm.messageText = l.importConfirmTitle
        confirm.informativeText = l.importConfirmBody(
            incomingDex: incoming.dexCount,
            incomingTokens: Self.grouped(incoming.lifetimeTokens),
            exportedAt: Self.exportedAtText(envelope.exportedAt),
            sourceDevice: envelope.sourceDevice,
            currentDex: current.dexCount,
            currentTokens: Self.grouped(current.lifetimeTokens))
        confirm.addButton(withTitle: l.importConfirmReplace)
        confirm.addButton(withTitle: l.cancel)
        // 파괴적 동작을 기본 버튼으로 두지 않는다(Return 한 번에 진행이 대체되지 않게).
        // 규칙 자체는 ImportConfirmPolicy 에 있고 여기선 적용만 한다 — NSAlert 구성은 테스트 불가라
        // 순서가 뒤바뀌어도 잡을 자동 경로가 없기 때문이다.
        for (index, button) in confirm.buttons.enumerated() {
            button.keyEquivalent = ImportConfirmPolicy.keyEquivalent(forButtonAt: index)
        }
        guard confirm.runModal() == .alertFirstButtonReturn else { return }

        do {
            try companion.applySave(envelope)
        } catch {
            presentAlert(title: l.importSaveLabel, message: l.importErrorMessage(error), style: .warning)
            return
        }
        presentAlert(title: l.importSaveLabel,
                     message: l.importSaveDone(dex: incoming.dexCount,
                                               tokens: Self.grouped(incoming.lifetimeTokens)),
                     style: .informational)
    }

    private static func grouped(_ value: Int) -> String {
        value.formatted(.number.grouping(.automatic))
    }

    /// 확인창에 보일 내보낸 시각 — 사용자 로케일 기준 짧은 표기.
    private static func exportedAtText(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: date)
    }

    private func presentAlert(title: String, message: String, style: NSAlert.Style) {
        let alert = NSAlert()
        alert.alertStyle = style
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: l.close)
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
