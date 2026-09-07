import SwiftUI

/// 도전 탭에서 여는 전체화면 오버레이(체육관·오늘의 던전·레이드·경매 시장)가 공유하는 헤더.
/// 제목 폰트가 `.headline`/`.callout.bold()`/`.title3.bold()`로, 닫기 버튼이 `xmark`/
/// `xmark.circle.fill`로 화면마다 제각각이던 것을 하나로 맞춘다. 아이콘·색·부가 정보(체육관의
/// 배지 개수 같은)는 화면마다 다르므로 `tint`·`trailing`으로 남겨 둔다.
struct ChallengeOverlayHeader<Trailing: View>: View {
    let title: String
    let systemImage: String
    var tint: Color = .primary
    let closeHelp: String
    let onClose: () -> Void
    // 마지막 파라미터라야 호출부에서 후행 클로저(trailing closure) 문법으로 넘길 수 있다 —
    // `onClose` 보다 앞에 두면 이름 있는 인자 뒤에 블록만 붙이는 흔한 SwiftUI 호출 모양이 안 된다.
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack {
            Label(title, systemImage: systemImage).font(.headline).foregroundStyle(tint)
            trailing()
            Spacer()
            Button(action: onClose) { Image(systemName: "xmark.circle.fill") }
                .buttonStyle(.plain).foregroundStyle(.secondary).help(closeHelp)
        }
    }
}

extension ChallengeOverlayHeader where Trailing == EmptyView {
    init(title: String, systemImage: String, tint: Color = .primary, closeHelp: String,
         onClose: @escaping () -> Void) {
        self.init(title: title, systemImage: systemImage, tint: tint, closeHelp: closeHelp,
                  onClose: onClose, trailing: { EmptyView() })
    }
}
