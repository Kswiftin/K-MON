import Foundation

/// 부화 후보 — 진화라인 시작점(base) 종과 공식 희귀도.
struct BaseSpecies: Sendable, Codable {
    let id: Int
    let captureRate: Int    // 3(뮤츠급)~255(캐터피급), 공식 희귀도 신호
}

/// 포켓몬 라인 데이터 제공(주입 가능 — 테스트는 스텁 사용).
protocol PokeProviding: Sendable {
    func line(baseSpeciesID: Int) async throws -> EvoLine
    /// 1~5세대 base 전체 인덱스 (GraphQL 1쿼리, 디스크 캐시).
    func baseSpeciesIndex() async throws -> [BaseSpecies]
    /// 단일 종이 base(진화 시작점)면 BaseSpecies, 아니면 nil.
    /// GraphQL 인덱스 엔드포인트 장애 시 REST(pokemon-species)로 부화 후보를 뽑는 폴백용.
    func baseSpecies(id: Int) async throws -> BaseSpecies?
    /// 종의 타입·종족값. **타입이 도감에 영구 저장되므로**(`DexEntry.types`) 이 조회는 주입 가능해야
    /// 한다 — `PokeAPIClient.shared` 를 직접 부르면 그 경로를 밟는 테스트를 쓸 수 없다.
    func battleProfile(speciesID: Int) async throws -> PokemonBattleProfile
}

extension PokeProviding {
    /// 기본값은 실 클라이언트 — 타입을 쓰지 않는 스텁은 그대로 두면 된다.
    func battleProfile(speciesID: Int) async throws -> PokemonBattleProfile {
        try await PokeAPIClient.shared.battleProfile(speciesID: speciesID)
    }
}

