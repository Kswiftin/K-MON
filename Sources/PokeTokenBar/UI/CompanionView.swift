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
    /// 네트워크/캐시 실패 때 알 이모지 대신 호출자가 정한 식별자를 유지한다.
    var fallbackLabel: String? = nil
    /// 배틀 필드의 내 쪽만 등 스프라이트다. 한 뷰의 방향은 평생 바뀌지 않으므로 `needsReload` 의
    /// 축이 아니다 — 앞을 보던 스프라이트가 뒤로 도는 일은 없다.
    var back: Bool = false
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
         shiny: Bool = false, fallbackLabel: String? = nil, back: Bool = false, minFrameDelay: TimeInterval = 0) {
        self.speciesID = speciesID
        self.size = size
        self.bob = bob
        self.animated = animated
        self.shiny = shiny
        self.fallbackLabel = fallbackLabel
        self.back = back
        self.minFrameDelay = minFrameDelay
        // 캐시에 있으면 즉시(동기) 표시 — 재렌더 플래시 방지 + 정적 스냅샷에서도 보임.
        // speciesID==nil(알 상태)이면 알 스프라이트를 시드(없으면 body 가 🥚 폴백).
        let cached = speciesID.map { SpriteLoader.cachedImage(speciesID: $0, shiny: shiny, back: back) }
            ?? SpriteLoader.cachedEggImage()
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
            } else if let fallbackLabel {
                Text(fallbackLabel)
                    .font(.system(size: size * 0.38, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .frame(width: size, height: size)
                    .background(Color.secondary.opacity(0.14), in: Circle())
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
                let loaded = await SpriteLoader.image(speciesID: id, animated: false, shiny: shiny, back: back)
                // 취소된 로드는 반영하지 않는다(#138). 이로치 축은 **반영될 때만** 기록해
                // subject(종)와 loadedShiny 가 어긋나 다음 판정이 틀어지는 것을 막는다.
                if let next = subject.applyingLoad(loaded, for: id, cancelled: Task.isCancelled) {
                    apply(next)
                    loadedShiny = shiny
                }
            }
            guard animated else { return }
            // animated GIF 시도(shiny 미제공 종은 일반 GIF 폴백) → 프레임 2개 이상이면 순환 루프
            var ready = await SpriteLoader.decodedFrames(speciesID: id, shiny: shiny, back: back)
            if ready.isEmpty, shiny {
                ready = await SpriteLoader.decodedFrames(speciesID: id, shiny: false, back: back)
            }
            // 등 GIF 커버리지는 앞면과 다르다(`hasAnimatedSprite` 는 앞면 기준 하드코딩 집합).
            // 없으면 정적 등 PNG 가 이미 위에서 깔렸으니 프레임만 비워 둔다.
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
    /// 사탕 확인창을 열어 둔 상태. 되돌릴 수 없는 소비라 한 번 묻는다(가방과 같은 규칙).
    @State private var confirmingCandy = false
    // 별명 인라인 편집
    @State private var editingName = false
    @State private var nameDraft = ""
    @Environment(PokemonChatPresenter.self) private var chatPresenter
    /// 기술 목록은 처음부터 펼쳐 둔다. 파트너에게 무엇이 있는지가 홈에서 가장 자주 보는 정보인데,
    /// 접혀 있으면 팝오버를 열 때마다 한 번 더 눌러야 했다. 접으면 그 팝오버가 열려 있는 동안은
    /// 접힌 채로 있고, 닫았다 열면 다시 펼쳐진다(`@State` 라 팝오버 생명주기를 따른다).
    @State private var showingMoves = true

    private func commitNickname() {
        store.setNickname(nameDraft)
        editingName = false
    }

    /// 부화 임박(90%+) — 알이 흔들리고 문구가 바뀐다.
    private var eggImminent: Bool { store.isEgg && store.eggProgress >= 0.9 }

    /// 이름 옆 이상한사탕 — **쓸 수 있을 때만** 나온다. 가방까지 가지 않고 홈에서 바로 먹인다.
    ///
    /// 되돌릴 수 없는 소비라 한 번 묻는다(가방과 같은 규칙). 확인은 `confirmationDialog` 로
    /// 띄운다 — 인라인으로 펼치면 헤더 높이가 그 순간 늘어나 아래 카드가 통째로 밀린다.
    ///
    /// 사용 뒤 피드백("+XP"·진화 연출)은 이 헤더가 이미 `candyFeedbackSeq` 로 재생하고 있다.
    /// 가방에서 쓰면 홈 탭으로 보내는 것도 그 연출을 보여주기 위함이라, 여기서 쓰면 탭 이동조차
    /// 없이 그 자리에서 재생된다.
    private var rareCandyButton: some View {
        Button { confirmingCandy = true } label: {
            ItemIconView(kind: .rareCandy, size: 14)
        }
        .buttonStyle(.borderless).controlSize(.mini)
        .accessibilityLabel(store.l.itemName(.rareCandy))
        // 문구는 가방과 **같은 것**을 쓴다. 여기서 새로 지으면 같은 행동을 두 화면이 다르게 말한다.
        .confirmationDialog(store.l.useOnCurrent(store.displayName), isPresented: $confirmingCandy) {
            Button(store.l.use) { store.useRareCandy() }
            Button(store.l.cancel, role: .cancel) { confirmingCandy = false }
        }
    }

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
                        if store.hasActive, !editingName {
                            Button { if let id = store.activeMonID { chatPresenter.open(companionID: id) } } label: {
                                Image(systemName: "bubble.left.and.bubble.right")
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            .buttonStyle(.borderless).controlSize(.mini)
                            .accessibilityLabel(store.l.t("포켓몬과 대화", "Chat with Pokémon", "ポケモンと話す"))
                        }
                        // 쓸 수 있을 때만 나온다 — 재고가 0 이거나 알 상태면 자리조차 잡지 않는다.
                        // `canUseRareCandy` 는 가방이 보는 것과 **같은 판정**이다. 여기서 조건을
                        // 다시 쓰면 가방에선 회색인데 여기선 눌리는 두 화면이 생긴다.
                        if store.canUseRareCandy, !editingName { rareCandyButton }
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
                                 ? store.l.t("다음 레벨까지 \(GameNumberFormatter.compact(store.experienceToNextLevel)) EXP",
                                         "\(GameNumberFormatter.compact(store.experienceToNextLevel)) EXP to next level",
                                         "次のレベルまで \(GameNumberFormatter.compact(store.experienceToNextLevel)) EXP")
                                 : store.l.t("최고 레벨", "Max level", "最高レベル"))
                                .font(.caption2).foregroundStyle(.tertiary)
                            Spacer()
                        }
                        ProgressView(value: store.levelProgress)
                            .controlSize(.small).tint(.blue)
                        HStack(spacing: 6) {
                            Spacer(minLength: 0)
                            if let evolutionLevel = store.nextEvolutionLevel {
                                Text(store.l.t("Lv.\(evolutionLevel)에 진화", "Evolves at Lv.\(evolutionLevel)", "Lv.\(evolutionLevel) で進化"))
                                    .font(.caption2).foregroundStyle(.tertiary)
                            } else if let evolutionItem = store.nextEvolutionItem {
                                // 돌·교환 진화는 레벨이 아무리 올라도 저절로 일어나지 않는다 —
                                // 무엇을 사야 하는지 여기서 말해주지 않으면 알 길이 없다.
                                Text(store.l.evolutionNeedsItem(store.l.itemName(evolutionItem)))
                                    .font(.caption2).foregroundStyle(.tertiary)
                            } else if let graduationLevel = store.graduationLevelRequirement {
                                // 최종형에 닿으면 위 두 안내가 모두 사라진다. 그대로 두면 졸업 버튼이
                                // 안 뜨는 이유를 화면 어디서도 알 수 없다.
                                Text(store.l.graduatesAtLevel(graduationLevel))
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
                            Text(store.l.t("집중 세션을 완료하면 부화", "Complete focus sessions to hatch", "集中セッションの完了でふ化"))
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
            if let prompt = store.evolutionPrompt { EvolutionPromptCard(store: store, prompt: prompt) }
            if store.canGraduate { GraduateCard(store: store) }
            if let prompt = store.moveLearningPrompt { MoveLearningCard(store: store, prompt: prompt) }
            if store.isLoadingRelearnCandidates {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(store.l.relearnLoading).font(.caption2).foregroundStyle(.secondary)
                }
            } else if store.moveLearningPrompt == nil, let relearn = store.relearnPrompt {
                // 학습 카드가 떠 있을 땐 그리지 않는다 — 두 카드가 겹쳐 뜨면 어느 쪽 결정인지 알 수 없다.
                MoveRelearnCard(store: store, prompt: relearn)
            }
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
        case .levelUp: return store.justEvolvedTo.map { l.statusEvolved($0) } ?? l.statusGrew
        }
    }
}

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

    /// 마우스가 올라간 기술. 슬롯에 뭘 그릴지는 이 값 하나로 정해진다.
    @State private var hoveredMoveID: Int?

    /// 호버 상태 전이 — 들어온 행으로 바꾸기만 하고, 이탈 이벤트로는 지우지 않는다.
    /// 60초 방치 틱이 팝오버를 다시 그리면 AppKit 이 트래킹 영역을 재설치하는데, 커서가 안 움직였으면
    /// `mouseExited` 만 오고 재진입은 안 온다 — 이탈에서 지우면 마우스를 올려둔 채로 설명이 사라진다.
    /// 행 A→B 이동 때 A 이탈이 B 진입보다 늦게 오는 순서 뒤집힘도 같이 막힌다.
    static func hoverState(current: Int?, moveID: Int, isInside: Bool) -> Int? {
        isInside ? moveID : current
    }

    /// 슬롯 문구 — 호버 id 를 실제 기술로 되짚는 단계까지 여기 둔다. 되짚기를 뷰 안에 숨기면
    /// "상태는 맞는데 문구가 안 따라가는" 배선 결함을 테스트가 못 본다(#40과 같은 false confidence).
    /// 목록이 바뀐 뒤 남은 옛 id 는 엉뚱한 기술이 아니라 안내 문구로 떨어진다.
    static func panelText(hoveredID: Int?, moves: [MoveSpec], l: L) -> String {
        l.moveHoverText(hoveredID.flatMap { id in moves.first { $0.id == id } })
    }

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
                    row(move)
                        // 배경이 없는 행이라 이게 없으면 글자 사이 빈칸에서 호버가 안 잡힌다.
                        .contentShape(Rectangle())
                        .onHover { inside in
                            hoveredMoveID = Self.hoverState(current: hoveredMoveID,
                                                            moveID: move.id, isInside: inside)
                        }
                        .help(moveHelp(move))
                }
            }
            if !store.displayedMoves.isEmpty || store.isLoadingDisplayedMoves {
                MoveHoverPanel(text: Self.panelText(hoveredID: hoveredMoveID,
                                                    moves: store.displayedMoves, l: l))
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

    /// 접근성 보조 문구 겸 팝오버 밖 일반 창에서 뜨는 네이티브 툴팁 — 슬롯과 같은 어휘를 쓴다(갈리면 #10 재발).
    /// **표시 경로로 믿으면 안 된다**: `.help()` 는 NSPopover 안에서 아무것도 띄우지 않는다(defect-log 참고).
    /// 사용자가 꼭 봐야 하는 정보는 위 `MoveHoverPanel` 에 직접 그린다.
    private func moveHelp(_ move: MoveSpec) -> String {
        let details = l.moveDetailLine(move)
        if let description = move.description(store.language), !description.isEmpty {
            return "\(move.name(store.language))\n\(description)\n\(details)"
        }
        return "\(move.name(store.language))\n\(details)"
    }
}

