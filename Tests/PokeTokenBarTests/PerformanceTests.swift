import XCTest
@testable import PokeTokenBar

// 성능(measure) + 스케일/비퇴화 검증. baseline 은 머신 의존이라 느슨하게(게이트는 정확성에).
// SeededRNG / StubProvider 는 CompanionTests.swift 의 내부 헬퍼 재사용.

private func pnode(_ id: Int, _ children: [EvoNode] = []) -> EvoNode { EvoNode(speciesID: id, children: children) }
private func pline(base: Int, rarity: Rarity) -> EvoLine {
    EvoLine(baseID: base, tree: pnode(base, [pnode(base + 1, [pnode(base + 2)])]), rarity: rarity, names: [:])
}
private let pNow = Date(timeIntervalSince1970: 1_700_000_000)
private func tmpURL() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("poke-perf-\(UUID().uuidString).json")
}

// MARK: 순수 계산 핫패스

final class PureComputePerformanceTests: XCTestCase {
    func testPhaseThresholdThroughput() {
        measure {
            var acc = 0
            for i in 0..<100_000 {
                acc &+= PokemonBalance.phaseThreshold(rarity: .rare, totalForms: 3, stageIndex: i % 3)
            }
            XCTAssertGreaterThan(acc, 0)
        }
    }

}

// MARK: 스토어 핫패스 / 스케일

@MainActor
final class StorePerformanceTests: XCTestCase {
    /// 큰 도감을 파일 로드로 주입하고 정렬 비용/정확성을 함께 본다.
    private func storeWithLargeDex(_ count: Int) throws -> CompanionStore {
        let entries = (0..<count).map { i -> DexEntry in
            let r: Rarity = [.common, .uncommon, .rare, .legendary][i % 4]
            return DexEntry(baseID: i, finalID: i, chainOrder: [i], rarity: r,
                            caughtAt: pNow.addingTimeInterval(Double(i)))
        }
        let dexJSON = String(data: try JSONEncoder().encode(entries), encoding: .utf8)!
        let url = tmpURL()
        try Data("{\"economyVersion\":2,\"forcedResetVersion\":1,\"starterChosen\":true,\"dex\":\(dexJSON),\"language\":\"ko\"}".utf8).write(to: url)
        return CompanionStore(provider: StubProvider(value: pline(base: 1, rarity: .common)),
                              clock: { pNow }, fileURL: url, rng: SeededRNG(seed: 1))
    }

    func testLargeDexSortPerformanceAndCorrectness() throws {
        let s = try storeWithLargeDex(1000)
        XCTAssertEqual(s.dexEntries.count, 1000)
        measure {
            let sorted = s.dexEntriesSorted
            XCTAssertEqual(sorted.count, 1000)
        }
        // 정렬 정확성: 포획 로그는 기록 시각 최신순 — 희귀도는 순서에 관여하지 않는다.
        let sorted = s.dexEntriesSorted
        for i in 1..<sorted.count {
            XCTAssertGreaterThanOrEqual(
                sorted[i - 1].caughtAt ?? .distantPast,
                sorted[i].caughtAt ?? .distantPast)
        }
        XCTAssertEqual(sorted.first?.caughtAt, pNow.addingTimeInterval(999), "가장 최신 항목이 맨 앞")
        XCTAssertEqual(s.dexCount(.legendary), 250)
    }
}

// MARK: 비퇴화(터미네이션) 가드

@MainActor
final class StoreTerminationTests: XCTestCase {
    func testHugeDeltaGraduatesOnceAndTerminates() async {
        // 거대한 단일 델타가 무한 루프 없이 라인을 통과해 정확히 1회 졸업하는지 (guardCount 캡 보호).
        let s = CompanionStore(provider: StubProvider(value: pline(base: 1, rarity: .common)),
                               clock: { pNow }, fileURL: tmpURL(), rng: SeededRNG(seed: 1))
        await s.hatch(baseID: 1)
        s.debugAccrueLevelExperience(300_000_000)   // 졸업은 희귀도 무관 레벨 30 게이트(#19)
        s.applyUsage(Int(PokemonBalance.graduationTotal(.common)) * 10)   // 졸업 총량의 10배
        XCTAssertNil(s.state.active)            // 졸업 완료
        XCTAssertEqual(s.dexEntries.count, 1)   // 정확히 1회
        XCTAssertEqual(s.dexEntries[0].chainOrder, [1, 2, 3])
        XCTAssertEqual(s.state.eggUsage, 0)     // 새 알 인큐베이션 리셋
    }

