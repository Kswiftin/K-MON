import AppKit
import SwiftUI

// MARK: - 레이아웃 예산

/// 배틀 화면의 크기 예산 — 계획 §6.3 **안 B**(기존 팝오버 안). 모든 숫자가 팝오버 콘텐츠 폭에서
/// 거꾸로 나온다. 화면이 **팝오버 본체 `ScrollView` 안**이라 자기 세로 스크롤을 둘 수 없으므로
/// (defect-log — 안쪽은 스크롤되지 않고 잘린다) 넘치는 건 **고정 높이 칸 + 최근 N줄**로 자른다.
/// 로그가 필드 옆이 아니라 아래인 이유도 폭이다(`testALogBesideTheFieldWouldNotFitThePopoverWidth`).
enum BattleFieldMetrics {
    /// 팝오버가 주는 폭 그대로. 더 요구하면 매번 압축돼 그려진다.
    static var width: CGFloat { PopoverMetrics.contentWidth }
    static let spacing: CGFloat = 7
    /// 필드 높이 — 상대(우상단)와 나(좌하단)가 겹치지 않는 최소선. 창이 아니라 탭 안이라 여기서
    /// 더 키우면 아래 기술 버튼이 잘린다(잘리는 쪽이 조작이라 더 나쁘다).
    static let fieldHeight: CGFloat = 150
    /// HP바·이름이 들어가는 칸 — 양쪽이 같은 폭이라야 좌우가 대칭으로 읽힌다.
    static let barWidth: CGFloat = 168
    static let mySpriteSize: CGFloat = 64
    static let opponentSpriteSize: CGFloat = 52
    /// 로그 줄 수와 그 칸의 **고정** 높이. 높이가 로그를 따라 커지면 늘어난 만큼 아래 기술 버튼이
    /// 잘린다. 전체 로그는 Phase 9 에서 별 시트로 붙는다.
    static let logLines = 4
    /// 4줄 × 9pt + 줄간격 + 패딩. 예산 검증은 **보고하는** 높이만 보므로 실제로 담기는지는
    /// `testTheLogBoxIsTallEnoughForTheLinesItDraws` 가 본다(58 이면 2pt 넘친다).
    static let logHeight: CGFloat = 64
}

// MARK: - HP 표시

/// HP바 색 3단계 — Showdown 과 같은 임계다. 예전엔 `hp > 0 ? .green : .red` 라 HP 5% 와 100% 가
/// 같은 색이었다(`teamSlotCard`, 멀티 격자). 경계값은 **아래로** 떨어진다: 정확히 50% 는 이미
/// 초록이 아니고, 정확히 20% 는 이미 노랑이 아니다.
enum HPTier: Equatable {
    case healthy, warning, critical

    static func of(hp: Int, max maximum: Int) -> HPTier {
        guard maximum > 0 else { return .critical }   // 구버전 피어·손상 세이브의 0 을 0 나눗셈으로 만들지 않는다
        let ratio = Double(hp) / Double(maximum)
        if ratio > 0.5 { return .healthy }
        if ratio > 0.2 { return .warning }
        return .critical
    }

    var color: Color {
        switch self {
        case .healthy:  return .green
        case .warning:  return .yellow
        case .critical: return .red
        }
    }
}

/// HP 표기 — **내 쪽은 실수치, 상대는 % 만.** Showdown 이 그렇게 하는 이유가 그대로 우리에게도
/// 있다: 상대 실수치는 원래 모르는 정보고, 정보 은닉이 곧 게임성이다.
enum HPReadout {
    static func mine(hp: Int, max maximum: Int) -> String { "\(Swift.max(0, hp))/\(maximum)" }

    /// 살아 있으면 최소 1% 로 올린다. 내림만 하면 121 중 1 이 `0%` 로 보여, 아직 서 있는 상대가
    /// 쓰러진 것처럼 읽힌다 — 쓰러졌을 때만 `0%` 여야 그 표기가 정보가 된다.
    static func theirs(hp: Int, max maximum: Int) -> String {
        guard maximum > 0, hp > 0 else { return "0%" }
        return "\(Swift.max(1, hp * 100 / maximum))%"
    }

