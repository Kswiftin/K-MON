import Foundation
import UserNotifications

/// 플로팅 펫 그림 — 움직임과 선명함 중 하나를 고른다. **둘 다는 안 된다.**
///
/// 공식 애니메이션 스프라이트는 5세대(블랙·화이트)가 마지막이고 6세대부터는 3D 모델로 넘어가서,
/// GIF 로 배포되는 소스가 아예 존재하지 않는다. 그래서 어느 사이트를 가도 같은 45~133px 원본을
/// 재배포한다(Showdown·PokemonDB·projectpokemon 전부 실측 동일). 그보다 선명한 건 정지 렌더뿐이다.
///
/// 정지를 골라도 펫이 화면을 돌아다니는 건 그대로다 — 그건 창 이동이라 스프라이트와 무관하다.
/// 없어지는 건 제자리 팔다리 움직임뿐이고, 대신 위아래로 살짝 흔들린다.
enum FloatingPetArtwork: String, Sendable, CaseIterable {
    /// 5세대 도트 GIF — 45~133px. 96pt 로 띄우면 레티나에서 평균 2.5배 확대된다.
    case animated
    /// Pokémon HOME 렌더 — 512×512 정지.
    case sharp
}

/// 게임과 앱 동작에 필요한 사용자 설정만 보관한다.
/// 게임과 앱 자체 동작에 필요한 설정 표면이다.
@MainActor
@Observable
final class AppSettings {
    private let defaults: UserDefaults
    private let clock: () -> Date

    var memoryHomeEnabled: Bool { didSet { defaults.set(memoryHomeEnabled, forKey: "memoryHomeEnabled") } }
    var memoryHomeDiagnosticsEnabled: Bool { didSet { defaults.set(memoryHomeDiagnosticsEnabled, forKey: "memoryHomeDiagnosticsEnabled") } }

    var floatingPetEnabled: Bool { didSet { defaults.set(floatingPetEnabled, forKey: "floatingPetEnabled") } }
    var floatingPetSize: Double { didSet { defaults.set(floatingPetSize, forKey: "floatingPetSize") } }
    var floatingPetRoamingEnabled: Bool {
        didSet { defaults.set(floatingPetRoamingEnabled, forKey: "floatingPetRoamingEnabled") }
    }
    var floatingPetMouseChaseEnabled: Bool {
        didSet { defaults.set(floatingPetMouseChaseEnabled, forKey: "floatingPetMouseChaseEnabled") }
    }
    var floatingPetMovementSpeed: Double {
        didSet { defaults.set(floatingPetMovementSpeed, forKey: "floatingPetMovementSpeed") }
    }
    /// 플로팅 펫 그림 — 움직임과 선명함은 맞바꿈이다. 애니메이션 소스는 5세대 도트가 마지막이라
    /// 원본이 45~133px 뿐이고, 그보다 선명한 건 정지 렌더(512×512)밖에 없다.
    var floatingPetArtwork: FloatingPetArtwork {
        didSet { defaults.set(floatingPetArtwork.rawValue, forKey: "floatingPetArtwork") }
    }
    var imageAntialiasing: Bool { didSet { defaults.set(imageAntialiasing, forKey: "imageAntialiasing") } }
    /// 배틀 재생 속도. **끄기가 있어야 하는 설정**이다 — 저전력과 접근성 둘 다 걸린다.
    /// 저전력 모드에선 이 값과 무관하게 재생하지 않는다(`BattleReplay.effectiveSpeed`).
    var battleReplaySpeed: ReplaySpeed {
        didSet { defaults.set(battleReplaySpeed.rawValue, forKey: "battleReplaySpeed") }
    }
    /// 기술 상성 안내를 배틀 버튼에 표시한다. 도움을 받는 대신 LAN 프로필에 초보자 배지가 공개된다.
    var beginnerModeEnabled: Bool {
        didSet { defaults.set(beginnerModeEnabled, forKey: "beginnerModeEnabled") }
    }
    /// 플로팅에 고정해 둘 도감 종. nil = 지금 키우는 파트너를 따라간다(기본).
    /// 키를 지우는 쪽으로 nil 을 표현한다 — 0 같은 센티넬을 쓰면 종 번호와 구분되지 않는다.
    var floatingPetSpeciesID: Int? {
        didSet {
            if let floatingPetSpeciesID { defaults.set(floatingPetSpeciesID, forKey: "floatingPetSpeciesID") }
            else { defaults.removeObject(forKey: "floatingPetSpeciesID") }
        }
    }
    /// 소유 포켓몬 탭의 정렬. **탭을 오가도 유지돼야 한다** — 뷰의 `@State` 에 두면 탭을 떠날 때
    /// 뷰가 사라지면서 기본값으로 돌아가, 60마리 박스에서 매번 다시 고르게 된다.
    var rosterSort: RosterSort { didSet { defaults.set(rosterSort.rawValue, forKey: "rosterSort") } }
    var rosterSortAscending: Bool {
        didSet { defaults.set(rosterSortAscending, forKey: "rosterSortAscending") }
    }
    var companionNotifications: Bool { didSet { defaults.set(companionNotifications, forKey: "companionNotifications") } }
    /// 레이드 알림(5★ 부화 15분 전 · 근처 방 개설). 부화 시각이 무작위라 습관이 대신해 주지
    /// 못하므로 기본은 켬이다 — 끄면 예약 부화는 사실상 참여 불가가 된다.
    var raidNotifications: Bool { didSet { defaults.set(raidNotifications, forKey: "raidNotifications") } }
    var updateNotificationsEnabled: Bool { didSet { defaults.set(updateNotificationsEnabled, forKey: "updateNotificationsEnabled") } }
    var automaticUpdateDownloadsEnabled: Bool {
        didSet { defaults.set(automaticUpdateDownloadsEnabled, forKey: "automaticUpdateDownloadsEnabled") }
    }
    /// 업데이트로 버전이 올라간 뒤 첫 실행에 릴리스 노트 창을 띄운다. 꺼도 버전 도장은 찍혀서
    /// (`ReleaseNotesGate`) 다시 켰을 때 묵은 노트가 튀어나오지 않는다.
    var releaseNotesOnUpdateEnabled: Bool {
        didSet { defaults.set(releaseNotesOnUpdateEnabled, forKey: "releaseNotesOnUpdateEnabled") }
    }
    var doNotDisturb: Bool { didSet { defaults.set(doNotDisturb, forKey: "doNotDisturb") } }
    /// 팝오버를 열지 않아도 LAN 배틀 신청을 받는다. **켜져 있는 동안에만** Bonjour 리스너가 뜨고,
    /// 리스너가 뜨는 순간 macOS 가 로컬 네트워크 권한을 묻는다 — 배틀을 안 하는 사용자가 그 창을
    /// 영영 안 보게 하는 유일한 스위치다. 기본값은 기존 동작(켜짐)이다.
    var battleInvitesEnabled: Bool { didSet { defaults.set(battleInvitesEnabled, forKey: "battleInvitesEnabled") } }
    /// Random installation identity for Memory Home LAN access controls.  It is intentionally not
    /// DeviceID: reinstalling/resetting preferences creates a new identity and clears old blocks.
    let memoryHomeLANPeerID: UUID
    private var chatExecutablePaths: [String: String]
    /// 대화를 외부 CLI 로 보내는 데 한 번이라도 동의했는가. **기본값은 `false` 여야 한다** — 여기서
    /// 새면 확인 창은 코드에만 있고 화면엔 없는 것이 된다. `?? false` 라 키가 없는 기존 사용자도
    /// 한 번은 묻는 쪽에서 시작한다.
    var hasAcknowledgedExternalChatSend: Bool {
        didSet { defaults.set(hasAcknowledgedExternalChatSend, forKey: "hasAcknowledgedExternalChatSend") }
    }