/// 호버한 기술의 설명 슬롯. 높이를 고정한다 — 설명 길이를 따라 늘어나면 행 사이를
/// 지날 때마다 아래 콘텐츠가 밀려 팝오버 안이 떨린다(#9와 같은 부류).
/// 높이는 숫자 상수가 아니라 같은 폰트의 더미 줄에서 유도한다(폰트·OS 따라 실제 줄 높이가 다르다).
///
/// 줄 수는 3이다. 2줄로 두면 PokéAPI 최장급 설명(157자, 예: 그래스필드)이 잘리는데,
/// 잘린 나머지를 볼 경로가 없다 — `.help()` 툴팁은 팝오버 안에서 안 뜬다(이 화면의 원래 결함).
struct MoveHoverPanel: View {
    static let lines = 3

    let text: String

    var body: some View {
        ZStack(alignment: .topLeading) {
            Text(verbatim: Array(repeating: "—", count: Self.lines).joined(separator: "\n"))
                .opacity(0).accessibilityHidden(true)
            Text(text).lineLimit(Self.lines)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(6)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 7))
    }
}

/// 최종 진화형 도달 후 "다음 포켓몬으로 넘어가기" 카드. 졸업해도 개체는 박스로 가므로
/// 되돌릴 수 없는 동작이 아니다 — 문구도 그렇게 읽히게 쓴다(예전 자동 졸업은 영구 삭제였다).
private struct GraduateCard: View {
    let store: CompanionStore

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(store.l.t("다 키웠어요!", "Fully grown!", "育ちきりました！"), systemImage: "graduationcap.fill")
                .font(.caption.weight(.semibold))
            Text(store.l.t("도감에 기록하고 새 알을 받아요. 이 포켓몬은 박스에 보관돼 언제든 다시 데려올 수 있어요.",
                     "Records it in the Pokédex and starts a new egg. This Pokémon moves to your box, so you can bring it back anytime.",
                     "図鑑に記録して新しいタマゴを受け取ります。このポケモンはボックスに預けられ、いつでも連れ戻せます。"))
                .font(.caption2).foregroundStyle(.secondary)
            Button(store.l.t("도감에 등록하고 새 알 받기", "Record and get a new egg", "図鑑に登録して新しいタマゴ")) {
                store.graduateCompanion()
            }
            .buttonStyle(.borderedProminent).controlSize(.small)
        }
        .padding(9)
        .background(Color.green.opacity(0.10), in: RoundedRectangle(cornerRadius: 9))
    }
}

