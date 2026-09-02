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

    func testImportReplacesMemoryAlbumAndNormalizesInvalidEntriesAndPins() throws {
        let url = tempURL("memory-album")
        let store = store(at: url)
        let valid = populatedMon(25), orphan = UUID(), validMemoryID = UUID()
        store.memoryAlbum.addManual(companionID: orphan, body: "local orphan")
        var imported = oldMacState(); imported.active = valid
        let validMemory = PokemonMemory(id: validMemoryID, companionID: valid.id, createdAt: transferNow,
                                        source: .manual, body: "imported private note", isHidden: true)
        let badCompanion = PokemonMemory(companionID: orphan, createdAt: transferNow, source: .event, body: "orphan")
        let tooLong = PokemonMemory(companionID: valid.id, createdAt: transferNow, source: .event,
                                    body: String(repeating: "x", count: 181))
        let album = PokemonMemoryAlbumSnapshot(memories: [valid.id: [validMemory, badCompanion, tooLong], orphan: [badCompanion]],
                                               pinnedMemoryIDs: [valid.id: validMemoryID, orphan: badCompanion.id])
        let data = try SaveTransfer.encode(state: imported, memoryAlbum: album, appVersion: "2.5.0",
                                           deviceName: "Old Mac", now: transferNow)

        try store.applySave(try SaveTransfer.decode(data))

        XCTAssertEqual(store.memoryAlbum.entries(for: valid.id), [validMemory])
        XCTAssertEqual(store.memoryAlbum.pinned(for: valid.id)?.id, validMemoryID)
        XCTAssertTrue(store.memoryAlbum.entries(for: orphan).isEmpty)
    }

    func testSchemaTwoImportKeepsTheExistingMemoryPruningPolicy() throws {
        let url = tempURL("legacy-memory")
        let store = store(at: url)
        let retained = populatedMon(25), orphan = UUID()
        store.memoryAlbum.addManual(companionID: retained.id, body: "keep me")
        store.memoryAlbum.addManual(companionID: orphan, body: "remove me")
        var imported = oldMacState(); imported.active = retained
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: SaveTransfer.encode(state: imported, appVersion: "2.5.0", deviceName: "Old Mac", now: transferNow)) as? [String: Any])
        json["schema"] = 2
        json.removeValue(forKey: "memoryAlbum")

        try store.applySave(try SaveTransfer.decode(JSONSerialization.data(withJSONObject: json)))

        XCTAssertEqual(store.memoryAlbum.entries(for: retained.id).map(\.body), ["keep me"])
        XCTAssertTrue(store.memoryAlbum.entries(for: orphan).isEmpty)
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

    /// [부류] 세이브에서 온 **문자열은 길이가 무제한**이었다 — 원장 키·이름이 그대로 무결성 canonical
    /// (매 저장의 해시 입력)과 화면·LAN 전송에 실린다. 숫자만 자르고 문자열을 빼 둔 자리다.
    /// 잘린 키는 어떤 실제 키와도 안 맞아 진행도가 0으로 읽히고 다음 기록에서 갱신된다.
    func testOversizedStringsFromASaveAreClampedAtTheBoundary() {
        let long = String(repeating: "x", count: 100_000)
        var evil = CompanionState()
        evil.seasons.seasonKey = long
        evil.missions.dayKey = long
        evil.missions.weekKey = long
        evil.adventureWeekKey = long
        evil.lastAdventureBonusDate = long
        evil.lastCandyDate = long
        evil.activeSecondsDate = long
        evil.trainerName = long
        evil.gymBadges = [long]
        evil.gymLeagueBadges = [long]
        evil.active = MonState(baseID: 1, pathIDs: [1], plannedPathIDs: [1], stageIndex: 0,
                               usedAtStage: 0, rarity: .common, totalForms: 1, nickname: long)
        evil.boxedMons = [MonState(baseID: 2, pathIDs: [2], plannedPathIDs: [2], stageIndex: 0,
                                   usedAtStage: 0, rarity: .common, totalForms: 1, nickname: long)]

        let s = SaveTransfer.sanitized(evil)

        for key in [s.seasons.seasonKey, s.missions.dayKey, s.missions.weekKey, s.adventureWeekKey,
                    s.lastAdventureBonusDate, s.lastCandyDate, s.activeSecondsDate] {
            XCTAssertEqual(key.count, SaveTransfer.maxKeyLength)
        }
        XCTAssertEqual(s.trainerName.count, SaveTransfer.maxNameLength)
        XCTAssertEqual(s.active?.nickname?.count, SaveTransfer.maxNameLength)
        XCTAssertEqual(s.boxedMons.first?.nickname?.count, SaveTransfer.maxNameLength,
                       "박스 개체도 같은 경계를 지난다 — 활성만 자르면 부류가 반만 막힌다")
        XCTAssertEqual(s.gymBadges.first?.count, SaveTransfer.maxNameLength)
        XCTAssertEqual(s.gymLeagueBadges.first?.count, SaveTransfer.maxNameLength)
        XCTAssertLessThan(SaveTransfer.canonicalString(s).count, 1_000,
                          "해시 입력이 세이브 한 장으로 무한히 커지면 매 저장이 그만큼 느려진다")
    }

    /// [설계 못박기] 불러오기는 **무결성 검사를 지나지 않는다** — 사용자가 고른 파일은 이 기기 서명을
    /// 가질 수 없다. 그래서 `isTampered` 의 구버전 면제 구멍(`integrityVersion` 을 낮게 써 넣으면 검사
    /// 면제)을 막아도 **조작 상한은 그대로다**: 같은 이득이 불러오기로 늘 열려 있다. 반대로 버전 하한을
    /// 세이브 밖에 두면 다운그레이드 사용자의 정상 세이브만 초기화된다. 그래서 그 구멍은 막지 않는다.
    func testImportIsNotSubjectToTheIntegrityCheck() throws {
        var crafted = CompanionState()
        crafted.starPieces = 999_999
        crafted.integrityVersion = SaveTransfer.integrityVersion
        crafted.integrity = "deadbeef"   // 이 기기 해시와 맞지 않는 서명
        XCTAssertTrue(SaveTransfer.isTampered(crafted), "같은 상태가 로컬 파일이면 조작으로 잡힌다")

        let data = try SaveTransfer.encode(state: crafted, appVersion: "2.9.0",
                                           deviceName: "Other", now: transferNow)
        let store = store(at: tempURL("crafted"))
        try store.applySave(try SaveTransfer.decode(data))

        XCTAssertEqual(store.state.starPieces, 999_999, "불러오기는 서명을 보지 않는다 — 의도된 설계")
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

    /// 조건부 세그먼트를 **전부 켠** 상태에서 canonical 이 내보내는 접두 어휘를 동결한다.
    ///
    /// 위 `testDefaultStateCanonicalFormIsFrozen` 은 기본값만 본다 — 조건부 세그먼트는 기본값
    /// canonical 에 애초에 없으므로, 돌봄(`care`·`care2`·`health`·`disc`·`sleep`)을 통째로 지웠을 때
    /// 아무것도 걸리지 않았다. 그 순간 이미 배포된 세이브의 서명은 이 빌드가 재현할 수 없는 문자열이
    /// 되고, `integrityVersion` 을 안 올리면 정상 사용자가 조작 판정으로 진행을 잃는다.
    ///
    /// 값이 아니라 **접두 집합**을 고정하는 이유: 값을 통째로 박으면 무관한 값 변경마다 깨져 fixture
    /// 유지비가 가드값을 넘는다. 열거형 rawValue 처럼 값에서 나온 토큰도 같이 얼어붙는데 이건 의도한
    /// 것이다 — rawValue 를 바꾸는 것도 기존 서명을 못 맞추게 만드는 같은 부류의 변경이다.
    func testEveryConditionalCanonicalSegmentPrefixIsFrozen() {
        let prefixes = Set(SaveTransfer.canonicalString(fullyPopulatedState())
            .components(separatedBy: "|")
            .map { String($0.prefix(while: { $0.isLowercase })) })

        XCTAssertEqual(prefixes, Self.frozenCanonicalPrefixes, """
                       canonical 의 세그먼트 어휘가 바뀌었다. 세그먼트를 지웠거나 접두를 바꿨다면
                       **integrityVersion 을 올려라** — 안 올리면 그 세그먼트가 들어 있던 기존 세이브가
                       전부 조작 판정을 받는다. 세그먼트를 새로 추가한 것이라면(조건부 append) 이 집합에
                       더하면 된다.
                       """)
    }

    /// 위 가드의 기대값. 목록을 본문 밖에 두는 이유는 실패 메시지에서 diff 가 읽히게 하기 위해서다.
    private static let frozenCanonicalPrefixes: Set<String> = [
        // 세그먼트 접두 — 하나라도 사라지면 이미 배포된 서명을 재현할 수 없다.
        "v", "u", "sp", "pc", "eg", "br", "pr", "tp", "msd", "achfocus", "sn",
        "gbbrock", "glbbug", "shc", "fe", "fer", "ef", "ab", "wk", "wc", "tier", "cand", "inv",
        "adv", "ah", "bh", "act", "box", "dex", "dg", "cf", "sec",
        // 값에서 나온 토큰 — fixture 가 고정하므로 결정적이다. 열거형 rawValue 변경도 기존 서명을
        // 깨는 같은 부류라 일부러 얼려 둔다. `""` 는 숫자로만 된 이어붙임 조각.
        "", "w", "scfalse", "false", "forest", "free", "common"
    ]

    /// 조건부 append 를 **전부 켜는** 최소 상태. 값 자체는 의미가 없고 "기본값이 아니다"만 만족하면
    /// 된다 — 접두 어휘만 보는 가드라 값이 커질수록 fixture 유지비만 는다.
    private func fullyPopulatedState() -> CompanionState {
        var s = CompanionState()
        s.battleRank = BattleRank(points: 10)
        s.pendingRanked = PendingRankedBattle(stake: 5, opponent: BattleRank(points: 1))
        s.trainer.points = 7
        s.missions.dayKey = "1"
        s.achievements.counts["focus"] = 1
        s.seasons.seasonKey = "1"
        s.gymBadges = ["brock"]
        s.gymLeagueBadges = ["bug"]
        s.shinyEggCharges = 1
        s.focusEggs = 1
        s.focusEggReadyDates = [Date(timeIntervalSince1970: 0)]
        s.adventure = AdventureRun(zone: .forest, startedAt: Date(timeIntervalSince1970: 0),
                                   endsAt: Date(timeIntervalSince1970: 60), companionSpeciesID: 1)
        s.adventureHistory = [AdventureRecord(id: UUID(), zone: .forest, companionSpeciesID: 1,
                                              completedAt: Date(timeIntervalSince1970: 0),
                                              stardust: 1, foundRareCandy: false)]
        s.battleHistory = [BattleRecord(playedAt: Date(timeIntervalSince1970: 0), mode: .freeForAll,
                                        participantCount: 2, won: false, reward: 1, opponentNames: [])]
        s.active = populatedMon(1)
        s.boxedMons = [populatedMon(2)]
        s.dex = [DexEntry(baseID: 1, finalID: 1, chainOrder: [1], rarity: .common,
                          caughtAt: Date(timeIntervalSince1970: 0))]
        return s
    }

    private func populatedMon(_ id: Int) -> MonState {
        MonState(baseID: id, pathIDs: [id], stageIndex: 0, usedAtStage: 0,
                 rarity: .common, totalForms: 1, names: [id: ["en": "P\(id)"]])
    }

    /// [부류 가드] 서명 밖에 남은 필드는 **자유롭게 고칠 수 있는 필드다.** 미결 랭크전의 상대 랭크가
    /// 그랬다 — 패배 LP 는 `apply(win:false)` 의 `tier > opponent.tier` 로 결정되므로 상대를 최고
    /// 티어로 고쳐 두면 이탈이 LP 무손실이 된다. 에스크로가 막으려던 "지고 있으면 앱 종료"가 그대로
    /// 돌아오므로, 판돈만 서명하고 상대 랭크를 빼 두면 가드가 없는 것과 같다.
    func testThePendingEscrowSignatureCoversTheOpponentRank() {
        var state = CompanionState()
        state.pendingRanked = PendingRankedBattle(stake: 5_000, opponent: BattleRank(points: 0))
        var tampered = state
        tampered.pendingRanked = PendingRankedBattle(stake: 5_000,
                                                    opponent: BattleRank(points: BattleRank.maximumPoints))

        XCTAssertNotEqual(SaveTransfer.canonicalString(state), SaveTransfer.canonicalString(tampered),
                          "상대 랭크를 고치면 서명이 달라져야 한다")
        XCTAssertNotEqual(SaveTransfer.integrityHash(state), SaveTransfer.integrityHash(tampered))
        // 대조군: 에스크로가 없는 세이브는 아무것도 붙이지 않는다(구버전 서명 호환).
        XCTAssertFalse(SaveTransfer.canonicalString(CompanionState()).contains("|pr"))
    }

    /// 에스크로 판돈은 **판돈 상한**에서 자른다. 일반 수치 상한(10^15)까지 허용하면 승리 정산의
    /// `escrowed * 2` 가 세이브 한 장으로 별의조각을 찍어낸다.
    func testAnImportedEscrowIsClampedToTheStakeCeiling() {
        var state = CompanionState()
        state.pendingRanked = PendingRankedBattle(stake: SaveTransfer.maxTokenValue,
                                                  opponent: BattleRank(points: 0))

        let clean = SaveTransfer.sanitized(state)

        XCTAssertEqual(clean.pendingRanked?.stake, BattleRank.maximumStake)
        XCTAssertEqual(SaveTransfer.sanitized({
            var s = CompanionState()
            s.pendingRanked = PendingRankedBattle(stake: 5_000, opponent: BattleRank(points: 0))
            return s
        }()).pendingRanked?.stake, 5_000, "정상 판돈은 그대로 통과한다")
    }

    // MARK: 필드 부류 (딥리뷰 M-g)

    /// 돌봄을 지우며 canonical 구성이 바뀌었다 — 그 순간 **이미 배포된 세이브의 서명은 이 빌드가
    /// 재현할 수 없는 문자열**이 된다(돌봄 세그먼트가 빠지므로). `integrityVersion` 을 올려 두지
    /// 않으면 그 세이브 전부가 조작 판정을 받아, 정상 사용자가 자기 진행을 잃는다.
    ///
    /// 그래서 이 가드는 "구서명이 안 맞는다"가 아니라 **"직전 배포 버전으로 찍힌 세이브가 면제된다"**
    /// 를 본다. 리터럴 7 은 돌봄이 canonical 에 들어 있던 마지막 버전이고, 이 상수를 안 올린 채
    /// canonical 만 바꾸면 여기서 걸린다(고의 주입으로 확인 — 7 인 상태에서 실패한다).
    func testASaveStampedByTheReleaseThatStillHadCareIsNotBlamedAsTampered() {
        var legacy = CompanionState()
        legacy.integrityVersion = 7
        legacy.integrity = "signature-computed-with-care-segments"
        XCTAssertFalse(SaveTransfer.isTampered(legacy))

        // 대조군 — 이 빌드가 찍은 세이브는 면제 대상이 아니다. 서명을 손대면 조작으로 잡혀야 한다.
        var current = SaveTransfer.signed(CompanionState())
        XCTAssertFalse(SaveTransfer.isTampered(current))
        current.integrity = "tampered"
        XCTAssertTrue(SaveTransfer.isTampered(current))
    }

    /// [딥리뷰 M-g] 이전 시 필드 분류가 산문 규약뿐이라, 새 필드가 추가되면 아무 판단 없이 "진행"으로
    /// 딸려 들어간다(`language` 가 실제로 그랬다). 필드 목록을 테스트로 고정해 **분류를 강제**한다.
    func testEveryCompanionStateFieldIsClassifiedForTransfer() {
        // 진행: 어느 기기에서든 참. eggTier(알 등급 보증)도 산 물건이라 기기를 옮겨도 따라간다.
        let progress: Set<String> = ["economyVersion", "usedSinceInstall", "spentTokens", "eggUsage",
                                     "eggTier", "pendingHatchID", "trainerName", "starterChosen",
                                     "starterCandidates", "active", "dex", "collectedFinals", "gymBadges", "gymLeagueBadges", "shinyEggCharges", "inventory",
                                     // 기술머신도 산 물건이다 — `inventory` 와 같은 부류라 기기를 옮겨도 따라간다.
                                     "technicalMachines",
                                     // 트레이너 꾸미기 — 산 의상과 착용 상태는 진행이라 그대로 따라간다.
                                     "outfit", "ownedOutfits", "battleRepresentativeID",
                                     "activeSecondsTotal", "activeSecondsToday", "activeSecondsDate", "boxedMons",
                                     // 즐겨찾기는 그 개체에 건 잠금이다 — 개체가 따라가는데 잠금만
                                     // 두고 오면 옮긴 기기에서 아끼던 포켓몬이 그냥 놓아줄 수 있게 된다.
                                     "favoriteMonIDs",
                                     "battleRank", "trainer", "missions", "achievements", "seasons", "battleHistory",
                                     // 진행 중인 랭크전 에스크로 — 이미 지갑에서 빠져나간 돈이다.
                                     // 기기를 옮길 때 안 따라가면 배틀 중에 이전해서 판돈을 챙길 수 있다.
                                     "pendingRanked",
                                     // 체육관 도전 기록은 전적(`battleHistory`)과 같은 부류다 —
                                     // 내 기록이라 기기를 옮겨도 따라간다.
                                     "gymDefenseLog",
                                     "adventure", "adventureHistory",
                                     "adventureWeekKey", "weeklyAdventureCount", "focusEggs", "focusEggReadyDates", "eggFragments",
                                     "starPieces", "forcedResetVersion", "integrityVersion", "lastAdventureBonusDate"]
        // 로컬 장부: 이 기기의 시계 기준값·서명 → 새 기기 기준 재설정(저장 시 재서명).
        // 체육관 관장 자격도 같은 부류다 — 이 기기가 호스팅 중인 살아있는 역할이라, 따라가면
        // 옮겨간 기기가 열지도 않은 체육관의 관장을 자처하고 방어팀 넷이 거기서 잠긴다.
        let deviceLedger: Set<String> = ["lastTickAt", "integrity", "gymLeadership"]
        // 계정 원장(로컬 날짜 문자열 — 비교 가능): 더 최근 값 유지.
        // 웨이브 런 실적도 병합 대상이다 — 소모되지 않는 누적이라 축별로 큰 값을 남긴다
        // (한쪽을 고르면 다른 기기에서 세운 최고 기록이 사라진다).
        // 체육관 방어 보상의 일일 원장도 같은 부류다 — 같은 날이면 많이 받은 쪽을 남겨야
        // 세이브를 주고받는 것만으로 하루 상한이 되살아나지 않는다.
        let accountLedger: Set<String> = ["lastCandyDate", "waveRun",
                                          "gymDefenseRewardDate", "gymDefenseRewardToday"]
        // 기기 환경설정: 현재 기기 값 유지.
        let devicePreference: Set<String> = ["language"]

        let classified = progress.union(deviceLedger).union(accountLedger).union(devicePreference)
        let actual = Set(Mirror(reflecting: CompanionState()).children.compactMap(\.label))
        XCTAssertEqual(actual, classified, """
            CompanionState 필드가 바뀌었다. 세이브 이전에서 이 필드가 무엇인지 정하고 목록을 갱신하라 —
            진행(그대로) / 로컬 장부(새 기기 기준 재설정) / 계정 원장(병합) / 기기 환경설정(현재 값 유지).
            """)
    }

    /// `CompanionState` 는 디코더만 손으로 쓰고 인코더는 합성이다. 새 필드를 더하면서 그 손글씨
    /// 디코더에 줄을 안 넣으면 **쓰이기는 하고 읽히지는 않는** 필드가 된다 — 컴파일도 되고 인코딩
    /// 왕복 테스트도 통과하며(둘 다 기본값), 앱에서만 "설정했는데 재시작하면 사라진다"로 나타난다.
    /// 실제로 즐겨찾기를 그렇게 한 번 놓쳤다. 필드 이름이 디코더에 `forKey: .이름` 으로 등장하는지
    /// 소스에서 직접 확인한다 — `forKey:` 는 이 파일에서 디코더만 쓴다.
    func testEveryCompanionStateFieldIsReadByTheHandWrittenDecoder() throws {
        let model = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/PokeTokenBar/Core/CompanionModel.swift")
        let source = try String(contentsOf: model, encoding: .utf8)
        // 경로가 깨지면 빈 문자열을 훑고 조용히 통과한다 — 그걸 막는 단언.
        XCTAssertTrue(source.contains("struct CompanionState"), "CompanionModel.swift 를 못 찾았다")

        let fields = Mirror(reflecting: CompanionState()).children.compactMap(\.label)
        XCTAssertGreaterThan(fields.count, 20, "필드 목록이 비었다 — 가드가 무력해진다")
        let unread = fields.filter { !source.contains("forKey: .\($0)") }.sorted()
        XCTAssertEqual(unread, [], """
            CompanionState 의 손글씨 init(from:) 이 이 필드를 읽지 않는다 — 저장은 되는데 로드에서
            기본값으로 돌아간다. 디코더에 `c.lenient(...)` 줄을 추가해라.
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
