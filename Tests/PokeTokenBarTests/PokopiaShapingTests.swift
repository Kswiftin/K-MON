import XCTest
@testable import PokeTokenBar

// MARK: 포코피아 마을 — 지형 밀기(비용 없음) · 브러시 게이트 · 되돌리기

@MainActor
final class PokopiaShapingTests: XCTestCase {
    private func album(_ tag: String = "pokopia-shaping") -> PokemonMemoryAlbum {
        PokemonMemoryAlbum(fileURL: memoryAlbumURL(tag))
    }

    private func resident(_ speciesID: Int, _ type: PokemonType = .water,
                          at date: Date = Date(timeIntervalSince1970: 1_000)) -> TownResident {
        TownResident(speciesID: speciesID, name: "주민\(speciesID)", types: [type], arrivedAt: date)
    }

    // MARK: 비용이 없다

    /// **이 회차의 핵심 변화.** 티켓이 없으므로 같은 지형을 몇 번이든 밀 수 있다 —
    /// "원하는 지형의 티켓이 나올 때까지 기다린다" 가 사라졌다는 것이 이 단정의 뜻이다.
    func testShapingHasNoCostAndRepeatsFreely() throws {
        let album = album()
        for col in 0..<PokopiaTown.columns {
            XCTAssertTrue(album.shapeTownTile(col: col, row: 0, to: .water), "col \(col)")
        }
        let firstRow = album.town.terrain.prefix(PokopiaTown.columns)
        XCTAssertTrue(firstRow.allSatisfy { $0 == .water }, "한 줄을 통째로 물로 못 바꿨다")
    }

    /// 같은 지형으로 다시 미는 것은 no-op 이다 — undo 스택에 빈 항목을 쌓지 않는다.
    func testReshapingTheSameTerrainIsANoOp() {
        let album = album()
        XCTAssertFalse(album.shapeTownTile(col: 0, row: 0, to: .grass), "이미 풀인 칸")
        XCTAssertFalse(album.canUndoTownEdit, "no-op 이 undo 스택을 더럽혔다")
    }

    func testShapingOutsideTheGridIsRejected() {
        let album = album()
        XCTAssertFalse(album.shapeTownTile(col: PokopiaTown.columns, row: 0, to: .water))
        XCTAssertFalse(album.shapeTownTile(col: 0, row: PokopiaTown.rows, to: .water))
        XCTAssertFalse(album.shapeTownTile(col: -1, row: -1, to: .water))
        XCTAssertEqual(album.town.terrain, PokopiaTown.defaultTerrain, "거절했는데 지형이 바뀌었다")
    }

    // MARK: 브러시 게이트 (변신이 유일한 도구)

    /// 변신하지 않으면 브러시가 없다. **이 판정이 무너지면 변신이 다시 장식이 된다.**
    func testBrushIsNilWithoutATransform() {
        XCTAssertNil(PokopiaTown.brush(dittoFormTypes: nil))
        XCTAssertNil(PokopiaTown.brush(dittoFormTypes: []), "빈 타입 배열도 '모른다' 다")
        XCTAssertEqual(PokopiaTown.brush(dittoFormTypes: [.water]), .water)
        XCTAssertEqual(PokopiaTown.brush(dittoFormTypes: [.fire, .flying]), .sand,
                       "첫 타입이 브러시를 정한다")
    }

    /// 18 타입 전부가 브러시를 가진다 — 어떤 종으로 변신해도 뭔가는 밀 수 있다.
    func testEveryTypeYieldsABrush() {
        for type in PokemonType.allCases {
            XCTAssertNotNil(PokopiaTown.brush(dittoFormTypes: [type]), "\(type)")
        }
    }

    // MARK: 되돌리기

    /// **주민은 되돌리기 대상이 아니다.** 지형을 되돌릴 때 찾아온 포켓몬이 사라지면 그건
    /// 되돌리기가 아니라 상실이다 — 스냅샷에 주민을 넣으면 이 테스트가 빨개진다.
    func testUndoRestoresTerrainButNeverRemovesResidents() throws {
        let album = album()
        XCTAssertTrue(album.shapeTownTile(col: 3, row: 3, to: .water))
        XCTAssertTrue(album.admitTownResident(resident(7)))

        album.undoTownEdit()

        let index = try XCTUnwrap(PokopiaTown.index(col: 3, row: 3))
        XCTAssertEqual(album.town.terrain[index], .grass, "지형이 안 되돌아왔다")
        XCTAssertEqual(album.town.residents.map(\.speciesID), [7],
                       "실행 취소가 이사 온 주민을 지웠다")
    }

