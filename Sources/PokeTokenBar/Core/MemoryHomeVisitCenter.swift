import Foundation
import Network
import Observation

/// Deliberately tiny, separate LAN protocol for Memory Home.  A peer ID is an access-control
/// hint, not authentication; never treat it as proof of a person's identity.
struct MemoryHomeProfileCard: Codable, Sendable, Equatable {
    var displayName: String
    var speciesID: Int
    var isShiny: Bool
    var sharedMemoryBody: String?
    /// 대문 문구. `Optional` 이라 합성 `Codable` 이 `decodeIfPresent` 를 쓴다 → 이 키가 없는
    /// R4 이전 피어의 페이로드도 그대로 디코드되므로 `protocolVersion` 은 1 을 유지한다.
    /// 여기를 "기본값 있는 비옵셔널"로 바꾸면 그 경로는 **throw 한다** — 옵셔널로 남겨야 한다.
    var profileMessage: String?
    /// A deliberately small, read-only home showcase. It excludes notes, aliases, guestbook and
    /// exact placements; a LAN visit should reveal a home's personality, not its private data.
    var roomTheme: PokemonMemoryRoomTheme? = nil
    var showcaseFurniture: [ItemKind] = []
    /// v2 is an explicitly published, read-only showroom. No diary, aliases, guestbook or
    /// local counters are represented here.
    var roomStyle: MemoryHomeRoomStyle? = nil
    var placedDecor: [MemoryHomePlacedDecor] = []
    var featuredPhoto: MemoryHomePhoto? = nil

    private enum CodingKeys: String, CodingKey { case displayName, speciesID, isShiny, sharedMemoryBody, profileMessage, roomTheme, showcaseFurniture, roomStyle, placedDecor, featuredPhoto }
    init(displayName: String, speciesID: Int, isShiny: Bool, sharedMemoryBody: String?, profileMessage: String?,
         roomTheme: PokemonMemoryRoomTheme? = nil, showcaseFurniture: [ItemKind] = [], roomStyle: MemoryHomeRoomStyle? = nil,
         placedDecor: [MemoryHomePlacedDecor] = [], featuredPhoto: MemoryHomePhoto? = nil) {
        self.displayName = displayName; self.speciesID = speciesID; self.isShiny = isShiny
        self.sharedMemoryBody = sharedMemoryBody; self.profileMessage = profileMessage
        self.roomTheme = roomTheme; self.showcaseFurniture = showcaseFurniture
        self.roomStyle = roomStyle; self.placedDecor = placedDecor; self.featuredPhoto = featuredPhoto
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        displayName = try c.decode(String.self, forKey: .displayName)
        speciesID = try c.decode(Int.self, forKey: .speciesID)
        isShiny = try c.decode(Bool.self, forKey: .isShiny)
        sharedMemoryBody = try c.decodeIfPresent(String.self, forKey: .sharedMemoryBody)
        profileMessage = try c.decodeIfPresent(String.self, forKey: .profileMessage)
        roomTheme = try c.decodeIfPresent(PokemonMemoryRoomTheme.self, forKey: .roomTheme)
        showcaseFurniture = try c.decodeIfPresent([ItemKind].self, forKey: .showcaseFurniture) ?? []
        roomStyle = try c.decodeIfPresent(MemoryHomeRoomStyle.self, forKey: .roomStyle)
        placedDecor = try c.decodeIfPresent([MemoryHomePlacedDecor].self, forKey: .placedDecor) ?? []
        featuredPhoto = try c.decodeIfPresent(MemoryHomePhoto.self, forKey: .featuredPhoto)
    }

    /// Shown in the visit sheet. This was inline in the view with the interpolation backslash
    /// missing — Swift accepts that as a plain literal, so it shipped printing the expression
    /// source verbatim. It is a tested pure property now; `test-gate.sh` greps for the typo class.
    var speciesLabel: String { "#\(speciesID)" + (isShiny ? " ✨" : "") }
}

enum MemoryHomeVisitRequest: Codable, Sendable, Equatable {
    case profileRequest(protocolVersion: Int, peerID: UUID, displayName: String)
}

enum MemoryHomeVisitResponse: Codable, Sendable, Equatable {
    case profileCard(protocolVersion: Int, card: MemoryHomeProfileCard)
    case rejected(protocolVersion: Int)
}

