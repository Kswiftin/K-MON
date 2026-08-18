import XCTest
@testable import PokeTokenBar

// MARK: 스텁 (이 파일 전용 — 다른 테스트 파일의 스텁은 file-private)

private enum TransferStubError: Error { case unavailable }

/// 세이브 이전 테스트는 진화 라인을 필요로 하지 않는다 — 성장 적립은 라인 미로딩에서도
/// 동작해야 하기 때문(CompanionStore.applyUsage 주석). 전부 실패시켜 그 경로를 강제한다.
private struct OfflineProvider: PokeProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine { throw TransferStubError.unavailable }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { throw TransferStubError.unavailable }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { throw TransferStubError.unavailable }
}

private let transferNow = Date(timeIntervalSince1970: 1_700_000_000)

/// 시각을 앞으로 밀 수 있는 주입 시계 — 백업 슬롯이 불러오기마다 갈리는지 보려면 두 번의
/// `applySave` 가 서로 다른 초를 봐야 한다.
private final class MutableClock: @unchecked Sendable {
    var now: Date
    init(_ now: Date) { self.now = now }
}

/// 비동기 경합 테스트용 1회성 신호 — 부화가 네트워크 대기에 들어간 순간을 정확히 잡기 위해
/// sleep 대신 쓴다(타이밍 의존 = flaky).
private actor TransferSignal {
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var fired = false
    func fire() { fired = true; waiters.forEach { $0.resume() }; waiters.removeAll() }
    func wait() async {
        if fired { return }
        await withCheckedContinuation { waiters.append($0) }
    }
}

/// **종 롤**(`baseSpeciesIndex`)에서 멈추는 provider — `hatchIfNeeded` 의 첫 await 창을 재현한다.
private struct GatedIndexProvider: PokeProviding {
    let entered: TransferSignal
    let release: TransferSignal
    let result: EvoLine
    func line(baseSpeciesID: Int) async throws -> EvoLine { result }
    func baseSpeciesIndex() async throws -> [BaseSpecies] {
        await entered.fire()
        await release.wait()
        return [BaseSpecies(id: 1, captureRate: 255)]
    }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
}

/// 라인 fetch 에서 멈춰 있다가 신호를 받고 반환하는 provider — 부화 중 상태 교체를 재현한다.
private struct GatedProvider: PokeProviding {
    let entered: TransferSignal
    let release: TransferSignal
    let result: EvoLine
    func line(baseSpeciesID: Int) async throws -> EvoLine {
        await entered.fire()
        await release.wait()
        return result
    }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { throw TransferStubError.unavailable }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { throw TransferStubError.unavailable }
}

@MainActor
final class SaveTransferTests: XCTestCase {

