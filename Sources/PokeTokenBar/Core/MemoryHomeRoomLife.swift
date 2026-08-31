import Foundation

/// 기획서 §5 "미니룸 안에 실제 포켓몬이 생활함" — 미니룸 한 줄의 **유일한** 출처다.
///
/// 저장 필드가 하나도 없다. 종 번호·놓인 가구·같이 사는 동행·그날 기분·달력·시계만 읽어
/// 파생한다(POKÉLOG·일기·계절이 같은 원칙을 쓴다). 그래서 세이브 마이그레이션이 필요 없고,
/// 기존 사용자의 방도 업데이트 즉시 자기 종의 문장을 갖는다.
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
    /// **이 앱에 있는 가구 12종**으로 옮긴 것 + 같은 결의 열하나. CRT 컴퓨터·욕조·어항은 가구
    /// 목록에 없으므로 레트로 TV·화장대·화분이 그 자리를 받는다.
    static let pairedSpecies: Set<Pair> = Set(pairLines.keys)

    /// 좁은 조건이 먼저 이긴다: **종×가구 → 룸메이트 → 가구 → 기분 → 하루(아침·밤) → 계절.**
    ///
    /// 룸메이트가 가구보다 앞인 이유: "둘이 같이 있다" 는 이 방에만 있는 사실이고, 가구 단독
    /// 문구는 같은 가구를 놓은 모든 방이 공유한다. 좁은 것이 먼저라는 같은 규칙이다.
    ///
    /// `decor` 는 배열 순서를 그대로 쓴다 — 짝은 배열 전체에서 먼저 찾고, 없으면 첫 가구를
    /// 쓴다. 같은 상태·같은 시각이면 같은 문장이 나온다(방을 열 때마다 문장이 바뀌면 방이
    /// 불안해 보인다). 그래서 `timeOfDay` 를 **인자로 받는다** — 함수 안에서 시계를 읽으면
    /// 테스트가 실행 시각에 따라 다른 가지를 밟아, 밤에 돌린 CI 만 빨개진다.
    static func line(speciesID: Int, decor: [ItemKind], roommates: [String] = [],
                     mood: MemoryHomeMood?, season: MemoryHomeSeason,
                     timeOfDay: MemoryHomeTimeOfDay = .day, companion: String, _ l: L) -> String {
        if let paired = decor.lazy.compactMap({ pairLines[Pair(speciesID: speciesID, item: $0)] }).first {
            return l.t(paired.ko, paired.en, paired.ja)
        }
        if let roommate = roommates.first {
            return roommateLine(roommate, others: roommates.count - 1, timeOfDay: timeOfDay,
                                companion: companion, l)
        }
        if let item = decor.first(where: { $0.roomReaction != nil }) {
            return furnitureLine(item, l)
        }
        if let mood { return MemoryHomeMoodStyle.reaction(mood, companion: companion, l) }
        return idleLine(season: season, timeOfDay: timeOfDay, companion: companion, l)
    }

    /// 같이 사는 동행이 있으면 방의 주인공은 물건이 아니라 관계다.
    ///
    /// 이름 뒤에 "와/과" 를 붙이지 않는다 — 받침에 따라 갈리는 조사인데 동행 이름은 사용자가
    /// 짓는 값이라 받침을 알 수 없다(별명이 이모지 하나여도 이 문장은 성립해야 한다).
    private static func roommateLine(_ roommate: String, others: Int,
                                     timeOfDay: MemoryHomeTimeOfDay, companion: String,
                                     _ l: L) -> String {
        let company = others > 0
            ? l.t("\(roommate) 외 \(others)마리", "\(roommate) and \(others) more", "\(roommate) ほか \(others) 匹")
            : roommate
        switch timeOfDay {
        case .morning:
            return l.t("\(companion)이 \(company) 곁에서 같이 부스스 일어났어요.",
                       "\(companion) woke up bleary-eyed next to \(company).",
                       "\(companion)が \(company) のそばで一緒に寝ぼけまなこで起きました。")
        case .day:
            return l.t("\(companion)이 \(company) 옆에 딱 붙어 뒹굴고 있어요.",
                       "\(companion) is glued to \(company)'s side, rolling around.",
                       "\(companion)が \(company) にぴったりくっついて転がっています。")
        case .night:
            return l.t("\(companion)이 \(company) 곁에 몸을 붙이고 잠들었어요.",
                       "\(companion) fell asleep pressed up against \(company).",
                       "\(companion)が \(company) に体を寄せて眠りました。")
        }
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

    /// 가구도 룸메이트도 기분도 없는 빈 방. 아침과 밤은 **계절보다 방을 잘 설명한다** — 창밖이
    /// 벚꽃이든 낙엽이든, 갓 깨어난 방과 잠든 방은 다르다. 그래서 그 둘이 계절을 덮고, 낮에만
    /// 계절이 나온다. 세 가지가 모두 살아 있어서 어느 하나도 죽은 가지가 아니다.
    ///
    /// 계절은 여기서도 방 색을 덮지 않는다(같은 이유로 `MemoryHomeSeasonStyle` 도 색을 주지 않는다).
    private static func idleLine(season: MemoryHomeSeason, timeOfDay: MemoryHomeTimeOfDay,
                                 companion: String, _ l: L) -> String {
        switch timeOfDay {
        case .morning:
            return l.t("\(companion)이 아침 햇살에 눈을 비비며 기지개를 켜고 있어요.",
                       "\(companion) is stretching and rubbing its eyes in the morning light.",
                       "\(companion)が朝の光の中で目をこすりながら伸びをしています。")
        case .night:
            return l.t("\(companion)이 불을 끈 방에서 새근새근 잠들었어요.",
                       "\(companion) is fast asleep in the darkened room.",
                       "\(companion)が明かりを消した部屋ですやすや眠っています。")
        case .day:
            return seasonLine(season, companion: companion, l)
        }
    }

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
    ///
    /// 가구 12종이 **전부** 최소 한 짝을 갖는다. 한 종류라도 비면 그 가구를 산 사용자만 계속
    /// 일반 문구를 보게 되는데, 화면에서는 "내 가구만 반응이 없다" 로 읽힌다.
    private static let pairLines: [Pair: PairLine] = [
        // 잠만보 + 침대 → 침대를 통째로 차지함 (기획서 §5)
        Pair(speciesID: 143, item: .roomBed): .init(
            ko: "침대를 통째로 차지하고 코를 골고 있어요.",
            en: "Has claimed the entire bed and is snoring away.",
            ja: "ベッドを丸ごと占領していびきをかいています。"),
        // 캐이시 + 침대 → 하루 대부분을 잠으로 보내는 종
        Pair(speciesID: 63, item: .roomBed): .init(
            ko: "침대에 눕자마자 또 잠들었어요. 오늘도 대부분 자고 있어요.",
            en: "Fell asleep the moment it hit the bed. Asleep most of today, again.",
            ja: "ベッドに横になった瞬間また眠りました。今日もほとんど寝ています。"),
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
        // 메타몽 + 화장대 → 거울 속 모습을 따라 변신해 봄
        Pair(speciesID: 132, item: .lovelyVanity): .init(
            ko: "거울에 비친 모습을 따라 변신해 보다가 그만뒀어요.",
            en: "Tried transforming into its own reflection, then gave up.",
            ja: "鏡に映った姿に変身しようとして、やめました。"),
        // 꼬부기 + 화분 → 물을 계속 봄 (기획서의 어항 자리)
        Pair(speciesID: 7, item: .naturePlant): .init(
            ko: "화분에 물을 주다 자기가 더 흠뻑 젖었어요.",
            en: "Watered the plant and ended up soaking itself instead.",
            ja: "鉢に水をやって、自分のほうがびしょ濡れになりました。"),
        // 이상해씨 + 화분 → 등의 씨앗과 나란히 햇볕을 쬠
        Pair(speciesID: 1, item: .naturePlant): .init(
            ko: "화분 옆에 등을 대고 나란히 햇볕을 쬐고 있어요.",
            en: "Sunning its bulb right alongside the potted plant.",
            ja: "鉢のとなりで背中を向けて一緒に日なたぼっこしています。"),
        // 디그다 + 화분 → 흙에서 불쑥 올라옴
        Pair(speciesID: 50, item: .naturePlant): .init(
            ko: "화분 흙에서 불쑥 올라왔다가 다시 쏙 들어갔어요.",
            en: "Popped up out of the plant's soil and burrowed straight back down.",
            ja: "鉢の土からひょっこり出て、また潜っていきました。"),
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
        // 푸린 + 라디오 → 흘러나오는 노래를 따라 부름
        Pair(speciesID: 39, item: .retroRadio): .init(
            ko: "라디오에서 나오는 노래를 따라 부르다 스스로 잠들었어요.",
            en: "Sang along with the radio until it put itself to sleep.",
            ja: "ラジオの歌に合わせて歌ううちに、自分で眠ってしまいました。"),
        // 야돈 + 테이블 → 테이블 위에서 아무 생각 없이 있음
        Pair(speciesID: 79, item: .roomTable): .init(
            ko: "테이블 위에 턱을 올린 채 아무 생각도 하지 않고 있어요.",
            en: "Resting its chin on the table, thinking about absolutely nothing.",
            ja: "テーブルにあごをのせて、なにも考えていません。"),
        // 코일 + 전등 → 전기에 이끌려 조명에 붙음
        Pair(speciesID: 81, item: .roomLamp): .init(
            ko: "전등에 딱 붙어 전기가 흐르는 소리를 내고 있어요.",
            en: "Stuck to the lamp, humming along with the current.",
            ja: "ランプにぴったりくっついて、電気の音を立てています。"),
        // 식스테일 + 하트 조명 → 꼬리를 펼쳐 빛을 받음
        Pair(speciesID: 37, item: .lovelyHeartLamp): .init(
            ko: "하트 조명 아래 꼬리 여섯 개를 활짝 펼쳐 두었어요.",
            en: "Fanned out all six tails under the heart lamp.",
            ja: "ハートの照明の下で、六本の尻尾をぱっと広げています。"),
        // 버터플 + 랜턴 → 불빛 주위를 맴돔
        Pair(speciesID: 12, item: .natureLantern): .init(
            ko: "랜턴 불빛 주위를 천천히 맴돌고 있어요.",
            en: "Circling slowly around the lantern's glow.",
            ja: "ランタンの明かりのまわりをゆっくり回っています。"),
    ]
}