    /// HP바가 채울 비율 0…1. **뷰 밖에 있어야 한다** — `GeometryReader` 안에서 계산하면 0 나눗셈
    /// 가드가 실제 레이아웃 때만 돌아 커버리지에서 영영 미실행으로 남는다(`badgeTint` 와 같은 부류).
    /// 최대가 0 이하인 스냅샷은 손상 세이브·적대적 피어에서 온다.
    static func ratio(hp: Int, max maximum: Int) -> Double {
        guard maximum > 0 else { return 0 }
        return Swift.min(1, Swift.max(0, Double(hp) / Double(maximum)))
    }
}

// MARK: - 색 대비

/// WCAG 대비 계산 — 타입색 18종 위에 흑·백 중 어느 쪽을 올릴지 고르는 데 쓴다.
/// 한쪽으로 고정하면 18색 중 절반이 읽히지 않는다.
enum ColorContrast {
    static func relativeLuminance(_ rgb: (r: Double, g: Double, b: Double)) -> Double {
        func linear(_ channel: Double) -> Double {
            channel <= 0.03928 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(rgb.r) + 0.7152 * linear(rgb.g) + 0.0722 * linear(rgb.b)
    }

    /// 대비비 1…21. AA 본문 기준은 4.5 다.
    static func ratio(_ a: (r: Double, g: Double, b: Double), _ b: (r: Double, g: Double, b: Double)) -> Double {
        let first = relativeLuminance(a), second = relativeLuminance(b)
        return (Swift.max(first, second) + 0.05) / (Swift.min(first, second) + 0.05)
    }
}

extension PokemonType {
    /// 본가·Showdown 계열 타입색. 예전 `typeChip` 은 18타입 전부를 accent 한 색으로 그려서
    /// 배지가 타입 정보를 하나도 전달하지 못했다.
    var battleRGB: (r: Double, g: Double, b: Double) {
        switch self {
        case .normal:   return (0.659, 0.655, 0.478)
        case .fire:     return (0.933, 0.506, 0.188)
        case .water:    return (0.388, 0.565, 0.941)
        case .electric: return (0.969, 0.816, 0.173)
        case .grass:    return (0.478, 0.780, 0.298)
        case .ice:      return (0.588, 0.851, 0.839)
        case .fighting: return (0.761, 0.180, 0.157)
        case .poison:   return (0.639, 0.243, 0.631)
        case .ground:   return (0.886, 0.749, 0.396)
        case .flying:   return (0.663, 0.561, 0.953)
        case .psychic:  return (0.976, 0.333, 0.533)
        case .bug:      return (0.651, 0.725, 0.102)
        case .rock:     return (0.714, 0.631, 0.212)
        case .ghost:    return (0.451, 0.341, 0.592)
        case .dragon:   return (0.435, 0.208, 0.988)
        case .dark:     return (0.439, 0.341, 0.275)
        case .steel:    return (0.718, 0.718, 0.808)
        case .fairy:    return (0.839, 0.522, 0.678)
        }
    }

    var battleColor: Color { Color(red: battleRGB.r, green: battleRGB.g, blue: battleRGB.b) }

    /// 이 배경 위에 검은 글자를 올릴지 — 흑·백 중 대비가 큰 쪽이다. 두 후보의 대비비는 휘도
    /// 0.179 에서 교차하므로, 이 선택은 어느 색에서도 AA(4.5:1) 이상을 낸다.
    var prefersDarkLabel: Bool {
        ColorContrast.ratio(battleRGB, (0, 0, 0)) > ColorContrast.ratio(battleRGB, (1, 1, 1))
    }

    var battleLabelColor: Color { prefersDarkLabel ? .black : .white }
}

extension MoveDamageClass {
    /// 분류 아이콘. 위력만으로는 변화기와 "위력 0 인 공격기" 를 가릴 수 없다 —
    /// 변화기가 무브셋에 들어오는 Phase 3 부터는 이 아이콘이 유일한 구분이다.
    var symbolName: String {
        switch self {
        case .physical: return "burst.fill"
        case .special:  return "sparkles"
        case .status:   return "arrow.up.arrow.down"
        }
    }
}

// MARK: - PP 경고

/// PP 경고 3단계. 예전엔 0 만 빨강이라 1 남은 기술과 35 남은 기술이 같아 보였다.
/// 경계값(정확히 1/4)은 경고로 떨어지고, 0 은 경고가 아니라 **소진**이다(고를 수 없다).
enum PPTier: Equatable {
    case ample, low, empty

