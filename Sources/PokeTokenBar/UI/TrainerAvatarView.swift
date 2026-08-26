import SwiftUI

/// 친구 목록 한 줄에 그리는 착장 아바타. `TrainerSprite` 합성은 착장이 바뀔 때만 다시 하고
/// `@State` 에 캐시한다 — 목록이 다시 그려질 때마다 합성하면 여러 피어 행이 매 프레임 합성한다.
struct TrainerAvatarView: View {
    let outfit: TrainerOutfit
    var facing: Facing = .down
    var scale: CGFloat = 2

    @State private var cgImage: CGImage?

    var body: some View {
        Group {
            if let cgImage {
                Image(decorative: cgImage, scale: 1)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 16 * scale, height: 24 * scale)
            } else {
                Color.clear.frame(width: 16 * scale, height: 24 * scale)
            }
        }
        .onAppear { rebuild() }
        .onChange(of: outfit) { rebuild() }
    }

    private func rebuild() {
        // 친구 목록 행마다 이 뷰가 새로 생기니, 12프레임을 다 만드는 `TrainerSprite(outfit:)` 대신
        // 필요한 한 프레임만 직접 합성한다.
        cgImage = TrainerSprite.compose(outfit: outfit, facing: facing, step: 0)
            .cgImage(palette: TrainerPixelArt.palette)
    }
}
