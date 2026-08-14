import SwiftUI

func rarityColor(_ r: Rarity?) -> Color {
    switch r {
    case .uncommon: return .green
    case .rare: return .blue
    case .legendary: return .orange
    default: return .gray
    }
}

/// 희귀도 캡슐을 늘어놓는 순서(귀한 것부터) — 포획 로그 요약 헤더와 도감 헤더가 공유한다.
/// 순수 표시 순서다. 목록 정렬에는 쓰지 않는다.
let rarityDisplayOrder: [Rarity] = [.legendary, .rare, .uncommon, .common]

/// 아이템 아이콘 — 실제 스프라이트(런타임 로드+캐시) 우선, 로딩 전/미제공/실패 시 이모지 폴백.
struct ItemIconView: View {
    let kind: ItemKind
    var size: CGFloat = 30
    @State private var img: NSImage?

    init(kind: ItemKind, size: CGFloat = 30) {
        self.kind = kind
        self.size = size
        // 캐시에 있으면 즉시(동기) 표시 — 재렌더 플래시 방지.
        _img = State(initialValue: kind.spriteName.flatMap { SpriteLoader.cachedItemImage(name: $0) })
    }

    var body: some View {
        Group {
            if let img {
                Image(nsImage: img).resizable().interpolation(.none)
                    .frame(width: size, height: size)
            } else {
                Text(kind.fallbackEmoji).font(.system(size: size))
                    .frame(width: size, height: size)
            }
        }
        .task(id: kind.spriteName ?? "") {
            guard img == nil, let name = kind.spriteName else { return }
            img = await SpriteLoader.itemImage(name: name)
        }
    }
}

/// SpriteView 가 그리는 주체(정적 이미지 + 그 이미지가 어느 종의 것인지)의 전이 규칙.
///
/// SwiftUI `.task` 는 호스트 없이 돌릴 수 없어 규칙만 순수 값 전이로 빼 둔다(`frameDelay` 와 같은 방식).
/// 여기 담긴 규칙은 둘 다 "화면에 남은 픽셀이 지금 주체의 것인가"를 지킨다.
struct SpriteSubject: Equatable {
    var image: NSImage?
    /// image 가 어느 speciesID 것인지. nil = 알(또는 로드된 개체 없음).
    var loadedID: Int?

    /// 주체가 알로 바뀌었다(졸업·새 알). 이전 **개체**의 이미지는 다른 주체의 픽셀이라 버린다.
    /// 이미 알이던 경우(loadedID == nil)엔 손대지 않는다 — 시드된 알 이미지를 지워 🥚 글리프로 깜빡이게 하지 않기 위해.
    func becomingEgg(cachedEgg: NSImage?) -> SpriteSubject {
        guard loadedID != nil else { return self }
        return SpriteSubject(image: cachedEgg, loadedID: nil)
    }

    /// 로드된 정적 스프라이트를 반영한 결과. **취소된 로드는 nil — 상태를 아예 건드리지 않는다.**
    /// 취소는 곧 주체가 바뀌었다는 뜻이고, 협조적 취소라 continuation 은 그대로 실행되므로 후속 `.task`
    /// 가 이미 새 주체로 잡아 둔 상태를 뒤늦게 덮어쓸 수 있다. 그러면 알 위에 옛 개체가 되살아나고
    /// (#135 와 같은 증상), 실패한 로드가 `loadedID` 만 남기면 다음에 그 종이 다시 활성일 때
    /// "이미 로드됨"으로 판단해 🥚 글리프가 고정된다.
    /// (nil 로 돌려주는 이유: 같은 값을 되쓰면 @State 무효화가 한 번 더 돌아 항상 떠 있는 펫에 불필요한 재렌더가 생긴다.)
    func applyingLoad(_ image: NSImage?, for id: Int, cancelled: Bool) -> SpriteSubject? {
        cancelled ? nil : SpriteSubject(image: image, loadedID: id)
    }

    /// 로드된 알 스프라이트를 반영한 결과(같은 이유로 취소면 nil). 알은 종이 없으므로 loadedID 는 그대로.
    func applyingEgg(_ image: NSImage?, cancelled: Bool) -> SpriteSubject? {
        cancelled ? nil : SpriteSubject(image: image, loadedID: loadedID)
    }
}

/// 스프라이트 1개(런타임 로드 + 캐시). 없으면 알 글리프. bob 으로 가벼운 상하 움직임.
/// animated=true 면 Showdown GIF 프레임을 순환(미지원/오프라인이면 정적+bob 으로 폴백).
private struct SpriteAntialiasingKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var spriteAntialiasing: Bool {
        get { self[SpriteAntialiasingKey.self] }
        set { self[SpriteAntialiasingKey.self] = newValue }
    }
}

struct SpriteView: View {
    @Environment(\.spriteAntialiasing) private var antialiasing
    let speciesID: Int?
    var size: CGFloat = 84
    var bob: Bool = false
    var animated: Bool = false
    var shiny: Bool = false
    /// GIF 프레임 지속의 하한(초). 0=원본 delay 그대로. >0 이면 fps 상한 + wakeup 코얼레싱을 적용해
    /// idle 배터리를 통제한다 — 항상 떠 있는 플로팅 펫(0.4s≈2.5fps)이 메뉴바 GIF 규율과 동치가 되게.
    /// 팝오버 등 일시적 표시는 0(기본)으로 두어 네이티브 fps 유지.
    var minFrameDelay: TimeInterval = 0
    @State private var img: NSImage?
    @State private var up = false
    @State private var loadedID: Int?   // img 가 어느 speciesID 것인지(id 변경 시 갱신 판단)
    /// img 가 이로치 스프라이트인지 — 재로드 판정의 두 번째 축(근거는 needsReload).
    @State private var loadedShiny = false
    @State private var frames: [(image: NSImage, delay: TimeInterval)] = []
    @State private var frameIndex = 0

    init(speciesID: Int?, size: CGFloat = 84, bob: Bool = false, animated: Bool = false,
         shiny: Bool = false, minFrameDelay: TimeInterval = 0) {
        self.speciesID = speciesID
        self.size = size
        self.bob = bob
        self.animated = animated
        self.shiny = shiny
        self.minFrameDelay = minFrameDelay
        // 캐시에 있으면 즉시(동기) 표시 — 재렌더 플래시 방지 + 정적 스냅샷에서도 보임.
        // speciesID==nil(알 상태)이면 알 스프라이트를 시드(없으면 body 가 🥚 폴백).
        let cached = speciesID.map { SpriteLoader.cachedImage(speciesID: $0, shiny: shiny) } ?? SpriteLoader.cachedEggImage()
        _img = State(initialValue: cached)
        _loadedID = State(initialValue: (speciesID != nil && cached != nil) ? speciesID : nil)
        _loadedShiny = State(initialValue: shiny)
    }

    /// 프레임 지속(초) = max(원본 delay, 하한). 순수·테스트용 — fps 상한 회귀 가드.
    static func frameDelay(base: TimeInterval, floor: TimeInterval) -> TimeInterval { max(base, floor) }

    /// 디코드된 GIF 프레임 중 실제로 재생할 것 — 취소됐거나 2프레임 미만이면 빈 배열(정적 폴백).
    /// 취소 검사가 여기 있는 이유: `frames` 는 body 에서 `img` 보다 먼저 그려지므로, 취소된 로드가
    /// 뒤늦게 대입되면 새 주체(알) 위에 옛 개체의 GIF 가 정지 상태로 올라온다.
    static func framesToApply(_ decoded: [(image: NSImage, delay: TimeInterval)],
                              cancelled: Bool) -> [(image: NSImage, delay: TimeInterval)] {
        (cancelled || decoded.count < 2) ? [] : decoded
    }

    /// 현재 그리는 주체(순수 전이 입력).
    private var subject: SpriteSubject { SpriteSubject(image: img, loadedID: loadedID) }

    /// 전이 결과를 @State 로 되돌린다(State 세터는 nonmutating). 값이 그대로면 쓰지 않는다 —
    /// @State 는 같은 값을 써도 무효화가 돌아, 항상 떠 있는 펫에 불필요한 재렌더가 생긴다.
    private func apply(_ next: SpriteSubject) {
        guard next != subject else { return }
        img = next.image
        loadedID = next.loadedID
    }
    /// 정적 스프라이트를 다시 불러야 하는가 — 종이 바뀌었거나 **이로치 여부가 뒤집혔을 때**.
    /// 순수·테스트용(frameDelay 와 같은 이유). 종만 비교하던 과거 판정은 도감의 이로치 토글에서
    /// .task 가 다시 돌아도 "이미 그 종을 로드했다"로 판정해 색이 안 바뀌는 회귀를 낳았다.
    static func needsReload(loadedID: Int?, loadedShiny: Bool, id: Int, shiny: Bool) -> Bool {
        loadedID != id || loadedShiny != shiny
    }

