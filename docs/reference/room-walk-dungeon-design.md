---
summary: "오늘의 던전을 '방 화면에서 트레이너가 걸어 다니는' 조작으로 바꾸고, 그 트레이너를 꾸미는 시스템과 친구 목록 아바타 공유의 기반을 놓는 설계 (spec 1/2)."
read_when:
  - 던전 방 화면(`RoomCanvas`)·격자 이동(`DungeonWalker`)·키 입력(`KeyCapture`)을 손볼 때
  - 트레이너 꾸미기 카탈로그(`OutfitItem`)·합성(`TrainerSprite`)에 아이템을 더할 때
  - 친구 광고(`PeerAdvertisement`)의 `outfit` 키를 읽거나 바꿀 때
  - spec 2(내 방 가구 배치·친구 방 방문)를 시작할 때 — 이 문서가 전제다
---

# 던전 방 화면 걷기 + 트레이너 꾸미기 (spec 1)

## 배경 — 왜 바꾸나

층 던전 재설계([`layered-dungeon-design.md`](layered-dungeon-design.md))로 판 길이 문제는
풀렸지만, 화면은 여전히 "출구 이름 목록을 클릭"하는 텍스트 UI 라 **어디로 가는지 감이 안 온다**는
사용성 문제가 남았다. 이 설계는 규칙(방 그래프·통로 비용·체력 예산·하루 한 판)은 그대로 두고
**화면과 조작만** 바꾼다 — 방 하나가 화면 하나이고, 트레이너가 방향키로 걸어 문에 닿으면 옆 방으로 간다
(『Binding of Isaac』의 방 구조, 전투는 현행 유지).

같은 트레이너 스프라이트가 꾸미기 대상이 되고, 꾸민 상태가 근처 트레이너 목록(친구 탭)에 보인다.
싸이월드식 "내 방 가구 배치 + 친구 방 방문"은 **spec 2** 로 미루되, 아이템 카탈로그와 광고 페이로드는
그때 갈아엎지 않게 지금 자리를 잡는다.

## 범위

| 포함 (spec 1) | 제외 (spec 2 이후) |
|---|---|
| 방 화면 렌더링·격자 이동·사방 문 전환 | 방 안 가구 배치·장애물 |
| 방 이벤트 짧은 연출(교전·샘·보물·보스) | 실시간 전투·적 AI |
| 트레이너 base + 꾸미기 레이어 12개, 상점·업적 단계 보상 획득 | 아이템 대량 추가, 계절·한정 아이템 |
| 친구 목록 카드에 상대 아바타 표시 | 친구 방 방문, 방 배치 전송 |
| 시작 방(0번) = 내 방(벽지·바닥만 다름) | 내 방 꾸미기 UI |

## 조사 결론 (2026-08-26)

- **에셋**: 공식 트레이너 걷기 스프라이트는 PokeAPI 에 없고(포켓몬·아이템만), 있는 곳(`pret/pokeemerald`)은
  통짜 캐릭터라 모자·옷 레이어가 없다. 레이어 분리된 공개 세트는 LPC(64px, GPL/CC-BY-SA, 서양 RPG 톤)뿐인데
  팝오버 크기·포켓몬 톤과 맞지 않는다. → **자체 도트**(코드 리터럴, 에셋 파일·다운로드 없음). 포켓몬
  스프라이트는 지금처럼 PokeAPI 를 쓴다(비상업 팬 프로젝트 범위).
- **구현**: 팝오버 폭 360pt 에 방 하나면 SpriteKit 이 과하다. `Canvas` + `TimelineView` 게임루프로 충분.
  키 입력은 `.onKeyPress` 만으론 `NSPopover` 안에서 포커스가 불안정해 `NSEvent.addLocalMonitorForEvents` 를 쓴다.
- **대화 CLI(Claude Code) 연동은 쓰지 않는다.** 텍스트 전용·수 초 지연·CLI 없는 사용자 존재. 후속 후보로
  `dungeon.status`/`dungeon.enter` 도구만 남긴다(이 spec 범위 밖).

## 구조

