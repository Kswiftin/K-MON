import AppKit
import SwiftUI

/// 방 진입 연출 상태 — `DungeonView` 가 도착 이벤트로 만들고 `duration` 뒤에 지운다.
/// 값 하나로 묶는 이유는 연출 중 입력 잠금·타임라인 재생 여부가 모두 "연출이 있나"로 갈리기 때문이다.
struct RoomPresentation: Equatable {
    enum Kind: Equatable {
        case encounter(species: Int, damage: Int)
        case heal(Int)
        case springDry
        case loot(Int)
        case cacheEmpty
        case boss(species: Int, damage: Int, felled: Bool)
        case collapsed
    }

    let kind: Kind
    let startedAt: Date
    static let duration: TimeInterval = 0.8

    /// 스프라이트를 미리 받아 둘 종. 없으면 그림 없이 숫자만 뜬다.
    var species: Int? {
        switch kind {
        case .encounter(let species, _), .boss(let species, _, _): return species
        default: return nil
        }
    }
}

/// 트레이너 12프레임(4방향 × 3)을 구운 결과. 착장이 바뀔 때만 만든다 — 캔버스가 초당 60번
/// 그리므로 프레임마다 합성하면 그것만으로 CPU 가 눌린다(설계 "게임루프와 에너지").
struct TrainerFrameCache {
    private let images: [CGImage?]

    init(outfit: TrainerOutfit) {
        let sprite = TrainerSprite(outfit: outfit)
        images = Facing.allCases.flatMap { facing in
            (0..<3).map { sprite.frame(facing, step: $0).cgImage(palette: TrainerPixelArt.palette) }
        }
    }

    func image(_ facing: Facing, step: Int) -> CGImage? {
        let facingIndex = Facing.allCases.firstIndex(of: facing) ?? 0
        return images[facingIndex * 3 + min(max(step, 0), 2)]
    }
}

/// 방 하나를 그리는 캔버스. 게임루프도 여기 있다 — `walker` 가 멈춰 있고 연출도 없으면
/// `TimelineView` 가 **정지**한다(던전 탭을 열어 둔 채 방치해도 60fps 로 돌지 않는다).
///
/// 상태를 갖지 않는다. 걷기 상태는 `DungeonView` 의 `@State` 에 있고 여기는 `onTick` 으로
/// 시각만 넘긴다 — 뷰 본문 평가 중에 상태를 바꾸지 않기 위해서다.
struct RoomCanvas: View {
    /// 칸 크기(pt). 16px 타일의 1.5배라 정수배가 아니어서 `interpolation(.none)` 이 필수다.
    static let cell: CGFloat = 24
    static let width = CGFloat(DungeonRoomLayout.columns) * cell
    static let height = CGFloat(DungeonRoomLayout.rows) * cell

    let walker: DungeonWalker
    let frames: TrainerFrameCache
    let presentation: RoomPresentation?
    let onDoorTap: (RoomDoor) -> Void
    let onTick: (Date) -> Void