private struct EvolutionPromptCard: View {
    let store: CompanionStore
    let prompt: CompanionStore.EvolutionPrompt

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(store.l.t("진화할 수 있어요!", "Evolution is available!", "進化できます！"), systemImage: "sparkles")
                .font(.caption.weight(.semibold)).foregroundStyle(.orange)
            HStack(spacing: 10) {
                SpriteView(speciesID: prompt.fromSpeciesID, size: 46, shiny: store.state.active?.isShiny ?? false)
                Image(systemName: "arrow.right").foregroundStyle(.secondary)
                SpriteView(speciesID: prompt.toSpeciesID, size: 46, shiny: store.state.active?.isShiny ?? false)
                VStack(alignment: .leading, spacing: 2) {
                    Text(prompt.toName).font(.callout.bold())
                    Text(store.l.t("Lv.\(prompt.requiredLevel) 진화", "Evolves at Lv. \(prompt.requiredLevel)", "Lv.\(prompt.requiredLevel) で進化"))
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
            }
            Text(store.l.t("\(prompt.toName)(으)로 진화할까요?", "Evolve into \(prompt.toName)?", "\(prompt.toName) に進化させますか？"))
                .font(.caption)
            HStack {
                Button(store.l.t("예, 진화할래요", "Yes, evolve", "はい、進化させる")) { store.acceptEvolution() }
                    .buttonStyle(.borderedProminent).controlSize(.small)
                Button(store.l.t("아니오", "No", "いいえ")) { store.declineEvolution() }
                    .controlSize(.small)
            }
        }
        .padding(9)
        .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 9))
    }
}

