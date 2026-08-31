import XCTest
import Network
@testable import PokeTokenBar

/// Memory Home 의 LAN 방문 프로토콜 — 카드의 전선 형식(구버전 호환·v2 확장), 남이 보낸
/// 페이로드를 거르는 신뢰경계 클램프(`MemoryHomeVisitCenter.valid`), 그리고 연결 수명.
@MainActor
final class MemoryHomeVisitProtocolTests: XCTestCase {
    // MARK: - LAN 카드 계약

    func testPreR4ProfileCardPayloadStillDecodes() throws {
        // `profileMessage` 키가 없는 R4 이전 피어의 페이로드. `Optional` 이라 합성 Codable 이
        // `decodeIfPresent` 를 쓰므로 통과해야 한다 — 여기가 깨지면 프로토콜 호환이 끊긴다.
        let legacy = #"{"displayName":"MemoryHome","speciesID":25,"isShiny":true}"#
        let card = try JSONDecoder().decode(MemoryHomeProfileCard.self, from: Data(legacy.utf8))
        XCTAssertEqual(card.speciesID, 25)
        XCTAssertNil(card.profileMessage)
        XCTAssertTrue(MemoryHomeVisitCenter.valid(card))
    }

    func testRemoteProfileMessageIsValidatedLikeALocalOne() {
        var card = MemoryHomeProfileCard(displayName: "MemoryHome", speciesID: 25, isShiny: false,
                                         sharedMemoryBody: nil, profileMessage: "피카츄랑 여행중 :)")
        XCTAssertTrue(MemoryHomeVisitCenter.valid(card), "로컬에서 저장 가능한 문구를 상대가 거부했다")

        card.profileMessage = "줄바꿈\n주입"
        XCTAssertFalse(MemoryHomeVisitCenter.valid(card), "줄바꿈이 든 원격 문구가 통과했다")

        card.profileMessage = String(repeating: "가", count: MemoryHomeAccessSettings.profileMessageLimit + 1)
        XCTAssertFalse(MemoryHomeVisitCenter.valid(card), "길이 상한을 넘는 원격 문구가 통과했다")

        card.profileMessage = "   "
        XCTAssertFalse(MemoryHomeVisitCenter.valid(card))
    }

    // MARK: - 신뢰경계 클램프 (원격 카드가 통과하면 안 되는 것들)

    /// `valid(_:)` 는 남이 보낸 페이로드를 거르는 **유일한** 관문인데, 여기 있던 테스트는
    /// `profileMessage` 하나만 부정 검증했다. 나머지 필드는 "통과하는 카드" 로만 확인돼서,
    /// 상한을 통째로 지워도 깨지는 테스트가 없었다 — 가드가 있는데 무테스트인 부류다.
    private func card(_ mutate: (inout MemoryHomeProfileCard) -> Void = { _ in }) -> MemoryHomeProfileCard {
        var card = MemoryHomeProfileCard(displayName: "MemoryHome", speciesID: 25, isShiny: false,
                                         sharedMemoryBody: nil, profileMessage: nil)
        mutate(&card)
        return card
    }

    func testValidRejectsOutOfRangeSpeciesID() {
        XCTAssertTrue(MemoryHomeVisitCenter.valid(card()), "정상 카드가 거부됐다")
        XCTAssertFalse(MemoryHomeVisitCenter.valid(card { $0.speciesID = 0 }), "종 번호 0 이 통과했다")
        XCTAssertFalse(MemoryHomeVisitCenter.valid(card { $0.speciesID = -1 }), "음수 종 번호가 통과했다")
        XCTAssertFalse(MemoryHomeVisitCenter.valid(card { $0.speciesID = 10_001 }), "상한을 넘는 종 번호가 통과했다")
        XCTAssertTrue(MemoryHomeVisitCenter.valid(card { $0.speciesID = 10_000 }), "경계값 10000 이 거부됐다")
    }

