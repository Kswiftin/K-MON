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

    /// 필드 칸이 둘인 배틀(웨이브 런의 2대2)용 — **필드에 서 있는 모든 개체**를 활성으로 본다.
    /// 활성 칸이 하나라는 전제로 그리면 나머지 칸에 선 개체가 교체 후보로 남아, 한 개체가 두 자리에
    /// 서게 된다(코어가 막지만 화면은 누를 수 있는 버튼을 보여 준다).
    static func slots(_ sides: [BattleSide], activeIndices: Set<Int>) -> [SwitchSlot] {
        sides.indices.map { SwitchSlot(index: $0, side: sides[$0],
                                       isActive: activeIndices.contains($0)) }
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
        // 잠듦과 같은 회색을 주면 "독·맹독만 색을 공유한다"는 배지 불변식이 조용히 깨진다.
        // 하한 단언(`>= 6`)만 두면 테스트가 그걸 통과시킨다.
        case .flinch:          return .brown
        }
    }
}

/// 랭크 화살표 — `Atk▲2 Spe▼1`. **뷰 밖의 순수 함수다**(`badgeTint` 와 같은 이유): 뷰 안의
/// `private var` 로 두면 화면에 뜬 조합만 실행되고 나머지는 커버리지에서 초록으로 보고된다.
///
/// 0 인 랭크는 빼고 캐논 순서(공·방·특공·특방·스피드·명중·회피)로 붙인다. 순서가 흔들리면
/// 같은 상태가 턴마다 다른 문자열로 보인다.
enum StageReadout {
    static func text(_ stages: [BattleStat: Int]) -> String? {
        let parts = BattleStat.allCases.compactMap { stat -> String? in
            guard let stage = stages[stat], stage != 0 else { return nil }
            return "\(stat.shortLabel)\(stage > 0 ? "▲" : "▼")\(abs(stage))"
        }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }
}

struct StageArrows: View {
    let side: BattleSide