    /// 이사는 undo 스택을 건드리지 않는다 — 사건이라 되돌릴 대상이 아니다.
    func testAdmittingAResidentDoesNotEnterTheUndoStack() {
        let album = album()
        XCTAssertTrue(album.admitTownResident(resident(7)))
        XCTAssertFalse(album.canUndoTownEdit)
    }

    func testRedoReappliesTheShaping() throws {
        let album = album()
        XCTAssertTrue(album.shapeTownTile(col: 1, row: 1, to: .soil))
        XCTAssertFalse(album.canRedoTownEdit, "되돌리기 전에 다시 하기가 켜져 있다")
        album.undoTownEdit()
        XCTAssertTrue(album.canRedoTownEdit)
        album.redoTownEdit()
        let index = try XCTUnwrap(PokopiaTown.index(col: 1, row: 1))
        XCTAssertEqual(album.town.terrain[index], .soil)
        XCTAssertFalse(album.canRedoTownEdit, "다 쓴 다시 하기가 켜진 채 남았다")
    }

    /// 빈 스택에서 되돌리기·다시 하기는 아무 일도 안 한다. 화면은 `.disabled` 로 막지만
    /// 함수 자체가 안전해야 한다.
    func testUndoAndRedoOnEmptyStacksAreNoOps() {
        let album = album()
        let before = album.town
        album.undoTownEdit(); album.redoTownEdit()
        XCTAssertEqual(album.town, before)
    }

    /// 되돌리기 깊이 상한. 넘으면 가장 오래된 것부터 버린다.
    func testUndoStackIsCappedAtTheDeclaredDepth() throws {
        let album = album()
        for step in 0...PokopiaTown.undoDepth {
            let col = step % PokopiaTown.columns
            let row = step / PokopiaTown.columns
            XCTAssertTrue(album.shapeTownTile(col: col, row: row, to: .soil), "step \(step)")
        }
        for _ in 0..<PokopiaTown.undoDepth { album.undoTownEdit() }
        XCTAssertFalse(album.canUndoTownEdit, "상한을 넘겼는데 스택이 안 잘렸다")
        let first = try XCTUnwrap(PokopiaTown.index(col: 0, row: 0))
        XCTAssertEqual(album.town.terrain[first], .soil, "버려진 스냅샷의 편집까지 되돌아갔다")
    }

    /// 방 undo 와 마을 undo 가 섞이지 않는다.
    func testRoomAndTownUndoStacksAreIndependent() throws {
        let album = album()
        XCTAssertTrue(album.shapeTownTile(col: 2, row: 2, to: .water))
        XCTAssertNotNil(album.placeDecor(.roomBed, at: .init(x: 0.5, y: 0.5),
                                         ownedItems: [ItemKind.roomBed.rawValue: 1]))
        album.undoRoomEdit()
        let index = try XCTUnwrap(PokopiaTown.index(col: 2, row: 2))
        XCTAssertEqual(album.town.terrain[index], .water, "방 실행 취소가 마을 지형을 되돌렸다")
    }

    // MARK: 주민 받기 · 내보내기

    /// **같은 종은 두 번 오지 않는다.** 이것이 이사의 멱등이고, 세션 단위 가드를 안 쓰는 근거다.
    func testTheSameSpeciesIsNeverAdmittedTwice() {
        let album = album()
        XCTAssertTrue(album.admitTownResident(resident(7)))
        XCTAssertFalse(album.admitTownResident(resident(7)), "같은 종이 두 번 들어왔다")
        XCTAssertEqual(album.town.residents.count, 1)
    }

    func testAdmittingStopsAtThePopulationLimit() {
        let album = album()
        for offset in 0..<(PokopiaTown.populationLimit + 3) {
            _ = album.admitTownResident(resident(offset + 1))
        }
        XCTAssertEqual(album.town.residents.count, PokopiaTown.populationLimit)
    }