struct MemoryHomePeer: Identifiable, Equatable {
    let id: String
    let displayName: String
    let endpoint: NWEndpoint
}

@MainActor @Observable
final class MemoryHomeVisitCenter {
    nonisolated static let serviceType = "_kmonhome._tcp"
    nonisolated static let protocolVersion = 2
    nonisolated static let maxFrameBytes: UInt32 = 16 * 1024
    /// 진열장·배치 상한. 가구 종류가 12개(`ItemKind.memoryHomeFurniture`)라 그 이상은 로컬에서
    /// 만들 수 없는 값이다 — 원격만 보낼 수 있으니 곧 남이 보낸 쓰레기다.
    nonisolated static let maxShowcaseItems = 12
    /// 사진 스타일 태그("star"·"studio"·"left"·"explorer" 등)의 길이 상한. 렌더는 알려진 값만
    /// 비교하고 나머지는 기본값으로 떨어지므로 주입 위험은 없고, 막는 건 길이뿐이다.
    nonisolated static let styleTagLimit = 24
    /// `.failed` 재시작 상한. 여기서 멈추면 마지막 오류 문구가 화면에 남아 원인이 보인다 —
    /// 무한 재시도는 오류를 계속 덮어쓰기만 하고 아무것도 복구하지 못한다.
    nonisolated static let maxBrowserRestarts = 5

    private(set) var homes: [MemoryHomePeer] = []
    private(set) var selectedProfile: MemoryHomeProfileCard?
    private(set) var lastError: String?
    /// `isActive` is the visit-browser state. Hosting has a separate app-lifetime.
    private(set) var isActive = false
    private(set) var isHosting = false
    private let companion: CompanionStore
    private let peerID: UUID
    private var browser: NWBrowser?
    private var listener: NWListener?
    /// `NWListener.Service` 에 **실제로 건넨** 이름. 자기 필터의 근거는 "지금 닉네임으로 이름을 다시
    /// 구우면 이럴 것" 이 아니라 "내가 지금 광고 중인 문자열" 이어야 한다. 계산값으로 거르면 닉네임을
    /// 쓰는 새 경로(설정 동기화·세이브 이전·채팅 툴)가 `refreshAccess()` 를 한 번 잊는 순간 광고는
    /// 옛 이름, 필터는 새 이름으로 갈라져 **내 집이 내 목록에 뜨고 방문하면 나에게 전화한다.**
    /// 여기에 담아 두면 재광고와 필터가 같은 대입 한 번으로 함께 움직여 갈라질 수가 없다.
    private var advertisedServiceName: String?
    /// `.failed` 재시작 횟수. 상한이 없으면 영구 불가 상태(권한 차단·서비스 타입 차단)에서 5초마다
    /// 브라우저를 새로 만들며 하루 종일 돈다.
    private var browserRestartAttempts = 0
    /// 파도타기 커서 = **마지막으로 방문한 홈**. 목록을 눌러 간 방문도 커서를 옮긴다 —
    /// 파도타기가 옮길 때만 옮기면, 손으로 마지막 집에 다녀온 뒤의 파도타기가 뒤로 돌아간다.
    /// **저장하지 않는다** — 창을 닫으면 처음부터 돈다. 통산 기록은 방문 도장이 맡으므로
    /// 여기에 새 저장 필드를 만들 이유가 없다(이 홈의 "새 필드 0개" 원칙).
    private var surfCursor: String?
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    private var visitHomeIDs: [ObjectIdentifier: String] = [:]
    /// 회수를 관찰할 수 있는 유일한 창이다. `connections` 를 통째로 `private` 로 두면 "연결이
    /// 새는지" 를 검증할 방법이 없어 이 부류가 조용히 돌아온다 — `valid(_:)` 를 `private` 로
    /// 두지 않은 것과 같은 이유다. 파생값이라 상태가 갈라지지 않는다.
    var trackedConnectionCount: Int { connections.count }

    init(companion: CompanionStore, peerID: UUID) { self.companion = companion; self.peerID = peerID }

