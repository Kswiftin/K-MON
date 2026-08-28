import Foundation

// 웨이브 런 밸런스 시뮬레이터 — 앱을 띄우지 않고 판만 수천 번 돌린다.
// 앱과 **같은 코어**(`RogueRun`·`BattleEngine`)를 컴파일해 쓰므로, 여기서 잰 숫자가 실제 판의
// 숫자다. 실행은 `scripts/rogue-sim.sh` — 앱 빌드나 세이브에 닿지 않는다.

// MARK: 스냅샷 캐시

/// PokéAPI 왕복을 판 수만큼 반복하지 않으려고 (종, 레벨) 스냅샷을 디스크에 쌓는다.
/// `.build/` 아래라 저장소에도 앱 캐시에도 섞이지 않는다.
actor SnapshotCache {
    private var entries: [String: BattleSnapshot] = [:]
    private let file: URL
    private var dirty = false

    init(file: URL) {
        self.file = file
        if let data = try? Data(contentsOf: file),
           let decoded = try? JSONDecoder().decode([String: BattleSnapshot].self, from: data) {
            entries = decoded
        }
    }

    var count: Int { entries.count }

    func snapshot(speciesID: Int, level: Int) async -> BattleSnapshot? {
        let key = "\(speciesID)-\(level)"
        if let hit = entries[key] { return hit }
        guard let profile = try? await PokeAPIClient.shared.battleProfile(speciesID: speciesID)
        else { return nil }
        let moves = await PokeAPIClient.shared.moveSet(speciesID: speciesID, level: level,
                                                       types: profile.types)
        let built = BattleSnapshot(speciesID: speciesID, name: "#\(speciesID)", trainer: nil,
                                   level: level, nature: nil, isShiny: false, types: profile.types,
                                   base: profile.stats, moves: moves, ability: profile.abilitySlug,
                                   weightHectograms: profile.weightHectograms)
        entries[key] = built
        dirty = true
        return built
    }

    func flush() {
        guard dirty, let data = try? JSONEncoder().encode(entries) else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
        dirty = false
    }
}

// MARK: 자동 플레이어

/// 판을 대신 두는 규칙. **여기 규칙이 곧 측정 대상의 절반이다** — 사람이 더 잘 두면 실제 클리어율은
/// 이 숫자보다 높다. 그래서 규칙을 단순하고 설명 가능하게 둔다.
///
/// 1. 잡을 수 있고 성공률이 절반을 넘으면 던진다(파티가 빌 때까지).
/// 2. 아니면 기대 위력이 가장 큰 기술을 쓴다 — 위력 × 자속 × 상성.
/// 3. 활성 개체가 쓰러지면 코어가 알아서 다음 개체를 세운다(교체는 쓰지 않는다).
enum AutoPlayer {
    static let catchThreshold = 0.5

    static func act(_ run: inout RogueRun) {
        if run.canThrowBall,
           RogueRun.catchChance(target: run.battle.opponentSlot) >= catchThreshold {
            run.throwBall()
            return
        }
        run.useMove(bestMoveIndex(run.battle.mySlot, against: run.battle.opponentSlot))
    }

    static func bestMoveIndex(_ me: BattleSide, against target: BattleSide) -> Int {
        var best = 0
        var bestScore = -1.0
        for index in me.moves.indices where me.canUse(moveAt: index) {
            let move = me.move(at: index)
            let stab = me.snapshot.types.contains(move.type) ? 1.5 : 1.0
            let chart = TypeChart.effectiveness(move.type, against: target.snapshot.types)
            let score = Double(move.power ?? 0) * stab * chart
            if score > bestScore { bestScore = score; best = index }
        }
        return best
    }
}

// MARK: 한 판

struct RunResult {
    var reachedWave: Int
    var cleared: Bool
    var partySize: Int
    var ballsUsed: Int
    var catches: Int
    var turns: Int
}

