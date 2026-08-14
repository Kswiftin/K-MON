import AppKit
import Observation
import Sparkle

/// GitHub 릴리스에서 표시할 최신 버전을 찾고, 안정 릴리스 설치는 Sparkle에 위임한다.
/// Sparkle은 별도의 signed appcast로 다운로드를 다시 조회하고 EdDSA 서명을 검증한다.
@MainActor
@Observable
final class UpdateChecker {
    struct ReleaseInfo: Decodable, Sendable {
        struct Asset: Decodable, Sendable { let name: String; let browser_download_url: String }
        let tag_name: String
        let html_url: String
        let target_commitish: String
        let draft: Bool
        let prerelease: Bool
        let assets: [Asset]
    }
    struct Available: Equatable {
        enum Channel: Equatable { case stable, development }
        let version: String
        let url: String
        let downloadURL: String?
        let channel: Channel
    }

    private(set) var available: Available?
    private(set) var isUpdating = false

    let currentVersion: String
    let currentCommit: String
    private let repo = "Kswiftin/K-MON"
    private let clock: () -> Date
    private var lastChecked: Date?
    private let sparkleController: SPUStandardUpdaterController
    private var sparkleStarted = false
    private let updateChannel: Available.Channel

    init(currentVersion: String? = nil, currentCommit: String? = nil,
         clock: @escaping () -> Date = Date.init) {
        sparkleController = SPUStandardUpdaterController(
            startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
        self.currentVersion = currentVersion
            ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0"
        self.clock = clock
        self.currentCommit = currentCommit
            ?? (Bundle.main.object(forInfoDictionaryKey: "KMONSourceCommit") as? String) ?? "unknown"
        self.updateChannel = (Bundle.main.object(forInfoDictionaryKey: "KMONUpdateChannel") as? String) == "development"
            ? .development : .stable
    }

    /// Sparkle의 검증·다운로드·원자적 교체 helper를 시작한다. 단위 테스트 실행 파일은
    /// .app 번들이 아니므로 시작하지 않아 잘못된 feed 설정 경고창이 테스트를 방해하지 않는다.
    func startInstaller(automaticDownloads: Bool) {
        guard !sparkleStarted, Bundle.main.bundleURL.pathExtension == "app" else { return }
        sparkleController.startUpdater()
        sparkleStarted = true
        sparkleController.updater.automaticallyChecksForUpdates = true
        sparkleController.updater.automaticallyDownloadsUpdates = automaticDownloads
    }

    func setAutomaticDownloads(_ enabled: Bool) {
        guard sparkleStarted else { return }
        sparkleController.updater.automaticallyDownloadsUpdates = enabled
    }

    static let autoUpdateEnabled = true

    /// 최신 릴리스 조회 → 새 버전이고 사용자가 그 버전을 'skip' 하지 않았으면 available 설정.
    /// minInterval 보다 자주 호출되면 무시(레이트리밋 보호).
    func check(minInterval: TimeInterval = 1800) async {
        guard Self.autoUpdateEnabled else { return }
        if let last = lastChecked, clock().timeIntervalSince(last) < minInterval { return }
        lastChecked = clock()
        guard let url = URL(string: "https://api.github.com/repos/\(repo)/releases?per_page=10") else { return }
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let releases = try? JSONDecoder().decode([ReleaseInfo].self, from: data)
        else { return }
        let stable = releases.first { !$0.draft && !$0.prerelease }
        let development = releases.first { $0.tag_name == "development" && !$0.draft }
        let skipped = UserDefaults.standard.string(forKey: "skippedUpdateVersion")
        if updateChannel == .stable, let stable,
           let candidate = Self.releaseCandidate(from: stable, channel: .stable),
           Self.isNewer(candidate.version, than: currentVersion), candidate.version != skipped {
            available = candidate; return
        }
        if updateChannel == .development, let development, currentCommit != "unknown",
           !development.target_commitish.hasPrefix(currentCommit),
           !currentCommit.hasPrefix(development.target_commitish),
           let candidate = Self.releaseCandidate(from: development, channel: .development),
           candidate.version != skipped {
            available = candidate; return
        }
        available = nil
    }

    /// 이 버전은 다시 알리지 않음.
    func skipCurrent() {
        if let v = available?.version { UserDefaults.standard.set(v, forKey: "skippedUpdateVersion") }
        available = nil
    }

    /// 안정·개발 채널 모두 각자의 EdDSA 서명 appcast를 Sparkle이 검증하고 원자적으로 교체한다.
    func applyUpdate() {
        guard let update = available, !isUpdating else { return }
        if sparkleStarted {
            sparkleController.checkForUpdates(nil)
            return
        }
        guard let url = URL(string: update.url), url.scheme == "https", url.host == "github.com" else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: 버전 비교

    /// a 가 b 보다 높은 semver 인가. ("2.0.10" > "2.0.9" 등 숫자 비교)
    nonisolated static func isNewer(_ a: String, than b: String) -> Bool {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    /// 릴리스에 올라가는 zip 이름. `scripts/release.sh` · `.github/workflows/ci.yml` 이 만드는 이름과
    /// **글자 그대로** 같아야 한다 — 다르면 다운로드 URL 이 늘 nil 이라 앱 내 업데이트가 조용히 죽는다.
    /// ASCII 로 두는 이유: GitHub 이 에셋 이름의 비-ASCII 를 정규화해서(`Pokédoro.zip` → `Pokedoro.zip`)
    /// 업로드한 이름과 조회되는 이름이 달라진다.
    nonisolated static let releaseAssetName = "Pokedoro.zip"

    nonisolated static func releaseCandidate(from release: ReleaseInfo, channel: Available.Channel) -> Available? {
        let tag = release.tag_name
        let html = release.html_url
        guard
              let htmlURL = URL(string: html), htmlURL.scheme == "https", htmlURL.host == "github.com" else { return nil }
        let rawDownload = release.assets.first { $0.name == releaseAssetName }?.browser_download_url
        let download = rawDownload.flatMap { value -> String? in
            guard let url = URL(string: value), url.scheme == "https", url.host == "github.com" else { return nil }
            return value
        }
        let version: String
        switch channel {
        case .stable: version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        case .development:
            let sha = release.target_commitish.prefix(7)
            version = "main-\(sha)"
        }
        return Available(version: version, url: html, downloadURL: download, channel: channel)
    }
}
