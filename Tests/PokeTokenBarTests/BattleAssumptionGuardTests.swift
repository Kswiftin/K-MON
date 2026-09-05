import XCTest
@testable import PokeTokenBar

/// 유예한 단순화의 **전제가 말없이 깨지는 것**을 막는 가드.
///
/// 엔진에는 "오늘 도감에는 그런 기술이 없으니 이 경로는 안 밟는다" 로 접어 둔 자리가 있다
/// (`BattleEngine.resolveAttack` 의 위력 뽑기 위치, 실패와 면역의 병합). 접은 것 자체는 부채가
/// 아니다 — **전제가 깨져도 아무도 모르는 것**이 부채다. 두 전제 모두 `VariableDamage` 의 스위치
/// 한 곳에서 결정되므로, 그 스위치를 동결해 두면 누가 손댈 때 여기서 걸린다.
///
/// 목록이 바뀌었다고 이 테스트가 빨개지는 것은 **정상 동작**이다. 목록만 갱신하고 넘어가지 말고,
/// 실패 메시지가 묻는 것(새 기술이 물·전기인가 / 다단기인가)을 먼저 답한 뒤 갱신한다.
///
/// 위력 공식 자체는 `VariableDamageTests` 가 엔진을 통과시켜 검증한다. 여기는 **어느 기술이
/// 어느 부류에 드는가**만 본다. 와이어 쪽 반려는 `BattlePhase5Tests` 가 이미 덮으므로, 여기서는
/// 도감 쪽 검출과 와이어 쪽 반려가 **같은 상수를 보는지**만 잠근다.
///
/// 주석 줄은 스캔에서 뺀다. 규칙을 설명하는 주석이 패턴을 담고 있어(이 파일도 그렇다) 빼지 않으면
/// 가드가 자기 설명에 걸린다 — `LanguageSplitGuardTests` 와 같은 이유다.
final class BattleAssumptionGuardTests: XCTestCase {

    // MARK: 동결 목록

    /// `.noEffect`(= 실패)를 낼 수 있는 기술. 오늘 타입은 격투·풀·강철·불꽃·에스퍼·땅·노말·얼음뿐이라
    /// `BattleEngine.resolveAttack` 의 "물·전기는 이 자리로 안 온다" 가 성립한다.
    private static let frozenCanFail: Set<String> = [
        "lowKick", "grassKnot",             // 격투 · 풀 (체중 미수신)
        "heavySlam", "heatCrash",           // 강철 · 불꽃 (체중 미수신)
        "counter", "mirrorCoat",            // 격투 · 에스퍼 (맞은 게 없음)
        "metalBurst",                       // 강철 (맞은 게 없음)
        "guillotine", "hornDrill",          // 노말 (레벨 우위)
        "fissure", "sheerCold",             // 땅 · 얼음 (레벨 우위)
    ]

    /// 위력을 상황에서 뽑는 기술. 오늘 전부 단발기라 `BattleEngine.resolveAttack` 의
    /// "가변위력과 다단기는 안 겹친다" 가 성립한다.
    private static let frozenVariablePower: Set<String> = [
        "electroBall", "gyroBall",
        "flail", "reversal",
        "wringOut", "crushGrip",
        "punishment",
        "lowKick", "grassKnot",
        "heavySlam", "heatCrash",
        "trumpCard",
        "magnitude",
    ]

    // MARK: 소스 스캔