    static func of(remaining: Int, max maximum: Int) -> PPTier {
        if remaining <= 0 { return .empty }
        guard maximum > 0 else { return .ample }
        return remaining * 4 <= maximum ? .low : .ample
    }

    var color: Color {
        switch self {
        case .ample: return .secondary
        case .low:   return .orange
        case .empty: return .red
        }
    }

    /// 색만 바꾸고 활성으로 두면 눌려서 아무 일도 안 일어난다.
    var isSelectable: Bool { self != .empty }
}

// MARK: - 교체 슬롯

/// 교체 스트립 한 칸. 팀 연습에만 있던 스트립(`BattleView.teamPracticeView`)을 일반화한 것으로,
/// 교체가 전 모드로 퍼지는 Phase 4 가 그대로 쓴다.
struct SwitchSlot: Identifiable, Equatable {
    let index: Int
    let side: BattleSide
    let isActive: Bool

    var id: Int { index }

    /// 지금 나와 있는 포켓몬으로도, 쓰러진 포켓몬으로도 교체할 수 없다.
    var isSelectable: Bool { !isActive && side.isAlive }
}

enum SwitchStripModel {
    /// 쓰러진 슬롯도 자리는 남긴다 — 파티가 몇 마리 남았는지가 그 자체로 정보다.
    /// 인덱스가 곧 교체 대상이라 걸러내면 눌렀을 때 다른 포켓몬이 나온다.
    static func slots(_ sides: [BattleSide], active: Int) -> [SwitchSlot] {
        sides.indices.map { SwitchSlot(index: $0, side: sides[$0], isActive: $0 == active) }
    }

    /// LAN 단일전에는 교체 대상이 없으므로 줄 자체를 숨긴다. 팀전은 인덱스 보존을 위해 전체 슬롯을 둔다.
    static func battleSlots(_ sides: [BattleSide], active: Int) -> [SwitchSlot] {
        sides.count > 1 ? slots(sides, active: active) : []
    }
}

// MARK: - 상태 배지

/// HP바 옆 상태 배지 — Showdown 과 같은 약어라 언어를 타지 않는다. 혼란은 주 상태와 함께 붙으므로
/// 두 자리를 따로 그린다(한 자리만 그리면 "화상 + 혼란" 이 화면에서 하나로 뭉개진다).
struct StatusBadgeRow: View {
    let side: BattleSide?

    var body: some View {
        if let side, side.status != nil || side.isConfused {
            HStack(spacing: 3) {
                if let status = side.status { StatusBadge(status: status) }
                if side.isConfused { StatusBadge(status: .confusion) }
            }
        }
    }
}

extension Status {
    /// 배지 색. 뷰 안의 `private var` 로 두면 7개 분기 중 화면에 뜬 것만 실행되고 나머지는 테스트에서
    /// 한 번도 돌지 않는다 — 라인 커버리지는 그걸 초록으로 보고한다(PR 3 에서 `Status.init(ailment:)`
    /// 로 겪은 부류다). 밖으로 빼서 전 분기를 직접 검증한다.
    var badgeTint: Color {
        switch self {
        case .burn:            return .orange
        case .poison, .toxic:  return .purple
        case .paralysis:       return .yellow
        case .sleep:           return .gray
        case .freeze:          return .cyan
        case .confusion:       return .pink
        }
    }
}

struct StatusBadge: View {
    let status: Status

    var body: some View {
        Text(status.badge)
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(Capsule().fill(status.badgeTint))
    }
}

// MARK: - HP바 한 칸

/// 이름 · Lv · 상태 배지 · HP바 · HP 표기. 세 모드가 같은 칸을 쓴다 — 모드마다 다른 카드를 쓰던
/// 것도 지금의 조잡함 중 하나였다(`snapshotCard` 와 `teamSlotCard` 가 서로 달랐다).
///
/// 랭크 화살표(▲▼)가 붙을 자리는 상태 배지 옆이다. 랭크는 Phase 3 에서 생기므로 지금은 없다.
struct CombatantBar: View {
    let side: BattleSide
    let title: String
    let l: L
    /// 내 쪽만 실수치를 보여 준다 — 상대는 % 다(`HPReadout`).
    let revealsExactHP: Bool

