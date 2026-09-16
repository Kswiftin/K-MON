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

struct PokemonTFTArmyUnit: Codable, Sendable, Equatable {
    let definitionID: Int
    let star: Int
    let boardSlot: Int
}

struct PokemonTFTArmy: Codable, Sendable, Equatable {
    let units: [PokemonTFTArmyUnit]
}

struct PokemonTFTPlayerState: Codable, Sendable, Equatable, Identifiable {
    let id: UUID
    let trainerName: String
    var health: Int
    var isEliminated: Bool { health <= 0 }
}

enum PokemonTFTRoundSettlement {
    /// 각 클라이언트의 전투는 독립 리플레이라 같은 매치의 양쪽이 모두 패배를 보고할 수 있다.
    /// 마지막 생존자들이 동시에 0이 되면 우승자가 영원히 정해지지 않으므로, 라운드 시작 시 체력이
    /// 가장 높았던 참가자 한 명을 1로 남긴다. 동률은 UUID 순으로 고정해 모든 실행에서 같다.
    static func apply(players: [PokemonTFTPlayerState], results: [UUID: Bool], damage: Int)
        -> [PokemonTFTPlayerState] {
        let aliveBefore = players.filter { !$0.isEliminated }
        var updated = players
        for index in updated.indices where results[updated[index].id] == false {
            updated[index].health = max(0, updated[index].health - damage)
        }
        if !aliveBefore.isEmpty, updated.allSatisfy(\.isEliminated),
           let survivor = aliveBefore.sorted(by: {
               $0.health == $1.health
                   ? $0.id.uuidString < $1.id.uuidString
                   : $0.health > $1.health
           }).first,
           let index = updated.firstIndex(where: { $0.id == survivor.id }) {
            updated[index].health = 1
        }
        return updated
    }
}

struct PokemonTFTMatchup: Codable, Sendable, Equatable {
    let round: Int
    let opponentID: UUID
    let opponentName: String
    let army: PokemonTFTArmy
}

struct PokemonTFTFighter: Identifiable, Sendable, Equatable {
    enum Team: Sendable { case player, enemy }
    let id: UUID
    let speciesID: Int
    let name: String
    let type: PokemonType
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

struct PokemonTFTBattleAction: Sendable, Equatable {
    enum Kind: Sendable { case move, attack, critical, skill }
    let kind: Kind
    let sourceID: UUID
    let targetID: UUID?
    let sourceX: Int
    let sourceY: Int
    let targetX: Int
    let targetY: Int
    let type: PokemonType
}

struct PokemonTFTBattleFrame: Sendable, Equatable {
    let fighters: [PokemonTFTFighter]
    let message: String
    let action: PokemonTFTBattleAction?
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
        .init(id: 27,  name: "모래두지", type: .ground,   cost: 1, attack: 48, health: 112),
        .init(id: 37,  name: "식스테일", type: .fire,     cost: 2, attack: 68, health: 84),
        .init(id: 63,  name: "캐이시",   type: .psychic,  cost: 2, attack: 84, health: 72),
        .init(id: 25,  name: "피카츄",   type: .electric, cost: 2, attack: 70, health: 88),
        .init(id: 66,  name: "알통몬",   type: .fighting, cost: 2, attack: 74, health: 120),
        .init(id: 81,  name: "코일",     type: .steel,    cost: 2, attack: 72, health: 108),
        .init(id: 92,  name: "고오스",   type: .ghost,    cost: 2, attack: 82, health: 78),
        .init(id: 133, name: "이브이",   type: .normal,   cost: 2, attack: 62, health: 100),
        .init(id: 147, name: "미뇽",     type: .dragon,   cost: 3, attack: 88, health: 118),
        .init(id: 152, name: "치코리타", type: .grass,    cost: 1, attack: 40, health: 118),
        .init(id: 158, name: "리아코",   type: .water,    cost: 1, attack: 52, health: 108),
        .init(id: 179, name: "메리프",   type: .electric, cost: 2, attack: 66, health: 102),
        .init(id: 215, name: "포푸니",   type: .dark,     cost: 3, attack: 96, health: 90),
        .init(id: 280, name: "랄토스",   type: .psychic,  cost: 3, attack: 92, health: 94),
        .init(id: 304, name: "가보리",   type: .steel,    cost: 3, attack: 70, health: 155),
        .init(id: 353, name: "어둠대신", type: .ghost,    cost: 3, attack: 94, health: 86),
        .init(id: 443, name: "딥상어동", type: .ground,   cost: 4, attack: 116, health: 145),
        .init(id: 446, name: "먹고자",   type: .normal,   cost: 3, attack: 76, health: 165),
        .init(id: 447, name: "리오르",   type: .fighting, cost: 4, attack: 120, health: 126),
        .init(id: 570, name: "조로아",   type: .dark,     cost: 4, attack: 132, health: 105),
        .init(id: 610, name: "터검니",   type: .dragon,   cost: 5, attack: 148, health: 150)
    ]

