import Network
import XCTest
import SwiftUI
@testable import PokeTokenBar

// 팝오버 세로 오버플로 가드(#9).
// 증상: "기술 보기" 를 펼치면 팝오버 위(타이머)가 잘리고 기술 4행 중 2행만 보이며 푸터가 사라졌다.
// 원인: 팝오버 콘텐츠에 가로 폭만 있고 높이 상한도 스크롤도 없었다 — NSPopover 는 넘친 만큼을
// 스크롤이 아니라 클리핑으로 처리한다.
//
// 트리거 브랜치를 재현한다: 상한 없는 긴 콘텐츠가 실제로 화면 가용 높이를 넘는지까지 확인해야
// "상한 어서션이 애초에 통과할 조건이었다" 는 false confidence 를 막는다.
@MainActor
final class PopoverLayoutTests: XCTestCase {

    private func renderedHeight(_ view: some View, proposingWidth: CGFloat = PopoverMetrics.width) -> CGFloat {
        NSHostingController(rootView: view)
            .sizeThatFits(in: CGSize(width: proposingWidth, height: .greatestFiniteMagnitude)).height
    }

    private func renderedWidth(_ view: some View, proposing: CGFloat) -> CGFloat {
        NSHostingController(rootView: view)
            .sizeThatFits(in: CGSize(width: proposing, height: 900)).width
    }

    // MARK: 높이 상한

    /// 트리거 재현: 상한이 없으면 긴 콘텐츠는 그대로 자기 높이만큼 요청한다(= 잘리던 조건).
    func testUnboundedContentRequestsMoreThanTheCap() {
        let tall = VStack { Color.clear.frame(height: 3_000) }
        XCTAssertGreaterThan(renderedHeight(tall), PopoverMetrics.maxHeight(screenHeight: 900))
    }

    /// 수정 후: 창 높이가 고정이라 긴 콘텐츠도 그 높이를 넘지 않는다(넘는 부분은 안에서 스크롤).
    func testFixedHeightNeverExceedsItself() {
        let h = PopoverMetrics.height(for: .home, screenHeight: 900)
        let tall = ScrollView { Color.clear.frame(height: 3_000) }.frame(height: h)
        XCTAssertEqual(renderedHeight(tall), h, accuracy: 1)
    }

    /// 짧은 콘텐츠도 같은 높이를 유지한다 — 탭을 바꾸거나 기술 목록을 접었다 펴도 창이 안 흔들린다.
    /// (예전엔 `.fixedSize` 로 자연 높이를 따라가서 펼칠 때마다 팝오버가 커졌다 작아지며 떨렸다.)
    func testShortContentKeepsTheSameHeightAsTallContent() {
        let h = PopoverMetrics.height(for: .home, screenHeight: 900)
        let short = ScrollView { Color.clear.frame(height: 120) }.frame(height: h)
        let tall = ScrollView { Color.clear.frame(height: 3_000) }.frame(height: h)
        XCTAssertEqual(renderedHeight(short), renderedHeight(tall), accuracy: 1)
    }

    /// 상한은 화면 높이에서만 파생된다 — 작은 화면일수록 낮게, 큰 화면에선 화면만큼 커진다.
    func testMaxHeightDerivesFromScreenHeight() {
        XCTAssertEqual(PopoverMetrics.maxHeight(screenHeight: 700),
                       700 - PopoverMetrics.verticalChrome)
        XCTAssertEqual(PopoverMetrics.maxHeight(screenHeight: 1_440),
                       1_440 - PopoverMetrics.verticalChrome)
        XCTAssertEqual(PopoverMetrics.maxHeight(screenHeight: 200), PopoverMetrics.minHeight)
        XCTAssertLessThan(PopoverMetrics.maxHeight(screenHeight: 600),
                          PopoverMetrics.maxHeight(screenHeight: 760))
    }

    /// 탭별 고정 높이는 화면이 넉넉하면 그대로, 좁으면 화면에 맞춰 줄어든다.
    /// 회귀(#9 2차): 720pt 고정 천장 시절엔 1440pt 화면에서도 펼친 홈 탭이 상한을 넘겨
    /// 헤더 첫 줄과 아래 카드가 잘려 보였다 — 화면엔 두 배 넘는 자리가 남아 있는데도.
    func testTabHeightIsFixedOnBigScreensAndClampsOnSmallOnes() {
        XCTAssertEqual(PopoverMetrics.height(for: .home, screenHeight: 1_440),
                       PopoverTab.home.contentHeight)
        XCTAssertEqual(PopoverMetrics.height(for: .collection, screenHeight: 700),
                       700 - PopoverMetrics.verticalChrome)
        // 탭을 옮겨도 창이 뛰지 않도록 모든 탭이 같은 높이를 쓴다.
        XCTAssertEqual(PopoverTab.home.contentHeight, PopoverTab.collection.contentHeight)
        XCTAssertEqual(PopoverTab.battle.contentHeight, PopoverTab.collection.contentHeight)
        XCTAssertEqual(PopoverTab.shop.contentHeight, PopoverTab.collection.contentHeight)
    }

    // MARK: 도전 탭 — 진입점 도달성

    /// **회귀 원본.** 체육관·던전은 친구가 필요 없는 콘텐츠인데 친구 탭 두 단계 안
    /// (친구 → 배틀 → 버튼 줄)에 있었다. 배틀 화면이 `FriendView` 아래로 한 겹 들어가면서
    /// 사실상 닿을 수 없게 됐고, 사용자가 "체육관이 사라졌다"고 보고했다.
    ///
    /// 도달성은 뷰 계층이라 순수 함수로 못 잰다 — 어느 화면이 그 문을 여는지를 소스에서 본다.
    /// 주석은 뺀다(규칙을 설명하는 주석이 같은 이름을 담아 가드가 자기 설명에 걸린다).
    func testSoloChallengesAreReachableFromTheChallengeTabNotBuriedInFriends() throws {
        func code(_ file: String) throws -> String {
            let url = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("Sources/PokeTokenBar/UI/\(file)")
            return try String(contentsOf: url, encoding: .utf8)
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map { line -> String in
                    guard let comment = line.range(of: "//") else { return String(line) }
                    return String(line[..<comment.lowerBound])
                }
                .joined(separator: "\n")
        }
        let challenge = try code("ChallengeView.swift")
        XCTAssertTrue(challenge.contains("nav.showGymLeague = true"), "체육관은 도전 탭에서 연다")
        XCTAssertTrue(challenge.contains("nav.showDungeon = true"), "던전도 같은 자리에서 연다")

        let battle = try code("BattleView.swift")
        XCTAssertFalse(battle.contains("showGymLeague"), "친구 탭 안으로 되돌아가면 다시 파묻힌다")
        XCTAssertFalse(battle.contains("showDungeon"))

        let popover = try code("PopoverView.swift")
        XCTAssertTrue(popover.contains("case .challenge: ChallengeView"), "도전 탭이 이 화면을 연다")
    }

