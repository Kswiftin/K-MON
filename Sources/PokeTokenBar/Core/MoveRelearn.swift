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
    /// - Returns: id 기준 중복 제거 후 id 오름차순. 정렬을 고정하는 이유는 표시 순서가 조회
    ///   순서(비동기 완료 순)에 따라 흔들리지 않게 하기 위함이다.
    static func candidates(inherited: [[MoveSpec]], learned: [MoveSpec]) -> [MoveSpec] {
        let known = Set(learned.map(\.id))
        var seen = Set<Int>()
        var out: [MoveSpec] = []
        for moves in inherited {
            for move in moves where !known.contains(move.id) && seen.insert(move.id).inserted {
                out.append(move)
            }
        }
        return out.sorted { $0.id < $1.id }
    }
}
