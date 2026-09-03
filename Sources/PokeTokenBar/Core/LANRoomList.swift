import Foundation

/// LAN 방 목록의 활동 접두와 가시성 판정.
///
/// **개설과 목록이 같은 값을 읽어야 한다.** 접두는 `MultiplayerRoomCenter.startHosting` 이
/// 광고 이름에 붙이고 각 화면이 목록을 거를 때 다시 읽는데, 두 곳에 따로 적혀 있으면 한쪽만
/// 바꾼 순간 만든 방이 어느 목록에도 안 뜬다 — 2~4인 방 배틀이 정확히 그 상태로 세 주를
/// 보냈다(#209). 그래서 접두 문자열은 여기 한 곳에만 있다.
enum LANRoomList {
    /// 활동이 광고 이름 앞에 붙이는 접두.
    ///
    /// 체육관·레이드는 이름 생성기(`PlayerGymRoomName`·`RaidRoomName`)가 따로 있지만 접두는
    /// 그쪽 상수를 그대로 읽는다 — 같은 문자열을 두 번 적으면 갈라진다.
    static func prefix(for activity: RoomActivity) -> String {
        switch activity {
        case .battle: "BATTLE"
        case .pokeathlon: "RUN"
        case .pokemonQuiz: "QUIZ"
        case .tournament: "TOUR"
        case .gym: PlayerGym.roomNamePrefix
        case .raid: RaidRoomName.prefix
        }
    }

    /// 이 이름이 **그 활동의 방인가.** 방 종류를 묻는 자리는 전부 여기로 온다 —
    /// `PlayerGym.isGymRoomName`·`RaidRoomName.isRaidRoomName`·참가 직전의 토너먼트 판정까지.
    /// 저마다 접두를 다시 적으면 한쪽만 바뀐 순간 갈라진다.
    ///
    /// 소유는 안 본다. 참가 직전에 "이 방이 무슨 방인가" 를 묻는 자리(`MultiplayerRoomCenter.join`)
    /// 에서는 내 방인지가 답을 바꾸면 안 된다 — 소유까지 보려면 `isVisible` 을 쓴다.
    static func matches(_ serviceName: String, activity: RoomActivity) -> Bool {
        // 구분자까지 포함해 비교한다. 접두만 보면 `BATTLE` 이 `BATTLEROYALE` 에 걸린다.
        serviceName.hasPrefix("\(prefix(for: activity)) · ")
    }

    /// 이 방을 **내 목록에 보여 줄 것인가.** 두 조건을 함께 본다.
    ///
    /// 1. 활동이 맞다 — 안 거르면 배틀 목록에 레이드 방이 뜨고, 붙은 게스트는 자기가 누른 적
    ///    없는 협동전 화면으로 끌려간다.
    /// 2. 내 방이 아니다 — 자기 방에 "참가" 를 누르면 `guard phase == .idle` 에 걸려 조용히
    ///    거절되고, 사용자에게는 눌러도 아무 일이 없는 버튼으로 보인다.
    ///
    /// **`serviceName`(원문)으로 본다.** `name` 은 `#` 앞에서 잘려 있어 내 꼬리표를 못 찾는다 —
    /// 체육관이 그 실수로 자기 방을 남의 방으로 읽었다.
    static func isVisible(_ serviceName: String, activity: RoomActivity, myTag: String) -> Bool {
        matches(serviceName, activity: activity) && !isMine(serviceName, myTag: myTag)
    }

    /// 이름 끝의 꼬리표가 내 것인가. `#` 을 붙여 비교한다 — 없이 비교하면 남의 꼬리표
    /// 부분열이나 트레이너 이름에 우연히 걸린다.
    static func isMine(_ serviceName: String, myTag: String) -> Bool {
        serviceName.contains("#\(myTag)")
    }
}
