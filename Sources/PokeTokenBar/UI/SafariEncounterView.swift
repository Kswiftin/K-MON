import SwiftUI

/// 사파리존 조우 화면 — 미끼/진흙/볼/도망 네 액션과 결과 배너.
///
/// **결과가 나는 즉시 `SafariVisit.currentEncounter` 가 `nil` 이 된다.** 배너를 보여주는
/// 동안에도 조우 정보(스프라이트·단계)를 화면에 붙잡아야 하므로, `displayedEncounter` 가
/// 그 마지막 스냅샷을 들고 있다가 사용자가 "계속"을 누르면 놓는다. 배너 표시 여부(`pendingOutcome`)
/// 는 이 뷰의 로컬 상태가 아니라 부모(`SafariZoneView`)가 바인딩으로 들고 있다 — 그래야 배너가
/// 뜨는 동안 부모가 이 뷰를 걷기 화면으로 바꿔치기하지 않는다.
struct SafariEncounterView: View {
    @Bindable var store: CompanionStore
    @Binding var pendingOutcome: SafariOutcome?
    @State private var displayedEncounter: SafariEncounter?
    @State private var speciesName: String?
    @State private var types: [PokemonType] = []
    @State private var abilityText: String?
    @State private var isCommitting = false
    /// 던지기→반응 두 단계가 재생되는 동안 버튼을 막는다. `isCommitting`(포획 영구 반영 대기)
    /// 과는 별개 축 — 애니메이션은 항상 먼저 끝나고, 잡았을 때만 그 뒤에 커밋이 이어진다.
    @State private var isAnimating = false
    /// 던지는 아이템(볼/미끼/진흙)의 현재 위치·회전·불투명도. 조우가 바뀌면 리셋한다.
    @State private var thrownAction: SafariAction?
    @State private var thrownItemOffset: CGSize = .zero
    @State private var thrownItemRotation: Double = 0
    @State private var thrownItemOpacity: Double = 0
    /// 포켓몬 쪽 반응 — 흔들림(shake)·축소(흡수)·투명도(페이드)·바운스(scale).
    @State private var targetShake: CGFloat = 0
    @State private var targetScale: CGFloat = 1
    @State private var targetOpacity: Double = 1
    @State private var mudOverlayOpacity: Double = 0