    var body: some View {
        if let text = StageReadout.text(side.stages) {
            Text(text)
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                // 일곱 축이 다 붙으면 칸보다 넓다. 우선도를 낮춰 **화살표가 먼저 잘리게** 한다 —
                // 같은 우선도면 옆의 HP 표기까지 깎인다. 총폭 검증으론 못 잡는 부분이다.
                .layoutPriority(-1)
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
/// 랭크 화살표(▲▼)는 이름 줄이 아니라 **HP 표기 줄**에 있다. 이름 줄에 넣으면 332pt 폭에서
/// 이름이 먼저 잘린다 — 누가 싸우는지가 랭크보다 중요하다.
struct CombatantBar: View {
    let side: BattleSide
    let title: String
    let l: L
    /// 내 쪽만 실수치를 보여 준다 — 상대는 % 다(`HPReadout`).
    let revealsExactHP: Bool
    /// 재생이 값을 움직이는 동안만 바를 보간한다. **끄기·저전력에서는 보간도 없어야 한다** —
    /// 끄기가 있는 이유가 저전력과 접근성이라, 여기에 상시 애니메이션을 걸면 "안 움직이는 화면"
    /// 이라는 그 설정의 약속이 깨진다(값은 한 번에 오는데 바만 0.4초 흐른다).
    var animatesHP = false

    private var tier: HPTier { HPTier.of(hp: side.hp, max: side.stats.hp) }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                if side.snapshot.isShiny { Text("✨").font(.system(size: 9)) }
                Text(side.snapshot.name).font(.caption.bold()).lineLimit(1)
                Text(l.battleLv(side.snapshot.level))
                    .font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
                // 이름이 이미 이 줄에서 가장 먼저 잘리는 요소다(위 주석) — 타입 배지는 그 뒤,
                // 로그 칩·기술 버튼과 같은 타입색 팔레트(`battleColor`)로 작게 붙인다.
                ForEach(side.snapshot.types, id: \.self) { type in
                    Text(type.name(l.lang).uppercased())
                        .font(.system(size: 7, weight: .heavy))
                        .foregroundStyle(type.battleLabelColor)
                        .padding(.horizontal, 3).padding(.vertical, 1)
                        .background(type.battleColor, in: Capsule())
                }
                Spacer(minLength: 2)
                StatusBadgeRow(side: side)
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.12))
                    Capsule().fill(tier.color)
                        .frame(width: geometry.size.width * CGFloat(fillRatio))
                        // 재생이 HP 를 스텝마다 바꾸므로 바는 그 사이를 보간하기만 하면 된다.
                        // 연출이 꺼져 있으면(`animatesHP == false`) 보간도 걸지 않는다 —
                        // 값만 즉시 오고 바가 0.4초 흐르면 "끄기" 가 끄기가 아니다.
                        .animation(animatesHP ? .easeOut(duration: 0.4) : nil, value: side.hp)
                }
            }
            .frame(height: 6)
            HStack(spacing: 4) {
                Text(title).font(.system(size: 8)).foregroundStyle(.tertiary).lineLimit(1)
                Spacer(minLength: 2)
                StageArrows(side: side)
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
    /// 좌우 두 자리인 배틀에서 내가 어느 쪽인가 — 재생 오버레이가 가리키는 `BattleActor` 를
    /// 화면의 위·아래로 옮기는 데만 쓴다. 결과 화면처럼 재생이 없으면 필요 없다.
    var myActor: BattleActor = .a
    var overlay: ReplayOverlay = .idle
    /// 손가락흔들기처럼 전투원의 정규 무브셋 밖에서 호출된 기술의 연출 데이터.
    var calledMoves: [MoveSpec] = []

    private var activeMove: MoveSpec? {
        guard let actor = overlay.moveActor, let moveID = overlay.moveID else { return nil }
        let side = actor == myActor ? mine : theirs
        return (side.moves + calledMoves).first { $0.id == moveID }
            ?? (moveID == MoveSpec.struggleID ? .struggle() : nil)
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color.accentColor.opacity(0.10), Color.primary.opacity(0.03)],
                           startPoint: .top, endPoint: .bottom)
            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 6) {
                    CombatantBar(side: theirs, title: theirTitle, l: l, revealsExactHP: false,
                                 animatesHP: overlay.isPlaying)
                        .frame(width: BattleFieldMetrics.barWidth)
                    Spacer(minLength: 0)
                    combatant(theirs, size: BattleFieldMetrics.opponentSpriteSize, back: false,
                              isStruck: overlay.hit != nil && overlay.hit != myActor)
                }
                Spacer(minLength: 0)
                HStack(alignment: .bottom, spacing: 6) {
                    combatant(mine, size: BattleFieldMetrics.mySpriteSize, back: true,
                              isStruck: overlay.hit == myActor)
                    Spacer(minLength: 0)
                    CombatantBar(side: mine, title: myTitle, l: l, revealsExactHP: true,
                                 animatesHP: overlay.isPlaying)
                        .frame(width: BattleFieldMetrics.barWidth)
                }
            }
            .padding(8)
            if let move = activeMove, let actor = overlay.moveActor {
                BattleMoveEffect(move: move, attacksFromMine: actor == myActor)
                    .id("\(actor)-\(move.id)-\(overlay.isPlaying)")
                    .allowsHitTesting(false)
            }
            // 팝 문구는 **필드 위에 겹쳐** 그린다. 흐름에 넣으면 뜰 때마다 아래 기술 버튼이 밀려
            // 내려가고, 팝오버는 넘친 만큼을 잘라 낸다(`testTheArenaKeepsItsBudgetWhileAPhrasePopped`).
            if let phrase = overlay.popped.flatMap({ BattleReplay.popup(for: $0, l: l) }) {
                Text(phrase)
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(Color.black.opacity(0.55)))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    /// 스프라이트 + 지면 타원 그림자. 기절하면 흐려지고, 맞은 턴엔 잠깐 흔들리며 번쩍인다.
    /// 흔들림은 **맞은 쪽**에만 건다 — 때린 쪽이 흔들리면 누가 맞았는지 반대로 읽힌다.
    private func combatant(_ side: BattleSide, size: CGFloat, back: Bool,
                           isStruck: Bool) -> some View {
        VStack(spacing: -3) {
            ZStack {
                SpriteView(speciesID: side.snapshot.speciesID, size: size, animated: true,
                           shiny: side.snapshot.isShiny, back: back)
                    .opacity(side.isAlive ? (isStruck ? 0.45 : 1) : 0.12)
                    .scaleEffect(side.isAlive ? 1 : 0.72, anchor: .bottom)
                    .rotationEffect(.degrees(side.isAlive ? 0 : (back ? -9 : 9)))
                    .offset(x: isStruck ? 4 : 0, y: side.isAlive ? 0 : size * 0.18)
                    .animation(.easeInOut(duration: 0.08).repeatCount(4, autoreverses: true),
                               value: isStruck)
                    .animation(.easeIn(duration: 0.58), value: side.isAlive)

                if !side.isAlive {
                    Text(l.t("기절", "FAINTED", "ひんし"))
                        .font(.system(size: max(10, size * 0.12), weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.red.opacity(0.9)))
                        .overlay(Capsule().stroke(Color.white.opacity(0.85), lineWidth: 1.5))
                        .shadow(color: .black.opacity(0.3), radius: 3, y: 2)
                        .transition(.scale(scale: 1.45).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.42, dampingFraction: 0.68), value: side.isAlive)
            Ellipse()
                .fill(Color.primary.opacity(side.isAlive ? 0.14 : 0.05))
                .frame(width: size * 0.62, height: size * 0.12)
                .blur(radius: 1.5)
                .animation(.easeOut(duration: 0.45), value: side.isAlive)
        }
    }
}

/// 기술 타입과 분류를 짧은 벡터 연출로 표현한다. 외부 이미지가 없어 오프라인 배틀에서도 동일하며,
/// 저전력/연출 끄기는 재생기에서 오버레이 자체를 내리지 않으므로 자동으로 정지 화면이 된다.
private enum BattleMoveAnimationStyle {
    case hydroPump, fireBlast, beam, wave, slash, punch, bite, charge, quake, storm
    case drain, heal, buff, ailment, projectile

