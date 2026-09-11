import CoreBluetooth
import Foundation

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

    /// 설정이 켜져 있을 때만 부른다 — `CBPeripheralManager` 를 만드는 순간 macOS 가 블루투스를
    /// 묻기 때문에, 토글을 끈 사용자는 그 창을 보지 않아야 한다. 기본값은 켜짐이라
    /// (`battleInvitesEnabled` 와 같다) 대부분은 첫 실행에서 한 번 보게 된다.
    ///
    /// **거부는 되돌리기 어렵다.** macOS 는 한 번 거부하면 다시 묻지 않고, 사용자가 시스템 설정에서
    /// 직접 켜야 한다. 그래서 이 창이 뜨는 시점에 화면이 이유를 설명하고 있어야 한다 — 맥락 없이
    /// 물으면 거부가 쌓이고, 나중에 근접 발견(#342 1번)을 붙여도 그 사용자에게는 이미 막혀 있다.
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
