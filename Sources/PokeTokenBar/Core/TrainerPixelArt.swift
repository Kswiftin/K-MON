import Foundation

/// 트레이너 도트. 16×24, 4방향 × 3프레임. `right` 는 `left` 의 좌우 반전이다.
/// 스타일은 3세대 오버월드 비율을 참고했고 픽셀은 전부 새로 그렸다(공식 에셋 복제 아님).
///
/// 행을 문자열로 직접 세지 않고 `Grid`(좌표 채우기)로 만든다 — 24행×16열을 손으로
/// 맞추다 줄 길이가 어긋나면 `PixelSprite.init(rows:key:)` 의 precondition 이 바로 죽는다.
enum TrainerPixelArt {
    static let width = 16, height = 24
    static let key: [Character: UInt8] = [
        "o": 1, "s": 2, "S": 3, "h": 4, "H": 5, "w": 6, "r": 7, "b": 8, "k": 9, "y": 10, "g": 11, "n": 12, "d": 13
    ]
    static let palette = PixelPalette(colors: [
        0, 0x1B1B2F, 0xF3C9A6, 0xD9A07A, 0x5A3A2A, 0x3A241A, 0xF6F6F6,
        0xD83A3A, 0x3B6ED8, 0xB8A46E, 0xE3C55A, 0x9A9A9A, 0x8A5A2B, 0x3C3C50
    ])

    private static func sprite(_ rows: [String]) -> PixelSprite { PixelSprite(rows: rows, key: key) }

    static func body(_ facing: Facing, step: Int) -> PixelSprite {
        switch facing {
        case .down: return sprite(bodyDown[step])
        case .up: return sprite(bodyUp[step])
        case .left: return sprite(bodyLeft[step])
        case .right: return sprite(bodyLeft[step]).flippedHorizontally()
        }
    }

    static func layer(_ item: OutfitItem, facing: Facing, step: Int) -> PixelSprite {
        let table = layers[item]!
        switch facing {
        case .down: return sprite(table.down[step])
        case .up: return sprite(table.up[step])
        case .left: return sprite(table.left[step])
        case .right: return sprite(table.left[step]).flippedHorizontally()
        }
    }

    struct LayerSet { let down: [[String]]; let up: [[String]]; let left: [[String]] }

    // MARK: - 좌표 채우기 격자

    private struct Grid {
        var cells = Array(repeating: Array(repeating: Character("."), count: TrainerPixelArt.width), count: TrainerPixelArt.height)

        mutating func fillRect(cols: ClosedRange<Int>, rows: ClosedRange<Int>, _ c: Character) {
            for y in rows where cells.indices.contains(y) {
                for x in cols where cells[y].indices.contains(x) { cells[y][x] = c }
            }
        }

        mutating func set(_ x: Int, _ y: Int, _ c: Character) {
            guard cells.indices.contains(y), cells[y].indices.contains(x) else { return }
            cells[y][x] = c
        }

        var rows: [String] { cells.map { String($0) } }
    }

    private static func rectLayer(cols: ClosedRange<Int>, rows: ClosedRange<Int>, _ c: Character) -> [String] {
        var g = Grid()
        g.fillRect(cols: cols, rows: rows, c)
        return g.rows
    }

    private static func pointsLayer(_ points: [(Int, Int)], _ c: Character) -> [String] {
        var g = Grid()
        for p in points { g.set(p.0, p.1, c) }
        return g.rows
    }

    /// 여러 도형(사각·점)을 한 레이어에 겹쳐 그린다 — 모자 챙, 소매, 꽁지머리처럼
    /// 밑 사각형 하나로 못 그리는 실루엣용.
    private static func layerRows(_ paint: (inout Grid) -> Void) -> [String] {
        var g = Grid()
        paint(&g)
        return g.rows
    }

    // MARK: - 본체(맨몸)

