import CoreBluetooth
import Foundation

// BLE 프로브 — 이슈 #342 의 0단계 실측 도구. 앱에는 닿지 않는다.
//
//   맥 A:  scripts/ble-probe.sh advertise --name PROBE-A
//   맥 B:  scripts/ble-probe.sh scan --seconds 60 --csv baseline.csv
//   판정:  scripts/ble-probe-report.sh baseline.csv
//
// 재려는 값은 둘뿐이다. ①우리 앱끼리의 **광고 주기**(macOS 에 주기를 지정하는 API 가 없어
// 재보기 전에는 모른다) ②사람이 두 노드 사이를 막을 때의 **신호 낙폭**. 이 두 값이 이슈의
// 중단 기준이라, 도구는 원시 표본만 CSV 로 남기고 판정은 리포트 스크립트가 한다.

/// 프로브 전용 service UUID. 광고에 이 UUID 를 실고 스캔도 이것만 필터한다.
///
/// 필터가 없으면 주변 기기 200여 대가 함께 잡혀 주기 측정이 잡음에 묻힌다. 이 값은 앱의
/// 서비스가 아니라 실측용이므로, 나중에 앱에 BLE 를 넣을 때 같은 UUID 를 쓰지 않는다.
let probeServiceUUID = CBUUID(string: "5A9E2C10-7F3B-4D8E-9C41-1B6A0F2E4D77")

func nowMillis() -> Int64 { Int64(Date().timeIntervalSince1970 * 1000) }

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

// MARK: 인자

struct Options {
    var mode = ""
    var name = "PROBE"
    var seconds = 60.0
    var csvPath: String?
}

func parseOptions() -> Options {
    var options = Options()
    var arguments = Array(CommandLine.arguments.dropFirst())
    guard let mode = arguments.first, mode == "advertise" || mode == "scan" else {
        fail("""
        사용법:
          ble-probe advertise [--name PROBE-A]
          ble-probe scan [--seconds 60] [--csv out.csv]
        """)
    }
    options.mode = mode
    arguments.removeFirst()
    while let flag = arguments.first {
        arguments.removeFirst()
        guard let value = arguments.first else { fail("\(flag) 에 값이 없다") }
        arguments.removeFirst()
        switch flag {
        case "--name": options.name = value
        case "--seconds":
            guard let parsed = Double(value) else { fail("--seconds 가 숫자가 아니다") }
            options.seconds = parsed
        case "--csv": options.csvPath = value
        default: fail("모르는 인자: \(flag)")
        }
    }
    return options
}

// MARK: 광고

/// 광고만 한다. 연결은 받지 않는다 — 0단계가 재는 것은 광고가 도착하는 빈도와 세기뿐이다.
final class Advertiser: NSObject, CBPeripheralManagerDelegate {
    private var manager: CBPeripheralManager!
    private let localName: String

    init(localName: String) {
        self.localName = localName
        super.init()
        manager = CBPeripheralManager(delegate: self, queue: nil)
    }

    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        print("peripheral state=\(peripheral.state.rawValue)")
        guard peripheral.state == .poweredOn else { return }
        // Apple 플랫폼의 광고에는 local name 과 service UUID 만 실린다(manufacturer data 불가).
        // 그래서 메타데이터는 이름 문자열에 담는 `LANServiceName` 규칙을 그대로 따를 수 있다.
        peripheral.startAdvertising([
            CBAdvertisementDataLocalNameKey: localName,
            CBAdvertisementDataServiceUUIDsKey: [probeServiceUUID],
        ])
    }

    func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        if let error {
            fail("advertise 실패: \(error.localizedDescription)")
        }
        print("advertise OK isAdvertising=\(peripheral.isAdvertising) name=\(localName)")
        print("중단은 Ctrl-C. 이 맥은 잠들면 광고가 끊기므로 caffeinate 로 묶어 둔다.")
    }
}

// MARK: 스캔

/// 광고를 받은 그대로 CSV 한 줄로 남긴다. 평균·표준편차·판정은 하지 않는다 —
/// 원시 표본을 남겨야 나중에 창을 다시 잘라 보거나 다른 기준으로 재판정할 수 있다.
final class Scanner: NSObject, CBCentralManagerDelegate {
    private var manager: CBCentralManager!
    private let output: FileHandle?
    private let deadline: Date
    /// CoreBluetooth 가 "세기를 못 읽었다" 를 알리는 값. 측정값이 아니라 센티넬이다.
    static let rssiUnavailable = 127