    func testValidRejectsMalformedDisplayName() {
        XCTAssertFalse(MemoryHomeVisitCenter.valid(card { $0.displayName = "" }), "빈 이름이 통과했다")
        XCTAssertFalse(MemoryHomeVisitCenter.valid(card { $0.displayName = "   " }), "공백뿐인 이름이 통과했다")
        XCTAssertFalse(MemoryHomeVisitCenter.valid(card { $0.displayName = "줄바꿈\n주입" }), "줄바꿈이 든 이름이 통과했다")
        XCTAssertFalse(MemoryHomeVisitCenter.valid(card { $0.displayName = String(repeating: "가", count: 41) }),
                       "40자 상한을 넘는 이름이 통과했다")
    }

    func testValidRejectsOversizedSharedMemoryBody() {
        XCTAssertTrue(MemoryHomeVisitCenter.valid(card { $0.sharedMemoryBody = String(repeating: "가", count: 280) }))
        XCTAssertFalse(MemoryHomeVisitCenter.valid(card { $0.sharedMemoryBody = String(repeating: "가", count: 281) }),
                       "280자 상한을 넘는 추억 본문이 통과했다")
    }

    func testValidRejectsNonFurnitureAndOffGridDecor() {
        XCTAssertFalse(MemoryHomeVisitCenter.valid(card { $0.showcaseFurniture = [.rareCandy] }),
                       "가구가 아닌 아이템이 진열장에 통과했다")
        XCTAssertFalse(MemoryHomeVisitCenter.valid(card {
            $0.placedDecor = [.init(item: .rareCandy, position: .init(x: 0.5, y: 0.5))]
        }), "가구가 아닌 배치 아이템이 통과했다")
        XCTAssertFalse(MemoryHomeVisitCenter.valid(card {
            $0.placedDecor = [.init(item: .retroArcade, position: .init(x: 1.5, y: 0.5))]
        }), "격자 밖 x 좌표가 통과했다")
        XCTAssertFalse(MemoryHomeVisitCenter.valid(card {
            $0.placedDecor = [.init(item: .retroArcade, position: .init(x: 0.5, y: -0.2))]
        }), "격자 밖 y 좌표가 통과했다")
        XCTAssertFalse(MemoryHomeVisitCenter.valid(card {
            $0.placedDecor = (0..<13).map { _ in .init(item: .retroArcade, position: .init(x: 0.5, y: 0.5)) }
        }), "12칸 상한을 넘는 배치가 통과했다")
    }

    /// `placedDecor` 는 12개로 잘리는데 `showcaseFurniture` 는 **개수 상한이 없었다** — 원소가
    /// 전부 진짜 가구여도 통과한다. 방문 시트가 이 배열을 `ForEach` 로 한 줄에 늘어놓으므로
    /// (`MemoryHomePresenter`), 16KB 프레임에 들어가는 ~1000개를 보내면 화면이 멎는다.
    func testValidRejectsAFloodOfShowcaseFurniture() {
        XCTAssertTrue(MemoryHomeVisitCenter.valid(card {
            $0.showcaseFurniture = Array(repeating: .retroArcade, count: 12)
        }), "12개 진열이 거부됐다")
        XCTAssertFalse(MemoryHomeVisitCenter.valid(card {
            $0.showcaseFurniture = Array(repeating: .retroArcade, count: 1_000)
        }), "1000개짜리 진열장이 통과했다 — 방문 시트가 그대로 그린다")
    }

