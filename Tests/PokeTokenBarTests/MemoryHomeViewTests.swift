import XCTest
@testable import PokeTokenBar

@MainActor
final class MemoryHomeViewTests: XCTestCase {
    func testMemoryHomeCanBeConstructedForTheActiveCompanion() {
        let store = CompanionStore(fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("memory-home-view-\(UUID().uuidString).json"))

        XCTAssertNotNil(MemoryHomeView(store: store))
    }
}
