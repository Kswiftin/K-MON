import SwiftUI

/// 도전 탭에서 여는 전체화면 오버레이(체육관·오늘의 던전·레이드·경매 시장)가 공유하는 헤더.
/// 제목 폰트가 `.headline`/`.callout.bold()`/`.title3.bold()`로, 닫기 버튼이 `xmark`/
/// `xmark.circle.fill`로 화면마다 제각각이던 것을 하나로 맞춘다. 아이콘·색·부가 정보(체육관의
/// 배지 개수 같은)는 화면마다 다르므로 `tint`·`trailing`으로 남겨 둔다.
///
/// `Trailing: View` 제네릭 대신 `AnyView` 를 쓴다 — 제네릭 파라미터가 선언 줄에 있으면
/// `AdventureClaimTests.testEveryDeclaredViewHasACallSite` 의 이름 파싱(공백으로 토큰을 나눠
/// `struct` 다음 토큰을 그대로 타입 이름으로 쓰는 방식)이 `ChallengeOverlayHeader<Trailing` 을
/// 이름으로 오인해 "마운트 안 됨"으로 오탐한다.
struct ChallengeOverlayHeader: View {
    let title: String
    let systemImage: String
    var tint: Color = .primary
    let closeHelp: String
    var trailing: AnyView = AnyView(EmptyView())
    let onClose: () -> Void

    var body: some View {
        HStack {
            Label(title, systemImage: systemImage).font(.headline).foregroundStyle(tint)
            trailing
            Spacer()
            Button(action: onClose) { Image(systemName: "xmark.circle.fill") }
                .buttonStyle(.plain).foregroundStyle(.secondary).help(closeHelp)
        }
    }
}
