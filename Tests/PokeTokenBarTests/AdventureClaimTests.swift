import XCTest
@testable import PokeTokenBar

// 모험 보상 정산 도달성 회귀(#8).
// 증상: 첫 집중 모험 이후 "모험 보내고 집중 시작" 이 영구 비활성. `state.adventure` 를 비우는 유일한
// 코드가 claimAdventure() 인데, 그 호출부(AdventureCard)가 어디에도 마운트돼 있지 않았다.
// 세션 완료(completeFocusSession)도 save() 만 하고 정산하지 않았다.
//
// 트리거 브랜치를 그대로 재현한다: "모험이 끝났지만 아직 정산 안 된" 상태(= 예전 게이트가 잠기던
// 바로 그 조건)를 만들고, 정산·게이트·재시작이 모두 풀리는지 본다.
@MainActor
final class AdventureClaimTests: XCTestCase {

    private func makeStore(_ clock: TestClock) -> CompanionStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("poke-adv-\(UUID().uuidString).json")
        return CompanionStore(provider: StubProvider(value: claimTestLine), clock: clock.closure,
                              fileURL: url, rng: SeededRNG(seed: 11))
    }

    private func hatchedStore(_ clock: TestClock) async -> CompanionStore {
        let store = makeStore(clock)
        await store.hatch(baseID: 1)
        XCTAssertNotNil(store.state.active, "테스트 전제: 활성 포켓몬이 있어야 모험을 보낼 수 있다")
        return store
    }

    /// 집중 세션이 끝나면 그 세션의 모험이 자동 정산된다 — 보상이 들어오고 슬롯이 비워진다.
    func testFocusSessionCompletionClaimsTheAdventure() async {
        let clock = TestClock()
        let store = await hatchedStore(clock)
        let starPiecesBefore = store.state.starPieces
        let expBefore = store.state.active?.levelExperience ?? 0

        XCTAssertTrue(store.startFocusAdventure(minutes: 25))
        clock.advance(25 * 60)
        let reward = store.completeFocusSession(minutes: 25)

        XCTAssertNil(store.activeAdventure, "정산 후에는 모험 슬롯이 비어야 한다")
        XCTAssertGreaterThan(store.state.starPieces, starPiecesBefore)
        XCTAssertGreaterThan(store.state.active?.levelExperience ?? 0, expBefore)
        // 보상 객체가 지갑 증가분을 **전부** 설명해야 한다. 트레이너 레벨업·미션 완료처럼 정산 중에
        // 함께 지급되는 값도 여기 실려야, 알려준 값과 실제 잔액이 어긋나지 않는다.
        XCTAssertEqual(reward.totalStardust, store.state.starPieces - starPiecesBefore,
                       "세션 보상은 claimAdventure() 결과 그대로 — 별도 가산이면 이중 지급이다")
    }

    /// [회귀 가드] 위 테스트는 25분 세션이라 어떤 미션도 완료되지 않아, 미션이 지갑에 **몰래** 더해도
    /// 통과했다(트레이너 레벨과 미션을 합칠 때 실제로 그랬다). 완전설명 불변식은 부가 지급이 실제로
    /// 일어나는 세션에서 검사해야 의미가 있다 — 60분 목표를 넘기는 90분으로 그 분기를 밟는다.
    func testRewardExplainsWalletEvenWhenAMissionCompletes() async {
        let clock = TestClock()
        let store = await hatchedStore(clock)
        let starPiecesBefore = store.state.starPieces

        XCTAssertTrue(store.startFocusAdventure(minutes: 90))
        clock.advance(90 * 60)
        let reward = store.completeFocusSession(minutes: 90)

        XCTAssertGreaterThan(reward.missionBonus, 0, "테스트 전제: 이 세션은 일간 집중 미션을 완료시킨다")
        // 90분 세션은 집중 업적 1단계(60분)도 함께 넘긴다 — 지급 경로가 넷이 됐으니 넷 다 실려야 한다.
        XCTAssertGreaterThan(reward.achievementBonus, 0, "테스트 전제: 이 세션은 집중 업적 1단계도 넘긴다")
        XCTAssertEqual(reward.totalStardust, store.state.starPieces - starPiecesBefore,
                       "미션·업적·시즌 보상까지 보상 객체가 설명해야 한다")
    }

    /// 이중 지급 가드: 세션 완료 후 한 번 더 정산해도 아무것도 늘지 않는다.
    func testClaimingTwiceDoesNotPayTwice() async {
        let clock = TestClock()
        let store = await hatchedStore(clock)
        XCTAssertTrue(store.startFocusAdventure(minutes: 25))
        clock.advance(25 * 60)
        _ = store.completeFocusSession(minutes: 25)

        let starPieces = store.state.starPieces
        let fragments = store.eggFragmentCount
        XCTAssertNil(store.claimAdventure())
        XCTAssertEqual(store.state.starPieces, starPieces)
        XCTAssertEqual(store.eggFragmentCount, fragments)
    }

    func testEachCompletedAdventureRecordsOnePersistentAutomaticMemory() async {
        let clock = TestClock()
        let store = await hatchedStore(clock)
        let companionID = try! XCTUnwrap(store.state.active?.id)

        XCTAssertTrue(store.startFocusAdventure(minutes: 25))
        clock.advance(25 * 60)
        XCTAssertNotNil(store.claimAdventure())
        XCTAssertTrue(store.startFocusAdventure(minutes: 25))
        clock.advance(25 * 60)
        XCTAssertNotNil(store.claimAdventure())

        let adventureMemories = store.memoryAlbum.entries(for: companionID)
            .filter { $0.eventID?.hasPrefix("adventure:") == true }
        XCTAssertEqual(adventureMemories.count, 2)
        XCTAssertEqual(Set(adventureMemories.compactMap(\.eventID)).count, 2,
                       "Each persisted run UUID identifies exactly one automatic memory")
        XCTAssertEqual(store.memoryAlbum.milestones(for: companionID).filter {
            if case .focusSessions = $0.kind { return true }
            return false
        }.count, 0, "Two settled runs do not unlock a focus threshold early")
    }

    /// 트리거 재현 — 진행 중 / 완료-미정산 두 브랜치를 각각 확인한다.
    /// 예전 게이트(`isAdventuring`)는 완료-미정산에서도 참이라 버튼이 영구 비활성이었다.
    func testGateBlocksOnlyWhileRunIsStillInProgress() async {
        let clock = TestClock()
        let store = await hatchedStore(clock)
        XCTAssertTrue(store.startFocusAdventure(minutes: 25))

        clock.advance(24 * 60)
        XCTAssertTrue(store.isAdventureInProgress, "진행 중에는 막아야 한다")

        clock.advance(2 * 60)   // 종료 시각 통과 — 정산 전
        XCTAssertTrue(store.isAdventuring, "슬롯은 아직 차 있다(= 예전 게이트가 잠기던 조건)")
        XCTAssertFalse(store.isAdventureInProgress, "끝난 모험은 더 이상 시작을 막지 않는다")
    }

    /// 앱이 꺼진 채 모험이 끝났거나 정산 UI 를 못 본 세이브(실제 회귀 리포트의 상태) —
    /// 다음 모험을 시작하면 밀린 보상이 먼저 자동 정산된다. 정산이 없으면 시작이 조용히 실패한다.
    func testStartingNewRunAutoClaimsStaleCompletedRun() async {
        let clock = TestClock()
        let store = await hatchedStore(clock)
        XCTAssertTrue(store.startFocusAdventure(minutes: 25))
        let staleRunID = store.activeAdventure?.id
        clock.advance(6 * 3600)   // 몇 시간 방치

        let starPiecesBefore = store.state.starPieces
        XCTAssertTrue(store.startFocusAdventure(minutes: 25), "밀린 보상 때문에 시작이 막히면 안 된다")

        XCTAssertGreaterThan(store.state.starPieces, starPiecesBefore, "밀린 보상이 정산돼야 한다")
        XCTAssertEqual(store.recentAdventures.first?.id, staleRunID, "정산 기록이 남는다")
        XCTAssertNotEqual(store.activeAdventure?.id, staleRunID, "새 모험이 시작됐다")
        XCTAssertTrue(store.isAdventureInProgress)
    }

    /// 집중 시간이 존을 고른다 — 존은 보상 계산의 입력이라(`AdventureRules.reward`) 경계가 밀리면
    /// 같은 25분이 다른 값을 낸다. 이 매핑이 유일한 존 선택 경로다(존 버튼은 사라졌다).
    func testFocusMinutesPickTheZoneAtEveryBoundary() async {
        for (minutes, zone) in [(25, AdventureZone.forest), (49, .forest), (50, .cave),
                                (89, .cave), (90, .coast)] {
            let clock = TestClock()
            let store = await hatchedStore(clock)
            XCTAssertTrue(store.startFocusAdventure(minutes: minutes))
            XCTAssertEqual(store.activeAdventure?.zone, zone, "\(minutes)분")
        }
    }

    /// 모험을 안 보낸 집중 세션은 정산할 게 없다 — 보상 0, 크래시 없음.
    func testFocusSessionWithoutAdventureYieldsNoReward() async {
        let clock = TestClock()
        let store = await hatchedStore(clock)
        let starPiecesBefore = store.state.starPieces
        let reward = store.completeFocusSession(minutes: 25)
        XCTAssertEqual(reward.stardust, 0)
        XCTAssertFalse(reward.foundEgg)
        XCTAssertEqual(store.state.starPieces, starPiecesBefore)
    }

    /// 아직 안 끝난 모험은 세션이 일찍 끝나도 정산되지 않는다(시간 조건을 우회하지 않는다).
    func testIncompleteRunIsNotClaimedEarly() async {
        let clock = TestClock()
        let store = await hatchedStore(clock)
        XCTAssertTrue(store.startFocusAdventure(minutes: 50))
        clock.advance(10 * 60)

        let reward = store.completeFocusSession(minutes: 50)
        XCTAssertEqual(reward.stardust, 0)
        XCTAssertNotNil(store.activeAdventure, "미완료 모험은 그대로 유지")
        XCTAssertTrue(store.isAdventureInProgress)
    }

    // MARK: 도달성 가드 — 선언만 되고 아무 데서도 마운트되지 않는 뷰 금지

    /// #8 의 진짜 원인은 로직이 아니라 "뷰가 어디에도 안 붙어 있었다" 였다. 로직 테스트로는 절대
    /// 안 걸리므로, UI 파일의 View 선언에 호출부가 하나라도 있는지를 소스에서 기계적으로 검사한다.
    func testEveryDeclaredViewHasACallSite() throws {
        let uiDirectory = Self.repositoryRoot.appendingPathComponent("Sources/PokeTokenBar/UI")
        let sourceDirectory = Self.repositoryRoot.appendingPathComponent("Sources/PokeTokenBar")
        let allSources = try Self.swiftFiles(in: sourceDirectory)
            .map { try String(contentsOf: $0, encoding: .utf8) }

        // 앱 진입점에서 NSHostingView/Controller 로만 붙는 루트 뷰는 이름 호출부가 없을 수 있다.
        let rootViews: Set<String> = ["PopoverView", "FloatingPetView"]
        // 이미 마운트가 끊긴 채로 남아 있던 뷰들 — 포획 로그 화면(개체 단위 목록)이 도감 격자로
        // 대체되면서 호출부가 사라졌다. 화면을 되살릴지 지울지는 별도 과제라 여기선 목록을 고정해
        // "더 늘어나지 않는다" 만 잠근다. 해결하면 이 목록에서 지운다.
        // AdventureCard 는 폐기된 돌보기 UI를 소스 호환 목적으로만 남긴 상태다. 모험 정산은
        // FocusTimerView와 CompanionStore의 자동 정산 경로가 담당하므로 다시 마운트하면 안 된다.
        let knownUnmounted: Set<String> = ["StarterCard", "DexSummaryHeader", "DexEntryRow", "AdventureCard"]

        var unmounted: [String] = []
        for file in try Self.swiftFiles(in: uiDirectory) {
            let text = try String(contentsOf: file, encoding: .utf8)
            for name in Self.declaredViewNames(in: text)
            where !rootViews.contains(name) && !knownUnmounted.contains(name) {
                let hasCallSite = allSources.contains { source in
                    source.contains("\(name)(") && !source.contains("struct \(name)(")
                }
                if !hasCallSite { unmounted.append(name) }
            }
        }
        XCTAssertTrue(unmounted.isEmpty,
                      "마운트되지 않은 View: \(unmounted) — 선언만 있고 화면에 안 붙으면 그 안의 기능(보상 정산 등)은 도달 불가다")
    }

    /// 위 가드의 형제. `struct X: View` 가 아니라 **화면 안의 조각**(`private var x: some View`)이
    /// 아무 데서도 안 불리는 형태다 — 컴파일러는 안 쓰는 computed property 에 warning 을 내지
    /// 않으므로 빌드도 테스트도 초록인 채로 화면만 죽는다.
    ///
    /// #209 가 그 상태였다: 2~4인 방 배틀의 `multiplayerRooms` / `multiplayerLobby` 가 세 주 동안
    /// 아무 데도 안 붙어 있었고, 그 사이 `RecentBattleLabel` 의 단위 테스트는 계속 통과했다.
    /// 순수 로직 테스트가 도달 불가 화면에 false confidence 를 주는 부류다.
    ///
    /// **천장**: 한 단계만 본다. 죽은 하위 트리는 **뿌리만** 잡힌다(`multiplayerLobby` 가 걸리고
    /// 그것만 참조하는 `multiplayerArena` 는 안 걸린다). 뿌리를 지우면 나머지가 다음 실행에서
    /// 걸리므로 결국 전부 드러난다. 서로만 참조하는 죽은 순환은 못 잡는다 — 그때는 사람이 본다.
    func testEveryDeclaredViewMemberHasACallSite() throws {
        let uiDirectory = Self.repositoryRoot.appendingPathComponent("Sources/PokeTokenBar/UI")
        let files = try Self.swiftFiles(in: uiDirectory)
        // 경로가 깨지면 빈 목록을 훑고 조용히 통과한다 — 그걸 막는 단언.
        XCTAssertGreaterThan(files.count, 10, "UI 소스를 못 찾았다 — 경로가 깨지면 가드가 무력해진다")

        var orphans: [String] = []
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            let lines = text.components(separatedBy: "\n")
            for member in Self.declaredViewMembers(in: lines) {
                // 선언 줄을 뺀 나머지 어디에도 이름이 없으면 아무도 이 조각을 그리지 않는다.
                let mentioned = lines.contains { line in
                    !Self.declares(member, in: line) && Self.mentions(member, in: line)
                }
                if !mentioned { orphans.append("\(file.lastPathComponent):\(member)") }
            }
        }
        XCTAssertEqual(orphans, [], """
            아무 데서도 안 불리는 View 조각: \(orphans) — 선언만 있고 화면에 안 붙으면 \
            그 안의 기능은 도달 불가다. 그리는 자리를 붙이거나 삭제하라.
            """)
    }

    /// 정산 진입점은 `claimAdventure()` 하나다 — 완료 판정을 감싸는 래퍼가 다시 생기면 같은 가드가
    /// 두 곳에 놓여 한쪽만 바뀌는 사고가 난다. 소스로 고정한다.
    func testAdventureIsClaimedThroughASingleStoreEntryPoint() throws {
        let store = try String(
            contentsOf: Self.repositoryRoot.appendingPathComponent("Sources/PokeTokenBar/Core/CompanionStore.swift"),
            encoding: .utf8)
        XCTAssertFalse(store.contains("claimCompletedAdventureIfNeeded"),
                       "완료 판정 래퍼가 다시 생겼다 — 정산 판정은 claimAdventure() 안에만 둔다")
        XCTAssertEqual(store.components(separatedBy: "func claimAdventure()").count - 1, 1)
    }

    private static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)          // Tests/PokeTokenBarTests/AdventureClaimTests.swift
            .deletingLastPathComponent()         // Tests/PokeTokenBarTests
            .deletingLastPathComponent()         // Tests
            .deletingLastPathComponent()         // <repo>
    }

    private static func swiftFiles(in directory: URL) throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(at: directory,
                                                              includingPropertiesForKeys: nil) else { return [] }
        return enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
    }

    /// `private var x: some View` / `private func x(...) -> some View` 의 이름을 뽑는다.
    /// `body` 는 SwiftUI 가 부르므로 제외한다.
    ///
    /// **private 만 본다.** 파일 밖에서 쓰이는 멤버(`PokedoroTheme.pageBackground`,
    /// `View.pokedoroCard`)는 한 파일만 읽어서는 도달성을 판단할 수 없다 — 그 부류를 넣으면
    /// 허용 목록으로 덮어야 하고, 허용 목록은 곧 진짜 고아도 덮는다. private 는 정의상
    /// 자기 파일 안에서만 불리므로 이 검사만으로 결론이 난다.
    private static func declaredViewMembers(in lines: [String]) -> [String] {
        var names: [String] = []
        for line in lines {
            guard let name = declaredMemberName(in: line), name != "body" else { continue }
            names.append(name)
        }
        return Array(Set(names)).sorted()
    }

    /// 한 줄이 View 조각을 선언하는가 — 그렇다면 그 이름.
    private static func declaredMemberName(in line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        // `@ViewBuilder private var x` 처럼 속성이 같은 줄에 붙는 형태도 받는다.
        guard trimmed.contains("private ") else { return nil }
        if let range = trimmed.range(of: "var "), trimmed.contains(": some View") {
            let rest = trimmed[range.upperBound...]
            let name = String(rest.prefix { $0.isLetter || $0.isNumber || $0 == "_" })
            return name.isEmpty ? nil : name
        }
        if let range = trimmed.range(of: "func "), trimmed.contains("-> some View") {
            let rest = trimmed[range.upperBound...]
            let name = String(rest.prefix { $0.isLetter || $0.isNumber || $0 == "_" })
            return name.isEmpty ? nil : name
        }
        return nil
    }

    private static func declares(_ member: String, in line: String) -> Bool {
        declaredMemberName(in: line) == member
    }

    /// 이름이 **식별자 하나로** 나오는가. 부분 문자열(`header` 가 `headerRow` 에)과 주석·문자열
    /// 안의 언급은 세지 않는다 — 주석만으로 살아 있다고 치면 가드가 헐거워진다.
    private static func mentions(_ member: String, in line: String) -> Bool {
        let code = line.range(of: "//").map { String(line[line.startIndex..<$0.lowerBound]) } ?? line
        var index = code.startIndex
        while let found = code.range(of: member, range: index..<code.endIndex) {
            let before = found.lowerBound == code.startIndex
                ? nil : code[code.index(before: found.lowerBound)]
            let after = found.upperBound == code.endIndex ? nil : code[found.upperBound]
            let boundedBefore = before.map { !($0.isLetter || $0.isNumber || $0 == "_") } ?? true
            let boundedAfter = after.map { !($0.isLetter || $0.isNumber || $0 == "_") } ?? true
            if boundedBefore && boundedAfter { return true }
            index = found.upperBound
        }
        return false
    }

    /// `struct Foo: View {` / `struct Foo: View, Sendable` 형태의 선언 이름을 뽑는다.
    private static func declaredViewNames(in text: String) -> [String] {
        text.split(separator: "\n").compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("struct ") || trimmed.hasPrefix("private struct ")
                    || trimmed.hasPrefix("fileprivate struct ") else { return nil }
            let parts = trimmed.split(separator: " ")
            guard let structIndex = parts.firstIndex(of: "struct"), parts.count > structIndex + 1 else { return nil }
            let name = parts[structIndex + 1].split(separator: ":").first.map(String.init) ?? ""
            guard trimmed.contains(": View"), !name.isEmpty else { return nil }
            return name
        }
    }
}

// 부화용 최소 진화 라인(1 → 2 → 3).
private let claimTestLine: EvoLine = {
    var names: [Int: [String: String]] = [:]
    for id in [1, 2, 3] { names[id] = ["en": "P\(id)", "ko": "포\(id)", "ja": "ポ\(id)"] }
    return EvoLine(baseID: 1,
                   tree: EvoNode(speciesID: 1, children: [EvoNode(speciesID: 2, children: [EvoNode(speciesID: 3, children: [])])]),
                   rarity: .common, names: names)
}()
