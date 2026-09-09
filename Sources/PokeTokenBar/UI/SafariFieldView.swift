import SwiftUI

/// 사파리존 걷기 화면 — `Canvas` + `TimelineView` 로 벌판과 트레이너를 그린다.
/// `room-walk-dungeon-design.md` 의 `RoomCanvas` 설계에서 문·방 로직만 뺀 것.
struct SafariFieldView: View {
    @Bindable var store: CompanionStore
    @State private var heldKeys: Set<SafariDirectionKey> = []
    /// 착용이 바뀔 때만 다시 굽는다(`TrainerAvatarView` 와 같은 이유) — 매 프레임 합성 금지.
    @State private var trainerImages: [Facing: [CGImage]] = [:]
    /// 존이 바뀔 때만 다시 굽는다 — 타일 자체는 `SafariFieldPixelArt.tiles(for:)` 2종뿐이다.
    @State private var tileImages: [CGImage] = []
    /// 칸(y행 우선)마다 어느 타일을 쓸지 — 존이 바뀔 때 한 번만 결정론으로 계산해 고정한다.
    /// 매 프레임 다시 고르면 같은 칸이 프레임마다 다른 타일로 깜빡인다.
    @State private var tilePlan: [Int] = []
    /// 장애물(나무·물웅덩이·바위) 이미지 — 존마다 한 장뿐이라 타일처럼 배치표가 필요 없다.
    @State private var obstacleImage: CGImage?
    @State private var lastTickDate: Date?
    @State private var isVisible = true

    private var l: L { store.l }
    private static let cellSize: CGFloat = 24
    private static let bounds = SafariFieldBounds.standard

