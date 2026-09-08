import XCTest
@testable import PokeTokenBar

/// 플레이트 17종 — 그 타입 기술의 위력을 1.2 배로 만든다. 효과는 타입 강화 도구(`typeBoost`)와
/// **같다**: 아르세우스의 폼체인지가 이 엔진에 없어서 플레이트에 남는 일이 배율뿐이다.
///
/// 그래서 여기서 잠그는 것은 새 규칙이 아니라 **표의 정합**이다: 17종이 노말을 뺀 17타입에
/// 하나씩 붙고, 강철 자리가 드디어 채워졌다는 사실(금속코트가 진화 아이템이라 비어 있던 자리다).
@MainActor
final class PlateTests: XCTestCase {

    private static let plates: [ItemKind] = [
        .flamePlate, .splashPlate, .zapPlate, .meadowPlate, .iciclePlate, .fistPlate,
        .toxicPlate, .earthPlate, .skyPlate, .mindPlate, .insectPlate, .stonePlate,
        .spookyPlate, .dracoPlate, .dreadPlate, .ironPlate, .pixiePlate
    ]

    /// 17종이 전부 지닌물건 갈래를 타고 상점·스프라이트·문구를 갖춘다.
    func testThePlatesRideTheHeldItemAxis() {
        for kind in Self.plates {
            XCTAssertEqual(kind.bagUse, .heldItem, kind.rawValue)
            XCTAssertNotNil(kind.heldBattleEffect, "\(kind.rawValue) 가 배틀에서 하는 일이 없다")
            XCTAssertNil(kind.evolutionRule, kind.rawValue)
            XCTAssertNotNil(kind.shopPrice, kind.rawValue)
            XCTAssertNotNil(kind.spriteName, kind.rawValue)
            XCTAssertTrue(MultiplayerValidation.validHeldItem(kind), "피어의 \(kind.rawValue) 가 반려된다")
            XCTAssertFalse(L().itemName(kind).isEmpty, kind.rawValue)
            XCTAssertFalse(L().itemDescription(kind).isEmpty, kind.rawValue)
        }
        XCTAssertEqual(ItemKind.flamePlate.spriteName, "flame-plate")
        XCTAssertEqual(L().itemName(.flamePlate), "불구슬플레이트")
    }

    /// **노말을 뺀 17타입에 하나씩**이다 — 노말 플레이트는 본가에도 없다(아르세우스의 기본형).
    func testThePlatesCoverEveryTypeButNormal() {
        let types = Self.plates.compactMap { $0.heldBattleEffect?.boostedMoveType }
        XCTAssertEqual(types.count, Self.plates.count)
        XCTAssertEqual(Set(types), Set(PokemonType.allCases).subtracting([.normal]))
    }

    /// 강철 자리가 채워졌다 — 금속코트가 진화 아이템이라 타입 강화 도구에서 비어 있던 칸이다.
    func testTheIronPlateFillsTheEmptySteelSlot() {
        XCTAssertEqual(ItemKind.ironPlate.heldBattleEffect, .typeBoost(.steel))
        XCTAssertNil(ItemKind.allCases.first { $0.typeEnhancedType == .steel },
                     "강철 강화 도구가 생겼으면 금속코트 예외를 다시 본다")
    }

    /// 효과가 타입 강화 도구와 **같은 값**이다 — 같은 일을 하는 두 물건이 다른 갈래를 만들면
    /// 데미지 자리가 둘 다 물어야 하고, 한쪽만 물으면 그 물건만 조용히 아무 일도 안 한다.
    func testAPlateSharesTheTypeEnhancerEffect() {
        XCTAssertEqual(ItemKind.flamePlate.heldBattleEffect, ItemKind.charcoal.heldBattleEffect)
        XCTAssertEqual(ItemKind.splashPlate.heldBattleEffect, ItemKind.mysticWater.heldBattleEffect)
    }
}