    private var variableDamageSource: URL {
        URL(fileURLWithPath: #filePath)                 // Tests/PokeTokenBarTests/이 파일
            .deletingLastPathComponent()                // Tests/PokeTokenBarTests
            .deletingLastPathComponent()                // Tests
            .deletingLastPathComponent()                // 저장소 루트
            .appendingPathComponent("Sources/PokeTokenBar/Core/VariableDamage.swift")
    }

    /// `MoveID.<이름>` 의 이름만 뽑는다. 경계를 안 보면 나중에 `MoveID.lowKickAlt` 같은 이름이
    /// `lowKick` 으로 읽혀 새 기술이 동결 목록을 그냥 통과한다.
    private func moveIDLabels(in text: String) -> Set<String> {
        var labels: Set<String> = []
        var rest = Substring(text)
        while let found = rest.range(of: "MoveID.") {
            let tail = rest[found.upperBound...]
            let name = tail.prefix { $0.isLetter || $0.isNumber || $0 == "_" }
            if !name.isEmpty { labels.insert(String(name)) }
            rest = tail
        }
        return labels
    }

    /// `VariableDamage.from` 의 스위치를 `case` 단위로 쪼갠다.
    private func switchBlocks() throws -> [(labels: Set<String>, body: String)] {
        let lines = try String(contentsOf: variableDamageSource, encoding: .utf8)
            .components(separatedBy: .newlines)
        guard let start = lines.firstIndex(where: { $0.contains("switch move.id {") }),
              let end = lines[start...].firstIndex(where: { $0.contains("default: return nil") })
        else { return [] }

        var blocks: [(labels: Set<String>, body: String)] = []
        for line in lines[start..<end]
        where !line.trimmingCharacters(in: .whitespaces).hasPrefix("//") {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("case MoveID.") {
                blocks.append((labels: moveIDLabels(in: line), body: line))
            } else if !blocks.isEmpty {
                blocks[blocks.count - 1].body += "\n" + line
            }
        }
        return blocks
    }

    // MARK: 전제 동결

    func testMovesThatCanFailAreFrozen() throws {
        let blocks = try switchBlocks()
        // 파싱이 깨지면 빈 목록을 훑고 조용히 통과한다 — 그걸 막는 단언.
        XCTAssertGreaterThan(blocks.count, 15, "스위치를 못 읽었다 — 파싱이 깨지면 가드가 무력해진다")

        // 카운터·미러코트는 `.noEffect` 를 헬퍼에 위임한다. 토큰만 찾으면 그 둘을 놓친다.
        let canFail = blocks
            .filter { $0.body.contains(".noEffect") || $0.body.contains("counterDamage(") }
            .reduce(into: Set<String>()) { $0.formUnion($1.labels) }

        XCTAssertEqual(canFail, Self.frozenCanFail, """
            실패(`.noEffect`)를 낼 수 있는 기술이 바뀌었다. `resolveAttack` 은 실패와 면역을 \
            `effectiveness == 0` 하나로 합치므로, 새 기술이 **물·전기 타입이면 저수·전기흡수가 \
            실패한 기술에서 HP 를 회복한다.** 물·전기가 아니면 위 목록만 갱신하고, 맞으면 \
            `AttackOutcome` 에서 실패를 면역과 갈라라(0배 하나로는 구별할 수 없다). \
            차이: \(canFail.symmetricDifference(Self.frozenCanFail).sorted())
            """)
    }

    func testVariablePowerMovesAreFrozen() throws {
        let blocks = try switchBlocks()
        XCTAssertGreaterThan(blocks.count, 15, "스위치를 못 읽었다 — 파싱이 깨지면 가드가 무력해진다")

        let variablePower = blocks
            .filter { $0.body.contains(".power(") }
            .reduce(into: Set<String>()) { $0.formUnion($1.labels) }

        XCTAssertEqual(variablePower, Self.frozenVariablePower, """
            가변위력 기술이 바뀌었다. `resolveAttack` 은 위력을 다단기 루프 **안**에서 뽑으므로, \
            새 기술의 `maxHits` 가 1 보다 크면 히트마다 위력이 다시 뽑힌다. 단발기면 위 목록만 \
            갱신하고, 다단기면 뽑기를 루프 앞으로 올리고 `rulesVersion` 도 함께 올려라. \
            차이: \(variablePower.symmetricDifference(Self.frozenVariablePower).sorted())
            """)
    }

    // MARK: 와이어 천장 드리프트

    private func spec(power: Int, hits: Int? = nil) -> MoveSpec {
        var move = MoveSpec(id: 1, names: ["en": "Test"], type: .normal, power: power,
                            damageClass: .physical, accuracy: nil, pp: 20)
        move.minHits = hits
        move.maxHits = hits
        return move
    }

    /// 도감 쪽 검출과 와이어 쪽 반려가 갈라지면 경고가 거짓말을 한다 — 넘었다고 찍은 기술이 실제로는
    /// 통과하거나, 통과한다고 본 기술이 상대에게서 반려된다. 두 곳이 같은 상수를 보는지 잠근다.
    ///
    /// 다단기 경로를 쓴다. 위력이 큰 단발기로 보면 곱 규칙이 죽어 있어도 `(0...250).contains(power)`
    /// 가 대신 잡아 초록이 된다 — 트리거 브랜치를 안 밟는 테스트가 된다.
    func testDexCapDetectionAgreesWithPeerMoveValidation() {
        let overByHits = spec(power: 100, hits: 3)          // 300 > 250, 위력 축은 통과한다
        XCTAssertTrue(MultiplayerValidation.exceedsTurnDamageCap(overByHits))
        XCTAssertFalse(MultiplayerValidation.validMoves([overByHits]),
                       "천장을 넘는다고 본 기술은 와이어도 반려해야 한다")

        let icicleSpear = spec(power: 25, hits: 5)          // 125 — 도감에 실제로 있는 다단기
        XCTAssertFalse(MultiplayerValidation.exceedsTurnDamageCap(icicleSpear))
        XCTAssertTrue(MultiplayerValidation.validMoves([icicleSpear]),
                      "천장 안의 기술을 넘었다고 보면 정상 기술이 조용히 반려된다")

        let atCap = spec(power: MultiplayerValidation.turnDamageCap)
        XCTAssertFalse(MultiplayerValidation.exceedsTurnDamageCap(atCap), "천장 자체는 넘은 게 아니다")
        XCTAssertTrue(MultiplayerValidation.validMoves([atCap]))
    }
}
