import XCTest
@testable import PokeTokenBar

// MARK: 이로치 스프라이트 갱신 (도감 이로치 토글)

/// 도감은 이로치를 잡은 종을 기본 일반색으로 그리고, 탭하면 같은 종을 이로치색으로 바꾼다 —
/// 즉 speciesID 는 그대로고 shiny 만 뒤집힌다. 갱신 판정이 종만 비교하면 .task 가 다시 돌아도
/// "이미 그 종을 로드했다"로 빠져나가 색이 바뀌지 않는다(플래시 방지 가드가 토글을 삼킨다).
@MainActor
final class SpriteShinyReloadTests: XCTestCase {
    func testShinyFlipReloadsSpriteForSameSpecies() {
        // 도감 토글의 두 방향 — 이 두 줄이 회귀의 본체다.
        XCTAssertTrue(SpriteView.needsReload(loadedID: 1, loadedShiny: false, id: 1, shiny: true),
                      "일반 → 이로치 토글이 갱신을 트리거해야 한다")
        XCTAssertTrue(SpriteView.needsReload(loadedID: 1, loadedShiny: true, id: 1, shiny: false),
                      "이로치 → 일반 토글도 마찬가지")
    }

    func testUnchangedSpriteSkipsReload() {
        // 같은 종·같은 이로치 여부면 재요청하지 않는다(재렌더 플래시 방지 가드 유지).
        XCTAssertFalse(SpriteView.needsReload(loadedID: 1, loadedShiny: false, id: 1, shiny: false))
        XCTAssertFalse(SpriteView.needsReload(loadedID: 1, loadedShiny: true, id: 1, shiny: true))
    }

    func testSpeciesChangeReloadsRegardlessOfShiny() {
        XCTAssertTrue(SpriteView.needsReload(loadedID: 1, loadedShiny: false, id: 2, shiny: false))
        XCTAssertTrue(SpriteView.needsReload(loadedID: nil, loadedShiny: false, id: 1, shiny: false),
                      "미로드(캐시 미스) 상태에서는 항상 불러온다")
    }
}