    // MARK: 소유 포켓몬 — 페이지 도달성

    /// 트리거 재현: 한 페이지를 넘긴 마릿수. 페이지가 하나로 머물면 초과분은 다시 도달 불가가 되고,
    /// 그게 스크롤 시절의 결함이었다 — 팝오버 본체 ScrollView 안에 중첩된 격자 ScrollView 가
    /// 스크롤되지 않아, 격자에 들어가는 만큼만 보이고 나머지는 볼 방법이 없었다.
    /// (260 시절 9마리쯤, 520 으로 늘린 뒤 20마리쯤에서 끊겼다.)
    func testARosterThatOverflowsOnePageGetsAnother() {
        XCTAssertEqual(PokemonRosterView.pageCount(ownedCount: PokemonRosterView.pageSize), 1)
        XCTAssertEqual(PokemonRosterView.pageCount(ownedCount: PokemonRosterView.pageSize + 1), 2)
    }

    /// 몇 마리를 가졌든 마지막 한 마리까지 어느 페이지엔가 들어간다 — 페이저로 도달할 수 있다.
    func testEveryOwnedPokemonLandsOnSomePage() {
        let pageSize = PokemonRosterView.pageSize
        for ownedCount in [0, 1, pageSize - 1, pageSize, pageSize + 1, 21, 100] {
            let pages = PokemonRosterView.pageCount(ownedCount: ownedCount)
            XCTAssertGreaterThanOrEqual(pages, 1, "\(ownedCount)마리: 빈 격자라도 한 장은 있어야 한다")
            XCTAssertGreaterThanOrEqual(pages * pageSize, ownedCount,
                                        "\(ownedCount)마리가 \(pages)페이지에 다 안 들어간다")
            // 마지막 페이지에 최소 한 마리는 있어야 한다 — 빈 페이지를 넘기게 두지 않는다.
            XCTAssertLessThan((pages - 1) * pageSize, max(1, ownedCount),
                              "\(ownedCount)마리인데 마지막 페이지가 비어 있다")
        }
    }

    // MARK: 근처 트레이너 — 페이지 도달성

    /// 트리거 재현: 한 페이지를 넘긴 상대 수. 상한(5명)까지만 그리고 나머지는 "그 밖에 n명 더" 문구로만
    /// 알리던 시절엔 **여섯 번째 트레이너에게 신청할 방법이 아예 없었다** — 중첩 스크롤을 걷어내며
    /// 넣은 그 처방이 로스터·도감이 이미 겪은 부류를 그대로 되풀이했다. 상한을 늘리는 것도, 남은 수를
    /// 문구로 알리는 것도 처방이 아니다. 기준은 하나다 — **마지막 한 명에게 도달할 수 있나**.
    func testANearbyListThatOverflowsOnePageGetsAnother() {
        XCTAssertEqual(BattleView.peerPageCount(BattleView.peerPageSize), 1)
        XCTAssertEqual(BattleView.peerPageCount(BattleView.peerPageSize + 1), 2)
    }

    /// 몇 명이 잡히든 마지막 한 명까지 어느 페이지엔가 들어간다 — 페이저로 도달할 수 있다.
    func testEveryNearbyTrainerLandsOnSomePage() {
        let pageSize = BattleView.peerPageSize
        for peerCount in [0, 1, pageSize - 1, pageSize, pageSize + 1, 12, 40] {
            let pages = BattleView.peerPageCount(peerCount)
            XCTAssertGreaterThanOrEqual(pages, 1, "\(peerCount)명: 빈 목록이라도 한 장은 있어야 한다")
            XCTAssertGreaterThanOrEqual(pages * pageSize, peerCount,
                                        "\(peerCount)명이 \(pages)페이지에 다 안 들어간다")
            // 마지막 페이지에 최소 한 명은 있어야 한다 — 빈 페이지를 넘기게 두지 않는다.
            XCTAssertLessThan((pages - 1) * pageSize, max(1, peerCount),
                              "\(peerCount)명인데 마지막 페이지가 비어 있다")
        }
    }

    // MARK: 근처 트레이너 카드 (진행도가 잘리지 않는가)

