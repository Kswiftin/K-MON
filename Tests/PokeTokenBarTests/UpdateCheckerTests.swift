import XCTest
@testable import PokeTokenBar

final class UpdateCheckerTests: XCTestCase {
    func testNewerPatch() {
        XCTAssertTrue(UpdateChecker.isNewer("2.0.2", than: "2.0.1"))
    }
    func testSameIsNotNewer() {
        XCTAssertFalse(UpdateChecker.isNewer("2.0.1", than: "2.0.1"))
    }
    func testOlderIsNotNewer() {
        XCTAssertFalse(UpdateChecker.isNewer("2.0.0", than: "2.0.1"))
        XCTAssertFalse(UpdateChecker.isNewer("2.0.9", than: "2.1.0"))
    }
    func testNumericNotLexical() {
        // "2.0.10" 은 "2.0.9" 보다 높다 (문자열 비교면 반대로 틀림)
        XCTAssertTrue(UpdateChecker.isNewer("2.0.10", than: "2.0.9"))
    }
    func testMinorAndMajor() {
        XCTAssertTrue(UpdateChecker.isNewer("2.1.0", than: "2.0.9"))
        XCTAssertTrue(UpdateChecker.isNewer("3.0.0", than: "2.9.9"))
    }
    func testDifferentComponentCounts() {
        XCTAssertTrue(UpdateChecker.isNewer("2.0.1", than: "2.0"))   // 2.0.1 > 2.0.0
        XCTAssertFalse(UpdateChecker.isNewer("2.0", than: "2.0.0"))  // 동일
    }

    func testKMONStableReleaseCandidate() {
        let release = UpdateChecker.ReleaseInfo(tag_name: "v2.6.0",
            html_url: "https://github.com/2giduck/K-MON/releases/tag/v2.6.0",
            target_commitish: "abcdef123456", draft: false, prerelease: false,
            assets: [
                .init(name: UpdateChecker.releaseAssetName,
                    url: "https://api.github.com/repos/2giduck/K-MON/releases/assets/67890",
                    browser_download_url: "https://github.com/2giduck/K-MON/releases/download/v2.6.0/\(UpdateChecker.releaseAssetName)"),
                .init(name: "appcast.xml",
                    url: "https://api.github.com/repos/2giduck/K-MON/releases/assets/12345",
                    browser_download_url: "https://github.com/2giduck/K-MON/releases/download/v2.6.0/appcast.xml"),
            ])
        let candidate = UpdateChecker.releaseCandidate(from: release, channel: .stable)
        XCTAssertEqual(candidate?.version, "2.6.0")
        XCTAssertEqual(candidate?.channel, .stable)
        XCTAssertNotNil(candidate?.downloadURL)
        XCTAssertEqual(candidate?.feedURL, "https://api.github.com/repos/2giduck/K-MON/releases/assets/12345")
        XCTAssertEqual(candidate?.downloadAPIURL, "https://api.github.com/repos/2giduck/K-MON/releases/assets/67890")
    }

