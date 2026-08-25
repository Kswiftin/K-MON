import XCTest
@testable import PokeTokenBar

/// CLI 를 **찾는** 일의 계약. 도구 샌드박스가 "무엇을 실행할 수 있나" 를 지킨다면 여기는
/// "실행할 것을 애초에 찾아내나" 를 지킨다 — 못 찾으면 대화 기능 전체가 조용히 없는 기능이 된다.
final class PokemonChatProviderPathTests: XCTestCase {

    private var root: URL!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("chat-cli-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    /// 실행 가능한 더미 파일 하나. 내용은 보지 않으므로 실행 권한만 정확하면 된다.
    @discardableResult
    private func makeExecutable(_ url: URL) throws -> URL {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data("#!/bin/sh\n".utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    // MARK: 탐색 범위

    /// 사용자가 CLI 를 어디에 설치하든 찾아낸다. 목록의 **어느 자리든** 단독으로 성립해야 한다 —
    /// 앞자리가 늘 채워진 케이스로만 시험하면 뒷자리는 한 번도 안 밟힌다.
    func testAnExecutableIsFoundInEverySearchedDirectory() throws {
        let candidates = PokemonChatProviderExecutableResolver.searchDirectories
        XCTAssertGreaterThan(candidates.count, 3, "탐색 자리가 늘지 않았다면 이 결함은 고쳐지지 않았다")

        for (index, _) in candidates.enumerated() {
            // 자리마다 독립된 트리를 쓴다. 한 트리를 재사용하면 앞 회차가 만든 파일이
            // 뒷 회차를 통과시켜 "그 자리를 실제로 뒤졌다" 는 증거가 되지 못한다.
            let tree = root.appendingPathComponent("dir-\(index)")
            let searchPaths = (0..<candidates.count).map {
                tree.appendingPathComponent("slot-\($0)").appendingPathComponent("claude").path
            }
            let planted = try makeExecutable(URL(fileURLWithPath: searchPaths[index]))

            let found = PokemonChatProviderExecutableResolver.executableURL(
                for: .claude, override: nil, searchPaths: searchPaths)

            XCTAssertEqual(found?.path, planted.path, "\(index)번째 탐색 자리를 뒤지지 않았다")
        }
    }

    /// 실제로 쓰이는 설치 자리가 목록에 있는가. 동작 테스트는 "주어진 목록을 뒤진다" 만 증명하므로
    /// **목록에서 빠진 자리**는 잡지 못한다 — 이 결함(`~/.local/bin` 누락)이 정확히 그 부류였다.
    func testTheSearchListCoversHowThesCLIsAreActuallyInstalled() {
        let directories = Set(PokemonChatProviderExecutableResolver.searchDirectories)
        for expected in ["~/.local/bin",        // npm/uv 사용자 설치 — 이 결함의 실제 재현 경로
                         "~/.claude/local",     // Claude Code 자체 설치 관리자
                         "/opt/homebrew/bin",   // Homebrew (Apple Silicon)
                         "/usr/local/bin",      // Homebrew (Intel) · 수동 설치
                         "~/.bun/bin", "~/.volta/bin", "~/.npm-global/bin", "~/.cargo/bin",
                         "~/.asdf/shims", "~/.mise/shims", "~/.deno/bin",
                         "/opt/local/bin", "/usr/bin"] {
            XCTAssertTrue(directories.contains(expected), "\(expected) 에 설치한 사용자는 CLI 를 못 쓴다")
        }
    }

    /// 목록은 한 벌이고 이름만 갈린다. 종류별로 경로 목록을 따로 들면 새 설치 자리가 한쪽에만
    /// 들어가 다른 CLI 는 영영 못 찾는다.
    func testBothCLIsSearchTheSameDirectoriesAndDifferOnlyInBinaryName() {
        let claude = PokemonChatProviderExecutableResolver.standardPaths(for: .claude)
        let codex = PokemonChatProviderExecutableResolver.standardPaths(for: .codex)

        XCTAssertEqual(claude.count, PokemonChatProviderExecutableResolver.searchDirectories.count)
        XCTAssertEqual(claude.map { URL(fileURLWithPath: $0).deletingLastPathComponent().path },
                       codex.map { URL(fileURLWithPath: $0).deletingLastPathComponent().path })
        XCTAssertTrue(claude.allSatisfy { $0.hasSuffix("/claude") })
        XCTAssertTrue(codex.allSatisfy { $0.hasSuffix("/codex") })
        // 격리를 보장할 수 없는 제공자는 찾을 대상 자체가 없다.
        XCTAssertTrue(PokemonChatProviderExecutableResolver.standardPaths(for: .opencode).isEmpty)
        XCTAssertTrue(PokemonChatProviderExecutableResolver.standardPaths(for: .custom).isEmpty)
    }

    /// `~` 는 문자 그대로의 디렉터리가 아니다. 확장하지 않으면 홈 아래 설치분을 전부 놓친다.
    func testHomeRelativeDirectoriesAreExpandedBeforeTheyAreSearched() {
        let paths = PokemonChatProviderExecutableResolver.standardPaths(for: .claude)
        XCTAssertFalse(paths.contains { $0.contains("~") }, "확장되지 않은 ~ 경로는 존재하지 않는 자리다")
        XCTAssertTrue(paths.contains { $0 == NSHomeDirectory() + "/.local/bin/claude" })
    }

    // MARK: 심볼릭 링크

    /// `~/.local/bin/claude` 는 버전 디렉터리를 가리키는 심볼릭 링크다. 링크를 풀어 대상 경로를
    /// 들고 있으면 **CLI 가 업데이트되는 순간 앱만 옛 버전을 가리키다 사라진다.**
    func testAResolvedCLIKeepsItsSymlinkPathSoACLIUpdateDoesNotBreakIt() throws {
        let versioned = try makeExecutable(root.appendingPathComponent("share/versions/2.1.243/claude"))
        let binDirectory = root.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: binDirectory, withIntermediateDirectories: true)
        let link = binDirectory.appendingPathComponent("claude")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: versioned)

        let found = PokemonChatProviderExecutableResolver.executableURL(
            for: .claude, override: nil, searchPaths: [link.path])

        XCTAssertEqual(found?.path, link.path, "링크를 풀면 다음 CLI 업데이트에 경로가 죽는다")
        XCTAssertNotEqual(found?.path, versioned.path)
    }

    // MARK: 직접 입력 · 우선순위

    /// 설정에서 지정한 경로가 표준 자리를 이긴다. 지정해 두고도 다른 게 실행되면 사용자는
    /// 자기가 무엇을 실행하는지 알 수 없다.
    func testAnExplicitOverrideWinsOverEveryStandardPath() throws {
        let standard = try makeExecutable(root.appendingPathComponent("standard/claude"))
        let chosen = try makeExecutable(root.appendingPathComponent("chosen/claude"))

        let found = PokemonChatProviderExecutableResolver.executableURL(
            for: .claude, override: chosen.path, searchPaths: [standard.path])

        XCTAssertEqual(found?.path, chosen.path)
    }

    /// 쓸 수 없는 override 는 앱을 막지 않는다. 오래된 지정 하나가 남았다고 표준 설치분을
    /// 못 쓰게 되면, 사용자는 왜 안 되는지 알 길이 없다.
    func testAnUnusableOverrideFallsBackToTheStandardPathsInsteadOfFailing() throws {
        let standard = try makeExecutable(root.appendingPathComponent("standard/claude"))

        let found = PokemonChatProviderExecutableResolver.executableURL(
            for: .claude, override: root.appendingPathComponent("gone/claude").path,
            searchPaths: [standard.path])

        XCTAssertEqual(found?.path, standard.path)
    }

    /// 설정이 저장 **전에** 쓰는 판정과 대화가 실행 **직전에** 쓰는 판정은 같은 한 벌이어야 한다.
    /// 두 벌이면 설정에서 초록으로 통과한 경로가 대화에서 조용히 실패한다.
    func testTypedPathsAreJudgedByTheSameRuleThatDecidesWhatRuns() throws {
        let executable = try makeExecutable(root.appendingPathComponent("bin/claude"))
        let plainFile = root.appendingPathComponent("bin/notes.txt")
        try Data("hello".utf8).write(to: plainFile)

        XCTAssertEqual(PokemonChatProviderExecutableResolver.validatedExecutable(executable.path)?.path,
                       executable.path)
        XCTAssertNil(PokemonChatProviderExecutableResolver.validatedExecutable(plainFile.path),
                     "실행 권한이 없는 파일")
        XCTAssertNil(PokemonChatProviderExecutableResolver.validatedExecutable(root.path),
                     "디렉터리")
        XCTAssertNil(PokemonChatProviderExecutableResolver.validatedExecutable(
            root.appendingPathComponent("nope").path), "없는 경로")
        XCTAssertNil(PokemonChatProviderExecutableResolver.validatedExecutable("   "), "빈 입력")
    }

    /// 격리가 검증되지 않은 제공자는 경로가 있어도 실행 대상이 되지 않는다. 탐색 범위를 넓히는
    /// 변경이 이 관문을 우회하면, 넓어진 건 편의가 아니라 구멍이다.
    func testWideningTheSearchNeverResolvesABlockedProvider() throws {
        let planted = try makeExecutable(root.appendingPathComponent("bin/opencode"))

        for kind in [PokemonChatProviderKind.opencode, .custom] {
            XCTAssertNil(PokemonChatProviderExecutableResolver.executableURL(
                for: kind, override: planted.path, searchPaths: [planted.path]),
                         "\(kind.rawValue) 는 실행 대상이 아니다")
        }
    }
}