    private var tier: HPTier { HPTier.of(hp: side.hp, max: side.stats.hp) }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                if side.snapshot.isShiny { Text("✨").font(.system(size: 9)) }
                Text(side.snapshot.name).font(.caption.bold()).lineLimit(1)
                Text(l.battleLv(side.snapshot.level))
                    .font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
                Spacer(minLength: 2)
                StatusBadgeRow(side: side)
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.12))
                    Capsule().fill(tier.color)
                        .frame(width: geometry.size.width * CGFloat(fillRatio))
                }
            }
            .frame(height: 6)
            HStack(spacing: 4) {
                Text(title).font(.system(size: 8)).foregroundStyle(.tertiary).lineLimit(1)
                Spacer(minLength: 2)
                Text(revealsExactHP
                     ? HPReadout.mine(hp: side.hp, max: side.stats.hp)
                     : HPReadout.theirs(hp: side.hp, max: side.stats.hp))
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.07)))
    }

    private var fillRatio: Double { HPReadout.ratio(hp: side.hp, max: side.stats.hp) }
}

// MARK: - 필드 (Showdown 배치)

/// 상대는 우상단 정면, 나는 좌하단 **등 스프라이트**. 배경은 단색 그라데이션이다 —
/// 배경 이미지는 안 넣는다(에셋 용량을 늘릴 이유가 없다, 계획 §6.5).
struct BattleFieldView: View {
    let mine: BattleSide
    let theirs: BattleSide
    let myTitle: String
    let theirTitle: String
    let l: L

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color.accentColor.opacity(0.10), Color.primary.opacity(0.03)],
                           startPoint: .top, endPoint: .bottom)
            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 6) {
                    CombatantBar(side: theirs, title: theirTitle, l: l, revealsExactHP: false)
                        .frame(width: BattleFieldMetrics.barWidth)
                    Spacer(minLength: 0)
                    combatant(theirs, size: BattleFieldMetrics.opponentSpriteSize, back: false)
                }
                Spacer(minLength: 0)
                HStack(alignment: .bottom, spacing: 6) {
                    combatant(mine, size: BattleFieldMetrics.mySpriteSize, back: true)
                    Spacer(minLength: 0)
                    CombatantBar(side: mine, title: myTitle, l: l, revealsExactHP: true)
                        .frame(width: BattleFieldMetrics.barWidth)
                }
            }
            .padding(8)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    /// 스프라이트 + 지면 타원 그림자. 기절하면 흐려진다(Phase 7 이 여기에 낙하 연출을 얹는다).
    private func combatant(_ side: BattleSide, size: CGFloat, back: Bool) -> some View {
        VStack(spacing: -3) {
            SpriteView(speciesID: side.snapshot.speciesID, size: size, animated: true,
                       shiny: side.snapshot.isShiny, back: back)
                .opacity(side.isAlive ? 1 : 0.3)
            Ellipse()
                .fill(Color.primary.opacity(0.14))
                .frame(width: size * 0.62, height: size * 0.12)
                .blur(radius: 1.5)
        }
    }
}

// MARK: - 선택 패널 (Showdown 버튼)

