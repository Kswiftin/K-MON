import SwiftUI

/// 하루 한 판 퍼즐 던전 화면(#79). **타일 지도를 그리지 않는다** — 360pt 폭에 지도를 넣으면
/// 아무것도 읽히지 않는다. 헤더·예산 줄·로그·출구 목록만으로 글로 그린다.
///
/// 시도 상태는 이 뷰가 들고 있다(세이브에 없다). 화면을 닫으면 시도는 버려지고
/// 맵 기억만 스토어로 넘어간다.
struct DungeonView: View {
    @Bindable var store: CompanionStore
    let onClose: () -> Void

    @State private var run: DungeonRun?
    /// 시작 전 체크 — 마시겠다고 켜 두면 `startDungeonRun` 이 한 병을 소모한다.
    @State private var drinkFreshWater = false

    private var l: L { store.l }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if let run {
                Text(l.dungeonBudgetLine(run.map.affinity, run.budget))
                    .font(.caption2).foregroundStyle(.secondary)
                logList(run)
                footer(run)
            } else {
                lobby
            }
        }
        .padding(PopoverMetrics.padding)
        .frame(height: PopoverMetrics.currentHeight(for: .battle))
        // 팝오버가 닫히거나 화면이 바뀌어도 맵 기억은 남긴다 — 실패·이탈은 시도만 버린다.
        .onDisappear { if let run { store.rememberDungeon(run.revealed) } }
    }

    private var header: some View {
        HStack {
            Label(l.dungeonTitle, systemImage: "map.fill").font(.headline)
            Spacer()
            if let run {
                Text(l.dungeonRoomCounter(run.revealed.count, PuzzleDungeon.roomCount))
                    .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                Text(l.dungeonHitPoints(run.hp, run.budget))
                    .font(.caption2.monospacedDigit())
            }
            Button(action: close) { Image(systemName: "xmark") }
                .buttonStyle(.plain).help(l.dungeonLeave)
        }
    }

    /// 시작 전 화면 — 오늘의 상성 축, 보상 상태, 먹는샘물 선택.
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

    private func logList(_ run: DungeonRun) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(run.events.enumerated()), id: \.offset) { entry in
                    Text(l.dungeonEventLine(entry.element))
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func footer(_ run: DungeonRun) -> some View {
        switch run.stage {
        case .exploring:
            VStack(alignment: .leading, spacing: 4) {
                ForEach(run.exits, id: \.room) { exit in
                    Button { move(to: exit.room) } label: {
                        HStack {
                            Text("› " + (exit.known.map(l.dungeonRoomName) ?? l.dungeonExitUnknown))
                            if let known = exit.known, known == .spring, run.usedSprings.contains(exit.room) {
                                Text(l.dungeonSpringSpent).foregroundStyle(.tertiary)
                            }
                            Spacer()
                            Text(l.dungeonExitCost(exit.cost)).foregroundStyle(.secondary)
                        }
                        .font(.caption)
                    }
                    .buttonStyle(.plain)
                }
            }
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

    private func start() {
        if let run { store.rememberDungeon(run.revealed) }
        run = store.startDungeonRun(drinkFreshWater: drinkFreshWater)
        // 한 병은 한 시도에만 쓰인다 — 켜 둔 채로 재도전하면 재고가 조용히 빠진다.
        drinkFreshWater = false
    }

    private func move(to room: Int) {
        guard var session = run else { return }
        session.move(to: room)
        run = session
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