    /// 이름 없는 주민·타입 없는 주민·음수 종·**그릴 수 없는 종**은 받지 않는다 — 화면에서 결함처럼
    /// 보이는 줄이다.
    ///
    /// 스프라이트 케이스는 리뷰에서 뒤늦게 들어왔다. 이 테스트가 `admitTownResident` 의 `guard` 를
    /// 그대로 베껴 조건을 셌기 때문에, `guard` 에 빠진 조건은 테스트에도 빠져 **초록인 채로**
    /// 형제 검증기(`normalized`)와 갈려 있었다 — 그 경로로 들어온 주민은 저장되고 다음 실행에서
    /// 소리 없이 사라진다.
    func testMalformedResidentsAreRefused() {
        let album = album()
        XCTAssertFalse(album.admitTownResident(
            TownResident(speciesID: 7, name: "  ", types: [.water], arrivedAt: Date())))
        XCTAssertFalse(album.admitTownResident(
            TownResident(speciesID: 7, name: "꼬부기", types: [], arrivedAt: Date())))
        XCTAssertFalse(album.admitTownResident(
            TownResident(speciesID: 0, name: "꼬부기", types: [.water], arrivedAt: Date())))
        let spriteless = PokemonAssets.spriteGaps.min() ?? 990
        XCTAssertFalse(album.admitTownResident(resident(spriteless)),
                       "스프라이트 없는 종이 들어왔다 — 다음 실행의 정규화가 소리 없이 지운다")
        XCTAssertTrue(album.town.residents.isEmpty)
    }

    /// 받는 자리와 거르는 자리가 **같은 술어**를 쓴다. 두 자리가 갈리면 한쪽으로 들어온 주민이
    /// 다른 쪽에서 사라지는데, 그 갈라짐은 각 자리를 따로 테스트하는 한 보이지 않는다 — 그래서
    /// 같은 입력을 둘 다에 넣고 답이 같은지 직접 맞댄다.
    func testAdmitAndNormalizeAgreeOnEveryMalformedResident() {
        let spriteless = PokemonAssets.spriteGaps.min() ?? 990
        let probes: [TownResident] = [
            resident(7),
            TownResident(speciesID: 7, name: " ", types: [.water], arrivedAt: Date()),
            TownResident(speciesID: 7, name: "꼬부기", types: [], arrivedAt: Date()),
            TownResident(speciesID: 0, name: "꼬부기", types: [.water], arrivedAt: Date()),
            TownResident(speciesID: -3, name: "꼬부기", types: [.water], arrivedAt: Date()),
            resident(spriteless),
        ]
        for probe in probes {
            let admitted = album("pokopia-parity-\(probe.speciesID)-\(probe.name.count)-\(probe.types.count)")
                .admitTownResident(probe)
            var state = PokopiaTownState(); state.residents = [probe]
            let kept = !PokopiaTown.normalized(state).residents.isEmpty
            XCTAssertEqual(admitted, kept,
                           "두 검증기가 갈렸다 — admit=\(admitted) normalize=\(kept): \(probe)")
        }
        // 정상 주민 하나는 둘 다 통과해야 한다 — 전부 거절해도 위 등식은 통과하므로 따로 센다.
        XCTAssertTrue(PokopiaTown.isAdmissible(resident(7)))
    }

    func testEvictingWorksAndEvictingAStrangerIsRejected() {
        let album = album()
        XCTAssertTrue(album.admitTownResident(resident(7)))
        XCTAssertFalse(album.evictTownResident(speciesID: 999))
        XCTAssertTrue(album.evictTownResident(speciesID: 7))
        XCTAssertTrue(album.town.residents.isEmpty)
    }

    /// 도착 순서를 지킨다 — 정렬하면 "누가 먼저 왔는지" 가 화면에서 사라진다.
    func testResidentsKeepArrivalOrder() {
        let album = album()
        for id in [25, 7, 4] { _ = album.admitTownResident(resident(id)) }
        XCTAssertEqual(album.town.residents.map(\.speciesID), [25, 7, 4])
    }

    // MARK: 읽기 전용 앨범(터미널)

    /// 가드는 `save()` 한 곳에 있다("호출부마다 가드를 두면 새 mutator 가 무검사로 남는다").
    /// 마을 mutator 는 새로 만든 쓰기 경로이므로 그 전제를 여기서 검증한다.
    func testReadOnlyAlbumNeverWritesTheTownToDisk() {
        let file = memoryAlbumURL("pokopia-shaping-readonly")
        let readOnly = PokemonMemoryAlbum(fileURL: file, isReadOnly: true)

        _ = readOnly.shapeTownTile(col: 2, row: 2, to: .water)
        _ = readOnly.setDittoForm(25, registeredSpecies: [25])
        _ = readOnly.admitTownResident(resident(7))

        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path),
                       "읽기 전용 앨범이 파일을 만들었다 — 앱의 쓰기를 덮어쓸 수 있다")
        XCTAssertEqual(PokemonMemoryAlbum(fileURL: file).town, PokopiaTownState(),
                       "새로 열었더니 읽기 전용 세션의 편집이 남아 있다")
    }
}
