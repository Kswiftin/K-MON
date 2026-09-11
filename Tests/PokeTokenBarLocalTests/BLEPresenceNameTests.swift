import Foundation
import Testing
@testable import PokeTokenBar

/// BLE 광고 이름의 **길이와 내용**을 고정한다 (#342 0단계).
///
/// 길이가 계약인 이유: legacy BLE 광고 payload 는 31바이트뿐이고, 우리 광고는 flags 3 +
/// 128비트 service UUID 18 을 이미 쓴다. 남는 10바이트에서 AD 헤더 2를 빼면 이름은 **8바이트**다.
/// 넘치면 macOS 가 이름을 scan response 로 밀어내 스캐너 쪽 도착 주기가 달라진다 — 0단계가
/// 재려는 값이 바로 그 주기라, 이름이 한 글자 길어지면 측정 자체가 다른 걸 재게 된다.
///
/// 내용이 계약인 이유: 트레이너 이름·식별자를 실으면 **벽 너머 아무 앱에게나 상시 방송**된다.
/// LAN(`LANServiceName`)은 같은 서브넷 안이지만 BLE 에는 그 울타리가 없다.
@Suite("BLEPresenceNameTests")
struct BLEPresenceNameTests {

    @Test("토큰을 16진 4자리로 채워 8바이트 이름을 만든다")
    func formatsFixedWidth() {
        #expect(BLEPresenceName.make(token: 0x1A2B) == "KMON1A2B")
        #expect(BLEPresenceName.make(token: 0x000A) == "KMON000A")
        #expect(BLEPresenceName.make(token: 0xFFFF) == "KMONFFFF")
    }

    @Test("어떤 토큰이든 광고 payload 상한 안에 든다")
    func staysWithinAdvertisementBudget() {
        for token in [UInt16.min, 0x0100, 0x7FFF, UInt16.max] {
            #expect(BLEPresenceName.make(token: token).utf8.count == BLEPresenceName.maxNameBytes)
        }
    }

    @Test("이름에 트레이너 식별자가 섞이지 않는다")
    func carriesNoTrainerIdentity() {
        let name = BLEPresenceName.make(token: BLEPresenceName.randomToken())
        #expect(name.hasPrefix(BLEPresenceName.prefix))
        // 접두사 뒤는 16진수뿐 — 이름을 만드는 곳이 늘어나도 여기서 걸린다.
        let token = name.dropFirst(BLEPresenceName.prefix.count)
        #expect(token.allSatisfy { $0.isHexDigit && !$0.isLowercase })
    }

    @Test("토큰은 실행마다 달라진다")
    func randomTokenVaries() {
        let draws = Set((0..<200).map { _ in BLEPresenceName.randomToken() })
        #expect(draws.count > 100)
    }
}