/// 판 하나를 끝까지 돌린다. 상대는 앱과 같은 규칙(`RogueRun.chooseOpponent`)으로 뽑는다.
func playOne(seed: UInt64, cache: SnapshotCache, tuning: RogueTuning) async -> RunResult? {
    var rng = SplitMix64(seed: seed)
    let starterID = RogueRun.starterPool[Int(rng.next() % UInt64(RogueRun.starterPool.count))]
    guard let starter = await cache.snapshot(speciesID: starterID, level: 5) else { return nil }
    guard let first = await wilds(wave: 1, cache: cache, rng: &rng, tuning: tuning),
          !first.isEmpty else { return nil }

    var run = RogueRun(party: [starter], opponents: first, seed: rng.next(), tuning: tuning)
    var catches = 0
    var turns = 0
    // 한 웨이브가 끝나지 않는 판(둘 다 결정타가 없는 조합)에 걸려도 시뮬레이터는 멈추지 않는다.
    let turnLimit = 2_000

    while turns < turnLimit {
        switch run.stage {
        case .battling:
            let before = run.party.count
            AutoPlayer.act(&run)
            if run.party.count > before { catches += 1 }
            turns += 1
        case .picking:
            run.pick(pickBest(run))
        case .loadingWave:
            guard let next = await wilds(wave: run.wave, cache: cache, rng: &rng, tuning: tuning),
                  !next.isEmpty
            else { return nil }
            run.beginWave(opponents: next)
        case .cleared, .failed:
            return RunResult(reachedWave: run.wave, cleared: run.stage == .cleared,
                             partySize: run.party.count,
                             ballsUsed: tuning.ballsPerRun - run.balls,
                             catches: catches, turns: turns)
        }
    }
    return RunResult(reachedWave: run.wave, cleared: false, partySize: run.party.count,
                     ballsUsed: tuning.ballsPerRun - run.balls, catches: catches, turns: turns)
}

/// 보상 선택 — 쓰러진 식구가 있으면 되살리고, 아니면 회복 우선. 사람이 고르는 순서에 가깝게 둔다.
func pickBest(_ run: RogueRun) -> RunModifier {
    let priority: [RunModifier] = run.party.contains { !$0.isAlive }
        ? [.revive, .potion, .cleanse, .elixir, .candy]
        : [.potion, .candy, .elixir, .cleanse, .revive]
    return priority.first { run.offers.contains($0) } ?? run.offers[0]
}

func wilds(wave: Int, cache: SnapshotCache, rng: inout SplitMix64,
           tuning: RogueTuning) async -> [BattleSnapshot]? {
    let level = RogueRun.opponentLevel(wave: wave, tuning: tuning)
    var built: [BattleSnapshot] = []
    for _ in 0..<RogueRun.opponentCount(wave: wave, tuning: tuning) {
        // 추첨 seed 는 판의 흐름에서 뽑는다 — 같은 seed 로 같은 판이 재현돼야 밸런스 비교가 된다.
        var ids: [Int] = []
        for _ in 0..<RogueRun.wildDrawAttempts {
            ids.append(RogueRun.wildSpeciesPool.lowerBound
                       + Int(rng.next() % UInt64(RogueRun.wildSpeciesPool.count)))
        }
        var cursor = 0
        let chosen = await RogueRun.chooseOpponent(wave: wave, tuning: tuning) { () -> BattleSnapshot? in
            guard cursor < ids.count else { return nil }
            defer { cursor += 1 }
            return await cache.snapshot(speciesID: ids[cursor], level: level)
        }
        if let chosen { built.append(chosen) }
    }
    return built
}

// MARK: 실행

let arguments = CommandLine.arguments
func option(_ name: String) -> String? {
    guard let at = arguments.firstIndex(of: name), at + 1 < arguments.count else { return nil }
    return arguments[at + 1]
}
func intOption(_ name: String, _ fallback: Int) -> Int { option(name).flatMap(Int.init) ?? fallback }
func doubleOption(_ name: String, _ fallback: Double) -> Double {
    option(name).flatMap(Double.init) ?? fallback
}

var tuning = RogueTuning.standard
tuning.finalWave = intOption("--final-wave", tuning.finalWave)
tuning.bossEvery = intOption("--boss-every", tuning.bossEvery)
tuning.wildLevelHandicap = intOption("--handicap", tuning.wildLevelHandicap)
tuning.bossLevelBonus = intOption("--boss-level", tuning.bossLevelBonus)
tuning.finalLevelBonus = intOption("--final-level", tuning.finalLevelBonus)
tuning.firstTierCap = intOption("--first-cap", tuning.firstTierCap)
tuning.lastTierCap = intOption("--last-cap", tuning.lastTierCap)
tuning.bossStatBonus = intOption("--boss-stat", tuning.bossStatBonus)
tuning.minStatRatio = doubleOption("--min-ratio", tuning.minStatRatio)
tuning.doubleOpponentFrom = doubleOption("--double-from", tuning.doubleOpponentFrom)
tuning.ballsPerRun = intOption("--balls", tuning.ballsPerRun)
tuning.partyLimit = intOption("--party-limit", tuning.partyLimit)