    private func peerStore(_ language: AppLanguage = .ko) -> CompanionStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("poke-peer-layout-\(UUID().uuidString).json")
        let json = #"{"economyVersion":2,"forcedResetVersion":1,"language":"\#(language.rawValue)"}"#
        try? Data(json.utf8).write(to: url)
        return CompanionStore(provider: StubProvider(value: moveTestLine),
                              clock: { Date(timeIntervalSince1970: 1_755_000_000) },
                              fileURL: url, rng: SeededRNG(seed: 13))
    }

    private func peer(_ name: String, _ advertisement: PeerAdvertisement) -> BattlePeer {
        BattlePeer(name: name, serviceName: "\(name)#abc123",
                   endpoint: .hostPort(host: "127.0.0.1", port: 4_242),
                   advertisement: advertisement)
    }

    /// 가장 긴 랭크 문구를 내는 점수. `maximumPoints` 가 아니다. 최고점은 "Challenger · 99 LP"
    /// (18자)인데 티어 이름이 더 긴 "Grandmaster · 10 LP"(19자) 구간이 있다. 상한값을 최악으로
    /// 가정하면 폭 검증이 진짜 최악보다 좁은 입력을 재고 통과한다.
    private var widestRankPoints: Int {
        (0...BattleRank.maximumPoints).max {
            BattleRank(points: $0).displayName.count < BattleRank(points: $1).displayName.count
        }!
    }

    /// 카드가 그릴 수 있는 최악의 진행도. 여기서 안 잘리면 어떤 상대에서도 안 잘린다. 배지
    /// 분모는 상대가 광고하니 내 카탈로그(16)가 아니라 표시 상한까지 커질 수 있다.
    private var widestAdvertisement: PeerAdvertisement {
        PeerAdvertisement(rankPoints: widestRankPoints,
                          trainerLevel: TrainerLevel.maximumLevel,
                          achievementTiers: PeerAdvertisement.maximumTierCeiling,
                          achievementCeiling: PeerAdvertisement.maximumTierCeiling)
    }

    private func peerRow(_ name: String, _ advertisement: PeerAdvertisement,
                         _ language: AppLanguage = .ko) -> some View {
        PeerRow(store: peerStore(language), peer: peer(name, advertisement),
                isEnabled: true, onChallenge: {})
    }

    /// 카드가 원하는 폭. 행 안에 `Spacer()` 가 있어 넉넉한 제안을 주면 그대로 채우니
    /// (제안 4,000 → 4,000) 이상 폭 측정만으로는 아무것도 알 수 없다. 내용의 이상 크기를 보려면
    /// `fixedSize` 로 고정해야 한다. 기술 목록은 Spacer 가 없어 그냥 재도 됐다.
    private func intrinsicWidth(_ view: some View) -> CGFloat {
        renderedWidth(view.fixedSize(horizontal: true, vertical: false), proposing: 4_000)
    }

    /// 대조군: 광고가 실린 카드는 빈 카드보다 넓어야 한다. 이게 없으면 누가 레벨·배지 칸을 지워도
    /// 아래 폭 검증이 그냥 통과한다. 총폭 검증은 누가 빠졌는지를 못 잡는다(defect-log).
    func testPeerRowActuallyCarriesTheAdvertisedProgress() {
        let bare = intrinsicWidth(peerRow("Ash", PeerAdvertisement()))
        let advertised = intrinsicWidth(peerRow("Ash", widestAdvertisement))
        XCTAssertGreaterThan(advertised, bare + 20,
                             "레벨·배지가 카드에 실제로 그려지지 않으면 폭 검증이 무의미해진다")
    }

    /// 최악의 진행도를 실은 카드가 세 언어 모두 팝오버 콘텐츠 폭 안에 들어와야 한다.
    /// 버튼 문구가 언어마다 다르다(대결 신청 / Challenge / 対戦を申し込む).
    func testPeerRowFitsTheContentWidthInEveryLanguage() {
        for language in [AppLanguage.ko, .en, .ja] {
            let width = intrinsicWidth(peerRow("Ash", widestAdvertisement, language))
            XCTAssertLessThanOrEqual(width, PopoverMetrics.contentWidth,
                                     "\(language.rawValue): 진행도 줄이 카드 폭을 넘겼다")
        }
    }

    /// 두 줄을 유지해야 한다. 진행도 때문에 세 번째 줄이 생기면 한 페이지 5명 예산이 깨지고,
    /// 여섯 번째 상대에게 도달 못 하던 부류로 되돌아간다.
    func testPeerRowKeepsItsTwoLineHeightRegardlessOfAdvertisement() {
        let bare = renderedHeight(peerRow("Ash", PeerAdvertisement()),
                                  proposingWidth: PopoverMetrics.contentWidth)
        let advertised = renderedHeight(peerRow("Ash", widestAdvertisement),
                                       proposingWidth: PopoverMetrics.contentWidth)
        XCTAssertEqual(advertised, bare, accuracy: 1, "광고가 실리면서 줄이 늘었다")
    }

    /// 상대 이름은 Bonjour 에서 와 길이를 우리가 정하지 못한다. 길면 줄바꿈이 아니라 잘려야
    /// 한다. 줄바꿈되면 카드가 커져 페이지 예산이 무너진다.
    func testALongPeerNameTruncatesInsteadOfGrowingTheRow() {
        let short = renderedHeight(peerRow("Ash", widestAdvertisement),
                                   proposingWidth: PopoverMetrics.contentWidth)
        let long = renderedHeight(peerRow(String(repeating: "트레이너", count: 10), widestAdvertisement),
                                  proposingWidth: PopoverMetrics.contentWidth)
        XCTAssertEqual(long, short, accuracy: 1, "긴 이름이 카드 높이를 키웠다")
    }

    /// 세 언어에서 카드 높이가 같아야 한다. 한 언어에서만 줄바꿈되면 그 언어에서만 목록이 넘친다.
    /// 기술 목록에서 이미 겪은 부류다(CI 118pt vs 로컬 78pt).
    func testPeerRowHeightDoesNotDependOnLanguage() {
        let korean = renderedHeight(peerRow("Ash", widestAdvertisement, .ko),
                                    proposingWidth: PopoverMetrics.contentWidth)
        for language in [AppLanguage.en, .ja] {
            XCTAssertEqual(renderedHeight(peerRow("Ash", widestAdvertisement, language),
                                          proposingWidth: PopoverMetrics.contentWidth),
                           korean, accuracy: 1, "\(language.rawValue) 에서 카드 높이가 달라졌다")
        }
    }

    // MARK: 대화 — 외부 전송 동의 줄

    /// 대조군: 이름이 긴 CLI 는 줄을 더 넓게 만들어야 한다. 이게 없으면 누가 대상 이름을 지워도
    /// 아래 폭 검증은 그냥 통과한다 — 총폭 검증은 누가 빠졌는지를 못 잡는다(defect-log).
    func testTheConsentLineActuallyCarriesTheProviderName() {
        let short = intrinsicWidth(PokemonChatConsentLabel(kind: .codex, language: .ko))    // "Codex"
        let long = intrinsicWidth(PokemonChatConsentLabel(kind: .claude, language: .ko))    // "Claude Code"
        XCTAssertGreaterThan(long, short, "대상 CLI 이름이 안 그려지면 폭 검증이 무의미해진다")
    }

    /// 전송 버튼이 곧 동의이므로 이 줄은 **안전 경계의 표시**다. 팝오버 폭(360)에서 잘리면
    /// 사용자는 어디로 나가는지 못 읽은 채 누르게 된다.
    ///
    /// 앵커는 **이 줄이 실제로 쓰는 예산**이어야 한다. 예전엔 `PopoverMetrics.contentWidth`(332)를
    /// 썼는데 그 상수는 `mainContent` 것이고 대화는 그 형제 가지라 360 을 통째로 받는다(실제 336).
    /// 4pt 더 빡빡해 우연히 안전했을 뿐이라, `PopoverMetrics.padding` 이 10 으로 바뀌면 앵커가
    /// 340 으로 **느슨해져** 실제로 잘리는 338pt 라벨을 통과시킨다 — 막으려던 실패를 통과시킨다.
    func testTheConsentLineFitsTheContentWidthInEveryLanguage() {
        for kind in PokemonChatProviderSafety.verifiedKinds {
            for language in [AppLanguage.ko, .en, .ja] {
                XCTAssertLessThanOrEqual(
                    intrinsicWidth(PokemonChatConsentLabel(kind: kind, language: language)),
                    PokemonChatConsentLabel.contentWidth,
                    "\(language.rawValue)/\(kind.rawValue): 동의 줄이 팝오버 폭을 넘겼다")
            }
        }
    }

    /// 앵커가 뷰의 실제 여백에서 나오는가. 상수만 옮기고 뷰가 옛 여백을 그대로 쓰면 두 벌이 되어
    /// 같은 결함이 되돌아온다 — 뷰가 이 상수를 **쓰는지**는 컴파일러가 지키고, 값이 팝오버 폭에서
    /// 파생되는지는 여기서 지킨다.
    func testTheConsentLineBudgetIsDerivedFromThePopoverItActuallyLivesIn() {
        XCTAssertEqual(PokemonChatConsentLabel.contentWidth,
                       PopoverMetrics.width - PokemonChatConsentLabel.horizontalPadding * 2,
                       "동의 줄 예산이 팝오버 폭과 대화 여백에서 파생되지 않는다")
        XCTAssertEqual(PokemonChatConsentLabel.contentWidth, 336)
    }

    // MARK: 대화 — 칩 줄

    /// 칩 줄은 **가로 스크롤 한 줄**이다. 개수가 늘어 세로로 감기면 그만큼 메시지 영역·입력칸·
    /// 승인 카드가 밀린다 — 승인 카드는 안전 경계라 축소 대상이 아니다(PRD 위험표).
    /// 상태 변경 칩이 붙는 순간 그 높이가 변하는지를 여기서 고정한다.
    ///
    /// 폭은 `PopoverMetrics.width` 다. 칩 줄은 입력칸 `VStack` 의 **형제**라 대화 좌우 여백
    /// (`horizontalPadding`)을 받지 않는다 — `contentWidth`(336) 로 재면 실제보다 24pt 좁은 줄을
    /// 재게 되고, 가로 스크롤은 높이가 폭에 무관해서 그 어긋남이 지금은 우연히 안 보인다.
    /// 줄이 감기도록 바꾸는 순간(이 테스트가 막겠다는 바로 그 변경) 앵커가 틀린다.
    func testActionChipsDoNotMakeTheChipRowTaller() {
        let questions = ["너의 타입이 뭐야?", "지금 기분은 어때?", "오늘의 도감을 보여 줘",
                         "배운 기술을 알려 줘", "너는 어떤 포켓몬이야?", "다음 진화는 언제야?"]
        let bare = renderedHeight(PokemonChatChipRow(actions: [], questions: questions,
                                                     language: .ko, onTap: { _ in }),
                                  proposingWidth: PopoverMetrics.width)
        let withActions = renderedHeight(
            PokemonChatChipRow(actions: [.startFocus, .acceptEvolution, .useRareCandy],
                               questions: questions, language: .ko, onTap: { _ in }),
            proposingWidth: PopoverMetrics.width)

        XCTAssertEqual(withActions, bare, accuracy: 1, "액션 칩이 칩 줄을 두 줄로 만들었다")
    }

    /// 대조군. 위 단언은 "높이가 같다" 만 보므로 **액션 칩을 통째로 지워도** 통과한다 —
    /// 두 팔이 다 질문만 그리면 당연히 같은 높이다. 그래서 여기서는 액션 축만 흔든다:
    /// 질문 없이 액션 하나만 준 줄이 빈 줄보다 높아야 한다. 이걸 안 걸면 `ForEach(actions)` 를
    /// 지운 채로 대화 칩 기능의 유일한 뷰 테스트가 전부 초록으로 남는다.
    func testTheChipRowActuallyDrawsItsActionChips() {
        let empty = renderedHeight(PokemonChatChipRow(actions: [], questions: [],
                                                      language: .ko, onTap: { _ in }),
                                   proposingWidth: PopoverMetrics.width)
        let onlyAction = renderedHeight(PokemonChatChipRow(actions: [.startFocus], questions: [],
                                                           language: .ko, onTap: { _ in }),
                                        proposingWidth: PopoverMetrics.width)
        let onlyQuestion = renderedHeight(PokemonChatChipRow(actions: [], questions: ["너의 타입이 뭐야?"],
                                                             language: .ko, onTap: { _ in }),
                                          proposingWidth: PopoverMetrics.width)

        XCTAssertGreaterThan(onlyAction, empty, "액션 칩이 아무것도 안 그린다")
        XCTAssertGreaterThan(onlyQuestion, empty, "질문 칩이 아무것도 안 그린다")
    }

    /// 칩 하나 잘못 눌렀다고 쓰던 문장이 사라지면 안 된다. 초안은 `PokemonChatStore` 에 살아서
    /// (팝오버가 닫혀도 남으라고 그렇게 뒀다) 되돌릴 `@State` 스냅샷이 없고, 액션 칩은 채워진
    /// 배경으로 줄 **맨 앞**에 앉는다 — 눈이 먼저 닿는 자리라 오타를 부른다.
    func testTappingAChipKeepsWhatTheTrainerWasTyping() {
        XCTAssertEqual(PokemonChatChipRow.composed(draft: "", chip: "25분 집중하자"), "25분 집중하자",
                       "빈 입력칸은 칩 문장 그대로여야 한다")
        XCTAssertEqual(PokemonChatChipRow.composed(draft: "   \n ", chip: "25분 집중하자"), "25분 집중하자",
                       "공백뿐인 입력칸도 비어 있는 것으로 친다 — 전송 버튼이 그렇게 센다")
        XCTAssertEqual(PokemonChatChipRow.composed(draft: "오늘 어땠어?", chip: "25분 집중하자"),
                       "오늘 어땠어? 25분 집중하자", "쓰던 문장이 칩 하나에 지워졌다")
    }

    /// 같은 부류 스윕: 릴레이 방 목록도 LAN 이 길이를 정한다 — 상한도 페이저도 없으면 팝오버가 잘린다.
    func testEveryRelayRoomLandsOnSomePage() {
        let pageSize = PokeathlonView.roomPageSize
        for roomCount in [0, 1, pageSize, pageSize + 1, 20] {
            let pages = PokeathlonView.roomPageCount(roomCount)
            XCTAssertGreaterThanOrEqual(pages * pageSize, roomCount,
                                        "\(roomCount)개 방이 \(pages)페이지에 다 안 들어간다")
            XCTAssertLessThan((pages - 1) * pageSize, max(1, roomCount),
                              "\(roomCount)개인데 마지막 페이지가 비어 있다")
        }
    }

    // MARK: 미션 카드 — 세로 예산

    /// 홈 탭 스크롤 뷰포트 예산. 560pt 창에서 패딩·상단 바·타이머·탭 피커·푸터를 빼면 약 250pt 가
    /// 남고, 파트너 카드(`CompanionHeader`)가 그중 176pt 를 쓴다. 미션 카드가 이 값을 넘으면
    /// 파트너가 뷰포트 밖으로 밀려 홈 탭을 열었을 때 앱의 주인공이 안 보인다.
    private static let missionCardBudget: CGFloat = 100

    private func missionStore(_ language: AppLanguage = .ko) -> CompanionStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("poke-mission-layout-\(UUID().uuidString).json")
        let json = #"{"economyVersion":2,"forcedResetVersion":1,"language":"\#(language.rawValue)"}"#
        try? Data(json.utf8).write(to: url)
        return CompanionStore(provider: StubProvider(value: moveTestLine),
                              clock: { Date(timeIntervalSince1970: 1_755_000_000) },
                              fileURL: url, rng: SeededRNG(seed: 5))
    }

    /// 트리거 재현: 미션마다 `ProgressView` 를 한 줄씩 깔면 예산을 두 배로 넘긴다(첫 버전이 211pt).
    /// 이 대조군이 없으면 아래 예산 검증이 "애초에 통과할 조건이었다"는 false confidence 가 된다.
    func testAGaugePerMissionRowBlowsThroughTheBudget() {
        let gauged = VStack(alignment: .leading, spacing: 6) {
            Text("🎯 미션").font(.caption.weight(.semibold))
            ForEach(MissionBoard.catalog) { mission in
                HStack {
                    Text(mission.id).font(.caption2)
                    Spacer()
                    Text("0/\(mission.target)").font(.caption2)
                }
                ProgressView(value: 0.3)
            }
        }
        .padding(9)
        XCTAssertGreaterThan(renderedHeight(gauged), Self.missionCardBudget * 2,
                             "대조군이 안 넘치면 예산 검증이 무의미해진다")
    }

    /// 미션 카드는 파트너와 한 화면에 공존해야 한다 — 게이지를 행마다 두지 않는 이유가 이것뿐이다.
    func testMissionCardFitsTheHomeViewportBudget() {
        XCTAssertLessThanOrEqual(renderedHeight(MissionBoardView(store: missionStore())),
                                 Self.missionCardBudget)
    }

    /// 예산 여유가 3pt 뿐이라 **언어가 높이를 흔들면 안 된다**. 이름이 한 줄을 넘기는 순간 행이
    /// 통째로 커지는데, 그 회귀를 기술 목록에서 이미 겪었다(CI 118pt vs 로컬 78pt — 한국어 이름만
    /// 짧아 로컬에선 안 걸렸다).
    ///
    /// 지금은 세 언어 다 이름이 짧아 아무것도 줄바꿈되지 않는다 — 즉 이 테스트는 현재
    /// `lineLimit(1)` 을 밟지 못한다. 미션을 더하거나 문구를 늘렸을 때 한 언어만 넘치는 상황을
    /// 잡는 **전방 가드**다. 실패하면 예산이 아니라 그 문구를 줄여야 한다.
    func testMissionCardHeightDoesNotDependOnLanguage() {
        let korean = renderedHeight(MissionBoardView(store: missionStore(.ko)))
        for language in [AppLanguage.en, .ja] {
            XCTAssertEqual(renderedHeight(MissionBoardView(store: missionStore(language))), korean,
                           accuracy: 1, "\(language.rawValue) 에서 행 높이가 달라졌다")
        }
    }

    // MARK: 도감 목표 줄 — 세로 예산

    /// 도감 헤더가 쓸 수 있는 여유. 컬렉션 탭 예산은 `520 − 세그먼트 24 − 헤더 39 − 하단 18 − 간격 24
    /// = 격자 415` 로 잡혔고(`CollectionView.contentHeight`), 그 세그먼트 24pt 를 **목표 줄이 먼저 썼다.**
    /// 그래서 나중에 들어온 도감 | 업적 세그먼트는 이 프레임 밖에 얹혀 있다 — 안으로 넣으면 24pt 가
    /// 이중 장부가 되어 격자 6행이 눌리고 스프라이트가 잘린다.
    ///
    /// 재는 대상은 줄 높이가 아니라 **헤더가 실제로 커지는 양**이다 — 헤더 VStack 의 spacing 5 가 줄과
    /// 함께 따라오므로 줄만 24 와 비교하면 5pt 를 공짜로 봐준다.
    private static let dexHeaderSpacing: CGFloat = 5
    private static let dexGoalStripBudget: CGFloat = 24 - dexHeaderSpacing

    private func dexGoalStore(_ language: AppLanguage = .ko) -> CompanionStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("poke-dexgoal-layout-\(UUID().uuidString).json")
        // 세 축이 **모두 분수로 보이는** 상태 — 종 12/25, 타입 8/9, 이로치 2/3.
        // 한 축이라도 사다리 끝까지 넘으면 그 칸이 "✓" 한 글자가 되어 최악의 폭에서 빠진다.
        let types = ["normal", "fire", "water", "electric", "grass", "ice", "fighting", "poison"]
        let entries = (0..<12).map { i in
            #"{"baseID":\#(100 + i),"finalID":\#(100 + i),"chainOrder":[\#(100 + i)],"rarity":"common","#
                + #""isShiny":\#(i < 2),"types":["\#(types[i % types.count])"]}"#
        }
        let json = #"{"economyVersion":2,"forcedResetVersion":1,"language":"\#(language.rawValue)","#
            + #""dex":[\#(entries.joined(separator: ","))]}"#
        try? Data(json.utf8).write(to: url)
        return CompanionStore(provider: StubProvider(value: moveTestLine),
                              clock: { Date(timeIntervalSince1970: 1_755_000_000) },
                              fileURL: url, rng: SeededRNG(seed: 7))
    }

    /// 트리거 재현: 목표마다 게이지를 한 줄씩 깔면 예산을 통째로 넘긴다(미션 카드가 겪은 그 실수).
    /// 이 대조군이 없으면 아래 예산 검증이 "애초에 통과할 조건이었다"는 false confidence 가 된다.
    func testAGaugePerGoalRowBlowsThroughTheDexHeaderBudget() {
        let gauged = VStack(alignment: .leading, spacing: 4) {
            ForEach(DexGoals.catalog) { goal in
                Text("\(goal.id) 0/\(goal.target)").font(.system(size: 9))
                ProgressView(value: 0.3)
            }
        }
        XCTAssertGreaterThan(renderedHeight(gauged), Self.dexGoalStripBudget * 2,
                             "대조군이 안 넘치면 예산 검증이 무의미해진다")
    }

    /// 목표 줄은 도감 헤더의 남은 24pt 안에 들어가야 한다 — 한 줄로 유지하는 이유가 이것뿐이다.
    func testDexGoalStripFitsTheDexHeaderBudget() {
        XCTAssertLessThanOrEqual(renderedHeight(DexGoalStrip(store: dexGoalStore())),
                                 Self.dexGoalStripBudget)
    }

    /// 축 라벨이 세 언어에서 길이가 다르다(종 / Species / 種). 한 언어에서 줄바꿈되면 그 언어에서만
    /// 격자가 눌린다 — 기술 목록에서 이미 겪은 부류(CI 118pt vs 로컬 78pt)라 전방 가드를 둔다.
    func testDexGoalStripHeightDoesNotDependOnLanguage() {
        let korean = renderedHeight(DexGoalStrip(store: dexGoalStore(.ko)))
        for language in [AppLanguage.en, .ja] {
            XCTAssertEqual(renderedHeight(DexGoalStrip(store: dexGoalStore(language))), korean,
                           accuracy: 1, "\(language.rawValue) 에서 목표 줄 높이가 달라졌다")
        }
    }

    // MARK: 업적 선반 — 세로 예산

    /// 업적 선반은 컬렉션 탭 세그먼트 하나를 차지한다. 6행이라(던전 트랙 2개 추가) 예산은 넉넉하지만
    /// 행마다 게이지를 깔면 미션 카드(211pt)·도감 목표 줄이 겪은 초과를 되풀이한다. 상한을 두는
    /// 이유는 선반이 도감 격자와 **같은 프레임**을 쓰기 때문이다 — 넘치면 세그먼트를 바꿀 때
    /// 스크롤이 생겨 두 화면의 높이가 달라 보인다.
    /// 4행 160pt 기준에서 던전 트랙 2행만큼(행당 ~14pt) 얹었다.
    private static let achievementShelfBudget: CGFloat = 188

    private func achievementStore(_ language: AppLanguage = .ko) -> CompanionStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("poke-achievement-layout-\(UUID().uuidString).json")
        // 네 트랙이 **모두 분수로 보이는** 상태 — 한 트랙이라도 사다리 끝을 넘으면 그 행이 "✓" 한
        // 글자가 되어 최악의 폭에서 빠진다.
        let json = #"{"economyVersion":2,"forcedResetVersion":1,"language":"\#(language.rawValue)","#
            + #""achievements":{"counts":{"focus":100,"evolve":4,"battle":2,"race":2}}}"#
        try? Data(json.utf8).write(to: url)
        return CompanionStore(provider: StubProvider(value: moveTestLine),
                              clock: { Date(timeIntervalSince1970: 1_755_000_000) },
                              fileURL: url, rng: SeededRNG(seed: 9))
    }

    /// 트리거 재현: 행마다 `ProgressView` 를 깔면 예산을 넘긴다. 이 대조군이 없으면 아래 예산
    /// 검증이 "애초에 통과할 조건이었다" 는 false confidence 가 된다.
    func testAGaugePerAchievementRowBlowsThroughTheShelfBudget() {
        let gauged = VStack(alignment: .leading, spacing: 6) {
            Text("🏅 업적").font(.caption.weight(.semibold))
            ForEach(AchievementLadder.catalog) { entry in
                HStack {
                    Text(entry.id).font(.caption2)
                    Spacer()
                    Text("0/\(entry.tiers[0])").font(.caption2)
                }
                ProgressView(value: 0.3)
            }
        }
        .padding(9)
        XCTAssertGreaterThan(renderedHeight(gauged), Self.achievementShelfBudget,
                             "대조군이 안 넘치면 예산 검증이 무의미해진다")
    }

    func testAchievementShelfFitsItsBudget() {
        XCTAssertLessThanOrEqual(renderedHeight(AchievementShelfView(store: achievementStore())),
                                 Self.achievementShelfBudget)
    }

    // MARK: 꾸미기(옷장) 오버레이 — 던전과 같은 층, 같은 높이 예산.

    /// 던전 오버레이와 같은 `PopoverMetrics.currentHeight(for: .battle)` 프레임을 쓴다 — 아이템
    /// 목록을 가로 스크롤로 묶은 이유가 바로 이 예산을 넘기지 않기 위해서다.
    func testOutfitViewFitsTheOverlayHeight() {
        let store = achievementStore()
        XCTAssertLessThanOrEqual(renderedHeight(OutfitView(store: store, onClose: {})),
                                 PopoverMetrics.currentHeight(for: .battle))
    }

    /// 트랙 이름이 세 언어에서 길이가 다르다(집중 시간 / Focus time / 集中時間). 한 언어에서
    /// 줄바꿈되면 그 언어에서만 선반이 커진다 — 기술 목록에서 이미 겪은 부류(CI 118pt vs 로컬 78pt).
    func testAchievementShelfHeightDoesNotDependOnLanguage() {
        let korean = renderedHeight(AchievementShelfView(store: achievementStore(.ko)))
        for language in [AppLanguage.en, .ja] {
            XCTAssertEqual(renderedHeight(AchievementShelfView(store: achievementStore(language))),
                           korean, accuracy: 1, "\(language.rawValue) 에서 선반 높이가 달라졌다")
        }
    }

    // MARK: 시즌 카드 — 세로 예산

    /// 시즌 카드는 업적 선반과 **같은 세그먼트**에 얹힌다(컬렉션 탭, 520pt 프레임). 둘을 합쳐도
    /// 프레임 안에 있어야 세그먼트를 바꿀 때 스크롤이 생기지 않는다. 3행이라 선반(4행·160pt)보다
    /// 작아야 하고, 행마다 게이지를 깔면 미션 카드(211pt)가 겪은 초과를 되풀이한다.
    private static let seasonCardBudget: CGFloat = 140

    /// 로테이션 세트마다 행 문구 길이가 다르다(`집중 1200분`·`600/1200` vs `집중 900분`·`450/900`,
    /// 완료 보상 9,000 vs 5,000). 한 달만 재면 나머지 세트가 무검증으로 남으므로 **세트 수만큼**
    /// 달을 옮겨 가며 잰다. 31일 간격이면 시즌 인덱스가 매번 1~2 늘어 세 세트를 모두 밟는다.
    private static let seasonDates: [Date] = (0..<SeasonBoard.rotation.count).map {
        Date(timeIntervalSince1970: 1_755_000_000 + Double($0) * 31 * 86_400)
    }

    /// `progressRatio` 로 행 상태를 고른다 — 0.5 는 분수(`600/1200`), 1 은 완료(`✓ 9000 ⭐`).
    /// 어느 쪽 문구가 더 긴지 단정할 수 없어 둘 다 예산에 넣는다.
    /// 시즌 키는 **시계에서 뽑는다** — 상수로 박으면 시계를 옮길 때 세트가 어긋나 진행도가 전부 0 이
    /// 되고, 예산 검증이 가장 짧은 화면을 재면서 조용히 통과한다.
    private func seasonStore(_ language: AppLanguage = .ko, progressRatio: Double = 0.5,
                             at date: Date = seasonDates[0]) -> CompanionStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("poke-season-layout-\(UUID().uuidString).json")
        let key = CompanionStore.seasonKey(date)
        let counts = SeasonBoard.challenges(forSeasonKey: key)
            .map { "\"\($0.id)\":\(Int(Double($0.target) * progressRatio))" }.joined(separator: ",")
        let json = #"{"economyVersion":2,"forcedResetVersion":1,"language":"\#(language.rawValue)","#
            + #""seasons":{"seasonKey":"\#(key)","counts":{\#(counts)}}}"#
        try? Data(json.utf8).write(to: url)
        return CompanionStore(provider: StubProvider(value: moveTestLine), clock: { date },
                              fileURL: url, rng: SeededRNG(seed: 17))
    }

    /// 트리거 재현: 행마다 `ProgressView` 를 깔면 예산을 넘긴다. 이 대조군이 없으면 아래 예산
    /// 검증이 "애초에 통과할 조건이었다" 는 false confidence 가 된다.
    func testAGaugePerSeasonRowBlowsThroughTheCardBudget() {
        let gauged = VStack(alignment: .leading, spacing: 6) {
            Text("🗓️ 시즌").font(.caption.weight(.semibold))
            ForEach(SeasonBoard.rotation[0]) { challenge in
                HStack {
                    Text(challenge.id).font(.caption2)
                    Spacer()
                    Text("0/\(challenge.target)").font(.caption2)
                }
                ProgressView(value: 0.3)
            }
        }
        .padding(9)
        XCTAssertGreaterThan(renderedHeight(gauged), Self.seasonCardBudget,
                             "대조군이 안 넘치면 예산 검증이 무의미해진다")
    }

    /// 분수 상태 — 로테이션 세트 전부.
    func testSeasonCardFitsItsBudget() {
        for date in Self.seasonDates {
            XCTAssertLessThanOrEqual(renderedHeight(SeasonChallengeView(store: seasonStore(at: date))),
                                     Self.seasonCardBudget, CompanionStore.seasonKey(date))
        }
    }

    /// 시즌 말에는 세 행이 모두 완료 상태로 보인다 — 분수 상태만 재면 사용자가 매달 도달하는 화면이
    /// 무검증으로 남는다. `compact` 는 10,000 미만을 줄이지 않아 완료 문구가 더 길다.
    func testCompletedSeasonCardFitsItsBudget() {
        for date in Self.seasonDates {
            XCTAssertLessThanOrEqual(
                renderedHeight(SeasonChallengeView(store: seasonStore(progressRatio: 1, at: date))),
                Self.seasonCardBudget, CompanionStore.seasonKey(date))
        }
    }

    /// 두 카드가 한 세그먼트를 공유한다 — 합이 프레임을 넘으면 업적 선반이 잘리거나 스크롤이 생긴다.
    /// 프레임·간격은 `CollectionView` 의 상수를 그대로 읽는다(테스트가 실제 레이아웃을 따라오게).
    func testSeasonCardAndAchievementShelfShareTheSegmentWithoutOverflowing() {
        let combined = renderedHeight(SeasonChallengeView(store: seasonStore()))
            + CollectionView.cardSpacing
            + renderedHeight(AchievementShelfView(store: achievementStore()))
        XCTAssertLessThanOrEqual(combined, CollectionView.contentHeight)
    }

    /// 남은 일수 문구가 세 언어에서 길이가 다르다(12일 남음 / 12d left / 残り12日). 한 언어에서
    /// 헤더가 줄바꿈되면 그 언어에서만 카드가 커진다 — 기술 목록에서 이미 겪은 부류다.
    func testSeasonCardHeightDoesNotDependOnLanguage() {
        let korean = renderedHeight(SeasonChallengeView(store: seasonStore(.ko)))
        for language in [AppLanguage.en, .ja] {
            XCTAssertEqual(renderedHeight(SeasonChallengeView(store: seasonStore(language))),
                           korean, accuracy: 1, "\(language.rawValue) 에서 카드 높이가 달라졌다")
        }
    }

    // MARK: 기술 목록 행 — 가로 폭 · 자리표시자 높이

    private func moveStore(_ moves: [MoveSpec]) -> CompanionStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("poke-moves-\(UUID().uuidString).json")
        let store = CompanionStore(provider: StubProvider(value: moveTestLine),
                                   clock: { Date(timeIntervalSince1970: 1_700_000_000) },
                                   fileURL: url, rng: SeededRNG(seed: 3))
        store.debugSetDisplayedMoves(moves)
        return store
    }

    /// 이름이 긴 기술 4개 — 실제로 넘치는 최악 케이스.
    private var longMoves: [MoveSpec] {
        (0..<MoveListView.maxRows).map { index in
            MoveSpec(id: index, names: ["ko": String(repeating: "폭발", count: 8),
                                        "en": String(repeating: "Hyper", count: 6),
                                        "ja": String(repeating: "ばくれつ", count: 6)],
                     type: .fire, power: 250, damageClass: .special, accuracy: 100, pp: 40)
        }
    }

    /// 트리거 재현: 폭 제한이 없으면 기술 행이 팝오버 콘텐츠 폭을 넘는다.
    func testMoveRowsWithoutMaxWidthOverflow() {
        let store = moveStore(longMoves)
        // 제안 폭이 아니라 "이상 폭"(넉넉한 제안)으로 잰다 — 행이 얼마나 원하는지를 봐야
        // 폭 제한이 실제로 일하는지 알 수 있다.
        let width = renderedWidth(MoveListView(store: store), proposing: 4_000)
        XCTAssertGreaterThan(width, PopoverMetrics.contentWidth,
                             "안 넘치면 아래 fit 검증이 무의미해진다")
    }

    /// 수정 후: 주어진 폭 안에 들어온다.
    func testMoveRowsFitGivenWidth() {
        let store = moveStore(longMoves)
        let maxWidth = PopoverMetrics.contentWidth - 16
        XCTAssertLessThanOrEqual(renderedWidth(MoveListView(store: store, maxWidth: maxWidth), proposing: 4_000),
                                 maxWidth, "이상 폭도 상한 이하")
        XCTAssertLessThanOrEqual(renderedWidth(MoveListView(store: store, maxWidth: maxWidth), proposing: maxWidth),
                                 maxWidth)
    }

    /// 긴 라틴 문자 이름(영문 UI 의 실제 최악 케이스)이 행 높이를 키우면 안 된다.
    /// 예전엔 이름에 밀린 타입 배지 글자가 줄바꿈돼 행이 통째로 커졌다 — 한국어 이름은 짧아
    /// 로컬에선 안 걸리고 영어로 도는 CI 에서만 4행이 78pt 대신 118pt 로 잡혔다.
    func testLongLatinNameDoesNotGrowRowHeight() {
        let maxWidth = PopoverMetrics.contentWidth - 16
        let latin = (0..<MoveListView.maxRows).map { index in
            MoveSpec(id: 100 + index, names: ["en": String(repeating: "Hyper", count: 6)],
                     type: .fire, power: 250, damageClass: .special, accuracy: 100, pp: 40)
        }
        let short = moveStore((0..<MoveListView.maxRows).map { index in
            MoveSpec(id: index, names: ["en": "Tackle"], type: .normal, power: 40,
                     damageClass: .physical, accuracy: 100, pp: 35)
        })
        XCTAssertEqual(renderedHeight(MoveListView(store: moveStore(latin), maxWidth: maxWidth),
                                      proposingWidth: maxWidth),
                       renderedHeight(MoveListView(store: short, maxWidth: maxWidth),
                                      proposingWidth: maxWidth),
                       accuracy: 2, "이름 길이에 따라 행 높이가 달라지면 안 된다")
    }

    /// 로딩 자리표시자 높이가 완성본(4행)과 같아야 팝오버가 한 번만 리사이즈된다.
    /// 자리표시자는 같은 행 뷰를 투명하게 깔아 높이를 잡는다 — 숫자 상수로 두면 폰트·OS 에 따라
    /// 실제 행 높이와 어긋나 이 검증이 기계마다 다른 결과를 낸다(CI 118pt vs 로컬 78pt 회귀).
    func testLoadingPlaceholderMatchesFinalHeight() {
        let maxWidth = PopoverMetrics.contentWidth - 16
        // 언어에 상관없이 같은(긴 라틴) 이름을 쓴다 — CI 는 영어, 로컬은 한국어로 돌아
        // 언어별 이름을 쓰면 두 환경이 서로 다른 케이스를 검증하게 된다.
        let loaded = moveStore((0..<MoveListView.maxRows).map { index in
            MoveSpec(id: 200 + index, names: ["en": String(repeating: "Hyper", count: 6)],
                     type: .fire, power: 250, damageClass: .special, accuracy: 100, pp: 40)
        })
        let loading = moveStore([])
        loading.debugSetDisplayedMoves([], loading: true)

        let loadedHeight = renderedHeight(MoveListView(store: loaded, maxWidth: maxWidth),
                                          proposingWidth: maxWidth)
        let loadingHeight = renderedHeight(MoveListView(store: loading, maxWidth: maxWidth),
                                           proposingWidth: maxWidth)
        XCTAssertEqual(loadingHeight, loadedHeight, accuracy: 2,
                       "자리표시자와 완성본 높이가 다르면 펼친 직후 팝오버가 두 번 리사이즈된다")
    }
}

private let moveTestLine: EvoLine = {
    var names: [Int: [String: String]] = [:]
    for id in [1, 2, 3] { names[id] = ["en": "P\(id)", "ko": "포\(id)", "ja": "ポ\(id)"] }
    return EvoLine(baseID: 1,
                   tree: EvoNode(speciesID: 1, children: [EvoNode(speciesID: 2, children: [EvoNode(speciesID: 3, children: [])])]),
                   rarity: .common, names: names)
}()
