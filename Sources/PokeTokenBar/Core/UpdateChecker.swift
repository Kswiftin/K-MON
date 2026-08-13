import AppKit
import Observation

/// GitHub 릴리스 최신 버전을 확인해 새 버전이 있으면 팝오버에 알린다.
/// 실제 설치는 brew 사용자면 `brew upgrade`, 그 외엔 릴리스 페이지 열기(저위험·인프라 0).
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
    private let repo = "2giduck/K-MON"
    private let clock: () -> Date
    private var lastChecked: Date?

    init(currentVersion: String? = nil, currentCommit: String? = nil,
         clock: @escaping () -> Date = Date.init) {
        self.currentVersion = currentVersion
            ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0"
        self.clock = clock
        self.currentCommit = currentCommit
            ?? (Bundle.main.object(forInfoDictionaryKey: "KMONSourceCommit") as? String) ?? "unknown"
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
        if let stable, let candidate = Self.releaseCandidate(from: stable, channel: .stable),
           Self.isNewer(candidate.version, than: currentVersion), candidate.version != skipped {
            available = candidate; return
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

    /// 이 버전은 다시 알리지 않음.
    func skipCurrent() {
        if let v = available?.version { UserDefaults.standard.set(v, forKey: "skippedUpdateVersion") }
        available = nil
    }

    /// 서명되지 않은 바이너리를 앱이 스스로 덮어쓰지 않는다. 검증된 K-MON 릴리스 페이지를 열어
    /// 사용자가 ZIP과 변경 내역을 확인한 뒤 설치하게 한다.
    func applyUpdate() {
        guard let update = available, !isUpdating else { return }
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

    nonisolated static func releaseCandidate(from release: ReleaseInfo, channel: Available.Channel) -> Available? {
        let tag = release.tag_name
        let html = release.html_url
        guard
              let htmlURL = URL(string: html), htmlURL.scheme == "https", htmlURL.host == "github.com" else { return nil }
        let rawDownload = release.assets.first { $0.name == "PokeTokenBar.zip" }?.browser_download_url
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
