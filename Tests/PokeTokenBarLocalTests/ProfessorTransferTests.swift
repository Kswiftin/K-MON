import Foundation
import Testing
@testable import PokeTokenBar

@MainActor
@Suite("Professor transfer")
struct ProfessorTransferTests {
    private func store(_ name: String) -> CompanionStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pokedoro-professor-\(name)-\(UUID().uuidString).json")
        return CompanionStore(clock: { Date(timeIntervalSince1970: 2_000_000_000) }, fileURL: url)
    }

    private func mon(_ id: Int) -> MonState {
        MonState(baseID: id, pathIDs: [id], stageIndex: 0, usedAtStage: 0,
                 rarity: .common, totalForms: 1,
                 names: [id: ["ko": "포\(id)"]])
    }

    @Test("four then two transfers carry one remainder and award two eggs")
    func fourThenTwoCarriesTheRemainder() {
        let s = store("carry")
        let first = (1...4).map(mon)
        s.debugSetBoxedMons(first)

        let a = s.sendToProfessor(Set(first.map(\.id)))
        #expect(a == .init(sent: 4, eggs: 1, progress: 1))
        #expect(s.focusEggCount == 1)
        #expect(s.state.focusEggReadyDates.count == 1)

        let second = [mon(5), mon(6)]
        s.debugSetBoxedMons(second)
        let b = s.sendToProfessor(Set(second.map(\.id)))
        #expect(b == .init(sent: 2, eggs: 1, progress: 0))
        #expect(s.focusEggCount == 2)
        #expect(s.state.focusEggReadyDates.count == 2)
        #expect(s.state.eggTier == nil)
    }

    @Test("remainder and egg reward survive relaunch")
    func persistence() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pokedoro-professor-persist-\(UUID().uuidString).json")
        let first = CompanionStore(clock: { Date(timeIntervalSince1970: 2_000_000_000) }, fileURL: url)
        let mons = [mon(1), mon(2), mon(3), mon(4)]
        first.debugSetBoxedMons(mons)
        #expect(first.sendToProfessor(Set(mons.map(\.id))) != nil)

        let reloaded = CompanionStore(clock: { Date(timeIntervalSince1970: 2_000_000_000) }, fileURL: url)
        #expect(reloaded.professorTransferProgress == 1)
        #expect(reloaded.focusEggCount == 1)
        #expect(reloaded.boxedMons.isEmpty)
    }

    @Test("a locked selection rejects the whole batch")
    func lockedSelectionIsAtomic() {
        let s = store("locked")
        let a = mon(1), b = mon(2), c = mon(3)
        s.debugSetBoxedMons([a, b, c])
        #expect(s.toggleFavorite(b.id))

        #expect(s.sendToProfessor([a.id, b.id, c.id]) == nil)
        #expect(s.boxedMons.count == 3)
        #expect(s.focusEggCount == 0)
        #expect(s.professorTransferProgress == 0)
    }
}