    var body: some View {
        Group {
            if !frames.isEmpty {
                // GIF 애니메이션 경로 — 현재 프레임만 렌더
                Image(nsImage: frames[frameIndex % frames.count].image)
                    .resizable().interpolation(antialiasing ? .high : .none)
                    .frame(width: size, height: size)
            } else if let img {
                Image(nsImage: img).resizable().interpolation(antialiasing ? .high : .none)
                    .frame(width: size, height: size)
            } else {
                Text("🥚").font(.system(size: size * 0.62)).frame(width: size, height: size)
            }
        }
        // GIF 재생 중엔 bob 정지(프레임 자체가 움직임) — 폴백/정적일 때만 상하 움직임
        .offset(y: bob && frames.isEmpty && up ? -3 : 0)
        .task(id: "\(speciesID.map(String.init) ?? "nil")-\(shiny)") {
            // animated 프레임은 id/shiny 변경 시 항상 초기화(이전 개체 프레임 잔상 방지)
            frames = []
            frameIndex = 0
            guard let id = speciesID else {
                // 알 상태 — 정적 알 스프라이트 로드(애니메이션 알은 없음). 실패/오프라인이면 body 가 🥚 폴백.
                // 종 → 알(졸업·새 알)이면 이전 개체 이미지를 버려야 한다 — img 는 뷰 identity 가 살아있는 동안
                // 유지되고 플로팅 펫 패널은 졸업 때 재생성되지 않아, 안 버리면 옛 포켓몬이 계속 떠 있다.
                apply(subject.becomingEgg(cachedEgg: SpriteLoader.cachedEggImage()))
                if img == nil {
                    let egg = await SpriteLoader.eggImage()
                    if let next = subject.applyingEgg(egg, cancelled: Task.isCancelled) { apply(next) }
                }
                return
            }
            // 정적 스프라이트 먼저(즉시 표시 + 폴백 보장).
            // 캐시 시드로 이미 같은 종·같은 이로치 여부면 재요청 생략(플래시 방지)
            if Self.needsReload(loadedID: loadedID, loadedShiny: loadedShiny, id: id, shiny: shiny) {
                let loaded = await SpriteLoader.image(speciesID: id, animated: false, shiny: shiny)
                // 취소된 로드는 반영하지 않는다(#138). 이로치 축은 **반영될 때만** 기록해
                // subject(종)와 loadedShiny 가 어긋나 다음 판정이 틀어지는 것을 막는다.
                if let next = subject.applyingLoad(loaded, for: id, cancelled: Task.isCancelled) {
                    apply(next)
                    loadedShiny = shiny
                }
            }
            guard animated else { return }
            // animated GIF 시도(shiny 미제공 종은 일반 GIF 폴백) → 프레임 2개 이상이면 순환 루프
            var ready = await SpriteLoader.decodedFrames(speciesID: id, shiny: shiny)
            if ready.isEmpty, shiny { ready = await SpriteLoader.decodedFrames(speciesID: id, shiny: false) }
            // 단일 프레임/디코드 실패 → 정적 폴백. 취소됐으면 아예 반영하지 않는다.
            ready = Self.framesToApply(ready, cancelled: Task.isCancelled)
            guard !ready.isEmpty else { return }
            frames = ready
            // delay 기반 프레임 advance. .task 취소 시(speciesID 변경/뷰 소멸) 루프 종료 — 누수 없음
            while !Task.isCancelled {
                let delay = Self.frameDelay(base: frames[frameIndex % frames.count].delay, floor: minFrameDelay)
                // minFrameDelay>0(플로팅 펫): fps 상한 + tolerance 로 wakeup 코얼레싱 — 메뉴바
                // max(0.4,delay)+timer.tolerance 규율과 동치(항상 뜬 표면의 idle 배터리 통제). 0 이면 네이티브.
                try? await Task.sleep(for: .seconds(delay),
                                      tolerance: minFrameDelay > 0 ? .seconds(delay * 0.5) : .zero)
                if Task.isCancelled { break }
                frameIndex = (frameIndex + 1) % frames.count
            }
        }
        .onAppear {
            guard bob else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { up = true }
        }
    }
}

/// 진화 라인(초기→최종, 다음 후보 미리보기). done/cur/future.
///
/// 분기 라인은 "현재 경로 + 다음 후보 전부"라 길다(이브이 = 본체 1 + 후보 8 → 40pt 기준 472pt).
/// 폭 제한 없는 HStack 은 팝오버 콘텐츠 폭(332pt)을 넘고, **넘친 자식이 부모 VStack 폭을 부풀려
/// 팝오버 전체가 좌우로 잘린다**(진화줄뿐 아니라 탭바·합계까지). `maxWidth` 를 주면 그 폭 안에서
/// 가로 스크롤한다 — 썸네일 크기는 유지하고, 가장자리 페이드 + 셰브론으로 스크롤 가능함을 알린다.
struct EvoLineView: View {
    let nodes: [EvoLineItem]
    let mysteryLabel: String
    var thumb: CGFloat = 40
    var shiny: Bool = false     // 개체가 shiny 면 라인 전체를 shiny 스프라이트로
    var names: [Int: String]? = nil   // 제공되면 각 스프라이트 밑에 작은 이름 라벨(도감 단계별 이름)
    /// 한 줄이 쓸 수 있는 가로 폭. 기본 .infinity = 제한 없음(스크롤 없이 나열).
    var maxWidth: CGFloat = .infinity

    private static let spacing: CGFloat = 2
    /// 화살표 칸 폭 = 썸네일 × 이 비율. 고정 frame 을 줘 SF Symbol 글리프 폭에 의존하지 않게 한다 —
    /// rowWidth 가 실제 렌더 폭과 어긋나면 스크롤 판정이 틀어진다.
    private static let arrowRatio: CGFloat = 0.25
    /// 이름 라벨이 썸네일보다 넓어질 수 있는 최대치.
    private static let nameSlack: CGFloat = 6
    private static let fadeWidth: CGFloat = 24

    @State private var scrollX: CGFloat = 0        // 현재 가로 스크롤 오프셋
    @State private var contentWidth: CGFloat = 0   // 실제 렌더된 한 줄 폭(측정값)

    /// 한 줄이 차지하는 가로 폭. 레이아웃과 같은 식을 쓰는 순수 함수 — 이름 라벨은 상한만 알 수
    /// 있어(`.frame(maxWidth:)`) names 가 있으면 실제 폭이 이 값 이하일 수 있다.
    static func rowWidth(count: Int, thumb: CGFloat, hasNames: Bool) -> CGFloat {
        guard count > 0 else { return 0 }
        let column = thumb + (hasNames ? nameSlack : 0)
        let arrows = CGFloat(count - 1) * thumb * arrowRatio
        // 아이템 수 = 썸네일 count + 화살표 (count-1) → 사이 간격은 (2*count - 2)개
        let gaps = CGFloat(2 * count - 2) * spacing
        return CGFloat(count) * column + arrows + gaps
    }

    /// 스크롤 컨테이너가 필요한가 — 한 줄이 `maxWidth` 를 넘는가. 순수 함수(오버플로 회귀 테스트 대상).
    /// 안 넘으면 기존과 완전히 동일한 평범한 HStack 을 그린다(대부분의 2~3단계 라인).
    static func needsScroll(count: Int, thumb: CGFloat, hasNames: Bool, maxWidth: CGFloat) -> Bool {
        guard maxWidth.isFinite, maxWidth > 0 else { return false }
        return rowWidth(count: count, thumb: thumb, hasNames: hasNames) > maxWidth
    }

    var body: some View {
        if Self.needsScroll(count: nodes.count, thumb: thumb,
                            hasNames: names != nil, maxWidth: maxWidth) {
            scrollableRow
        } else {
            row
        }
    }

    // MARK: 스크롤 라인 + 스크롤 가능 신호

    /// 어느 쪽에 스크롤 여지가 남았는지 — 페이드와 셰브론이 공유하는 순수 판정.
    /// 남은 쪽에만 띄워야 끝에 도달한 뒤 "눌러도 안 움직이는 셰브론"이 남지 않는다.
    static func scrollAffordance(scrollX: CGFloat, contentWidth: CGFloat,
                                 maxWidth: CGFloat) -> (back: Bool, forward: Bool) {
        guard contentWidth > maxWidth + 0.5 else { return (false, false) }
        return (scrollX > 0.5, scrollX < contentWidth - maxWidth - 0.5)
    }

    /// 페이드/셰브론 판정에 쓸 한 줄 폭. 측정 전(첫 프레임)엔 rowWidth 추정치를 쓴다 — 측정값만
    /// 믿으면 팝오버를 연 직후 한 프레임 동안 "스크롤 가능" 신호가 없어 그냥 잘린 것처럼 보인다.
    private var effectiveContentWidth: CGFloat {
        contentWidth > 0 ? contentWidth
                         : Self.rowWidth(count: nodes.count, thumb: thumb, hasNames: names != nil)
    }
    private var canScrollBack: Bool {
        Self.scrollAffordance(scrollX: scrollX, contentWidth: effectiveContentWidth,
                              maxWidth: maxWidth).back
    }
    private var canScrollForward: Bool {
        Self.scrollAffordance(scrollX: scrollX, contentWidth: effectiveContentWidth,
                              maxWidth: maxWidth).forward
    }

