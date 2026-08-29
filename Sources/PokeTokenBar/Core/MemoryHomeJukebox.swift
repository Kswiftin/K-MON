import Foundation

/// 기획서 §11 "BGM은 엄청 중요함" — 홈에 걸어 두는 대표 곡. 핵심은 목록이 아니라 **해금**이다:
/// "음악을 들으면 특정 포켓몬과의 기억이 떠오르게 됩니다."
///
/// 그래서 곡은 상점에서 사는 물건이 아니라 **이미 쌓인 기억이 여는 것**이다. 해금 상태를 따로
/// 저장하지 않는다 — 기억에서 파생하므로 세이브 필드가 0개이고, 세이브를 옮겨도 같이 따라온다.
///
/// 실제 오디오는 재생하지 않는다(저작권 음원과 재생 권한은 이 기능의 범위 밖이다).
/// `MemoryHomeJukeboxTrack` 주석이 말하는 그대로, 홈에 걸어 두는 **선택값**이다.
enum MemoryHomeJukebox {
    /// 기본 트랙은 항상 열려 있다 — 하나도 못 고르는 주크박스는 고장난 것과 구별되지 않는다.
    static let defaultTrack = MemoryHomeJukeboxTrack.afterSchool

    /// 밤으로 세는 구간. 자정을 가로지르므로 `22...4` 로 적을 수 없다 — `MemoryHomeSeason` 의
    /// 겨울이 `default` 로 12·1·2 를 함께 받는 것과 같은 부류다.
    static func isNight(_ date: Date, calendar: Calendar = .current) -> Bool {
        let hour = calendar.component(.hour, from: date)
        return hour >= 22 || hour < 4
    }

    static func isUnlocked(_ track: MemoryHomeJukeboxTrack, memories: [PokemonMemory],
                           focusSessions: Int, calendar: Calendar = .current) -> Bool {
        switch track {
        case .afterSchool:
            return true
        case .rainyWalk:
            return focusSessions >= 10
        case .summerRiver:
            return memories.contains { MemoryHomeSeason.current($0.createdAt) == .summer }
        case .lavenderNight:
            return memories.contains { isNight($0.createdAt, calendar: calendar) }
        }
    }

    static func name(_ track: MemoryHomeJukeboxTrack, _ l: L) -> String {
        switch track {
        case .afterSchool: return l.t("방과 후", "After School", "放課後")
        case .rainyWalk: return l.t("비 오는 날의 산책", "A Walk in the Rain", "雨の日の散歩")
        case .lavenderNight: return l.t("잠들지 않는 밤", "The Night That Never Sleeps", "眠らない夜")
        case .summerRiver: return l.t("여름, 강변", "Summer, Riverside", "夏、川辺")
        }
    }

    static func symbol(_ track: MemoryHomeJukeboxTrack) -> String {
        switch track {
        case .afterSchool: return "backpack.fill"
        case .rainyWalk: return "cloud.rain.fill"
        case .lavenderNight: return "moon.stars.fill"
        case .summerRiver: return "water.waves"
        }
    }

    /// 잠긴 곡 옆에 붙는 조건 문구. 조건을 화면에 적지 않으면 해금이 "가끔 늘어나는 목록" 으로
    /// 읽혀서, 기억과 음악을 잇는다는 §11 의 목적이 사라진다.
    static func requirement(_ track: MemoryHomeJukeboxTrack, _ l: L) -> String {
        switch track {
        case .afterSchool: return l.t("처음부터 들을 수 있어요.", "Available from the start.", "はじめから聴けます。")
        case .rainyWalk: return l.t("함께 집중 10번", "10 focus sessions together", "いっしょに集中 10 回")
        case .lavenderNight: return l.t("밤 10시 이후의 기억 1개", "One memory after 10 p.m.", "夜10時以降の思い出 1 件")
        case .summerRiver: return l.t("여름에 남긴 기억 1개", "One memory made in summer", "夏に残した思い出 1 件")
        }
    }
}
