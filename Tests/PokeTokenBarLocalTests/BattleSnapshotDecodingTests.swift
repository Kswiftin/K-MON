import Foundation
import Testing
@testable import PokeTokenBar

/// 스냅샷은 피어가 보내오는 값이다. `BattleSide(_:)` 가 디코딩 **직후** 유효 스탯을 계산하므로
/// (`MultiplayerFighter.init(from:)`), 종족값·레벨을 경계에서 자르지 않으면 검증이 돌기 전에
/// `(2 * hp + 31) * level` 이 오버플로로 트랩된다 — 라운드 메시지 하나로 게스트가 죽는다.
@Suite struct BattleSnapshotDecodingTests {
    private func decode(_ json: String) throws -> BattleSnapshot {
        try JSONDecoder().decode(BattleSnapshot.self, from: Data(json.utf8))
    }

    private func snapshotJSON(level: String, base: String,
                              types: String = #"["electric"]"#, extra: String = "") -> String {
        """
        {"v":1,"speciesID":25,"name":"Pikachu","level":\(level),"isShiny":false,
         "types":\(types),"base":\(base)\(extra)}
        """
    }

    /// 종족값·레벨이 Int 상한 근처로 오면 유효 스탯 계산이 오버플로로 트랩된다.
    /// 자르기가 없으면 이 테스트는 **예외가 아니라 프로세스 크래시**로 죽는다.
    @Test func hugeStatsCannotOverflowTheEffectiveStatFormula() throws {
        let huge = String(Int.max)
        let snapshot = try decode(snapshotJSON(
            level: huge,
            base: """
                {"hp":\(huge),"atk":\(huge),"def":\(huge),"spa":\(huge),"spd":\(huge),"spe":\(huge)}
                """))
        #expect(BattleSnapshot.levelRange.contains(snapshot.level))
        for value in [snapshot.base.hp, snapshot.base.atk, snapshot.base.def,
                      snapshot.base.spa, snapshot.base.spd, snapshot.base.spe] {
            #expect(BattleSnapshot.baseStatRange.contains(value))
        }
        // 계산이 실제로 트랩 없이 끝나는지 본다 — 클램프의 목적은 값이 아니라 이 한 줄이다.
        let stats = snapshot.effectiveStats()
        #expect(stats.hp > 0)
        #expect(BattleSide(snapshot).hp == stats.hp)
    }

    /// 음수·0 레벨은 스탯을 0 이하로 만들어 `hp = 0` 인(=시작부터 기절한) 개체가 된다.
    @Test func aNonPositiveLevelIsPulledUpIntoTheBattleRange() throws {
        let snapshot = try decode(snapshotJSON(
            level: "-9000",
            base: #"{"hp":35,"atk":55,"def":40,"spa":50,"spd":50,"spe":90}"#))
        #expect(snapshot.level == BattleSnapshot.levelRange.lowerBound)
        #expect(BattleSide(snapshot).isAlive)
    }

    /// 타입·기술 배열은 화면 한 줄과 기술 네 칸에 그려지는 수다. 상한이 없으면 라운드마다
    /// 참가자 수만큼 다시 나가는 프레임이 그대로 커진다.
    @Test func typeAndMoveArraysAreCutToWhatTheBattleUses() throws {
        let move = #"{"id":1,"names":{"en":"Tackle"},"type":"normal","power":40,"damageClass":"physical","pp":35}"#
        let snapshot = try decode(snapshotJSON(
            level: "50",
            base: #"{"hp":35,"atk":55,"def":40,"spa":50,"spd":50,"spe":90}"#,
            types: #"["electric","fire","water","grass"]"#,
            extra: ",\"moves\":[\(move),\(move),\(move),\(move),\(move),\(move)]"))
        #expect(snapshot.types.count == BattleSnapshot.maximumTypes)
        #expect(snapshot.moves?.count == BattleSnapshot.maximumMoves)
    }

    /// 종 번호는 스프라이트가 있는 범위로 자른다 — 정본은 `PokemonAssets.clampedID` 다.
    @Test func theSpeciesNumberIsCutToTheSpriteRange() throws {
        let snapshot = try decode("""
            {"v":1,"speciesID":99999,"name":"?","level":50,"isShiny":false,"types":["normal"],
             "base":{"hp":35,"atk":55,"def":40,"spa":50,"spd":50,"spe":90},
             "weightHectograms":-40}
            """)
        #expect(PokemonAssets.animatedSpeciesIDs.contains(snapshot.speciesID))
        // 체중은 위력 표를 타므로 음수는 "가장 가벼움" 칸으로 들어간다.
        #expect((snapshot.weightHectograms ?? 0) >= 0)
    }

    /// 라운드 브로드캐스트의 HP 는 호스트 소유다. 최대치를 넘겨 받으면 회복 이벤트를 재생하는
    /// 자리에서 `hp + amount` 가 오버플로로 트랩된다(`BattleReplay.apply`).
    @Test func aFighterHPAboveItsMaximumIsCutAtTheBoundary() throws {
        let fighter = try JSONDecoder().decode(MultiplayerFighter.self, from: Data("""
            {"id":"\(UUID().uuidString)","trainerName":"Red","team":"solo",
             "snapshot":{"v":1,"speciesID":25,"name":"Pikachu","level":50,"isShiny":false,
              "types":["electric"],
              "base":{"hp":35,"atk":55,"def":40,"spa":50,"spd":50,"spe":90}},
             "hp":\(Int.max),"pp":[\(Int.max)],
             "statusCounter":-5,"confusionTurns":-5}
            """.utf8))
        #expect(fighter.side.hp == fighter.side.stats.hp)
        #expect(fighter.side.pp.allSatisfy { $0 >= 0 })
        for (index, remaining) in fighter.side.pp.enumerated() {
            #expect(remaining <= fighter.side.moves[index].pp)
        }
        #expect(fighter.side.statusCounter == 0)
        #expect(fighter.side.confusionTurns == 0)
        // 회복 이벤트 재생이 트랩 없이 끝나는지 본다 — 클램프의 목적이 이 한 줄이다.
        let steps = BattleReplay.steps([.heal(.fighter(fighter.id), amount: 40)],
                                       from: [.fighter(fighter.id): ReplaySide(team: [fighter.side],
                                                                               active: 0)],
                                       speed: .normal)
        #expect(steps.count == 1)
    }

    /// 정상 스냅샷은 왕복해도 한 값도 바뀌지 않는다 — 클램프가 정상 대전을 바꾸면 두 피어가
    /// 서로 다른 개체로 싸운다(desync).
    @Test func aNormalSnapshotRoundTripsUnchanged() throws {
        let snapshot = BattleSnapshot(
            speciesID: 25, name: "피카츄", trainer: "Red", level: 50, nature: .jolly,
            isShiny: false, types: [.electric],
            base: BattleStats(hp: 35, atk: 55, def: 40, spa: 50, spd: 50, spe: 90),
            moves: MoveSpec.fallbackSet(types: [.electric]),
            ability: "static", weightHectograms: 60)
        let decoded = try JSONDecoder().decode(BattleSnapshot.self,
                                               from: try JSONEncoder().encode(snapshot))
        #expect(decoded == snapshot)
    }
}
