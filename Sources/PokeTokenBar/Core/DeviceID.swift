import Foundation
import IOKit

/// 재설치·상태 초기화에도 바뀌지 않는 기기 고유값. **세이브 무결성 서명이 유일한 용도다.**
/// IP는 DHCP로 바뀌므로 쓰지 않고 하드웨어 UUID(IOPlatformUUID)를 쓴다 — 훨씬 안정적이고 기기당 유일.
///
/// 예전엔 첫 스타터 후보 3종을 이 값으로 뽑아 "앱을 지웠다 깔아 리세마라" 를 막았다. 그 경로는
/// `2179921` 이 화면을 타입 선택으로 갈아끼우면서 죽었고 `starterSeed()` 는 #225 가 지웠다.
/// **리세마라 방지는 지금 없다** — `chooseStarterType` 은 `SystemRandomNumberGenerator` 로
/// 종과 이로치를 굴리므로, 세이브를 지우고 다시 고르면 얼마든지 다시 뽑을 수 있다.
/// 되살릴지는 게임 설계 판단이고, 되살린다면 시드는 여기가 아니라 그 함수 쪽에 둔다.
enum DeviceID {
    /// 하드웨어 UUID. 조회 실패(권한·샌드박스 등)면 호스트명 폴백 → 그마저 없으면 고정 상수.
    /// **폴백 값을 세이브 무결성 서명에 넣으면 안 된다** — 그 용도는 `hardwareIdentifier()` 를 쓴다.
    static func stableIdentifier() -> String {
        if let uuid = hardwareIdentifier() { return uuid }
        let host = Host.current().localizedName ?? ""
        return host.isEmpty ? "poketokenbar-default-device" : host
    }

    /// 폴백 **없는** 하드웨어 UUID — 조회에 실패하면 그대로 nil 을 알린다.
    ///
    /// 무결성 서명이 이 값을 쓴다. `stableIdentifier()` 처럼 폴백으로 메우면 서명이 실행마다 달라져
    /// 정상 세이브가 통째로 조작 판정을 받는다(2026-09-02: IOKit 조회가 한 번 실패해 호스트명이
    /// 시드로 들어갔고, 진행도 전체가 초기화됐다). 시드를 못 읽은 실행은 **서명도 검사도 하지 않는
    /// 쪽**이 옳다 — 오탐 비용(진행도 전멸)이 미탐 비용(손편집 세이브 하나)과 비교가 안 된다.
    ///
    /// 프로세스당 한 번만 조회한다. `save()` 가 자주 불리는데 매번 조회하면 그중 한 번의 실패가
    /// 같은 사고를 만든다.
    static func hardwareIdentifier() -> String? { cachedHardwareUUID }

    private static let cachedHardwareUUID: String? = {
        let uuid = hardwareUUID()
        if uuid == nil {
            // 이 한 줄이 없어서 원인 규명에 로그가 아니라 해시 재현이 필요했다.
            AppLog.write("device hardware UUID unavailable — save integrity check and signing are skipped this run")
        }
        return uuid
    }()

    private static func hardwareUUID() -> String? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard let cf = IORegistryEntryCreateCFProperty(service, kIOPlatformUUIDKey as CFString,
                                                       kCFAllocatorDefault, 0) else { return nil }
        return cf.takeRetainedValue() as? String
    }
}
