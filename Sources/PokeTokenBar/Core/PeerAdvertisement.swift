import Foundation
import Network

/// 근처 트레이너 카드에 띄우는 표시용 진행도. Bonjour TXT 로 오간다.
///
/// 표시 전용이다. 판돈·해금·승패는 읽지 않는다. 상대가 스스로 신고하는 값이라 권위가 없고,
/// 판돈은 핸드셰이크의 `BattleRankProfile` 에서 온다(`BattleRank.clamped` 와 같은 한계).
///
/// 굽는 쪽과 읽는 쪽이 이 한 곳을 지난다. 키 이름은 와이어 계약이라 바꾸면 상대 목록의 그 칸이
/// 조용히 비는데 컴파일은 통과하고, 클램프도 흩어지면 한 곳이 빠진다.
struct PeerAdvertisement: Equatable, Sendable {
    /// TXT 키. `rankPoints` 는 #85 때 이미 배포된 이름이라 바꾸지 않는다.
    enum Key {
        static let rank = "rankPoints"
        static let level = "trainerLevel"
        static let tiers = "achievementTiers"
        static let ceiling = "achievementCeiling"
        static let outfit = "outfit"
        static let representativeSpecies = "partnerSpecies"
        static let representativeShiny = "partnerShiny"
        static let runBestWave = "runWave"
        static let runFinalWave = "runFinal"
        static let runClears = "runClears"
        static let beginner = "beginner"
    }

    /// 광고된 분모의 표시 상한. 세 자리가 되면 카드가 밀려 배지 칸이 잘린다.
    static let maximumTierCeiling = 99

    /// 랭크는 원본 포인트. 이미 배포된 형식이고 읽는 쪽이 `BattleRank` 로 파생한다.
    let rankPoints: Int?
    /// 레벨은 표시값이다. 곡선(`TrainerLevel.pointsPerStep`)이 조절 손잡이라, 포인트를 실으면
    /// 곡선을 바꾼 순간 구버전이 남의 레벨을 틀리게 계산한다.
    let trainerLevel: Int?
    /// 도달 단계 합계. 같은 이유로 표시값이다.
    let achievementTiers: Int?
    /// 상대의 분모. 카탈로그는 조절 손잡이라 언젠가 늘어난다. 안 실으면 구버전이 18/20 인 상대를
    /// `16/16`(완료)으로 그리고, 그때는 고칠 방법이 없다.
    let achievementCeiling: Int?
    /// 상대 카드에 그릴 착장. 표시 전용이라 소유 검증은 안 한다(그건 세이브 신뢰경계 몫).
    let outfit: TrainerOutfit?
    /// 배틀 프로필 대표 포켓몬. 표시 전용이며 실제 출전 파티나 보유 검증에는 쓰지 않는다.
    let representativeSpeciesID: Int?
    let representativeIsShiny: Bool
    /// 웨이브 런(오늘의 던전)에서 가장 멀리 간 웨이브. 표시값이다.
    let runBestWave: Int?
    /// 상대가 도달한 판의 **최종 웨이브** — 업적 분모(`achievementCeiling`)와 같은 이유로 싣는다.
    /// 밸런스 손잡이(`RogueTuning.finalWave`)라 판 길이가 바뀌는데, 안 실으면 30 웨이브를 도는
    /// 상대의 기록을 12 웨이브 자로 그려 "18/12" 가 나온다.
    let runFinalWave: Int?
    /// 최종 웨이브까지 넘긴 판 수.
    let runClears: Int?
    /// 기술 상성 안내를 쓰는 트레이너. 혜택을 숨기지 않도록 친구 목록에 공개한다.
    let beginnerMode: Bool

    /// 굽는 쪽 진입점. 클램프는 여기 한 곳이고 파싱도 이 자리를 지난다.
    init(rankPoints: Int? = nil, trainerLevel: Int? = nil,
         achievementTiers: Int? = nil, achievementCeiling: Int? = nil,
         outfit: TrainerOutfit? = nil, representativeSpeciesID: Int? = nil,
         representativeIsShiny: Bool = false,
         runBestWave: Int? = nil, runFinalWave: Int? = nil, runClears: Int? = nil,
         beginnerMode: Bool = false) {
        self.rankPoints = rankPoints.map { BattleRank.clamped($0) }
        // 레벨 하한은 1. `TrainerLevel.level` 이 1 부터라 Lv.0 은 없는 값이다.
        self.trainerLevel = trainerLevel.map { min(TrainerLevel.maximumLevel, max(1, $0)) }
        // 분모 하한도 1. 0 을 분모로 그리면 나눗셈이 아니다.
        let ceiling = achievementCeiling.map { min(Self.maximumTierCeiling, max(1, $0)) }
        self.achievementCeiling = ceiling
        // 단계는 상대가 신고한 분모 안으로 자른다. 내 상한으로 자르면 새 카탈로그 상대의 진행이
        // 깎여 완료로 보인다. 분모를 안 보낸 구버전만 내 상한을 쓴다.
        self.achievementTiers = achievementTiers.map {
            min(ceiling ?? AchievementLadder.tierCeiling, max(0, $0))
        }
        // 빈 착장은 nil 로 정규화 — 키를 안 실어야 `wireString` 규칙과 왕복이 맞는다.
        self.outfit = outfit.flatMap { $0.worn.isEmpty ? nil : $0 }
        self.representativeSpeciesID = representativeSpeciesID.flatMap { (1...20_000).contains($0) ? $0 : nil }
        self.representativeIsShiny = self.representativeSpeciesID == nil ? false : representativeIsShiny
        // 판 길이도 하한 1 — 0 을 분모로 그리면 나눗셈이 아니다(업적 분모와 같은 규칙).
        let finalWave = runFinalWave.map { max(1, $0) }
        self.runFinalWave = finalWave
        // 웨이브는 상대가 신고한 판 길이 안으로 자른다. 내 길이로 자르면 더 긴 판을 도는 상대의
        // 기록이 깎여 "완주"로 보인다. 길이를 안 보낸 구버전만 내 값을 쓴다.
        self.runBestWave = runBestWave.map {
            min(finalWave ?? RogueRun.finalWave, max(0, $0))
        }
        self.runClears = runClears.map { max(0, $0) }
        self.beginnerMode = beginnerMode
    }