    /// 모든 기술이 반드시 한 프로필을 얻는다. 잘 알려진 동작군은 ID로 고정하고, 새 기술이나
    /// 미분류 기술은 분류·타입·부가효과로 의미 있는 폴백을 고른다.
    static func resolve(_ move: MoveSpec) -> Self {
        if move.id == 56 { return .hydroPump }
        if move.id == 126 { return .fireBlast }
        if [13, 15, 75, 163, 210, 314, 332, 400, 403, 427, 440].contains(move.id) { return .slash }
        if [4, 5, 7, 8, 9, 146, 183, 223, 264, 309, 325, 327, 359, 409, 418].contains(move.id) { return .punch }
        if [44, 158, 242, 305, 422, 423, 424].contains(move.id) { return .bite }
        if [33, 34, 36, 38, 66, 98, 130, 224, 229, 263, 276, 394, 428].contains(move.id) { return .charge }
        if [89, 90, 222, 284, 328, 414, 523].contains(move.id) { return .quake }
        if [16, 19, 59, 87, 239, 257, 542].contains(move.id) { return .storm }
        if [58, 63, 76, 85, 93, 94, 247, 324, 406, 408, 411, 430, 434, 451, 473].contains(move.id) { return .beam }
        if [55, 57, 61, 83, 127, 145, 250, 352, 503].contains(move.id) { return .wave }
        if move.drainPercent > 0 { return .drain }
        if move.healingPercent > 0 || move.id == MoveSpec.restMoveID { return .heal }
        if move.damageClass == .status {
            if move.inflictedStatus != nil { return .ailment }
            return .buff
        }
        if move.damageClass == .physical { return move.power >= 90 ? .charge : .punch }
        if move.power >= 100 { return .beam }
        return .projectile
    }
}

/// 기술 연출 오버레이. `internal` 인 이유는 웨이브 런의 2대2 경기장(`WaveRunArenaView`)이 같은
/// 연출을 써야 하기 때문이다 — 화면마다 따로 그리면 같은 기술이 화면에 따라 달라 보인다.
struct BattleMoveEffect: View {
    let move: MoveSpec
    let attacksFromMine: Bool
    @State private var progress = false
    @State private var impactBurst = false
    private var style: BattleMoveAnimationStyle { .resolve(move) }