    private var scrollableRow: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                row
                    .background(
                        GeometryReader { geo in
                            let frame = geo.frame(in: .named(Self.scrollSpace))
                            Color.clear
                                .onChange(of: frame.minX, initial: true) { _, minX in scrollX = -minX }
                                .onChange(of: frame.width, initial: true) { _, w in contentWidth = w }
                        }
                    )
            }
            // 페이드+셰브론이 같은 역할을 하고, "스크롤 막대 항상 표시" 설정에선 두꺼운 legacy
            // 스크롤러가 줄 높이까지 먹는다. `.hidden` 은 그 경우를 못 막아 `.never` 여야 한다.
            .scrollIndicators(.never)
            .coordinateSpace(name: Self.scrollSpace)
            .frame(maxWidth: maxWidth, alignment: .leading)
            // 넘치는 쪽 가장자리를 흐리게 — 잘린 게 아니라 "이어진다"는 표시.
            .mask(edgeFade)
            .overlay(alignment: .topLeading) { chevron(forward: false, proxy: proxy) }
            .overlay(alignment: .topTrailing) { chevron(forward: true, proxy: proxy) }
            .animation(.easeInOut(duration: 0.15), value: canScrollBack)
            .animation(.easeInOut(duration: 0.15), value: canScrollForward)
        }
    }

    private static let scrollSpace = "evoLineScroll"

    /// 스크롤 여지가 있는 쪽만 페이드아웃하는 마스크(가운데는 불투명).
    private var edgeFade: some View {
        let f = Self.fadeWidth / maxWidth   // 이 경로는 needsScroll 통과 = maxWidth 유한·양수
        return LinearGradient(
            stops: [
                .init(color: canScrollBack ? .clear : .black, location: 0),
                .init(color: .black, location: f),
                .init(color: .black, location: 1 - f),
                .init(color: canScrollForward ? .clear : .black, location: 1),
            ],
            startPoint: .leading, endPoint: .trailing)
    }

    /// 한 화면씩 넘기는 셰브론. 스크롤 여지가 있는 쪽에만 떠서 신호를 겸한다
    /// (스크롤바를 껐으므로 이게 유일한 시각 단서이자 마우스 사용자의 조작 수단).
    @ViewBuilder
    private func chevron(forward: Bool, proxy: ScrollViewProxy) -> some View {
        if forward ? canScrollForward : canScrollBack {
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    // 앵커는 항상 .leading — 콘텐츠 끝을 넘는 요청이 clamp 되어 끝에 정확히 닿는다.
                    // .trailing 은 마지막 칸에서 끝에 못 미쳐 멈췄다(실측).
                    proxy.scrollTo(pageTarget(forward: forward), anchor: .leading)
                }
            } label: {
                Image(systemName: forward ? "chevron.right" : "chevron.left")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 16, height: 16)
                    .background(.regularMaterial, in: Circle())
                    .overlay(Circle().strokeBorder(Color.primary.opacity(0.12)))
            }
            .buttonStyle(.plain)
            .padding(forward ? .trailing : .leading, 1)
            .padding(.top, max(0, thumb / 2 - 8))   // 16pt 버튼의 중심을 스프라이트 중심에
            .transition(.opacity)
        }
    }

    private func pageTarget(forward: Bool) -> Int {
        Self.pageTarget(forward: forward, scrollX: scrollX, count: nodes.count,
                        thumb: thumb, hasNames: names != nil, maxWidth: maxWidth)
    }

    /// 셰브론 한 번에 이동할 칸 인덱스 — 왼쪽 끝 칸에서 "한 화면에 보이는 칸 수"만큼 앞/뒤로.
    /// 현재 위치 기준이라 누를 때마다 목표가 바뀐다(고정 목표는 재클릭 시 제자리 — 겪은 회귀).
    static func pageTarget(forward: Bool, scrollX: CGFloat, count: Int,
                           thumb: CGFloat, hasNames: Bool, maxWidth: CGFloat) -> Int {
        guard count > 0 else { return 0 }
        let stride = thumb + (hasNames ? nameSlack : 0) + thumb * arrowRatio + spacing * 2
        let visible = max(1, Int(maxWidth / stride))
        let first = max(0, Int((scrollX / stride).rounded()))
        return min(max(0, first + (forward ? visible : -visible)), count - 1)
    }

    // MARK: 라인 본체

    private var row: some View {
        HStack(alignment: .top, spacing: Self.spacing) {
            ForEach(Array(nodes.enumerated()), id: \.offset) { i, node in
                if i > 0 {
                    Image(systemName: "arrow.right").font(.system(size: thumb * 0.2))
                        .foregroundStyle(.tertiary)
                        .frame(width: thumb * Self.arrowRatio)
                        .padding(.top, thumb * 0.4)   // 스프라이트 세로 중앙에 정렬
                }
                VStack(spacing: 1) {
                    Group {
                        switch node.content {
                        case .species(let id):
                            SpriteView(speciesID: id, size: thumb, shiny: shiny)
                        case .mystery:
                            Text("?")
                                .font(.system(size: thumb * 0.55, weight: .bold, design: .rounded))
                                .frame(width: thumb, height: thumb)
                                .accessibilityLabel(Text(mysteryLabel))
                        }
                    }
                        .opacity(node.state == .future ? 0.32 : 1)
                        .saturation(node.state == .future ? 0.4 : 1)
                        .overlay(alignment: .bottom) {
                            if node.state == .current {
                                Circle().fill(Color.accentColor).frame(width: 4, height: 4).offset(y: 2)
                            }
                        }
                    if let names, case .species(let id) = node.content {
                        Text(names[id] ?? "…")
                            .font(.system(size: 8)).foregroundStyle(.secondary)
                            .lineLimit(1).minimumScaleFactor(0.7).frame(maxWidth: thumb + Self.nameSlack)
                    }
                }
                .frame(width: thumb + (names == nil ? 0 : Self.nameSlack))
                .id(i)   // 셰브론 페이징(ScrollViewProxy.scrollTo) 대상
            }
        }
    }
}

/// 팝오버 상단 — 현재 포켓몬 + 진화 진행 + 부화/진화 연출.
struct CompanionHeader: View {
    let store: CompanionStore
    // 연출 상태 — 부화/진화 순간 흰 플래시 + 스프링 스케일(본가 진화 신 오마주)
    @State private var flashOpacity: Double = 0
    @State private var celebScale: CGFloat = 1
    @State private var shinyBurst = false
    @State private var dittoBurst = false   // 메타몽 리빌 🎭 버스트
    @State private var seenSeq = -1     // 재생 완료한 celebrationSeq (팝오버 재오픈 시 1회 재생 보장)
    @State private var eggWiggle = false
    // 사탕 "+XP" 순간 표시 (진화 없이 부분 진행일 때도 피드백)
    @State private var seenCandySeq = -1
    @State private var candyXPShown = false
    @State private var candyXPAmount = 0     // 표시 순간 캡처(consume 후에도 텍스트 유지)
    // 민트 사용 시 "반짝" 스파클 (성격 변경 피드백 — 텍스트 없이 짧은 이펙트)
    @State private var seenMintSeq = -1
    @State private var mintSparkle = false
    // 별명 인라인 편집
    @State private var editingName = false
    @State private var nameDraft = ""
    @State private var showingMoves = false

    private func commitNickname() {
        store.setNickname(nameDraft)
        editingName = false
    }

    /// 부화 임박(90%+) — 알이 흔들리고 문구가 바뀐다.
    private var eggImminent: Bool { store.isEgg && store.eggProgress >= 0.9 }

    var body: some View {
        if store.needsStarterSelection {
            StarterPickerView(store: store)
        } else {
            companionContent
        }
    }

