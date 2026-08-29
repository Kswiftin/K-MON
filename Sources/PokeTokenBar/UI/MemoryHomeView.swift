import SwiftUI
import AppKit
import UniformTypeIdentifiers

enum MemoryHomeRoomTheme {
    static func tint(for theme: PokemonMemoryRoomTheme) -> Color {
        switch theme {
        case .blue: PokedoroTheme.blue
        case .mint: PokedoroTheme.mint
        case .yellow: PokedoroTheme.yellow
        case .red: PokedoroTheme.red
        }
    }
}

/// 방 스타일의 색과 이름. `MemoryHomeRoomTheme` 와 같은 이유로 뷰 밖에 둔다.
///
/// 테마(사용자가 고른 4색)와 스타일(해금하는 4종)은 다른 축이다 — 스타일 색은 바닥 띠에만
/// 쓰고 방 전체를 덮지 않는다. 덮으면 사용자가 고른 테마가 화면에서 사라진다.
extension MemoryHomeRoomStyle {
    static func tint(for style: MemoryHomeRoomStyle) -> Color {
        switch style {
        case .campus: PokedoroTheme.blue
        case .lovely: Color.pink
        case .retro: Color.orange
        case .nature: PokedoroTheme.mint
        }
    }

    func name(_ l: L) -> String {
        switch self {
        case .campus: l.t("캠퍼스", "Campus", "キャンパス")
        case .lovely: l.t("러블리", "Lovely", "ラブリー")
        case .retro: l.t("레트로", "Retro", "レトロ")
        case .nature: l.t("자연", "Nature", "ナチュラル")
        }
    }
}

/// 카드 아이콘·제목. `Kind` 에 케이스를 더하면 여기 `switch` 가 컴파일 에러로 알려 주고,
/// 테스트가 세 언어 문구까지 확인한다 — 뷰 안 `private` 함수였을 때는 둘 다 없었다.
enum MemoryHomeCardStyle {
    static func icon(_ milestone: PokemonMemoryMilestone) -> String {
        switch milestone.kind {
        case .firstMeeting: "person.2.fill"
        case .focusSessions: "timer"
        case .evolution: "arrow.triangle.2.circlepath"
        case .anniversary: "sparkles"
        case .togetherDays: "heart.circle.fill"
        case .homeVisits: "figure.wave"
        case .firstWinter: "snowflake"
        case .christmas: "gift.fill"
        }
    }

    static func title(_ milestone: PokemonMemoryMilestone, _ l: L) -> String {
        switch milestone.kind {
        case .firstMeeting: l.t("첫 만남", "First meeting", "最初の出会い")
        case .focusSessions(let count): l.t("집중 모험 \(count)회", "\(count) focus adventures", "集中冒険 \(count) 回")
        case .evolution: l.t("진화의 순간", "Evolution moment", "進化の瞬間")
        case .anniversary: l.t("첫 만남 1주년", "First-meeting anniversary", "最初の出会い 1周年")
        case .togetherDays(let days): l.t("함께한 \(days)일", "\(days) days together", "いっしょに \(days) 日")
        case .homeVisits(let count): l.t("방문 \(count)명 달성", "\(count) home visits", "訪問 \(count) 件達成")
        case .firstWinter: l.t("함께한 첫 겨울", "Our first winter", "はじめての冬")
        case .christmas: l.t("함께한 크리스마스", "Christmas together", "いっしょのクリスマス")
        }
    }
}

/// 뷰 안의 `private` 함수로 두면 세 언어 문구가 무테스트로 남는다 — `MemoryHomeRoomTheme` 와 같은
/// 이유로 파일 스코프의 순수 헬퍼로 뺀다. 종별 반응은 없다: 1000종 × 5기분은 헤더의 범위가 아니다.
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

