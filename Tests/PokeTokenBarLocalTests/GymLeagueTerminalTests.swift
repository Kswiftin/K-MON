import Foundation
import Testing
@testable import PokeTokenBar

/// 체육관 리그를 터미널에서 보는 자리 (Phase 5-7).
///
/// **LAN 방 쪽과 근거가 다르다.** 리그 진행(배지)은 세이브에 남으므로 터미널이 읽기 전용으로
/// 직접 읽고 화면 채널을 타지 않는다 — 웨이브 런·Memory Home 과 같은 쪽이고, 그래서
/// `pokedoro gym` 은 앱이 꺼져 있어도 답한다. 방에서 도는 판(관장 대전)만 채널이다.
///
/// 이 스위트가 잡은 결함: 터미널은 **아무도 쓰지 않는 옛 칸**을 세고 있었다. 현행 리그는
/// `gymLeagueBadges` 에 첫 승리를 적는데(`CompanionStore.recordGymVictory`) `pokedoro challenge`
/// 는 `gymBadges` 를 셌다. 앱의 `GymLeagueView` 는 처음부터 `gymLeagueBadges` 를 읽으므로,
/// 같은 세이브를 두고 앱과 터미널이 **다른 숫자**를 보여 주고 있었다.
@Suite("GymLeagueTerminalTests")
@MainActor
struct GymLeagueTerminalTests {

    private func makeStore(_ directory: URL) -> CompanionStore {
        let store = CompanionStore(clock: { Date(timeIntervalSince1970: 1_700_000_000) },
                                   fileURL: directory.appendingPathComponent("state.json"))
        store.setLanguage(.ko)
        return store
    }

    /// 결함의 회귀. 체육관 하나를 이긴 뒤 배지 줄이 **움직여야** 한다.
    @Test func testTheBadgeRowCountsTheFieldTheLeagueActuallyWrites() throws {
        let directory = storeFixtureDirectory("gym-badges")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = makeStore(directory)
        let gym = try #require(GymLeague.catalog.first)

        let before = PokedoroCLI.challengeRows(store, width: 60)
        store.recordGymVictory(gym)
        let after = PokedoroCLI.challengeRows(store, width: 60)

        #expect(before.contains { $0.contains("0/\(GymLeague.catalog.count)") }, "\(before)")
        #expect(after.contains { $0.contains("1/\(GymLeague.catalog.count)") },
                "배지를 땄는데 줄이 그대로다 — 아무도 쓰지 않는 칸을 세고 있다: \(after)")
    }

    /// 앱과 터미널이 **같은 칸**을 읽는다. 두 화면이 갈라지면 어느 쪽이 맞는지 알 방법이 없다.
    @Test func testTheAppAndTheTerminalReadTheSameBadgeField() throws {
        let directory = storeFixtureDirectory("gym-same-field")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = makeStore(directory)
        // 옛 칸에만 값이 있는 세이브 — 이전 배포에서 넘어온 모양이다.
        store.debugSetLegacyGymBadges(["fire", "water", "grass"])

        let rows = PokedoroCLI.challengeRows(store, width: 60)

        #expect(store.state.gymLeagueBadges.isEmpty)
        #expect(rows.contains { $0.contains("0/\(GymLeague.catalog.count)") },
                "옛 칸을 세면 이긴 적 없는 체육관이 배지로 잡힌다: \(rows)")
    }

    // MARK: 목록

    /// 여덟 곳이 **전부** 나온다. 카탈로그 길이를 여기 적지 않는 이유는 항목이 늘 때 이 줄만
    /// 옛말이 되기 때문이다.
    @Test func testEveryGymInTheCatalogGetsARow() throws {
        let directory = storeFixtureDirectory("gym-rows")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = makeStore(directory)

        let rows = PokedoroCLI.gymRows(store, width: 72)

        for gym in GymLeague.catalog {
            #expect(rows.contains { $0.contains(gym.leaderName(.ko)) },
                    "\(gym.id) 가 목록에 없다")
        }
    }

    /// 딴 곳에 표시가 있다 — 없으면 어디를 다시 가야 하는지 알 수 없다.
    @Test func testAClearedGymIsMarked() throws {
        let directory = storeFixtureDirectory("gym-cleared")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = makeStore(directory)
        let gym = try #require(GymLeague.catalog.first)
        store.recordGymVictory(gym)

        let rows = PokedoroCLI.gymRows(store, width: 72)
        let row = try #require(rows.first { $0.contains(gym.leaderName(.ko)) })
        let other = try #require(rows.first { $0.contains(GymLeague.catalog[1].leaderName(.ko)) })

        #expect(row != other)
        #expect(row.contains(TUIRender.doneMark), "\(row)")
        #expect(!other.contains(TUIRender.doneMark), "\(other)")
    }

    /// 도전 요건을 **같은 표에서** 읽는다. 여기 숫자를 적으면 균형을 바꿀 때 이 줄만 거짓이 되고,
    /// 사용자는 요건을 채웠다고 믿은 채 거절당한다.
    @Test func testTheChallengeRequirementComesFromTheLeagueTable() throws {
        let directory = storeFixtureDirectory("gym-requirement")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = makeStore(directory)

        let rows = PokedoroCLI.gymRows(store, width: 72)

        #expect(rows.contains { $0.contains("\(GymLeague.minChallengerLevel)") }, "\(rows)")
        #expect(rows.contains { $0.contains("\(GymLeague.teamSize)") }, "\(rows)")
    }

    /// 도전은 **앱에서** 한다 — 팀을 고르고 종 데이터를 받아 와야 판이 선다. 안내가 그 말을
    /// 해야 사용자가 터미널에서 명령을 찾다 그만두지 않는다.
    @Test func testTheListSaysWhereChallengingHappens() throws {
        let directory = storeFixtureDirectory("gym-where")
        defer { try? FileManager.default.removeItem(at: directory) }

        let rows = PokedoroCLI.gymRows(makeStore(directory), width: 72)

        #expect(rows.contains { $0.contains("앱") }, "\(rows)")
    }

    /// 조회라 **요청이 되지 않는다** — 앱이 꺼져 있어도 답한다(웨이브 런·Memory Home 과 같다).
    @Test func testTheGymListNeedsNoRunningApp() throws {
        #expect(try PokedoroCommandParser.parse(["gym"]).request == nil)
    }
}
