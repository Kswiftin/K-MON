import Foundation

/// Memory Home 의 **이름 표 중 Core 에 있어야 하는 것들.**
///
/// 방 스타일이 왜 잠겼는지는 화면에도, 터미널의 거절 문구에도 나가야 한다. 그런데 그 표는
/// `MemoryHomePresenter` 의 `private func` 이었다 — 두 번째 프런트엔드가 붙는 순간 손으로 한
/// 벌 더 쓰게 되고, 조건이 바뀌면 한쪽만 옛말이 된다(웨이브 런에서 `RunModifier.name` 을
/// `RunNames.swift` 로 꺼낸 것과 같은 이유다).
enum MemoryHomeNames {
    /// 이 스타일이 열리는 조건. 해금 판정은 `PokemonMemoryAlbum.isRoomStyleUnlocked` 가 하고
    /// 여기선 **이름만** 붙인다 — 판정과 문구를 한 함수에 두면 문구를 고치려다 조건이 바뀐다.
    static func requirement(_ style: MemoryHomeRoomStyle, _ l: L) -> String {
        switch style {
        case .campus: l.t("기본", "Default", "基本")
        case .lovely: l.t("집중 첫 업적", "First focus achievement", "集中の初実績")
        case .nature: l.t("진화 첫 업적", "First evolution achievement", "進化の初実績")
        case .retro: l.t("배틀 첫 업적", "First battle achievement", "バトルの初実績")
        }
    }
}