/// 계절 이름·심볼. `MemoryHomeMoodStyle` 과 같은 이유로 뷰 밖에 둔다 — 뷰 안 `private` 함수면
/// 세 언어 문구가 무테스트로 남는다.
///
/// 색은 일부러 주지 않는다. 방에는 이미 사용자가 고른 테마 4색이 있고, 계절색으로 덮으면 사용자의
/// 선택을 뭉갠다 — 계절은 대문의 한 줄이지 방의 주인이 아니다.
enum MemoryHomeSeasonStyle {
    static func name(_ season: MemoryHomeSeason, _ l: L) -> String {
        switch season {
        case .spring: l.t("봄", "Spring", "春")
        case .summer: l.t("여름", "Summer", "夏")
        case .autumn: l.t("가을", "Autumn", "秋")
        case .winter: l.t("겨울", "Winter", "冬")
        }
    }

    static func symbol(_ season: MemoryHomeSeason) -> String {
        switch season {
        case .spring: "camera.macro"
        case .summer: "sun.max.fill"
        case .autumn: "leaf.fill"
        case .winter: "snowflake"
        }
    }
}

struct MemoryHomeStickerPhotoSheet: View {
    let speciesID: Int
    let shiny: Bool
    let language: L
    let album: PokemonMemoryAlbum
    @State private var caption = ""
    @State private var frame: StickerPhotoFrame = .heart
    @State private var background = "sunset"
    @State private var composition = "together"
    @State private var trainerStyle = "trainer"
    @State private var sprite: NSImage?
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 12) {
            StickerPhotoCanvas(sprite: sprite, caption: caption, frame: frame, background: background, composition: composition, trainerStyle: trainerStyle)
                .frame(width: 280, height: 220)
            TextField(language.t("캡션", "Caption", "キャプション"), text: $caption)
            Picker(language.t("프레임", "Frame", "フレーム"), selection: $frame) {
                ForEach(StickerPhotoFrame.allCases) { frame in
                    Label(frame.name(language), systemImage: frame.symbol).tag(frame)
                }
            }
            .pickerStyle(.menu)
            .accessibilityHint(language.t("스티커 사진의 장식 프레임을 고릅니다.", "Choose a decorative frame for the sticker photo.", "ステッカー写真の飾りフレームを選びます。"))
            Picker(language.t("배경", "Background", "背景"), selection: $background) { Text(language.t("노을", "Sunset", "夕焼け")).tag("sunset"); Text(language.t("숲", "Forest", "森")).tag("forest"); Text(language.t("스튜디오", "Studio", "スタジオ")).tag("studio") }.pickerStyle(.segmented)
            Picker(language.t("구도", "Composition", "構図"), selection: $composition) { Text(language.t("함께", "Together", "一緒")).tag("together"); Text(language.t("왼쪽", "Left", "左")).tag("left"); Text(language.t("오른쪽", "Right", "右")).tag("right") }.pickerStyle(.segmented)
            Picker(language.t("트레이너", "Trainer", "トレーナー"), selection: $trainerStyle) { Text(language.t("캐주얼", "Casual", "カジュアル")).tag("trainer"); Text(language.t("모험가", "Explorer", "冒険家")).tag("explorer") }.pickerStyle(.segmented)
            HStack { Button(language.t("닫기", "Close", "閉じる")) { dismiss() }; Spacer()
                Button(language.t("전시하기", "Add to gallery", "展示する")) { album.addPhoto(.init(speciesID: speciesID, isShiny: shiny, caption: caption, frame: frame.rawValue, background: background, composition: composition, trainerStyle: trainerStyle)) }.buttonStyle(.bordered)
                Button(language.t("PNG로 저장", "Save PNG", "PNGで保存")) { export() }.buttonStyle(.borderedProminent) }
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
        }.padding().task { sprite = await SpriteLoader.image(speciesID: speciesID, shiny: shiny) }
    }
    private func export() {
        let panel = NSSavePanel(); panel.title = language.t("스티커 사진 저장", "Save sticker photo", "ステッカー写真を保存")
        panel.nameFieldStringValue = "PokeTokenBar-Sticker.png"; panel.allowedContentTypes = [.png]
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let renderer = ImageRenderer(content: StickerPhotoCanvas(sprite: sprite, caption: caption, frame: frame, background: background, composition: composition, trainerStyle: trainerStyle).frame(width: 840, height: 660))
        guard let data = renderer.nsImage?.tiffRepresentation, let bitmap = NSBitmapImageRep(data: data), let png = bitmap.representation(using: .png, properties: [:]) else { error = language.t("이미지를 만들 수 없어요.", "Could not render image.", "画像を作成できません。"); return }
        do { try png.write(to: url, options: .atomic); NSWorkspace.shared.activateFileViewerSelecting([url]) }
        catch { self.error = error.localizedDescription }
    }
}

