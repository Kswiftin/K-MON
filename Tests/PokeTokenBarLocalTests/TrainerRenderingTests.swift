import Foundation
import Testing
@testable import PokeTokenBar

@Suite("트레이너 외형과 염색 도트")
struct TrainerRenderingTests {
    @Test(arguments: OutfitItem.allCases, Facing.allCases)
    func allItemsRender(item: OutfitItem, facing: Facing) {
        let trainer = TrainerSprite(outfit: TrainerOutfit(worn: [item.slot: item]))
        #expect(trainer.frames.count == 12)
        for step in 0...2 {
            let frame = trainer.frame(facing, step: step)
            #expect(frame.width == 16 && frame.height == 24)
            #expect(frame.opaqueCount > 0)
            #expect(frame.pixels.allSatisfy { Int($0) < TrainerPixelArt.palette.colors.count })
            #expect(TrainerSprite.image(outfit: TrainerOutfit(worn: [item.slot: item]), facing: facing, step: step) != nil)
        }
    }

    @Test func defaultOutfitKeepsLegacyPixels() {
        let old: [OutfitItem] = [.capRed, .strawHat, .hairBob, .hairPony, .jacketBlue, .teeWhite,
            .shortsKhaki, .backpack, .hairMessy, .cloakWorn, .bootsLong, .helmetExplorer]
        for item in old {
            for facing in Facing.allCases {
                for step in 0...2 {
                    let expected = TrainerPixelArt.body(facing, step: step).overlaying(TrainerPixelArt.layer(item, facing: facing, step: step))
                    #expect(TrainerSprite.compose(outfit: TrainerOutfit(worn: [item.slot: item]), facing: facing, step: step) == expected)
                }
            }
        }
    }

    @Test(arguments: TrainerSkinTone.allCases, TrainerHairColor.allCases)
    func skinAndHairApplyIndependently(skin: TrainerSkinTone, hair: TrainerHairColor) {
        let appearance = TrainerAppearance(baseHair: .short, skinTone: skin, hairColor: hair)
        let frame = TrainerSprite.compose(outfit: TrainerOutfit(appearance: appearance), facing: .down, step: 0)
        let skinRGB: [UInt32] = [0xFFE0C5, 0xF3C9A6, 0xC98E60, 0x85563D]
        let hairRGB: [UInt32] = [0x5A3A2A, 0x343440, 0xE3C55A, 0xA65338, 0xCECEDB, 0x3B6ED8]
        #expect(TrainerPixelArt.palette.colors[Int(frame.pixel(x: 7, y: 7))] == skinRGB[TrainerSkinTone.allCases.firstIndex(of: skin)!])
        #expect(TrainerPixelArt.palette.colors[Int(frame.pixel(x: 7, y: 3))] == hairRGB[TrainerHairColor.allCases.firstIndex(of: hair)!])
        #expect(frame.pixel(x: 6, y: 6) == 1)
        #expect(frame.pixel(x: 4, y: 23) == 1)
    }

    @Test func outfitHairReplacesBaseHairAndHatCoversIt() {
        let short = TrainerOutfit(worn: [.hair: .hairBob], appearance: TrainerAppearance(baseHair: .short))
        let curly = TrainerOutfit(worn: [.hair: .hairBob], appearance: TrainerAppearance(baseHair: .curly))
        #expect(TrainerSprite.compose(outfit: short, facing: .down, step: 0) == TrainerSprite.compose(outfit: curly, facing: .down, step: 0))
        let capped = TrainerOutfit(worn: [.hat: .capRed], appearance: .creationDefault)
        #expect(TrainerSprite.compose(outfit: capped, facing: .down, step: 0).pixel(x: 7, y: 3) == 7)
        let bare = TrainerSprite.compose(outfit: TrainerOutfit(), facing: .down, step: 0)
        #expect(TrainerSprite.compose(outfit: TrainerOutfit(appearance: .creationDefault), facing: .down, step: 0) != bare)
        #expect(TrainerSprite.compose(outfit: TrainerOutfit(appearance: TrainerAppearance(baseHair: .curly)), facing: .down, step: 0) != bare)
    }

    @Test func tintDoesNotChangeSkinOrOtherSlots() {
        let plain = TrainerOutfit(worn: [.hat: .capRed, .top: .jacketBlue])
        var pink = plain
        pink.tints = [.hat: .pink]
        let a = TrainerSprite.compose(outfit: plain, facing: .down, step: 0)
        let b = TrainerSprite.compose(outfit: pink, facing: .down, step: 0)
        #expect(a != b)
        #expect(TrainerPixelArt.palette.colors[Int(b.pixel(x: 7, y: 2))] == 0xE988B0)
        for y in 6..<24 {
            for x in 0..<16 { #expect(a.pixel(x: x, y: y) == b.pixel(x: x, y: y)) }
        }
    }

    @Test(arguments: OutfitItem.allCases.filter { $0.slot != .hair }, OutfitTint.allCases)
    func everyTintChangesOnlyItsLayer(item: OutfitItem, tint: OutfitTint) {
        let raw = TrainerPixelArt.layer(item, facing: .down, step: 0)
        let dyed = TrainerPixelArt.applyingTint(tint, to: raw, item: item)
        #expect(raw != dyed)
        for i in raw.pixels.indices where [UInt8(0), 1, 2, 3, 4, 5].contains(raw.pixels[i]) {
            #expect(raw.pixels[i] == dyed.pixels[i])
        }
        #expect(dyed.pixels.allSatisfy { Int($0) < TrainerPixelArt.palette.colors.count })
        let outfit = TrainerOutfit(worn: [item.slot: item], tints: [item.slot: tint])
        for facing in Facing.allCases {
            for step in 0...2 { #expect(TrainerSprite.image(outfit: outfit, facing: facing, step: step) != nil) }
        }
    }

    @Test func stripesAndShadingRemainVisible() {
        let layer = TrainerPixelArt.layer(.stripedTee, facing: .down, step: 0)
        let dyed = TrainerPixelArt.applyingTint(.pink, to: layer, item: .stripedTee)
        #expect(layer.pixels.contains(6))
        for i in layer.pixels.indices where layer.pixels[i] == 6 { #expect(dyed.pixels[i] == 6) }
        let hoodie = TrainerPixelArt.applyingTint(.yellow, to: TrainerPixelArt.layer(.hoodie, facing: .down, step: 0), item: .hoodie)
        let colors = Set(hoodie.pixels.filter { $0 != 0 }.map { TrainerPixelArt.palette.colors[Int($0)] })
        #expect(colors.contains(0xE3C55A))
        #expect(colors.contains(0xA58A34))
    }

    @Test func rightIsMirroredAndStepsClamp() {
        let outfit = TrainerOutfit(worn: [.accessory: .crossbodyBag], appearance: .creationDefault, tints: [.accessory: .purple])
        let sprite = TrainerSprite(outfit: outfit)
        #expect(sprite.frame(.right, step: 1) == sprite.frame(.left, step: 1).flippedHorizontally())
        #expect(sprite.frame(.down, step: -1) == sprite.frame(.down, step: 0))
        #expect(sprite.frame(.up, step: 9) == sprite.frame(.up, step: 2))
    }
}
