import Foundation

/// 업데이트로 버전이 올라간 **뒤 첫 실행**에 릴리스 노트를 띄울지 정한다.
///
/// 창·네트워크와 떼어 둔 이유: 판정이 프레젠터 안에 있으면 "신규 설치엔 안 띄운다"·"버전당 한 번"
/// 이라는 규칙을 테스트가 밟을 수 없다. 판정은 여기 한 곳이고, 도장(마지막으로 보여 준 버전)도
/// 같은 키 상수를 통해서만 읽고 쓴다.
enum ReleaseNotesGate {
    enum Action: Equatable {
        /// 창을 띄운다. 도장은 **창을 띄운 뒤에** 찍는다 — 먼저 찍으면 조회에 실패한 노트가 영영 사라진다.
        case show
        /// 창 없이 도장만. 신규 설치이거나 사용자가 기능을 꺼 둔 경우다.
        case stampOnly
        /// 아무것도 하지 않는다. 같은 버전 재실행이거나 옛 빌드를 도로 실행한 경우다.
        case skip
    }

    static let lastSeenVersionKey = "lastSeenReleaseNotesVersion"

    /// - Parameters:
    ///   - lastSeen: 마지막으로 노트를 보여 준(=도장 찍은) 버전. `nil` 이면 이 Mac 의 첫 실행이다.
    static func decide(current: String, lastSeen: String?, enabled: Bool) -> Action {
        // 첫 실행에 남의 릴리스 노트를 던지지 않는다. 도장만 찍어 다음 업데이트부터 센다.
        guard let lastSeen else { return .stampOnly }
        // 문자열 비교는 "2.0.9" > "2.0.10" 으로 뒤집힌다 — 업데이트 판정과 같은 semver 비교를 쓴다.
        guard UpdateChecker.isNewer(current, than: lastSeen) else { return .skip }
        // 꺼 둔 동안에도 도장은 찍는다. 안 찍으면 다시 켰을 때 묵은 버전 노트가 튀어나온다.
        return enabled ? .show : .stampOnly
    }

    static func lastSeenVersion(in defaults: UserDefaults) -> String? {
        defaults.string(forKey: lastSeenVersionKey)
    }

    static func stamp(_ version: String, in defaults: UserDefaults) {
        defaults.set(version, forKey: lastSeenVersionKey)
    }
}
