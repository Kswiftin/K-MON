import XCTest
@testable import PokeTokenBar

/// 카테고리형 효과(날씨·필드·진영 상태)는 **데이터가 어느 기술인지 답하고 엔진은 효과만 구현한다.**
///
/// 회귀 원본: 세 카테고리가 각자 손으로 쓴 id 목록을 들고 있었다. 쇼다운이 같은 부류의 기술을
/// 하나 더 추가하면(한기의고동처럼 두 번째 눈 기술) 아무도 모르게 빠지고, 화면에는 "그 기술만
/// 아무 일도 안 한다"로 나타난다. 이 테스트는 데이터에 있는데 엔진이 모르는 키를 빨갛게 만든다.
final class ShowdownEffectTableTests: XCTestCase {

    /// 아직 구현하지 않은 자기 편 상태 — **왜 없는지**를 함께 잠근다. 구현하면 여기서 뺀다.
    /// 자기 편 상태는 지금 전부 구현했다. 새 키가 늘면 사유와 함께 여기 적는다 —
    /// 빈 집합이어도 **테스트는 남긴다**(다음 키가 조용히 지나가지 않게 하는 것이 이 목록의 일이다).
    private static let unmodeledAllySideConditions: Set<String> = []

    /// 아직 구현하지 않은 volatile — **왜 없는지**를 함께 잠근다. 구현하면 여기서 뺀다.
    /// 방어 부류 여덟 키(`protect`·`kingsshield` …)는 `BattleGuard` 가 이미 아니까 여기 없다.
    private static let unmodeledVolatiles: Set<String> = [
        // 기술 **선택**을 막는 부류 — 네 모드(1v1·모의전·웨이브·방)와 터미널 UI 까지 번진다.
        "disable", "encore", "taunt", "torment", "imprison", "healblock",
        // 맞은 데미지를 모아 두 배로 되돌려주는 부류 — 기술이 나가기 전에 턴을 잡아먹는 자리가 없다.
        "bide",
        // HP 대신 맞는 층(대타출동)이 없다 — 데미지·상태 경로 전부를 지나야 한다.
        "substitute",
        // 다인전 타겟 유도 — 대상을 고르는 자리가 방·웨이브에만 있다.
        "followme", "ragepowder", "spotlight", "helpinghand",
        // 랭크·급소·명중 배율을 한 줄씩 얹는 부류. 얹는 자리는 있고 아직 안 얹었다.
        "stockpile", "dragoncheer", "noretreat", "powertrick", "powershift",
        // 상성·접지·명중 규칙을 바꾸는 부류 — 상성표를 지나는 자리가 하나가 아니다.
        "foresight", "miracleeye", "smackdown", "telekinesis", "magnetrise", "tarshot",
        "electrify", "gastroacid", "embargo", "octolock",
        // 기술을 훔치거나 되돌리는 부류 — 기술이 나가기 **전에** 끼어드는 자리가 없다.
        "snatch", "magiccoat",
        // 나머지 턴 끝·행동 판정 부류. 잔뎀 자리는 열렸으니 다음 배치로 이어진다.
        "saltcure", "syrupbomb", "sparklingaria", "powder", "attract", "yawn",
    ]

    /// volatile 도 구현한 것과 **아직 아닌 것**으로만 갈린다 — 새 키가 늘면 어느 쪽인지 답해야 한다.
    /// 이 열거형이 없던 시절에는 데이터에 키가 있어도 그 기술이 턴만 태우고 아무 일도 하지 않았다.
    func testEveryVolatileIsEitherModelledOrKnowinglyMissing() {
        for (id, effect) in ShowdownMoveData.effects {
            guard let key = effect.volatileStatus else { continue }
            if BattleVolatile.called(byMoveID: id) != nil { continue }
            if BattleGuard.called(byMoveID: id) { continue }
            XCTAssertTrue(Self.unmodeledVolatiles.contains(key),
                          "volatile '\(key)'(기술 \(id))가 구현도 안 됐고 미구현 목록에도 없다")
        }
    }

    /// 미구현 목록에 **구현한 키가 남아 있지 않은지** 본다. 남으면 목록이 낡았다는 뜻이고,
    /// 낡은 목록은 다음에 붙일 것을 세는 데 쓸 수 없다.
    func testTheUnmodeledVolatileListHasNoStaleEntries() {
        for key in Self.unmodeledVolatiles {
            XCTAssertNil(BattleVolatile(showdownKey: key), "'\(key)' 는 이미 구현했다 — 목록에서 뺀다")
            XCTAssertFalse(BattleGuard.showdownKeys.contains(key), "'\(key)' 는 방어 부류가 이미 안다")
        }
    }

    /// 날씨를 부르는 기술은 **전부** 엔진이 안다. 하나라도 모르면 그 기술은 턴만 태운다.
    func testEveryWeatherMoveInTheDataReachesTheEngine() {
        for (id, effect) in ShowdownMoveData.effects {
            guard let key = effect.weather else { continue }
            XCTAssertNotNil(BattleWeather.called(byMoveID: id),
                            "쇼다운 날씨 '\(key)'(기술 \(id))를 엔진이 모른다")
        }
    }