```
Core/
  PixelSprite.swift        팔레트 인덱스 2차원 배열 + 팔레트. 리터럴로 정의. CGImage 로 굽는 함수.
  TrainerOutfit.swift      OutfitSlot / OutfitItem / TrainerOutfit(착용 상태, Codable)
  TrainerSprite.swift      base(4방향 × 3프레임) 위에 착용 레이어 합성 → 프레임별 PixelSprite. 착용 변경 때만 재생성.
  DungeonRoomLayout.swift  방 번호 → 14×9칸 레이아웃(벽·바닥·문). 문 위치는 DungeonMap.exits + DungeonCoord 방위.
  DungeonWalker.swift      격자 이동 상태기계. 문 칸 도달 시 DungeonRun.move(to:) 를 부른다. 코어 규칙은 손대지 않는다.
UI/
  RoomCanvas.swift         Canvas + TimelineView 루프. 타일·문·트레이너·연출을 그린다.
  KeyCapture.swift         NSEvent 로컬 모니터. 던전 탭 표시 중에만 등록.
  OutfitView.swift         꾸미기 화면(미리보기 + 슬롯별 선택). ShopView 에 "의상" 섹션.
  DungeonView.swift        목록 UI 제거 → 체력·층 1줄 / RoomCanvas / 로그 2줄.
```

### 방 레이아웃 (`DungeonRoomLayout`)

- 캔버스 **14×9칸, 칸 24pt** (16px 타일 × 1.5 — 정수배가 아니라 흐려지지 않게 `interpolation(.none)` 으로
  가장 가까운 픽셀을 쓴다; 트레이너는 16×24px 로 칸에 정확히 맞춘다). 336×216pt, 팝오버 `contentWidth` 안.
- 바깥 한 칸은 벽. 문은 벽 가운데 칸: **동쪽 = 다음 층 본선 방**(본선 방이 2개면 동쪽 벽 위·아래 두 문),
  **북/남 = 곁방**(곁방에서는 되나오는 문 하나), **서쪽 = 없음**(왼쪽으로 못 가는 규칙을 문 자체가 없는 것으로
  표현). 문 옆에 통로 비용(1~3)을 작은 숫자로 그린다 — 지금 목록이 보여 주던 정보를 잃지 않는다.
- 안개: 문 너머 방의 정체는 `revealed` 에 있을 때만 문 위에 아이콘(샘·보물·교전·보스)을 그린다.
- 장식 타일(바닥 얼룩·이끼)은 `dayKey` seed 로 결정론 배치. 장애물은 없다(spec 1).
- 0번 방은 내 방 팔레트(벽지·마루)를 쓴다. 문 규칙은 같다.

### 이동 (`DungeonWalker`)

- 상태: 현재 칸, 바라보는 방향, 이동 중이면 출발 칸·목표 칸·진행도(0~1).
- 입력은 "눌린 키 집합". `tick(dt)` 마다: 이동 중이면 진행도 += dt / 0.18s, 도착하면 스냅. 정지 상태에서
  방향키가 눌려 있으면 그 방향 한 칸을 목표로 잡는다(벽이면 방향만 바꾸고 제자리). 홀드하면 칸 단위로 이어서 간다.
- `dt` 는 실제 경과 시간이되 **0.1s 로 클램프** — 팝오버가 숨었다 돌아올 때 순간이동을 막는다.
- 문 칸에 도착하면 `run.move(to:)` 를 **정확히 한 번** 부르고, 새 방의 반대편 문 앞 칸에서 시작한다.
  `move` 가 `false`(허용되지 않은 이동)를 돌려주는 일은 레이아웃이 exits 에서만 문을 만들므로 없어야 하며,
  발생하면 로그로 남기고 제자리에 둔다.
- 연출 중(`presenting`)에는 입력을 무시한다.
- 마우스 폴백: 문 클릭 → 그 문까지 최단 격자 경로로 자동 걷기(장애물이 없어 직선 두 번이면 된다).

### 연출

방 진입 후 `DungeonEvent` 를 읽어 0.6~0.8초 짧은 연출을 한 번 보여 준다. 그동안 입력 잠금.

| 이벤트 | 연출 |
|---|---|
| `entered(.encounter)` + `damaged` | 방 가운데 야생 포켓몬(PokeAPI 정적 스프라이트, 오늘 상성 축 타입에서 결정론 선택) 등장 → 데미지 숫자 떠오름 → 사라짐 |
| `healed` / `springAlreadyUsed` | 샘 타일 반짝 / 회색 샘 |
| `looted` / `cacheAlreadyLooted` | 상자 열림 + 별의조각 숫자 / 열린 상자 |
| `bossFelled` | 보스 스프라이트 등장 → 데미지 → 쓰러짐 → 클리어 footer |
| `collapsed` | 트레이너 주저앉음 → 실패 footer |

텍스트 로그(`DungeonNarration`)는 캔버스 아래 2줄에 그대로 살린다 — 로컬라이즈 자산 재사용, 시각 연출을
못 본 사람의 폴백.

### 입력 (`KeyCapture`)

