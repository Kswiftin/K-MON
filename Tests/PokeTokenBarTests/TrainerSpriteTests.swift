import XCTest
@testable import PokeTokenBar

final class TrainerSpriteTests: XCTestCase {
    func testBodyFramesHaveTheTrainerSizeAndAreOpaqueSomewhere() {
        for facing in Facing.allCases {
            for step in 0..<3 {
                let s = TrainerPixelArt.body(facing, step: step)
                XCTAssertEqual(s.width, 16); XCTAssertEqual(s.height, 24)
                XCTAssertGreaterThan(s.opaqueCount, 60, "\(facing) \(step) 몸통이 비어 있다")
            }
        }
    }

    func testWalkStepsDifferFromStanding() {
        for facing in Facing.allCases {
            XCTAssertNotEqual(TrainerPixelArt.body(facing, step: 0), TrainerPixelArt.body(facing, step: 1), "\(facing)")
            XCTAssertNotEqual(TrainerPixelArt.body(facing, step: 1), TrainerPixelArt.body(facing, step: 2), "\(facing)")
        }
    }

    func testRightIsTheMirrorOfLeft() {
        XCTAssertEqual(TrainerPixelArt.body(.right, step: 1), TrainerPixelArt.body(.left, step: 1).flippedHorizontally())
    }

    func testEveryItemLayerFitsAndDrawsSomething() {
        for item in OutfitItem.allCases {
            for facing in Facing.allCases {
                for step in 0..<3 {
                    let layer = TrainerPixelArt.layer(item, facing: facing, step: step)
                    XCTAssertEqual(layer.width, 16); XCTAssertEqual(layer.height, 24)
                    XCTAssertGreaterThan(layer.opaqueCount, 0, "\(item) \(facing) \(step) 레이어가 비었다")
                }
            }
        }
    }

    func testHatCoversHairWhereTheyOverlap() {
        let outfit = TrainerOutfit(worn: [.hair: .hairPony, .hat: .capRed])
        let composed = TrainerSprite.compose(outfit: outfit, facing: .down, step: 0)
        let hat = TrainerPixelArt.layer(.capRed, facing: .down, step: 0)
        for y in 0..<24 { for x in 0..<16 where hat.pixel(x: x, y: y) != 0 {
            XCTAssertEqual(composed.pixel(x: x, y: y), hat.pixel(x: x, y: y), "(\(x),\(y)) 모자 위로 머리카락이 보인다")
        } }
    }

    func testComposeWithAllShopItemsStillHasSkinVisible() {
        let outfit = TrainerOutfit(worn: [.hat: .capRed, .hair: .hairBob, .top: .jacketBlue, .bottom: .shortsKhaki, .accessory: .backpack])
        let s = TrainerSprite.compose(outfit: outfit, facing: .down, step: 0)
        XCTAssertTrue(s.pixels.contains(2), "얼굴이 전부 가려졌다")
    }

    func testSpriteCachesTwelveFrames() {
        let sprite = TrainerSprite(outfit: TrainerOutfit())
        XCTAssertEqual(sprite.frames.count, 12)
        XCTAssertEqual(sprite.frame(.left, step: 2), TrainerPixelArt.body(.left, step: 2))
    }

    func testAllFramesBakeToImages() {
        let sprite = TrainerSprite(outfit: TrainerOutfit(worn: [.top: .cloakWorn]))
        for frame in sprite.frames { XCTAssertNotNil(frame.cgImage(palette: TrainerPixelArt.palette)) }
    }
}