    var body: some View {
        GeometryReader { proxy in
            let start = attacksFromMine
                ? CGPoint(x: proxy.size.width * 0.24, y: proxy.size.height * 0.72)
                : CGPoint(x: proxy.size.width * 0.78, y: proxy.size.height * 0.27)
            let end = attacksFromMine
                ? CGPoint(x: proxy.size.width * 0.77, y: proxy.size.height * 0.28)
                : CGPoint(x: proxy.size.width * 0.25, y: proxy.size.height * 0.70)

            ZStack {
                battleBackdrop
                speedLines(from: start, to: end)
                switch style {
                case .hydroPump:
                    hydroPump(from: start, to: end)
                case .fireBlast:
                    fireBlast(from: start, to: end)
                case .beam, .wave:
                    energyLine(from: start, to: end, isWave: style == .wave)
                case .slash:
                    slashEffect(at: end)
                case .punch, .bite, .charge:
                    projectileTrail(from: start, to: end)
                    projectile
                        .position(progress ? end : start)
                    impact
                        .position(end)
                        .opacity(impactBurst ? 0.95 : 0)
                        .scaleEffect(impactBurst ? 1.35 : 0.25)
                case .quake, .storm:
                    fieldEffect(at: end, storm: style == .storm)
                case .drain:
                    drainEffect(from: end, to: start)
                case .heal, .buff, .ailment:
                    statusAura.position(style == .heal || style == .buff ? start : end)
                case .projectile:
                    projectileTrail(from: start, to: end)
                    projectile.position(progress ? end : start)
                    impact.position(end).opacity(impactBurst ? 0.95 : 0)
                        .scaleEffect(impactBurst ? 1.35 : 0.25)
                }
                typeParticles(at: end)
            }
            .onAppear {
                withAnimation(.timingCurve(0.18, 0.72, 0.24, 1, duration: 0.42)) { progress = true }
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(300))
                    withAnimation(.spring(response: 0.22, dampingFraction: 0.52)) { impactBurst = true }
                }
            }
        }
    }

    private var battleBackdrop: some View {
        RadialGradient(colors: [move.type.battleColor.opacity(impactBurst ? 0.22 : 0.04), .clear],
                       center: .center, startRadius: 5, endRadius: impactBurst ? 190 : 70)
            .animation(.easeOut(duration: 0.32), value: impactBurst)
            .allowsHitTesting(false)
    }

    private func speedLines(from start: CGPoint, to end: CGPoint) -> some View {
        ZStack {
            ForEach(0..<7, id: \.self) { index in
                attackPath(from: CGPoint(x: start.x, y: start.y + CGFloat(index - 3) * 8),
                           to: CGPoint(x: end.x, y: end.y + CGFloat(index - 3) * 13))
                    .trim(from: progress ? 0.62 : 0, to: progress ? 1 : 0.12)
                    .stroke(move.type.battleColor.opacity(0.12),
                            style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            }
        }.allowsHitTesting(false)
    }

    private func projectileTrail(from start: CGPoint, to end: CGPoint) -> some View {
        ZStack {
            ForEach(0..<5, id: \.self) { index in
                let ratio = CGFloat(index + 1) / 7
                Circle().fill(move.type.battleColor.opacity(0.34 - Double(index) * 0.045))
                    .frame(width: CGFloat(14 - index * 2), height: CGFloat(14 - index * 2))
                    .position(x: start.x + (end.x - start.x) * ratio,
                              y: start.y + (end.y - start.y) * ratio)
                    .opacity(progress ? 0 : 0.8)
                    .animation(.easeOut(duration: 0.34).delay(Double(index) * 0.025), value: progress)
            }
        }
    }

    private func typeParticles(at point: CGPoint) -> some View {
        ZStack {
            ForEach(0..<10, id: \.self) { index in
                Image(systemName: projectileSymbol)
                    .font(.system(size: CGFloat(5 + index % 3)))
                    .foregroundStyle(index.isMultiple(of: 3) ? Color.white : move.type.battleColor)
                    .offset(x: impactBurst ? cos(Double(index) * .pi / 5) * CGFloat(28 + index * 2) : 0,
                            y: impactBurst ? sin(Double(index) * .pi / 5) * CGFloat(22 + index * 2) : 0)
                    .opacity(impactBurst ? 0 : 0.85)
                    .scaleEffect(impactBurst ? 1.25 : 0.35)
            }
        }
        .position(point)
        .animation(.easeOut(duration: 0.48), value: impactBurst)
        .allowsHitTesting(false)
    }

    private func attackPath(from start: CGPoint, to end: CGPoint) -> Path {
        Path { path in
            path.move(to: start)
            path.addLine(to: end)
        }
    }

    /// 하이드로펌프 — 굵은 고압 물줄기와 물방울이 공격자에서 상대까지 뻗는다.
    @ViewBuilder
    private func hydroPump(from start: CGPoint, to end: CGPoint) -> some View {
        ZStack {
            attackPath(from: start, to: end)
                .trim(from: 0, to: progress ? 1 : 0)
                .stroke(Color.cyan.opacity(0.32), style: StrokeStyle(lineWidth: 18, lineCap: .round))
                .blur(radius: 3)
            attackPath(from: start, to: end)
                .trim(from: 0, to: progress ? 1 : 0)
                .stroke(Color.blue, style: StrokeStyle(lineWidth: 11, lineCap: .round))
            attackPath(from: start, to: end)
                .trim(from: 0, to: progress ? 1 : 0)
                .stroke(Color.white.opacity(0.8), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            ForEach(0..<7, id: \.self) { index in
                let ratio = CGFloat(index + 1) / 8
                Circle()
                    .fill(index.isMultiple(of: 2) ? Color.cyan : Color.blue)
                    .frame(width: 5, height: 5)
                    .position(x: start.x + (end.x - start.x) * ratio,
                              y: start.y + (end.y - start.y) * ratio + (index.isMultiple(of: 2) ? -9 : 9))
                    .opacity(progress ? 0.9 : 0)
                    .scaleEffect(progress ? 1 : 0.2)
            }
            impact.position(end).opacity(progress ? 1 : 0).scaleEffect(progress ? 1.5 : 0.2)
        }
    }

    /// 불대문자 — 불꽃으로 된 大 문양이 날아가며 착탄 지점에서 크게 번진다.
    @ViewBuilder
    private func fireBlast(from start: CGPoint, to end: CGPoint) -> some View {
        ZStack {
            Text("大")
                .font(.system(size: progress ? 38 : 18, weight: .black, design: .rounded))
                .foregroundStyle(.yellow)
                .shadow(color: .orange, radius: 3)
                .shadow(color: .red, radius: 7)
                .position(progress ? end : start)
            ForEach(0..<8, id: \.self) { index in
                Image(systemName: "flame.fill")
                    .font(.system(size: 9 + CGFloat(index % 3) * 2))
                    .foregroundStyle(index.isMultiple(of: 2) ? Color.yellow : Color.orange)
                    .offset(y: progress ? -CGFloat(22 + index * 3) : 0)
                    .rotationEffect(.degrees(Double(index) * 45))
                    .position(end)
                    .opacity(progress ? 0.15 : 0.9)
            }
        }
    }

    @ViewBuilder
    private func energyLine(from start: CGPoint, to end: CGPoint, isWave: Bool) -> some View {
        ZStack {
            attackPath(from: start, to: end)
                .trim(from: 0, to: progress ? 1 : 0)
                .stroke(move.type.battleColor.opacity(0.28),
                        style: StrokeStyle(lineWidth: isWave ? 15 : 10, lineCap: .round,
                                           dash: isWave ? [7, 5] : []))
                .blur(radius: 3)
            attackPath(from: start, to: end)
                .trim(from: 0, to: progress ? 1 : 0)
                .stroke(move.type.battleColor,
                        style: StrokeStyle(lineWidth: isWave ? 5 : 4, lineCap: .round,
                                           dash: isWave ? [7, 5] : []))
            if !isWave {
                Circle().fill(Color.white).frame(width: 8, height: 8)
                    .shadow(color: move.type.battleColor, radius: 7)
                    .position(progress ? end : start)
            }
            impact.position(end).opacity(progress ? 1 : 0).scaleEffect(progress ? 1.2 : 0.2)
        }
    }

    @ViewBuilder
    private func slashEffect(at point: CGPoint) -> some View {
        ZStack {
            ForEach(0..<3, id: \.self) { index in
                Capsule()
                    .fill(LinearGradient(colors: [.white, move.type.battleColor],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: progress ? 54 : 5, height: 4)
                    .rotationEffect(.degrees(-38))
                    .offset(y: CGFloat(index - 1) * 13)
                    .opacity(progress ? 0.9 : 0)
            }
        }
        .position(point)
    }

    @ViewBuilder
    private func fieldEffect(at point: CGPoint, storm: Bool) -> some View {
        ZStack {
            ForEach(0..<9, id: \.self) { index in
                Image(systemName: storm ? projectileSymbol : "diamond.fill")
                    .font(.system(size: CGFloat(7 + index % 4)))
                    .foregroundStyle(move.type.battleColor)
                    .offset(x: CGFloat((index % 3) - 1) * 24,
                            y: progress ? CGFloat(30 - (index / 3) * 25) : -45)
                    .rotationEffect(.degrees(progress ? Double(index * 55) : 0))
                    .opacity(progress ? 0.2 : 0.95)
            }
            if !storm {
                Ellipse().stroke(move.type.battleColor, lineWidth: 4)
                    .frame(width: progress ? 82 : 18, height: progress ? 28 : 7)
                    .opacity(progress ? 0.1 : 0.9)
            }
        }
        .position(point)
    }

    @ViewBuilder
    private func drainEffect(from start: CGPoint, to end: CGPoint) -> some View {
        ZStack {
            ForEach(0..<6, id: \.self) { index in
                Circle()
                    .fill(index.isMultiple(of: 2) ? move.type.battleColor : Color.green)
                    .frame(width: CGFloat(6 + index % 3), height: CGFloat(6 + index % 3))
                    .position(progress ? end : CGPoint(x: start.x + CGFloat(index - 3) * 6,
                                                       y: start.y + CGFloat(index % 2) * 8))
                    .shadow(color: .green.opacity(0.7), radius: 4)
            }
        }
    }

    private var projectile: some View {
        ZStack {
            Circle().fill(move.type.battleColor.opacity(0.24)).frame(width: 34, height: 34).blur(radius: 3)
            Image(systemName: projectileSymbol)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(move.type.battleColor)
                .shadow(color: move.type.battleColor.opacity(0.8), radius: 5)
        }
    }

    /// 전용 연출이 아직 없는 기술도 타입에 맞는 모양으로 보인다. 기술 ID별 연출은 위 분기에
    /// 계속 추가할 수 있고, 여기 폴백 덕분에 새 PokéAPI 기술이 무표정하게 지나가지 않는다.
    private var projectileSymbol: String {
        if move.damageClass == .physical { return "burst.fill" }
        switch move.type {
        case .fire:                         return "flame.fill"
        case .water, .ice:                  return "drop.fill"
        case .electric:                     return "bolt.fill"
        case .grass, .bug:                  return "leaf.fill"
        case .flying:                       return "wind"
        case .rock, .ground, .steel:        return "diamond.fill"
        case .poison, .ghost, .dark:        return "smoke.fill"
        case .psychic, .fairy, .dragon:     return "sparkles"
        case .normal, .fighting:            return "circle.fill"
        }
    }

    private var impact: some View {
        ZStack {
            Circle().stroke(move.type.battleColor, lineWidth: 3).frame(width: 38, height: 38)
            ForEach(0..<6, id: \.self) { index in
                Capsule().fill(move.type.battleColor)
                    .frame(width: 3, height: 13)
                    .offset(y: -27)
                    .rotationEffect(.degrees(Double(index) * 60))
            }
        }
    }

    private var statusAura: some View {
        ZStack {
            Circle().stroke(move.type.battleColor.opacity(0.75), lineWidth: 3)
                .frame(width: progress ? 58 : 18, height: progress ? 58 : 18)
                .opacity(progress ? 0.1 : 1)
            Image(systemName: "sparkles")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(move.type.battleColor)
                .scaleEffect(progress ? 1.15 : 0.65)
        }
        .animation(.easeOut(duration: 0.4), value: progress)
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
    /// 초보자 모드일 때만 상대 타입을 넘긴다. nil 이면 상성 정보가 버튼에 전혀 나타나지 않는다.
    var effectivenessAgainst: [PokemonType]? = nil
    /// 광역기(`MoveSpec.hitsSpread`)에 범위 표시를 붙일까. **필드에 둘 이상이 설 때만 켠다** —
    /// 1대1 에서는 가리킬 대상이 하나뿐이라 표시가 정보가 아니고 버튼만 복잡해진다.
    var showsSpreadMark = false
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
                    // 무엇이 전원을 때리는지 버튼에서 읽혀야 한다 — 설명 툴팁만으로는 고르는
                    // 순간에 보이지 않는다(2대2 에서 지진과 단일기의 차이가 곧 판단이다).
                    if showsSpreadMark && move.hitsSpread {
                        Image(systemName: "circle.hexagongrid.fill")
                            .font(.system(size: 7, weight: .bold))
                    }
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
                if let hint = effectivenessHint(move) {
                    Text(hint.text)
                        .font(.system(size: 7, weight: .heavy))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(hint.color, in: Capsule())
                }
            }
            .foregroundStyle(move.type.battleLabelColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            // 못 고르는 버튼은 못 고르게 **보여야** 한다. PP 가 마른 칸만 흐리게 두는 동안,
            // 재생 중 잠긴 네 칸은 평소와 똑같아 보여서 눌러 보고서야 잠긴 걸 알았다.
            .background(move.type.battleColor.opacity(isEnabled && tier.isSelectable ? 1 : 0.35),
                        in: RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled || !tier.isSelectable)
        .help(move.description(language) ?? move.name(language))
    }

    private func effectivenessHint(_ move: MoveSpec) -> (text: String, color: Color)? {
        guard move.damageClass != .status, let types = effectivenessAgainst else { return nil }
        let multiplier = TypeChart.effectiveness(move.type, against: types)
        let l = L(language)
        if multiplier == 0 { return (l.battleNoEffect, .gray) }
        if multiplier > 1 { return (l.battleSuperEffective, .green) }
        if multiplier < 1 { return (l.battleNotVeryEffective, .orange) }
        return nil
    }
}

/// 초보자 모드 혜택을 쓰는 사실을 친구 목록과 대전 화면에 동일하게 공개하는 배지.
struct BeginnerBadgeView: View {
    let l: L
    var owner: String? = nil

    var body: some View {
        let badge = l.t("🐣 저는 개초보입니다", "🐣 total newbie here", "🐣 ド初心者です")
        Text(owner.map { "\($0) · \(badge)" } ?? badge)
            .font(.system(size: 8, weight: .bold, design: .rounded))
            .foregroundStyle(Color.brown.opacity(0.88))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Color.yellow.opacity(0.28), in: RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4)
                .stroke(Color.brown.opacity(0.28), style: StrokeStyle(lineWidth: 1, dash: [2, 2])))
            .rotationEffect(.degrees(-1.5))
            .fixedSize()
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
        // 잠근 줄은 잠긴 것처럼 보여야 한다 — 직접 그린 배경은 `.disabled` 로 어두워지지 않는다
        // (defect-log: 같은 이유로 `MoveGridView` 도 배경 불투명도에 잠금을 태운다). 호출부가 아니라
        // 여기서 거는 이유는 잠금을 아는 쪽이 여기라서다.
        .opacity(isEnabled ? 1 : 0.45)
    }
}

