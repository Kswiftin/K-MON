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
            html_url: "https://github.com/Kswiftin/K-MON/releases/tag/v2.6.0",
            target_commitish: "abcdef123456", draft: false, prerelease: false,
            assets: [
                .init(name: UpdateChecker.releaseAssetName,
                    url: "https://api.github.com/repos/Kswiftin/K-MON/releases/assets/67890",
                    browser_download_url: "https://github.com/Kswiftin/K-MON/releases/download/v2.6.0/\(UpdateChecker.releaseAssetName)"),
                .init(name: "appcast.xml",
                    url: "https://api.github.com/repos/Kswiftin/K-MON/releases/assets/12345",
                    browser_download_url: "https://github.com/Kswiftin/K-MON/releases/download/v2.6.0/appcast.xml"),
            ])
        let candidate = UpdateChecker.releaseCandidate(from: release)
        XCTAssertEqual(candidate?.version, "2.6.0")
        XCTAssertNotNil(candidate?.downloadURL)
        XCTAssertEqual(candidate?.feedURL, "https://api.github.com/repos/Kswiftin/K-MON/releases/assets/12345")
        XCTAssertEqual(candidate?.downloadAPIURL, "https://api.github.com/repos/Kswiftin/K-MON/releases/assets/67890")
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

    func testDevelopmentReleaseIsNeverAnUpdateCandidate() {
        let release = UpdateChecker.ReleaseInfo(tag_name: "development",
            html_url: "https://github.com/Kswiftin/K-MON/releases/tag/development",
            target_commitish: "1234567890abcdef", draft: false, prerelease: true,
            assets: validAssets(version: "development"))
        XCTAssertNil(UpdateChecker.releaseCandidate(from: release))
    }

    func testNewestStableCandidateIgnoresOrderPrereleasesAndMalformedTags() {
        let releases = [
            release("v2.7.2"),
            release("development", prerelease: true),
            release("latest"),
            release("v2.8.0", draft: true),
            release("v2.7.10"),
            release("v2.7.3"),
        ]
        XCTAssertEqual(UpdateChecker.newestStableCandidate(from: releases)?.version, "2.7.10")
    }

    func testStableCandidateRequiresAuthenticatedAppcastAPIURL() {
        let release = UpdateChecker.ReleaseInfo(tag_name: "v2.7.1",
            html_url: "https://github.com/Kswiftin/K-MON/releases/tag/v2.7.1",
            target_commitish: "abcdef", draft: false, prerelease: false,
            assets: [.init(name: "appcast.xml", url: "https://evil.example/appcast.xml",
                           browser_download_url: "https://github.com/appcast.xml")])
        XCTAssertNil(UpdateChecker.releaseCandidate(from: release))
    }

    func testOAuthFormBodyIsStableAndPercentEncoded() {
        let body = GitHubOAuth.formBody(["scope": "repo user", "client_id": "abc"])
        XCTAssertEqual(String(decoding: body, as: UTF8.self), "client_id=abc&scope=repo%20user")
    }

    func testGitHubAppDeviceFlowDoesNotRequestBroadRepoScope() {
        let authorization = GitHubOAuth.deviceAuthorizationBody(clientID: "client")
        XCTAssertEqual(String(decoding: authorization, as: UTF8.self), "client_id=client")

        let token = GitHubOAuth.tokenBody(clientID: "client", deviceCode: "device",
                                          repositoryID: "1332674561")
        XCTAssertEqual(String(decoding: token, as: UTF8.self),
                       "client_id=client&device_code=device&grant_type=urn:ietf:params:oauth:grant-type:device_code&repository_id=1332674561")
    }

    func testGitHubAppRefreshUsesNoClientSecretAndBuildsExpirations() throws {
        let body = GitHubOAuth.refreshBody(clientID: "client", refreshToken: "refresh")
        XCTAssertEqual(String(decoding: body, as: UTF8.self),
                       "client_id=client&grant_type=refresh_token&refresh_token=refresh")
        XCTAssertFalse(String(decoding: body, as: UTF8.self).contains("client_secret"))

        let now = Date(timeIntervalSince1970: 1_000)
        let response = GitHubOAuth.AccessTokenResponse(
            access_token: "access", expires_in: 28_800,
            refresh_token: "refresh", refresh_token_expires_in: 15_897_600,
            error: nil, error_description: nil, interval: nil)
        let credentials = try GitHubOAuth.credentials(from: response, now: now)
        XCTAssertEqual(credentials.accessToken, "access")
        XCTAssertEqual(credentials.refreshToken, "refresh")
        XCTAssertEqual(credentials.expiresAt, now.addingTimeInterval(28_800))
        XCTAssertEqual(credentials.refreshTokenExpiresAt, now.addingTimeInterval(15_897_600))
    }

    @MainActor
    func testExpiredAccessTokenRefreshesAndPersistsRotatedCredentials() async {
        let now = Date(timeIntervalSince1970: 10_000)
        let store = OAuthStoreStub(credentials: expiredCredentials(now: now))
        let json = #"{"access_token":"new-access","expires_in":28800,"refresh_token":"new-refresh","refresh_token_expires_in":15897600}"#
        let oauth = GitHubOAuth(clientID: "client", session: oauthSession(status: 200, json: json),
                                keychain: store)

        let result = await oauth.refreshAccessTokenIfNeeded(now: now)
        XCTAssertEqual(result, .valid)
        XCTAssertEqual(store.saved?.accessToken, "new-access")
        XCTAssertEqual(store.saved?.refreshToken, "new-refresh")
        XCTAssertTrue(oauth.isSignedIn)
    }

    @MainActor
    func testRefreshKeychainFailureIsNotReportedAsNetworkFailure() async {
        let now = Date(timeIntervalSince1970: 10_000)
        let store = OAuthStoreStub(credentials: expiredCredentials(now: now), failsToSave: true)
        let json = #"{"access_token":"new-access","expires_in":28800,"refresh_token":"new-refresh","refresh_token_expires_in":15897600}"#
        let oauth = GitHubOAuth(clientID: "client", session: oauthSession(status: 200, json: json),
                                keychain: store)

        let result = await oauth.refreshAccessTokenIfNeeded(now: now)
        XCTAssertEqual(result, .keychain)
        XCTAssertTrue(oauth.isSignedIn)
        XCTAssertFalse(store.deleted)
    }

    @MainActor
    func testBadRefreshTokenSignsOutAndRequiresAuthentication() async {
        let now = Date(timeIntervalSince1970: 10_000)
        let store = OAuthStoreStub(credentials: expiredCredentials(now: now))
        let json = #"{"error":"bad_refresh_token","error_description":"expired"}"#
        let oauth = GitHubOAuth(clientID: "client", session: oauthSession(status: 200, json: json),
                                keychain: store)

        let result = await oauth.refreshAccessTokenIfNeeded(now: now)
        XCTAssertEqual(result, .authenticationRequired)
        XCTAssertFalse(oauth.isSignedIn)
        XCTAssertTrue(store.deleted)
    }

    func testAuthenticatedAppcastRewritesOnlyToKMONAssetAPI() {
        let browser = "https://github.com/Kswiftin/K-MON/releases/download/v2.7.1/Pokedoro.zip"
        let api = "https://api.github.com/repos/Kswiftin/K-MON/releases/assets/67890"
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

    private func release(_ tag: String, draft: Bool = false,
                         prerelease: Bool = false) -> UpdateChecker.ReleaseInfo {
        UpdateChecker.ReleaseInfo(
            tag_name: tag,
            html_url: "https://github.com/Kswiftin/K-MON/releases/tag/\(tag)",
            target_commitish: "abcdef", draft: draft, prerelease: prerelease,
            assets: validAssets(version: tag))
    }

    private func validAssets(version: String) -> [UpdateChecker.ReleaseInfo.Asset] {
        [
            .init(name: UpdateChecker.releaseAssetName,
                  url: "https://api.github.com/repos/Kswiftin/K-MON/releases/assets/100",
                  browser_download_url: "https://github.com/Kswiftin/K-MON/releases/download/\(version)/Pokedoro.zip"),
            .init(name: "appcast.xml",
                  url: "https://api.github.com/repos/Kswiftin/K-MON/releases/assets/101",
                  browser_download_url: "https://github.com/Kswiftin/K-MON/releases/download/\(version)/appcast.xml"),
        ]
    }

    private func expiredCredentials(now: Date) -> GitHubOAuth.Credentials {
        GitHubOAuth.Credentials(
            accessToken: "old-access", refreshToken: "old-refresh",
            expiresAt: now.addingTimeInterval(-1),
            refreshTokenExpiresAt: now.addingTimeInterval(3_600))
    }

    private func oauthSession(status: Int, json: String) -> URLSession {
        OAuthURLProtocolStub.response = (status, Data(json.utf8))
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OAuthURLProtocolStub.self]
        return URLSession(configuration: configuration)
    }
}

private final class OAuthStoreStub: OAuthCredentialStore, @unchecked Sendable {
    private let initial: GitHubOAuth.Credentials?
    private let failsToSave: Bool
    private(set) var saved: GitHubOAuth.Credentials?
    private(set) var deleted = false

    init(credentials: GitHubOAuth.Credentials?, failsToSave: Bool = false) {
        initial = credentials
        self.failsToSave = failsToSave
    }

    func load() -> GitHubOAuth.Credentials? { initial }
    func save(_ credentials: GitHubOAuth.Credentials) throws {
        if failsToSave { throw NSError(domain: "OAuthStoreStub", code: 1) }
        saved = credentials
    }
    func delete() { deleted = true }
}

private final class OAuthURLProtocolStub: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var response = (200, Data())

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let (status, data) = Self.response
        let response = HTTPURLResponse(url: request.url!, statusCode: status,
                                       httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