    /// 사진의 네 스타일 문자열은 자유 `String` 이다. 렌더는 알려진 리터럴만 비교하고 나머지는
    /// 기본값으로 떨어지므로 **주입 위험은 없다** — 문제는 길이가 열려 있다는 것뿐이다.
    /// 그래도 신뢰경계라고 적어 둔 검증기가 실제로는 안 보는 필드가 있으면 안 된다.
    func testValidRejectsOverlongPhotoStyleStrings() {
        func photo(_ mutate: (inout MemoryHomePhoto) -> Void) -> MemoryHomeProfileCard {
            var shot = MemoryHomePhoto(speciesID: 25, isShiny: false, caption: "hi", frame: "star",
                                       background: "studio", composition: "left", trainerStyle: "explorer")
            mutate(&shot)
            return card { $0.featuredPhoto = shot }
        }
        XCTAssertTrue(MemoryHomeVisitCenter.valid(photo { _ in }), "정상 사진이 거부됐다")
        XCTAssertFalse(MemoryHomeVisitCenter.valid(photo { $0.speciesID = 0 }), "사진의 종 번호 0 이 통과했다")
        XCTAssertFalse(MemoryHomeVisitCenter.valid(photo { $0.caption = String(repeating: "가", count: 61) }),
                       "60자 상한을 넘는 캡션이 통과했다")
        for label in ["frame", "background", "composition", "trainerStyle"] {
            let flood = String(repeating: "x", count: 200)
            let card = photo {
                switch label {
                case "frame": $0.frame = flood
                case "background": $0.background = flood
                case "composition": $0.composition = flood
                default: $0.trainerStyle = flood
                }
            }
            XCTAssertFalse(MemoryHomeVisitCenter.valid(card), "\(label) 의 200자 문자열이 통과했다")
        }
    }

    func testSpeciesLabelRendersTheNumberNotItsSource() {
        // 백슬래시가 빠진 보간이 리터럴로 나갔던 결함(fb7e67e)의 회귀 테스트.
        let shiny = MemoryHomeProfileCard(displayName: "MemoryHome", speciesID: 25, isShiny: true,
                                          sharedMemoryBody: nil, profileMessage: nil)
        XCTAssertEqual(shiny.speciesLabel, "#25 ✨")
        let plain = MemoryHomeProfileCard(displayName: "MemoryHome", speciesID: 1, isShiny: false,
                                          sharedMemoryBody: nil, profileMessage: nil)
        XCTAssertEqual(plain.speciesLabel, "#1")
        XCTAssertFalse(plain.speciesLabel.contains("speciesID"), "표현식 소스가 그대로 렌더됐다")
    }

    func testV2CardRetainsPlacedShowroomAndFeaturedPhoto() throws {
        let decor = MemoryHomePlacedDecor(item: .retroArcade, position: .init(x: 0.75, y: 0.5))
        let photo = MemoryHomePhoto(speciesID: 25, isShiny: true, caption: "Arcade night", frame: "star",
                                    background: "studio", composition: "left", trainerStyle: "explorer")
        let card = MemoryHomeProfileCard(displayName: "MemoryHome", speciesID: 25, isShiny: false,
                                         sharedMemoryBody: nil, profileMessage: nil, roomStyle: .retro,
                                         placedDecor: [decor], featuredPhoto: photo)
        let decoded = try JSONDecoder().decode(MemoryHomeProfileCard.self,
                                               from: JSONEncoder().encode(card))
        XCTAssertEqual(decoded.roomStyle, .retro)
        XCTAssertEqual(decoded.placedDecor, [decor])
        XCTAssertEqual(decoded.featuredPhoto, photo)
    }

    func testVisitBrowsingDoesNotOwnPublicHostingLifetime() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("visit-lifetime-\(UUID().uuidString)")
        let stateURL = directory.appendingPathComponent("state.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = CompanionStore(fileURL: stateURL)
        let visits = MemoryHomeVisitCenter(companion: store, peerID: UUID())
        visits.startHostingIfEligible()
        XCTAssertTrue(visits.isHosting)

        visits.start()
        visits.stop()
        XCTAssertFalse(visits.isActive)
        XCTAssertTrue(visits.isHosting, "leaving Visit must not unpublish the home")

        store.memoryAlbum.setMemoryHomeVisibility(.blocked)
        visits.refreshAccess()
        XCTAssertFalse(visits.isHosting)
        visits.start()
        XCTAssertTrue(visits.isActive, "private users may still browse other public homes")
        visits.shutdown()
    }

