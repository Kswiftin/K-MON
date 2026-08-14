import AppKit
import Observation
import Security

/// Organization 소유 GitHub App의 Device Flow 인증을 담당한다.
/// Client ID는 공개 식별자라 앱 번들에 포함하고, 발급된 토큰만 macOS Keychain에 저장한다.
@MainActor
@Observable
final class GitHubOAuth {
    enum State: Equatable {
        case signedOut
        case requestingCode
        case authorizing(code: String)
        case signedIn(login: String?)
        case failed(String)
    }

    struct DeviceCodeResponse: Decodable, Equatable {
        let device_code: String
        let user_code: String
        let verification_uri: String
        let expires_in: Int
        let interval: Int
    }

    struct AccessTokenResponse: Decodable, Equatable {
        let access_token: String?
        let expires_in: Int?
        let refresh_token: String?
        let refresh_token_expires_in: Int?
        let error: String?
        let error_description: String?
        let interval: Int?
    }

    struct Credentials: Codable, Equatable, Sendable {
        let accessToken: String
        let refreshToken: String?
        let expiresAt: Date?
        let refreshTokenExpiresAt: Date?
    }

    private struct UserResponse: Decodable { let login: String }

    private(set) var state: State
    @ObservationIgnored private var credentials: Credentials?

    private let clientID: String
    private let repositoryID: String
    private let session: URLSession
    private let keychain: OAuthTokenKeychain

    var isSignedIn: Bool { credentials != nil }
    var isAuthorizing: Bool {
        switch state {
        case .requestingCode, .authorizing: true
        default: false
        }
    }
    var login: String? {
        if case let .signedIn(login) = state { login } else { nil }
    }
    var deviceCode: String? {
        if case let .authorizing(code) = state { code } else { nil }
    }
    var errorMessage: String? {
        if case let .failed(message) = state { message } else { nil }
    }
    var authorizationHeaders: [String: String]? {
        guard let token = credentials?.accessToken else { return nil }
        return [
            "Authorization": "Bearer \(token)",
            "X-GitHub-Api-Version": "2022-11-28",
        ]
    }
    var assetDownloadHeaders: [String: String]? {
        guard var headers = authorizationHeaders else { return nil }
        headers["Accept"] = "application/octet-stream"
        return headers
    }

    init(clientID: String? = nil,
         repositoryID: String = "1332674561",
         session: URLSession = .shared,
         keychain: OAuthTokenKeychain = OAuthTokenKeychain()) {
        self.clientID = clientID
            ?? (Bundle.main.object(forInfoDictionaryKey: "KMONGitHubOAuthClientID") as? String)
            ?? ""
        self.repositoryID = repositoryID
        self.session = session
        self.keychain = keychain
        credentials = keychain.load()
        state = credentials == nil ? .signedOut : .signedIn(login: nil)
    }

    func signIn() async {
        guard !clientID.isEmpty else {
            state = .failed("GitHub OAuth Client ID가 앱에 설정되지 않았어요.")
            return
        }
        state = .requestingCode
        do {
            let device = try await requestDeviceCode()
            state = .authorizing(code: device.user_code)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(device.user_code, forType: .string)
            if let url = URL(string: device.verification_uri), url.scheme == "https", url.host == "github.com" {
                NSWorkspace.shared.open(url)
            }
            let newCredentials = try await pollForToken(device)
            try keychain.save(newCredentials)
            credentials = newCredentials
            state = .signedIn(login: nil)
            await refreshUser()
        } catch is CancellationError {
            state = .signedOut
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func refreshUser() async {
        guard await refreshAccessTokenIfNeeded(), let token = credentials?.accessToken,
              let url = URL(string: "https://api.github.com/user") else { return }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { return }
            if http.statusCode == 401 {
                signOut()
                return
            }
            guard http.statusCode == 200,
                  let user = try? JSONDecoder().decode(UserResponse.self, from: data) else { return }
            state = .signedIn(login: user.login)
        } catch {
            // 이미 저장된 토큰은 일시적인 네트워크 오류 때문에 지우지 않는다.
        }
    }

    func signOut() {
        keychain.delete()
        credentials = nil
        state = .signedOut
    }

    private func requestDeviceCode() async throws -> DeviceCodeResponse {
        var request = URLRequest(url: URL(string: "https://github.com/login/device/code")!, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.deviceAuthorizationBody(clientID: clientID)
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw OAuthError.requestFailed }
        return try JSONDecoder().decode(DeviceCodeResponse.self, from: data)
    }

    private func pollForToken(_ device: DeviceCodeResponse) async throws -> Credentials {
        let deadline = Date().addingTimeInterval(TimeInterval(device.expires_in))
        var interval = max(device.interval, 5)
        while Date() < deadline {
            try await Task.sleep(for: .seconds(interval))
            var request = URLRequest(url: URL(string: "https://github.com/login/oauth/access_token")!, timeoutInterval: 15)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = Self.tokenBody(clientID: clientID, deviceCode: device.device_code,
                                              repositoryID: repositoryID)
            let (data, response) = try await session.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw OAuthError.requestFailed }
            let result = try JSONDecoder().decode(AccessTokenResponse.self, from: data)
            if result.access_token != nil { return try Self.credentials(from: result) }
            switch result.error {
            case "authorization_pending": continue
            case "slow_down": interval = max(interval + 5, result.interval ?? 0)
            case "access_denied": throw OAuthError.accessDenied
            case "expired_token": throw OAuthError.codeExpired
            default: throw OAuthError.server(result.error_description ?? result.error ?? "Unknown OAuth error")
            }
        }
        throw OAuthError.codeExpired
    }

