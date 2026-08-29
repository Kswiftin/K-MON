import Foundation

/// 기획서 §5 "미니룸 안에 실제 포켓몬이 생활함" — 미니룸 한 줄의 **유일한** 출처다.
///
/// 저장 필드가 하나도 없다. 종 번호·놓인 가구·그날 기분·달력 계절만 읽어 파생한다(POKÉLOG·
/// 일기·계절이 같은 원칙을 쓴다). 그래서 세이브 마이그레이션이 필요 없고, 기존 사용자의
/// 방도 업데이트 즉시 자기 종의 문장을 갖는다.
///
/// 뷰 안 `private` 함수로 두지 않는 이유는 `MemoryHomeMoodStyle` 과 같다 — 뷰 안이면 세 언어
/// 문구가 무테스트로 남는다. 실제로 그렇게 돼 있던 동안 이 문구는 가구 3종만 보는 3줄이었고,
/// 종을 아예 읽지 않아 누구의 방이든 같은 문장이 나왔다.
enum MemoryHomeRoomLife {
    /// 짝 표의 키. 테스트가 표를 직접 읽어 전수 검증하므로 `internal` 이다 — 표에 줄을 더하고
    /// 테스트 배열에 안 더해서 새 짝이 무테스트로 남는 부류를 구조로 막는다.
    struct Pair: Hashable, Sendable {
        let speciesID: Int
        let item: ItemKind
    }

    /// 기획서가 든 다섯 짝(피카츄+모니터, 잠만보+침대, 고라파덕+거울, 고오스+TV, 꼬부기+물)을
    /// **이 앱에 있는 가구 12종**으로 옮긴 것 + 같은 결의 셋. CRT 컴퓨터·욕조·어항은 가구
    /// 목록에 없으므로 레트로 TV·화장대·화분이 그 자리를 받는다.
    static let pairedSpecies: Set<Pair> = Set(pairLines.keys)

    /// 좁은 조건이 먼저 이긴다: **종×가구 → 가구 → 기분 → 계절.**
    ///
    /// `decor` 는 배열 순서를 그대로 쓴다 — 짝은 배열 전체에서 먼저 찾고, 없으면 첫 가구를
    /// 쓴다. 같은 상태면 같은 문장이 나온다(방을 열 때마다 문장이 바뀌면 방이 불안해 보인다).
    static func line(speciesID: Int, decor: [ItemKind], mood: MemoryHomeMood?,
                     season: MemoryHomeSeason, companion: String, _ l: L) -> String {
        if let paired = decor.lazy.compactMap({ pairLines[Pair(speciesID: speciesID, item: $0)] }).first {
            return l.t(paired.ko, paired.en, paired.ja)
        }
        if let item = decor.first(where: { $0.roomReaction != nil }) {
            return furnitureLine(item, l)
        }
        if let mood { return MemoryHomeMoodStyle.reaction(mood, companion: companion, l) }
        return seasonLine(season, companion: companion, l)
    }

    /// 가구 단독. 아이템 12개마다 문장을 쓰는 대신 이미 있는 `ItemKind.roomReaction` 배치
    /// 3종(`onTop`/`under`/`beside`)에 이름을 끼운다 — 가구를 더해도 문구가 자동으로 생긴다.
    private static func furnitureLine(_ item: ItemKind, _ l: L) -> String {
        let name = l.itemName(item)
        switch item.roomReaction {
        case "onTop":
            return l.t("\(name) 위에 올라가 몸을 말고 있어요.",
                       "Curled up on top of the \(name).",
                       "\(name)の上で丸くなっています。")
        case "under":
            return l.t("\(name) 불빛 아래에서 꾸벅꾸벅 졸고 있어요.",
                       "Dozing off under the \(name)'s glow.",
                       "\(name)の明かりの下でうとうとしています。")
        default:
            return l.t("\(name) 옆에 자리를 잡고 앉았어요.",
                       "Settled in right beside the \(name).",
                       "\(name)のそばに座り込みました。")
        }
    }

