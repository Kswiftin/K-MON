import Foundation
import Testing
@testable import PokeTokenBar

@MainActor @Suite("트레이너 편집 저장 경계")
struct TrainerEditingTests {
    private func makeStore(at url: URL, readOnly: Bool = false) -> CompanionStore {
        CompanionStore(provider: TrainerEditProvider(), clock: { Date(timeIntervalSince1970: 1_700_000_000) },
            fileURL: url, rng: TrainerEditRNG(), isReadOnly: readOnly)
    }
    private func seed(_ url: URL, owned: Set<OutfitItem> = [.beanie, .hoodie]) throws {
        var state = CompanionState()
        state.trainerName = "기존 이름"
        state.ownedOutfits = owned
        state.starPieces = 1_000
        try JSONEncoder().encode(SaveTransfer.signed(state)).write(to: url)
    }

    @Test func draftPreviewAndCancelDoNotWrite() throws {
        let url = storeFixtureStateURL("trainer-draft")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try seed(url)
        let store = makeStore(at: url)
        let before = try Data(contentsOf: url)
        let saved = store.trainerEditDraft
        var draft = saved
        draft.name = "새 이름"
        draft.outfit.appearance = .creationDefault
        draft.select(.beret, in: .hat)
        #expect(draft.outfit.worn[.hat] == .beret)
        #expect(store.trainerEditDraft == saved)
        #expect(store.state.starPieces == 1_000)
        #expect(try Data(contentsOf: url) == before)
    }

    @Test func saveCommitsAllFields() throws {
        let url = storeFixtureStateURL("trainer-save")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try seed(url)
        let store = makeStore(at: url)
        let draft = TrainerEditDraft(name: "  루카스\n", outfit: TrainerOutfit(worn: [.hat: .beanie],
            appearance: .creationDefault, tints: [.hat: .pink]))
        #expect(store.saveTrainer(draft))
        let disk = try JSONDecoder().decode(CompanionState.self, from: Data(contentsOf: url))
        #expect(disk.trainerName == "루카스")
        #expect(disk.outfit == draft.outfit)
        #expect(disk.starPieces == 1_000)
        #expect(store.trainerName == "루카스")
        #expect(TrainerEditDraft(name: String(repeating: "가", count: 22), outfit: TrainerOutfit()).normalizedName.count == 20)
    }

    @Test func invalidDraftChangesNothing() throws {
        let url = storeFixtureStateURL("trainer-reject")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try seed(url)
        let store = makeStore(at: url)
        let bytes = try Data(contentsOf: url)
        let original = store.trainerEditDraft
        let drafts = [TrainerEditDraft(name: " \n", outfit: TrainerOutfit()),
            TrainerEditDraft(name: "바뀐 이름", outfit: TrainerOutfit(worn: [.hat: .beret])),
            TrainerEditDraft(name: "바뀐 이름", outfit: TrainerOutfit(worn: [.hat: .hoodie]))]
        for draft in drafts {
            #expect(!store.saveTrainer(draft))
            #expect(store.trainerEditDraft == original)
            #expect(try Data(contentsOf: url) == bytes)
        }
    }

    @Test func ownershipChangesBeforeCommit() throws {
        let url = storeFixtureStateURL("trainer-recheck")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try seed(url)
        let store = makeStore(at: url)
        var draft = store.trainerEditDraft
        draft.select(.beanie, in: .hat)
        #expect(store.trainerEditIssue(draft) == nil)
        var replacement = store.state
        replacement.ownedOutfits = []
        try store.applySave(SaveEnvelope(format: SaveEnvelope.formatID, schema: SaveEnvelope.schemaVersion, appVersion: "test", exportedAt: Date(), sourceDevice: "테스트", state: replacement))
        #expect(store.trainerEditIssue(draft) == .unownedOutfit)
        #expect(!store.saveTrainer(draft))
        #expect(store.outfit.worn.isEmpty)
    }

