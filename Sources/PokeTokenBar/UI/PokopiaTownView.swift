import SwiftUI
import AppKit

/// 포코피아 마을 탭. **변신한 종의 타입이 곧 브러시**이고, 지형을 미는 데 비용이 없다.
/// 집중 세션은 지형을 주는 대신 이사를 부른다(`CompanionStore.rollTownImmigration`).
///
/// 팔레트가 없다. 무엇을 밀 수 있는지는 **지금 무엇으로 변신했는지**가 답한다 — 그것이
/// 포코피아의 동사이고, 버튼 여덟 개는 그 동사를 자원 선택으로 바꿔 놓았다.
///
/// `TimelineView`·`SpriteView` 를 쓰지 않는다 — 이 화면에 계속 도는 것이 없다. 작업 연출은
/// `withAnimation` + `Task.sleep` 일회성이라 idle 비용이 0이다(`defect-log.md` "에너지" 부류는
/// 프레임 루프가 상주하는 표면을 말한다).
struct PokopiaTownView: View {
    let store: CompanionStore

    @State private var feedback: String?
    @State private var transforming = false
    @State private var evicting: TownResident?
    /// 아바타가 서 있는 칸. **저장하지 않는다** — 뷰 상태다(새 저장 필드 0개).
    @State private var avatarCell: (col: Int, row: Int) = (PokopiaTown.columns / 2,
                                                            PokopiaTown.rows - 1)
    @State private var working = false

    private var album: PokemonMemoryAlbum { store.memoryAlbum }
    private var town: PokopiaTownState { album.town }
    /// 마을 개발도. 파생이라 매번 다시 센다 — 192칸 집계 + 주민 16 이라 화면 한 번 그리는 비용에 묻힌다.
    private var development: PokopiaTown.TownDevelopment {
        PokopiaTown.development(town.terrain, residents: town.residents)
    }

    var body: some View {
        // 캔버스가 504×315pt 라 창을 최소 크기로 줄이면 넘친다. 고정 높이 칸은 넘친 내용을
        // 숨기지 않으므로(`defect-log.md`) 스크롤 컨테이너로 감싼다.
        ScrollView([.vertical, .horizontal]) {
            VStack(alignment: .leading, spacing: 10) {
                header
                brushBanner
                PokopiaTownCanvas(town: town, residents: residentSprites,
                                  outfit: store.state.outfit,
                                  avatarCell: avatarCell, working: working,
                                  onTap: shape)
                Text(lifeLine)
                    .font(.callout)
                    .foregroundStyle(PokedoroTheme.ink)
                    .frame(maxWidth: 512, alignment: .leading)
                habitatBoard
                if let feedback {
                    Text(feedback).font(.caption).foregroundStyle(PokedoroTheme.red)
                }
                residentList
            }
            .padding(12)
        }
        .sheet(isPresented: $transforming) { PokopiaTransformSheet(store: store) }
        .alert("\(evicting?.name ?? "") 내보낼까요?", isPresented: .init(
            get: { evicting != nil }, set: { if !$0 { evicting = nil } })) {
            Button("취소", role: .cancel) { evicting = nil }
            Button("내보내기", role: .destructive) {
                if let resident = evicting { _ = album.evictTownResident(speciesID: resident.speciesID) }
                evicting = nil
            }
        } message: {
            Text("다시 찾아올 수도 있지만, 지금 마을에서는 사라져요.")
        }
    }

