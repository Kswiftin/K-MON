import Foundation

/// 부화 후보 — 진화라인 시작점(base) 종과 공식 희귀도.
struct BaseSpecies: Sendable, Codable {
    let id: Int
    let captureRate: Int    // 3(뮤츠급)~255(캐터피급), 공식 희귀도 신호

    /// 부화 후보에서 **스프라이트 없는 종을 걷어낸다.**
    ///
    /// 구멍 14종은 전부 기본형(진화 전)이라 `evolves_from IS NULL` 조회에 그대로 딸려 온다.
    /// 거르지 않으면 가중 추첨이 그걸 뽑고, `EvoLine.init` 은 가지치기 결과가 nil 일 때 **같은
    /// baseID 로 노드를 다시 만들어** 스프라이트 없는 단일형태 개체가 그대로 부화한다.
    static func hatchable(_ entries: [BaseSpecies]) -> [BaseSpecies] {
        entries.filter { PokemonAssets.hasAnimatedSprite(speciesID: $0.id) }
    }
}

/// 포켓몬 라인 데이터 제공(주입 가능 — 테스트는 스텁 사용).
protocol PokeProviding: Sendable {
    func line(baseSpeciesID: Int) async throws -> EvoLine
    /// 1~9세대 base 전체 인덱스 (GraphQL 1쿼리, 디스크 캐시).
    func baseSpeciesIndex() async throws -> [BaseSpecies]
    /// 단일 종이 base(진화 시작점)면 BaseSpecies, 아니면 nil.
    /// GraphQL 인덱스 엔드포인트 장애 시 REST(pokemon-species)로 부화 후보를 뽑는 폴백용.
    func baseSpecies(id: Int) async throws -> BaseSpecies?
    /// 종의 타입·종족값. **타입이 도감에 영구 저장되므로**(`DexEntry.types`) 이 조회는 주입 가능해야
    /// 한다 — `PokeAPIClient.shared` 를 직접 부르면 그 경로를 밟는 테스트를 쓸 수 없다.
    func battleProfile(speciesID: Int) async throws -> PokemonBattleProfile
    /// 세이브에 든 기술 스펙의 빠진 축을 채우는 조회. `battleProfile` 과 같은 이유로 주입 가능해야
    /// 한다 — 대전 스냅샷이 이 보강을 지나는지를 네트워크 없이 테스트한다.
    func moveDetail(id: Int) async -> MoveSpec?
    /// 레벨에 맞는 자동 무브셋. `battleProfile` 과 같은 이유로 주입 가능해야 한다 — 웨이브 런의
    /// 야생·스타터가 이 조회를 지나므로, 여기가 `shared` 직접 호출이면 **판을 여는 경로 전체**를
    /// 네트워크 없이 테스트할 수 없다.
    func moveSet(speciesID: Int, level: Int, types: [PokemonType]) async -> [MoveSpec]
    /// 해당 종이 본가 기술머신(machine 방식)으로 기술을 배울 수 있는지 확인한다.
    func canLearnMachine(speciesID: Int, moveID: Int) async -> Bool
    /// 획득 가능 범위 전 종의 타입 (GraphQL 1쿼리, 디스크 캐시). 도감 타입 필터가 읽는다 —
    /// **아직 안 잡은 종에도 걸려야** 해서 `battleProfile` 종별 조회로는 대체할 수 없다(1천 회 넘는다).
    func speciesTypeIndex() async throws -> [Int: [PokemonType]]
}

extension PokeProviding {
    /// 기본값은 실 클라이언트 — 타입을 쓰지 않는 스텁은 그대로 두면 된다.
    func battleProfile(speciesID: Int) async throws -> PokemonBattleProfile {
        try await PokeAPIClient.shared.battleProfile(speciesID: speciesID)
    }

    func moveDetail(id: Int) async -> MoveSpec? {
        await PokeAPIClient.shared.moveDetail(id: id)
    }

    func moveSet(speciesID: Int, level: Int, types: [PokemonType]) async -> [MoveSpec] {
        await PokeAPIClient.shared.moveSet(speciesID: speciesID, level: level, types: types)
    }

    func canLearnMachine(speciesID: Int, moveID: Int) async -> Bool {
        await PokeAPIClient.shared.canLearnMachine(speciesID: speciesID, moveID: moveID)
    }

    func speciesTypeIndex() async throws -> [Int: [PokemonType]] {
        try await PokeAPIClient.shared.speciesTypeIndex()
    }
}

