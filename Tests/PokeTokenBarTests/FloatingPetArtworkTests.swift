import XCTest
@testable import PokeTokenBar

// MARK: 플로팅 펫 그림 — 움직임 vs 선명함

/// 애니메이션 원본은 5세대 도트가 마지막이라 45~133px 뿐이다. 96pt 로 띄우면 레티나에서 평균
/// 2.5배, 최대 192pt 설정에서는 8배 넘게 확대된다. 그보다 선명한 건 정지 렌더(HOME 512×512)밖에
/// 없고, 어느 사이트를 가도 애니메이션은 같은 원본을 재배포한다(실측 확인).
///
/// 그래서 설정으로 고르게 한다. 여기서 지키는 건 **고르는 쪽이 실제로 다른 그림을 받는가** 와
/// **그 선택이 배틀 등 스프라이트를 깨뜨리지 않는가** 둘이다.
final class FloatingPetArtworkTests: XCTestCase {

    // MARK: 주소

    func testTheSharpOptionAsksForTheHomeRender() {
        let url = SpriteStore.spriteURL(speciesID: 25, animated: false, shiny: false, back: false,
                                        highResolution: true)
        XCTAssertTrue(url.hasSuffix("/other/home/25.png"), url)
    }

    func testTheSharpOptionHasItsOwnShinyFolder() {
        let url = SpriteStore.spriteURL(speciesID: 25, animated: false, shiny: true, back: false,
                                        highResolution: true)
        XCTAssertTrue(url.hasSuffix("/other/home/shiny/25.png"), url)
    }

    /// **HOME 에는 뒷모습이 없다**(`other/home/back/…` 은 404). 걸러내지 않으면 배틀 필드의 내 쪽
    /// 스프라이트가 통째로 사라진다 — 펫 설정 하나가 배틀 화면을 깨는 부류다.
    func testTheSharpOptionNeverAsksForABackSprite() {
        let url = SpriteStore.spriteURL(speciesID: 25, animated: false, shiny: false, back: true,
                                        highResolution: true)
        XCTAssertFalse(url.contains("/home/"), "HOME 에 없는 주소를 요청한다: \(url)")
        XCTAssertTrue(url.contains("/back/"), url)
    }

    /// 애니메이션을 켠 요청은 GIF 그대로다 — 두 축이 겹쳐 들어와도 GIF 가 이긴다.
    func testAnimatedRequestsAreUntouched() {
        let url = SpriteStore.spriteURL(speciesID: 25, animated: true, shiny: false, back: false,
                                        highResolution: true)
        XCTAssertTrue(url.hasSuffix("/showdown/25.gif"), url)
    }

    /// 아무것도 안 켜면 예전 그대로 — 기본 경로가 바뀌면 이미 받아 둔 캐시가 통째로 무효가 된다.
    func testTheOrdinaryPathIsUnchanged() {
        XCTAssertTrue(SpriteStore.spriteURL(speciesID: 25, animated: false, shiny: false, back: false)
                        .hasSuffix("/pokemon/25.png"))
    }

    // MARK: 캐시 키

    /// **96px 과 512px 이 같은 키를 쓰면 먼저 받은 쪽이 양쪽에 나온다.** 앞·뒤를 나눈 것과 같은 이유다.
    func testTheHomeRenderGetsItsOwnCacheNamespace() {
        let sharp = SpriteStore.cacheKey(speciesID: 25, animated: false, shiny: false,
                                         back: false, highResolution: true)
        let pixel = SpriteStore.cacheKey(speciesID: 25, animated: false, shiny: false)
        let animated = SpriteStore.cacheKey(speciesID: 25, animated: true, shiny: false)
        XCTAssertNotEqual(sharp, pixel)
        XCTAssertNotEqual(sharp, animated)
    }

    func testTheHomeCacheKeySplitsShiny() {
        XCTAssertNotEqual(
            SpriteStore.cacheKey(speciesID: 25, animated: false, shiny: true, back: false, highResolution: true),
            SpriteStore.cacheKey(speciesID: 25, animated: false, shiny: false, back: false, highResolution: true))
    }

    /// 기존 키는 그대로여야 한다 — 바뀌면 사용자가 이미 받아 둔 스프라이트를 전부 다시 받는다.
    func testExistingCacheKeysDoNotMove() {
        XCTAssertEqual(SpriteStore.cacheKey(speciesID: 25, animated: false, shiny: false), "25-s")
        XCTAssertEqual(SpriteStore.cacheKey(speciesID: 25, animated: true, shiny: false),
                       "25-showdown-normal")
    }

    // MARK: 설정

    /// rawValue 가 UserDefaults 에 남는다 — case 이름을 바꾸면 조용히 기본값으로 되돌아간다.
    func testTheStoredKeysStayStable() {
        XCTAssertEqual(FloatingPetArtwork.animated.rawValue, "animated")
        XCTAssertEqual(FloatingPetArtwork.sharp.rawValue, "sharp")
        XCTAssertEqual(FloatingPetArtwork.allCases.count, 2)
    }

    /// 문구는 세 언어 모두 있어야 하고, **"선명하게" 는 돌아다니기가 남는다는 걸 말해야 한다** —
    /// 안 그러면 펫이 아예 멈추는 줄 알고 아무도 안 고른다.
    func testTheSharpHintSaysRoamingStillWorks() {
        for language in AppLanguage.allCases {
            let localized = L(language)
            for artwork in FloatingPetArtwork.allCases {
                XCTAssertFalse(localized.floatingPetArtworkLabel(artwork).isEmpty, "\(language) 라벨 누락")
                XCTAssertFalse(localized.floatingPetArtworkHint(artwork).isEmpty, "\(language) 설명 누락")
            }
        }
        XCTAssertNotEqual(L(.ko).floatingPetArtworkLabel(.sharp), L(.en).floatingPetArtworkLabel(.sharp))
        XCTAssertNotEqual(L(.ko).floatingPetArtworkLabel(.sharp), L(.ja).floatingPetArtworkLabel(.sharp))

        XCTAssertTrue(L(.ko).floatingPetArtworkHint(.sharp).contains("돌아다니기"))
        XCTAssertTrue(L(.en).floatingPetArtworkHint(.sharp).contains("Roaming"))
    }
}
