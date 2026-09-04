import Foundation

/// 웨이브 런에서 **네트워크가 필요한 자리** 한 벌 — 스타터·야생 상대·진화.
///
/// 규칙(레벨 곡선·종족값 상한·채택)은 전부 `RogueRun` 이 들고 있고 여기는 그 규칙에 맞는 값을
/// 받아 오기만 한다. 따로 있는 이유는 **입구가 둘**이기 때문이다: 앱 화면(`RogueRunView`)과
/// 터미널 요청 실행기(`PokedoroRequestExecutor`). 예전엔 화면의 `private static` 이라, 터미널이
/// 판을 열려면 같은 절차를 다시 쓰거나 **팝오버가 열려 있기를 기다려야** 했다 — 후자는
/// `.loadingWave` 에 멈춘 판이 창을 열 때까지 영영 진행되지 않는다는 뜻이다.
///
/// 조회는 스토어의 `provider` 를 지난다(`wildSnapshot`·`evolutionLine`). `PokeAPIClient.shared`
/// 를 직접 부르면 판을 여는 경로가 통째로 단위 테스트 밖에 남는다.
@MainActor
enum WaveRunLoader {
    /// 스타터 레벨. 화면과 터미널이 같은 값을 쓰도록 여기 한 곳에 둔다.
    static let starterLevel = 5

    /// 이 웨이브의 상대 전원. **한 마리라도 만들었으면 그대로 간다** — 둘째를 못 받았다고 판을
    /// 세우면 네트워크가 흔들릴 때마다 진행 중인 런이 멈춘다.
    static func wilds(wave: Int, route: RunRoute, seed: UInt64,
                      store: CompanionStore) async -> [BattleSnapshot] {
        var built: [BattleSnapshot] = []
        for _ in 0..<RogueRun.opponentCount(wave: wave, seed: seed) {
            if let one = await wild(wave: wave, route: route, store: store) { built.append(one) }
        }
        return built
    }

    /// 웨이브에 맞는 야생 하나. 종을 전 범위에서 균등 추첨하면 웨이브 1 에 슬라킹이 나오므로
    /// 채택 규칙은 코어(`RogueRun.chooseOpponent`)가 든다 — 시뮬레이터와 같은 규칙을 써야 한다.
    static func wild(wave: Int, route: RunRoute, store: CompanionStore) async -> BattleSnapshot? {
        let level = RogueRun.opponentLevel(wave: wave, route: route)
        return await RogueRun.chooseOpponent(wave: wave, route: route) {
            await store.wildSnapshot(speciesID: RogueRun.wildSpeciesPool.randomElement() ?? 1,
                                     level: level)
        }
    }

    /// 새 판. 상대를 못 만들면 **판을 만들지 않는다** — 빈 상대로 연 판은 첫 정산에서 패배로 닫힌다.
    @discardableResult
    static func startRun(starter speciesID: Int, store: CompanionStore) async -> Bool {
        guard let starter = await store.wildSnapshot(speciesID: speciesID, level: starterLevel)
        else { return false }
        // 판 seed 를 먼저 정한다 — 첫 웨이브의 마릿수 판정이 이 값을 본다.
        let seed = UInt64.random(in: UInt64.min...UInt64.max)
        let opponents = await wilds(wave: 1, route: .safe, seed: seed, store: store)
        guard !opponents.isEmpty else { return false }
        store.rogueRun = RogueRun(party: [starter], opponents: opponents, seed: seed)
        return true
    }

    /// 상대를 받다 만 판을 이어 연다. **이 국면에서 받는 사용자 동작이 없으므로** 여기서 다시
    /// 열지 않으면 네트워크가 한 번 흔들린 판이 영영 멈춘다(화면은 스피너, 터미널은 "받는 중").
    ///
    /// 실패해도 판은 그대로 둔다 — 다음 호출이 다시 시도한다.
    @discardableResult
    static func openNextWaveIfNeeded(store: CompanionStore) async -> Bool {
        guard var run = store.rogueRun, run.stage == .loadingWave else { return false }
        let opponents = await wilds(wave: run.wave, route: run.route, seed: run.seed, store: store)
        guard !opponents.isEmpty else { return false }
        run.beginWave(opponents: opponents)
        store.rogueRun = run
        return true
    }

    /// 웨이브를 넘긴 파티에서 **레벨 조건을 채운 개체를 진화시킨다.** 진화 전 이름을 돌려준다 —
    /// 조용히 처리하면 판의 가장 큰 사건이 스프라이트가 바뀐 것으로만 남는다.
    ///
    /// 보상 화면(`.picking`)에서만 돈다: 전투 중에 개체를 갈면 진행 중인 턴의 활성 슬롯이 다른
    /// 종으로 바뀐다. 조회가 실패하면 **진화하지 않고 그대로 간다** — 판을 세우는 것보다 낫다.
    static func evolveParty(store: CompanionStore) async -> [String] {
        guard let run = store.rogueRun, run.stage == .picking else { return [] }
        var evolved: [String] = []
        for (index, member) in run.party.enumerated() {
            guard let line = await store.evolutionLine(speciesID: member.snapshot.speciesID),
                  let node = line.tree.node(withID: member.snapshot.speciesID),
                  let target = RogueRun.levelUpEvolution(from: node, level: member.snapshot.level),
                  // 애니메이션 스프라이트가 없는 종으로 진화시키면 화면에서 개체가 사라진다.
                  PokemonAssets.hasAnimatedSprite(speciesID: target.speciesID),
                  let snapshot = await store.wildSnapshot(speciesID: target.speciesID,
                                                          level: member.snapshot.level),
                  // 판을 **매번 다시 읽는다** — 조회 사이에 다른 입구가 판을 바꿨을 수 있다.
                  var current = store.rogueRun, current.stage == .picking
            else { continue }
            let before = member.snapshot.name
            current.evolve(memberAt: index, into: snapshot)
            store.rogueRun = current
            evolved.append(before)
        }
        return evolved
    }

    /// 스타터 후보 하나 — 번호는 `RogueRun.starterPool` 의 순번(1부터)이다.
    ///
    /// **고정 목록에서 번호로 고른다.** 화면처럼 셋을 무작위로 뽑아 보여 주면 그 목록이 어딘가에
    /// 남아 있어야 하는데, 터미널은 명령마다 새 프로세스라 들고 있을 자리가 없다.
    static func starter(number: Int) -> Int? {
        let index = number - 1
        return RogueRun.starterPool.indices.contains(index) ? RogueRun.starterPool[index] : nil
    }
}