    @Test func wearPreservesAppearanceAndOtherTints() throws {
        let url = storeFixtureStateURL("trainer-wear")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try seed(url)
        let store = makeStore(at: url)
        #expect(store.saveTrainer(TrainerEditDraft(name: "이름", outfit: TrainerOutfit(worn: [.hat: .beanie, .top: .hoodie],
            appearance: .creationDefault, tints: [.hat: .pink, .top: .green]))))
        store.wear(nil, in: .hat)
        #expect(store.outfit.appearance == .creationDefault)
        #expect(store.outfit.tints == [.top: .green])
        var draft = store.trainerEditDraft
        draft.select(.stripedTee, in: .top)
        #expect(draft.outfit.tints[.top] == .green)
        draft.select(nil, in: .top)
        #expect(draft.outfit.tints.isEmpty)
    }

    @Test func saveFailureDoesNotReportSuccess() throws {
        let url = storeFixtureStateURL("trainer-fail")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let store = makeStore(at: url)
        let draft = TrainerEditDraft(name: "이름", outfit: TrainerOutfit(appearance: .creationDefault))
        let original = store.trainerEditDraft
        #expect(!store.saveTrainer(draft))
        #expect(store.trainerEditDraft == original, "저장 실패 후 취소하면 외형과 이름이 원래 값이어야 한다")
        #expect(store.saveFailed)
        try FileManager.default.removeItem(at: url)
        #expect(store.saveTrainer(draft))
        #expect(!store.saveFailed)
    }

    @Test func readOnlyStoreDoesNotReportSuccess() throws {
        let url = storeFixtureStateURL("trainer-readonly")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try seed(url)
        let store = makeStore(at: url, readOnly: true)
        let before = try Data(contentsOf: url)
        #expect(!store.saveTrainer(TrainerEditDraft(name: "새 이름", outfit: TrainerOutfit(appearance: .creationDefault))))
        #expect(store.trainerName == "기존 이름")
        #expect(try Data(contentsOf: url) == before)
    }

    @Test func sanitizePreservesNewAppearance() {
        var state = CompanionState()
        state.ownedOutfits = [.beanie]
        state.outfit = TrainerOutfit(worn: [.hat: .beanie, .top: .hoodie], appearance: .creationDefault,
            tints: [.hat: .pink, .top: .blue, .bottom: .black])
        let sanitized = SaveTransfer.sanitized(state)
        #expect(sanitized.outfit.appearance == .creationDefault)
        #expect(sanitized.outfit.worn == [.hat: .beanie])
        #expect(sanitized.outfit.tints == [.hat: .pink])
    }

    @Test func displayFieldsDoNotChangeIntegrity() {
        var state = CompanionState()
        let before = SaveTransfer.canonicalString(state)
        state.outfit = TrainerOutfit(appearance: .creationDefault)
        #expect(SaveTransfer.canonicalString(state) == before)
        state.ownedOutfits = [.beanie]
        let owned = SaveTransfer.canonicalString(state)
        #expect(owned != before)
        state.outfit.worn = [.hat: .beanie]
        state.outfit.tints = [.hat: .green]
        #expect(SaveTransfer.canonicalString(state) == owned)
    }

    @Test func purchaseAndAcquisitionDescriptions() throws {
        let url = storeFixtureStateURL("trainer-buy")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try seed(url, owned: [])
        let store = makeStore(at: url)
        #expect(store.buyOutfit(.crossbodyBag))
        #expect(store.state.starPieces == 200)
        #expect(!store.buyOutfit(.crossbodyBag))
        #expect(!store.buyOutfit(.hoodie))
        #expect(OutfitItem.helmetExplorer.acquisitionDescription(l: L()).contains("20회"))
        #expect(OutfitItem.cloakWorn.acquisitionDescription(l: L()).contains("5회"))
        #expect(OutfitItem.beanie.acquisitionDescription(l: L()) == "상점 · 별의조각 300")
        #expect(OutfitItem.hairMessy.acquisitionDescription(l: L()).contains("던전 클리어 · 1단계"))
        #expect(OutfitItem.cloakWorn.acquisitionDescription(l: L()).contains("던전 클리어 · 2단계"))
        #expect(OutfitItem.bootsLong.acquisitionDescription(l: L()).contains("위험한 길 완주 · 1단계"))
        #expect(OutfitItem.helmetExplorer.acquisitionDescription(l: L()).contains("위험한 길 완주 · 3단계"))
    }
}

private struct TrainerEditProvider: PokeProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine {
        EvoLine(baseID: 1, tree: EvoNode(speciesID: 1, children: []), rarity: .common, names: [1: ["ko": "이상해씨"]])
    }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [BaseSpecies(id: 1, captureRate: 255)] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { id == 1 ? BaseSpecies(id: 1, captureRate: 255) : nil }
}
private struct TrainerEditRNG: RandomNumberGenerator {
    mutating func next() -> UInt64 { 42 }
}