// MARK: - 로그 칸

/// 최근 `BattleFieldMetrics.logLines` 줄만, **고정 높이**로. 세 모드가 같은 칸을 쓴다 — 멀티만
/// 높이·줄바꿈 제한이 없던 동안은 긴 줄이 감겨 아래 기술 버튼을 밀어냈다.
/// `ScrollView` 를 쓰지 않는 이유는 `BattleFieldMetrics.logLines` 주석에 있다.
struct BattleLogBox: View {
    let lines: [BattleLog.Line]
    /// 내 편 줄을 오른쪽·진하게, 상대 줄을 왼쪽·연하게 가르는 기준. **집합**인 이유는 2대2 다 —
    /// 내 편 두 칸이 각자 다른 주인(`.fighter`)이라 하나로는 한 칸만 내 편으로 읽힌다.
    /// 비어 있으면 어느 줄도 내 편이 아니다(관전 화면).
    let myActors: Set<BattleActor>

    init(lines: [BattleLog.Line], myActor: BattleActor?) {
        self.lines = lines
        self.myActors = myActor.map { [$0] } ?? []
    }

    init(lines: [BattleLog.Line], myActors: Set<BattleActor>) {
        self.lines = lines
        self.myActors = myActors
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(lines.suffix(BattleFieldMetrics.logLines).enumerated()), id: \.offset) { _, line in
                BattleLogRow(line: line, isMine: line.actor.map { myActors.contains($0) })
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

/// 로그 한 줄. 기술을 쓴 줄은 `MoveGridView`와 같은 타입색·아이콘 칩으로 그려 "무엇을 썼는지"가
/// 색으로도 읽히게 한다 — 예전엔 회색 텍스트 한 줄이라 기술 버튼과 다른 줄처럼 보였다. 턴 구분선처럼
/// 주인이 없는 줄과, 잔뎀·회복·상태처럼 기술이 없는 줄은 문구 그대로 그린다.
///
/// 정렬은 채팅처럼 **내 편은 오른쪽, 상대는 왼쪽**이다 — 누가 한 행동인지 색뿐 아니라 위치로도 읽는다.
struct BattleLogRow: View {
    let line: BattleLog.Line
    /// nil = 턴 구분선처럼 주인이 없다(가운데 정렬). true/false 는 각각 오른쪽/왼쪽.
    let isMine: Bool?

    var body: some View {
        Group {
            if let moveType = line.moveType, let damageClass = line.moveDamageClass,
               let moveDisplayName = line.moveDisplayName {
                chip(moveType: moveType, damageClass: damageClass, moveDisplayName: moveDisplayName)
            } else {
                Text(line.text)
                    .font(.system(size: 9))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(isMine == true ? .primary : .secondary)
            }
        }
        .frame(maxWidth: .infinity,
               alignment: isMine == nil ? .center : (isMine == true ? .trailing : .leading))
    }

    private func chip(moveType: PokemonType, damageClass: MoveDamageClass, moveDisplayName: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: damageClass.symbolName).font(.system(size: 7, weight: .bold))
            if let actorName = line.actorName {
                Text(actorName).font(.system(size: 9, weight: .bold)).lineLimit(1)
            }
            Text(moveDisplayName).font(.system(size: 9, weight: .semibold)).lineLimit(1)
            if let damage = line.damage {
                Text("-\(damage)").font(.system(size: 9, weight: .bold, design: .monospaced))
            }
            ForEach(line.badges, id: \.self) { badge in
                Text(badge).font(.system(size: 7, weight: .bold)).lineLimit(1)
                    .padding(.horizontal, 3)
                    .background(Color.black.opacity(0.16), in: Capsule())
            }
        }
        .foregroundStyle(moveType.battleLabelColor)
        .padding(.horizontal, 5)
        .background(moveType.battleColor, in: Capsule())
    }
}

