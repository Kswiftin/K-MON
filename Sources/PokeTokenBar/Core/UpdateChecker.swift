import AppKit
import Observation
import Sparkle

/// OAuth로 비공개 GitHub 릴리스를 찾고, 안정 릴리스 설치는 Sparkle에 위임한다.
/// Sparkle의 ZIP 요청에도 같은 인증 헤더를 전달하며 실행 파일의 EdDSA 검증을 유지한다.
@MainActor
@Observable
final class UpdateChecker {
    struct ReleaseInfo: Decodable, Sendable {
        struct Asset: Decodable, Sendable {
            let name: String
            let url: String?
            let browser_download_url: String

            init(name: String, url: String? = nil, browser_download_url: String) {
                self.name = name
                self.url = url
                self.browser_download_url = browser_download_url
            }
        }
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
        let feedURL: String?
        let downloadAPIURL: String?
        let channel: Channel
    }

    private(set) var available: Available?
    private(set) var isUpdating = false
    private(set) var checkError: CheckError?
    let githubAuth: GitHubOAuth

    let currentVersion: String
    let currentCommit: String
    private let repo = "2giduck/K-MON"
    private let clock: () -> Date
    private var lastChecked: Date?
    private let sparkleController: SPUStandardUpdaterController
    private let sparkleDelegate: AuthenticatedSparkleDelegate
    private var sparkleStarted = false
    private var automaticDownloads = true
    private var periodicTimer: Timer?

    enum CheckError: Equatable { case authenticationRequired, network, repositoryAccess }

    init(currentVersion: String? = nil, currentCommit: String? = nil,
         clock: @escaping () -> Date = Date.init,
         githubAuth: GitHubOAuth? = nil) {
        let auth = githubAuth ?? GitHubOAuth()
        self.githubAuth = auth
        sparkleDelegate = AuthenticatedSparkleDelegate()
        sparkleController = SPUStandardUpdaterController(
            startingUpdater: false, updaterDelegate: sparkleDelegate, userDriverDelegate: nil)
        self.currentVersion = currentVersion
            ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0"
        self.clock = clock
        self.currentCommit = currentCommit
            ?? (Bundle.main.object(forInfoDictionaryKey: "KMONSourceCommit") as? String) ?? "unknown"
    }

