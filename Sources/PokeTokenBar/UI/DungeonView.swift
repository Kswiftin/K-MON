import SwiftUI

/// 하루 한 판 퍼즐 던전 화면(#79). **방 하나가 화면 하나**이고 트레이너가 방향키로 걸어 문에
/// 닿으면 옆 방으로 간다(설계: `docs/reference/room-walk-dungeon-design.md`).
///
/// 예전에는 출구 이름 목록을 클릭하는 텍스트 UI 였다 — 규칙은 맞았지만 "어디로 가는지 감이 안
/// 온다"는 사용성 문제가 남았다. 목록이 주던 정보(통로 비용·밝혀진 정체)는 방 화면에서
/// 문 옆 숫자와 글리프로 그대로 보인다.
///
/// 걷기 규칙은 `DungeonWalker`, 방 그래프 규칙은 `DungeonRun` 에 있다 — 이 화면은 상태를 잇고
/// 연출을 띄우고 정산을 부르는 일만 한다. 글 로그(`DungeonNarration.trail`)는 캔버스 아래에
/// 그대로 살렸다(연출을 놓친 사람의 폴백).
struct DungeonView: View {
    @Bindable var store: CompanionStore
    let onClose: () -> Void

    @State private var walker: DungeonWalker?
    /// 시작 전 체크 — 마시겠다고 켜 두면 `startDungeonRun` 이 한 병을 소모한다.
    @State private var drinkFreshWater = false
    /// 방 진입 연출. 떠 있는 동안 입력이 잠기고 타임라인이 계속 돈다.
    @State private var presentation: RoomPresentation?
    /// 지난 프레임 시각 — 실제 경과 시간으로 걷게 한다(델타 상한은 `DungeonWalker` 가 건다).
    @State private var lastTick: Date?
    @State private var frames = TrainerFrameCache(outfit: TrainerOutfit())

    init(store: CompanionStore, onClose: @escaping () -> Void, initialRun: DungeonRun? = nil) {
        self.store = store
        self.onClose = onClose
        // `initialRun` 은 테스트가 탐색 중 화면을 그대로 세우기 위한 입구다(프로덕션은 `start()`).
        _walker = State(initialValue: initialRun.map { DungeonWalker(run: $0) })
    }

    private var l: L { store.l }

