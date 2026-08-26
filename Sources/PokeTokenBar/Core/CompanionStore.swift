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
    /// 학습 제안의 출처. 하트비늘 유래일 때만 아이템을 소모하므로 구분이 필요하다.
    /// 기본값이 `.levelUp` 이라 기존 생성부(레벨업·이상한 사탕)는 손대지 않는다.
    enum MoveLearningOrigin: Sendable { case levelUp, heartScale, technicalMachine }

    struct MoveLearningPrompt: Identifiable {
        let id = UUID()
        let monID: UUID
        let level: Int
        let move: MoveSpec
        var origin: MoveLearningOrigin = .levelUp
    }

    /// 하트비늘 후보 목록 카드(#97). 개체 단위로만 유효하다.
    struct RelearnPrompt: Identifiable {
        let id = UUID()
        let monID: UUID
        let candidates: [MoveSpec]
    }
    struct EvolutionPrompt: Identifiable {
        let id = UUID()
        let monID: UUID
        let fromSpeciesID: Int
        let toSpeciesID: Int
        let requiredLevel: Int
        let toName: String
    }
    /// 저장된 원본 — 표시는 `moveLearningPrompt` 를 쓴다(현재 동행 것만 통과시킨다).
    private(set) var pendingMoveLearningPrompt: MoveLearningPrompt?
    /// 지금 동행에게 해당하는 기술 학습 제안만 노출한다. 개체가 바뀌면(교체·졸업·리롤) 이전 개체의
    /// 카드가 그대로 떠 있어 "다른 포켓몬인데 배우기 창이 남는" 문제가 됐다. 해제 지점을 일일이
    /// 추가하는 대신 표시 단계에서 걸러, 새 전환 경로가 생겨도 자동으로 막힌다.
    var moveLearningPrompt: MoveLearningPrompt? {
        guard let prompt = pendingMoveLearningPrompt, state.active?.id == prompt.monID else { return nil }
        return prompt
    }
    /// 저장된 원본 — 표시는 `relearnPrompt` 를 쓴다.
    private(set) var pendingRelearnPrompt: RelearnPrompt?
    /// `moveLearningPrompt` 와 같은 이유의 표시 게이트 — 개체가 바뀌면 이전 개체의 후보 목록이 그대로
    /// 떠 있는 문제를 해제 지점마다 막는 대신 읽는 자리 한 곳에서 막는다(새 전환 경로도 자동으로 막힌다).
    var relearnPrompt: RelearnPrompt? {
        guard let prompt = pendingRelearnPrompt, state.active?.id == prompt.monID else { return nil }
        return prompt
    }
    /// 후보 조회 중 — 가방의 재사용 방지 + 홈의 로딩 표시.
    private(set) var isLoadingRelearnCandidates = false
    private(set) var evolutionPrompt: EvolutionPrompt?
    private var declinedEvolutionMonID: UUID?
    private var declinedEvolutionLevel = 0
    private var declinedEvolutionTargetID = 0
    private var loadedTypes: [PokemonType] = []
    /// `loadedTypes` 가 **어느 종의** 타입인가. 태그 없이 배열만 들면 개체가 바뀌어도(부화·박스 교체·
    /// 불러오기) 이전 종의 타입이 남는다. 표시는 다음 조회가 고치지만, 졸업이 이 값을 `DexEntry.types` 로
    /// **영구 저장**하므로 오프라인 졸업 한 번이 남의 타입을 도감에 박고 백필도 재시도하지 않는다.
    private var loadedTypesSpeciesID: Int?
    /// 지금 개체의 타입. 태그가 안 맞으면 빈 배열 — 교체 지점마다 리셋을 심는 대신 읽는 자리 한 곳에서
    /// 막는다(리셋 지점은 계속 늘어나고 하나만 빠뜨리면 같은 결함이 돌아온다).
    var currentTypes: [PokemonType] { loadedTypesSpeciesID == currentPresentationID ? loadedTypes : [] }
    /// 종족값 — 타입과 **같은 조회**(`battleProfile`)에서 온다. 따로 받지 않는다.
    private var loadedBaseStats: BattleStats?
    /// 지금 개체의 실제 능력치 — 종족값에 **이 개체의 레벨과 성격**을 먹인 값이다.
    ///
    /// 종족값을 그대로 띄우지 않는 이유: 이 앱엔 성격과 민트가 있다. 종족값만 보이면 성격을 바꿔도
    /// 숫자가 안 움직여, 민트를 쓰는 의미가 화면에서 사라진다.
    ///
    /// 태그 검사는 `currentTypes` 와 같은 이유다 — 개체가 바뀌었는데 남의 종족값으로 계산하면
    /// 그럴듯하게 틀린 숫자가 나온다(빈 값은 화면이 자리를 비우지만, 틀린 숫자는 안 들킨다).
    var currentStats: BattleStats? {
        guard loadedTypesSpeciesID == currentPresentationID, let base = loadedBaseStats,
              let mon = state.active else { return nil }
        return base.effective(level: mon.level, nature: mon.nature)
    }
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
    /// 진화 업적이 오르는 **유일한** 지점. 진화 호출부 셋(프롬프트 수락·자동 진화·돌 진화)이 모두
    /// 여기를 지난다 — 호출부마다 심으면 네 번째 경로가 생길 때 조용히 빠진다. `.hatch`·`.dittoReveal`
    /// 은 세지 않는다. 연출 재생용으로 재사용하면 이중 계수가 되니 그때는 적립을 떼낸다.
    private func fireCelebration(_ c: Celebration) {
        celebration = c; celebrationSeq += 1
        if case .evolve = c {
            recordAchievement(.evolve, 1)
            // A species or event-kind key would collapse every later evolution for this
            // individual.  The post-transition stage and species identify this one durable
            // transition, while the UUID prevents cross-companion collisions.
            guard let mon = state.active else { return }
            recordEventMemory("\(speciesName)로 진화했다.", "Evolved into \(speciesName).", "\(speciesName)に進化した。",
                              companionID: mon.id,
                              eventID: "evolution:\(mon.id.uuidString):\(mon.stageIndex):\(mon.currentID)")
        }
    }
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
    let memoryAlbum: PokemonMemoryAlbum
    let chatStore: PokemonChatStore
    private var rng: any RandomNumberGenerator
    private let dittoDisguiseRollingEnabled: Bool
    /// 세션 내 활성 개체 교체 감지용. await 뒤 이전 개체의 결과가 새 개체를 덮지 않게 한다.
    private var activeGeneration = 0

    init(provider: any PokeProviding = PokeAPIClient.shared,
         clock: @escaping () -> Date = Date.init,
         fileURL: URL? = nil,
         memoryAlbum: PokemonMemoryAlbum? = nil,
         chatStore: PokemonChatStore? = nil,
         rng: any RandomNumberGenerator = SystemRandomNumberGenerator(),
         dittoDisguiseRollingEnabled: Bool = AppEnv.isBundledApp) {
        self.provider = provider
        self.clock = clock
        // An injected URL is an explicit test/embedding contract; only default construction uses
        // the canonical state filename.
        self.fileURL = fileURL ?? CompanionStorageLocations().stateURL
        // 디렉토리가 없으면 `save()` 의 `try?` 가 조용히 아무것도 안 쓴다 — 신규 설치와
        // 존재하지 않는 `PTB_STATE_DIR` 가 그 경로다. 상태 파일을 잡는 이 자리에서 한 번 만든다.
        let directory = self.fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // 대화·기억은 상태 파일 **옆에** 산다. 주입된 URL 은 명시적 테스트/임베딩 계약이므로
        // 그 디렉토리를 따라가야 한다 — 기본 위치로 새면 테스트가 실제 사용자 파일을 건드린다.
        self.memoryAlbum = memoryAlbum
            ?? PokemonMemoryAlbum(fileURL: directory.appendingPathComponent(CompanionStorageLocations.memoryFileName))
        self.chatStore = chatStore
            ?? PokemonChatStore(fileURL: directory.appendingPathComponent(CompanionStorageLocations.chatFileName),
                                album: self.memoryAlbum)
        self.rng = rng
        self.dittoDisguiseRollingEnabled = dittoDisguiseRollingEnabled
        load()
        reconcileStoredEggDates()
        // 정산 없이 앱이 죽은 랭크전은 여기서 패배로 마감한다(에스크로는 이미 빠져나가 있다).
        settleAbandonedRankedBattleIfNeeded()
        // 앱이 종료된 사이 끝난 집중 모험은 기동 즉시 정산한다. FocusTimer 는 세션 메모리 상태라
        // 재실행하면 .idle 로 돌아오지만 모험은 디스크에 남으므로, 여기서 비우지 않으면 시작 버튼이
        // 완료된 모험 때문에 비활성으로 보이는 복구 불가능 상태가 된다.
        claimAdventure()   // 끝난 run 만 정산한다 — 진행 중이면 그대로 둔다.
        if state.active != nil { displayState = .idle }
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
    var currentGender: PokemonGender? { state.active?.gender }
    var currentLevel: Int { state.active?.level ?? 1 }
    var experienceToNextLevel: Int {
        guard let mon = state.active, !mon.isMaxLevel else { return 0 }
        return mon.level * PokemonBalance.experiencePerLevel - mon.levelExperience
    }
    /// 현재 레벨 구간 진행도(0...1). **만렙은 1이다** — 990,000,000 은 구간 폭으로 나눈 나머지가 0 이라
    /// 가드가 없으면 다 키운 개체의 막대가 텅 빈 채로 그려졌다(#81). `TrainerLevel.progress` 와 같은 규칙.
    var levelProgress: Double {
        guard let mon = state.active else { return 0 }
        guard !mon.isMaxLevel else { return 1 }
        let within = max(0, mon.levelExperience) % PokemonBalance.experiencePerLevel
        return Double(within) / Double(PokemonBalance.experiencePerLevel)
    }
    /// 지금 형태에서 다음으로 갈 노드 — 미리 정한 경로가 있으면 그쪽, 없으면 첫 자식.
    private var nextEvolutionNode: EvoNode? {
        guard let mon = state.active, let node = currentLine?.tree.node(withID: mon.currentID),
              !node.children.isEmpty else { return nil }
        let intrinsic = node.children.filter {
            $0.evolutionTrigger != "shed"
                && ($0.evolutionGender == nil || $0.evolutionGender == mon.gender)
                && ($0.evolutionRelativePhysicalStats == nil
                    || $0.evolutionRelativePhysicalStats == mon.evolutionStatRelation)
        }
        let timed = intrinsic.filter { Self.routeMatches($0, mon: mon, date: clock()) }
        let eligible = intrinsic.count > 1 && !timed.isEmpty ? timed : intrinsic
        guard !eligible.isEmpty else { return nil }
        let nextIndex = mon.stageIndex + 1
        return mon.plannedPathIDs.indices.contains(nextIndex)
            ? eligible.first(where: { $0.speciesID == mon.plannedPathIDs[nextIndex] })
            : eligible.first
    }

    var nextEvolutionLevel: Int? { nextEvolutionNode?.evolutionLevel }

    /// 다음 진화에 필요한 아이템 — 레벨이 아니라 돌·교환으로 넘어가는 종에만 있다.
    ///
    /// 이게 없으면 화면이 아무 말도 하지 않는다. 레벨 진화 종은 "Lv.N 에 진화" 가 뜨는데
    /// 돌 진화 종은 그 자리가 비어, 오지 않을 진화를 레벨만 올리며 기다리게 된다
    /// (치라미가 그랬다 — 빛의돌을 쓰기 전엔 레벨을 아무리 올려도 아무 일도 일어나지 않는다).
    var nextEvolutionItem: ItemKind? {
        guard let next = nextEvolutionNode else { return nil }
        // 규칙 매칭 하나로 돌·순수 교환·지닌물건 진화를 모두 덮는다. 트리거로 분기하던 예전 코드는
        // 지닌물건 진화(trade+held_item, level-up+held_item)를 연결의끈으로 잘못 안내했다.
        return ItemKind.allCases.first { $0.evolutionRule?.opens(next) == true }
    }
    /// 갈라지는 진화의 한 갈래 — "무엇을 하면 무엇이 되는가".
    struct EvolutionBranch: Identifiable, Sendable {
        let id: Int              // 대상 종 번호
        let targetName: String
        let item: ItemKind?      // 돌·지닌물건·교환으로 여는 갈래
        let level: Int?          // 레벨로 열리는 갈래
    }

    /// 지금 개체가 갈 수 있는 **모든** 갈래. 갈래가 하나뿐이면 빈 배열이다(그때는 기존 한 줄 안내가 맡는다).
    ///
    /// 이게 없던 동안 화면은 **정해진 경로 쪽 갈래 하나만** 말했다(`nextEvolutionItem` 이 계획을 본다).
    /// 그런데 아이템 사용은 계획을 보지 않는다 — `useEvolutionItem` 은 그 아이템이 여는 갈래로 간다.
    /// 즉 물의돌로 강챙이가 되는데 화면엔 왕의징표석만 떠서, 나머지 갈래가 막힌 것처럼 보였다.
    var evolutionBranches: [EvolutionBranch] {
        guard let mon = state.active, let line = currentLine,
              let node = line.tree.node(withID: mon.currentID),
              node.children.count >= 2 else { return [] }
        return node.children.map { child in
            EvolutionBranch(id: child.speciesID,
                            targetName: line.localizedName(child.speciesID, state.language),
                            item: ItemKind.allCases.first { $0.evolutionRule?.opens(child) == true },
                            level: child.evolutionLevel)
        }
    }

    /// 다음 진화가 요구하는 기술의 id — 기술 습득 카드가 "이건 진화 기술" 표식을 다는 근거다.
    /// 이미 배웠는지는 보지 않는다. 카드는 아직 안 배운 기술만 제안하므로 그 구분이 필요 없다.
    var nextEvolutionKnownMoveID: Int? { nextEvolutionNode?.evolutionKnownMoveID }

    /// 다음 진화 대상의 표시 이름 — 안내 문구가 "무엇으로" 진화하는지 말하려면 필요하다.
    var nextEvolutionName: String? {
        guard let next = nextEvolutionNode, let line = currentLine else { return nil }
        return line.localizedName(next.speciesID, state.language)
    }

    /// 지금 개체의 "종 + 배운 기술" 을 한 값으로 묶은 것. 뷰가 이 값이 바뀔 때만 안내를 다시 받는다 —
    /// 기술을 배우는 순간 진화 조건이 채워지므로 종만 보면 안내가 낡은 채로 남는다.
    var currentMoveSetIdentity: String {
        guard let mon = state.active else { return "none" }
        return "\(mon.currentID):" + mon.learnedMoves.map { String($0.id) }.sorted().joined(separator: ",")
    }

    /// 다음 진화가 요구하는데 **아직 안 배운** 기술. 이게 있으면 아무리 키워도 진화가 열리지 않는다.
    ///
    /// 스펙을 통째로 들고 있는 이유: 이름은 언어를 타는데, 문자열로 굳혀 두면 언어를 바꿔도 안 바뀐다.
    /// 조회가 필요해 뷰의 `.task` 가 채운다(`loadEvolutionRequiredMove`).
    private(set) var evolutionRequiredMove: MoveSpec?

    /// 요구 기술의 이름을 1회 받아 둔다. 이미 배웠거나 요구가 없으면 비운다 —
    /// 안 비우면 진화 조건을 채운 뒤에도 "이 기술이 필요해요" 가 남는다.
    func loadEvolutionRequiredMove() async {
        guard let requiredID = nextEvolutionKnownMoveID,
              state.active?.learnedMoves.contains(where: { $0.id == requiredID }) == false else {
            evolutionRequiredMove = nil
            return
        }
        if evolutionRequiredMove?.id == requiredID { return }   // 이름은 이미 받아 뒀다
        guard let move = await provider.moveDetail(id: requiredID),
              nextEvolutionKnownMoveID == requiredID else { return }   // await 뒤 재확인
        evolutionRequiredMove = move
    }

    /// 홈에서 항상 보여 주는 다음 진화 조건. 레벨/아이템만 따로 그리던 UI는 최종형이나 PokéAPI의
    /// 비정형 level-up 조건에서 줄 자체가 사라졌다. 판정에 실제로 쓰는 정규화된 노드를 그대로 읽어
    /// 모든 동행 포켓몬이 '다음 조건' 또는 '최종 진화체' 중 하나를 반드시 표시한다.
    var evolutionRequirementText: String? {
        guard state.active != nil else { return nil }
        guard let next = nextEvolutionNode else {
            if let level = graduationLevelRequirement {
                return "\(l.finalForm) · \(l.graduatesAtLevel(level))"
            }
            return l.finalForm
        }
        var conditions: [String] = []
        if let gender = next.evolutionGender { conditions.append(gender.name(language)) }
        if let time = next.evolutionTimeOfDay {
            conditions.append(time == "day" ? l.t("낮", "Daytime", "昼") : l.t("밤", "Night", "夜"))
        }
        if let relation = next.evolutionRelativePhysicalStats {
            conditions.append(relation > 0 ? l.t("공격 > 방어", "Attack > Defense", "攻撃 > 防御")
                              : relation < 0 ? l.t("공격 < 방어", "Attack < Defense", "攻撃 < 防御")
                              : l.t("공격 = 방어", "Attack = Defense", "攻撃 = 防御"))
        }
        if let partyID = next.evolutionPartySpeciesID {
            let partyName = ownedMons.first(where: { $0.currentID == partyID })
                .map { RosterOrdering.displayName($0, language: language) } ?? specialSpeciesName(partyID)
            conditions.append(l.t("\(partyName) 보유", "Own \(partyName)", "\(partyName)を所持"))
        }
        let genderPrefix = conditions.isEmpty ? "" : conditions.joined(separator: " · ") + " · "
        if let moveID = next.evolutionKnownMoveID {
            let moveName = currentLine?.evolutionMoveNames[moveID]
                .flatMap { language.resolveName($0) } ?? "#\(moveID)"
            return genderPrefix + l.t("\(moveName) 습득 후 레벨업", "Level up knowing \(moveName)",
                                      "\(moveName)を覚えてレベルアップ")
        }
        if let level = next.evolutionLevel {
            return genderPrefix + l.t("Lv.\(level)에 진화", "Evolves at Lv.\(level)", "Lv.\(level) で進化")
        }
        if let item = nextEvolutionItem { return genderPrefix + l.evolutionNeedsItem(l.itemName(item)) }
        switch next.evolutionTrigger {
        case "level-up":
            return genderPrefix + l.t("레벨업으로 진화", "Evolves by leveling up", "レベルアップで進化")
        case "trade":
            if let partnerID = next.evolutionTradeSpeciesID {
                let partner = specialSpeciesName(partnerID)
                return genderPrefix + l.t("\(partner)와 교환", "Trade with \(partner)", "\(partner)と交換")
            }
            return genderPrefix + l.evolutionNeedsItem(l.itemName(.linkingCord))
        default:
            return genderPrefix + l.t("특수 조건으로 진화", "Evolves under a special condition", "特殊な条件で進化")
        }
    }

    private func specialSpeciesName(_ id: Int) -> String {
        switch id {
        case 223: return l.t("총어", "Remoraid", "テッポウオ")
        case 588: return l.t("딱정곤", "Karrablast", "カブルモ")
        case 616: return l.t("쪼마리", "Shelmet", "チョボマキ")
        default: return "#\(id)"
        }
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
        guard let profile = try? await provider.battleProfile(speciesID: mon.presentationID) else { return nil }
        let name = mon.currentID == 479
            ? (mon.rotomForm ?? .normal).name(language)
            : await resolveSpeciesName(mon.currentID)
        // 자동 무브셋은 **스냅샷 레벨** 기준이다. 예전엔 여기만 `mon.level` 이라, Lv.50 으로 나가는
        // 개체가 자기 실제 레벨까지 배우는 기술만 들고 갔다 — 몸은 50 인데 기술은 3 인 상태.
        let moves = mon.learnedMoves.isEmpty
            ? await PokeAPIClient.shared.moveSet(speciesID: mon.presentationID, level: level, types: profile.types)
            : await detailedMoves(of: mon)
        return BattleSnapshot(speciesID: mon.presentationID, name: mon.nickname ?? name, trainer: trainerName,
                              level: level, nature: mon.nature, isShiny: mon.isShiny,
                              types: profile.types, base: profile.stats, moves: moves,
                              ability: profile.abilitySlug,
                              weightHectograms: profile.weightHectograms)
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
        if a.currentID == 479, let form = a.rotomForm { return form.name(state.language) }
        return line.localizedName(a.currentID, state.language)
    }
    /// 종 이름(별명 무시) — 별명 입력 플레이스홀더·리셋 기준값.
    var speciesName: String {
        guard let a = state.active, let line = currentLine else { return "" }
        if a.currentID == 479, let form = a.rotomForm { return form.name(state.language) }
        return line.localizedName(a.currentID, state.language)
    }
    var currentNickname: String? { state.active?.nickname }
    /// AI 대화는 종이 아니라 개체 UUID를 키로 삼는다. 같은 개체가 진화해도 이 스냅샷만 새 형태로 갱신한다.
    func chatProfile(for mon: MonState) -> PokemonChatProfile {
        let speciesName = chatSpeciesName(for: mon)
        // currentTypes/displayedMoves are presentation caches for the active species. A boxed mon can ask
        // for a profile while those caches still belong to another species, so assemble individual data
        // from MonState and reuse the tagged type cache only when the requested species owns it.
        let types = mon.currentID == currentSpeciesID ? currentTypes.map { $0.name(language) } : []
        // 능력치는 **개체의** 값이다 — `currentStats` 가 활성 개체의 레벨·성격으로 계산하므로,
        // 종만 맞춰 싣는 타입과 달리 활성 개체가 아니면 아예 넣지 않는다. 같은 종의 레벨 3 짜리
        // 프로필에 레벨 20 의 숫자가 실리면 그럴듯하게 틀린 값이 되고, 그건 안 들킨다.
        let stats = mon.id == activeMonID ? currentStats.map {
            "HP \($0.hp) / Atk \($0.atk) / Def \($0.def) / SpA \($0.spa) / SpD \($0.spd) / Spe \($0.spe)"
        } : nil
        return PokemonChatProfile(speciesID: mon.currentID, displayName: speciesName, nickname: mon.nickname,
                                  isShiny: mon.isShiny,
                                  nature: mon.nature?.name(language), level: mon.level,
                                  stage: mon.id == activeMonID ? stageText : "Lv.\(mon.level)",
                                  flavorText: nil, language: language,
                                  types: types, stats: stats,
                                  moves: mon.learnedMoves.map { $0.name(language) },
                                  nextEvolution: nextEvolutionName(for: mon))
    }

    /// 대화가 동료를 지목하는 **유일한** 방법. 모델에게 UUID 를 문자열로 넘기면 그게 곧 임의 문자열
    /// 인자다 — 대신 안정된 인덱스를 찍어 주고, 그 인덱스로만 교체를 받는다.
    ///
    /// 순서는 `ownedMons`(활성이 0번, 나머지는 박스 순서)를 그대로 따른다. 도구가 자기만의 정렬을
    /// 만들면 `roster.list` 가 찍은 번호와 `companion.switch` 가 세는 번호가 갈린다.
    struct ChatRosterEntry: Equatable, Sendable {
        let index: Int
        let id: UUID
        let name: String
        let level: Int
        /// 이로치 여부. 도감·로스터 카드에 표식이 붙었는데 대화만 몰랐다 — 개체를 알아보는 값이다.
        let isShiny: Bool
        let isActive: Bool
    }

    /// 종 이름 한 곳. 로스터는 이름만 필요하므로 프로필을 만들지 않는다 — 프로필 한 벌은 진화 트리
    /// 조회와 능력치 문자열 조립까지 딸려 오는데, 로스터는 그 둘을 곧바로 버린다.
    private func chatSpeciesName(for mon: MonState) -> String {
        mon.names.flatMap { language.resolveName($0[mon.currentID] ?? [:]) } ?? "#\(mon.currentID)"
    }

    var chatRosterEntries: [ChatRosterEntry] {
        ownedMons.enumerated().map { index, mon in
            ChatRosterEntry(index: index, id: mon.id,
                            name: mon.nickname ?? chatSpeciesName(for: mon),
                            level: mon.level, isShiny: mon.isShiny, isActive: mon.id == activeMonID)
        }
    }

    /// 진화 도구가 "정말 한 단계 올라갔는가" 를 사실로 돌려주기 위한 값.
    var activeStageIndex: Int? { state.active?.stageIndex }

    private func nextEvolutionName(for mon: MonState) -> String? {
        guard let node = currentLine?.tree.node(withID: mon.currentID), let next = node.children.first else { return nil }
        return currentLine?.localizedName(next.speciesID, language)
    }

    /// 현재 포켓몬 별명 설정 — 공백이면 nil(종 이름으로 표시). 진화해도 유지.
    func setNickname(_ name: String) {
        guard state.active != nil else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        // 상한은 세이브 경계와 **같은 상수**를 쓴다 — 경계가 더 짧으면 방금 넣은 이름이 로드 때 잘린다.
        state.active!.nickname = trimmed.isEmpty ? nil : String(trimmed.prefix(SaveTransfer.maxNameLength))
        save()
    }

    // MARK: 트레이너 이름 (배틀 표시)
    var trainerName: String { state.trainerName }
    var hasTrainerName: Bool { !state.trainerName.trimmingCharacters(in: .whitespaces).isEmpty }
    func setTrainerName(_ name: String) {
        state.trainerName = String(name.trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(SaveTransfer.maxNameLength))
        save()
    }

    var battleRepresentative: MonState? {
        guard let id = state.battleRepresentativeID else { return nil }
        return ownedMons.first { $0.id == id }
    }

    func setBattleRepresentative(_ id: UUID?) {
        guard id == nil || ownedMons.contains(where: { $0.id == id }) else { return }
        state.battleRepresentativeID = id
        save()
    }
    var currentSpeciesID: Int? { state.active?.currentID }
    var currentPresentationID: Int? { state.active?.presentationID }

    func changeRotomForm(_ form: RotomForm) async {
        guard state.active?.currentID == 479 else { return }
        let signatureIDs = Set(RotomForm.allCases.compactMap(\.signatureMoveID))
        let signatureMove: MoveSpec?
        if let moveID = form.signatureMoveID {
            // 전용기를 가져오지 못한 상태에서 폼만 바뀌면 저장 데이터와 배틀 구성이 어긋난다.
            guard let loaded = await provider.moveDetail(id: moveID) else { return }
            signatureMove = loaded
        } else {
            signatureMove = nil
        }
        var moves = state.active!.learnedMoves.filter { !signatureIDs.contains($0.id) }
        if let signatureMove {
            if moves.count >= 4 { moves.removeLast() }
            moves.append(signatureMove)
        }
        guard state.active?.currentID == 479 else { return }
        state.active!.rotomForm = form == .normal ? nil : form
        state.active!.learnedMoves = moves
        displayedMoves = moves
        loadedTypesSpeciesID = nil
        save()
        await loadCurrentTypes()
    }
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
        state.active.map { livingDexEntry($0, isActive: true) }
    }

    /// 아직 졸업하지 않은 개체(활성 + 박스)의 화면용 도감 항목.
    ///
    /// 이름은 개체에 저장된 `MonState.names` 를 먼저 쓴다 — `currentLine` 은 **활성 개체만** 로드되므로
    /// 박스 개체를 그것으로 채우면 종 번호(#25)로 그려진다(#28). 활성 개체는 구버전 저장분(names 없음)을
    /// 위해 currentLine 폴백을 남긴다.
    private func livingDexEntry(_ mon: MonState, isActive: Bool) -> DexEntry {
        var names = mon.names ?? [:]
        if isActive, let line = currentLine {
            // 구버전 저장에는 names 딕셔너리가 존재해도 일부 진화 단계만 들어 있을 수 있다.
            // `??` 폴백은 그런 부분 저장을 완성된 데이터로 취급해 비버니 같은 종을 #번호로 남겼다.
            for id in mon.pathIDs where names[id] == nil { names[id] = line.names[id] }
        }
        return DexEntry(
            // 활성 항목 id 는 기존 형식을 유지한다(뷰 diffing·테스트가 이 문자열에 의존).
            // 박스는 같은 종이 여럿일 수 있어 개체 UUID 로 구분한다.
            id: isActive ? "active-\(mon.baseID)-\(mon.currentID)" : "boxed-\(mon.id)",
            baseID: mon.baseID,
            finalID: mon.currentID,
            // 도달분만 — stageIndex 는 MonState.init(from:) clamp + SaveTransfer 정규화가 범위를 보장하지만,
            // 손상 입력에서 pathIDs 가 더 길 수 있어 방어적으로 자른다(원래 dexSpecies 가 하던 처리).
            chainOrder: Array(mon.pathIDs.prefix(mon.stageIndex + 1)),
            rarity: mon.rarity,
            caughtAt: nil,
            // 위장 메타몽은 리빌 전까지 이로치를 숨긴다(판정 단일 소스). 박스 개체는 그 판정이
            // 활성 전용이라 저장된 값을 쓰되 위장 중이면 같은 규칙으로 감춘다.
            isShiny: isActive ? currentIsShiny
                : (mon.dittoDisguise != nil && !mon.dittoRevealed ? false : mon.isShiny),
            nature: mon.nature,
            names: names.isEmpty ? nil : names
        )
    }

    /// 졸업 기록 + **아직 키우는 중인 개체 전부**(활성 + 박스). 박스를 빼면 #25 가 만든 "동행을 유지한 채
    /// 박스에 부화" 경로의 개체가 도감에서 사라지고, 활성으로 바꿔야만 나타난다(#28).
    var dexEntries: [DexEntry] {
        state.dex + livingDexEntries
    }

    private var livingDexEntries: [DexEntry] {
        // 졸업분은 state.dex 의 영구 기록이 이미 담당한다 — 여기서 또 만들면 같은 개체가 두 번 잡힌다.
        (activeDexEntry.map { [$0] } ?? [])
            + state.boxedMons.filter { !$0.isGraduated }.map { livingDexEntry($0, isActive: false) }
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
    /// 포함 종 = 졸업분 `chainOrder` ∪ 키우는 중인 개체(활성 + 박스)의 **도달분** `pathIDs[0...stageIndex]`.
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
        // 활성 + 박스 — 박스를 빼면 #25 의 "동행 유지한 채 박스에 부화" 개체가 도감에서 빠진다(#28).
        for entry in livingDexEntries {
            // 도달분만 — chainOrder 는 이미 pathIDs(도달 경로)라 미도달 단계가 섞이지 않는다.
            for id in entry.chainOrder {
                var a = acc[id] ?? DexAccumulator(rarity: entry.rarity)
                if let n = entry.names?[id] { a.names = n }
                if entry.isShiny { a.isShiny = true }   // 위장 중 숨김 규칙은 livingDexEntry 가 적용
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

    /// 도감 격자 한 칸. 아직 안 잡은 칸도 자리를 차지하므로 `species` 가 nil 일 수 있다.
    ///
    /// 미포획 칸이 아는 건 **번호와 타입뿐**이다 — 이름·희귀도·이로치는 개체를 잡아야 생기는 값이라
    /// `DexSpecies` 를 옵셔널 필드투성이로 만드는 대신 통째로 비운다.
    struct DexSlot: Identifiable, Sendable {
        let id: Int
        let species: DexSpecies?
        var isCaught: Bool { species != nil }
    }

    /// 도감 격자에 걸린 필터. **판정은 뷰가 아니라 여기 있다** — 어떤 축이 미포획 칸에도 걸리는지가
    /// 이 화면의 규칙 전부라, 뷰 안에 두면 그 규칙을 테스트가 흉내 내는 수밖에 없다.
    struct DexFilter: Sendable {
        var caughtOnly = true
        var rarity: Rarity?
        var shinyOnly = false
        var type: PokemonType?

        /// 희귀도·이로치는 **잡아야 생기는 값**이라 미포획 칸에는 없다. 하나라도 걸리면
        /// 잡은 것만 보기가 켜진 것과 같아진다 — 조용히 그러면 "실루엣이 사라졌다" 로 읽힌다.
        var caughtOnlyLocked: Bool { rarity != nil || shinyOnly }

        /// 타입만 별도 인자인 이유: 종별 타입은 세이브가 아니라 PokéAPI 인덱스에서 온다.
        /// 인덱스를 아직 못 받았으면(빈 표) 타입 필터는 아무것도 통과시키지 못하므로 뷰가 잠근다.
        func matches(_ slot: DexSlot, typesBySpecies: [Int: [PokemonType]]) -> Bool {
            if caughtOnly || caughtOnlyLocked, !slot.isCaught { return false }
            if let rarity, slot.species?.rarity != rarity { return false }
            if shinyOnly, slot.species?.isShiny != true { return false }
            // 타입은 미포획 칸도 아는 유일한 축이다 — 잡기 전에 "남은 물타입" 을 볼 수 있어야 한다.
            if let type, typesBySpecies[slot.id]?.contains(type) != true { return false }
            return true
        }
    }

    /// 전체 도감 — 획득 가능 범위(`PokemonAssets.animatedSpeciesIDs`) ∪ 보유 종, 번호 오름차순.
    ///
    /// 보유 종을 합집합으로 얹는 이유: 진화 체인이 범위 밖으로 나가는 라인이 있다(이브이 → 님피아 #700).
    /// 범위만 쓰면 실제로 가진 종이 자기 도감에서 빠진다.
    var dexSlots: [DexSlot] {
        let caught = Dictionary(dexSpecies.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let ids = Set(PokemonAssets.animatedSpeciesIDs).union(caught.keys)
        return ids.sorted().map { DexSlot(id: $0, species: caught[$0]) }
    }

    /// 한 페이지가 덮는 도감 번호 구간(첫 칸·끝 칸). 페이지가 비어 있으면 nil.
    ///
    /// **`page × pageSize` 로 계산하면 안 된다.** 필터가 걸리면 번호가 띄엄띄엄해져서, 3페이지가
    /// 덮는 게 `#49~#72` 가 아니라 `#150~#498` 일 수 있다. 실제로 그 자리에 놓이는 칸을 읽는다.
    ///
    /// 마지막 페이지는 칸이 덜 차므로 끝 인덱스를 자른다 — 안 자르면 범위를 벗어난다.
    nonisolated static func dexPageBounds(_ slots: [DexSlot], page: Int,
                                          pageSize: Int) -> (first: Int, last: Int)? {
        let start = page * pageSize
        guard pageSize > 0, page >= 0, start < slots.count else { return nil }
        return (slots[start].id, slots[min(start + pageSize - 1, slots.count - 1)].id)
    }

    /// 종별 타입 — 도감 타입 필터가 읽는다. 비어 있으면 아직 못 받았다는 뜻이고, 그때는 필터가 잠긴다.
    /// 세이브에 넣지 않는다 — PokéAPI 사실 데이터라 `PokeAPIClient` 의 디스크 캐시가 이미 주인이다.
    private(set) var speciesTypes: [Int: [PokemonType]] = [:]

    /// 타입 인덱스를 1회 채운다(뷰의 `.task` 에서 호출). 받아 둔 뒤로는 아무 일도 하지 않는다.
    func loadSpeciesTypeIndex() async {
        guard speciesTypes.isEmpty else { return }
        guard let index = try? await provider.speciesTypeIndex(), !index.isEmpty else { return }
        speciesTypes = index
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
        else { return (currentPresentationID, currentIsShiny) }
        return (pinned.id, pinned.isShiny)
    }

    /// 이름이 없는 구버전 졸업 항목의 체인 이름을 채운다(도감 격자 진입 시 1회).
    ///
    /// 격자는 저장된 이름만 읽으므로 백필이 없으면 칸이 종 번호(`#41`)로 남는다. 포획 로그는 행이
    /// 뜰 때 행 단위로 같은 일을 해 왔지만, 로그를 한 번도 안 열면 격자는 계속 번호다.
    /// 라인 조회는 `PokeAPIClient` 가 base 단위로 캐시하므로 같은 라인이 여러 항목이어도 네트워크는 1회.
    /// 오프라인이면 `dexResolveChainNames` 가 저장 없이 폴백만 돌려주므로 다음 진입에서 다시 시도한다.
    func backfillMissingDexNames() async {
        for entry in state.dex where entry.chainOrder.contains(where: {
            entry.names?[$0].flatMap { state.language.resolveName($0) } == nil
        }) {
            _ = await dexResolveChainNames(entry)   // 성공분만 내부에서 state.dex 에 저장
        }
    }

    /// 교환·구버전 저장에서 이름 사전이 없거나 일부 단계만 남은 소유 개체를 영구 복구한다.
    /// 화면의 임시 문자열만 채우면 첫 네트워크 실패 뒤 `#399`가 계속 남고, 교환/대화처럼 다른 화면은
    /// 여전히 번호를 읽는다. 개체의 base 라인을 병합해 모든 표시 경로가 같은 저장 데이터를 쓰게 한다.
    func backfillMissingOwnedNames() async {
        // inout으로 state의 개체를 갱신하는 동안 state.language를 다시 읽으면 Swift 독점 접근 충돌이다.
        // 현재 언어를 값으로 고정해 병합 클로저가 state를 중첩 접근하지 않게 한다.
        let language = state.language
        let targets = ownedMons.filter { mon in
            mon.names?[mon.currentID].flatMap { language.resolveName($0) } == nil
        }
        guard !targets.isEmpty else { return }
        var changed = false
        for target in targets {
            if Task.isCancelled { break }
            guard let line = try? await provider.line(baseSpeciesID: target.baseID) else { continue }
            func merge(_ mon: inout MonState) {
                var names = mon.names ?? [:]
                for id in mon.pathIDs where names[id].flatMap({ language.resolveName($0) }) == nil {
                    if let resolved = line.names[id] { names[id] = resolved }
                }
                guard names != mon.names else { return }
                mon.names = names
                changed = true
            }
            if state.active?.id == target.id { merge(&state.active!) }
            else if let index = state.boxedMons.firstIndex(where: { $0.id == target.id }) {
                merge(&state.boxedMons[index])
            }
        }
        if changed { save() }
    }

    /// 타입 미저장(구버전·오프라인 졸업) 항목을 최종체 1회 조회로 채운다. 채워진 뒤엔 아무 요청도
    /// 하지 않는다(이름 백필과 같은 계약). 조회는 주입된 `provider` 를 지난다 — 저장까지 가는 값이라
    /// 스텁으로 검증할 수 있어야 한다.
    ///
    /// **여기서 보상을 지급하지 않는다.** 지급하면 구버전 세이브가 백필 한 번에 타입 목표를 소급 달성해
    /// 알을 한꺼번에 받는다. 다음 졸업의 `before` 스냅샷이 백필분을 이미 포함하므로 소급분은 자연히 빠진다.
    func backfillMissingDexTypes() async {
        var filled = false
        for entry in state.dex where entry.types == nil {
            // 뷰가 사라지면(.task 취소) 남은 항목까지 실패할 요청을 계속 쏘지 않고 멈춘다.
            if Task.isCancelled { break }
            guard let profile = try? await provider.battleProfile(speciesID: entry.finalID),
                  !profile.types.isEmpty,
                  // 조회 중에 도감이 바뀔 수 있다(졸업·불러오기) — 인덱스가 아니라 항목 id 로 되찾는다.
                  let idx = state.dex.firstIndex(where: { $0.id == entry.id }) else { continue }
            state.dex[idx].types = profile.types
            filled = true
        }
        if filled { save() }   // 항목마다 저장하면 세이브 전체를 항목 수만큼 다시 쓴다
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
        if let stored = dexStoredChainNames(entry),
           entry.chainOrder.allSatisfy({ stored[$0]?.isEmpty == false }) { return stored }
        guard let line = try? await provider.line(baseSpeciesID: entry.baseID) else {
            let stored = dexStoredChainNames(entry) ?? [:]
            return Dictionary(uniqueKeysWithValues: entry.chainOrder.map { ($0, stored[$0] ?? "#\($0)") })
        }
        var chainNames = entry.names ?? [:]
        for id in entry.chainOrder where chainNames[id].flatMap({ state.language.resolveName($0) }) == nil {
            if let resolved = line.names[id] { chainNames[id] = resolved }
        }
        if let idx = state.dex.firstIndex(where: { $0.id == entry.id }), chainNames != entry.names {
            state.dex[idx].names = chainNames   // 부분 저장도 병합해 다음 실행부터 네트워크 0
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
    func debugAddCandy(_ n: Int) { debugAddItem(.rareCandy, n) }
    /// 테스트 전용 — 인벤토리에 아이템 주입(상점 구매 경로를 우회). 진화 아이템 사용 테스트용.
    func debugAddItem(_ kind: ItemKind, _ count: Int = 1) {
        state.inventory[kind.rawValue, default: 0] += count
        save()
    }
    /// 테스트 전용 — 인벤토리 개수를 직접 세팅한다(카드가 뜬 사이 재고가 사라진 상황 재현).
    func debugSetItemCount(_ kind: ItemKind, _ count: Int) {
        state.inventory[kind.rawValue] = count
        save()
    }
    /// 테스트 전용 — 후보 조회(비동기)를 우회해 하트비늘 목록 카드를 세운다.
    func debugPresentRelearnPrompt(candidates: [MoveSpec]) {
        guard let mon = state.active else { return }
        pendingRelearnPrompt = RelearnPrompt(monID: mon.id, candidates: candidates)
    }
    /// 테스트 전용 — 레벨업 유래 학습 카드를 세운다(하트비늘 소모 분기의 대조군).
    func debugPresentLevelUpPrompt(move: MoveSpec, level: Int) {
        guard let mon = state.active else { return }
        pendingMoveLearningPrompt = MoveLearningPrompt(monID: mon.id, level: level, move: move)
    }
    /// 테스트 전용 — 스타터 선택 완료 후의 기존 사용자 상태를 재현한다.
    func debugMarkStarterChosen() { state.starterChosen = true; save() }
    /// 테스트 전용 — 레벨 경험치를 직접 주입하고 진화·졸업 판정까지 트리거한다(applyUsage(0) 은
    /// claimAdventure() 가 레벨만 올릴 때 쓰는 것과 같은 형태). 프로덕션 호출 경로 없음.
    func debugAccrueLevelExperience(_ amount: Int) {
        guard state.active != nil else { return }
        state.active!.gainExperience(amount)
        applyUsage(0)
    }
    /// 테스트 전용 — 기술 목록 표시 상태를 직접 세팅(네트워크 로드 없이 행 레이아웃을 재기 위함).
    func debugSetDisplayedMoves(_ moves: [MoveSpec], loading: Bool = false) {
        displayedMoves = moves
        isLoadingDisplayedMoves = loading
    }
    /// 테스트 전용 — 타입 표시 캐시와 소유자 태그를 함께 세팅한다. 둘을 분리하면 프로덕션에서
    /// 만들 수 없는 태그 없는 캐시 상태가 생겨 회귀 테스트가 실제 결함과 다른 조건을 검증한다.
    func debugSetLoadedTypes(_ types: [PokemonType], speciesID: Int, base: BattleStats? = nil) {
        loadedTypes = types
        loadedBaseStats = base
        loadedTypesSpeciesID = speciesID
    }
    /// 테스트 전용 — 비동기 계승 기술 복원과 동행 교체의 경합을 네트워크 없이 재현한다.
    func debugSetActiveLearnedMoves(_ moves: [MoveSpec]) {
        state.active?.learnedMoves = moves
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

    // MARK: 기억·모험

    private func recordEventMemory(_ ko: String, _ en: String, _ ja: String,
                                   companionID: UUID, eventID: String) {
        memoryAlbum.record(companionID: companionID, body: l.t(ko, en, ja), source: .event, eventID: eventID)
    }
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
    /// (`startFocusAdventure`) 셋이지만 모두 이 함수를 부른다 — 완료 판정을 감싸는
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
            state.active!.gainExperience(reward.experience)
            let newLevel = state.active!.level
            applyUsage(0)
            if newLevel > oldLevel { queueMoveLearning(from: oldLevel + 1, through: newLevel) }
        }
        if reward.foundRareCandy { state.inventory[ItemKind.rareCandy.rawValue, default: 0] += 1 }
        let minutes = Int((run.endsAt.timeIntervalSince(run.startedAt) / 60).rounded())
        // 트레이너 포인트는 **정산된** 분만 인정한다 — 시작만으로 적립하면 타이머를 켜 두는 것이
        // 곧 성장이 돼 집중과 무관해진다.
        reward.trainerBonus = accrueTrainerPoints(minutes)
        // 미션은 **정산된** 분만 인정한다 — 시작만으로 진행되면 타이머를 켜 두는 것이 곧 미션
        // 진행이 되어 목표가 집중과 무관해진다.
        reward.missionBonus = recordMission(.focusMinutes, minutes) + recordMission(.adventures, 1)
        // 시즌 챌린지도 같은 정산분을 센다 — 미션과 이벤트 어휘가 같아 훅이 이 한 줄로 끝난다.
        reward.seasonBonus = recordSeason(.focusMinutes, minutes) + recordSeason(.adventures, 1)
        // 업적도 **정산된** 분만 센다. 세 시작 경로가 모두 여기를 지나니 훅은 이 한 줄이다.
        reward.achievementBonus = recordAchievement(.focus, minutes)
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
        // `AdventureRun.id` is persisted before a run can be claimed.  Replaying a claim
        // after a relaunch therefore hits the same idempotency key, but each new run gets
        // its own memory.
        if let mon = state.active {
            recordEventMemory("모험을 무사히 마쳤다.", "Finished the adventure safely.", "冒険を無事に終えた。",
                              companionID: mon.id, eventID: "adventure:\(run.id.uuidString)")
        }
        state.adventureHistory.insert(AdventureRecord(id: run.id, zone: run.zone,
                                                       companionSpeciesID: run.companionSpeciesID,
                                                       completedAt: now, stardust: reward.starPieces,
                                                       foundRareCandy: reward.foundRareCandy), at: 0)
        if state.adventureHistory.count > 30 { state.adventureHistory.removeLast(state.adventureHistory.count - 30) }
        save()
        return reward
    }

    var trainerLevel: TrainerLevel { state.trainer }

    /// 트레이너 포인트 적립의 **유일한** 경로 — 레벨업 보상(별의조각)과 알림도 여기서 처리한다.
    /// 적립 지점(모험 정산·졸업)마다 보상 계산을 흩뿌리면 한쪽만 바뀌는 사고가 난다.
    /// 반환값은 이번에 지급한 별의조각 — 호출부가 보상 객체에 실어 사용자에게 알린 값과
    /// 실제 지갑 증가가 어긋나지 않게 한다.
    @discardableResult
    private func accrueTrainerPoints(_ amount: Int) -> Int {
        let gained = state.trainer.add(amount)
        guard gained > 0 else { return 0 }
        let level = state.trainer.level
        // 한 번에 두 칸 이상 올랐으면 건너뛴 레벨의 보상도 모두 지급한다(마지막 레벨만 주면 손실).
        let bonus = ((level - gained + 1)...level).reduce(0) { $0 + TrainerLevel.reward(forReaching: $1) }
        state.starPieces += bonus
        notifyCompanionEvent(l.notifTrainerLevelUpTitle, l.notifTrainerLevelUpBody(level, bonus))
        return bonus
    }

    /// 미션 기록의 **유일한** 경로 — 완료 보상(별의조각)과 알림도 여기서 처리한다.
    /// 적립 지점(모험 정산·졸업)마다 `state.missions` 를 직접 만지면 갱신과 클램프가 두 곳으로 갈라진다.
    /// 완료된 미션만 돌아오므로 "이미 줬나"를 따로 기억하지 않는다.
    /// 반환값은 이번에 지급한 별의조각 — `accrueTrainerPoints` 와 같은 계약이다. 정산 경로는 이 값을
    /// 보상 객체에 실어야 한다. 지갑만 늘리고 보고하지 않으면 알려준 값과 실제 잔액이 어긋난다.
    @discardableResult
    private func recordMission(_ event: MissionEvent, _ amount: Int) -> Int {
        let now = clock()
        let done = state.missions.record(event, amount,
                                        dayKey: Self.dayKey(now), weekKey: Self.weekKey(now))
            .map { (name: l.missionName($0), reward: $0.reward) }
        guard let merged = Self.mergedCompletion(done) else { return 0 }
        state.starPieces += merged.reward
        notifyCompanionEvent(l.notifMissionDoneTitle,
                             l.notifMissionDoneBody(merged.name, merged.reward))
        return merged.reward
    }

    /// 한 정산에서 완료된 목표를 **한 통**으로 묶는다 — 이름은 가운뎃점으로 잇고 보상은 합산한다.
    /// 완료마다 한 통씩 띄우면 시즌·미션이 함께 완료되는 정산에서 배너가 6개 연달아 뜬다.
    nonisolated static func mergedCompletion(_ done: [(name: String, reward: Int)])
        -> (name: String, reward: Int)? {
        guard !done.isEmpty else { return nil }
        return (done.map(\.name).joined(separator: " · "), done.reduce(0) { $0 + $1.reward })
    }

    /// 시즌 기록의 **유일한** 경로 — 완료 보상(별의조각)과 알림까지 여기서 끝낸다.
    /// 계약은 `recordMission` 과 같다: 반환값은 이번에 지급한 별의조각이고, 정산 경로가 그 값을
    /// 보상 객체에 실어 보고한다.
    @discardableResult
    private func recordSeason(_ event: MissionEvent, _ amount: Int) -> Int {
        let done = state.seasons.record(event, amount, seasonKey: Self.seasonKey(clock()))
            .map { (name: l.goalName($0.event, $0.target), reward: $0.reward) }
        guard let merged = Self.mergedCompletion(done) else { return 0 }
        state.starPieces += merged.reward
        notifyCompanionEvent(l.notifSeasonDoneTitle,
                             l.notifMissionDoneBody(merged.name, merged.reward))
        return merged.reward
    }

    /// 화면용 시즌 목록 — 세트도 진행도도 **읽는 시점의** 시즌 키로 판정한다. 달이 바뀌면 기록 없이도
    /// 새 세트가 빈 채로 보인다(상태는 그대로 — 다음 기록이 갱신한다).
    var seasonRows: [(challenge: SeasonChallenge, progress: Int)] {
        let key = Self.seasonKey(clock())
        return SeasonBoard.challenges(forSeasonKey: key).map {
            ($0, state.seasons.progress($0, seasonKey: key))
        }
    }

    /// 시즌 카드 헤더가 읽는 남은 일수. 뷰가 달력을 직접 만지지 않게 하는 자리다.
    var seasonDaysRemaining: Int { SeasonBoard.daysRemaining(at: clock()) }

    /// 화면용 미션 목록. 진행도는 **읽는 시점의** 날짜·주 키로 판정하므로, 자정이 지나면 아무 기록
    /// 없이도 일간이 비어 보인다(상태는 그대로 — 다음 기록이 실제로 갱신한다).
    var missionRows: [(mission: Mission, progress: Int)] {
        let now = clock()
        let day = Self.dayKey(now), week = Self.weekKey(now)
        return MissionBoard.catalog.map { ($0, state.missions.progress($0, dayKey: day, weekKey: week)) }
    }

    /// 도감 완성 목표 지급의 **유일한** 경로. 호출부가 도감을 바꾸기 전에 `before` 를 잡아 두고 바꾼 뒤
    /// 이 함수를 부른다 — 차집합이 곧 "이번에 넘은 목표"라 수령 플래그가 필요 없다.
    ///
    /// `before` 를 **호출부가** 잡는 게 핵심이다. 여기서 잡으면 이미 바뀐 뒤라 차집합이 항상 비어
    /// 아무것도 지급되지 않는다. 저장은 호출부(`graduate()`)가 이어서 한다.
    private func grantNewlyCompletedDexGoals(before: Set<String>) {
        // 정렬 — Set 순회 순서는 실행마다 다르다. 두 목표를 한 번에 넘길 때 알림 순서가 흔들리면
        // 테스트가 간헐 실패한다.
        for id in DexGoals.completed(in: state.dex).subtracting(before).sorted() {
            guard let goal = DexGoals.goal(id: id) else { continue }
            grantReward(goal.reward)
            notifyCompanionEvent(l.notifDexGoalTitle, l.notifDexGoalBody(l.dexGoalName(goal)))
        }
    }

    /// 업적 기록의 **유일한** 경로 — 보상(별의조각)과 알림까지 여기서 끝낸다. 적립 지점마다
    /// `state.achievements` 를 직접 만지면 클램프와 경계 판정이 갈라진다.
    /// 반환값은 이번에 지급한 별의조각(`recordMission` 과 같은 계약). 정산 경로는 이 값을 보상
    /// 객체에 실어야 한다 — 지갑만 늘리면 보고액과 잔액이 어긋난다.
    /// `save()` 는 호출부 몫이다(레이스만 예외 — `recordRaceFinish`).
    @discardableResult
    private func recordAchievement(_ track: AchievementTrack, _ amount: Int) -> Int {
        var paid = 0
        for award in state.achievements.record(track, amount) {
            let reward = award.achievement.rewards[award.tier - 1]
            state.starPieces += reward
            paid += reward
            if let outfit = award.achievement.outfits[award.tier - 1] { grantOutfit(outfit) }
            notifyCompanionEvent(l.notifAchievementTitle,
                                 l.notifAchievementBody(l.achievementName(award.achievement.track),
                                                        award.tier, reward))
        }
        return paid
    }

    /// 포켓슬론 완주 적립. 호출부가 스토어 밖(`MultiplayerRoomCenter`)이라 저장도 여기서 한다.
    /// 세는 건 우승이 아니라 **완주**다 — 우승만 세면 4인 방에서 ¾은 영원히 못 넘는다.
    func recordRaceFinish() {
        recordAchievement(.race, 1)
        save()
    }

    /// 화면용 업적 행 — 카탈로그 순서 그대로.
    var achievementRows: [(achievement: Achievement, count: Int, tier: Int)] { state.achievements.rows }

    /// 도달한 업적 단계의 합계. 카드와 LAN 광고가 쓴다. 뷰·네트워크가 `state` 를 직접 만지지
    /// 않게 하는 자리다(`achievementRows` 와 같은 이유).
    var achievementTierTotal: Int { state.achievements.tierTotal }

    /// 아직 안 넘은 첫 문턱. 최고 단계면 nil — 선반이 숫자 대신 완료 표식을 띄운다.
    func nextAchievementTier(_ track: AchievementTrack) -> (goal: Int, tier: Int)? {
        state.achievements.next(track)
    }

    /// 화면용 목표 행 — 축마다 아직 안 넘은 첫 목표 하나씩. **졸업 기록만** 넘긴다.
    /// `dexEntries`(활성·박스 합성)를 넘기면 알을 새로 살 때 표시 진행도가 되감겨 지급 판정과
    /// 화면이 다른 수를 말한다.
    var dexGoalRows: [(goal: DexGoal, progress: Int)] { DexGoals.rows(in: state.dex) }

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
                                  foundEgg: reward.bonusEggs > 0, trainerBonus: reward.trainerBonus,
                                  missionBonus: reward.missionBonus,
                                  achievementBonus: reward.achievementBonus,
                                  seasonBonus: reward.seasonBonus)
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

    /// 방생 — 박스의 개체를 놓아준다. 박스는 지금까지 늘기만 했고(부화는 영구), 줄어드는 길은
    /// 동행으로 올리는 것과 디버그 훅뿐이었다(#88).
    ///
    /// **활성 개체는 대상이 아니다** — 동행이 사라지면 성장 tick 이 붙을 곳이 없어진다. 먼저 교체한다.
    ///
    /// **도감 영구 기록은 건드리지 않는다.** 졸업분은 `state.dex` 에 남고 도감 목표도 그 기록만
    /// 세므로(`DexGoals.completed(in: state.dex)`), 졸업한 개체를 놓아줘도 달성도는 그대로다.
    /// 미졸업 개체는 박스에 있는 동안만 도감에 합성되던 줄이라(`livingDexEntries`) 개체와 함께 사라진다 —
    /// 애초에 영구 기록이 아니었던 것이고, 그래서 방생이 달성도를 지우는 경로가 되지 않는다.
    @discardableResult
    func releaseMon(_ id: UUID) -> Bool {
        guard let index = state.boxedMons.firstIndex(where: { $0.id == id }) else { return false }
        let released = state.boxedMons.remove(at: index)
        AppLog.write("released boxed mon species=\(released.currentID) lv\(released.level) graduated=\(released.isGraduated)")
        memoryAlbum.deleteAll(for: released.id)
        chatStore.deleteSession(for: released.id)
        save()
        return true
    }

    /// 통신 교환을 한 번에 반영한다. 동행을 내보내면 받은 포켓몬이 그 자리를 이어받고,
    /// 박스 개체를 내보내면 같은 박스 칸에 들어간다. 상대의 대화/추억은 개인정보라 전송하지 않는다.
    @discardableResult
    func performTrade(offeredID: UUID, received incoming: MonState) -> Bool {
        guard incoming.id != offeredID,
              (1...649).contains(incoming.currentID),
              !ownedMons.contains(where: { $0.id == incoming.id }) else { return false }

        let offeredSpecies = state.active?.id == offeredID
            ? state.active?.currentID : state.boxedMons.first(where: { $0.id == offeredID })?.currentID
        var received = incoming
        if let offeredSpecies { Self.applyPairedTradeEvolution(to: &received, counterpartSpeciesID: offeredSpecies) }
        if state.active?.id == offeredID {
            guard let sent = state.active else { return false }
            preserveDexRecord(for: sent)
            memoryAlbum.deleteAll(for: sent.id)
            chatStore.deleteSession(for: sent.id)
            state.active = received
            activeGeneration += 1
            currentLine = nil
            displayedMoves = []
            evolutionPrompt = nil
            pendingMoveLearningPrompt = nil
            moveLearningQueue.removeAll()
            displayState = .idle
            save()
            Task { await loadCurrentLine() }
            return true
        }
        guard let index = state.boxedMons.firstIndex(where: { $0.id == offeredID }) else { return false }
        let sent = state.boxedMons[index]
        preserveDexRecord(for: sent)
        memoryAlbum.deleteAll(for: sent.id)
        chatStore.deleteSession(for: sent.id)
        state.boxedMons[index] = received
        save()
        return true
    }

    private static func applyPairedTradeEvolution(to mon: inout MonState, counterpartSpeciesID: Int) {
        let target: Int?
        switch (mon.currentID, counterpartSpeciesID) {
        case (588, 616): target = 589   // 딱정곤 + 쪼마리 → 슈바르고
        case (616, 588): target = 617   // 쪼마리 + 딱정곤 → 어지리더
        default: target = nil
        }
        guard let target else { return }
        mon.pathIDs = Array(mon.pathIDs.prefix(mon.stageIndex + 1)) + [target]
        mon.plannedPathIDs = mon.pathIDs
        mon.stageIndex += 1
        mon.totalForms = mon.pathIDs.count
        mon.usedAtStage = 0
    }

    /// 교환으로 소유권이 넘어가도 한 번 만난 종은 도감에서 지우지 않는다. 미졸업 개체는 평소
    /// `livingDexEntries`로만 합성되므로, 내보내기 직전에 도달한 단계까지 영구 기록으로 승격한다.
    /// 이미 졸업한 개체는 같은 기록이 state.dex에 있으므로 중복 추가하지 않는다.
    private func preserveDexRecord(for mon: MonState) {
        guard !mon.isGraduated else { return }
        let reached = Array(mon.pathIDs.prefix(mon.stageIndex + 1))
        guard let finalID = reached.last else { return }
        state.dex.append(DexEntry(
            id: "traded-\(mon.id.uuidString)", baseID: mon.baseID, finalID: finalID,
            chainOrder: reached, rarity: mon.rarity, caughtAt: clock(),
            isShiny: mon.dittoDisguise != nil && !mon.dittoRevealed ? false : mon.isShiny,
            nature: mon.nature, names: mon.names))
    }

    func switchCompanion(to id: UUID) {
        guard let index = state.boxedMons.firstIndex(where: { $0.id == id }) else { return }
        let selected = state.boxedMons.remove(at: index)
        if let active = state.active { state.boxedMons.append(active) }
        state.active = selected
        activeGeneration += 1
        currentLine = nil
        displayedMoves = []
        evolutionPrompt = nil
        // 이전 개체의 기술 학습 대기분까지 버린다 — 표시 게이트가 현재 카드는 막지만, 큐에 남은
        // 다른 개체 몫이 나중에 승격되면 같은 증상이 재발한다.
        pendingMoveLearningPrompt = nil
        moveLearningQueue.removeAll()
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
              let target = node.children.first(where: { $0.speciesID == prompt.toSpeciesID }),
              Self.routeMatches(target, mon: active, date: clock()),
              target.evolutionPartySpeciesID.map({ required in
                  ownedMons.contains(where: { $0.currentID == required })
              }) ?? true,
              target.evolutionKnownMoveID.map({ moveID in
                  active.learnedMoves.contains(where: { $0.id == moveID })
              }) ?? true else {
            evolutionPrompt = nil; return
        }
        evolutionPrompt = nil
        declinedEvolutionMonID = nil
        state.active!.pathIDs = Array(active.pathIDs.prefix(active.stageIndex + 1)) + [prompt.toSpeciesID]
        state.active!.stageIndex += 1
        let threshold = PokemonBalance.phaseThreshold(
            rarity: active.rarity, totalForms: active.totalForms, stageIndex: active.stageIndex - 1)
        state.active!.usedAtStage = max(0, active.usedAtStage - threshold)
        spawnShedinjaIfNeeded(from: active, evolvedTo: prompt.toSpeciesID, line: line)
        justEvolvedTo = prompt.toName
        fireCelebration(.evolve)
        eventUntil = clock().addingTimeInterval(4)
        notifyCompanionEvent(l.notifEvolveTitle, l.notifEvolveBody(prompt.toName))
        save()
        applyUsage(0)
    }

    /// 토중몬은 아이스크로 진화하면서 빈 박스에 껍질몬이 함께 생긴다. 박스는 무제한이라 빈 슬롯
    /// 조건은 항상 충족하며, 별도 몬스터볼 재화가 없는 앱 규칙상 추가 소모도 없다.
    private func spawnShedinjaIfNeeded(from source: MonState, evolvedTo targetID: Int, line: EvoLine) {
        guard source.currentID == 290, targetID == 291 else { return }
        var shedinja = MonState(baseID: 290, pathIDs: [290, 292], plannedPathIDs: [290, 292],
                                stageIndex: 1, usedAtStage: 0, rarity: source.rarity, totalForms: 2,
                                isShiny: source.isShiny, nature: source.nature, gender: .genderless,
                                evolutionStatRelation: source.evolutionStatRelation, names: line.names)
        shedinja.levelExperience = source.levelExperience
        shedinja.learnedMoves = source.learnedMoves
        state.boxedMons.append(shedinja)
    }

    func declineMoveLearning() {
        pendingMoveLearningPrompt = nil
        showNextMoveLearningPrompt()
    }

    func acceptMoveLearning(replacing index: Int? = nil) {
        guard let prompt = moveLearningPrompt else { declineMoveLearning(); return }
        if prompt.origin == .technicalMachine {
            guard technicalMachineCount(prompt.move.id) > 0 else {
                pendingMoveLearningPrompt = nil
                showNextMoveLearningPrompt()
                return
            }
        }
        if state.active!.learnedMoves.count < 4 {
            state.active!.learnedMoves.append(prompt.move)
        } else if let index, state.active!.learnedMoves.indices.contains(index) {
            state.active!.learnedMoves[index] = prompt.move
        } else { return }   // 무변경(범위 밖 인덱스) — 아래 하트비늘 소모도 타지 않는다
        // 하트비늘은 **무브셋이 실제로 바뀐 뒤에만** 소모한다. 목록에서 취소하거나 교체를 거절한
        // 경우까지 태우면 클릭 한 번에 500 별의조각이 사라지는 함정이 된다.
        if prompt.origin == .heartScale {
            state.inventory[ItemKind.heartScale.rawValue] = max(0, itemCount(.heartScale) - 1)
        } else if prompt.origin == .technicalMachine {
            let count = technicalMachineCount(prompt.move.id)
            state.technicalMachines[prompt.move.id] = count - 1
        }
        // 표시 목록을 여기서 맞춘다. 기술 목록의 `.task(id:)` 는 "개체 id + 레벨" 이라 **레벨이
        // 바뀌지 않는 학습**(하트비늘)에서는 다시 돌지 않는다 — 레벨업 경로는 레벨이 함께 바뀌어
        // 이 공백이 가려져 있었다. 상세(설명·랭크 변화)는 다음 로드가 채운다.
        displayedMoves = state.active!.learnedMoves
        save()
        pendingMoveLearningPrompt = nil
        // 같은 레벨에서 막 배운 기술이 진화 조건일 수 있다. **레벨업으로 배운 경우만** 다시 판정한다.
        // 하트비늘로 가만히 서서 배운 기술은 본가 규칙대로 다음 레벨업까지 기다려야 한다.
        if prompt.origin == .levelUp { applyUsage(0) }
        showNextMoveLearningPrompt()
    }

    /// 레벨 구간에서 새로 배울 기술을 큐에 넣는다.
    ///
    /// 개체를 값으로 한 번 캡처해 두면 안 된다. 이 루프는 await 를 끼고 도는 동안 사용자가 기술을
    /// 수락하거나(learnedMoves 증가) 개체가 진화·교체될 수 있는데, 캡처본은 그대로라 **이미 배운
    /// 기술을 다시 제안**하고 중복 카드가 쌓였다. 매 반복마다 현재 상태를 다시 읽는다.
    private func queueMoveLearning(from first: Int, through last: Int) {
        guard let monID = state.active?.id else { return }
        Task { @MainActor in
            for level in first...last {
                // 도중에 개체가 바뀌었으면(교체·졸업·리롤) 남은 구간은 그 개체 몫이 아니다.
                guard let mon = state.active, mon.id == monID else { return }
                let moves = await PokeAPIClient.shared.movesLearned(speciesID: mon.currentID, at: level)
                guard let current = state.active, current.id == monID else { return }   // await 뒤 재확인
                for move in moves {
                    // 이미 배운 것 + 아직 답 안 한 대기분(큐·표시 중) 모두와 대조한다. 한쪽만 보면
                    // 같은 기술이 여러 장으로 쌓인다.
                    let alreadyKnown = current.learnedMoves.contains { $0.id == move.id }
                    let alreadyQueued = moveLearningQueue.contains { $0.move.id == move.id }
                        || pendingMoveLearningPrompt?.move.id == move.id
                    guard !alreadyKnown, !alreadyQueued else { continue }
                    moveLearningQueue.append(MoveLearningPrompt(monID: monID, level: level, move: move))
                }
            }
            showNextMoveLearningPrompt()
        }
    }

    private func showNextMoveLearningPrompt() {
        guard pendingMoveLearningPrompt == nil, !moveLearningQueue.isEmpty else { return }
        pendingMoveLearningPrompt = moveLearningQueue.removeFirst()
    }

    func loadCurrentTypes() async {
        guard let id = currentPresentationID,
              let profile = try? await provider.battleProfile(speciesID: id),
              currentPresentationID == id else { return }
        loadedTypes = profile.types
        loadedBaseStats = profile.stats
        loadedTypesSpeciesID = id
    }

    /// 스펙을 다시 받아야 하는가 — 아직 안 받아봤거나(nil), 예전 파서가 저장한
    /// "사용할 수 없는 기술입니다" 안내문이 들어 있으면 다시 받는다.
    /// nil 일 때만 받으면 이미 세이브에 박힌 안내문이 영영 안 고쳐진다. 반대로 빈 dict 까지
    /// "없음"으로 보면 안 된다 — 안내문뿐인 기술은 조회해도 빈 dict 라 로드할 때마다 다시 받게 된다.
    ///
    /// 랭크 변화(Phase 3)도 같은 부류다. `statChanges == nil` 은 "랭크 이전 세이브" 라는 뜻이라
    /// 한 번 다시 받아야 변화기가 동작한다 — `[]`(받았고 변화 없음)와 섞으면 안 된다.
    static func needsDetailRefresh(_ move: MoveSpec) -> Bool {
        // 합성 기술(발버둥·fetch 실패 폴백)은 `moveDetail(id:)` 가 거절하는 id 다. 여기서 참을
        // 주면 매 로드마다 헛도는 조회가 된다.
        guard move.id > 0 else { return false }
        if move.statChanges == nil { return true }
        // **축을 더할 때 이 판정도 같이 늘린다.** `statChanges` 만 보면, 그 축으로 한 번 갱신된
        // 세이브는 이후 어떤 새 축이 비어 있어도 다시 받지 않고 옛 데이터로 싸운다.
        if move.targetsUser == nil { return true }
        // 드레인·반동·다단·풀린치(Phase 5)도 같은 부류다. 넷이 같은 `meta` 블록에서 한 번에
        // 오므로 `drain` 하나가 넷을 대표한다. `minHits`/`maxHits` 로는 못 본다 — 단발기는
        // 받아봐도 nil 이라 영원히 수렴하지 않는다.
        if move.drain == nil { return true }
        // **`drain` 이 `healing` 을 대표하지 못한다.** 같은 `meta` 블록에서 오지만 `healing` 은
        // 나중에 추가된 축이라, 그 사이에 받은 세이브는 `drain` 만 차 있고 `healing` 은 비어 있다.
        // 그 상태로 두면 회복기가 조용히 0 회복이 된다 — 상태기가 죽어 있던 것과 같은 부류다.
        if move.healing == nil { return true }
        guard let descriptions = move.descriptions else { return true }
        return descriptions.values.contains(where: PokeAPIClient.isUnusableMoveNotice)
    }

    /// 축이 빠진 기술만 다시 받아 채우고, 채운 값을 세이브에 되쓴다.
    ///
    /// **대전 스냅샷도 반드시 여기를 지나야 한다.** 예전엔 기술 목록 화면만 보강했고 스냅샷은
    /// `learnedMoves` 를 그대로 실어 보냈다 — 축이 늘어나기 전(`ailment` 이전)의 세이브로
    /// 싸우면 상태기가 **조용히** 무효가 된다. `ailment` 가 없으면 `inflictedStatus` 가 nil 이라
    /// `applySecondaryEffect` 가 이벤트 없이 빠져나가고, 위력 0 이라 데미지 줄도 안 나가서
    /// 로그에는 기술명 한 줄만 남는다(수면가루를 써도 아무 일도 안 일어난 것처럼 보인다).
    /// 화면을 한 번도 안 펼친 사용자는 그 상태에서 빠져나올 길이 없었다.
    ///
    /// 되쓰기가 있어야 한 번 채운 개체가 대전마다 같은 조회를 반복하지 않는다. 조회 중 개체가
    /// 바뀔 수 있으므로 같은 id 를 다시 찾았을 때만 쓴다.
    func detailedMoves(of mon: MonState) async -> [MoveSpec] {
        var enriched = mon.learnedMoves
        var filled = false
        for index in enriched.indices where Self.needsDetailRefresh(enriched[index]) {
            if let detail = await provider.moveDetail(id: enriched[index].id) {
                enriched[index] = detail
                filled = true
            }
        }
        guard filled else { return mon.learnedMoves }
        if state.active?.id == mon.id {
            state.active!.learnedMoves = enriched
            save()
        } else if let index = state.boxedMons.firstIndex(where: { $0.id == mon.id }) {
            state.boxedMons[index].learnedMoves = enriched
            save()
        }
        return enriched
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
            let enriched = await detailedMoves(of: refreshed)
            guard state.active?.id == active.id else { return }
            displayedMoves = enriched
            return
        }
        isLoadingDisplayedMoves = true
        defer { isLoadingDisplayedMoves = false }
        let profile = try? await PokeAPIClient.shared.battleProfile(speciesID: speciesID)
        let moves = await PokeAPIClient.shared.canonicalLevelUpMoves(speciesID: speciesID, level: active.level)
        guard state.active?.id == active.id else { return }
        if let profile { loadedTypes = profile.types; loadedTypesSpeciesID = speciesID }
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

    func grantBattleReward(won: Bool, participantCount: Int, mode: MultiplayerBattleMode,
                           opponentNames: [String]) {
        guard state.active != nil else { return }
        let dust = 0
        state.battleHistory.insert(BattleRecord(playedAt: clock(), mode: mode,
                                                participantCount: participantCount, won: won,
                                                reward: dust, opponentNames: opponentNames), at: 0)
        if state.battleHistory.count > 30 { state.battleHistory.removeLast(state.battleHistory.count - 30) }
        // LAN 배틀 **승리만**. 연습 배틀은 혼자 무한 반복이라 업적이 클릭 노동이 된다 — 호출부가
        // 하나(`MultiplayerRoomCenter.grantRewardIfFinished`)라 그 경계가 지켜진다.
        if won { recordAchievement(.battle, 1) }
        save()
    }

    var recentAdventures: [AdventureRecord] { Array(state.adventureHistory.prefix(5)) }
    var recentBattles: [BattleRecord] { Array(state.battleHistory.prefix(5)) }
    var battleRank: BattleRank { state.battleRank }
    var battleRankProfile: BattleRankProfile {
        BattleRankProfile(rank: state.battleRank, stardust: availableTokens)
    }

    var hasPendingRankedBattle: Bool { state.pendingRanked != nil }

    /// 랭크전 개시 — 판돈을 **지금** 지갑에서 뺀다. 잔액이 모자라면 아무것도 하지 않고 false
    /// (호출부가 배틀을 시작하지 않는다). 판돈 0 이어도 기록은 남긴다 — 이탈의 LP 대가가 걸려 있다.
    ///
    /// 정산이 배틀 끝에만 있던 때는 지고 있을 때 앱을 종료하면 내 쪽 정산이 아예 돌지 않아 판돈을
    /// 안 냈다. 개시 시점은 앱이 확실히 살아 있는 순간이라 여기로 옮기면 그 회피가 사라진다.
    @discardableResult
    func escrowRankedBattle(stake: Int, opponent: BattleRank) -> Bool {
        guard state.pendingRanked == nil else { return false }   // 이중 차감 차단
        let amount = max(0, stake)
        guard availableTokens >= amount else { return false }
        state.starPieces -= amount
        state.pendingRanked = PendingRankedBattle(stake: amount, opponent: opponent)
        save()
        return true
    }

    /// 1:1 맞짱 랭크전 정산. 판돈은 개시 때 잡아 둔 에스크로에서만 움직인다 —
    /// 이기면 내 몫이 돌아오고 상대 몫이 더해져 순증은 판돈 1배, 지면 이미 낸 것으로 끝난다.
    /// 에스크로가 없으면(구버전 세이브에서 이어진 배틀) 판돈 이동 없이 LP 만 반영한다.
    ///
    /// **판돈(화폐)과 LP(실력 지표)는 다른 자원이다.** 예전엔 판돈을 못 내면 그 자리에서
    /// `return 0` 해서 LP 차감까지 건너뛰었고, 지갑을 비워 두면 무손실 랭크가 됐다.
    @discardableResult
    func settleRankedBrawl(won: Bool, opponent: BattleRank) -> Int {
        let escrowed = state.pendingRanked?.stake ?? 0
        state.pendingRanked = nil
        if won { state.starPieces += escrowed * 2 }
        let delta = state.battleRank.apply(win: won, opponent: opponent)
        save()
        return delta
    }

    /// 무효(끊김 동률·무승부) — 에스크로만 돌려주고 랭크는 건드리지 않는다.
    func refundRankedEscrow() {
        guard let pending = state.pendingRanked else { return }
        state.pendingRanked = nil
        state.starPieces += max(0, pending.stake)
        save()
    }

    /// 정산되지 않은 랭크전을 패배로 마감한다 — 기동 때 한 번 돈다.
    ///
    /// 크래시와 고의 종료는 로컬에서 구분할 수 없다. 환급으로 두면 "지고 있으면 앱을 끈다"가
    /// 다시 최적해가 되므로 랭크 게임의 통상 규칙대로 이탈은 패배로 본다.
    private func settleAbandonedRankedBattleIfNeeded() {
        guard let pending = state.pendingRanked else { return }
        let delta = settleRankedBrawl(won: false, opponent: pending.opponent)
        AppLog.write("abandoned ranked battle settled as a loss: stake \(pending.stake), \(delta) LP")
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

    // MARK: 체육관 첫 승리 보상

    /// 체육관 승리 기록 — **첫 승리에만** 별의조각과 알이 나간다. 현행 리그는 기존 `gymBadges`와
    /// 분리된 `gymLeagueBadges`를 써 이전 배지 기록과 겹치지 않는다. 배지는 표시하지 않지만,
    /// 여덟 곳을 모두 이기면 이로치 확정 부화 1회가 더해진다.
    ///
    /// 멱등성이 이 함수의 전부다. 체육관은 몇 번이고 다시 갈 수 있게 열어 둘 참인데, 그러면
    /// 승리 지점을 반복해서 지나게 된다 — 졸업이 정확히 그 구조로 알을 무한히 뱉었다(#27→#34).
    /// 여기서는 내부 첫 승리 키가 가드다: 들어 있으면 아무것도 지급하지 않는다.
    @discardableResult
    func recordGymVictory(_ gym: Gym) -> GymReward? {
        guard !state.gymLeagueBadges.contains(gym.id) else { return nil }
        state.gymLeagueBadges.insert(gym.id)
        var reward = gym.firstClearReward
        if state.gymLeagueBadges.count == GymLeague.catalog.count {
            reward = reward.merging(GymLeague.completionReward)
        }
        grantReward(reward)
        save()
        return reward
    }

    // MARK: 포켓로그식 런 (프로토타입)

    /// 진행 중인 런. **메모리 전용이다** — 팝오버를 닫거나 다른 탭을 들렀다 와도 이어지지만 앱을
    /// 끄면 사라진다. 세이브·무결성 서명에 넣지 않으므로 밸런스를 고쳐도 이전이 필요 없다
    /// (영속은 `RunProgress` 를 확정한 뒤에 붙인다).
    var rogueRun: RogueRun?

    /// 웨이브 런 실적. 판 밖으로 남는 것은 이 값 하나다 — 재화도 도감도 주지 않는다.
    var runProgress: RunProgress { state.waveRun }

    /// 끝난 판 하나를 실적에 적는다. **끝난 판만 센다** — 화면만 열고 닫은 판을 실패로 세면
    /// 클리어율이 실제보다 낮게 보인다. 도달 웨이브는 코어가 든 값이라 화면이 보낸 값을 클램프한다.
    func recordRunResult(reachedWave: Int, cleared: Bool) {
        state.waveRun.record(reachedWave: reachedWave, cleared: cleared)
        state.waveRun.normalize()
        save()
    }

    // MARK: 퍼즐 던전 (#79)

    /// 오늘의 맵. 날짜 키에서 나오므로 저장하지 않는다 — 매번 같은 값이 다시 계산된다.
    var dungeonMap: DungeonMap { PuzzleDungeon.map(dayKey: Self.dayKey(clock())) }

    /// 오늘 쓸 체력 예산. 기준선 100 에 보정만 더한다. `usedItem` 은 시도 시작에서 실제로
    /// 먹는샘물을 마셨는지이고, 화면에 예산을 미리 보여줄 때는 보유 여부로 가늠한다.
    func dungeonBudget(usedItem: Bool) -> Int {
        PuzzleDungeon.budget(partnerTypes: currentTypes,
                             against: dungeonMap.affinity,
                             usedItem: usedItem,
                             trainerLevel: state.trainer.level)
    }

    /// 먹는샘물을 마시면 얼마가 되는지 — 카드에 "지금 들어가면 103" 을 그리는 값.
    var dungeonBudgetPreview: Int { dungeonBudget(usedItem: itemCount(.freshWater) > 0) }

    var dungeonCleared: Bool {
        var progress = state.dungeon
        progress.roll(dayKey: Self.dayKey(clock()))
        return progress.cleared
    }

    /// 새 시도 — 오늘 기억한 방을 들려 보낸다. 시도 중 상태는 저장되지 않는다.
    ///
    /// `drinkFreshWater` 가 참이고 재고가 있으면 **여기서 한 병을 소모한다.** 소모와 예산 계산이
    /// 갈라지면 마셨는데 예산이 안 오르거나(재고만 줄고) 그 반대가 된다 — 한 지점에서 같이 한다.
    func startDungeonRun(drinkFreshWater: Bool = false) -> DungeonRun {
        state.dungeon.roll(dayKey: Self.dayKey(clock()))
        var drank = false
        if drinkFreshWater, itemCount(.freshWater) > 0 {
            state.inventory[ItemKind.freshWater.rawValue] = itemCount(.freshWater) - 1
            drank = true
            save()
        }
        return DungeonRun(map: dungeonMap, budget: dungeonBudget(usedItem: drank),
                          remembered: state.dungeon.remembered, looted: state.dungeon.looted)
    }

    /// 곁방 보물 정산 — **하루 한 번만.** 이미 턴 방이면 0 을 돌려주고 아무것도 바꾸지 않는다.
    /// 시도가 실패로 끝나도 턴 보물은 남는다(하루 상한이 방 단위라 시도 결과와 무관하다).
    @discardableResult
    func lootDungeonCache(room: Int, starPieces: Int) -> Int {
        state.dungeon.roll(dayKey: Self.dayKey(clock()))
        guard dungeonMap.rooms.indices.contains(room), dungeonMap.room(room).kind == .cache,
              !state.dungeon.looted.contains(room) else { return 0 }
        // 액수는 맵이 정한다 — 화면이 보낸 값을 믿지 않는다.
        let amount = dungeonMap.room(room).damage
        state.dungeon.looted.insert(room)
        state.dungeon.remembered[room] = .cache
        state.starPieces += amount
        save()
        return amount
    }

    /// 시도가 끝나거나 화면을 닫을 때 맵 기억만 남긴다(실패·이탈은 시도만 버린다).
    func rememberDungeon(_ revealed: [Int: RoomKind]) {
        state.dungeon.roll(dayKey: Self.dayKey(clock()))
        state.dungeon.remembered.merge(revealed) { _, new in new }
        state.dungeon.normalize()
        save()
    }

    /// 클리어 정산 — **여기 한 곳에서만** 보상이 나간다. 이미 정산했으면 0 을 돌려주고
    /// 그 뒤 재플레이는 보상 없는 연습으로 열려 있다.
    @discardableResult
    func settleDungeonClear(revealed: [Int: RoomKind], sweptAllCaches: Bool = false) -> Int {
        state.dungeon.roll(dayKey: Self.dayKey(clock()))
        state.dungeon.remembered.merge(revealed) { _, new in new }
        state.dungeon.cleared = true
        state.dungeon.normalize()
        guard !state.dungeon.rewardPaid else { save(); return 0 }
        state.dungeon.rewardPaid = true
        state.starPieces += PuzzleDungeon.firstClearReward
        // 재정산은 위 guard 가 막는다 — 업적 기록도 그 안쪽이라야 재플레이가 카운터를 올리지 않는다.
        recordAchievement(.dungeon, 1)
        if sweptAllCaches { recordAchievement(.dungeonSweep, 1) }
        save()
        notifyCompanionEvent(l.dungeonClearedTitle,
                             l.dungeonRewardBody(PuzzleDungeon.firstClearReward))
        return PuzzleDungeon.firstClearReward
    }

    /// 보상 지급 — 알은 보관 알로 들어가고(5분 뒤 부화), 보증과 이로치 확정은 상태에 쌓인다.
    /// 체육관과 도감 목표가 같은 보상 형태를 쓰므로 지급 경로도 하나다.
    private func grantReward(_ reward: GymReward) {
        state.starPieces += reward.starPieces
        if reward.eggs > 0 {
            state.focusEggs = min(999, state.focusEggs + reward.eggs)
            for _ in 0..<reward.eggs {
                state.focusEggReadyDates.append(clock().addingTimeInterval(Self.storedEggHatchDelay))
            }
            state.eggTier = Self.strongerGuarantee(state.eggTier, reward.eggGuarantee)
        }
        state.shinyEggCharges = min(99, state.shinyEggCharges + reward.shinyCharges)
    }

    /// 토너먼트 우승 보상. 참가 인원에 따른 보증만 다르고 전설 보증은 만들지 않는다.
    func grantTournamentEgg(_ reward: TournamentEggReward) {
        guard state.focusEggs < 999 else { return }
        state.focusEggs += 1
        state.focusEggReadyDates.append(clock().addingTimeInterval(Self.storedEggHatchDelay))
        state.eggTier = Self.strongerGuarantee(state.eggTier, reward.guarantee)
        save()
        notifyCompanionEvent(l.t("토너먼트 우승!", "Tournament Champion!", "トーナメント優勝！"),
                             l.t("우승 보상 알이 도착했습니다.", "Your champion Egg has arrived.",
                                 "優勝報酬のタマゴが届きました。"))
    }

    /// 이로치 확정을 **한 번 쓴다.** 남아 있으면 true 를 돌려주고 하나 깎는다.
    ///
    /// 두 부화 경로가 모두 이걸 지나야 한다. `eggTier` 가 한쪽에서만 소비돼 영구 보증이 됐던 것과
    /// 같은 부류다 — 확정이 안 깎이면 그 뒤 모든 부화가 이로치가 된다.
    private func consumeShinyCharge() -> Bool {
        guard state.shinyEggCharges > 0 else { return false }
        state.shinyEggCharges -= 1
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

    /// 로컬 시간대 기준 YYYY-MM-DD — 일일 보상 원장 키.
    ///
    /// 달력은 시즌 만료와 **같은 접근자**(`SeasonBoard.gregorian`)를 쓴다 — 갈라지면 자정 근처에서
    /// 원장 키와 남은 일수가 다른 날을 센다. 그 접근자를 굳히거나 `timeZone = .current` 로 덮으면
    /// 실행 중 시간대 변경을 놓친다(이유는 `SeasonBoard.gregorian` 주석).
    /// `DateFormatter` 대신 성분을 조립하는 건 호출당 생성 비용 때문이다(실측 16.3µs → 1.6µs).
    nonisolated static func dayKey(_ date: Date) -> String {
        let parts = SeasonBoard.gregorian.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// 로컬 달력 기준 YYYY-MM — 시즌 원장 키. 포맷터를 하나 더 두지 않고 `dayKey` 를 자른다 —
    /// 두 원장 키가 다른 로케일·달력으로 갈라질 여지를 없앤다.
    nonisolated static func seasonKey(_ date: Date) -> String {
        String(dayKey(date).prefix(7))
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
               let planned = node.children.first(where: {
                   $0.speciesID == a.plannedPathIDs[nextIndex] && Self.routeMatches($0, mon: a, date: clock())
               }) {
                next = planned
            } else {
                guard let picked = pickPlannedChild(node, baseID: a.baseID) else { break }
                next = picked
                let fallbackRoute = [node.speciesID] + makeEvolutionPlan(from: next, baseID: a.baseID)
                let repaired = Self.repairedPlan(realizedPath: a.pathIDs, stageIndex: a.stageIndex,
                                                 fallbackRoute: fallbackRoute)
                state.active!.plannedPathIDs = repaired
                state.active!.totalForms = repaired.count
                AppLog.write("evolve: repaired invalid planned path for base \(a.baseID)")
            }
            guard Self.routeMatches(next, mon: a, date: clock()) else { break }
            guard next.evolutionPartySpeciesID.map({ required in
                ownedMons.contains(where: { $0.currentID == required })
            }) ?? true else { break }
            // 본가처럼 레벨만으로 게이팅한다 — acceptEvolution() 도 이미 usedAtStage 를 참조하지
            // 않고 0 으로 리셋할 뿐이다(#19). 여기서 성장치까지 같이 요구하면 acceptEvolution 이
            // 절대 실행 못 하는 조건을 사전에 막는, 실질 의미 없는 이중 게이트가 된다.
            if let moveID = next.evolutionKnownMoveID {
                guard a.learnedMoves.contains(where: { $0.id == moveID }) else { break }
                let requiredLevel = a.level
                if declinedEvolutionMonID == a.id, declinedEvolutionLevel == a.level,
                   declinedEvolutionTargetID == next.speciesID { break }
                if evolutionPrompt == nil {
                    evolutionPrompt = EvolutionPrompt(monID: a.id, fromSpeciesID: a.currentID,
                        toSpeciesID: next.speciesID, requiredLevel: requiredLevel,
                        toName: line.localizedName(next.speciesID, state.language))
                }
                break
            }
            if next.evolutionTrigger == "level-up", next.evolutionLevel == nil,
               next.evolutionPartySpeciesID != nil || next.evolutionTimeOfDay != nil
                    || next.evolutionRelativePhysicalStats != nil {
                let requiredLevel = a.level
                if declinedEvolutionMonID == a.id, declinedEvolutionLevel == a.level,
                   declinedEvolutionTargetID == next.speciesID { break }
                if evolutionPrompt == nil {
                    evolutionPrompt = EvolutionPrompt(monID: a.id, fromSpeciesID: a.currentID,
                        toSpeciesID: next.speciesID, requiredLevel: requiredLevel,
                        toName: line.localizedName(next.speciesID, state.language))
                }
                break
            }
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
            // 아이템·지닌물건이 필요한 진화는 성장치만으로 열리면 안 된다 — 열리면 진화 아이템이
            // 무의미해지고 졸업 면제 판정(grewIntoFinalByItem)도 실제 경로와 어긋난다.
            guard next.evolutionItem == nil, next.evolutionHeldItem == nil else { break }
            // 특정 기술을 배운 채로 자라야 하는 진화(원시의힘·흉내내기·구르기·더블어택)는 그 기술을
            // 들고 있을 때만 연다. 본가와 같은 조건이고, 앱이 판정할 재료(learnedMoves)도 이미 있다.
            //
            // 기술 조건이 **아닌** 나머지(장소·파티·shed)는 판정할 축이 없어 여전히 닫아 둔다 —
            // 트리거가 채워져 있으면 우리가 모르는 조건이라는 뜻이므로 성장치만으로 열지 않는다.
            if let requiredMoveID = next.evolutionKnownMoveID {
                guard a.learnedMoves.contains(where: { $0.id == requiredMoveID }) else { break }
            } else {
                guard next.evolutionTrigger == nil else { break }
            }
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

    private func pickPlannedChild(_ node: EvoNode, baseID: Int, gender: PokemonGender? = nil) -> EvoNode? {
        let resolvedGender = gender ?? state.active?.gender
        // 성별 전용 자식은 일치할 때만 후보가 된다. 조건 없는 자식은 어느 성별이든 가능하다.
        let candidates = node.children.filter {
            ($0.evolutionTrigger != "shed")
                && ($0.evolutionGender == nil || resolvedGender == nil || $0.evolutionGender == resolvedGender)
                && ($0.evolutionRelativePhysicalStats == nil
                    || state.active?.evolutionStatRelation == nil
                    || $0.evolutionRelativePhysicalStats == state.active?.evolutionStatRelation)
        }
        guard !candidates.isEmpty else { return nil }
        let fresh = candidates.filter { ch in
            ch.finalIDs.contains { !state.collectedFinals.contains("\(baseID):\($0)") }
        }
        let pool = fresh.isEmpty ? candidates : fresh
        return pool[Int(rng.next() % UInt64(pool.count))]
    }

    private static func routeMatches(_ node: EvoNode, mon: MonState, date: Date) -> Bool {
        guard node.evolutionTrigger != "shed",
              node.evolutionGender == nil || node.evolutionGender == mon.gender,
              node.evolutionRelativePhysicalStats == nil
                || node.evolutionRelativePhysicalStats == mon.evolutionStatRelation else { return false }
        guard let time = node.evolutionTimeOfDay else { return true }
        let hour = Calendar.current.component(.hour, from: date)
        return time == "day" ? (6..<18).contains(hour) : !(6..<18).contains(hour)
    }

    private func makeEvolutionPlan(from root: EvoNode, baseID: Int, gender: PokemonGender? = nil) -> [Int] {
        var plan = [root.speciesID]
        var node = root
        while !node.children.isEmpty {
            guard let next = pickPlannedChild(node, baseID: baseID, gender: gender) else { break }
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
    ///
    /// 레벨 30 면제는 **레벨로 진화해 온 개체**에만 준다(#19). 자동 진화 경로가
    /// `guard a.level >= requiredLevel` 로 막혀 있어, 최종형에 닿았다는 것 자체가 그 종의 마지막
    /// 진화 요구 레벨을 통과했다는 뜻이기 때문이다. 무진화 종(totalForms==1)은 그 관문이 아예
    /// 없어 레벨 30 을 대신 세운다.
    ///
    /// 아이템·교환 진화는 그 관문이 없다 — `useEvolutionItem` 은 레벨을 보지 않는다. 그래서
    /// 500 짜리 돌 하나로 레벨 1 개체를 최종형으로 만든 뒤 졸업해, 20,000 짜리 알과 도감·트레이너
    /// 포인트·주간 미션을 한 번에 받아내는 경로가 열려 있었다(개체는 박스에 버리면 그만이다).
    /// 그 경로로 온 개체는 면제 대상이 아니다.
    var canGraduate: Bool {
        guard let a = state.active, let line = currentLine,
              line.tree.node(withID: a.currentID)?.children.isEmpty == true else { return false }
        // 이미 졸업한 개체는 다시 졸업할 수 없다. 졸업해도 개체는 박스에 남으므로(#27) 박스에서
        // 다시 꺼내면 최종형·레벨 조건은 그대로 만족한다 — 이 검사가 없으면 졸업 → 스위치 → 졸업을
        // 반복해 알을 무한히 받아낼 수 있다. 도감 기록도 그 개체당 한 번이어야 한다.
        guard !a.isGraduated else { return false }
        let earnedExemption = a.totalForms > 1 && !grewIntoFinalByItem(a, in: line)
        return earnedExemption || a.level >= PokemonBalance.graduationRequiredLevel
    }

    /// 졸업까지 채워야 하는 레벨 — **관문에 걸려 있을 때만** 값이 있다.
    /// 이미 졸업할 수 있거나, 최종형이 아니거나, 레벨 면제를 받은 개체면 nil 이다.
    ///
    /// 이게 없으면 화면이 아무 말도 하지 않는다. 최종형에 닿는 순간 "Lv.N 에 진화"도
    /// "○○돌 필요"도 사라지고, 졸업 버튼은 조건을 채워야 나타나므로 **왜 못 하는지 알 길이 없다**.
    /// 돌로 진화시킨 개체가 특히 그렇다 — 레벨 1 파르셀은 최종형이지만 졸업은 한참 남았다.
    var graduationLevelRequirement: Int? {
        guard let active = state.active, let line = currentLine,
              line.tree.node(withID: active.currentID)?.children.isEmpty == true,
              !active.isGraduated, !canGraduate else { return nil }
        return PokemonBalance.graduationRequiredLevel
    }

    /// 지금 형태까지 오는 동안 아이템·교환 진화를 한 번이라도 거쳤는가.
    ///
    /// 걸어온 길(`pathIDs`)의 전이를 하나씩 트리에서 조회한다 — 개체에는 "어떻게 진화했는지" 가
    /// 남지 않아 경로를 되짚는 수밖에 없다. 한 번이라도 섞였으면 레벨 관문을 지나온 게 아니다.
    private func grewIntoFinalByItem(_ mon: MonState, in line: EvoLine) -> Bool {
        for (index, speciesID) in mon.pathIDs.enumerated() where index > 0 {
            guard let parent = line.tree.node(withID: mon.pathIDs[index - 1]),
                  let child = parent.children.first(where: { $0.speciesID == speciesID })
            else { continue }
            // 지닌물건 진화(#89)도 같은 부류다 — trigger 가 level-up 인 것(어둠대신·붐볼)까지 있어
            // 트리거만 보면 예리한손톱으로 최종형이 된 개체가 레벨 면제를 그대로 받아 간다.
            if child.evolutionTrigger == "use-item" || child.evolutionTrigger == "trade"
                || child.evolutionHeldItem != nil { return true }
        }
        return false
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
        // 졸업은 파트너를 초기화하지만 트레이너 성장은 여기서 이어진다 — 모험을 한 번도 하지 않고
        // 졸업만 해도 적립된다(집중 경로와 독립).
        accrueTrainerPoints(TrainerLevel.graduationPoints)
        // 졸업은 파트너를 초기화하지만 미션 진행은 여기서 이어진다 — 모험을 한 번도 하지 않고
        // 졸업만 해도 기록된다(집중 경로와 독립).
        recordMission(.graduations, 1)
        recordSeason(.graduations, 1)
        // 도감 목표는 이 항목이 들어가기 **전**의 완료 집합과 비교해 지급한다 — 스냅샷을 먼저 잡는다.
        let goalsBefore = DexGoals.completed(in: state.dex)
        state.dex.append(DexEntry(baseID: a.baseID, finalID: finalID,
                                  chainOrder: a.pathIDs, rarity: a.rarity, caughtAt: clock(),
                                  isShiny: a.isShiny, nature: a.nature,
                                  names: currentLine.map { line in   // 체인 각 종의 다국어 이름 저장(표시 즉시)
                                      Dictionary(uniqueKeysWithValues:
                                          a.pathIDs.compactMap { id in line.names[id].map { (id, $0) } })
                                  },
                                  // 타입을 모르면(오프라인) 빈 배열이 아니라 nil 로 남긴다 —
                                  // 빈 배열은 "타입 없음"이라 백필이 영영 재시도하지 않는다.
                                  types: currentTypes.isEmpty ? nil : currentTypes))
        grantNewlyCompletedDexGoals(before: goalsBefore)
        let name = currentLine?.localizedName(finalID, state.language) ?? ""
        justGraduated = name
        notifyCompanionEvent(l.notifGraduateTitle, l.notifGraduateBody(name))
        eventUntil = clock().addingTimeInterval(6)
        // 도감은 기록만 남는다(DexEntry 엔 레벨·경험치가 없다) — 개체 자체는 박스로 옮겨 계속
        // 키울 수 있게 한다. 예전엔 여기서 그냥 버려서, 졸업이 곧 그 개체의 영구 삭제였다.
        var graduated = a
        graduated.isGraduated = true   // 영구 DexEntry 가 이미 기록됐다 — 화면용 행으로 중복 집계 금지(#28)
        state.boxedMons.append(graduated)
        state.active = nil
        // 졸업도 개체 교체다 — 남은 학습 제안은 그 개체 몫이므로 함께 버린다.
        pendingMoveLearningPrompt = nil
        moveLearningQueue.removeAll()
        activeGeneration += 1
        currentLine = nil
        // 졸업 보상 알은 보관 알과 같은 5분 타이머를 쓴다. 예전엔 eggUsage(누적 임계) 알을 줬는데,
        // 그 값을 채우는 생산 경로가 Pokédoro 개편으로 사라져(accrue 는 호출자가 없다) 영원히
        // 부화하지 않았다 — 졸업이 곧 진행 정지였다. 타이머 경로는 hatchStoredEggIfNeeded 가
        // 이미 돌리고 있고, 활성이 비어 있으면 박스가 아니라 활성으로 부화한다.
        state.focusEggs = min(999, state.focusEggs + 1)
        state.focusEggReadyDates.append(clock().addingTimeInterval(Self.storedEggHatchDelay))
        // 도감 기록·졸업 알·목표 보상이 모두 이 함수에서만 생긴다 — 다음 틱(60초)을 기다리면
        // 그 사이 종료가 알림만 남기고 지급을 날린다.
        save()
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
        state.active!.gainExperience(RareCandy.xp)
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

    // MARK: 하트비늘 (기술 다시 배우기 — #97)

    /// 사용 가능 — 활성 개체 + 재고>0 + 조회 중 아님. `currentLine` 은 보지 않는다(민트와 같은 이유:
    /// pathIDs·level 은 MonState 에 있어 재시작 직후·오프라인에도 판정할 수 있다).
    var canUseHeartScale: Bool {
        hasActive && itemCount(.heartScale) > 0 && !isLoadingRelearnCandidates
    }

    /// 하트비늘 사용 — 후보를 조회해 목록 카드를 띄운다. **여기서는 아무것도 소모하지 않는다**
    /// (소모는 `acceptMoveLearning` 이 무브셋을 바꿀 때).
    func useHeartScale() {
        guard canUseHeartScale, let mon = state.active else { return }
        let monID = mon.id
        isLoadingRelearnCandidates = true
        Task { @MainActor in
            defer { isLoadingRelearnCandidates = false }
            var inherited: [[MoveSpec]] = []
            var index = 0
            // pathIDs 도 매 반복 다시 읽는다 — 조회 중에 진화하면 경로에 종이 **붙는다**. 캡처본으로
            // 돌면 새로 붙은 종의 기술이 후보에서 통째로 빠진다.
            while true {
                // 도중에 개체가 바뀌었으면(교체·졸업·리롤) 남은 조회는 그 개체 몫이 아니다.
                guard let current = state.active, current.id == monID else { return }
                guard index < current.pathIDs.count else { break }
                let speciesID = current.pathIDs[index]
                // 무브셋용(`canonicalLevelUpMoves`)이 아니라 **전체 이력**이다. 그쪽은 기술 칸 넷을
                // 채우는 함수라 4개에서 멈추는데, 다시 배우기는 배울 수 있었던 것 전부에서 고른다.
                let moves = await PokeAPIClient.shared
                    .levelUpMoveHistory(speciesID: speciesID, level: current.level)
                guard state.active?.id == monID else { return }   // await 뒤 재확인
                inherited.append(moves)
                index += 1
            }
            // 배운 기술은 루프가 끝난 **지금** 다시 읽는다 — await 사이에 다른 카드에서 기술을
            // 배웠을 수 있고, 캡처본으로 계산하면 이미 배운 기술을 후보로 내놓는다(queueMoveLearning 과 같은 함정).
            guard let fresh = state.active, fresh.id == monID else { return }
            pendingRelearnPrompt = RelearnPrompt(
                monID: monID,
                candidates: MoveRelearn.candidates(inherited: inherited, learned: fresh.learnedMoves))
        }
    }

    /// 후보 하나를 고른다 → 기존 학습 카드로 넘긴다(4개 꽉 찬 개체의 교체 UI 를 새로 만들지 않는다).
    /// 카드가 떠 있는 동안 재고가 사라졌으면(다른 경로 소모) 넘기지 않고 목록만 닫는다.
    func pickRelearnCandidate(_ move: MoveSpec) {
        guard let prompt = relearnPrompt, itemCount(.heartScale) > 0 else {
            pendingRelearnPrompt = nil
            return
        }
        pendingRelearnPrompt = nil
        pendingMoveLearningPrompt = MoveLearningPrompt(
            monID: prompt.monID, level: state.active?.level ?? 0, move: move, origin: .heartScale)
    }

    /// 후보 목록 닫기 — 무소모.
    func cancelRelearn() { pendingRelearnPrompt = nil }

    func canUseEvolutionItem(_ kind: ItemKind) -> Bool {
        guard itemCount(kind) > 0, let rule = kind.evolutionRule,
              let mon = state.active, let node = currentLine?.tree.node(withID: mon.currentID) else { return false }
        return node.children.contains {
            rule.opens($0) && Self.routeMatches($0, mon: mon, date: clock())
        }
    }

    private static func genderAllows(_ node: EvoNode, _ gender: PokemonGender?) -> Bool {
        node.evolutionGender == nil || node.evolutionGender == gender
    }

    @discardableResult
    func useEvolutionItem(_ kind: ItemKind) -> Bool {
        guard canUseEvolutionItem(kind), let rule = kind.evolutionRule,
              let line = currentLine, let mon = state.active,
              let node = line.tree.node(withID: mon.currentID),
              let next = node.children.first(where: {
                  rule.opens($0) && Self.routeMatches($0, mon: mon, date: clock())
              })
        else { return false }
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

    func technicalMachineCount(_ moveID: Int) -> Int { state.technicalMachines[moveID] ?? 0 }

    var ownedTechnicalMachines: [(machine: TechnicalMachine, count: Int)] {
        TechnicalMachine.catalog.compactMap { machine in
            let count = technicalMachineCount(machine.moveID)
            return count > 0 ? (machine, count) : nil
        }
    }

    func canBuyTechnicalMachine(_ machine: TechnicalMachine) -> Bool {
        availableTokens >= machine.price
    }

    @discardableResult
    func buyTechnicalMachine(_ machine: TechnicalMachine) -> Bool {
        guard canBuyTechnicalMachine(machine) else { return false }
        state.starPieces -= machine.price
        state.technicalMachines[machine.moveID, default: 0] += 1
        save()
        return true
    }

    /// 기술머신 사용은 구매와 분리한다. 호환되지 않거나 이미 배운 기술이면 재고를 소모하지 않는다.
    /// 실제 소모는 학습/교체가 확정되는 `acceptMoveLearning`에서만 일어난다.
    @discardableResult
    func useTechnicalMachine(_ machine: TechnicalMachine) async -> Bool {
        guard let mon = state.active, technicalMachineCount(machine.moveID) > 0,
              pendingMoveLearningPrompt == nil,
              !mon.learnedMoves.contains(where: { $0.id == machine.moveID }),
              await provider.canLearnMachine(speciesID: mon.currentID, moveID: machine.moveID),
              let move = await provider.moveDetail(id: machine.moveID),
              state.active?.id == mon.id else { return false }
        pendingMoveLearningPrompt = MoveLearningPrompt(monID: mon.id, level: mon.level,
                                                       move: move, origin: .technicalMachine)
        return true
    }

    /// 상점 판매 아이템 — shopPrice 있는 것만. 가격 저렴한 순, 단 구매 완료한 보유형은 맨 아래로.
    var purchasableItems: [ItemKind] {
        ItemKind.allCases
            .filter { $0.shopPrice != nil }
            .sorted { a, b in
                // 구매 완료한 보유형(이로치 부적 등)은 맨 아래로 — 재구매 불가라 위에 있을 이유가 없다.
                let aDone = a.isPassive && itemCount(a) > 0
                let bDone = b.isPassive && itemCount(b) > 0
                if aDone != bDone { return !aDone }
                let (pa, pb) = (a.shopPrice ?? 0, b.shopPrice ?? 0)
                // 진화 아이템 28종이 모두 같은 값이라 가격만으로는 순서가 정해지지 않는다(sort 는
                // 안정 정렬이 아니라 목록이 실행마다 뒤바뀔 수 있다) → 선언 순서로 고정한다.
                if pa != pb { return pa < pb }
                return Self.declarationOrder(a) < Self.declarationOrder(b)
            }
    }

    /// ItemKind 선언 순서 — 같은 가격 아이템의 표시 순서를 결정적으로 만드는 tiebreaker.
    private static func declarationOrder(_ kind: ItemKind) -> Int {
        ItemKind.allCases.firstIndex(of: kind) ?? Int.max
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
        entries += OutfitItem.allCases.filter { $0.shopPrice != nil }.map { ShopEntry.outfit($0) }
        // enumerated 인덱스를 tiebreaker 로 써서 같은 가격끼리는 위 병합 순서(= purchasableItems 의
        // 선언 순서)를 유지한다. 진화 아이템 28종이 전부 같은 값이라 이게 없으면 매 호출 순서가 다를 수 있다.
        return entries.enumerated().sorted { a, b in
            let aDone = isPurchasedPassive(a.element)
            let bDone = isPurchasedPassive(b.element)
            if aDone != bDone { return !aDone }
            if a.element.price != b.element.price { return a.element.price < b.element.price }
            return a.offset < b.offset
        }.map(\.element)
    }

    /// 구매 완료한 보유형(이로치 부적·의상 등)인지 — shopEntries 정렬에서 맨 아래로 보낼 판정.
    private func isPurchasedPassive(_ entry: ShopEntry) -> Bool {
        switch entry {
        case .item(let kind): return kind.isPassive && itemCount(kind) > 0
        case .outfit(let item): return ownsOutfit(item)   // 재구매 불가라 위에 있을 이유가 없다
        case .egg: return false   // 즉시 액션 — 보유 개념 없음
        }
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

    // MARK: 의상

    var outfit: TrainerOutfit { state.outfit }
    func ownsOutfit(_ item: OutfitItem) -> Bool { state.ownedOutfits.contains(item) }

    /// 구매 가능 — 상점 판매(업적 전용은 nil) + 미소유 + 잔액 충분.
    func canBuyOutfit(_ item: OutfitItem) -> Bool {
        guard let price = item.shopPrice, !ownsOutfit(item) else { return false }
        return availableTokens >= price
    }

    /// 의상 1개 구매 — `buy(_:)` 와 같은 규칙(지갑 차감, 소유 추가, 저장). 미판매·소유·잔액 부족은 no-op.
    @discardableResult
    func buyOutfit(_ item: OutfitItem) -> Bool {
        guard canBuyOutfit(item), let price = item.shopPrice else { return false }
        state.starPieces -= price
        state.ownedOutfits.insert(item)
        save()
        return true
    }

    /// 업적 보상 경로 — 값을 받지 않는다. 이미 있으면 false(중복 지급 아님).
    @discardableResult
    func grantOutfit(_ item: OutfitItem) -> Bool {
        guard !ownsOutfit(item) else { return false }
        state.ownedOutfits.insert(item)
        save()
        return true
    }

    /// nil 이면 벗는다. 미소유·슬롯 불일치는 무시 — 신뢰경계는 `normalized(owned:)` 하나다.
    func wear(_ item: OutfitItem?, in slot: OutfitSlot) {
        var worn = state.outfit.worn
        if let item { worn[slot] = item } else { worn.removeValue(forKey: slot) }
        state.outfit = TrainerOutfit(worn: worn).normalized(owned: state.ownedOutfits)
        save()
    }

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
        // 값을 매길 때 쓴 보증을 상태에도 적는다. 이 줄이 없어서 등급 보증 알은 값만 비싸고
        // 아무것도 보장하지 않았다 — 상점이 보증 알을 팔지 않아 드러나지 않았을 뿐이다.
        state.eggTier = Self.strongerGuarantee(state.eggTier, tier)
        state.focusEggs = min(999, state.focusEggs + 1)
        state.focusEggReadyDates.append(clock().addingTimeInterval(Self.storedEggHatchDelay))
        AppLog.write("egg purchased: added to egg inventory")
        save()
        return true
    }

    /// 보증은 상태에 하나만 들어간다. 이미 들고 있는데 새로 받으면 **높은 쪽을 남긴다** —
    /// 낮은 등급으로 덮으면 이미 얻은 보증이 조용히 깎인다.
    static func strongerGuarantee(_ current: Rarity?, _ incoming: Rarity?) -> Rarity? {
        guard let incoming else { return current }
        guard let current else { return incoming }
        return incoming.sortRank > current.sortRank ? incoming : current
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
        // 보증을 여기서도 검사한다. `chooseBase` 가 후보를 좁히지만 인덱스가 낡았거나 REST 폴백을
        // 타면 미달이 올라온다 — `hatchCore` 와 같은 관문이다. 알과 보증을 그대로 두고 다음 틱에 다시.
        if let tier = state.eggTier, line.rarity.sortRank < tier.sortRank {
            AppLog.write("stored egg: rolled \(line.rarity) below guaranteed \(tier) — re-roll next tick")
            return
        }
        // **보증은 여기서 소비된다.** 예전엔 이 경로가 보증을 읽지도 지우지도 않아, 한 번 얻은
        // 보증이 남아 이후 모든 부화에 적용됐다(`hatchCore` 만 소비했다).
        state.eggTier = nil
        // rng 는 확정이든 아니든 항상 굴린다 — 소비량이 갈리면 같은 시드가 다른 결과를 낸다.
        let rolledShiny = Self.rollsShiny(roll: rng.next(), charmOwned: ownsShinyCharm)
        let shiny = consumeShinyCharge() || rolledShiny
        let nature = PokemonNature.allCases[Int(rng.next() % UInt64(PokemonNature.allCases.count))]
        let gender = PokemonGender.from(genderRate: line.genderRate, roll: rng.next())
        let statRelation = Int(rng.next() % 3) - 1
        let plan = makeEvolutionPlan(from: line.tree, baseID: line.baseID, gender: gender)
        let mon = MonState(baseID: line.baseID, pathIDs: [line.baseID], plannedPathIDs: plan,
                           stageIndex: 0, usedAtStage: 0, rarity: line.rarity, totalForms: plan.count,
                           isShiny: shiny, nature: nature, gender: gender,
                           evolutionStatRelation: statRelation,
                           names: line.names)   // 박스 개체는 currentLine 이 없어 이름을 여기서 들고 가야 한다
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
        // Stored eggs can hatch into the box while another companion is active.  Attribute
        // the evidence to the newborn rather than whichever companion happens to be active.
        recordEventMemory("\(name)이(가) 알에서 태어났다.", "\(name) hatched from an egg.", "\(name)がタマゴから生まれた。",
                          companionID: mon.id, eventID: "hatch:\(mon.id.uuidString)")
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
        let rolledShiny = Self.rollsShiny(roll: rng.next(), charmOwned: ownsShinyCharm)
        let isShiny = consumeShinyCharge() || rolledShiny
        let nature = PokemonNature.allCases[Int(rng.next() % UInt64(PokemonNature.allCases.count))]
        // 메타몽 위장 롤 — common·≥2형태에 한해 1/128. .app 게이트(&& 단락 → 비앱에선 rng 미소비로
        // 기존 테스트 RNG 시퀀스 무영향). 위장/리빌 로직은 상태 기반으로 별도 테스트한다.
        var dittoDisguise: Int?
        if dittoDisguiseRollingEnabled,
           Self.dittoDisguiseHit(rarity: line.rarity, totalForms: line.totalForms, roll: rng.next()) {
            dittoDisguise = line.baseID
        }
        // 새 개체 속성은 기존 메타몽 위장 롤 뒤에서 뽑는다. 앞에 끼우면 같은 시드의 위장 확률이
        // 앱 업데이트만으로 달라져 기존 결정론과 재현 가능한 테스트가 깨진다.
        let gender = PokemonGender.from(genderRate: line.genderRate, roll: rng.next())
        let statRelation = Int(rng.next() % 3) - 1
        let evolutionPlan = makeEvolutionPlan(from: line.tree, baseID: line.baseID, gender: gender)
        // 위장 중엔 이로치를 숨긴다 — 부화 알림·연출도 일반체로(정체는 리빌 때 공개).
        let showShiny = isShiny && dittoDisguise == nil
        activeGeneration += 1
        state.active = MonState(baseID: line.baseID, pathIDs: [line.baseID], plannedPathIDs: evolutionPlan,
                                stageIndex: 0, usedAtStage: 0, rarity: line.rarity, totalForms: evolutionPlan.count,
                                isShiny: isShiny, nature: nature, gender: gender,
                                evolutionStatRelation: statRelation, dittoDisguise: dittoDisguise,
                                names: line.names)   // 박스로 들어가도 도감이 이름을 그릴 수 있게 개체에 저장
        let hatchedID = state.active!.id
        AppLog.write("hatch: base=\(line.baseID) rarity=\(line.rarity) shiny=\(isShiny) forms=\(evolutionPlan.count) ditto=\(dittoDisguise != nil)")
        let name = line.localizedName(line.baseID, state.language)
        recordEventMemory("\(name)이(가) 알에서 태어났다.", "\(name) hatched from an egg.", "\(name)がタマゴから生まれた。",
                          companionID: hatchedID, eventID: "hatch:\(hatchedID.uuidString)")
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
            var migrated = latest
            if migrated.gender == nil {
                // 구버전 세이브 보완은 난수를 소비하지 않는다. 재실행할 때마다 이후 진화 경로·알 결과가
                // 달라지지 않도록 종 번호에서 안정적으로 성별을 정한다.
                migrated.gender = PokemonGender.from(genderRate: line.genderRate,
                                                      roll: UInt64(migrated.baseID))
                // 이미 저장된 유효 진화 경로는 유지한다. 성별 필드를 보완한다는 이유로 경로를 지우면
                // 업데이트 직후 사용자가 보던 진화 대상이 바뀌고 불필요한 RNG까지 소비된다.
            }
            if migrated.evolutionStatRelation == nil {
                migrated.evolutionStatRelation = (migrated.baseID % 3) - 1
            }
            state.active = normalizedEvolutionState(migrated, from: line.tree)
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
        try SaveTransfer.encode(state: state, memoryAlbum: memoryAlbum.snapshot, appVersion: appVersion, deviceName: deviceName, now: clock())
    }

    /// 검증된 세이브를 이 기기에 적용 — 기존 상태 백업 → 기기 기준 재정렬 → 저장 → 라인 재로딩.
    /// 백업을 못 남기면 **적용하지 않고** throw 한다 — 확인창이 "직전 상태가 남는다"고 약속하므로,
    /// 그 약속을 못 지키는 채로 덮어쓰면 사용자는 되돌릴 수단 없이 진행을 잃는다.
    func applySave(_ envelope: SaveEnvelope) throws {
        try backupStateBeforeImport()
        state = SaveTransfer.rebasedForThisDevice(envelope.state, current: state)
        let validIDs = Set(([state.active].compactMap { $0 } + state.boxedMons).map(\.id))
        if let importedAlbum = envelope.memoryAlbum {
            memoryAlbum.replace(with: importedAlbum, validCompanionIDs: validIDs)
        } else {
            memoryAlbum.prune(validCompanionIDs: validIDs)
        }
        chatStore.prune(validCompanionIDs: validIDs)
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
        guard let stateData = try? JSONEncoder().encode(state),
              let memoryData = try? memoryAlbum.snapshotData(),
              let chatData = try? chatStore.snapshotData() else { throw SaveTransferError.backupFailed }
        let dir = fileURL.deletingLastPathComponent()
        let names = SaveTransfer.importBackupFileNames(date: clock())
        let backup = dir.appendingPathComponent(names.state)
        let targets = [(backup, stateData), (dir.appendingPathComponent(names.memory), memoryData),
                       (dir.appendingPathComponent(names.chat), chatData)]
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            for (url, data) in targets { try data.write(to: url, options: .atomic) }
        } catch {
            for (url, _) in targets { try? FileManager.default.removeItem(at: url) }
            AppLog.write("save import aborted — backup write failed: \(error)")
            throw SaveTransferError.backupFailed
        }
        pruneImportBackups(in: dir)
        return backup
    }

    /// 세 파일을 한 묶음으로 유지한다 — 한쪽만 살아남으면 되돌릴 때 상태와 대화가 어긋난다.
    /// 파일명 접미가 초 단위 타임스탬프라 사전순 정렬이 곧 시간순이다.
    private func pruneImportBackups(in dir: URL) {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return }
        let stateNames = names.filter { $0.hasPrefix(SaveTransfer.backupFilePrefix) }.sorted()
        let complete = stateNames.filter { state in
            let stamp = state.replacingOccurrences(of: SaveTransfer.backupFilePrefix, with: "")
            return names.contains(SaveTransfer.memoryBackupFilePrefix + stamp)
                && names.contains(SaveTransfer.chatBackupFilePrefix + stamp)
        }
        guard complete.count > SaveTransfer.backupsToKeep else { return }
        for stale in complete.dropLast(SaveTransfer.backupsToKeep) {
            let stamp = stale.replacingOccurrences(of: SaveTransfer.backupFilePrefix, with: "")
            for name in [stale, SaveTransfer.memoryBackupFilePrefix + stamp, SaveTransfer.chatBackupFilePrefix + stamp] {
                try? FileManager.default.removeItem(at: dir.appendingPathComponent(name))
            }
        }
    }

    #if DEBUG
    /// 테스트 전용 — 도감을 직접 세팅(생산 배율·마이그레이션 계승 검증용). 프로덕션 경로 없음.
    func debugSetDex(_ entries: [DexEntry]) { state.dex = entries; save() }

    /// 업적 카운터를 원하는 지점에 세운다 — 문턱 직전·상한 도달처럼 실제 플레이로 수천 분이 드는
    /// 상태를 테스트가 밟는 유일한 수단이다. 보상 지급은 거치지 않는다.
    func debugSetAchievementCount(_ track: AchievementTrack, _ count: Int) {
        state.achievements.counts[track.rawValue] = count
        save()
    }
    /// 테스트 전용 — 박스를 직접 세팅(보관 알 부화의 네트워크 경로 없이 박스 상태만 재현). 프로덕션 경로 없음.
    func debugSetBoxedMons(_ mons: [MonState]) { state.boxedMons = mons; save() }
    /// 테스트 전용 — 레벨업 없이 기술 학습 제안을 세운다(네트워크 무브 조회 우회). 프로덕션 경로 없음.
    /// 테스트 전용 — 대기 중인(표시 전) 학습 제안 수.
    var debugMoveLearningQueueCount: Int { moveLearningQueue.count }
    func debugQueueMoveLearning(monID: UUID) {
        pendingMoveLearningPrompt = MoveLearningPrompt(
            monID: monID, level: 10,
            move: MoveSpec(id: 1, names: [:], type: .normal, power: 40,
                           damageClass: .physical, accuracy: 100, pp: 20))
    }
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
                state = SaveTransfer.sanitized(s, origin: .localDisk)
                return
            }
            state = SaveTransfer.resetForTamper(s)
            save()   // 즉시 새 서명으로 덮어써 조작본을 남기지 않는다
            return
        }
        // 불러오기 경계와 같은 정규화를 디스크에서 읽을 때도 건다. 불러오기만 막으면 **이미 저장된**
        // 극단값은 그대로 남아, 앱이 매 기동마다 같은 값을 읽어 산술 트랩으로 죽는 상태를 못 벗어난다
        // (디코드는 *성공*하므로 위의 .corrupt 복구도 발동하지 않는다). 여기서 걸면 자가 복구된다.
        // 출처를 .localDisk 로 넘겨 **개수 절단만** 뺀다 — 값 클램프는 그대로 걸린다(#145).
        state = SaveTransfer.sanitized(s, origin: .localDisk)
    }
    private func save() {
        // 저장 직전 서명 — 다음 로드에서 손편집을 잡는다(integrity 는 해시 입력에서 제외).
        guard let data = try? JSONEncoder().encode(SaveTransfer.signed(state)) else { return }
        try? data.write(to: fileURL, options: .atomic)   // 부분 쓰기 손상 방지(펫 상태)
    }
}
