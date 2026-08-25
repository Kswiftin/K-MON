import Foundation
import UserNotifications

/// 게임과 앱 동작에 필요한 사용자 설정만 보관한다.
/// 게임과 앱 자체 동작에 필요한 설정 표면이다.
@MainActor
@Observable
final class AppSettings {
    private let defaults: UserDefaults

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
    var imageAntialiasing: Bool { didSet { defaults.set(imageAntialiasing, forKey: "imageAntialiasing") } }
    /// 배틀 재생 속도. **끄기가 있어야 하는 설정**이다 — 저전력과 접근성 둘 다 걸린다.
    /// 저전력 모드에선 이 값과 무관하게 재생하지 않는다(`BattleReplay.effectiveSpeed`).
    var battleReplaySpeed: ReplaySpeed {
        didSet { defaults.set(battleReplaySpeed.rawValue, forKey: "battleReplaySpeed") }
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
    var updateNotificationsEnabled: Bool { didSet { defaults.set(updateNotificationsEnabled, forKey: "updateNotificationsEnabled") } }
    var automaticUpdateDownloadsEnabled: Bool {
        didSet { defaults.set(automaticUpdateDownloadsEnabled, forKey: "automaticUpdateDownloadsEnabled") }
    }
    var doNotDisturb: Bool { didSet { defaults.set(doNotDisturb, forKey: "doNotDisturb") } }
    /// 팝오버를 열지 않아도 LAN 배틀 신청을 받는다. **켜져 있는 동안에만** Bonjour 리스너가 뜨고,
    /// 리스너가 뜨는 순간 macOS 가 로컬 네트워크 권한을 묻는다 — 배틀을 안 하는 사용자가 그 창을
    /// 영영 안 보게 하는 유일한 스위치다. 기본값은 기존 동작(켜짐)이다.
    var battleInvitesEnabled: Bool { didSet { defaults.set(battleInvitesEnabled, forKey: "battleInvitesEnabled") } }
    private var chatExecutablePaths: [String: String]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        floatingPetEnabled = defaults.object(forKey: "floatingPetEnabled") as? Bool ?? false
        floatingPetSize = defaults.object(forKey: "floatingPetSize") as? Double ?? 96
        floatingPetRoamingEnabled = defaults.object(forKey: "floatingPetRoamingEnabled") as? Bool ?? false
        floatingPetMouseChaseEnabled = defaults.object(forKey: "floatingPetMouseChaseEnabled") as? Bool ?? false
        floatingPetMovementSpeed = defaults.object(forKey: "floatingPetMovementSpeed") as? Double ?? 80
        imageAntialiasing = defaults.object(forKey: "imageAntialiasing") as? Bool ?? true
        battleReplaySpeed = (defaults.string(forKey: "battleReplaySpeed")
            .flatMap(ReplaySpeed.init(rawValue:))) ?? .normal
        floatingPetSpeciesID = defaults.object(forKey: "floatingPetSpeciesID") as? Int
        rosterSort = (defaults.string(forKey: "rosterSort").flatMap(RosterSort.init(rawValue:))) ?? .caught
        rosterSortAscending = defaults.object(forKey: "rosterSortAscending") as? Bool ?? true
        companionNotifications = defaults.object(forKey: "companionNotifications") as? Bool ?? true
        updateNotificationsEnabled = defaults.object(forKey: "updateNotificationsEnabled") as? Bool ?? true
        automaticUpdateDownloadsEnabled = defaults.object(forKey: "automaticUpdateDownloadsEnabled") as? Bool ?? true
        doNotDisturb = defaults.object(forKey: "doNotDisturb") as? Bool
            ?? defaults.object(forKey: "officeMode") as? Bool ?? false
        battleInvitesEnabled = defaults.object(forKey: "battleInvitesEnabled") as? Bool ?? true
        chatExecutablePaths = defaults.dictionary(forKey: "pokemonChatExecutablePaths") as? [String: String] ?? [:]
    }

    /// LAN 탐색을 시작해도 되는가. 설정값을 읽는 자리와 리스너를 올리는 자리가 각각 판정하면
    /// 한쪽만 바뀌어도 아무 테스트가 안 깨진다 — 판정은 여기 한 곳이다.
    var shouldStartLANDiscovery: Bool { battleInvitesEnabled }

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
