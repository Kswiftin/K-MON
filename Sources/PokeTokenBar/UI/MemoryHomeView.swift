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

    var name: String {
        switch self {
        case .campus: "캠퍼스"
        case .lovely: "러블리"
        case .retro: "레트로"
        case .nature: "자연"
        }
    }
}

/// 카드 아이콘·제목. `Kind` 에 케이스를 더하면 여기 `switch` 가 컴파일 에러로 알려 주고,
/// 테스트가 문구까지 확인한다 — 뷰 안 `private` 함수였을 때는 둘 다 없었다.
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
        case .newYear: "sunrise.fill"
        case .allFourSeasons: "circle.hexagongrid.fill"
        case .memoryStreak: "flame.fill"
        }
    }

    static func title(_ milestone: PokemonMemoryMilestone) -> String {
        switch milestone.kind {
        case .firstMeeting: "첫 만남"
        case .focusSessions(let count): "집중 모험 \(count)회"
        case .evolution: "진화의 순간"
        case .anniversary: "첫 만남 1주년"
        case .togetherDays(let days): "함께한 \(days)일"
        case .homeVisits(let count): "방문 \(count)명 달성"
        case .firstWinter: "함께한 첫 겨울"
        case .christmas: "함께한 크리스마스"
        case .newYear: "함께 맞은 새해"
        case .allFourSeasons: "사계절을 함께 보냈어요"
        case .memoryStreak(let days): "\(days)일 연속 기록"
        }
    }
}

/// 계절 이름·심볼. `MemoryHomeMoodStyle` 과 같은 이유로 뷰 밖에 둔다 — 뷰 안 `private` 함수면
/// 문구가 무테스트로 남는다.
///
/// 색은 일부러 주지 않는다. 방에는 이미 사용자가 고른 테마 4색이 있고, 계절색으로 덮으면 사용자의
/// 선택을 뭉갠다 — 계절은 대문의 한 줄이지 방의 주인이 아니다.
/// 창밖 시각의 이름. `MemoryHomeSeasonStyle` 의 형제이며 같은 이유로 뷰 밖에 산다 — 뷰 안
/// `private` 이면 문구가 무테스트로 남는다. VoiceOver 가 읽는 유일한 창 설명이라
/// 비어 있으면 창이 스크린리더에게는 존재하지 않는 것과 같다.
enum MemoryHomeTimeOfDayStyle {
    static func name(_ timeOfDay: MemoryHomeTimeOfDay) -> String {
        switch timeOfDay {
        case .morning: "아침"
        case .day: "낮"
        case .night: "밤"
        }
    }
}

