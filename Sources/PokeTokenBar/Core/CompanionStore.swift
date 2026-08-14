import Foundation
import Observation
import UserNotifications

/// 게임 상태의 출처. 앱이 켜져 있는 동안 시간이 별의모래로 적립돼(tick) 포켓몬을 진화시키고,
/// 최종체 + 추가 임계 도달 시 도감(라인 전체)에 보존 + 새 알. 진화 트리/희귀도/이름은
/// PokeProviding 으로 런타임 주입하며 시간 기반 성장과 게임 상태를 관리한다.
@MainActor
@Observable
final class CompanionStore {
    static let storedEggHatchDelay: TimeInterval = 5 * 60
    struct MoveLearningPrompt: Identifiable {
        let id = UUID()
        let monID: UUID
        let level: Int
        let move: MoveSpec
    }
    struct EvolutionPrompt: Identifiable {
        let id = UUID()
        let monID: UUID
        let fromSpeciesID: Int
        let toSpeciesID: Int
        let requiredLevel: Int
        let toName: String
    }
    private(set) var moveLearningPrompt: MoveLearningPrompt?
    private(set) var evolutionPrompt: EvolutionPrompt?
    private var declinedEvolutionMonID: UUID?
    private var declinedEvolutionLevel = 0
    private var declinedEvolutionTargetID = 0
    private(set) var currentTypes: [PokemonType] = []
    private(set) var displayedMoves: [MoveSpec] = []
    private(set) var isLoadingDisplayedMoves = false
    private var moveLearningQueue: [MoveLearningPrompt] = []
    private(set) var state = CompanionState()
    private(set) var displayState: CompanionStateKind = .egg
    private(set) var currentLine: EvoLine?
    private(set) var isHatching = false
    private var isRevealingDitto = false   // 메타몽 리빌 비동기 중복 방지(isHatching 자매)
    private var isStoredEggHatching = false
    private(set) var justEvolvedTo: String?     // 이름(연출/문구)
    private(set) var justGraduated: String?
    private var eventUntil: Date?

    /// 부화/진화 연출 트리거 — seq 증가로 UI 가 감지, 팝오버가 닫혀 있었어도 다음 오픈에 1회 재생.
    enum Celebration: Equatable { case hatch(shiny: Bool), evolve, dittoReveal(shiny: Bool) }
    private(set) var celebration: Celebration?
    private(set) var celebrationSeq = 0
    private func fireCelebration(_ c: Celebration) { celebration = c; celebrationSeq += 1 }
    /// 연출 재생 후 UI 가 호출(1회성 보장).
    func consumeCelebration() { celebration = nil }

    /// 사탕 사용 시 "+XP" 순간 표시 — 진화 없이 부분 진행일 때도 피드백. seq 증가로 CompanionHeader 감지.
    private(set) var candyFeedbackSeq = 0
    private(set) var candyFeedbackAmount = 0
    /// "+XP" 표시 1회성 보장 — CompanionHeader 가 재생 후 호출한다. 소비하지 않으면 다른 탭에 갔다
    /// 홈으로 재진입할 때(CompanionHeader 재마운트) @State 가 초기화돼 같은 값이 다시 떠오른다(회귀).
    func consumeCandyFeedback() { candyFeedbackAmount = 0 }

    /// 민트 사용 시 "성격이 X로" 순간 표시 — 사탕 피드백과 동일 1회성 패턴(seq + consume).
    private(set) var mintFeedbackSeq = 0
    private(set) var mintFeedbackNature: PokemonNature?
    func consumeMintFeedback() { mintFeedbackNature = nil }

    private let provider: any PokeProviding
    private let clock: () -> Date
    private let fileURL: URL
    private var rng: any RandomNumberGenerator
    private let dittoDisguiseRollingEnabled: Bool
    /// 세션 내 활성 개체 교체 감지용. await 뒤 이전 개체의 결과가 새 개체를 덮지 않게 한다.
    private var activeGeneration = 0

    init(provider: any PokeProviding = PokeAPIClient.shared,
         clock: @escaping () -> Date = Date.init,
         fileURL: URL? = nil,
         rng: any RandomNumberGenerator = SystemRandomNumberGenerator(),
         dittoDisguiseRollingEnabled: Bool = AppEnv.isBundledApp) {
        self.provider = provider
        self.clock = clock
        self.fileURL = fileURL ?? Self.defaultURL()
        self.rng = rng
        self.dittoDisguiseRollingEnabled = dittoDisguiseRollingEnabled
        load()
        reconcileStoredEggDates()
        // 앱이 종료된 사이 끝난 집중 모험은 기동 즉시 정산한다. FocusTimer 는 세션 메모리 상태라
        // 재실행하면 .idle 로 돌아오지만 모험은 디스크에 남으므로, 여기서 비우지 않으면 시작 버튼이
        // 완료된 모험 때문에 비활성으로 보이는 복구 불가능 상태가 된다.
        claimAdventure()   // 끝난 run 만 정산한다 — 진행 중이면 그대로 둔다.
        if state.active != nil { displayState = .idle }
    }

