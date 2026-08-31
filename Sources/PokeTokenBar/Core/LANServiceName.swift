import Foundation

/// Bonjour 서비스 **인스턴스 이름**의 바이트 예산. 상한은 63 UTF-8 바이트(RFC 6763 §4.1.1)이고,
/// 넘기면 mDNSResponder 가 조용히 꼬리를 자르거나 광고를 아예 올리지 않는다.
///
/// 왜 글자 수로 자르면 안 되나: 한글은 글자당 3바이트라 20자면 이미 60바이트다. "40자 제한" 같은
/// `Character` 기준 클램프는 ASCII 에서만 맞고 한글·이모지에서는 두세 배를 흘려보낸다. 그리고
/// 잘리는 건 **꼬리**라, 네 센터가 이름 뒤에 붙이는 고유 접미(`#ABCDEF`)가 제일 먼저 먹힌다 →
/// 같은 닉네임 두 기기가 같은 이름을 광고 → mDNS 가 한쪽을 `이름 (2)` 로 개명 → 개명당한 쪽은
/// 잘리지 않은 로컬 원문으로 자기를 걸러 **상대를 자기로 착각해 목록에서 지운다.** 접미를 붙인
/// 이유 자체가 무효가 되는 경로다.
///
/// 이 계산은 `PlayerGymRoomName.make` 안에만 있었다. 나머지 세 센터(`BattleNet`·`PokemonTrade`·
/// `MultiplayerRoomCenter`)와 `MemoryHomeVisitCenter` 는 예산을 아예 보지 않았다 — 한 곳에만
/// 사는 규칙은 부류로 남는다. `test-gate.sh` 가 광고 이름을 굽는 자리를 여기로 강제한다.
enum LANServiceName {
    static let maxBytes = 63

    /// `base` 를 예산 안으로 줄여 `base + suffix` 를 만든다.
    ///
    /// `suffix` 는 **절대 자르지 않는다** — 고유성이 거기에만 있고, 잘린 접미는 접미가 없는 것보다
    /// 나쁘다(길이만 맞고 충돌은 그대로다). `removeLast()` 는 `Character` 단위라 그래핌 클러스터
    /// 중간에서 끊기지 않는다: 스칼라를 반으로 자르면 깨진 UTF-8 이 광고에 실린다.
    static func make(base: String, suffix: String) -> String {
        var base = base
        let budget = max(0, maxBytes - suffix.utf8.count)
        while base.utf8.count > budget, !base.isEmpty { base.removeLast() }
        return base + suffix
    }
}
