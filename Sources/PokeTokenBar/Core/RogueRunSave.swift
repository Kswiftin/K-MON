import Foundation

/// 진행 중인 웨이브 런을 디스크로 옮기는 형식. **런의 값 타입을 그대로 `Codable` 로 만들지
/// 않는다** — `BattleSide` 가 `Codable` 이 아니라는 사실이 두 자리의 근거이기 때문이다:
/// 그 타입은 와이어에 실리지 않으므로 필드를 더해도 `rulesVersion` 을 올리지 않는다
/// (`BattleSide.lastHitThisTurn`·`runBoosts` 주석). 저장 형식을 따로 두면 그 성질을 지키면서
/// 판만 디스크로 옮길 수 있고, 무엇을 남기고 무엇을 버리는지가 한 파일에 보인다.
///
/// 판 하나가 30 웨이브라 앱을 끄면 사라지는 것이 실제 손실이 됐다. 그래서 세이브 본체가 아니라
/// **옆 파일**(`wave-run.json`)에 둔다 — 런은 재화도 도감도 주지 않으므로 무결성 서명과 세이브
/// 이전(migration) 경로에 닿지 않는다는 결정을 그대로 지킨다.
struct RogueRunSave: Codable, Sendable {
    /// 형식 판. 모르는 판은 **런을 버린다** — 진행 중인 판은 소모품이고, 반쯤 읽어 되살린 판이
    /// 세이브 복구보다 나쁘다(잘못 복원한 전투는 크래시로 끝난다).
    /// 2 판에서 전투가 **필드 칸 배열**로 넓어졌다(2대2). 1 판 파일은 활성 칸이 각각 하나라
    /// 되살릴 자리가 없어 버린다 — 진행 중인 판은 소모품이라는 결정을 그대로 따른다.
    static let currentVersion = 2

    var version = currentVersion
    var wave: Int
    var stage: RogueRun.Stage
    var route: RunRoute
    var offers: [RunModifier]
    var remainingPicks: Int
    var balls: Int
    var boosts: BoostsSave
    var resultRecorded: Bool
    /// 런 rng 의 현재 상태. 씨앗이 아니라 **소비한 뒤의 상태**를 적는다 — 씨앗을 적으면 앱을
    /// 껐다 켤 때마다 같은 보상 목록이 다시 나온다.
    var rngState: UInt64
    /// 판을 심은 값. `rngState` 와 달리 소비되지 않는다 — 상대 마릿수 판정이 판 어디서든 같은
    /// 답을 내야 해서다. 옛 파일엔 없으므로 기본값 0 이고, 그 판은 마릿수만 다시 뽑힌다.
    var seed: UInt64 = 0
    /// 갈림길을 전부 위험한 길로 왔나. 옛 파일엔 없으므로 기본값은 **false** 다 — 없는 기록을
    /// 참으로 두면 이어 연 판이 안 한 일로 업적을 받는다.
    var tookOnlyRiskyRoutes = false
    var party: [SideSave]
    var battle: BattleSave

    /// 지속 강화. 타입 키를 문자열로 눕힌다 — `[PokemonType: Int]` 를 그대로 인코딩하면
    /// JSON 이 키·값이 번갈아 든 배열이 되어 파일을 사람이 읽을 수 없다.
    struct BoostsSave: Codable, Sendable {
        var typeDamage: [String: Int] = [:]
        var critStages = 0
        var leftovers = 0
        /// 기본값을 두는 이유는 옛 파일이다 — 이 세 칸이 없던 판이 복원되면 강화 없이 이어진다.
        var attack = 0
        var defense = 0
        var speed = 0

        init(_ boosts: RunBoosts) {
            typeDamage = Dictionary(uniqueKeysWithValues:
                boosts.typeDamage.map { ($0.key.rawValue, $0.value) })
            critStages = boosts.critStages
            leftovers = boosts.leftovers
            attack = boosts.attack
            defense = boosts.defense
            speed = boosts.speed
        }

        /// 모르는 타입 이름은 버린다(손편집·구버전). 강화 하나가 빠지는 것이 판을 못 여는 것보다 낫다.
        var restored: RunBoosts {
            var boosts = RunBoosts()
            for (name, stacks) in typeDamage {
                guard let type = PokemonType(rawValue: name), stacks > 0 else { continue }
                boosts.typeDamage[type] = stacks
            }
            boosts.critStages = max(0, critStages)
            boosts.leftovers = max(0, leftovers)
            boosts.attack = max(0, attack)
            boosts.defense = max(0, defense)
            boosts.speed = max(0, speed)
            return boosts
        }
    }