    func testRepeatedGraduationGrowsDexLinearly() async {
        // 무진화 라인을 반복 졸업 — dex 가 선형으로 증가하고 상태가 매번 정합한지.
        let provider = StubProvider(value: pline(base: 1, rarity: .common))
        let s = CompanionStore(provider: provider, clock: { pNow }, fileURL: tmpURL(), rng: SeededRNG(seed: 9))
        for n in 1...20 {
            await s.hatch(baseID: 1)
            s.debugAccrueLevelExperience(300_000_000)   // 졸업은 희귀도 무관 레벨 30 게이트(#19)
            s.applyUsage(Int(PokemonBalance.graduationTotal(.common)) * 10)
            XCTAssertEqual(s.dexEntries.count, n)
            XCTAssertNil(s.state.active)
        }
    }
}

// MARK: 플로팅 펫 / 스프라이트 애니메이션 규율

/// 플로팅 펫은 쇼다운 원본 속도를 유지하고, 저전력 모드에서만 정적으로 전환한다.
@MainActor
final class FloatingPetEnergyTests: XCTestCase {
    /// floor가 지정된 다른 표면은 여전히 최소 프레임 지연을 지킨다.
    func testPetFrameDelayHonorsFloor() {
        XCTAssertEqual(SpriteView.frameDelay(base: 0.1, floor: 0.4), 0.4, accuracy: 1e-9)   // 빠른 프레임 → 캡
        XCTAssertEqual(SpriteView.frameDelay(base: 0.6, floor: 0.4), 0.6, accuracy: 1e-9)   // 이미 느리면 원본 유지
    }

    /// floor=0이면 네이티브 delay를 그대로 사용한다.
    func testTransientSpriteKeepsNativeDelay() {
        XCTAssertEqual(SpriteView.frameDelay(base: 0.1, floor: 0), 0.1, accuracy: 1e-9)
        XCTAssertEqual(SpriteView.frameDelay(base: 0.03, floor: 0), 0.03, accuracy: 1e-9)
    }

    /// 저전력 모드면 펫 애니메이션을 정지(정적)해 배터리를 아낀다. 정상 모드면 애니메이션.
    func testPetFreezesUnderLowPower() {
        XCTAssertFalse(FloatingPetController.shouldAnimate(lowPower: true))
        XCTAssertTrue(FloatingPetController.shouldAnimate(lowPower: false))
    }

    /// [회귀] 플로팅 펫은 별도 fps 캡 없이 쇼다운 GIF의 원본 delay를 사용한다.
    func testPetUsesNativeFrameRate() {
        XCTAssertEqual(FloatingPetView.frameFloor, 0, accuracy: 1e-9)
    }

    func testPanelKeepsPetOrigin() {
        let pet: CGFloat = 96
        let panel = FloatingPetController.panelSize(petSize: pet)
        XCTAssertEqual(panel, NSSize(width: pet, height: pet))

        let petOrigin = NSPoint(x: 400, y: 200)
        let panelOrigin = FloatingPetController.panelOrigin(
            petOrigin: petOrigin, petSize: pet, panelSize: panel)
        XCTAssertEqual(panelOrigin.y, petOrigin.y, accuracy: 0.5)
        let roundTrip = FloatingPetController.petOrigin(
            panelOrigin: panelOrigin, petSize: pet, panelSize: panel)
        XCTAssertEqual(roundTrip.x, petOrigin.x, accuracy: 0.5)
        XCTAssertEqual(roundTrip.y, petOrigin.y, accuracy: 0.5)
    }

    func testAdjacentMonitorsFormOneWalkableSurface() {
        let left = NSRect(x: 0, y: 0, width: 1000, height: 800)
        let right = NSRect(x: 1000, y: 0, width: 1000, height: 800)
        let crossingPet = NSRect(x: 950, y: 200, width: 100, height: 100)
        XCTAssertTrue(FloatingPetController.isCovered(crossingPet, by: [left, right]))

        let moved = FloatingPetController.resolvedMotion(
            origin: NSPoint(x: 940, y: 200), petSize: 100,
            velocity: CGVector(dx: 100, dy: 0), delta: 0.2, screens: [left, right])
        XCTAssertEqual(moved.origin.x, 960, accuracy: 0.001)
        XCTAssertGreaterThan(moved.velocity.dx, 0)
    }

