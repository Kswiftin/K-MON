import Foundation

/// 관장 자격의 수명주기를 한곳에서 다룬다 — **구멍이 몰려 있는 자리라 분기를 흩어 두지 않는다.**
///
/// 자격을 얻는 길은 셋(신규 개설·도전 승리·앱 재시작 복원)이고, 잃는 길은 다섯(패배·자진 퇴위·
/// 재시작 양보·세이브 정규화·세팅 기한 초과)이다. 잃는 길이 하나라도 `CompanionStore`
/// `resignGymLeadership()` 을 안 지나면 방어팀 넷이 영영 잠긴 채 남는다.
@MainActor
@Observable
final class PlayerGymCoordinator {
    private let companion: CompanionStore
    private let rooms: MultiplayerRoomCenter
    private let clock: () -> Date
    private var scanTask: Task<Void, Never>?

    /// 개설을 눌렀는데 이미 열린 체육관이 있어 막혔다.
    private(set) var blockedByExistingGym = false

    /// 내 앱이 낮아 체육관을 아예 못 쓴다 — 더 새로운 프로토콜의 체육관이 보인다.
    /// 개설도 도전도 막고 업데이트를 안내한다.
    var needsAppUpdateForGym: Bool { rooms.isOutdatedForGym }
    /// 재시작 후 자격을 반납했다 — 그 사이 남이 체육관을 열었다는 뜻이라 한 번 알린다.
    private(set) var yieldedToExistingGym = false

    /// 다음에 열리는 체육관 방에 경합 판정을 걸까. **직접 연 체육관에만** 건다.
    ///
    /// 배틀로 넘겨받은 자리는 경합이 아니다. 승계 직후 몇 초 동안은 내가 방금 이긴 옛 관장의 방이
    /// 아직 광고되는데(`concludeGymMatch` 가 결과를 보여 주고 3초 뒤에 닫는다), 그 방의 재임 시각은
    /// 나보다 이르다 — 경합으로 다루면 **딴 체육관을 그 자리에서 반납한다.**
    private var checksConflictWhenRoomOpens = false

    /// 브라우저가 한 바퀴 돌기 전에는 개설 버튼을 잠근다. **빈 목록을 "없음"으로 읽으면**
    /// 단일성 정책 전체가 무의미해진다 — 둘이 동시에 열어도 아무도 못 막는다.
    ///
    /// **방 개수 변화로 판정하면 안 된다.** 아무 방도 없는 것이 정상인 상황(첫 사용자, 혼자
    /// 켠 경우)에서는 개수가 0 에서 움직이지 않아 영영 "검색 중" 에 갇힌다. 실제로 그렇게
    /// 만들었다가 그 화면만 보이는 증상이 나왔다 — 그래서 **시간으로** 넘긴다.
    private(set) var hasScannedOnce = false

    /// 브라우저가 한 바퀴 돌기까지 주는 시간. Bonjour 응답은 보통 1초 안에 오지만, 늦게 온
    /// 체육관을 "없음" 으로 읽고 두 번째 체육관을 여는 것보다는 조금 더 기다리는 편이 낫다.
    static let scanWindow: TimeInterval = 2.5

    /// LAN 탐색 자체가 꺼져 있나. 꺼져 있으면 브라우저가 아예 돌지 않아 **영원히 아무것도 못 찾는다** —
    /// 그 상태를 "검색 중" 으로 보여주면 사용자는 고장으로 읽는다.
    var isDiscoveryUnavailable: Bool { !rooms.isBrowsing }

    init(companion: CompanionStore, rooms: MultiplayerRoomCenter, clock: @escaping () -> Date = Date.init) {
        self.companion = companion
        self.rooms = rooms
        self.clock = clock
        rooms.onGymRoomOpened = { [weak self] in
            guard let self, self.checksConflictWhenRoomOpens else { return }
            self.checksConflictWhenRoomOpens = false
            self.scheduleConflictCheck()
        }
        rooms.onGymLeadershipWon = { [weak self] gymID in self?.takeLeadership(gymID: gymID) }
        rooms.onGymLeadershipLost = { [weak self] in self?.companion.resignGymLeadership() }
    }