    private var samples = 0
    private var dropped = 0
    private var peers = Set<String>()
    private var marks = 0
    private let startedAt = Date()

    init(seconds: Double, csvPath: String?) {
        deadline = Date().addingTimeInterval(seconds)
        if let csvPath {
            let url = URL(fileURLWithPath: csvPath)
            FileManager.default.createFile(atPath: url.path, contents: nil)
            output = try? FileHandle(forWritingTo: url)
            output?.write(Data("unix_ms,peer,name,rssi,marker\n".utf8))
        } else {
            output = nil
        }
        super.init()
        manager = CBCentralManager(delegate: self, queue: nil)
        scheduleStatus()
        readMarkers()
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        print("central state=\(central.state.rawValue)")
        guard central.state == .poweredOn else { return }
        // 이 옵션이 0단계의 전부다. 빼면 기기당 콜백이 **한 번만** 와서 광고 주기를 잴 수 없다.
        central.scanForPeripherals(
            withServices: [probeServiceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
        print("scan 시작 — \(Int(deadline.timeIntervalSinceNow))초. 사람이 사이를 지나기 직전에 Enter.")
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        // 센티넬을 그대로 적으면 평균·표준편차가 통째로 망가진다 — 60초 표본에 2개가 섞여
        // sd 가 4 에서 29 로 튀었고, 그 값이 #342 의 중단 판정에 그대로 들어갔다.
        // **`ble-probe-report.sh` 도 같은 값을 거른다** — CSV 가 두 도구의 계약이라
        // 한쪽만 바꾸면 조용히 어긋난다.
        guard RSSI.intValue != Self.rssiUnavailable else { dropped += 1; return }
        let peer = String(peripheral.identifier.uuidString.prefix(8))
        let name = (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? ""
        samples += 1
        peers.insert(peer)
        write("\(nowMillis()),\(peer),\(name),\(RSSI.intValue),0")
    }

    /// Enter 를 누른 시각을 표본과 같은 파일에 남긴다. 초시계로 따로 적으면 두 시계가 어긋난다.
    private func readMarkers() {
        DispatchQueue.global().async { [weak self] in
            while readLine() != nil {
                let millis = nowMillis()
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.marks += 1
                    self.write("\(millis),MARK,,0,1")
                    print("  mark #\(self.marks)")
                }
            }
        }
    }

    private func scheduleStatus() {
        Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            let elapsed = Date().timeIntervalSince(startedAt)
            if Date() >= deadline {
                timer.invalidate()
                // 버린 표본을 숨기지 않는다 — 수가 크면 측정이 아니라 장비를 의심해야 한다.
                print(String(format: "끝 — %.1fs samples=%d peers=%d marks=%d dropped=%d",
                             elapsed, samples, peers.count, marks, dropped))
                manager.stopScan()
                try? output?.close()
                exit(0)
            }
            print(String(format: "  %.0fs samples=%d peers=%d", elapsed, samples, peers.count))
        }
    }

    private func write(_ line: String) {
        output?.write(Data((line + "\n").utf8))
    }
}

// MARK: 진입점

let options = parseOptions()

// 전역에 붙잡아야 한다. `case` 안의 지역 `let` 은 그 블록이 끝나면 ARC 가 바로 풀어버리고
// (`_ = x` 는 마지막 사용일 뿐 수명을 늘리지 않는다), 그러면 CoreBluetooth 매니저가 함께
// 죽어 콜백이 한 번도 안 온다. 상태 타이머까지 `[weak self]` 라 첫 발화에서 스스로
// invalidate 해, 에러 없이 표본 0인 채 런루프만 도는 모습이 된다.
var keepAlive: AnyObject?

switch options.mode {
case "advertise":
    keepAlive = Advertiser(localName: options.name)
case "scan":
    keepAlive = Scanner(seconds: options.seconds, csvPath: options.csvPath)
default:
    fail("모르는 모드")
}
RunLoop.main.run()