    /// 앱이 찾는 에셋 이름과 릴리스가 실제로 올리는 이름이 어긋나면 다운로드 URL 이 늘 nil 이라
    /// 앱 내 업데이트가 조용히 죽는다(에러도 안 난다 — 릴리스 페이지만 열린다).
    /// 예전엔 앱이 `PokeTokenBar.zip` 을 찾는데 CI 는 `Pokédoro.zip` 을 올렸고, GitHub 이 그걸
    /// `Pokedoro.zip` 으로 정규화까지 해서 세 이름이 전부 달랐다. 테스트가 가짜 릴리스를 *자기가 지은*
    /// 이름으로 만들어 통과시켰던 게 이걸 못 잡은 이유다 — 이제 실제 Asset을 올리는 두 Workflow와 대조한다.
    func testReleaseAssetNameMatchesWhatTheReleaseScriptsUpload() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        for path in [".github/workflows/ci.yml", ".github/workflows/release.yml"] {
            let text = try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
            XCTAssertTrue(text.contains(UpdateChecker.releaseAssetName),
                          "\(path) 가 올리는 zip 이름이 UpdateChecker.releaseAssetName 과 다르다")
        }
        XCTAssertEqual(UpdateChecker.releaseAssetName,
                       UpdateChecker.releaseAssetName.folding(options: .diacriticInsensitive, locale: nil),
                       "GitHub 이 비-ASCII 에셋 이름을 정규화하므로 이름에 발음기호를 쓰면 안 된다")
    }

    func testDevelopmentCandidateUsesCommitPrefixAndRejectsForeignURL() {
        let release = UpdateChecker.ReleaseInfo(tag_name: "development",
            html_url: "https://github.com/2giduck/K-MON/releases/tag/development",
            target_commitish: "1234567890abcdef", draft: false, prerelease: true,
            assets: [.init(name: UpdateChecker.releaseAssetName, browser_download_url: "https://evil.example/app.zip")])
        let candidate = UpdateChecker.releaseCandidate(from: release, channel: .development)
        XCTAssertEqual(candidate?.version, "main-1234567")
        XCTAssertEqual(candidate?.channel, .development)
        XCTAssertNil(candidate?.downloadURL)
    }

    func testStableCandidateRequiresAuthenticatedAppcastAPIURL() {
        let release = UpdateChecker.ReleaseInfo(tag_name: "v2.7.1",
            html_url: "https://github.com/2giduck/K-MON/releases/tag/v2.7.1",
            target_commitish: "abcdef", draft: false, prerelease: false,
            assets: [.init(name: "appcast.xml", url: "https://evil.example/appcast.xml",
                           browser_download_url: "https://github.com/appcast.xml")])
        XCTAssertNil(UpdateChecker.releaseCandidate(from: release, channel: .stable))
    }

    func testOAuthFormBodyIsStableAndPercentEncoded() {
        let body = GitHubOAuth.formBody(["scope": "repo user", "client_id": "abc"])
        XCTAssertEqual(String(decoding: body, as: UTF8.self), "client_id=abc&scope=repo%20user")
    }

    func testAuthenticatedAppcastRewritesOnlyToKMONAssetAPI() {
        let browser = "https://github.com/2giduck/K-MON/releases/download/v2.7.1/Pokedoro.zip"
        let api = "https://api.github.com/repos/2giduck/K-MON/releases/assets/67890"
        let original = #"<rss><enclosure url="\#(browser)" sparkle:edSignature="signed" /></rss>"#
        let rewritten = UpdateChecker.rewriteAppcast(original, browserDownloadURL: browser, assetAPIURL: api)
        XCTAssertFalse(rewritten?.contains(browser) ?? true)
        XCTAssertTrue(rewritten?.contains(api) ?? false)
        XCTAssertNil(UpdateChecker.rewriteAppcast(original, browserDownloadURL: browser,
                                                   assetAPIURL: "https://evil.example/update.zip"))
    }

    @MainActor
    func testLocalAppcastServerOnlyServesExpectedPath() async throws {
        let server = LocalAppcastServer()
        let expected = Data("<rss>test</rss>".utf8)
        let url = try await server.serve(expected)
        XCTAssertEqual(url.scheme, "http")
        XCTAssertEqual(url.host, "127.0.0.1")
        let (data, response) = try await URLSession.shared.data(from: url)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual(data, expected)
        let queryURL = URL(string: "\(url.absoluteString)?channel=stable")!
        let (queryData, queryResponse) = try await URLSession.shared.data(from: queryURL)
        XCTAssertEqual((queryResponse as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual(queryData, expected)
        let missing = URL(string: "http://127.0.0.1:\(url.port!)/missing")!
        let (_, missingResponse) = try await URLSession.shared.data(from: missing)
        XCTAssertEqual((missingResponse as? HTTPURLResponse)?.statusCode, 404)
    }
}
