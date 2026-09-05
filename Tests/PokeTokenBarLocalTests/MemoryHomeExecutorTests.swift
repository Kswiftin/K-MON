import Foundation
import Testing
@testable import PokeTokenBar

/// 터미널이 부탁한 Memory Home 동작을 **앱이** 실행하는 자리.
///
/// 창구가 없는 첫 라이브 기능이다 — 앨범은 소켓이 아니라 `CompanionStore` 가 이미 들고 있는
/// 파일이라, 실행기가 `companion.memoryAlbum` 을 그대로 쓴다. 대신 **재광고 하나**만 닫아
/// 준다(`refreshMemoryHome`): 공개 닉네임이 바뀌면 LAN 광고 이름도 함께 바뀌어야 하고, 그
/// 일은 소켓을 든 `MemoryHomeVisitCenter` 가 한다.
@MainActor
@Suite("MemoryHomeExecutorTests")
struct MemoryHomeExecutorTests {

    /// 새 세이브는 **알 하나**다 — 동행도 가구도 없다. 이 기능은 방을 꾸미는 일이라 둘 다
    /// 있어야 검증이 되므로, 픽스처가 동행 하나와 가구 재고를 직접 세운다.
    ///
    /// 상점을 지나지 않는 이유: 새 세이브의 별의조각이 0 이라 `buy` 가 거절한다. 여기서 보는
    /// 것은 배치 규칙이고 구매 규칙은 다른 테스트의 몫이다.
    private func makeStore(in directory: URL, furniture: Int = 0) -> CompanionStore {
        let store = CompanionStore(clock: { Date(timeIntervalSince1970: 1_700_000_000) },
                                   fileURL: directory.appendingPathComponent("state.json"))
        store.setLanguage(.ko)
        // **두 마리**를 세운다. 한 마리뿐이면 룸메이트 테스트가 `guard` 로 빠져나가 본문을
        // 한 줄도 밟지 않는다 — 초록이지만 아무것도 지키지 않는 상태였고, `^0` 이 그것을 드러냈다.
        let mon = MonState(baseID: 25, pathIDs: [25], stageIndex: 0, usedAtStage: 0,
                           rarity: .common, totalForms: 1)
        // 룸메이트 정원(3)을 넘겨 보려면 동행 + 넷이 필요하다.
        let others = (0..<4).map { index in
            MonState(baseID: 133 + index, pathIDs: [133 + index], stageIndex: 0, usedAtStage: 0,
                     rarity: .common, totalForms: 1)
        }
        store.debugSetBoxedMons([mon] + others)
        store.switchCompanion(to: mon.id)
        if furniture > 0 { store.debugSetItemCount(.roomBed, furniture) }
        return store
    }

    private func execute(_ action: PokedoroRequest.Action, on store: CompanionStore,
                         refresh: (() -> Void)? = nil) async -> PokedoroReply {
        let request = PokedoroRequest(id: UUID(), action: action, requestedAt: Date())
        var executor = PokedoroRequestExecutor(timer: FocusTimer(), companion: store)
        executor.refreshMemoryHome = refresh
        return await executor.execute(request)
    }

    // MARK: 기분과 스타일