    private var companionContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 12) {
                SpriteView(speciesID: store.currentSpeciesID, size: 76, bob: true, animated: true,
                           shiny: store.currentIsShiny)
                    .frame(width: 76, height: 76)
                    .background(Color.secondary.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .rotationEffect(.degrees(eggImminent && eggWiggle ? 5 : (eggImminent ? -5 : 0)))
                    .scaleEffect(celebScale)
                    .overlay(RoundedRectangle(cornerRadius: 12).fill(.white).opacity(flashOpacity))
                    .overlay(alignment: .topTrailing) {
                        if shinyBurst {
                            Text("✨").font(.system(size: 22))
                                .transition(.scale.combined(with: .opacity))
                                .offset(x: 6, y: -6)
                        }
                    }
                    .overlay(alignment: .top) {
                        if dittoBurst {
                            Text("🎭").font(.system(size: 26))
                                .transition(.scale.combined(with: .opacity))
                                .offset(y: -12)
                        }
                    }
                    .overlay(alignment: .top) {
                        if candyXPShown {
                            Text("+\(GameNumberFormatter.compact(candyXPAmount)) XP")
                                .font(.caption.weight(.bold)).foregroundStyle(.orange)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(.regularMaterial, in: Capsule())
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                                .offset(y: -16)
                        }
                    }
                    .overlay {
                        if mintSparkle {
                            ZStack {
                                Text("✨").font(.system(size: 22)).offset(x: -11, y: -9)
                                Text("✨").font(.system(size: 15)).offset(x: 13, y: 5)
                                Text("✨").font(.system(size: 12)).offset(x: 1, y: 13)
                            }
                            .transition(.scale.combined(with: .opacity))
                        }
                    }
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        if editingName {
                            TextField(store.speciesName, text: $nameDraft)
                                .textFieldStyle(.roundedBorder)
                                .font(.callout.weight(.semibold))
                                .frame(maxWidth: 140)
                                .onSubmit { commitNickname() }
                            Button(action: commitNickname) { Image(systemName: "checkmark") }
                                .buttonStyle(.borderless).controlSize(.small)
                        } else {
                            Text(store.displayName).font(.callout.weight(.semibold))
                            if store.currentIsShiny { Text("✨").font(.system(size: 11)) }
                            // 별명 짓기/바꾸기 — 활성 개체 + 라인 로딩 후에만(종 이름 폴백 준비됨).
                            if store.hasActive, store.currentLine != nil {
                                Button {
                                    nameDraft = store.currentNickname ?? ""
                                    editingName = true
                                } label: { Image(systemName: "pencil").font(.system(size: 10)) }
                                .buttonStyle(.borderless).controlSize(.mini)
                                .foregroundStyle(.secondary)
                            }
                        }
                        if let r = store.rarity, !editingName {
                            Text(store.l.rarityLabel(r).uppercased()).font(.system(size: 8, weight: .bold))
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(rarityColor(r)).foregroundStyle(.white)
                                .clipShape(Capsule())
                        }
                    }
                    if store.hasActive {
                        // 단계 + 성격(부화 시 확정된 개체 아이덴티티)
                        let nature = store.currentNature.map { " · \($0.name(store.language))" } ?? ""
                        Text("Lv.\(store.currentLevel) · " + store.stageText + nature)
                            .font(.caption2).foregroundStyle(.secondary)
                        if !store.currentTypes.isEmpty {
                            HStack(spacing: 4) {
                                ForEach(store.currentTypes, id: \.self) { TypeBadge(type: $0, language: store.language) }
                            }
                        }
                        HStack {
                            Text(store.experienceToNextLevel > 0
                                 ? (store.language == .ko
                                    ? "다음 레벨까지 \(GameNumberFormatter.compact(store.experienceToNextLevel)) EXP"
                                    : "\(GameNumberFormatter.compact(store.experienceToNextLevel)) EXP to next level")
                                 : (store.language == .ko ? "최고 레벨" : "Max level"))
                                .font(.caption2).foregroundStyle(.tertiary)
                            Spacer()
                        }
                        ProgressView(value: store.levelProgress)
                            .controlSize(.small).tint(.blue)
                        HStack(spacing: 6) {
                            Spacer(minLength: 0)
                            if let evolutionLevel = store.nextEvolutionLevel {
                                Text(store.language == .ko ? "Lv.\(evolutionLevel)에 진화" : "Evolves at Lv.\(evolutionLevel)")
                                    .font(.caption2).foregroundStyle(.tertiary)
                            }
                        }
                    } else {
                        // 알 인큐베이션 — 부화까지 진행 (임박 시 문구·색 전환)
                        HStack(spacing: 6) {
                            Text(eggImminent ? store.l.eggImminent : store.l.eggIncubating)
                                .font(.caption2)
                                .foregroundStyle(eggImminent ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                            // 등급 보증 알이면 무엇을 품고 있는지 — 도감 칩과 같은 라벨·색.
                            // 알 스프라이트는 한 장뿐이라 등급 구분은 이 배지가 유일한 신호다.
                            if let guarantee = store.eggGuarantee {
                                Text(store.l.eggGuaranteeHint(guarantee)).font(.system(size: 8, weight: .bold))
                                    .padding(.horizontal, 5).padding(.vertical, 1)
                                    .background(rarityColor(guarantee)).foregroundStyle(.white)
                                    .clipShape(Capsule())
                            }
                        }
                        ProgressView(value: store.eggProgress).controlSize(.small).tint(.orange)
                        HStack(spacing: 6) {
                            Text(store.l.eggToHatch(GameNumberFormatter.compact(store.eggTokensToHatch)))
                                .font(.caption2).foregroundStyle(.tertiary)
                            Spacer(minLength: 0)
                            Text(store.language == .ko ? "집중 세션을 완료하면 부화" : "Complete focus sessions to hatch")
                                .font(.caption2).foregroundStyle(.tertiary)
                        }
                        // 첫 실행(적립 0) — 정적 알 앞에서 "고장났나" 오해 방지용 한 줄 안내
                        if !store.eggStarted {
                            Text(store.l.eggFirstRunHint)
                                .font(.caption2).foregroundStyle(.tertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Text(statusLine).font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
            }
            if store.hasActive, !store.lineNodes.isEmpty {
                // 폭을 안 주면 분기 라인(이브이)이 넘쳐 팝오버 콘텐츠 전체가 좌우로 잘린다.
                EvoLineView(nodes: store.lineNodes, mysteryLabel: store.l.unknownNextEvolution, shiny: store.currentIsShiny,
                            maxWidth: PopoverMetrics.contentWidth)
            }
            if store.hasActive {
                DisclosureGroup(isExpanded: $showingMoves) {
                    // 폭을 넘기지 않으면 이름·배지·위력/명중/PP 가 한 줄에서 넘쳐 팝오버가 좌우로 잘린다.
                    MoveListView(store: store, maxWidth: PopoverMetrics.contentWidth - 16)
                        .task(id: "\(store.state.active?.id.uuidString ?? "-")-\(store.currentLevel)") {
                            await store.loadDisplayedMoves()
                        }
                } label: {
                    Label(store.l.movesTitle, systemImage: "bolt.fill")
                        .font(.caption.weight(.semibold))
                }
                .padding(8)
                .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 9))
            }
            if !store.boxedMons.isEmpty { CompanionBoxView(store: store) }
            if let prompt = store.evolutionPrompt { EvolutionPromptCard(store: store, prompt: prompt) }
            if let prompt = store.moveLearningPrompt { MoveLearningCard(store: store, prompt: prompt) }
            if let g = store.justGraduated {
                Text(store.l.graduated(g))
                    .font(.caption2).foregroundStyle(.orange)
            }
        }
        .task(id: store.currentSpeciesID) { await store.loadCurrentTypes() }
        .onAppear {
            playCelebrationIfNeeded()
            showCandyXPIfNeeded()
            showMintIfNeeded()
            syncEggWiggle()
        }
        .onChange(of: store.celebrationSeq) { playCelebrationIfNeeded() }
        .onChange(of: store.candyFeedbackSeq) { showCandyXPIfNeeded() }
        .onChange(of: store.mintFeedbackSeq) { showMintIfNeeded() }
        .onChange(of: eggImminent) { syncEggWiggle() }
    }

    /// 부화/진화 연출 1회 재생 — 흰 플래시 페이드아웃 + 스프링 팝. shiny 부화는 ✨ 버스트 추가.
    private func playCelebrationIfNeeded() {
        guard let c = store.celebration, store.celebrationSeq != seenSeq else { return }
        seenSeq = store.celebrationSeq
        store.consumeCelebration()
        flashOpacity = 0.85
        celebScale = 0.6
        withAnimation(.easeOut(duration: 0.8)) { flashOpacity = 0 }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.55)) { celebScale = 1 }
        if case .hatch(shiny: true) = c {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.5).delay(0.3)) { shinyBurst = true }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 2_600_000_000)
                withAnimation(.easeOut(duration: 0.5)) { shinyBurst = false }
            }
        }
        // 메타몽 리빌 — 위장체→메타몽 스프라이트 교체를 플래시가 덮고, 🎭 버스트(이로치면 ✨ 동반).
        if case .dittoReveal(let shiny) = c {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.5).delay(0.25)) { dittoBurst = true }
            if shiny {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.5).delay(0.45)) { shinyBurst = true }
            }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 2_600_000_000)
                withAnimation(.easeOut(duration: 0.5)) { dittoBurst = false; shinyBurst = false }
            }
        }
    }

    /// 사탕 사용 "+XP" 1회 표시. store 를 consume 해 1회성 보장 — 다른 탭 갔다 홈 재진입해
    /// CompanionHeader 가 재마운트(@State 초기화)돼도 다시 뜨지 않는다(회귀 수정).
    private func showCandyXPIfNeeded() {
        guard store.candyFeedbackAmount > 0, store.candyFeedbackSeq != seenCandySeq else { return }
        seenCandySeq = store.candyFeedbackSeq
        candyXPAmount = store.candyFeedbackAmount
        store.consumeCandyFeedback()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) { candyXPShown = true }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_300_000_000)
            withAnimation(.easeOut(duration: 0.4)) { candyXPShown = false }
        }
    }

    /// 민트 사용 "반짝" 스파클 1회 재생 — 사탕과 동일 1회성 계약(consume 로 재마운트 재생 방지). 텍스트 없음.
    private func showMintIfNeeded() {
        guard store.mintFeedbackNature != nil, store.mintFeedbackSeq != seenMintSeq else { return }
        seenMintSeq = store.mintFeedbackSeq
        store.consumeMintFeedback()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.5)) { mintSparkle = true }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 900_000_000)
            withAnimation(.easeOut(duration: 0.4)) { mintSparkle = false }
        }
    }

    private func syncEggWiggle() {
        if eggImminent {
            withAnimation(.easeInOut(duration: 0.35).repeatForever(autoreverses: true)) { eggWiggle = true }
        } else {
            withAnimation(.default) { eggWiggle = false }
        }
    }

    private var statusLine: String {
        let l = store.l
        switch store.displayState {
        case .egg:     return l.statusEgg
        case .idle:    return l.statusIdle
        case .working: return l.statusWorking
        case .focus:   return l.statusFocus
        case .tired:   return l.statusTired
        case .sleep:   return l.statusSleep
        case .levelUp: return store.justEvolvedTo.map { l.statusEvolved($0) } ?? l.statusGrew
        }
    }
}

/// 동물농장식 돌봄 + 시간 기반 모험의 첫 플레이 루프.
private struct TypeBadge: View {
    let type: PokemonType
    let language: AppLanguage

    var body: some View {
        // lineLimit/fixedSize 가 없으면 좁은 행(긴 기술 이름 옆)에서 배지 글자가 줄바꿈돼
        // 행 높이가 통째로 늘어난다 — 기술 목록이 언어에 따라 다른 높이로 그려지던 원인.
        Text(type.name(language).uppercased())
            .font(.system(size: 8, weight: .heavy))
            .foregroundStyle(.white)
            .lineLimit(1).fixedSize()
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(type.color, in: Capsule())
    }
}

private extension PokemonType {
    var color: Color {
        switch self {
        case .normal: Color(red: 0.57, green: 0.58, blue: 0.50)
        case .fire: Color(red: 0.93, green: 0.29, blue: 0.20)
        case .water: Color(red: 0.18, green: 0.50, blue: 0.88)
        case .electric: Color(red: 0.95, green: 0.72, blue: 0.10)
        case .grass: Color(red: 0.25, green: 0.65, blue: 0.31)
        case .ice: Color(red: 0.35, green: 0.76, blue: 0.82)
        case .fighting: Color(red: 0.78, green: 0.22, blue: 0.18)
        case .poison: Color(red: 0.63, green: 0.25, blue: 0.67)
        case .ground: Color(red: 0.72, green: 0.53, blue: 0.25)
        case .flying: Color(red: 0.50, green: 0.62, blue: 0.88)
        case .psychic: Color(red: 0.92, green: 0.29, blue: 0.51)
        case .bug: Color(red: 0.57, green: 0.66, blue: 0.12)
        case .rock: Color(red: 0.65, green: 0.55, blue: 0.25)
        case .ghost: Color(red: 0.39, green: 0.32, blue: 0.58)
        case .dragon: Color(red: 0.38, green: 0.30, blue: 0.82)
        case .dark: Color(red: 0.36, green: 0.29, blue: 0.26)
        case .steel: Color(red: 0.40, green: 0.57, blue: 0.65)
        case .fairy: Color(red: 0.87, green: 0.47, blue: 0.70)
        }
    }
}

