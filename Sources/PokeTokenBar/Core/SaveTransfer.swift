import Foundation

/// 기기 교체용 세이브 이전 — 상태를 봉투에 담아 내보내고, 다른 기기에서 들여온다.
///
/// `CompanionState` 를 그대로 파일로 쓰지 않고 봉투로 감싸는 이유: 상태 디코딩이 의도적으로
/// 관대해서(`lenient*` — 한 필드가 깨져도 도감 전체를 날리지 않으려고) **아무 JSON 이나 넣어도
/// 전 필드가 기본값으로 흡수되며 "성공"한다.** 봉투 없이는 남의 JSON 을 골라도 불러오기가
/// 성공한 뒤 도감이 빈 상태가 되어, 사용자에겐 "앱이 내 진행을 지웠다"로 보인다.
/// 봉투의 `format`/`schema` 는 관대 디코딩 대상이 아니라(기본값 없음) 이 오인을 먼저 차단한다.
struct SaveEnvelope: Codable, Sendable {
    static let formatID = "poketokenbar.save"
    /// 2 = 방치형 경제(별의모래). 구버전 앱이 새 세이브를 토큰 경제로 오독하지 않게 올렸다 —
    /// 구버전은 `newerSchema` 로 거절하고, 이 빌드는 schema 1(토큰 시절)도 받아 리셋 마이그레이션한다.
    static let schemaVersion = 2

    var format: String
    var schema: Int
    var appVersion: String
    var exportedAt: Date
    var sourceDevice: String
    var state: CompanionState
}

/// 봉투의 앞부분만 읽는 최소 구조 — 본문(`state`)이 상위 스키마라 못 읽히더라도 "새 버전 세이브"임을
/// 알아보고 정확한 안내를 하기 위해서다. 이게 없으면 상위 스키마 파일이 "세이브 파일이 아니에요"로
/// 뜬다(사용자는 앱을 업데이트하면 된다는 걸 모른다).
private struct SaveHeader: Decodable {
    let format: String
    let schema: Int
}

/// 덮어쓰기 확인에 쓰는 요약 — "무엇이 대체되는지"를 수치로 보여주기 위한 값.
/// (경고문에 대상을 구체적으로 적는 것이 일반적인 "정말 진행할까요?" 보다 사용자에게 유용하다.)
struct SaveSummary: Equatable, Sendable {
    var dexCount: Int
    var lifetimeTokens: Int

    init(state: CompanionState) {
        dexCount = state.dex.count
        lifetimeTokens = state.usedSinceInstall
    }
}

enum SaveTransferError: Error, Equatable {
    /// 봉투가 아니거나 다른 앱의 JSON.
    case notASaveFile
    /// 이 빌드보다 새 스키마 — 상위 버전에서 만든 세이브.
    case newerSchema(found: Int, supported: Int)
    /// 세이브로 보기엔 과하게 큰 파일 — 파싱이 메인스레드를 오래 잡는다.
    case fileTooLarge(bytes: Int, limit: Int)
    /// 덮어쓰기 전 백업을 못 남겼다 — 확인창이 약속한 복구 수단이 없으므로 불러오기를 중단한다.
    case backupFailed
}

/// 불러오기 확인창의 버튼 배치 규칙. AppKit 밖으로 빼둔 이유는 이 규칙이 **데이터 손실과 직결**되는데
/// `NSAlert` 구성은 XCTest 에서 도달할 수 없기 때문이다 — 두 줄이 뒤바뀌면 Return 한 키로 이 Mac 의
/// 진행이 대체되는데 잡을 자동 테스트가 없었다.
enum ImportConfirmPolicy {
    static let replaceButtonIndex = 0
    static let cancelButtonIndex = 1

    /// 기본 버튼(Return)은 **취소**여야 한다. 파괴적 동작을 기본으로 두지 않는다.
    static func keyEquivalent(forButtonAt index: Int) -> String {
        index == cancelButtonIndex ? "\r" : ""
    }
}

