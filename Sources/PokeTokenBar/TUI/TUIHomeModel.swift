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
    /// 파트너 그림. 이미 터미널 칸으로 접힌 줄이고(`TUISprite.block`) **빈 배열이 정상**이다 —
    /// 스프라이트 캐시가 비었거나, 출력이 파이프거나, 창이 좁으면 그림 없이 그린다.
    ///
    /// 왜 완성된 줄로 받나: 이 줄에는 SGR escape 가 들어가 폭 계산(`TUIText.displayWidth`)을
    /// 통과할 수 없다. 렌더가 픽셀을 받아 조립하면 그 판정이 렌더 안으로 들어와 순수 함수가
    /// 디스크(스프라이트 캐시)를 읽게 된다.
    var partnerArt: [String] = []
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
