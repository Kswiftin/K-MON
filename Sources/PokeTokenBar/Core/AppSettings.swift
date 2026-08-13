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
    var companionNotifications: Bool { didSet { defaults.set(companionNotifications, forKey: "companionNotifications") } }
    var updateNotificationsEnabled: Bool { didSet { defaults.set(updateNotificationsEnabled, forKey: "updateNotificationsEnabled") } }
    var doNotDisturb: Bool { didSet { defaults.set(doNotDisturb, forKey: "doNotDisturb") } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        floatingPetEnabled = defaults.object(forKey: "floatingPetEnabled") as? Bool ?? false
        floatingPetSize = defaults.object(forKey: "floatingPetSize") as? Double ?? 96
        companionNotifications = defaults.object(forKey: "companionNotifications") as? Bool ?? true
        updateNotificationsEnabled = defaults.object(forKey: "updateNotificationsEnabled") as? Bool ?? true
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
