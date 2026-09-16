import Foundation

struct PokemonTFTUnitDefinition: Identifiable, Sendable, Equatable {
    let id: Int
    let name: String
    let type: PokemonType
    let cost: Int
    let attack: Int
    let health: Int
}

struct PokemonTFTUnit: Identifiable, Sendable, Equatable {
    let id: UUID
    let definitionID: Int
    var star: Int
    var boardSlot: Int?

    init(definitionID: Int, star: Int = 1, boardSlot: Int? = nil, id: UUID = UUID()) {
        self.id = id
        self.definitionID = definitionID
        self.star = star
        self.boardSlot = boardSlot
    }
}

struct PokemonTFTFighter: Identifiable, Sendable, Equatable {
    enum Team: Sendable { case player, enemy }
    let id: UUID
    let speciesID: Int
    let name: String
    let team: Team
    var x: Int
    var y: Int
    let maxHP: Int
    var hp: Int
    let attack: Int
    let defense: Int
    let attackRange: Int
    let speed: Int
    var mana: Int
}

struct PokemonTFTBattleFrame: Sendable, Equatable {
    let fighters: [PokemonTFTFighter]
    let message: String
}

struct PokemonTFTBattleReplay: Sendable {
    let frames: [PokemonTFTBattleFrame]
    let playerWon: Bool
}

/// 포켓몬식 오토배틀러 한 판. 앱의 보유 포켓몬/재화와 분리된 세션이라 중도 종료해도 세이브를
/// 오염시키지 않는다. 화면은 입력만 전달하고 경제·합성·전투 판정은 전부 이 구조체가 담당한다.
struct PokemonTFTGame: Sendable {
    enum Phase: Sendable, Equatable { case shopping, finished(won: Bool) }

    static let boardColumns = 4
    static let boardRows = 3
    static let boardSlots = boardColumns * boardRows
    static let combatColumns = 8
    static let combatRows = 6
    static let benchLimit = 8
    static let finalRound = 12
    private static let rangedTypes: Set<PokemonType> = [.fire, .water, .grass, .electric, .psychic, .ghost, .dragon]
    static let catalog: [PokemonTFTUnitDefinition] = [
        .init(id: 1,   name: "이상해씨", type: .grass,    cost: 1, attack: 42, health: 105),
        .init(id: 4,   name: "파이리",   type: .fire,     cost: 1, attack: 55, health: 82),
        .init(id: 7,   name: "꼬부기",   type: .water,    cost: 1, attack: 40, health: 115),
        .init(id: 25,  name: "피카츄",   type: .electric, cost: 2, attack: 70, health: 88),
        .init(id: 66,  name: "알통몬",   type: .fighting, cost: 2, attack: 74, health: 120),
        .init(id: 92,  name: "고오스",   type: .ghost,    cost: 2, attack: 82, health: 78),
        .init(id: 133, name: "이브이",   type: .normal,   cost: 2, attack: 62, health: 100),
        .init(id: 147, name: "미뇽",     type: .dragon,   cost: 3, attack: 88, health: 118),
        .init(id: 215, name: "포푸니",   type: .dark,     cost: 3, attack: 96, health: 90),
        .init(id: 280, name: "랄토스",   type: .psychic,  cost: 3, attack: 92, health: 94),
        .init(id: 304, name: "가보리",   type: .steel,    cost: 3, attack: 70, health: 155),
        .init(id: 443, name: "딥상어동", type: .ground,   cost: 4, attack: 116, health: 145),
        .init(id: 447, name: "리오르",   type: .fighting, cost: 4, attack: 120, health: 126),
        .init(id: 570, name: "조로아",   type: .dark,     cost: 4, attack: 132, health: 105),
        .init(id: 610, name: "터검니",   type: .dragon,   cost: 5, attack: 148, health: 150)
    ]

    var health = 100
    var gold = 10
    var round = 1
    var level = 3
    var experience = 0
    var units: [PokemonTFTUnit] = []
    var shop: [Int?] = []
    var phase: Phase = .shopping
    var lastBattleText = "포켓몬을 구매해 배치하세요."
    private var seed: UInt64

    init(seed: UInt64 = UInt64.random(in: 1...UInt64.max)) {
        self.seed = seed
        refreshShop(free: true)
    }