struct MoveListView: View {
    let store: CompanionStore
    /// 부모가 주는 콘텐츠 폭. 안 주면 행이 넘쳐 팝오버 전체가 좌우로 잘린다(EvoLineView 와 같은 이유).
    var maxWidth: CGFloat = .infinity

    static let rowSpacing: CGFloat = 5
    static let maxRows = 4
    /// 자리표시자용 더미 기술 — 로딩 중에도 완성본과 *같은 행 레이아웃*을 그려 높이를 예약한다.
    /// 높이를 숫자 상수로 두면 폰트·OS 버전에 따라 실제 행 높이와 어긋난다(CI 118pt vs 로컬 78pt).
    private static let skeletonMove = MoveSpec(id: -1, names: [:], type: .normal, power: 0,
                                               damageClass: .physical, accuracy: 100, pp: 0)

    private var l: L { store.l }

    var body: some View {
        VStack(spacing: Self.rowSpacing) {
            if store.isLoadingDisplayedMoves {
                ZStack {
                    // 최종 행 수만큼 같은 구조를 투명하게 깔아 높이를 잡는다 → 로드 완료 시 리사이즈 0회.
                    VStack(spacing: Self.rowSpacing) {
                        ForEach(0..<Self.maxRows, id: \.self) { _ in row(Self.skeletonMove) }
                    }
                    .opacity(0)
                    .accessibilityHidden(true)
                    HStack { ProgressView().controlSize(.small); Text(l.movesLoading) }
                        .font(.caption2).foregroundStyle(.secondary)
                }
                .frame(maxWidth: maxWidth)
            } else if store.displayedMoves.isEmpty {
                Text(l.movesEmpty)
                    .font(.caption2).foregroundStyle(.secondary)
            } else {
                ForEach(store.displayedMoves) { move in
                    row(move).help(moveHelp(move))
                }
            }
        }
        .frame(maxWidth: maxWidth, alignment: .leading)
        .padding(.top, 7)
    }

    /// 기술 한 줄. 자리표시자와 완성본이 이 한 곳을 공유해야 높이가 구조적으로 같아진다.
    private func row(_ move: MoveSpec) -> some View {
        HStack(spacing: 6) {
            Text(move.name(store.language)).font(.caption.weight(.semibold))
                .lineLimit(1).layoutPriority(1)
            TypeBadge(type: move.type, language: store.language)
            Spacer(minLength: 2)
            Group {
                Text(move.damageClass == .status ? l.moveCategoryStatus : l.movePowerShort(move.power))
                Text(move.accuracy.map { l.moveAccuracyShort($0) } ?? l.moveAlwaysHits)
                Text(l.movePP(move.pp))
            }
            .font(.caption2).foregroundStyle(.secondary)
            .lineLimit(1).minimumScaleFactor(0.75)
        }
        .frame(maxWidth: maxWidth, alignment: .leading)
    }

    private func moveHelp(_ move: MoveSpec) -> String {
        let category = l.moveCategory(move.damageClass)
        let power = move.damageClass == .status ? "—" : "\(move.power)"
        let accuracy = move.accuracy.map(String.init) ?? l.moveAlwaysHits
        let details = "\(move.type.name(store.language)) · \(category)\n\(l.movePowerLabel) \(power) · \(l.moveAccuracyLabel) \(accuracy) · \(l.movePP(move.pp))"
        if let description = move.description(store.language), !description.isEmpty {
            return "\(move.name(store.language))\n\(description)\n\(details)"
        }
        return "\(move.name(store.language))\n\(details)"
    }
}

private struct EvolutionPromptCard: View {
    let store: CompanionStore
    let prompt: CompanionStore.EvolutionPrompt

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(store.language == .ko ? "진화할 수 있어요!" : "Evolution is available!", systemImage: "sparkles")
                .font(.caption.weight(.semibold)).foregroundStyle(.orange)
            HStack(spacing: 10) {
                SpriteView(speciesID: prompt.fromSpeciesID, size: 46, shiny: store.state.active?.isShiny ?? false)
                Image(systemName: "arrow.right").foregroundStyle(.secondary)
                SpriteView(speciesID: prompt.toSpeciesID, size: 46, shiny: store.state.active?.isShiny ?? false)
                VStack(alignment: .leading, spacing: 2) {
                    Text(prompt.toName).font(.callout.bold())
                    Text(store.language == .ko ? "Lv.\(prompt.requiredLevel) 진화" : "Evolves at Lv. \(prompt.requiredLevel)")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
            }
            Text(store.language == .ko ? "\(prompt.toName)(으)로 진화할까요?" : "Evolve into \(prompt.toName)?")
                .font(.caption)
            HStack {
                Button(store.language == .ko ? "예, 진화할래요" : "Yes, evolve") { store.acceptEvolution() }
                    .buttonStyle(.borderedProminent).controlSize(.small)
                Button(store.language == .ko ? "아니오" : "No") { store.declineEvolution() }
                    .controlSize(.small)
            }
        }
        .padding(9)
        .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 9))
    }
}

private struct CompanionBoxView: View {
    let store: CompanionStore

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(store.language == .ko ? "포켓몬 박스" : "Pokémon Box", systemImage: "shippingbox.fill")
                .font(.caption.weight(.semibold))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(store.boxedMons, id: \.id) { mon in
                        BoxMonCard(store: store, mon: mon)
                    }
                }
            }
        }
        .padding(8)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 9))
    }
}

private struct BoxMonCard: View {
    let store: CompanionStore
    let mon: MonState
    @State private var name = ""
    @State private var types: [PokemonType] = []

    var body: some View {
        Button { store.switchCompanion(to: mon.id) } label: {
            VStack(spacing: 3) {
                SpriteView(speciesID: mon.currentID, size: 42, shiny: mon.isShiny)
                Text(name.isEmpty ? "#\(mon.currentID)" : name).font(.caption2.bold()).lineLimit(1)
                Text("Lv.\(mon.level)").font(.system(size: 8)).foregroundStyle(.secondary)
                HStack(spacing: 2) { ForEach(types, id: \.self) { TypeBadge(type: $0, language: store.language) } }
            }.frame(width: 82).padding(5)
        }
        .buttonStyle(.bordered)
        .task(id: mon.currentID) {
            name = await store.resolveSpeciesName(mon.currentID)
            types = (try? await PokeAPIClient.shared.battleProfile(speciesID: mon.currentID).types) ?? []
        }
    }
}

private struct MoveLearningCard: View {
    let store: CompanionStore
    let prompt: CompanionStore.MoveLearningPrompt

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(store.language == .ko ? "새로운 기술을 배울 수 있어요" : "A new move is available",
                  systemImage: "sparkles")
                .font(.caption.weight(.semibold)).foregroundStyle(.purple)
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(prompt.move.name(store.language)).font(.callout.bold())
                    HStack(spacing: 5) {
                        Text("Lv.\(prompt.level)").font(.caption2).foregroundStyle(.secondary)
                        TypeBadge(type: prompt.move.type, language: store.language)
                        Text(prompt.move.damageClass == .status ? "변화" : "Power \(prompt.move.power)")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            if let active = store.state.active, active.learnedMoves.count >= 4 {
                Text(store.language == .ko ? "잊을 기술을 선택하세요." : "Choose a move to forget.")
                    .font(.caption2).foregroundStyle(.secondary)
                ForEach(Array(active.learnedMoves.enumerated()), id: \.element.id) { index, move in
                    Button("\(move.name(store.language)) · \(move.type.name(store.language)) → \(prompt.move.name(store.language))") {
                        store.acceptMoveLearning(replacing: index)
                    }.controlSize(.small)
                }
            } else {
                HStack {
                    Button(store.language == .ko ? "예, 배울래요" : "Yes, learn it") {
                        store.acceptMoveLearning()
                    }.buttonStyle(.borderedProminent).controlSize(.small)
                    Button(store.language == .ko ? "아니오" : "No") { store.declineMoveLearning() }
                        .controlSize(.small)
                }
            }
            if store.state.active?.learnedMoves.count ?? 0 >= 4 {
                Button(store.language == .ko ? "배우지 않기" : "Don't learn") { store.declineMoveLearning() }
                    .controlSize(.small)
            }
        }
        .padding(9)
        .background(Color.purple.opacity(0.09), in: RoundedRectangle(cornerRadius: 9))
    }
}

struct AdventureCard: View {
    let store: CompanionStore
    @State private var rewardText: String?

    private func zoneName(_ zone: AdventureZone) -> String {
        switch (store.language, zone) {
        case (.ko, .forest): return "숲"
        case (.ko, .cave): return "동굴"
        case (.ko, .coast): return "바닷가"
        case (.ja, .forest): return "森"
        case (.ja, .cave): return "洞窟"
        case (.ja, .coast): return "海辺"
        case (_, .forest): return "Forest"
        case (_, .cave): return "Cave"
        case (_, .coast): return "Coast"
        }
    }