enum SaveTransfer {
    /// canonical 구성이 바뀌면 **반드시 올린다** — 낮은 버전 서명은 조작 검사에서 면제되니
    /// (`isTampered`) 구서명이 새 canonical 과 안 맞아 리셋되는 일이 없다.
    /// 조건부 append 로 버티는 건 **이전 배포에 없던 필드**뿐이다(구세이브는 항상 기본값이라
    /// 세그먼트가 안 붙는다). 이미 배포된 필드를 넣으면 값이 든 정상 세이브가 전부 조작 판정되므로
    /// 버전 상향이 유일한 방어다 — `gymBadges`·`shinyEggCharges` 때문에 6 → 7.
    static let integrityVersion = 7
    /// 2026-08-13 게임 구조 개편 배포: 모든 기존 진행 데이터를 한 번 완전 초기화한다.
    static let forcedResetVersion = 1
    /// 세이브 파일 크기 상한. 정상 세이브는 수 KB 이고 도감이 가득 차도 수백 KB 를 넘지 않는다.
    /// 상한이 없으면 거대한 JSON 이 메인스레드 파싱을 수 초간 잡는다(실측: 39MB → 약 1.8초 정지).
    static let maxFileBytes = 8 * 1024 * 1024

    /// 세이브에 들어올 수 있는 수치의 상한 — 실사용(수십억)의 10만 배라 정상 진행을 자르지 않으면서,
    /// 이 값끼리 더하고 빼도 Int64 범위 안에 머문다.
    static let maxTokenValue = 1_000_000_000_000_000

    /// 내보내기 파일명 — 날짜가 들어가야 여러 번 내보내도 덮어쓰지 않는다.
    static func suggestedFileName(date: Date) -> String {
        "PokeTokenBar-Save-\(dayStamp(date)).json"
    }

    /// 백업 파일명 — 불러올 때마다 새 슬롯. 하나만 유지하면 두 번째 불러오기가 **원본**을 덮어써,
    /// "잘못 불러왔으니 되돌린다"는 바로 그 상황에서 되돌릴 대상이 사라진다.
    static func backupFileName(date: Date) -> String {
        "companion-state.pre-import-\(secondStamp(date)).json"
    }
    static let backupFilePrefix = "companion-state.pre-import-"
    /// 유지할 백업 개수 — 오래된 것부터 지운다.
    static let backupsToKeep = 5