    var deployedCount: Int { units.filter { $0.boardSlot != nil }.count }
    var unitLimit: Int { min(level, 6) }
    var benchCount: Int { units.filter { $0.boardSlot == nil }.count }
    var experienceNeeded: Int { level >= 6 ? 0 : level * 4 }

    /// 현재 라운드에서 화면에 보여 줄 상대 진영. 전투 판정의 난이도 곡선과 같은 마릿수를 쓰고,
    /// 라운드로만 고르므로 연출을 다시 그려도 상대 모습이 바뀌지 않는다.
    var enemyPreview: [PokemonTFTUnitDefinition] {
        let count = min(2 + round / 2, 6)
        return (0..<count).map { offset in
            let index = (round * 3 + offset * 5) % Self.catalog.count
            return Self.catalog[index]
        }
    }

    func definition(for id: Int) -> PokemonTFTUnitDefinition {
        Self.catalog.first { $0.id == id }!
    }

    mutating func buy(shopIndex: Int) -> Bool {
        guard phase == .shopping, shop.indices.contains(shopIndex),
              let definitionID = shop[shopIndex] else { return false }
        let definition = definition(for: definitionID)
        guard gold >= definition.cost, benchCount < Self.benchLimit else { return false }
        gold -= definition.cost
        units.append(PokemonTFTUnit(definitionID: definitionID))
        shop[shopIndex] = nil
        combine(definitionID: definitionID)
        return true
    }

    mutating func refreshShop(free: Bool = false) {
        guard phase == .shopping, free || gold >= 2 else { return }
        if !free { gold -= 2 }
        shop = (0..<6).map { _ in rollDefinitionID() }
    }

    mutating func buyExperience() {
        guard phase == .shopping, level < 6, gold >= 4 else { return }
        gold -= 4; experience += 4
        while level < 6, experience >= level * 4 {
            experience -= level * 4; level += 1
        }
    }

    mutating func toggleDeployment(_ id: UUID) {
        guard phase == .shopping, let index = units.firstIndex(where: { $0.id == id }) else { return }
        if units[index].boardSlot != nil {
            units[index].boardSlot = nil
        } else if deployedCount < unitLimit {
            units[index].boardSlot = (0..<Self.boardSlots).first { slot in
                !units.contains { $0.boardSlot == slot }
            }
        }
    }

    mutating func move(_ id: UUID, to slot: Int) {
        guard phase == .shopping, (0..<Self.boardSlots).contains(slot),
              let index = units.firstIndex(where: { $0.id == id }) else { return }
        if let other = units.firstIndex(where: { $0.boardSlot == slot }) {
            units[other].boardSlot = units[index].boardSlot
        } else if units[index].boardSlot == nil, deployedCount >= unitLimit { return }
        units[index].boardSlot = slot
    }

    mutating func sell(_ id: UUID) {
        guard phase == .shopping, let index = units.firstIndex(where: { $0.id == id }) else { return }
        let unit = units.remove(at: index)
        gold += definition(for: unit.definitionID).cost * (unit.star == 1 ? 1 : unit.star * 2)
    }

    mutating func fight() {
        guard phase == .shopping, deployedCount > 0 else { return }
        settleBattle(playerWon: makeBattleReplay().playerWon)
    }

    mutating func settleBattle(playerWon: Bool) {
        guard phase == .shopping, deployedCount > 0 else { return }
        if playerWon {
            let income = 5 + min(round / 3, 4)
            gold += income
            lastBattleText = "승리! +\(income) 골드"
            if round == Self.finalRound { phase = .finished(won: true); return }
        } else {
            let damage = max(4, 3 + round)
            health = max(0, health - damage)
            lastBattleText = "패배 · 체력 -\(damage)"
            if health == 0 { phase = .finished(won: false); return }
        }
        round += 1
        gold += min(gold / 10, 5) // 10골드당 이자, 최대 5
        refreshShop(free: true)
    }