    private func duration(_ seconds: TimeInterval) -> String {
        seconds >= 3600 ? "\(Int(seconds / 3600))h" : "\(Int(seconds / 60))m"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Label(store.language == .ko ? "돌보기와 모험" : "Care & Adventure",
                      systemImage: "map.fill").font(.caption.weight(.semibold))
                Spacer()
                if let rewardText { Text(rewardText).font(.caption2).foregroundStyle(.orange) }
            }
            HStack(spacing: 7) {
                careGauge("🍖", store.care.hunger)
                careGauge("😊", store.care.happiness)
                careGauge("⚡", store.care.energy)
                careGauge("💗", store.care.affection)
                careGauge("🫧", store.care.hygiene)
            }
            HStack(spacing: 4) {
                Text("🎓").font(.system(size: 10))
                ProgressView(value: store.care.discipline, total: 100).controlSize(.mini)
                Text("\(Int(store.care.discipline))")
                    .font(.system(size: 9).monospacedDigit()).foregroundStyle(.secondary)
            }
            if store.care.isSick {
                Label(store.language == .ko ? "아파요 · 씻긴 뒤 약을 주세요" : "Sick · clean, then give medicine",
                      systemImage: "cross.case.fill")
                    .font(.caption.weight(.semibold)).foregroundStyle(.red)
                    .padding(.horizontal, 7).padding(.vertical, 5)
                    .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 7))
            }
            if store.care.isSleeping {
                Label(store.language == .ko ? "자는 중 · 에너지를 회복하고 있어요" : "Sleeping · recovering energy",
                      systemImage: "moon.zzz.fill")
                    .font(.caption.weight(.semibold)).foregroundStyle(.indigo)
            }
            if store.care.messCount > 0 {
                HStack(spacing: 4) {
                    Text(String(repeating: "💩", count: store.care.messCount))
                    Text(store.language == .ko ? "주변을 청소해 주세요" : "Time to clean up")
                        .font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                }
            }
            if let need = store.care.pendingNeed, let deadline = store.care.needDeadline {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    HStack(spacing: 5) {
                        Image(systemName: "bell.badge.fill").foregroundStyle(.orange)
                        Text(needText(need)).font(.caption.weight(.semibold))
                        Spacer()
                        if deadline > context.date {
                            Text(deadline, style: .timer).font(.caption.monospacedDigit())
                        } else {
                            Text(store.language == .ko ? "놓쳤어요" : "Missed")
                                .font(.caption).foregroundStyle(.red)
                        }
                    }
                    .padding(.horizontal, 7).padding(.vertical, 5)
                    .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))
                }
            }
            HStack(spacing: 5) {
                Menu {
                    ForEach(CareFood.allCases) { food in
                        Button("\(food.symbol) \(food == store.favoriteFood ? "★" : "")") {
                            store.feedCompanion(food)
                        }
                    }
                } label: { Text(store.favoriteFood.symbol) }
                .help(store.language == .ko ? "좋아하는 간식 ★" : "Favorite treat ★")
                Button("🎾") { store.playWithCompanion() }.help("Play")
                Button("💤") { store.restCompanion() }.help("Rest")
                Button("🖐️") { _ = store.petCompanion() }
                    .help(store.language == .ko ? "쓰다듬기 · 5분마다" : "Pet · every 5 minutes")
                Button(store.care.messCount > 0 ? "🧹" : "🛁") { store.cleanCompanion() }
                    .help(store.language == .ko ? "씻기·청소" : "Clean")
                if store.care.isSick {
                    Button("💊") { _ = store.medicateCompanion() }
                        .help(store.language == .ko ? "약 먹이기 · 위생 40 이상 필요" : "Medicine · requires 40 hygiene")
                        .disabled(store.care.hygiene < 40)
                }
                Button("🎓") { _ = store.trainCompanion() }
                    .help(store.language == .ko ? "훈련 · 에너지 10 · 30분마다" : "Train · 10 energy · every 30 min")
                    .disabled(store.care.energy < 10 || store.care.isSick)
                Spacer()
                Text(careSummary).font(.system(size: 9)).foregroundStyle(.tertiary)
            }
            .controlSize(.small)
            .disabled(store.isAdventuring || store.care.isSleeping)

            if store.care.isSleeping {
                Button(store.language == .ko ? "불 켜고 깨우기" : "Turn on lights & wake") {
                    store.wakeCompanion()
                }.controlSize(.small)
            } else {
                Button(store.language == .ko ? "불 끄고 재우기" : "Lights out") {
                    _ = store.sleepCompanion()
                }
                .controlSize(.small)
                .disabled(store.isAdventuring || store.care.isSick || store.care.energy >= 100)
            }

            if let run = store.activeAdventure {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Label(zoneName(run.zone), systemImage: run.zone.symbol).font(.caption)
                            Spacer()
                            if run.isComplete(at: context.date) {
                                Button(store.language == .ko ? "보상 받기" : "Claim") {
                                    if let reward = store.claimAdventure() {
                                        rewardText = "+\(GameNumberFormatter.compact(reward.experience)) EXP · +\(reward.starPieces) ⭐ · +\(reward.eggFragments) 🧩"
                                            + (reward.bonusEggs > 0 ? " · +\(reward.bonusEggs) 🥚" : "")
                                            + (reward.foundRareCandy ? " · +🍬" : "")
                                    }
                                }.controlSize(.small)
                            } else {
                                Text(run.endsAt, style: .timer).font(.caption.monospacedDigit())
                            }
                        }
                        ProgressView(value: run.progress(at: context.date)).controlSize(.small).tint(.green)
                    }
                }
            } else {
                HStack(spacing: 5) {
                    ForEach(AdventureZone.allCases) { zone in
                        Button { _ = store.startAdventure(zone) } label: {
                            VStack(spacing: 1) {
                                Image(systemName: zone.symbol)
                                Text("\(zoneName(zone)) · \(duration(zone.duration))").font(.system(size: 9))
                            }.frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(store.care.energy < 15 || store.care.isSick || store.care.isSleeping)
                    }
                }
            }
            if let recent = store.recentAdventures.first, store.activeAdventure == nil {
                HStack(spacing: 5) {
                    Image(systemName: "book.closed.fill").foregroundStyle(.secondary)
                    Text("\(zoneName(recent.zone)) · +\(recent.stardust) ⭐" + (recent.foundRareCandy ? " · 🍬" : ""))
                        .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    Spacer()
                    Text(recent.completedAt, style: .relative).font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
        .padding(8)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 9))
    }

    private func careGauge(_ icon: String, _ value: Double) -> some View {
        HStack(spacing: 3) {
            Text(icon).font(.system(size: 10))
            ProgressView(value: value, total: 100).controlSize(.mini)
        }.frame(maxWidth: .infinity)
    }

    private func needText(_ need: CareNeed) -> String {
        switch (store.language, need) {
        case (.ko, .hungry): return "배고파요 · 🍎"
        case (.ko, .lonely): return "놀고 싶어요 · 🎾"
        case (.ko, .tired): return "졸려요 · 💤"
        case (.ja, .hungry): return "おなかすいた · 🍎"
        case (.ja, .lonely): return "遊びたい · 🎾"
        case (.ja, .tired): return "ねむい · 💤"
        case (_, .hungry): return "Hungry · 🍎"
        case (_, .lonely): return "Wants to play · 🎾"
        case (_, .tired): return "Sleepy · 💤"
        }
    }

    private var careSummary: String {
        let bonus = Int(((store.care.growthMultiplier - 1) * 100).rounded())
        switch store.language {
        case .ko: return "돌봄 \(bonus >= 0 ? "+" : "")\(bonus)% · 실수 \(store.care.careMistakes)"
        case .ja: return "お世話 \(bonus >= 0 ? "+" : "")\(bonus)% · ミス \(store.care.careMistakes)"
        case .en: return "Care \(bonus >= 0 ? "+" : "")\(bonus)% · \(store.care.careMistakes) misses"
        }
    }
}

/// 스타터 선택 — 맨 처음 1회. 알로 시작하는 대신 1세대 기본형 랜덤 3종 중 하나를 고른다.
/// 후보는 store.ensureStarterCandidates 가 뽑아 고정하고(재렌더/재시작에도 동일), 탭하면 즉시 부화한다.
struct StarterPickerView: View {
    let store: CompanionStore
    @State private var picking = false   // 선택 후 중복 탭 방지
    @State private var trainer = ""

    private var l: L { store.l }
    private var nameReady: Bool { !trainer.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 1) 트레이너 이름 — 배틀에 표시된다. 이름을 넣어야 스타터를 고를 수 있다.
            VStack(alignment: .leading, spacing: 4) {
                Text(l.trainerNamePrompt).font(.callout.weight(.semibold))
                TextField(l.trainerNamePlaceholder, text: $trainer)
                    .textFieldStyle(.roundedBorder)
                    .disabled(picking)
                    .onSubmit { store.setTrainerName(trainer) }
            }

            Divider()

            // 2) 타입 선택 — 해당 타입의 1세대 미진화체 한 마리가 알에서 무작위로 부화한다.
            Text(store.language == .ko ? "원하는 타입을 골라요" : "Choose a type")
                .font(.callout.weight(.semibold))
            if picking {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(store.language == .ko ? "알 속의 포켓몬을 만나고 있어요…" : "Meeting the Pokémon inside the Egg…")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 24)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 66))], spacing: 7) {
                    ForEach(store.starterSelectableTypes, id: \.self) { type in
                        Button {
                            picking = true
                            store.setTrainerName(trainer)
                            Task {
                                if !(await store.chooseStarterType(type)) { picking = false }
                            }
                        } label: {
                            TypeBadge(type: type, language: store.language)
                                .frame(maxWidth: .infinity).padding(.vertical, 5)
                        }
                        .buttonStyle(.bordered).disabled(!nameReady)
                    }
                }
                Text(nameReady
                     ? (store.language == .ko
                        ? "선택한 타입의 1세대 미진화체가 알에서 무작위로 태어나요. 전설·환상은 제외됩니다."
                        : "A random unevolved Gen I Pokémon of that type will hatch. Legendary and Mythical Pokémon are excluded.")
                     : l.starterNeedName)
                    .font(.caption2).foregroundStyle(nameReady ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.orange))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear { if trainer.isEmpty { trainer = store.trainerName } }
    }
}