struct MemoryHomeSeasonRecapSheet: View {
    let recap: MemoryHomeSeasonRecap
    let language: L
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text(language.t("계절 결산", "Season recap", "季節のまとめ")).font(.headline); Spacer(); Button(language.t("닫기", "Close", "閉じる")) { dismiss() } }
            Text(MemoryHomeSeasonStyle.name(recap.season, language)).font(.title2.weight(.bold))
            Text(language.t("이번 계절에 만난 동행 \(recap.companionsMet)마리", "\(recap.companionsMet) companions met this season", "今季出会った相棒 \(recap.companionsMet) 匹"))
            // 집중만 **통산**이다 — 저장 구조에 세션 날짜가 없어 계절로 좁힐 수 없다. 계절 라벨
            // 아래 통산값을 그냥 두면 결산이 거짓말을 하므로, 라벨에 그 사실을 적는다.
            Text(language.t("이번 계절 기억 \(recap.memoryCount)개 · 집중 통산 \(recap.focusSessions)회", "\(recap.memoryCount) memories this season · \(recap.focusSessions) focus sessions all time", "今季の思い出 \(recap.memoryCount) 件・集中は通算 \(recap.focusSessions) 回"))
            if let mood = recap.mostChosenMood { Text(language.t("가장 많이 고른 기분: ", "Most chosen mood: ", "もっとも選んだ気分: ") + MemoryHomeMoodStyle.name(mood, language)) }
            Text(language.t("기억은 최대 200개까지만 보관됩니다.", "Memories are retained up to 200 entries.", "思い出は最大200件まで保管されます。")) .font(.caption).foregroundStyle(.secondary)
        }.padding().frame(minWidth: 320)
    }
}

/// 기획서 §25 — 한 해를 한 장으로 되돌려 주고 "내년에도 같이 놀자." 로 끝난다.
///
/// 문장 순서가 기획서를 따른다(만난 동행 → 가장 오래 함께한 친구 → 함께한 날 → 기억·사진 →
/// 대표 BGM). 숫자 나열이 목적이 아니라 회고가 목적이라서다.
///
/// 표시 이름은 **화면이** 넣는다 — `MemoryHomeYearRecap` 은 id 만 안다.
struct MemoryHomeYearRecapSheet: View {
    let recap: MemoryHomeYearRecap
    let topCompanionName: String?
    let language: L
    @Environment(\.dismiss) private var dismiss