    /// Starts discovery only: private visitors may still browse public homes.
    func start() {
        guard !isActive else { return }; isActive = true; lastError = nil
        startBrowsing()
    }
    func stop() {
        isActive = false; homes = []; selectedProfile = nil
        browser?.cancel(); browser = nil; browserRestartAttempts = 0
        cancelVisitConnections()
    }
    func startHostingIfEligible() {
        guard companion.memoryAlbum.memoryHomeAccess.visibility == .open else { return }
        startHosting()
    }
    /// The feature being disabled or the app ending is the only normal host teardown path.
    func shutdown() {
        stop()
        stopHosting()
        cancelConnections()
    }
    func refreshAccess() {
        if companion.memoryAlbum.memoryHomeAccess.visibility == .blocked {
            stopHosting()
            cancelConnections()
            return
        }
        // Recreate only the advertised service after a nickname edit; browse results stay up.
        stopHosting()
        startHosting()
    }
    /// 광고를 내리는 **유일한** 자리. 세 호출부가 각자 `listener?.cancel(); listener = nil` 을 적고
    /// 있었기에 `advertisedServiceName` 같은 형제 상태를 더하면 반드시 한 곳을 빠뜨린다.
    private func stopHosting() {
        listener?.cancel(); listener = nil; isHosting = false; advertisedServiceName = nil
    }
    /// 기획서 §14 파도타기 — 다음 홈으로 건너뛴다. 목표를 고르는 판단은 전부 `MemoryHomeSurf`
    /// 가 하고 여기서는 방문만 한다(`homes(fromServices:)` 를 순수 함수로 뺀 것과 같은 이유).
    func surf() {
        guard isActive else { return }
        let visited = MemoryHomeSurf.visitedIDs(in: companion.memoryAlbum.memoryHomeAccess.visitedHomeStamps,
                                                on: CompanionStore.dayKey(Date()))
        guard let target = MemoryHomeSurf.target(in: homes, visited: visited, after: surfCursor) else {
            // 목록이 비었을 때 아무것도 하지 않으면 죽은 버튼이 된다 — 이 화면의 다른 실패와
            // 같은 자리(`lastError`)에 이유를 적는다.
            lastError = companion.l.t("파도타기 할 홈이 아직 안 보여요. 같은 LAN의 다른 Mac에서 홈을 공개해 주세요.",
                                      "No homes to surf yet. Open a home on another Mac on this LAN.",
                                      "波乗りできるホームがまだありません。同じLANの別のMacでホームを公開してください。")
            return
        }
        visit(target)
    }
    func visit(_ peer: MemoryHomePeer) {
        guard isActive else { return }; selectedProfile = nil; lastError = nil; surfCursor = peer.id
        let connection = NWConnection(to: peer.endpoint, using: Self.parameters())
        let key = ObjectIdentifier(connection); visitHomeIDs[key] = peer.id
        track(connection, key: key) { [weak self, weak connection] in
            guard let self, let connection else { return }
            self.send(MemoryHomeVisitRequest.profileRequest(protocolVersion: Self.protocolVersion, peerID: self.peerID,
                      displayName: self.localDisplayName), over: connection) { [weak self, weak connection] in
                guard let self, let connection else { return }
                self.receiveResponse(on: connection, key: key)
            }
        }
        connection.start(queue: .main)
    }
    /// 연결이 끝나는 길은 성공 하나가 아니다 — 거절, 프레임 오류, 상대 없음도 모두 끝이다.
    /// 호출부마다 회수를 적어 넣으면 반드시 한두 갈래를 빠뜨린다: 거절 분기(`receiveRequest`)와
    /// `receive` 의 실패 분기 넷이 정확히 그렇게 새고 있었고, 공개 호스트는 앱이 사는 내내 듣고
    /// 있으므로 거절 한 번마다 항목이 하나씩 쌓였다. 그래서 회수는 **여기 한 곳에만** 둔다.
    private func track(_ connection: NWConnection, key: ObjectIdentifier,
                       whenReady: (@MainActor () -> Void)? = nil) {
        connections[key] = connection
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                if let whenReady { Task { @MainActor in whenReady() } }
            case .cancelled, .failed:
                Task { @MainActor in
                    self?.connections.removeValue(forKey: key)
                    self?.visitHomeIDs.removeValue(forKey: key)
                }
            default: break
            }
        }
    }
    private func startBrowsing() {
        guard browser == nil else { return }
        let browser = NWBrowser(for: .bonjour(type: Self.serviceType, domain: nil), using: Self.parameters())
        // 자기 이름은 결과가 올 때 **그 시점의 값**을 읽는다. 브라우저를 만들 때 캡처하면 닉네임을
        // 바꾼 뒤(리스너만 다시 굽는 `refreshAccess`) 옛 이름으로 자기를 걸러, 내 새 광고가 내
        // 목록에 뜨고 옛 이름을 쓰는 남의 집이 사라진다.
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor in self?.updateHomes(results) }
        }
        browser.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in self?.handleBrowserState(state) }
        }
        browser.start(queue: .main); self.browser = browser
    }

    /// 브라우저 상태 → 화면에 뜨는 오류의 수명. 클로저 안에 두면 테스트가 닿지 못해 "지워지지
    /// 않는 오류" / "너무 빨리 지워지는 오류" 부류가 통째로 무테스트로 남는다 — 실제로 둘 다 있었다.
    /// `internal` 인 것은 그래서다(`trackedConnectionCount` 를 열어 둔 것과 같은 이유).
    func handleBrowserState(_ state: NWBrowser.State) {
        switch state {
        // 오류를 지우는 근거는 **브라우저가 정상으로 돌아왔다** 하나뿐이다. 결과 콜백에서 지우면
        // mDNS TTL 갱신 한 번이 "이 홈은 방문을 받지 않아요" 를 사용자가 읽는 도중 지운다.
        case .ready:
            lastError = nil; browserRestartAttempts = 0
        // 권한 거부·차단은 `.failed` 가 아니라 `.waiting` 으로 **조용히 머문다**. 여기를 비워
        // 두면 화면은 영영 "주변 홈을 찾는 중" 이고 사용자는 이유를 알 길이 없다.
        case .waiting(let error):
            lastError = networkFailureMessage(error)
        case .failed(let error):
            lastError = networkFailureMessage(error)
            // 참조만 버리면 실패한 브라우저가 큐·핸들러를 붙든 채 살아남아 슬립 복귀마다 쌓인다
            // (`BattleNet.startListener` 가 같은 규칙을 적어 둔 부류다). `guard browser == nil`
            // 로도 회수할 수 없다 — 참조를 이미 버렸기 때문이다.
            browser?.cancel(); browser = nil
            guard isActive, browserRestartAttempts < Self.maxBrowserRestarts else { return }
            browserRestartAttempts += 1
            // 지수 백오프. 영구 불가 상태에서 5초 고정으로 돌면 하루에 수천 번 재생성한다.
            let delay = min(5 << (browserRestartAttempts - 1), 60)
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(delay))
                guard let self, self.isActive else { return }
                self.startBrowsing()
            }
        default: break
        }
    }

    /// 광고 목록 하나를 집 목록으로 옮긴다. `NWBrowser.Result` 는 테스트에서 만들 수 없으므로
    /// **여기서 이름·엔드포인트만 뽑아** 순수 함수(`homes(fromServices:excluding:)`)에 넘긴다 —
    /// `private` 인 이 메서드를 "테스트가 닿는다" 고 적어 두면 닿지 않는 코드가 무테스트로 남는다.
    private func updateHomes(_ results: Set<NWBrowser.Result>) {
        applyDiscovered(results.compactMap { result in
            guard case let .service(name, _, _, _) = result.endpoint else { return nil }
            return (name: name, endpoint: result.endpoint)
        })
    }

    /// 광고 목록을 화면 목록으로 반영한다. **`lastError` 를 건드리지 않는다** — 방문 결과 문구를
    /// mDNS 갱신이 지우던 결함이 여기서 났다.
    func applyDiscovered(_ services: [(name: String, endpoint: NWEndpoint)]) {
        homes = Self.homes(fromServices: services, excluding: advertisedServiceName ?? myServiceName)
    }

    /// 정렬 키가 `displayName` 하나면 동명이 있을 때 순서가 `Set` 순회 순서를 따라 흔들린다 —
    /// 목록이 갱신마다 자리를 바꿔 사용자가 겨눈 줄을 눌러도 다른 기기로 방문한다. 키는 유일해야
    /// 하므로 광고 원문(`id`)까지 본다. 그리고 라벨이 겹치면(이 PR 이 푸는 시나리오 그 자체 —
    /// 같은 기본 닉네임 두 대) 접미를 되붙여 구분할 수 있게 한다.
    nonisolated static func homes(fromServices services: [(name: String, endpoint: NWEndpoint)],
                                  excluding myServiceName: String) -> [MemoryHomePeer] {
        let peers = services
            .compactMap { peer(fromService: $0.name, excluding: myServiceName, endpoint: $0.endpoint) }
            .sorted { ($0.displayName, $0.id) < ($1.displayName, $1.id) }
        let labelCounts = peers.reduce(into: [String: Int]()) { $0[$1.displayName, default: 0] += 1 }
        return peers.map { peer in
            guard labelCounts[peer.displayName, default: 0] > 1,
                  let hash = peer.id.lastIndex(of: "#") else { return peer }
            return MemoryHomePeer(id: peer.id, displayName: "\(peer.displayName) \(peer.id[hash...])",
                                  endpoint: peer.endpoint)
        }
    }
    private func startHosting() {
        guard listener == nil else { return }
        do {
            let listener = try NWListener(using: Self.parameters())
            let serviceName = myServiceName
            listener.service = .init(name: serviceName, type: Self.serviceType)
            advertisedServiceName = serviceName
            listener.newConnectionHandler = { [weak self] connection in Task { @MainActor in self?.accept(connection) } }
            listener.stateUpdateHandler = { [weak self] state in
                if case .failed(let error) = state {
                    Task { @MainActor in self?.lastError = self?.networkFailureMessage(error) }
                }
            }
            listener.start(queue: .main); self.listener = listener; isHosting = true
        } catch { lastError = error.localizedDescription }
    }
    private func accept(_ connection: NWConnection) {
        // A visibility change can race an already accepted TCP connection. Let its request reach
        // `receiveRequest`, which responds with the explicit protocol rejection instead of
        // accidentally serving a profile or silently treating the peer as accepted.
        guard isHosting else { connection.cancel(); return }
        let key = ObjectIdentifier(connection); track(connection, key: key)
        connection.start(queue: .main)
        receiveRequest(on: connection, key: key)
    }
    private func receiveRequest(on connection: NWConnection, key: ObjectIdentifier) {
        receive(MemoryHomeVisitRequest.self, on: connection) { [weak self, weak connection] request in
            guard let self, let connection else { return }
            guard case let .profileRequest(version, visitorID, name) = request,
                  (1...Self.protocolVersion).contains(version), Self.clean(name, limit: 40) != nil,
                  self.companion.memoryAlbum.memoryHomeAccess.visibility == .open,
                  self.companion.state.active != nil,
                  !self.companion.memoryAlbum.memoryHomeAccess.blockedPeerIDs.contains(visitorID) else {
                self.send(MemoryHomeVisitResponse.rejected(protocolVersion: Self.protocolVersion), over: connection) { connection.cancel() }; return
            }
            self.companion.memoryAlbum.recordMemoryHomeRequester(displayName: name, peerID: visitorID)
            self.send(MemoryHomeVisitResponse.profileCard(protocolVersion: version, card: self.profileCard(version: version)), over: connection) { connection.cancel() }
        }
    }
    private func receiveResponse(on connection: NWConnection, key: ObjectIdentifier) {
        receive(MemoryHomeVisitResponse.self, on: connection) { [weak self] response in
            // 회수는 `track` 의 종료 핸들러가 맡는다 — 여기서 또 지우면 규칙이 두 곳에 생긴다.
            defer { connection.cancel() }
            guard let self else { return }
            switch response {
            case let .profileCard(version, card) where (1...Self.protocolVersion).contains(version) && Self.valid(card):
                self.selectedProfile = card
                if let homeID = self.visitHomeIDs[key] { self.companion.memoryAlbum.recordMemoryHomeVisitStamp(homeID: homeID) }
            case let .rejected(version) where (1...Self.protocolVersion).contains(version):
                self.lastError = "This home is not accepting visits."
            default: self.lastError = "Invalid Memory Home response."
            }
        }
    }
    /// Do not fall back to the trainer name: malformed/legacy payloads still get a safe album
    /// fallback, never an accidental disclosure.
    private var localDisplayName: String { companion.memoryAlbum.memoryHomePublicNickname }
    /// 지금 닉네임으로 광고한다면 나올 이름. 자기 필터는 이 계산값이 아니라 실제로 광고한
    /// `advertisedServiceName` 을 먼저 본다 — 호스팅 중이 아닐 때만 여기로 떨어진다.
    private var myServiceName: String { Self.serviceName(nickname: localDisplayName, peerID: peerID) }

    /// Bonjour 광고 이름 = 닉네임 + 설치별 고유 접미. `BattleNet`·`PokemonTrade`·
    /// `MultiplayerRoomCenter` 가 모두 쓰는 형태이며, 같은 닉네임을 쓰는 두 기기가 서로를 자기로
    /// 오인하지 않게 하는 유일한 근거다. 접미가 없으면 mDNS 가 충돌한 쪽을 `이름 (2)` 로 개명하고,
    /// 개명당한 쪽은 저장된 원문으로 자기를 거르므로 상대를 자기로 착각해 목록에서 지운다.
    /// 접미는 `AppSettings.memoryHomeLANPeerID` 에서 나온다 — 설치마다 고정이라 재실행해도 같다.
    /// 길이는 `LANServiceName` 이 **바이트로** 자른다: 글자 수(40)로 자르면 한글 닉네임이 63바이트
    /// 상한을 넘고, mDNS 가 꼬리부터 자르므로 방금 붙인 접미가 제일 먼저 사라진다.
    nonisolated static func serviceName(nickname: String, peerID: UUID) -> String {
        LANServiceName.make(base: clean(nickname, limit: 40) ?? "MemoryHome",
                            suffix: "#\(peerID.uuidString.prefix(6))")
    }

    /// 목록에 적을 이름. 고유 접미를 떼고 남이 지은 문자열을 거른다.
    /// `clean` 을 쓰지 않는 이유: 개명된 구버전 이름(`MemoryHome (2)`)에는 공백이 들어 있어
    /// `clean` 이 통째로 버리고, 그러면 모든 집이 같은 기본 라벨로 뭉개져 구분할 수 없다.
    /// 줄바꿈·제어문자는 라벨을 망가뜨리므로 그대로 거른다.
    nonisolated static func displayName(fromService service: String) -> String? {
        let base = service.lastIndex(of: "#").map { String(service[service.startIndex..<$0]) } ?? service
        let trimmed = base.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 40,
              !trimmed.unicodeScalars.contains(where: {
                  CharacterSet.newlines.contains($0) || CharacterSet.controlCharacters.contains($0)
              }) else { return nil }
        return trimmed
    }

    /// 광고 하나를 집 한 채로 옮긴다. `id` 는 광고 원문이라 방문 도장이 기기별로 남는다.
    nonisolated static func peer(fromService name: String, excluding myServiceName: String,
                                 endpoint: NWEndpoint) -> MemoryHomePeer? {
        guard name != myServiceName, let displayName = displayName(fromService: name) else { return nil }
        return MemoryHomePeer(id: name, displayName: displayName, endpoint: endpoint)
    }
    /// 대문 문구는 `profileMessageForSharing` 만 읽는다 — 공유를 명시적으로 켠 경우에만 값이
    /// 나오는 프로퍼티다. `memoryHomeAccess.profileMessage` 를 직접 읽으면 동의 없이 새어 나간다.
    /// `internal` 인 것은 `valid(_:)`·`trackedConnectionCount` 와 같은 이유다 — 방문자가 실제로
    /// 받는 페이로드를 `private` 로 두면 "무엇을 내보내는가" 가 통째로 무테스트로 남는다.
    /// 대표 기억·대표 사진이 셋 다 빈 채로 릴리스된 동안 앨범 테스트는 전부 초록불이었다.
    func profileCard(version: Int = protocolVersion) -> MemoryHomeProfileCard {
        let sharedMessage = companion.memoryAlbum.profileMessageForSharing
        guard let mon = companion.state.active else {
            return .init(displayName: localDisplayName, speciesID: 1, isShiny: false,
                         sharedMemoryBody: nil, profileMessage: sharedMessage)
        }
        let access = companion.memoryAlbum.memoryHomeAccess
        let base = MemoryHomeProfileCard(displayName: localDisplayName, speciesID: mon.currentID, isShiny: mon.isShiny,
                     sharedMemoryBody: companion.memoryAlbum.sharedPinnedMemory(for: mon.id)?.body,
                     profileMessage: sharedMessage, roomTheme: companion.memoryAlbum.theme(for: mon.id),
                     showcaseFurniture: access.placedDecor.map(\.item))
        guard version >= 2 else { return base }
        return .init(displayName: base.displayName, speciesID: base.speciesID, isShiny: base.isShiny,
                     sharedMemoryBody: base.sharedMemoryBody, profileMessage: base.profileMessage,
                     roomTheme: base.roomTheme, showcaseFurniture: base.showcaseFurniture,
                     roomStyle: access.roomStyle, placedDecor: access.placedDecor,
                     featuredPhoto: access.featuredPhotoID.flatMap { id in access.photos.first { $0.id == id } })
    }
    /// 신뢰경계 클램프다 — `private` 로 두면 원격 페이로드 검증이 무테스트로 남는다.
    nonisolated static func valid(_ card: MemoryHomeProfileCard) -> Bool {
        guard clean(card.displayName, limit: 40) != nil, card.speciesID > 0, card.speciesID <= 10_000 else { return false }
        guard card.sharedMemoryBody.map({ clean($0, limit: 280) != nil }) ?? true else { return false }
        // 문구는 내부 공백을 허용하므로 `clean` 이 아니라 앨범과 같은 검증기를 쓴다 — 두 곳이
        // 규칙을 따로 가지면 내가 저장할 수 있는 문구를 상대가 거부하게 된다.
        return card.profileMessage.map { PokemonMemoryAlbum.validProfileMessage($0) != nil } ?? true
            // 원소가 전부 진짜 가구여도 **개수**가 열려 있으면 안 된다 — 방문 시트가 이 배열을
            // 그대로 `ForEach` 로 늘어놓으므로, 16KB 프레임에 들어가는 ~1000개면 화면이 멎는다.
            && card.showcaseFurniture.count <= Self.maxShowcaseItems
            && card.showcaseFurniture.allSatisfy { ItemKind.memoryHomeFurniture.contains($0) }
            && card.placedDecor.count <= Self.maxShowcaseItems
            && card.placedDecor.allSatisfy { ItemKind.memoryHomeFurniture.contains($0.item) && (0...1).contains($0.position.x) && (0...1).contains($0.position.y) }
            && (card.featuredPhoto.map { photo in
                photo.speciesID > 0 && photo.speciesID <= 10_000 && photo.caption.count <= 60
                    // 네 스타일 태그는 자유 문자열이라 여기서 길이를 막지 않으면 검증기 밖으로 샌다.
                    && [photo.frame, photo.background, photo.composition, photo.trainerStyle]
                        .allSatisfy { $0.count <= Self.styleTagLimit }
            } ?? true)
    }
    nonisolated static func clean(_ value: String, limit: Int) -> String? {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.count <= limit,
              !value.unicodeScalars.contains(where: {
                  CharacterSet.whitespacesAndNewlines.contains($0) || CharacterSet.controlCharacters.contains($0)
              }) else { return nil }
        return value
    }
    /// `includePeerToPeer` 는 AWDL(피어투피어)까지 켠다. `BattleNet`·`PokemonTrade`·
    /// `MultiplayerRoomCenter` 셋 다 켜는데 여기만 빠져 있어 같은 Wi-Fi 가 아닌 이웃을 못 봤다.
    private static func parameters() -> NWParameters {
        let params = NWParameters.tcp
        params.includePeerToPeer = true
        return params
    }

    /// Bonjour 권한 거부를 Network 프레임워크의 내부 코드로 노출하지 않는다. 특히 `NoAuth` 는
    /// 홈 계정 인증이 아니라 macOS의 로컬 네트워크 서비스 권한을 뜻한다.
    ///
    /// 나머지 오류도 원문을 그대로 올리지 않는다 — `localizedDescription` 은 영어 프레임워크
    /// 문자열이라 ko/ja 화면에 "Network is down" 이 그대로 실린다. 원인은 `AppLog` 로 보낸다
    /// (`BattleNet` 이 로그와 화면 문구를 나눠 갖는 것과 같은 형태다).
    private func networkFailureMessage(_ error: NWError) -> String {
        guard error.localizedDescription.localizedCaseInsensitiveContains("noauth") else {
            AppLog.write("memory home discovery failed: \(error)")
            return companion.l.t("주변 홈을 찾을 수 없어요. 네트워크 상태를 확인해 주세요.",
                                 "Nearby homes are unavailable. Check your network connection.",
                                 "近くのホームを探せません。ネットワークの状態を確認してください。")
        }
        return companion.l.t("주변 홈을 찾을 수 없어요. 앱을 다시 열어 로컬 네트워크 접근을 허용해 주세요.",
                             "Nearby homes are unavailable. Reopen the app and allow local network access.",
                             "近くのホームを探せません。アプリを開き直してローカルネットワークへのアクセスを許可してください。")
    }
    private func cancelConnections() {
        connections.values.forEach { $0.cancel() }
        connections.removeAll(); visitHomeIDs.removeAll()
    }
    private func cancelVisitConnections() {
        for key in visitHomeIDs.keys { connections.removeValue(forKey: key)?.cancel() }
        visitHomeIDs.removeAll()
    }
    /// 완료 핸들러를 `@MainActor` 함수 타입으로 못 박는다. 이유가 둘 있다:
    /// 1) 전역 액터 격리 함수 타입은 암묵적으로 `Sendable` 이라, `@Sendable` 인 Network 콜백에
    ///    캡처될 수 있다 — 그냥 `() -> Void` 로 두면 Swift 6 concurrency warning 이 남는다.
    /// 2) 호출부(`receiveRequest` 등)는 앨범·상태 같은 MainActor 상태를 직접 만진다. 파라미터를
    ///    `@Sendable` 로 바꾸면 그 호출부가 전부 깨지므로, 격리를 없애는 게 아니라 **명시**해야 한다.
    /// 그래서 Network 콜백 안에서는 `Task { @MainActor in }` 로 한 번 홉한다.
    /// 프레임은 요청→응답 1회 왕복뿐이라 이 홉이 순서를 바꾸지 않는다.
    private func send<T: Encodable & Sendable>(_ value: T, over connection: NWConnection,
                                              completion: @escaping @MainActor () -> Void = {}) {
        guard let data = try? JSONEncoder().encode(value), data.count <= Int(Self.maxFrameBytes) else { connection.cancel(); return }
        var length = UInt32(data.count).bigEndian; let header = Data(bytes: &length, count: 4)
        connection.send(content: header + data, completion: .contentProcessed { error in
            // 실패한 전송에는 응답이 오지 않는다 — 연결을 접어 대기 중인 쪽이 풀리게 한다.
            guard error == nil else { connection.cancel(); return }
            Task { @MainActor in completion() }
        })
    }
    /// `T: Sendable` 은 메타타입(`T.Type`)이 격리 클로저로 넘어갈 수 있게 하려고 붙인다.
    /// 이 전송로의 페이로드 두 종은 이미 `Sendable` 이라 실질 제약이 아니다.
    private func receive<T: Decodable & Sendable>(_ type: T.Type, on connection: NWConnection,
                                                 completion: @escaping @MainActor (T) -> Void) {
        // `self` 를 쓰지 않는다 — 프레임 상한은 `Self` 로 읽으므로 weak 캡처가 필요 없었다.
        connection.receive(minimumIncompleteLength: 4, maximumLength: 4) { header, _, _, error in
            guard error == nil, let header, header.count == 4 else { connection.cancel(); return }
            // `load(as:)` 는 정렬을 전제한다 — `NWConnection` 이 주는 `Data` 는 4바이트 정렬을
            // 보장하지 않으므로 반드시 `loadUnaligned` 다. BattleNet·MultiplayerRoomCenter·
            // PokemonTrade 의 프레이밍과 같은 형태다. `test-gate.sh` 가 이 부류를 스윕한다.
            let length = header.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }.bigEndian
            guard length > 0, length <= Self.maxFrameBytes else { connection.cancel(); return }
            connection.receive(minimumIncompleteLength: Int(length), maximumLength: Int(length)) { data, _, _, error in
                guard error == nil, let data, data.count == Int(length),
                      let value = try? JSONDecoder().decode(T.self, from: data) else { connection.cancel(); return }
                Task { @MainActor in completion(value) }
            }
        }
    }
}