    /// Sparkle의 검증·다운로드·원자적 교체 helper를 시작한다. 단위 테스트 실행 파일은
    /// .app 번들이 아니므로 시작하지 않아 잘못된 feed 설정 경고창이 테스트를 방해하지 않는다.
    func startInstaller(automaticDownloads: Bool) {
        guard !sparkleStarted, Bundle.main.bundleURL.pathExtension == "app" else { return }
        self.automaticDownloads = automaticDownloads
        applyAuthenticationToSparkle()
        sparkleController.startUpdater()
        sparkleStarted = true
        // 최신 appcast의 REST asset URL은 릴리스마다 달라져 GitHub API 조회를 먼저 해야 한다.
        // 따라서 Sparkle 자체 스케줄 대신 아래 OAuth 조회 타이머가 feed URL을 갱신한다.
        sparkleController.updater.automaticallyChecksForUpdates = false
        sparkleController.updater.automaticallyDownloadsUpdates = automaticDownloads
        periodicTimer = Timer.scheduledTimer(withTimeInterval: 21_600, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.check(minInterval: 0) }
        }
    }

    func setAutomaticDownloads(_ enabled: Bool) {
        automaticDownloads = enabled
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
        checkError = nil
        guard let headers = githubAuth.authorizationHeaders else {
            available = nil
            checkError = .authenticationRequired
            return
        }
        guard let url = URL(string: "https://api.github.com/repos/\(repo)/releases?per_page=10") else { return }
        var req = URLRequest(url: url, timeoutInterval: 15)
        headers.forEach { req.setValue($0.value, forHTTPHeaderField: $0.key) }
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              let status = (resp as? HTTPURLResponse)?.statusCode else {
            available = nil; checkError = .network; return
        }
        if status == 401 {
            githubAuth.signOut()
            applyAuthenticationToSparkle()
            available = nil; checkError = .authenticationRequired; return
        }
        guard status == 200,
              let releases = try? JSONDecoder().decode([ReleaseInfo].self, from: data) else {
            available = nil; checkError = status == 403 || status == 404 ? .repositoryAccess : .network; return
        }
        let stable = releases.first { !$0.draft && !$0.prerelease }
        let development = releases.first { $0.tag_name == "development" && !$0.draft }
        let skipped = UserDefaults.standard.string(forKey: "skippedUpdateVersion")
        if let stable, let candidate = Self.releaseCandidate(from: stable, channel: .stable),
           Self.isNewer(candidate.version, than: currentVersion), candidate.version != skipped {
            do {
                sparkleDelegate.feedURL = try await prepareAuthenticatedFeed(candidate)
            } catch {
                available = nil; checkError = .network; return
            }
            available = candidate
            applyAuthenticationToSparkle()
            if sparkleStarted, automaticDownloads { sparkleController.updater.checkForUpdatesInBackground() }
            return
        }
        if let development, currentCommit != "unknown",
           !development.target_commitish.hasPrefix(currentCommit),
           !currentCommit.hasPrefix(development.target_commitish),
           let candidate = Self.releaseCandidate(from: development, channel: .development),
           candidate.version != skipped {
            available = candidate; return
        }
        available = nil
    }

    func signInToGitHub() async {
        await githubAuth.signIn()
        applyAuthenticationToSparkle()
        guard githubAuth.isSignedIn else { return }
        lastChecked = nil
        await check(minInterval: 0)
    }

    func signOutFromGitHub() {
        githubAuth.signOut()
        sparkleDelegate.feedURL = nil
        available = nil
        checkError = .authenticationRequired
        applyAuthenticationToSparkle()
    }

    /// 이 버전은 다시 알리지 않음.
    func skipCurrent() {
        if let v = available?.version { UserDefaults.standard.set(v, forKey: "skippedUpdateVersion") }
        available = nil
    }

    /// 안정 릴리스는 Sparkle이 EdDSA 서명을 검증하고 앱 종료 뒤 원자적으로 교체한다.
    /// rolling development 빌드는 서명된 appcast 대상이 아니므로 기존처럼 릴리스 페이지를 연다.
    func applyUpdate() {
        guard let update = available, !isUpdating else { return }
        if update.channel == .stable, sparkleStarted, sparkleDelegate.feedURL != nil,
           githubAuth.isSignedIn {
            applyAuthenticationToSparkle()
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
        let rawDownloadAPI = release.assets.first { $0.name == releaseAssetName }?.url
        let downloadAPI = rawDownloadAPI.flatMap(Self.validAssetAPIURL)
        let rawFeed = release.assets.first { $0.name == "appcast.xml" }?.url
        let feed = rawFeed.flatMap(Self.validAssetAPIURL)
        let version: String
        switch channel {
        case .stable: version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        case .development:
            let sha = release.target_commitish.prefix(7)
            version = "main-\(sha)"
        }
        if channel == .stable, (feed == nil || download == nil || downloadAPI == nil) { return nil }
        return Available(version: version, url: html, downloadURL: download, feedURL: feed,
                         downloadAPIURL: downloadAPI, channel: channel)
    }

    nonisolated private static func validAssetAPIURL(_ value: String) -> String? {
        guard let url = URL(string: value), url.scheme == "https", url.host == "api.github.com",
              url.path.hasPrefix("/repos/2giduck/K-MON/releases/assets/") else { return nil }
        return value
    }

    /// GitHub의 private `browser_download_url`은 Bearer 토큰을 받지 않아 404를 반환한다.
    /// 인증 가능한 REST asset URL로 enclosure만 치환한 로컬 appcast를 Sparkle에 공급한다.
    /// feed 자체는 HTTPS+OAuth로 받고, 실제 실행 파일은 기존 `sparkle:edSignature`로 검증된다.
    private func prepareAuthenticatedFeed(_ candidate: Available) async throws -> URL {
        guard let feedString = candidate.feedURL, let feedURL = URL(string: feedString),
              let browserDownload = candidate.downloadURL,
              let apiDownload = candidate.downloadAPIURL,
              let headers = githubAuth.assetDownloadHeaders else { throw FeedError.invalid }
        var request = URLRequest(url: feedURL, timeoutInterval: 20)
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let original = String(data: data, encoding: .utf8),
              original.contains("<rss"), original.contains("sparkle:edSignature="),
              original.contains(browserDownload) else { throw FeedError.invalid }
        guard let rewritten = Self.rewriteAppcast(original, browserDownloadURL: browserDownload,
                                                  assetAPIURL: apiDownload) else { throw FeedError.invalid }
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Pokédoro/Updates", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let localFeed = base.appendingPathComponent("authenticated-appcast.xml")
        try Data(rewritten.utf8).write(to: localFeed, options: .atomic)
        return localFeed
    }

    private enum FeedError: Error { case invalid }

    nonisolated static func rewriteAppcast(_ original: String, browserDownloadURL: String,
                                           assetAPIURL: String) -> String? {
        guard original.contains("<rss"), original.contains("sparkle:edSignature="),
              original.contains(browserDownloadURL),
              validAssetAPIURL(assetAPIURL) != nil else { return nil }
        return original.replacingOccurrences(of: browserDownloadURL, with: assetAPIURL)
    }

    private func applyAuthenticationToSparkle() {
        sparkleController.updater.httpHeaders = githubAuth.assetDownloadHeaders
    }
}

/// 인증된 appcast에서 ZIP 주소만 REST asset URL로 바꾼 로컬 feed를 Sparkle에 제공한다.
@MainActor
final class AuthenticatedSparkleDelegate: NSObject, SPUUpdaterDelegate {
    var feedURL: URL?
    func feedURLString(for updater: SPUUpdater) -> String? { feedURL?.absoluteString }
}