    func testOuterDisplayEdgeReflectsMovement() {
        let screen = NSRect(x: 0, y: 0, width: 1000, height: 800)
        let moved = FloatingPetController.resolvedMotion(
            origin: NSPoint(x: 900, y: 200), petSize: 100,
            velocity: CGVector(dx: 100, dy: 20), delta: 0.2, screens: [screen])
        XCTAssertEqual(moved.origin.x, 900, accuracy: 0.001)
        XCTAssertLessThan(moved.velocity.dx, 0)
        XCTAssertGreaterThan(moved.velocity.dy, 0)
    }

    func testGapBetweenMonitorsIsAClosedBoundary() {
        let left = NSRect(x: 0, y: 0, width: 1000, height: 800)
        let separated = NSRect(x: 1010, y: 0, width: 1000, height: 800)
        let crossingGap = NSRect(x: 950, y: 200, width: 100, height: 100)
        XCTAssertFalse(FloatingPetController.isCovered(crossingGap, by: [left, separated]))
    }

    func testOffsetMonitorAllowsOnlyOverlappingPassage() {
        let left = NSRect(x: 0, y: 0, width: 1000, height: 800)
        let upperRight = NSRect(x: 1000, y: 400, width: 1000, height: 800)
        XCTAssertTrue(FloatingPetController.isCovered(
            NSRect(x: 950, y: 500, width: 100, height: 100), by: [left, upperRight]))
        XCTAssertFalse(FloatingPetController.isCovered(
            NSRect(x: 950, y: 100, width: 100, height: 100), by: [left, upperRight]))
    }

    func testBlockedRightwardCrossingFindsNearestPortal() {
        let left = NSRect(x: -1920, y: 712, width: 1920, height: 1080)
        let right = NSRect(x: 0, y: 0, width: 1728, height: 1084)
        let route = FloatingPetController.portalRoute(
            origin: NSPoint(x: -96, y: 1500), petSize: 96,
            velocity: CGVector(dx: 80, dy: 0), screens: [left, right])
        XCTAssertNotNil(route)
        XCTAssertEqual(route?.target ?? 0, 988, accuracy: 0.001)
        XCTAssertEqual(route?.crossingSign ?? 0, 1, accuracy: 0.001)
        XCTAssertEqual(route?.completionCoordinate ?? 1, 0, accuracy: 0.001)
    }

    func testDiagonalEntryFromPortraitDisplayIsLockedBeforeStraddling() {
        let portrait = NSRect(x: -3000, y: 11, width: 1080, height: 1920)
        let center = NSRect(x: -1920, y: 712, width: 1920, height: 1080)
        let route = FloatingPetController.portalRoute(
            origin: NSPoint(x: -1992, y: 1000), petSize: 72,
            velocity: CGVector(dx: 141, dy: 141), screens: [portrait, center])
        XCTAssertNotNil(route, "유효 통로에서도 경계에 걸치기 전에 통과 잠금을 시작해야 함")
        XCTAssertEqual(route?.target ?? 0, 1000, accuracy: 0.001)
        XCTAssertEqual(route?.crossingSign ?? 0, 1, accuracy: 0.001)
        XCTAssertEqual(route?.completionCoordinate ?? 0, -1920, accuracy: 0.001)
    }

    func testPortraitToCenterPortalUsesAtomicHandoff() {
        let portrait = NSRect(x: -3000, y: 11, width: 1080, height: 1920)
        let center = NSRect(x: -1920, y: 712, width: 1920, height: 1080)
        let route = FloatingPetController.PortalRoute(
            axis: .horizontal, target: 1000, crossingSign: 1,
            completionCoordinate: -1920)
        let destination = FloatingPetController.portalDestinationOrigin(
            from: NSPoint(x: -1992, y: 1000), route: route)
        XCTAssertEqual(destination.x, -1920, accuracy: 0.001)
        XCTAssertEqual(destination.y, 1000, accuracy: 0.001)
        XCTAssertTrue(FloatingPetController.isCovered(
            NSRect(origin: destination, size: NSSize(width: 72, height: 72)),
            by: [portrait, center]))
    }

    func testStraddledPortraitBoundaryCanRecoverPortalLock() {
        let portrait = NSRect(x: -3000, y: 11, width: 1080, height: 1920)
        let center = NSRect(x: -1920, y: 712, width: 1920, height: 1080)
        let route = FloatingPetController.portalRoute(
            origin: NSPoint(x: -1950, y: 1000), petSize: 72,
            velocity: CGVector(dx: 180, dy: 40), screens: [portrait, center])
        XCTAssertNotNil(route, "이미 경계에 걸친 상태에서도 오른쪽 통과 잠금을 복구해야 함")
        XCTAssertEqual(route?.target ?? 0, 1000, accuracy: 0.001)
        XCTAssertEqual(route?.crossingSign ?? 0, 1, accuracy: 0.001)
        XCTAssertEqual(route?.completionCoordinate ?? 0, -1920, accuracy: 0.001)
    }