    /// 읽는 쪽 진입점. 관대 파싱이고 실패하지 않는다(`init?` 가 아니다). 실패시키면 그 피어가
    /// 목록에서 사라져 신청조차 못 한다. 없는 키·비숫자는 nil 로 둔다. 0 으로 떨어뜨리면 랭크 없는
    /// 상대가 "Poké Ball R4 · 0 LP" 로 보인다.
    init(_ record: NWTXTRecord) {
        self.init(rankPoints: record[Key.rank].flatMap(Int.init),
                  trainerLevel: record[Key.level].flatMap(Int.init),
                  achievementTiers: record[Key.tiers].flatMap(Int.init),
                  achievementCeiling: record[Key.ceiling].flatMap(Int.init),
                  outfit: record[Key.outfit].map(TrainerOutfit.init(wireString:)),
                  representativeSpeciesID: record[Key.representativeSpecies].flatMap(Int.init),
                  representativeIsShiny: record[Key.representativeShiny] == "1",
                  runBestWave: record[Key.runBestWave].flatMap(Int.init),
                  runFinalWave: record[Key.runFinalWave].flatMap(Int.init),
                  runClears: record[Key.runClears].flatMap(Int.init),
                  beginnerMode: record[Key.beginner] == "1")
    }

    /// 빈 칸은 키를 싣지 않는다. 읽는 쪽이 "없음"과 "0"을 구별해야 한다.
    var txtRecord: NWTXTRecord {
        var entries: [String: String] = [:]
        if let rankPoints { entries[Key.rank] = String(rankPoints) }
        if let trainerLevel { entries[Key.level] = String(trainerLevel) }
        if let achievementTiers { entries[Key.tiers] = String(achievementTiers) }
        if let achievementCeiling { entries[Key.ceiling] = String(achievementCeiling) }
        if let wire = outfit?.wireString { entries[Key.outfit] = wire }
        if let representativeSpeciesID {
            entries[Key.representativeSpecies] = String(representativeSpeciesID)
            if representativeIsShiny { entries[Key.representativeShiny] = "1" }
        }
        // 한 판도 안 돌린 상대는 키를 싣지 않는다 — `0/30` 을 그리면 "기록 없음"과 "첫 판에서
        // 전멸"이 같은 줄이 된다.
        if let runBestWave, runBestWave > 0 {
            entries[Key.runBestWave] = String(runBestWave)
            if let runFinalWave { entries[Key.runFinalWave] = String(runFinalWave) }
            if let runClears, runClears > 0 { entries[Key.runClears] = String(runClears) }
        }
        if beginnerMode { entries[Key.beginner] = "1" }
        return NWTXTRecord(entries)
    }

    /// 카드가 그릴 분수. 분모는 상대 것을 쓰고, 안 보낸 구버전은 내 카탈로그로 그린다.
    /// 단계가 없으면 분수도 없다. 분모만 온 광고로 `0/20` 을 그리면 없는 정보를 만든다.
    var achievementProgress: (tiers: Int, ceiling: Int)? {
        guard let achievementTiers else { return nil }
        return (achievementTiers, achievementCeiling ?? AchievementLadder.tierCeiling)
    }

    /// 카드가 쓰는 랭크. 없으면 nil 이어야 한다. 빈 `BattleRank()` 는 Poké Ball R4 로 그려져
    /// 정보 없음과 최하위가 구별되지 않는다.
    var rank: BattleRank? { rankPoints.map { BattleRank(points: $0) } }

    /// 카드가 그릴 런 기록. 분모는 상대 것을 쓰고, 안 보낸 구버전은 내 판 길이로 그린다.
    /// 웨이브가 없으면 줄 자체가 없다 — 클리어 횟수만 온 광고로 "0 웨이브"를 만들지 않는다.
    var runRecord: (wave: Int, finalWave: Int, clears: Int)? {
        guard let runBestWave, runBestWave > 0 else { return nil }
        return (runBestWave, runFinalWave ?? RogueRun.finalWave, runClears ?? 0)
    }
}