enum MemoryHomeSeasonStyle {
    static func name(_ season: MemoryHomeSeason) -> String {
        switch season {
        case .spring: "봄"
        case .summer: "여름"
        case .autumn: "가을"
        case .winter: "겨울"
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
            TextField("캡션", text: $caption)
            Picker("프레임", selection: $frame) {
                ForEach(StickerPhotoFrame.allCases) { frame in
                    Label(frame.name, systemImage: frame.symbol).tag(frame)
                }
            }
            .pickerStyle(.menu)
            .accessibilityHint("스티커 사진의 장식 프레임을 고릅니다.")
            Picker("배경", selection: $background) { Text("노을").tag("sunset"); Text("숲").tag("forest"); Text("스튜디오").tag("studio") }.pickerStyle(.segmented)
            Picker("구도", selection: $composition) { Text("함께").tag("together"); Text("왼쪽").tag("left"); Text("오른쪽").tag("right") }.pickerStyle(.segmented)
            Picker("트레이너", selection: $trainerStyle) { Text("캐주얼").tag("trainer"); Text("모험가").tag("explorer") }.pickerStyle(.segmented)
            HStack { Button("닫기") { dismiss() }; Spacer()
                Button("전시하기") { album.addPhoto(.init(speciesID: speciesID, isShiny: shiny, caption: caption, frame: frame.rawValue, background: background, composition: composition, trainerStyle: trainerStyle)) }.buttonStyle(.bordered)
                Button("PNG로 저장") { export() }.buttonStyle(.borderedProminent) }
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
        }.padding().task { sprite = await SpriteLoader.image(speciesID: speciesID, shiny: shiny) }
    }
    private func export() {
        let panel = NSSavePanel(); panel.title = "스티커 사진 저장"
        panel.nameFieldStringValue = "PokeTokenBar-Sticker.png"; panel.allowedContentTypes = [.png]
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let renderer = ImageRenderer(content: StickerPhotoCanvas(sprite: sprite, caption: caption, frame: frame, background: background, composition: composition, trainerStyle: trainerStyle).frame(width: 840, height: 660))
        guard let data = renderer.nsImage?.tiffRepresentation, let bitmap = NSBitmapImageRep(data: data), let png = bitmap.representation(using: .png, properties: [:]) else { error = "이미지를 만들 수 없어요."; return }
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
            HStack { Text("계절 결산").font(.headline); Spacer(); Button("닫기") { dismiss() } }
            Text(MemoryHomeSeasonStyle.name(recap.season)).font(.title2.weight(.bold))
            Text("이번 계절에 만난 동행 \(recap.companionsMet)마리")
            // 집중만 **통산**이다 — 저장 구조에 세션 날짜가 없어 계절로 좁힐 수 없다. 계절 라벨
            // 아래 통산값을 그냥 두면 결산이 거짓말을 하므로, 라벨에 그 사실을 적는다.
            Text("이번 계절 기억 \(recap.memoryCount)개 · 집중 통산 \(recap.focusSessions)회")
            if let mood = recap.mostChosenMood { Text("가장 많이 고른 기분: " + MemoryHomeMoodStyle.name(mood)) }
            Text("기억은 최대 200개까지만 보관됩니다.") .font(.caption).foregroundStyle(.secondary)
        }.padding().frame(minWidth: 320)
    }
}

/// 기획서 §25 — 한 해를 한 장으로 되돌려 주고 "내년에도 같이 놀자." 로 끝난다.
///
/// 문장 순서가 기획서를 따른다(만난 동행 → 가장 오래 함께한 친구 → 함께한 날 → 기억·사진).
/// 숫자 나열이 목적이 아니라 회고가 목적이라서다.
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
                Text("연말 결산").font(.headline)
                Spacer()
                Button("닫기") { dismiss() }
            }
            Text(verbatim: "\(recap.year)").font(.title.weight(.bold)).foregroundStyle(PokedoroTheme.red)
            if isEmpty {
                Text("아직 돌아볼 기록이 없어요. 함께 시간을 쌓아 볼까요?")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                Text("올해 \(recap.companionsMet)마리의 동행을 만났어요.")
                    .font(.title3.weight(.semibold))
                if let topCompanionName {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("가장 많은 시간을 함께한 동행")
                            .font(.caption).foregroundStyle(.secondary)
                        Text(topCompanionName).font(.title3.weight(.bold))
                        Text("함께한 \(recap.topCompanionDays)일")
                            .font(.callout)
                    }
                }
                Text("올해의 기억 \(recap.memoryCount)개 · 사진 \(recap.photoCount)장")
                Text("내년에도 같이 놀자.")
                    .font(.headline).foregroundStyle(PokedoroTheme.blue).padding(.top, 4)
            }
            // 두 캡을 밝힌다. 밝히지 않으면 오래된 해의 결산이 조용히 과소집계로 읽힌다
            // (계절 결산 시트가 기억 캡을 적는 것과 같은 이유다).
            Text("기억은 200개, 사진은 60장까지만 보관됩니다.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding().frame(minWidth: 320)
    }
}

enum StickerPhotoFrame: String, CaseIterable, Identifiable {
    case heart, star, ribbon, flower
    var id: String { rawValue }
    var symbol: String { switch self { case .heart: "heart.fill"; case .star: "star.fill"; case .ribbon: "ribbon"; case .flower: "camera.macro" } }
    var name: String { switch self { case .heart: "하트"; case .star: "별"; case .ribbon: "리본"; case .flower: "꽃" } }
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