    /// 표준 quad ease-in-out — 0→0.5 구간은 가속, 0.5→1 구간은 감속한다.
    private static func easeInOut(_ progress: Double) -> Double {
        progress < 0.5 ? 2 * progress * progress : 1 - pow(-2 * progress + 2, 2) / 2
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            summary
            field
        }
        .onAppear { rebuildTrainerImages(); rebuildFieldTiles() }
        .onChange(of: store.outfit) { rebuildTrainerImages() }
        .onChange(of: store.safariVisit?.zone) { rebuildFieldTiles() }
        .onDisappear { isVisible = false }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 10) {
                if let zone = store.safariVisit?.zone {
                    Text(l.safariZoneName(zone)).font(.caption.bold())
                }
                Spacer()
                Label(l.safariBallsRemainingLabel(store.safariVisit?.balls ?? 0), systemImage: "circle.fill")
                Label(l.safariStepsRemainingLabel(store.safariVisit?.stepsRemaining ?? 0), systemImage: "figure.walk")
                Label(l.safariCatchesRemainingTodayLabel(store.safariZoneCatchesRemainingToday),
                     systemImage: "pawprint.fill")
            }
            .font(.caption2)
            // 볼·걸음이 남았는데 아무 일도 안 일어나면 버그처럼 보인다 — 새 조우가 더 안 뜨는
            // 이유를 화면에 알린다.
            if store.safariZoneCatchesRemainingToday == 0 {
                Text(l.safariZoneNoMoreCatchesTodayBanner)
                    .font(.caption2).foregroundStyle(.secondary)
            }
            if let caughtIDs = store.safariVisit?.caughtSpeciesIDs, !caughtIDs.isEmpty {
                caughtRow(caughtIDs)
            }
        }
    }

    /// 이번 방문에서 잡은 포켓몬을 걷기 화면에도 보여준다 — 조우 화면에서만 잠깐 보고 마는 대신
    /// 계속 확인할 수 있게.
    private func caughtRow(_ speciesIDs: [Int]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(l.safariCaughtThisVisitLabel).font(.caption2).foregroundStyle(.secondary)
            HStack(spacing: 2) {
                ForEach(Array(speciesIDs.enumerated()), id: \.offset) { _, speciesID in
                    SpriteView(speciesID: speciesID, size: 20, shiny: false)
                }
            }
        }
    }

    private var field: some View {
        let width = Self.cellSize * CGFloat(Self.bounds.width)
        let height = Self.cellSize * CGFloat(Self.bounds.height)
        return TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !isVisible)) { context in
            Canvas { ctx, size in drawField(ctx: ctx, size: size) }
                .onChange(of: context.date) { _, newDate in tick(now: newDate) }
        }
        .frame(width: width, height: height)
        .clipped()
        .background(zoneBackgroundColor)
        .background(SafariKeyCapture(heldKeys: $heldKeys))
    }

    private var zoneBackgroundColor: Color {
        switch store.safariVisit?.zone {
        case .grassland: .green.opacity(0.25)
        case .wetland: .teal.opacity(0.25)
        case .cave: .brown.opacity(0.25)
        case nil: .clear
        }
    }

    private func drawField(ctx: GraphicsContext, size: CGSize) {
        drawTiles(ctx: ctx)
        guard let walker = store.safariVisit?.walker else { return }
        let origin = walker.moveOrigin ?? walker.cell
        let target = walker.moveTarget ?? walker.cell
        let progress = walker.moveProgress
        // 좌표 보간에만 ease-in-out 을 먹인다 — Core(`SafariWalker.moveProgress`)는 그대로 선형
        // 이라 걸음 소모·인카운터 굴림 타이밍은 안 바뀐다. 딱딱한 등속 대신 칸 진입·이탈이
        // 자연스럽게 가속·감속한다.
        let eased = Self.easeInOut(progress)
        let cellX = CGFloat(origin.x) + (CGFloat(target.x) - CGFloat(origin.x)) * eased
        let cellY = CGFloat(origin.y) + (CGFloat(target.y) - CGFloat(origin.y)) * eased
        guard let images = trainerImages[walker.facing], !images.isEmpty else { return }
        // 발걸음 프레임 전환은 원본(선형) progress 로 재야 걷는 속도감과 어긋나지 않는다 —
        // 좌표만 느슨해지고 발은 그대로 빠르게 바뀌면 미끄러지는 것처럼 보인다.
        let step = progress > 0 ? Int(progress * 3) % images.count : 0
        let image = images[step]
        // 스프라이트 원본은 16×24 — 정수배(2배)로 그려야 `.interpolation(.none)` 확대가 각
        // 픽셀 경계에서 깨끗하다(1.5배 같은 비정수배는 픽셀이 살짝 뭉개진다). 칸(24×24)보다
        // 커지므로 가로는 칸 중앙에, 세로는 발이 칸 아래에 오도록 맞춘다.
        let width: CGFloat = 32
        let height: CGFloat = 48
        let rect = CGRect(x: cellX * Self.cellSize - (width - Self.cellSize) / 2,
                          y: cellY * Self.cellSize - (height - Self.cellSize),
                          width: width, height: height)
        ctx.draw(Image(decorative: image, scale: 1).interpolation(.none), in: rect)
    }

    private func rebuildTrainerImages() {
        let sprite = TrainerSprite(outfit: store.outfit)
        var built: [Facing: [CGImage]] = [:]
        for facing in Facing.allCases {
            built[facing] = (0..<3).compactMap {
                sprite.frame(facing, step: $0).cgImage(palette: TrainerPixelArt.palette)
            }
        }
        trainerImages = built
    }

    /// 존이 바뀔 때만 부른다 — 타일 이미지를 굽고, 칸마다 쓸 타일을 결정론으로 미리 정한다.
    /// `(x*7 + y*13) % 타일종류수` 는 씨앗이 아니라 순수 좌표 해시라 같은 칸은 방문 내내
    /// 같은 타일을 쓴다(매 프레임 다시 고르면 깜빡인다).
    private func rebuildFieldTiles() {
        guard let zone = store.safariVisit?.zone else {
            tileImages = []; tilePlan = []; obstacleImage = nil
            return
        }
        let palette = SafariFieldPixelArt.palette(for: zone)
        tileImages = SafariFieldPixelArt.tiles(for: zone).compactMap { $0.cgImage(palette: palette) }
        obstacleImage = SafariFieldPixelArt.obstacle(for: zone)
            .cgImage(palette: SafariFieldPixelArt.obstaclePalette(for: zone))
        guard !tileImages.isEmpty else { tilePlan = []; return }
        tilePlan = (0..<(Self.bounds.width * Self.bounds.height)).map { index in
            let x = index % Self.bounds.width, y = index / Self.bounds.width
            return (x * 7 + y * 13) % tileImages.count
        }
    }

    private func drawTiles(ctx: GraphicsContext) {
        guard !tileImages.isEmpty else { return }
        let obstacles = store.safariVisit.map { SafariZone.obstacles(for: $0.zone) } ?? []
        for y in 0..<Self.bounds.height {
            for x in 0..<Self.bounds.width {
                let tile = tileImages[tilePlan[y * Self.bounds.width + x]]
                let rect = CGRect(x: CGFloat(x) * Self.cellSize, y: CGFloat(y) * Self.cellSize,
                                  width: Self.cellSize, height: Self.cellSize)
                ctx.draw(Image(decorative: tile, scale: 1).interpolation(.none), in: rect)
                if let obstacleImage, obstacles.contains(SafariCell(x: x, y: y)) {
                    ctx.draw(Image(decorative: obstacleImage, scale: 1).interpolation(.none), in: rect)
                }
            }
        }
    }

    /// 매 프레임 호출 — 실제 걸음 소모·인카운터 굴림은 `SafariVisit.advance` 가 한다. 여기서는
    /// 경과 시간(dt)만 재고 방문을 꺼내 바꾸고 되넣는다.
    private func tick(now: Date) {
        defer { lastTickDate = now }
        guard let last = lastTickDate else { return }
        let dt = now.timeIntervalSince(last)
        let catchesRemainingToday = store.safariZoneCatchesRemainingToday
        mutate { $0.advance(dt: dt, heldKeys: heldKeys, catchesRemainingToday: catchesRemainingToday) }
    }

    /// store 의 방문을 꺼내 바꾸고 되넣는다 — 뷰가 값 타입 코어를 다루는 유일한 자리다
    /// (`RogueRunView.mutate` 와 같은 자리).
    private func mutate(_ body: (inout SafariVisit) -> Void) {
        guard var visit = store.safariVisit else { return }
        body(&visit)
        store.safariVisit = visit
    }
}
