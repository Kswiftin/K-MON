import Foundation
import Testing
@testable import PokeTokenBar

@Suite("레이드 보스 정보")
struct RaidBossInfoTests {
    @Test("복합 타입의 4배 약점과 ¼배 반감을 구분하고 보통 상성은 생략한다")
    func dualTypeMatchups() {
        let groups = RaidBossInfo.matchups(types: [.fire, .flying])
        #expect(groups.map(\.multiplier) == [4, 2, 0.5, 0.25, 0])
        #expect(groups.first { $0.multiplier == 4 }?.types == [.rock])
        #expect(groups.first { $0.multiplier == 2 }?.types == [.water, .electric])
        #expect(groups.first { $0.multiplier == 0.25 }?.types == [.grass, .bug])
        #expect(groups.first { $0.multiplier == 0 }?.types == [.ground])
        #expect(!groups.flatMap(\.types).contains(.ice))
    }

    @Test("면역은 다른 타입의 약점보다 우선하고 정보가 없으면 상성을 추측하지 않는다")
    func immunityAndUnknownTypes() {
        let groups = RaidBossInfo.matchups(types: [.water, .ground])
        #expect(groups.first { $0.multiplier == 0 }?.types == [.electric])
        #expect(groups.first { $0.multiplier == 4 }?.types == [.grass])
        #expect(RaidBossInfo.matchups(types: []).isEmpty)
    }

    @Test("미리보기는 일반 포켓몬 HP 대신 레이드 티어의 레벨과 HP를 보여준다")
    func previewUsesRaidRules() {
        let profile = PokemonBattleProfile(speciesID: 6,
            stats: BattleStats(hp: 78, atk: 84, def: 78, spa: 109, spd: 85, spe: 100),
            types: [.fire, .flying], weightHectograms: 905, abilitySlug: "blaze")
        let info = RaidBossInfo(speciesID: 6, name: "리자몽", profile: profile, tier: .three)
        #expect(info.name == "리자몽")
        #expect(info.level == 25)
        #expect(info.maxHP == 1_600)
        #expect(info.types == [.fire, .flying])
        #expect(info.abilitySlug == "blaze")
    }

    @Test("전투에서는 원래 종의 타입이 아닌 현재 타입과 특성을 보여준다")
    func battleUsesCurrentSide() {
        let snapshot = BattleSnapshot(speciesID: 6, name: "리자몽", trainer: nil,
            level: 40, nature: nil, isShiny: false, types: [.fire, .flying],
            base: BattleStats(hp: 78, atk: 84, def: 78, spa: 109, spd: 85, spe: 100),
            moves: [], ability: "blaze", storedTeraType: .water)
        var side = BattleSide(snapshot)
        side.isTerastallized = true
        side.abilityOverride = .waterAbsorb
        side.hp = 500
        let info = RaidBossInfo(side: side, maxHP: 2_800)
        #expect(info.types == [.water])
        #expect(info.abilitySlug == "water-absorb")
        #expect(info.level == 40)
        #expect(info.maxHP == 2_800)
        #expect(info.groups.first { $0.multiplier == 2 }?.types == [.electric, .grass])
    }

    @Test("오른쪽·아래쪽 보스에서도 툴팁 전체가 화면 안에 머문다")
    func tooltipStaysWithinViewport() {
        let rect = RaidBossTooltipLayout.frame(
            anchor: CGRect(x: 295, y: 450, width: 60, height: 40),
            container: CGSize(width: 360, height: 500),
            tooltip: CGSize(width: 300, height: 320))
        #expect(rect.minX >= 8)
        #expect(rect.maxX <= 352)
        #expect(rect.minY >= 8)
        #expect(rect.maxY <= 492)
        #expect(rect.maxY < 450)
    }

    @Test("이전 보스의 늦은 이탈 이벤트가 새 보스의 툴팁을 닫지 않는다")
    @MainActor func oldExitDoesNotCloseNewBoss() async throws {
        let hover = RaidBossHoverState()
        hover.setHovered("one", isInside: true)
        hover.setHovered("three", isInside: true)
        hover.setHovered("one", isInside: false)
        try await Task.sleep(for: .milliseconds(300))
        #expect(hover.targetID == "three")
        hover.dismiss()
    }

    @Test("툴팁으로 커서를 옮기면 유지하고 완전히 벗어나면 닫는다")
    @MainActor func tooltipHoverLifecycle() async throws {
        let hover = RaidBossHoverState()
        hover.setHovered("one", isInside: true)
        hover.setHovered("one", isInside: false)
        hover.setHovered("one", isInside: true)
        try await Task.sleep(for: .milliseconds(300))
        #expect(hover.targetID == "one")
        hover.setHovered("one", isInside: false)
        // CI에서 메인 액터가 밀리면 닫힘 Task도 늦게 시작한다. 실제 닫힘을 기다리되,
        // 닫힘 자체가 고장 난 경우에는 유한한 시간 안에 실패해야 한다.
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while hover.targetID != nil, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(hover.targetID == nil)
    }
}