    /// 개체 하나. **턴 안에서만 사는 값은 싣지 않는다**(`flinched`·`lastHitThisTurn`) — 저장은
    /// 행동이 끝난 뒤에 일어나고, 그 값들은 다음 턴 머리(`BattleEngine.beginTurn`)에서 어차피
    /// 지워진다. 유효 스탯·기술 목록도 싣지 않는다: 스냅샷에서 같은 규칙으로 다시 나온다.
    struct SideSave: Codable, Sendable {
        var snapshot: BattleSnapshot
        var hp: Int
        var pp: [Int]
        var status: Status?
        var statusCounter: Int
        var confusionTurns: Int
        var stages: [BattleStat: Int]

        init(_ side: BattleSide) {
            snapshot = side.snapshot
            hp = side.hp
            pp = side.pp
            status = side.status
            statusCounter = side.statusCounter
            confusionTurns = side.confusionTurns
            stages = side.stages
        }

        /// 되살린 개체. **HP 는 0…최대치로 자른다** — 손편집된 값이 들어오면 화면의 HP 바가
        /// 음수·초과로 그려지고, 기절 판정(`isAlive`)이 실제 파티 상태와 어긋난다.
        /// PP 길이가 기술 수와 다르면(구버전·손편집) 만피 PP 로 되돌린다.
        var restored: BattleSide {
            var side = BattleSide(snapshot)
            side.hp = min(side.stats.hp, max(0, hp))
            if pp.count == side.moves.count {
                side.pp = zip(pp, side.moves).map { min($1.pp, max(0, $0)) }
            }
            side.status = status
            side.statusCounter = max(0, statusCounter)
            side.confusionTurns = max(0, confusionTurns)
            side.stages = stages.compactMapValues { value in
                let clamped = StatStages.clamped(value)
                return clamped == 0 ? nil : clamped
            }
            return side
        }
    }

    /// 진행 중인 전투. **이벤트 스트림은 싣지 않는다** — 로그는 그 판을 보고 있는 사람을 위한
    /// 값이고, 앱을 다시 켠 화면은 지나간 턴을 재생할 이유가 없다(재생기는 빈 스트림을 새 배틀로
    /// 읽어 현재 상태를 그대로 그린다). 승부(`result`)도 싣지 않는다: 저장되는 판은 진행 중인
    /// 판뿐이고, 끝난 판은 결과 화면이 실적에 적은 뒤 사라진다.
    struct BattleSave: Codable, Sendable {
        var mine: [SideSave]
        var opponents: [SideSave]
        /// 필드 칸이 든 팀 인덱스 — **배열 길이가 곧 이 웨이브의 형식**이다(하나면 단일전,
        /// 둘이면 2대2). 칸의 이벤트 주인(`FieldSlot.id`)은 싣지 않는다: 이벤트 스트림을
        /// 저장하지 않으므로 옛 id 를 가리키는 값이 파일 안에 없다.
        var myField: [Int]
        var opponentField: [Int]
        var turn: Int
        var rngState: UInt64

        init(_ battle: WaveBattle) {
            mine = battle.mine.map(SideSave.init)
            opponents = battle.opponents.map(SideSave.init)
            myField = battle.myField.map(\.teamIndex)
            opponentField = battle.opponentField.map(\.teamIndex)
            turn = battle.turn
            rngState = battle.rng.state
        }

        /// 되살린 전투. **칸이 하나라도 어긋나면 `nil` 이다** — 범위 밖 인덱스로 필드를 세우면
        /// 첫 접근에서 크래시하고, 같은 개체가 두 칸에 서면 그 개체가 한 턴에 두 번 움직인다.
        var restored: WaveBattle? {
            guard !mine.isEmpty, !opponents.isEmpty,
                  !myField.isEmpty, !opponentField.isEmpty,
                  myField.count <= WaveBattle.maxFieldSlots,
                  opponentField.count <= WaveBattle.maxFieldSlots,
                  Set(myField).count == myField.count,
                  Set(opponentField).count == opponentField.count,
                  myField.allSatisfy({ mine.indices.contains($0) }),
                  opponentField.allSatisfy({ opponents.indices.contains($0) })
            else { return nil }
            var battle = WaveBattle(mine: mine.map(\.restored),
                                    opponents: opponents.map(\.restored),
                                    rng: SplitMix64(seed: 0))
            battle.rng.state = rngState
            battle.turn = max(1, turn)
            // 필드는 저장값으로 덮는다 — 초기화가 세운 칸은 "살아 있는 앞쪽 개체" 라서, 판 도중에
            // 교체·기절 보충으로 옮겨 앉은 자리를 되살리지 못한다.
            battle.myField = myField.map { WaveBattle.FieldSlot(id: UUID(), teamIndex: $0) }
            battle.opponentField = opponentField.map {
                WaveBattle.FieldSlot(id: UUID(), teamIndex: $0)
            }
            return battle
        }
    }
}
