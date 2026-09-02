import Foundation
import Testing
@testable import PokeTokenBar

/// 경기 상태는 호스트가 보내오는 값이다. 화면은 `teamSpeciesIDs` 의 인덱스로 `stamina` 를 읽고
/// `activeSpeciesID` 는 `activeTeamIndex` 로 팀을 읽으므로, 경계에서 자르지 않으면 조작된(또는
/// 버전이 다른) 호스트가 게스트를 인덱스 범위 밖 접근으로 죽인다.
@Suite struct PokeathlonDecodingTests {
    private func decodeRacer(_ json: String) throws -> PokeathlonRacer {
        try JSONDecoder().decode(PokeathlonRacer.self, from: Data(json.utf8))
    }

    /// 팀보다 짧은 스태미나 배열은 화면이 그리는 순간 죽는다 — 팀 자리 수만큼 채운다.
    @Test func staminaIsResizedToTheTeamItIsIndexedBy() throws {
        let racer = try decodeRacer("""
            {"id":"\(UUID().uuidString)","trainerName":"Red","speciesID":25,
             "teamSpeciesIDs":[25,4,7],"activeTeamIndex":0,"stamina":[100],
             "distance":0,"crashes":0,"lane":1,"finished":false}
            """)
        #expect(racer.stamina.count == racer.teamSpeciesIDs.count)
        for index in racer.teamSpeciesIDs.indices { #expect(racer.stamina[index] >= 0) }
    }

    /// 음수 인덱스는 `activeSpeciesID` 의 첨자로 그대로 들어간다.
    @Test func aNegativeActiveIndexIsPulledBackIntoTheTeam() throws {
        let racer = try decodeRacer("""
            {"id":"\(UUID().uuidString)","trainerName":"Red","speciesID":25,
             "teamSpeciesIDs":[25,4],"activeTeamIndex":-7,"stamina":[100,100],
             "distance":0,"crashes":0,"lane":1,"finished":false}
            """)
        #expect(racer.activeTeamIndex == 0)
        #expect(racer.activeSpeciesID == 25)
    }

    /// 범위 밖 값들은 화면이 쓰는 범위로 잘린다.
    @Test func outOfRangeValuesAreClamped() throws {
        let racer = try decodeRacer("""
            {"id":"\(UUID().uuidString)","trainerName":"   ","speciesID":99999,
             "teamSpeciesIDs":[1,2,3,4,5,6,7,8,9],"activeTeamIndex":0,
             "stamina":[9999,-40,0,0,0,0],"distance":99999,"crashes":-3,"lane":9,"finished":false}
            """)
        #expect(racer.speciesID <= 649)
        #expect(racer.teamSpeciesIDs.count == PokeathlonRacer.maximumTeamSize)
        #expect(racer.stamina.allSatisfy { (0...PokeathlonRacer.maximumStamina).contains($0) })
        #expect(racer.distance <= PokeathlonRace.finishLine)
        #expect(racer.crashes == 0)
        #expect((0...2).contains(racer.lane))
        #expect(!racer.trainerName.isEmpty, "빈 이름은 화면에서 이름 자리를 통째로 지운다")
    }

    /// 트랙에 없는 우승자는 정산이 아무에게도 닿지 않는 값이다.
    @Test func aWinnerWhoIsNotRacingIsDropped() throws {
        let racerID = UUID()
        let race = try JSONDecoder().decode(PokeathlonRace.self, from: Data("""
            {"racers":[{"id":"\(racerID.uuidString)","trainerName":"Red","speciesID":25,
             "teamSpeciesIDs":[25],"activeTeamIndex":0,"stamina":[100],
             "distance":0,"crashes":0,"lane":1,"finished":false}],
             "winnerID":"\(UUID().uuidString)","startsAt":0}
            """.utf8))
        #expect(race.winnerID == nil)
        #expect(race.racers.count == 1)
    }

    /// 정상 값은 그대로 통과한다 — 클램프가 정상 경기까지 바꾸면 화면이 다른 경기를 그린다.
    @Test func aNormalRaceRoundTripsUnchanged() throws {
        let race = PokeathlonRace(racers: [
            PokeathlonRacer(id: UUID(), trainerName: "Red", speciesID: 25, teamSpeciesIDs: [25, 4, 7])
        ])
        let decoded = try JSONDecoder().decode(PokeathlonRace.self,
                                               from: try JSONEncoder().encode(race))
        #expect(decoded == race)
    }
}
