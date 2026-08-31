import SwiftUI

/// 웨이브 런의 경기장 — **한쪽에 최대 두 칸**이 서는 화면이다(2대2).
///
/// `BattleArenaView` 를 늘리지 않고 따로 두는 이유는 그 화면이 LAN 대전·체육관·토너먼트가 함께
/// 쓰는 1대1 경기장이라서다. 한 칸짜리 필드와 기술 격자 하나를 전제로 짜여 있어, 여기에 칸
/// 배열과 타겟 고르기를 끼우면 세 화면의 배치가 함께 흔들린다. 대신 **작은 조각은 전부
/// 재사용한다** — 스프라이트·HP 색·상태 배지·기술 격자·교체 줄·로그 칸·기술 연출은 배틀 화면과
/// 같은 컴포넌트다(그래야 같은 기술이 화면에 따라 달라 보이지 않는다).
struct WaveRunArenaView: View {
    /// 필드 한 칸에 그릴 것. `side` 는 **재생 진행도가 반영된 표시용** 개체다(엔진의 최종 상태와
    /// 다를 수 있다는 것이 `ReplaySide` 의 존재 이유다).
    struct Cell: Identifiable, Equatable {
        let ordinal: Int
        let actor: BattleActor
        let side: BattleSide
        var id: Int { ordinal }
    }

    let mine: [Cell]
    let theirs: [Cell]
    let l: L
    let turn: Int
    /// 상대 쪽 라벨 — 야생/보스.
    let theirTitle: String
    let logLines: [BattleLog.Line]
    let overlay: ReplayOverlay
    /// 지금 행동을 정할 내 칸. `nil` 이면 입력을 받지 않는다(재생 중이거나 이미 다 정했다).
    let actingSlot: Int?
    /// 쓰러진 개체를 내보낼 칸을 고르는 중인가. 이 값이 있으면 **교체 줄이 기절 보충으로** 쓰인다
    /// (턴을 쓰지 않는다 — `WaveBattle.sendOut`).
    let sendOutSlot: Int?
    let switchSlots: [SwitchSlot]
    let isEnabled: Bool
    /// (기술 인덱스, 상대 필드 칸).
    let onMove: (Int, Int) -> Void
    let onSwitch: (Int) -> Void
    let onForfeit: () -> Void

    /// 타겟을 고르는 중인 기술. 상대가 둘일 때만 이 단계를 지난다 — 하나면 고를 것이 없다.
    @State private var pendingMove: Int?

    private var actingCell: Cell? { mine.first { $0.ordinal == actingSlot } }
    private var livingTargets: [Cell] { theirs.filter { $0.side.isAlive } }
    private var acceptsInput: Bool { isEnabled && actingSlot != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: BattleFieldMetrics.spacing) {
            header
            field
            prompt
            actionRow
            if !switchSlots.isEmpty {
                SwitchStripView(slots: switchSlots,
                                label: sendOutSlot == nil
                                    ? l.battleSwitch
                                    : l.t("내보내기", "Send out", "くり出す"),
                                isEnabled: isEnabled && (acceptsInput || sendOutSlot != nil),
                                onSwitch: onSwitch)
            }
            BattleLogBox(lines: logLines, myActors: Set(mine.map(\.actor)))
        }
        .frame(maxWidth: BattleFieldMetrics.width, alignment: .leading)
        // 고르던 기술은 그 칸의 것이다 — 칸이 넘어가면 버린다. 안 버리면 2번 칸이 1번 칸에서
        // 고른 기술 인덱스로 공격한다.
        .onChange(of: actingSlot) { pendingMove = nil }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(l.battleTurnLabel(turn)).font(.caption.bold()).monospacedDigit()
            Spacer()
            Button(l.battleForfeit, action: onForfeit)
                .controlSize(.mini)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: 필드