struct BattleChatConfiguration {
    let messages: [BattleChatMessage]
    let mySenderID: UUID
    let isEnabled: Bool
    let unavailableMessage: String?
    let l: L
    let onSend: (String) -> Void
}

/// 전투 로그와 분리된 고정 높이 세션 채팅. ScrollView 안에서만 과거를 탐색한다.
struct BattleChatPanel: View {
    let configuration: BattleChatConfiguration
    @State private var draft = ""
    @State private var isReadingHistory = false
    @State private var unseenCount = 0

    private let bottomID = "battle-chat-bottom"

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(configuration.l.battleChatTitle).font(.caption.bold())
                Spacer()
                Text("\(draft.count)/\(BattleChatPolicy.maximumLength)")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 3) {
                        ForEach(configuration.messages) { message in
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text(message.senderName).font(.system(size: 10, weight: message.senderID == configuration.mySenderID ? .bold : .regular))
                                Text(message.body).font(.system(size: 10))
                            }
                            .foregroundStyle(message.senderID == configuration.mySenderID ? .primary : .secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        Color.clear.frame(height: 1).id(bottomID)
                    }
                }
                .frame(height: 82)
                .onAppear { proxy.scrollTo(bottomID, anchor: .bottom) }
                .onChange(of: configuration.messages.count) {
                    guard !isReadingHistory else { unseenCount += 1; return }
                    withAnimation { proxy.scrollTo(bottomID, anchor: .bottom) }
                }
                .simultaneousGesture(DragGesture().onChanged { _ in isReadingHistory = true })
                if unseenCount > 0 {
                    Button(configuration.l.battleChatNewMessages(unseenCount)) {
                        isReadingHistory = false; unseenCount = 0
                        withAnimation { proxy.scrollTo(bottomID, anchor: .bottom) }
                    }.font(.caption2)
                }
            }
            if let unavailable = configuration.unavailableMessage {
                Text(unavailable).font(.caption2).foregroundStyle(.secondary)
            }
            HStack(spacing: 5) {
                TextField(configuration.l.battleChatPlaceholder, text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1)
                    .onSubmit(send)
                    .disabled(!configuration.isEnabled)
                Button(configuration.l.battleChatSend, action: send)
                    .controlSize(.small).disabled(!canSend)
            }
        }
        .padding(6)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
    }

    private var canSend: Bool {
        configuration.isEnabled && BattleChatPolicy.normalizedBody(draft) != nil
    }

    private func send() {
        guard canSend else { return }
        configuration.onSend(draft); draft = ""
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
    /// 재생 중인가 · 누가 맞았나 · 무슨 문구가 떠 있나. 재생이 없으면 `.idle` 이라 예전 화면 그대로다.
    var overlay: ReplayOverlay = .idle
    var calledMoves: [MoveSpec] = []
    /// 관전 화면은 같은 경기장을 그리되 행동 버튼만 잠근다.
    var allowsActions = true
    var myBeginnerMode = false
    var theirBeginnerMode = false
    var showsForfeit = true
    let onChoose: (Int) -> Void
    let onSwitch: (Int) -> Void
    let onForfeit: () -> Void
    var chat: BattleChatConfiguration? = nil

    /// 재생이 끝나기 전에 다음 기술을 고르면 무엇이 일어났는지 보지 못한 채 턴이 넘어간다.
    private var acceptsInput: Bool {
        allowsActions && mine.isAlive && theirs.isAlive
            && BattleReplay.acceptsInput(isWaitingForOpponent: isWaitingForOpponent,
                                                    isReplaying: overlay.isPlaying)
    }

    /// 전멸했거나 관전 중인 화면에 교체 지시를 띄우지 않는다. 실제 선택 가능한 후보가 있는
    /// 당사자에게만 다음 포켓몬을 고르라고 안내해야 한다.
    private var needsForcedReplacement: Bool {
        allowsActions && !mine.isAlive && switchSlots.contains(where: \.isSelectable)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: BattleFieldMetrics.spacing) {
            header
            BattleFieldView(mine: mine, theirs: theirs,
                            myTitle: myTitle, theirTitle: theirTitle, l: l,
                            myActor: myActor, overlay: overlay, calledMoves: calledMoves)
                .frame(height: BattleFieldMetrics.fieldHeight)
            if !allowsActions {
                Label(l.t("현재 경기를 관전 중입니다.", "You are spectating this match.", "この試合を観戦中です。"),
                      systemImage: "eye.fill")
                    .font(.caption).foregroundStyle(.secondary)
            } else if isWaitingForOpponent {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text(l.battleWaitingOpponent).font(.caption).foregroundStyle(.secondary)
                }
            } else if !theirs.isAlive {
                Text(l.t("상대가 다음 포켓몬을 선택하고 있습니다…",
                         "Opponent is choosing their next Pokémon…",
                         "相手が次のポケモンを選んでいます…"))
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text(l.battleYourTurn)
                    .font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
            }
            if mine.isAlive {
                MoveGridView(moves: mine.mustStruggle ? [.struggle()] : mine.moves,
                             pp: mine.mustStruggle ? [] : mine.pp,
                             language: l.lang,
                             isEnabled: acceptsInput,
                             effectivenessAgainst: myBeginnerMode ? theirs.snapshot.types : nil,
                             onChoose: { onChoose(mine.mustStruggle ? -1 : $0) })
            } else if needsForcedReplacement {
                VStack(alignment: .leading, spacing: 5) {
                    Label(l.t("\(mine.snapshot.name)이(가) 쓰러졌습니다!",
                              "\(mine.snapshot.name) fainted!",
                              "\(mine.snapshot.name)は たおれた！"),
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.headline)
                    Text(l.t("아래에서 다음 포켓몬을 선택하세요.",
                             "Choose your next Pokémon below.",
                             "下から次のポケモンを選んでください。"))
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 11).fill(Color.red.opacity(0.88)))
                .overlay(RoundedRectangle(cornerRadius: 11)
                    .stroke(Color.orange.opacity(0.9), lineWidth: 2))
                .shadow(color: .red.opacity(0.22), radius: 6, y: 2)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            if !switchSlots.isEmpty {
                // 교체도 그 턴의 행동이다 — 기술만 잠그면 재생 중에 교체로 턴을 넘길 수 있다.
                // 흐리게 그리는 건 `SwitchStripView` 가 자기 잠금 상태로 한다.
                SwitchStripView(slots: switchSlots, label: l.battleSwitch,
                                isEnabled: acceptsInput, onSwitch: onSwitch)
            }
            BattleLogBox(lines: logLines, myActor: myActor)
            if let chat { BattleChatPanel(configuration: chat) }
        }
        // 팝오버가 주는 폭을 넘겨 요구하지 않는다 — 넘기면 매번 압축돼 그려진다. 바깥 여백은
        // 팝오버(`PopoverMetrics.padding`)가 이미 준다.
        .frame(maxWidth: BattleFieldMetrics.width, alignment: .leading)
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: needsForcedReplacement)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(l.battleTurnLabel(turn)).font(.caption.bold()).monospacedDigit()
            if myBeginnerMode {
                BeginnerBadgeView(l: l, owner: l.t("나", "YOU", "自分"))
            }
            if theirBeginnerMode {
                BeginnerBadgeView(l: l, owner: l.t("상대", "FOE", "相手"))
            }
            if let turnEndsAt, !isWaitingForOpponent {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let left = max(0, Int(turnEndsAt.timeIntervalSince(context.date)))
                    Text("\(left)s")
                        .font(.caption.monospacedDigit().bold())
                        .foregroundStyle(left <= 5 ? .red : .orange)
                }
            }
            Spacer()
            if showsForfeit {
                Button(l.battleForfeit, action: onForfeit)
                    .controlSize(.mini)
                    .foregroundStyle(.secondary)
            }
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
                        move: { actor, id in
                            let moves = actor == mine ? myMoves : theirMoves
                            return moves.first { $0.id == id } ?? .struggle()
                        })
    }

    /// LAN 팀전 누적 로그 — 각 턴이 발생했을 때의 활성 포켓몬 문맥으로 이름과 기술을 해석한다.
    ///
    /// `playedCount` 는 재생이 도달한 **평평한** 이벤트 수(`NetBattleState.events` 기준)다.
    /// 배치는 그 평평한 스트림과 같은 순서로만 쌓이므로(`resolveChosenActions`) 배치들을 가로질러
    /// 같은 개수만큼 자르면 재생 진행도와 정확히 맞는다 — 로그가 결과를 먼저 알려 주지 않는다.
    static func netBattle(_ battle: NetBattleState, mine: BattleActor, l: L,
                          playedCount: Int = .max) -> [BattleLog.Line] {
        var remaining = playedCount
        return battle.eventBatches.flatMap { batch -> [BattleLog.Line] in
            guard remaining > 0 else { return [] }
            let events = Array(batch.events.prefix(remaining))
            remaining -= events.count
            let myContext = mine == .a ? batch.a : batch.b
            let theirContext = mine == .a ? batch.b : batch.a
            return twoSided(events, mine: mine, l: l,
                            myName: myContext.name, theirName: theirContext.name,
                            myMoves: myContext.moves, theirMoves: theirContext.moves)
        }
    }
}