/// 타입색 배경 + 분류 아이콘 + 위력·명중·PP. 예전엔 4개가 전부 회색 `.bordered` 였다.
struct MoveGridView: View {
    let moves: [MoveSpec]
    /// 비어 있으면 PP 를 표시하지 않는다 — 발버둥은 PP 개념이 없다.
    let pp: [Int]
    let language: AppLanguage
    let isEnabled: Bool
    let onChoose: (Int) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 5), GridItem(.flexible(), spacing: 5)],
                  spacing: 5) {
            ForEach(Array(moves.enumerated()), id: \.offset) { index, move in
                button(move, index: index)
            }
        }
    }

    private func button(_ move: MoveSpec, index: Int) -> some View {
        let remaining = pp.indices.contains(index) ? pp[index] : nil
        let tier = remaining.map { PPTier.of(remaining: $0, max: move.pp) } ?? .ample
        return Button { onChoose(index) } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 3) {
                    Image(systemName: move.damageClass.symbolName).font(.system(size: 8, weight: .bold))
                    Text(move.name(language)).font(.caption2.bold()).lineLimit(1)
                }
                HStack(spacing: 5) {
                    // 변화기는 위력이, 필중기는 명중이 "없다" — 0 이나 ∞ 로 쓰면 있는 값처럼 읽힌다.
                    Text(move.damageClass == .status ? "—" : "\(move.power)")
                    Text(move.accuracy.map { "\($0)%" } ?? "—")
                    Spacer(minLength: 2)
                    if let remaining {
                        Text("\(remaining)/\(move.pp)")
                            .padding(.horizontal, tier == .ample ? 0 : 3)
                            .background(tier == .ample ? Color.clear : tier.color, in: Capsule())
                    }
                }
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
            }
            .foregroundStyle(move.type.battleLabelColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(move.type.battleColor.opacity(tier.isSelectable ? 1 : 0.35),
                        in: RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled || !tier.isSelectable)
        .help(move.description(language) ?? move.name(language))
    }
}

/// 교체 슬롯 — 미니 스프라이트 + HP바 + 상태 배지. 팀 연습의 스트립을 일반화했다.
struct SwitchStripView: View {
    let slots: [SwitchSlot]
    let label: String
    let isEnabled: Bool
    let onSwitch: (Int) -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(label).font(.system(size: 8, weight: .semibold)).foregroundStyle(.secondary)
            ForEach(slots) { slot in
                Button { onSwitch(slot.index) } label: {
                    VStack(spacing: 1) {
                        SpriteView(speciesID: slot.side.snapshot.speciesID, size: 22,
                                   shiny: slot.side.snapshot.isShiny)
                            .opacity(slot.side.isAlive ? 1 : 0.3)
                        Capsule()
                            .fill(HPTier.of(hp: slot.side.hp, max: slot.side.stats.hp).color)
                            .frame(width: 20, height: 3)
                        StatusBadgeRow(side: slot.side)
                    }
                }
                .buttonStyle(.plain)
                .padding(2)
                .background(RoundedRectangle(cornerRadius: 5)
                    .fill(slot.isActive ? Color.accentColor.opacity(0.20) : Color.primary.opacity(0.05)))
                .disabled(!isEnabled || !slot.isSelectable)
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - 로그 칸

/// 최근 `BattleFieldMetrics.logLines` 줄만, **고정 높이**로. 세 모드가 같은 칸을 쓴다 — 멀티만
/// 높이·줄바꿈 제한이 없던 동안은 긴 줄이 감겨 아래 기술 버튼을 밀어냈다.
/// `ScrollView` 를 쓰지 않는 이유는 `BattleFieldMetrics.logLines` 주석에 있다.
struct BattleLogBox: View {
    let lines: [BattleLog.Line]
    /// 내 편 줄을 진하게 그리는 기준.
    let myActor: BattleActor?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(lines.suffix(BattleFieldMetrics.logLines).enumerated()), id: \.offset) { _, line in
                Text(line.text)
                    .font(.system(size: 9))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(line.actor == myActor ? .primary : .secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, minHeight: BattleFieldMetrics.logHeight,
               maxHeight: BattleFieldMetrics.logHeight, alignment: .topLeading)
        // 고정 높이는 **보고하는** 높이만 고정한다 — 넘친 줄은 칸 밖에 그려져 기술 버튼 위에 겹친다.
        // 줄 수가 칸에 맞는지는 `testTheLogBoxIsTallEnoughForTheLinesItDraws` 가 지키고, 이 clip 은
        // 그 가드를 넘어선 경우에도 조작을 가리지 않게 하는 두 번째 방어선이다.
        .clipped()
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
    }
}

// MARK: - 배틀 화면 전체 (순수 렌더러)

/// 필드 + 선택 패널 + 옆 로그. 상태를 하나도 들지 않는 **순수 렌더러**라 세 모드가 같은 화면을
/// 쓰고, 테스트가 실제 폭·높이를 잴 수 있다.
struct BattleArenaView: View {
    let mine: BattleSide
    let theirs: BattleSide
    let myTitle: String
    let theirTitle: String
    let l: L
    let turn: Int
    let logLines: [BattleLog.Line]
    /// 로그에서 내 편 줄을 진하게 그리는 기준.
    let myActor: BattleActor
    /// 비었으면 교체 줄을 안 그린다 — 단일전과 교체할 아군이 없는 화면은 줄 자체가 필요 없다.
    let switchSlots: [SwitchSlot]
    let turnEndsAt: Date?
    let isWaitingForOpponent: Bool
    let onChoose: (Int) -> Void
    let onSwitch: (Int) -> Void
    let onForfeit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: BattleFieldMetrics.spacing) {
            header
            BattleFieldView(mine: mine, theirs: theirs,
                            myTitle: myTitle, theirTitle: theirTitle, l: l)
                .frame(height: BattleFieldMetrics.fieldHeight)
            if isWaitingForOpponent {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text(l.battleWaitingOpponent).font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text(l.battleYourTurn)
                    .font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
            }
            MoveGridView(moves: mine.mustStruggle ? [.struggle()] : mine.moves,
                         pp: mine.mustStruggle ? [] : mine.pp,
                         language: l.lang,
                         isEnabled: !isWaitingForOpponent,
                         onChoose: { onChoose(mine.mustStruggle ? -1 : $0) })
            if !switchSlots.isEmpty {
                SwitchStripView(slots: switchSlots, label: l.battleSwitch,
                                isEnabled: !isWaitingForOpponent, onSwitch: onSwitch)
            }
            BattleLogBox(lines: logLines, myActor: myActor)
        }
        // 팝오버가 주는 폭을 넘겨 요구하지 않는다 — 넘기면 매번 압축돼 그려진다. 바깥 여백은
        // 팝오버(`PopoverMetrics.padding`)가 이미 준다.
        .frame(maxWidth: BattleFieldMetrics.width, alignment: .leading)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(l.battleTurnLabel(turn)).font(.caption.bold()).monospacedDigit()
            if let turnEndsAt, !isWaitingForOpponent {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let left = max(0, Int(turnEndsAt.timeIntervalSince(context.date)))
                    Text("\(left)s")
                        .font(.caption.monospacedDigit().bold())
                        .foregroundStyle(left <= 5 ? .red : .orange)
                }
            }
            Spacer()
            Button(l.battleForfeit, action: onForfeit)
                .controlSize(.mini)
                .foregroundStyle(.secondary)
        }
    }

}

