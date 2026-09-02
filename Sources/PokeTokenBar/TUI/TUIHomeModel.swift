import Foundation

/// 홈 화면이 그리는 값 한 벌. `CompanionStore` 를 렌더에서 직접 읽지 않고 이 구조체를 거치는 이유는
/// 렌더를 순수 함수로 유지하기 위해서다 — 스토어는 `@MainActor` 에 네트워크 로딩까지 물려 있어
/// 테스트에서 화면 조합만 따로 검증할 방법이 없어진다.
struct TUIHomeModel: Equatable, Sendable {
    /// 진행 중이거나 정산을 기다리는 모험.
    struct Adventure: Equatable, Sendable {
        var zone: String
        var minutes: Int
        /// 남은 초. 0 이면 정산 가능하다.
        var remainingSeconds: Int
        var progress: Double
        var isClaimable: Bool { remainingSeconds <= 0 }
    }

    var trainerName: String
    /// 파트너가 없을 수 있다 — 알을 부화기에 넣으면 활성 개체가 빈다.
    var partnerName: String?
    var partnerLevel: Int
    var isShiny: Bool
    var levelProgress: Double
    var experienceToNextLevel: Int
    var starPieces: Int
    var adventure: Adventure?
    /// 이 화면이 읽기 전용 세이브를 보고 있다. 터미널은 항상 참이다 — 쓰기는 앱에만 있다.
    var isReadOnly: Bool
    /// 마지막 동작의 결과 한 줄(보상 요약·거절 사유). 다음 입력까지 남는다.
    var status: String?
}

extension TUIHomeModel {
    /// 렌더 테스트용 표본. 실제 진행과 무관한 고정값이다.
    static let sample = TUIHomeModel(
        trainerName: "트레이너",
        partnerName: "피카츄",
        partnerLevel: 34,
        isShiny: true,
        levelProgress: 0.71,
        experienceToNextLevel: 4_200,
        starPieces: 12_480_000,
        adventure: Adventure(zone: "동굴", minutes: 50, remainingSeconds: 1_122, progress: 0.38),
        isReadOnly: false,
        status: nil)
}
