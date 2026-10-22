import Foundation
import Testing
@testable import PokeTokenBar

@MainActor
@Suite("Professor transfer")
struct ProfessorTransferTests {
    private func store(_ name: String) -> CompanionStore {
        let url = storeFixtureStateURL("professor-\(name)")
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
        let url = storeFixtureStateURL("professor-persist")
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

    // MARK: 자동 선택 — 졸업한 계열의 중복만, 계열마다 하나 남김

    private func lineMon(_ speciesID: Int, level: Int, shiny: Bool = false) -> MonState {
        var made = MonState(baseID: speciesID, pathIDs: [speciesID], stageIndex: 0, usedAtStage: 0,
                            rarity: .common, totalForms: 1, isShiny: shiny)
        made.levelExperience = (level - 1) * PokemonBalance.experiencePerLevel
        return made
    }

    private func graduated(_ chain: [Int]) -> DexEntry {
        DexEntry(baseID: chain[0], finalID: chain[chain.count - 1], chainOrder: chain, rarity: .common, caughtAt: nil)
    }

    @Test("auto selection keeps the highest level of each graduated line and skips ungraduated lines")
    func autoSelectionKeepsTheHighestLevelPerGraduatedLine() {
        let s = store("auto-highest")
        // 1→2→3 계열은 졸업했다. 2(중간 종)로 잡은 개체도 같은 계열로 센다 — baseID 로 묶으면 갈린다.
        s.debugSetDex([graduated([1, 2, 3])])
        let low = lineMon(1, level: 5), high = lineMon(2, level: 30), mid = lineMon(3, level: 12)
        let unGraduatedA = lineMon(7, level: 3), unGraduatedB = lineMon(7, level: 4)
        s.debugSetBoxedMons([low, high, mid, unGraduatedA, unGraduatedB])

        #expect(s.professorAutoSelection == [low.id, mid.id])
    }

    @Test("auto selection never picks shiny or favorite mons and lets them be the kept one")
    func autoSelectionSkipsShinyAndFavorites() {
        let s = store("auto-locked")
        s.debugSetDex([graduated([1, 2]), graduated([4, 5])])
        let shiny = lineMon(1, level: 2, shiny: true), plainA = lineMon(2, level: 40)
        let favorite = lineMon(4, level: 1), plainB = lineMon(5, level: 50)
        s.debugSetBoxedMons([shiny, plainA, favorite, plainB])
        s.toggleFavorite(favorite.id)

        // 이로치·즐겨찾기가 계열의 남는 몫이 되므로 레벨이 더 높아도 나머지가 고른 대상이다.
        #expect(s.professorAutoSelection == [plainA.id, plainB.id])
    }

    @Test("auto selection is empty when every graduated line has one mon")
    func autoSelectionIsEmptyWithoutDuplicates() {
        let s = store("auto-empty")
        s.debugSetDex([graduated([1, 2])])
        s.debugSetBoxedMons([lineMon(1, level: 9), lineMon(8, level: 9), lineMon(8, level: 3)])
        #expect(s.professorAutoSelection.isEmpty)
    }
}
