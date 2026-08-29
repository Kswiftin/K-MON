import Foundation

/// 기획서 §13 — 동행이 **아주 드물게** 방명록에 흔적을 남긴다.
///
/// 저장 필드가 없다. "오늘 남겼는가" 는 이미 저장되는 방명록 글의 `createdAt`+`authorKind` 로
/// 판정하고, "오늘 남기는 날인가" 는 dayKey 에서 파생한다.
///
/// **난수를 쓰지 않는 이유**: 방명록은 사용자가 직접 쓴 글과 같은 목록(캡 50개)을 쓴다.
/// `randomElement()` 류로 판정하면 창을 여닫는 횟수만큼 확률이 굴러가, 하루에 여러 줄이
/// 쌓이고 사용자의 기록을 밀어낸다. dayKey 결정론이면 같은 날은 항상 같은 답이다.
enum MemoryHomeCompanionTrace {
    /// 오늘이 흔적을 남기는 날인가. 약 4일에 1번.
    ///
    /// `Hasher`·`hashValue` 는 **쓸 수 없다** — Swift 의 해시는 프로세스마다 시드가 달라서
    /// 앱을 재시작하면 같은 날의 답이 바뀐다. 그래서 스칼라 합이라는 시시한 식을 쓴다.
    nonisolated static func leavesTrace(dayKey: String) -> Bool {
        dayKey.unicodeScalars.reduce(0) { $0 + Int($1.value) } % 4 == 0
    }

    /// 그날의 기분을 따라간다. 우울한 날 "오늘 진짜 신났어!" 가 뜨면 §17(기분 → 반응)을
    /// 정면으로 배신하므로, 기분이 이 문구의 입력이다.
    static func body(mood: MemoryHomeMood?, _ l: L) -> String {
        switch mood {
        case .excited:
            return l.t("오늘 진짜 신났어! 또 놀자ㅋㅋ",
                       "Today was so much fun! Let's do it again.",
                       "今日はすごく楽しかった！また遊ぼう。")
        case .down:
            return l.t("아무 말 안 해도 돼. 옆에 있을게.",
                       "You don't have to say anything. I'll stay right here.",
                       "何も言わなくていいよ。そばにいるね。")
        case .annoyed:
            return l.t("잠깐 쉬자. 그러고 나서 같이 놀자.",
                       "Let's take a break first. Then let's play.",
                       "少し休もう。それから一緒に遊ぼう。")
        case .fluttering:
            return l.t("두근두근… 내일도 여기 있을게!",
                       "My heart's racing… I'll be here tomorrow too!",
                       "どきどき…明日もここにいるね！")
        case .calm:
            return l.t("오늘도 같이 있어서 좋았어.",
                       "It was nice being together today too.",
                       "今日も一緒でよかった。")
        case .none:
            return l.t("방문 찍고 감~ 발자국 남겨 둘게.",
                       "Stopped by! Leaving some pawprints behind.",
                       "遊びに来たよ〜 足あとを残しておくね。")
        }
    }
}