/// PokéAPI 클라이언트 — 종/진화체인을 런타임 fetch + 파싱. 포켓몬 데이터는 레포에 번들하지 않는다.
/// species 응답은 actor 캐시(다국어 이름 재사용).
actor PokeAPIClient: PokeProviding {
    static let shared = PokeAPIClient()
    private let base = URL(string: "https://pokeapi.co/api/v2")!
    private let langCodes = ["ko", "en", "ja-Hrkt", "ja"]
    private var speciesCache: [Int: SpeciesDTO] = [:]
    private var lineCache: [Int: EvoLine] = [:]   // 프리패칭 → 부화 순간 네트워크 0

    func line(baseSpeciesID: Int) async throws -> EvoLine {
        if let cached = lineCache[baseSpeciesID] { return cached }
        let baseSpecies = try await species(baseSpeciesID)
        // PokéAPI 응답의 URL — 비정상/빈 값이면 force-unwrap 대신 throw(앱은 알 상태 유지).
        guard let chainURL = Self.validatedChainURL(baseSpecies.evolution_chain.url) else {
            throw URLError(.badURL)
        }
        let chainDTO: ChainDTO = try await get(chainURL)
        let tree = node(from: chainDTO.chain)
        let rarity = Rarity.from(captureRate: baseSpecies.capture_rate,
                                 isLegendary: baseSpecies.is_legendary,
                                 isMythical: baseSpecies.is_mythical)
        // 라인의 모든 종 이름(지원 언어만)
        var names: [Int: [String: String]] = [:]
        for id in allIDs(tree) {
            let sp = try await species(id)
            var byLang: [String: String] = [:]
            for n in sp.names where langCodes.contains(n.language.name) { byLang[n.language.name] = n.name }
            names[id] = byLang
        }
        let line = EvoLine(baseID: baseSpeciesID, tree: tree, rarity: rarity, names: names)
        lineCache[baseSpeciesID] = line
        return line
    }

    // MARK: base 인덱스 (부화 후보)

    private var baseIndexCache: [BaseSpecies]?
    private var restBuildInFlight = false
    private var restBuildTried = false   // 세션당 1회 (GraphQL 다운 시 REST 인덱스 구축 트리거)
    private static let baseIndexFile: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PokeTokenBar")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("base-index.json")
    }()
    private struct BaseIndexSnapshot: Codable { let fetchedAt: Date; let entries: [BaseSpecies] }
    private struct GraphQLBaseResponse: Decodable {
        struct DataBox: Decodable { let pokemonspecies: [Row] }
        struct Row: Decodable { let id: Int; let capture_rate: Int }
        let data: DataBox
    }

    /// 1~5세대 base(진화라인 시작점) 전체 — PokéAPI GraphQL 1쿼리.
    /// 우선순위: 메모리 캐시 → 디스크 캐시(30일 TTL) → GraphQL fetch(성공 시 디스크 갱신)
    /// → TTL 지난 디스크라도 있으면 사용(오프라인 폴백). 전부 실패 시 throw(알 유지, 다음 틱 재시도).
    func baseSpeciesIndex() async throws -> [BaseSpecies] {
        if let c = baseIndexCache { return c }
        let disk = (try? Data(contentsOf: Self.baseIndexFile))
            .flatMap { try? JSONDecoder().decode(BaseIndexSnapshot.self, from: $0) }
        if let disk, Date().timeIntervalSince(disk.fetchedAt) < 30 * 86400, !disk.entries.isEmpty {
            baseIndexCache = disk.entries
            return disk.entries
        }
        do {
            let entries = try await fetchBaseIndex()
            baseIndexCache = entries
            if let data = try? JSONEncoder().encode(BaseIndexSnapshot(fetchedAt: Date(), entries: entries)) {
                try? data.write(to: Self.baseIndexFile, options: .atomic)
            }
            return entries
        } catch {
            if let disk, !disk.entries.isEmpty {   // 오프라인 — 오래된 인덱스라도 사용
                baseIndexCache = disk.entries
                return disk.entries
            }
            // GraphQL 다운 + 캐시 없음 → REST 로 인덱스를 백그라운드 구축(세션 1회).
            // 이번 부화는 per-hatch REST 폴백(chooseBaseViaREST)이 즉시 처리하고,
            // 구축이 끝나면 디스크 캐시로 남아 이후 선택이 가중·수집반영·오프라인가능으로 복귀한다.
            if !restBuildTried {
                restBuildTried = true
                Task { await self.buildBaseIndexViaREST() }
            }
            AppLog.write("base index (GraphQL) failed, no cache — REST build triggered; per-hatch fallback handles now: \(error)")
            throw error
        }
    }

    /// GraphQL base 인덱스 엔드포인트 장애 시 REST(pokemon-species/{id})로 base 인덱스를 직접 구축·영속.
    /// 한 번 성공하면 base-index.json(30일)으로 남아 이후 선택은 네트워크 없이 가중·수집반영으로 동작 →
    /// 부화가 특정 엔드포인트 생존에 영구히 묶이지 않게 하는 자가치유 캐시. PokéAPI 배려로 소규모 동시성.
    func buildBaseIndexViaREST() async {
        guard baseIndexCache == nil, !restBuildInFlight else { return }
        restBuildInFlight = true
        defer { restBuildInFlight = false }
        AppLog.write("base index: building via REST (GraphQL unavailable)…")
        var bases: [BaseSpecies] = []
        let batchSize = 6
        var start = 1
        let maxID = PokemonAssets.animatedSpeciesIDs.upperBound
        while start <= maxID {
            let end = min(start + batchSize - 1, maxID)
            let found = await withTaskGroup(of: BaseSpecies?.self) { group -> [BaseSpecies] in
                for id in start...end { group.addTask { try? await self.baseSpecies(id: id) } }
                var acc: [BaseSpecies] = []
                for await r in group { if let r { acc.append(r) } }
                return acc
            }
            bases.append(contentsOf: found)
            start += batchSize
        }
        // 대부분 실패(네트워크 불안정)면 빈약한 인덱스를 영속하지 않고 다음 세션 재시도.
        guard bases.count >= 150 else {
            AppLog.write("base index: REST build incomplete (\(bases.count)) — not cached, will retry next session")
            return
        }
        bases.sort { $0.id < $1.id }
        baseIndexCache = bases
        if let data = try? JSONEncoder().encode(BaseIndexSnapshot(fetchedAt: Date(), entries: bases)) {
            try? data.write(to: Self.baseIndexFile, options: .atomic)
        }
        AppLog.write("base index: REST build done — \(bases.count) bases persisted (offline-capable now)")
    }

    private func fetchBaseIndex() async throws -> [BaseSpecies] {
        // 공식 GraphQL — evolves_from IS NULL(=base) + id ≤ 649(Gen-V 애니메이션 스프라이트 상한)
        guard let url = URL(string: "https://graphql.pokeapi.co/v1beta2") else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 15
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // 메타몽(#132)은 위장 리빌 전용 → 일반 부화 풀에서 제외(_neq).
        let maxID = PokemonAssets.animatedSpeciesIDs.upperBound
        let query = "{ pokemonspecies(where: {evolves_from_species_id: {_is_null: true}, id: {_lte: \(maxID), _neq: \(PokemonOdds.dittoSpeciesID)}}, order_by: {id: asc}) { id capture_rate } }"
        req.httpBody = try JSONSerialization.data(withJSONObject: ["query": query])
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        let decoded = try JSONDecoder().decode(GraphQLBaseResponse.self, from: data)
        let entries = decoded.data.pokemonspecies.map { BaseSpecies(id: $0.id, captureRate: $0.capture_rate) }
        guard !entries.isEmpty else { throw URLError(.cannotParseResponse) }
        return entries
    }

    private func species(_ id: Int) async throws -> SpeciesDTO {
        if let c = speciesCache[id] { return c }
        let dto: SpeciesDTO = try await get(base.appendingPathComponent("pokemon-species/\(id)"))
        speciesCache[id] = dto
        return dto
    }

    /// REST 폴백 — 단일 종 상세(pokemon-species/{id})로 base 여부·capture_rate 판정.
    /// GraphQL base 인덱스가 죽어도 REST(pokeapi.co/api/v2)는 별개 엔드포인트라 동작한다.
    func baseSpecies(id: Int) async throws -> BaseSpecies? {
        guard id != PokemonOdds.dittoSpeciesID else { return nil }   // 메타몽은 위장 리빌 전용 — 일반 부화 제외
        let dto = try await species(id)
        guard dto.evolves_from_species == nil else { return nil }   // 진화 중간체는 부화 후보 아님
        return BaseSpecies(id: id, captureRate: dto.capture_rate)
    }

    // MARK: 배틀 프로필 (종족값·타입)

    private var battleProfileCache: [Int: PokemonBattleProfile] = [:]

    /// `/pokemon/{id}` 에서 배틀에 필요한 종족값·타입만 파싱. id ≤ 649(Gen-V) 기본 폼은 species id 와 동일.
    /// PokéAPI 가 모르는 타입을 주면 건너뛴다(모두 무효면 throw — 스냅샷에 빈 types 를 내보내지 않게).
    func battleProfile(speciesID: Int) async throws -> PokemonBattleProfile {
        if let c = battleProfileCache[speciesID] { return c }
        let dto: PokemonDTO = try await get(base.appendingPathComponent("pokemon/\(speciesID)"))
        var stats = BattleStats(hp: 1, atk: 1, def: 1, spa: 1, spd: 1, spe: 1)
        for s in dto.stats {
            switch s.stat.name {
            case "hp":              stats.hp = s.base_stat
            case "attack":          stats.atk = s.base_stat
            case "defense":         stats.def = s.base_stat
            case "special-attack":  stats.spa = s.base_stat
            case "special-defense": stats.spd = s.base_stat
            case "speed":           stats.spe = s.base_stat
            default: break
            }
        }
        let types = dto.types
            .sorted { $0.slot < $1.slot }
            .compactMap { PokemonType(rawValue: $0.type.name) }
        guard !types.isEmpty else { throw URLError(.cannotParseResponse) }
        let profile = PokemonBattleProfile(speciesID: speciesID, stats: stats, types: types)
        battleProfileCache[speciesID] = profile
        return profile
    }

    // MARK: 무브셋 (네트워크 대전)

    private var moveSetCache: [String: [MoveSpec]] = [:]   // "speciesID-level" → 4기술

    /// 현재 레벨까지 레벨업으로 배우는 기술 중 4개 선택(위력·타입 다양성 우선, 변화기 최대 한 칸).
    /// 후보가 모자라면 레벨 제한을 풀고, 그래도 없거나 fetch 실패면 합성 무브셋 폴백 —
    /// 대전 성립이 기술 데이터 fetch 성공에 묶이면 안 된다.
    func moveSet(speciesID: Int, level: Int, types: [PokemonType]) async -> [MoveSpec] {
        let cacheKey = "\(speciesID)-\(level)"
        if let c = moveSetCache[cacheKey] { return c }
        do {
            let dto: PokemonMovesDTO = try await get(base.appendingPathComponent("pokemon/\(speciesID)"))
            let candidates = Self.moveCandidates(dto, level: level)
            var picked: [MoveSpec] = []
            for name in candidates {
                if picked.count >= 8 { break }   // 상세 fetch 상한(PokéAPI 배려)
                guard let spec = try? await moveDetail(named: name) else { continue }
                // 변화기도 들이되 후보는 **두 개까지**다. 상한 8건을 변화기가 채우면 `pickFour` 에
                // 넘길 공격기가 남지 않는다(상한은 올리지 않는다 — 계획 §5 Phase 3).
                guard spec.power > 0 || picked.filter({ $0.power <= 0 }).count < 2 else { continue }
                picked.append(spec)
            }
            let four = Self.pickFour(from: picked, types: types)
            // 공격기가 한 개도 없으면 데미지를 낼 방법이 없다 → 합성 무브셋으로 떨어뜨린다.
            guard four.contains(where: { $0.power > 0 }) else { throw URLError(.cannotParseResponse) }
            moveSetCache[cacheKey] = four
            return four
        } catch {
            AppLog.write("moveSet: fetch failed for \(speciesID) lv\(level): \(error)")
            return []
        }
    }

    /// 본가 레벨업 습득표에서 현재 레벨까지 배울 수 있는 최근 기술 4개. 변화기도 포함한다.
    func canonicalLevelUpMoves(speciesID: Int, level: Int) async -> [MoveSpec] {
        guard let dto: PokemonMovesDTO = try? await get(base.appendingPathComponent("pokemon/\(speciesID)")) else { return [] }
        let names = Self.levelUpMoveNames(dto, through: level)
        var moves: [MoveSpec] = []
        for name in names {
            guard let move = try? await moveDetail(named: name) else { continue }
            moves.append(move)
            if moves.count == 4 { break }
        }
        return moves
    }

    static func levelUpMoveNames(_ dto: PokemonMovesDTO, through level: Int) -> [String] {
        var learned: [String: Int] = [:]
        for entry in dto.moves {
            let levels = entry.version_group_details
                .filter { $0.move_learn_method.name == "level-up" && $0.level_learned_at <= max(1, level) }
                .map(\.level_learned_at)
            guard let learnedAt = levels.max() else { continue }
            learned[entry.move.name] = max(learned[entry.move.name] ?? 0, learnedAt)
        }
        return learned.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }.map(\.key)
    }

    /// 정확히 이 레벨에 배우는 공격 기술. 사용자 기술 습득 선택창에서 사용한다.
    func movesLearned(speciesID: Int, at level: Int) async -> [MoveSpec] {
        guard let dto: PokemonMovesDTO = try? await get(base.appendingPathComponent("pokemon/\(speciesID)")) else { return [] }
        let names = dto.moves.compactMap { entry -> String? in
            let learnsHere = entry.version_group_details.contains {
                $0.move_learn_method.name == "level-up" && $0.level_learned_at == level
            }
            return learnsHere ? entry.move.name : nil
        }
        var result: [MoveSpec] = []
        for name in Array(Set(names)).sorted() {
            if let move = try? await moveDetail(named: name) { result.append(move) }
        }
        return result
    }

    /// 레벨업 습득 기술을 (습득레벨 내림차순, 현 레벨 이하 우선) 이름 목록으로.
    static func moveCandidates(_ dto: PokemonMovesDTO, level: Int) -> [String] {
        struct Learn { let name: String; let level: Int }
        var best: [String: Int] = [:]   // 이름 → 최소 습득레벨(버전그룹 중)
        for m in dto.moves {
            let levels = m.version_group_details
                .filter { $0.move_learn_method.name == "level-up" }
                .map(\.level_learned_at)
            guard let l = levels.min() else { continue }
            best[m.move.name] = min(best[m.move.name] ?? Int.max, l)
        }
        let learns = best.map { Learn(name: $0.key, level: $0.value) }
        let within = learns.filter { $0.level <= max(1, level) }
        // 현 레벨 이하가 4개 못 되면 전체로 완화 — 저레벨도 대전은 돼야 한다.
        let pool = within.count >= 4 ? within : learns
        return pool.sorted { $0.level == $1.level ? $0.name < $1.name : $0.level > $1.level }.map(\.name)
    }

    /// 기술 4개 — 공격기는 STAB·고위력 우선하되 타입 중복은 뒤로(견제폭), **변화기는 최대 한 칸**.
    ///
    /// 칸을 나누는 게 핵심이다. 위력 내림차순 한 줄에 변화기를 그냥 섞으면 위력 0 이라 늘 꼴찌라
    /// **절대 안 뽑힌다** — 이 함수가 `guard spec.power > 0` 을 대신하는 자리다.
    static func pickFour(from specs: [MoveSpec], types: [PokemonType]) -> [MoveSpec] {
        let attacks = specs.filter { $0.power > 0 }
        let statusPick = pickStatusMove(from: specs.filter { $0.power <= 0 })
        // 남은 칸을 공격기로 되채우는 루프는 필요 없다 — `pickAttacks` 의 두 번째 루프가 이미
        // 상한까지 전 공격기를 채우므로, 여기 도달하면 out 은 4개거나 attacks 를 전부 담고 있다.
        var out = pickAttacks(from: attacks, types: types, limit: statusPick == nil ? 4 : 3)
        if let statusPick { out.append(statusPick) }
        return out
    }

    /// 변화기 한 칸의 주인 — **구현된 효과(랭크·상태)가 있는 것만**. 효과 미구현 변화기(ailment
    /// 14종)는 PP 만 태우므로 `nil` 을 돌려 그 칸을 공격기에게 넘긴다.
    /// 순서는 후보 정렬(습득 레벨 내림차순)을 그대로 따라가므로 결정적이다.
    private static func pickStatusMove(from specs: [MoveSpec]) -> MoveSpec? {
        specs.first { $0.inflictedStatus != nil || !($0.statChanges ?? []).isEmpty }
    }

    private static func pickAttacks(from attacks: [MoveSpec], types: [PokemonType],
                                    limit: Int) -> [MoveSpec] {
        let ranked = attacks.sorted {
            let stab0 = types.contains($0.type), stab1 = types.contains($1.type)
            if stab0 != stab1 { return stab0 }
            return $0.power > $1.power
        }
        var out: [MoveSpec] = []
        for s in ranked where !out.contains(where: { $0.type == s.type }) {
            out.append(s)
            if out.count == limit { return out }
        }
        for s in ranked where !out.contains(where: { $0.id == s.id }) {
            out.append(s)
            if out.count == limit { break }
        }
        return out
    }

    private var moveDetailCache: [String: MoveSpec] = [:]
    func moveDetail(id: Int) async -> MoveSpec? {
        guard id > 0 else { return nil }
        return try? await moveDetail(named: String(id))
    }

    /// 이름으로 기술 하나. 체육관 카탈로그가 관장 기술을 이름으로 지정하므로 외부에서도 쓴다.
    func moveDetail(named name: String) async throws -> MoveSpec {
        if let c = moveDetailCache[name] { return c }
        let dto: MoveDTO = try await get(base.appendingPathComponent("move/\(name)"))
        guard let spec = MoveSpec.from(dto, fallbackName: name, languages: langCodes) else {
            throw URLError(.cannotParseResponse)
        }
        moveDetailCache[name] = spec
        return spec
    }

    /// 언어별 기술 설명 — flavor_text 는 버전그룹 오름차순이라 **뒤로 갈수록 최신**이다.
    /// 그래서 순서대로 덮어쓰면 최신이 남는데, 소드·실드에서 *삭제된* 기술은 그 최신 항목이 설명이 아니라
    /// "사용할 수 없는 기술입니다" 안내문이다(실측: move/return). 안내문 항목은 건너뛰므로 결과적으로
    /// **가장 최신의 진짜 설명**이 남는다. (순회는 오래된 것부터다 — `break` 를 넣으면 정반대가 된다.)
    static func flavorTexts(_ entries: [(language: String, text: String)],
                            languages: [String]) -> [String: String] {
        var out: [String: String] = [:]
        for entry in entries where languages.contains(entry.language) {
            guard !isUnusableMoveNotice(entry.text) else { continue }
            out[entry.language] = entry.text
                .replacingOccurrences(of: "\n", with: " ")
                .replacingOccurrences(of: "\u{000C}", with: " ")
        }
        return out
    }

    /// 삭제된 기술의 안내문인가. **접두사로만** 판정한다 — "사용할 수 없"을 부분일치로 보면
    /// 금지어("4턴 동안 사용할 수 없게 만든다") 같은 진짜 설명까지 지운다.
    static func isUnusableMoveNotice(_ text: String) -> Bool {
        let normalized = text
            .replacingOccurrences(of: "\u{2019}", with: "'")     // PokéAPI 는 굽은 따옴표를 쓴다
            .replacingOccurrences(of: "\u{3000}", with: " ")     // 일본어 전각 공백
            // 공백류는 개수까지 접는다 — 1:1 치환만 하면 "この技は　　使えません"처럼 겹친 경우를 놓친다.
            .replacingOccurrences(of: "[\\s\u{000C}]+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return unusableNoticePrefixes.contains { normalized.hasPrefix($0) }
    }

    private static let unusableNoticePrefixes = [
        "사용할 수 없는 기술입니다",
        "This move can't be used",
        "この技は 使えません",
        "このわざは つかえません",
    ]

    private func get<T: Decodable>(_ url: URL) async throws -> T {
        var req = URLRequest(url: url)
        req.timeoutInterval = 15
        let (data, _) = try await URLSession.shared.data(for: req)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func node(from link: ChainLink) -> EvoNode {
        EvoNode(speciesID: Self.id(from: link.species.url ?? ""),
                children: link.evolves_to.map(node(from:)),
                // 친밀도 진화는 min_level 이 없다(trigger=level-up, min_happiness 만 존재) → 그대로 두면
                // 레벨 게이트를 못 타고 아이템/트리거 게이트에도 막혀 영영 진화하지 않는다.
                // 앱에 친밀도 축이 없으므로 요구 친밀도를 레벨로 환산해 같은 레벨 게이트에 태운다.
                evolutionLevel: link.evolution_details.compactMap(\.min_level).first
                    ?? link.evolution_details.compactMap(\.min_happiness).first
                        .map(PokemonBalance.friendshipLevel(minHappiness:)),
                evolutionTrigger: link.evolution_details.first?.trigger.name,
                evolutionItem: link.evolution_details.first?.item?.name)
    }
    private func allIDs(_ n: EvoNode) -> [Int] { [n.speciesID] + n.children.flatMap(allIDs) }

    static func id(from speciesURL: String) -> Int {
        // ".../pokemon-species/{id}/"
        let parts = speciesURL.split(separator: "/").filter { !$0.isEmpty }
        return Int(parts.last ?? "0") ?? 0
    }

    /// PokéAPI evolution_chain URL 검증(SSRF 가드) — 서버 제어 문자열이므로 https + pokeapi.co 로 고정해
    /// 응답 변조 시 임의 호스트 fetch 를 막는다. 부적합하면 nil(호출부가 throw → 앱은 알 상태 유지).
    static func validatedChainURL(_ raw: String) -> URL? {
        guard let url = URL(string: raw), url.scheme == "https", url.host == "pokeapi.co" else { return nil }
        return url
    }
}

// MARK: - DTO (PokéAPI 응답 부분 디코드)

struct SpeciesDTO: Decodable, Sendable {
    let capture_rate: Int
    let is_legendary: Bool
    let is_mythical: Bool
    let names: [NameDTO]
    let evolution_chain: URLRef
    let evolves_from_species: NamedRef?   // nil = 진화라인 시작점(base)
}
struct NameDTO: Decodable, Sendable { let name: String; let language: NamedRef }
struct NamedRef: Decodable, Sendable { let name: String; let url: String? }
struct URLRef: Decodable, Sendable { let url: String }
struct ChainDTO: Decodable, Sendable { let chain: ChainLink }

/// 배틀에 필요한 종 데이터(종족값·타입) — `/pokemon/{id}` 부분 디코드 결과.
struct PokemonBattleProfile: Sendable {
    let speciesID: Int
    let stats: BattleStats
    let types: [PokemonType]
}
struct PokemonDTO: Decodable, Sendable {
    struct StatEntry: Decodable, Sendable { let base_stat: Int; let stat: NamedRef }
    struct TypeEntry: Decodable, Sendable { let slot: Int; let type: NamedRef }
    let stats: [StatEntry]
    let types: [TypeEntry]
}
/// `/pokemon/{id}` 의 moves 부분만 — 배틀 프로필과 별도 디코드(무브셋은 대전 시작 때만 필요).
struct PokemonMovesDTO: Decodable, Sendable {
    struct MoveEntry: Decodable, Sendable {
        struct Detail: Decodable, Sendable {
            let level_learned_at: Int
            let move_learn_method: NamedRef
        }
        let move: NamedRef
        let version_group_details: [Detail]
    }
    let moves: [MoveEntry]
}
/// `/move/{name}` 부분 디코드.
struct MoveDTO: Decodable, Sendable {
    struct FlavorText: Decodable, Sendable {
        let flavor_text: String
        let language: NamedRef
    }
    /// `/move` 응답의 `meta` 블록 — 실제로 쓰는 필드만 꺼낸다. 통째로 담으면 `MoveSpec` 이
    /// 안 쓰는 값까지 세이브·와이어로 나른다(계획 §7 의 "MoveSpec 필드 증가" 리스크).
    /// 상태이상(`ailment`)·랭크변화(`stat_chance`)는 Phase 2·3 에서 이 자리에 붙는다.
    struct Meta: Decodable, Sendable {
        let crit_rate: Int?
        /// `/move-ailment` 이름. 상태를 걸지 않는 기술은 `none` 이 온다(키가 빠지는 게 아니다).
        let ailment: NamedRef?
        let ailment_chance: Int?
        /// 랭크 변화가 걸릴 확률. 변화기(본체가 랭크 변화)는 0 이 온다.
        let stat_chance: Int?
    }
    /// 랭크 변화 한 항목. `stat.name` 은 `special-attack` 처럼 PokéAPI 표기다.
    struct StatChangeDTO: Decodable, Sendable {
        let change: Int
        let stat: NamedRef
    }
    let id: Int
    let power: Int?
    let accuracy: Int?
    let pp: Int?
    let type: NamedRef
    let damage_class: NamedRef
    let names: [NameDTO]
    let flavor_text_entries: [FlavorText]
    /// 턴 순서에서 스피드보다 먼저 보는 값. 응답에 늘 들어 있지만, 옛 캐시 응답을 대비해 옵셔널로 둔다.
    let priority: Int?
    let meta: Meta?
    /// 응답에 늘 있고 변화가 없으면 **빈 배열**이다. 그래서 `nil`(키 없음)은 "옛 캐시 응답" 이고,
    /// 그 구분이 `MoveSpec.statChanges` 로 그대로 넘어간다.
    let stat_changes: [StatChangeDTO]?
}

extension MoveSpec {
    /// `/move` 응답 하나를 대전용 스펙으로. 모르는 타입·분류면 `nil`(호출부가 그 기술을 건너뛴다),
    /// 이름이 하나도 없으면 요청 이름을 영어 자리에 넣어 화면에 "?" 가 남지 않게 한다.
    /// 매핑을 여기 한 곳에 둬서 필드가 늘어도(priority → crit_rate → ailment) 네트워크 없이 테스트된다.
    static func from(_ dto: MoveDTO, fallbackName: String, languages: [String]) -> MoveSpec? {
        guard let type = PokemonType(rawValue: dto.type.name),
              let damageClass = MoveDamageClass(rawValue: dto.damage_class.name) else { return nil }
        var names: [String: String] = [:]
        for entry in dto.names where languages.contains(entry.language.name) {
            names[entry.language.name] = entry.name
        }
        if names["en"] == nil { names["en"] = fallbackName }
        let descriptions = PokeAPIClient.flavorTexts(dto.flavor_text_entries.map {
            (language: $0.language.name, text: $0.flavor_text)
        }, languages: languages)
        let ailment = dto.meta?.ailment?.name
        // 구현하지 않은 상태(trap·nightmare·yawn·leech-seed 등 14종)는 조용히 삼키지 않고 한 번 남긴다.
        // 스펙을 만들 때 한 번만 찍히므로(스펙은 캐시된다) 턴마다 로그가 불어나지 않는다.
        if let ailment, ailment != "none", Status(ailment: ailment) == nil, dto.id != MoveSpec.toxicMoveID {
            AppLog.write("move \(dto.id) (\(fallbackName)): ailment '\(ailment)' not implemented — ignored")
        }
        // 모르는 스탯 이름(랭크가 없는 `hp` 등)은 건너뛰되 조용히 삼키지 않는다 — ailment 와 같은 규칙.
        let statChanges = dto.stat_changes?.compactMap { change -> StatChange? in
            guard let stat = BattleStat(apiName: change.stat.name) else {
                AppLog.write("move \(dto.id) (\(fallbackName)): stat '\(change.stat.name)' has no stage — ignored")
                return nil
            }
            return StatChange(stat: stat, change: change.change)
        }
        return MoveSpec(id: dto.id, names: names, type: type,
                        power: dto.power ?? 0, damageClass: damageClass,
                        accuracy: dto.accuracy, pp: dto.pp ?? 10,
                        descriptions: descriptions, priority: dto.priority,
                        critRate: dto.meta?.crit_rate,
                        ailment: ailment, ailmentChance: dto.meta?.ailment_chance,
                        statChanges: statChanges, statChance: dto.meta?.stat_chance)
    }
}
struct ChainLink: Decodable, Sendable {
    struct EvolutionDetail: Decodable, Sendable {
        let min_level: Int?
        /// 친밀도 진화 조건(160·220). 앱엔 친밀도 축이 없어 레벨로 환산한다 — PokemonBalance.friendshipLevel.
        let min_happiness: Int?
        let trigger: NamedRef
        let item: NamedRef?
    }
    let species: NamedRef
    let evolves_to: [ChainLink]
    let evolution_details: [EvolutionDetail]
}
