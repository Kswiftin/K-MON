import Foundation

/// BLE 광고 이름. 정본은 여기 하나다 — 길이 계산이 광고를 띄우는 곳과 갈라지면
/// 한쪽만 고쳐도 아무 테스트가 안 깨진다.
enum BLEPresenceName {
    static let prefix = "KMON"

    /// legacy 광고 payload 31바이트 중 이름 몫. flags 3 + 128비트 service UUID 18 + AD 헤더 2 를
    /// 빼고 남는 값이다. 넘기면 macOS 가 이름을 scan response 로 밀어내 스캐너에 도착하는 주기가
    /// 달라진다 — 그 주기가 #342 0단계의 측정 대상이라 길이는 계약이다.
    static let maxNameBytes = 8

    static func make(token: UInt16) -> String {
        prefix + String(format: "%04X", token)
    }

    /// 실행마다 새로 뽑는다. **트레이너 이름·식별자를 쓰지 않는다** — LAN 은 같은 서브넷 안이지만
    /// BLE 광고는 벽 너머 아무 앱이나 읽으므로, 고정 식별자를 실으면 상시 추적표를 뿌리는 셈이다.
    /// 0단계가 필요한 건 "어느 노드인가" 뿐이라 16비트면 충분하다.
    static func randomToken() -> UInt16 { UInt16.random(in: .min ... .max) }
}
