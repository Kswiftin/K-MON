import Foundation
import IOKit

/// 재설치·상태 초기화에도 바뀌지 않는 기기 고유값. 첫 스타터 후보를 이 값으로 결정해
/// "앱을 지웠다 깔아 리세마라"를 막는다(같은 Mac이면 항상 같은 3종). IP는 DHCP로 바뀌므로 쓰지 않고
/// 하드웨어 UUID(IOPlatformUUID)를 쓴다 — 훨씬 안정적이고 기기당 유일.
enum DeviceID {
    /// 하드웨어 UUID. 조회 실패(권한·샌드박스 등)면 호스트명 폴백 → 그마저 없으면 고정 상수.
    static func stableIdentifier() -> String {
        if let uuid = hardwareUUID() { return uuid }
        let host = Host.current().localizedName ?? ""
        return host.isEmpty ? "poketokenbar-default-device" : host
    }

    /// SplitMix64 시드용 — 안정 식별자의 FNV-1a 64.
    static func starterSeed() -> UInt64 {
        var h: UInt64 = 0xcbf29ce484222325
        for b in stableIdentifier().utf8 {
            h ^= UInt64(b)
            h = h &* 0x100000001b3
        }
        return h
    }

    private static func hardwareUUID() -> String? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard let cf = IORegistryEntryCreateCFProperty(service, kIOPlatformUUIDKey as CFString,
                                                       kCFAllocatorDefault, 0) else { return nil }
        return cf.takeRetainedValue() as? String
    }
}
