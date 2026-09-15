import Testing
@testable import PokeTokenBar

@Suite struct FrontierSignatureTests {
    /// 2.39.0 테스트판은 프런티어 값을 저장하면서도 13 형식의 구서명을 남길 수 있었다.
    /// 정상 진행을 초기화하지 않고 한 번 마이그레이션한 뒤에는 다시 엄격히 검사해야 한다.
    @Test func version13FrontierSaveMigratesAndThenRemainsProtected() {
        let seed = "frontier-save-regression-device"
        var legacy = SaveTransfer.signed(CompanionState(), deviceSeed: seed)
        legacy.integrityVersion = 13
        legacy.frontierBestStreak = 5
        legacy.frontierBP = 36

        #expect(!SaveTransfer.isTampered(legacy, deviceSeed: seed))

        let migrated = SaveTransfer.signed(legacy, deviceSeed: seed)
        #expect(migrated.integrityVersion == 14)
        #expect(!SaveTransfer.isTampered(migrated, deviceSeed: seed))

        var edited = migrated
        edited.frontierBP += 1
        #expect(SaveTransfer.isTampered(edited, deviceSeed: seed))
    }
}
