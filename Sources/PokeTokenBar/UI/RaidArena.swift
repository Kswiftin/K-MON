import SwiftUI

/// 레이드 교전 화면의 **순수 판정**. 뷰가 읽기만 하는 값으로 떼어 둔 이유는 두 가지다 —
/// 소켓 없이 검증할 수 있어야 하고(`MultiplayerRoomCenter.creditsRaceFinish` 와 같은 이유),
/// 재생이 실제로 도는지를 가르는 결정이 뷰 본문에 흩어지면 아무도 못 보기 때문이다.
enum RaidArena {
    /// 재생기에 넘길 주인별 표시 상태. 레이드는 **1인 1마리**라 팀이 한 칸씩이다
    /// (교체가 없으므로 `active` 는 언제나 0).
    ///
    /// 보스도 주인이다 — 빼면 보스 바만 재생을 안 타 혼자 최종값으로 튄다.
    static func replaySides(_ fighters: [MultiplayerFighter]) -> [BattleActor: ReplaySide] {
        fighters.reduce(into: [:]) { out, fighter in
            out[.fighter(fighter.id)] = ReplaySide(team: [fighter.side], active: 0)
        }
    }

    /// 결과·정산을 열어도 되나. **재생이 따라잡은 뒤여야 한다** — 승부가 난 라운드가 즉시 결과로
    /// 넘어가면 재생기를 붙인 이유(결정타를 보여 주는 것)가 가장 중요한 턴에 그대로 사라진다.
    static func showsResult(isFinished: Bool, playedCount: Int, streamCount: Int) -> Bool {
        isFinished && playedCount >= streamCount
    }

    /// 기술 버튼을 받아도 되나. 재생 중에 받으면 지난 턴을 보는 도중에 다음 턴이 나간다.
    static func acceptsInput(hasSubmitted: Bool, isAlive: Bool,
                             isFinished: Bool, isReplaying: Bool) -> Bool {
        !hasSubmitted && isAlive && !isFinished && !isReplaying
    }

    /// 화면에 그릴 이벤트 — **재생이 소비한 만큼만**이다. 스트림 전체를 그리면 재생이 그 줄에
    /// 닿기 전에 결과가 로그로 먼저 새어 나가 재생할 이유가 없어진다.
    ///
    /// 재생기가 스트림보다 앞선 값을 보고하는 순간(새 판으로 갈아타는 프레임)에도 터지면 안 되므로
    /// 위쪽을 자른다.
    static func visibleEvents(_ stream: [BattleEvent], playedCount: Int) -> [BattleEvent] {
        Array(stream.prefix(max(0, playedCount)))
    }
}

/// 레이드 교전 필드 — 보스 하나가 위, 파티가 아래.
///
/// `WaveRunArenaView` 를 재사용하지 않는다. 그 타입의 `mine` 은 **내 파티**라 모든 칸을 내가
/// 조작하고 교체 줄까지 딸려 있는데, 레이드에서 내 것은 한 칸뿐이고 나머지는 남의 포켓몬이며
/// 교체가 없다(1인 1마리). 돌아가는 화면에 소유권 분기를 심는 대신 부품
/// (`CombatantBar`·`BattleMoveEffect`·`MoveGridView`·`StatusBadgeRow`)만 같이 쓴다.
struct RaidArenaView: View {
    /// 필드 한 칸. `side` 는 **재생 진행도가 반영된 표시용** 개체다(`WaveRunArenaView.Cell` 과 같다).
    struct Cell: Identifiable, Equatable {
        let id: UUID
        let title: String
        let side: BattleSide
        var actor: BattleActor { .fighter(id) }
    }

    let boss: Cell
    /// 보스 HP 막대의 분모 — 종족값이 아니라 티어 절대값이다.
    let bossMaxHP: Int
    let party: [Cell]
    let myID: UUID
    let l: L
    let round: Int
    let turnsLeft: Int
    let overlay: ReplayOverlay
    let logLines: [BattleLog.Line]
    /// 내 칸이 지금 기술을 고를 수 있나(`RaidArena.acceptsInput`).
    let acceptsInput: Bool
    let onMove: (Int) -> Void

