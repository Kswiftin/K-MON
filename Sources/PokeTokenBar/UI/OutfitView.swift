import SwiftUI

/// 꾸미기(옷장) 오버레이 — 슬롯별로 소유한 의상을 갈아입힌다. 상점·업적 보상으로 얻은 아이템만
/// 입힐 수 있고, 나머지는 자물쇠로 잠가 보여준다(구매/해금 유도는 상점·업적 화면이 맡는다).
///
/// 미리보기는 정지 아바타가 아니라 걷기 애니메이션(0→1→0→2, 4fps)이다 — 옷이 실제로 어떻게
/// 보이는지는 걷는 모습이라야 감이 온다. 이 화면은 오버레이(transient)라 뜬 동안만 타이머가
/// 돈다 — `참조 문서`의 "상시 애니메이션" 규칙은 계속 살아 있는 메뉴바 아이콘 대상이라 여기엔
/// 해당하지 않지만, 그래도 닫히면 확실히 멈추게 `isVisible` 로 한 번 더 막는다.
struct OutfitView: View {
    @Bindable var store: CompanionStore
    let onClose: () -> Void

    @State private var slot: OutfitSlot = .hat
    @State private var facing: Facing = .down
    /// facing 별 step 0/1/2 CGImage — 착장이 바뀔 때만 다시 합성한다(4 facing × 3 step = 12장).
    @State private var frames: [Facing: [CGImage]] = [:]
    @State private var isVisible = true

    private var l: L { store.l }

    /// 브리핑 순서(모자/머리/상의/하의/소품) — `OutfitSlot` 선언 순서(합성 순서)와는 다르다.
    private static let slotOrder: [OutfitSlot] = [.hat, .hair, .top, .bottom, .accessory]
    /// 걷기 사이클 — 4fps 틱마다 이 순서로 프레임(step)을 밟는다.
    private static let walkSteps = [0, 1, 0, 2]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            preview
            slotPicker
            itemList
            Spacer(minLength: 0)
        }
        .padding(PopoverMetrics.padding)
        .frame(height: PopoverMetrics.currentHeight(for: .battle))
        .onAppear { rebuildFrames() }
        .onChange(of: store.outfit) { rebuildFrames() }
        .onDisappear { isVisible = false }
    }

    private var header: some View {
        HStack {
            Label(l.outfitTitle, systemImage: "tshirt.fill").font(.headline)
            Spacer()
            Button(action: onClose) { Image(systemName: "xmark") }
                .buttonStyle(.plain)
        }
    }

    private var preview: some View {
        VStack(spacing: 6) {
            // `.periodic` 에는 멈춤 파라미터가 없다 — `.animation(paused:)` 로 바꿔야 오버레이가 닫힌
            // 뒤(`isVisible = false`) 타이머 자체가 서고, 위 헤더 주석("닫히면 확실히 멈추게")이 실제로
            // 맞는 말이 된다.
            TimelineView(.animation(minimumInterval: 0.25, paused: !isVisible)) { context in
                let step = walkStep(at: context.date)
                let images = frames[facing] ?? []
                if images.indices.contains(step) {
                    Image(decorative: images[step], scale: 1)
                        .interpolation(.none)
                        .resizable()
                        .frame(width: 16 * 4, height: 24 * 4)
                } else {
                    Color.clear.frame(width: 16 * 4, height: 24 * 4)
                }
            }
            HStack(spacing: 24) {
                Button { rotate(-1) } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(.borderless)
                Button { rotate(1) } label: { Image(systemName: "chevron.right") }
                    .buttonStyle(.borderless)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var slotPicker: some View {
        Picker("", selection: $slot) {
            ForEach(Self.slotOrder, id: \.self) { s in
                Text(l.outfitSlotName(s)).tag(s)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    private var itemList: some View {
        VStack(alignment: .leading, spacing: 6) {
            // 세로로 계속 늘면 오버레이 높이 예산(`PopoverMetrics.currentHeight(for: .battle)`)을
            // 넘길 수 있다 — 가로 스크롤로 묶어 슬롯당 아이템 수가 늘어도 세로 예산은 그대로다.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    takeOffChip
                    ForEach(OutfitItem.allCases.filter { $0.slot == slot }, id: \.self) { item in
                        itemChip(item)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var takeOffChip: some View {
        let isBare = store.outfit.worn[slot] == nil
        let button = Button(l.outfitTakeOff) { store.wear(nil, in: slot) }
        if isBare {
            button.buttonStyle(.borderedProminent).controlSize(.small)
        } else {
            button.buttonStyle(.bordered).controlSize(.small)
        }
    }

    @ViewBuilder
    private func itemChip(_ item: OutfitItem) -> some View {
        let owned = store.ownsOutfit(item)
        let worn = store.outfit.worn[slot] == item
        let button = Button {
            store.wear(item, in: slot)
        } label: {
            HStack(spacing: 4) {
                Text(l.outfitItemName(item))
                if !owned { Image(systemName: "lock.fill").font(.caption2) }
            }
        }
        .disabled(!owned)
        .help(owned ? "" : l.outfitLocked)
        if worn {
            button.buttonStyle(.borderedProminent).controlSize(.small)
        } else {
            button.buttonStyle(.bordered).controlSize(.small)
        }
    }

    private func rotate(_ delta: Int) {
        let all = Facing.allCases
        guard let index = all.firstIndex(of: facing) else { return }
        facing = all[(index + delta + all.count) % all.count]
    }

    private func rebuildFrames() {
        // 착장은 4 facing 이 다 같이 입는다 — `TrainerSprite` 를 facing 루프 밖에서 한 번만 만들어야
        // 12장(4 facing × 3 step)만 합성한다. 안에서 새로 만들면 매 facing 마다 다시 합성해 48장이 된다.
        let sprite = TrainerSprite(outfit: store.outfit)
        var built: [Facing: [CGImage]] = [:]
        for target in Facing.allCases {
            built[target] = (0...2).compactMap { sprite.frame(target, step: $0).cgImage(palette: TrainerPixelArt.palette) }
        }
        frames = built
    }

    private func walkStep(at date: Date) -> Int {
        let tick = Int(date.timeIntervalSinceReferenceDate / 0.25)
        let index = ((tick % Self.walkSteps.count) + Self.walkSteps.count) % Self.walkSteps.count
        return Self.walkSteps[index]
    }
}