    init(defaults: UserDefaults = .standard, clock: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.clock = clock
        // Memory Home is part of the default experience.  `object(forKey:)` deliberately
        // distinguishes an existing user's explicit `false` choice from an unset legacy key.
        memoryHomeEnabled = defaults.object(forKey: "memoryHomeEnabled") as? Bool ?? true
        memoryHomeDiagnosticsEnabled = defaults.object(forKey: "memoryHomeDiagnosticsEnabled") as? Bool ?? false
        floatingPetEnabled = defaults.object(forKey: "floatingPetEnabled") as? Bool ?? false
        floatingPetSize = defaults.object(forKey: "floatingPetSize") as? Double ?? 96
        floatingPetRoamingEnabled = defaults.object(forKey: "floatingPetRoamingEnabled") as? Bool ?? false
        floatingPetMouseChaseEnabled = defaults.object(forKey: "floatingPetMouseChaseEnabled") as? Bool ?? false
        floatingPetMovementSpeed = defaults.object(forKey: "floatingPetMovementSpeed") as? Double ?? 80
        // 기본은 지금까지의 모습(움직임) — 설정을 새로 넣었다고 남의 펫이 말없이 정지하면 안 된다.
        floatingPetArtwork = defaults.string(forKey: "floatingPetArtwork")
            .flatMap(FloatingPetArtwork.init(rawValue:)) ?? .animated
        imageAntialiasing = defaults.object(forKey: "imageAntialiasing") as? Bool ?? true
        battleReplaySpeed = (defaults.string(forKey: "battleReplaySpeed")
            .flatMap(ReplaySpeed.init(rawValue:))) ?? .normal
        beginnerModeEnabled = defaults.object(forKey: "beginnerModeEnabled") as? Bool ?? false
        floatingPetSpeciesID = defaults.object(forKey: "floatingPetSpeciesID") as? Int
        rosterSort = (defaults.string(forKey: "rosterSort").flatMap(RosterSort.init(rawValue:))) ?? .caught
        rosterSortAscending = defaults.object(forKey: "rosterSortAscending") as? Bool ?? true
        companionNotifications = defaults.object(forKey: "companionNotifications") as? Bool ?? true
        raidNotifications = defaults.object(forKey: "raidNotifications") as? Bool ?? true
        updateNotificationsEnabled = defaults.object(forKey: "updateNotificationsEnabled") as? Bool ?? true
        automaticUpdateDownloadsEnabled = defaults.object(forKey: "automaticUpdateDownloadsEnabled") as? Bool ?? true
        releaseNotesOnUpdateEnabled = defaults.object(forKey: "releaseNotesOnUpdateEnabled") as? Bool ?? true
        doNotDisturb = defaults.object(forKey: "doNotDisturb") as? Bool
            ?? defaults.object(forKey: "officeMode") as? Bool ?? false
        battleInvitesEnabled = defaults.object(forKey: "battleInvitesEnabled") as? Bool ?? true
        if let value = defaults.string(forKey: "memoryHomeLANPeerID"), let id = UUID(uuidString: value) {
            memoryHomeLANPeerID = id
        } else {
            let id = UUID(); memoryHomeLANPeerID = id
            defaults.set(id.uuidString, forKey: "memoryHomeLANPeerID")
        }
        chatExecutablePaths = defaults.dictionary(forKey: "pokemonChatExecutablePaths") as? [String: String] ?? [:]
        hasAcknowledgedExternalChatSend = defaults.object(forKey: "hasAcknowledgedExternalChatSend") as? Bool ?? false
    }