    /// 만료 5분 전부터 갱신한다. Device Flow로 발급된 Refresh Token은 Client Secret 없이 교환된다.
    func refreshAccessTokenIfNeeded(now: Date = Date()) async -> Bool {
        guard let current = credentials else { return false }
        guard let expiresAt = current.expiresAt,
              expiresAt <= now.addingTimeInterval(300) else { return true }
        guard let refreshToken = current.refreshToken,
              current.refreshTokenExpiresAt.map({ $0 > now }) != false else {
            signOut()
            return false
        }

        do {
            var request = URLRequest(url: URL(string: "https://github.com/login/oauth/access_token")!,
                                     timeoutInterval: 15)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = Self.refreshBody(clientID: clientID, refreshToken: refreshToken)
            let (data, response) = try await session.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return false }
            let result = try JSONDecoder().decode(AccessTokenResponse.self, from: data)
            guard result.error == nil else {
                if result.error == "bad_refresh_token" { signOut() }
                return false
            }
            let refreshed = try Self.credentials(from: result, now: now)
            try keychain.save(refreshed)
            credentials = refreshed
            return true
        } catch {
            // 일시적 네트워크·Keychain 오류라면 기존 Refresh Token을 지우지 않고 다음 확인 때 재시도한다.
            return false
        }
    }

    nonisolated static func formBody(_ values: [String: String]) -> Data {
        var components = URLComponents()
        components.queryItems = values.sorted { $0.key < $1.key }.map(URLQueryItem.init)
        return Data((components.percentEncodedQuery ?? "").utf8)
    }

    nonisolated static func deviceAuthorizationBody(clientID: String) -> Data {
        formBody(["client_id": clientID])
    }

    nonisolated static func tokenBody(clientID: String, deviceCode: String,
                                      repositoryID: String) -> Data {
        formBody([
            "client_id": clientID,
            "device_code": deviceCode,
            "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
            "repository_id": repositoryID,
        ])
    }

    nonisolated static func refreshBody(clientID: String, refreshToken: String) -> Data {
        formBody([
            "client_id": clientID,
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
        ])
    }

    nonisolated static func credentials(from response: AccessTokenResponse,
                                        now: Date = Date()) throws -> Credentials {
        guard let accessToken = response.access_token else {
            throw OAuthError.server(response.error_description ?? response.error ?? "Missing access token")
        }
        return Credentials(
            accessToken: accessToken,
            refreshToken: response.refresh_token,
            expiresAt: response.expires_in.map { now.addingTimeInterval(TimeInterval($0)) },
            refreshTokenExpiresAt: response.refresh_token_expires_in.map {
                now.addingTimeInterval(TimeInterval($0))
            })
    }

    enum OAuthError: LocalizedError {
        case requestFailed, accessDenied, codeExpired, server(String)
        var errorDescription: String? {
            switch self {
            case .requestFailed: "GitHub 로그인 요청에 실패했어요. 잠시 후 다시 시도해 주세요."
            case .accessDenied: "GitHub 로그인이 취소되었어요."
            case .codeExpired: "로그인 코드가 만료되었어요. 다시 시도해 주세요."
            case let .server(message): message
            }
        }
    }
}

/// OAuth 토큰 전용 Generic Password 항목. 저장 실패는 로그인 성공으로 처리하지 않는다.
struct OAuthTokenKeychain: Sendable {
    private let service = "io.github.chattymin.poketokenbar.github-oauth"
    private let account = "Kswiftin/K-MON"

    func load() -> GitHubOAuth.Credentials? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        if let credentials = try? JSONDecoder().decode(GitHubOAuth.Credentials.self, from: data) {
            return credentials
        }
        // 초기 OAuth 구현이 저장한 평문 토큰도 한 번은 읽어 새 형식으로 마이그레이션한다.
        guard let token = String(data: data, encoding: .utf8), !token.isEmpty else { return nil }
        return GitHubOAuth.Credentials(accessToken: token, refreshToken: nil,
                                       expiresAt: nil, refreshTokenExpiresAt: nil)
    }

    func save(_ credentials: GitHubOAuth.Credentials) throws {
        let data = try JSONEncoder().encode(credentials)
        let status: OSStatus
        if load() == nil {
            var query = baseQuery
            query[kSecValueData as String] = data
            status = SecItemAdd(query as CFDictionary, nil)
        } else {
            status = SecItemUpdate(baseQuery as CFDictionary,
                                   [kSecValueData as String: data] as CFDictionary)
        }
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }

    func delete() {
        SecItemDelete(baseQuery as CFDictionary)
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    struct KeychainError: LocalizedError {
        let status: OSStatus
        var errorDescription: String? {
            SecCopyErrorMessageString(status, nil) as String? ?? "Keychain 오류 (\(status))"
        }
    }
}