/// 스타터 후보 1장 — 스프라이트 + 이름(비동기 조회) + 탭. 이름은 라인 조회로 채운다(캐시 → 보통 0콜).
private struct StarterCard: View {
    let store: CompanionStore
    let speciesID: Int
    let disabled: Bool
    let onPick: () -> Void
    @State private var name: String = ""

    var body: some View {
        Button(action: onPick) {
            VStack(spacing: 6) {
                SpriteView(speciesID: speciesID, size: 64, bob: true, animated: true)
                    .frame(width: 64, height: 64)
                Text(name.isEmpty ? "#\(speciesID)" : name)
                    .font(.caption2.weight(.medium)).lineLimit(1)
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Color.secondary.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.secondary.opacity(0.15)))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .task(id: speciesID) { name = await store.resolveSpeciesName(speciesID) }
    }
}

/// 희귀도 1종 캡슐 — 색 점 + 라벨 + 개수. 선택 시 원색 링 + 체크마크로 강조.
/// (solid 채움 대신 링+체크 — green/orange 위 흰 텍스트 대비 문제 회피 + 라이트/다크 양쪽 가독.
///  텍스트는 .primary 라 모드 자동 적응, 색 정체성은 점·링·체크로 유지 → 엔트리 배지와 안 어긋남.)
/// 0이면 흐리게(필터 불가).
struct RarityTally: View {
    let label: String
    let count: Int
    let color: Color
    var isSelected: Bool = false      // 이 희귀도로 필터 활성 → 원색 링 + 체크
    var body: some View {
        HStack(spacing: 3) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label).font(.system(size: 9, weight: isSelected ? .semibold : .medium))
            Text("\(count)").font(.system(size: 9, weight: .bold))
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 7, weight: .bold)).foregroundStyle(color)
            }
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(color.opacity(isSelected ? 0.22 : 0.12))
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(isSelected ? color : color.opacity(0.35),
                                        lineWidth: isSelected ? 1.5 : 0.5))
        .opacity(count == 0 ? 0.4 : 1)
    }
}

/// 포획 로그 요약 헤더 — 총 개체 수 + 희귀도별 개체 수 캡슐.
/// 개수 단위가 개체(store.dexCount)라 종 단위인 도감 헤더와 공유하지 않는다.
struct DexSummaryHeader: View {
    let store: CompanionStore
    let selected: Rarity?                  // nil = 필터 없음(전체)
    let onSelect: (Rarity) -> Void         // 캡슐 탭 → 토글
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(store.l.catchLogTitle).font(.callout.weight(.semibold))
                Text(store.l.dexTotal(store.dexEntries.count))
                    .font(.caption2).foregroundStyle(.secondary)
            }
            HStack(spacing: 4) {
                ForEach(rarityDisplayOrder, id: \.self) { r in
                    let count = store.dexCount(r)
                    Button { onSelect(r) } label: {
                        RarityTally(
                            label: store.l.rarityLabel(r), count: count, color: rarityColor(r),
                            isSelected: selected == r)
                    }
                    .buttonStyle(.plain)
                    .disabled(count == 0)          // 0마리 희귀도는 필터 불가
                    .help(store.l.dexFilterHint)
                }
            }
        }
    }
}

/// 컬렉션 탭 — 도감과 포획 로그를 하위 세그먼트로 전환한다.
///
/// 두 화면은 같은 데이터를 다른 축으로 본다:
///  - **도감**: 종 1개 = 1칸. 같은 라인을 여러 번 키워도 한 칸으로 접힌다(종 정보만).
///  - **로그**: 개체 1마리 = 1행. 같은 라인이 여러 행으로 나오는 게 정상 — 성격·획득 시각처럼
///    개체에 딸린 정보는 여기에만 있다.
/// 상위 탭(PopoverTab)은 그대로 4개 — 세그먼트 폭(332/2)이 넉넉해 탭바를 늘릴 필요가 없다.
struct CollectionView: View {
    let store: CompanionStore

    /// 도감·로그 공통 높이 — 상점·가방과 같은 520. 세그먼트를 전환할 때도, 탭을 넘나들 때도
    /// 팝오버가 리사이즈되지 않는다.
    ///
    /// 예산: 520 − 세그먼트 24 − 헤더 39 − 하단 줄 18 − 간격 24 = 격자 415. 6행 spacing 4 면
    /// 행이 65.8 이고, 칸 여백 6 과 이름 12 를 빼면 스프라이트에 47.8 이 남는다(현재 44).
    private static let contentHeight: CGFloat = 520

    var body: some View {
        if store.dexEntries.isEmpty {
            emptyState
        } else {
            DexGridView(store: store).frame(height: Self.contentHeight)
        }
    }

    /// 빈 도감 — 안내 마스코트(피카츄, PokéAPI) + 포켓몬을 모으라는 문구.
    private var emptyState: some View {
        VStack(spacing: 10) {
            SpriteView(speciesID: 25, size: 96, animated: true)   // 피카츄(움직임)
            Text(store.l.dexEmptyTitle).font(.callout.weight(.semibold))
            Text(store.l.dexEmptyHint)
                .font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }
}

/// 도감 — 보유 종만 도감 번호순으로, 한 페이지 24칸(4열×6행) 고정 격자.
///
/// 페이지식이라 ScrollView 를 쓰지 않는다 — 팝오버 재오픈 시 fitting size 가 줄어드는 기존 결함을
/// 우회(고정 높이 + maxHeight)가 아니라 회피로 피한다. 페이지 크기가 고정이라 모든 칸이 항상
/// 렌더되므로 지연 격자(LazyVGrid)도 필요 없다 — 평범한 VStack/HStack 으로 동기 렌더한다.
/// 미보유 종은 아예 그리지 않는다(물음표·실루엣 칸 없음).
private struct DexGridView: View {
    let store: CompanionStore
    @State private var selectedRarity: Rarity?
    @State private var page = 0

    /// 선택한 칸 — 하단 줄에 희귀도를 띄우고, 이로치를 잡은 종이면 스프라이트를 그 색으로 바꾼다.
    @State private var selectedID: Int?

    private static let columns = 4
    private static let rows = 6
    private static let pageSize = columns * rows      // 24
    private static let spacing: CGFloat = 4

    var body: some View {
        // 종별 집계는 한 번만 훑고 하위로 넘긴다 — 칸마다 재집계하면 도감이 O(칸×도감) 이 된다.
        let all = store.dexSpecies
        let visible = selectedRarity.map { r in all.filter { $0.rarity == r } } ?? all
        let pageCount = max(1, (visible.count + Self.pageSize - 1) / Self.pageSize)
        let current = min(page, pageCount - 1)   // 보유 종이 줄어든 경우(필터 등) 범위 방어
        let slice = Array(visible.dropFirst(current * Self.pageSize).prefix(Self.pageSize))
        VStack(alignment: .leading, spacing: 8) {
            header(all)
            grid(slice)
            footer(slice, current: current, pageCount: pageCount)
        }
        // 이름이 저장돼 있지 않은 구버전 졸업분을 채운다 — 격자는 저장분만 읽으므로 이게 없으면
        // 칸이 `#41` 로 남는다. 저장된 항목은 조회하지 않으므로 채워진 뒤로는 아무 일도 하지 않는다.
        .task { await store.backfillMissingDexNames() }
    }