    /// 얼굴 rows2–8, 몸통 rows9–15(손은 몸통 폭 바깥 `handXs` 열에 튀어나와 옷에 안 가려진다),
    /// 다리 rows16–20, 신발 rows21–23. `step` 1/2 는 한쪽 다리를 1행 낮게(발 내밈), 반대쪽
    /// 손을 1행 높게(팔 흔듦) 그려 정지 자세와 구분한다 — 머리는 고정.
    private static func bodyFrame(
        headCols: ClosedRange<Int>, eyeXs: [Int], hasEyes: Bool,
        torsoCols: ClosedRange<Int>, handXs: (Int, Int),
        legLeft: ClosedRange<Int>, legRight: ClosedRange<Int>,
        step: Int
    ) -> [String] {
        var g = Grid()
        g.fillRect(cols: headCols, rows: 2...8, "o")
        let inner = (headCols.lowerBound + 1)...(headCols.upperBound - 1)
        g.fillRect(cols: inner, rows: 3...8, "s")
        if hasEyes {
            g.fillRect(cols: inner, rows: 2...4, "h")
            g.set(inner.lowerBound, 2, "H")
            g.set(inner.upperBound, 2, "H")
            for x in eyeXs { g.set(x, 6, "o") }
        } else {
            g.fillRect(cols: inner, rows: 2...8, "h")
            g.set(inner.lowerBound, 3, "H")
            g.set(inner.upperBound, 3, "H")
        }

        g.fillRect(cols: torsoCols, rows: 9...15, "d")
        let leftHandRows: ClosedRange<Int> = step == 2 ? 11...13 : 12...14
        let rightHandRows: ClosedRange<Int> = step == 1 ? 11...13 : 12...14
        g.fillRect(cols: handXs.0...handXs.0, rows: leftHandRows, "s")
        g.fillRect(cols: handXs.1...handXs.1, rows: rightHandRows, "s")

        let leftLegTop = step == 1 ? 17 : 16
        let rightLegTop = step == 2 ? 17 : 16
        g.fillRect(cols: legLeft, rows: leftLegTop...20, "d")
        g.fillRect(cols: legRight, rows: rightLegTop...20, "d")
        g.fillRect(cols: legLeft, rows: 21...23, "o")
        g.fillRect(cols: legRight, rows: 21...23, "o")
        return g.rows
    }

    static let bodyDown: [[String]] = (0..<3).map {
        bodyFrame(headCols: 4...11, eyeXs: [6, 9], hasEyes: true,
                  torsoCols: 4...11, handXs: (3, 12), legLeft: 4...6, legRight: 9...11, step: $0)
    }
    static let bodyUp: [[String]] = (0..<3).map {
        bodyFrame(headCols: 4...11, eyeXs: [], hasEyes: false,
                  torsoCols: 4...11, handXs: (3, 12), legLeft: 4...6, legRight: 9...11, step: $0)
    }
    static let bodyLeft: [[String]] = (0..<3).map {
        bodyFrame(headCols: 5...10, eyeXs: [6], hasEyes: true,
                  torsoCols: 5...10, handXs: (4, 11), legLeft: 5...6, legRight: 9...10, step: $0)
    }

    // MARK: - 착용 레이어

    /// 걷기 스텝에 안 움직이는 부위(모자·머리·상의·하의)는 세 스텝이 같은 행을 그대로
    /// 쓴다 — 본체만 걸음마다 달라지면 충분하다(#79 던전 방걷기 설계).
    private static func stillLayer(_ rows: [String]) -> [[String]] { Array(repeating: rows, count: 3) }

    // MARK: 모자 — 색만 다르면 같은 슬롯 안에서 구분이 안 된다. 챙 모양으로 실루엣을 가른다.

    private static let capRedSet = LayerSet(
        down: stillLayer(layerRows { g in
            g.fillRect(cols: 4...11, rows: 0...4, "r")
            g.fillRect(cols: 3...12, rows: 5...5, "r") // 챙 — 정면에서 좌우로 1칸씩 더 나온다
        }),
        up: stillLayer(layerRows { g in
            g.fillRect(cols: 4...11, rows: 0...4, "r")
            g.fillRect(cols: 3...12, rows: 5...5, "r")
        }),
        left: stillLayer(layerRows { g in
            g.fillRect(cols: 5...10, rows: 0...4, "r")
            g.fillRect(cols: 4...10, rows: 5...5, "r") // 챙이 진행 방향(왼쪽)으로만 1칸 나온다
        })
    )

