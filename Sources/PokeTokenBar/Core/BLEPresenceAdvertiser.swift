import CoreBluetooth
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

/// 근처 노드에게 BLE 광고만 띄운다 (#342 0단계 측정용).
///
/// **스캔은 앱에 넣지 않는다.** 주기·세기·낙폭은 전부 스캔하는 쪽에서 나오고, 스캔은 블루투스
/// 권한 프롬프트와 결과 화면을 함께 끌고 온다. 0단계는 구역 감지를 접을지 정하는 측정이라,
/// 접힐 수도 있는 기능에 그만큼의 앱 표면을 먼저 쓰지 않는다. 측정하는 쪽은
/// `scripts/ble-probe.sh scan` 이다.
///
/// 광고는 연결을 받지 않는다. 서비스도 올리지 않으므로 상대가 붙어도 읽을 것이 없다.
@MainActor
final class BLEPresenceAdvertiser: NSObject, CBPeripheralManagerDelegate {
    /// 프로브와 **같은 UUID**여야 `scripts/ble-probe.sh` 의 필터에 잡힌다.
    static let serviceUUID = CBUUID(string: "5A9E2C10-7F3B-4D8E-9C41-1B6A0F2E4D77")

    let localName: String
    private var manager: CBPeripheralManager?
    /// 설정이 켜져 있는가. 화면 잠자기로 잠깐 멈춘 상태(`isSuspended`)와 구분한다.
    private var isEnabled = false
    private var isSuspended = false

    init(localName: String = BLEPresenceName.make(token: BLEPresenceName.randomToken())) {
        self.localName = localName
        super.init()
    }

    /// 설정이 켜져 있을 때만 부른다. `CBPeripheralManager` 를 만드는 순간 macOS 가 블루투스를
    /// 물을 수 있어, 이 기능을 안 쓰는 사용자는 그 창을 영영 보지 않아야 한다
    /// (`battleInvitesEnabled` 가 로컬 네트워크 권한에 대해 하는 일과 같다).
    func start() {
        guard manager == nil else { return }
        isEnabled = true
        manager = CBPeripheralManager(delegate: self, queue: .main)
    }

    func stop() {
        isEnabled = false
        manager?.stopAdvertising()
        manager = nil
    }

    /// 화면이 잠들면 광고를 멈춘다. 자리를 뜬 사람의 맥이 계속 떠드는 것을 막는다.
    ///
    /// 측정할 때 주의: 이 구간은 표본이 아예 비므로 리포트의 `rate` 가 낮게 나온다. **사람이 앞에
    /// 있는 동안만** 재는 것이 0단계의 전제라 문제가 아니지만, 가려짐(낙폭)과 혼동하면 안 된다 —
    /// 낙폭은 값이 떨어지는 것이고 이쪽은 값이 없는 것이다.
    func setDisplayAwake(_ awake: Bool) {
        isSuspended = !awake
        syncAdvertising()
    }

    /// 델리게이트는 `nonisolated` 로 받는다 — `CBPeripheralManagerDelegate` 자체에 액터가 없어
    /// `@MainActor` 클래스가 그대로 채택하면 Swift 6 가 데이터 레이스로 막는다. 매니저를 메인 큐
    /// (`queue: .main`)로 만들었으므로 콜백은 실제로 메인에서 오고, `assumeIsolated` 가 그 사실을
    /// 컴파일러에 알린다. **큐를 바꾸면 이 가정이 깨진다.**
    nonisolated func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        MainActor.assumeIsolated { self.syncAdvertising() }
    }

    /// 상태·설정·잠자기가 바뀔 때마다 같은 판정을 다시 돌린다(멱등 — 중복 호출 안전).
    private func syncAdvertising() {
        guard let manager, manager.state == .poweredOn else { return }
        let shouldAdvertise = isEnabled && !isSuspended
        if shouldAdvertise {
            guard !manager.isAdvertising else { return }
            manager.startAdvertising([
                CBAdvertisementDataLocalNameKey: localName,
                CBAdvertisementDataServiceUUIDsKey: [Self.serviceUUID],
            ])
        } else if manager.isAdvertising {
            manager.stopAdvertising()
        }
    }
}
