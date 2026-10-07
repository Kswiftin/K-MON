import Foundation
import Testing
@testable import PokeTokenBar

@MainActor
struct TrainerEditorFlowTests {
    @Test func creationAdvancesOnlyAfterSuccessfulSave() {
        var progress = TrainerCreationProgress(hasTrainerName: false)
        #expect(!progress.isComplete)
        progress.complete(ifSaved: false)
        #expect(!progress.isComplete)
        progress.complete(ifSaved: true)
        #expect(progress.isComplete)
        #expect(TrainerCreationProgress(hasTrainerName: true).isComplete)
    }

    @Test func wardrobeReplacesEveryOtherOverlay() {
        let nav = PopoverNavigation()
        nav.showSettings = true; nav.showGymLeague = true; nav.showDungeon = true
        nav.showBattleFrontier = true; nav.showPokemonTFT = true; nav.showRaid = true
        nav.showSafariZone = true; nav.showFocusRecap = true; nav.showAuction = true
        nav.chatCompanionID = UUID()
        nav.goToOutfit()
        #expect(nav.showOutfit)
        #expect(!nav.showSettings && !nav.showGymLeague && !nav.showDungeon)
        #expect(!nav.showBattleFrontier && !nav.showPokemonTFT && !nav.showRaid)
        #expect(!nav.showSafariZone && !nav.showFocusRecap && !nav.showAuction)
        #expect(nav.chatCompanionID == nil)
    }

    @Test func lockedPreviewCannotBeSavedAndTakingOffClearsTint() {
        var draft = TrainerEditDraft(name: "루카", outfit: TrainerOutfit())
        draft.select(.hoodie, in: .top)
        draft.outfit.tints[.top] = .pink
        #expect(draft.outfit.worn[.top] == .hoodie)
        #expect(draft.validationIssue(owned: []) == .unownedOutfit)
        draft.select(nil, in: .top)
        #expect(draft.outfit.tints[.top] == nil)
        #expect(draft.validationIssue(owned: []) == nil)
        draft.name = " \n "
        #expect(draft.validationIssue(owned: []) == .emptyName)
    }

    @Test func previewPausesWhenHiddenAndReopensStill() {
        var preview = TrainerPreviewState()
        preview.show()
        #expect(!preview.isAnimating)
        preview.isWalking = true
        #expect(preview.isAnimating)
        #expect((0..<4).map { preview.step(at: Date(timeIntervalSinceReferenceDate: Double($0) * 0.25)) } == [0, 1, 0, 2])
        preview.hide()
        #expect(!preview.isAnimating)
        preview.show()
        #expect(!preview.isWalking)
        #expect(preview.step(at: Date(timeIntervalSinceReferenceDate: 0.25)) == 0)
        let initial = preview.facing
        for _ in 0..<4 { preview.rotate(1) }
        #expect(preview.facing == initial)
    }
}