    static func defaultURL() -> URL {
        // 상태 파일 위치. 기본은 Application Support/PokeTokenBar. `PTB_STATE_DIR` 환경변수가 있으면
        // 그 디렉토리를 쓴다 — 개발/QA 격리용(실제 companion 상태를 건드리지 않고 데모 상태로 실행).
        // 프로덕션은 이 변수가 없어 무영향.
        // 공백만 있는 값은 무시(URL(fileURLWithPath:)가 CWD 상대경로로 해석되는 것 방지).
        let override = (ProcessInfo.processInfo.environment["PTB_STATE_DIR"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let dir: URL
        if !override.isEmpty {
            dir = URL(fileURLWithPath: override, isDirectory: true)
        } else {
            dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("PokeTokenBar")
        }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("companion-state.json")
    }

    // MARK: 파생값 (UI)

    var language: AppLanguage { state.language }
    func setLanguage(_ lang: AppLanguage) { state.language = lang; save() }
    /// 앱 전체 UI 문자열 — language 변경 시 자동 재렌더.
    var l: L { L(language) }

    var hasActive: Bool { state.active != nil }
    var rarity: Rarity? { state.active?.rarity }
    var currentIsShiny: Bool {
        guard let a = state.active else { return false }
        if a.dittoDisguise != nil && !a.dittoRevealed { return false }   // 위장 중엔 이로치 숨김(리빌 때 공개)
        return a.isShiny
    }
    var currentNature: PokemonNature? { state.active?.nature }
    var currentLevel: Int { state.active?.level ?? 1 }
    var experienceToNextLevel: Int {
        guard let mon = state.active, mon.level < 100 else { return 0 }
        return mon.level * 10_000_000 - mon.levelExperience
    }
    var levelProgress: Double {
        guard let mon = state.active else { return 0 }
        return Double(mon.levelExperience % 10_000_000) / 10_000_000
    }
    var nextEvolutionLevel: Int? {
        guard let mon = state.active, let node = currentLine?.tree.node(withID: mon.currentID),
              !node.children.isEmpty else { return nil }
        let nextIndex = mon.stageIndex + 1
        let next = mon.plannedPathIDs.indices.contains(nextIndex)
            ? node.children.first(where: { $0.speciesID == mon.plannedPathIDs[nextIndex] })
            : node.children.first
        return next?.evolutionLevel
    }
    var boxedMons: [MonState] { state.boxedMons }
    var ownedMons: [MonState] { (state.active.map { [$0] } ?? []) + state.boxedMons }
    var activeMonID: UUID? { state.active?.id }

    // 스타터 선택 — 맨 처음 1회, 알 대신 세 마리 중 택1. 고르면 starterChosen=true 로 이후엔 알 루프.
    // 후보 풀 규칙(범위·전설 제외)은 StarterRules 공유.

    /// 스타터 선택 화면을 보여야 하는가 — 아직 안 골랐고 활성 개체도 없을 때(맨 처음).
    var needsStarterSelection: Bool { !state.starterChosen && state.active == nil }
    var starterSelectableTypes: [PokemonType] { PokemonType.allCases.filter { $0 != .dark } }
    /// 뽑아둔 후보 3종(선택 화면이 그린다). 아직 못 뽑았으면 빈 배열.
    var starterCandidateIDs: [Int] { state.starterCandidates }

    /// 후보 3종을 아직 안 뽑았으면 뽑아 고정한다 — 1세대 기본형(baseSpeciesIndex 는 진화 루트만 담는다)
    /// 에서 메타몽 제외. **기기 고유 시드로 결정적**이라 재설치·상태 초기화에도 같은 Mac이면 같은 3종
    /// (리세마라 방지). 풀을 id 순으로 정렬해 시드가 같으면 결과도 같게 고정한다.
    /// 인덱스 조회 실패(오프라인)면 다음 호출에 재시도(빈 채로 둔다).
    func ensureStarterCandidates() async {
        guard needsStarterSelection, state.starterCandidates.isEmpty, !isHatching else { return }
        guard let index = try? await provider.baseSpeciesIndex(), !index.isEmpty else { return }
        var pool = index.map(\.id)
            .filter { StarterRules.genRange.contains($0)
                && $0 != PokemonOdds.dittoSpeciesID
                && !StarterRules.isLegendary($0) }   // 전설 제외
            .sorted()   // 안정 순서 — 같은 시드 + 같은 풀이면 항상 같은 결과
        guard pool.count >= 3 else { return }
        var seeded = SplitMix64(seed: DeviceID.starterSeed())
        var picked: [Int] = []
        for _ in 0..<3 {
            let i = Int(seeded.next() % UInt64(pool.count))
            picked.append(pool.remove(at: i))
        }
        state.starterCandidates = picked
        save()
    }

    /// 종의 표시 이름(현재 언어) — 스타터 카드 라벨용. 라인 조회 후 캐시, 실패 시 #번호 폴백.
    func resolveSpeciesName(_ speciesID: Int) async -> String {
        if let line = try? await provider.line(baseSpeciesID: speciesID) {
            return line.localizedName(speciesID, state.language)
        }
        return "#\(speciesID)"
    }

    func battleSnapshot(for mon: MonState, level: Int = 50) async -> BattleSnapshot? {
        guard let profile = try? await PokeAPIClient.shared.battleProfile(speciesID: mon.currentID) else { return nil }
        let name = await resolveSpeciesName(mon.currentID)
        let moves = mon.learnedMoves.isEmpty
            ? await PokeAPIClient.shared.moveSet(speciesID: mon.currentID, level: mon.level, types: profile.types)
            : mon.learnedMoves
        return BattleSnapshot(speciesID: mon.currentID, name: mon.nickname ?? name, trainer: trainerName,
                              level: level, nature: mon.nature, isShiny: mon.isShiny,
                              types: profile.types, base: profile.stats, moves: moves)
    }

    /// 스타터 확정 — 고른 종으로 즉시 부화(알 단계 건너뜀). 이후 졸업하면 기존 알/부화 루프로 돌아간다.
    func chooseStarter(_ speciesID: Int) async {
        guard needsStarterSelection, !isHatching else { return }
        guard state.starterCandidates.contains(speciesID) else { return }   // 화면에 뜬 후보만 허용(방어)
        state.starterChosen = true
        state.starterCandidates = []
        state.eggUsage = 0
        state.eggTier = nil
        state.pendingHatchID = nil
        save()
        await hatch(baseID: speciesID)   // hatchCore 재사용 — shiny/성격 롤·연출·저장 포함
    }

    @discardableResult
    func chooseStarterType(_ type: PokemonType) async -> Bool {
        guard needsStarterSelection, !isHatching, starterSelectableTypes.contains(type),
              let index = try? await provider.baseSpeciesIndex() else { return false }
        let ids = index.map(\.id).filter {
            StarterRules.genRange.contains($0)
                && !StarterRules.isLegendary($0)
        }
        let candidates = await withTaskGroup(of: Int?.self, returning: [Int].self) { group in
            for id in ids {
                group.addTask {
                    guard let profile = try? await PokeAPIClient.shared.battleProfile(speciesID: id),
                          profile.types.contains(type) else { return nil }
                    return id
                }
            }
            var matches: [Int] = []
            for await id in group { if let id { matches.append(id) } }
            return matches.sorted()
        }
        guard !candidates.isEmpty else { return false }
        let picked = candidates[Int(rng.next() % UInt64(candidates.count))]
        state.starterChosen = true
        state.starterCandidates = []
        state.eggUsage = 0
        state.eggTier = nil
        state.pendingHatchID = nil
        save()
        await hatch(baseID: picked)
        return state.active != nil
    }

    // 알 인큐베이션 (active 없을 때)
    var isEgg: Bool { state.active == nil }
    var eggStarted: Bool { state.eggUsage > 0 }
    var eggProgress: Double { min(1, max(0, Double(state.eggUsage) / Double(PokemonBalance.eggHatchThreshold))) }
    var eggTokensToHatch: Int { max(0, PokemonBalance.eggHatchThreshold - state.eggUsage) }

    var displayName: String {
        guard let a = state.active, let line = currentLine else { return "Token Egg" }
        if let nick = a.nickname, !nick.trimmingCharacters(in: .whitespaces).isEmpty { return nick }
        return line.localizedName(a.currentID, state.language)
    }
    /// 종 이름(별명 무시) — 별명 입력 플레이스홀더·리셋 기준값.
    var speciesName: String {
        guard let a = state.active, let line = currentLine else { return "" }
        return line.localizedName(a.currentID, state.language)
    }
    var currentNickname: String? { state.active?.nickname }

    /// 현재 포켓몬 별명 설정 — 공백이면 nil(종 이름으로 표시). 진화해도 유지.
    func setNickname(_ name: String) {
        guard state.active != nil else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        state.active!.nickname = trimmed.isEmpty ? nil : String(trimmed.prefix(20))
        save()
    }

    // MARK: 트레이너 이름 (배틀 표시)
    var trainerName: String { state.trainerName }
    var hasTrainerName: Bool { !state.trainerName.trimmingCharacters(in: .whitespaces).isEmpty }
    func setTrainerName(_ name: String) {
        state.trainerName = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(20))
        save()
    }
    var currentSpeciesID: Int? { state.active?.currentID }
    var isFinalStage: Bool {
        guard let a = state.active, let line = currentLine else { return false }
        return line.tree.node(withID: a.currentID)?.children.isEmpty ?? true
    }
    var stageText: String {
        guard let a = state.active else { return "" }
        return isFinalStage ? l.finalForm : l.stage(a.stageIndex + 1, a.totalForms)
    }
    var threshold: Int {
        guard let a = state.active else { return 1 }
        return PokemonBalance.phaseThreshold(rarity: a.rarity, totalForms: a.totalForms, stageIndex: a.stageIndex)
    }
    var progress: Double {
        guard let a = state.active, threshold > 0 else { return 0 }
        return min(1, max(0, Double(a.usedAtStage) / Double(threshold)))
    }
    var tokensToNext: Int { guard let a = state.active else { return 0 }; return max(0, threshold - a.usedAtStage) }

    /// 진화 라인 표시용: 실현된 경로 + 다음 단계 미리보기.
    /// 유일하게 이어지는 단계 뒤에 분기가 있으면, 그 확정 접두어와 하나의 미지 항목을 함께 보여 준다.
    /// 분기 후보는 부화 시 계획됐더라도 실제 진화 전까지 하나의 미지 항목으로 숨긴다.
    var lineNodes: [EvoLineItem] {
        guard let a = state.active, let line = currentLine else { return [] }
        var out = Self.realizedLineItems(pathIDs: a.pathIDs, stageIndex: a.stageIndex)
        if let current = line.tree.node(withID: a.currentID) {
            var node = current
            var guaranteedPrefix: [EvoNode] = []
            while node.children.count == 1, let child = node.children.first {
                guaranteedPrefix.append(child)
                node = child
            }

            if node.children.count > 1 {
                out += guaranteedPrefix.map { EvoLineItem(.species($0.speciesID), .future) }
                out.append(EvoLineItem(.mystery, .future))
            } else {
                out += guaranteedPrefix.map { EvoLineItem(.species($0.speciesID), .future) }
            }
        }
        return out
    }

    static func realizedLineItems(pathIDs: [Int], stageIndex: Int) -> [EvoLineItem] {
        pathIDs.enumerated().map { i, id in
            EvoLineItem(.species(id), i == stageIndex ? .current : .done)
        }
    }
    /// 도감에는 영구 보존된 졸업 개체와 현재 키우는 포켓몬을 함께 표시한다.
    /// 현재 개체는 영속 dex 에 중복 저장하지 않고 화면용 항목으로 합성한다. 졸업 시 active 가 사라지고
    /// 같은 개체의 영구 DexEntry 가 추가되므로 목록 개수는 그대로 유지된다.
    private var activeDexEntry: DexEntry? {
        guard let active = state.active else { return nil }
        return DexEntry(
            id: "active-\(active.baseID)-\(active.currentID)",
            baseID: active.baseID,
            finalID: active.currentID,
            chainOrder: active.pathIDs,
            rarity: active.rarity,
            caughtAt: nil,
            isShiny: currentIsShiny,   // 위장 메타몽은 리빌 전까지 이로치를 숨긴다(판정 단일 소스)
            nature: active.nature,
            names: currentLine.map { line in
                Dictionary(uniqueKeysWithValues:
                    active.pathIDs.compactMap { id in line.names[id].map { (id, $0) } })
            }
        )
    }

    var dexEntries: [DexEntry] {
        guard let activeDexEntry else { return state.dex }
        return state.dex + [activeDexEntry]
    }

    /// 합성된 현재 포켓몬 항목인지 판별한다. caughtAt 이 없는 구버전 졸업 항목과 혼동하지 않는다.
    func isActiveDexEntry(_ entry: DexEntry) -> Bool {
        entry.id == activeDexEntry?.id
    }

    /// 포획 로그 표시 순서 — 현재 키우는 포켓몬을 맨 앞에 고정하고, 졸업 항목은 **기록 시각 최신순**.
    ///
    /// 과거에는 희귀도 내림차순이 먼저였다(종 단위 도감의 규칙). 로그는 시간순 기록이라 희귀도로
    /// 먼저 묶으면 방금 졸업한 개체가 며칠 전에 잡은 상위 희귀도 밑에 묻힌다. 희귀도로 좁히는 일은
    /// 이제 필터 캡슐과 도감이 담당한다.
    ///
    /// caughtAt 이 없는 구버전 항목은 .distantPast 로 묶여 맨 뒤에 온다(그들끼리의 순서는 미정).
    var dexEntriesSorted: [DexEntry] {
        let graduated = state.dex.sorted {
            ($0.caughtAt ?? .distantPast) > ($1.caughtAt ?? .distantPast)
        }
        guard let activeDexEntry else { return graduated }
        return [activeDexEntry] + graduated
    }

    /// 희귀도별 포획 로그 개수(요약 헤더용) — 개체 수 기준. 도감(종 단위)은 dexSpecies 를 쓴다.
    func dexCount(_ rarity: Rarity) -> Int { dexEntries.lazy.filter { $0.rarity == rarity }.count }

    /// 도감 한 칸 — 종 1개로 접힌 수집 기록. 같은 라인을 여러 번 키워도 종은 한 칸이다.
    /// **종 정보만 담는다** — 성격·획득 횟수처럼 개체에 딸린 것은 포획 로그가 개체 단위로 보여준다.
    struct DexSpecies: Identifiable, Sendable {
        let id: Int                     // speciesID = 도감 번호(정렬 키)
        let name: String
        let rarity: Rarity
        let isShiny: Bool               // 이 종을 이로치로 보유한 적이 있는가
        /// 이 칸의 근거가 **지금 키우는 개체뿐**이다 — 졸업 기록이 없어 아직 확정이 아니다.
        /// 알을 새로 사면 개체가 폐기되고(dex 미변경) 이 칸은 사라지며, 메타몽이 리빌하면 위장했던
        /// 종이 빠진다. 영구 기록과 같은 모양으로 두면 종 수가 줄어드는 게 결함으로 보이므로 뷰가 표식을 단다.
        let isRaising: Bool
    }

    /// 종 하나가 모으는 것 — 누적 전용. 병렬 딕셔너리를 여러 개 두면 키 집합이 서로 어긋날 수 있고
    /// (한쪽에만 써서 그 종이 조용히 사라지거나), 읽는 쪽에 도달 불가한 기본값이 생긴다. 하나로 묶어
    /// 두 여지를 함께 없앤다.
    private struct DexAccumulator {
        /// 첫 발견 때 확정 — 같은 종은 항상 같은 base 라인에서 오므로 갱신할 값이 없다.
        let rarity: Rarity
        var names: [String: String]?
        var isShiny = false
        /// 졸업 기록에서 온 적이 있는가 — 한 번이라도 true 면 이 종은 영구 보존분이라 사라지지 않는다.
        /// 같은 라인을 다시 키우는 중이어도(현재 개체와 겹쳐도) 표식 대상이 아니다.
        var isGraduated = false
    }

    /// 도감 목록 — 보유 종만, 도감 번호 오름차순.
    ///
    /// 포함 종 = 졸업분 `chainOrder` ∪ 현재 개체의 **도달분** `pathIDs[0...stageIndex]`.
    /// `plannedPathIDs`(사전 선택된 전체 경로)는 미도달 단계를 포함하므로 절대 쓰지 않는다 — 쓰면
    /// 아직 진화하지 않은 종이 보유로 잡힌다.
    var dexSpecies: [DexSpecies] {
        // 종별 누적을 한 번에 훑는다(뷰가 body 에서 1회 소비 — 메모이즈 없이 충분).
        var acc: [Int: DexAccumulator] = [:]
        for entry in state.dex {
            for id in entry.chainOrder {
                var a = acc[id] ?? DexAccumulator(rarity: entry.rarity)
                if let n = entry.names?[id] { a.names = n }   // 이름 없는 구버전 항목이 덮어쓰지 않게
                if entry.isShiny { a.isShiny = true }
                a.isGraduated = true
                acc[id] = a
            }
        }
        if let active = state.active {
            // 도달분만 — stageIndex 가 pathIDs 범위 안임은 두 입구가 보장한다:
            // MonState.init(from:) 의 clamp, 그리고 SaveTransfer 의 가져오기 정규화.
            for id in active.pathIDs.prefix(active.stageIndex + 1) {
                var a = acc[id] ?? DexAccumulator(rarity: active.rarity)
                if let n = currentLine?.names[id] { a.names = n }
                if currentIsShiny { a.isShiny = true }   // 위장 중 숨김 규칙 재사용
                acc[id] = a
            }
        }
        return acc.sorted { $0.key < $1.key }.map { id, a in
            DexSpecies(
                id: id,
                name: a.names.flatMap { state.language.resolveName($0) } ?? "#\(id)",
                rarity: a.rarity,
                isShiny: a.isShiny,
                isRaising: !a.isGraduated)
        }
    }

    /// 도감 한 줄 = 진화 라인 하나. 선택 메뉴가 기본형 아래에 단계들을 접어 보여주기 위한 묶음이다.
    struct DexLine: Identifiable, Sendable {
        let id: Int                  // 기본형 종 번호 — 라인 식별자이자 메뉴 제목의 근거
        let name: String
        let species: [DexSpecies]    // 수록된 단계만, 초기→최종 순서
    }

    /// 도감을 진화 라인 단위로 묶는다.
    ///
    /// 칸의 내용(이름·이로치·희귀도)은 `dexSpecies` 에서 그대로 읽는다 — 여기서 다시 만들면 격자와
    /// 메뉴가 같은 종을 다른 이름·표식으로 보여줄 수 있다.
    ///
    /// 분기 진화(이브이처럼 기본형 하나에 여러 최종형)는 **한 라인으로 합친다**. 졸업 기록이 분기마다
    /// 따로 남아 있어도 트레이너에겐 같은 갈래이므로, 기본형 이름이 메뉴에 여러 번 뜨면 어느 쪽을
    /// 골라야 할지 알 수 없다.
    var dexLines: [DexLine] {
        let speciesByID = Dictionary(dexSpecies.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var memberIDsByBase: [Int: [Int]] = [:]
        func collect(_ chain: [Int]) {
            guard let base = chain.first else { return }
            var members = memberIDsByBase[base] ?? []
            for id in chain where speciesByID[id] != nil && !members.contains(id) { members.append(id) }
            memberIDsByBase[base] = members
        }
        for entry in state.dex { collect(entry.chainOrder) }
        if let active = state.active { collect(Array(active.pathIDs.prefix(active.stageIndex + 1))) }

        return memberIDsByBase.keys.sorted().compactMap { base in
            let members = (memberIDsByBase[base] ?? []).compactMap { speciesByID[$0] }
            guard let head = members.first else { return nil }
            return DexLine(id: base, name: head.name, species: members)
        }
    }

    /// 플로팅 펫이 그릴 대상 — 설정에서 고른 도감 종이 있으면 그 종, 없으면 지금 키우는 개체.
    ///
    /// 수록 판정과 이로치 여부를 `dexSpecies` 에서 그대로 읽는다. 같은 규칙을 여기에 다시 적으면
    /// (졸업 기록 + 지금 키우는 개체의 도달 단계) 한쪽만 바뀌었을 때 고를 수 있는 종과 실제로 그려지는
    /// 종이 어긋난다.
    ///
    /// 고른 종이 도감에서 사라졌으면 파트너로 되돌아간다 — 졸업 전 개체만 근거였던 칸은 그 개체를
    /// 놓아주면 없어지므로(`isRaising`), 그대로 두면 보유한 적 없는 종이 바탕화면에 남는다.
    func floatingPetSubject(pinnedSpeciesID: Int?) -> (speciesID: Int?, isShiny: Bool) {
        guard let pinnedSpeciesID,
              let pinned = dexSpecies.first(where: { $0.id == pinnedSpeciesID })
        else { return (currentSpeciesID, currentIsShiny) }
        return (pinned.id, pinned.isShiny)
    }

    /// 이름이 없는 구버전 졸업 항목의 체인 이름을 채운다(도감 격자 진입 시 1회).
    ///
    /// 격자는 저장된 이름만 읽으므로 백필이 없으면 칸이 종 번호(`#41`)로 남는다. 포획 로그는 행이
    /// 뜰 때 행 단위로 같은 일을 해 왔지만, 로그를 한 번도 안 열면 격자는 계속 번호다.
    /// 라인 조회는 `PokeAPIClient` 가 base 단위로 캐시하므로 같은 라인이 여러 항목이어도 네트워크는 1회.
    /// 오프라인이면 `dexResolveChainNames` 가 저장 없이 폴백만 돌려주므로 다음 진입에서 다시 시도한다.
    func backfillMissingDexNames() async {
        for entry in state.dex where entry.names == nil {
            _ = await dexResolveChainNames(entry)   // 성공분만 내부에서 state.dex 에 저장
        }
    }

    /// 도감 항목 진화 체인 각 종의 이름(speciesID → 현재 언어 이름). 저장돼 있으면 즉시(네트워크 0),
    /// 없으면 nil(뷰가 async 조회로 폴백).
    func dexStoredChainNames(_ entry: DexEntry) -> [Int: String]? {
        guard let names = entry.names, !names.isEmpty else { return nil }
        return names.compactMapValues { state.language.resolveName($0) }
    }

    /// 이름 미저장(구버전) 항목용 — line 을 1회 조회해 체인 전 종의 다국어 이름을 얻고 항목에 백필한다
    /// (다음부터 네트워크 0). 저장돼 있으면 그대로(fetch 없음). 오프라인이면 종 번호(#id)로 폴백.
    /// 반환은 chainOrder 전 종을 채운 [speciesID: 현재 언어 이름].
    func dexResolveChainNames(_ entry: DexEntry) async -> [Int: String] {
        if let stored = dexStoredChainNames(entry) { return stored }
        guard let line = try? await provider.line(baseSpeciesID: entry.baseID) else {
            return Dictionary(uniqueKeysWithValues: entry.chainOrder.map { ($0, "#\($0)") })
        }
        let chainNames = Dictionary(uniqueKeysWithValues:
            entry.chainOrder.compactMap { id in line.names[id].map { (id, $0) } })
        if !chainNames.isEmpty, let idx = state.dex.firstIndex(where: { $0.id == entry.id }) {
            state.dex[idx].names = chainNames   // 백필 저장
            save()
        }
        return Dictionary(uniqueKeysWithValues: entry.chainOrder.map { id in
            (id, chainNames[id].flatMap { state.language.resolveName($0) } ?? "#\(id)")
        })
    }

    // MARK: 생산 틱 (시간 → 별의모래)

    /// 방치 생산 — 앱이 켜져 있는 동안 경과 시간을 별의모래로 적립한다. AppDelegate 의 60초 타이머와
    /// refresh 훅이 호출한다. 슬립·시계 점프는 maxTickInterval 캡으로 잘린다(켜져 있던 시간만 인정).
    /// 부화·진화·졸업은 공통 성장량 적용 경로를 사용한다.
    func tick() {
        let now = clock()
        refreshLifecycle()
        defer {
            grantDailyCandyIfNeeded(now: now)
            save()
        }
        guard let last = state.lastTickAt else {
            state.lastTickAt = now   // 첫 틱은 기준점만 — 설치/리셋 이전 시간을 소급하지 않는다
            return
        }
        state.lastTickAt = now
        // 스타터를 고르기 전엔 인큐베이션할 알이 없다 — 생산은 첫 파트너를 고른 뒤부터.
        guard !needsStarterSelection else { return }
        let elapsed = min(max(0, now.timeIntervalSince(last)), IdleEconomy.maxTickInterval)
        guard elapsed > 0 else { return }
        // 함께한 시간 누적 — 날짜가 바뀐 첫 틱에 오늘 버킷 리셋(대시보드 "오늘 함께한 시간").
        let today = Self.dayKey(now)
        if state.activeSecondsDate != today { state.activeSecondsDate = today; state.activeSecondsToday = 0 }
        state.activeSecondsTotal += elapsed
        state.activeSecondsToday += elapsed
        // 별의모래는 완료한 집중 세션에서만 지급한다. 틱은 함께한 시간 기록과 생명주기 갱신만 담당한다.
    }

    /// 생산분을 상태에 반영 — 알이면 인큐베이션, 활성이면 성장(진화/졸업 판정). tick 과 테스트가 공유.
    private func accrue(_ dust: Int) {
        state.usedSinceInstall += dust
        if state.active == nil {
            state.eggUsage += dust   // 알 인큐베이션 누적
        } else {
            applyUsage(dust)
        }
    }

    #if DEBUG
    /// 테스트 전용 — 시간을 전진시키지 않고 생산분을 직접 주입한다. tick 의 적립 경로(accrue)를 그대로
    /// 태우므로 임계·이월·진화·졸업이 실동작과 동일하게 발화한다. 프로덕션 호출 경로 없음.
    func debugAccrue(_ dust: Int) { accrue(dust) }
    /// 테스트 전용 — 인벤토리에 사탕 n개 주입(일일 지급 경로를 우회). 사용(useRareCandy) 테스트용.
    func debugAddCandy(_ n: Int) { state.inventory[ItemKind.rareCandy.rawValue, default: 0] += n; save() }
    /// 테스트 전용 — 스타터 선택 완료 후의 기존 사용자 상태를 재현한다.
    func debugMarkStarterChosen() { state.starterChosen = true; save() }
    /// 테스트 전용 — 레벨 경험치를 직접 주입하고 진화·졸업 판정까지 트리거한다(applyUsage(0) 은
    /// claimAdventure() 가 레벨만 올릴 때 쓰는 것과 같은 형태). 프로덕션 호출 경로 없음.
    func debugAccrueLevelExperience(_ amount: Int) {
        guard state.active != nil else { return }
        state.active!.levelExperience = min(990_000_000, state.active!.levelExperience + amount)
        applyUsage(0)
    }
    /// 테스트 전용 — 기술 목록 표시 상태를 직접 세팅(네트워크 로드 없이 행 레이아웃을 재기 위함).
    func debugSetDisplayedMoves(_ moves: [MoveSpec], loading: Bool = false) {
        displayedMoves = moves
        isLoadingDisplayedMoves = loading
    }
    #endif

    /// 생산 배율 — 도감에 등록한 종(고유 최종체) 1종당 +2%. 수집이 곧 성장 엔진.
    var productionMultiplier: Double {
        let collection = 1.0 + IdleEconomy.dexBonusPerSpecies * Double(Set(state.dex.map(\.finalID)).count)
        return collection
    }

    /// 시간당 생산량(표시용) — 현재 배율 반영.
    var productionPerHour: Int { Int(IdleEconomy.dustPerSecond * 3600 * productionMultiplier) }

    /// 대시보드용 함께한 시간(초).
    var activeSecondsToday: Double { state.activeSecondsToday }
    var activeSecondsTotal: Double { state.activeSecondsTotal }

    // MARK: 돌봄·모험

    var care: PetCareState { state.care }
    var activeAdventure: AdventureRun? { state.adventure }
    var isAdventuring: Bool { state.adventure != nil }
    /// "지금 나가 있는 중" — 끝났지만 아직 정산 안 된 모험은 포함하지 않는다.
    /// UI 게이트는 이걸 써야 한다. `isAdventuring` 으로 막으면 정산 전 상태에서 영영 잠긴다(#8).
    var isAdventureInProgress: Bool {
        guard let run = state.adventure else { return false }
        return !run.isComplete(at: clock())
    }

    func adventureProgress(at date: Date? = nil) -> Double {
        state.adventure?.progress(at: date ?? clock()) ?? 0
    }

    @discardableResult
    func startAdventure(_ zone: AdventureZone) -> Bool {
        claimAdventure()
        let now = clock()
        state.care.advance(to: now)
        guard let speciesID = currentSpeciesID, state.adventure == nil,
              !state.care.isSick, !state.care.isSleeping, state.care.energy >= 15 else { return false }
        state.care.energy -= 15
        state.adventure = AdventureRun(zone: zone, startedAt: now,
                                       endsAt: now.addingTimeInterval(zone.duration),
                                       companionSpeciesID: speciesID)
        save()
        return true
    }

    @discardableResult
    func startFocusAdventure(minutes: Int) -> Bool {
        claimAdventure()
        let now = clock()
        guard let speciesID = currentSpeciesID, state.adventure == nil else { return false }
        let zone: AdventureZone = minutes >= 90 ? .coast : (minutes >= 50 ? .cave : .forest)
        state.adventure = AdventureRun(zone: zone, startedAt: now,
                                       endsAt: now.addingTimeInterval(TimeInterval(max(1, minutes) * 60)),
                                       companionSpeciesID: speciesID)
        save()
        return true
    }

    /// 진행 중인 집중 세션을 사용자가 중단했을 때 모험도 함께 취소한다. 보상은 지급하지 않는다.
    func cancelFocusAdventure() {
        guard state.adventure != nil else { return }
        state.adventure = nil
        save()
    }

    /// 모험 정산의 **유일한** 진입점. 끝난 run 만 정산하고(미완료면 nil) 보상 계산도 여기 한 곳에만 있다.
    /// 정산 계기는 "보상 받기" 버튼, 집중 세션 완료(`completeFocusSession`), 새 모험 시작
    /// (`startAdventure`·`startFocusAdventure`) 셋이지만 모두 이 함수를 부른다 — 완료 판정을 감싸는
    /// 래퍼를 따로 두면 같은 가드가 두 곳에 생겨 한쪽만 바뀌는 사고가 난다.
    @discardableResult
    func claimAdventure() -> AdventureReward? {
        let now = clock()
        guard let run = state.adventure, run.isComplete(at: now) else { return nil }
        var reward = AdventureRules.reward(for: run)
        state.adventure = nil
        state.starPieces += reward.starPieces
        if state.active != nil {
            let oldLevel = state.active!.level
            state.active!.levelExperience = min(990_000_000,
                state.active!.levelExperience + reward.experience)
            let newLevel = state.active!.level
            applyUsage(0)
            if newLevel > oldLevel { queueMoveLearning(from: oldLevel + 1, through: newLevel) }
        }
        if reward.foundRareCandy { state.inventory[ItemKind.rareCandy.rawValue, default: 0] += 1 }
        let minutes = Int((run.endsAt.timeIntervalSince(run.startedAt) / 60).rounded())
        var fragments = minutes >= 90 ? 6 : (minutes >= 50 ? 3 : 1)
        let today = Self.dayKey(now)
        if state.lastAdventureBonusDate != today {
            state.lastAdventureBonusDate = today
            fragments += 1
        }
        state.eggFragments += fragments
        let fragmentEggs = state.eggFragments / 10
        state.eggFragments %= 10
        let week = Self.weekKey(now)
        if state.adventureWeekKey != week {
            state.adventureWeekKey = week
            state.weeklyAdventureCount = 0
        }
        state.weeklyAdventureCount += 1
        let weeklyEgg = state.weeklyAdventureCount == 10 ? 1 : 0
        let rareEgg = reward.foundEgg ? 1 : 0
        let earnedEggs = fragmentEggs + weeklyEgg + rareEgg
        let acceptedEggs = min(earnedEggs, 999 - state.focusEggs)
        state.focusEggs += acceptedEggs
        state.focusEggReadyDates.append(contentsOf:
            repeatElement(now.addingTimeInterval(Self.storedEggHatchDelay), count: acceptedEggs))
        reward.eggFragments = fragments
        reward.bonusEggs = earnedEggs
        state.care.happiness = min(100, state.care.happiness + 10)
        state.adventureHistory.insert(AdventureRecord(id: run.id, zone: run.zone,
                                                       companionSpeciesID: run.companionSpeciesID,
                                                       completedAt: now, stardust: reward.starPieces,
                                                       foundRareCandy: reward.foundRareCandy), at: 0)
        if state.adventureHistory.count > 30 { state.adventureHistory.removeLast(state.adventureHistory.count - 30) }
        save()
        return reward
    }

    var favoriteFood: CareFood { CareFood.favorite(for: currentSpeciesID ?? 0) }

    func feedCompanion(_ food: CareFood = .apple) {
        guard state.active != nil, state.adventure == nil, !state.care.isSleeping else { return }
        if let event = state.care.advance(to: clock()) { handleCareEvent(event) }
        state.care.feed(favorite: food == favoriteFood); save()
    }
    func playWithCompanion() {
        guard state.active != nil, state.adventure == nil, !state.care.isSleeping else { return }
        if let event = state.care.advance(to: clock()) { handleCareEvent(event) }
        state.care.play(); save()
    }
    func restCompanion() {
        guard state.active != nil, state.adventure == nil, !state.care.isSleeping else { return }
        if let event = state.care.advance(to: clock()) { handleCareEvent(event) }
        state.care.rest(); save()
    }

    func cleanCompanion() {
        guard state.active != nil, state.adventure == nil, !state.care.isSleeping else { return }
        if let event = state.care.advance(to: clock()) { handleCareEvent(event) }
        state.care.clean(); save()
    }

    @discardableResult
    func medicateCompanion() -> Bool {
        guard state.active != nil, state.adventure == nil, !state.care.isSleeping else { return false }
        if let event = state.care.advance(to: clock()) { handleCareEvent(event) }
        let healed = state.care.giveMedicine()
        if healed { save() }
        return healed
    }

    @discardableResult
    func trainCompanion() -> CareTrainingResult {
        guard state.active != nil, state.adventure == nil, !state.care.isSick,
              !state.care.isSleeping else { return .tooTired }
        if let event = state.care.advance(to: clock()) { handleCareEvent(event) }
        let result = state.care.train(at: clock())
        if result == .trained { save() }
        return result
    }

    @discardableResult
    func petCompanion() -> Bool {
        guard state.active != nil, state.adventure == nil, !state.care.isSleeping else { return false }
        if let event = state.care.advance(to: clock()) { handleCareEvent(event) }
        let accepted = state.care.pet(at: clock())
        if accepted { save() }
        return accepted
    }

    @discardableResult
    func sleepCompanion() -> Bool {
        guard state.active != nil, state.adventure == nil, !state.care.isSick else { return false }
        let started = state.care.sleep(at: clock())
        if started { save() }
        return started
    }

    func wakeCompanion() {
        guard state.care.wake(at: clock()) else { return }
        save()
    }

    var focusEggCount: Int { state.focusEggs }
    var nextStoredEggHatchAt: Date? { state.focusEggReadyDates.min() }
    var eggFragmentCount: Int { state.eggFragments }
    var weeklyAdventureProgress: Int {
        state.adventureWeekKey == Self.weekKey(clock()) ? state.weeklyAdventureCount : 0
    }

    /// 집중 세션이 끝나면 그 세션으로 보낸 모험을 바로 정산한다.
    /// 예전엔 save() 만 해서 보상이 안 들어오고 `state.adventure` 도 안 비워졌다(#8).
    /// 보상 계산은 claimAdventure() 한 곳에만 있다 — 여기서 따로 더하면 이중 지급이 된다.
    @discardableResult
    func completeFocusSession(minutes: Int, roll: Int? = nil) -> FocusSessionReward {
        guard let reward = claimAdventure() else {
            save()
            return FocusSessionReward(minutes: minutes, stardust: 0, foundEgg: false)
        }
        return FocusSessionReward(minutes: minutes, stardust: reward.starPieces,
                                  foundEgg: reward.bonusEggs > 0)
    }

    func beginIncubatingFocusEgg() -> Bool {
        guard state.focusEggs > 0, let active = state.active else { return false }
        state.boxedMons.append(active)
        state.active = nil
        state.focusEggs -= 1
        if !state.focusEggReadyDates.isEmpty { state.focusEggReadyDates.removeFirst() }
        state.eggUsage = 0
        state.eggTier = nil
        state.pendingHatchID = nil
        activeGeneration += 1
        currentLine = nil
        save()
        return true
    }

    func switchCompanion(to id: UUID) {
        guard let index = state.boxedMons.firstIndex(where: { $0.id == id }) else { return }
        let selected = state.boxedMons.remove(at: index)
        if let active = state.active { state.boxedMons.append(active) }
        state.active = selected
        activeGeneration += 1
        currentLine = nil
        currentTypes = []
        displayedMoves = []
        evolutionPrompt = nil
        displayState = .idle
        save()
        Task { await loadCurrentLine() }
    }

    func declineEvolution() {
        guard let prompt = evolutionPrompt, let active = state.active, active.id == prompt.monID else {
            evolutionPrompt = nil; return
        }
        declinedEvolutionMonID = active.id
        declinedEvolutionLevel = active.level
        declinedEvolutionTargetID = prompt.toSpeciesID
        evolutionPrompt = nil
    }

    func acceptEvolution() {
        guard let prompt = evolutionPrompt, let line = currentLine, let active = state.active,
              active.id == prompt.monID, active.currentID == prompt.fromSpeciesID,
              active.level >= prompt.requiredLevel,
              let node = line.tree.node(withID: active.currentID),
              node.children.contains(where: { $0.speciesID == prompt.toSpeciesID }) else {
            evolutionPrompt = nil; return
        }
        evolutionPrompt = nil
        declinedEvolutionMonID = nil
        state.active!.pathIDs = Array(active.pathIDs.prefix(active.stageIndex + 1)) + [prompt.toSpeciesID]
        state.active!.stageIndex += 1
        let threshold = PokemonBalance.phaseThreshold(
            rarity: active.rarity, totalForms: active.totalForms, stageIndex: active.stageIndex - 1)
        state.active!.usedAtStage = max(0, active.usedAtStage - threshold)
        justEvolvedTo = prompt.toName
        fireCelebration(.evolve)
        eventUntil = clock().addingTimeInterval(4)
        notifyCompanionEvent(l.notifEvolveTitle, l.notifEvolveBody(prompt.toName))
        save()
        applyUsage(0)
    }

    func declineMoveLearning() {
        moveLearningPrompt = nil
        showNextMoveLearningPrompt()
    }

    func acceptMoveLearning(replacing index: Int? = nil) {
        guard let prompt = moveLearningPrompt, state.active?.id == prompt.monID else {
            declineMoveLearning(); return
        }
        if state.active!.learnedMoves.count < 4 {
            state.active!.learnedMoves.append(prompt.move)
        } else if let index, state.active!.learnedMoves.indices.contains(index) {
            state.active!.learnedMoves[index] = prompt.move
        } else { return }
        save()
        moveLearningPrompt = nil
        showNextMoveLearningPrompt()
    }

    private func queueMoveLearning(from first: Int, through last: Int) {
        guard let mon = state.active else { return }
        Task { @MainActor in
            for level in first...last {
                let moves = await PokeAPIClient.shared.movesLearned(speciesID: mon.currentID, at: level)
                for move in moves where !mon.learnedMoves.contains(where: { $0.id == move.id }) {
                    moveLearningQueue.append(MoveLearningPrompt(monID: mon.id, level: level, move: move))
                }
            }
            showNextMoveLearningPrompt()
        }
    }

    private func showNextMoveLearningPrompt() {
        guard moveLearningPrompt == nil, !moveLearningQueue.isEmpty else { return }
        moveLearningPrompt = moveLearningQueue.removeFirst()
    }

    func loadCurrentTypes() async {
        guard let id = currentSpeciesID,
              let profile = try? await PokeAPIClient.shared.battleProfile(speciesID: id),
              currentSpeciesID == id else { return }
        currentTypes = profile.types
    }

    func loadDisplayedMoves() async {
        guard let active = state.active, let speciesID = currentSpeciesID else {
            displayedMoves = []; return
        }
        if active.learnedMoves.isEmpty { await ensureInheritedMoves() }
        guard let refreshed = state.active, refreshed.id == active.id else { return }
        if !refreshed.learnedMoves.isEmpty {
            isLoadingDisplayedMoves = true
            defer { isLoadingDisplayedMoves = false }
            var enriched = refreshed.learnedMoves
            for index in enriched.indices where enriched[index].descriptions == nil {
                if let detail = await PokeAPIClient.shared.moveDetail(id: enriched[index].id) {
                    enriched[index] = detail
                }
            }
            guard state.active?.id == active.id else { return }
            state.active!.learnedMoves = enriched
            displayedMoves = enriched
            save()
            return
        }
        isLoadingDisplayedMoves = true
        defer { isLoadingDisplayedMoves = false }
        let profile = try? await PokeAPIClient.shared.battleProfile(speciesID: speciesID)
        let moves = await PokeAPIClient.shared.canonicalLevelUpMoves(speciesID: speciesID, level: active.level)
        guard state.active?.id == active.id else { return }
        if let profile { currentTypes = profile.types }
        displayedMoves = moves
    }

    /// 진화 경로의 모든 이전 종에서 현재 레벨까지 배울 수 있었던 본가 기술을 복원한다.
    /// 한번 저장된 learnedMoves는 이후 진화에서도 MonState와 함께 그대로 유지된다.
    func ensureInheritedMoves() async {
        guard let mon = state.active, mon.learnedMoves.isEmpty else { return }
        var inherited: [MoveSpec] = []
        for speciesID in mon.pathIDs {
            let moves = await PokeAPIClient.shared.canonicalLevelUpMoves(speciesID: speciesID, level: mon.level)
            for move in moves where !inherited.contains(where: { $0.id == move.id }) {
                inherited.append(move)
            }
        }
        guard state.active?.id == mon.id else { return }
        // 오래된 기술부터 최대 4개. 이후 새 기술은 학습 선택 카드에서 교체한다.
        state.active!.learnedMoves = Array(inherited.prefix(4))
        displayedMoves = state.active!.learnedMoves
        if !inherited.isEmpty { save() }
    }

    private func handleCareEvent(_ event: CareAdvanceEvent) {
        if case .becameSick = event {
            let copy: (String, String)
            switch state.language {
            case .ko: copy = ("파트너가 아파요!", "먼저 씻긴 뒤 약을 먹여 주세요.")
            case .ja: copy = ("パートナーが病気です！", "きれいにしてから薬をあげてください。")
            case .en: copy = ("Your partner is sick!", "Clean it first, then give medicine.")
            }
            notifyCompanionEvent(copy.0, copy.1)
            return
        }
        guard case let .requested(need) = event else { return }
        let copy: (String, String)
        switch (state.language, need) {
        case (.ko, .hungry): copy = ("배가 고파요!", "30분 안에 사과를 주세요.")
        case (.ko, .lonely): copy = ("같이 놀고 싶어요!", "30분 안에 공으로 놀아주세요.")
        case (.ko, .tired): copy = ("졸려요!", "30분 안에 쉬게 해주세요.")
        case (.ja, .hungry): copy = ("おなかがすいた！", "30分以内に食べ物をあげてください。")
        case (.ja, .lonely): copy = ("遊びたい！", "30分以内に一緒に遊んでください。")
        case (.ja, .tired): copy = ("ねむい！", "30分以内に休ませてください。")
        case (_, .hungry): copy = ("I'm hungry!", "Please feed me within 30 minutes.")
        case (_, .lonely): copy = ("Let's play!", "Please play with me within 30 minutes.")
        case (_, .tired): copy = ("I'm sleepy!", "Please let me rest within 30 minutes.")
        }
        notifyCompanionEvent(copy.0, copy.1)
    }

    func grantBattleReward(won: Bool, participantCount: Int, mode: MultiplayerBattleMode,
                           opponentNames: [String]) {
        guard state.active != nil else { return }
        let dust = 0
        state.battleHistory.insert(BattleRecord(playedAt: clock(), mode: mode,
                                                participantCount: participantCount, won: won,
                                                reward: dust, opponentNames: opponentNames), at: 0)
        if state.battleHistory.count > 30 { state.battleHistory.removeLast(state.battleHistory.count - 30) }
        save()
    }

    var recentAdventures: [AdventureRecord] { Array(state.adventureHistory.prefix(5)) }
    var recentBattles: [BattleRecord] { Array(state.battleHistory.prefix(5)) }
    var battleRank: BattleRank { state.battleRank }
    var battleRankProfile: BattleRankProfile {
        BattleRankProfile(rank: state.battleRank, stardust: availableTokens)
    }

    /// 1:1 맞짱 랭크전 정산. 판돈은 계산된 고정액만 이동한다.
    @discardableResult
    func settleRankedBrawl(won: Bool, opponent: BattleRank, stake: Int) -> Int {
        if won {
            state.starPieces += max(0, stake)
        } else if stake > 0 {
            guard availableTokens >= stake else { return 0 }
            state.starPieces -= stake
        }
        let delta = state.battleRank.apply(win: won, opponent: opponent)
        save()
        return delta
    }

    /// 관전자 베팅 에스크로 — 판돈을 지갑에서 뺀다. 잔액이 모자라거나 금액이 0 이하면 no-op(false).
    /// 원장 브로드캐스트에서 자기 베팅을 본 시점에 각 클라이언트가 스스로 호출한다(호스트가 남의
    /// 지갑을 건드리지 않는 구조).
    @discardableResult
    func escrowStarPieces(_ amount: Int) -> Bool {
        guard amount > 0, availableTokens >= amount else { return false }
        state.starPieces -= amount
        save()
        return true
    }

    /// 베팅 정산 지급. 환불도 "판돈과 같은 금액 지급" 이라 같은 경로를 쓴다.
    func creditStarPieces(_ amount: Int) {
        guard amount > 0 else { return }
        state.starPieces += amount
        save()
    }

    /// 일일 사탕 — 날짜가 바뀐 첫 틱에 지급(방치형 출석 보상). 첫 실행도 지급(웰컴 사탕).
    private func grantDailyCandyIfNeeded(now: Date) {
        let today = Self.dayKey(now)
        guard state.lastCandyDate != today else { return }
        state.lastCandyDate = today
        state.inventory[ItemKind.rareCandy.rawValue, default: 0] += RareCandy.dailyGrant
        notifyCompanionEvent(l.notifCandyTitle(item: l.itemName(.rareCandy), count: RareCandy.dailyGrant),
                             l.notifDailyCandyBody)
    }

    /// 로컬 달력 기준 YYYY-MM-DD — 일일 보상 원장 키.
    nonisolated static func dayKey(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    nonisolated static func weekKey(_ date: Date) -> String {
        let calendar = Calendar(identifier: .iso8601)
        let parts = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return "\(parts.yearForWeekOfYear ?? 0)-W\(parts.weekOfYear ?? 0)"
    }

    // MARK: 생명주기 갱신

    /// 시간 생산 틱에서 표시 상태와 부화·진화 관련 비동기 작업을 갱신한다.
    private func refreshLifecycle() {
        // 이벤트(진화/졸업/부화) 창 만료 — .levelUp 창이 끝날 때 문구 플래그를 함께 정리한다.
        // justEvolvedTo 는 여기(창 만료)에서만 지운다: 과거엔 매 update() 초입에 무조건 nil 로 밀어,
        // 진화 후 4초 창 도중 update 틱이 끼면 "…(으)로 진화했어요"→"성장했어요"로 되돌아갔다(회귀 #4).
        if let until = eventUntil, clock() > until {
            justGraduated = nil; justEvolvedTo = nil; eventUntil = nil
        }
        // 알 상태 프리패칭 — 종 pre-roll + 라인/스프라이트 예열(부화 순간 딜레이 제거).
        // 성공할 때까지 매 update 틱마다 재시도(성공 후엔 no-op). 스타터 선택 중엔 알이 없어 건너뛴다.
        if state.active == nil, !needsStarterSelection, !isHatching {
            Task { await ensureEggPrefetch() }
        }
        // 알이 부화 임계에 도달하면 부화
        if state.active == nil, state.eggUsage >= PokemonBalance.eggHatchThreshold, !isHatching {
            Task { await hatchIfNeeded() }
        }
        if state.focusEggs > 0, state.focusEggReadyDates.first.map({ $0 <= clock() }) == true,
           !isStoredEggHatching {
            Task { await hatchStoredEggIfNeeded() }
        }
        // active 인데 라인 미로딩(앱 재시작) → 로드
        if state.active != nil, currentLine == nil, !isHatching {
            Task { await loadCurrentLine() }
        }
        // 위장 메타몽이 첫 진화 임계 도달 → 리빌(재시작 등 applyUsage 킥을 못 탄 경우 백업 트리거)
        if let a = state.active, a.dittoDisguise != nil, !a.dittoRevealed, currentLine != nil,
           !isHatching, !isRevealingDitto,
           a.usedAtStage >= PokemonBalance.phaseThreshold(rarity: a.rarity, totalForms: a.totalForms, stageIndex: 0) {
            Task { await revealDitto() }
        }
        if state.active == nil { displayState = .egg }
        else if justGraduated != nil || (eventUntil != nil && clock() < eventUntil!) { displayState = .levelUp }
        else { displayState = .idle }
        save()
    }

    /// 별의모래 증분을 현재 포켓몬에 적용 — 임계 도달 시 진화/졸업.
    /// 라인 미로딩(재시작 직후·오프라인)이어도 성장량은 항상 적립하고 진화 판정만 미룬다.
    func applyUsage(_ delta: Int, maxTransitions: Int = .max) {
        guard state.active != nil else { return }
        state.active!.usedAtStage += delta
        guard let line = currentLine else { save(); return }
        var guardCount = 0
        var transitions = 0
        while state.active != nil, guardCount < 50 {
            guardCount += 1
            let a = state.active!
            guard let node = line.tree.node(withID: a.currentID) else { break }
            // 위장체는 부화 때는 다형태지만, 에셋 정규화/마이그레이션 뒤 leaf가 될 수 있다.
            // 따라서 terminal 졸업보다 먼저 리빌해야 위장 종이 도감으로 잘못 졸업하지 않는다.
            if a.dittoDisguise != nil, !a.dittoRevealed {
                if !isRevealingDitto { Task { await revealDitto() } }
                break
            }
            // 최종 진화형 도달 — 졸업은 여기서 자동으로 하지 않는다. 사용자가 직접
            // `graduateCompanion()` 을 눌러야 한다(canGraduate 가 조건을 판정). 자동 졸업은
            // 진화 수락 직후 그 개체를 곧바로 활성에서 빼앗아, 방금 진화시킨 최종형을 한 순간도
            // 못 데리고 있게 만들었다.
            if node.children.isEmpty { break }
            let threshold = PokemonBalance.phaseThreshold(
                rarity: a.rarity, totalForms: a.totalForms, stageIndex: a.stageIndex)
            let nextIndex = a.stageIndex + 1
            let next: EvoNode
            if a.plannedPathIDs.indices.contains(nextIndex),
               let planned = node.children.first(where: { $0.speciesID == a.plannedPathIDs[nextIndex] }) {
                next = planned
            } else {
                next = pickPlannedChild(node, baseID: a.baseID)
                let fallbackRoute = [node.speciesID] + makeEvolutionPlan(from: next, baseID: a.baseID)
                let repaired = Self.repairedPlan(realizedPath: a.pathIDs, stageIndex: a.stageIndex,
                                                 fallbackRoute: fallbackRoute)
                state.active!.plannedPathIDs = repaired
                state.active!.totalForms = repaired.count
                AppLog.write("evolve: repaired invalid planned path for base \(a.baseID)")
            }
            // 본가처럼 레벨만으로 게이팅한다 — acceptEvolution() 도 이미 usedAtStage 를 참조하지
            // 않고 0 으로 리셋할 뿐이다(#19). 여기서 성장치까지 같이 요구하면 acceptEvolution 이
            // 절대 실행 못 하는 조건을 사전에 막는, 실질 의미 없는 이중 게이트가 된다.
            if let requiredLevel = next.evolutionLevel {
                guard a.level >= requiredLevel else { break }
                if declinedEvolutionMonID == a.id, declinedEvolutionLevel == a.level,
                   declinedEvolutionTargetID == next.speciesID { break }
                if evolutionPrompt == nil {
                    evolutionPrompt = EvolutionPrompt(monID: a.id, fromSpeciesID: a.currentID,
                        toSpeciesID: next.speciesID, requiredLevel: requiredLevel,
                        toName: line.localizedName(next.speciesID, state.language))
                }
                break
            }
            // 레벨 메타데이터가 없는 진화(구버전 픽스처 등)만 성장치로 게이팅한다 — 본가에 대응하는
            // 레벨 값이 없어 게이트로 삼을 다른 기준이 없다.
            guard a.usedAtStage >= threshold else { break }
            guard next.evolutionTrigger == nil, next.evolutionItem == nil else { break }
            state.active!.pathIDs = Array(a.pathIDs.prefix(a.stageIndex + 1)) + [next.speciesID]
            state.active!.stageIndex += 1
            state.active!.usedAtStage = max(0, a.usedAtStage - threshold)
            fireCelebration(.evolve)
            transitions += 1
            if transitions >= maxTransitions { break }
            continue
        }
        save()
    }

    private func pickPlannedChild(_ node: EvoNode, baseID: Int) -> EvoNode {
        let fresh = node.children.filter { ch in
            ch.finalIDs.contains { !state.collectedFinals.contains("\(baseID):\($0)") }
        }
        let pool = fresh.isEmpty ? node.children : fresh
        return pool[Int(rng.next() % UInt64(pool.count))]
    }

    private func makeEvolutionPlan(from root: EvoNode, baseID: Int) -> [Int] {
        var plan = [root.speciesID]
        var node = root
        while !node.children.isEmpty {
            let next = pickPlannedChild(node, baseID: baseID)
            plan.append(next.speciesID)
            node = next
        }
        return plan
    }

    static func repairedPlan(realizedPath: [Int], stageIndex: Int, fallbackRoute: [Int]) -> [Int] {
        guard !realizedPath.isEmpty else { return fallbackRoute }
        let currentIndex = min(stageIndex, realizedPath.count - 1)
        let prefix = Array(realizedPath.prefix(currentIndex + 1))
        guard fallbackRoute.first == prefix.last else { return prefix }
        return prefix + fallbackRoute.dropFirst()
    }

    /// 루트부터 실제로 이어지는 가장 긴 ID 경로와 마지막 유효 노드. 첫 ID가 루트와 다르면 루트로 복구한다.
    private func longestValidPath(_ ids: [Int], from root: EvoNode) -> (path: [Int], lastNode: EvoNode) {
        var path = [root.speciesID]
        var node = root
        guard ids.first == root.speciesID else { return (path, node) }
        for id in ids.dropFirst() {
            guard let child = node.children.first(where: { $0.speciesID == id }) else { break }
            path.append(id)
            node = child
        }
        return (path, node)
    }

    /// 저장된 실제 경로와 계획을 현재 에셋 트리에 맞춘다. 완전한 계획만 재사용해 재시작 시 RNG를 소비하지 않는다.
    private func normalizedEvolutionState(_ saved: MonState, from root: EvoNode) -> MonState {
        var normalized = saved
        let realized = longestValidPath(saved.pathIDs, from: root)
        let candidate = longestValidPath(saved.plannedPathIDs, from: root)
        let canReusePlan = candidate.path == saved.plannedPathIDs
            && candidate.path.starts(with: realized.path)
            && candidate.lastNode.children.isEmpty
        let plan: [Int]
        if canReusePlan {
            plan = candidate.path
        } else {
            let suffix = makeEvolutionPlan(from: realized.lastNode, baseID: saved.baseID)
            plan = realized.path + suffix.dropFirst()
        }
        normalized.pathIDs = realized.path
        normalized.plannedPathIDs = plan
        normalized.stageIndex = realized.path.count - 1
        normalized.totalForms = plan.count
        return normalized
    }

    /// 졸업 가능 여부 — 최종 진화형에 도달했으면 언제든 사용자가 직접 졸업시킬 수 있다.
    /// 진화가 없는 종(totalForms==1)만 레벨 30을 함께 요구한다(#19): 진화를 거친 종은 그 마지막
    /// 진화 요구 레벨이 이미 관문이었지만, 무진화 종은 그 관문이 아예 없어 대신 세우는 기준이다.
    var canGraduate: Bool {
        guard let a = state.active, let line = currentLine,
              line.tree.node(withID: a.currentID)?.children.isEmpty == true else { return false }
        return a.totalForms > 1 || a.level >= PokemonBalance.graduationRequiredLevel
    }

    /// 졸업 — 도감에 기록하고 **개체는 박스로 보낸 뒤** 새 알을 시작한다. 사용자가 직접 누르는
    /// 액션이다(자동 아님): 다음 포켓몬으로 넘어가는 버튼이지, 지금 개체를 버리는 것이 아니다.
    /// 박스에 남으므로 `switchCompanion(to:)` 로 언제든 다시 데려와 계속 키울 수 있다.
    @discardableResult
    func graduateCompanion() -> Bool {
        guard canGraduate else { return false }
        graduate()
        return true
    }

    private func graduate() {
        guard let a = state.active else { return }
        let finalID = a.currentID
        state.collectedFinals.insert("\(a.baseID):\(finalID)")
        state.dex.append(DexEntry(baseID: a.baseID, finalID: finalID,
                                  chainOrder: a.pathIDs, rarity: a.rarity, caughtAt: clock(),
                                  isShiny: a.isShiny, nature: a.nature,
                                  names: currentLine.map { line in   // 체인 각 종의 다국어 이름 저장(표시 즉시)
                                      Dictionary(uniqueKeysWithValues:
                                          a.pathIDs.compactMap { id in line.names[id].map { (id, $0) } })
                                  }))
        let name = currentLine?.localizedName(finalID, state.language) ?? ""
        justGraduated = name
        notifyCompanionEvent(l.notifGraduateTitle, l.notifGraduateBody(name))
        eventUntil = clock().addingTimeInterval(6)
        // 도감은 기록만 남는다(DexEntry 엔 레벨·경험치가 없다) — 개체 자체는 박스로 옮겨 계속
        // 키울 수 있게 한다. 예전엔 여기서 그냥 버려서, 졸업이 곧 그 개체의 영구 삭제였다.
        state.boxedMons.append(a)
        state.active = nil
        state.care = PetCareState(lastNeedAt: clock(), lastUpdatedAt: clock())
        activeGeneration += 1
        currentLine = nil
        // 졸업 보상 알은 보관 알과 같은 5분 타이머를 쓴다. 예전엔 eggUsage(누적 임계) 알을 줬는데,
        // 그 값을 채우는 생산 경로가 Pokédoro 개편으로 사라져(accrue 는 호출자가 없다) 영원히
        // 부화하지 않았다 — 졸업이 곧 진행 정지였다. 타이머 경로는 hatchStoredEggIfNeeded 가
        // 이미 돌리고 있고, 활성이 비어 있으면 박스가 아니라 활성으로 부화한다.
        state.focusEggs = min(999, state.focusEggs + 1)
        state.focusEggReadyDates.append(clock().addingTimeInterval(Self.storedEggHatchDelay))
    }

    // MARK: 인벤토리 / 이상한 사탕

    var rareCandyCount: Int { itemCount(.rareCandy) }
    func itemCount(_ kind: ItemKind) -> Int { state.inventory[kind.rawValue] ?? 0 }
    /// 이로치 부적 보유 여부 — 보유형이라 개수>0 = 소유(부화 shiny 분모를 낮춘다).
    var ownsShinyCharm: Bool { itemCount(.shinyCharm) > 0 }

    /// 소유 아이템(개수>0) — 가방 목록. 정렬은 ItemKind.allCases 순서.
    var ownedItems: [(kind: ItemKind, count: Int)] {
        ItemKind.allCases.compactMap { k in
            let c = itemCount(k)
            return c > 0 ? (k, c) : nil
        }
    }

    /// 이상한 사탕 사용 가능 — 활성 포켓몬 + 라인 로딩 완료 + 재고>0.
    /// 라인 미로딩(재시작 직후·오프라인)이면 비활성 — 사탕이 진화 없이 적립만 되는 것 방지.
    var canUseRareCandy: Bool { hasActive && currentLine != nil && rareCandyCount > 0 }

    /// 사탕 사용 결과 — UI 피드백 분기용.
    enum CandyUseResult: Equatable { case evolved, graduated, progressed, unavailable }

    /// 이상한 사탕 1개 사용 — 현재 포켓몬에 +RareCandy.xp. applyUsage 재사용으로 이월·진화·졸업·연출 자동.
    /// 사탕 XP 는 현재 진화 진행에만 반영한다.
    @discardableResult
    func useRareCandy() -> CandyUseResult {
        guard canUseRareCandy else { return .unavailable }
        state.inventory[ItemKind.rareCandy.rawValue] = rareCandyCount - 1
        let beforeStage = state.active?.stageIndex ?? 0
        // 진화 안 될 때(부분 진행)도 즉시 "+XP" 피드백 — CompanionHeader 가 연출과 별개로 표시.
        candyFeedbackAmount = RareCandy.xp
        candyFeedbackSeq += 1
        let oldLevel = state.active!.level
        state.active!.usedAtStage += RareCandy.xp
        state.active!.levelExperience += RareCandy.xp
        let newLevel = state.active!.level
        if newLevel > oldLevel { queueMoveLearning(from: oldLevel + 1, through: newLevel) }
        applyUsage(0, maxTransitions: 1)   // 사탕 1개는 최대 1단계만 진행한다.
        if state.active == nil { return .graduated }
        if state.active!.stageIndex > beforeStage { return .evolved }
        return .progressed
    }

    // MARK: 민트 (성격 랜덤 재설정)

    /// 민트 사용 가능 — 활성 포켓몬 + 재고>0. 성격은 MonState 에만 있어 진화 라인 로딩과 무관하다
    /// (사탕과 달리 currentLine 조건 없음 — 재시작 직후·오프라인에도 사용 가능).
    var canUseMint: Bool { hasActive && itemCount(.mint) > 0 }

    /// 민트 1개 사용 — 현재 포켓몬 성격을 '현재와 다른' 무작위 성격으로 교체(반드시 바뀐다). 성장·shiny·
    /// 종·usedAtStage·통계 전부 무관(순수 코스메틱). 사용 불가면 nil(무소모). 바뀐 성격을 반환(피드백용).
    @discardableResult
    func useMint() -> PokemonNature? {
        guard canUseMint, state.active != nil else { return nil }
        let cur = state.active!.nature
        let pool = PokemonNature.allCases.filter { $0 != cur }   // cur=nil(구버전 개체)이면 25종 전체
        let new = pool[Int(rng.next() % UInt64(pool.count))]
        state.active!.nature = new
        state.inventory[ItemKind.mint.rawValue] = itemCount(.mint) - 1
        mintFeedbackNature = new
        mintFeedbackSeq += 1
        save()
        return new
    }

    func canUseEvolutionItem(_ kind: ItemKind) -> Bool {
        guard itemCount(kind) > 0, let key = kind.evolutionKey,
              let mon = state.active, let node = currentLine?.tree.node(withID: mon.currentID) else { return false }
        return node.children.contains { child in
            key == "trade" ? child.evolutionTrigger == "trade"
                : child.evolutionTrigger == "use-item" && child.evolutionItem == key
        }
    }

    @discardableResult
    func useEvolutionItem(_ kind: ItemKind) -> Bool {
        guard canUseEvolutionItem(kind), let key = kind.evolutionKey,
              let line = currentLine, let mon = state.active,
              let node = line.tree.node(withID: mon.currentID),
              let next = node.children.first(where: { child in
                  key == "trade" ? child.evolutionTrigger == "trade"
                      : child.evolutionTrigger == "use-item" && child.evolutionItem == key
              }) else { return false }
        state.inventory[kind.rawValue] = itemCount(kind) - 1
        state.active!.pathIDs = Array(mon.pathIDs.prefix(mon.stageIndex + 1)) + [next.speciesID]
        state.active!.plannedPathIDs = state.active!.pathIDs
            + Array(makeEvolutionPlan(from: next, baseID: mon.baseID).dropFirst())
        state.active!.stageIndex += 1
        state.active!.totalForms = state.active!.plannedPathIDs.count
        state.active!.usedAtStage = 0
        let newName = line.localizedName(next.speciesID, state.language)
        justEvolvedTo = newName
        fireCelebration(.evolve)
        eventUntil = clock().addingTimeInterval(4)
        notifyCompanionEvent(l.notifEvolveTitle, l.notifEvolveBody(newName))
        save()
        return true
    }

    // MARK: 상점 (재화 = 별의모래)

    /// 상점에서 쓸 수 있는 별의모래 = 누적 생산량 − 상점 지출 누적. 성장 미터(usedSinceInstall)는
    /// 여기선 읽기만 — 구매는 spentTokens 만 올려 잔액을 깎는다(진화 진행·오늘/주/월 통계 무영향).
    var availableTokens: Int { max(0, state.starPieces) }

    /// 상점 판매 아이템 — shopPrice 있는 것만. 가격 저렴한 순, 단 구매 완료한 보유형은 맨 아래로.
    var purchasableItems: [ItemKind] {
        ItemKind.allCases
            .filter { $0.shopPrice != nil }
            .sorted { a, b in
                // 구매 완료한 보유형(이로치 부적 등)은 맨 아래로 — 재구매 불가라 위에 있을 이유가 없다.
                let aDone = a.isPassive && itemCount(a) > 0
                let bDone = b.isPassive && itemCount(b) > 0
                if aDone != bDone { return !aDone }
                return (a.shopPrice ?? 0) < (b.shopPrice ?? 0)   // 나머지는 가격 저렴한 순
            }
    }

    /// 상점 표시 순서 — 판매 아이템 + (활성 포켓몬 있을 때) 알 3종을 하나의 가격 오름차순 목록으로 병합.
    /// 정렬 규칙은 purchasableItems 와 동일: 구매 완료한 보유형은 맨 아래, 나머지는 가격 저렴한 순.
    /// 알은 즉시 액션이라 '보유' 개념이 없어 가격 순서에만 참여한다.
    ///
    /// 등급 알끼리 붙여 '티어 사다리'로 묶어 보이게 하는 안도 검토했으나 채택하지 않았다 — 지금의 순수
    /// 가격 오름차순은 "알이 무조건 맨 아래로 append 돼 더 비싼 부적보다 아래에 놓이던" 표시 회귀를
    /// 고치며 들어온 규칙이라(ShopTests 참조), 그룹 배치는 그 회귀를 부분적으로 되살린다. 티어 관계는
    /// 카드의 등급 배지로 읽히게 한다.
    var shopEntries: [ShopEntry] {
        var entries: [ShopEntry] = purchasableItems.map { ShopEntry.item($0) }
        entries += FreshEgg.shopTiers.map { ShopEntry.egg($0) }
        return entries.sorted { a, b in
            let aDone = isPurchasedPassive(a)
            let bDone = isPurchasedPassive(b)
            if aDone != bDone { return !aDone }
            return a.price < b.price
        }
    }

    /// 구매 완료한 보유형(이로치 부적 등)인지 — shopEntries 정렬에서 맨 아래로 보낼 판정.
    private func isPurchasedPassive(_ entry: ShopEntry) -> Bool {
        guard case .item(let kind) = entry else { return false }   // 알은 즉시 액션 — 보유 개념 없음
        return kind.isPassive && itemCount(kind) > 0
    }

    /// 구매 가능 — 잔액이 그 아이템 가격 이상(상점 미판매면 false). 활성/알 무관(재고는 미리 쌓아둘 수 있음).
    func canBuy(_ kind: ItemKind) -> Bool {
        guard let price = kind.shopPrice else { return false }
        if kind.isPassive && itemCount(kind) > 0 { return false }   // 보유형은 1회만(재구매 불가)
        return availableTokens >= price
    }

    /// 아이템 1개 구매 — 지갑에서 price 차감, 인벤토리 +1. usedSinceInstall(성장·통계)·진화 진행엔
    /// 무영향(지출 원장만 증가). 잔액 부족/미판매면 no-op(false).
    @discardableResult
    func buy(_ kind: ItemKind) -> Bool {
        guard let price = kind.shopPrice, availableTokens >= price else { return false }
        if kind.isPassive && itemCount(kind) > 0 { return false }   // 보유형 중복 구매 방지(방어)
        state.starPieces -= price
        state.inventory[kind.rawValue, default: 0] += 1
        save()
        return true
    }

    // 사탕 전용 래퍼 — 기존 호출부/테스트 호환.
    var canBuyRareCandy: Bool { canBuy(.rareCandy) }
    @discardableResult
    func buyRareCandy() -> Bool { buy(.rareCandy) }

    // MARK: 알 (리롤 — 현재 포켓몬 폐기, 도감·확률 무영향)

    /// 현재 알이 보증하는 등급 하한(UI 표시용). 활성 포켓몬이 있으면 알이 없으므로 nil.
    var eggGuarantee: Rarity? { state.active == nil ? state.eggTier : nil }

    /// 알 구매 가능 — 폐기할 활성 포켓몬이 있고 지갑이 그 티어 가격 이상일 때만.
    /// 알 상태에서도 살 수 있게 하는 안은 채택하지 않았다(기존 새 알과 게이트 통일) — 알끼리 교체하는
    /// 동작을 새로 만들지 않고, 상점의 알은 언제나 "지금 개체를 놓아주고 다시 뽑는다"는 한 가지 의미만 갖는다.
    func canBuyEgg(_ tier: Rarity?) -> Bool {
        // 파는 티어인지 먼저 확인한다 — 만족 불가능한 보증(전설: capture_rate 로 표현 불가)을 사면
        // 두 롤 경로 모두 후보가 0개라 알이 영영 안 깨지고, 부화가 없으니 보증도 안 풀리며,
        // 새 알 구매는 `hasActive` 에 막혀 되돌릴 수단이 없다. 가격만 계산되면 값이 빠져나가므로
        // 판매 목록을 여기서 강제한다(호출부 하나가 실수하면 토큰이 통째로 사라진다).
        guard FreshEgg.shopTiers.contains(tier) else { return false }
        return availableTokens >= FreshEgg.price(guaranteeing: tier)
    }

    /// 알 구매 — 현재 포켓몬을 폐기하고 처음부터 인큐베이션하는 새 알로. 지갑에서 가격 차감.
    /// graduate() 의 알-리셋만 미러링하고 dex/collectedFinals(도감·확률 가중)는 손대지 않는다
    /// → "뽑은 적 없던 것처럼". 성장(usedAtStage)은 소멸(추가 비용).
    ///
    /// 여기서 종을 롤하지 않는다 — 롤에는 네트워크가 필요해서 오프라인이면 토큰만 사라진다. 보증만
    /// 상태(`eggTier`)에 적고, 실제 롤은 프리패치/부화 경로가 그 보증을 읽어 수행한다.
    @discardableResult
    func buyEgg(_ tier: Rarity?) -> Bool {
        guard canBuyEgg(tier) else { return false }
        state.starPieces -= FreshEgg.price(guaranteeing: tier)
        state.focusEggs = min(999, state.focusEggs + 1)
        state.focusEggReadyDates.append(clock().addingTimeInterval(Self.storedEggHatchDelay))
        AppLog.write("egg purchased: added to egg inventory")
        save()
        return true
    }

    // 보증 없는 기본 알 래퍼 — 기존 호출부/테스트 호환.
    var canBuyFreshEgg: Bool { canBuyEgg(nil) }
    @discardableResult
    func buyFreshEgg() -> Bool { buyEgg(nil) }

    /// 보관 알은 획득 5분 뒤 현재 동행·모험을 건드리지 않고 새 포켓몬으로 부화해 박스에 들어간다.
    private func hatchStoredEggIfNeeded() async {
        guard !isStoredEggHatching, state.focusEggs > 0,
              state.focusEggReadyDates.first.map({ $0 <= clock() }) == true else { return }
        isStoredEggHatching = true
        defer { isStoredEggHatching = false }
        guard let baseID = await chooseBase(),
              let line = try? await provider.line(baseSpeciesID: baseID) else { return }
        let shiny = Self.rollsShiny(roll: rng.next(), charmOwned: ownsShinyCharm)
        let nature = PokemonNature.allCases[Int(rng.next() % UInt64(PokemonNature.allCases.count))]
        let plan = makeEvolutionPlan(from: line.tree, baseID: line.baseID)
        let mon = MonState(baseID: line.baseID, pathIDs: [line.baseID], plannedPathIDs: plan,
                           stageIndex: 0, usedAtStage: 0, rarity: line.rarity, totalForms: plan.count,
                           isShiny: shiny, nature: nature)
        // 동행이 비어 있으면(졸업 직후 등) 박스가 아니라 바로 동행으로 부화한다 — 그러지 않으면
        // 졸업 후 동행 없는 상태로 남아 사용자가 박스에서 직접 꺼내야 한다.
        if state.active == nil {
            state.active = mon
            activeGeneration += 1
            currentLine = line
            displayState = .levelUp
            eventUntil = clock().addingTimeInterval(4)
            fireCelebration(.hatch(shiny: shiny))
        } else {
            state.boxedMons.append(mon)
        }
        state.focusEggs -= 1
        state.focusEggReadyDates.removeFirst()
        let name = line.localizedName(line.baseID, state.language)
        notifyCompanionEvent(shiny ? l.notifShinyHatchTitle : l.notifHatchTitle,
                             shiny ? l.notifShinyHatchBody(name) : l.notifHatchBody(name))
        AppLog.write("stored egg hatched: base=\(line.baseID) shiny=\(shiny)")
        save()
    }

    /// 구버전 세이브의 보관 알에는 시각이 없다. 업데이트 시점부터 5분 타이머를 시작한다.
    ///
    /// **바꿀 게 없으면 저장하지 않는다.** init 이 load() 직후 무조건 호출하므로, 무조건 save() 하면
    /// 손상 세이브를 `.corrupt` 로 옮겨 둔 자리에 파일을 곧바로 되만들어 그 복구 장치를 무력화한다
    /// (load 의 백업 분기는 "다음 save 가 원본을 덮어쓰기 전에" 옮겨두는 것이 전제다).
    private func reconcileStoredEggDates() {
        let trimmed = Array(state.focusEggReadyDates.sorted().prefix(state.focusEggs))
        var dates = trimmed
        while dates.count < state.focusEggs {
            dates.append(clock().addingTimeInterval(Self.storedEggHatchDelay))
        }
        guard dates != state.focusEggReadyDates else { return }
        state.focusEggReadyDates = dates
        save()
    }

    /// companion 이벤트 시스템 알림(.app + 토글 ON 일 때만). 한도 알림과 독립.
    private var notifSeq = 0
    private func notifyCompanionEvent(_ title: String, _ body: String) {
        guard AppEnv.isBundledApp else { return }
        guard !(UserDefaults.standard.object(forKey: "doNotDisturb") as? Bool ?? false) else { return }
        guard UserDefaults.standard.object(forKey: "companionNotifications") as? Bool ?? true else { return }
        notifSeq += 1
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "companion-event-\(notifSeq)", content: content, trigger: nil))
    }

    // MARK: 부화

    func hatchIfNeeded() async {
        guard state.active == nil, !isHatching, state.eggUsage >= PokemonBalance.eggHatchThreshold else { return }
        // 프리패치가 "종 롤 중"(pending 미확정)일 때만 대기 — 이중 rng 소비 방지.
        // pending 확정 후의 예열(라인/스프라이트)과는 동시 진행해도 안전하다.
        guard state.pendingHatchID != nil || !prefetchInFlight else { return }
        // isHatching 을 롤~부화 전체에 defer 로 잠근다. 과거엔 chooseBase 후 isHatching 을 잠깐
        // 내렸다가(hatch 자체 가드 통과용) hatch 를 호출해, 그 await 창에서 다른 update 틱이
        // 두 번째 종을 롤하는 경합이 있었다. hatchCore 는 isHatching 을 재검사하지 않으므로
        // 여기서 소유한 락 하나로 롤·부화가 원자적으로 보호된다.
        let generation = activeGeneration
        isHatching = true
        defer { isHatching = false }
        // 프리패칭된 종이 있으면 그대로 사용(라인·스프라이트 예열됨 → 딜레이 ~0), 없으면 지금 롤.
        let base: Int?
        if let pending = state.pendingHatchID {
            base = pending
        } else {
            base = await chooseBase()
        }
        guard let base else { return }   // 네트워크 불안정 → 알 유지, 다음 update 틱에 재시도
        // 세대 검사는 **여기서** 해야 한다. `chooseBase()` 대기 창에서 상태가 통째로 교체되면
        // (세이브 불러오기) 그 뒤에 진입하는 hatchCore 는 *교체 이후*의 세대를 캡처해 자기 가드가
        // 무조건 통과한다 — 옛 롤 결과가 불러온 개체를 덮어쓰고 save() 로 디스크에 박힌다.
        guard activeGeneration == generation, state.active == nil else {
            AppLog.write("hatch: discarded before core — subject replaced during species roll")
            kickLineLoadIfNeeded()
            return
        }
        state.pendingHatchID = nil
        await hatchCore(baseID: base)
    }

    /// 부화가 폐기된 뒤 남은 개체(대개 방금 불러온 개체)의 진화 라인을 다시 로드한다.
    /// `loadCurrentLine` 은 `!isHatching` 을 요구하므로 부화 중에 걸린 로드는 조용히 실패한다 —
    /// 아무도 재시도하지 않으면 다음 update 틱(기본 120초)까지 이름이 "Token Egg" 로 남는다.
    /// Task 본문은 현재 동기 실행(= defer 로 isHatching 해제)이 끝난 뒤 돌므로 락이 이미 풀려 있다.
    private func kickLineLoadIfNeeded() {
        guard state.active != nil, currentLine == nil else { return }
        Task { await loadCurrentLine() }
    }

    // MARK: 알 프리패칭

    private var prefetchInFlight = false
    private var prefetchedLineID: Int?   // 라인·스프라이트 예열 완료한 종(세션 메모리)

    /// 알 상태에서 부화를 미리 준비 — ① 종 pre-roll(pendingHatchID, 영속) ② 진화 라인
    /// fetch(provider 캐시 적재) ③ 스프라이트 예열(정적+애니메이션+shiny 애니메이션).
    /// 전부 성공하면 부화 순간 네트워크 0. 실패 지점부터 다음 update 틱에 이어서 재시도.
    private func ensureEggPrefetch() async {
        guard state.active == nil, !isHatching, !prefetchInFlight else { return }
        let generation = activeGeneration
        prefetchInFlight = true
        defer { prefetchInFlight = false }

        if state.pendingHatchID == nil {
            guard let id = await chooseBase() else { return }   // 오프라인 → 다음 틱 재시도
            // await 사이에 부화가 끝났거나(active != nil) 상태가 통째로 교체됐으면(세이브 불러오기)
            // 이 롤을 버린다 — 안 그러면 불러온 알의 pre-roll 을 남의 롤로 덮어쓴다.
            guard state.active == nil, activeGeneration == generation else { return }
            state.pendingHatchID = id
            save()
        }
        guard let id = state.pendingHatchID, prefetchedLineID != id else { return }
        guard let line = try? await provider.line(baseSpeciesID: id) else { return }   // 라인 예열
        // 스프라이트 예열 — 부화 직후 보일 것들: base 정적+애니메이션, shiny 롤(1/64) 대비 shiny 애니메이션.
        // .app 번들에서만(단위 테스트가 실네트워크에 닿지 않도록 — 알림과 동일한 게이트).
        if AppEnv.isBundledApp {
            _ = await SpriteStore.shared.data(speciesID: line.baseID, animated: false, shiny: false)
            _ = await SpriteStore.shared.data(speciesID: line.baseID, animated: true, shiny: false)
            _ = await SpriteStore.shared.data(speciesID: line.baseID, animated: true, shiny: true)
        }
        prefetchedLineID = id
    }

    func hatch(baseID: Int) async {
        guard !isHatching else { return }
        isHatching = true
        defer { isHatching = false }
        await hatchCore(baseID: baseID)
    }

    // MARK: 메타몽 위장/리빌

    /// 메타몽 위장 롤 판정(순수) — common·≥2형태만, 미리 뽑은 roll 값으로 1/128. (부수효과 없이 xctest)
    nonisolated static func dittoDisguiseHit(rarity: Rarity, totalForms: Int, roll: UInt64) -> Bool {
        rarity == .common && totalForms >= 2 && roll % PokemonOdds.dittoDisguiseDenominator == 0
    }

    /// 이로치 부화 판정(순수) — 미리 뽑은 roll 값 % 분모(부적 보유 48, 없으면 64)==0. (부수효과 없이 xctest)
    nonisolated static func rollsShiny(roll: UInt64, charmOwned: Bool) -> Bool {
        roll % (charmOwned ? ShinyCharm.shinyDenominator : PokemonOdds.shinyDenominator) == 0
    }

    /// 실제 부화 로직 — isHatching 락은 호출자(hatch / hatchIfNeeded)가 소유·해제한다.
    private func hatchCore(baseID: Int) async {
        let generation = activeGeneration
        guard let line = try? await provider.line(baseSpeciesID: baseID) else {
            AppLog.write("hatch: line fetch failed for base \(baseID) — egg kept, retry next tick")
            return
        }
        // 라인 fetch 창(네트워크) 동안 활성 개체가 교체됐으면 이 부화 결과를 폐기한다. 세이브 불러오기가
        // 그 창에 들어오면, 여기서 멈추지 않는 한 갓 부화한 개체가 방금 불러온 개체를 덮어쓴다.
        // (loadCurrentLine·revealDitto 와 같은 세대 가드 — isHatching 락은 같은 앱 내 중복 부화만 막는다.)
        guard activeGeneration == generation else {
            AppLog.write("hatch: discarded — active subject replaced during line fetch")
            kickLineLoadIfNeeded()
            return
        }
        // 산 보증을 지키는 마지막 관문 — 진짜 등급을 아는 건 여기뿐이다(후보 인덱스엔 capture_rate 만
        // 있고 is_legendary 가 없다). 필터가 어긋났으면(인덱스 stale 등) 낮은 등급을 그냥 내주지 말고
        // 알을 유지한 채 pre-roll 만 버려 다음 틱에 다시 뽑는다 — 사용자는 산 보증을 계속 들고 있는다.
        if let tier = state.eggTier, line.rarity.sortRank < tier.sortRank {
            AppLog.write("hatch: rolled \(line.rarity) below guaranteed \(tier) — discarded, re-roll next tick")
            state.pendingHatchID = nil
            prefetchedLineID = nil
            save()
            return
        }
        currentLine = line
        // 부화 임계 초과분은 부화체 성장에 이월(낭비 없음).
        let overflow = max(0, state.eggUsage - PokemonBalance.eggHatchThreshold)
        state.eggUsage = 0
        state.eggTier = nil   // 보증은 이 부화로 소비된다(다음 알은 다시 무보증)
        // 개체 롤 — shiny(1/64)·성격(25종)은 부화 순간 확정, 진화해도 유지.
        let isShiny = Self.rollsShiny(roll: rng.next(), charmOwned: ownsShinyCharm)
        let nature = PokemonNature.allCases[Int(rng.next() % UInt64(PokemonNature.allCases.count))]
        // 메타몽 위장 롤 — common·≥2형태에 한해 1/128. .app 게이트(&& 단락 → 비앱에선 rng 미소비로
        // 기존 테스트 RNG 시퀀스 무영향). 위장/리빌 로직은 상태 기반으로 별도 테스트한다.
        var dittoDisguise: Int?
        if dittoDisguiseRollingEnabled,
           Self.dittoDisguiseHit(rarity: line.rarity, totalForms: line.totalForms, roll: rng.next()) {
            dittoDisguise = line.baseID
        }
        let evolutionPlan = makeEvolutionPlan(from: line.tree, baseID: line.baseID)
        // 위장 중엔 이로치를 숨긴다 — 부화 알림·연출도 일반체로(정체는 리빌 때 공개).
        let showShiny = isShiny && dittoDisguise == nil
        activeGeneration += 1
        state.active = MonState(baseID: line.baseID, pathIDs: [line.baseID], plannedPathIDs: evolutionPlan,
                                stageIndex: 0, usedAtStage: 0, rarity: line.rarity, totalForms: evolutionPlan.count,
                                isShiny: isShiny, nature: nature, dittoDisguise: dittoDisguise)
        AppLog.write("hatch: base=\(line.baseID) rarity=\(line.rarity) shiny=\(isShiny) forms=\(evolutionPlan.count) ditto=\(dittoDisguise != nil)")
        let name = line.localizedName(line.baseID, state.language)
        notifyCompanionEvent(showShiny ? l.notifShinyHatchTitle : l.notifHatchTitle,
                             showShiny ? l.notifShinyHatchBody(name) : l.notifHatchBody(name))
        justEvolvedTo = nil        // 새 부화는 "성장" 문구(진화 아님) — 직전 진화명이 남아 표시되지 않게
        displayState = .levelUp
        eventUntil = clock().addingTimeInterval(4)
        if overflow > 0 { applyUsage(overflow) }   // 이월분 즉시 반영(필요 시 진화/리빌까지)
        // 연출은 이월 진화 뒤에 발화 — 이월 evolve 가 shiny 부화 버스트를 덮지 않도록
        // 마지막 이벤트를 hatch 로 유지한다. 이월로 즉시 졸업한 극단 케이스면 생략(이미 도감행).
        if state.active != nil { fireCelebration(.hatch(shiny: showShiny)) }
        save()
    }

    /// 위장 → 리빌: 진화 못 하는 메타몽이 "첫 진화 임계"에서 진화 대신 정체를 드러내는 순간.
    /// Ditto 라인 로드 후 상태 변환(rare·단일형태·초과분 이월, isShiny/nature 유지) + 연출·알림.
    private func revealDitto() async {
        guard let a = state.active, a.dittoDisguise != nil, !a.dittoRevealed, !isRevealingDitto else { return }
        let generation = activeGeneration
        let firstEvoThr = PokemonBalance.phaseThreshold(rarity: a.rarity, totalForms: a.totalForms, stageIndex: 0)
        guard a.usedAtStage >= firstEvoThr else { return }   // 임계 미달 방어
        isRevealingDitto = true
        defer { isRevealingDitto = false }
        guard let dittoLine = try? await provider.line(baseSpeciesID: PokemonOdds.dittoSpeciesID) else {
            AppLog.write("ditto reveal: line fetch failed — retry next tick"); return
        }
        guard activeGeneration == generation,
              var m = state.active, m.dittoDisguise != nil, !m.dittoRevealed else { return }
        let latestFirstEvoThr = PokemonBalance.phaseThreshold(rarity: m.rarity, totalForms: m.totalForms, stageIndex: 0)
        guard m.usedAtStage >= latestFirstEvoThr else { return }
        let disguiseName = currentLine?.localizedName(m.baseID, state.language) ?? "#\(m.baseID)"
        let carryOver = max(0, m.usedAtStage - latestFirstEvoThr)   // 위장체 첫 진화 초과분 → 메타몽 성장 이월
        // 메타몽으로 전환 — rarity/forms 는 로드한 라인에서, isShiny/nature/dittoDisguise 는 유지.
        m.baseID = dittoLine.baseID
        let evolutionPlan = makeEvolutionPlan(from: dittoLine.tree, baseID: dittoLine.baseID)
        m.pathIDs = [dittoLine.baseID]
        m.plannedPathIDs = evolutionPlan
        m.stageIndex = 0
        m.rarity = dittoLine.rarity
        m.totalForms = evolutionPlan.count
        m.usedAtStage = carryOver
        m.dittoRevealed = true
        let shiny = m.isShiny
        state.active = m
        currentLine = dittoLine
        AppLog.write("ditto reveal: disguise=\(m.dittoDisguise ?? -1) → ditto rarity=\(dittoLine.rarity) shiny=\(shiny)")
        fireCelebration(.dittoReveal(shiny: shiny))
        displayState = .levelUp
        eventUntil = clock().addingTimeInterval(5)
        notifyCompanionEvent(shiny ? l.notifShinyDittoRevealTitle : l.notifDittoRevealTitle,
                             shiny ? l.notifShinyDittoRevealBody(disguiseName) : l.notifDittoRevealBody(disguiseName))
        save()
        applyUsage(0)   // 이월분으로 메타몽 졸업 재평가(rare 3B라 보통 즉시 졸업 아님)
    }

    private func loadCurrentLine() async {
        guard let a = state.active, currentLine == nil, !isHatching else { return }
        let generation = activeGeneration
        isHatching = true
        defer { isHatching = false }
        if let line = try? await provider.line(baseSpeciesID: a.baseID) {
            // await 중 사용량·민트 등 활성 상태는 계속 바뀔 수 있다. 요청 당시 스냅샷을 다시 쓰지 말고
            // 같은 개체가 아직 활성인 경우에만 최신 상태를 정규화한다.
            guard activeGeneration == generation,
                  let latest = state.active, latest.baseID == a.baseID, currentLine == nil else { return }
            state.active = normalizedEvolutionState(latest, from: line.tree)
            currentLine = line
            save()   // 마이그레이션 선택을 사용량 재평가 전에 영속화해 재시작마다 다시 롤리지 않는다.
            applyUsage(0)   // 라인 미로딩 동안 적립된 사용량이 임계를 넘었으면 지금 진화 판정
        }
    }

    /// 부화 종 선정 — 하드코딩 풀 없이 PokéAPI 1~5세대 base 전체(329종)에서 가중 선택.
    ///   ① base 인덱스(id + capture_rate)를 GraphQL 1쿼리로 취득(30일 디스크 캐시 → 보통 0콜)
    ///   ② 가중치 = 공식 capture_rate 그대로(캐터피 255 vs 뮤츠 3 = 85:1, 전설군 ≈ 0.77%)
    ///      단, 이미 수집한 base 는 가중치 ½(미수집 부스트 — 재부화/shiny 사냥은 열어둠)
    ///   ③ 누적 가중치에서 정확히 1롤 — 루프/재롤 없음, 시간 상한 확정적
    /// 인덱스 취득 실패(오프라인 + 캐시 없음) 시 nil → 알 유지, 다음 갱신 틱 재시도.
    private func chooseBase() async -> Int? {
        let tier = state.eggTier
        if let full = try? await provider.baseSpeciesIndex(), !full.isEmpty {
            // 등급 보증 알은 후보를 먼저 좁힌다 — capture_rate 상한이 곧 등급 하한이므로
            // (Rarity.captureRateCeiling) 전설도 자연히 포함된다("희귀 이상"에 전설이 들어가는 게 정상).
            // 좁힌 결과가 비면 보증을 못 지키므로 전체 풀로 폴백하지 말고 알을 유지한다(다음 틱 재시도).
            let index = tier.map { t in full.filter { t.includes(captureRate: $0.captureRate) } } ?? full
            guard !index.isEmpty else {
                AppLog.write("hatch: no candidate for guaranteed \(tier?.rawValue ?? "none") — egg kept, retry next tick")
                return nil
            }
            let weights = index.map { e in
                state.collectedFinals.contains(where: { $0.hasPrefix("\(e.id):") })
                    ? max(1, e.captureRate / 2) : max(1, e.captureRate)
            }
            let total = weights.reduce(0, +)
            var r = Int(rng.next() % UInt64(total))
            for (i, w) in weights.enumerated() {
                r -= w
                if r < 0 { return index[i].id }
            }
            return index.last?.id   // 도달 불가(방어)
        }
        // GraphQL base 인덱스 엔드포인트 장애 → REST 폴백. 부화가 한 엔드포인트에 묶이지 않게.
        AppLog.write("hatch: base index unavailable — REST fallback")
        return await chooseBaseViaREST()
    }

    /// REST 폴백 — animated 에셋 지원 범위에서 무작위 id 를 뽑아 base 인지 확인(rejection sampling).
    /// GraphQL 인덱스가 죽어도 부화가 되게 한다. 가중치(capture_rate)는 생략 — 희귀도는 부화 후
    /// line() 이 실제 capture_rate 로 계산하므로 결과 개체의 등급은 정확하다. 인덱스 복구 시 가중 선택 재개.
    private func chooseBaseViaREST() async -> Int? {
        let tier = state.eggTier
        for attempt in 1...16 {
            let ids = PokemonAssets.animatedSpeciesIDs
            let id = Int(rng.next() % UInt64(ids.count)) + ids.lowerBound
            do {
                if let bs = try await provider.baseSpecies(id: id) {
                    // 등급 보증은 가중 경로와 **같은 기준**으로 여기서도 걸러야 한다 — 이 폴백만 빠지면
                    // GraphQL 인덱스 장애 때 보증이 조용히 깨진다. 못 찾으면 알 유지(구매 소멸 금지).
                    if let tier, !tier.includes(captureRate: bs.captureRate) { continue }
                    AppLog.write("hatch: REST fallback picked base \(id) (cap \(bs.captureRate), \(attempt) tries)")
                    return id
                }
                // nil = base 아님(진화 중간체) → 다음 시도
            } catch {
                AppLog.write("hatch: REST fallback network error — retry next tick: \(error)")
                return nil   // REST 도 불가 → 알 유지, 다음 update 틱 재시도
            }
        }
        AppLog.write("hatch: REST fallback exhausted 16 tries")
        return nil
    }

    // MARK: 세이브 이전 (기기 교체)

    /// 덮어쓰기 확인에 쓸 "이 기기의 현재 진행" 요약.
    var transferSummary: SaveSummary { SaveSummary(state: state) }

    /// 저장 패널에 채울 기본 파일명. 봉투의 `exportedAt` 과 **같은 시계**에서 뽑는다 — 뷰가 따로
    /// `Date()` 를 부르면 파일명 날짜와 내용의 날짜가 갈릴 수 있다(자정 경계).
    var suggestedExportFileName: String { SaveTransfer.suggestedFileName(date: clock()) }

    /// 내보내기 페이로드. 파일 쓰기는 호출자(UI)가 사용자가 고른 위치에 수행한다.
    func exportedSaveData(appVersion: String, deviceName: String) throws -> Data {
        try SaveTransfer.encode(state: state, appVersion: appVersion, deviceName: deviceName, now: clock())
    }

    /// 검증된 세이브를 이 기기에 적용 — 기존 상태 백업 → 기기 기준 재정렬 → 저장 → 라인 재로딩.
    /// 백업을 못 남기면 **적용하지 않고** throw 한다 — 확인창이 "직전 상태가 남는다"고 약속하므로,
    /// 그 약속을 못 지키는 채로 덮어쓰면 사용자는 되돌릴 수단 없이 진행을 잃는다.
    func applySave(_ envelope: SaveEnvelope) throws {
        try backupStateBeforeImport()
        state = SaveTransfer.rebasedForThisDevice(envelope.state, current: state)
        // 이전 개체 기준으로 진행 중이던 비동기·연출을 전부 무효화한다. activeGeneration 을 올리지
        // 않으면 먼저 떠 있던 라인 로드가 완료되며 새로 불러온 개체를 덮어쓴다.
        activeGeneration += 1
        currentLine = nil
        prefetchedLineID = nil
        justEvolvedTo = nil
        justGraduated = nil
        eventUntil = nil
        celebration = nil
        // 이전 개체 기준의 1회성 피드백(사탕 +XP·민트 성격)도 비운다 — 안 비우면 불러온 직후 남의
        // 개체에 대한 "+XP" 가 새 개체 위에 떠오른다.
        candyFeedbackAmount = 0
        mintFeedbackNature = nil
        displayState = state.active != nil ? .idle : .egg
        save()
        if state.active != nil { Task { await loadCurrentLine() } }
        AppLog.write("save imported from \(envelope.sourceDevice): dex=\(state.dex.count) lifetime=\(state.usedSinceInstall)")
    }

    /// 덮어쓰기 직전 현재 상태를 옆에 남긴다 — 잘못 불러왔을 때 되돌릴 수단.
    /// 슬롯을 하나만 쓰면 두 번째 불러오기가 **원본**을 덮어써, "잘못 불러왔으니 되돌린다"는 바로 그
    /// 상황에서 되돌릴 대상이 사라진다. 불러올 때마다 새 슬롯을 쓰고 오래된 것부터 정리한다.
    @discardableResult
    private func backupStateBeforeImport() throws -> URL {
        guard let data = try? JSONEncoder().encode(state) else { throw SaveTransferError.backupFailed }
        let dir = fileURL.deletingLastPathComponent()
        let backup = dir.appendingPathComponent(SaveTransfer.backupFileName(date: clock()))
        do {
            try data.write(to: backup, options: .atomic)
        } catch {
            AppLog.write("save import aborted — backup write failed: \(error)")
            throw SaveTransferError.backupFailed
        }
        pruneImportBackups(in: dir)
        return backup
    }

    /// 최근 N 개만 남기고 오래된 백업을 지운다. 파일명이 `yyyy-MM-dd-HHmmss` 라 사전순 = 시간순이다.
    private func pruneImportBackups(in dir: URL) {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return }
        let backups = names.filter { $0.hasPrefix(SaveTransfer.backupFilePrefix) }.sorted()
        guard backups.count > SaveTransfer.backupsToKeep else { return }
        for stale in backups.dropLast(SaveTransfer.backupsToKeep) {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(stale))
        }
    }

    #if DEBUG
    /// 테스트 전용 — 도감을 직접 세팅(생산 배율·마이그레이션 계승 검증용). 프로덕션 경로 없음.
    func debugSetDex(_ entries: [DexEntry]) { state.dex = entries; save() }
    #endif

    // MARK: 영속
    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }   // 파일 없음 = 신규 설치
        guard let s = try? JSONDecoder().decode(CompanionState.self, from: data) else {
            // 디코드 실패(전면 손상/미래 스키마) → fresh 로 시작하되, 다음 save() 가 원본을 덮어써 영구
            // 유실되기 전에 .corrupt 로 보존해 수동 복구 여지를 남긴다(도감 per-entry 격리로 못 살린 경우 대비).
            let backup = fileURL.appendingPathExtension("corrupt")
            try? FileManager.default.removeItem(at: backup)
            try? FileManager.default.moveItem(at: fileURL, to: backup)
            AppLog.write("companion state decode failed — original backed up to \(backup.lastPathComponent), starting fresh")
            return
        }
        // 배포 강제 초기화는 무결성 검사보다 먼저 처리하고 즉시 디스크에 기록한다. 다음 자동 저장을
        // 기다리면 사용자가 첫 화면에서 바로 종료했을 때 구세이브가 남아 다음 실행마다 재초기화될 수 있다.
        if s.forcedResetVersion < SaveTransfer.forcedResetVersion {
            AppLog.write("forced save reset on load: v\(s.forcedResetVersion) → v\(SaveTransfer.forcedResetVersion)")
            state = CompanionState()
            save()
            return
        }
        // 무결성 검사는 **정규화 전** 원본에서 한다 — sanitized 가 값을 바꾸면(클램프·전설 리셋) 서명이
        // 달라져 정상 세이브도 조작으로 오인된다. 원본 서명이 안 맞으면 손편집이므로 리셋한다.
        if SaveTransfer.isTampered(s) {
            AppLog.write("save integrity check failed — tampered save detected, resetting progress")
            // 리셋 전에 원본을 반드시 보존한다. 무결성 규칙 회귀나 실제 손편집 어느 경우든 복구 가능해야 한다.
            let stamp = Int(clock().timeIntervalSince1970)
            let backup = fileURL.deletingLastPathComponent()
                .appendingPathComponent("companion-state.pre-reset-\(stamp).json")
            do {
                try data.write(to: backup, options: .atomic)
                AppLog.write("pre-reset save backed up to \(backup.lastPathComponent)")
            } catch {
                AppLog.write("save reset aborted — pre-reset backup failed: \(error)")
                state = SaveTransfer.sanitized(s)
                return
            }
            state = SaveTransfer.resetForTamper(s)
            save()   // 즉시 새 서명으로 덮어써 조작본을 남기지 않는다
            return
        }
        // 불러오기 경계와 같은 정규화를 디스크에서 읽을 때도 건다. 불러오기만 막으면 **이미 저장된**
        // 극단값은 그대로 남아, 앱이 매 기동마다 같은 값을 읽어 산술 트랩으로 죽는 상태를 못 벗어난다
        // (디코드는 *성공*하므로 위의 .corrupt 복구도 발동하지 않는다). 여기서 걸면 자가 복구된다.
        state = SaveTransfer.sanitized(s)
    }
    private func save() {
        // 저장 직전 서명 — 다음 로드에서 손편집을 잡는다(integrity 는 해시 입력에서 제외).
        guard let data = try? JSONEncoder().encode(SaveTransfer.signed(state)) else { return }
        try? data.write(to: fileURL, options: .atomic)   // 부분 쓰기 손상 방지(펫 상태)
    }
}
