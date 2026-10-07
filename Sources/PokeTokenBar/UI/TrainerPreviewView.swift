import SwiftUI

struct TrainerPreviewState {
    var facing: Facing = .down
    var isWalking = false
    private(set) var isVisible = false
    var isAnimating: Bool { isVisible && isWalking }
    mutating func show() { isVisible = true; isWalking = false }
    mutating func hide() { isVisible = false }
    mutating func rotate(_ delta: Int) {
        let all = Facing.allCases
        let index = all.firstIndex(of: facing) ?? 0
        facing = all[(index + delta % all.count + all.count) % all.count]
    }
    func step(at date: Date) -> Int {
        guard isAnimating else { return 0 }
        let tick = Int(floor(date.timeIntervalSinceReferenceDate / 0.25))
        return [0, 1, 0, 2][((tick % 4) + 4) % 4]
    }
}

struct TrainerPreviewView: View {
    let outfit: TrainerOutfit
    var scale: CGFloat = 4
    @State private var preview = TrainerPreviewState()
    @State private var frames: [Facing: [CGImage]] = [:]

    var body: some View {
        VStack(spacing: 8) {
            TimelineView(.animation(minimumInterval: 0.25, paused: !preview.isAnimating)) { context in
                let step = preview.step(at: context.date)
                let images = frames[preview.facing] ?? []
                if images.indices.contains(step) {
                    Image(decorative: images[step], scale: 1).resizable().interpolation(.none)
                        .frame(width: 16 * scale, height: 24 * scale)
                } else {
                    Color.clear.frame(width: 16 * scale, height: 24 * scale)
                }
            }
            HStack(spacing: 22) {
                Button { preview.rotate(-1) } label: { Image(systemName: "chevron.left") }
                    .accessibilityLabel("왼쪽으로 돌리기")
                Button(preview.isWalking ? "정지" : "걷기") { preview.isWalking.toggle() }
                Button { preview.rotate(1) } label: { Image(systemName: "chevron.right") }
                    .accessibilityLabel("오른쪽으로 돌리기")
            }.buttonStyle(.borderless)
        }
        .padding(12).frame(maxWidth: .infinity)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
        .onAppear { preview.show(); rebuildFrames() }
        .onDisappear { preview.hide() }
        .onChange(of: outfit) { rebuildFrames() }
    }

    private func rebuildFrames() {
        let sprite = TrainerSprite(outfit: outfit)
        frames = Dictionary(uniqueKeysWithValues: Facing.allCases.map { facing in
            (facing, (0...2).compactMap { sprite.frame(facing, step: $0).cgImage(palette: TrainerPixelArt.palette) })
        })
    }
}
