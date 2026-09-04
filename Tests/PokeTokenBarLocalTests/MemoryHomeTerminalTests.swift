import Foundation
import Testing
@testable import PokeTokenBar

/// Memory Home 을 터미널에서 보고 방을 꾸미는 자리.
///
/// **이 기능은 채널을 타지 않는다.** 앨범은 세이브 **옆 파일**(`memory.json`)에 저장되므로
/// 터미널이 읽기 전용으로 직접 읽는다 — 웨이브 런과 같은 쪽이고, 대전·방·교환·경매와 갈리는
/// 지점이다. 그래서 `pokedoro home` 은 앱이 꺼져 있어도 답한다.
///
/// 고유한 위험은 **읽기 전용이 앨범까지 덮지 않는다**는 것이었다. `CompanionStore` 는 자기
/// 파일만 지켰고, 그 스토어가 들고 있는 앨범·대화 기록은 아무 가드 없이 `save()` 를 불렀다 —
/// 이 단계가 앨범을 건드리는 첫 단계라 여기서 막는다.
@MainActor
@Suite("MemoryHomeTerminalTests")
struct MemoryHomeTerminalTests {

    // MARK: 읽기 전용이 옆 파일까지 덮는가

    /// **터미널이 여는 저장소 셋 중 둘이 무가드였다.** 세이브는 `isReadOnly` 로 막혀 있었지만
    /// 앨범과 대화 기록은 같은 프로세스에서 그대로 썼다. 앱이 켜져 있는 동안 터미널이 그 파일을
    /// 쓰면 잠금이 없어 나중 쓰기가 앞 쓰기를 통째로 덮는다 — 세이브에서 막아 둔 것과 같은 부류다.
    @Test func testAReadOnlyAlbumCannotWriteItsFile() throws {
        let directory = storeFixtureDirectory("home-readonly")
        defer { try? FileManager.default.removeItem(at: directory) }
        let albumURL = directory.appendingPathComponent(CompanionStorageLocations.memoryFileName)

        // 쓰기 가능한 앨범이 파일을 만든다 — 그게 있어야 "안 덮었다" 를 볼 수 있다.
        let writable = PokemonMemoryAlbum(fileURL: albumURL)
        writable.setMood(.calm)
        let before = try #require(try? Data(contentsOf: albumURL))

        let readOnly = PokemonMemoryAlbum(fileURL: albumURL, isReadOnly: true)
        #expect(readOnly.mood() == .calm, "읽기는 그대로 된다 — 막는 것은 쓰기뿐이다")
        readOnly.setMood(.annoyed)
        readOnly.selectRoomStyle(.retro)
        readOnly.resetDecor()
        _ = readOnly.addManual(companionID: UUID(), body: "터미널이 쓴 줄")

        let after = try #require(try? Data(contentsOf: albumURL))
        #expect(after == before, "읽기 전용 앨범이 파일을 고쳤다")
    }

