/// 하트비늘(기술 다시 배우기, #97) 순수 로직 — 네트워크·상태 없음.
///
/// 후보 계산이 여기 사는 이유: 조회(`PokeAPIClient.canonicalLevelUpMoves`)는 Store 가 하고 이 함수는
/// 받은 배열만 본다. 그래야 순수 함수로 테스트되고 커버리지 게이트(`scripts/test-gate.sh` 의
/// LOGIC_CORE)에 잡힌다.
enum MoveRelearn {
    /// 상점가. 진화 아이템 공통가(500)와 값이 같지만 **별 상수로 둔다** — `evolutionItemPrice` 를
    /// 재사용하면 진화 아이템 값을 조정하는 순간 다시 배우기 값이 같이 끌려간다.
    static let price = 500

    /// 다시 배울 수 있는 기술 목록.
    ///
    /// - Parameters:
    ///   - inherited: 진화 경로의 종별 "현재 레벨 이하 레벨업 기술" 배열(종 하나당 배열 하나).
    ///   - learned: 지금 배우고 있는 기술 — 목록에서 뺀다(고르면 아무 일도 안 나는 선택지).
    /// - Returns: id 기준 중복 제거 후 **습득 레벨 오름차순**(같은 레벨은 id 순). 진화 단계마다 배우는
    ///   레벨이 다르면 가장 이른 레벨을 쓴다. 예전엔 id 순이라 레벨이 들쭉날쭉하게 섞여 보였다.
    ///   정렬을 고정하는 이유는 표시 순서가 조회 순서(비동기 완료 순)에 흔들리지 않게 하기 위함이다.
    static func candidates(inherited: [[LevelUpMove]], learned: [MoveSpec]) -> [MoveSpec] {
        let known = Set(learned.map(\.id))
        var earliest: [Int: LevelUpMove] = [:]
        for moves in inherited {
            for entry in moves where !known.contains(entry.move.id) {
                if let existing = earliest[entry.move.id], existing.level <= entry.level { continue }
                earliest[entry.move.id] = entry
            }
        }
        return earliest.values
            .sorted { $0.level == $1.level ? $0.move.id < $1.move.id : $0.level < $1.level }
            .map(\.move)
    }
}

/// 레벨업으로 배우는 기술 하나와 그 습득 레벨.
struct LevelUpMove: Sendable {
    let move: MoveSpec
    let level: Int
}