/// 기분별 이모지·이름·반응 문구. **Core 에 둔다** — 이 파일(`roomLine`)이 반응 문구를 부르므로
/// 뷰에 두면 코어가 UI 파일에 기대고, 앱 없이 코어만 세우는 밸런스 시뮬레이터가 컴파일되지 않는다.
/// 뷰 안 `private` 함수로 두지 않는 이유는 세 언어 문구가 무테스트로 남기 때문이다. 종별 반응은 없다: 1000종 × 5기분은 헤더의 범위가 아니다.
enum MemoryHomeMoodStyle {
    static func emoji(_ mood: MemoryHomeMood) -> String {
        switch mood {
        case .excited: "😊"
        case .calm: "😌"
        case .down: "😢"
        case .annoyed: "😡"
        case .fluttering: "💗"
        }
    }

    static func name(_ mood: MemoryHomeMood, _ l: L) -> String {
        switch mood {
        case .excited: l.t("신남", "Excited", "うきうき")
        case .calm: l.t("평범", "Calm", "ふつう")
        case .down: l.t("우울", "Down", "しずんだ")
        case .annoyed: l.t("짜증", "Annoyed", "いらいら")
        case .fluttering: l.t("설렘", "Fluttering", "どきどき")
        }
    }

    static func reaction(_ mood: MemoryHomeMood, companion: String, _ l: L) -> String {
        switch mood {
        case .excited: l.t("\(companion)도 꼬리를 흔들며 같이 신났어요.",
                           "\(companion) is bouncing around with you.",
                           "\(companion)も一緒にうきうきしています。")
        case .calm: l.t("\(companion)이 옆에서 조용히 낮잠을 자요.",
                        "\(companion) is dozing quietly beside you.",
                        "\(companion)がそばで静かに眠っています。")
        case .down: l.t("\(companion)이 말없이 옆에 앉았어요.",
                        "\(companion) sat down next to you without a word.",
                        "\(companion)が何も言わずに隣に座りました。")
        case .annoyed: l.t("\(companion)도 같이 머리를 감싸 쥐었어요.",
                           "\(companion) is holding its head right along with you.",
                           "\(companion)も一緒に頭を抱えています。")
        case .fluttering: l.t("\(companion)이 하트를 띄웠어요.",
                              "\(companion) let out a little heart.",
                              "\(companion)がハートを浮かべました。")
        }
    }
}