    /// 파티 칸 스프라이트. 두 칸이 나란히 서므로 웨이브 런의 좁은 카드와 같은 치수를 쓴다.
    private static let partySpriteSize: CGFloat = 40

    private var me: Cell? { party.first { $0.id == myID } }

    var body: some View {
        VStack(spacing: 7) {
            header
            field
            prompt
            if !logLines.isEmpty { BattleLogBox(lines: logLines, myActor: .fighter(myID)) }
        }
    }

    private var header: some View {
        HStack {
            Text("R\(round)").font(.caption.monospacedDigit().bold())
            Spacer()
            Text("\(l.raidTurnsLeft) \(turnsLeft)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(turnsLeft <= 3 ? .red : .secondary)
        }
    }

    /// 기술 연출과 팝업은 **필드 한 겹**에만 얹는다 — 칸마다 얹으면 광역 연출이 칸 수만큼 겹친다
    /// (`WaveRunArenaView.field` 와 같은 구성).
    ///
    /// 배경 그라데이션은 `ZStack` 층이 아니라 `.background` 다. 층으로 두면 그라데이션이
    /// **제안된 높이를 통째로 가져가** 필드가 무한히 커진다(웨이브 런은 `.frame(height:)` 로
    /// 막았지만, 레이드는 파티 수에 따라 한 줄·두 줄이라 높이를 고정할 수 없다).
    /// 같은 이유로 연출·팝업도 `.overlay` 다 — 크기를 정하는 건 내용뿐이어야 한다.
    private var field: some View {
        VStack(spacing: 5) {
            bossZone
            Divider().opacity(0.4)
            partyGrid
        }
        .padding(7)
        .background(LinearGradient(colors: [Color.purple.opacity(0.12), Color.primary.opacity(0.03)],
                                   startPoint: .top, endPoint: .bottom),
                    in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            if let move = activeMove, let actor = overlay.moveActor {
                BattleMoveEffect(move: move, attacksFromMine: party.contains { $0.actor == actor })
                    .id("\(actor)-\(move.id)-\(overlay.isPlaying)")
                    .allowsHitTesting(false)
            }
        }
        .overlay {
            if let phrase = overlay.popped.flatMap({ BattleReplay.popup(for: $0, l: l) }) {
                Text(phrase)
                    .font(.caption.bold()).foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(Color.black.opacity(0.55)))
            }
        }
    }

    /// 보스는 한 마리뿐이라 폭이 남는다 — 1v1·체육관과 **같은 `CombatantBar`** 를 쓴다.
    /// 파티 칸은 둘씩 서므로 그 바가 안 들어가고(168pt 고정 폭), 아래에서 좁은 카드를 따로 짠다.
    private var bossZone: some View {
        let isStruck = overlay.hit == boss.actor
        return VStack(spacing: 3) {
            SpriteView(speciesID: boss.side.snapshot.speciesID, size: 64,
                       animated: true, shiny: boss.side.snapshot.isShiny)
                .opacity(boss.side.isAlive ? (isStruck ? 0.45 : 1) : 0.3)
                .offset(x: isStruck ? 4 : 0)
                .animation(.easeInOut(duration: 0.08).repeatCount(4, autoreverses: true),
                           value: isStruck)
            CombatantBar(side: boss.side, title: boss.title, l: l,
                         revealsExactHP: true, animatesHP: overlay.isPlaying,
                         maxHPOverride: bossMaxHP)
        }
    }

