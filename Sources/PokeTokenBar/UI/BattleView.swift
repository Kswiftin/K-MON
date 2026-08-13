import AppKit
import SwiftUI

/// 배틀 탭 — 같은 네트워크(LAN) 실시간 대전이 기본. 상대 목록에서 신청하고, 신청이 오면
/// 알림+수락 화면, 대전 중엔 기술 4개 중 선택. 오프라인 폴백으로 배틀 코드 대전을 접어 둔다.
struct BattleView: View {
    @Bindable var store: CompanionStore
    @Environment(BattleCenter.self) private var center

    // 수동(IP) 연결 상태
    @State private var manualAddress = ""
    @State private var addressCopied = false

    // 배틀 코드(오프라인) 상태
    @State private var codeExpanded = false
    @State private var myCode: String?
    @State private var mySnapshot: BattleSnapshot?
    @State private var codeLoadFailed = false
    @State private var copied = false
    @State private var pastedCode = ""
    @State private var codeOpponent: BattleSnapshot?
    @State private var codeError: String?
    @State private var codeResult: BattleResult?
    @State private var revealedTurns = 0
    @State private var revealTask: Task<Void, Never>?
    @State private var replayCount: UInt64 = 0

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
                if isIdlePhase {
                    Divider()
                    codeSection
                }
            }
        }
        .onAppear { center.pendingAttention = false }
    }

    private var isIdlePhase: Bool {
        switch center.phase {
        case .ready, .preparing: return true
        default: return false
        }
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
            if let b = center.battle { arenaView(b) }
        case .finished(let iWon, let byForfeit):
            finishedView(iWon: iWon, byForfeit: byForfeit)
        }
    }

    private var peerList: some View {
        VStack(alignment: .leading, spacing: 6) {
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
                        Button(l.battleChallengeButton) { center.challenge(peer) }
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
        center.challengeManual(manualAddress)
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

    // MARK: 배틀 코드 대전 (오프라인 폴백)

    private var codeSection: some View {
        DisclosureGroup(isExpanded: $codeExpanded) {
            VStack(alignment: .leading, spacing: 8) {
                codeExportRow
                codeOpponentInput
                codeBattleControls
                if let codeResult { codeBattleLog(codeResult) }
            }
            .padding(.top, 6)
        } label: {
            Text(l.battleCodeSection).font(.caption).foregroundStyle(.secondary)
        }
        .task(id: codeTaskKey) {
            if codeExpanded, mySnapshot == nil { await buildMyCodeSnapshot() }
        }
    }

    private var codeTaskKey: String { "\(codeExpanded)-\(store.currentSpeciesID ?? 0)" }

    private var codeExportRow: some View {
        HStack(spacing: 8) {
            Button {
                guard let myCode else { return }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(myCode, forType: .string)
                copied = true
                Task { try? await Task.sleep(for: .seconds(2)); copied = false }
            } label: {
                Label(copied ? l.battleCodeCopied : l.battleCopyCode,
                      systemImage: copied ? "checkmark" : "doc.on.doc")
            }
            .controlSize(.small)
            .disabled(myCode == nil)
            if mySnapshot == nil {
                Text(codeLoadFailed ? l.battleStatsFailed : l.battleLoadingStats)
                    .font(.caption2)
                    .foregroundStyle(codeLoadFailed ? .orange : .secondary)
                if codeLoadFailed {
                    Button(l.refresh) { Task { await buildMyCodeSnapshot() } }
                        .controlSize(.small)
                }
            }
            Spacer()
        }
    }

    private var codeOpponentInput: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(l.battleShareHint)
                .font(.caption2)
                .foregroundStyle(.secondary)
            TextField(l.battlePastePlaceholder, text: $pastedCode)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11, design: .monospaced))
                .onChange(of: pastedCode) { _, newValue in decodeCodeOpponent(newValue) }
            if let codeError {
                Text(codeError)
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
    }

    private func decodeCodeOpponent(_ raw: String) {
        codeResult = nil
        revealTask?.cancel()
        revealedTurns = 0
        guard !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            codeOpponent = nil; codeError = nil; return
        }
        do {
            codeOpponent = try BattleCode.decode(raw)
            codeError = nil
        } catch BattleCode.DecodeError.badChecksum {
            codeOpponent = nil; codeError = l.battleTamperedCode
        } catch {
            codeOpponent = nil; codeError = l.battleInvalidCode
        }
    }

    private var codeBattleControls: some View {
        HStack {
            Spacer()
            Button {
                runCodeBattle()
            } label: {
                Label(codeResult == nil ? l.battleStart : l.battleAgain, systemImage: "bolt.fill")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(mySnapshot == nil || codeOpponent == nil)
            Spacer()
        }
    }

    private func runCodeBattle() {
        guard let mySnapshot, let codeOpponent, let myCode else { return }
        // 같은 코드 쌍 → 같은 seed(순서 무관) → 양쪽 Mac 에서 동일한 배틀. 재대결은 seed 를 굴린다.
        let seed = BattleEngine.symmetricSeed(myCode, pastedCode.trimmingCharacters(in: .whitespacesAndNewlines)) &+ replayCount
        replayCount &+= 1
        let battle = BattleEngine.simulate(a: mySnapshot, b: codeOpponent, seed: seed)
        codeResult = battle
        revealedTurns = 0
        revealTask?.cancel()
        revealTask = Task {
            for i in 1...battle.turns.count {
                try? await Task.sleep(for: .milliseconds(450))
                guard !Task.isCancelled else { return }
                revealedTurns = i
            }
        }
    }

    private func codeBattleLog(_ result: BattleResult) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                codeLogLines(result)
            }
            .frame(height: 100)
            .padding(6)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
            .onChange(of: revealedTurns) { _, n in
                let target: AnyHashable = n >= result.turns.count ? AnyHashable("winner") : AnyHashable(n - 1)
                withAnimation { proxy.scrollTo(target, anchor: .bottom) }
            }
        }
    }

    private func codeLogLines(_ result: BattleResult) -> some View {
        let visible: [(offset: Int, element: BattleTurn)] = Array(result.turns.prefix(revealedTurns).enumerated())
        return VStack(alignment: .leading, spacing: 3) {
            ForEach(visible, id: \.offset) { pair in
                codeTurnLine(pair.element).id(pair.offset)
            }
            if revealedTurns >= result.turns.count {
                codeWinnerLine(result).id("winner")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func codeTurnLine(_ turn: BattleTurn) -> some View {
        let attacker = turn.attackerIsA ? (mySnapshot?.name ?? "?") : (codeOpponent?.name ?? "?")
        let moveName = turn.moveType?.name(store.language) ?? l.battleStruggle
        return VStack(alignment: .leading, spacing: 0) {
            Text(l.battleUsedMove(attacker, type: moveName, damage: turn.damage))
                .font(.caption2)
                .foregroundStyle(turn.attackerIsA ? .primary : .secondary)
            if turn.isCritical {
                Text(l.battleCritical).font(.caption2).foregroundStyle(.red)
            }
            if turn.effectiveness > 1 {
                Text(l.battleSuperEffective).font(.caption2).foregroundStyle(.orange)
            } else if turn.effectiveness < 1 {
                Text(l.battleNotVeryEffective).font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }

    private func codeWinnerLine(_ result: BattleResult) -> some View {
        let text: String = {
            switch result.winnerIsA {
            case .some(true):  return l.battleWinner(mySnapshot?.name ?? "?")
            case .some(false): return l.battleWinner(codeOpponent?.name ?? "?")
            case .none:        return l.battleDraw
            }
        }()
        return Text("🏆 \(text)")
            .font(.caption)
            .bold()
            .padding(.top, 2)
    }

    private func buildMyCodeSnapshot() async {
        mySnapshot = nil
        myCode = nil
        codeLoadFailed = false
        guard let active = store.state.active, let speciesID = store.currentSpeciesID else { return }
        do {
            let profile = try await PokeAPIClient.shared.battleProfile(speciesID: speciesID)
            let level = BattleSnapshot.level(stageIndex: active.stageIndex,
                                             totalForms: active.totalForms,
                                             stageProgress: store.progress)
            let snapshot = BattleSnapshot(speciesID: speciesID,
                                          name: store.displayName,
                                          trainer: NSFullUserName(),
                                          level: level,
                                          nature: active.nature,
                                          isShiny: active.isShiny,
                                          types: profile.types,
                                          base: profile.stats)
            myCode = try BattleCode.encode(snapshot)
            mySnapshot = snapshot
        } catch {
            AppLog.write("battle: profile load failed for \(speciesID): \(error)")
            codeLoadFailed = true
        }
    }
}