    /// 연결이 끝나는 길은 성공 하나가 아니다 — 거절, 프레임 오류, 상대의 조기 종료도 모두 끝이고
    /// 셋 다 `cancel()` 로 끝난다. 회수를 성공 분기에만 걸어 두면 나머지가 전부 샌다(공개 호스트는
    /// 앱이 사는 내내 듣고 있으므로 거절 한 번마다 항목이 하나씩 쌓였다).
    ///
    /// 죽은 포트로는 검증할 수 없다 — `NWConnection` 은 거부당하면 `.failed` 가 아니라 `.waiting`
    /// 으로 **재시도하며 머문다**(살아 있는 연결이므로 계속 추적하는 게 맞다). 그래서 받아주자마자
    /// 끊는 루프백 리스너를 세워, 프레임 읽기가 실패해 `cancel()` 로 끝나는 실제 경로를 밟는다.
    func testConnectionsEndingInCancelAreReleasedFromTracking() async throws {
        let listener = try NWListener(using: .tcp)
        defer { listener.cancel() }
        listener.newConnectionHandler = { incoming in
            incoming.start(queue: .main)
            incoming.cancel()   // 받자마자 끊는다 → 방문자 쪽 프레임 읽기가 실패한다.
        }
        listener.start(queue: .main)
        // `port` 는 준비되기 전엔 **0(`.any`)** 이다 — nil 검사만 하면 0번 포트로 붙으러 가서
        // `EADDRNOTAVAIL` 로 끝나고, 정작 검증하려던 경로는 한 번도 안 밟힌다.
        for _ in 0..<50 where (listener.port?.rawValue ?? 0) == 0 {
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        let port = try XCTUnwrap(listener.port, "루프백 리스너가 포트를 받지 못했다")
        XCTAssertNotEqual(port.rawValue, 0, "리스너가 아직 준비되지 않았다")

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("visit-release-\(UUID().uuidString)")
        let stateURL = directory.appendingPathComponent("state.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = CompanionStore(fileURL: stateURL)
        let visits = MemoryHomeVisitCenter(companion: store, peerID: UUID())
        visits.start()
        defer { visits.shutdown() }

        visits.visit(.init(id: "loopback", displayName: "loopback",
                           endpoint: .hostPort(host: "127.0.0.1", port: port)))
        XCTAssertEqual(visits.trackedConnectionCount, 1, "방문 연결이 추적되지 않았다")

        // `stop()`/`shutdown()` 은 부르지 않는다 — 일괄 정리가 아니라 **연결 스스로의 종료**가
        // 회수하는지를 보는 테스트다. 최대 5초 폴링.
        for _ in 0..<50 where visits.trackedConnectionCount != 0 {
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTAssertEqual(visits.trackedConnectionCount, 0,
                       "cancel 로 끝난 연결이 회수되지 않았다 — 거절·프레임 오류도 같은 경로로 샌다")
    }

}

/// Bonjour 광고 이름의 고유성. `BattleNet`·`PokemonTrade`·`MultiplayerRoomCenter` 는 셋 다
/// 이름 뒤에 고유 접미를 붙이고 그 접미로 자기를 가르는데, Memory Home 만 닉네임 원문을 광고하고
/// 원문으로 자기를 걸렀다 — 같은 닉네임 두 대가 서로를 자기로 오인해 VISIT 목록이 빈 채로 남았다.
/// `PeerAdvertisementTests.testTheSameTrainerNameOnAnotherMachineIsStillAPeer` 의 형제다.
@MainActor
final class MemoryHomeServiceNameTests: XCTestCase {
    private let anyEndpoint: NWEndpoint = .hostPort(host: "127.0.0.1", port: 55_555)

    private func home(_ name: String, mine: String = "MemoryHome#000000") -> MemoryHomePeer? {
        MemoryHomeVisitCenter.peer(fromService: name, excluding: mine, endpoint: anyEndpoint)
    }

    /// 같은 설치는 언제 물어도 같은 이름을 준다 — 매번 새 UUID 를 굽던 `BattleNet` 과 달리
    /// Memory Home 은 `AppSettings.memoryHomeLANPeerID` 라는 영구 ID 를 이미 갖고 있다.
    func testServiceNameIsStableForTheSameInstall() {
        let id = UUID(uuidString: "44D58000-0000-0000-0000-000000000000")!
        XCTAssertEqual(MemoryHomeVisitCenter.serviceName(nickname: "MemoryHome", peerID: id),
                       MemoryHomeVisitCenter.serviceName(nickname: "MemoryHome", peerID: id))
    }

    /// 이 결함의 핵심이다. 닉네임이 같아도 설치가 다르면 광고 이름이 달라야 한다.
    func testTheSameNicknameOnTwoInstallsAdvertisesDifferentNames() {
        // 랜덤 UUID 로 쓰면 1600만분의 1로 접미가 겹쳐 이 테스트가 스스로 흔들린다 — 고정값을 쓴다.
        let a = MemoryHomeVisitCenter.serviceName(nickname: "MemoryHome",
                                                  peerID: UUID(uuidString: "44D58000-0000-0000-0000-000000000000")!)
        let b = MemoryHomeVisitCenter.serviceName(nickname: "MemoryHome",
                                                  peerID: UUID(uuidString: "FFFFFF00-0000-0000-0000-000000000000")!)
        XCTAssertNotEqual(a, b, "같은 닉네임 두 설치가 같은 이름을 광고하면 mDNS 가 한쪽을 개명한다")
    }

    /// 광고 이름은 Bonjour 이름이라 공백·제어문자가 없어야 한다 — `clean` 이 거르는 것과 같은 규칙.
    func testServiceNameIsBonjourSafe() {
        let name = MemoryHomeVisitCenter.serviceName(nickname: "Memory Home\n", peerID: UUID())
        XCTAssertNotNil(MemoryHomeVisitCenter.clean(name, limit: 64), "광고 이름에 공백·제어문자가 남았다")
    }

    func testMyOwnHomeIsFilteredOut() {
        XCTAssertNil(home("MemoryHome#000000"))
    }

    /// 닉네임이 같은 다른 기기는 남이다. 원문으로 걸렀다면 여기서 `nil` 이 나온다.
    func testTheSameNicknameOnAnotherMachineIsStillAHome() {
        let other = home("MemoryHome#FFFFFF")
        XCTAssertEqual(other?.displayName, "MemoryHome")
        XCTAssertEqual(other?.id, "MemoryHome#FFFFFF", "id 는 광고 원문이어야 방문 도장이 기기별로 남는다")
    }

    /// mDNS 가 충돌로 개명한 이름(` (2)`)에도 공백이 든다. `clean` 으로 라벨을 만들면 전부
    /// "Memory Home" 으로 뭉개져 어느 집인지 구분할 수 없었다.
    func testRenamedLegacyHomeKeepsAReadableLabel() {
        XCTAssertEqual(home("MemoryHome (2)")?.displayName, "MemoryHome (2)")
    }

    /// 접미가 없는 구버전(2.20.x) 피어도 목록에 남아야 한다.
    func testLegacyHomeWithoutSuffixIsStillAHome() {
        XCTAssertEqual(home("OldHome")?.displayName, "OldHome")
    }

    /// 원격 이름은 남이 지은 문자열이다. 줄바꿈·제어문자는 라벨에 실리면 안 되고, 남는 게 없으면
    /// 목록에서 뺀다 — 빈 버튼은 눌러도 어디로 가는지 알 수 없다.
    func testHostileRemoteNameIsRejected() {
        XCTAssertNil(home("줄바꿈\n주입#ABCDEF"))
        XCTAssertNil(home("#ABCDEF"))
        XCTAssertNil(home(String(repeating: "가", count: 41) + "#ABCDEF"))
    }
}