/// PokéAPI 클라이언트 — 종/진화체인을 런타임 fetch + 파싱. 포켓몬 데이터는 레포에 번들하지 않는다.
/// species 응답은 actor 캐시(다국어 이름 재사용).
actor PokeAPIClient: PokeProviding {
    static let shared = PokeAPIClient()
    private let base = URL(string: "https://pokeapi.co/api/v2")!
    private let langCodes = ["ko", "en", "ja-Hrkt", "ja"]
    private var speciesCache: [Int: SpeciesDTO] = [:]
    private var chatSpeciesIdentityCache: [String: PokemonSpeciesIdentity] = [:]
    private var lineCache: [Int: EvoLine] = [:]   // 프리패칭 → 부화 순간 네트워크 0

    func line(baseSpeciesID: Int) async throws -> EvoLine {
        if let cached = lineCache[baseSpeciesID] { return cached }
        let baseSpecies = try await species(baseSpeciesID)
        // PokéAPI 응답의 URL — 비정상/빈 값이면 force-unwrap 대신 throw(앱은 알 상태 유지).
        guard let chainURL = Self.validatedChainURL(baseSpecies.evolution_chain.url) else {
            throw URLError(.badURL)
        }
        let chainDTO: ChainDTO = try await get(chainURL)
        let tree = Self.evoNode(from: chainDTO.chain)
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
        var evolutionMoveNames: [Int: [String: String]] = [:]
        for id in Set(Self.allKnownMoveIDs(tree)) {
            if let move = await moveDetail(id: id) { evolutionMoveNames[id] = move.names }
        }
        let line = EvoLine(baseID: baseSpeciesID, tree: tree, rarity: rarity, names: names,
                           genderRate: baseSpecies.gender_rate ?? -1,
                           evolutionMoveNames: evolutionMoveNames)
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
    /// `maxSpeciesID` 는 이 스냅샷을 만들 때의 `PokemonAssets.speciesRange.upperBound` — 종 범위가
    /// 넓어져도(#212) 30일 TTL 은 안 지나므로, 값이 없거나 지금 범위와 다르면 시간과 무관하게 다시
    /// 받는다. 기존 캐시 파일엔 이 키가 없어 디코딩이 실패하고, `try?` 가 그걸 "캐시 없음"으로
    /// 흡수해 자연스럽게 한 번 재조회로 넘어간다.
    struct BaseIndexSnapshot: Codable { let fetchedAt: Date; let maxSpeciesID: Int; let entries: [BaseSpecies] }

    /// TTL·종 범위 판정을 뽑아 둔 순수 함수 — 파일 I/O·네트워크 없이 이 조건만 테스트한다.
    /// 범위 검사를 빼먹었던 게 바로 이 버그였다: 종 범위가 넓어져도 캐시가 30일 동안 옛 범위를
    /// 그대로 돌려줘, 새로 추가된 종이 부화 후보에 아예 안 들어갔다.
    static func isBaseIndexSnapshotUsable(_ snapshot: BaseIndexSnapshot,
                                          currentMaxSpeciesID: Int,
                                          now: Date,
                                          ttl: TimeInterval = 30 * 86400) -> Bool {
        snapshot.maxSpeciesID == currentMaxSpeciesID
            && now.timeIntervalSince(snapshot.fetchedAt) < ttl
            && !snapshot.entries.isEmpty
    }
    private struct GraphQLBaseResponse: Decodable {
        struct DataBox: Decodable { let pokemonspecies: [Row] }
        struct Row: Decodable { let id: Int; let capture_rate: Int }
        let data: DataBox
    }

    private var speciesTypeCache: [Int: [PokemonType]]?
    private static let speciesTypeFile: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PokeTokenBar")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("species-types.json")
    }()
    private struct SpeciesTypeSnapshot: Codable { let fetchedAt: Date; let entries: [Int: [PokemonType]] }
    private struct GraphQLTypeResponse: Decodable {
        struct DataBox: Decodable { let pokemon: [Row] }
        struct Row: Decodable { let id: Int; let pokemontypes: [Slot] }
        struct Slot: Decodable { struct Named: Decodable { let name: String }; let type: Named }
        let data: DataBox
    }

    /// 1~9세대 base(진화라인 시작점) 전체 — PokéAPI GraphQL 1쿼리.
    /// 우선순위: 메모리 캐시 → 디스크 캐시(30일 TTL, 종 범위 일치) → GraphQL fetch(성공 시 디스크
    /// 갱신) → TTL 지났거나 범위가 다른 디스크라도 있으면 사용(오프라인 폴백). 전부 실패 시
    /// throw(알 유지, 다음 틱 재시도).
    func baseSpeciesIndex() async throws -> [BaseSpecies] {
        if let c = baseIndexCache { return c }
        let disk = (try? Data(contentsOf: Self.baseIndexFile))
            .flatMap { try? JSONDecoder().decode(BaseIndexSnapshot.self, from: $0) }
        let currentMaxSpeciesID = PokemonAssets.speciesRange.upperBound
        // 디스크 캐시는 이 필터가 없던 빌드가 남겼을 수 있다 — 읽을 때도 한 번 더 거른다.
        // 종 범위가 넓어진 뒤의 캐시만 쓴다 — 옛 범위로 받은 캐시는 TTL 이 안 지났어도 새로 받는다.
        if let disk, Self.isBaseIndexSnapshotUsable(disk, currentMaxSpeciesID: currentMaxSpeciesID, now: Date()) {
            let usable = BaseSpecies.hatchable(disk.entries)
            baseIndexCache = usable
            return usable
        }
        do {
            let entries = try await fetchBaseIndex()
            baseIndexCache = entries
            if let data = try? JSONEncoder().encode(
                BaseIndexSnapshot(fetchedAt: Date(), maxSpeciesID: currentMaxSpeciesID, entries: entries)) {
                try? data.write(to: Self.baseIndexFile, options: .atomic)
            }
            return entries
        } catch {
            // 오프라인 — 범위가 지금과 다른(예: 종 확장 전) 오래된 인덱스라도 없는 것보단 낫다.
            if let disk, !disk.entries.isEmpty {
                let usable = BaseSpecies.hatchable(disk.entries)
                baseIndexCache = usable
                return usable
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
        let maxID = PokemonAssets.speciesRange.upperBound
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
        if let data = try? JSONEncoder().encode(
            BaseIndexSnapshot(fetchedAt: Date(), maxSpeciesID: maxID, entries: bases)) {
            try? data.write(to: Self.baseIndexFile, options: .atomic)
        }
        AppLog.write("base index: REST build done — \(bases.count) bases persisted (offline-capable now)")
    }

    /// 공식 GraphQL 엔드포인트 — base 인덱스와 타입 인덱스가 함께 쓴다.
    private static let graphQLEndpoint = "https://graphql.pokeapi.co/v1beta2"

    private func fetchBaseIndex() async throws -> [BaseSpecies] {
        // evolves_from IS NULL(=base) + id ≤ 종 번호 상한(`PokemonAssets.speciesRange`)
        guard let url = URL(string: Self.graphQLEndpoint) else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 15
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // 메타몽(#132)은 위장 리빌 전용 → 일반 부화 풀에서 제외(_neq).
        let maxID = PokemonAssets.speciesRange.upperBound
        // 스프라이트 없는 종은 서버에서부터 빼 온다 — 받아서 거르면 디스크 캐시에 남는다.
        let excluded = ([PokemonOdds.dittoSpeciesID] + PokemonAssets.spriteGaps.sorted())
            .map(String.init).joined(separator: ",")
        let query = "{ pokemonspecies(where: {evolves_from_species_id: {_is_null: true}, id: {_lte: \(maxID), _nin: [\(excluded)]}}, order_by: {id: asc}) { id capture_rate } }"
        req.httpBody = try JSONSerialization.data(withJSONObject: ["query": query])
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        let decoded = try JSONDecoder().decode(GraphQLBaseResponse.self, from: data)
        let entries = decoded.data.pokemonspecies.map { BaseSpecies(id: $0.id, captureRate: $0.capture_rate) }
        guard !entries.isEmpty else { throw URLError(.cannotParseResponse) }
        return entries
    }

    // MARK: 종별 타입 인덱스

    /// 획득 가능 범위 전 종의 타입 — GraphQL 1쿼리, 30일 디스크 캐시.
    ///
    /// **base 인덱스와 달리 REST 폴백을 두지 않는다.** 부화는 인덱스가 없으면 게임이 멈추지만,
    /// 이건 없어도 도감 타입 필터 하나가 잠길 뿐이다 — 종 수만큼 REST 조회를 걸 값어치가 없다.
    func speciesTypeIndex() async throws -> [Int: [PokemonType]] {
        if let cached = speciesTypeCache { return cached }
        let disk = (try? Data(contentsOf: Self.speciesTypeFile))
            .flatMap { try? JSONDecoder().decode(SpeciesTypeSnapshot.self, from: $0) }
        if let disk, Date().timeIntervalSince(disk.fetchedAt) < 30 * 86400, !disk.entries.isEmpty {
            speciesTypeCache = disk.entries
            return disk.entries
        }
        do {
            let entries = try await fetchSpeciesTypeIndex()
            speciesTypeCache = entries
            if let data = try? JSONEncoder().encode(SpeciesTypeSnapshot(fetchedAt: Date(), entries: entries)) {
                try? data.write(to: Self.speciesTypeFile, options: .atomic)
            }
            return entries
        } catch {
            if let disk, !disk.entries.isEmpty {   // 오프라인 — 오래된 인덱스라도 사용
                speciesTypeCache = disk.entries
                return disk.entries
            }
            throw error
        }
    }

    private func fetchSpeciesTypeIndex() async throws -> [Int: [PokemonType]] {
        guard let url = URL(string: Self.graphQLEndpoint) else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 15
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // slot 순으로 정렬 — 1번이 주 타입이다. 안 걸면 이중타입 표기 순서가 응답마다 흔들린다.
        let maxID = PokemonAssets.speciesRange.upperBound
        let query = "{ pokemon(where: {id: {_lte: \(maxID)}}, order_by: {id: asc})"
            + " { id pokemontypes(order_by: {slot: asc}) { type { name } } } }"
        req.httpBody = try JSONSerialization.data(withJSONObject: ["query": query])
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        let decoded = try JSONDecoder().decode(GraphQLTypeResponse.self, from: data)
        var index: [Int: [PokemonType]] = [:]
        for row in decoded.data.pokemon {
            // 모르는 타입 이름은 버린다 — 새 타입이 생겨도 나머지 종이 함께 무효가 되지 않게.
            let types = row.pokemontypes.compactMap { PokemonType(rawValue: $0.type.name) }
            if !types.isEmpty { index[row.id] = types }
        }
        guard !index.isEmpty else { throw URLError(.cannotParseResponse) }
        return index
    }

    private func species(_ id: Int) async throws -> SpeciesDTO {
        if let c = speciesCache[id] { return c }
        let dto: SpeciesDTO = try await get(base.appendingPathComponent("pokemon-species/\(id)"))
        speciesCache[id] = dto
        return dto
    }

    /// OX 퀴즈용 사실 데이터. 문제 문장은 이 응답에서만 조립하며 레포에 정답 목록을 두지 않는다.
    func pokemonQuizFacts(count: Int = 8) async throws -> [PokemonQuizFact] {
        let maximum = PokemonAssets.speciesRange.upperBound
        let ids = Array(1...maximum).shuffled().prefix(max(count * 2, 12))
        let facts = await withTaskGroup(of: PokemonQuizFact?.self) { group in
            for id in ids { group.addTask { try? await self.pokemonQuizFact(speciesID: id) } }
            var values: [PokemonQuizFact] = []
            for await fact in group where fact != nil { values.append(fact!) }
            return values
        }
        guard facts.count >= 4 else { throw URLError(.cannotLoadFromNetwork) }
        return Array(facts.shuffled().prefix(count))
    }

    private func pokemonQuizFact(speciesID: Int) async throws -> PokemonQuizFact {
        let detail = try await species(speciesID)
        let profile = try await battleProfile(speciesID: speciesID)
        let names = localizedNames(detail.names)
        guard let abilitySlug = profile.abilitySlug else { throw URLError(.cannotParseResponse) }
        let ability: AbilityDTO = try await get(base.appendingPathComponent("ability/\(abilitySlug)"))
        let abilityNames = localizedNames(ability.names)
        guard !names.isEmpty, !profile.types.isEmpty, !abilityNames.isEmpty else {
            throw URLError(.cannotParseResponse)
        }
        return PokemonQuizFact(speciesID: speciesID, names: names, types: profile.types,
                               abilityNames: abilityNames)
    }

    private func localizedNames(_ entries: [NameDTO]) -> [String: String] {
        Dictionary(uniqueKeysWithValues: entries.filter { langCodes.contains($0.language.name) }
            .map { ($0.language.name, $0.name) })
    }

    /// 대화에 필요한 종 정보만 fetch 한다. 각 응답은 독립적으로 실패할 수 있고 결과는 부분 정체성으로 남긴다.
    /// 페르소나 필드는 `SpeciesDTO` 가 아니라 `ChatSpeciesDTO` 로 따로 받는다 — 그래야 부화·진화라인
    /// 로드가 종 응답에서 가장 큰 배열(`flavor_text_entries`)을 매번 디코딩하고 버리지 않는다.
    func chatSpeciesIdentity(speciesID: Int, language: AppLanguage) async -> PokemonSpeciesIdentity {
        let cacheKey = "\(speciesID)-\(language.rawValue)"
        if let cached = chatSpeciesIdentityCache[cacheKey] { return cached }

        var genera: [String: String] = [:]
        var habitatSlug: String?
        var flavorTexts: [String: String] = [:]
        let speciesSucceeded: Bool
        if let dto: ChatSpeciesDTO = try? await get(base.appendingPathComponent("pokemon-species/\(speciesID)")) {
            speciesSucceeded = true
            for entry in dto.genera ?? [] where langCodes.contains(entry.language.name) {
                genera[entry.language.name] = entry.genus
            }
            habitatSlug = dto.habitat?.name
            flavorTexts = Self.flavorTexts((dto.flavor_text_entries ?? []).map {
                (language: $0.language.name, text: $0.flavor_text)
            }, languages: langCodes)
        } else { speciesSucceeded = false }

        var abilityNames: [String: String] = [:]
        var abilityTexts: [String: String] = [:]
        var pokemonSucceeded = false
        do {
            let dto: PokemonAbilitiesDTO = try await get(base.appendingPathComponent("pokemon/\(speciesID)"))
            pokemonSucceeded = true
            if let slug = PokemonAbilitiesDTO.primarySlug(of: dto.abilities) {
                let ability: AbilityDTO = try await get(base.appendingPathComponent("ability/\(slug)"))
                for entry in ability.names where langCodes.contains(entry.language.name) {
                    abilityNames[entry.language.name] = entry.name
                }
                abilityTexts = Self.flavorTexts(ability.flavor_text_entries.map {
                    (language: $0.language.name, text: $0.flavor_text)
                }, languages: langCodes)
            }
        } catch {
            AppLog.write("chat species identity: ability fetch failed for \(speciesID): \(error)")
        }

        let identity = PokemonSpeciesIdentity(
            genera: genera, habitatSlug: habitatSlug, flavorTexts: flavorTexts,
            abilityNames: abilityNames, abilityTexts: abilityTexts, language: language
        )
        // Do not turn a total transient outage into a permanent empty identity. A successful
        // species response is useful even if optional ability enrichment failed.
        if speciesSucceeded || pokemonSucceeded { chatSpeciesIdentityCache[cacheKey] = identity }
        return identity
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

    /// `/pokemon/{id}` 에서 배틀에 필요한 종족값·타입만 파싱. 기본 폼은 pokemon id 가 species id 와 같다
    /// (지역폼·메가는 10000번대라 이 범위에 없다).
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
        // 대표 특성 선택 규칙은 `PokemonAbilitiesDTO` 한 곳에만 둔다(숨은 특성 제외, slot 최소).
        let abilitySlug = PokemonAbilitiesDTO.primarySlug(of: dto.abilities ?? [])
        // 구현하지 않은 특성은 조용히 삼키지 않고 한 번 남긴다 — 프로필은 캐시되므로 종당 한 줄이다
        // (ailment 14종과 같은 규칙). 배틀은 바뀌지 않는다: 해석이 `nil` 로 접는다.
        if let abilitySlug, BattleAbility.resolve(abilitySlug) == nil {
            AppLog.write("battle profile \(speciesID): ability '\(abilitySlug)' not implemented — ignored")
        }
        let profile = PokemonBattleProfile(speciesID: speciesID, stats: stats, types: types,
                                           weightHectograms: dto.weight, abilitySlug: abilitySlug)
        battleProfileCache[speciesID] = profile
        return profile
    }

    // MARK: 무브셋 (네트워크 대전)

    private var moveSetCache: [String: [MoveSpec]] = [:]   // "speciesID-level" → 4기술
    private var machineCompatibilityCache: [String: Bool] = [:]

    func canLearnMachine(speciesID: Int, moveID: Int) async -> Bool {
        let key = "gen5-\(speciesID)-\(moveID)"
        if let cached = machineCompatibilityCache[key] { return cached }
        guard let dto: PokemonMovesDTO = try? await get(base.appendingPathComponent("pokemon/\(speciesID)")) else {
            return false
        }
        let result = dto.moves.contains { entry in
            Self.id(from: entry.move.url ?? "") == moveID
                && entry.version_group_details.contains {
                    $0.move_learn_method.name == "machine"
                        && $0.version_group.map {
                            ["black-white", "black-2-white-2"].contains($0.name)
                        } == true
                }
        }
        machineCompatibilityCache[key] = result
        return result
    }

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
                // 세는 기준은 `power > 0` 이 아니라 `dealsDamage` 다. 일렉트릭볼 부류는 위력이
                // 0 으로 오는 공격기라, 위력으로 세면 변화기 두 칸을 대신 잡아먹는다.
                guard VariableDamage.dealsDamage(spec)
                        || picked.filter({ !VariableDamage.dealsDamage($0) }).count < 2 else { continue }
                picked.append(spec)
            }
            let four = Self.pickFour(from: picked, types: types)
            // 공격기가 한 개도 없으면 데미지를 낼 방법이 없다 → 합성 무브셋으로 떨어뜨린다.
            guard four.contains(where: VariableDamage.dealsDamage) else { throw URLError(.cannotParseResponse) }
            moveSetCache[cacheKey] = four
            return four
        } catch {
            AppLog.write("moveSet: fetch failed for \(speciesID) lv\(level): \(error)")
            return []
        }
    }

    /// 본가 레벨업 습득표에서 현재 레벨까지 배울 수 있는 최근 기술 4개. 변화기도 포함한다.
    /// 아직 위력을 못 뽑는 기술(`VariableDamage.unmodeledMoveIDs`)은 뺀다 — 넣어 두면 PP 만
    /// 태우는 칸이 되고, 넷뿐인 자리를 죽은 기술이 차지한다.
    func canonicalLevelUpMoves(speciesID: Int, level: Int) async -> [MoveSpec] {
        await levelUpMoves(speciesID: speciesID, level: level, limit: 4)
    }

    /// 현재 레벨까지 배울 수 있었던 레벨업 기술 **전부** — 하트비늘(다시 배우기) 후보용.
    ///
    /// `canonicalLevelUpMoves` 와 나눠 둔다. 그쪽은 **무브셋을 채우는** 함수라 4개에서 멈추는데
    /// (기술 칸이 넷이다), 다시 배우기는 "지금까지 배울 수 있었던 것 중에 고른다" 라 상한이 없다.
    /// 한 함수를 두 용도로 쓰던 동안 후보 목록이 무브셋 상한을 물려받아 **종당 4개만** 보였다.
    func levelUpMoveHistory(speciesID: Int, level: Int) async -> [MoveSpec] {
        await levelUpMoves(speciesID: speciesID, level: level, limit: nil)
    }

    /// `limit` 이 nil 이면 전부. 개수만 다른 두 용도가 같은 필터·같은 순서를 쓰게 한 곳에 둔다 —
    /// 갈라 두면 무브셋에는 들어가는데 다시 배우기에는 안 뜨는 기술이 생긴다.
    private func levelUpMoves(speciesID: Int, level: Int, limit: Int?) async -> [MoveSpec] {
        guard let dto: PokemonMovesDTO = try? await get(base.appendingPathComponent("pokemon/\(speciesID)")) else { return [] }
        let names = Self.levelUpMoveNames(dto, through: level)
        var moves: [MoveSpec] = []
        for name in names {
            guard let move = try? await moveDetail(named: name), VariableDamage.isUsable(move) else { continue }
            moves.append(move)
            if let limit, moves.count == limit { break }
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
    /// `canonicalLevelUpMoves` 와 같은 이유로 위력을 못 뽑는 기술은 권하지 않는다 —
    /// 여기는 **쓰던 기술을 버리고** 고르는 자리라 죽은 기술을 올리면 손해가 더 크다.
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
            if let move = try? await moveDetail(named: name), VariableDamage.isUsable(move) {
                result.append(move)
            }
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
        let cutoff = max(1, level)
        // 현 레벨까지 배우는 기술은 **최근 것부터**. 그 레벨의 주력이 앞에 와야 한다.
        let recent = learns.filter { $0.level <= cutoff }
            .sorted { $0.level == $1.level ? $0.name < $1.name : $0.level > $1.level }
        guard recent.count < 4 else { return recent.map(\.name) }
        // 4개가 안 되면 아직 못 배운 기술로 칸을 채운다 — 저레벨도 대전은 돼야 한다. 다만
        // **가장 일찍 배우는 것부터** 채운다. 여기서도 내림차순으로 채우면 레벨 2 야생이 그 종의
        // 최종기를 들고 나와, 초반 상대의 세기가 종의 학습표 밀도에 따라 널뛴다(웨이브 런 실측).
        let later = learns.filter { $0.level > cutoff }
            .sorted { $0.level == $1.level ? $0.name < $1.name : $0.level < $1.level }
        return (recent + later).map(\.name)
    }

    /// 기술 4개 — 공격기는 STAB·고위력 우선하되 타입 중복은 뒤로(견제폭), **변화기는 최대 한 칸**.
    ///
    /// 칸을 나누는 게 핵심이다. 위력 내림차순 한 줄에 변화기를 그냥 섞으면 위력 0 이라 늘 꼴찌라
    /// **절대 안 뽑힌다** — 이 함수가 `guard spec.power > 0` 을 대신하는 자리다.
    ///
    /// 칸을 가르는 기준은 `VariableDamage.dealsDamage` 다. `power > 0` 으로 가르면 도감 위력이
    /// 0 인 공격기(일렉트릭볼·지구던지기·자이로볼 …)가 변화기 쪽으로 떨어지고 거기서도 거절당해
    /// **어느 칸에도 못 들어갔다.**
    ///
    /// ponytail: 그 부류는 `pickAttacks` 의 위력 정렬에서 0 이라 늘 꼴찌고, 같은 타입에 더 나은
    ///           공격기가 없을 때만 칸을 받는다. 기댓값 표를 만들 이유는 아직 없다.
    static func pickFour(from specs: [MoveSpec], types: [PokemonType]) -> [MoveSpec] {
        let attacks = specs.filter(VariableDamage.dealsDamage)
        let statusPick = pickStatusMove(from: specs.filter { !VariableDamage.dealsDamage($0) })
        // 남은 칸을 공격기로 되채우는 루프는 필요 없다 — `pickAttacks` 의 두 번째 루프가 이미
        // 상한까지 전 공격기를 채우므로, 여기 도달하면 out 은 4개거나 attacks 를 전부 담고 있다.
        var out = pickAttacks(from: attacks, types: types, limit: statusPick == nil ? 4 : 3)
        if let statusPick { out.append(statusPick) }
        return out
    }

    /// 변화기 한 칸의 주인 — **엔진이 실제로 적용하는 효과가 있는 것만**. PP 만 태우는 기술은
    /// `nil` 을 돌려 그 칸을 공격기에게 넘긴다. 걸러야 하는 셋:
    /// 효과 미구현 변화기(ailment 14종), 자기 대상 상태기(잠자기 — 회복이 없어 엔진이 건너뛴다),
    /// 부호가 섞인 랭크 변화(저주 — 대상을 가릴 수 없어 엔진이 건너뛴다), 대가를 모델링하지 않은
    /// 큰 상승(배가르기 — `statChangePercent` 가 0 으로 접는다).
    /// **엔진의 게이트와 같은 값을 본다** — 여기서만 거르면 `learnedMoves` 경로가 갈라진다.
    /// 순서는 후보 정렬(습득 레벨 내림차순)을 그대로 따라가므로 결정적이다.
    private static func pickStatusMove(from specs: [MoveSpec]) -> MoveSpec? {
        specs.first { $0.hasModeledStatusEffect }
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

    /// 진화체인 DTO → EvoNode. 순수 변환이라 actor 상태와 무관하고(nonisolated static), 조건 파싱을
    /// 테스트에서 직접 검증할 수 있어야 한다 — 필드 하나를 안 읽으면 진화 조건이 조용히 뭉개진다.
    static func evoNode(from link: ChainLink) -> EvoNode {
        let speciesID = Self.id(from: link.species.url ?? "")
        // 레어코일→자포코일은 구작 데이터에서 `level-up + 특정 장소`로만 내려오고 min_level/item 이
        // 비어 있다. 앱에는 장소 진화 축이 없고, 현행 본가에서는 천둥의돌로 진화하므로 그 규칙으로
        // 정규화한다. 그대로 두면 applyUsage 의 특수조건 가드와 아이템 매칭 양쪽에서 모두 막힌다.
        let stoneOverride: String? = [462: "thunder-stone", 470: "leaf-stone",
                                      471: "ice-stone", 476: "thunder-stone"][speciesID]
        return EvoNode(speciesID: speciesID,
                // 피오네→마나피는 진화가 아니라 번식 관계인데 체인 응답에 연결돼 있다. 앱에서
                // 성장 진화로 오인하지 않도록 지원 트리에서 제거한다.
                children: link.evolves_to.filter { Self.id(from: $0.species.url ?? "") != 490 }
                    .map(evoNode(from:)),
                // 친밀도 진화는 min_level 이 없다(trigger=level-up, min_happiness 만 존재) → 그대로 두면
                // 레벨 게이트를 못 타고 아이템/트리거 게이트에도 막혀 영영 진화하지 않는다.
                // 앱에 친밀도 축이 없으므로 요구 친밀도를 레벨로 환산해 같은 레벨 게이트에 태운다.
                evolutionLevel: link.evolution_details.compactMap(\.min_level).first
                    ?? link.evolution_details.compactMap(\.min_happiness).first
                        .map(PokemonBalance.friendshipLevel(minHappiness:)),
                evolutionTrigger: stoneOverride != nil
                    ? "use-item" : Self.evolutionCondition(link.evolution_details)?.trigger.name,
                evolutionItem: stoneOverride ?? Self.evolutionCondition(link.evolution_details)?.item?.name,
                // held_item 은 details[0] 이 아닐 수 있어(시간대 조건이 details 를 쪼갠다) 전체에서 찾는다.
                evolutionHeldItem: link.evolution_details.compactMap(\.held_item).first?.name,
                evolutionGender: PokemonGender.fromEvolutionCode(
                    link.evolution_details.compactMap(\.gender).first),
                evolutionKnownMoveID: link.evolution_details.compactMap(\.known_move).first
                    .map { Self.id(from: $0.url ?? "") },
                evolutionTimeOfDay: link.evolution_details.contains(where: { ($0.time_of_day ?? "").isEmpty })
                    ? nil : link.evolution_details.compactMap(\.time_of_day).first(where: { !$0.isEmpty }),
                evolutionRelativePhysicalStats: link.evolution_details.compactMap(\.relative_physical_stats).first,
                evolutionPartySpeciesID: link.evolution_details.compactMap(\.party_species).first
                    .map { Self.id(from: $0.url ?? "") },
                evolutionTradeSpeciesID: link.evolution_details.compactMap(\.trade_species).first
                    .map { Self.id(from: $0.url ?? "") })
    }

    /// 여러 조건 중 앱에서 실제로 실행 가능한 진화 조건 한 줄을 고른다.
    static func evolutionCondition(_ details: [ChainLink.EvolutionDetail]) -> ChainLink.EvolutionDetail? {
        let opensWithoutItem = details.contains {
            $0.min_level != nil || $0.min_happiness != nil || $0.held_item != nil
        }
        guard !opensWithoutItem else { return details.first }
        return details.first { $0.item != nil } ?? details.first
    }
    private func allIDs(_ n: EvoNode) -> [Int] { [n.speciesID] + n.children.flatMap(allIDs) }
    private static func allKnownMoveIDs(_ n: EvoNode) -> [Int] {
        (n.evolutionKnownMoveID.map { [$0] } ?? []) + n.children.flatMap(allKnownMoveIDs)
    }

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
    let gender_rate: Int?
    let names: [NameDTO]
    let evolution_chain: URLRef
    let evolves_from_species: NamedRef?   // nil = 진화라인 시작점(base)
}
/// `/pokemon-species/{id}` 중 **대화 페르소나만** 쓰는 부분. `SpeciesDTO` 에 합치지 않는다 —
/// `flavor_text_entries` 는 그 응답에서 가장 큰 배열(버전 × 언어 수십 개)이라, 부화와 진화라인
/// 로드마다 디코딩하고 버리는 값이 된다. 대화 화면이 열릴 때만 이 DTO 로 한 번 더 받는다.
struct ChatSpeciesDTO: Decodable, Sendable {
    let flavor_text_entries: [SpeciesFlavorTextDTO]?
    let genera: [GenusDTO]?
    let habitat: NamedRef?
}
struct SpeciesFlavorTextDTO: Decodable, Sendable { let flavor_text: String; let language: NamedRef }
struct GenusDTO: Decodable, Sendable { let genus: String; let language: NamedRef }
struct NameDTO: Decodable, Sendable { let name: String; let language: NamedRef }
struct NamedRef: Decodable, Sendable { let name: String; let url: String? }
struct URLRef: Decodable, Sendable { let url: String }
struct ChainDTO: Decodable, Sendable { let chain: ChainLink }

/// 배틀에 필요한 종 데이터(종족값·타입) — `/pokemon/{id}` 부분 디코드 결과.
struct PokemonBattleProfile: Sendable {
    let speciesID: Int
    let stats: BattleStats
    let types: [PokemonType]
    /// 헥토그램(0.1kg). 체중으로 위력이 정해지는 기술(저공격·풀묶기·헤비봄버·히트스탬프)이 쓴다.
    /// 기본값을 둔 이유는 타입만 쓰는 테스트 스텁을 그대로 두기 위함이다 — 실 클라이언트는 늘 채운다.
    var weightHectograms: Int = 0
    /// 대표 특성 슬러그(숨은 특성 제외, slot 이 가장 낮은 쪽). 조회 실패·미보유면 `nil` 이고,
    /// 그 경우 스냅샷도 `nil` 을 실어 특성이 없는 개체가 된다.
    var abilitySlug: String? = nil
}
struct PokemonDTO: Decodable, Sendable {
    struct StatEntry: Decodable, Sendable { let base_stat: Int; let stat: NamedRef }
    struct TypeEntry: Decodable, Sendable { let slot: Int; let type: NamedRef }
    let stats: [StatEntry]
    let types: [TypeEntry]
    /// 헥토그램(0.1kg). 본가가 이 단위로 위력 구간을 나누므로 kg 으로 바꾸지 않고 그대로 들고 간다 —
    /// 저공격·헤비봄버 구간표가 정수 비교로 끝난다(`VariableDamage`).
    let weight: Int
    /// 같은 응답에 이미 들어 있는 특성 목록 — **추가 요청 없이** 대표 특성을 고른다.
    /// 옵셔널인 이유는 이 필드를 안 읽던 시절의 캐시 응답 때문이다(없으면 특성 없는 개체가 된다).
    let abilities: [PokemonAbilitiesDTO.Entry]?
}
/// `/pokemon/{id}` 의 moves 부분만 — 배틀 프로필과 별도 디코드(무브셋은 대전 시작 때만 필요).
struct PokemonMovesDTO: Decodable, Sendable {
    struct MoveEntry: Decodable, Sendable {
        struct Detail: Decodable, Sendable {
            let level_learned_at: Int
            let move_learn_method: NamedRef
            let version_group: NamedRef?
        }
        let move: NamedRef
        let version_group_details: [Detail]
    }
    let moves: [MoveEntry]
}
/// `/pokemon/{id}` 의 abilities 부분만 — 배틀 프로필이 대표 특성을 고르는 데 쓴다.
struct PokemonAbilitiesDTO: Decodable, Sendable {
    struct Entry: Decodable, Sendable {
        let ability: NamedRef
        let is_hidden: Bool
        let slot: Int
    }
    let abilities: [Entry]

    /// 대표 특성 슬러그 — 숨은 특성은 빼고 slot 이 가장 낮은 쪽.
    /// 튜플을 받는 이유는 DTO 를 만들지 않고도 규칙만 시험할 수 있게 하려는 것이다.
    static func primaryAbilitySlug(
        _ entries: [(slug: String, isHidden: Bool, slot: Int)]
    ) -> String? {
        entries.filter { !$0.isHidden }.min { $0.slot < $1.slot }?.slug
    }

    static func primarySlug(of entries: [Entry]) -> String? {
        primaryAbilitySlug(entries.map { (slug: $0.ability.name, isHidden: $0.is_hidden, slot: $0.slot) })
    }
}
/// `/ability/{slug}` 의 현지화 이름과 설명만.
struct AbilityDTO: Decodable, Sendable {
    let names: [NameDTO]
    let flavor_text_entries: [SpeciesFlavorTextDTO]
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
        let drain: Int?
        /// 자기 회복량(최대 HP 대비 %). 회복·아침햇살 계열이 50 이고, 잠자기는 0 이다
        /// (전회복이라 `meta` 로 표현되지 않는다 — `MoveSpec.restMoveID` 가 따로 본다).
        let healing: Int?
        let flinch_chance: Int?
        let min_hits: Int?
        let max_hits: Int?
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
    /// 기술의 대상(`user`·`selected-pokemon` …). `meta.ailment` 와 `stat_changes` 에는 대상이 없어서
    /// **이 값이 자기 대상 기술을 가리는 유일한 신호다** — 없으면 잠자기가 상대를 재운다.
    let target: NamedRef?

    /// `target` 이 자기 자신(또는 자기 진영)을 가리키는 이름들. `selected-pokemon` 은 자기 랭크를
    /// 깎는 공격기(인파이트)도 쓰므로 여기 없다 — 그쪽은 `statChangePercent` 가 따로 걸러낸다.
    static let userTargets: Set<String> = ["user", "users-field", "user-and-allies", "user-or-ally"]
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
        let spec = MoveSpec(id: dto.id, names: names, type: type,
                        power: dto.power ?? 0, damageClass: damageClass,
                        accuracy: dto.accuracy, pp: dto.pp ?? 10,
                        descriptions: descriptions, priority: dto.priority,
                        critRate: dto.meta?.crit_rate,
                        ailment: ailment, ailmentChance: dto.meta?.ailment_chance,
                        statChanges: statChanges, statChance: dto.meta?.stat_chance,
                        targetsUser: dto.target.map { MoveDTO.userTargets.contains($0.name) },
                        // 원문 슬러그를 그대로 싣는다 — 광역 범위(`MoveSpec.reach`)가 이 값을 읽는다.
                        target: dto.target?.name,
                        // **`?? 0` 이 세이브 수렴의 앵커다.** `drain` 이 nil 로 남으면
                        // `needsDetailRefresh` 가 "안 받아봤다"로 읽어 헛도는 조회가 로드마다
                        // 영구히 남는다(defect-log: "받을 수 없는 값을 참으로 만들면 안 된다").
                        // `meta` 가 통째로 없는 기술도 한 번 받으면 0 으로 확정된다.
                        // `min_hits`/`max_hits` 는 단발기의 null 이 **뜻이 있는** 값이라 그대로 둔다.
                        drain: dto.meta?.drain ?? 0, healing: dto.meta?.healing ?? 0,
                        flinchChance: dto.meta?.flinch_chance ?? 0,
                        minHits: dto.meta?.min_hits, maxHits: dto.meta?.max_hits)
        // 와이어 천장을 넘는 기술은 **상대가 반려한다** — 내 화면엔 멀쩡히 보이는데 대전만 안 된다.
        // 도감은 원격이라 코드를 안 건드려도 이 날이 온다. ailment 와 같은 규칙으로 한 번 남긴다.
        if MultiplayerValidation.exceedsTurnDamageCap(spec) {
            AppLog.write("""
                move \(dto.id) (\(fallbackName)): power×hits \
                \(spec.power * (spec.maxHits ?? 1)) exceeds wire cap \
                \(MultiplayerValidation.turnDamageCap) — peers will reject this move
                """)
        }
        return spec
    }
}
struct ChainLink: Decodable, Sendable {
    struct EvolutionDetail: Decodable, Sendable {
        let min_level: Int?
        /// 친밀도 진화 조건(160·220). 앱엔 친밀도 축이 없어 레벨로 환산한다 — PokemonBalance.friendshipLevel.
        let min_happiness: Int?
        let trigger: NamedRef
        let item: NamedRef?
        /// 지닌물건 진화 조건(킹스록·금속코트 …). `trigger` 는 trade 또는 level-up 이고 `item` 은 비어
        /// 있어, 이 필드를 읽지 않으면 "교환 진화" 전부가 한 조건으로 뭉개진다 — 연결의끈 하나로
        /// 야도킹·킹크로스까지 진화되던 원인이다.
        let held_item: NamedRef?
        /// 1=암컷, 2=수컷. 성별 분기가 아닌 진화는 null.
        let gender: Int?
        /// 특정 기술을 배운 채로 레벨업해야 하는 진화(원시의힘·흉내내기·구르기·더블어택).
        let known_move: NamedRef?
        let time_of_day: String?
        let relative_physical_stats: Int?
        let party_species: NamedRef?
        let trade_species: NamedRef?
    }
    let species: NamedRef
    let evolves_to: [ChainLink]
    let evolution_details: [EvolutionDetail]
}