    private var field: some View {
        ZStack {
            LinearGradient(colors: [Color.accentColor.opacity(0.10), Color.primary.opacity(0.03)],
                           startPoint: .top, endPoint: .bottom)
            VStack(spacing: 4) {
                HStack(alignment: .top, spacing: 6) {
                    ForEach(theirs) { cell in
                        card(cell, isMine: false,
                             isHighlighted: pendingMove != nil && cell.side.isAlive)
                    }
                }
                Spacer(minLength: 0)
                HStack(alignment: .bottom, spacing: 6) {
                    ForEach(mine) { cell in
                        card(cell, isMine: true, isHighlighted: cell.ordinal == actingSlot)
                    }
                }
            }
            .padding(6)
            if let move = activeMove, let actor = overlay.moveActor {
                BattleMoveEffect(move: move, attacksFromMine: mine.contains { $0.actor == actor })
                    .id("\(actor)-\(move.id)-\(overlay.isPlaying)")
                    .allowsHitTesting(false)
            }
            if let phrase = overlay.popped.flatMap({ BattleReplay.popup(for: $0, l: l) }) {
                Text(phrase)
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(Color.black.opacity(0.55)))
            }
        }
        .frame(height: Self.fieldHeight)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    /// 지금 재생 중인 기술 — 칸 중 주인이 맞는 쪽의 무브셋에서 찾는다.
    private var activeMove: MoveSpec? {
        guard let actor = overlay.moveActor, let moveID = overlay.moveID,
              let cell = (mine + theirs).first(where: { $0.actor == actor }) else { return nil }
        return cell.side.moves.first { $0.id == moveID }
            ?? (moveID == MoveSpec.struggleID ? .struggle() : nil)
    }