/// 하트비늘 후보 목록(#97) — 고르면 기존 MoveLearningCard 로 넘어간다(교체 UI 는 그쪽 한 곳만).
private struct MoveRelearnCard: View {
    let store: CompanionStore
    let prompt: CompanionStore.RelearnPrompt

    var body: some View {
        let l = store.l
        VStack(alignment: .leading, spacing: 7) {
            Label(l.relearnHeader, systemImage: "arrow.counterclockwise")
                .font(.caption.weight(.semibold)).foregroundStyle(.pink)
            if prompt.candidates.isEmpty {
                Text(l.relearnEmpty).font(.caption2).foregroundStyle(.secondary)
            } else {
                Text(l.relearnPickTitle).font(.caption2).foregroundStyle(.secondary)
                // 후보가 수십 개까지 늘 수 있다 — 높이를 묶어 카드가 팝오버를 밀어내지 않게 한다.
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(prompt.candidates) { move in
                            Button {
                                store.pickRelearnCandidate(move)
                            } label: {
                                HStack(spacing: 5) {
                                    Text(move.name(store.language)).font(.caption)
                                    TypeBadge(type: move.type, language: store.language)
                                    Text(move.damageClass == .status
                                         ? l.moveCategoryStatus : l.movePowerShort(move.power))
                                        .font(.caption2).foregroundStyle(.secondary)
                                    Spacer()
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 180)
            }
            Button(l.relearnClose) { store.cancelRelearn() }.controlSize(.small)
        }
        .padding(9)
        .background(Color.pink.opacity(0.09), in: RoundedRectangle(cornerRadius: 9))
    }
}

private struct MoveLearningCard: View {
    let store: CompanionStore
    let prompt: CompanionStore.MoveLearningPrompt

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            // 하트비늘 유래면 "다시 떠올리기" 로 말한다 — 레벨업으로 새로 얻은 기술이 아니다.
            Label(prompt.origin == .heartScale
                  ? store.l.relearnHeader
                  : store.l.t("새로운 기술을 배울 수 있어요", "A new move is available", "新しいわざを覚えられます"),
                  systemImage: prompt.origin == .heartScale ? "arrow.counterclockwise" : "sparkles")
                .font(.caption.weight(.semibold))
                .foregroundStyle(prompt.origin == .heartScale ? Color.pink : Color.purple)
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(prompt.move.name(store.language)).font(.callout.bold())
                    HStack(spacing: 5) {
                        // 다시 배우는 기술엔 습득 레벨이 없다 — 현재 레벨을 여기 찍으면 없는 숫자를 만든다.
                        if prompt.origin == .levelUp {
                            Text("Lv.\(prompt.level)").font(.caption2).foregroundStyle(.secondary)
                        }
                        TypeBadge(type: prompt.move.type, language: store.language)
                        // 행 라벨과 같은 L 어휘를 쓴다 — 예전엔 "변화"/"Power N"이 박혀 있어
                        // 한국어 UI 에 "Power 90", 영어 UI 에 "변화"가 나왔다(#10 부류).
                        //
                        // 명중·PP 까지 세운다. 아래 후보 줄과 **같은 세 칸**이어야 위아래를 눈으로
                        // 맞대 볼 수 있다 — 배울 쪽만 위력을 보여주면 무엇과 바꾸는지는 여전히 모른다.
                        Group {
                            Text(prompt.move.damageClass == .status
                                 ? store.l.moveCategoryStatus : store.l.movePowerShort(prompt.move.power))
                            Text(prompt.move.accuracy.map { store.l.moveAccuracyShort($0) }
                                 ?? store.l.moveAlwaysHits)
                            Text(store.l.movePP(prompt.move.pp))
                        }
                        .font(.caption2).foregroundStyle(.secondary)
                        .lineLimit(1).minimumScaleFactor(0.75)
                    }
                }
                Spacer()
            }
            // 배울지 말지 고르는 자리다 — 무슨 기술인지 모르고 결정하게 두지 않는다.
            Text(store.l.moveHoverText(prompt.move))
                .font(.caption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let active = store.state.active, active.learnedMoves.count >= 4 {
                Text(store.l.t("잊을 기술을 선택하세요.", "Choose a move to forget.", "忘れるわざを選んでください。"))
                    .font(.caption2).foregroundStyle(.secondary)
                ForEach(Array(active.learnedMoves.enumerated()), id: \.element.id) { index, move in
                    MoveReplacementRow(move: move, newMoveName: prompt.move.name(store.language),
                                       language: store.language, l: store.l) {
                        store.acceptMoveLearning(replacing: index)
                    }
                }
            } else {
                HStack {
                    Button(store.l.t("예, 배울래요", "Yes, learn it", "はい、覚える")) {
                        store.acceptMoveLearning()
                    }.buttonStyle(.borderedProminent).controlSize(.small)
                    Button(store.l.t("아니오", "No", "いいえ")) { store.declineMoveLearning() }
                        .controlSize(.small)
                }
            }
            if store.state.active?.learnedMoves.count ?? 0 >= 4 {
                Button(store.l.t("배우지 않기", "Don't learn", "覚えない")) { store.declineMoveLearning() }
                    .controlSize(.small)
            }
        }
        .padding(9)
        .background(Color.purple.opacity(0.09), in: RoundedRectangle(cornerRadius: 9))
    }
}

