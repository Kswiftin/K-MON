import AppKit

/// 포켓몬 스프라이트를 런타임에 받아 로컬(Application Support)에 캐시. 레포/번들에 미포함.
actor SpriteStore {
    static let shared = SpriteStore()
    /// `spriteURL` 이 actor 밖에서도 주소를 만들 수 있어야 해서 static 이다(테스트가 그 주소를 잰다).
    private static let base = "https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon"
    /// Higher-quality animated battle sprites. Keep this cache namespace separate from the
    /// former Gen-V assets so an existing install does not keep serving stale GIFs.
    private static let animatedBase = "\(base)/other/showdown"
    private let itemBase = "https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/items"
    private var mem: [String: Data] = [:]
    private var memOrder: [String] = []   // LRU 순서(최근 접근이 뒤). 상한 초과 시 앞(오래된 것)부터 evict
    // in-memory 스프라이트 캐시 상한 — 세션 중 종 변경 누적 무한증가 방지(#H1).
    // 도감 한 페이지가 24칸이라 상한 24 는 LRU 가 매 페이지 전환마다 완전 회전했다(돌아올 때 디스크
    // 동기 재읽기 24회). 정적 PNG 는 종당 0.5~1KB 라 64 로 올려도 메모리 비용이 무의미하다.
    private let memLimit = 64
    private let dir: URL = {
        let d = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PokeTokenBar/sprites")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

    /// 캐시 파일명 키 — 정적 PNG 키는 기존 형식을 유지하고, 애니메이션은 showdown 전용
    /// 네임스페이스를 사용해 이전 Gen-V GIF 캐시를 자동으로 무효화한다.
    ///
    /// `back` 은 배틀 필드가 쓰는 등 스프라이트다. **앞·뒤가 반드시 다른 키여야 한다** — 같은 키를
    /// 쓰면 먼저 받은 쪽이 양쪽에 나와서 "등 스프라이트가 안 붙는다" 가 아니라 "정면이 나온다" 로
    /// 보인다. 기본값이 `false` 인 것도 이유가 있다: 앞면 키가 바뀌면 기존 설치의 디스크 캐시가
    /// 통째로 무효화된다.
    static func cacheKey(speciesID: Int, animated: Bool, shiny: Bool, back: Bool = false) -> String {
        let facing = back ? "back-" : ""
        if animated {
            return "\(speciesID)-showdown-\(facing)\(shiny ? "shiny" : "normal")"
        }
        return "\(speciesID)-\(facing)\(shiny ? "sh" : "")s"
    }

    /// 원격 스프라이트 주소. 등 스프라이트는 앞면과 **폴더 하나 차이**다(계획 §6.4 에서 200 확인).
    /// 위치를 틀리면 조용히 404 → 앞면 폴백으로 떨어져 증상이 "정면이 나온다" 가 된다.
    nonisolated static func spriteURL(speciesID: Int, animated: Bool, shiny: Bool, back: Bool) -> String {
        let root = animated ? animatedBase : base
        let folders = (back ? "/back" : "") + (shiny ? "/shiny" : "")
        return "\(root)\(folders)/\(speciesID).\(animated ? "gif" : "png")"
    }

    func data(speciesID: Int, animated: Bool, shiny: Bool = false, back: Bool = false) async -> Data? {
        if animated, !PokemonAssets.hasAnimatedSprite(speciesID: speciesID) { return nil }
        let key = Self.cacheKey(speciesID: speciesID, animated: animated, shiny: shiny, back: back)
        if let d = mem[key] { touch(key); return d }
        let ext = animated ? "gif" : "png"
        let file = dir.appendingPathComponent("\(key).\(ext)")
        if let d = try? Data(contentsOf: file) { remember(key, d); return d }
        let urlStr = Self.spriteURL(speciesID: speciesID, animated: animated, shiny: shiny, back: back)
        guard let url = URL(string: urlStr),
              let (d, resp) = try? await URLSession.shared.data(from: url),
              (resp as? HTTPURLResponse)?.statusCode == 200, !d.isEmpty else { return nil }
        try? d.write(to: file, options: .atomic)   // torn write 방지 — 크래시/강제종료 시 손상 캐시가 남지 않게
        remember(key, d)
        return d
    }

    /// 아이템 스프라이트(정적 PNG, 이름 기반). 포켓몬과 같은 메모리/디스크 캐시 사용(키 "item-<name>",
    /// 포켓몬 파일 "<id>-..." 과 안 겹침). 미제공(404)/오프라인이면 nil → 뷰가 이모지로 폴백.
    func data(itemName: String) async -> Data? {
        let key = "item-\(itemName)"
        if let d = mem[key] { touch(key); return d }
        let file = dir.appendingPathComponent("\(key).png")
        if let d = try? Data(contentsOf: file) { remember(key, d); return d }
        guard let url = URL(string: "\(itemBase)/\(itemName).png"),
              let (d, resp) = try? await URLSession.shared.data(from: url),
              (resp as? HTTPURLResponse)?.statusCode == 200, !d.isEmpty else { return nil }
        try? d.write(to: file, options: .atomic)
        remember(key, d)
        return d
    }

    /// 알 스프라이트(정적, pokemon/egg.png) — 애니메이션 알은 없음. 포켓몬/아이템과 같은 메모리·디스크 캐시(키 "egg").
    func eggData() async -> Data? {
        let key = "egg"
        if let d = mem[key] { touch(key); return d }
        let file = dir.appendingPathComponent("egg.png")
        if let d = try? Data(contentsOf: file) { remember(key, d); return d }
        guard let url = URL(string: "\(Self.base)/egg.png"),
              let (d, resp) = try? await URLSession.shared.data(from: url),
              (resp as? HTTPURLResponse)?.statusCode == 200, !d.isEmpty else { return nil }
        try? d.write(to: file, options: .atomic)
        remember(key, d)
        return d
    }

    /// in-memory 캐시에 넣고 LRU 상한 유지(#H1) — 세션 중 종이 여러 번 바뀌어도 무한 성장 방지.
    private func remember(_ key: String, _ data: Data) {
        mem[key] = data
        touch(key)
        while memOrder.count > memLimit {
            let old = memOrder.removeFirst()
            mem.removeValue(forKey: old)
        }
    }
    /// 접근/삽입 키를 최근(뒤)으로 이동 — 활성 종이 evict 되지 않게 하는 LRU.
    private func touch(_ key: String) {
        if let i = memOrder.firstIndex(of: key) { memOrder.remove(at: i) }
        memOrder.append(key)
    }
}

@MainActor
enum SpriteLoader {
    static let cacheDir: URL = {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PokeTokenBar/sprites")
    }()
    private static let imageCache = NSCache<NSString, NSImage>()
    private static var frameCache: [String: [(image: NSImage, delay: TimeInterval)]] = [:]

    /// 디스크 캐시에 이미 있으면 동기 반환(네트워크 없음). 없으면 nil.
    /// shiny 캐시 미스는 일반 캐시로 폴백 — 오프라인에서 live mon 이 알 글리프로 보이는 것 방지.
    static func cachedImage(speciesID: Int, animated: Bool = false, shiny: Bool = false,
                            back: Bool = false) -> NSImage? {
        let key = SpriteStore.cacheKey(speciesID: speciesID, animated: animated, shiny: shiny, back: back)
        if let image = imageCache.object(forKey: key as NSString) { return image }
        let ext = animated ? "gif" : "png"
        let f = cacheDir.appendingPathComponent("\(key).\(ext)")
        if let d = try? Data(contentsOf: f), let img = NSImage(data: d) {
            imageCache.setObject(img, forKey: key as NSString)
            return img
        }
        if shiny { return cachedImage(speciesID: speciesID, animated: animated, shiny: false, back: back) }
        guard back else { return nil }
        return cachedImage(speciesID: speciesID, animated: animated, shiny: shiny, back: false)
    }

    /// 정적 스프라이트. animated=true 면 Gen-V 움직이는 스프라이트(없으면 정적으로 폴백).
    /// shiny=true 는 색이 다른 스프라이트 — 미제공 종이면 일반으로 폴백.
    /// back=true 는 배틀 필드의 내 쪽 등 스프라이트 — 커버리지가 앞면과 달라 폴백 사슬이 한 칸 길다.
    static func image(speciesID: Int, animated: Bool = false, shiny: Bool = false,
                      back: Bool = false) async -> NSImage? {
        let key = SpriteStore.cacheKey(speciesID: speciesID, animated: animated, shiny: shiny, back: back)
        if let image = imageCache.object(forKey: key as NSString) { return image }
        if animated,
           let d = await SpriteStore.shared.data(speciesID: speciesID, animated: true, shiny: shiny, back: back),
           let img = NSImage(data: d) {
            imageCache.setObject(img, forKey: key as NSString)
            return img
        }
        if let d = await SpriteStore.shared.data(speciesID: speciesID, animated: false, shiny: shiny, back: back),
           let img = NSImage(data: d) {
            imageCache.setObject(img, forKey: SpriteStore.cacheKey(speciesID: speciesID, animated: false,
                                                                  shiny: shiny, back: back) as NSString)
            return img
        }
        // shiny 미제공 → 일반 폴백
        if shiny { return await image(speciesID: speciesID, animated: animated, shiny: false, back: back) }
        // 등 스프라이트가 아예 없는 종 → 앞면. 배틀 중에 아무것도 안 그리는 것보다 낫지만, 이 폴백은
        // "등이 안 붙는다" 가 아니라 "정면이 나온다" 로 보이는 부류라 조용히 넘기지 않는다.
        guard back else { return nil }
        AppLog.write("sprite: no back asset for species \(speciesID) — using the front sprite")
        return await image(speciesID: speciesID, animated: animated, shiny: shiny, back: false)
    }

    static func decodedFrames(speciesID: Int, shiny: Bool,
                              back: Bool = false) async -> [(image: NSImage, delay: TimeInterval)] {
        let key = SpriteStore.cacheKey(speciesID: speciesID, animated: true, shiny: shiny, back: back)
        if let cached = frameCache[key] { return cached }
        guard let data = await SpriteStore.shared.data(speciesID: speciesID, animated: true,
                                                      shiny: shiny, back: back) else { return [] }
        let decoded = GIFDecoder.frames(from: data)
        guard decoded.count >= 2 else { return [] }
        frameCache[key] = decoded
        return decoded
    }

    /// 아이템 스프라이트 — 디스크 캐시 동기 조회(없으면 nil). 아이콘 즉시 표시용(재렌더 플래시 방지).
    static func cachedItemImage(name: String) -> NSImage? {
        let f = cacheDir.appendingPathComponent("item-\(name).png")
        if let d = try? Data(contentsOf: f), let img = NSImage(data: d) { return img }
        return nil
    }

    /// 아이템 스프라이트 — 런타임 로드(+캐시). 미제공/실패면 nil(뷰가 이모지로 폴백).
    static func itemImage(name: String) async -> NSImage? {
        guard let d = await SpriteStore.shared.data(itemName: name), let img = NSImage(data: d) else { return nil }
        return img
    }

    /// 알 스프라이트는 96×96 캔버스에 실제 알이 28×30(≈29%)만 차지 — 그대로 쓰면 프레임에서 아주 작게
    /// 보인다(🥚 이모지는 여백이 없어 꽉 찼음). 콘텐츠 경계로 1회 크롭해 여백을 제거하고 캐시 →
    /// 상점·홈 등 모든 크기에서 이모지처럼 프레임을 꽉 채운다.
    private static var croppedEgg: NSImage?

    /// 크롭 완료분만 동기 반환(미준비면 nil — 동기 크롭 안 함, 히치 방지). 첫 표시 때만 🥚 폴백 후 eggImage 로 교체.
    static func cachedEggImage() -> NSImage? { croppedEgg }

    /// 알 스프라이트 — 런타임 로드 + 콘텐츠 크롭(최초 1회 메모이즈). 오프라인/실패면 nil(뷰가 🥚 폴백).
    static func eggImage() async -> NSImage? {
        if let c = croppedEgg { return c }
        guard let d = await SpriteStore.shared.eggData(), let img = NSImage(data: d) else { return nil }
        croppedEgg = cropToContent(img)
        return croppedEgg
    }

    /// 비투명(alpha>0) 콘텐츠 경계로 크롭 — 큰 투명 여백 제거. 96×96 1회만 수행(메모이즈).
    private static func cropToContent(_ image: NSImage) -> NSImage {
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return image }
        let w = rep.pixelsWide, h = rep.pixelsHigh
        var minX = w, minY = h, maxX = -1, maxY = -1
        for y in 0..<h {
            for x in 0..<w where (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.01 {
                if x < minX { minX = x }; if x > maxX { maxX = x }
                if y < minY { minY = y }; if y > maxY { maxY = y }
            }
        }
        guard maxX >= minX, maxY >= minY else { return image }
        // 콘텐츠 bbox 를 정사각(긴 변 기준)으로 확장해 중앙 정렬 — 알 콘텐츠는 28×30(세로가 김)이라 그대로
        // 크롭하면 SpriteView 의 size×size 정사각 프레임에서 가로로 늘어나 뚱뚱해진다. 정사각 크롭이면 비율 보존.
        let bw = maxX - minX + 1, bh = maxY - minY + 1
        let side = min(max(bw, bh), min(w, h))
        let sx = max(0, min(minX - (side - bw) / 2, w - side))
        let sy = max(0, min(minY - (side - bh) / 2, h - side))
        guard let cg = rep.cgImage?.cropping(to: CGRect(x: sx, y: sy, width: side, height: side))
        else { return image }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }
}