    /// LAN 탐색을 시작해도 되는가. 설정값을 읽는 자리와 리스너를 올리는 자리가 각각 판정하면
    /// 한쪽만 바뀌어도 아무 테스트가 안 깨진다 — 판정은 여기 한 곳이다.
    var shouldStartLANDiscovery: Bool { battleInvitesEnabled }

    /// Opt-in only, local-only aggregate. No companion, memory, or chat content is retained here.
    func recordMemoryHomeEntry() {
        guard memoryHomeDiagnosticsEnabled else { return }
        let now = clock()
        recordMemoryHomeExposure(at: now)
        incrementDiagnostic("memoryHomeDiagnosticsHomeEntries", weekKey(for: now))
    }

    /// Visibility and entry are deliberately distinct: revealing the card while Home is already
    /// selected sets the period start but must not inflate the tab-entry counter.
    func recordMemoryHomeExposure() {
        guard memoryHomeDiagnosticsEnabled else { return }
        recordMemoryHomeExposure(at: clock())
    }

    func recordManualMemoryCreated() {
        guard memoryHomeDiagnosticsEnabled else { return }
        incrementDiagnostic("memoryHomeDiagnosticsManualCreations", weekKey(for: clock()))
    }

    func memoryHomeDiagnosticsData() throws -> Data {
        struct Export: Codable {
            let periodStart: Date?
            let periodEnd: Date
            let homeEntriesByWeek: [String: Int]
            let manualMemoriesByWeek: [String: Int]
        }
        let export = Export(periodStart: defaults.object(forKey: "memoryHomeDiagnosticsFirstSeen") as? Date,
                            periodEnd: clock(),
                            homeEntriesByWeek: defaults.dictionary(forKey: "memoryHomeDiagnosticsHomeEntries") as? [String: Int] ?? [:],
                            manualMemoriesByWeek: defaults.dictionary(forKey: "memoryHomeDiagnosticsManualCreations") as? [String: Int] ?? [:])
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(export)
    }

    private func incrementDiagnostic(_ key: String, _ week: String) {
        var counts = defaults.dictionary(forKey: key) as? [String: Int] ?? [:]
        counts[week, default: 0] += 1
        defaults.set(counts, forKey: key)
    }

    private func recordMemoryHomeExposure(at date: Date) {
        if defaults.object(forKey: "memoryHomeDiagnosticsFirstSeen") == nil {
            defaults.set(date, forKey: "memoryHomeDiagnosticsFirstSeen")
        }
    }

    private func weekKey(for date: Date) -> String {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = .current
        let parts = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return String(format: "%04d-W%02d", parts.yearForWeekOfYear ?? 0, parts.weekOfYear ?? 0)
    }

    static func chatProviderPathKey(_ kind: PokemonChatProviderKind) -> String { "pokemonChatExecutablePath.\(kind.rawValue)" }
    func chatProviderExecutablePath(for kind: PokemonChatProviderKind) -> String? { chatExecutablePaths[kind.rawValue] }
    func setChatProviderExecutablePath(_ path: String?, for kind: PokemonChatProviderKind) {
        if let path, !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { chatExecutablePaths[kind.rawValue] = path }
        else { chatExecutablePaths.removeValue(forKey: kind.rawValue) }
        defaults.set(chatExecutablePaths, forKey: "pokemonChatExecutablePaths")
        if let path { defaults.set(path, forKey: Self.chatProviderPathKey(kind)) } else { defaults.removeObject(forKey: Self.chatProviderPathKey(kind)) }
    }

    func requestNotificationAuthorizationIfNeeded() {
        Task {
            _ = try? await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound])
        }
    }
}