    /// 앱이 켜질 때와 화면이 뜰 때 부른다.
    ///
    /// 순서가 중요하다: **기한부터 본다.** 마감이 지난 채 복원됐으면 그 자리에서 자격이 풀려야
    /// 재시작으로 기한을 다시 받는 길이 막힌다.
    func refresh() {
        // 탐색이 꺼져 있지 않다면 창을 연다. 화면이 뜬 순간부터 재야 "검색 중" 이 끝난다.
        if rooms.isBrowsing { beginScanIfNeeded() }
        // 막혔던 사유가 사라졌으면 안내도 지운다 — 안 지우면 체육관이 닫힌 뒤에도
        // "이미 열린 체육관이 있습니다" 가 계속 남는다.
        if rooms.gymRoomHoldingTheSlot == nil { blockedByExistingGym = false }
        // 자격이 풀렸으면 **방도 닫는다.** 상태만 지우면 방은 계속 광고되는데 화면은 관장이
        // 아닌 것으로 떨어져, 자기 방이 목록에 남고 `join` 은 `phase == .hosting` 이라 조용히
        // 거절된다 — 도전·관전 버튼이 눌러도 아무 반응이 없는 상태가 그것이다.
        if companion.expireGymLeadershipIfSetupLapsed() { rooms.leaveRoom() }
        guard companion.isGymLeader else {
            // 자격은 없는데 체육관 방만 떠 있는 어긋남을 정리한다(크래시·예외 경로 대비).
            if rooms.isGymRoom { rooms.leaveRoom() }
            return
        }
        // 여기서부터는 **광고를 재개하는 경로**다(재시작·자격 복원). 내 방이 이미 떠 있거나 뜨는
        // 중이면 이 경로가 아니다 — 그때 남이 뒤늦게 연 체육관을 보고 자리를 내주면, 배틀로 딴
        // 체육관이 방어팀을 세우는 도중에 날아간다. 그 판정은 `resolveGymRoomConflict` 가 한다.
        guard rooms.phase == .idle else { return }
        // **개설 버튼만 막으면 여기로 새 나가** 체육관이 둘이 된다.
        if let existing = rooms.gymRoomHoldingTheSlot {
            AppLog.write("player gym: yielding leadership, another gym is already open (\(existing.name))")
            companion.resignGymLeadership()
            yieldedToExistingGym = true
            return
        }
        // 여기도 "빈 목록을 보고 연다" 는 같은 경합에 노출된다 — 연 뒤에 한 번 더 본다.
        checksConflictWhenRoomOpens = true
        rooms.createGymRoom()
    }

    /// 스캔 창을 연다 — 화면이 뜰 때마다 부르고, 창이 끝나면 목록을 신뢰한다.
    /// 이미 한 번 돌았으면 다시 기다리지 않는다(코디네이터는 앱 수명이라 값이 남는다).
    func beginScanIfNeeded() {
        guard !hasScannedOnce, scanTask == nil else { return }
        scanTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.scanWindow))
            guard !Task.isCancelled else { return }
            self?.hasScannedOnce = true
            self?.scanTask = nil
        }
    }

    /// 체육관을 새로 연다. 이미 보이는 체육관이 있으면 열지 않는다.
    ///
    /// 발견이 즉시가 아니라 둘이 동시에 빈 목록을 보고 열 수 있다 — 연 뒤에 한 번 더 본다.
    func openGym() {
        // 내 앱이 낮으면 열지 못한다. 열어 봐야 최신 앱들은 붙지 못하고, 그 방이 자리만 차지한다.
        guard !needsAppUpdateForGym else { return }
        guard rooms.gymRoomHoldingTheSlot == nil else { blockedByExistingGym = true; return }
        blockedByExistingGym = false
        checksConflictWhenRoomOpens = true
        companion.becomeGymLeader()
        rooms.createGymRoom()
    }

    /// 도전에서 이겨 자리를 넘겨받는다. 옛 관장 방은 곧 닫히므로 내 기기에서 새로 연다.
    func takeLeadership(gymID: UUID) {
        companion.becomeGymLeader(gymID: gymID)
        rooms.leaveRoom()
        rooms.createGymRoom()
    }

    /// 관장이 배틀 도중 사라진 자리를 이어받는다 — 도주가 이득이 되지 않게 하는 유일한 수단이다.
    /// 도주한 관장이 나중에 앱을 켜면 `refresh()` 에서 이 체육관을 보고 자격을 반납한다.
    func takeOverAbandonedGym() {
        rooms.dismissGymTakeoverOffer()
        openGym()
    }

    func resign() {
        companion.resignGymLeadership()
        rooms.leaveRoom()
    }

    func dismissNotices() {
        blockedByExistingGym = false
        yieldedToExistingGym = false
    }

    /// 방어팀 세팅 마감까지 남은 시간. nil = 마감이 없다(정원을 채웠다).
    var setupSecondsRemaining: TimeInterval? {
        guard let deadline = companion.gymLeadership?.defenseDeadline else { return nil }
        return max(0, deadline.timeIntervalSince(clock()))
    }

    /// 동시 개설 경합 흡수. 발견이 즉시가 아니라 둘 다 빈 목록을 보고 열 수 있으므로, 연 **뒤에**
    /// 한 번 더 본다.
    ///
    /// 선후는 발견 시각이 아니라 **재임 시작 시각**으로 정한다(`PlayerGym.yieldsToOtherGym`) —
    /// 발견 시각은 기기마다 달라 둘 다 닫거나 둘 다 남는다.
    private func scheduleConflictCheck() {
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.resolveGymRoomConflict()
        }
    }

    private func resolveGymRoomConflict() {
        // 경합 상대는 **자리를 다투는 방**뿐이다 — 붙지도 못하는 구버전 방에 자리를 내주면 안 된다.
        guard let mine = companion.gymLeadership?.heldSince,
              let other = rooms.gymRoomHoldingTheSlot,
              let theirTag = PlayerGymRoomName.idTag(fromRoomName: other.serviceName) else { return }
        // 옛 형식 방은 재임 시각이 안 실려 온다 — 그때는 식별자로 가른다.
        guard PlayerGym.yieldsToOtherGym(
            myHeldSince: mine, myRoomTag: rooms.myRoomTag,
            otherHeldSince: PlayerGymRoomName.parse(other.serviceName)?.heldSince,
            otherRoomTag: theirTag) else { return }
        AppLog.write("player gym: closing my gym, \(other.name) has held it longer")
        companion.resignGymLeadership()
        rooms.leaveRoom()
        yieldedToExistingGym = true
    }
}
