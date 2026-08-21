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
    var companionNotifications: Bool { didSet { defaults.set(companionNotifications, forKey: "companionNotifications") } }
    var updateNotificationsEnabled: Bool { didSet { defaults.set(updateNotificationsEnabled, forKey: "updateNotificationsEnabled") } }
    var automaticUpdateDownloadsEnabled: Bool {
        didSet { defaults.set(automaticUpdateDownloadsEnabled, forKey: "automaticUpdateDownloadsEnabled") }
    }
    var doNotDisturb: Bool { didSet { defaults.set(doNotDisturb, forKey: "doNotDisturb") } }

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
        companionNotifications = defaults.object(forKey: "companionNotifications") as? Bool ?? true
        updateNotificationsEnabled = defaults.object(forKey: "updateNotificationsEnabled") as? Bool ?? true
        automaticUpdateDownloadsEnabled = defaults.object(forKey: "automaticUpdateDownloadsEnabled") as? Bool ?? true
        doNotDisturb = defaults.object(forKey: "doNotDisturb") as? Bool
            ?? defaults.object(forKey: "officeMode") as? Bool ?? false
    }

    func requestNotificationAuthorizationIfNeeded() {
        Task {
            _ = try? await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound])
        }
    }
}
