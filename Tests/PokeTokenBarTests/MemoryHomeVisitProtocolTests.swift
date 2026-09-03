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
        let stateURL = storeStateURL("visit-lifetime")
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

        let stateURL = storeStateURL("visit-release")
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
    /// 입력을 한글로 두는 이유: `"Memory Home\n"` 은 `clean` 이 통째로 거부해서 10바이트 ASCII
    /// 기본값(`MemoryHome`)만 재게 된다 — 실제 광고 이름은 한 번도 안 밟는 테스트였다.
    func testServiceNameIsBonjourSafe() {
        let name = MemoryHomeVisitCenter.serviceName(nickname: "메모리 홈\n", peerID: UUID())
        XCTAssertNotNil(MemoryHomeVisitCenter.clean(name, limit: 64), "광고 이름에 공백·제어문자가 남았다")
    }

    /// 결함: 닉네임을 40 **글자**로 자르는데 Bonjour 인스턴스 이름 상한은 63 **UTF-8 바이트**다.
    /// 한글은 글자당 3바이트라 20자만 넘어도 상한을 넘고, mDNSResponder 가 꼬리를 잘라 광고한다
    /// → 고유 접미(`#ABCDEF`)가 통째로 먹히고, 같은 닉네임 두 기기가 같은 이름을 광고한다.
    /// 이 PR 이 막은 결함이 한글 사용자에게만 그대로 재발하는 경로다.
    func testLongNonASCIINicknameStillFitsBonjourAndKeepsItsSuffix() {
        let id = UUID(uuidString: "44D58000-0000-0000-0000-000000000000")!
        // `clean(limit: 40)` 을 통과하는 최대 길이 — 공백 없는 한글 40자 = 120바이트.
        let nickname = String(repeating: "가", count: 40)
        let name = MemoryHomeVisitCenter.serviceName(nickname: nickname, peerID: id)

        XCTAssertLessThanOrEqual(name.utf8.count, LANServiceName.maxBytes,
                                 "63바이트를 넘으면 mDNS 가 꼬리를 잘라 고유 접미가 사라진다")
        XCTAssertTrue(name.hasSuffix("#44D580"), "잘림이 고유 접미를 먹었다 — 자기 필터가 무너진다")
        XCTAssertTrue(name.hasPrefix("가"), "닉네임이 통째로 사라졌다")
    }

    /// 같은 닉네임 두 설치는 **잘린 뒤에도** 서로 달라야 한다. 위 테스트의 짝 — 길이만 맞고
    /// 접미가 사라지면 이 단언이 깨진다.
    func testTwoInstallsWithTheSameLongNonASCIINicknameStillDiffer() {
        let nickname = String(repeating: "가", count: 40)
        let a = MemoryHomeVisitCenter.serviceName(nickname: nickname,
                                                  peerID: UUID(uuidString: "44D58000-0000-0000-0000-000000000000")!)
        let b = MemoryHomeVisitCenter.serviceName(nickname: nickname,
                                                  peerID: UUID(uuidString: "FFFFFF00-0000-0000-0000-000000000000")!)
        XCTAssertNotEqual(a, b)
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

/// Bonjour 인스턴스 이름의 **바이트 예산**. 네 LAN 센터가 각자 `"\(이름)#\(접미)"` 를 굽고
/// 있었고 그중 셋은 예산을 아예 안 봤다 — `PlayerGymRoomName` 만 63바이트 루프를 갖고 있었다.
/// 여기가 그 루프를 옮겨 온 공용 자리다.
final class LANServiceNameTests: XCTestCase {
    /// 접미는 절대 잘리면 안 된다 — 고유성이 거기에만 있다. 잘리는 건 언제나 앞의 이름이다.
    func testSuffixSurvivesEvenWhenTheBaseMustBeCut() {
        let name = LANServiceName.make(base: String(repeating: "가", count: 100), suffix: "#ABCDEF")
        XCTAssertLessThanOrEqual(name.utf8.count, LANServiceName.maxBytes)
        XCTAssertTrue(name.hasSuffix("#ABCDEF"))
    }

    /// 예산 안이면 한 글자도 건드리지 않는다.
    func testShortNameIsUntouched() {
        XCTAssertEqual(LANServiceName.make(base: "MemoryHome", suffix: "#ABCDEF"), "MemoryHome#ABCDEF")
    }

    /// 바이트로 자르되 **글자 경계**를 지킨다. 스칼라 중간에서 자르면 깨진 UTF-8 이 나가고
    /// mDNSResponder 가 광고를 통째로 거부한다.
    func testCutsOnCharacterBoundariesNotBytes() {
        for count in 1...40 {
            let name = LANServiceName.make(base: String(repeating: "가", count: count), suffix: "#ABCDEF")
            XCTAssertLessThanOrEqual(name.utf8.count, LANServiceName.maxBytes, "\(count)자에서 예산을 넘었다")
            XCTAssertEqual(String(data: Data(name.utf8), encoding: .utf8), name, "글자 중간에서 잘렸다")
        }
    }

    /// 접미만으로 예산을 다 쓰는 병적인 입력에서도 크래시하지 않는다(`budget < 0`).
    func testOversizedSuffixDoesNotTrap() {
        let suffix = "#" + String(repeating: "x", count: 100)
        XCTAssertEqual(LANServiceName.make(base: "이름", suffix: suffix), suffix)
    }
}

/// 광고 목록 → 집 목록 사상. `updateHomes` 클로저 안에 있으면 `NWBrowser.Result` 를 만들 수 없어
/// 테스트가 닿지 못한다 — 순수 함수로 꺼내서 정렬·중복 라벨·자기 필터를 여기서 검증한다.
@MainActor
final class MemoryHomeListingTests: XCTestCase {
    private func endpoint(_ port: UInt16) -> NWEndpoint { .hostPort(host: "127.0.0.1", port: .init(rawValue: port)!) }

    private func homes(_ names: [String], mine: String = "나#000000") -> [MemoryHomePeer] {
        MemoryHomeVisitCenter.homes(fromServices: names.enumerated().map { (name: $1, endpoint: endpoint(UInt16(5_000 + $0))) },
                                    excluding: mine)
    }

    /// `displayName` 만으로 정렬하면 동명이 있을 때 순서가 `Set` 순회 순서를 따라 흔들린다 —
    /// 사용자가 겨눈 줄을 눌러도 다른 기기로 방문한다. 키는 유일해야 한다.
    func testEqualDisplayNamesGetAStableOrder() {
        let forward = homes(["MemoryHome#AAAAAA", "MemoryHome#BBBBBB"]).map(\.id)
        let reversed = homes(["MemoryHome#BBBBBB", "MemoryHome#AAAAAA"]).map(\.id)
        XCTAssertEqual(forward, reversed, "입력 순서가 결과 순서를 바꾸면 목록이 갱신마다 자리를 바꾼다")
        XCTAssertEqual(forward, ["MemoryHome#AAAAAA", "MemoryHome#BBBBBB"])
    }

    /// 이 PR 이 푸는 시나리오 자체(같은 기본 닉네임 두 대)가 라벨을 못 읽게 만든다 —
    /// `displayName(fromService:)` 가 접미를 떼므로 버튼 두 개가 똑같이 "MemoryHome" 이 된다.
    func testDuplicateLabelsAreDisambiguatedBySuffix() {
        let labels = homes(["MemoryHome#AAAAAA", "MemoryHome#BBBBBB"]).map(\.displayName)
        XCTAssertEqual(Set(labels).count, 2, "구분할 수 없는 버튼 두 개가 나왔다")
        XCTAssertTrue(labels.allSatisfy { $0.contains("MemoryHome") })
    }

    /// 유일한 이름은 접미로 더럽히지 않는다.
    func testUniqueLabelKeepsThePlainNickname() {
        XCTAssertEqual(homes(["피카홈#AAAAAA", "라이홈#BBBBBB"]).map(\.displayName), ["라이홈", "피카홈"])
    }

    func testMyOwnAdvertisementIsExcluded() {
        XCTAssertEqual(homes(["나#000000", "남#111111"]).map(\.id), ["남#111111"])
    }
}

/// 브라우저 상태 → 화면에 뜨는 오류의 수명. 상태 핸들러 클로저 안에 있으면 테스트가 닿지 못해
/// "에러가 지워지지 않는다/너무 빨리 지워진다" 부류가 통째로 무테스트로 남는다.
@MainActor
final class MemoryHomeDiscoveryStateTests: XCTestCase {
    private func center() -> MemoryHomeVisitCenter {
        let store = CompanionStore(fileURL: storeStateURL("visit-state"))
        return MemoryHomeVisitCenter(companion: store, peerID: UUID())
    }

    /// 결함: `.waiting` 이 세운 오류를 지우는 길이 "집이 한 채라도 보일 때" 뿐이었다. 주변에 홈이
    /// 없는(=흔한) 사용자는 Wi-Fi 가 돌아와 `.ready` 가 돼도 "권한을 허용해 주세요" 를 영원히 본다.
    func testReadyClearsAStaleDiscoveryError() {
        let visits = center()
        visits.handleBrowserState(.waiting(.posix(.ENETDOWN)))
        XCTAssertNotNil(visits.lastError, "조용한 대기 상태가 화면에 아무 이유도 남기지 않았다")

        visits.handleBrowserState(.ready)
        XCTAssertNil(visits.lastError, "복구된 뒤에도 옛 오류가 남아 이미 켠 권한을 다시 켜라고 안내한다")
    }

    /// 결함: 프레임워크 원문(`Network is down`)이 ko/ja UI 에 그대로 실렸다 — `networkFailureMessage`
    /// 의 주석은 "내부 코드를 노출하지 않는다" 고 적혀 있는데 NoAuth 가 아닌 경로만 그러지 않았다.
    func testNonAuthFailureIsNotShownAsRawFrameworkText() {
        let visits = center()
        visits.handleBrowserState(.waiting(.posix(.ENETDOWN)))
        let message = try? XCTUnwrap(visits.lastError)
        XCTAssertEqual(message?.localizedCaseInsensitiveContains("network is down"), false,
                       "번역되지 않은 프레임워크 문구가 화면에 실렸다")
        XCTAssertEqual(message?.localizedCaseInsensitiveContains("posix"), false)
    }

    /// `.failed` 분기는 커버리지에서 `^0` 이었다 — 오류 노출·브라우저 회수·재시도 상한이 전부
    /// 무테스트였다는 뜻이다. 탐색 중이 아닐 때(`isActive == false`)는 재시도하지 않고 원인만 남긴다.
    func testFailureShowsACauseAndDoesNotRetryWhileIdle() {
        let visits = center()
        visits.handleBrowserState(.failed(.posix(.ENETDOWN)))
        XCTAssertNotNil(visits.lastError, "실패가 화면에 아무 이유도 남기지 않았다")
        XCTAssertFalse(visits.isActive)
    }

    /// 탐색 중이면 재시도를 건다. 여기서 검증하는 건 재시도 자체가 아니라 **오류가 남는다**는 것 —
    /// 무한 재시도는 오류를 계속 덮어쓰기만 하므로 상한(`maxBrowserRestarts`)이 있어야 마지막
    /// 원인이 화면에 남는다.
    func testFailureWhileBrowsingKeepsTheCauseOnScreen() {
        let visits = center()
        visits.start()
        defer { visits.shutdown() }
        visits.handleBrowserState(.failed(.posix(.ENETDOWN)))
        XCTAssertNotNil(visits.lastError)
        XCTAssertLessThanOrEqual(MemoryHomeVisitCenter.maxBrowserRestarts, 10,
                                 "재시도 상한이 사실상 무한이면 오류가 계속 덮어써진다")
    }

    /// 결함: 광고 목록이 갱신될 때마다 `lastError` 를 지웠다. mDNS 는 TTL 갱신·피어 변동마다
    /// 이 콜백을 부르므로, "이 홈은 방문을 받지 않아요" 같은 **방문 결과** 문구가 사용자가 읽는
    /// 도중 몇 초 만에 사라졌다 — 그 문구를 띄우려고 붙인 화면 줄이 무의미해진다.
    func testBrowseResultsDoNotEraseAVisitError() {
        let visits = center()
        visits.handleBrowserState(.waiting(.posix(.ENETDOWN)))
        let shown = visits.lastError
        XCTAssertNotNil(shown)

        visits.applyDiscovered([(name: "남#111111", endpoint: .hostPort(host: "127.0.0.1", port: 5_001))])

        XCTAssertEqual(visits.homes.count, 1, "목록 갱신 자체가 안 됐다 — 테스트가 경로를 안 밟았다")
        XCTAssertEqual(visits.lastError, shown, "광고 갱신이 화면의 오류 문구를 지웠다")
    }
}