    /// 스토어가 읽기 전용이면 **그 스토어가 만든 옆 파일도** 읽기 전용이다. 앨범만 따로 막으면
    /// 다음 호출부가 스토어를 지나 무가드 앨범을 얻는다.
    @Test func testReadOnlyPropagatesFromTheStoreToTheFilesBesideIt() throws {
        let directory = storeFixtureDirectory("home-readonly-store")
        defer { try? FileManager.default.removeItem(at: directory) }
        let stateURL = directory.appendingPathComponent("state.json")
        let albumURL = directory.appendingPathComponent(CompanionStorageLocations.memoryFileName)

        let writable = CompanionStore(fileURL: stateURL)
        writable.memoryAlbum.setMood(.excited)
        let before = try #require(try? Data(contentsOf: albumURL))

        let readOnly = CompanionStore(fileURL: stateURL, isReadOnly: true)
        readOnly.memoryAlbum.setMood(.down)

        #expect((try? Data(contentsOf: albumURL)) == before,
                "읽기 전용 스토어의 앨범이 파일을 고쳤다")
    }

    // MARK: 명령 어휘

    @Test func testEveryHomeSubcommandParsesIntoItsRequest() throws {
        #expect(try PokedoroCommandParser.parse(["home"]) == .home)
        #expect(try PokedoroCommandParser.parse(["home", "mood", "calm"]) == .homeMood(.calm))
        #expect(try PokedoroCommandParser.parse(["home", "style", "retro"]) == .homeStyle(.retro))
        #expect(try PokedoroCommandParser.parse(["home", "note", "오늘", "좋았다"])
                == .homeNote(body: "오늘 좋았다"))
        #expect(try PokedoroCommandParser.parse(["home", "message", "작은", "방"])
                == .homeMessage(text: "작은 방"))
        #expect(try PokedoroCommandParser.parse(["home", "nickname", "lukas"])
                == .homeNickname(name: "lukas"))
        #expect(try PokedoroCommandParser.parse(["home", "roommate", "2"])
                == .homeRoommate(number: 2))
        #expect(try PokedoroCommandParser.parse(["home", "place", "roomBed", "12"])
                == .homePlace(item: .roomBed, cell: 12))
        #expect(try PokedoroCommandParser.parse(["home", "remove", "1"]) == .homeRemove(number: 1))
        #expect(try PokedoroCommandParser.parse(["home", "reset"]) == .homeReset(confirmed: false))
        #expect(try PokedoroCommandParser.parse(["home", "undo"]) == .homeUndo)
        #expect(try PokedoroCommandParser.parse(["home", "redo"]) == .homeRedo)
    }

    /// **닫힌 목록은 조용히 접지 않는다.** 모르는 기분·스타일을 기본값으로 접으면 사용자는
    /// 자기가 무엇을 골랐는지 모른 채 다른 방을 본다(길 이름과 같은 규칙).
    @Test func testUnknownMoodsAndStylesAreNamedNotFolded() {
        #expect(throws: PokedoroCommandError.unknownMood("happy")) {
            try PokedoroCommandParser.parse(["home", "mood", "happy"])
        }
        #expect(throws: PokedoroCommandError.unknownRoomStyle("gothic")) {
            try PokedoroCommandParser.parse(["home", "style", "gothic"])
        }
        // 가구가 아닌 아이템은 방에 놓을 수 없다 — **목록 밖 이름과 갈라 말한다.** 하나로
        // 뭉개면 "그런 아이템이 없다" 고 답하는데, 사탕은 있고 놓을 수만 없는 것이다.
        let notFurniture = ItemKind.allCases.first {
            !ItemKind.memoryHomeFurniture.contains($0) && ItemKind.named($0.rawValue) != nil
        }
        if let notFurniture {
            #expect(throws: PokedoroCommandError.notFurniture(notFurniture.rawValue)) {
                try PokedoroCommandParser.parse(["home", "place", notFurniture.rawValue, "1"])
            }
        }
        #expect(throws: PokedoroCommandError.unknownItem("bogus")) {
            try PokedoroCommandParser.parse(["home", "place", "bogus", "1"])
        }
    }

    /// **확인이 필요한 것은 초기화 하나다.** 가구가 한 번에 사라지고, 되돌리기 기록은 앱
    /// 메모리라 앱을 다시 켜면 없다. 나머지는 전부 한 번에 하나씩 되돌릴 수 있다.
    @Test func testOnlyResettingTheRoomNeedsConfirmation() throws {
        #expect(try PokedoroCommandParser.parse(["home", "reset"]).request == nil)
        #expect(try PokedoroCommandParser.parse(["home", "reset", "--yes"]).request == .homeReset)
        for words in [["home", "mood", "calm"], ["home", "style", "retro"],
                      ["home", "remove", "1"], ["home", "undo"], ["home", "redo"]] {
            #expect(try PokedoroCommandParser.parse(words).request != nil,
                    "\(words.joined(separator: " ")) 가 확인을 요구했다")
        }
    }

    /// `home` 은 앱 전용 목록에서 빠진다 — 방 상태가 파일에 있어 터미널이 직접 읽는다.
    @Test func testHomeIsNoLongerAnAppOnlyCommand() {
        #expect(!PokedoroCommandParser.appOnlyCommands.contains("home"))
    }

    @Test func testEveryHomeActionSurvivesTheRoundTripThroughTheFile() throws {
        let actions: [PokedoroRequest.Action] = [
            .homeMood(.calm), .homeStyle(.retro), .homeNote(body: "한 줄"),
            .homeMessage(text: "대문"), .homeNickname(name: "lukas"),
            .homeRoommate(number: 2), .homePlace(item: .roomBed, cell: 12),
            .homeRemove(number: 1), .homeReset, .homeUndo, .homeRedo,
        ]
        for action in actions {
            let sent = PokedoroRequest(id: UUID(), action: action, requestedAt: Date())
            let back = try JSONDecoder().decode(PokedoroRequest.self,
                                                from: try JSONEncoder().encode(sent))
            #expect(back.action == action, "\(action.name) 이 왕복에서 달라졌다")
        }
        #expect(PokedoroRequest.Action.homePlace(item: .roomBed, cell: 1).name == "home.place")
        // 손으로 고친 파일도 **닫힌 목록**을 지나야 한다.
        #expect(PokedoroRequest.Action(name: "home.mood", argument: "happy") == nil)
        #expect(PokedoroRequest.Action(name: "home.style", argument: "gothic") == nil)
        #expect(PokedoroRequest.Action(name: "home.place", argument: "rare-candy 1") == nil)
        #expect(PokedoroRequest.Action(name: "home.place", argument: "roomBed") == nil)
        #expect(PokedoroRequest.Action(name: "home.place", argument: "roomBed 0") == nil)
        #expect(PokedoroRequest.Action(name: "home.note", argument: "  ") == nil)
        #expect(PokedoroRequest.Action(name: "home.reset", argument: "1") == nil)
    }

    // MARK: 화면 투영

    /// 방의 **칸 번호는 하나의 수 공간**이다. 8×6 격자를 열·행 두 인자로 받으면 터미널에서
    /// 두 번호가 서로 다른 뜻인 자리가 하나 더 늘어난다(경매에서 넷까지 겪었다) — 1–48 한
    /// 숫자로 받고, 그 숫자 → 격자 변환은 **여기 한 곳**을 지난다.
    @Test func testTheGridIsOneNumberSpaceAndFoldsInOnePlace() throws {
        #expect(HomeScreen.cellCount == 48, "8×6 격자다")
        #expect(try #require(HomeScreen.gridPoint(cell: 1)) == (0, 0))
        #expect(try #require(HomeScreen.gridPoint(cell: 8)) == (7, 0))
        #expect(try #require(HomeScreen.gridPoint(cell: 9)) == (0, 1))
        #expect(try #require(HomeScreen.gridPoint(cell: HomeScreen.cellCount)) == (7, 5))
        // 격자 밖은 접지 않는다 — 그대로 첨자로 쓰면 방 밖에 가구가 놓인다.
        #expect(HomeScreen.gridPoint(cell: 0) == nil)
        #expect(HomeScreen.gridPoint(cell: HomeScreen.cellCount + 1) == nil)
        // 접기가 왕복한다 — 화면이 찍는 칸 번호와 실행기가 놓는 칸이 같아야 한다.
        for cell in 1...HomeScreen.cellCount {
            let point = try #require(HomeScreen.gridPoint(cell: cell))
            #expect(HomeScreen.cell(column: point.0, row: point.1) == cell)
        }
    }

    /// 놓인 가구 번호 → id. **접는 자리가 하나뿐이다** — 화면은 번호를 찍고 실행기는 id 로
    /// 치우는데, 두 값을 따로 구하면 목록이 다시 읽히는 사이 다른 가구가 사라진다.
    @Test func testPlacedFurnitureFoldsFromItsNumberToAnID() throws {
        let state = Self.decorated()
        let first = try #require(state.placed.first)
        #expect(HomeScreen.placedID(number: 1, in: state) == first.id)
        #expect(HomeScreen.placedID(number: 9, in: state) == nil)
    }

    /// 화면이 **묶음마다 이름을 달고** 낸다 — 프로필·방·가구·기억.
    @Test func testTheScreenNamesEveryGroupItShows() {
        let lines = HomeScreen.lines(Self.decorated(), width: 74)
        for label in ["오늘", "함께", "기분", "방 스타일", "놓인 가구", "기억"] {
            #expect(lines.contains { $0.contains(label) }, "\(label) 줄이 없다")
        }
        #expect(lines.contains { $0.contains("고디탱") }, "동행 이름이 안 보인다")
        #expect(lines.contains { $0.contains("침대") }, "놓인 가구 이름이 안 보인다")
    }

    /// **잠긴 스타일은 조건을 말한다.** 고를 수 있는 것처럼 찍으면 쳐도 아무 일이 없다.
    @Test func testLockedStylesSayWhatUnlocksThem() {
        let lines = HomeScreen.lines(Self.decorated(), width: 74)
        #expect(lines.contains { $0.contains("진화") },
                "잠긴 스타일의 조건이 안 보이면 왜 못 고르는지 알 수 없다")
        #expect(lines.contains { $0.contains("사용 중") }, "지금 쓰는 스타일이 안 보인다")
    }

    /// 안내는 **지금 할 수 있는 것 하나**를 말한다.
    @Test func testHintsPointAtTheMostUsefulNextCommand() {
        // 기분을 안 골랐으면 그것부터 — 방 문구가 기분으로 갈린다.
        var noMood = Self.decorated()
        noMood.moodName = nil
        #expect(HomeScreen.hints(noMood).contains("home mood"))
        // 되돌릴 것이 있으면 방금 꾸민 뒤다.
        #expect(HomeScreen.hints(Self.decorated()).contains("home undo"))
        // 아무것도 안 놓았으면 놓으라고 말한다.
        var empty = Self.decorated()
        empty.placed = []
        empty.canUndo = false
        #expect(HomeScreen.hints(empty).contains("home place"))

        // 놓여 있고 되돌릴 것이 없으면(앱을 다시 켠 뒤) 평소 안내다 — 세 갈래 모두 다르다.
        var settled = Self.decorated()
        settled.canUndo = false
        let hint = HomeScreen.hints(settled)
        #expect(hint.contains("home remove"), "치우는 방법이 안내에 없다")
        #expect(hint != HomeScreen.hints(empty), "안내가 상태에 따라 갈리지 않는다")
    }

    @Test func testEveryLineFitsTheRequestedWidth() {
        var bare = HomeTerminalState(nickname: "lukas", styleName: "캠퍼스")
        for state in [Self.decorated(), bare] {
            for width in [20, 40, 80] {
                for line in HomeScreen.lines(state, width: width) {
                    #expect(TUIText.displayWidth(line) <= width, "폭 \(width) 에서 넘친 줄: \(line)")
                }
            }
        }
        bare.styles = Self.decorated().styles
        #expect(HomeScreen.lines(bare, width: 20).allSatisfy { TUIText.displayWidth($0) <= 20 })
    }

    /// 동행이 없으면 **그렇다고 말한다.** 앱은 "동행을 기다리고 있어요" 를 띄우고, 터미널이
    /// 빈 줄을 내면 사용자는 화면이 고장난 줄 안다.
    @Test func testAHomeWithoutACompanionSaysSo() {
        var alone = Self.decorated()
        alone.companionName = nil
        #expect(HomeScreen.lines(alone, width: 60).contains { $0.contains("동행") })
    }

    // MARK: 세이브에서 조립한다

    /// 상태는 **앨범과 스토어에서** 나온다. 조립을 한 함수에 두는 이유는 터미널(읽기)과
    /// 실행기(쓰기)가 **같은 번호**를 봐야 하기 때문이다 — 두 곳이 각자 세면 사용자가 고른
    /// 번호와 앱이 치우는 가구가 갈라진다.
    @Test func testTheStateIsAssembledFromTheSaveWithoutTheApp() throws {
        let directory = storeFixtureDirectory("home-state")
        defer { try? FileManager.default.removeItem(at: directory) }
        let stateURL = directory.appendingPathComponent("state.json")
        let store = CompanionStore(fileURL: stateURL)
        store.setLanguage(.ko)
        store.memoryAlbum.setMood(.calm)

        let state = store.homeTerminalState
        #expect(state.decorLimit == 12)
        #expect(state.styleName == MemoryHomeRoomStyle.campus.name(L(.ko)))
        // 기분은 **이모지와 이름을 함께** 싣는다 — 앱 화면이 그렇게 보여 주므로 같은 값이다.
        #expect(state.moodName == MemoryHomeMoodStyle.emoji(.calm)
                + " " + MemoryHomeMoodStyle.name(.calm, L(.ko)))
        #expect(state.styles.contains { $0.isActive }, "지금 쓰는 스타일이 표시돼야 한다")
        #expect(state.styles.count == MemoryHomeRoomStyle.allCases.count)
        // 읽기 전용으로 열어도 같은 값이 나온다 — 이 화면이 앱 없이 도는 근거다.
        let readOnly = CompanionStore(fileURL: stateURL, isReadOnly: true)
        readOnly.setLanguage(.ko)
        #expect(readOnly.homeTerminalState.moodName == state.moodName)
    }

    // MARK: 키 배정

    /// Memory Home 화면도 **누를 키가 없다**(경매와 같은 근거 — 번호 공간이 셋이다).
    /// 이동 키는 `z` 다: 남은 글자가 그것뿐이었다.
    @Test func testTheMemoryHomeScreenTakesNoKeys() {
        #expect(TUIScreen.memoryHome.key == "z")
        #expect(HomeScreen.keys(Self.decorated()).isEmpty)
        for key in ["1", "a", "y", "s", "t"] {
            #expect(TUIKeymap.action(for: .char(Character(key)), screen: .memoryHome,
                                     canWrite: true) == .ignored,
                    "\(key) 가 Memory Home 화면에서 무언가를 했다")
        }
    }

    // MARK: 픽스처

    static func decorated() -> HomeTerminalState {
        var state = HomeTerminalState(nickname: "lukas", styleName: "레트로")
        state.message = "기억을 모으는 작은 방"
        state.visitToday = 2
        state.visitTotal = 41
        state.seasonName = "가을"
        state.isLANOpen = true
        state.companionName = "고디탱"
        state.daysTogether = 37
        state.memoryCount = 12
        state.closenessHearts = 4
        state.moodName = "😌 차분함"
        state.styles = [
            HomeScreen.Style(name: "캠퍼스", isUnlocked: true, isActive: false, requirement: "기본"),
            HomeScreen.Style(name: "레트로", isUnlocked: true, isActive: true,
                             requirement: "배틀 첫 업적"),
            HomeScreen.Style(name: "네이처", isUnlocked: false, isActive: false,
                             requirement: "진화 첫 업적"),
        ]
        state.placed = [HomeScreen.Placed(number: 1, id: UUID(), cell: 12, label: "침대"),
                        HomeScreen.Placed(number: 2, id: UUID(), cell: 20, label: "책상")]
        state.roommates = ["피카츄"]
        state.roomLine = "고디탱이 침대에서 뒹굴고 있다."
        state.pinned = "처음 만난 날"
        state.recent = ["집중 25분을 마쳤다", "진화했다"]
        state.cards = ["첫 만남", "함께 30일"]
        state.canUndo = true
        return state
    }
}
