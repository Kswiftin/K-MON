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
/// 1. 쓰러진 칸이 있으면 벤치 앞쪽으로 채운다(턴을 쓰지 않는다).
/// 2. 잡을 수 있고 성공률이 절반을 넘으면 던진다(파티가 빌 때까지).
/// 3. 아니면 **HP 가 가장 적은 상대**에게 기대 위력이 가장 큰 기술을 쓴다 — 위력 × 자속 × 상성.
///    2대2 는 화력을 한쪽에 모으는 편이 낫다(한 마리를 먼저 눕히면 그만큼 맞는 횟수가 줄어든다).
enum AutoPlayer {
    static let catchThreshold = 0.5

    /// 한 번 부르면 **한 칸의 결정 하나**를 낸다. 2대2 는 살아 있는 칸이 다 정해질 때까지 턴이
    /// 돌지 않으므로, 호출자의 루프가 그만큼 더 돈다.
    static func act(_ run: inout RogueRun) {
        if let slot = run.battle.slotsNeedingSendOut.first,
           let next = run.battle.benchCandidates.first {
            run.sendOut(next, toSlot: slot)
            return
        }
        let targets = run.battle.livingOpponentSlots
        // HP 가 가장 적은 상대. 볼도 같은 상대에게 던진다 — 성공률이 HP 로 정해지므로 그쪽이 가장 높다.
        guard let target = targets.min(by: {
            (run.battle.opponentSide(at: $0)?.hp ?? 0) < (run.battle.opponentSide(at: $1)?.hp ?? 0)
        }), let opponent = run.battle.opponentSide(at: target) else { return }
        if run.canThrowBall, RogueRun.catchChance(target: opponent) >= catchThreshold {
            run.throwBall(atSlot: target)
            return
        }
        guard let slot = run.battle.slotsAwaitingAction.first,
              let me = run.battle.mySide(at: slot) else { return }
        run.useMove(bestMoveIndex(me, against: opponent), fromSlot: slot, target: target)
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
    /// 자동 플레이어가 낸 **결정 수**다(턴 수가 아니다) — 2대2 웨이브는 한 턴에 칸마다 하나씩,
    /// 기절 보충도 하나로 센다. 판이 안 끝나는 조합을 자르는 상한(`turnLimit`)의 기준이기도 하다.
    var turns: Int
}

/// 판 하나를 끝까지 돌린다. 상대는 앱과 같은 규칙(`RogueRun.chooseOpponent`)으로 뽑는다.
func playOne(seed: UInt64, cache: SnapshotCache, tuning: RogueTuning) async -> RunResult? {
    var rng = SplitMix64(seed: seed)
    let starterID = RogueRun.starterPool[Int(rng.next() % UInt64(RogueRun.starterPool.count))]
    guard let starter = await cache.snapshot(speciesID: starterID, level: 5) else { return nil }
    // 판 seed 를 먼저 뽑는다 — 첫 웨이브의 마릿수 판정(`opponentCount`)이 이 값을 본다.
    let runSeed = rng.next()
    guard let first = await wilds(wave: 1, cache: cache, rng: &rng, seed: runSeed, tuning: tuning),
          !first.isEmpty else { return nil }

    var run = RogueRun(party: [starter], opponents: first, seed: runSeed, tuning: tuning)
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
        case .routing:
            run.take(routeChoice(run))
        case .loadingWave:
            guard let next = await wilds(wave: run.wave, route: run.route, cache: cache,
                                         rng: &rng, seed: run.seed, tuning: tuning),
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

/// 길 선택 — 파티가 온전하고 **다음이 보스가 아닐 때만** 험한 길을 탄다. 늘 험한 길을 타면
/// 측정값이 "최대 난이도"가 되고, 늘 평탄한 길을 타면 험한 길의 균형을 한 번도 재지 않는다.
/// 보스 앞에서 피하는 것은 사람이 두는 방식에 맞춘 것이다(보스는 이미 벽이라 위험이 겹친다).
func routeChoice(_ run: RogueRun) -> RunRoute {
    guard !RogueRun.isBoss(wave: run.wave + 1, tuning: run.tuning) else { return .safe }
    let healthy = run.party.filter(\.isAlive)
    guard healthy.count == run.party.count else { return .safe }
    return healthy.allSatisfy { Double($0.hp) / Double(max(1, $0.stats.hp)) > 0.8 } ? .risky : .safe
}

/// 보상 선택 — 급한 것을 먼저 메우고, 급할 게 없으면 **지속 강화**를 쌓는다. 사람이 고르는 순서에
/// 가깝게 둔다. 지속형을 뒤로 미루면 자동 플레이어가 12 웨이브를 소모형만 들고 지나서, 판의
/// 난이도를 강화 없는 옛 규칙으로 재게 된다.
func pickBest(_ run: RogueRun) -> RunModifier {
    let hurt = run.party.contains { $0.isAlive && Double($0.hp) / Double(max(1, $0.stats.hp)) < 0.5 }
    let dry = run.party.contains { $0.isAlive && $0.pp.reduce(0, +) <= 2 }
    var priority: [RunModifier] = []
    if run.party.contains(where: { !$0.isAlive }) { priority.append(.revive) }
    if hurt { priority.append(.potion) }
    if dry { priority.append(.elixir) }
    priority += [.typeBoost, .focusLens, .leftovers, .candy, .potion, .elixir, .cleanse, .revive]
    return priority.first { run.offers.contains($0) } ?? run.offers[0]
}

func wilds(wave: Int, route: RunRoute = .safe, cache: SnapshotCache, rng: inout SplitMix64,
           seed: UInt64, tuning: RogueTuning) async -> [BattleSnapshot]? {
    let level = RogueRun.opponentLevel(wave: wave, route: route, tuning: tuning)
    var built: [BattleSnapshot] = []
    for _ in 0..<RogueRun.opponentCount(wave: wave, seed: seed, tuning: tuning) {
        // 추첨 seed 는 판의 흐름에서 뽑는다 — 같은 seed 로 같은 판이 재현돼야 밸런스 비교가 된다.
        var ids: [Int] = []
        for _ in 0..<RogueRun.wildDrawAttempts {
            ids.append(RogueRun.wildSpeciesPool.lowerBound
                       + Int(rng.next() % UInt64(RogueRun.wildSpeciesPool.count)))
        }
        var cursor = 0
        let chosen = await RogueRun.chooseOpponent(wave: wave, route: route,
                                                   tuning: tuning) { () -> BattleSnapshot? in
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
tuning.wildLevelHandicapStart = intOption("--handicap", tuning.wildLevelHandicapStart)
// 기본값은 **struct 의 값**이다. `--handicap` 을 물려받게 두면 플래그 없이 돌린 판이
// 끝까지 같은 폭(4/4)으로 돌아, 기본값을 재려던 실행이 다른 밸런스를 잰다(실제로 그렇게 어긋났다).
tuning.wildLevelHandicapEnd = intOption("--handicap-end", tuning.wildLevelHandicapEnd)
tuning.bossLevelBonus = intOption("--boss-level", tuning.bossLevelBonus)
tuning.finalLevelBonus = intOption("--final-level", tuning.finalLevelBonus)
tuning.firstTierCap = intOption("--first-cap", tuning.firstTierCap)
tuning.lastTierCap = intOption("--last-cap", tuning.lastTierCap)
tuning.bossStatBonus = intOption("--boss-stat", tuning.bossStatBonus)
tuning.minStatRatio = doubleOption("--min-ratio", tuning.minStatRatio)
tuning.doubleDenominator = intOption("--double-denom", tuning.doubleDenominator)
tuning.bossDoubleDenominator = intOption("--boss-double-denom", tuning.bossDoubleDenominator)
tuning.ballsPerRun = intOption("--balls", tuning.ballsPerRun)
tuning.bossHealRatio = doubleOption("--boss-heal", tuning.bossHealRatio)
tuning.partyLimit = intOption("--party-limit", tuning.partyLimit)

if arguments.contains("--dump-tuning") { print(tuning); exit(0) }
let runCount = intOption("--runs", 100)
let baseSeed = UInt64(intOption("--seed", 1))
let label = option("--label") ?? ""
let cacheFile = URL(fileURLWithPath: ".build/rogue-sim/snapshots.json")
let cache = SnapshotCache(file: cacheFile)

/// 이 튜닝이 쓰는 (종, 레벨) 조합을 미리 다 받아 둔다. 스윕은 같은 조합을 수백 번 다시 보므로,
/// 채워 두면 그 뒤 실험은 네트워크를 한 번도 타지 않는다.
func warm(tuning: RogueTuning, cache: SnapshotCache, range: ClosedRange<Int>?) async {
    var levels = Set([5])
    if let range { levels.formUnion(range) }
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
    // "1-31" 처럼 범위를 주면 그 레벨을 통째로 받아 둔다 — 핸디캡을 흔드는 스윕은 레벨 세트가
    // 매번 달라지므로, 넓게 한 번 채워 두는 편이 실험마다 네트워크를 타는 것보다 싸다.
    let range = option("--warm-levels").flatMap { text -> ClosedRange<Int>? in
        let parts = text.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 2, parts[0] <= parts[1] else { return nil }
        return parts[0]...parts[1]
    }
    await warm(tuning: tuning, cache: cache, range: range)
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

/// 웨이브별 **조건부 사망률**(hazard) — 그 웨이브에 도달한 판 중 거기서 끝난 비율.
/// 절대 탈락 수는 생존자가 줄어드는 만큼 저절로 작아져서, 판이 뒤로 갈수록 어려워지는지를
/// 그 숫자로는 볼 수 없다.
let reached = (1...tuning.finalWave).map { wave in
    results.filter { $0.reachedWave >= wave }.count
}
let deathsByWave = (1...tuning.finalWave).map { wave in
    results.filter { $0.reachedWave == wave && !$0.cleared }.count
}
let hazard = (0..<tuning.finalWave).map { index -> Double in
    reached[index] > 0 ? Double(deathsByWave[index]) / Double(reached[index]) : 0
}

/// **역전량** — hazard 가 앞 웨이브보다 낮아진 크기의 합. 판은 뒤로 갈수록 어려워야 하므로
/// 우상향은 벌하지 않고 톱니(웨이브 4 가 5–7 보다 사나운 것 같은)만 벌한다.
/// 도달 판이 너무 적은 웨이브는 잡음이라 세지 않는다.
let minimumSample = max(5, results.count / 20)
var inversion = 0.0
var previous = 0.0
for index in 0..<tuning.finalWave where reached[index] >= minimumSample {
    if hazard[index] < previous { inversion += previous - hazard[index] }
    previous = max(previous, hazard[index])
}
let finalIsHardest = hazard.last == hazard.max()

let clearRate = Double(cleared) / Double(results.count) * 100
print(String(format: "%@판 %d · seed %d · 클리어 %.1f%% · 평균도달 %.2f · 역전 %.3f%@ · 파티 %.2f · 볼 %.2f",
             label.isEmpty ? "" : "[\(label)] " as String,
             results.count, Int(baseSeed), clearRate,
             mean(results.map(\.reachedWave)), inversion,
             finalIsHardest ? "" : " (최종이 최고점 아님)",
             mean(results.map(\.partySize)), mean(results.map(\.ballsUsed))))
if arguments.contains("--detail") {
    for index in 0..<tuning.finalWave where deathsByWave[index] > 0 || reached[index] > 0 {
        let wave = index + 1
        let bar = String(repeating: "█", count: Int(hazard[index] * 40))
        print(String(format: "  %2d%@ 도달 %3d 탈락 %3d  hazard %.3f %@", wave,
                     RogueRun.isBoss(wave: wave, tuning: tuning) ? "*" : " ",
                     reached[index], deathsByWave[index], hazard[index], bar))
    }
}
