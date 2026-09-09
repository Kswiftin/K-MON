import Foundation

/// 마을 화면 한 줄의 **유일한** 출처.
///
/// 저장 필드가 하나도 없다 — 주민·지형·계절·시각에서 파생한다(`MemoryHomeRoomLife` 와 같은
/// 원칙). 뷰 안 `private` 함수로 두지 않는 이유도 같다: 뷰 안이면 문구가 무테스트로 남고,
/// 실제로 미니룸 문구가 그 상태였던 동안 종을 아예 읽지 않아 누구의 방이든 같은 문장이 나왔다.
///
/// **좁은 조건이 먼저 이긴다**: 갓 온 주민 → 자리를 잃은 주민 → 서식 만족 주민 → 터만 닦인
/// 마을 → 텅 빈 마을. 좁은 것이 먼저라는 규칙은 방과 같다 — 넓은 문장은 모든 마을이 공유하고,
/// 좁은 문장은 이 마을에만 있는 사실이다.
///
/// `season`·`timeOfDay`·`now` 를 **인자로 받는다.** 함수 안에서 시계를 읽으면 테스트가 실행
/// 시각에 따라 다른 가지를 밟아, 밤에 돌린 CI 만 빨개진다.
///
/// 이름 뒤에 조사를 붙이지 않는다(`MemoryHomeRoomLife` 의 "와/과" 규칙). 주민 이름은 PokéAPI
/// 한국어 종 이름이라 받침을 계산할 수는 있지만, 조사 계산기를 새로 만들 값이 아니고 문장을
/// 조사 없이 쓰면 규칙이 하나로 남는다.
///
/// `L` 을 받지 않는다 — 이 저장소는 한국어 전용이고(`docs/reference/korean-only.md`),
/// `MemoryHomeRoomLife` 가 `_ l: L` 을 받는 것은 다국어 시절의 흔적이다(문구는 이미 한국어
/// 리터럴이다).
enum PokopiaTownLife {

    /// 갓 온 주민으로 볼 시간. 세션 하나가 부른 사건이니 그 뒤 한동안은 그것이 화면의 주인공이다.
    /// 6시간은 "오늘 안에 마을을 다시 열면 아직 새 소식" 정도의 폭이다.
    static let freshArrivalWindow: TimeInterval = 60 * 60 * 6

    static func line(residents: [TownResident], terrain: [TownTerrain],
                     season: MemoryHomeSeason, timeOfDay: MemoryHomeTimeOfDay,
                     now: Date) -> String {
        // ① 갓 온 주민. 도착 순서를 지키므로 **가장 최근**을 뒤에서 찾는다.
        if let fresh = residents.last(where: { now.timeIntervalSince($0.arrivedAt) < freshArrivalWindow
                                               && now >= $0.arrivedAt }) {
            return "\(fresh.name) 이 마을이 마음에 든 모양이에요. 방금 도착했어요."
        }
        // ② 자리를 잃은 주민. 사용자가 그 지형을 없앤 결과이므로 넓은 문장보다 먼저 말한다.
        if let unsettled = residents.first(where: { !PokopiaTown.isSettled($0, terrain: terrain) }) {
            return "\(unsettled.name) 살던 자리를 찾는 중이에요."
        }
        // ③ 서식이 만족된 주민. 그 주민이 사는 지형이 문장을 정한다.
        if let settled = residents.first, let type = settled.types.first {
            return settledLine(settled.name, terrain: PokopiaTown.terrain(for: type),
                               timeOfDay: timeOfDay)
        }
        // ④ 주민은 없는데 부르는 환경은 됐다.
        if !PokopiaTown.welcomingTypes(terrain).isEmpty {
            return "터를 잘 닦아 뒀어요. 이제 누가 올까요?"
        }
        // ⑤ 텅 빈 마을. 무엇을 하면 되는지 말한다 — 여기서 계절을 읊으면 사용자가 다음 동작을 못 찾는다.
        return emptyLine(season: season)
    }

    /// 지형별 문장. 여덟 지형 전부에 답이 있어야 한다(전수 `switch`) — 빠진 지형은 그 위에 사는
    /// 주민의 마을이 영영 다른 문장을 갖는다.
    ///
    /// 시각으로 갈리는 것은 낮과 밤뿐이다. 여덟 지형 × 세 시각을 다 쓰면 24문장이 되고, 그중
    /// 대부분은 아침과 낮을 구별하지 못한 채 늘어난다.
    private static func settledLine(_ name: String, terrain: TownTerrain,
                                    timeOfDay: MemoryHomeTimeOfDay) -> String {
        let isNight = timeOfDay == .night
        switch terrain {
        case .water:
            return isNight ? "\(name) 물가에 비친 달을 보고 있어요."
                           : "\(name) 물가에서 몸을 말리고 있어요."
        case .grass:
            return isNight ? "\(name) 풀밭에 몸을 묻고 잠들었어요."
                           : "\(name) 풀밭을 천천히 돌아다녀요."
        case .soil:
            return isNight ? "\(name) 파 둔 흙 속에서 조용해요."
                           : "\(name) 흙을 파헤치며 놀고 있어요."
        case .sand:
            return isNight ? "\(name) 식은 모래에 배를 대고 있어요."
                           : "\(name) 따뜻한 모래에 뒹굴고 있어요."
        case .flower:
            return isNight ? "\(name) 꽃밭 한가운데서 잠들었어요."
                           : "\(name) 꽃밭에서 낮잠을 자고 있어요."
        case .tree:
            return isNight ? "\(name) 나무 위에서 밤바람을 쐬고 있어요."
                           : "\(name) 나무 그늘에 앉아 있어요."
        case .rock:
            return isNight ? "\(name) 바위에 기대 별을 보고 있어요."
                           : "\(name) 바위 위에서 힘을 겨루고 있어요."
        case .path:
            return isNight ? "\(name) 길 끝을 한참 바라보고 있어요."
                           : "\(name) 길을 따라 마을을 둘러봐요."
        }
    }

    /// 텅 빈 마을. 계절로 갈리되 **무엇을 하면 되는지**를 문장마다 담는다.
    private static func emptyLine(season: MemoryHomeSeason) -> String {
        switch season {
        case .spring: "아직 아무도 살지 않아요. 물이나 꽃밭을 넓혀 보세요."
        case .summer: "아직 아무도 살지 않아요. 물가를 넓히면 누군가 올지도 몰라요."
        case .autumn: "아직 아무도 살지 않아요. 나무를 심어 보세요."
        case .winter: "아직 아무도 살지 않아요. 바위나 흙을 넓혀 보세요."
        }
    }
}
