import SwiftUI

/// 체육관 목록 — 설정과 같은 **오버레이**다. 팝오버 본체 ScrollView 밖에 놓이므로 여기서는
/// 세로 스크롤을 써도 된다(탭 안이었다면 안쪽이 잘렸다 — `BattleFieldTests` 가 막는 그 함정).
/// 체육관이 넷에서 열여덟로 늘어도 이 화면은 그대로 감당한다.
struct GymLeagueView: View {
    @Bindable var store: CompanionStore
    @Environment(BattleCenter.self) private var center
    let onClose: () -> Void

    private var l: L { store.l }

    var body: some View {
        if center.activeGym != nil, center.phase != .ready {
            // 엔진은 친구 대전과 같아도 체육관에서 시작한 전투는 이 오버레이 안에서 끝낸다.
            // 앱 전역 고정 윈도우도 `goToGymBattle()`으로 이 문맥을 보존한다.
            BattleView(store: store)
                .padding(PopoverMetrics.padding)
                .frame(height: PopoverMetrics.currentHeight(for: .battle))
        } else {
            picker
        }
    }

    private var picker: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(l.gymLeagueTitle, systemImage: "building.columns.fill")
                    .font(.headline)
                Text(l.gymBadgeCount(store.state.gymLeagueBadges.count, GymLeague.catalog.count))
                    .font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Button(action: onClose) { Image(systemName: "xmark") }
                    .buttonStyle(.plain).help(l.battleClose)
            }
            if let error = center.lastError {
                Text(error).font(.caption2).foregroundStyle(.orange)
            }
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(GymLeague.catalog) { gym in
                        GymRow(gym: gym, store: store,
                               isCleared: store.state.gymLeagueBadges.contains(gym.id),
                               onChallenge: { center.startGymChallenge(gym) })
                    }
                }
            }
            // 팀 고르기는 **맨 아래 고정**이다. 목록 위에 있을 땐 체육관을 훑어 내려가는 동안
            // 화면 밖으로 밀려나, 도전 버튼을 누를 때는 누구를 데려가는지 보이지 않았다.
            // 목록만 스크롤하고 이 영역은 제자리에 있는다.
            TeamPicker(store: store,
                       selection: Binding(get: { center.pickedTeam }, set: { center.pickedTeam = $0 }),
                       limit: GymLeague.teamSize)
        }
        .padding(PopoverMetrics.padding)
        .frame(height: PopoverMetrics.currentHeight(for: .battle))
        .alert(l.gymLevelGateTitle,
               isPresented: Binding(get: { center.gymLevelGateMessage != nil },
                                    set: { if !$0 { center.dismissGymLevelGateAlert() } })) {
        } message: {
            Text(center.gymLevelGateMessage ?? "")
        }
    }
}

/// 체육관 한 줄 — 타입, 관장 이름, 관장 레벨, 첫 승리 보상.
private struct GymRow: View {
    let gym: Gym
    let store: CompanionStore
    let isCleared: Bool
    let onChallenge: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(gym.type.name(store.language))
                .font(.system(size: 9, weight: .heavy)).foregroundStyle(.white)
                .frame(width: 42)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.accentColor.opacity(0.55)))
            VStack(alignment: .leading, spacing: 1) {
                Text(gym.leaderName(store.language)).font(.caption.bold()).lineLimit(1)
                Text(store.l.gymLeaderLevel(gym.level) + "+")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            if isCleared {
                Label(store.l.gymCleared, systemImage: "checkmark.seal.fill")
                    .font(.caption2).foregroundStyle(.green)
            } else {
                RewardLabel(reward: gym.firstClearReward, store: store)
            }
            Button(isCleared ? store.l.gymRematch : store.l.gymChallenge, action: onChallenge)
                .controlSize(.small)
        }
        .padding(7)
        .background(RoundedRectangle(cornerRadius: 8)
            .fill(Color.primary.opacity(isCleared ? 0.06 : 0.03)))
    }
}

/// 체육관 줄의 보상 표시 — 알의 보증 등급과 별의조각을 함께 보여 준다.
private struct RewardLabel: View {
    let reward: GymReward
    let store: CompanionStore

    var body: some View {
        HStack(spacing: 4) {
            if reward.eggs > 0 {
                HStack(spacing: 1) {
                    Text("🥚")
                    if let tier = reward.eggGuarantee {
                        Text(store.l.rarityLabel(tier))
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(Color.accentColor)
                    }
                }
            }
            if reward.starPieces > 0 {
                Text("⭐ \(GameNumberFormatter.compact(reward.starPieces))")
            }
        }
        .font(.caption2.monospacedDigit())
        .foregroundStyle(.secondary)
    }
}