- `NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged])`.
- 던전 탭이 보일 때 등록, 사라질 때 해제. 팝오버는 닫힐 때 `contentViewController = nil` 이라(defect-log
  "에너지" 절) 뷰가 내려가며 자연히 해제되지만, **탭 전환**으로도 사라지므로 `onDisappear` 해제가 필수다 —
  안 하면 다른 탭에서 화살표가 먹히고 모니터 핸들이 누수된다.
- 방향키·WASD 는 소비(`nil` 반환 — 반환하지 않으면 시스템 경고음). Esc(keyCode 53)·나머지는 통과.
- 텍스트 입력 뷰가 first responder 이면 전부 통과한다(채팅·검색 필드 보호).
- 팝오버 표시 시 `AppDelegate` 가 `window.makeKey()` 를 부른다 — 안 하면 첫 키가 씹힌다.

### 게임루프와 에너지

- `TimelineView(.animation(minimumInterval: 1/60, paused: idle))`. **idle(정지·연출 없음)이면 멈춘다** — 던전
  탭을 열어 둔 채 방치해도 60fps 로 돌지 않는다(defect-log "항상 뜬 애니메이션 표면" 규율).
- 매 틱 스프라이트 합성 금지. `TrainerSprite` 는 착용 변경 때만 12프레임(4방향 × 3)을 `CGImage` 로 굽고
  캐시한다. 타일 시트도 한 번 굽는다.

### 꾸미기 (`TrainerOutfit`)

```swift
enum OutfitSlot: String, CaseIterable, Codable { case hat, hair, top, bottom, accessory }
enum OutfitItem: String, CaseIterable, Codable { /* 12개, rawValue 가 세이브·와이어 ID */ }
struct TrainerOutfit: Codable, Equatable { var worn: [OutfitSlot: OutfitItem] }
```

- `OutfitItem` 마다 `slot`, `price: Int?`(nil = 상점 판매 안 함), 4방향 레이어 픽셀. 머리카락은 모자 아래
  레이어이고 모자가 가리는 픽셀은 모자 레이어가 위에 덮는다 — 합성 순서 `body < bottom < top < hair < hat < accessory`.
- 초기 12개: hat 3 · hair 3 · top 3 · bottom 2 · accessory 1. base 는 성별 중립 실루엣, 16×24px, 팔레트 ~12색.
- 획득 경로는 둘이다.
  - **상점 구매 8개** (`ShopView` "의상" 섹션, 별의조각): 빨간 캡 300 · 밀짚모자 400 · 단발 300 · 포니테일 300 ·
    파란 재킷 500 · 흰 티셔츠 300 · 반바지 300 · 백팩 800.
  - **업적 단계 보상 4개** (상점 미판매) — 컬렉션 > 업적(`AchievementLadder`)에 던전 트랙 둘을 더하고 단계에
    의상을 붙인다. 별의조각 단계 보상(300/1,000/3,000/6,000)은 다른 트랙과 같다.

    | 트랙 | 세는 것 | 문턱 | 의상 |
    |---|---|---|---|
    | `dungeon` | 던전 클리어 횟수 | 1 / 5 / 20 / 50 | 1단계 흐트러진 머리 · 2단계 낡은 망토 |
    | `dungeonSweep` | 오늘 보물방을 **전부** 털고 클리어한 횟수 | 1 / 5 / 20 / 50 | 1단계 부츠 · 3단계 탐험가 헬멧 |

    sweep 이 난이도 축이다 — 곁방을 다 열 만큼 체력을 관리해야 한다. "체력 N 남기고 클리어" 는 넣지 않는다
    (안개 때문에 운 요소가 크고 N 튜닝에 365일 실측이 필요하다). 판정은 `DungeonRun` 이 이미 가진 값
    (`looted`, 맵의 `cache` 방 집합)으로 하며 코어 규칙은 바꾸지 않는다. 기록 지점은 클리어 정산(`rewardPaid`
    를 세우는 곳) 한 곳 — `record(.dungeon, 1)`, 조건이 맞으면 `record(.dungeonSweep, 1)`.
  - `Achievement` 에 `outfits: [OutfitItem?]`(`tiers` 와 같은 길이) 을 더한다. 카탈로그 정합 테스트가 길이를
    강제한다. `AchievementLadderTests` 의 총액 상한(41,200)은 트랙 둘이 늘어 61,800 으로 올리고 근거(평생 1회,
    알 3개 규모)를 주석에 남긴다. LAN 카드 분모(`tierCeiling`)는 카탈로그에서 파생되므로 따로 손대지 않는다.
  - 던전 첫 클리어 즉시 보상 별의조각 1,000 은 그대로다.