    /// 방 번호 → 이름 슬롯. 날짜가 같으면 어느 기기에서나 같은 이름이다.
    private var nameSlots: [Int] { DungeonNarration.nameSlots(dayKey: store.dungeonMap.dayKey) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if let walker {
                exploring(walker)
            } else {
                lobby
            }
        }
        .padding(PopoverMetrics.padding)
        .frame(height: PopoverMetrics.currentHeight(for: .battle))
        .onAppear { frames = TrainerFrameCache(outfit: store.outfit) }
        .onChange(of: store.outfit) { frames = TrainerFrameCache(outfit: store.outfit) }
        // 팝오버가 닫히거나 화면이 바뀌어도 맵 기억은 남긴다 — 실패·이탈은 시도만 버린다.
        .onDisappear { if let walker { store.rememberDungeon(walker.run.revealed) } }
    }

    private func roomTitle(_ room: Int) -> String { l.dungeonRoomTitle(nameSlots[room]) }

    // MARK: 헤더

    private var header: some View {
        HStack {
            Label(headerTitle, systemImage: "map.fill").font(.headline)
            Spacer()
            Button(action: close) { Image(systemName: "xmark") }
                .buttonStyle(.plain).help(l.dungeonLeave)
        }
    }

    private var headerTitle: String {
        guard let walker else { return l.dungeonTitle }
        return l.dungeonTitle + " · " + roomTitle(walker.run.current)
    }

    // MARK: 시작 전

    /// 오늘의 상성 축, 보상 상태, 먹는샘물 선택.
    private var lobby: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(l.dungeonBudgetLine(store.dungeonMap.affinity, store.dungeonBudgetPreview))
                .font(.caption).foregroundStyle(.secondary)
            if store.dungeonCleared {
                Text(l.dungeonAlreadyCleared).font(.caption2).foregroundStyle(.secondary)
            } else {
                Text(l.dungeonRewardPreview(PuzzleDungeon.firstClearReward))
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Toggle(l.dungeonDrinkFreshWater(store.itemCount(.freshWater)), isOn: $drinkFreshWater)
                .toggleStyle(.checkbox)
                .font(.caption2)
                .disabled(store.itemCount(.freshWater) == 0)
            Spacer()
            Button(l.dungeonEnter, action: start)
                .buttonStyle(.borderedProminent)
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: 탐색 중

    private func exploring(_ current: DungeonWalker) -> some View {
        let run = current.run
        return VStack(alignment: .leading, spacing: 8) {
            vitals(run)
            RoomCanvas(walker: current, frames: frames, presentation: presentation,
                       onDoorTap: { door in walker?.walkTo(door: door) },
                       onTick: { date in tick(at: date) })
                // 캔버스는 14칸 × 24pt = 336pt 다. 팝오버 패딩 14pt 를 그대로 두면 332pt 로 눌려
                // 타일이 정수 픽셀 배율을 잃고 흐려진다 — 이 줄만 가로 여백을 12pt 로 되돌린다.
                .padding(.horizontal, -2)
            Text(run.current == 0 ? l.dungeonHomeHint : l.dungeonKeyHint)
                .font(.caption2).foregroundStyle(.secondary)
            footer(run)
            Divider()
            trailList(DungeonNarration.trail(run.events, start: run.map.room(0).kind))
            Spacer(minLength: 0)
        }
        // 걷기 키는 이 화면이 보일 때만 잡는다 — 다른 탭으로 넘어가면 모니터가 함께 내려간다.
        .captureWalkKeys(onPress: { direction in walker?.press(direction) },
                         onRelease: { direction in walker?.release(direction) })
    }

    /// 체력 게이지와 진행도. 숫자만 두면 남은 여유가 감으로 안 온다.
    private func vitals(_ run: DungeonRun) -> some View {
        HStack(spacing: 6) {
            Text(DungeonNarration.gauge(hp: run.hp, budget: run.budget))
                .font(.caption2.monospaced())
            Text(l.dungeonHitPoints(run.hp, run.budget))
                .font(.caption2.monospacedDigit())
            Spacer()
            Text(l.dungeonFloorLine(layer: run.layer + 1, total: run.map.layerCount))
                .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func footer(_ run: DungeonRun) -> some View {
        switch run.stage {
        case .exploring:
            EmptyView()
        case .failed:
            VStack(alignment: .leading, spacing: 4) {
                Text(l.dungeonFailed).font(.caption)
                Button(l.dungeonRetry, action: start).buttonStyle(.borderedProminent)
            }
        case .cleared:
            VStack(alignment: .leading, spacing: 4) {
                Text(l.dungeonClearedTitle).font(.caption.bold())
                Text(l.dungeonAlreadyCleared).font(.caption2).foregroundStyle(.secondary)
                Button(l.dungeonRetry, action: start).controlSize(.small)
            }
        }
    }

    // MARK: 지나온 길

    private func trailList(_ trail: [DungeonTrailStep]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(l.dungeonTrailTitle).font(.caption2.bold()).foregroundStyle(.secondary)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(trail.enumerated()), id: \.offset) { entry in
                            trailRow(entry.element).id(entry.offset)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                // 새 줄이 아래로 쌓이므로 따라가지 않으면 방금 일어난 일이 화면 밖에 남는다.
                .onChange(of: trail.count) { _, count in
                    withAnimation { proxy.scrollTo(count - 1, anchor: .bottom) }
                }
                // 로그는 두 줄만 남긴다 — 캔버스가 화면의 주인이고 로그는 폴백이다.
                .frame(height: 40)
            }
        }
    }

    private func trailRow(_ step: DungeonTrailStep) -> some View {
        HStack(spacing: 4) {
            Text(roomTitle(step.room)).font(.caption2)
            Text("· " + l.dungeonRoomName(step.kind)).font(.caption2).foregroundStyle(.secondary)
            if step.springWasDry {
                Text(l.dungeonEventLine(.springAlreadyUsed(step.room))).font(.caption2).foregroundStyle(.tertiary)
            }
            if step.looted > 0 {
                Text(l.dungeonEventLine(.looted(room: step.room, starPieces: step.looted))).font(.caption2)
            }
            if step.cacheWasEmpty {
                Text(l.dungeonEventLine(.cacheAlreadyLooted(step.room))).font(.caption2).foregroundStyle(.tertiary)
            }
            Spacer()
            if !step.deltas.isEmpty {
                Text(l.dungeonDeltaList(step.deltas)).font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            if step.felledBoss { Text("★").font(.caption2) }
            if step.collapsed { Text("✕").font(.caption2).foregroundStyle(.red) }
        }
    }

    // MARK: 게임루프

    /// 한 프레임. 캔버스가 시각을 넘겨 주고 상태 변경은 전부 여기서만 한다 — 뷰 본문 평가 중에
    /// 상태를 바꾸면 SwiftUI 가 같은 프레임에서 무한 갱신에 빠진다.
    private func tick(at date: Date) {
        guard var current = walker else { return }
        let delta = lastTick.map { date.timeIntervalSince($0) } ?? 1.0 / 60
        lastTick = date
        current.tick(delta)
        let arrival = current.consumeArrival()
        walker = current
        guard let arrival else { return }
        settleLoot(arrival)
        let shown = presentation(for: arrival, run: current.run)
        presentation = shown
        if shown == nil {
            // 보여 줄 것이 없으면 기다릴 이유도 없다 — 문을 지나 걷던 흐름이 끊기지 않게 바로 푼다.
            release()
        } else {
            scheduleRelease(shown)
        }
    }

    /// 보물은 밟은 순간 정산한다 — 시도가 실패로 끝나도 턴 보물은 남는다(하루 상한은 방 단위).
    private func settleLoot(_ events: [DungeonEvent]) {
        for event in events {
            guard case .looted(let room, let starPieces) = event else { continue }
            _ = store.lootDungeonCache(room: room, starPieces: starPieces)
        }
    }

    private func scheduleRelease(_ shown: RoomPresentation?) {
        Task {
            try? await Task.sleep(for: .seconds(RoomPresentation.duration))
            // 그새 다음 연출로 바뀌었으면 잠금을 푸는 건 그쪽 타이머의 몫이다.
            guard presentation == shown else { return }
            release()
        }
    }

    /// 연출을 걷고 입력 잠금을 푼다. 판정이 끝난 시도는 잠근 채로 둔다 — 안 그러면 클리어·실패 뒤에도
    /// 문에 닿아 `run.move` 가 계속 거절당한다(로그만 쌓인다).
    private func release() {
        presentation = nil
        guard var current = walker else { return }
        switch current.run.stage {
        case .cleared:
            // 정산은 클리어 순간 한 번만 부른다. 스토어가 재지급을 막지만 알림이 겹치지 않게 한다.
            _ = store.settleDungeonClear(revealed: current.run.revealed,
                                         sweptAllCaches: current.run.sweptAllCaches)
        case .failed:
            store.rememberDungeon(current.run.revealed)
        case .exploring:
            current.locked = false
        }
        walker = current
    }

    /// 도착 이벤트 묶음에서 보여 줄 연출 하나를 고른다. 우선순위는 보스 > 쓰러짐 > 교전 >
    /// 보물 > 샘 — 한 번 들어갈 때 여러 일이 겹치면 판을 가르는 쪽을 보여 준다.
    private func presentation(for events: [DungeonEvent], run: DungeonRun) -> RoomPresentation? {
        var enteredKind: RoomKind?
        var damage = 0
        var healed: Int?
        var springDry = false
        var loot: Int?
        var cacheEmpty = false
        var felled = false
        var collapsed = false
        for event in events {
            switch event {
            case .entered(_, let kind): enteredKind = kind
            case .damaged(let amount): damage += amount
            case .healed(let amount): healed = amount
            case .springAlreadyUsed: springDry = true
            case .looted(_, let starPieces): loot = starPieces
            case .cacheAlreadyLooted: cacheEmpty = true
            case .bossFelled: felled = true
            case .collapsed: collapsed = true
            }
        }
        let dayKey = store.dungeonMap.dayKey
        let kind: RoomPresentation.Kind?
        if enteredKind == .boss {
            kind = .boss(species: DungeonEncounterSprite.boss(dayKey: dayKey), damage: damage, felled: felled)
        } else if collapsed {
            kind = .collapsed
        } else if enteredKind == .encounter, damage > 0 {
            let species = DungeonEncounterSprite.species(dayKey: dayKey, room: run.current,
                                                        affinity: run.map.affinity)
            kind = .encounter(species: species, damage: damage)
        } else if let loot {
            kind = .loot(loot)
        } else if cacheEmpty {
            kind = .cacheEmpty
        } else if let healed {
            kind = .heal(healed)
        } else if springDry {
            kind = .springDry
        } else {
            kind = nil
        }
        guard let kind else { return nil }
        return RoomPresentation(kind: kind, startedAt: .now)
    }

    // MARK: 조작

    private func start() {
        if let walker { store.rememberDungeon(walker.run.revealed) }
        walker = DungeonWalker(run: store.startDungeonRun(drinkFreshWater: drinkFreshWater))
        // 한 병은 한 시도에만 쓰인다 — 켜 둔 채로 재도전하면 재고가 조용히 빠진다.
        drinkFreshWater = false
        presentation = nil
        lastTick = nil
    }

    private func close() {
        if let walker { store.rememberDungeon(walker.run.revealed) }
        onClose()
    }
}