    private static let strawHatSet = LayerSet(
        down: stillLayer(layerRows { g in
            g.fillRect(cols: 4...11, rows: 0...4, "y")
            g.fillRect(cols: 2...13, rows: 5...5, "y") // 밀짚모자 챙 — 캡보다 훨씬 넓다
        }),
        up: stillLayer(layerRows { g in
            g.fillRect(cols: 4...11, rows: 0...4, "y")
            g.fillRect(cols: 2...13, rows: 5...5, "y")
        }),
        left: stillLayer(layerRows { g in
            g.fillRect(cols: 5...10, rows: 0...4, "y")
            g.fillRect(cols: 3...12, rows: 5...5, "y")
        })
    )

    private static let helmetExplorerSet = LayerSet(
        down: stillLayer(layerRows { g in
            g.fillRect(cols: 4...11, rows: 0...5, "g") // 챙 없이 머리 전체를 덮는 헬멧
            g.set(7, 0, "y") // 정면 랜턴 장식
        }),
        up: stillLayer(layerRows { g in
            g.fillRect(cols: 4...11, rows: 0...5, "g")
            g.set(7, 0, "y")
        }),
        left: stillLayer(layerRows { g in
            g.fillRect(cols: 5...10, rows: 0...5, "g")
            g.set(5, 2, "y")
        })
    )

    // MARK: 머리 — 단발은 아래가 둥글게 퍼지고, 묶은 머리는 뒤/옆에 꽁지가 삐친다.

    private static let hairBobSet = LayerSet(
        down: stillLayer(layerRows { g in
            g.fillRect(cols: 4...11, rows: 2...8, "h")
            g.fillRect(cols: 3...12, rows: 6...8, "h") // 단발 — 아래쪽이 옆으로 둥글게 퍼진다
        }),
        up: stillLayer(layerRows { g in
            g.fillRect(cols: 4...11, rows: 2...8, "h")
            g.fillRect(cols: 3...12, rows: 6...8, "h")
        }),
        left: stillLayer(layerRows { g in
            g.fillRect(cols: 5...10, rows: 2...8, "h")
            g.fillRect(cols: 4...11, rows: 6...8, "h")
        })
    )

    private static let hairPonySet = LayerSet(
        down: stillLayer(layerRows { g in
            g.fillRect(cols: 4...11, rows: 2...8, "h") // 정면은 앞머리만 — 묶은 머리는 안 보인다
        }),
        up: stillLayer(layerRows { g in
            g.fillRect(cols: 4...11, rows: 2...8, "h")
            g.fillRect(cols: 7...8, rows: 9...11, "h") // 뒷모습 — 묶은 머리가 등 위로 늘어진다
        }),
        left: stillLayer(layerRows { g in
            g.fillRect(cols: 5...10, rows: 2...8, "h")
            g.fillRect(cols: 10...11, rows: 7...9, "h") // 옆모습 — 뒤통수 밖으로 꽁지가 삐친다
        })
    )

    private static let hairMessySet = LayerSet(
        down: stillLayer(layerRows { g in
            g.fillRect(cols: 4...11, rows: 2...8, "H")
            g.set(5, 1, "H"); g.set(9, 1, "H") // 뻗친 머리 — 정수리 위로 두 갈래가 삐친다
        }),
        up: stillLayer(layerRows { g in
            g.fillRect(cols: 4...11, rows: 2...8, "H")
            g.set(5, 1, "H"); g.set(9, 1, "H")
        }),
        left: stillLayer(layerRows { g in
            g.fillRect(cols: 5...10, rows: 2...8, "H")
            g.set(6, 1, "H"); g.set(9, 1, "H")
        })
    )