    /// 8×6 격자에서 가장 가까운 적을 찾아 이동하고 사거리 안이면 공격하는 전투 리플레이.
    /// pokemonAutoChess의 보드/상태 머신 개념을 참고했지만 Swift로 독립 구현했다.
    func makeBattleReplay() -> PokemonTFTBattleReplay {
        var fighters: [PokemonTFTFighter] = units.filter { $0.boardSlot != nil }.map { unit in
            let definition = definition(for: unit.definitionID)
            let slot = unit.boardSlot ?? 0
            let multiplier = pow(1.65, Double(unit.star - 1))
            let hp = Int(Double(definition.health) * multiplier)
            let typeCount = units.filter { candidate in
                candidate.boardSlot != nil && self.definition(for: candidate.definitionID).type == definition.type
            }.count
            let synergy = typeCount >= 4 ? 1.25 : typeCount >= 2 ? 1.10 : 1
            return PokemonTFTFighter(id: unit.id, speciesID: definition.id, name: definition.name,
                team: .player, x: (slot % Self.boardColumns) * 2, y: 5 - slot / Self.boardColumns,
                maxHP: Int(Double(hp) * synergy), hp: Int(Double(hp) * synergy),
                attack: Int(Double(definition.attack) * multiplier * synergy),
                defense: max(4, definition.health / 12),
                attackRange: Self.rangedTypes.contains(definition.type) ? 2 : 1,
                speed: 45 + definition.attack / 4, mana: 0)
        }
        let enemyScale = 1.0 + Double(round - 1) * 0.10
        fighters += enemyPreview.enumerated().map { index, definition in
            let hp = Int(Double(definition.health) * enemyScale)
            return PokemonTFTFighter(id: UUID(), speciesID: definition.id, name: definition.name,
                team: .enemy, x: (index % 4) * 2, y: index / 4,
                maxHP: hp, hp: hp, attack: Int(Double(definition.attack) * enemyScale),
                defense: max(4, Int(Double(definition.health / 12) * enemyScale)),
                attackRange: Self.rangedTypes.contains(definition.type) ? 2 : 1,
                speed: 45 + definition.attack / 4, mana: 0)
        }
        var frames = [PokemonTFTBattleFrame(fighters: fighters, message: "전투 시작!")]
        for tick in 0..<36 {
            var firstMessage: String?
            let turnOrder = fighters.filter { $0.hp > 0 }
                .sorted { $0.speed > $1.speed }.map(\.id)
            for (turn, actorID) in turnOrder.enumerated() {
                guard let actorIndex = fighters.firstIndex(where: { $0.id == actorID && $0.hp > 0 }) else { continue }
                let enemies = fighters.indices.filter { fighters[$0].team != fighters[actorIndex].team && fighters[$0].hp > 0 }
                guard let targetIndex = enemies.min(by: {
                    Self.distance(fighters[actorIndex], fighters[$0]) < Self.distance(fighters[actorIndex], fighters[$1])
                }) else { break }
                if Self.distance(fighters[actorIndex], fighters[targetIndex]) <= fighters[actorIndex].attackRange {
                    let usesSkill = fighters[actorIndex].mana >= 100
                    let critical = !usesSkill && ((tick * 17 + turn * 31 + fighters[actorIndex].speciesID) % 10 == 0)
                    let rawDamage = Double(fighters[actorIndex].attack) * (usesSkill ? 1.65 : critical ? 2 : 1)
                    let damage = max(1, Int(rawDamage / (1 + Double(fighters[targetIndex].defense) * 0.05)))
                    fighters[targetIndex].hp = max(0, fighters[targetIndex].hp - damage)
                    if usesSkill {
                        fighters[actorIndex].mana = 0
                        // 간단한 범위기: 대상과 인접한 적에게 절반 피해.
                        let splashTargets = fighters.indices.filter {
                            $0 != targetIndex && fighters[$0].team != fighters[actorIndex].team &&
                            fighters[$0].hp > 0 && Self.distance(fighters[$0], fighters[targetIndex]) <= 1
                        }
                        for splash in splashTargets {
                            fighters[splash].hp = max(0, fighters[splash].hp - damage / 2)
                        }
                        firstMessage = firstMessage ?? "\(fighters[actorIndex].name)의 스킬!"
                    } else {
                        fighters[actorIndex].mana = min(100, fighters[actorIndex].mana + 5)
                        fighters[targetIndex].mana = min(100, fighters[targetIndex].mana + 8)
                        firstMessage = firstMessage ?? "\(fighters[actorIndex].name)의 \(critical ? "급소 공격" : "공격")!"
                    }
                } else {
                    let occupied = Set(fighters.filter { $0.hp > 0 && $0.id != actorID }.map { "\($0.x),\($0.y)" })
                    let dx = fighters[targetIndex].x == fighters[actorIndex].x ? 0 : (fighters[targetIndex].x > fighters[actorIndex].x ? 1 : -1)
                    let dy = fighters[targetIndex].y == fighters[actorIndex].y ? 0 : (fighters[targetIndex].y > fighters[actorIndex].y ? 1 : -1)
                    let candidates = [(fighters[actorIndex].x + dx, fighters[actorIndex].y),
                                      (fighters[actorIndex].x, fighters[actorIndex].y + dy)]
                    if let next = candidates.first(where: {
                        (0..<Self.combatColumns).contains($0.0) &&
                        (0..<Self.combatRows).contains($0.1) &&
                        !occupied.contains("\($0.0),\($0.1)")
                    }) {
                        fighters[actorIndex].x = next.0
                        fighters[actorIndex].y = next.1
                    }
                }
            }
            frames.append(PokemonTFTBattleFrame(fighters: fighters,
                                                 message: firstMessage ?? "상대를 향해 이동 중…"))
            let playerAlive = fighters.contains { $0.team == .player && $0.hp > 0 }
            let enemyAlive = fighters.contains { $0.team == .enemy && $0.hp > 0 }
            if !playerAlive || !enemyAlive {
                return PokemonTFTBattleReplay(frames: frames, playerWon: playerAlive)
            }
        }
        let playerHP = fighters.filter { $0.team == .player }.reduce(0) { $0 + $1.hp }
        let enemyHP = fighters.filter { $0.team == .enemy }.reduce(0) { $0 + $1.hp }
        return PokemonTFTBattleReplay(frames: frames, playerWon: playerHP >= enemyHP)
    }