    /// 파티는 최대 넷이라 두 칸씩 접는다 — 한 줄에 넷을 세우면 팝오버 폭에서 이름과 HP 표기가
    /// 먼저 잘린다(웨이브 런이 `CombatantBar` 를 안 쓴 것과 같은 이유).
    ///
    /// **혼자면 한 칸이다.** 1★ 솔로가 흔한 경로인데 2열로 두면 오른쪽 절반이 빈 채로 남아
    /// "누가 빠졌나" 로 읽힌다.
    private var partyGrid: some View {
        let columns = party.count <= 1 ? 1 : 2
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5),
                                        count: columns),
                         spacing: 5) {
            ForEach(party) { cell in partyCard(cell) }
        }
    }

    private func partyCard(_ cell: Cell) -> some View {
        let side = cell.side
        let isMine = cell.id == myID
        let isStruck = overlay.hit == cell.actor
        let tier = HPTier.of(hp: side.hp, max: side.stats.hp)
        return VStack(spacing: 1) {
            SpriteView(speciesID: side.snapshot.speciesID, size: Self.partySpriteSize,
                       animated: true, shiny: side.snapshot.isShiny, back: isMine)
                .opacity(side.isAlive ? (isStruck ? 0.45 : 1) : 0.3)
                .offset(x: isStruck ? 4 : 0)
                .animation(.easeInOut(duration: 0.08).repeatCount(4, autoreverses: true),
                           value: isStruck)
            HStack(spacing: 3) {
                Text(cell.title).font(.system(size: 9, weight: .bold)).lineLimit(1)
                Spacer(minLength: 2)
                StatusBadgeRow(side: side)
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.12))
                    Capsule().fill(tier.color)
                        .frame(width: geometry.size.width
                               * CGFloat(HPReadout.ratio(hp: side.hp, max: side.stats.hp)))
                        // 재생이 값을 움직이는 동안만 보간한다 — 끄기·저전력에서는 보간도 없어야
                        // 한다(그 설정이 있는 이유가 저전력과 접근성이다).
                        .animation(overlay.isPlaying ? .easeOut(duration: 0.4) : nil, value: side.hp)
                }
            }
            .frame(height: 4)
            HStack(spacing: 3) {
                StageArrows(side: side)
                Spacer(minLength: 2)
                // 내 실수치만 드러낸다 — 남의 HP 는 원래 모르는 정보다(4인 방과 같은 규칙).
                Text(isMine ? HPReadout.mine(hp: side.hp, max: side.stats.hp)
                            : HPReadout.theirs(hp: side.hp, max: side.stats.hp))
                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 5).padding(.vertical, 3)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 8)
            .fill(Color.primary.opacity(isMine ? 0.12 : 0.05)))
        .overlay(RoundedRectangle(cornerRadius: 8)
            .strokeBorder(isMine ? Color.accentColor : .clear, lineWidth: 1.5))
    }

    @ViewBuilder
    private var prompt: some View {
        if let me {
            if overlay.isPlaying {
                Text(l.t("턴을 재생하는 중…", "Playing the turn…", "ターンを再生中…"))
                    .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity)
            } else if !me.side.isAlive {
                Text(l.t("탈락 — 파티를 응원하고 있습니다.", "Knocked out - cheering the party on.",
                         "戦闘不能 — パーティを応援中です。"))
                    .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity)
            } else if !acceptsInput {
                HStack { ProgressView().controlSize(.small)
                    Text(l.t("다른 참가자의 행동을 기다리는 중…", "Waiting for other players…",
                             "ほかの参加者の行動を待っています…")) }
                    .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity)
            } else {
                // 대상 고르기가 없다 — 때릴 것은 보스 하나다. 상성 힌트는 1v1 과 같은 자리에 붙는다.
                let struggling = me.side.mustStruggle
                MoveGridView(moves: struggling ? [.struggle()] : me.side.moves,
                             pp: struggling ? [] : me.side.pp, language: l.lang,
                             isEnabled: true,
                             effectivenessAgainst: boss.side.snapshot.types) { index in
                    onMove(struggling ? -1 : index)
                }
            }
        }
    }

    /// 지금 재생 중인 기술 — 칸 중 주인이 맞는 쪽의 무브셋에서 찾는다.
    private var activeMove: MoveSpec? {
        guard let actor = overlay.moveActor, let moveID = overlay.moveID,
              let cell = ([boss] + party).first(where: { $0.actor == actor }) else { return nil }
        return cell.side.moves.first { $0.id == moveID }
            ?? (moveID == MoveSpec.struggleID ? .struggle() : nil)
    }
}