    func testBlockedLeftwardCrossingFindsSamePortal() {
        let left = NSRect(x: -1920, y: 712, width: 1920, height: 1080)
        let right = NSRect(x: 0, y: 0, width: 1728, height: 1084)
        let route = FloatingPetController.portalRoute(
            origin: NSPoint(x: 0, y: 300), petSize: 96,
            velocity: CGVector(dx: -80, dy: 0), screens: [left, right])
        XCTAssertNotNil(route)
        XCTAssertEqual(route?.target ?? 0, 712, accuracy: 0.001)
        XCTAssertEqual(route?.crossingSign ?? 0, -1, accuracy: 0.001)
        XCTAssertEqual(route?.completionCoordinate ?? 0, -96, accuracy: 0.001)
    }

    func testOuterEdgeHasNoPortalRoute() {
        let screen = NSRect(x: 0, y: 0, width: 1000, height: 800)
        XCTAssertNil(FloatingPetController.portalRoute(
            origin: NSPoint(x: 900, y: 200), petSize: 100,
            velocity: CGVector(dx: 80, dy: 0), screens: [screen]))
    }

    func testRandomDirectionHasMinimumTravelWindow() {
        XCTAssertGreaterThanOrEqual(FloatingPetController.minimumTravelDuration, 3)
        XCTAssertGreaterThan(FloatingPetController.maximumTravelDuration,
                             FloatingPetController.minimumTravelDuration)
    }

    func testRoamingSettingsDefaultAndPersist() {
        let suite = "FloatingPetRoamingTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let initial = AppSettings(defaults: defaults)
        XCTAssertFalse(initial.floatingPetRoamingEnabled)
        XCTAssertFalse(initial.floatingPetMouseChaseEnabled)
        XCTAssertEqual(initial.floatingPetMovementSpeed, 80)
        initial.floatingPetRoamingEnabled = true
        initial.floatingPetMouseChaseEnabled = true
        initial.floatingPetMovementSpeed = 140

        let restored = AppSettings(defaults: defaults)
        XCTAssertTrue(restored.floatingPetRoamingEnabled)
        XCTAssertTrue(restored.floatingPetMouseChaseEnabled)
        XCTAssertEqual(restored.floatingPetMovementSpeed, 140)
    }

    func testMouseChaseUsesDirectShortestVectorAndStopsNearPointer() {
        let velocity = FloatingPetController.mouseChaseVelocity(
            petOrigin: NSPoint(x: 0, y: 0), petSize: 20,
            mouse: NSPoint(x: 40, y: 50), speed: 100)
        XCTAssertEqual(velocity.dx, 60, accuracy: 0.001)
        XCTAssertEqual(velocity.dy, 80, accuracy: 0.001)

        let stopped = FloatingPetController.mouseChaseVelocity(
            petOrigin: NSPoint(x: 0, y: 0), petSize: 40,
            mouse: NSPoint(x: 35, y: 20), speed: 100)
        XCTAssertEqual(stopped, .zero)
    }

    func testMouseChasePortalUsesStraightLineIntersection() {
        let portrait = NSRect(x: -3000, y: 11, width: 1080, height: 1920)
        let center = NSRect(x: -1920, y: 712, width: 1920, height: 1080)
        let route = FloatingPetController.portalRoute(
            origin: NSPoint(x: -1992, y: 1000), petSize: 72,
            velocity: CGVector(dx: 100, dy: 100), screens: [portrait, center],
            destination: NSPoint(x: -1884, y: 1236))
        XCTAssertEqual(route?.target ?? 0, 1100, accuracy: 0.001)
    }

    /// Click opens the popover only when the pointer barely moved; larger movement is a drag.
    func testClickThresholdDistinguishesClickFromDrag() {
        let a = NSPoint(x: 10, y: 10)
        XCTAssertTrue(FloatingPetController.isClick(from: a, to: NSPoint(x: 11, y: 12)))
        XCTAssertTrue(FloatingPetController.isClick(from: a, to: a))
        XCTAssertFalse(FloatingPetController.isClick(from: a, to: NSPoint(x: 20, y: 10)))
    }

}