    /// 희귀도 필터 — 로그와 같은 RarityTally 를 쓰되 개수는 **종 단위**다.
    /// (DexSummaryHeader 는 개체 수 dexCount 를 내부에서 직접 부르므로 재사용하려면 시그니처를 바꿔
    ///  로그 경로까지 건드려야 한다. 캡슐 4개짜리 헤더라 여기서는 인라인으로 둔다.)
    private func header(_ all: [CompanionStore.DexSpecies]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(store.l.dexTitle).font(.callout.weight(.semibold))
                // 총계는 필터와 무관한 전체 종 수 — 로그 헤더(dexTotal)와 같은 규칙.
                // 필터 중인 희귀도의 개수는 아래 캡슐이 이미 보여준다.
                Text(store.l.dexSpeciesTotal(all.count)).font(.caption2).foregroundStyle(.secondary)
            }
            HStack(spacing: 4) {
                ForEach(rarityDisplayOrder, id: \.self) { r in
                    let count = all.lazy.filter { $0.rarity == r }.count
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selectedRarity = (selectedRarity == r) ? nil : r
                            page = 0        // 필터가 바뀌면 페이지 범위도 바뀐다 — 항상 첫 페이지부터
                            selectedID = nil // 선택한 칸이 필터 밖으로 나가면 하단 줄이 유령 정보를 남긴다
                        }
                    } label: {
                        RarityTally(label: store.l.rarityLabel(r), count: count,
                                    color: rarityColor(r), isSelected: selectedRarity == r)
                    }
                    .buttonStyle(.plain)
                    .disabled(count == 0)          // 0종 희귀도는 필터 불가
                    .help(store.l.dexFilterHint)
                }
            }
        }
    }

    /// 고정 격자 — 남는 칸은 투명(테두리·물음표 없이 정렬만 유지).
    /// 모든 행에 maxHeight 를 걸어 6행이 높이를 균등 분할하게 한다 — 빈 칸의 Color 는 유연 크기라,
    /// 행마다 안 걸면 빈 행이 늘어나 채워진 행을 짓누른다(보유 종이 적을 때 첫 줄이 찌그러짐).
    private func grid(_ slice: [CompanionStore.DexSpecies]) -> some View {
        VStack(spacing: Self.spacing) {
            ForEach(0..<Self.rows, id: \.self) { row in
                HStack(spacing: Self.spacing) {
                    ForEach(0..<Self.columns, id: \.self) { col in
                        let i = row * Self.columns + col
                        if i < slice.count {
                            let sp = slice[i]
                            DexSpeciesCell(store: store, species: sp, isSelected: selectedID == sp.id) {
                                selectedID = (selectedID == sp.id) ? nil : sp.id
                            }
                            .frame(maxWidth: .infinity)
                        } else {
                            Color.clear.frame(maxWidth: .infinity)
                        }
                    }
                }
                .frame(maxHeight: .infinity)
            }
        }
        .frame(maxHeight: .infinity)
    }

    /// 하단 한 줄 — 왼쪽은 선택한 칸의 희귀도, 오른쪽은 페이저.
    /// 페이저가 1페이지라 안 보일 때도 이 줄을 **항상** 예약한다 — 페이지 수나 선택 여부에 따라
    /// 격자 높이가 흔들리지 않게.
    private func footer(_ slice: [CompanionStore.DexSpecies],
                        current: Int, pageCount: Int) -> some View {
        HStack(spacing: 8) {
            if let sel = slice.first(where: { $0.id == selectedID }) {
                // 칸은 번호·스프라이트·이름만 보여주므로 희귀도가 선택으로 얻는 정보다.
                Text("#\(sel.id) \(sel.name) · \(store.l.rarityLabel(sel.rarity))")
                    .font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            if pageCount > 1 {
                Button { page = max(0, current - 1); selectedID = nil } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.plain).disabled(current == 0)
                .accessibilityLabel(store.l.dexPagePrev)
                Text("\(current + 1) / \(pageCount)")
                    .font(.system(size: 10, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(store.l.dexPageLabel(current + 1, pageCount))
                Button { page = min(pageCount - 1, current + 1); selectedID = nil } label: {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.plain).disabled(current == pageCount - 1)
                .accessibilityLabel(store.l.dexPageNext)
            }
        }
        .font(.system(size: 11, weight: .semibold))
        .frame(height: 18)
    }
}

/// 도감 한 칸 — 도감 번호 + 스프라이트 + 종 이름. 종 정보만 담는다(성격·획득 횟수는 로그의 몫).
/// 정적 스프라이트만 쓴다(animated 생략) — 한 페이지 24칸을 GIF 로 동시 재생하면 CPU 가 안 된다.
private struct DexSpeciesCell: View {
    let store: CompanionStore
    let species: CompanionStore.DexSpecies
    let isSelected: Bool
    let onTap: () -> Void

    /// 로그(56)보다 작다 — 24칸 격자에 이름까지 담아야 한다. 원본 96×96 픽셀아트를
    /// interpolation(.none) 으로 축소하므로 이 크기에서도 식별에 문제없다.
    private static let thumb: CGFloat = 44

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 1) {
                // 기본은 일반색. 이로치를 잡은 종은 선택하면 이로치색으로 바뀐다 —
                // 일반·이로치를 둘 다 가진 종도 두 모습을 다 볼 수 있다(본가 HOME 의 이로치 토글과 같은 결).
                SpriteView(speciesID: species.id, size: Self.thumb,
                           shiny: species.isShiny && isSelected)
                    .frame(width: Self.thumb, height: Self.thumb)
                    // 표식은 스프라이트 아래가 아니라 위에 겹친다 — 별도 줄로 빼면 칸 높이가 넘친다.
                    // 이 줄은 번호·이로치와 폭을 다투지 않아 세 언어 모두 8pt 그대로 들어간다
                    // (가장 긴 en "RAISING" 이 캡슐 포함 45pt, 칸 안쪽 폭 74pt).
                    // `fixedSize` 필수 — 오버레이는 붙은 뷰(스프라이트 44)의 폭을 제안받아서, 없으면
                    // 칸이 아니라 스프라이트 폭에 갇혀 "RAISIN/G" 로 줄바꿈된다.
                    .overlay(alignment: .bottom) {
                        if species.isRaising { raisingBadge.fixedSize() }
                    }
                Text(species.name)
                    .font(.system(size: 9))
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            // 번호·이로치는 스프라이트(44)가 아니라 **칸 안쪽 폭**(74)에 건다 — 스프라이트에 걸면
            // 가운데 정렬된 44 기준이라 좌우 15 씩 안으로 밀려 번호가 칸 중앙 쪽에 떠 보인다.
            // 칸 기준으로 두면 양 끝으로 붙고, 픽셀아트 몸통과 겹치는 폭도 줄어든다.
            .overlay(alignment: .topLeading) { numberTag }
            .overlay(alignment: .topTrailing) {
                // ✨ = 이 종의 이로치를 잡은 적이 있다는 표식(탭하면 그 색으로 바뀐다).
                if species.isShiny {
                    Text("✨")
                        .font(.system(size: 8))
                        .padding(.horizontal, 2)
                        .background(.regularMaterial, in: Capsule())
                        .accessibilityLabel(store.l.dexShinyLabel)
                }
            }
            .padding(3)
            .background(Color.secondary.opacity(isSelected ? 0.16 : 0.06))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.accentColor, lineWidth: 1.5)
                }
            }
        }
        .buttonStyle(.plain)
        .help(tooltip)
        .accessibilityLabel(tooltip)
    }

    /// material 판 — 어두운 스프라이트 위에서도 읽히게(라이트/다크 자동).
    /// 스프라이트 위 라벨에 이미 쓰는 패턴과 동일.
    private var numberTag: some View {
        Text("#\(species.id)")
            .font(.system(size: 8, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 2)
            .background(.regularMaterial, in: Capsule())
    }

    /// "키우는 중" — 아직 졸업 기록이 없어 사라질 수 있는 칸임을 알린다. 포획 로그의 같은 뱃지와
    /// 글자·색을 맞춰 두 화면이 같은 말을 쓰게 한다. accent 틴트는 반투명이라 스프라이트가 비치므로
    /// material 을 한 겹 깔아 대비를 확보한다(로그는 카드 배경 위라 필요 없었다).
    private var raisingBadge: some View {
        Text(store.l.dexRaising.uppercased())
            .font(.system(size: 8, weight: .bold))
            .padding(.horizontal, 5).padding(.vertical, 1)
            .foregroundStyle(Color.accentColor)
            .background(Color.accentColor.opacity(0.14), in: Capsule())
            .background(.regularMaterial, in: Capsule())
    }

    /// 툴팁과 접근성 라벨이 같은 문장을 쓴다 — 칸이 글자로 못 보여주는 희귀도를 담는다.
    /// ✨ 는 이모지라 스크린리더가 일관되게 읽지 못하므로 명사로 함께 넣는다.
    private var tooltip: String {
        var parts = ["#\(species.id) \(species.name)", store.l.rarityLabel(species.rarity)]
        if species.isShiny { parts.append(store.l.dexShinyLabel) }
        if species.isRaising { parts.append(store.l.dexRaising) }
        return parts.joined(separator: " · ")
    }
}

/// 포획 로그 한 항목 — 희귀도·성격 헤더 + 진화 체인 스프라이트(각 밑에 종 이름) + 잡은 시각.
/// 체인 각 종의 이름은 저장분이 있으면 body 에서 즉시(플래시 없음), 없으면(구버전) .task 로 조회 후 백필.
private struct DexEntryRow: View {
    let store: CompanionStore
    let entry: DexEntry
    @State private var resolved: [Int: String] = [:]

    /// 카드 안쪽 여백. 진화 라인이 쓸 수 있는 폭 계산과 단일 소스를 공유한다.
    private static let cardPadding: CGFloat = 8

    var body: some View {
        // 저장분 우선(즉시·언어대응), 없으면 async 로 채운 resolved 사용.
        let names = resolved.isEmpty ? store.dexStoredChainNames(entry) : resolved
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(store.l.rarityLabel(entry.rarity).uppercased())
                    .font(.system(size: 8, weight: .bold))
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(rarityColor(entry.rarity)).foregroundStyle(.white)
                    .clipShape(Capsule())
                if store.isActiveDexEntry(entry) {
                    Text(store.l.dexRaising.uppercased())
                        .font(.system(size: 8, weight: .bold))
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Color.accentColor.opacity(0.14))
                        .foregroundStyle(Color.accentColor)
                        .clipShape(Capsule())
                }
                if entry.isShiny {
                    // 이모지는 스크린리더가 일관되게 읽지 못해 명사 라벨을 붙인다(도감 칸과 동일 규칙).
                    Text("✨").font(.system(size: 10))
                        .accessibilityLabel(store.l.dexShinyLabel)
                }
                Spacer()
                if let nature = entry.nature {
                    Text(nature.name(store.language))
                        .font(.system(size: 9)).foregroundStyle(.secondary)
                }
            }
            EvoLineView(nodes: entry.chainOrder.map { EvoLineItem(.species($0), .done) },
                        mysteryLabel: store.l.unknownNextEvolution, thumb: 56,
                        shiny: entry.isShiny, names: names,
                        maxWidth: PopoverMetrics.contentWidth - Self.cardPadding * 2)
            if let caughtAt = entry.caughtAt {
                Text(caughtAt, style: .relative).font(.system(size: 9)).foregroundStyle(.tertiary)
            }
        }
        .padding(Self.cardPadding)
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .task(id: "\(entry.id)-\(store.language.rawValue)") {
            if store.dexStoredChainNames(entry) == nil {   // 저장분 없으면(구버전) 조회
                resolved = await store.dexResolveChainNames(entry)
            }
        }
    }
}