    // MARK: 머리말

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("포코피아 마을").font(.headline)
                Text("집중 세션을 마치면 마을 환경에 맞는 포켓몬이 찾아와요.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            // 상한이 아니라 **정원**을 보여 준다 — 상한(16)은 개발도가 열어 주기 전엔 닿을 수
            // 없는 수라, 그것만 적으면 사용자가 "16까지 그냥 차는 것" 으로 읽는다.
            VStack(alignment: .trailing, spacing: 1) {
                Text("마을 인구 \(town.residents.count)/\(development.capacity)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(town.residents.count >= development.capacity
                                     ? PokedoroTheme.red : .secondary)
                Text("환경 Lv.\(development.level) \(development.name) · 지형 \(development.habitats)/\(TownTerrain.allCases.count) · 정착 \(development.settled)/\(town.residents.count)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: 512, alignment: .leading)
    }

    /// 브러시 배너 — **팔레트를 대신한다.** 변신하지 않았으면 그 사실과 다음 동작을 말한다.
    private var brushBanner: some View {
        HStack(spacing: 8) {
            if let brush = store.townBrush {
                PokopiaTerrainSwatch(terrain: brush, side: 26)
                VStack(alignment: .leading, spacing: 1) {
                    Text("밀 수 있는 것: \(brush.name)").font(.caption.weight(.semibold))
                    // 목표를 조작 옆에 둔다 — 문턱(`habitatThreshold`)이 코드에만 있던 동안
                    // 사용자는 몇 칸을 밀어야 무슨 일이 생기는지 알 방법이 없었다.
                    Text(brushHint(brush))
                        .font(.caption2).foregroundStyle(.secondary)
                }
            } else {
                Image(systemName: "theatermasks").foregroundStyle(PokedoroTheme.red)
                VStack(alignment: .leading, spacing: 1) {
                    Text("변신해야 마을을 만들 수 있어요.").font(.caption.weight(.semibold))
                    Text(store.townTransformCandidates.isEmpty
                         ? "도감에 기록된 포켓몬이 생기면 변신할 수 있어요."
                         : "도감의 포켓몬으로 변신하면 그 타입의 지형을 밀 수 있어요.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button {
                transforming = true
            } label: {
                Label(town.dittoForm == nil ? "변신" : "바꾸기", systemImage: "theatermasks")
            }
            .font(.caption)
            .disabled(store.townTransformCandidates.isEmpty)

            Button { album.undoTownEdit(); feedback = nil } label: {
                Image(systemName: "arrow.uturn.backward")
            }
            .disabled(!album.canUndoTownEdit)
            .accessibilityLabel("실행 취소")

            Button { album.redoTownEdit(); feedback = nil } label: {
                Image(systemName: "arrow.uturn.forward")
            }
            .disabled(!album.canRedoTownEdit)
            .accessibilityLabel("다시 실행")
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .frame(maxWidth: 512, alignment: .leading)
        .background(store.townBrush == nil ? PokedoroTheme.red.opacity(0.09)
                                           : PokedoroTheme.blue.opacity(0.10),
                    in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    // MARK: 서식 현황 (무엇을 하면 되는가)

    /// 지형별 서식 현황표. **이 화면의 목표가 여기 있다** — 지형을 문턱까지 밀면 그 타입이
    /// 찾아온다는 규칙이 지금까지 코드(`PokopiaTown.habitatThreshold`)에만 있었다.
    ///
    /// 판정은 하지 않는다. 칸 수·문턱·부르는 타입은 전부 `PokopiaTown.habitats` 가 준다 —
    /// 화면이 자기 계산을 더하면 같은 표가 둘이 된다.
    private var habitatBoard: some View {
        let habitats = PokopiaTown.habitats(town.terrain)
        let welcoming = habitats.filter(\.isWelcoming)
        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text("서식 현황").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text("한 지형을 \(PokopiaTown.habitatThreshold)칸 이상 만들면 그 타입이 찾아오고, 마을 정원이 \(PokopiaTown.residentsPerHabitat)자리 늘고 환경 레벨이 1 올라요")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            // 보상 시점. 이 탭에서 굴리는 것이 아니라 집중 세션이 굴린다는 것을 말해 준다 —
            // 안 적으면 마을을 다 만들어 놓고 아무 일도 안 일어나는 화면으로 남는다.
            //
            // **정원이 찼을 때를 먼저 가른다.** 안 가르면 "찾아올 수 있어요" 가 거짓이 되고,
            // 사용자는 세션을 아무리 마쳐도 아무도 안 오는 이유를 알 수 없다.
            Text(nextArrivalLine(welcoming: welcoming))
                .font(.caption)
                .foregroundStyle(welcoming.isEmpty || isFull ? PokedoroTheme.red : PokedoroTheme.ink)
            ForEach(habitats) { habitat in
                habitatRow(habitat)
            }
            // 복합 서식지. 판정은 `PokopiaTown.compositeHabitats` 가 한다 — 여기서 맞닿음을 다시 세면 표가 둘이 된다.
            Text("복합 서식지")
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                .padding(.top, 4)
            Text("문턱을 넘은 두 지형이 상하좌우로 맞닿으면 두 타입을 함께 가진 포켓몬이 먼저 찾아와요")
                .font(.caption2).foregroundStyle(.secondary)
            ForEach(PokopiaTown.compositeHabitats(town.terrain)) { composite in
                compositeRow(composite)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .frame(maxWidth: 512, alignment: .leading)
        .background(PokedoroTheme.mint.opacity(0.10),
                    in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private var isFull: Bool { town.residents.count >= development.capacity }

    /// 다음 손님 한 줄. 좁은 조건이 먼저 이긴다 — **정원 → 부르는 타입 없음 → 정상**
    /// (`PokopiaTownLife.line` 이 쓰는 순서 규칙과 같다).
    private func nextArrivalLine(welcoming: [PokopiaTown.HabitatStatus]) -> String {
        if isFull {
            return "정원이 찼어요(\(development.capacity)자리). 새 지형을 \(PokopiaTown.habitatThreshold)칸 만들면 \(PokopiaTown.residentsPerHabitat)자리가 더 열려요."
        }
        // **이 분기는 실전에서 안 밟힌다** — 192칸을 8종에 나누면 비둘기집 원리로 적어도 한
        // 종이 24칸을 갖고 24 > 문턱 6 이다(`PokopiaTownTests` 의 `terrain(welcomingHabitats:)`
        // 주석이 그 근거다). 그래도 남긴다: 지우면 빈 목록이 "집중 세션을 마치면  타입 중" 이라는
        // 문장으로 새고, 격자 크기를 줄이는 변경이 그 길을 연다.
        if welcoming.isEmpty {
            return "아직 아무 타입도 부르지 않아요. 지형을 \(PokopiaTown.habitatThreshold)칸까지 밀어 보세요."
        }
        let types = welcoming.flatMap(\.types).map(\.name).joined(separator: "·")
        return "집중 세션을 마치면 \(types) 타입 중 한 마리가 찾아올 수 있어요."
    }

    private func habitatRow(_ habitat: PokopiaTown.HabitatStatus) -> some View {
        HStack(spacing: 7) {
            PokopiaTerrainSwatch(terrain: habitat.terrain, side: 22)
            Text(habitat.terrain.name)
                .font(.caption.weight(.medium))
                .frame(width: 44, alignment: .leading)
            Text("\(habitat.tiles)칸")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(habitat.isWelcoming ? PokedoroTheme.mint : .secondary)
                .frame(width: 40, alignment: .leading)
            Text(habitat.isWelcoming
                 // "…를" 이 아니라 "…타입을" 이다 — 타입 이름 뒤에 조사를 직접 붙이면 받침에서
                 // 어긋난다("악 를"). "타입" 을 끼우면 어느 목록이 와도 조사가 맞는다
                 // (`MemoryHomeRoomLife` 의 "와/과" 규칙과 같은 처방).
                 ? "\(habitat.types.map(\.name).joined(separator: "·")) 타입을 부르는 중"
                 : "\(habitat.remaining)칸 더 — \(habitat.types.map(\.name).joined(separator: "·")) 타입으로 변신하면 밀 수 있어요")
                .font(.caption2)
                .foregroundStyle(habitat.isWelcoming ? .secondary : .secondary)
                .lineLimit(1)
            Spacer()
        }
    }

    /// 복합 서식지 한 줄. 견본 둘(조합의 두 지형) · 이름 · 상태 문장.
    private func compositeRow(_ composite: PokopiaTown.CompositeStatus) -> some View {
        HStack(spacing: 7) {
            HStack(spacing: 2) {
                PokopiaTerrainSwatch(terrain: composite.recipe.first, side: 16)
                PokopiaTerrainSwatch(terrain: composite.recipe.second, side: 16)
            }
            Text(composite.recipe.name)
                .font(.caption.weight(.medium))
                .frame(width: 88, alignment: .leading)
            Text(compositeLine(composite))
                .font(.caption2)
                .foregroundStyle(composite.isFormed ? PokedoroTheme.mint : .secondary)
                .lineLimit(1)
            Spacer()
        }
    }

    /// 복합 줄의 문장. 좁은 조건이 먼저 이긴다 — **성립 → 문턱 미달 → 떨어져 있음**(`nextArrivalLine` 과 같은 순서 규칙).
    private func compositeLine(_ composite: PokopiaTown.CompositeStatus) -> String {
        let recipe = composite.recipe
        if composite.isFormed {
            let first = PokopiaTown.typesMaking(recipe.first).map(\.name).joined(separator: "·")
            let second = PokopiaTown.typesMaking(recipe.second).map(\.name).joined(separator: "·")
            // "…타입을" — 타입 이름 뒤에 조사를 직접 붙이지 않는다(서식 줄과 같은 처방).
            return "성립 — \(first) × \(second) 두 타입을 함께 가진 포켓몬이 먼저 와요"
        }
        if !composite.bothWelcoming {
            // "…지형을" — 지형 이름(모래·나무·바위는 받침이 없다) 뒤에도 조사를 직접 붙이지 않는다(`shape` 의 처방).
            return "\(recipe.first.name)·\(recipe.second.name) 지형을 각각 \(PokopiaTown.habitatThreshold)칸 이상 만들면 열려요"
        }
        return "두 지형이 다 있어요 — 상하좌우로 맞닿게 이어 보세요"
    }

    /// 브러시 배너의 둘째 줄. 지금 밀고 있는 지형이 문턱에 얼마나 가까운지를 조작 옆에 둔다.
    private func brushHint(_ brush: TownTerrain) -> String {
        let status = PokopiaTown.habitats(town.terrain).first { $0.terrain == brush }
        guard let status else { return "칸을 누르면 그 자리로 가서 지형을 바꿔요." }
        if status.isWelcoming {
            return "칸을 누르면 지형을 바꿔요. \(brush.name) \(status.tiles)칸 — 이미 문턱을 넘었어요."
        }
        return "칸을 누르면 지형을 바꿔요. \(brush.name) \(status.tiles)/\(PokopiaTown.habitatThreshold)칸 — \(status.remaining)칸 더 밀면 손님이 와요."
    }

    // MARK: 주민 목록

    private var residentList: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text("마을 인구").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                // 축 B 의 조작법. 서식 현황 부제가 축 A 를 말하듯, 여기가 정착이 레벨을 올린다는 사실을 말한다 —
                // 안 적으면 "정착 2/3" 이 무엇을 위한 숫자인지 화면에 없다.
                Text("주민 절반 이상이 정착하면 환경 레벨 +1, 정원을 채우고 전원 정착하면 +1 더")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            if town.residents.isEmpty {
                Text("아직 아무도 살지 않아요.").font(.caption2).foregroundStyle(.secondary)
            } else {
                // 도착 순서를 지킨다 — 정렬하면 "누가 먼저 왔는지" 가 화면에서 사라진다.
                ForEach(town.residents) { resident in
                    residentRow(resident)
                }
            }
        }
        .frame(maxWidth: 512, alignment: .leading)
    }

    private func residentRow(_ resident: TownResident) -> some View {
        // 정착 지형은 파생이다 — 판정표는 `PokopiaTown.settledTerrain` 하나이고 화면은 계산을 더하지 않는다.
        let home = PokopiaTown.settledTerrain(resident, terrain: town.terrain)
        let settled = home != nil
        return HStack(spacing: 8) {
            PokopiaResidentView(speciesID: resident.speciesID, isShiny: false, side: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(resident.name).font(.caption.weight(.medium)).lineLimit(1)
                Text(home.map { "\($0.name)에 살아요" } ?? "살던 자리를 찾는 중이에요")
                    .font(.caption2)
                    .foregroundStyle(settled ? .secondary : PokedoroTheme.red)
            }
            Spacer()
            Button("내보내기") { evicting = resident }.font(.caption2)
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(settled ? PokedoroTheme.mint.opacity(0.14) : PokedoroTheme.red.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: 동작

    /// 칸 하나를 민다. 아바타가 그 자리로 옮겨가고 먼지가 한 번 뜬다.
    private func shape(col: Int, row: Int) {
        guard let brush = store.townBrush else {
            feedback = "먼저 변신해야 지형을 바꿀 수 있어요."
            return
        }
        // 아바타는 **거절 여부와 무관하게** 옮긴다 — 누른 자리로 가는 것이 조작의 피드백이다.
        withAnimation(.easeOut(duration: 0.18)) { avatarCell = (col, row) }
        guard album.shapeTownTile(col: col, row: row, to: brush) else {
            // 이름 뒤에 조사를 직접 붙이지 않는다 — 모래·나무·바위는 받침이 없어 "모래이에요" 가
            // 된다. `지형` 을 끼우면 8종 전부 맞는다(타입 이름의 "…타입을" 과 같은 처방).
            feedback = "이미 \(brush.name) 지형이에요."
            return
        }
        feedback = nil
        // 일회성 연출(`CompanionView` 의 `dittoBurst` 패턴). 프레임 루프를 만들지 않는다.
        withAnimation(.easeOut(duration: 0.12)) { working = true }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 420_000_000)
            withAnimation(.easeOut(duration: 0.25)) { working = false }
        }
    }

    private var lifeLine: String {
        PokopiaTownLife.line(residents: town.residents, terrain: town.terrain,
                            season: MemoryHomeSeason.current(),
                            timeOfDay: MemoryHomeTimeOfDay.current(),
                            now: Date())
    }

    /// 그릴 주민. 자리는 `PokopiaTown.residentSpot` 이 정한다(자기 지형 위).
    private var residentSprites: [PokopiaTownCanvas.Resident] {
        let dayKey = CompanionStore.dayKey(Date())
        return town.residents.map { resident in
            let spot = PokopiaTown.residentSpot(resident, terrain: town.terrain, dayKey: dayKey)
            return .init(id: resident.speciesID, speciesID: resident.speciesID,
                         col: spot.col, row: spot.row)
        }
    }
}


// MARK: - 아이소메트릭 캔버스

/// 마을 격자를 아이소메트릭 마름모로 그린다. 값은 전부 `PokopiaTownIso` 에서 오고 여기서는
/// `Path` 만 만든다 — 색·높이·여백을 뷰가 정하면 배너 견본과 마을이 갈린다.
///
/// **뒤에서 앞으로** 그린다(`col + row` 오름차순). 앞 칸이 뒤 칸의 측면을 덮어야 격자가
/// 이어진 땅으로 보이고, 순서를 뒤집으면 솟은 바위가 앞 칸에 잘려 보인다.
///
/// 타일을 굽지 않는다 — 도트 판은 8장을 `@State` 에 굽고 192번 그렸는데, 마름모는 `Path`
/// 채우기라 구울 것이 없다. `CGImage` 캐시가 사라진 만큼 상태가 하나 줄었다.
struct PokopiaTownCanvas: View {
    struct Resident: Identifiable {
        let id: Int
        let speciesID: Int
        let col: Int
        let row: Int
    }

    let town: PokopiaTownState
    let residents: [Resident]
    let outfit: TrainerOutfit
    let avatarCell: (col: Int, row: Int)
    let working: Bool
    let onTap: (Int, Int) -> Void

    private var canvasSize: CGSize { PokopiaTownIso.canvasSize }

    var body: some View {
        Canvas { context, size in
            // 하늘. 마름모 격자는 사각 캔버스의 네 귀퉁이를 비우므로, 그 자리를 채우지 않으면
            // 격자가 잘려 나간 것처럼 보인다.
            context.fill(Path(CGRect(origin: .zero, size: size)),
                         with: .linearGradient(
                            Gradient(colors: [Color(rgb: PokopiaTownIso.skyTop),
                                              Color(rgb: PokopiaTownIso.skyBottom)]),
                            startPoint: .zero, endPoint: .init(x: 0, y: size.height)))
            for depth in 0...(PokopiaTown.columns + PokopiaTown.rows - 2) {
                for col in 0..<PokopiaTown.columns {
                    let row = depth - col
                    guard let index = PokopiaTown.index(col: col, row: row),
                          town.terrain.indices.contains(index) else { continue }
                    let terrain = town.terrain[index]
                    context.drawIsoTile(
                        terrain,
                        center: PokopiaTownIso.center(col: col, row: row,
                                                      elevation: PokopiaTownIso.elevation(terrain)),
                        halfWidth: PokopiaTownIso.tileWidth / 2,
                        skirt: PokopiaTownIso.skirt(terrain),
                        jitter: PokopiaTownIso.jitter(col: col, row: row))
                }
            }
        }
        .frame(width: canvasSize.width, height: canvasSize.height)
        .overlay { standees }
        .contentShape(Rectangle())
        .onTapGesture { location in
            // 높이를 아는 판정이다 — 솟은 타일의 보이는 윗면이 그 타일로 잡힌다(`cell(at:terrain:)`).
            guard let cell = PokopiaTownIso.cell(at: location, terrain: town.terrain) else { return }
            onTap(cell.col, cell.row)
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        }
        .accessibilityLabel("마을 지형 \(PokopiaTown.columns)×\(PokopiaTown.rows) 격자")
    }

    /// 땅 위에 서 있는 것들. 스프라이트는 비동기로 오는 SwiftUI 뷰라 `Canvas` 안이 아니라
    /// 위에 얹는다(`Canvas` 의 그리기는 동기다).
    ///
    /// ponytail: 스프라이트 레이어가 지형 **전체** 위에 온다 — 나무 뒤에 선 주민이 나무 앞으로
    /// 보인다. 칸별 가리기가 필요해지면 스프라이트도 `Canvas` 안에서 그려야 하고(로드된
    /// `NSImage` 를 `@State` 로 모아 두는 형태), 그때 깊이순으로 지형과 섞는다.
    private var standees: some View {
        ZStack {
            // 앞쪽(깊이가 큰 쪽)이 나중에 그려져 위로 온다. 정렬하지 않으면 도착 순서가
            // 그리기 순서가 되어 뒷줄 주민이 앞줄을 가린다.
            ForEach(residents.sorted { $0.col + $0.row < $1.col + $1.row }) { resident in
                standee(col: resident.col, row: resident.row, side: 34) {
                    PokopiaResidentView(speciesID: resident.speciesID, isShiny: false, side: 34)
                }
            }
            // 아바타는 늘 맨 위다 — 조작의 커서라, 주민 뒤에 숨으면 내가 어디 있는지 모른다.
            standee(col: avatarCell.col, row: avatarCell.row, side: 44) { avatar }
        }
        // 탭은 격자가 받는다 — 스프라이트가 가로채면 주민이 서 있는 칸을 못 민다.
        .allowsHitTesting(false)
    }

    /// 타일 위에 세우는 것 — 그림자 타원 + 내용. **발이 윗면 중심에 닿게** 아래를 기준으로
    /// 놓는다. 그림자가 없으면 스프라이트가 땅에 붙지 않고 공중에 뜬 스티커로 보인다.
    private func standee<Content: View>(col: Int, row: Int, side: CGFloat,
                                        @ViewBuilder content: () -> Content) -> some View {
        let terrain = PokopiaTown.index(col: col, row: row)
            .flatMap { town.terrain.indices.contains($0) ? town.terrain[$0] : nil }
        // 솟은 바위 위에 서면 그림자도 같이 올라간다 — 지형 높이를 안 보면 발만 땅에 남는다.
        let foot = PokopiaTownIso.center(col: col, row: row,
                                         elevation: terrain.map(PokopiaTownIso.elevation) ?? 0)
        return ZStack {
            Ellipse()
                .fill(.black.opacity(0.2))
                .frame(width: PokopiaTownIso.tileWidth * 0.5,
                       height: PokopiaTownIso.tileHeight * 0.42)
                .position(x: foot.x, y: foot.y + 1)
            content()
                .frame(width: side, height: side)
                .position(x: foot.x, y: foot.y - side / 2 + 4)
        }
    }

    private var avatar: some View {
        ZStack {
            PokopiaTownAvatarView(dittoForm: town.dittoForm, outfit: outfit, side: 44)
            if working {
                // 작업 먼지. 글리프이므로 `glyphFont` 를 쓴다 — 읽는 글자가 아니다.
                Text("💨")
                    .font(PokedoroTheme.glyphFont(size: 15))
                    .offset(x: 18, y: 2)
                    .transition(.opacity)
            }
        }
    }
}

/// 브러시 배너·변신 시트의 지형 견본. 캔버스와 **같은 함수**로 그리므로 배너의 색과 마을의
/// 색이 갈릴 수 없다. 견본은 좁아서 소품이 잘리기 쉬우니 중심을 아래로 내려 잡는다.
struct PokopiaTerrainSwatch: View {
    let terrain: TownTerrain
    let side: CGFloat

    var body: some View {
        Canvas { context, size in
            let halfWidth = size.width * 0.34
            context.drawIsoTile(terrain,
                                center: .init(x: size.width / 2, y: size.height * 0.66),
                                halfWidth: halfWidth, skirt: halfWidth * 0.45, jitter: 0)
        }
        .frame(width: side, height: side)
        .accessibilityLabel(terrain.name)
    }
}

// MARK: - 마름모 한 칸

private extension GraphicsContext {
    /// 마름모 한 칸 — 윗면 + 좌·우 측면 + 소품. **캔버스와 배너 견본이 이 함수 하나를 쓴다.**
    ///
    /// 소품 크기는 전부 `halfWidth` 의 배수다 — 그래서 13pt 견본과 36pt 타일이 같은 그림을 낸다.
    /// 픽셀 값을 박으면 견본에서 나무가 타일보다 커진다.
    mutating func drawIsoTile(_ terrain: TownTerrain, center: CGPoint, halfWidth: CGFloat,
                              skirt: CGFloat, jitter: Int) {
        drawIsoBlock(center: center, halfWidth: halfWidth, skirt: skirt,
                     rgb: PokopiaTownIso.topColor(terrain), grid: true)
        drawProp(terrain, center: center, halfWidth: halfWidth, jitter: jitter)
    }

    /// 아이소메트릭 블록 하나 — 윗면 마름모 + 좌·우 측면. 타일도 이것이고 바위도 이것이다
    /// (크기와 색만 다르다). 소품을 다른 도법으로 그리면 그 소품만 세계에서 떠 보인다.
    mutating func drawIsoBlock(center: CGPoint, halfWidth: CGFloat, skirt: CGFloat,
                               rgb: UInt32, grid: Bool) {
        let halfHeight = halfWidth / 2
        let top = CGPoint(x: center.x, y: center.y - halfHeight)
        let right = CGPoint(x: center.x + halfWidth, y: center.y)
        let bottom = CGPoint(x: center.x, y: center.y + halfHeight)
        let left = CGPoint(x: center.x - halfWidth, y: center.y)
        let dropped: (CGPoint) -> CGPoint = { .init(x: $0.x, y: $0.y + skirt) }

        // 측면을 먼저, 윗면을 나중에 — 측면이 윗면 경계를 1px 넘어도 윗면이 덮는다.
        fill(Self.quad(left, bottom, dropped(bottom), dropped(left)),
             with: .color(Color(rgb: PokopiaTownIso.shaded(rgb, PokopiaTownIso.leftShade))))
        fill(Self.quad(bottom, right, dropped(right), dropped(bottom)),
             with: .color(Color(rgb: PokopiaTownIso.shaded(rgb, PokopiaTownIso.rightShade))))
        let face = Self.quad(top, right, bottom, left)
        fill(face, with: .color(Color(rgb: rgb)))
        // 칸선. 실틈을 덮으면서 격자를 고르게 만든다 — 근거는 `PokopiaTownIso.gridShade`.
        if grid {
            stroke(face, with: .color(Color(rgb: PokopiaTownIso.shaded(rgb,
                                                                       PokopiaTownIso.gridShade))),
                   lineWidth: 0.6)
        }
    }

    /// 타일 위 소품. 지형을 색만으로 가르면 나무와 풀밭, 바위와 흙이 화면에서 헷갈린다 —
    /// 실루엣이 있어야 한 눈에 갈린다.
    mutating func drawProp(_ terrain: TownTerrain, center: CGPoint, halfWidth hw: CGFloat,
                           jitter: Int) {
        switch terrain {
        case .tree:
            fill(Path(roundedRect: CGRect(x: center.x - 0.14 * hw, y: center.y - 0.78 * hw,
                                          width: 0.28 * hw, height: 0.88 * hw),
                      cornerRadius: 0.1 * hw),
                 with: .color(Color(rgb: PokopiaTownIso.Prop.trunk)))
            fill(Path(ellipseIn: CGRect(x: center.x - 0.72 * hw, y: center.y - 1.78 * hw,
                                        width: 1.44 * hw, height: 1.22 * hw)),
                 with: .color(Color(rgb: PokopiaTownIso.Prop.canopy)))
            fill(Path(ellipseIn: CGRect(x: center.x - 0.55 * hw, y: center.y - 1.72 * hw,
                                        width: 0.9 * hw, height: 0.7 * hw)),
                 with: .color(Color(rgb: PokopiaTownIso.Prop.canopyLit)))
        case .rock:
            // 바위는 **작은 블록**이다 — 타일과 같은 도법이라 세계에서 떠 보이지 않는다.
            // 타원 두 겹으로 그렸던 판은 바위를 여러 칸 밀면 같은 돌기가 줄지어 레고 판처럼
            // 보였다. `jitter` 로 칸마다 크기·자리를 흔들어 능선으로 읽히게 한다.
            let wobble = CGFloat(jitter) - 2
            drawIsoBlock(center: .init(x: center.x + wobble * 0.05 * hw,
                                       y: center.y - 0.34 * hw + wobble * 0.02 * hw),
                         halfWidth: (0.46 + CGFloat(jitter % 3) * 0.05) * hw,
                         skirt: 0.34 * hw,
                         rgb: PokopiaTownIso.Prop.boulder, grid: false)
        case .flower:
            let petals = PokopiaTownIso.Prop.petals
            // 마름모 안쪽 네 자리. `jitter` 가 칸마다 조금 돌려, 이어 붙은 꽃밭이 같은 도장을
            // 찍은 것처럼 보이지 않게 한다.
            let spots: [(CGFloat, CGFloat)] = [(-0.42, 0.06), (0.02, -0.20),
                                               (0.34, 0.10), (-0.06, 0.30)]
            for (order, spot) in spots.enumerated() {
                let radius = 0.13 * hw
                let x = center.x + (spot.0 + CGFloat(jitter) * 0.02) * hw
                let y = center.y + (spot.1 + CGFloat((jitter + order) % 3) * 0.03) * hw
                fill(Path(ellipseIn: CGRect(x: x - radius, y: y - radius * 0.8,
                                            width: radius * 2, height: radius * 1.6)),
                     with: .color(Color(rgb: petals[(jitter + order) % petals.count])))
            }
        case .water:
            // 잔물결 두 줄. **정지 그림이다** — 이 화면에 도는 것을 만들지 않는다
            // (`defect-log.md` "에너지 (상시 표시 애니메이션)" 부류).
            for wave in [(x: -0.34, y: -0.10, width: 0.50), (x: 0.12, y: 0.20, width: 0.36)] {
                fill(Path(roundedRect: CGRect(x: center.x + wave.x * hw, y: center.y + wave.y * hw,
                                              width: wave.width * hw, height: 0.1 * hw),
                          cornerRadius: 0.05 * hw),
                     with: .color(Color(rgb: PokopiaTownIso.Prop.waterCrest).opacity(0.8)))
            }
        case .grass, .soil, .sand, .path:
            // 소품 없음. 평평한 바닥은 색과 측면만으로 읽힌다 — 여기에 점을 흩뿌리면 192칸에서
            // 노이즈가 된다. `default:` 를 쓰지 않는 이유는 지형이 늘 때 컴파일 에러로 알게 하려는 것.
            break
        }
    }

    /// 네 점 다각형. `Path` 를 네 번 쓰는 코드가 세 번 반복되므로 여기 한 줄로 모은다.
    static func quad(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, _ d: CGPoint) -> Path {
        var path = Path()
        path.move(to: a)
        path.addLine(to: b)
        path.addLine(to: c)
        path.addLine(to: d)
        path.closeSubpath()
        return path
    }
}

fileprivate extension Color {
    /// `0xRRGGBB`. 도트 팔레트(`PixelPalette.colors`)와 같은 표기라 저장소에 색 형식이 하나다.
    init(rgb: UInt32) {
        self.init(.sRGB,
                  red: Double((rgb >> 16) & 0xFF) / 255,
                  green: Double((rgb >> 8) & 0xFF) / 255,
                  blue: Double(rgb & 0xFF) / 255)
    }
}
