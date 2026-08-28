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
    /// 화면에 띄울 도감 종 목록. 비어 있으면 이전 버전과 호환되도록 현재 파트너 하나를 띄운다.
    var floatingPetSpeciesIDs: [Int] {
        didSet { defaults.set(floatingPetSpeciesIDs, forKey: "floatingPetSpeciesIDs") }
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
        // 기본은 지금까지의 모습(움직임) — 설정을 새로 넣었다고 남의 펫이 말없이 정지하면 안 된다.
        floatingPetArtwork = defaults.string(forKey: "floatingPetArtwork")
            .flatMap(FloatingPetArtwork.init(rawValue:)) ?? .animated
        imageAntialiasing = defaults.object(forKey: "imageAntialiasing") as? Bool ?? true
        battleReplaySpeed = (defaults.string(forKey: "battleReplaySpeed")
            .flatMap(ReplaySpeed.init(rawValue:))) ?? .normal
        floatingPetSpeciesID = defaults.object(forKey: "floatingPetSpeciesID") as? Int
        rosterSort = (defaults.string(forKey: "rosterSort").flatMap(RosterSort.init(rawValue:))) ?? .caught
        rosterSortAscending = defaults.object(forKey: "rosterSortAscending") as? Bool ?? true
        // 예전의 단일 선택을 최초 한 번만 새 복수 선택 목록으로 옮긴다.
        if let saved = defaults.array(forKey: "floatingPetSpeciesIDs") as? [Int] {
            floatingPetSpeciesIDs = saved
        } else if let legacy = defaults.object(forKey: "floatingPetSpeciesID") as? Int {
            floatingPetSpeciesIDs = [legacy]
        } else {
            floatingPetSpeciesIDs = []
        }
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