    /// 필드 한 칸. 1대1 의 `CombatantBar`(168pt 고정)를 쓰지 않는 이유는 폭이다 — 두 칸이 나란히
    /// 서면 팝오버 폭(332pt)에 들어가지 않는다. 그래서 같은 조각으로 좁은 카드를 따로 짠다.
    private func card(_ cell: Cell, isMine: Bool, isHighlighted: Bool) -> some View {
        let side = cell.side
        let isStruck = overlay.hit == cell.actor
        let tier = HPTier.of(hp: side.hp, max: side.stats.hp)
        return VStack(spacing: 1) {
            SpriteView(speciesID: side.snapshot.speciesID,
                       size: isMine ? Self.mySpriteSize : Self.theirSpriteSize,
                       animated: true, shiny: side.snapshot.isShiny, back: isMine)
                .opacity(side.isAlive ? (isStruck ? 0.45 : 1) : 0.3)
                .offset(x: isStruck ? 4 : 0)
                .animation(.easeInOut(duration: 0.08).repeatCount(4, autoreverses: true),
                           value: isStruck)
            HStack(spacing: 3) {
                if side.snapshot.isShiny { Text("✨").font(.system(size: 8)) }
                Text(side.snapshot.name).font(.system(size: 10, weight: .bold)).lineLimit(1)
                Text(l.battleLv(side.snapshot.level))
                    .font(.system(size: 8, weight: .semibold)).foregroundStyle(.secondary)
                Spacer(minLength: 2)
                StatusBadgeRow(side: side)
            }
            // 트랙(회색)과 채움(색)을 겹쳐 그린다 — 채움에 `scaleEffect` 를 걸면 배경 트랙까지
            // 같이 줄어 HP 가 깎인 만큼 바 자체가 짧아진다.
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.12))
                    Capsule().fill(tier.color)
                        .frame(width: geometry.size.width
                               * CGFloat(HPReadout.ratio(hp: side.hp, max: side.stats.hp)))
                        // 재생이 값을 움직이는 동안만 보간한다 — 끄기·저전력에서는 보간도 없어야
                        // 한다(그 설정이 있는 이유가 저전력과 접근성이다).
                        .animation(overlay.isPlaying ? .easeOut(duration: 0.4) : nil,
                                   value: side.hp)
                }
            }
            .frame(height: 4)
            HStack(spacing: 3) {
                Text(isMine ? l.battleMyPokemon : theirTitle)
                    .font(.system(size: 8)).foregroundStyle(.tertiary).lineLimit(1)
                Spacer(minLength: 2)
                StageArrows(side: side)
                Text(isMine ? HPReadout.mine(hp: side.hp, max: side.stats.hp)
                            : HPReadout.theirs(hp: side.hp, max: side.stats.hp))
                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 5).padding(.vertical, 3)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 8)
            .fill(Color.primary.opacity(isHighlighted ? 0.12 : 0.05)))
        .overlay(RoundedRectangle(cornerRadius: 8)
            .strokeBorder(isHighlighted ? Color.accentColor : .clear, lineWidth: 1.5))
    }

    // MARK: 조작

    /// 지금 무엇을 해야 하는지 한 줄. 2대2 는 칸마다 따로 정하므로, 이 줄이 없으면 방금 누른 기술이
    /// 어느 칸의 것인지 화면에 남지 않는다.
    @ViewBuilder
    private var prompt: some View {
        if let sendOutSlot {
            Label(l.t("\(sendOutSlot + 1)번 칸에 내보낼 포켓몬을 고른다 (턴을 쓰지 않는다)",
                      "Choose who takes slot \(sendOutSlot + 1) (this costs no turn)",
                      "\(sendOutSlot + 1)番目の枠に出すポケモンを選ぶ（ターンを消費しない）"),
                  systemImage: "arrow.up.circle")
                .font(.caption2).foregroundStyle(.orange)
        } else if pendingMove != nil {
            Label(l.t("때릴 상대를 고른다", "Choose a target", "攻撃する相手を選ぶ"),
                  systemImage: "scope")
                .font(.caption2).foregroundStyle(.orange)
        } else if let actingCell, mine.count > 1 {
            Text(l.t("\(actingCell.ordinal + 1)번 칸 — \(actingCell.side.snapshot.name) 의 행동",
                     "Slot \(actingCell.ordinal + 1) — \(actingCell.side.snapshot.name)'s action",
                     "\(actingCell.ordinal + 1)番目の枠 — \(actingCell.side.snapshot.name) の行動"))
                .font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
        } else {
            Text(l.battleYourTurn)
                .font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var actionRow: some View {
        if let pendingMove {
            HStack(spacing: 6) {
                ForEach(livingTargets) { target in
                    Button {
                        onMove(pendingMove, target.ordinal)
                        self.pendingMove = nil
                    } label: {
                        HStack(spacing: 4) {
                            SpriteView(speciesID: target.side.snapshot.speciesID, size: 22,
                                       shiny: target.side.snapshot.isShiny)
                            Text(target.side.snapshot.name).font(.caption2.bold()).lineLimit(1)
                        }
                        .padding(.horizontal, 6).padding(.vertical, 4)
                        .frame(maxWidth: .infinity)
                        .background(RoundedRectangle(cornerRadius: 7)
                            .fill(Color.accentColor.opacity(0.20)))
                    }
                    .buttonStyle(.plain)
                    .disabled(!isEnabled)
                }
                Button(l.t("취소", "Cancel", "やめる")) { self.pendingMove = nil }
                    .controlSize(.small)
            }
        } else if let actingCell {
            let side = actingCell.side
            MoveGridView(moves: side.mustStruggle ? [.struggle()] : side.moves,
                         pp: side.mustStruggle ? [] : side.pp,
                         language: l.lang,
                         isEnabled: acceptsInput,
                         onChoose: { index in choose(moveIndex: side.mustStruggle ? -1 : index) })
        } else if sendOutSlot == nil {
            // 행동을 다 정했거나 재생 중이다 — 빈 자리를 두면 아래 줄이 위로 밀려 올라온다.
            Text(l.battleWaitingOpponent)
                .font(.system(size: 9)).foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, minHeight: 20, alignment: .leading)
        }
    }

    /// 상대가 하나면 타겟 단계를 지나지 않는다 — 고를 것이 없는 단계를 두면 매 턴 클릭이 하나 늘고,
    /// 단일전(웨이브의 대부분)이 통째로 느려진다.
    private func choose(moveIndex: Int) {
        let targets = livingTargets
        if targets.count <= 1 {
            onMove(moveIndex, targets.first?.ordinal ?? 0)
        } else {
            pendingMove = moveIndex
        }
    }

    /// 2대2 는 한 화면에 네 개체가 든다 — 1대1 필드(150pt)에 두 줄을 넣으면 카드가 잘린다.
    static let fieldHeight: CGFloat = 186
    static let mySpriteSize: CGFloat = 54
    static let theirSpriteSize: CGFloat = 46
}

// MARK: - 스트림 → 로그 줄

extension BattleLogSource {
    /// 웨이브 런(최대 2대2)의 스트림을 로그 줄로 접는다. 주인이 `.fighter(UUID)` 라 좌우 두 자리
    /// 규칙(`twoSided`)으로는 같은 편 두 칸이 한 이름으로 접힌다.
    static func waveRun(_ events: [BattleEvent], cells: [WaveRunArenaView.Cell],
                        l: L) -> [BattleLog.Line] {
        // 이름·무브셋을 주인으로 찾는다. 모르는 주인(이 웨이브의 칸이 아닌 옛 이벤트)은 물음표로
        // 남긴다 — 엉뚱한 칸의 이름을 붙이는 것보다 낫다.
        let byActor = Dictionary(cells.map { ($0.actor, $0.side) },
                                 uniquingKeysWith: { first, _ in first })
        return BattleLog.lines(events, l: l,
                               name: { byActor[$0]?.snapshot.name ?? "?" },
                               move: { actor, id in
                                   byActor[actor]?.moves.first { $0.id == id } ?? .struggle()
                               })
    }
}
