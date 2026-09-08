import Foundation

/// 진행 중인 사파리존 방문을 디스크로 옮기는 형식 — `RogueRunSave` 와 같은 모양·같은 이유다.
/// `SafariVisit` 을 그대로 `Codable` 로 만들지 않는 이유는 `SplitMix64` 가 `Codable` 이 아니라서다
/// (씨앗과 "소비된 뒤의 상태" 를 분리해서 저장해야 다음 굴림이 재시작 후에도 이어진다).
///
/// 세이브 본체가 아니라 **옆 파일**(`safari-zone.json`)에 둔다 — 방문은 재화도 도감도 직접
/// 주지 않으므로(포획 커밋은 `CompanionStore.catchInSafariZone` 이 별도로 하고 그 결과만
/// 세이브 본체에 남는다) 무결성 서명과 세이브 이전 경로에 닿지 않는다.
struct SafariZoneSave: Codable, Sendable {
    /// 형식 판. 모르는 판은 **방문을 버린다** — 진행 중인 방문은 소모품이고, 반쯤 읽어 되살린
    /// 방문이 처음부터 다시 시작하는 것보다 나쁘다(범위 밖 워커 위치는 크래시로 끝난다).
    static let currentVersion = 1

    var version = currentVersion
    var zone: SafariZone.ZoneID
    var seed: UInt64
    var balls: Int
    var stepsRemaining: Int
    var walker: SafariWalker
    var currentEncounter: SafariEncounter?
    var catchesThisVisit: Int
    var caughtSpeciesIDs: [Int]
    var visitLog: [SafariLogEntry]
    var hasEnded: Bool
    /// rng 의 현재 상태(소비된 뒤 값). `seed` 와 달리 이 값을 그대로 복원해야 다음 굴림이
    /// 저장 시점에 이어서 계속된다 — seed 로 되돌리면 앱을 껐다 켤 때마다 같은 조우가 다시 나온다.
    var rngState: UInt64

    init(_ visit: SafariVisit) {
        zone = visit.zone
        seed = visit.seed
        balls = visit.balls
        stepsRemaining = visit.stepsRemaining
        walker = visit.walker
        currentEncounter = visit.currentEncounter
        catchesThisVisit = visit.catchesThisVisit
        caughtSpeciesIDs = visit.caughtSpeciesIDs
        visitLog = visit.visitLog
        hasEnded = visit.hasEnded
        rngState = visit.rngState
    }

    /// 되살린 방문. 형식 판이 다르면 `nil` — 복원 실패는 버리는 게 낫다는 `RogueRunSave` 의
    /// 계약과 동일하다. 걸음·볼 개수는 0 이상으로 자른다(손편집·구버전 대비).
    var restored: SafariVisit? {
        guard version == Self.currentVersion else { return nil }
        return SafariVisit(zone: zone, seed: seed, balls: max(0, balls),
                           stepsRemaining: max(0, stepsRemaining), walker: walker,
                           currentEncounter: currentEncounter,
                           catchesThisVisit: max(0, catchesThisVisit),
                           caughtSpeciesIDs: caughtSpeciesIDs, visitLog: visitLog,
                           hasEnded: hasEnded, rngState: rngState)
    }
}