let runCount = intOption("--runs", 100)
let baseSeed = UInt64(intOption("--seed", 1))
let label = option("--label") ?? ""
let cacheFile = URL(fileURLWithPath: ".build/rogue-sim/snapshots.json")
let cache = SnapshotCache(file: cacheFile)

/// 이 튜닝이 쓰는 (종, 레벨) 조합을 미리 다 받아 둔다. 스윕은 같은 조합을 수백 번 다시 보므로,
/// 채워 두면 그 뒤 실험은 네트워크를 한 번도 타지 않는다.
func warm(tuning: RogueTuning, cache: SnapshotCache) async {
    var levels = Set([5])
    for wave in 1...tuning.finalWave { levels.insert(RogueRun.opponentLevel(wave: wave, tuning: tuning)) }
    let sorted = levels.sorted()
    FileHandle.standardError.write(Data("레벨 \(sorted) × 종 \(RogueRun.wildSpeciesPool.count)\n".utf8))
    var done = 0
    for chunk in Array(RogueRun.wildSpeciesPool).chunked(into: 16) {
        await withTaskGroup(of: Void.self) { group in
            for speciesID in chunk {
                group.addTask {
                    for level in sorted { _ = await cache.snapshot(speciesID: speciesID, level: level) }
                }
            }
        }
        done += chunk.count
        await cache.flush()
        FileHandle.standardError.write(Data("warm \(done)/\(RogueRun.wildSpeciesPool.count)\n".utf8))
    }
}

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}

if arguments.contains("--warm") {
    await warm(tuning: tuning, cache: cache)
    let total = await cache.count
    print("캐시 \(total)개")
    exit(0)
}

var results: [RunResult] = []
for index in 0..<runCount {
    guard let result = await playOne(seed: baseSeed &+ UInt64(index), cache: cache, tuning: tuning)
    else {
        FileHandle.standardError.write(Data("run \(index): PokéAPI 실패, 건너뜀\n".utf8))
        continue
    }
    results.append(result)
    if (index + 1) % 25 == 0 {
        await cache.flush()
        FileHandle.standardError.write(Data("\(index + 1)/\(runCount)\n".utf8))
    }
}
await cache.flush()

guard !results.isEmpty else {
    print("판을 하나도 돌리지 못했다 — PokéAPI 연결을 확인한다.")
    exit(1)
}

let cleared = results.filter(\.cleared).count
func mean(_ values: [Int]) -> Double {
    values.isEmpty ? 0 : Double(values.reduce(0, +)) / Double(values.count)
}

/// 탈락이 한 웨이브에 몰린 정도 — 가장 많이 죽은 웨이브가 평균의 몇 배인가. 1 에 가까울수록
/// 곡선이 고르다. 클리어율만 보면 "웨이브 4 에서 10% 가 죽고 나머지는 심심한" 판을 구분하지 못한다.
let deathsByWave = (1...tuning.finalWave).map { wave in
    results.filter { $0.reachedWave == wave && !$0.cleared }.count
}
let deathTotal = deathsByWave.reduce(0, +)
let spike = deathTotal > 0
    ? Double(deathsByWave.max() ?? 0) / (Double(deathTotal) / Double(tuning.finalWave))
    : 0

let clearRate = Double(cleared) / Double(results.count) * 100
print(String(format: "%@판 %d · seed %d · 클리어 %.1f%% · 평균도달 %.2f · 쏠림 %.2f · 파티 %.2f · 볼 %.2f",
             label.isEmpty ? "" : "[\(label)] " as String,
             results.count, Int(baseSeed), clearRate,
             mean(results.map(\.reachedWave)), spike,
             mean(results.map(\.partySize)), mean(results.map(\.ballsUsed))))
if arguments.contains("--detail") {
    for (offset, count) in deathsByWave.enumerated() where count > 0 {
        let wave = offset + 1
        let bar = String(repeating: "█", count: max(1, count * 40 / results.count))
        print(String(format: "  %2d%@ %3d  %@", wave,
                     RogueRun.isBoss(wave: wave, tuning: tuning) ? "*" : " ", count, bar))
    }
}