    /// 테스트마다 **전용 디렉토리**를 준다. 불러오기 백업은 상태 파일 이름이 아니라 시각으로 이름이
    /// 정해지므로, 공유 임시 디렉토리를 쓰면 고정 시계를 쓰는 테스트들끼리 같은 백업 파일명을 놓고 충돌한다.
    private func tempURL(_ tag: String) -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ptb-\(tag)-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("companion-state.json")
    }

    private func store(at url: URL) -> CompanionStore {
        CompanionStore(provider: OfflineProvider(), clock: { transferNow }, fileURL: url)
    }

    /// 옛 기기에서 내보낸 것과 같은 모양의 상태 — 진행이 쌓여 있는 시점. economyVersion 은 현행이라
    /// 마이그레이션 리셋을 타지 않는다(진행 보존 검증용).
    private func oldMacState() -> CompanionState {
        var s = CompanionState()
        s.usedSinceInstall = 8_000_000_000
        s.spentTokens = 3_500_000_000
        s.lastCandyDate = "2026-08-01"
        s.inventory = ["rareCandy": 2]
        s.collectedFinals = ["1-3"]
        s.dex = [DexEntry(baseID: 1, finalID: 3, chainOrder: [1, 2, 3], rarity: .common, caughtAt: transferNow)]
        return s
    }

    // MARK: 봉투

    func testRoundTripPreservesProgress() throws {
        let original = oldMacState()
        let data = try SaveTransfer.encode(state: original, appVersion: "2.5.0",
                                           deviceName: "Old Mac", now: transferNow)
        let envelope = try SaveTransfer.decode(data)

        XCTAssertEqual(envelope.format, SaveEnvelope.formatID)
        XCTAssertEqual(envelope.sourceDevice, "Old Mac")
        XCTAssertEqual(envelope.state.usedSinceInstall, original.usedSinceInstall)
        XCTAssertEqual(envelope.state.spentTokens, original.spentTokens)
        XCTAssertEqual(envelope.state.inventory, original.inventory)
        XCTAssertEqual(envelope.state.dex.count, 1)
        XCTAssertEqual(envelope.state.collectedFinals, original.collectedFinals)
    }

    /// [핵심] 봉투가 없으면 `CompanionState` 의 관대 디코딩이 아무 JSON 이나 빈 상태로 흡수해
    /// "불러오기 성공 → 도감이 사라짐"이 된다. 포맷 id 로 먼저 거른다.
    func testForeignJSONIsRejectedRatherThanImportedAsEmptyState() throws {
        let foreign = Data(#"{"some":"other app","dex":123}"#.utf8)
        XCTAssertThrowsError(try SaveTransfer.decode(foreign)) { error in
            XCTAssertEqual(error as? SaveTransferError, .notASaveFile)
        }

        // 상태만 담긴(봉투 없는) 예전식 파일도 세이브로 인정하지 않는다.
        let bare = try JSONEncoder().encode(oldMacState())
        XCTAssertThrowsError(try SaveTransfer.decode(bare)) { error in
            XCTAssertEqual(error as? SaveTransferError, .notASaveFile)
        }
    }

    /// [회귀·딥리뷰 H4] `decode` 는 "디코딩 실패 **또는** format 불일치"라는 `A || B` 게이트인데,
    /// 기존 두 케이스는 모두 필수 키 누락이라 A 로만 통과했다. 여기서 **B 단독**을 고정한다:
    /// 필드가 전부 유효하고 `format` 값만 다른 완전한 봉투.
    func testValidEnvelopeWithWrongFormatIDIsRejected() throws {
        let data = try SaveTransfer.encode(state: oldMacState(),
                                           appVersion: "2.5.0", deviceName: "Other App", now: transferNow)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["format"] as? String, SaveEnvelope.formatID, "전제: 원본은 유효한 포맷")
        json["format"] = "someotherapp.save"
        let patched = try JSONSerialization.data(withJSONObject: json)

        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        XCTAssertNotNil(try? decoder.decode(SaveEnvelope.self, from: patched),
                        "전제: 필드 구조는 유효 — 여기서 nil 이면 A 분기로 새어 테스트가 무의미해진다")

        XCTAssertThrowsError(try SaveTransfer.decode(patched)) { error in
            XCTAssertEqual(error as? SaveTransferError, .notASaveFile)
        }
    }

    func testNewerSchemaIsRejected() throws {
        var data = try SaveTransfer.encode(state: CompanionState(), appVersion: "2.5.0",
                                           deviceName: "Future Mac", now: transferNow)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json["schema"] = SaveEnvelope.schemaVersion + 1
        data = try JSONSerialization.data(withJSONObject: json)

        XCTAssertThrowsError(try SaveTransfer.decode(data)) { error in
            XCTAssertEqual(error as? SaveTransferError,
                           .newerSchema(found: SaveEnvelope.schemaVersion + 1,
                                        supported: SaveEnvelope.schemaVersion))
        }
    }

    // MARK: 경제 마이그레이션 (토큰 → 방치형)

    /// 토큰 경제 세이브(economyVersion 없음)를 불러오면 진행은 리셋되고 도감·수집·언어만 남는다.
    func testImportingTokenEraSaveResetsProgressKeepsDex() throws {
        // 봉투를 손으로 구성해 economyVersion 키를 뺀다(구버전 세이브 재현).
        var tokenState = oldMacState()
        tokenState.economyVersion = 0   // 인코딩엔 포함되지만, 값이 구버전이라 마이그레이션 대상
        let data = try SaveTransfer.encode(state: tokenState, appVersion: "2.0.0",
                                           deviceName: "Token Mac", now: transferNow)
        let envelope = try SaveTransfer.decode(data)   // decode 가 sanitized → migrate
        XCTAssertEqual(envelope.state.economyVersion, IdleEconomy.currentVersion)
        XCTAssertEqual(envelope.state.usedSinceInstall, 0, "토큰 누적은 환산 안 함 — 리셋")
        XCTAssertEqual(envelope.state.spentTokens, 0)
        XCTAssertTrue(envelope.state.inventory.isEmpty)
        XCTAssertEqual(envelope.state.dex.count, 1, "도감은 계승")
        XCTAssertEqual(envelope.state.collectedFinals, ["1-3"], "수집도 계승")
    }

    // MARK: 진행 보존 · 가드레일

    func testImportKeepsProgress() throws {
        let url = tempURL("progress")
        let s = store(at: url)
        let data = try SaveTransfer.encode(state: oldMacState(), appVersion: "2.5.0",
                                           deviceName: "Old Mac", now: transferNow)
        try s.applySave(try SaveTransfer.decode(data))

        XCTAssertEqual(s.state.usedSinceInstall, 8_000_000_000)
        XCTAssertEqual(s.state.spentTokens, 3_500_000_000)
        XCTAssertEqual(s.state.dex.count, 1)
        XCTAssertEqual(s.state.inventory["rareCandy"], 2)
    }

    /// 덮어쓰기 전 직전 상태를 남긴다 — 잘못 불러왔을 때 손으로 되돌릴 수단.
    func testPreviousStateIsBackedUpBeforeOverwrite() throws {
        let url = tempURL("backup")

        var mine = CompanionState()
        mine.usedSinceInstall = 123_456_789
        try JSONEncoder().encode(mine).write(to: url)

        let s = store(at: url)
        XCTAssertEqual(s.state.usedSinceInstall, 123_456_789)

        let data = try SaveTransfer.encode(state: oldMacState(), appVersion: "2.5.0",
                                           deviceName: "Old Mac", now: transferNow)
        try s.applySave(try SaveTransfer.decode(data))

        let backup = url.deletingLastPathComponent()
            .appendingPathComponent(SaveTransfer.backupFileName(date: transferNow))
        let restored = try JSONDecoder().decode(CompanionState.self, from: Data(contentsOf: backup))
        XCTAssertEqual(restored.usedSinceInstall, 123_456_789, "덮어쓰기 전 상태가 그대로 남아야 한다")
        XCTAssertEqual(s.state.usedSinceInstall, 8_000_000_000)
    }

    /// [회귀] 불러오기가 진행 중인 부화의 네트워크 대기 창에 들어오면, 뒤늦게 끝난 부화가 방금 불러온
    /// 개체를 덮어썼다. `isHatching` 락은 같은 앱 안의 중복 부화만 막을 뿐 상태 통째 교체는 못 막는다.
    func testImportDuringHatchDiscardsTheHatch() async throws {
        let entered = TransferSignal()
        let release = TransferSignal()
        let evo = EvoLine(baseID: 1, tree: EvoNode(speciesID: 1, children: []), rarity: .common,
                          names: [1: ["en": "P1", "ko": "포1", "ja": "ポ1"]])
        let url = tempURL("hatchrace")
        let s = CompanionStore(provider: GatedProvider(entered: entered, release: release, result: evo),
                               clock: { transferNow }, fileURL: url)

        let hatching = Task { await s.hatch(baseID: 1) }
        await entered.wait()   // 부화가 라인 fetch(네트워크) 대기 지점에 도달

        var imported = oldMacState()
        imported.active = MonState(baseID: 403, pathIDs: [403], plannedPathIDs: [403],
                                   stageIndex: 0, usedAtStage: 0, rarity: .common, totalForms: 1)
        let data = try SaveTransfer.encode(state: imported, appVersion: "2.5.0",
                                           deviceName: "Old Mac", now: transferNow)
        try s.applySave(try SaveTransfer.decode(data))

        await release.fire()
        await hatching.value

        XCTAssertEqual(s.state.active?.baseID, 403, "뒤늦게 끝난 부화가 불러온 개체를 덮어쓰면 안 된다")
        XCTAssertEqual(s.state.dex.count, imported.dex.count, "도감도 부화 경로에 밀려나면 안 된다")
    }

    /// [회귀·딥리뷰 B1] 부화의 **첫** await(`chooseBase`) 창에 불러오기가 들어오면, 그 뒤 진입하는
    /// `hatchCore` 는 *교체 이후*의 세대를 캡처해 자기 가드가 무조건 통과했다.
    func testImportDuringSpeciesRollDiscardsTheHatch() async throws {
        let entered = TransferSignal()
        let release = TransferSignal()
        let evo = EvoLine(baseID: 1, tree: EvoNode(speciesID: 1, children: []), rarity: .common,
                          names: [1: ["en": "P1", "ko": "포1", "ja": "ポ1"]])
        let url = tempURL("rollrace")

        // 알 상태 + 부화 임계 도달 + pre-roll 없음 → `chooseBase()` 로 들어간다.
        var egg = CompanionState()
        egg.eggUsage = PokemonBalance.eggHatchThreshold
        try JSONEncoder().encode(egg).write(to: url)

        let s = CompanionStore(provider: GatedIndexProvider(entered: entered, release: release, result: evo),
                               clock: { transferNow }, fileURL: url)
        XCTAssertNil(s.state.active, "전제: 알 상태에서 시작")

        let hatching = Task { await s.hatchIfNeeded() }
        await entered.wait()   // 종 롤이 인덱스 대기 지점에 도달

        var imported = oldMacState()
        imported.active = MonState(baseID: 403, pathIDs: [403], plannedPathIDs: [403],
                                   stageIndex: 0, usedAtStage: 0, rarity: .common, totalForms: 1)
        let data = try SaveTransfer.encode(state: imported, appVersion: "2.5.0",
                                           deviceName: "Old Mac", now: transferNow)
        try s.applySave(try SaveTransfer.decode(data))

        await release.fire()
        await hatching.value

        XCTAssertEqual(s.state.active?.baseID, 403, "종 롤 대기 중 들어온 불러오기를 부화가 덮어쓰면 안 된다")
        XCTAssertEqual(s.state.dex.count, imported.dex.count)
    }

    /// [회귀·딥리뷰 H3] 부화가 폐기된 뒤 불러온 개체의 진화 라인이 다시 로드돼야 한다.
    func testImportDuringHatchStillLoadsTheImportedLine() async throws {
        let entered = TransferSignal()
        let release = TransferSignal()
        let evo = EvoLine(baseID: 403, tree: EvoNode(speciesID: 403, children: []), rarity: .common,
                          names: [403: ["en": "Shinx", "ko": "꼬링크", "ja": "コリンク"]])
        let url = tempURL("linereload")
        let s = CompanionStore(provider: GatedProvider(entered: entered, release: release, result: evo),
                               clock: { transferNow }, fileURL: url)

        let hatching = Task { await s.hatch(baseID: 1) }
        await entered.wait()

        var imported = oldMacState()
        imported.active = MonState(baseID: 403, pathIDs: [403], plannedPathIDs: [403],
                                   stageIndex: 0, usedAtStage: 0, rarity: .common, totalForms: 1)
        let data = try SaveTransfer.encode(state: imported, appVersion: "2.5.0",
                                           deviceName: "Old Mac", now: transferNow)
        try s.applySave(try SaveTransfer.decode(data))
        XCTAssertNil(s.currentLine, "전제: 부화 락에 막혀 라인이 아직 없다")

        await release.fire()
        await hatching.value

        var spins = 0
        while s.currentLine == nil, spins < 500 { await Task.yield(); spins += 1 }

        XCTAssertNotNil(s.currentLine, "부화가 폐기됐으면 불러온 개체의 라인을 다시 로드해야 한다")
        XCTAssertEqual(s.currentLine?.baseID, 403)
        XCTAssertNotEqual(s.displayName, "Token Egg", "이름이 알 표기로 남으면 안 된다")
    }

    // MARK: 신뢰경계 값 정규화 (딥리뷰 H2)

    /// [회귀·딥리뷰 H2] 극단값 세이브가 그대로 저장되면 이후 산술이 오버플로 트랩으로 프로세스를 죽인다.
    func testExtremeValuesAreClampedAtTheTrustBoundary() throws {
        var evil = CompanionState()
        evil.usedSinceInstall = 2_000_000_000_000_000
        evil.spentTokens = -1
        evil.eggUsage = 2_000_000_000_000_000
        evil.active = MonState(baseID: 1, pathIDs: [1], plannedPathIDs: [1],
                               stageIndex: 2_000_000_000_000_000, usedAtStage: 2_000_000_000_000_000, rarity: .common,
                               totalForms: 2_000_000_000_000_000)

        let data = try SaveTransfer.encode(state: evil, appVersion: "2.5.0",
                                           deviceName: "Corrupt", now: transferNow)
        let envelope = try SaveTransfer.decode(data)
        let s = envelope.state

        XCTAssertEqual(s.usedSinceInstall, SaveTransfer.maxTokenValue)
        XCTAssertEqual(s.spentTokens, 0, "음수는 0 으로")
        XCTAssertEqual(s.eggUsage, SaveTransfer.maxTokenValue)
        XCTAssertEqual(s.active?.usedAtStage, SaveTransfer.maxTokenValue)
        XCTAssertEqual(s.active?.totalForms, 12)
        XCTAssertEqual(s.active?.stageIndex, 0, "pathIDs 범위를 넘지 않아야 한다")

        // 정규화된 값으로 실제 산술 경로를 태워 트랩이 안 나는지 확인한다.
        let url = tempURL("clamped")
        let store = store(at: url)
        try store.applySave(envelope)
        XCTAssertGreaterThanOrEqual(store.availableTokens, 0)
    }

    /// [회귀·딥리뷰 H2 후속] 디스크에 있는 극단값도 로드 경계에서 정규화돼야 자가 복구된다.
    /// economyVersion 을 현행으로 심어 마이그레이션 리셋이 아니라 클램프 경로를 밟게 한다.
    func testCorruptStateOnDiskIsClampedOnLoadNotJustOnImport() throws {
        let url = tempURL("diskclamp")
        let json = #"{"economyVersion":2,"forcedResetVersion":1,"starterChosen":true,"usedSinceInstall":2000000000000000,"#
            + #""spentTokens":-1,"eggUsage":2000000000000000}"#
        try Data(json.utf8).write(to: url)

        let raw = try JSONDecoder().decode(CompanionState.self, from: Data(json.utf8))
        let s = SaveTransfer.sanitized(raw)
        XCTAssertEqual(s.usedSinceInstall, SaveTransfer.maxTokenValue)
        XCTAssertEqual(s.spentTokens, 0)
        XCTAssertEqual(s.eggUsage, SaveTransfer.maxTokenValue)
        XCTAssertGreaterThanOrEqual(s.usedSinceInstall - s.spentTokens, 0)
    }

    /// [부류 가드] 기본값 상태의 canonical 은 **동결**이다. 새 필드를 조건 없이 붙이면 여기서 깨진다 —
    /// 그런 append 는 그 필드가 없던 시절의 정상 세이브를 전부 조작으로 판정해 진행을 초기화한다.
    ///
    /// 필드마다 있던 `hash(기본값) == hash(기본값)` 형태의 테스트 3개는 이걸 못 잡았다: 무조건 append 로
    /// 바꿔도 비교 대상 양쪽이 똑같이 바뀌어 그대로 통과한다. 자기 자신이 아니라 **동결된 문자열**과 대조한다.
    func testDefaultStateCanonicalFormIsFrozen() {
        let canonical = SaveTransfer.canonicalString(CompanionState())
        XCTAssertEqual(canonical.components(separatedBy: "|sec").first,
                       "v2|u0|sp0|pc0|eg0|ef0|ab|wk|wc0|tier-|scfalse|cand|inv|act-|dex|cf",
                       """
                       기본값 canonical 이 바뀌었다. 새 필드를 조건 없이 붙였다면 되돌려라 —
                       그 필드가 없던 세이브가 전부 조작 판정된다. 형식을 의도적으로 바꾼 것이라면
                       integrityVersion 을 올리고 이 기대값을 갱신하라.
                       """)
    }

    // MARK: 필드 부류 (딥리뷰 M-g)

    /// [딥리뷰 M-g] 이전 시 필드 분류가 산문 규약뿐이라, 새 필드가 추가되면 아무 판단 없이 "진행"으로
    /// 딸려 들어간다(`language` 가 실제로 그랬다). 필드 목록을 테스트로 고정해 **분류를 강제**한다.
    func testEveryCompanionStateFieldIsClassifiedForTransfer() {
        // 진행: 어느 기기에서든 참. eggTier(알 등급 보증)도 산 물건이라 기기를 옮겨도 따라간다.
        let progress: Set<String> = ["economyVersion", "usedSinceInstall", "spentTokens", "eggUsage",
                                     "eggTier", "pendingHatchID", "trainerName", "starterChosen",
                                     "starterCandidates", "active", "dex", "collectedFinals", "inventory",
                                     "activeSecondsTotal", "activeSecondsToday", "activeSecondsDate", "boxedMons",
                                     "care", "battleRank", "trainer", "missions", "battleHistory",
                                     "adventure", "adventureHistory",
                                     "adventureWeekKey", "weeklyAdventureCount", "focusEggs", "focusEggReadyDates", "eggFragments",
                                     "starPieces", "forcedResetVersion", "integrityVersion", "lastAdventureBonusDate"]
        // 로컬 장부: 이 기기의 시계 기준값·서명 → 새 기기 기준 재설정(저장 시 재서명).
        let deviceLedger: Set<String> = ["lastTickAt", "integrity"]
        // 계정 원장(로컬 날짜 문자열 — 비교 가능): 더 최근 값 유지.
        let accountLedger: Set<String> = ["lastCandyDate"]
        // 기기 환경설정: 현재 기기 값 유지.
        let devicePreference: Set<String> = ["language"]

        let classified = progress.union(deviceLedger).union(accountLedger).union(devicePreference)
        let actual = Set(Mirror(reflecting: CompanionState()).children.compactMap(\.label))
        XCTAssertEqual(actual, classified, """
            CompanionState 필드가 바뀌었다. 세이브 이전에서 이 필드가 무엇인지 정하고 목록을 갱신하라 —
            진행(그대로) / 로컬 장부(새 기기 기준 재설정) / 계정 원장(병합) / 기기 환경설정(현재 값 유지).
            """)
    }

    /// [딥리뷰 M-c] `language` 는 진행이 아니라 이 기기에서 보는 방식이다. 일본어 Mac 의 세이브가
    /// 영어 Mac 의 UI 언어를 조용히 바꾸면 안 된다.
    func testImportKeepsThisDevicesLanguage() throws {
        let url = tempURL("lang")
        var mine = CompanionState()
        mine.language = .en
        try JSONEncoder().encode(mine).write(to: url)
        let s = store(at: url)
        XCTAssertEqual(s.language, .en)

        var imported = oldMacState()
        imported.language = .ja
        let data = try SaveTransfer.encode(state: imported, appVersion: "2.5.0",
                                           deviceName: "JA Mac", now: transferNow)
        try s.applySave(try SaveTransfer.decode(data))

        XCTAssertEqual(s.language, .en, "불러온 세이브의 언어가 이 기기 설정을 덮으면 안 된다")
        XCTAssertEqual(s.state.dex.count, imported.dex.count, "진행은 그대로 들어와야 한다")
    }

    /// 일일 사탕 원장은 로컬 날짜라 비교 가능 — 더 최근 값을 남겨 재지급을 막는다.
    func testRebaseKeepsNewerCandyDateAndResetsTick() {
        var imported = oldMacState()
        imported.lastTickAt = Date(timeIntervalSince1970: 1_000)
        imported.lastCandyDate = "2026-08-01"
        var current = CompanionState()
        current.lastCandyDate = "2026-08-13"
        let out = SaveTransfer.rebasedForThisDevice(imported, current: current)
        XCTAssertNil(out.lastTickAt, "옛 기기 시각을 이 기기 가동 시간으로 오인하지 않게 리셋")
        XCTAssertEqual(out.lastCandyDate, "2026-08-13", "더 최근 날짜를 남겨 사탕 재지급 방지")
    }

    // MARK: 백업 가드레일 (딥리뷰 M-a·M-b)

    /// [딥리뷰 M-a] 확인창은 3개 언어로 "직전 상태가 남는다"고 약속한다. 백업을 못 남기면 그 약속을
    /// 못 지키는 것이므로 **덮어쓰지 않고 중단**해야 한다.
    func testImportAbortsWhenBackupCannotBeWritten() throws {
        let url = tempURL("nobackup")
        var mine = CompanionState()
        mine.usedSinceInstall = 123_456_789
        try JSONEncoder().encode(mine).write(to: url)
        let s = store(at: url)

        // 백업이 쓰일 자리를 디렉토리로 막아 쓰기를 실패시킨다.
        let blocked = url.deletingLastPathComponent()
            .appendingPathComponent(SaveTransfer.backupFileName(date: transferNow))
        try FileManager.default.createDirectory(at: blocked, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: blocked) }

        let data = try SaveTransfer.encode(state: oldMacState(), appVersion: "2.5.0",
                                           deviceName: "Old Mac", now: transferNow)
        let envelope = try SaveTransfer.decode(data)
        XCTAssertThrowsError(try s.applySave(envelope)) {
            XCTAssertEqual($0 as? SaveTransferError, .backupFailed)
        }
        XCTAssertEqual(s.state.usedSinceInstall, 123_456_789, "중단했으면 진행이 그대로여야 한다")
        XCTAssertTrue(s.state.dex.isEmpty)
    }

    /// [딥리뷰 M-b] 백업 슬롯이 하나면 두 번째 불러오기가 **원본**을 덮어써, 되돌리려는 바로 그
    /// 순간 되돌릴 대상이 사라진다. 불러올 때마다 새 슬롯이어야 한다.
    func testSecondImportDoesNotDestroyTheOriginalBackup() throws {
        let url = tempURL("twoimports")
        var original = CompanionState()
        original.usedSinceInstall = 111
        try JSONEncoder().encode(original).write(to: url)

        let clock = MutableClock(transferNow)
        let s = CompanionStore(provider: OfflineProvider(), clock: { clock.now }, fileURL: url)

        var first = oldMacState(); first.usedSinceInstall = 222
        try s.applySave(try SaveTransfer.decode(
            try SaveTransfer.encode(state: first, appVersion: "2.5.0", deviceName: "A", now: transferNow)))

        clock.now = transferNow.addingTimeInterval(60)   // 다음 백업은 다른 슬롯
        var second = oldMacState(); second.usedSinceInstall = 333
        try s.applySave(try SaveTransfer.decode(
            try SaveTransfer.encode(state: second, appVersion: "2.5.0", deviceName: "B", now: transferNow)))

        let dir = url.deletingLastPathComponent()
        let backups = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .filter { $0.hasPrefix(SaveTransfer.backupFilePrefix) }.sorted()
        XCTAssertEqual(backups.count, 2, "불러오기마다 새 슬롯이어야 한다")
        let oldest = try JSONDecoder().decode(
            CompanionState.self, from: Data(contentsOf: dir.appendingPathComponent(backups[0])))
        XCTAssertEqual(oldest.usedSinceInstall, 111, "가장 오래된 백업이 원본이어야 한다")
        for name in backups { try? FileManager.default.removeItem(at: dir.appendingPathComponent(name)) }
    }

    // MARK: 확인창 정책 · 표시 상태 (딥리뷰 M-f·M-h)

    /// [딥리뷰 M-f] 파괴적 버튼이 기본이면 Return 한 키로 진행이 대체된다.
    func testCancelIsTheDefaultButtonOnTheImportConfirmation() {
        XCTAssertEqual(ImportConfirmPolicy.keyEquivalent(forButtonAt: ImportConfirmPolicy.cancelButtonIndex), "\r")
        XCTAssertEqual(ImportConfirmPolicy.keyEquivalent(forButtonAt: ImportConfirmPolicy.replaceButtonIndex), "",
                       "대체(파괴적) 버튼이 기본이면 안 된다")
    }

    /// [딥리뷰 M-h] `applySave` 가 정하는 표시 상태 — 개체가 들어왔으면 idle, 알만이면 egg.
    func testApplySaveSetsDisplayStateFromWhetherACompanionCameIn() throws {
        var withMon = oldMacState()
        withMon.active = MonState(baseID: 403, pathIDs: [403], plannedPathIDs: [403],
                                  stageIndex: 0, usedAtStage: 0, rarity: .common, totalForms: 1)
        let a = store(at: tempURL("dispA"))
        try a.applySave(try SaveTransfer.decode(
            try SaveTransfer.encode(state: withMon, appVersion: "2.5.0", deviceName: "A", now: transferNow)))
        XCTAssertEqual(a.displayState, .idle)

        let eggOnly = oldMacState()   // active == nil
        let b = store(at: tempURL("dispB"))
        try b.applySave(try SaveTransfer.decode(
            try SaveTransfer.encode(state: eggOnly, appVersion: "2.5.0", deviceName: "B", now: transferNow)))
        XCTAssertEqual(b.displayState, .egg)
    }

    // MARK: 파일 경계 (딥리뷰 LOW)

    /// 거대한 JSON 은 메인스레드 파싱을 수 초간 잡는다(실측 39MB ≈ 1.8초). 세이브는 수 KB 라 상한이 안전하다.
    func testOversizedFileIsRejectedBeforeParsing() {
        let huge = Data(count: SaveTransfer.maxFileBytes + 1)
        XCTAssertThrowsError(try SaveTransfer.decode(huge)) { error in
            XCTAssertEqual(error as? SaveTransferError,
                           .fileTooLarge(bytes: SaveTransfer.maxFileBytes + 1, limit: SaveTransfer.maxFileBytes))
        }
    }

    /// 상위 스키마 세이브는 본문 모양이 달라 전체 디코드가 실패할 수 있다. 그래도 "세이브 파일이
    /// 아니에요"가 아니라 "앱을 업데이트하라"로 안내해야 한다 — 헤더를 먼저 읽는 이유다.
    func testNewerSchemaIsReportedEvenWhenTheBodyIsUnreadable() throws {
        let json = #"{"format":"poketokenbar.save","schema":99,"whatever":{"unknown":true}}"#
        XCTAssertThrowsError(try SaveTransfer.decode(Data(json.utf8))) { error in
            XCTAssertEqual(error as? SaveTransferError,
                           .newerSchema(found: 99, supported: SaveEnvelope.schemaVersion))
        }
    }

    // MARK: 오류 문구 매핑

    func testImportErrorMessagesAreLocalizedNotRawSwiftText() {
        for lang in [AppLanguage.ko, .en, .ja] {
            let l = L(lang)
            let notSave = l.importErrorMessage(SaveTransferError.notASaveFile)
            let newer = l.importErrorMessage(SaveTransferError.newerSchema(found: 2, supported: 1))
            XCTAssertEqual(notSave, l.importErrorNotSaveFile, "\(lang)")
            XCTAssertEqual(newer, l.importErrorNewerSchema, "\(lang)")
            for message in [notSave, newer] {
                XCTAssertFalse(message.contains("SaveTransferError"), "원문 노출: \(message)")
                XCTAssertFalse(message.contains("couldn't be completed"), "원문 노출: \(message)")
            }
        }
        let other = NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoSuchFileError)
        XCTAssertEqual(L(.en).importErrorMessage(other), other.localizedDescription)
    }

    func testSuggestedFileNameCarriesDate() {
        let name = SaveTransfer.suggestedFileName(date: Date(timeIntervalSince1970: 1_785_758_400))
        XCTAssertTrue(name.hasPrefix("PokeTokenBar-Save-"))
        XCTAssertTrue(name.hasSuffix(".json"))
        XCTAssertTrue(name.contains("2026-08-03"), "실제 이름: \(name)")
    }
}