    private var l: L { store.l }
    private var encounter: SafariEncounter? { store.safariVisit?.currentEncounter ?? displayedEncounter }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let encounter {
                header(encounter)
                Divider()
                stageGauges(encounter)
                Divider()
                if let pendingOutcome {
                    banner(pendingOutcome)
                } else {
                    actionButtons
                }
                Divider()
                log
            }
        }
        .onChange(of: store.safariVisit?.currentEncounter) { old, new in
            if let old, new == nil { displayedEncounter = old }
            if new != nil { displayedEncounter = nil; pendingOutcome = nil; resetAnimationState() }
        }
    }

    private func resetAnimationState() {
        thrownAction = nil
        thrownItemOffset = .zero
        thrownItemRotation = 0
        thrownItemOpacity = 0
        targetShake = 0
        targetScale = 1
        targetOpacity = 1
        mudOverlayOpacity = 0
    }

    private func header(_ encounter: SafariEncounter) -> some View {
        VStack(spacing: 2) {
            ZStack {
                HStack {
                    Spacer()
                    SpriteView(speciesID: encounter.speciesID, size: 64, shiny: false)
                        .offset(x: targetShake)
                        .scaleEffect(targetScale)
                        .opacity(targetOpacity)
                    Spacer()
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 8).fill(Color.brown.opacity(mudOverlayOpacity))
                        .allowsHitTesting(false)
                )
                if let thrownAction {
                    thrownItemImage(thrownAction)
                        .offset(thrownItemOffset)
                        .rotationEffect(.degrees(thrownItemRotation))
                        .opacity(thrownItemOpacity)
                }
            }
            HStack(spacing: 4) {
                Text(speciesName ?? " ").font(.caption.bold())
                if let gender = encounter.gender, gender != .genderless {
                    Text(gender.symbol).font(.caption.bold())
                        .foregroundStyle(gender == .male ? .blue : .pink)
                }
            }
            HStack(spacing: 4) {
                ForEach(types, id: \.self) { TypeBadge(type: $0) }
            }
            if let abilityText {
                Text(abilityText).font(.caption2).foregroundStyle(.secondary)
                    .lineLimit(2).multilineTextAlignment(.center)
            }
        }
        .task(id: encounter.speciesID) {
            async let name = store.safariEncounterName(encounter.speciesID)
            async let loadedTypes = store.safariEncounterTypes(encounter.speciesID)
            async let identity = PokeAPIClient.shared.chatSpeciesIdentity(speciesID: encounter.speciesID)
            speciesName = await name
            types = await loadedTypes
            abilityText = await identity.ability
            // 조우가 뜬 직후 딱 한 번만 굴린다 — `SafariEncounter.setGender` 가 이미 정해진
            // 값이면 무시하므로, 재진입(창을 닫았다 열어도)에도 안전하다.
            if encounter.gender == nil, let gender = await store.rollSafariEncounterGender(encounter.speciesID) {
                mutate { $0.setCurrentEncounterGender(gender) }
            }
        }
    }

    private func thrownItemImage(_ action: SafariAction) -> some View {
        let sprite: PixelSprite
        let palette: PixelPalette
        switch action {
        case .ball: sprite = SafariActionPixelArt.ball; palette = SafariActionPixelArt.ballPalette
        case .bait: sprite = SafariActionPixelArt.bait; palette = SafariActionPixelArt.baitPalette
        case .mud: sprite = SafariActionPixelArt.mud; palette = SafariActionPixelArt.mudPalette
        case .run: sprite = SafariActionPixelArt.ball; palette = SafariActionPixelArt.ballPalette
        }
        guard let cgImage = sprite.cgImage(palette: palette) else { return AnyView(EmptyView()) }
        return AnyView(Image(decorative: cgImage, scale: 1).interpolation(.none)
            .resizable().frame(width: 16, height: 16))
    }

    private func stageGauges(_ encounter: SafariEncounter) -> some View {
        let catchPercent = SafariZone.catchPercent(rarity: encounter.rarity, catchStage: encounter.catchStage)
        let fleePercent = SafariZone.fleePercent(fleeStage: encounter.fleeStage)
        return HStack {
            Label(l.safariCatchPercentLabel(catchPercent), systemImage: "arrow.up.circle")
            Spacer()
            Label(l.safariFleePercentLabel(fleePercent), systemImage: "arrow.down.circle")
        }
        .font(.caption2)
    }

    private var actionButtons: some View {
        HStack(spacing: 6) {
            actionButton("\(l.safariBaitAction) 1", action: .bait, shortcut: "1")
            actionButton("\(l.safariMudAction) 2", action: .mud, shortcut: "2")
            actionButton("\(l.safariBallAction) 3", action: .ball, shortcut: "3",
                        disabled: (store.safariVisit?.balls ?? 0) <= 0)
            actionButton("\(l.safariRunAction) 4", action: .run, shortcut: "4")
        }
    }

    private func actionButton(_ title: String, action: SafariAction, shortcut: KeyEquivalent,
                              disabled: Bool = false) -> some View {
        Button(title) { perform(action) }
            .buttonStyle(.bordered).controlSize(.small)
            .disabled(disabled || isCommitting || isAnimating)
            .keyboardShortcut(shortcut, modifiers: [])
    }

    /// **던지기 → 결과 확정(`act` 호출) → 반응**, 이 순서를 지킨다. `act()` 를 던지기 애니메이션
    /// 뒤로 미루는 이유는, `act()` 가 호출되는 순간 `currentEncounter` 가 `nil` 이 될 수 있어(잡음·
    /// 도망·시간초과) 그 즉시 배너/걷기 화면 전환 로직이 반응하기 때문이다 — 애니메이션이 재생될
    /// 새도 없이 화면이 넘어간다. 결과를 먼저 정하고 그 결과에 맞는 반응(흡수/흔들림/바운스)을
    /// 재생한 뒤에야 화면을 넘긴다.
    private func perform(_ action: SafariAction) {
        guard !isAnimating else { return }
        // 도망은 사용자가 직접 조우를 그만두는 선택이라 던지는 연출이 없다 — 결과가 뻔하므로
        // (항상 놓아줌) 배너로 한 번 더 확인시키지 않고 바로 걷기 화면으로 돌아간다.
        if action == .run {
            guard let outcome = mutate({ $0.act(action) }), outcome != .continuing else { return }
            pendingOutcome = nil
            displayedEncounter = nil
            return
        }
        isAnimating = true
        Task {
            await playThrow(action)
            guard let outcome = mutate({ $0.act(action) }) else {
                isAnimating = false
                resetAnimationState()
                return
            }
            // `act()` 가 방금 `currentEncounter` 를 `nil` 로 만들었을 수 있다(잡음·도망·시간초과) —
            // `pendingOutcome` 을 반응 애니메이션 재생 **전에** 여기서 동기적으로 세워야
            // `SafariZoneView` 가 그 프레임에 이미 "배너를 보여주는 중"으로 판단한다. 반응
            // 애니메이션이 끝날 때까지 이걸 미루면, 그 사이(`currentEncounter == nil` 인데
            // `pendingOutcome` 도 아직 `nil` 인 프레임)에 부모가 걷기 화면으로 바꿔치기해 버려서
            // 화면이 통째로 비는 결함이 났다(미끼 사용 후 도망친 조우에서 실제로 재현됨).
            if outcome != .continuing {
                pendingOutcome = outcome
            }
            await playReaction(action: action, outcome: outcome)
            isAnimating = false
            resetAnimationState()
            guard outcome != .continuing else { return }
            guard outcome == .caught, let speciesID = displayedEncounter?.speciesID ?? encounter?.speciesID
            else { return }
            let gender = displayedEncounter?.gender ?? encounter?.gender
            isCommitting = true
            // act(.caught) 가 낙관적으로 이미 catchesThisVisit 을 올렸다 — 실제 영구 반영이
            // 실패하면(라인 조회 실패 등) 그 낙관적 갱신을 되돌려야 방문당 상한이 잡지도 못한
            // 개체 때문에 부풀려지지 않는다. `isCaught` 로 판정해 `RaidCatchResult` 에 새 case
            // 가 추가돼도 기본이 "실패로 보고 되돌린다" 쪽이 되게 한다. `gender` 는 조우가 뜰 때
            // 화면이 미리 굴려 보여준 값 — 여기서 새로 안 굴리고 그대로 넘겨 화면에 보여준 성별과
            // 실제로 잡힌 성별이 갈리지 않게 한다.
            if !(await store.catchInSafariZone(speciesID: speciesID, gender: gender)).isCaught {
                mutate { $0.revertUncommittedCatch() }
            }
            isCommitting = false
            // 잡았을 때도 자동으로 안 넘어간다 — 도망·시간초과와 똑같이 "계속" 버튼을 눌러야
            // 걷기 화면으로 돌아간다.
        }
    }

    /// 아이템이 트레이너 자리(화면 아래)에서 포켓몬 쪽(화면 위)으로 날아간다 — 결과와 무관한
    /// 공통 연출. 볼은 날아가며 회전한다.
    private func playThrow(_ action: SafariAction) async {
        thrownAction = action
        thrownItemOffset = CGSize(width: 0, height: 40)
        thrownItemOpacity = 1
        thrownItemRotation = 0
        let duration = 0.45
        withAnimation(.easeIn(duration: duration)) {
            thrownItemOffset = .zero
            if action == .ball { thrownItemRotation = 360 }
        }
        try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
    }

    /// 결과에 따라 포켓몬·아이템이 반응한다. 잡았으면 포켓몬이 흡수되며 볼이 몇 번 흔들리고,
    /// 볼이 실패했으면(도망·시간초과 포함) 포켓몬이 짧게 흔들리고 볼은 사라진다. 미끼/진흙은
    /// 결과와 무관하게 항상 같은 반응(바운스/흔들림+얼룩)을 보여준다.
    private func playReaction(action: SafariAction, outcome: SafariOutcome) async {
        switch action {
        case .ball where outcome == .caught:
            withAnimation(.easeIn(duration: 0.3)) { targetScale = 0.1; targetOpacity = 0 }
            try? await Task.sleep(nanoseconds: 300_000_000)
            for _ in 0..<3 {
                withAnimation(.easeInOut(duration: 0.1)) { thrownItemRotation += 20 }
                try? await Task.sleep(nanoseconds: 100_000_000)
                withAnimation(.easeInOut(duration: 0.1)) { thrownItemRotation -= 20 }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        case .ball:
            await shakeTarget()
            withAnimation(.easeOut(duration: 0.2)) { thrownItemOpacity = 0 }
            try? await Task.sleep(nanoseconds: 200_000_000)
        case .bait:
            withAnimation(.easeInOut(duration: 0.12)) { targetScale = 1.08 }
            try? await Task.sleep(nanoseconds: 120_000_000)
            withAnimation(.easeInOut(duration: 0.12)) { targetScale = 1.0 }
            try? await Task.sleep(nanoseconds: 120_000_000)
        case .mud:
            await shakeTarget()
            withAnimation(.easeIn(duration: 0.15)) { mudOverlayOpacity = 0.25 }
            try? await Task.sleep(nanoseconds: 150_000_000)
            withAnimation(.easeOut(duration: 0.15)) { mudOverlayOpacity = 0 }
            try? await Task.sleep(nanoseconds: 150_000_000)
        case .run:
            break
        }
    }

    private func shakeTarget() async {
        withAnimation(.easeInOut(duration: 0.08)) { targetShake = -6 }
        try? await Task.sleep(nanoseconds: 80_000_000)
        withAnimation(.easeInOut(duration: 0.08)) { targetShake = 6 }
        try? await Task.sleep(nanoseconds: 80_000_000)
        withAnimation(.easeInOut(duration: 0.08)) { targetShake = 0 }
    }

    private func banner(_ outcome: SafariOutcome) -> some View {
        VStack(spacing: 6) {
            Text(bannerText(outcome)).font(.caption.bold())
            Button(l.safariContinue) {
                pendingOutcome = nil
                displayedEncounter = nil
            }
            // 반응 애니메이션이 아직 재생 중일 때(`isAnimating`) 누르면, `displayedEncounter`
            // 가 비어버린 채로 애니메이션이 계속 그 값을 참조하려 들 수 있다 — 애니메이션이
            // 끝날 때까지는 막는다.
            .buttonStyle(.bordered).controlSize(.small).disabled(isCommitting || isAnimating)
        }
    }

    private func bannerText(_ outcome: SafariOutcome) -> String {
        switch outcome {
        case .caught: l.safariOutcomeCaught
        case .fled: l.safariOutcomeFled
        case .ranAway: l.safariOutcomeRanAway
        case .timedOut: l.safariOutcomeTimedOut
        case .continuing: ""
        }
    }

    /// 이번 조우에서 있었던 줄만 — 방문 전체 로그(`visitLog`)는 곁파일에 그대로 쌓이지만, 화면은
    /// 마지막 "조우 시작" 줄(`action == nil`) 이후만 보여준다. 안 그러면 새 조우가 뜰 때마다 이전
    /// 조우의 로그가 섞여 남아 어떤 줄이 지금 조우의 것인지 구별이 안 된다.
    private var currentEncounterLog: [SafariLogEntry] {
        let all = store.safariVisit?.visitLog ?? []
        guard let startIndex = all.lastIndex(where: { $0.action == nil }) else { return all }
        return Array(all[startIndex...])
    }

    /// 로그는 고정 높이 안에서만 스크롤한다(`BattleField.swift` 의 82pt 채팅창과 같은 규칙) —
    /// `NestedScrollGuardTests` 가 높이 안 묶인 중첩 스크롤을 막는다. 줄이 늘어날 때마다 마지막
    /// 줄로 자동 스크롤해 최신 내용이 항상 보이게 한다.
    private var log: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(currentEncounterLog.enumerated()), id: \.offset) { index, entry in
                        Text(logLine(entry)).font(.caption2).foregroundStyle(.secondary)
                            .id(index)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 100)
            .onChange(of: currentEncounterLog.count) {
                guard let lastIndex = currentEncounterLog.indices.last else { return }
                withAnimation { proxy.scrollTo(lastIndex, anchor: .bottom) }
            }
        }
    }

    private func logLine(_ entry: SafariLogEntry) -> String {
        guard let action = entry.action, let outcome = entry.outcome else {
            return l.safariLogEncounterStarted
        }
        return l.safariLogLine(action: action, outcome: outcome, sideEffectTriggered: entry.sideEffectTriggered)
    }

    @discardableResult
    private func mutate<T>(_ body: (inout SafariVisit) -> T) -> T? {
        guard var visit = store.safariVisit else { return nil }
        let result = body(&visit)
        store.safariVisit = visit
        return result
    }
}