    /// 연출에 쓰는 포켓몬 스프라이트. 없으면 숫자만 뜬다(그림 때문에 연출이 멈추지 않는다).
    @State private var actorImages: [Int: NSImage] = [:]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: walker.isIdle && presentation == nil)) { context in
            Canvas { ctx, _ in draw(&ctx, now: context.date) }
                .onChange(of: context.date) { _, date in onTick(date) }
        }
        .frame(width: Self.width, height: Self.height)
        .contentShape(Rectangle())
        .onTapGesture { location in
            let point = GridPoint(x: Int(location.x / Self.cell), y: Int(location.y / Self.cell))
            guard let door = walker.layout.door(at: point) else { return }
            onDoorTap(door)
        }
        .task(id: presentation) { await loadActor() }
    }

    private func loadActor() async {
        guard let species = presentation?.species, actorImages[species] == nil else { return }
        guard let image = await SpriteLoader.image(speciesID: species) else { return }
        // 연출은 한 번에 하나뿐이다 — 방을 지날 때마다 쌓아 두면 판이 길어질수록 메모리만 먹는다
        // (원본 캐시는 `SpriteLoader` 가 LRU 로 들고 있어 되돌아가도 네트워크를 다시 타지 않는다).
        actorImages = [species: image]
    }

    // MARK: 그리기

    private func draw(_ ctx: inout GraphicsContext, now: Date) {
        let layout = walker.layout
        drawTiles(&ctx, layout)
        drawDecor(&ctx, layout)
        drawFeature(&ctx, layout)
        drawDoorLabels(&ctx, layout)
        drawPresentation(&ctx, now: now)
        drawTrainer(&ctx)
    }

    private func drawTiles(_ ctx: inout GraphicsContext, _ layout: DungeonRoomLayout) {
        let wall: RoomTile = layout.isHome ? .wallHome : .wall
        let floor: RoomTile = layout.isHome ? .floorHome : .floor
        for y in 0..<DungeonRoomLayout.rows {
            for x in 0..<DungeonRoomLayout.columns {
                let point = GridPoint(x: x, y: y)
                if layout.door(at: point) != nil {
                    draw(&ctx, wall, at: point)
                    draw(&ctx, .doorOpen, at: point)
                } else {
                    draw(&ctx, layout.isWall(point) ? wall : floor, at: point)
                }
            }
        }
    }

    private func drawDecor(_ ctx: inout GraphicsContext, _ layout: DungeonRoomLayout) {
        for (point, decor) in layout.decor {
            guard let tile = RoomTile(decor: decor) else { continue }
            draw(&ctx, tile, at: point)
        }
    }

    /// 방의 정체를 방 가운데 타일 하나로 보여 준다 — 로그를 안 읽어도 여기가 샘인지 보물방인지 보인다.
    private func drawFeature(_ ctx: inout GraphicsContext, _ layout: DungeonRoomLayout) {
        let room = walker.run.map.room(layout.room)
        let tile: RoomTile?
        switch room.kind {
        case .spring: tile = .spring
        case .cache: tile = walker.run.looted.contains(room.id) ? .chestOpen : .chest
        case .boss: tile = .stairsBoss
        case .empty, .encounter: tile = nil
        }
        guard let tile else { return }
        draw(&ctx, tile, at: Self.featureCell)
    }

    /// 문마다 통로 비용 숫자, 그리고 밝혀진 방이면 정체 글리프. 글리프는 언어와 무관한 기호라
    /// 로컬라이즈 자산이 아니라 코드에 둔다.
    private func drawDoorLabels(_ ctx: inout GraphicsContext, _ layout: DungeonRoomLayout) {
        for door in layout.doors {
            ctx.draw(Text("\(door.cost)").font(.system(size: 8, weight: .bold)).foregroundStyle(.white),
                     at: center(of: door.cell))
            guard let kind = walker.run.revealed[door.target], let glyph = Self.glyph(for: kind) else { continue }
            ctx.draw(Text(glyph).font(.system(size: 11)).foregroundStyle(.white),
                     at: center(of: Self.interiorCell(of: door)))
        }
    }

    private func drawPresentation(_ ctx: inout GraphicsContext, now: Date) {
        guard let presentation else { return }
        let elapsed = now.timeIntervalSince(presentation.startedAt)
        let progress = min(max(elapsed / RoomPresentation.duration, 0), 1)
        let middle = CGPoint(x: Self.width / 2, y: Self.height / 2)

        switch presentation.kind {
        case .encounter(let species, let damage):
            drawActor(&ctx, species: species, side: 48, at: middle)
            drawRising(&ctx, "-\(damage)", color: .red, from: middle, progress: progress)
        case .boss(let species, let damage, let felled):
            drawActor(&ctx, species: species, side: 64, at: middle)
            drawRising(&ctx, felled ? "-\(damage) ★" : "-\(damage)", color: .red, from: middle, progress: progress)
        case .heal(let amount):
            let spring = center(of: Self.featureCell)
            drawSparkles(&ctx, around: spring, progress: progress)
            drawRising(&ctx, "+\(amount)", color: .green, from: spring, progress: progress)
        case .springDry:
            ctx.draw(Text("♨").font(.system(size: 20)).foregroundStyle(.secondary), at: middle)
        case .loot(let starPieces):
            drawRising(&ctx, "+\(starPieces) ⭐", color: .yellow, from: middle, progress: progress)
        case .cacheEmpty:
            ctx.draw(Text("▣").font(.system(size: 20)).foregroundStyle(.secondary), at: middle)
        case .collapsed:
            break
        }
    }

    private func drawActor(_ ctx: inout GraphicsContext, species: Int, side: CGFloat, at point: CGPoint) {
        guard let image = actorImages[species] else { return }
        let rect = CGRect(x: point.x - side / 2, y: point.y - side, width: side, height: side)
        // 포켓몬 스프라이트도 도트다 — 보간을 켜면 이 그림만 흐릿해 화면에서 혼자 튄다.
        ctx.draw(Image(nsImage: image).interpolation(.none), in: rect)
    }

    /// 데미지·보상 숫자는 연출 동안 12pt 떠오르며 흐려진다 — 숫자가 제자리에 있으면 뭐가 바뀐 건지 안 읽힌다.
    private func drawRising(_ ctx: inout GraphicsContext, _ label: String, color: Color,
                            from point: CGPoint, progress: Double) {
        var ctx = ctx
        ctx.opacity = 1 - progress * 0.6
        ctx.draw(Text(label).font(.system(size: 13, weight: .bold)).foregroundStyle(color),
                 at: CGPoint(x: point.x, y: point.y - 12 * progress))
    }

    /// 회복 반짝임 — 샘 타일을 도는 흰 사각형 넷.
    private func drawSparkles(_ ctx: inout GraphicsContext, around point: CGPoint, progress: Double) {
        let radius = 14.0
        for index in 0..<4 {
            let angle = progress * 2 * .pi + Double(index) * .pi / 2
            let dot = CGRect(x: point.x + cos(angle) * radius - 1.5,
                             y: point.y + sin(angle) * radius - 1.5, width: 3, height: 3)
            ctx.fill(Path(dot), with: .color(.white))
        }
    }

    private func drawTrainer(_ ctx: inout GraphicsContext) {
        let collapsed = presentation?.kind == .collapsed
        let facing: Facing = collapsed ? .down : walker.facing
        guard let image = frames.image(facing, step: collapsed ? 0 : walker.animationStep) else { return }
        let position = walker.visualPosition
        // 발이 칸 바닥에 붙게 아래로 정렬한다 — 16×24px 을 24×36pt(1.5배)로 그리므로 칸(24pt)보다 높다.
        let rect = CGRect(x: position.x * Self.cell, y: position.y * Self.cell + Self.cell - 36,
                          width: 24, height: 36)
        var ctx = ctx
        if collapsed { ctx.opacity = 0.5 }
        ctx.draw(Image(decorative: image, scale: 1).interpolation(.none), in: rect)
    }

    // MARK: 좌표

    /// 방 정체 타일이 앉는 칸 — 가운데.
    static let featureCell = GridPoint(x: DungeonRoomLayout.columns / 2, y: DungeonRoomLayout.rows / 2)

    private func draw(_ ctx: inout GraphicsContext, _ tile: RoomTile, at point: GridPoint) {
        guard let image = RoomTileArt.image(tile) else { return }
        ctx.draw(Image(decorative: image, scale: 1).interpolation(.none), in: cellRect(point))
    }

    private func cellRect(_ point: GridPoint) -> CGRect {
        CGRect(x: CGFloat(point.x) * Self.cell, y: CGFloat(point.y) * Self.cell,
               width: Self.cell, height: Self.cell)
    }

    private func center(of point: GridPoint) -> CGPoint {
        CGPoint(x: (CGFloat(point.x) + 0.5) * Self.cell, y: (CGFloat(point.y) + 0.5) * Self.cell)
    }

    /// 문 바로 안쪽 칸 — 글리프를 문 위에 겹치지 않게 여기 놓는다.
    private static func interiorCell(of door: RoomDoor) -> GridPoint {
        switch door.side {
        case .east: return GridPoint(x: door.cell.x - 1, y: door.cell.y)
        case .west: return GridPoint(x: door.cell.x + 1, y: door.cell.y)
        case .north: return GridPoint(x: door.cell.x, y: door.cell.y + 1)
        case .south: return GridPoint(x: door.cell.x, y: door.cell.y - 1)
        }
    }

    private static func glyph(for kind: RoomKind) -> String? {
        switch kind {
        case .spring: return "♨"
        case .cache: return "▣"
        case .encounter: return "⚔"
        case .boss: return "★"
        case .empty: return nil
        }
    }
}