    private static func stamp(_ date: Date, _ format: String) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = format
        return f.string(from: date)
    }
    private static func dayStamp(_ date: Date) -> String { stamp(date, "yyyy-MM-dd") }
    private static func secondStamp(_ date: Date) -> String { stamp(date, "yyyy-MM-dd-HHmmss") }

    static func encode(state: CompanionState, appVersion: String, deviceName: String, now: Date) throws -> Data {
        let envelope = SaveEnvelope(format: SaveEnvelope.formatID,
                                    schema: SaveEnvelope.schemaVersion,
                                    appVersion: appVersion,
                                    exportedAt: now,
                                    sourceDevice: deviceName,
                                    state: state)
        let encoder = JSONEncoder()
        // 사람이 열어봤을 때 읽히도록(무엇이 옮겨가는지 확인 가능) — 4KB 라 크기는 무의미.
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(envelope)
    }

    static func decode(_ data: Data) throws -> SaveEnvelope {
        guard data.count <= maxFileBytes else {
            throw SaveTransferError.fileTooLarge(bytes: data.count, limit: maxFileBytes)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        // 헤더를 먼저 읽는다 — 본문이 상위 스키마라 못 읽혀도 "새 버전 세이브"로 정확히 안내하기 위해.
        guard let header = try? decoder.decode(SaveHeader.self, from: data),
              header.format == SaveEnvelope.formatID else {
            throw SaveTransferError.notASaveFile
        }
        guard header.schema <= SaveEnvelope.schemaVersion else {
            throw SaveTransferError.newerSchema(found: header.schema, supported: SaveEnvelope.schemaVersion)
        }
        guard var envelope = try? decoder.decode(SaveEnvelope.self, from: data) else {
            throw SaveTransferError.notASaveFile   // 같은 스키마인데 못 읽힘 = 손상
        }
        envelope.state = sanitized(envelope.state)
        return envelope
    }

    /// 신뢰경계 값 정규화 — 세이브는 **앱 밖에서** 온다(손편집·전송 중 손상·다른 빌드).
    ///
    /// `CompanionState` 의 디코딩은 의도적으로 관대해서(한 필드가 깨져도 도감을 안 날리려고) 말이 안 되는
    /// 값도 통과시킨다. 그 값이 그대로 저장되면 이후 산술이 Swift 오버플로 트랩으로 **프로세스를 죽이고,
    /// 재기동해도 같은 파일을 읽어 다시 죽는다** — 사용자가 파일을 손으로 지우기 전까지 앱을 못 쓴다
    /// (`load()` 의 `.corrupt` 자동복구는 디코드가 *성공*하므로 발동하지 않는다).
    ///
    /// 다운스트림 산술 지점마다 막으면 새 지점이 생길 때마다 재발하므로, 값이 **들어오는 경계 한 곳**에서
    /// 정규화한다. 대상은 실제로 산술에 쓰이는 필드뿐이다 — 도감·인벤토리 항목은 잘라내지 않는다(데이터 손실).
    static func sanitized(_ state: CompanionState) -> CompanionState {
        guard state.forcedResetVersion >= forcedResetVersion else {
            AppLog.write("forced save reset: v\(state.forcedResetVersion) → v\(forcedResetVersion)")
            return CompanionState()
        }
        func clampToken(_ v: Int) -> Int { min(max(0, v), maxTokenValue) }
        var s = migratedToIdleEconomy(state)
        s.usedSinceInstall = clampToken(s.usedSinceInstall)
        s.spentTokens = clampToken(s.spentTokens)
        s.starPieces = clampToken(s.starPieces)
        s.battleRank.points = BattleRank.clamped(s.battleRank.points)
        // 에스크로도 세이브에 실려 오는 수치다 — 산술(환급·2배 지급)에 쓰이므로 경계에서 자른다.
        // 상한은 일반 수치 상한이 아니라 **판돈 상한**이다 — 승리 정산이 `escrowed * 2` 를 지급하므로
        // 10^15 까지 허용하면 세이브 한 장으로 별의조각을 찍을 수 있다(정상 최대는 45,000).
        if let pending = s.pendingRanked {
            s.pendingRanked = PendingRankedBattle(
                stake: min(BattleRank.maximumStake, clampToken(pending.stake)),
                opponent: pending.opponent)
        }
        s.trainer.points = min(TrainerLevel.maximumPoints, max(0, s.trainer.points))
        // 카탈로그에서 사라진 미션의 잔재를 버리고 진행도를 목표에서 클램프한다 — 클램프된 값은 곧 완료 상태라
        // 손편집으로 목표를 넘겨도 보상이 다시 나오지 않는다.
        s.missions.normalize()
        // 업적도 경계에서 한 번만 자른다 — 사라진 트랙의 잔재를 버리고 마지막 문턱으로 클램프한다.
        // 클램프된 값이 곧 최고 단계라 손편집으로 넘겨도 보상이 다시 나오지 않는다.
        s.achievements.normalize()
        // 시즌도 같은 자리에서 자른다 — 저장된 시즌의 세트에 없는 키를 버리고 목표에서 클램프한다.
        s.seasons.normalize()
        s.focusEggs = min(max(0, s.focusEggs), 999)
        s.focusEggReadyDates = Array(s.focusEggReadyDates.sorted().prefix(s.focusEggs))
        s.eggFragments = min(max(0, s.eggFragments), 9)
        s.weeklyAdventureCount = min(max(0, s.weeklyAdventureCount), 10)
        s.eggUsage = clampToken(s.eggUsage)
        // 알 보증은 "지금 품고 있는 알"에만 붙는 값이라 활성 포켓몬과 공존할 수 없다. 손편집·구버전
        // 조합으로 둘 다 들어오면 그 보증이 다음 알로 새어 영구 프리미엄이 되므로 여기서 떨군다.
        // 그 보증으로 미리 뽑아둔 종(pendingHatchID)도 함께 버린다 — 보증만 지우면 졸업 후 받는 **무료**
        // 알이 그 pre-roll 로 부화해, 아무도 사지 않은 프리미엄 결과가 나온다.
        if s.active != nil { s.eggTier = nil; s.pendingHatchID = nil }
        // 만족시킬 수 없는 보증은 알을 영구히 못 깨게 만든다 — 전설은 capture_rate 로 표현할 수 없어
        // (captureRateCeiling == nil) 두 롤 경로 모두 후보를 0개로 만들고, 부화가 없으니 보증도 소비되지
        // 않으며, 새 알 구매는 `hasActive` 게이트에 막혀 빠져나갈 수단이 없다. 디코드는 *성공*하므로
        // load() 의 .corrupt 복구도 안 걸려 파일을 손으로 지우기 전엔 앱을 못 쓴다.
        // 관대 디코딩은 모르는 rawValue 만 걸러낼 뿐 **아는데 만족 불가능한 값**은 그대로 통과시킨다.
        if s.eggTier?.captureRateCeiling == nil { s.eggTier = nil }
        if var active = s.active {
            active.usedAtStage = clampToken(active.usedAtStage)
            // totalForms 는 `kk * (kk + 1)` 형태로 쓰여(PokemonBalance.phaseThreshold) 큰 값이 그 자체로 트랩이다.
            active.totalForms = min(max(1, active.totalForms), 12)
            active.stageIndex = min(max(0, active.stageIndex), max(0, active.pathIDs.count - 1))
            // 박스 개체만 자르고 활성 개체를 빼 두면, 손편집으로 들어온 큰 값에 이상한 사탕 XP 를
            // 더하는 순간 Swift 오버플로 트랩으로 프로세스가 죽는다(#81 부류 스윕).
            active.levelExperience = min(max(0, active.levelExperience), PokemonBalance.maxLevelExperience)
            s.active = active
        }
        s.boxedMons = Array(s.boxedMons.prefix(100)).map { mon in
            var m = mon
            m.levelExperience = min(max(0, m.levelExperience), PokemonBalance.maxLevelExperience)
            m.learnedMoves = Array(m.learnedMoves.prefix(4))
            return m
        }
        // 인벤토리 개수 클램프 — 손편집으로 999999개 같은 값이 들어와도 상한을 둔다(조작 방어 2차).
        s.inventory = s.inventory.reduce(into: [:]) { r, e in r[e.key] = min(max(0, e.value), 999) }
        s.care.hunger = min(max(0, s.care.hunger), 100)
        s.care.happiness = min(max(0, s.care.happiness), 100)
        s.care.energy = min(max(0, s.care.energy), 100)
        s.care.affection = min(max(0, s.care.affection), 100)
        s.care.hygiene = min(max(0, s.care.hygiene), 100)
        s.care.messCount = min(max(0, s.care.messCount), 3)
        s.care.discipline = min(max(0, s.care.discipline), 100)
        s.care.careMistakes = min(max(0, s.care.careMistakes), 99_999)
        if s.care.pendingNeed == nil { s.care.needDeadline = nil }
        if !s.care.isSleeping { s.care.sleepStartedAt = nil }
        if let adventure = s.adventure,
           adventure.endsAt <= adventure.startedAt ||
           adventure.endsAt.timeIntervalSince(adventure.startedAt) > 24 * 60 * 60 {
            s.adventure = nil
        }
        s.adventureHistory = Array(s.adventureHistory
            .filter { (1...10_000).contains($0.companionSpeciesID) && (0...maxTokenValue).contains($0.stardust) }
            .sorted { $0.completedAt > $1.completedAt }.prefix(30))
        s.battleHistory = Array(s.battleHistory
            .filter { (2...4).contains($0.participantCount) && (0...maxTokenValue).contains($0.reward) }
            .sorted { $0.playedAt > $1.playedAt }.prefix(30))
        s.battleHistory = s.battleHistory.map { record in
            var record = record
            record.opponentNames = Array(record.opponentNames.prefix(3)).map {
                String($0.trimmingCharacters(in: .whitespacesAndNewlines).prefix(30))
            }.filter { !$0.isEmpty }
            return record
        }
        // 전설 스타터 리셋 — 첫 동반자(dex 비어 있음)가 전설이면 스타터를 다시 고르게 한다.
        // (구버전 스타터 롤이 전설을 허용했을 때의 개체. 알/졸업으로 얻은 전설은 dex 가 비지 않아 유지된다.)
        if let a = s.active, a.rarity == .legendary, s.dex.isEmpty, s.starterChosen {
            s.active = nil
            s.starterChosen = false
            s.starterCandidates = []
            s.eggUsage = 0
            s.eggTier = nil
            s.pendingHatchID = nil
        }
        // 후보에 전설·범위 밖이 섞였으면(구버전·조작) 비워 재추첨하게 한다.
        if s.starterCandidates.contains(where: { StarterRules.isLegendary($0) || !StarterRules.genRange.contains($0) }) {
            s.starterCandidates = []
        }
        return s
    }

    // MARK: 세이브 무결성 (손편집 조작 방어)

    /// 조작에 민감한 필드의 canonical 문자열 → 기기 시드 FNV 해시. `integrity` 자신은 입력에서 제외.
    /// 손으로 JSON 을 고치면(재화·인벤토리·개체·도감) 이 해시가 안 맞아 로드 때 조작으로 판정된다.
    /// 기기 시드가 들어가 다른 기기·해시 알고리즘을 모르면 유효 서명을 못 만든다(캐주얼 편집 차단).
    static func integrityHash(_ s: CompanionState) -> String {
        String(fnv1a(canonicalString(s)), radix: 16)
    }

    /// 해시의 입력 원문. 해시가 아니라 이 문자열을 테스트에 노출하는 이유는 **조건부 append 규칙을
    /// 검사할 방법이 이것뿐**이기 때문이다 — 기본값 상태의 해시를 자기 자신과 비교하면 무조건 append
    /// 로 바뀌어도 양쪽이 똑같이 바뀌어 그대로 통과한다(그 형태의 테스트 3개가 실제로 아무것도 못 걸렀다).
    static func canonicalString(_ s: CompanionState) -> String {
        var p: [String] = []
        p.append("v\(s.economyVersion)")
        p.append("u\(s.usedSinceInstall)"); p.append("sp\(s.spentTokens)"); p.append("pc\(s.starPieces)"); p.append("eg\(s.eggUsage)")
        if s.battleRank.points != 0 { p.append("br\(s.battleRank.points)") }
        // 구버전 서명 호환: 에스크로가 없으면(대부분) 아무것도 붙이지 않는다.
        // 상대 랭크도 서명에 넣는다 — 미결 배틀의 패배 LP 는 `apply(win:false)` 의 `tier > opponent.tier`
        // 로 결정되므로, 이 값이 서명 밖에 있으면 상대를 최고 티어로 고쳐 두는 것만으로 이탈이 무손실이
        // 된다(막으려던 "지고 있으면 앱 종료"가 그대로 돌아온다).
        if let pending = s.pendingRanked { p.append("pr\(pending.stake)|\(pending.opponent.points)") }
        // 구버전 서명 호환: 기본값(0)이면 아무것도 붙이지 않는다. 무조건 붙이면 트레이너 필드가
        // 없던 시절의 정상 세이브가 전부 조작으로 판정돼 진행이 초기화된다.
        if s.trainer.points != 0 { p.append("tp\(s.trainer.points)") }
        // 구버전 서명 호환: 기본값이면 아무것도 붙이지 않는다. 무조건 붙이면 미션 필드가 없던
        // 시절의 정상 세이브가 전부 조작으로 판정돼 진행이 초기화된다.
        if s.missions != MissionBoard() { p.append("ms\(s.missions.canonical)") }
        // 업적 카운터가 곧 단계 판정이다 — 서명 밖에 두면 값을 올려 적는 것만으로 보상을 받는다.
        // 조건부인 이유는 위 두 필드와 같다. 새 필드라 값이 든 기존 세이브가 없으니
        // `integrityVersion` 은 올리지 않는다(올리면 그 배포의 모든 세이브가 검사를 면제받는다).
        //
        // 접두는 `ac` 가 아니라 `ach` 다. 아래 활성 포켓몬이 `act` 를 쓰므로 `ac` 면 기본값 세이브의
        // `|act-` 가 업적 세그먼트로 읽힌다(`shc` 가 `sec` 를 피한 것과 같다). 위조가 되는 건
        // 아니지만 세그먼트 유무를 보는 테스트가 조용히 거짓이 된다.
        if s.achievements != AchievementLadder() { p.append("ach\(s.achievements.canonical)") }
        // 시즌 진행도도 서명에 넣는다 — 밖에 두면 목표 직전 값을 적어 넣는 것만으로 보상이 공짜다.
        // 조건부인 이유는 위 세 필드와 같고, 새 필드라 `integrityVersion` 은 올리지 않는다.
        //
        // 접두는 `s` 가 아니라 `sn` 이다. `s` 면 기본값 세이브의 `sp0`·`scfalse` 가 시즌 세그먼트로
        // 읽혀 세그먼트 유무를 보는 테스트가 조용히 거짓이 된다(`ach` 가 `ac` 를 피한 것과 같다).
        if s.seasons != SeasonBoard() { p.append("sn\(s.seasons.canonical)") }
        // 체육관 배지는 첫 승리 보상의 **유일한** 멱등 가드다(`recordGymVictory`) — 서명 밖에 있으면
        // 배지 키 한 줄을 지워 같은 체육관에서 알을 다시 받는다. 정렬 필수: `Set` 순회 순서는 실행마다
        // 달라 정렬하지 않으면 같은 상태가 다른 서명을 낸다. (아래 두 필드가 이미 배포분이라 버전을 올렸다.)
        if !s.gymBadges.isEmpty { p.append("gb" + s.gymBadges.sorted().joined(separator: ",")) }
        // 이로치 확정 부화 횟수 — 받은 시점과 쓰는 시점이 떨어져 있어 세이브에 남는다. 손으로 올리면
        // 확정 이로치가 공짜다. 접두 `sec` 는 아래 기기 시드가 이미 쓰고 있어 `shc` 를 쓴다.
        if s.shinyEggCharges != 0 { p.append("shc\(s.shinyEggCharges)") }
        if s.focusEggs != 0 { p.append("fe\(s.focusEggs)") }
        if !s.focusEggReadyDates.isEmpty {
            p.append("fer" + s.focusEggReadyDates.map { String($0.timeIntervalSince1970) }.joined(separator: ","))
        }
        p.append("ef\(s.eggFragments)|ab\(s.lastAdventureBonusDate)|wk\(s.adventureWeekKey)|wc\(s.weeklyAdventureCount)")
        p.append("tier\(s.eggTier?.rawValue ?? "-")"); p.append("sc\(s.starterChosen)")
        p.append("cand" + s.starterCandidates.map(String.init).joined(separator: ","))
        p.append("inv" + s.inventory.sorted { $0.key < $1.key }.map { "\($0.key):\($0.value)" }.joined(separator: ","))
        // 구버전 서명 호환: 새 필드가 완전히 기본값이면 기존 canonical 문자열을 유지한다.
        if s.care != PetCareState() {
            p.append("care\(Int(s.care.hunger))|\(Int(s.care.happiness))|\(Int(s.care.energy))")
        }
        if s.care.affection != 50 || s.care.careMistakes != 0 || s.care.pendingNeed != nil {
            p.append("care2\(Int(s.care.affection))|\(s.care.careMistakes)|\(s.care.pendingNeed?.rawValue ?? "-")")
        }
        if s.care.hygiene != 100 || s.care.isSick || s.care.messCount != 0 {
            p.append("health\(Int(s.care.hygiene))|\(s.care.isSick)|\(s.care.messCount)")
        }
        if s.care.discipline != 0 { p.append("disc\(Int(s.care.discipline))") }
        if s.care.isSleeping { p.append("sleep\(s.care.sleepStartedAt?.timeIntervalSince1970 ?? 0)") }
        if let run = s.adventure {
            p.append("adv\(run.id)|\(run.zone.rawValue)|\(run.startedAt.timeIntervalSince1970)|\(run.endsAt.timeIntervalSince1970)|\(run.companionSpeciesID)")
        }
        if !s.adventureHistory.isEmpty {
            p.append("ah" + s.adventureHistory.map { "\($0.id)|\($0.zone.rawValue)|\($0.stardust)|\($0.foundRareCandy)" }.joined(separator: ","))
        }
        if !s.battleHistory.isEmpty {
            p.append("bh" + s.battleHistory.map { "\($0.id)|\($0.mode.rawValue)|\($0.participantCount)|\($0.won)|\($0.reward)" }.joined(separator: ","))
        }
        if let a = s.active {
            p.append("act\(a.id)|\(a.baseID)|\(a.stageIndex)|\(a.usedAtStage)|\(a.rarity.rawValue)|\(a.isShiny)|\(a.totalForms)|\(a.nickname ?? "")|\(a.levelExperience)|\(a.learnedMoves.map(\.id))")
        } else { p.append("act-") }
        if !s.boxedMons.isEmpty {
            p.append("box" + s.boxedMons.map { "\($0.id):\($0.baseID):\($0.stageIndex):\($0.levelExperience)" }.joined(separator: ","))
        }
        p.append("dex" + s.dex.map { "\($0.baseID):\($0.finalID):\($0.rarity.rawValue)" }.sorted().joined(separator: ","))
        // 도감 목표는 수령 플래그가 없어 멱등 가드가 **진행도의 단조성**뿐이다(`DexGoals`). 진행도가 읽는
        // `isShiny`·`chainOrder`·`types` 는 위 dex 줄에 없어 손으로 내려 적으면 다음 졸업이 같은 보상을
        // 재지급한다. 원자 필드 대신 **파생 진행도 숫자**를 넣는다 — 목표 id 를 넣으면 카탈로그 조정
        // (`species50` → `40`)이 정상 세이브를 전부 조작 판정으로 만든다. 조건부라 빈 도감은 canonical 동결.
        let dexProgress = DexGoalKind.allCases.map { String(DexGoals.progress($0, in: s.dex)) }
        if dexProgress.contains(where: { $0 != "0" }) {
            p.append("dg" + dexProgress.joined(separator: "|"))
        }
        p.append("cf" + s.collectedFinals.sorted().joined(separator: ","))
        p.append("sec\(DeviceID.stableIdentifier())")
        return p.joined(separator: "|")
    }

    private static func fnv1a(_ s: String) -> UInt64 {
        var h: UInt64 = 0xcbf29ce484222325
        for b in s.utf8 { h ^= UInt64(b); h = h &* 0x100000001b3 }
        return h
    }

    /// 저장 직전 서명 — integrity 를 현재 상태 해시로 채운 사본을 반환(원본 불변).
    static func signed(_ state: CompanionState) -> CompanionState {
        var s = state
        s.integrityVersion = integrityVersion
        s.integrity = integrityHash(s)
        return s
    }

    /// 서명이 있는데 안 맞는가(= 손편집됨). 서명 전(빈 값)·구버전은 조작으로 보지 않는다.
    static func isTampered(_ state: CompanionState) -> Bool {
        guard state.integrityVersion >= integrityVersion else { return false }
        return !state.integrity.isEmpty && state.integrity != integrityHash(state)
    }

    /// 조작 감지 시 초기화 — 언어·트레이너 이름(코스메틱)만 남기고 진행·도감·인벤토리를 전부 리셋.
    /// 스타터부터 다시 고르게 해 조작 이득을 무효화한다.
    static func resetForTamper(_ state: CompanionState) -> CompanionState {
        var fresh = CompanionState()
        fresh.language = state.language
        fresh.trainerName = state.trainerName
        return fresh
    }

    /// 토큰 경제 세이브(economyVersion < currentVersion)의 리셋 마이그레이션 — 도감·수집·언어만
    /// 계승하고 진행(활성 개체·알·재화·인벤토리)은 새로 시작한다(2026-08-13 결정). 토큰 누적과
    /// 별의모래는 단위가 달라 환산하지 않는다. 로드/불러오기 공통 경계(sanitized)에서 호출된다.
    static func migratedToIdleEconomy(_ state: CompanionState) -> CompanionState {
        guard state.economyVersion < IdleEconomy.currentVersion else { return state }
        var fresh = CompanionState()
        fresh.dex = state.dex
        fresh.collectedFinals = state.collectedFinals
        fresh.language = state.language
        AppLog.write("economy migration: v\(state.economyVersion) → v\(IdleEconomy.currentVersion) — progress reset, dex(\(state.dex.count)) preserved")
        return fresh
    }

    /// 다른 기기에서 온 상태를 **이 기기 기준으로 재정렬**한다.
    ///
    /// `CompanionState` 의 필드는 이전 관점에서 세 부류다.
    ///  - **진행**: 어느 기기에서든 참(`usedSinceInstall`·`dex`·`inventory`·`active`·`eggUsage`·`eggTier`…)
    ///    → 그대로. 알 보증(`eggTier`)은 산 물건이지 이 기기의 장부가 아니라 기기를 옮겨도 따라간다.
    ///  - **로컬 장부**: 이 기기의 시계 기준값(`lastTickAt`) → 리셋. 옛 기기의 시각을 그대로 들여오면
    ///    다음 틱이 그 시각과의 경과분(캡 적용)을 이 기기 가동 시간으로 오인한다.
    ///  - **기기 환경설정**: 진행이 아니라 이 기기에서 보는 방식(`language`) → **현재 기기 값을 지킨다**.
    ///    일본어 Mac 의 세이브가 영어 Mac 의 UI 언어를 바꾸면 안 된다.
    static func rebasedForThisDevice(_ imported: CompanionState,
                                     current: CompanionState) -> CompanionState {
        var state = imported
        state.language = current.language
        state.lastTickAt = nil
        // 일일 사탕 원장은 로컬 날짜 문자열이라 기기 간 비교 가능 — 더 최근 값을 남겨 재지급을 막는다.
        state.lastCandyDate = max(imported.lastCandyDate, current.lastCandyDate)
        return state
    }
}