/// 잊을 후보 한 줄 — 버리는 기술의 수치를 배울 기술과 **같은 어휘·같은 칸**으로 늘어놓는다.
///
/// 예전엔 `거품(물) → 일렉트릭볼` 한 줄이 전부였다. 위력 40 을 버리고 위력 0 을 배우는 선택과
/// 그 반대가 화면에서 똑같이 생겨서, 되돌릴 수 없는 결정을 이름만 보고 내려야 했다.
///
/// 줄마다 `→ 배울기술` 을 반복하지 않는다. 카드 전체가 그 기술 이야기이고, 같은 이름을 네 번
/// 되풀이하면 정작 비교해야 할 수치가 오른쪽으로 밀린다. 대신 접근성 라벨에 남긴다 —
/// 화면에서 얻던 문맥을 소리로 듣는 쪽에서 잃으면 안 된다.
private struct MoveReplacementRow: View {
    let move: MoveSpec
    let newMoveName: String
    let language: AppLanguage
    let l: L
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Text(move.name(language)).font(.caption.weight(.semibold))
                    .lineLimit(1).layoutPriority(1)
                TypeBadge(type: move.type, language: language)
                Spacer(minLength: 2)
                Group {
                    Text(move.damageClass == .status ? l.moveCategoryStatus : l.movePowerShort(move.power))
                    Text(move.accuracy.map { l.moveAccuracyShort($0) } ?? l.moveAlwaysHits)
                    Text(l.movePP(move.pp))
                }
                .font(.caption2).foregroundStyle(.secondary)
                .lineLimit(1).minimumScaleFactor(0.75)
            }
            .padding(.horizontal, 7).padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.28), lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(l.t("\(move.name(language)) 잊고 \(newMoveName) 배우기",
                                "Forget \(move.name(language)) and learn \(newMoveName)",
                                "\(move.name(language))を忘れて\(newMoveName)を覚える"))
        .accessibilityValue(l.moveDetailLine(move))
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
            Text(store.l.t("원하는 타입을 골라요", "Choose a type", "好きなタイプを選ぼう"))
                .font(.callout.weight(.semibold))
            if picking {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(store.l.t("알 속의 포켓몬을 만나고 있어요…", "Meeting the Pokémon inside the Egg…", "タマゴの中のポケモンに会っています…"))
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
                     ? store.l.t("선택한 타입의 1세대 미진화체가 알에서 무작위로 태어나요. 전설·환상은 제외됩니다.",
                             "A random unevolved Gen I Pokémon of that type will hatch. Legendary and Mythical Pokémon are excluded.",
                             "選んだタイプの第1世代・未進化ポケモンがランダムでふ化します。伝説・幻は除きます。")
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

/// 도감 헤더의 목표 한 줄 — 축마다 "아직 안 넘은 첫 목표" 하나씩.
///
/// **목표마다 게이지를 두지 않는다.** 미션 카드가 그렇게 했다가 예산을 두 배로 넘겼다(211pt). 도감
/// 헤더에 남은 여유는 24pt 뿐이라 한 줄이 상한이고, 진행도는 `12/25` 숫자로만 보인다
/// (`PopoverLayoutTests.testDexGoalStripFitsTheDexHeaderBudget` 이 지킨다).
///
/// 이 줄 때문에 새 탭을 만들지 않는다 — 탭을 늘리면 `PopoverTab` 높이 표와 360pt 세그먼트 피커가
/// 따라오는데 얻는 건 세 칸짜리 줄 하나다. 나중에 들어온 업적 세그먼트는 이 줄의 24pt 를 빼앗지
/// 않도록 `CollectionView` 프레임 **밖에** 얹혀 있다.
struct DexGoalStrip: View {
    let store: CompanionStore

    var body: some View {
        HStack(spacing: 6) {
            Text("🎯").accessibilityHidden(true)   // 장식 — 스크린리더가 이모지를 일관되게 읽지 못한다
            ForEach(store.dexGoalRows, id: \.goal.id) { row in
                HStack(spacing: 2) {
                    Text(store.l.dexGoalShortLabel(row.goal.kind)).foregroundStyle(.secondary)
                    if row.progress >= row.goal.target {
                        // 마지막 칸까지 넘겼다 — 남은 목표가 없으니 숫자 대신 완료 표식만 둔다.
                        Text("✓").fontWeight(.bold).foregroundStyle(.green)
                    } else {
                        Text("\(row.progress)/\(row.goal.target)").monospacedDigit()
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .font(.system(size: 9))
        .lineLimit(1)
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

    private enum Section: Hashable { case dex, achievements }
    @State private var section: Section = .dex

    private var l: L { store.l }

    /// 하위 화면 공통 높이 — 상점·가방과 같은 520. 두 세그먼트가 이 프레임을 공유하니 전환해도
    /// 높이가 튀지 않는다.
    ///
    /// 예산: 520 − 헤더 39 − 목표 줄 24 − 하단 줄 18 − 간격 24 = 격자 415. 6행 spacing 4 면
    /// 행이 65.8 이고, 칸 여백 6 과 이름 12 를 빼면 스프라이트에 47.8 이 남는다(현재 44).
    ///
    /// 이 24pt 는 원래 세그먼트 몫이었지만 목표 줄이 먼저 썼다 — 그래서 세그먼트는 이 프레임 밖에
    /// 얹는다. 안으로 넣으면 6행이 눌려 스프라이트가 잘린다.
    /// `PopoverLayoutTests` 가 읽는다 — 예산 검증이 실제 프레임을 따라오게 하려고 internal 이다.
    static let contentHeight: CGFloat = 520
    /// 업적 세그먼트에서 시즌 카드와 업적 선반 사이 간격. 예산 합산에 들어가므로 상수로 둔다.
    static let cardSpacing: CGFloat = 8

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("", selection: $section) {
                // 상위 탭이 "컬렉션" 이라 여기서는 `dexTitle`("도감") 을 쓴다 — `l.collection` 이면
                // 탭과 세그먼트가 같은 말이 되어 계층이 안 읽힌다.
                Text(l.dexTitle).tag(Section.dex)
                Text(l.achievementsTitle).tag(Section.achievements)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            // 두 분기가 **같은 프레임**을 공유한다 — 각자 프레임을 가지면 전환마다 높이가 달라진다.
            content.frame(height: Self.contentHeight, alignment: .top)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch section {
        case .dex:
            // 도감이 비어도 업적은 볼 수 있어야 한다 — 빈 화면은 도감 분기 안에만 둔다.
            if store.dexEntries.isEmpty { emptyState } else { DexGridView(store: store) }
        case .achievements:
            // 시즌 카드가 위 — 만료되는 쪽이 먼저 보여야 한다. 업적은 사라지지 않는다.
            VStack(alignment: .leading, spacing: Self.cardSpacing) {
                SeasonChallengeView(store: store)
                AchievementShelfView(store: store)
            }
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
        // 타입도 같은 자리에서 채운다 — 구버전 졸업분·오프라인 졸업은 타입이 nil 이라
        // 목표 줄의 타입 칸이 실제보다 낮게 보인다. 채워진 뒤로는 아무 요청도 하지 않는다.
        .task { await store.backfillMissingDexTypes() }
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
                // 육성중 몫을 따로 밝힌다 — 총계는 키우는 개체까지 세고 아래 목표 줄은 졸업 기록만
                // 센다(`dexGoalRows`). 안 밝히면 "12종" 과 "종 9/10" 이 나란히 보인다.
                Text(store.l.dexSpeciesTotal(all.count, raising: all.lazy.filter(\.isRaising).count))
                    .font(.caption2).foregroundStyle(.secondary)
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
            DexGoalStrip(store: store)
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
