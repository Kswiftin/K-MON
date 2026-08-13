import AppKit
import SwiftUI

/// 배틀 탭 — 같은 네트워크(LAN) 실시간 대전. 상대 목록에서 신청하고, 신청이 오면
/// 알림+수락 화면, 대전 중엔 기술 4개 중 선택.
struct BattleView: View {
    @Bindable var store: CompanionStore
    @Environment(BattleCenter.self) private var center

    // 수동(IP) 연결 상태
    @State private var manualAddress = ""
    @State private var addressCopied = false
    @State private var kind: BattleKind = .brawl   // 신청할 배틀 종류

    private var l: L { store.l }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if store.isEgg {
                Text(l.battleNeedHatch)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 24)
            } else {
                networkSection
            }
        }
        .onAppear { center.pendingAttention = false }
    }

    // MARK: 네트워크 대전

    @ViewBuilder
    private var networkSection: some View {
        switch center.phase {
        case .ready, .preparing:
            peerList
        case .challenging(let peer):
            waitingView(peer: peer)
        case .incoming(let peer):
            incomingView(peer: peer)
        case .battling:
            if let race = center.race { raceView(race) }        // 달리기
            else if let b = center.battle { arenaView(b) }       // 맞짱
        case .finished(let iWon, let byForfeit):
            finishedView(iWon: iWon, byForfeit: byForfeit)
        }
    }

    private var peerList: some View {
        VStack(alignment: .leading, spacing: 6) {
            // 배틀 종류 선택 — 맞짱(턴제) / 달리기(스피드 레이스). 신청 시 이 종류로 건다.
            Picker("", selection: $kind) {
                Text(l.battleKindBrawl).tag(BattleKind.brawl)
                Text(l.battleKindRace).tag(BattleKind.race)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            // 자동 수락 — 자리를 비워도 신청이 오면 바로 성사.
            Toggle(l.battleAutoAccept, isOn: Binding(
                get: { center.autoAccept },
                set: { center.autoAccept = $0 }))
                .font(.caption2)
                .toggleStyle(.checkbox)

            HStack(spacing: 6) {
                Text(l.battleNearby).font(.caption).bold()
                if case .preparing = center.phase { ProgressView().controlSize(.mini) }
                Spacer()
            }
            if let err = center.lastError {
                Text(err).font(.caption2).foregroundStyle(.orange)
            }
            if center.peers.isEmpty {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(l.battleNoPeers).font(.caption2).foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            } else {
                ForEach(center.peers) { peer in
                    HStack {
                        Image(systemName: "person.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(peer.name).font(.callout).lineLimit(1)
                        Spacer()
                        Button(l.battleChallengeButton) { center.challenge(peer, kind: kind) }
                            .controlSize(.small)
                            .disabled(!isChallengeEnabled)
                    }
                    .padding(.vertical, 2)
                }
            }
            manualConnect
        }
    }

    /// 사내망 등 mDNS 차단 환경 폴백 — 내 주소 공유 + 상대 주소 직접 입력.
    private var manualConnect: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(l.battleManualHint)
                .font(.caption2)
                .foregroundStyle(.secondary)
            if let addr = center.myManualAddress {
                HStack(spacing: 6) {
                    Text("\(l.battleMyAddress): \(addr)")
                        .font(.system(size: 11, design: .monospaced))
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(addr, forType: .string)
                        addressCopied = true
                        Task { try? await Task.sleep(for: .seconds(2)); addressCopied = false }
                    } label: {
                        Image(systemName: addressCopied ? "checkmark" : "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.mini)
                    Spacer()
                }
            }
            HStack(spacing: 6) {
                TextField(l.battleManualPlaceholder, text: $manualAddress)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11, design: .monospaced))
                    .onSubmit { challengeManual() }
                Button(l.battleChallengeButton) { challengeManual() }
                    .controlSize(.small)
                    .disabled(!isChallengeEnabled || manualAddress.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(.top, 4)
    }

    private func challengeManual() {
        guard isChallengeEnabled else { return }
        center.challengeManual(manualAddress, kind: kind)
    }

    private var isChallengeEnabled: Bool {
        if case .ready = center.phase { return true }
        return false
    }

    private func waitingView(peer: String) -> some View {
        VStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text("\(peer) — \(l.battleWaitingAccept)")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button(l.battleCancel) { center.cancelChallenge() }
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }

    private func incomingView(peer: String) -> some View {
        VStack(spacing: 8) {
            Text("⚔️ \(l.battleIncomingFrom(peer))")
                .font(.callout).bold()
                .multilineTextAlignment(.center)
            Text(l.battleKindLabel(center.incomingKind))
                .font(.caption2).foregroundStyle(.secondary)
            if let opp = center.incomingSnapshot {
                snapshotCard(opp, title: opp.trainer.map { l.battleTrainerLabel($0) } ?? "?", hpRatio: nil)
                    .frame(maxWidth: 180)
            }
            HStack(spacing: 12) {
                Button(l.battleAccept) { center.acceptIncoming() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                Button(l.battleDecline) { center.declineIncoming() }
                    .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    // MARK: 대전 화면

    private func arenaView(_ b: NetBattleState) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                snapshotCard(b.my, title: l.battleMyPokemon,
                             hpRatio: Double(b.myHP) / Double(max(1, b.myStats.hp)))
                VStack(spacing: 2) {
                    Text(l.battleTurnLabel(b.turn))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("VS")
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 34)
                snapshotCard(b.opp, title: b.opp.trainer.map { l.battleTrainerLabel($0) } ?? "?",
                             hpRatio: Double(b.oppHP) / Double(max(1, b.oppStats.hp)))
            }
            if !b.events.isEmpty { eventLog(b) }
            if b.myChoice == nil {
                Text(l.battleYourTurn).font(.caption).bold()
                moveButtons(b)
            } else {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(l.battleWaitingOpponent).font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }
            HStack {
                Spacer()
                Button(l.battleForfeit) { center.forfeit() }
                    .controlSize(.mini)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: 달리기 (레이스)

    private func raceView(_ race: RaceState) -> some View {
        RaceLane(center: center, l: l, onClose: { center.dismissResult() })
    }

    private func moveButtons(_ b: NetBattleState) -> some View {
        let columns = [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)]
        return LazyVGrid(columns: columns, spacing: 6) {
            if b.mustStruggle {
                moveButton(MoveSpec.struggle(), pp: nil) { center.chooseMove(-1) }
            } else {
                ForEach(Array(b.myMoves.enumerated()), id: \.element.id) { idx, move in
                    moveButton(move, pp: b.myPP[idx]) { center.chooseMove(idx) }
                        .disabled(b.myPP[idx] <= 0)
                }
            }
        }
    }

    private func moveButton(_ move: MoveSpec, pp: Int?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                Text(move.name(store.language))
                    .font(.caption).bold()
                    .lineLimit(1)
                HStack(spacing: 4) {
                    typeChip(move.type)
                    Text("\(move.power)")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let pp {
                        Text("PP \(pp)/\(move.pp)")
                            .font(.system(size: 9))
                            .foregroundStyle(pp == 0 ? .red : .secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(6)
        }
        .buttonStyle(.bordered)
    }

    private func finishedView(iWon: Bool?, byForfeit: Bool) -> some View {
        VStack(spacing: 10) {
            Text(finishText(iWon: iWon, byForfeit: byForfeit))
                .font(.title3).bold()
            if let b = center.battle, !b.events.isEmpty { eventLog(b) }
            Button(l.battleClose) { center.dismissResult() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private func finishText(iWon: Bool?, byForfeit: Bool) -> String {
        switch (iWon, byForfeit) {
        case (.some(true), true):   return l.battleOppForfeited
        case (.some(false), true):  return l.battleYouForfeited
        case (.some(true), false):  return l.battleWon
        case (.some(false), false): return l.battleLost
        default:                    return l.battleDraw
        }
    }

    // MARK: 로그/카드 공용

    private func eventLog(_ b: NetBattleState) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(b.events.suffix(4).enumerated()), id: \.offset) { _, e in
                eventLine(e, battle: b)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
    }

    private func eventLine(_ e: NetBattleEvent, battle b: NetBattleState) -> some View {
        // 이벤트 좌변(A/B) → 내/상대 매핑.
        let mineActed = e.attackerIsA == b.iAmA
        let attacker = mineActed ? b.my.name : b.opp.name
        let moves = mineActed ? b.myMoves : b.oppMoves
        let moveName = (moves.first { $0.id == e.moveID } ?? .struggle()).name(store.language)
        let text: String
        if e.missed {
            text = l.battleUsedMoveMissed(attacker, move: moveName) + " " + l.battleMissed
        } else if e.effectiveness == 0 {
            text = l.battleUsedMoveMissed(attacker, move: moveName) + " " + l.battleNoEffect
        } else {
            var s = l.battleUsedMoveNamed(attacker, move: moveName, damage: e.damage)
            if e.isCritical { s += " · " + l.battleCritical }
            if e.effectiveness > 1 { s += " · " + l.battleSuperEffective }
            else if e.effectiveness < 1 { s += " · " + l.battleNotVeryEffective }
            text = s
        }
        return Text(text)
            .font(.caption2)
            .foregroundStyle(mineActed ? .primary : .secondary)
    }

    private func snapshotCard(_ snapshot: BattleSnapshot, title: String, hpRatio: Double?) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            SpriteView(speciesID: snapshot.speciesID, size: 56, animated: true, shiny: snapshot.isShiny)
            HStack(spacing: 3) {
                if snapshot.isShiny { Text("✨").font(.caption2) }
                Text(snapshot.name).font(.caption).bold().lineLimit(1)
                Text(l.battleLv(snapshot.level)).font(.caption2).foregroundStyle(.secondary)
            }
            HStack(spacing: 3) {
                ForEach(snapshot.types, id: \.rawValue) { typeChip($0) }
            }
            if let hpRatio {
                ProgressView(value: max(0, min(1, hpRatio)))
                    .tint(hpRatio > 0.5 ? .green : hpRatio > 0.2 ? .yellow : .red)
                    .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04)))
    }

    private func typeChip(_ type: PokemonType) -> some View {
        Text(type.name(store.language))
            .font(.system(size: 9, weight: .semibold))
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(Capsule().fill(Color.accentColor.opacity(0.15)))
    }
}

/// 달리기 레인 — **키보드 ←/→ 를 번갈아** 눌러 직접 달린다(같은 키 연타는 무효, 번갈아야 전진).
/// 내 러너는 입력마다 전진하고 진행도를 상대에게 보내며, 상대 러너는 수신 진행도로 움직인다.
/// 먼저 결승선(finishLine)에 닿는 쪽 승리. 결과가 정해지면(race.iWon) 승패 + 닫기 표시.
private struct RaceLane: View {
    let center: BattleCenter
    let l: L
    let onClose: () -> Void

    @State private var monitor: Any?
    @State private var lastKey: UInt16?   // 123 = ←, 124 = →

    var body: some View {
        let race = center.race
        return VStack(alignment: .leading, spacing: 10) {
            Text("🏁 \(l.battleKindRace)").font(.callout).bold()
            if let race {
                lane(snapshot: race.my, title: l.battleMyPokemon, progress: race.myProgress)
                lane(snapshot: race.opp,
                     title: race.opp.trainer.map { l.battleTrainerLabel($0) } ?? "?",
                     progress: race.oppProgress)
                if let iWon = race.iWon {
                    Text(raceResultText(iWon)).font(.title3).bold()
                        .frame(maxWidth: .infinity)
                    Button(l.battleClose) { onClose() }
                        .buttonStyle(.borderedProminent).controlSize(.small)
                        .frame(maxWidth: .infinity)
                } else {
                    Text(l.battleRaceHint).font(.caption2).foregroundStyle(.orange)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .onAppear { installKeyMonitor() }
        .onDisappear { removeKeyMonitor() }
    }

    private func installKeyMonitor() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let code = event.keyCode
            guard code == 123 || code == 124 else { return event }   // ←/→ 만 처리
            // 번갈아 눌러야 전진 — 직전과 다른 키일 때만 한 스텝(같은 키 연타 방지 = 달리는 모션).
            if lastKey != code {
                lastKey = code
                center.raceStep()
            }
            return nil   // 방향키 소비(스크롤·삑 소리 방지)
        }
    }

    private func removeKeyMonitor() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private func raceResultText(_ iWon: Bool?) -> String {
        switch iWon {
        case .some(true):  return l.battleWon
        case .some(false): return l.battleLost
        case .none:        return l.battleDraw
        }
    }

    private func lane(snapshot: BattleSnapshot, title: String, progress: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            GeometryReader { geo in
                let travel = max(0, geo.size.width - 34)
                ZStack(alignment: .leading) {
                    Rectangle().fill(Color.secondary.opacity(0.25)).frame(width: 2)
                        .frame(maxWidth: .infinity, alignment: .trailing)   // 결승선
                    SpriteView(speciesID: snapshot.speciesID, size: 30, bob: true, animated: true, shiny: snapshot.isShiny)
                        .frame(width: 30, height: 30)
                        .offset(x: travel * progress)
                        .animation(.easeOut(duration: 0.15), value: progress)
                }
            }
            .frame(height: 32)
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
    }
}
