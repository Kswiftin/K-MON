import SwiftUI
import AppKit

/// 마을에 서 있는 나. 변신 중이면 그 종, 아니면 트레이너 도트다.
///
/// **HOME 512 렌더를 쓴다**(`highResolution: true`) — 플로팅 펫과 같은 에셋이다. 96px 정적
/// PNG 를 쓰던 동안 같은 앱에 화질이 두 벌이었고, 아이소메트릭 지형 위에서는 도트가 종이
/// 스티커처럼 붙어 보였다. HOME 이 없는 종은 `SpriteLoader` 가 96px 로 조용히 폴백한다.
///
/// 보간을 끄지 않는다(`.interpolation(.high)`). 도트는 정수 배 확대라 `.none` 이 맞았지만,
/// 512 렌더를 44pt 로 **줄여** 그리므로 `.none` 이면 계단이 생긴다.
///
/// 스프라이트 캐시는 `SpriteLoader` 를 그대로 쓴다 — 마을 전용 캐시를 만들면 같은 이미지가
/// 두 벌 메모리에 남는다. `cachedImage` 를 먼저 보고 없을 때만 비동기로 받으므로, 이미 받아
/// 둔 종은 첫 프레임부터 그려진다(빈 사각형이 한 번 깜빡이지 않는다).
///
/// 애니메이션 스프라이트를 쓰지 않는다. 마을은 창을 열어 두는 화면이라 상시 애니메이션이
/// 배터리를 먹는다 — `defect-log.md` "에너지 (상시 표시 애니메이션)" 부류다.
struct PokopiaTownAvatarView: View {
    let dittoForm: Int?
    let outfit: TrainerOutfit
    /// 한 변(pt). 부르는 쪽이 화면 크기를 그대로 준다 — 도트 시절의 "16 × 배율" 은 HOME
    /// 렌더에 뜻이 없는 단위였다.
    var side: CGFloat = 44

    @State private var formImage: NSImage?

    var body: some View {
        Group {
            if let dittoForm {
                // 변신 중. 프레임은 정사각으로 묶는다 — 종마다 스프라이트 비율이 달라서
                // 원본 크기로 그리면 변신할 때마다 아바타가 커지고 작아진다.
                Group {
                    if let formImage {
                        Image(nsImage: formImage)
                            .interpolation(.high)
                            .resizable()
                            .scaledToFit()
                    } else {
                        Color.clear
                    }
                }
                .frame(width: side, height: side)
                // `id:` 가 있어야 변신 대상을 바꿀 때 다시 받는다. `.onAppear` 면 옛 스프라이트가 남는다.
                // `??` 오른쪽에 `await` 를 둘 수 없다(autoclosure 는 async 를 못 받는다).
                .task(id: dittoForm) {
                    if let cached = SpriteLoader.cachedImage(speciesID: dittoForm,
                                                             highResolution: true) {
                        formImage = cached
                    } else {
                        formImage = await SpriteLoader.image(speciesID: dittoForm,
                                                             highResolution: true)
                    }
                }
                .accessibilityLabel("메타몽이 #\(dittoForm) 으로 변신한 모습")
            } else {
                // 변신하지 않은 나. 여기만 도트로 남는다 — 트레이너 모습은 코스튬
                // (`TrainerOutfit`)에서 합성하는 이 앱의 값이고, 대신할 렌더가 없다.
                // 높이가 폭의 1.5배라(16×24) 정사각 칸의 아래에 맞춰 세운다.
                TrainerAvatarView(outfit: outfit, scale: side / 24)
                    .accessibilityLabel("트레이너")
            }
        }
    }
}

/// 마을에 서 있는 주민 한 마리. 아바타와 같은 이유로 HOME 렌더 + 정지 스프라이트다.
struct PokopiaResidentView: View {
    let speciesID: Int
    let isShiny: Bool
    /// 한 변(pt). 마을 격자·주민 목록·변신 시트가 각자 크기를 준다.
    var side: CGFloat = 34

    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).interpolation(.high).resizable().scaledToFit()
            } else {
                Color.clear
            }
        }
        .frame(width: side, height: side)
        .task(id: speciesID) {
            if let cached = SpriteLoader.cachedImage(speciesID: speciesID, shiny: isShiny,
                                                     highResolution: true) {
                image = cached
            } else {
                image = await SpriteLoader.image(speciesID: speciesID, shiny: isShiny,
                                                 highResolution: true)
            }
        }
    }
}