    @Test func testSettingTheMoodReachesTheAlbum() async {
        let directory = storeFixtureDirectory("home-exec-mood")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = makeStore(in: directory)

        let reply = await execute(.homeMood(.annoyed), on: store)

        #expect(reply.succeeded, "\(reply.message)")
        #expect(store.memoryAlbum.mood() == .annoyed)
        #expect(reply.message.contains(MemoryHomeMoodStyle.name(.annoyed, L(.ko))),
                "고른 기분을 되읽어 말해야 무엇이 걸렸는지 안다")
    }

    /// **잠긴 스타일은 거절이고 조건을 말한다.** 앨범이 조용히 무시하므로, 성공으로 답하면
    /// 사용자는 방이 바뀐 줄 알고 다음 일을 한다.
    @Test func testALockedRoomStyleIsRefusedWithItsRequirement() async {
        let directory = storeFixtureDirectory("home-exec-style")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = makeStore(in: directory)
        let locked = MemoryHomeRoomStyle.allCases.first { !store.memoryAlbum.isRoomStyleUnlocked($0) }

        guard let locked else { return }   // 전부 해금된 세이브에서는 볼 것이 없다
        let reply = await execute(.homeStyle(locked), on: store)

        #expect(!reply.succeeded)
        #expect(store.memoryAlbum.roomStyle != locked)
        #expect(reply.message.contains(MemoryHomeNames.requirement(locked, L(.ko))),
                "무엇을 하면 열리는지 말해야 다음에 할 일을 안다")
    }

    @Test func testAnUnlockedRoomStyleIsSelected() async {
        let directory = storeFixtureDirectory("home-exec-style-ok")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = makeStore(in: directory)

        #expect(await execute(.homeStyle(.campus), on: store).succeeded)
        #expect(store.memoryAlbum.roomStyle == .campus)
    }

    // MARK: 글

    /// 앨범의 길이 규칙(1–60자·줄바꿈 금지)을 **앨범이** 판정한다. 거절을 삼키면 필드가
    /// 고장난 것처럼 보인다 — 앱 화면이 같은 이유로 빨간 줄을 남긴다.
    @Test func testTheAlbumsOwnValidationDecidesAndTheReasonIsPassedOn() async {
        let directory = storeFixtureDirectory("home-exec-text")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = makeStore(in: directory)

        let tooLong = String(repeating: "가", count: 61)
        let refused = await execute(.homeMessage(text: tooLong), on: store)
        #expect(!refused.succeeded)
        #expect(store.memoryAlbum.memoryHomeAccess.profileMessage != tooLong)

        let ok = await execute(.homeMessage(text: "작은 방"), on: store)
        #expect(ok.succeeded, "\(ok.message)")
        #expect(store.memoryAlbum.memoryHomeAccess.profileMessage == "작은 방")
    }

    /// **닉네임을 바꾸면 다시 광고한다.** 빠뜨리면 광고 중인 이름과 자기 필터가 갈라져, 자기
    /// 집이 남의 집 목록에 뜬다(앱 화면이 같은 순서를 지킨다).
    @Test func testChangingTheNicknameReAdvertises() async {
        let directory = storeFixtureDirectory("home-exec-nick")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = makeStore(in: directory)
        var refreshed = 0

        let reply = await execute(.homeNickname(name: "lukas"), on: store) { refreshed += 1 }

        #expect(reply.succeeded, "\(reply.message)")
        #expect(store.memoryAlbum.memoryHomePublicNickname == "lukas")
        #expect(refreshed == 1, "재광고를 안 불렀다")

        // 거절된 닉네임은 **다시 광고하지 않는다** — 바뀐 것이 없다.
        let bad = await execute(.homeNickname(name: "빈 칸 있음"), on: store) { refreshed += 1 }
        #expect(!bad.succeeded)
        #expect(refreshed == 1)
    }

    @Test func testAQuickNoteLandsInTheTimeline() async throws {
        let directory = storeFixtureDirectory("home-exec-note")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = makeStore(in: directory)
        let mon = try #require(store.ownedMons.first)

        let reply = await execute(.homeNote(body: "오늘은 좋았다"), on: store)

        #expect(reply.succeeded, "\(reply.message)")
        #expect(store.memoryAlbum.timeline(for: mon.id).contains { $0.body == "오늘은 좋았다" })
    }

    /// 앨범의 길이 규칙(280자)도 **앨범이** 판정한다 — 여기서 다시 세면 한쪽만 관대해진다.
    @Test func testAnOverlongNoteIsRefused() async {
        let directory = storeFixtureDirectory("home-exec-note-long")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = makeStore(in: directory)

        let reply = await execute(.homeNote(body: String(repeating: "가", count: 281)), on: store)
        #expect(!reply.succeeded)
        #expect(reply.message.contains("280"), "무엇이 한도인지 말해야 고칠 수 있다")
    }

    /// 동행이 없으면 남길 곳이 없다 — 조용히 성공하면 사용자는 기록이 어디로 갔는지 찾는다.
    @Test func testANoteWithoutACompanionIsRefused() async {
        let directory = storeFixtureDirectory("home-exec-note-alone")
        defer { try? FileManager.default.removeItem(at: directory) }
        // 알만 있는 새 세이브다 — 픽스처를 안 쓴다.
        let store = CompanionStore(clock: { Date(timeIntervalSince1970: 1_700_000_000) },
                                   fileURL: directory.appendingPathComponent("state.json"))
        store.setLanguage(.ko)

        let reply = await execute(.homeNote(body: "한 줄"), on: store)
        #expect(!reply.succeeded)
        #expect(reply.message.contains("동행"))
    }

    // MARK: 가구

    /// 칸 번호는 **격자 한 곳**을 지나 놓인다. 보유하지 않은 가구는 거절이고, 사유가 갈린다 —
    /// 없는 칸과 없는 재고는 사용자가 할 일이 다르다.
    @Test func testPlacingFurnitureFoldsTheCellAndSplitsItsRefusals() async {
        let directory = storeFixtureDirectory("home-exec-place")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = makeStore(in: directory)

        // 재고가 없다.
        let broke = await execute(.homePlace(item: .roomBed, cell: 12), on: store)
        #expect(!broke.succeeded)
        #expect(store.memoryAlbum.memoryHomeAccess.placedDecor.isEmpty)

        // 격자 밖은 **재고와 무관하게** 거절이다.
        let outside = await execute(.homePlace(item: .roomBed, cell: HomeScreen.cellCount + 1),
                                    on: store)
        #expect(!outside.succeeded)
        #expect(outside.message != broke.message, "격자 밖과 재고 부족을 갈라 말해야 한다")

        // 재고를 주면 놓인다.
        store.debugSetItemCount(.roomBed, 1)
        let placed = await execute(.homePlace(item: .roomBed, cell: 12), on: store)
        #expect(placed.succeeded, "\(placed.message)")
        #expect(store.memoryAlbum.memoryHomeAccess.placedDecor.count == 1)
    }

    /// 방이 가득 찬 것과 재고가 없는 것을 **갈라 말한다.** `isDecorCellAvailable` 이 셋을 한
    /// `Bool` 로 접으므로, 실행기가 다시 가르지 않으면 사용자는 무엇을 해야 할지 모른다
    /// (치우는 것과 사는 것은 다른 일이다).
    @Test func testAFullRoomSaysItIsFullRatherThanOutOfStock() async {
        let directory = storeFixtureDirectory("home-exec-full")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = makeStore(in: directory, furniture: PokemonMemoryAlbum.decorLimit + 1)

        for cell in 1...PokemonMemoryAlbum.decorLimit {
            #expect(await execute(.homePlace(item: .roomBed, cell: cell), on: store).succeeded,
                    "\(cell)번 칸에 못 놓았다")
        }
        let reply = await execute(.homePlace(item: .roomBed, cell: 40), on: store)

        #expect(!reply.succeeded)
        #expect(reply.message.contains("\(PokemonMemoryAlbum.decorLimit)"),
                "상한이 몇인지 말해야 무엇을 치울지 안다")
        #expect(reply.message.contains("home remove"))
    }

    /// 이미 가구가 있는 칸은 **세 번째 사유**다.
    @Test func testATakenCellSaysSo() async {
        let directory = storeFixtureDirectory("home-exec-taken")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = makeStore(in: directory, furniture: 2)

        #expect(await execute(.homePlace(item: .roomBed, cell: 12), on: store).succeeded)
        let reply = await execute(.homePlace(item: .roomBed, cell: 12), on: store)
        #expect(!reply.succeeded)
        #expect(reply.message.contains("칸"))
    }

    /// 치우기는 **화면이 찍은 번호**로 한다. 목록 밖 번호는 첫 가구로 접히지 않는다.
    @Test func testRemovingUsesThePrintedNumberAndRefusesOutsideIt() async {
        let directory = storeFixtureDirectory("home-exec-remove")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = makeStore(in: directory, furniture: 1)
        _ = await execute(.homePlace(item: .roomBed, cell: 12), on: store)

        let missing = await execute(.homeRemove(number: 4), on: store)
        #expect(!missing.succeeded)
        #expect(store.memoryAlbum.memoryHomeAccess.placedDecor.count == 1, "엉뚱한 가구를 치웠다")

        #expect(await execute(.homeRemove(number: 1), on: store).succeeded)
        #expect(store.memoryAlbum.memoryHomeAccess.placedDecor.isEmpty)
    }

    /// 초기화·되돌리기. **되돌릴 것이 없으면 거절이다** — 성공으로 답하면 사용자는 되돌아간
    /// 줄 알고 다시 꾸민다.
    @Test func testResetAndUndoWorkTogetherAndRefuseWhenThereIsNothingToDo() async {
        let directory = storeFixtureDirectory("home-exec-reset")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = makeStore(in: directory)

        #expect(!(await execute(.homeUndo, on: store).succeeded), "되돌릴 것이 없다")
        #expect(!(await execute(.homeRedo, on: store).succeeded), "다시 실행할 것이 없다")
        #expect(!(await execute(.homeReset, on: store).succeeded), "치울 가구가 없다")

        store.debugSetItemCount(.roomBed, 2)
        _ = await execute(.homePlace(item: .roomBed, cell: 12), on: store)
        _ = await execute(.homePlace(item: .roomBed, cell: 20), on: store)
        #expect(store.memoryAlbum.memoryHomeAccess.placedDecor.count == 2)

        #expect(await execute(.homeReset, on: store).succeeded)
        #expect(store.memoryAlbum.memoryHomeAccess.placedDecor.isEmpty)
        #expect(await execute(.homeUndo, on: store).succeeded)
        #expect(store.memoryAlbum.memoryHomeAccess.placedDecor.count == 2, "초기화가 안 되돌아갔다")
        #expect(await execute(.homeRedo, on: store).succeeded)
        #expect(store.memoryAlbum.memoryHomeAccess.placedDecor.isEmpty)
    }

    // MARK: 룸메이트

    /// 룸메이트는 **`party` 번호로 켜고 끈다**(같은 명령이 두 일을 한다 — 화면의 체크 표시와
    /// 같은 모양이다).
    @Test func testRoommateTogglesByPartyNumber() async throws {
        let directory = storeFixtureDirectory("home-exec-roommate")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = makeStore(in: directory)
        let other = try #require(store.chatRosterEntries.first { !$0.isActive })
        let number = TUIRender.printedRosterNumber(index: other.index)

        #expect(await execute(.homeRoommate(number: number), on: store).succeeded)
        #expect(store.memoryAlbum.memoryHomeAccess.roommateIDs.contains(other.id))
        #expect(await execute(.homeRoommate(number: number), on: store).succeeded)
        #expect(!store.memoryAlbum.memoryHomeAccess.roommateIDs.contains(other.id))
    }

    /// 정원(3)을 넘기면 **거절이고 정원을 말한다.** `setRoommates` 는 조용히 잘라 내므로,
    /// 성공으로 답하면 사용자는 넷째가 들어간 줄 안다.
    @Test func testRoommatesBeyondTheLimitAreRefusedWithTheLimit() async throws {
        let directory = storeFixtureDirectory("home-exec-roommate-cap")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = makeStore(in: directory)
        let others = store.chatRosterEntries.filter { !$0.isActive }
        #expect(others.count > PokemonMemoryAlbum.roommateLimit,
                "정원을 넘겨 볼 수 있어야 이 테스트가 뜻을 갖는다")

        for entry in others.prefix(PokemonMemoryAlbum.roommateLimit) {
            let number = TUIRender.printedRosterNumber(index: entry.index)
            #expect(await execute(.homeRoommate(number: number), on: store).succeeded)
        }
        let extra = try #require(others.dropFirst(PokemonMemoryAlbum.roommateLimit).first)
        let reply = await execute(
            .homeRoommate(number: TUIRender.printedRosterNumber(index: extra.index)), on: store)

        #expect(!reply.succeeded)
        #expect(reply.message.contains("\(PokemonMemoryAlbum.roommateLimit)"))
        #expect(store.memoryAlbum.memoryHomeAccess.roommateIDs.count
                == PokemonMemoryAlbum.roommateLimit)
    }

    /// 목록 밖 번호는 거절이다 — `party` 를 보라고 말한다.
    @Test func testARoommateNumberOutsideTheRosterIsRefused() async {
        let directory = storeFixtureDirectory("home-exec-roommate-bad")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = makeStore(in: directory)

        let reply = await execute(.homeRoommate(number: 99), on: store)
        #expect(!reply.succeeded)
        #expect(reply.message.contains("party"))
    }
}