    /// 기록이 하나도 없으면 숫자 0을 늘어놓지 않는다 — 설치 첫날 사용자에게 "0마리를
    /// 만났습니다" 는 회고가 아니라 고장으로 읽힌다.
    private var isEmpty: Bool { recap.memoryCount == 0 && recap.companionsMet == 0 && recap.photoCount == 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(language.t("연말 결산", "Year in review", "一年のまとめ")).font(.headline)
                Spacer()
                Button(language.t("닫기", "Close", "閉じる")) { dismiss() }
            }
            Text(verbatim: "\(recap.year)").font(.title.weight(.bold)).foregroundStyle(PokedoroTheme.red)
            if isEmpty {
                Text(language.t("아직 돌아볼 기록이 없어요. 함께 시간을 쌓아 볼까요?",
                                "Nothing to look back on yet. Let's start making memories.",
                                "まだ振り返る記録がありません。これから思い出を作りましょう。"))
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                Text(language.t("올해 \(recap.companionsMet)마리의 동행을 만났어요.",
                                "You met \(recap.companionsMet) companions this year.",
                                "今年は \(recap.companionsMet) 匹の相棒と出会いました。"))
                    .font(.title3.weight(.semibold))
                if let topCompanionName {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(language.t("가장 많은 시간을 함께한 동행", "Companion you spent the most time with", "いちばん長く一緒にいた相棒"))
                            .font(.caption).foregroundStyle(.secondary)
                        Text(topCompanionName).font(.title3.weight(.bold))
                        Text(language.t("함께한 \(recap.topCompanionDays)일", "\(recap.topCompanionDays) days together", "いっしょに \(recap.topCompanionDays) 日"))
                            .font(.callout)
                    }
                }
                Text(language.t("올해의 기억 \(recap.memoryCount)개 · 사진 \(recap.photoCount)장",
                                "\(recap.memoryCount) memories · \(recap.photoCount) photos",
                                "今年の思い出 \(recap.memoryCount) 件・写真 \(recap.photoCount) 枚"))
                Label(MemoryHomeJukebox.name(recap.jukeboxTrack, language), systemImage: MemoryHomeJukebox.symbol(recap.jukeboxTrack))
                    .font(.callout)
                    .accessibilityLabel(language.t("대표 BGM", "Home BGM", "ホームのBGM"))
                Text(language.t("내년에도 같이 놀자.", "Let's play together again next year.", "来年もいっしょに遊ぼう。"))
                    .font(.headline).foregroundStyle(PokedoroTheme.blue).padding(.top, 4)
            }
            // 두 캡을 밝힌다. 밝히지 않으면 오래된 해의 결산이 조용히 과소집계로 읽힌다
            // (계절 결산 시트가 기억 캡을 적는 것과 같은 이유다).
            Text(language.t("기억은 200개, 사진은 60장까지만 보관됩니다.",
                            "Up to 200 memories and 60 photos are retained.",
                            "思い出は200件、写真は60枚まで保管されます。"))
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding().frame(minWidth: 320)
    }
}

enum StickerPhotoFrame: String, CaseIterable, Identifiable {
    case heart, star, ribbon, flower
    var id: String { rawValue }
    var symbol: String { switch self { case .heart: "heart.fill"; case .star: "star.fill"; case .ribbon: "ribbon"; case .flower: "camera.macro" } }
    func name(_ l: L) -> String { switch self { case .heart: l.t("하트", "Heart", "ハート"); case .star: l.t("별", "Star", "星"); case .ribbon: l.t("리본", "Ribbon", "リボン"); case .flower: l.t("꽃", "Flower", "花") } }
    var marks: [String] { switch self { case .heart: ["♥", "♡", "♥"]; case .star: ["★", "✦", "★"]; case .ribbon: ["🎀", "✧", "🎀"]; case .flower: ["✿", "❀", "✿"] } }
}

struct StickerPhotoCanvas: View {
    let sprite: NSImage?
    let caption: String
    let frame: StickerPhotoFrame
    let background: String
    let composition: String
    let trainerStyle: String
    var body: some View {
        ZStack { RoundedRectangle(cornerRadius: 22).fill(background == "forest" ? PokedoroTheme.mint.opacity(0.52) : background == "studio" ? Color.white.opacity(0.78) : PokedoroTheme.yellow.opacity(0.52))
            HStack(spacing: 12) { if composition != "right" { trainer }; if let sprite { Image(nsImage: sprite).resizable().interpolation(.none).scaledToFit().frame(height: 140) } else { Image(systemName: "sparkles").font(.system(size: 72)).foregroundStyle(PokedoroTheme.red) }; if composition == "right" { trainer } }
            VStack { Spacer(); Text(caption.isEmpty ? "POKÉDORO" : caption).font(.headline).lineLimit(2).padding(.bottom, 20) }
            HStack { Text(frame.marks[0]); Spacer(); Text(frame.marks[1]); Spacer(); Text(frame.marks[2]) }
                .font(.title2).foregroundStyle(PokedoroTheme.red.opacity(0.82)).padding(16) }
    }
    private var trainer: some View { Image(systemName: trainerStyle == "explorer" ? "figure.hiking" : "person.fill").font(.system(size: 64)).foregroundStyle(PokedoroTheme.blue) }
}