    /// 가구도 기분도 없는 빈 방. 계절은 대문의 한 줄이라 방 색을 덮지 않는다(같은 이유로
    /// `MemoryHomeSeasonStyle` 도 색을 주지 않는다).
    private static func seasonLine(_ season: MemoryHomeSeason, companion: String, _ l: L) -> String {
        switch season {
        case .spring:
            return l.t("\(companion)이 창밖 벚꽃을 구경하고 있어요.",
                       "\(companion) is watching the spring blossoms outside.",
                       "\(companion)が窓の外の桜を眺めています。")
        case .summer:
            return l.t("\(companion)이 시원한 바닥을 찾아 뒹굴고 있어요.",
                       "\(companion) is rolling around hunting for a cool spot on the floor.",
                       "\(companion)が涼しい床を探して転がっています。")
        case .autumn:
            return l.t("\(companion)이 창틈으로 들어온 낙엽을 굴리고 있어요.",
                       "\(companion) is batting around a leaf that blew in.",
                       "\(companion)が窓から入った落ち葉を転がしています。")
        case .winter:
            return l.t("\(companion)이 첫눈을 기다리며 창가에 붙어 있어요.",
                       "\(companion) is pressed against the window waiting for the first snow.",
                       "\(companion)が初雪を待って窓辺にはりついています。")
        }
    }

    private struct PairLine {
        let ko: String
        let en: String
        let ja: String
    }

    /// 종별 문구는 이름을 끼우지 않는다 — "잠만보가 침대를 차지했다" 는 이미 그 종의 이야기라
    /// 이름을 또 부르면 문장이 늘어진다. 대신 방에 있는 물건을 구체적으로 말한다.
    private static let pairLines: [Pair: PairLine] = [
        // 잠만보 + 침대 → 침대를 통째로 차지함 (기획서 §5)
        Pair(speciesID: 143, item: .roomBed): .init(
            ko: "침대를 통째로 차지하고 코를 골고 있어요.",
            en: "Has claimed the entire bed and is snoring away.",
            ja: "ベッドを丸ごと占領していびきをかいています。"),
        // 피카츄 + 레트로 TV → 모니터 위에서 잠듦 (기획서의 CRT 컴퓨터 자리)
        Pair(speciesID: 25, item: .retroTV): .init(
            ko: "따뜻한 TV 위에 올라가 잠들었어요.",
            en: "Fell asleep on top of the warm TV.",
            ja: "あたたかいテレビの上で寝てしまいました。"),
        // 고오스 + TV → 가끔 화면에서 튀어나옴 (기획서 §5)
        Pair(speciesID: 92, item: .retroTV): .init(
            ko: "TV 화면에서 불쑥 튀어나왔다 다시 들어갔어요.",
            en: "Popped out of the TV screen and slipped back in.",
            ja: "テレビの画面から飛び出して、また戻っていきました。"),
        // 고라파덕 + 화장대 → 머리를 감싸 쥠 (기획서의 욕조 자리 — 거울이 더 이 종답다)
        Pair(speciesID: 54, item: .lovelyVanity): .init(
            ko: "거울 속 자기를 보다가 또 머리를 감싸 쥐었어요.",
            en: "Caught its own reflection and grabbed its head again.",
            ja: "鏡の自分を見て、また頭を抱えてしまいました。"),
        // 꼬부기 + 화분 → 물을 계속 봄 (기획서의 어항 자리)
        Pair(speciesID: 7, item: .naturePlant): .init(
            ko: "화분에 물을 주다 자기가 더 흠뻑 젖었어요.",
            en: "Watered the plant and ended up soaking itself instead.",
            ja: "鉢に水をやって、自分のほうがびしょ濡れになりました。"),
        // 이브이 + 소파 → 진화를 고르지 않은 채 그냥 잠 (기획서 §19 의 정서)
        Pair(speciesID: 133, item: .lovelySofa): .init(
            ko: "소파 한가운데 동그랗게 말려 잠들었어요.",
            en: "Curled into a ball right in the middle of the sofa.",
            ja: "ソファの真ん中で丸くなって寝ています。"),
        // 나옹 + 벤치 → 낮잠 (기획서 §2 문방구 앞 나옹)
        Pair(speciesID: 52, item: .natureBench): .init(
            ko: "벤치를 독차지하고 낮잠을 자고 있어요.",
            en: "Took over the whole bench for a nap.",
            ja: "ベンチを独占してお昼寝しています。"),
        // 파이리 + 오락기 → 화면에서 눈을 못 뗌 (기획서 §2 오락실)
        Pair(speciesID: 4, item: .retroArcade): .init(
            ko: "오락기 화면에서 눈을 못 떼고 있어요.",
            en: "Cannot take its eyes off the arcade screen.",
            ja: "ゲーム機の画面から目を離せません。"),
    ]
}