    func testEveryTerrainMoveInTheDataReachesTheEngine() {
        for (id, effect) in ShowdownMoveData.effects {
            guard let key = effect.terrain else { continue }
            XCTAssertNotNil(BattleTerrain.called(byMoveID: id),
                            "쇼다운 필드 '\(key)'(기술 \(id))를 엔진이 모른다")
        }
    }

    /// 자기 편 상태는 구현한 것과 **아직 아닌 것**으로만 갈린다 — 새 키가 늘면 어느 쪽인지 답해야 한다.
    func testEveryAllySideConditionIsEitherModelledOrKnowinglyMissing() {
        for (id, effect) in ShowdownMoveData.effects {
            guard let key = effect.sideCondition, effect.sideConditionTarget != "foeSide" else { continue }
            if BattleSideCondition.called(byMoveID: id) != nil { continue }
            XCTAssertTrue(Self.unmodeledAllySideConditions.contains(key),
                          "자기 편 상태 '\(key)'(기술 \(id))가 구현도 안 됐고 미구현 목록에도 없다")
        }
    }

    /// **엔진이 고르는 편은 데이터가 말하는 편과 같다.** 편을 열거형에서 파생하면 데이터를 두 번
    /// 적는 셈이라, 쇼다운이 같은 상태를 양쪽에 까는 기술을 더하면 조용히 어긋난다 — 그 어긋남은
    /// 화면에 "장막을 상대에게 씌운다"로 나타난다.
    func testTheEngineLandsEachSideConditionOnTheSideTheDataNames() {
        var foeSide = 0, allySide = 0
        for (id, effect) in ShowdownMoveData.effects where effect.sideCondition != nil {
            guard BattleSideCondition.called(byMoveID: id) != nil else { continue }
            let target = try? XCTUnwrap(effect.sideConditionTarget,
                                        "'\(effect.sideCondition ?? "?")'(기술 \(id))에 편이 안 적혀 있다")
            XCTAssertEqual(BattleSideCondition.landsOnFoeSide(moveID: id), target == "foeSide",
                           "기술 \(id) 의 편을 엔진이 데이터와 다르게 읽는다")
            if target == "foeSide" { foeSide += 1 } else { allySide += 1 }
        }
        // 양쪽이 실제로 존재해야 이 테스트가 재는 것이 있다(한쪽만이면 "늘 자기 편" 으로 뒤집어도 통과한다).
        XCTAssertGreaterThan(foeSide, 0, "상대 편에 까는 기술이 하나도 안 잡혔다")
        XCTAssertGreaterThan(allySide, 0, "자기 편에 까는 기술이 하나도 안 잡혔다")
    }

    /// 입장 데미지 넷은 **전부** 엔진이 안다. 데이터에 있는데 모르면 그 기술은 턴만 태운다.
    func testEveryEntryHazardInTheDataReachesTheEngine() {
        let hazardKeys = Set(BattleSideCondition.allCases.filter(\.isEntryHazard).map(\.rawValue))
        XCTAssertEqual(hazardKeys.count, 4)
        for (id, effect) in ShowdownMoveData.effects {
            guard effect.sideConditionTarget == "foeSide", let key = effect.sideCondition else { continue }
            let condition = BattleSideCondition.called(byMoveID: id)
            XCTAssertNotNil(condition, "상대 편 상태 '\(key)'(기술 \(id))를 엔진이 모른다")
            XCTAssertEqual(condition?.isEntryHazard, true,
                           "'\(key)' 를 밟는 부류로 안 세면 교체가 그것을 지나친다")
        }
    }

    /// 엔진이 아는 상태는 **하나씩 실제 기술이 있다.** 열거형에만 있고 부르는 기술이 없으면
    /// 아무도 못 쓰는 코드다.
    func testEveryModelledSideConditionHasAMoveThatCallsIt() {
        for condition in BattleSideCondition.allCases {
            XCTAssertTrue(ShowdownMoveData.effects.keys.contains {
                BattleSideCondition.called(byMoveID: $0) == condition
            }, "\(condition) 를 부르는 기술이 데이터에 없다")
        }
    }

    /// 같은 효과를 여러 기술이 부를 수 있다 — 눈이 그렇다(눈날림·싸라기눈·한기의고동).
    /// 손 목록 시절 실제로 빠뜨린 자리라 그대로 잠근다.
    func testSeveralMovesCanCallTheSameWeather() {
        let snowMoves = ShowdownMoveData.effects.keys.filter { BattleWeather.called(byMoveID: $0) == .snow }
        XCTAssertGreaterThanOrEqual(snowMoves.count, 3,
                                    "눈은 기술 여럿이 부른다 — 하나만 잡히면 목록 방식으로 되돌아간 것이다")
    }
}