// MARK: - 스트림 → 로그 줄

/// 좌우 두 자리인 배틀(1v1 LAN·연습)의 스트림을 로그 줄로 접는다. 문구 결정은 전부 `BattleLog` 에
/// 있고 여기는 "누가 내 편인가" 와 이름·기술명만 붙인다 — 뷰는 순수 렌더러로 남는다.
enum BattleLogSource {
    static func twoSided(_ events: [BattleEvent], mine: BattleActor, l: L,
                         myName: String, theirName: String,
                         myMoves: [MoveSpec], theirMoves: [MoveSpec]) -> [BattleLog.Line] {
        BattleLog.lines(events, l: l,
                        name: { $0 == mine ? myName : theirName },
                        moveName: { actor, id in
                            let moves = actor == mine ? myMoves : theirMoves
                            return (moves.first { $0.id == id } ?? .struggle()).name(l.lang)
                        })
    }

    /// LAN 팀전 누적 로그 — 각 턴이 발생했을 때의 활성 포켓몬 문맥으로 이름과 기술을 해석한다.
    static func netBattle(_ battle: NetBattleState, mine: BattleActor, l: L) -> [BattleLog.Line] {
        if battle.eventBatches.isEmpty {
            return twoSided(battle.events, mine: mine, l: l,
                            myName: battle.me.snapshot.name, theirName: battle.opp.snapshot.name,
                            myMoves: battle.me.moves, theirMoves: battle.opp.moves)
        }
        return battle.eventBatches.flatMap { batch in
            let myContext = mine == .a ? batch.a : batch.b
            let theirContext = mine == .a ? batch.b : batch.a
            return twoSided(batch.events, mine: mine, l: l,
                            myName: myContext.name, theirName: theirContext.name,
                            myMoves: myContext.moves, theirMoves: theirContext.moves)
        }
    }
}