    // MARK: 상의 — 재킷은 손목까지 오는 소매(그래도 손끝 한 줄은 남겨 살이 보인다) + 깃,
    // 티셔츠는 반팔(그 아래는 그냥 몸통뿐이라 소매가 없다).

    private static let jacketBlueSet = LayerSet(
        down: stillLayer(layerRows { g in
            g.fillRect(cols: 4...11, rows: 9...15, "b")
            g.fillRect(cols: 3...3, rows: 12...13, "b")
            g.fillRect(cols: 12...12, rows: 12...13, "b") // 소매가 손목까지 — 손끝(14행)만 남긴다
            g.fillRect(cols: 7...8, rows: 9...9, "w") // 깃
        }),
        up: stillLayer(layerRows { g in
            g.fillRect(cols: 4...11, rows: 9...15, "b")
            g.fillRect(cols: 3...3, rows: 12...13, "b")
            g.fillRect(cols: 12...12, rows: 12...13, "b")
            g.fillRect(cols: 7...8, rows: 9...9, "w")
        }),
        left: stillLayer(layerRows { g in
            g.fillRect(cols: 5...10, rows: 9...15, "b")
            g.fillRect(cols: 4...4, rows: 12...13, "b")
            g.fillRect(cols: 11...11, rows: 12...13, "b")
            g.fillRect(cols: 7...8, rows: 9...9, "w")
        })
    )

    private static let teeWhiteSet = LayerSet(
        down: stillLayer(layerRows { g in g.fillRect(cols: 4...11, rows: 9...15, "w") }),
        up: stillLayer(layerRows { g in g.fillRect(cols: 4...11, rows: 9...15, "w") }),
        left: stillLayer(layerRows { g in g.fillRect(cols: 5...10, rows: 9...15, "w") })
    )

    // 업적 보상 — 웃옷보다 길게 걸쳐(rows9–18) 확실히 구분되는 롱코트.
    private static let cloakWornSet = LayerSet(
        down: stillLayer(layerRows { g in g.fillRect(cols: 4...11, rows: 9...18, "n") }),
        up: stillLayer(layerRows { g in g.fillRect(cols: 4...11, rows: 9...18, "n") }),
        left: stillLayer(layerRows { g in g.fillRect(cols: 5...10, rows: 9...18, "n") })
    )

    // MARK: 하의 — 반바지와 장화는 같은 슬롯(`OutfitSlot.bottom`)이라 동시 착용이 없고,
    // 덮는 행 범위 자체가 달라(15–20 대 18–23) 실루엣이 이미 갈린다.

    private static func legSpanSet(rows: ClosedRange<Int>, char: Character) -> LayerSet {
        LayerSet(
            down: stillLayer(rectLayer(cols: 4...11, rows: rows, char)),
            up: stillLayer(rectLayer(cols: 4...11, rows: rows, char)),
            left: stillLayer(rectLayer(cols: 5...10, rows: rows, char))
        )
    }

    /// 배낭 — `left` 만 등판 전체(열 2–4), `down`/`up` 은 어깨끈 두 점만
    /// (설계 문서 "backpack columns 2–4 on left only, straps only on down/up").
    private static let backpackSet = LayerSet(
        down: stillLayer(pointsLayer([(5, 10), (10, 10)], "n")),
        up: stillLayer(pointsLayer([(5, 10), (10, 10)], "n")),
        left: stillLayer(rectLayer(cols: 2...4, rows: 9...15, "n"))
    )

    static let layers: [OutfitItem: LayerSet] = [
        .capRed: capRedSet,
        .strawHat: strawHatSet,
        .helmetExplorer: helmetExplorerSet,
        .hairBob: hairBobSet,
        .hairPony: hairPonySet,
        .hairMessy: hairMessySet,
        .jacketBlue: jacketBlueSet,
        .teeWhite: teeWhiteSet,
        .cloakWorn: cloakWornSet,
        .shortsKhaki: legSpanSet(rows: 15...20, char: "k"),
        .bootsLong: legSpanSet(rows: 18...23, char: "g"),
        .backpack: backpackSet,
    ]
}
