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

    // MARK: 자동 선택 — 고르지 않아도 보낼 수 있다

    /// 설치 여부를 주입한다. 실제 홈 디렉터리에 무엇이 깔려 있느냐로 갈리면, 이 판정은 CI 와
    /// 개발자 기계에서 서로 다른 것을 시험하게 된다.
    private func installed(_ kinds: PokemonChatProviderKind...) -> (PokemonChatProviderKind) -> Bool {
        { kinds.contains($0) }
    }

    /// 사용자가 고른 값이 여전히 쓸 수 있으면 그게 이긴다. 자동 선택이 사용자의 선택을 덮으면,
    /// 어느 CLI 로 나가는지가 사용자 손을 떠난다.
    func testAStoredChoiceThatStillWorksBeatsAutoSelection() {
        XCTAssertEqual(PokemonChatProviderSelection.effectiveKind(
            stored: "claude", isInstalled: installed(.codex, .claude)), .claude)
        XCTAssertEqual(PokemonChatProviderSelection.effectiveKind(
            stored: "codex", isInstalled: installed(.codex, .claude)), .codex)
    }

    /// 이 마일스톤의 본체 — 아무것도 고르지 않은 첫 방문에서 전송이 가능해야 한다.
    ///
    /// 우선순위를 `verifiedKinds` 순서로 **못 박는다**. 순서가 조용히 뒤집히면 사용자는 어제와
    /// 다른 CLI 로 외부 전송을 하게 되므로, 그 변경은 테스트를 빨갛게 만들어 눈에 띄어야 한다.
    func testAnEmptySelectionAutoPicksTheFirstInstalledVerifiedCLI() {
        XCTAssertEqual(PokemonChatProviderSafety.verifiedKinds, [.codex, .claude],
                       "우선순위가 바뀌면 아래 기대값도 함께 바뀌어야 한다 — 조용히 지나가면 안 된다")

        XCTAssertEqual(PokemonChatProviderSelection.effectiveKind(
            stored: "", isInstalled: installed(.codex, .claude)), .codex, "둘 다 있으면 우선순위 첫 번째")
        XCTAssertEqual(PokemonChatProviderSelection.effectiveKind(
            stored: "", isInstalled: installed(.claude)), .claude, "하나뿐이면 그것")
        XCTAssertEqual(PokemonChatProviderSelection.effectiveKind(
            stored: "", isInstalled: installed(.codex)), .codex)
    }

    /// 저장된 선택이 못 쓰게 되는 길은 둘이다 — CLI 를 지웠거나, 그 종류가 차단됐거나.
    /// 어느 쪽이든 **막다른 길이 아니라 폴백**이다. 실행 파일 해석이 이미 같은 방향을 택했다
    /// (`testAnUnusableOverrideFallsBackToTheStandardPathsInsteadOfFailing`).
    func testAStoredChoiceThatNoLongerWorksFallsBackInsteadOfBlockingChat() {
        XCTAssertEqual(PokemonChatProviderSelection.effectiveKind(
            stored: "codex", isInstalled: installed(.claude)), .claude, "지운 CLI 하나로 대화가 멎으면 안 된다")
        XCTAssertEqual(PokemonChatProviderSelection.effectiveKind(
            stored: "없는값", isInstalled: installed(.claude)), .claude, "해석 불가한 저장값")
    }

    /// **자동 선택은 새로 생긴 형제 경로다.** 지금까지 provider 로 가는 길은 "사용자가 Picker 에서
    /// 고른다" 하나뿐이었고 그 길에만 격리 관문이 있었다. 설치 여부만 보고 판정하면
    /// (`PokemonChatProviderKind(rawValue:)` + 설치 확인) 차단된 CLI 가 이 길로 샌다.
    func testAStoredBlockedProviderNeverSurvivesAutoSelection() {
        for blocked in [PokemonChatProviderKind.opencode, .custom] {
            let chosen = PokemonChatProviderSelection.effectiveKind(
                stored: blocked.rawValue,
                // 전부 "설치됨" — 설치 여부로만 거르는 구현이면 여기서 차단 CLI 가 통과한다.
                isInstalled: { _ in true })

            XCTAssertNotEqual(chosen, blocked, "\(blocked.rawValue) 는 격리를 보장할 수 없다")
            XCTAssertEqual(chosen, .codex, "차단된 저장값은 무시하고 검증된 우선순위로 폴백한다")
        }
    }

    /// 후보 집합이 `verifiedKinds` 밖으로 새지 않는가. 위 테스트는 *저장값*이 차단된 경우만 보므로,
    /// 자동 경로가 `allCases` 를 직접 도는 구현은 저장값이 빈 경우에 그대로 통과한다.
    func testAutoSelectionOnlyEverYieldsAVerifiedProvider() {
        let stored = ["", "claude", "codex", "opencode", "custom", "없는값", " "]
        for value in stored {
            let chosen = PokemonChatProviderSelection.effectiveKind(stored: value, isInstalled: { _ in true })
            guard let chosen else { continue }
            XCTAssertTrue(PokemonChatProviderSafety.availability(for: chosen).isVerified,
                          "저장값 '\(value)' 이 검증 안 된 \(chosen.rawValue) 로 이어졌다")
        }
    }

    /// 검증 CLI 가 하나도 안 잡히면 고를 것이 없다. 이때 화면은 **말없이 비활성인 전송 버튼**을
    /// 남기면 안 되므로, 그 사실을 판정으로 드러낸다(문구는 아래 테스트).
    func testNothingIsSelectedWhenNoVerifiedCLIIsInstalled() {
        XCTAssertNil(PokemonChatProviderSelection.effectiveKind(stored: "", isInstalled: { _ in false }))
        XCTAssertNil(PokemonChatProviderSelection.effectiveKind(stored: "claude", isInstalled: { _ in false }))
    }

    /// **트리거 재현.** 위의 두 테스트는 후보를 `allCases` 에서 뽑는 구현을 못 잡는다 — 검증 종류가
    /// 목록 앞자리(`codex, claude, opencode, custom`)에 있어, 검증 CLI 가 하나라도 설치된 상태에서는
    /// `allCases.first` 와 `verifiedKinds.first` 가 **같은 답**을 내기 때문이다. 결함을 주입해 보고
    /// 알았다: 관문이 뚫린 채로 그 테스트들이 전부 초록이었다.
    ///
    /// 새는 조건은 정확히 하나 — 검증 CLI 는 없고 **차단된 종류만** 잡히는 상태다.
    func testABlockedCLIIsNeverPickedEvenWhenItIsTheOnlyOneInstalled() {
        for blocked in [PokemonChatProviderKind.opencode, .custom] {
            XCTAssertNil(PokemonChatProviderSelection.effectiveKind(
                stored: "", isInstalled: installed(blocked)),
                         "검증 CLI 가 없으면 \(blocked.rawValue) 가 있어도 보낼 곳은 없다")
            XCTAssertNil(PokemonChatProviderSelection.effectiveKind(
                stored: blocked.rawValue, isInstalled: installed(blocked)),
                         "고른 것이 그 차단 CLI 여도 마찬가지다")
        }
    }

    /// 안내 문구는 Core 에 둔다 — 차단 사유(`PokemonChatBlockReason`)와 같은 이유로, 뷰가 문구를
    /// 들면 커버리지 게이트 밖에 남고 세 언어 중 하나가 조용히 빠진다.
    func testTheMissingCLIGuidanceExistsInAllThreeLanguages() {
        let messages = [AppLanguage.ko, .en, .ja].map(PokemonChatProviderSelection.noProviderMessage)
        XCTAssertEqual(Set(messages).count, 3, "세 언어가 서로 다른 문장이어야 한다")
        XCTAssertFalse(messages.contains { $0.trimmingCharacters(in: .whitespaces).isEmpty })
    }

    // MARK: 동의 — 전송 버튼이 곧 동의다

    /// 자동 선택이 "어느 CLI 인가" 를 사용자 손에서 가져갔으므로, **그 답을 전송하는 자리에서
    /// 돌려줘야** 누르는 행위가 동의가 된다. 이름 없는 "외부 전송" 은 어디로 가는지 안 알려준다.
    func testTheExternalSendLabelNamesTheCLIThatWillReceiveTheMessage() {
        for kind in PokemonChatProviderSafety.verifiedKinds {
            for language in [AppLanguage.ko, .en, .ja] {
                let label = PokemonChatProviderSelection.externalSendLabel(kind: kind, language: language)
                XCTAssertTrue(label.contains(kind.label(language)),
                              "\(language.rawValue)/\(kind.rawValue): 대상 CLI 이름이 없다 — '\(label)'")
            }
        }
        let translated = [AppLanguage.ko, .en, .ja].map {
            PokemonChatProviderSelection.externalSendLabel(kind: .claude, language: $0)
        }
        XCTAssertEqual(Set(translated).count, 3, "세 언어가 서로 다른 문장이어야 한다")
    }

    // MARK: 막혔을 때 — 말없이 비활성인 버튼을 남기지 않는다

    /// 배너는 **고른 것**과 **실제로 나갈 곳**을 함께 봐야 한다. 자동 선택이 둘을 갈라놓았기
    /// 때문이다 — 차단된 CLI 를 골라도 폴백이 조용히 다른 CLI 로 보내므로, 이유를 말하지 않으면
    /// 사용자는 자기 선택이 왜 무시됐는지 알 길이 없다(피커가 차단 종류를 굳이 보여 주는 이유).
    ///
    /// `effective == nil`(하나도 안 잡힘) 가 새로 생긴 가지다. 자동 선택 전에는 "AI 선택" 이 그
    /// 자리를 대신했지만, 이제는 아무도 없어 이유 없는 비활성 버튼만 남는다.
    func testEveryReasonAChatCannotSendHasItsOwnGuidance() {
        // 보낼 수 있으면 배너는 없다 — 고르지 않은 첫 방문도 포함.
        XCTAssertNil(PokemonChatProviderSelection.unavailableMessage(
            stored: "", effective: .codex, language: .ko))
        XCTAssertNil(PokemonChatProviderSelection.unavailableMessage(
            stored: "claude", effective: .claude, language: .ko))

        // 검증 CLI 가 하나도 안 잡힘.
        XCTAssertEqual(PokemonChatProviderSelection.unavailableMessage(
            stored: "", effective: nil, language: .ko),
                       PokemonChatProviderSelection.noProviderMessage(.ko))

        // 고른 종류가 차단됨 — 폴백이 보내 주더라도 왜 그 선택이 안 쓰이는지 말해야 한다.
        XCTAssertEqual(PokemonChatProviderSelection.unavailableMessage(
            stored: "opencode", effective: .codex, language: .ko),
                       PokemonChatBlockReason.unverifiedToolContract.message(.ko))
        XCTAssertEqual(PokemonChatProviderSelection.unavailableMessage(
            stored: "custom", effective: .codex, language: .ko),
                       PokemonChatBlockReason.arbitraryExecutable.message(.ko))
        XCTAssertNotEqual(PokemonChatBlockReason.unverifiedToolContract.message(.ko),
                          PokemonChatBlockReason.arbitraryExecutable.message(.ko),
                          "두 차단 사유는 사용자가 할 수 있는 일이 다르다")
    }

    /// 사유별 문구가 세 언어를 다 갖췄는가. 한 언어만 비면 그 사용자는 막힌 채 영어를 본다.
    func testEveryUnavailableGuidanceIsWrittenInAllThreeLanguages() {
        for stored in ["opencode", "custom", ""] {
            let messages = [AppLanguage.ko, .en, .ja].compactMap {
                PokemonChatProviderSelection.unavailableMessage(stored: stored, effective: nil, language: $0)
            }
            XCTAssertEqual(Set(messages).count, 3, "'\(stored)': 세 갈래가 아니다")
        }
    }
}
