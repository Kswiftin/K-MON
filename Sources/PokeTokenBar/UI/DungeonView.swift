import SwiftUI

/// 하루 한 판 퍼즐 던전 화면(#79). **타일 지도를 그리지 않는다** — 360pt 폭에 지도를 넣으면
/// 아무것도 읽히지 않는다. 헤더·서술·출구 목록·지나온 길만으로 글로 그린다.
///
/// 방마다 **고정 이름**을 보여 주는 것이 이 화면의 뼈대다. 이름 없이 방위만 두면 출구 줄이
/// "미탐사"로 글자까지 똑같아져(오늘 맵은 "남동쪽" 출구가 세 개) 무엇을 고르는지 알 수 없다.
/// 이름은 정체를 흘리지 않으므로 안개는 그대로 남는다.
///
/// 계산은 전부 `DungeonNarration`(순수·게이트 대상)에 있다. 여기서 계산하면 설계 목업의 줄들이
/// 무테스트로 남는다.
struct DungeonView: View {
    @Bindable var store: CompanionStore
    let onClose: () -> Void

    @State private var run: DungeonRun?
    /// 시작 전 체크 — 마시겠다고 켜 두면 `startDungeonRun` 이 한 병을 소모한다.
    @State private var drinkFreshWater = false
    /// 시작 방은 출구가 8개까지 나온다 — 기본은 접고 필요할 때만 전부 보여 준다.
    @State private var showAllFreshExits = false

    private var l: L { store.l }

    /// 방 번호 → 이름 슬롯. 날짜가 같으면 어느 기기에서나 같은 이름이다.
    private var nameSlots: [Int] { DungeonNarration.nameSlots(dayKey: store.dungeonMap.dayKey) }

    /// 접기 전에 보여 주는 새 길 수. 4개까지는 목록이 화면을 먹지 않는다.
    private static let collapsedExitLimit = 4

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if let run {
                exploring(run)
            } else {
                lobby
            }
        }
        .padding(PopoverMetrics.padding)
        .frame(height: PopoverMetrics.currentHeight(for: .battle))
        // 팝오버가 닫히거나 화면이 바뀌어도 맵 기억은 남긴다 — 실패·이탈은 시도만 버린다.
        .onDisappear { if let run { store.rememberDungeon(run.revealed) } }
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
        guard let run else { return l.dungeonTitle }
        return l.dungeonTitle + " · " + roomTitle(run.current)
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

    @ViewBuilder
    private func exploring(_ run: DungeonRun) -> some View {
        let trail = DungeonNarration.trail(run.events, start: run.map.room(0).kind)
        vitals(run, attemptRooms: trail.count)
        Text(l.dungeonSceneLine(DungeonNarration.scene(for: run)))
            .font(.caption).fixedSize(horizontal: false, vertical: true)
        Divider()
        footer(run)
        Divider()
        trailList(trail)
    }

    /// 체력 게이지와 진행도. 숫자만 두면 남은 여유가 감으로 안 온다.
    private func vitals(_ run: DungeonRun, attemptRooms: Int) -> some View {
        HStack(spacing: 6) {
            Text(DungeonNarration.gauge(hp: run.hp, budget: run.budget))
                .font(.caption2.monospaced())
            Text(l.dungeonHitPoints(run.hp, run.budget))
                .font(.caption2.monospacedDigit())
            Spacer()
            Text(l.dungeonProgressLine(remembered: run.revealed.count,
                                       total: PuzzleDungeon.roomCount,
                                       attemptRooms: attemptRooms))
                .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func footer(_ run: DungeonRun) -> some View {
        switch run.stage {
        case .exploring:
            exitLists(run)
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

    /// 새 길과 되돌아가기를 나눠 그린다 — 섞어 두면 무엇이 처음 가는 길인지 안 보인다.
    @ViewBuilder
    private func exitLists(_ run: DungeonRun) -> some View {
        let choices = DungeonNarration.choices(for: run)
        let shown = showAllFreshExits ? choices.fresh : Array(choices.fresh.prefix(Self.collapsedExitLimit))
        VStack(alignment: .leading, spacing: 4) {
            if !choices.fresh.isEmpty {
                Text(l.dungeonExitsFresh).font(.caption2.bold()).foregroundStyle(.secondary)
                ForEach(shown, id: \.room) { exitRow($0) }
                if choices.fresh.count > shown.count {
                    Button(l.dungeonMoreExits(choices.fresh.count - shown.count)) { showAllFreshExits = true }
                        .buttonStyle(.plain).font(.caption2).foregroundStyle(.link)
                }
            }
            if !choices.back.isEmpty {
                Text(l.dungeonExitsBack).font(.caption2.bold()).foregroundStyle(.secondary)
                ForEach(choices.back, id: \.room) { exitRow($0) }
            }
        }
    }

    private func exitRow(_ choice: DungeonExitChoice) -> some View {
        Button { move(to: choice.room) } label: {
            HStack(spacing: 4) {
                Text(choice.direction?.arrow ?? "•").font(.caption2)
                Text(roomTitle(choice.room)).font(.caption)
                Text(exitDetail(choice)).font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Text(l.dungeonExitCost(choice.cost))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(choice.isLethal ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
            }
            // 텍스트 폭만 눌리면 어디를 눌러야 하는지 알 수 없다 — 줄 전체를 히트영역으로 둔다.
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(choice.isLethal ? l.dungeonLethalExit : "")
    }

    /// 출구 줄의 부제 — 밝혀진 정체와 방위, 샘 사용 여부. 안개인 방은 "미탐사"만 붙는다.
    private func exitDetail(_ choice: DungeonExitChoice) -> String {
        var parts: [String] = []
        if let direction = choice.direction { parts.append(l.dungeonDirectionName(direction)) }
        if let known = choice.known {
            parts.append(l.dungeonRoomName(known))
            if known == .spring { parts.append(choice.springSpent ? l.dungeonSpringSpent : l.dungeonSpringUnused) }
        } else {
            parts.append(l.dungeonExitUnknown)
        }
        return "· " + parts.joined(separator: " · ")
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
            Spacer()
            if !step.deltas.isEmpty {
                Text(l.dungeonDeltaList(step.deltas)).font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            if step.felledBoss { Text("★").font(.caption2) }
            if step.collapsed { Text("✕").font(.caption2).foregroundStyle(.red) }
        }
    }

    // MARK: 조작

    private func start() {
        if let run { store.rememberDungeon(run.revealed) }
        run = store.startDungeonRun(drinkFreshWater: drinkFreshWater)
        // 한 병은 한 시도에만 쓰인다 — 켜 둔 채로 재도전하면 재고가 조용히 빠진다.
        drinkFreshWater = false
        showAllFreshExits = false
    }

    private func move(to room: Int) {
        guard var session = run else { return }
        session.move(to: room)
        run = session
        // 방이 바뀌면 출구 구성이 달라진다 — 펼친 상태를 물고 가면 새 방에서 8줄이 그대로 뜬다.
        showAllFreshExits = false
        // 정산은 클리어 순간 한 번만 부른다. 스토어가 재지급을 막지만 알림이 겹치지 않게 한다.
        switch session.stage {
        case .cleared: store.settleDungeonClear(revealed: session.revealed)
        case .failed: store.rememberDungeon(session.revealed)
        case .exploring: break
        }
    }

    private func close() {
        if let run { store.rememberDungeon(run.revealed) }
        onClose()
    }
}