- 세이브: `CompanionState.outfit: TrainerOutfit`, `ownedOutfits: Set<OutfitItem>` — 둘 다 `lenient` 디코드,
  옛 세이브는 기본값. 미소유 아이템 착용은 정규화에서 벗긴다. 무결성 서명에는 `ownedOutfits` 만 넣는다
  (재화로 산 것이라 조작 가드 대상; 착용 상태는 표시 전용).
- 시도 중 위치·방향은 저장하지 않는다(기존 원칙 — 팝오버를 닫으면 시도만 버려진다).

### 친구 광고 (`PeerAdvertisement`)

- 키 `outfit` 하나 추가, 값은 `slot:item` 을 `,` 로 이은 문자열(예: `hat:cap_red,top:jacket`). 빈 착용은 키를
  싣지 않는다(기존 규칙). 12개 전부 입어도 100바이트 안이라 TXT 1KB 한계에 넉넉하다.
- 읽는 쪽은 관대 파싱: 모르는 슬롯·아이템 ID 는 무시(신버전 상대의 새 아이템을 구버전이 받아도 카드가 비지
  않는다). 파싱 실패로 피어를 떨어뜨리지 않는다.
- `FriendView.trainerRow` 의 `person.crop.circle.fill` 자리를 상대 아바타(정면 정지 프레임, 2배)로 바꾼다.
  `outfit` 키가 없는 구버전 상대는 base 트레이너로 그린다.
- spec 2 의 방 배치는 1KB 를 넘을 수 있어 TXT 가 아니라 배틀 채널 요청으로 보낼 예정 — 이 spec 은 그 자리를
  예약만 한다(키 이름 `room` 을 쓰지 않는다).

## 테스트

| 대상 | 검증 |
|---|---|
| `DungeonWalkerTests` | 벽 거부(방향만 바뀜) · 문 도달 시 `move` 정확히 1회 · 도착 위치 = 반대편 문 앞 · dt 0.1s 클램프 · 홀드 연속 이동 · 연출 중 입력 무시 · 문 클릭 자동 걷기가 문에 닿음 |
| `DungeonRoomLayoutTests` | 365일 전수: 모든 방의 문 수 == `exits` 수, 문 방위가 `DungeonCoord` 와 일치(동 = 다음 층, 북/남 = 곁방), 곁방은 문 1개, 서쪽 문 없음, 장식은 같은 dayKey 로 두 번 만들어도 동일 |
| `TrainerSpriteTests` | 모든 아이템 × 4방향 × 3프레임 합성 성공 · 크기 16×24 · 불투명 픽셀 존재 · 슬롯당 레이어 하나만 · 모자가 머리카락 위 |
| `TrainerOutfitTests` | Codable 왕복 · 옛 세이브(키 없음) 기본값 · 미소유 착용 정규화에서 벗김 · `ownedOutfits` 서명 포함, 착용은 미포함 |
| `PeerAdvertisementTests` | `outfit` 왕복 · 모르는 ID 무시 · 빈 착용은 키 없음 · 잘못된 문자열에도 피어 유지 |
| 업적 던전 트랙 | 클리어 정산 1회에 `dungeon` 카운터 +1 · 보물방 전부 턴 날만 `dungeonSweep` +1(하나 남기면 안 오름) · 단계 넘을 때 의상이 `ownedOutfits` 에 들어감 · `rewardPaid` 뒤 재정산에도 카운터 안 오름 — **결함 주입**(가드 제거)으로 테스트가 실패하는지 확인 · 카탈로그 `outfits` 길이 == `tiers` 길이 |
| 기존 | `DungeonRunTests`·`PuzzleDungeonTests` 무변경 통과 — 코어 규칙을 건드리지 않았다는 증거 |

새 조건 분기는 `xcrun llvm-cov show ... --show-regions` 로 `^0` 을 직접 본다(CLAUDE.md 결함 대응 프로토콜 3).

## 문서·릴리스 영향

- `docs/reference/layered-dungeon-design.md` 의 "던전 화면(`DungeonView`)의 진행 표시·출구 목록" 항목은 이 문서로
  대체됨을 한 줄 추가한다.
- `CLAUDE.md` 참조 문서 표에 이 문서를 넣는다(읽는 때: 방 화면·이동·키 입력·꾸미기·광고 `outfit`).
- UI 변경이라 다음 릴리스에서 스크린샷·랜딩 갱신 대상(`release-workflow.md`).