    func synergyText() -> String {
        let counts = Dictionary(grouping: units.filter { $0.boardSlot != nil }) {
            definition(for: $0.definitionID).type
        }.mapValues(\.count)
        let active = counts.filter { $0.value >= 2 }.sorted { $0.key.rawValue < $1.key.rawValue }
        return active.isEmpty ? "활성 시너지 없음" : active.map { "\($0.key.rawValue) \($0.value)" }.joined(separator: " · ")
    }

    private static func distance(_ lhs: PokemonTFTFighter, _ rhs: PokemonTFTFighter) -> Int {
        abs(lhs.x - rhs.x) + abs(lhs.y - rhs.y)
    }

    private mutating func combine(definitionID: Int) {
        for star in 1...2 {
            while units.filter({ $0.definitionID == definitionID && $0.star == star }).count >= 3 {
                let matches = units.indices.filter { units[$0].definitionID == definitionID && units[$0].star == star }
                let deployedSlot = matches.compactMap { units[$0].boardSlot }.first
                for index in matches.prefix(3).sorted(by: >) { units.remove(at: index) }
                units.append(PokemonTFTUnit(definitionID: definitionID, star: star + 1,
                                            boardSlot: deployedSlot))
            }
        }
    }

    private mutating func rollDefinitionID() -> Int {
        let weights: [[Int]] = [
            [100, 0, 0, 0, 0], [75, 25, 0, 0, 0], [55, 35, 10, 0, 0],
            [35, 40, 22, 3, 0], [22, 34, 30, 12, 2], [12, 25, 34, 23, 6]
        ]
        let row = weights[min(max(level, 1), 6) - 1]
        let roll = Int(nextRandom() % 100)
        var accumulated = 0
        var cost = 1
        for (index, weight) in row.enumerated() {
            accumulated += weight
            if roll < accumulated { cost = index + 1; break }
        }
        let pool = Self.catalog.filter { $0.cost == cost }
        return pool[Int(nextRandom() % UInt64(pool.count))].id
    }

    private mutating func nextRandom() -> UInt64 {
        seed &+= 0x9E37_79B9_7F4A_7C15
        var z = seed
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