    struct SynergyInfo: Identifiable, Sendable {
        var id: String { type.rawValue }
        let type: PokemonType
        let members: [String]
        let deployed: Int
        var nextThreshold: Int? { deployed < 2 ? 2 : deployed < 4 ? 4 : nil }
        var effectText: String {
            if deployed >= 4 { return "4마리: 해당 타입 공격력·체력 +25%" }
            if deployed >= 2 { return "2마리: 해당 타입 공격력·체력 +10%" }
            return "2마리 +10% · 4마리 +25%"
        }
    }

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
    var armySnapshot: PokemonTFTArmy {
        PokemonTFTArmy(units: units.compactMap { unit in
            guard let slot = unit.boardSlot else { return nil }
            return PokemonTFTArmyUnit(definitionID: unit.definitionID, star: unit.star, boardSlot: slot)
        })
    }

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

    func synergyInfo(for type: PokemonType) -> SynergyInfo {
        let members = Self.catalog.filter { $0.type == type }.map(\.name)
        let deployed = units.filter {
            $0.boardSlot != nil && definition(for: $0.definitionID).type == type
        }.count
        return SynergyInfo(type: type, members: members, deployed: deployed)
    }

    var synergyGuide: [SynergyInfo] {
        Array(Set(Self.catalog.map(\.type))).map(synergyInfo(for:))
            .filter { $0.members.count >= 2 }
            .sorted { $0.type.rawValue < $1.type.rawValue }
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

    /// LAN TFT의 체력·탈락은 호스트가 단일 원장으로 관리한다. 로컬 클라이언트는
    /// 승패에 따른 상점 경제만 갱신하고, 12라운드 단독 모드 종료 규칙을 타지 않는다.
    mutating func settleMultiplayerBattle(playerWon: Bool) {
        guard phase == .shopping, deployedCount > 0 else { return }
        if playerWon {
            let income = 5 + min(round / 3, 4)
            gold += income; lastBattleText = "승리! +\(income) 골드"
        } else {
            lastBattleText = "패배 · 호스트 체력 정산 중"
        }
        round += 1
        gold += min(gold / 10, 5)
        refreshShop(free: true)
    }

    /// 8×6 격자에서 가장 가까운 적을 찾아 이동하고 사거리 안이면 공격하는 전투 리플레이.
    /// pokemonAutoChess의 보드/상태 머신 개념을 참고했지만 Swift로 독립 구현했다.
    func makeBattleReplay(opponent: PokemonTFTArmy? = nil) -> PokemonTFTBattleReplay {
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
                type: definition.type, team: .player,
                x: (slot % Self.boardColumns) * 2, y: 5 - slot / Self.boardColumns,
                maxHP: Int(Double(hp) * synergy), hp: Int(Double(hp) * synergy),
                attack: Int(Double(definition.attack) * multiplier * synergy),
                defense: max(4, definition.health / 12),
                attackRange: Self.rangedTypes.contains(definition.type) ? 2 : 1,
                speed: 45 + definition.attack / 4, mana: 80)
        }
        let enemyScale = opponent == nil ? 1.0 + Double(round - 1) * 0.10 : 1
        let enemyUnits: [(PokemonTFTUnitDefinition, Int, Int)] = opponent?.units.compactMap { unit in
            guard let definition = Self.catalog.first(where: { $0.id == unit.definitionID }) else { return nil }
            return (definition, unit.star, unit.boardSlot)
        } ?? enemyPreview.enumerated().map { ($0.element, 1, $0.offset) }
        fighters += enemyUnits.enumerated().map { index, entry in
            let (definition, star, slot) = entry
            let starScale = pow(1.65, Double(max(0, star - 1)))
            let hp = Int(Double(definition.health) * enemyScale * starScale)
            return PokemonTFTFighter(id: UUID(), speciesID: definition.id, name: definition.name,
                type: definition.type, team: .enemy,
                x: (slot % Self.boardColumns) * 2, y: min(2, slot / Self.boardColumns),
                maxHP: hp, hp: hp, attack: Int(Double(definition.attack) * enemyScale * starScale),
                defense: max(4, Int(Double(definition.health / 12) * enemyScale)),
                attackRange: Self.rangedTypes.contains(definition.type) ? 2 : 1,
                speed: 45 + definition.attack / 4, mana: 80)
        }
        var frames = [PokemonTFTBattleFrame(fighters: fighters, message: "전투 준비…", action: nil),
                      PokemonTFTBattleFrame(fighters: fighters, message: "전투 시작!", action: nil)]
        for tick in 0..<36 {
            let turnOrder = fighters.filter { $0.hp > 0 }
                .sorted { $0.speed > $1.speed }.map(\.id)
            for (turn, actorID) in turnOrder.enumerated() {
                guard let actorIndex = fighters.firstIndex(where: { $0.id == actorID && $0.hp > 0 }) else { continue }
                let enemies = fighters.indices.filter { fighters[$0].team != fighters[actorIndex].team && fighters[$0].hp > 0 }
                guard let targetIndex = enemies.min(by: {
                    Self.distance(fighters[actorIndex], fighters[$0]) < Self.distance(fighters[actorIndex], fighters[$1])
                }) else { break }
                if Self.distance(fighters[actorIndex], fighters[targetIndex]) <= fighters[actorIndex].attackRange {
                    let source = fighters[actorIndex]
                    let target = fighters[targetIndex]
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
                    } else {
                        // 전투가 짧은 소규모 모드라 스킬을 한 번도 못 보고 끝나지 않게
                        // 공격·피격 모두에서 마나를 빠르게 채운다.
                        fighters[actorIndex].mana = min(100, fighters[actorIndex].mana + 20)
                        fighters[targetIndex].mana = min(100, fighters[targetIndex].mana + 15)
                    }
                    let kind: PokemonTFTBattleAction.Kind = usesSkill ? .skill : critical ? .critical : .attack
                    let action = PokemonTFTBattleAction(kind: kind, sourceID: source.id, targetID: target.id,
                        sourceX: source.x, sourceY: source.y, targetX: target.x, targetY: target.y, type: source.type)
                    let verb = usesSkill ? "스킬" : critical ? "급소 공격" : "공격"
                    frames.append(PokemonTFTBattleFrame(fighters: fighters,
                                                        message: "\(source.name)의 \(verb)!", action: action))
                } else {
                    let source = fighters[actorIndex]
                    let occupied = Set(fighters.filter { $0.hp > 0 && $0.id != actorID }.map { "\($0.x),\($0.y)" })
                    if let next = Self.nextStep(from: source, toward: fighters[targetIndex], occupied: occupied) {
                        fighters[actorIndex].x = next.0
                        fighters[actorIndex].y = next.1
                        let action = PokemonTFTBattleAction(kind: .move, sourceID: source.id, targetID: nil,
                            sourceX: source.x, sourceY: source.y, targetX: next.0, targetY: next.1, type: source.type)
                        frames.append(PokemonTFTBattleFrame(fighters: fighters,
                                                            message: "\(source.name) 이동", action: action))
                    }
                }
            }
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

    /// 직선 앞이 막히면 옆으로 우회한다. 기존 구현은 목표 방향의 가로·세로
    /// 두 칸만 검사해, 앞줄이 겹치면 전원이 영원히 이동만 시도하는 교착이 생겼다.
    private static func nextStep(from actor: PokemonTFTFighter, toward target: PokemonTFTFighter,
                                 occupied: Set<String>) -> (Int, Int)? {
        let neighbors = [(actor.x + 1, actor.y), (actor.x - 1, actor.y),
                         (actor.x, actor.y + 1), (actor.x, actor.y - 1)]
            .filter {
                (0..<combatColumns).contains($0.0) && (0..<combatRows).contains($0.1) &&
                !occupied.contains("\($0.0),\($0.1)")
            }
        return neighbors.min {
            let lhs = abs($0.0 - target.x) + abs($0.1 - target.y)
            let rhs = abs($1.0 - target.x) + abs($1.1 - target.y)
            if lhs == rhs { return ($0.1, $0.0) < ($1.1, $1.0) }
            return lhs < rhs
        }
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
