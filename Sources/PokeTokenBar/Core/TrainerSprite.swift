import Foundation
import CoreGraphics

enum Facing: CaseIterable, Sendable, Codable { case down, up, left, right }

/// base + 착용 레이어를 `OutfitSlot.allCases` 순서로 얹는다. 착용이 바뀔 때만 만든다 —
/// 매 프레임 합성 금지(설계 "게임루프와 에너지").
struct TrainerSprite: Sendable {
    let frames: [PixelSprite]

    init(outfit: TrainerOutfit) {
        frames = Facing.allCases.flatMap { facing in
            (0..<3).map { Self.compose(outfit: outfit, facing: facing, step: $0) }
        }
    }

    func frame(_ facing: Facing, step: Int) -> PixelSprite {
        // `TrainerFrameCache.image` 처럼 범위를 벗어난 step 을 클램프한다 — 트랩 대신
        // 가장 가까운 유효 프레임을 돌려줘야 애니메이션 타이밍 계산이 살짝 어긋나도 크래시하지 않는다.
        let clampedStep = min(max(step, 0), 2)
        return frames[Facing.allCases.firstIndex(of: facing)! * 3 + clampedStep]
    }

    static func image(outfit: TrainerOutfit, facing: Facing, step: Int) -> CGImage? {
        compose(outfit: outfit, facing: facing, step: step).cgImage(palette: TrainerPixelArt.palette)
    }

    static func compose(outfit: TrainerOutfit, facing: Facing, step: Int) -> PixelSprite {
        let step = min(max(step, 0), 2)
        var out = TrainerPixelArt.applyingSkin(outfit.appearance.skinTone, to: TrainerPixelArt.body(facing, step: step))
        out = TrainerPixelArt.applyingHair(outfit.appearance.hairColor, to: out)
        for slot in OutfitSlot.allCases {
            if let item = outfit.worn[slot] {
                var layer = TrainerPixelArt.layer(item, facing: facing, step: step)
                if slot == .hair { layer = TrainerPixelArt.applyingHair(outfit.appearance.hairColor, to: layer) }
                else if let tint = outfit.tints[slot] { layer = TrainerPixelArt.applyingTint(tint, to: layer, item: item) }
                out = out.overlaying(layer)
            } else if slot == .hair {
                let hair = TrainerPixelArt.baseHair(outfit.appearance.baseHair, facing: facing, step: step)
                out = out.overlaying(TrainerPixelArt.applyingHair(outfit.appearance.hairColor, to: hair))
            }
        }
        return out
    }
}
